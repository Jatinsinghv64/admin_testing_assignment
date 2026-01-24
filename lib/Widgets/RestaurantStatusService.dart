import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import '../constants.dart';

/// Service to manage restaurant open/closed status based on manual override and schedule.
/// Uses lifecycle-aware timer to reduce resource usage when app is in background.
class RestaurantStatusService with ChangeNotifier, WidgetsBindingObserver {
  // Timer interval - set to 1 second for accurate countdown
  static const Duration _timerInterval = Duration(seconds: 1);
  static const Duration _closingWarningThreshold = Duration(minutes: 30);
  static const Duration _closingPopupThreshold = Duration(minutes: 2);

  bool _isActive = true;  // Lifecycle tracking
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
  bool get isOpen => _isManualOpen; // ✅ FIXED: Manual override takes precedence
  Duration? get timeUntilClose => _timeUntilClose;

  String get statusText {
    return isOpen ? "Open" : "Closed";
  }

  void initialize(String restaurantId, {String restaurantName = "Restaurant"}) {
    if (_restaurantId == restaurantId) return;

    _restaurantId = restaurantId;
    _restaurantName = restaurantName;

    tz_data.initializeTimeZones();

    _startListeningToRestaurantStatus();

    _timer?.cancel();
    // Timer runs every 30 seconds instead of every second to save battery
    _timer = Timer.periodic(_timerInterval, (timer) {
      if (_isActive) {
        _recalculateScheduleStatus();
      }
    });

    // Register for lifecycle events
    WidgetsBinding.instance.addObserver(this);
  }

