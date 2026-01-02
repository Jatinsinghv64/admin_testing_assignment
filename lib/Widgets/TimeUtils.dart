import 'package:cloud_firestore/cloud_firestore.dart';

class TimeUtils {
  /// Calculates the start of the "Business Day" (e.g., 6:00 AM).
  /// If the current time is before 6 AM (e.g., 2 AM), it belongs to the previous day's shift.
  static DateTime getBusinessStartDateTime() {
    var now = DateTime.now();
    if (now.hour < 6) {
      now = now.subtract(const Duration(days: 1));
    }
    return DateTime(now.year, now.month, now.day, 6, 0, 0);
  }

  /// Returns the Business Start Time as a Firestore Timestamp
  static Timestamp getBusinessStartTimestamp() {
    return Timestamp.fromDate(getBusinessStartDateTime());
  }

  /// Calculates the end of the "Business Day" (Tomorrow 6:00 AM)
  static DateTime getBusinessEndDateTime() {
    return getBusinessStartDateTime().add(const Duration(hours: 24));
  }

  /// ✅ ADDED: Returns the Business End Time as a Firestore Timestamp
  static Timestamp getBusinessEndTimestamp() {
    return Timestamp.fromDate(getBusinessEndDateTime());
  }

  /// Converts Device/Server Time -> Restaurant Time (e.g., UTC+3 for Qatar)
  static DateTime getRestaurantTime(DateTime date) {
    // 1. Convert to UTC to remove device timezone bias
    DateTime utc = date.toUtc();
    // 2. Add the Restaurant's Offset (e.g., +3 hours for Qatar/Saudi)
    // TODO: Ideally, fetch this offset from a configuration/remote config
    return utc.add(const Duration(hours: 3));
  }
}