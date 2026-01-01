import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:mdd/Widgets/working_hours_model.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

class RestaurantStatusService with ChangeNotifier, WidgetsBindingObserver {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Streams & Timers
  StreamSubscription<DocumentSnapshot>? _branchSubscription;
  Timer? _scheduleCheckTimer;

  // Controllers
  final _closingPopupController = StreamController<bool>.broadcast();
  Stream<bool> get closingPopupStream => _closingPopupController.stream;

  // State
  String? _restaurantId;
  String? _restaurantName;
  String _timezone = 'UTC';

  // Parsed Schedule
  Map<String, DaySchedule> _scheduleMap = {};

  // Status Flags
  bool _isManualOpen = false; // Database "isOpen" flag
  bool _isWithinSchedule = false; // Is current time within a valid slot?
  bool _isLoading = true;
  Duration? _timeUntilClose;

  // --- ✅ RESTORED GETTERS FOR UI ---
  bool get isLoading => _isLoading;
  String? get restaurantName => _restaurantName;
  Duration? get timeUntilClose => _timeUntilClose;

  // 1. Used by the Switch Widget to show if the "toggle" is On/Off
  bool get isManualOpen => _isManualOpen;

  // 2. Used by the App Bar to show "Green/Red" status
  // It is only "Fully Open" if the Switch is ON AND the Schedule matches.
  bool get isOpen => _isManualOpen && _isWithinSchedule;

  // 3. Used by the Status Badge text
  String get statusText {
    if (!_isManualOpen) return "Closed (Manually)";
    if (!_isWithinSchedule) return "Closed (Schedule)";
    return "Open";
  }

  RestaurantStatusService() {
    WidgetsBinding.instance.addObserver(this);
    tz_data.initializeTimeZones();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _branchSubscription?.cancel();
    _scheduleCheckTimer?.cancel();
    _closingPopupController.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _calculateScheduleStatus();
    }
  }

  void initialize(String restaurantId, {String restaurantName = "Restaurant"}) {
    if (_restaurantId == restaurantId) return;
    _restaurantId = restaurantId;
    _restaurantName = restaurantName;
    _startListening();
  }

  void _startListening() {
    _isLoading = true;
    notifyListeners();

    _branchSubscription?.cancel();
    _branchSubscription = _db.collection('Branch').doc(_restaurantId).snapshots().listen(
          (doc) {
        if (!doc.exists) {
          _handleErrorState();
          return;
        }

        final data = doc.data()!;
        _isManualOpen = data['isOpen'] ?? false;
        _restaurantName = data['name'] ?? _restaurantName;
        _timezone = data['timezone'] ?? 'UTC';

        // Parse Schedule
        final rawHours = data['workingHours'] as Map<String, dynamic>? ?? {};
        _scheduleMap = rawHours.map((key, value) =>
            MapEntry(key, DaySchedule.fromMap(value)));

        _isLoading = false;
        _calculateScheduleStatus();
      },
      onError: (e) => debugPrint("🔥 Error listening to branch: $e"),
    );
  }

  void _handleErrorState() {
    _isManualOpen = false;
    _isWithinSchedule = false;
    _isLoading = false;
    notifyListeners();
  }

  void _calculateScheduleStatus() {
    if (_scheduleMap.isEmpty) {
      // If no schedule is defined, we assume it's "Always Open" regarding schedule
      // and rely solely on the Manual Switch.
      if (!_isWithinSchedule) {
        _isWithinSchedule = true;
        notifyListeners();
      }
      return;
    }

    try {
      final location = tz.getLocation(_timezone);
      final now = tz.TZDateTime.now(location);

      final currentSlotEnd = _getCurrentSlotEndTime(now);
      final bool newScheduleStatus = currentSlotEnd != null;

      // Check for Auto-Close Trigger (Schedule ended while manually open)
      if (_isWithinSchedule && !newScheduleStatus && _isManualOpen) {
        debugPrint("⏰ Schedule End Reached. Closing Restaurant in DB...");
        toggleRestaurantStatus(false);
        _closingPopupController.add(true);
      }

      _isWithinSchedule = newScheduleStatus;

      if (_isWithinSchedule && currentSlotEnd != null) {
        final diff = currentSlotEnd.difference(now);
        _timeUntilClose = diff;
        _scheduleNextCheck(diff);
      } else {
        _timeUntilClose = null;
        _scheduleNextCheck(const Duration(minutes: 1));
      }

      notifyListeners();

    } catch (e) {
      debugPrint("⚠️ Schedule Calculation Error: $e");
    }
  }

  void _scheduleNextCheck(Duration duration) {
    _scheduleCheckTimer?.cancel();
    // Update at least every minute for UI countdowns
    final nextTick = duration.inSeconds > 60 ? const Duration(minutes: 1) : duration;

    _scheduleCheckTimer = Timer(nextTick, () {
      _calculateScheduleStatus();
    });
  }

  tz.TZDateTime? _getCurrentSlotEndTime(tz.TZDateTime now) {
    for (int dayOffset in [-1, 0]) {
      final checkDate = now.add(Duration(days: dayOffset));
      final dayName = _getDayName(checkDate.weekday);
      final schedule = _scheduleMap[dayName];

      if (schedule == null || !schedule.isOpen) continue;

      final int nowMinutesTotal = _getMinutesFromMidnight(now, checkDate);

      for (var slot in schedule.slots) {
        bool isOpen;

        if (slot.closeMinutes < slot.openMinutes) {
          // Spans midnight
          if (dayOffset == -1) {
            isOpen = nowMinutesTotal < slot.closeMinutes + 1440;
          } else {
            isOpen = nowMinutesTotal >= slot.openMinutes;
          }
        } else {
          // Standard Slot
          if (dayOffset == -1) continue;
          isOpen = nowMinutesTotal >= slot.openMinutes && nowMinutesTotal < slot.closeMinutes;
        }

        if (isOpen) {
          return _getPreciseClosingTime(checkDate, slot);
        }
      }
    }
    return null;
  }

  tz.TZDateTime _getPreciseClosingTime(tz.TZDateTime date, TimeSlot slot) {
    int closeDay = date.day;
    int closeMinutes = slot.closeMinutes;

    if (slot.closeMinutes < slot.openMinutes) {
      closeDay += 1;
    }

    return tz.TZDateTime(
        date.location, date.year, date.month, closeDay,
        closeMinutes ~/ 60, closeMinutes % 60
    );
  }

  int _getMinutesFromMidnight(tz.TZDateTime now, tz.TZDateTime midnightRef) {
    return now.difference(tz.TZDateTime(
        now.location, midnightRef.year, midnightRef.month, midnightRef.day
    )).inMinutes;
  }

  String _getDayName(int weekday) {
    const days = {1: 'monday', 2: 'tuesday', 3: 'wednesday', 4: 'thursday', 5: 'friday', 6: 'saturday', 7: 'sunday'};
    return days[weekday] ?? 'monday';
  }

  Future<void> toggleRestaurantStatus(bool newStatus) async {
    if (_restaurantId == null) return;

    _isManualOpen = newStatus;
    notifyListeners();

    try {
      await _db.collection('Branch').doc(_restaurantId!).update({
        'isOpen': newStatus,
        'lastStatusUpdate': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      _isManualOpen = !newStatus;
      notifyListeners();
      rethrow;
    }
  }
}