  /// Handle app lifecycle changes to pause timer in background
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isActive = state == AppLifecycleState.resumed;
    if (_isActive) {
      // Recalculate immediately when returning to foreground
      _recalculateScheduleStatus();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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

    // ✅ Updated to use AppConstants.collectionBranch
    _branchSubscription = _db
        .collection(AppConstants.collectionBranch)
        .doc(_restaurantId)
        .snapshots()
        .listen((doc) {
      if (doc.exists) {
        final data = doc.data()!;
        _isManualOpen = data['isOpen'] ?? false;
        _restaurantName = data['name'] ?? _restaurantName;
        _timezone = data['timezone'] ?? 'UTC';
        _workingHours = Map<String, dynamic>.from(data['workingHours'] ?? {});

        // Note: We do NOT reset _popupShownToday here to avoid loops.
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

      if (_isScheduleOpen != openNow) {
        _isScheduleOpen = openNow;
        // Only reset popup flag if the schedule effectively changes (e.g. new shift started)
        if (openNow) {
          _popupShownToday = false;
        }
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

      // Reset popup logic: If user extended time (difference > 5 mins), allow popup again later
      if (difference.inMinutes > 5) {
        _popupShownToday = false;
      }

      // Update Banner (Show if within threshold)
      if (difference <= _closingWarningThreshold && difference.inSeconds > 0) {
        _timeUntilClose = difference;
        notifyListeners();
      } else {
        if (_timeUntilClose != null) {
          _timeUntilClose = null;
          notifyListeners();
        }
      }

      // Trigger Popup (Show if within popup threshold)
      if (difference <= _closingPopupThreshold && difference.inSeconds > 0 && !_popupShownToday) {
        _popupShownToday = true;
        _closingPopupController.add(true);
      }
    }
  }

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

  bool _isToggling = false;
  bool get isToggling => _isToggling;

  /// Manually toggles the restaurant status.
  /// This should only be called by User Interaction (e.g. Tapping the Switch in Settings),
  /// NEVER by the automatic timer.
  Future<void> toggleRestaurantStatus(bool newStatus) async {
    if (_restaurantId == null) return;

    _isToggling = true;
    notifyListeners();

    try {
      // ✅ FIXED: Only set manual flags when acting AGAINST the schedule
      // - If schedule says OPEN and user is opening → no flags needed (following schedule)
      // - If schedule says OPEN and user is closing → set manuallyClosed
      // - If schedule says CLOSED and user is opening → set manuallyOpened
      // - If schedule says CLOSED and user is closing → no flags needed (following schedule)
      
      Map<String, dynamic> updateData = {
        'isOpen': newStatus,
        'lastStatusUpdate': FieldValue.serverTimestamp(),
      };

      if (_isScheduleOpen) {
        // Schedule says OPEN
        if (!newStatus) {
          // User is closing during scheduled hours → manual override
          updateData['manuallyClosed'] = true;
          updateData['manuallyOpened'] = false;
        } else {
          // User is opening during scheduled hours → following schedule, clear flags
          updateData['manuallyClosed'] = false;
          updateData['manuallyOpened'] = false;
        }
      } else {
        // Schedule says CLOSED
        if (newStatus) {
          // User is opening during off-hours → manual override
          updateData['manuallyOpened'] = true;
          updateData['manuallyClosed'] = false;
        } else {
          // User is closing during off-hours → following schedule, clear flags
          updateData['manuallyClosed'] = false;
          updateData['manuallyOpened'] = false;
        }
      }

      await _db.collection(AppConstants.collectionBranch).doc(_restaurantId!).set(
        updateData, 
        SetOptions(merge: true),
      );

      _isManualOpen = newStatus;
    } catch (e) {
      // Revert is handled by listener mostly, but we can notify error
      rethrow;
    } finally {
      _isToggling = false;
      notifyListeners();
    }
  }

  /// Static helper to check if a branch is within schedule hours.
  /// Can be used by any screen without needing an initialized service instance.
  /// Returns a Map with:
  /// - 'isScheduleOpen': bool - whether the branch is within schedule hours
  /// - 'isManuallyOverridden': bool - whether the status is manually overridden
  /// - 'currentIsOpen': bool - the current isOpen status
  static Future<Map<String, dynamic>> checkBranchScheduleStatus(String branchId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection(AppConstants.collectionBranch)
          .doc(branchId)
          .get();

      if (!doc.exists) {
        return {
          'isScheduleOpen': false,
          'isManuallyOverridden': false,
          'currentIsOpen': false,
          'error': 'Branch not found',
        };
      }

      final data = doc.data()!;
      final currentIsOpen = data['isOpen'] ?? false;
      final timezone = data['timezone'] ?? 'UTC';
      final workingHours = Map<String, dynamic>.from(data['workingHours'] ?? {});

      // If no working hours configured, consider schedule as "always open"
      if (workingHours.isEmpty) {
        return {
          'isScheduleOpen': true,
          'isManuallyOverridden': false,
          'currentIsOpen': currentIsOpen,
        };
      }

      // Check schedule using branch timezone
      tz_data.initializeTimeZones();
      final location = tz.getLocation(timezone);
      final now = tz.TZDateTime.now(location);

      bool isScheduleOpen = _checkDayScheduleStatic(now, 0, workingHours) || 
                            _checkDayScheduleStatic(now, -1, workingHours);

      // Determine if manually overridden
      bool isManuallyOverridden = false;
      if (isScheduleOpen && !currentIsOpen) {
        isManuallyOverridden = true; // Closed during scheduled hours
      } else if (!isScheduleOpen && currentIsOpen) {
        isManuallyOverridden = true; // Open outside scheduled hours
      }

      return {
        'isScheduleOpen': isScheduleOpen,
        'isManuallyOverridden': isManuallyOverridden,
        'currentIsOpen': currentIsOpen,
      };
    } catch (e) {
      debugPrint('Error checking branch schedule: $e');
      return {
        'isScheduleOpen': true, // Fail-open to allow toggling
        'isManuallyOverridden': false,
        'currentIsOpen': false,
        'error': e.toString(),
      };
    }
  }

  /// Static version of schedule check for a specific day
  static bool _checkDayScheduleStatic(tz.TZDateTime now, int dayOffset, Map<String, dynamic> workingHours) {
    final checkDate = now.add(Duration(days: dayOffset));
    const days = {1: 'monday', 2: 'tuesday', 3: 'wednesday', 4: 'thursday', 5: 'friday', 6: 'saturday', 7: 'sunday'};
    final dayName = days[checkDate.weekday] ?? 'monday';
    
    final dayData = workingHours[dayName];
    if (dayData == null || dayData['isOpen'] != true) return false;
    
    final List slots = dayData['slots'] ?? [];
    if (slots.isEmpty) return false;

    for (var slot in slots) {
      try {
        final openStr = slot['open'] as String?;
        final closeStr = slot['close'] as String?;
        if (openStr == null || closeStr == null) continue;

        final openParts = openStr.split(':').map(int.parse).toList();
        final closeParts = closeStr.split(':').map(int.parse).toList();

        final openTime = tz.TZDateTime(now.location, checkDate.year, checkDate.month, checkDate.day, openParts[0], openParts[1]);
        var closeTime = tz.TZDateTime(now.location, checkDate.year, checkDate.month, checkDate.day, closeParts[0], closeParts[1]);

        // Handle overnight shifts (e.g., 22:00 - 02:00)
        if (closeTime.isBefore(openTime) || closeTime.isAtSameMomentAs(openTime)) {
          closeTime = closeTime.add(const Duration(days: 1));
        }

        if (now.isAfter(openTime) && now.isBefore(closeTime)) {
          return true;
        }
      } catch (e) {
        debugPrint('Error parsing slot times: $e');
      }
    }
    return false;
  }

  /// Static helper to build the correct update data for toggling branch status
  static Map<String, dynamic> buildStatusUpdateData(bool newStatus, bool isScheduleOpen) {
    Map<String, dynamic> updateData = {
      'isOpen': newStatus,
      'lastStatusUpdate': FieldValue.serverTimestamp(),
    };

    if (isScheduleOpen) {
      if (!newStatus) {
        // Closing during scheduled hours → manual override
        updateData['manuallyClosed'] = true;
        updateData['manuallyOpened'] = false;
      } else {
        // Opening during scheduled hours → following schedule
        updateData['manuallyClosed'] = false;
        updateData['manuallyOpened'] = false;
      }
    } else {
      if (newStatus) {
        // Opening during off-hours → manual override
        updateData['manuallyOpened'] = true;
        updateData['manuallyClosed'] = false;
      } else {
        // Closing during off-hours → following schedule
        updateData['manuallyClosed'] = false;
        updateData['manuallyOpened'] = false;
      }
    }

    return updateData;
  }
}