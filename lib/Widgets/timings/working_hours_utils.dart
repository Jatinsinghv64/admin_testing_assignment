class WorkingHoursValidationIssue {
  final String code;
  final String message;
  final String day;
  final int? slotIndex;
  final String? relatedDay;
  final int? relatedSlotIndex;

  const WorkingHoursValidationIssue({
    required this.code,
    required this.message,
    required this.day,
    this.slotIndex,
    this.relatedDay,
    this.relatedSlotIndex,
  });
}

class WorkingHoursValidationResult {
  final Map<String, dynamic> normalizedWorkingHours;
  final List<WorkingHoursValidationIssue> issues;

  const WorkingHoursValidationResult({
    required this.normalizedWorkingHours,
    required this.issues,
  });

  bool get isValid => issues.isEmpty;

  String? get firstErrorMessage => issues.isEmpty ? null : issues.first.message;

  String? errorForDay(String day) {
    for (final issue in issues) {
      if (issue.day == day || issue.relatedDay == day) {
        return issue.message;
      }
    }
    return null;
  }

  Set<String> get conflictSlotKeys {
    final keys = <String>{};
    for (final issue in issues) {
      if (issue.code != 'same_day_overlap' &&
          issue.code != 'cross_day_overlap') {
        continue;
      }
      if (issue.slotIndex != null) {
        keys.add(_buildSlotKey(issue.day, issue.slotIndex!));
      }
      if (issue.relatedDay != null && issue.relatedSlotIndex != null) {
        keys.add(_buildSlotKey(issue.relatedDay!, issue.relatedSlotIndex!));
      }
    }
    return keys;
  }

  static String _buildSlotKey(String day, int slotIndex) => '$day:$slotIndex';
}

class WorkingHoursUtils {
  static const List<String> orderedDays = <String>[
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];

  static const String defaultOpenTime = '09:00';
  static const String defaultCloseTime = '22:00';

  static Map<String, dynamic> createDefaultWorkingHours({
    bool isOpen = true,
    bool includeStaffingDefaults = false,
    int defaultStaffCount = 4,
    int defaultRequiredStaff = 4,
  }) {
    final workingHours = <String, dynamic>{};

    for (final day in orderedDays) {
      workingHours[day] = <String, dynamic>{
        'isOpen': isOpen,
        'slots': <Map<String, dynamic>>[
          createDefaultSlot(
            includeStaffingDefaults: includeStaffingDefaults,
            defaultStaffCount: defaultStaffCount,
            defaultRequiredStaff: defaultRequiredStaff,
          ),
        ],
      };
    }

    return workingHours;
  }

  static Map<String, dynamic> createDefaultSlot({
    bool includeStaffingDefaults = false,
    int defaultStaffCount = 4,
    int defaultRequiredStaff = 4,
  }) {
    final slot = <String, dynamic>{
      'open': defaultOpenTime,
      'close': defaultCloseTime,
    };

    if (includeStaffingDefaults) {
      slot['staffCount'] = defaultStaffCount;
      slot['requiredStaff'] = defaultRequiredStaff;
    }

    return slot;
  }

  static Map<String, dynamic> cloneWorkingHours(
    Map<String, dynamic>? source, {
    bool includeStaffingDefaults = false,
  }) {
    final cloned = <String, dynamic>{};

    for (final day in orderedDays) {
      final rawDay = source != null ? source[day] : null;
      cloned[day] = _normalizeDaySchedule(
        rawDay,
        includeStaffingDefaults: includeStaffingDefaults,
      );
    }

    return cloned;
  }

