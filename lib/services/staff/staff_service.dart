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
        'isAvailable': true,
        'profileImageUrl': '',
        'rating': 0.0,
        'ratingCount': 0,
        'status': 'online',
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

  /// Returns ALL shift docs for the given [branchId] (or all if null).
  /// Caller must filter to the days in range — done client-side because
  /// Firestore `whereIn` on `dayOfWeek` is limited to 30 values max and
  /// day-of-week values 1-7 are well within that limit.
  Future<List<Map<String, dynamic>>> getShiftsForBranch({
    String? branchId,
  }) async {
    Query q = _db.collection('shifts');
    if (branchId != null && branchId.isNotEmpty) {
      q = q.where('branchIds', arrayContains: branchId);
    }
    final snap = await q.get();
    return snap.docs
        .map((d) => {
              ...(d.data() as Map<String, dynamic>),
              '_shiftDocId': d.id,
            })
        .toList();
  }


  // ---------------------------------------------------------------------------
  // ATTENDANCE CONFIG
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> getAttendanceConfig() async {
    final doc = await _db.collection('attendance_config').doc('default').get();
    if (!doc.exists) {
      return {
        'grace_period_minutes': 10,
        'early_arrival_minutes': 15,
        'overtime_trigger_minutes': 10,
        'auto_absent_after_minutes': 30,
        'very_late_threshold_minutes': 60,
        'allow_unscheduled': true,
      };
    }
    return doc.data()!;
  }

  // ---------------------------------------------------------------------------
  // CLOCK-IN — full status decision tree
  // ---------------------------------------------------------------------------

  /// Clock in a staff member with full shift-based status computation.
  ///
  /// Status outcomes:
  ///   `early`           — clocked in before (shiftStart - earlyArrivalWindow)
  ///   `present`         — clocked in within grace period
  ///   `late`            — clocked in after grace period
  ///   `very_late`       — clocked in past the very-late threshold
  ///   `unscheduled_present` — no shift found and allowUnscheduled = true
  ///
  /// Throws if already clocked in, or if not scheduled and allowUnscheduled=false.
  Future<void> clockIn({
    required String staffId,
    required String staffEmail,
    required String staffName,
    required List<String> branchIds,
    String? scheduledStart,
    String? scheduledEnd,
    String? shiftId,
  }) async {
    final today = _todayString();
    final now = DateTime.now();

    // Guard: already clocked in today (clockOut is null = still active session)
    // NOTE: Firestore does NOT support .where('field', isNull: true).
    // We fetch all records for today and filter in Dart.
    final todayDocs = await _db
        .collection('attendance')
        .where('staffId', isEqualTo: staffId)
        .where('date', isEqualTo: today)
        .get();

    final activeSession = todayDocs.docs.where((d) {
      final data = d.data() as Map<String, dynamic>;
      // clockOut is null (never clocked out) but MUST have clocked in (ignore absent)
      return data['clockIn'] != null && data['clockOut'] == null;
    }).toList();

    if (activeSession.isNotEmpty) {
      throw Exception('$staffName is already clocked in.');
    }

    // Look for existing 'absent' record to overwrite
    final absentRecords = todayDocs.docs.where((d) {
      final data = d.data() as Map<String, dynamic>;
      return data['status'] == 'absent' && data['clockIn'] == null;
    }).toList();

    // Fetch config
    final cfg = await getAttendanceConfig();
    final gracePeriod = (cfg['grace_period_minutes'] as num?)?.toInt() ?? 10;
    final earlyWindow = (cfg['early_arrival_minutes'] as num?)?.toInt() ?? 15;
    final veryLateThreshold =
        (cfg['very_late_threshold_minutes'] as num?)?.toInt() ?? 60;
    final allowUnscheduled = cfg['allow_unscheduled'] as bool? ?? true;

    // Resolve today's shift if not provided
    String? effectiveStart = scheduledStart;
    String? effectiveEnd = scheduledEnd;
    String? effectiveShiftId = shiftId;

    if (effectiveStart == null || effectiveStart.isEmpty) {
      final dow = now.weekday;
      // Fetch ALL shifts for this staff on this day and pick the most recently
      // updated one (avoids grabbing a stale doc when the form saved a new one).
      final shiftDocs = await _db
          .collection('shifts')
          .where('staffId', isEqualTo: staffId)
          .where('dayOfWeek', isEqualTo: dow)
          .where('isOff', isEqualTo: false)
          .get();

      if (shiftDocs.docs.isNotEmpty) {
        // Sort by lastUpdated desc in Dart to always get the freshest shift
        final sorted = shiftDocs.docs.toList()
          ..sort((a, b) {
            final aTs = (a.data() as Map<String, dynamic>)['lastUpdated'];
            final bTs = (b.data() as Map<String, dynamic>)['lastUpdated'];
            if (aTs == null && bTs == null) return 0;
            if (aTs == null) return 1;
            if (bTs == null) return -1;
            return (bTs as Timestamp).compareTo(aTs as Timestamp);
          });
        final best = sorted.first;
        final sd = best.data() as Map<String, dynamic>;
        effectiveStart = sd['startTime'] as String?;
        effectiveEnd = sd['endTime'] as String?;
        effectiveShiftId = best.id;
      }
    }

    // ── Unscheduled path ────────────────────────────────────────────────────
    if (effectiveStart == null || effectiveStart.isEmpty) {
      if (!allowUnscheduled) {
        throw Exception(
            '$staffName is not scheduled to work today. Clock-in blocked by policy.');
      }
      final attendanceData = {
        'staffId': staffId,
        'staffEmail': staffEmail,
        'staffName': staffName,
        'branchIds': branchIds,
        'date': today,
        'clockIn': FieldValue.serverTimestamp(),
        'clockOut': null,
        'status': 'unscheduled_present',
        'lateMinutes': 0,
        'earlyLeaveMinutes': 0,
        'overtimeMinutes': 0,
        'totalHoursWorked': 0.0,
        'scheduledStart': '',
        'scheduledEnd': '',
        'shiftId': null,
        'isApproved': false,
        'approvedBy': null,
        'note': '',
        'isAutoAbsent': false,
      };

      if (absentRecords.isNotEmpty) {
        await _db.collection('attendance').doc(absentRecords.first.id).update({
          ...attendanceData,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        attendanceData['createdAt'] = FieldValue.serverTimestamp();
        await _db.collection('attendance').add(attendanceData);
      }
      return;
    }

    // ── Scheduled path: compute status ──────────────────────────────────────
    final startParts = effectiveStart.split(':');
    final shiftHour = int.tryParse(startParts[0]) ?? 0;
    final shiftMin = int.tryParse(startParts.length > 1 ? startParts[1] : '0') ?? 0;
    final shiftStart =
        DateTime(now.year, now.month, now.day, shiftHour, shiftMin);

    final diffMinutes = now.difference(shiftStart).inMinutes;
    String status;
    int lateMinutes = 0;

    if (diffMinutes < -earlyWindow) {
      status = 'early';
    } else if (diffMinutes <= gracePeriod) {
      status = 'present';
    } else if (diffMinutes <= veryLateThreshold) {
      status = 'late';
      lateMinutes = diffMinutes - gracePeriod;
    } else {
      status = 'very_late';
      lateMinutes = diffMinutes - gracePeriod;
    }

    final attendanceData = {
      'staffId': staffId,
      'staffEmail': staffEmail,
      'staffName': staffName,
      'branchIds': branchIds,
      'date': today,
      'clockIn': FieldValue.serverTimestamp(),
      'clockOut': null,
      'status': status,
      'lateMinutes': lateMinutes,
      'earlyLeaveMinutes': 0,
      'overtimeMinutes': 0,
      'totalHoursWorked': 0.0,
      'scheduledStart': effectiveStart,
      'scheduledEnd': effectiveEnd ?? '',
      'shiftId': effectiveShiftId,
      'isApproved': true,
      'approvedBy': null,
      'note': '',
      'isAutoAbsent': false,
    };

    if (absentRecords.isNotEmpty) {
      await _db.collection('attendance').doc(absentRecords.first.id).update({
        ...attendanceData,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      attendanceData['createdAt'] = FieldValue.serverTimestamp();
      await _db.collection('attendance').add(attendanceData);
    }
  }

  // ---------------------------------------------------------------------------
  // CLOCK-OUT — computes overtime / early-leave / hours worked
  // ---------------------------------------------------------------------------

  Future<void> clockOut(String attendanceDocId, {String? notes}) async {
    final doc = await _db.collection('attendance').doc(attendanceDocId).get();
    if (!doc.exists) throw Exception('Attendance record not found.');

    final data = doc.data() as Map<String, dynamic>;
    final clockInTs = data['clockIn'] as Timestamp?;
    final scheduledEnd = (data['scheduledEnd'] as String?) ?? '';
    final now = DateTime.now();

    // Compute total hours worked
    double totalHoursWorked = 0.0;
    if (clockInTs != null) {
      final diff = now.difference(clockInTs.toDate());
      totalHoursWorked = diff.inSeconds / 3600.0;
    }

    // Fetch config for overtime & early-leave thresholds
    final cfg = await getAttendanceConfig();
    final overtimeTrigger =
        (cfg['overtime_trigger_minutes'] as num?)?.toInt() ?? 10;

    int earlyLeaveMinutes = 0;
    int overtimeMinutes = 0;
    String updatedStatus = data['status'] as String? ?? 'present';

    if (scheduledEnd.isNotEmpty) {
      final endParts = scheduledEnd.split(':');
      if (endParts.length >= 2) {
        final endH = int.tryParse(endParts[0]) ?? 0;
        final endM = int.tryParse(endParts[1]) ?? 0;
        final shiftEnd = DateTime(now.year, now.month, now.day, endH, endM);

        final diffFromEnd = now.difference(shiftEnd).inMinutes;

        if (diffFromEnd < 0) {
          // Clocked out before shift end
          earlyLeaveMinutes = diffFromEnd.abs();
          final wasLate = updatedStatus == 'late' || updatedStatus == 'very_late';
          updatedStatus = wasLate ? 'partial_shift' : 'early_leave';
        } else if (diffFromEnd > overtimeTrigger) {
          // Clocked out after overtime buffer
          overtimeMinutes = diffFromEnd - overtimeTrigger;
          updatedStatus = 'overtime';
        }
        // else: normal clock-out — keep existing status (present / late etc.)
      }
    }

    final updateData = <String, dynamic>{
      'clockOut': FieldValue.serverTimestamp(),
      'totalHoursWorked': totalHoursWorked,
      'earlyLeaveMinutes': earlyLeaveMinutes,
      'overtimeMinutes': overtimeMinutes,
      'status': updatedStatus,
    };
    if (notes != null && notes.isNotEmpty) updateData['note'] = notes;

    await _db.collection('attendance').doc(attendanceDocId).update(updateData);
  }

  // ---------------------------------------------------------------------------
  // ATTENDANCE STREAMS & QUERIES
  // ---------------------------------------------------------------------------

  /// Stream today's attendance records, optionally filtered by branch.
  Stream<QuerySnapshot> getTodayAttendanceStream(
      {String? selectedBranchId, List<String>? branchIds, String? staffId}) {
    final today = _todayString();
    if (staffId != null && staffId.isNotEmpty) {
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

  /// Stream attendance records for a specific date.
  Stream<QuerySnapshot> getAttendanceByDate(
    String dateStr, {
    String? selectedBranchId,
    List<String>? branchIds,
  }) {
    Query query =
        _db.collection('attendance').where('date', isEqualTo: dateStr);

    if (selectedBranchId != null && selectedBranchId.isNotEmpty) {
      query = query.where('branchIds', arrayContains: selectedBranchId);
    } else if (branchIds != null && branchIds.isNotEmpty) {
      query = query.where('branchIds',
          arrayContainsAny: branchIds.take(10).toList());
    }

    return query.snapshots();
  }

  /// Stream attendance records within a date range, optionally filtered by branch.
  Stream<QuerySnapshot> getAttendanceByDateRange(
    DateTime start,
    DateTime end, {
    String? selectedBranchId,
    List<String>? branchIds,
  }) {
    final startStr = _dateString(start);
    final endStr = _dateString(end);

    Query query = _db
        .collection('attendance')
        .where('date', isGreaterThanOrEqualTo: startStr)
        .where('date', isLessThanOrEqualTo: endStr)
        .orderBy('date', descending: true);

    if (selectedBranchId != null && selectedBranchId.isNotEmpty) {
      query = query.where('branchIds', arrayContains: selectedBranchId);
    } else if (branchIds != null && branchIds.isNotEmpty) {
      query = query.where('branchIds',
          arrayContainsAny: branchIds.take(10).toList());
    }

    return query.snapshots();
  }

  /// Stream pending approvals (unscheduled arrivals that need manager action).
  Stream<QuerySnapshot> getPendingApprovalsStream({
    String? selectedBranchId,
    List<String>? branchIds,
  }) {
    Query query = _db
        .collection('attendance')
        .where('status', isEqualTo: 'unscheduled_present')
        .where('isApproved', isEqualTo: false);

    if (selectedBranchId != null && selectedBranchId.isNotEmpty) {
      query = query.where('branchIds', arrayContains: selectedBranchId);
    } else if (branchIds != null && branchIds.isNotEmpty) {
      query = query.where('branchIds',
          arrayContainsAny: branchIds.take(10).toList());
    }

    return query.snapshots();
  }

  /// Stream attendance records that have a clockIn but no clockOut from a
  /// PREVIOUS date — "stale" open sessions that were never properly closed.
  /// Firestore can't query `clockOut == null AND date < today` directly, so
  /// we fetch all open sessions and filter client-side.
  Stream<List<Map<String, dynamic>>> getStaleClockedInStream({
    String? selectedBranchId,
    List<String>? branchIds,
  }) {
    final today = _todayString();

    Query query = _db
        .collection('attendance')
        .where('clockIn', isNull: false)
        .where('clockOut', isNull: true);

    if (selectedBranchId != null && selectedBranchId.isNotEmpty) {
      query = query.where('branchIds', arrayContains: selectedBranchId);
    } else if (branchIds != null && branchIds.isNotEmpty) {
      query = query.where('branchIds',
          arrayContainsAny: branchIds.take(10).toList());
    }

    return query.snapshots().map((snap) {
      return snap.docs
          .map((d) => {...(d.data() as Map<String, dynamic>), '_docId': d.id})
          .where((r) {
            final date = r['date'] as String? ?? '';
            return date.isNotEmpty && date != today;
          })
          .toList();
    });
  }


  // ---------------------------------------------------------------------------
  // PENDING APPROVAL ACTIONS
  // ---------------------------------------------------------------------------

  /// Approve an unscheduled clock-in.
  Future<void> approveUnscheduledArrival(
    String docId,
    String approvedBy, {
    String? note,
    String? retroShiftStart,
    String? retroShiftEnd,
    String? retroShiftId,
  }) async {
    final updates = <String, dynamic>{
      'isApproved': true,
      'approvedBy': approvedBy,
      'status': 'present',
    };
    if (note != null && note.isNotEmpty) updates['note'] = note;
    if (retroShiftStart != null) updates['scheduledStart'] = retroShiftStart;
    if (retroShiftEnd != null) updates['scheduledEnd'] = retroShiftEnd;
    if (retroShiftId != null) updates['shiftId'] = retroShiftId;
    await _db.collection('attendance').doc(docId).update(updates);
  }

  /// Reject and delete an unscheduled clock-in record.
  Future<void> rejectUnscheduledArrival(String docId, String rejectedBy) async {
    await _db.collection('attendance').doc(docId).update({
      'isApproved': false,
      'approvedBy': rejectedBy,
      'status': 'rejected',
      'note': 'Rejected by $rejectedBy',
    });
  }

  // ---------------------------------------------------------------------------
  // REGULARIZATION — full audit trail
  // ---------------------------------------------------------------------------

  /// Regularize an attendance record with mandatory reason + audit trail.
  Future<void> regularizeRecord({
    required String docId,
    required String managerId,
    required String reason,
    DateTime? newClockIn,
    DateTime? newClockOut,
    String? newStatus,
    String? newNote,
  }) async {
    final docRef = _db.collection('attendance').doc(docId);
    final snap = await docRef.get();
    if (!snap.exists) throw Exception('Attendance record not found.');

    final original = Map<String, dynamic>.from(snap.data() as Map);
    final updates = <String, dynamic>{
      'status': newStatus ?? 'regularized',
      'regularizedBy': managerId,
      'regularizedAt': FieldValue.serverTimestamp(),
    };

    if (newClockIn != null) {
      updates['clockIn'] = Timestamp.fromDate(newClockIn);
    }
    if (newClockOut != null) {
      updates['clockOut'] = Timestamp.fromDate(newClockOut);
      // Recompute total hours if both available
      final existingIn =
          (updates['clockIn'] as Timestamp?) ?? original['clockIn'] as Timestamp?;
      if (existingIn != null) {
        final diff = newClockOut.difference(existingIn.toDate());
        updates['totalHoursWorked'] = diff.inSeconds / 3600.0;
      }
    }
    if (newNote != null && newNote.isNotEmpty) updates['note'] = newNote;
    if (newStatus != null) updates['status'] = newStatus;
    // Ensure status is regularized if manually overridden
    if (newStatus == null) updates['status'] = 'regularized';

    await docRef.update(updates);

    // Write immutable audit sub-document
    await docRef.collection('audit_trail').add({
      'changedBy': managerId,
      'changedAt': FieldValue.serverTimestamp(),
      'reason': reason,
      'originalValues': {
        'clockIn': original['clockIn'],
        'clockOut': original['clockOut'],
        'status': original['status'],
        'note': original['note'],
        'lateMinutes': original['lateMinutes'],
        'earlyLeaveMinutes': original['earlyLeaveMinutes'],
        'overtimeMinutes': original['overtimeMinutes'],
      },
      'newValues': updates,
    });
  }

  // ---------------------------------------------------------------------------
  // AUTO-ABSENT (called by AttendanceAutoAbsentService)
  // ---------------------------------------------------------------------------

  /// Mark an employee as absent for today if no record exists.
  Future<bool> markAbsent({
    required String staffId,
    required String staffEmail,
    required String staffName,
    required List<String> branchIds,
    required String scheduledStart,
    required String scheduledEnd,
    required String shiftId,
    required int autoAbsentAfterMinutes,
  }) async {
    final today = _todayString();
    final existing = await _db
        .collection('attendance')
        .where('staffId', isEqualTo: staffId)
        .where('date', isEqualTo: today)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) return false; // Already has a record

    await _db.collection('attendance').add({
      'staffId': staffId,
      'staffEmail': staffEmail,
      'staffName': staffName,
      'branchIds': branchIds,
      'date': today,
      'clockIn': null,
      'clockOut': null,
      'status': 'absent',
      'lateMinutes': 0,
      'earlyLeaveMinutes': 0,
      'overtimeMinutes': 0,
      'totalHoursWorked': 0.0,
      'scheduledStart': scheduledStart,
      'scheduledEnd': scheduledEnd,
      'shiftId': shiftId,
      'isApproved': true,
      'approvedBy': 'system_auto',
      'note':
          'Auto-marked absent: no clock-in after $autoAbsentAfterMinutes min.',
      'createdAt': FieldValue.serverTimestamp(),
      'isAutoAbsent': true,
    });
    return true;
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

  /// Get count of staff clocked in today (clockOut == null = active session).
  Stream<int> getClockedInTodayCount(
      {String? selectedBranchId, List<String>? branchIds}) {
    final today = _todayString();
    // Firestore does not support isNull queries — fetch all today's records
    // and count the ones where clockOut is still null (active session).
    Query query =
        _db.collection('attendance').where('date', isEqualTo: today);

    if (selectedBranchId != null && selectedBranchId.isNotEmpty) {
      query = query.where('branchIds', arrayContains: selectedBranchId);
    } else if (branchIds != null && branchIds.isNotEmpty) {
      query = query.where('branchIds',
          arrayContainsAny: branchIds.take(10).toList());
    }

    return query.snapshots().map((snap) => snap.docs.where((d) {
          final data = d.data() as Map<String, dynamic>;
          return data['clockOut'] == null;
        }).length);
  }

  /// Get total attendance count for today — includes staff who have clocked out.
  Stream<int> getTotalAttendanceToday(
      {String? selectedBranchId, List<String>? branchIds}) {
    final today = _todayString();
    Query query =
        _db.collection('attendance').where('date', isEqualTo: today);

    if (selectedBranchId != null && selectedBranchId.isNotEmpty) {
      query = query.where('branchIds', arrayContains: selectedBranchId);
    } else if (branchIds != null && branchIds.isNotEmpty) {
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
  // DRIVERS (from 'staff' collection with staffType == 'driver')
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
}
