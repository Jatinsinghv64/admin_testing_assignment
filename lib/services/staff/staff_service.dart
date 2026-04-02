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

  Future<void> addStaff(Map<String, dynamic> data, String createdBy) async {
    final email = data['email'] as String;
    final docRef = _db.collection('staff').doc(email);
    final existing = await docRef.get();

    if (existing.exists) {
      throw Exception('Staff member with email "$email" already exists.');
    }

    final String staffType = data['role'] == 'driver' ? 'driver' : 'staff';

    final Map<String, dynamic> staffData = {
      'name': data['name'],
      'email': email,
      'phone': data['phone'] ?? '',
      'role': data['role'],
      'qid': data['qid'] ?? '',
      'passportNumber': data['passportNumber'] ?? '',
      'salary': data['salary'] ?? 0,
      'roleFields': data['roleFields'] ?? {},
      'isActive': true,
      'branchIds': data['branchIds'] ?? [],
      'permissions': data['permissions'] ?? {},
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': createdBy,
      'lastUpdated': FieldValue.serverTimestamp(),
      'staffType': staffType,
    };

    if (staffType == 'driver') {
      staffData.addAll({
        'assignedOrderId': '',
        'currentLocation': const GeoPoint(0, 0),
        'fcmToken': '',
        'isAvailable': false,
        'profileImageUrl': '',
        'rating': 0.0,
        'ratingCount': 0,
        'status': 'offline',
        'totalDeliveries': 0,
        'totalRatings': 0,
        'vehicle': {
          'type': (data['roleFields'] as Map?)?['vehicleType'] ?? 'car',
          'number': (data['roleFields'] as Map?)?['vehiclePlateNumber'] ?? '',
        },
      });
    }

    await docRef.set(staffData);
  }

  Future<void> updateStaff(
      String staffId, Map<String, dynamic> data, String updatedBy) async {
    final String staffType = data['role'] == 'driver' ? 'driver' : 'staff';
    
    final Map<String, dynamic> updateData = {
      'name': data['name'],
      'phone': data['phone'] ?? '',
      'role': data['role'],
      'qid': data['qid'] ?? '',
      'passportNumber': data['passportNumber'] ?? '',
      'salary': data['salary'] ?? 0,
      'roleFields': data['roleFields'] ?? {},
      'isActive': data['isActive'],
      'branchIds': data['branchIds'] ?? [],
      'permissions': data['permissions'] ?? {},
      'lastUpdated': FieldValue.serverTimestamp(),
      'lastUpdatedBy': updatedBy,
      'staffType': staffType,
    };

    if (staffType == 'driver') {
      updateData['vehicle'] = {
        'type': (data['roleFields'] as Map?)?['vehicleType'] ?? 'car',
        'number': (data['roleFields'] as Map?)?['vehiclePlateNumber'] ?? '',
      };
    }

    await _db.collection('staff').doc(staffId).update(updateData);
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

    // If scheduledStart is missing, try to find it from the shift for today
    String? effectiveScheduledStart = scheduledStart;
    if (effectiveScheduledStart == null || effectiveScheduledStart.isEmpty) {
      final dow = now.weekday; // 1=Mon, 7=Sun
      final shiftDocs = await _db
          .collection('shifts')
          .where('staffId', isEqualTo: staffId)
          .where('dayOfWeek', isEqualTo: dow)
          .where('isOff', isEqualTo: false)
          .limit(1)
          .get();
      
      if (shiftDocs.docs.isNotEmpty) {
        effectiveScheduledStart = shiftDocs.docs.first.data()['startTime'] as String?;
      }
    }

    // Determine status
    String status = 'on_time';
    if (effectiveScheduledStart != null && effectiveScheduledStart.isNotEmpty) {
      final parts = effectiveScheduledStart.split(':');
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
      'scheduledStart': effectiveScheduledStart ?? '',
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
  // DRIVERS (from 'Drivers' collection)
  // ---------------------------------------------------------------------------

  Stream<QuerySnapshot> getDriversStream({
    required List<String> branchIds,
    String? selectedBranchId,
  }) {
    Query query = _db.collection('staff').where('staffType', isEqualTo: 'driver');

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

  /// Get count of active (online/on_delivery) drivers.
  Stream<int> getActiveDriverCount(List<String> branchIds) {
    Query query = _db
        .collection('staff')
        .where('staffType', isEqualTo: 'driver')
        .where('status', whereIn: ['online', 'on_delivery']);
    if (branchIds.isNotEmpty && branchIds.length <= 10) {
      query = query.where('branchIds',
          arrayContainsAny: branchIds.take(10).toList());
    }
    return query.snapshots().map((snap) => snap.docs.length);
  }

  /// Get total driver count for given branches.
  Stream<int> getTotalDriverCount(List<String> branchIds) {
    Query query = _db.collection('staff').where('staffType', isEqualTo: 'driver');
    if (branchIds.isNotEmpty && branchIds.length <= 10) {
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

  String _dateString(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// Stream attendance records within a specific date range.
  /// Note: Filtering by branchIds is omitted at the database level to prevent 
  /// requiring complex composite indexes (date + arrayContainsAny). 
  Stream<QuerySnapshot> getAttendanceByDateRange(DateTime start, DateTime end,
      {String? selectedBranchId, List<String>? branchIds}) {
    final startStr = _dateString(start);
    final endStr = _dateString(end);

    Query query = _db
        .collection('attendance')
        .where('date', isGreaterThanOrEqualTo: startStr)
        .where('date', isLessThanOrEqualTo: endStr);

    return query.snapshots();
  }
}
