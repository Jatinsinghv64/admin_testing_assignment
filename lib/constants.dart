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
  static const String statusPrepared = 'prepared';         // NEW: Food ready (non-delivery)
  static const String statusServed = 'served';             // NEW: Dine-in served to table
  static const String statusPaid = 'paid';                 // NEW: Terminal for takeaway/dine-in
  static const String statusCollected = 'collected';       // NEW: Terminal for pickup (prepaid)
  static const String statusRiderAssigned = 'rider_assigned';
  static const String statusPickedUp = 'pickedUp';         // Standardized camelCase
  static const String statusPickedUpLegacy = 'pickedup';   // Legacy lowercase
  static const String statusDelivered = 'delivered';
  static const String statusCancelled = 'cancelled';
  static const String statusNeedsAssignment = 'needs_rider_assignment';
  static const String statusRefunded = 'refunded';

  // Terminal statuses (no further transitions allowed)
  static const List<String> terminalStatuses = [
    statusDelivered,
    statusCancelled,
    statusPaid,       // Terminal for takeaway/dine-in
    statusCollected,  // Terminal for pickup
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
        normalized == statusPickedUp ||
        normalized == statusPaid ||
        normalized == statusCollected;
  }

  // Order Types (Standardized)
  static const String orderTypeDelivery = 'delivery';
  static const String orderTypePickup = 'pickup';
  static const String orderTypeTakeaway = 'takeaway';
  static const String orderTypeDineIn = 'dine_in';

  /// Normalize order type for consistent comparison
  /// Handles variations like 'dine-in', 'dine_in', 'DineIn', 'Dine In', etc.
  static String normalizeOrderType(String? orderType) {
    if (orderType == null || orderType.isEmpty) return orderTypeDelivery;
    
    // Convert to lowercase and normalize separators
    final cleaned = orderType.toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
    
    // Map common variations
    if (cleaned == 'dinein' || cleaned == 'dine_in' || cleaned == 'dine') {
      return orderTypeDineIn;
    }
    if (cleaned == 'pickup' || cleaned == 'pick_up') {
      return orderTypePickup;
    }
    if (cleaned == 'takeaway' || cleaned == 'take_away') {
      return orderTypeTakeaway;
    }
    
    return cleaned;
  }

  /// Check if order type is delivery
  static bool isDeliveryOrder(String? orderType) {
    return normalizeOrderType(orderType) == orderTypeDelivery;
  }

  /// Check if order type is dine-in
  static bool isDineInOrder(String? orderType) {
    return normalizeOrderType(orderType) == orderTypeDineIn;
  }

  /// Check if order type is pickup or takeaway (non-delivery, non-dine-in)
  static bool isPickupOrder(String? orderType) {
    final normalized = normalizeOrderType(orderType);
    return normalized == orderTypePickup || normalized == orderTypeTakeaway;
  }

  /// Check if order type requires a rider (only delivery orders)
  static bool requiresRider(String? orderType) {
    return isDeliveryOrder(orderType);
  }

  /// Check if order type is takeaway (pay at counter)
  static bool isTakeawayOrder(String? orderType) {
    return normalizeOrderType(orderType) == orderTypeTakeaway;
  }

  /// Get the next status after 'preparing' based on order type
  static String getNextStatusAfterPreparing(String? orderType) {
    if (isDeliveryOrder(orderType)) {
      return statusNeedsAssignment; // Delivery goes to rider assignment
    }
    return statusPrepared; // All other types go to prepared
  }

  /// Get the next status after 'prepared' based on order type
  static String getNextStatusAfterPrepared(String? orderType) {
    final normalized = normalizeOrderType(orderType);
    if (normalized == orderTypeDineIn) return statusServed;
    if (normalized == orderTypePickup) return statusCollected;
    if (normalized == orderTypeTakeaway) return statusPaid;
    return statusDelivered; // Fallback
  }

  /// Get the completion button text based on order type and current status
  static String getCompletionButtonText(String? orderType, {String? currentStatus}) {
    final normalized = normalizeOrderType(orderType);
    
    // For preparing -> prepared
    if (currentStatus == statusPreparing && !isDeliveryOrder(orderType)) {
      return 'Mark Prepared';
    }
    
    // For prepared -> next status
    if (currentStatus == statusPrepared) {
      if (normalized == orderTypeDineIn) return 'Mark Served';
      if (normalized == orderTypePickup) return 'Collected';
      if (normalized == orderTypeTakeaway) return 'Mark Paid';
    }
    
    // For served -> paid (dine-in only)
    if (currentStatus == statusServed) {
      return 'Mark Paid';
    }
    
    // Legacy fallbacks
    if (isDineInOrder(orderType)) return 'Served to Table';
    if (isPickupOrder(orderType)) return 'Handed to Customer';
    return 'Mark as Delivered';
  }

  /// Get status display text (human readable)
  static String getStatusDisplayText(String? status, {String? orderType}) {
    if (status == null) return '';
    switch (status.toLowerCase()) {
      case 'pending': return 'PENDING';
      case 'preparing': return 'PREPARING';
      case 'prepared': return 'PREPARED';
      case 'served': return 'SERVED';
      case 'paid': return 'PAID';
      case 'collected': return 'COLLECTED';
      case 'needs_rider_assignment': return 'NEEDS RIDER';
      case 'rider_assigned': return 'RIDER ASSIGNED';
      case 'pickedup': return 'PICKED UP';
      case 'pickedUp': return 'PICKED UP';
      case 'delivered': return 'DELIVERED';
      case 'cancelled': return 'CANCELLED';
      case 'refunded': return 'REFUNDED';
      default: return status.toUpperCase();
    }
  }

  // --- PAYMENT METHOD HELPERS ---
  
  /// Check if payment method is cash-based (requires collection)
  static bool isCashPayment(String? paymentMethod) {
    if (paymentMethod == null || paymentMethod.isEmpty) return true; // Default to cash
    final p = paymentMethod.toLowerCase();
    return p == 'cash' || p == 'cod' || p == 'cash_on_delivery';
  }
  
  /// Check if payment method is prepaid (already collected)
  static bool isPrepaidPayment(String? paymentMethod) {
    if (paymentMethod == null || paymentMethod.isEmpty) return false;
    final p = paymentMethod.toLowerCase();
    return p == 'online' || p == 'card' || p == 'prepaid' || 
           p == 'apple_pay' || p == 'google_pay' || p == 'wallet';
  }
  
  /// Get display text for payment method
  static String getPaymentDisplayText(String? paymentMethod) {
    if (paymentMethod == null || paymentMethod.isEmpty) return 'CASH';
    switch (paymentMethod.toLowerCase()) {
      case 'cash':
      case 'cod':
      case 'cash_on_delivery':
        return 'CASH';
      case 'online':
      case 'card':
      case 'prepaid':
        return 'PREPAID';
      case 'apple_pay':
        return 'APPLE PAY';
      case 'google_pay':
        return 'GOOGLE PAY';
      case 'wallet':
        return 'WALLET';
      default:
        return paymentMethod.toUpperCase();
    }
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

/// Helper class for order number display
class OrderNumberHelper {
  /// Loading indicator text shown while order number is being generated
  static const String loadingText = 'Generating...';
  
  /// Get display order number from order data
  /// Returns the dailyOrderNumber if available, otherwise shows loading
  /// 
  /// The Cloud Function generates formatted order numbers like "ZKD-260107-001"
  /// If the number hasn't been assigned yet, we show "Generating..." instead
  /// of a misleading fallback like the document ID
  static String getDisplayNumber(Map<String, dynamic>? data, {String? orderId}) {
    if (data == null) return loadingText;
    
    final dailyOrderNumber = data['dailyOrderNumber'];
    
    // If we have a proper order number, display it
    if (dailyOrderNumber != null && dailyOrderNumber.toString().isNotEmpty) {
      return dailyOrderNumber.toString();
    }
    
    // Check if the order was just created (within last 5 seconds)
    // If so, the Cloud Function is likely still processing
    final timestamp = data['timestamp'];
    if (timestamp != null) {
      try {
        final orderTime = (timestamp as dynamic).toDate() as DateTime;
        final now = DateTime.now();
        final difference = now.difference(orderTime);
        
        // If order is less than 5 seconds old, show loading
        if (difference.inSeconds < 5) {
          return loadingText;
        }
      } catch (_) {
        // If we can't parse the timestamp, continue to fallback
      }
    }
    
    // If order is older and still no number, show abbreviated order ID
    // (This is the fallback for legacy orders or Cloud Function failures)
    if (orderId != null && orderId.isNotEmpty) {
      return '#${orderId.substring(0, 6).toUpperCase()}';
    }
    
    return loadingText;
  }
  
  /// Check if the order number is still being generated
  static bool isLoading(Map<String, dynamic>? data) {
    if (data == null) return true;
    final dailyOrderNumber = data['dailyOrderNumber'];
    return dailyOrderNumber == null || dailyOrderNumber.toString().isEmpty;
  }
}