  static WorkingHoursValidationResult validateWorkingHours(
    Map<String, dynamic>? source, {
    bool includeStaffingDefaults = false,
    bool requireSlotsForOpenDay = true,
  }) {
    final normalizedWorkingHours = cloneWorkingHours(
      source,
      includeStaffingDefaults: includeStaffingDefaults,
    );
    final issues = <WorkingHoursValidationIssue>[];

    for (final day in orderedDays) {
      final dayData =
          Map<String, dynamic>.from(normalizedWorkingHours[day] ?? const {});
      final isOpen = dayData['isOpen'] == true;
      final slots =
          List<Map<String, dynamic>>.from(dayData['slots'] ?? const []);

      if (isOpen && requireSlotsForOpenDay && slots.isEmpty) {
        issues.add(
          WorkingHoursValidationIssue(
            code: 'open_day_without_slots',
            message: '${_labelForDay(day)} is marked open but has no shifts.',
            day: day,
          ),
        );
      }

      if (!isOpen) {
        continue;
      }

      for (var index = 0; index < slots.length; index++) {
        final slot = slots[index];
        final open = parseTimeToMinutes(slot['open']);
        final close = parseTimeToMinutes(slot['close']);

        if (open == null) {
          issues.add(
            WorkingHoursValidationIssue(
              code: 'invalid_open_time',
              message:
                  '${_labelForDay(day)} shift ${index + 1} has an invalid opening time.',
              day: day,
              slotIndex: index,
            ),
          );
        }

        if (close == null) {
          issues.add(
            WorkingHoursValidationIssue(
              code: 'invalid_close_time',
              message:
                  '${_labelForDay(day)} shift ${index + 1} has an invalid closing time.',
              day: day,
              slotIndex: index,
            ),
          );
        }
      }

      for (var first = 0; first < slots.length; first++) {
        for (var second = first + 1; second < slots.length; second++) {
          if (doSlotsOverlap(slots[first], slots[second])) {
            issues.add(
              WorkingHoursValidationIssue(
                code: 'same_day_overlap',
                message:
                    '${_labelForDay(day)} shifts ${first + 1} and ${second + 1} overlap.',
                day: day,
                slotIndex: first,
                relatedDay: day,
                relatedSlotIndex: second,
              ),
            );
          }
        }
      }
    }

    for (var dayIndex = 0; dayIndex < orderedDays.length; dayIndex++) {
      final day = orderedDays[dayIndex];
      final nextDay = orderedDays[(dayIndex + 1) % orderedDays.length];
      final currentDayData =
          Map<String, dynamic>.from(normalizedWorkingHours[day] ?? const {});
      final nextDayData = Map<String, dynamic>.from(
          normalizedWorkingHours[nextDay] ?? const {});

      if (currentDayData['isOpen'] != true || nextDayData['isOpen'] != true) {
        continue;
      }

      final daySlots = _extractSlots(currentDayData);
      final nextDaySlots = _extractSlots(nextDayData);

      for (var currentIndex = 0;
          currentIndex < daySlots.length;
          currentIndex++) {
        final currentInterval =
            _slotInterval(daySlots[currentIndex], dayOffset: 0);
        if (currentInterval == null ||
            currentInterval.endMinutes <= _minutesPerDay) {
          continue;
        }

        for (var nextIndex = 0; nextIndex < nextDaySlots.length; nextIndex++) {
          final nextInterval =
              _slotInterval(nextDaySlots[nextIndex], dayOffset: 1);
          if (nextInterval == null) {
            continue;
          }

          if (_intervalsOverlap(currentInterval, nextInterval)) {
            issues.add(
              WorkingHoursValidationIssue(
                code: 'cross_day_overlap',
                message:
                    '${_labelForDay(day)} shift ${currentIndex + 1} overlaps with ${_labelForDay(nextDay)} shift ${nextIndex + 1}.',
                day: day,
                slotIndex: currentIndex,
                relatedDay: nextDay,
                relatedSlotIndex: nextIndex,
              ),
            );
          }
        }
      }
    }

    return WorkingHoursValidationResult(
      normalizedWorkingHours: normalizedWorkingHours,
      issues: issues,
    );
  }

  static List<Map<String, dynamic>> normalizeSlots(
    Object? rawSlots, {
    bool includeStaffingDefaults = false,
  }) {
    if (rawSlots is! List) {
      return <Map<String, dynamic>>[];
    }

    final normalized = <Map<String, dynamic>>[];

    for (final rawSlot in rawSlots) {
      if (rawSlot is! Map) {
        continue;
      }

      final slot = Map<String, dynamic>.from(rawSlot);
      final normalizedSlot = <String, dynamic>{
        'open': normalizeTimeString(slot['open']) ?? defaultOpenTime,
        'close': normalizeTimeString(slot['close']) ?? defaultCloseTime,
      };

      final includesStaffing = includeStaffingDefaults ||
          slot.containsKey('staffCount') ||
          slot.containsKey('requiredStaff');

      if (includesStaffing) {
        normalizedSlot['staffCount'] =
            _normalizeInt(slot['staffCount'], fallback: 4, min: 0);
        normalizedSlot['requiredStaff'] =
            _normalizeInt(slot['requiredStaff'], fallback: 4, min: 1);
      }

      normalized.add(normalizedSlot);
    }

    normalized.sort(_compareSlots);
    return normalized;
  }

  static String? normalizeTimeString(dynamic rawTime) {
    final minutes = parseTimeToMinutes(rawTime);
    if (minutes == null) {
      return null;
    }
    return formatMinutesToTime(minutes);
  }

