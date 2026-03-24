import 'package:cloud_firestore/cloud_firestore.dart';

/// Centralized service for all Staff Management operations.
/// Handles staff CRUD, shift scheduling, attendance tracking, and metrics.
class StaffService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ---------------------------------------------------------------------------
  // STAFF CRUD
  // ---------------------------------------------------------------------------

  /// Stream all staff filtered by branch IDs.
  Stream<QuerySnapshot> getStaffStream({
    required List<String> branchIds,
    String? selectedBranchId,
  }) {
    Query query = _db.collection('staff');

    if (selectedBranchId != null && selectedBranchId.isNotEmpty) {
      query = query
          .where('branchIds', arrayContains: selectedBranchId)
          .orderBy('name');
    } else if (branchIds.isNotEmpty && branchIds.length <= 10) {
      query = query
          .where('branchIds', arrayContainsAny: branchIds.take(10).toList())
          .orderBy('name');
    } else {
      query = query.orderBy('name');
    }

    return query.snapshots();
  }

  /// Add a new staff member. Doc ID = email.
  Future<void> addStaff(Map<String, dynamic> data, String createdBy) async {
    final email = data['email'] as String;
    final docRef = _db.collection('staff').doc(email);
    final existing = await docRef.get();

    if (existing.exists) {
      throw Exception('Staff member with email "$email" already exists.');
    }

    await docRef.set({
      'name': data['name'],
      'email': email,
      'phone': data['phone'] ?? '',
      'role': data['role'],
      'isActive': true,
      'branchIds': data['branchIds'] ?? [],
      'permissions': data['permissions'] ?? {},
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': createdBy,
      'lastUpdated': FieldValue.serverTimestamp(),
    });
  }

  /// Update an existing staff member.
  Future<void> updateStaff(
      String staffId, Map<String, dynamic> data, String updatedBy) async {
    await _db.collection('staff').doc(staffId).update({
      'name': data['name'],
      'phone': data['phone'] ?? '',
      'role': data['role'],
      'isActive': data['isActive'],
      'branchIds': data['branchIds'] ?? [],
      'permissions': data['permissions'] ?? {},
      'lastUpdated': FieldValue.serverTimestamp(),
      'lastUpdatedBy': updatedBy,
    });
  }

  /// Deactivate a staff member (soft delete).
  Future<void> deactivateStaff(String staffId, String updatedBy) async {
    await _db.collection('staff').doc(staffId).update({
      'isActive': false,
      'lastUpdated': FieldValue.serverTimestamp(),
      'lastUpdatedBy': updatedBy,
    });
  }

  /// Hard-delete a staff member. Use with caution.
  Future<void> deleteStaff(String staffId) async {
    await _db.collection('staff').doc(staffId).delete();
  }

  // ---------------------------------------------------------------------------
  // SHIFT SCHEDULING
  // ---------------------------------------------------------------------------

  /// Stream shifts filtered by branch. Returns all 7-day schedules.
  Stream<QuerySnapshot> getShiftsStream(
      {String? selectedBranchId, List<String>? branchIds}) {
    Query query = _db.collection('shifts');
    if (selectedBranchId != null && selectedBranchId.isNotEmpty) {
      query = query.where('branchIds', arrayContains: selectedBranchId);
    } else if (branchIds != null && branchIds.isNotEmpty) {
      query = query.where('branchIds',
          arrayContainsAny: branchIds.take(10).toList());
    }
    query = query.orderBy('staffName').orderBy('dayOfWeek');
    return query.snapshots();
  }

  /// Get shifts for a specific staff member.
  Stream<QuerySnapshot> getShiftsForStaff(String staffId) {
    return _db
        .collection('shifts')
        .where('staffId', isEqualTo: staffId)
        .orderBy('dayOfWeek')
        .snapshots();
  }

  /// Add a shift.
  Future<void> addShift({
    required String staffId,
    required String staffEmail,
    required String staffName,
    required List<String> branchIds,
    required int dayOfWeek,
    required String startTime,
    required String endTime,
    required String shiftType,
    required bool isOff,
    required String createdBy,
  }) async {
    // Check for existing shift on same day for same staff
    final existing = await _db
        .collection('shifts')
        .where('staffId', isEqualTo: staffId)
        .where('dayOfWeek', isEqualTo: dayOfWeek)
        .get();

    if (existing.docs.isNotEmpty) {
      // Update existing instead of creating duplicate
      await existing.docs.first.reference.update({
        'startTime': startTime,
        'endTime': endTime,
        'shiftType': shiftType,
        'isOff': isOff,
        'branchIds': branchIds,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      return;
    }

    await _db.collection('shifts').add({
      'staffId': staffId,
      'staffEmail': staffEmail,
      'staffName': staffName,
      'branchIds': branchIds,
      'dayOfWeek': dayOfWeek,
      'startTime': startTime,
      'endTime': endTime,
      'shiftType': shiftType,
      'isOff': isOff,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': createdBy,
    });
  }

  /// Delete a shift.
  Future<void> deleteShift(String shiftId) async {
    await _db.collection('shifts').doc(shiftId).delete();
  }

  /// Update a shift.
  Future<void> updateShift(String shiftId, Map<String, dynamic> data) async {
    await _db.collection('shifts').doc(shiftId).update({
      ...data,
      'lastUpdated': FieldValue.serverTimestamp(),
    });
  }

  // ---------------------------------------------------------------------------
  // ATTENDANCE
  // ---------------------------------------------------------------------------

  /// Stream today's attendance records, optionally filtered by branch.
  Stream<QuerySnapshot> getTodayAttendanceStream(
      {String? selectedBranchId, List<String>? branchIds, String? staffId}) {
    final today = _todayString();
    if (staffId != null && staffId.isNotEmpty) {
      // Keep the self time-clock stream index-light. Branch filters and orderBy
      // are not needed here and were causing fragile desktop loading states.
      return _db
          .collection('attendance')
          .where('staffId', isEqualTo: staffId)
          .where('date', isEqualTo: today)
          .snapshots();
    }

    Query query = _db.collection('attendance').where('date', isEqualTo: today);

    if (selectedBranchId != null && selectedBranchId.isNotEmpty) {
      query = query.where('branchIds', arrayContains: selectedBranchId);
    } else if (branchIds != null && branchIds.isNotEmpty) {
      query = query.where('branchIds',
          arrayContainsAny: branchIds.take(10).toList());
    }

    query = query.orderBy('clockIn', descending: true);
    return query.snapshots();
  }

  /// Clock in a staff member.
  Future<void> clockIn({
    required String staffId,
    required String staffEmail,
    required String staffName,
    required List<String> branchIds,
    String? scheduledStart,
  }) async {
    final today = _todayString();
    final now = DateTime.now();

    // Check if already clocked in today (active session)
    final existing = await _db
        .collection('attendance')
        .where('staffId', isEqualTo: staffId)
        .where('date', isEqualTo: today)
        .where('clockOut', isNull: true)
        .get();

    if (existing.docs.isNotEmpty) {
      throw Exception('$staffName is already clocked in.');
    }

    // Determine status
    String status = 'on_time';
    if (scheduledStart != null && scheduledStart.isNotEmpty) {
      final parts = scheduledStart.split(':');
      if (parts.length == 2) {
        final scheduledHour = int.tryParse(parts[0]) ?? 0;
        final scheduledMinute = int.tryParse(parts[1]) ?? 0;
        final scheduledTime = DateTime(
            now.year, now.month, now.day, scheduledHour, scheduledMinute);
        if (now.isAfter(scheduledTime.add(const Duration(minutes: 5)))) {
          status = 'late';
        }
      }
    }

    await _db.collection('attendance').add({
      'staffId': staffId,
      'staffEmail': staffEmail,
      'staffName': staffName,
      'branchIds': branchIds,
      'date': today,
      'clockIn': FieldValue.serverTimestamp(),
      'clockOut': null,
      'status': status,
      'scheduledStart': scheduledStart ?? '',
      'notes': '',
    });
  }

  /// Clock out a staff member.
  Future<void> clockOut(String attendanceDocId, {String? notes}) async {
    final updateData = <String, dynamic>{
      'clockOut': FieldValue.serverTimestamp(),
    };
    if (notes != null) updateData['notes'] = notes;
    await _db.collection('attendance').doc(attendanceDocId).update(updateData);
  }

  // ---------------------------------------------------------------------------
  // METRICS (computed from live data)
  // ---------------------------------------------------------------------------

  /// Get total active staff count for given branches.
  Stream<int> getTotalActiveStaffCount(List<String> branchIds) {
    Query query = _db.collection('staff').where('isActive', isEqualTo: true);
    if (branchIds.isNotEmpty && branchIds.length <= 10) {
      query = query.where('branchIds',
          arrayContainsAny: branchIds.take(10).toList());
    }
    return query.snapshots().map((snap) => snap.docs.length);
  }

  /// Get total staff count (active + inactive).
  Stream<int> getTotalStaffCount(List<String> branchIds) {
    Query query = _db.collection('staff');
    if (branchIds.isNotEmpty && branchIds.length <= 10) {
      query = query.where('branchIds',
          arrayContainsAny: branchIds.take(10).toList());
    }
    return query.snapshots().map((snap) => snap.docs.length);
  }

  /// Get count of staff clocked in today.
  Stream<int> getClockedInTodayCount(
      {String? selectedBranchId, List<String>? branchIds}) {
    final today = _todayString();
    Query query = _db
        .collection('attendance')
        .where('date', isEqualTo: today)
        .where('clockOut', isNull: true);

    if (selectedBranchId != null && selectedBranchId.isNotEmpty) {
      query = query.where('branchIds', arrayContains: selectedBranchId);
    } else if (branchIds != null && branchIds.isNotEmpty) {
      // Use arrayContainsAny for multi-branch filtering
      query = query.where('branchIds',
          arrayContainsAny: branchIds.take(10).toList());
    }

    return query.snapshots().map((snap) => snap.docs.length);
  }

  /// Get today's shift count.
  Stream<int> getTodayShiftCount(
      {String? selectedBranchId, List<String>? branchIds}) {
    final todayDow = DateTime.now().weekday; // 1=Mon, 7=Sun
    Query query = _db
        .collection('shifts')
        .where('dayOfWeek', isEqualTo: todayDow)
        .where('isOff', isEqualTo: false);

    if (selectedBranchId != null && selectedBranchId.isNotEmpty) {
      query = query.where('branchIds', arrayContains: selectedBranchId);
    } else if (branchIds != null && branchIds.isNotEmpty) {
      query = query.where('branchIds',
          arrayContainsAny: branchIds.take(10).toList());
    }

    return query.snapshots().map((snap) => snap.docs.length);
  }

  // ---------------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------------

  String _todayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}
