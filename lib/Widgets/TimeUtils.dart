// lib/Widgets/TimeUtils.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

class TimeUtils {
  static const String _qatarLocation = 'Asia/Qatar';
  static bool _isInitialized = false;

  /// Ensures timezones are loaded. Call this in main.dart
  static void initialize() {
    if (!_isInitialized) {
      tz_data.initializeTimeZones();
      _isInitialized = true;
    }
  }

  /// Gets the current time in Qatar (Professional Standard)
  static tz.TZDateTime nowQatar() {
    if (!_isInitialized) initialize();
    final qatar = tz.getLocation(_qatarLocation);
    return tz.TZDateTime.now(qatar);
  }

  /// Calculates the start of the "Business Day" (6:00 AM Qatar Time)
  /// If now is 2 AM, it returns 6 AM of the *previous* day.
  static DateTime getBusinessStartDateTime() {
    final now = nowQatar();

    // If it's before 6 AM, the business day started yesterday at 6 AM
    final effectiveDate = now.hour < 6
        ? now.subtract(const Duration(days: 1))
        : now;

    return tz.TZDateTime(
      now.location,
      effectiveDate.year,
      effectiveDate.month,
      effectiveDate.day,
      6, 0, 0, // 6:00 AM Start
    );
  }

  static Timestamp getBusinessStartTimestamp() {
    return Timestamp.fromDate(getBusinessStartDateTime());
  }

  /// Calculates the end of the "Business Day" (Tomorrow 6:00 AM)
  static DateTime getBusinessEndDateTime() {
    return getBusinessStartDateTime().add(const Duration(hours: 24));
  }

  static Timestamp getBusinessEndTimestamp() {
    return Timestamp.fromDate(getBusinessEndDateTime());
  }

  /// Converts any Date (Server/Device) to Qatar Time for Display
  static DateTime getRestaurantTime(DateTime date) {
    if (!_isInitialized) initialize();
    final qatar = tz.getLocation(_qatarLocation);
    return tz.TZDateTime.from(date, qatar);
  }
}