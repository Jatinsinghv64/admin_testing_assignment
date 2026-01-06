// lib/constants.dart

class AppConstants {
  // Firestore Collections
  static const String collectionOrders = 'Orders';
  static const String collectionStaff = 'staff';
  static const String collectionBranch = 'Branch';
  static const String collectionDrivers = 'Drivers';
  static const String collectionRiderAssignments = 'rider_assignments';
  static const String collectionMenuItems = 'menu_items';
  static const String collectionMenuCategories = 'menu_categories';
  static const String collectionCoupons = 'coupons';

  // Order Statuses (Standardized)
  static const String statusPending = 'pending';
  static const String statusPreparing = 'preparing';
  static const String statusRiderAssigned = 'rider_assigned';
  static const String statusPickedUp = 'pickedUp'; // Standardized camelCase
  static const String statusPickedUpLegacy = 'pickedup'; // Legacy lowercase
  static const String statusDelivered = 'delivered';
  static const String statusCancelled = 'cancelled';
  static const String statusNeedsAssignment = 'needs_rider_assignment';

  // Terminal statuses (no further transitions allowed)
  static const List<String> terminalStatuses = [
    statusDelivered,
    statusCancelled,
  ];

  // Firestore Operation Timeouts
  static const Duration firestoreTimeout = Duration(seconds: 10);
  static const Duration firestoreWriteTimeout = Duration(seconds: 15);

  // Login Rate Limiting
  static const int maxLoginAttempts = 5;
  static const Duration loginLockoutDuration = Duration(minutes: 15);

  // Cache Expiration
  static const Duration branchCacheExpiration = Duration(minutes: 30);

  /// Normalize order status for consistent comparison
  /// Handles legacy 'pickedup' vs standardized 'pickedUp'
  static String normalizeStatus(String? status) {
    if (status == null) return '';
    final lower = status.toLowerCase();
    if (lower == 'pickedup') return statusPickedUp;
    return status;
  }

  /// Check if two statuses are equivalent (handling legacy formats)
  static bool statusEquals(String? status1, String? status2) {
    return normalizeStatus(status1) == normalizeStatus(status2);
  }

  /// Check if status is terminal (order completed or cancelled)
  static bool isTerminalStatus(String? status) {
    final normalized = normalizeStatus(status);
    return terminalStatuses.contains(normalized) ||
        normalized.toLowerCase() == 'pickedup' ||
        normalized == statusPickedUp;
  }
}

/// Extension for String capitalization (used in UI)
extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }

  String toTitleCase() {
    return split(' ').map((word) => word.capitalize()).join(' ');
  }
}