  static int? parseTimeToMinutes(dynamic rawTime) {
    if (rawTime is! String) {
      return null;
    }

    final parts = rawTime.split(':');
    if (parts.length != 2) {
      return null;
    }

    final hours = int.tryParse(parts[0]);
    final minutes = int.tryParse(parts[1]);
    if (hours == null || minutes == null) {
      return null;
    }

    if (hours < 0 || hours > 23 || minutes < 0 || minutes > 59) {
      return null;
    }

    return (hours * 60) + minutes;
  }

  static String formatMinutesToTime(int totalMinutes) {
    final normalized =
        ((totalMinutes % _minutesPerDay) + _minutesPerDay) % _minutesPerDay;
    final hours = (normalized ~/ 60).toString().padLeft(2, '0');
    final minutes = (normalized % 60).toString().padLeft(2, '0');
    return '$hours:$minutes';
  }

  static int calculateSlotDurationMinutes(Map<String, dynamic> slot) {
    final open = parseTimeToMinutes(slot['open']);
    final close = parseTimeToMinutes(slot['close']);
    if (open == null || close == null) {
      return 0;
    }

    var duration = close - open;
    if (duration <= 0) {
      duration += _minutesPerDay;
    }
    return duration;
  }

  static bool doSlotsOverlap(
      Map<String, dynamic> first, Map<String, dynamic> second) {
    final firstInterval = _slotInterval(first, dayOffset: 0);
    final secondInterval = _slotInterval(second, dayOffset: 0);
    if (firstInterval == null || secondInterval == null) {
      return false;
    }

    return _intervalsOverlap(firstInterval, secondInterval);
  }

  static bool isOvernightSlot(Map<String, dynamic> slot) {
    final open = parseTimeToMinutes(slot['open']);
    final close = parseTimeToMinutes(slot['close']);
    if (open == null || close == null) {
      return false;
    }
    return close <= open;
  }

  static String slotKey(String day, int slotIndex) => '$day:$slotIndex';

  static Map<String, dynamic> _normalizeDaySchedule(
    Object? rawDay, {
    required bool includeStaffingDefaults,
  }) {
    final dayMap =
        rawDay is Map ? Map<String, dynamic>.from(rawDay) : <String, dynamic>{};

    return <String, dynamic>{
      'isOpen': dayMap['isOpen'] == true,
      'slots': normalizeSlots(
        dayMap['slots'],
        includeStaffingDefaults: includeStaffingDefaults,
      ),
    };
  }

  static List<Map<String, dynamic>> _extractSlots(Object? rawDay) {
    if (rawDay is! Map) {
      return <Map<String, dynamic>>[];
    }
    return List<Map<String, dynamic>>.from(rawDay['slots'] ?? const []);
  }

  static int _normalizeInt(
    dynamic rawValue, {
    required int fallback,
    required int min,
  }) {
    int? parsed;
    if (rawValue is int) {
      parsed = rawValue;
    } else if (rawValue is double) {
      parsed = rawValue.round();
    } else if (rawValue is String) {
      parsed = int.tryParse(rawValue);
    }

    if (parsed == null || parsed < min) {
      return fallback;
    }
    return parsed;
  }

  static int _compareSlots(
      Map<String, dynamic> left, Map<String, dynamic> right) {
    final leftOpen = parseTimeToMinutes(left['open']) ?? 0;
    final rightOpen = parseTimeToMinutes(right['open']) ?? 0;
    if (leftOpen != rightOpen) {
      return leftOpen.compareTo(rightOpen);
    }

    final leftDuration = calculateSlotDurationMinutes(left);
    final rightDuration = calculateSlotDurationMinutes(right);
    return leftDuration.compareTo(rightDuration);
  }

  static String _labelForDay(String day) {
    if (day.isEmpty) {
      return 'Unknown day';
    }

    return day[0].toUpperCase() + day.substring(1);
  }

  static const int _minutesPerDay = 24 * 60;

  static _SlotInterval? _slotInterval(
    Map<String, dynamic> slot, {
    required int dayOffset,
  }) {
    final open = parseTimeToMinutes(slot['open']);
    final close = parseTimeToMinutes(slot['close']);
    if (open == null || close == null) {
      return null;
    }

    final startMinutes = (dayOffset * _minutesPerDay) + open;
    var endMinutes = (dayOffset * _minutesPerDay) + close;
    if (close <= open) {
      endMinutes += _minutesPerDay;
    }

    return _SlotInterval(
      startMinutes: startMinutes,
      endMinutes: endMinutes,
    );
  }

  static bool _intervalsOverlap(_SlotInterval left, _SlotInterval right) {
    return left.startMinutes < right.endMinutes &&
        right.startMinutes < left.endMinutes;
  }
}

class _SlotInterval {
  final int startMinutes;
  final int endMinutes;

  const _SlotInterval({
    required this.startMinutes,
    required this.endMinutes,
  });
}
