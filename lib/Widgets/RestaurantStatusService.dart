import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

class RestaurantStatusService with ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  StreamSubscription<DocumentSnapshot>? _branchSubscription;
  Timer? _timer;

  final _closingPopupController = StreamController<bool>.broadcast();
  Stream<bool> get closingPopupStream => _closingPopupController.stream;

  bool _popupShownToday = false;

  // --- STATE VARIABLES ---
  bool _isManualOpen = false;
  bool _isScheduleOpen = false;
  bool _isLoading = false;
  Duration? _timeUntilClose;

  String? _restaurantId;
  String? _restaurantName;
  String _timezone = 'UTC';
  Map<String, dynamic> _workingHours = {};

  // --- GETTERS ---
  bool get isLoading => _isLoading;
  String? get restaurantId => _restaurantId;
  String? get restaurantName => _restaurantName;
  bool get isManualOpen => _isManualOpen;
  bool get isScheduleOpen => _isScheduleOpen;
  bool get isOpen => _isManualOpen && _isScheduleOpen;
  Duration? get timeUntilClose => _timeUntilClose;

  String get statusText {
    if (!_isManualOpen) return "Closed (Manually)";
    if (!_isScheduleOpen) return "Closed (Schedule)";
    return "Open";
  }

  void initialize(String restaurantId, {String restaurantName = "Restaurant"}) {
    if (_restaurantId == restaurantId) return;

    _restaurantId = restaurantId;
    _restaurantName = restaurantName;

    tz_data.initializeTimeZones();

    _startListeningToRestaurantStatus();

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _recalculateScheduleStatus();
    });
  }

  @override
  void dispose() {
    _branchSubscription?.cancel();
    _timer?.cancel();
    _closingPopupController.close();
    super.dispose();
  }

  void _startListeningToRestaurantStatus() {
    if (_restaurantId == null) return;
    _isLoading = true;
    notifyListeners();

    _branchSubscription?.cancel();
    _branchSubscription = _db.collection('Branch').doc(_restaurantId).snapshots().listen((doc) {
      if (doc.exists) {
        final data = doc.data()!;
        _isManualOpen = data['isOpen'] ?? false;
        _restaurantName = data['name'] ?? _restaurantName;
        _timezone = data['timezone'] ?? 'UTC';
        _workingHours = Map<String, dynamic>.from(data['workingHours'] ?? {});

        // ❌ REMOVED: _popupShownToday = false;
        // We DO NOT reset the flag here. Resetting on every snapshot causes the loop.
      } else {
        _isManualOpen = false;
      }

      _recalculateScheduleStatus();
      _isLoading = false;
      notifyListeners();
    });
  }

  void _recalculateScheduleStatus() {
    if (_workingHours.isEmpty) {
      if (_isScheduleOpen != true) {
        _isScheduleOpen = true;
        notifyListeners();
      }
      return;
    }

    try {
      final location = tz.getLocation(_timezone);
      final now = tz.TZDateTime.now(location);

      bool openNow = _checkDaySchedule(now, 0) || _checkDaySchedule(now, -1);

      // --- AUTO CLOSE LOGIC ---
      if (_isScheduleOpen && !openNow) {
        if (_isManualOpen) {
          debugPrint("⏰ Schedule Timer Expired: Closing Restaurant Manually.");
          toggleRestaurantStatus(false);
        }
      }

      if (_isScheduleOpen != openNow) {
        _isScheduleOpen = openNow;
        _popupShownToday = false; // ✅ Only reset if schedule actually changes (New Shift)
        notifyListeners();
      }

      // Only calculate countdown if we are effectively OPEN (Manual + Schedule)
      if (openNow && _isManualOpen) {
        _calculateTimeUntilClose(now);
      } else {
        _timeUntilClose = null;
        notifyListeners();
      }

    } catch (e) {
      debugPrint("⚠️ Schedule Error: $e");
      if (!_isScheduleOpen) {
        _isScheduleOpen = true;
        notifyListeners();
      }
    }
  }

  void _calculateTimeUntilClose(tz.TZDateTime now) {
    tz.TZDateTime? closingTime;

    for (int dayOffset in [0, -1]) {
      final checkDate = now.add(Duration(days: dayOffset));
      final dayName = _getDayName(checkDate.weekday);
      final dayData = _workingHours[dayName];
      if (dayData == null || dayData['isOpen'] != true) continue;

      final List slots = dayData['slots'] ?? [];
      for (var slot in slots) {
        final times = _parseSlotTimes(now, checkDate, slot['open'], slot['close']);
        if (times != null && now.isAfter(times['open']!) && now.isBefore(times['close']!)) {
          closingTime = times['close'];
          break;
        }
      }
      if (closingTime != null) break;
    }

    if (closingTime != null) {
      final difference = closingTime.difference(now);

      // ✅ RESET LOGIC: If time > 5 mins (e.g. user extended time), allow popup again later
      if (difference.inMinutes > 5) {
        _popupShownToday = false;
      }

      // Update Banner (Show if <= 30 mins)
      if (difference.inMinutes <= 30 && difference.inSeconds > 0) {
        _timeUntilClose = difference;
        notifyListeners();
      } else {
        if (_timeUntilClose != null) {
          _timeUntilClose = null;
          notifyListeners();
        }
      }

      // Trigger Popup (Show if <= 2 mins)
      if (difference.inMinutes <= 2 && difference.inSeconds > 0 && !_popupShownToday) {
        _popupShownToday = true;
        _closingPopupController.add(true);
      }
    }
  }

  // ... (Keep helper methods _checkDaySchedule, _parseSlotTimes, _getDayName exactly as before) ...
  bool _checkDaySchedule(tz.TZDateTime now, int dayOffset) {
    final checkDate = now.add(Duration(days: dayOffset));
    final String dayName = _getDayName(checkDate.weekday);
    final dayData = _workingHours[dayName];
    if (dayData == null || dayData['isOpen'] != true) return false;
    final List slots = dayData['slots'] ?? [];
    if (slots.isEmpty) return false;

    for (var slot in slots) {
      final times = _parseSlotTimes(now, checkDate, slot['open'], slot['close']);
      if (times != null && now.isAfter(times['open']!) && now.isBefore(times['close']!)) {
        return true;
      }
    }
    return false;
  }

  Map<String, tz.TZDateTime>? _parseSlotTimes(tz.TZDateTime now, tz.TZDateTime refDate, String openStr, String closeStr) {
    try {
      final openParts = openStr.split(':').map(int.parse).toList();
      final openTime = tz.TZDateTime(now.location, refDate.year, refDate.month, refDate.day, openParts[0], openParts[1]);

      final closeParts = closeStr.split(':').map(int.parse).toList();
      var closeTime = tz.TZDateTime(now.location, refDate.year, refDate.month, refDate.day, closeParts[0], closeParts[1]);

      if (closeTime.isBefore(openTime) || closeTime.isAtSameMomentAs(openTime)) {
        closeTime = closeTime.add(const Duration(days: 1));
      }
      return {'open': openTime, 'close': closeTime};
    } catch (e) {
      return null;
    }
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
      await _db.collection('Branch').doc(_restaurantId!).set({
        'isOpen': newStatus,
        'lastStatusUpdate': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      _isManualOpen = !newStatus;
      notifyListeners();
      rethrow;
    }
  }
}