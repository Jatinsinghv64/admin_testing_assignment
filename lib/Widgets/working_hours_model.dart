import 'package:flutter/material.dart';

class TimeSlot {
  final int openMinutes; // Minutes from midnight (e.g., 09:00 = 540)
  final int closeMinutes;

  TimeSlot({required this.openMinutes, required this.closeMinutes});

  // Factory to parse safe data
  factory TimeSlot.fromMap(Map<String, dynamic> map) {
    return TimeSlot(
      openMinutes: _timeStringToMinutes(map['open']),
      closeMinutes: _timeStringToMinutes(map['close']),
    );
  }

  static int _timeStringToMinutes(String? time) {
    if (time == null || !time.contains(':')) return 0;
    final parts = time.split(':');
    return (int.parse(parts[0]) * 60) + int.parse(parts[1]);
  }
}

class DaySchedule {
  final bool isOpen;
  final List<TimeSlot> slots;

  DaySchedule({required this.isOpen, required this.slots});

  factory DaySchedule.fromMap(Map<String, dynamic>? map) {
    if (map == null) return DaySchedule(isOpen: false, slots: []);

    final bool isOpen = map['isOpen'] ?? false;
    final List<dynamic> rawSlots = map['slots'] ?? [];

    // Only parse slots if the day is actually marked Open
    final slots = isOpen
        ? rawSlots.map((s) => TimeSlot.fromMap(Map<String, dynamic>.from(s))).toList()
        : <TimeSlot>[];

    return DaySchedule(isOpen: isOpen, slots: slots);
  }
}