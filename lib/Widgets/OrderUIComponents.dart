// lib/Widgets/OrderUIComponents.dart
// Shared UI components and utilities for Order-related screens
// Consolidates duplicated code from DashboardScreen and OrdersScreen

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../main.dart';

/// Centralized status color and display logic
class StatusUtils {
  /// Get the color for a given order status
  static Color getColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'preparing':
        return Colors.teal;
      case 'rider_assigned':
        return Colors.purple;
      case 'pickedup':
        return Colors.deepPurple;
      case 'delivered':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      case 'refunded':
        return Colors.pink;
      case 'needs_rider_assignment':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  /// Get status color considering order type
  /// For non-delivery orders with needs_rider_assignment, show green (ready) instead of orange
  static Color getColorForOrderType(String status, String orderType) {
    if (status.toLowerCase() == 'needs_rider_assignment') {
      if (!AppConstants.isDeliveryOrder(orderType)) {
        return Colors.green; // Ready color for non-delivery orders
      }
    }
    return getColor(status);
  }

  /// Get display text for a status
  static String getDisplayText(String status, {String? orderType}) {
    final statusLower = status.toLowerCase();

    // For non-delivery orders, show 'READY' instead of 'NEEDS ASSIGN'
    if (statusLower == 'needs_rider_assignment') {
      if (orderType != null && !AppConstants.isDeliveryOrder(orderType)) {
        return 'READY';
      }
      return 'NEEDS ASSIGN';
    }

    switch (statusLower) {
      case 'rider_assigned':
        return 'RIDER ASSIGNED';
      case 'pickedup':
        return 'PICKED UP';
      default:
        return status.toUpperCase();
    }
  }

  /// Get appropriate font size for status text based on length
  static double getFontSize(String status, {String? orderType}) {
    final displayText = getDisplayText(status, orderType: orderType);
    if (displayText.length > 12) return 9;
    if (displayText.length > 8) return 10;
    return 11;
  }
}

/// Reusable status badge widget
class StatusBadge extends StatelessWidget {
  final String status;
  final String? orderType;
  final double? maxWidth;

  const StatusBadge({
    super.key,
    required this.status,
    this.orderType,
    this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    final color = StatusUtils.getColorForOrderType(status, orderType ?? 'delivery');
    final displayText = StatusUtils.getDisplayText(status, orderType: orderType);
    final fontSize = StatusUtils.getFontSize(status, orderType: orderType);

    return Container(
      constraints: maxWidth != null ? BoxConstraints(maxWidth: maxWidth!) : null,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              displayText,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: fontSize,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Reusable detail row widget for order details
class OrderDetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final double fontSize;

  const OrderDetailRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.fontSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: fontSize + 2, color: Colors.deepPurple.shade400),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: TextStyle(
                fontSize: fontSize,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Reusable order item row widget
class OrderItemRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final double fontSize;

  const OrderItemRow({
    super.key,
    required this.item,
    this.fontSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    final String name = item['name']?.toString() ?? 'Unnamed Item';
    final int qty = (item['quantity'] as num? ?? 1).toInt();
    final double price = (item['price'] as num? ?? 0.0).toDouble();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            flex: 5,
            child: Text.rich(
              TextSpan(
                text: name,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w500,
                ),
                children: [
                  TextSpan(
                    text: ' (x$qty)',
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: FontWeight.normal,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'QAR ${(price * qty).toStringAsFixed(2)}',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: fontSize,
                color: Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Reusable summary row widget for price summaries
class OrderSummaryRow extends StatelessWidget {
  final String label;
  final double amount;
  final bool isTotal;

  const OrderSummaryRow({
    super.key,
    required this.label,
    required this.amount,
    this.isTotal = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 16 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color: isTotal ? Colors.black : Colors.grey[800],
            ),
          ),
          Text(
            'QAR ${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: isTotal ? 16 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color: isTotal ? Colors.black : Colors.grey[800],
            ),
          ),
        ],
      ),
    );
  }
}

/// Reusable section header widget
class OrderSectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const OrderSectionHeader({
    super.key,
    required this.title,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.deepPurple, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.deepPurple,
          ),
        ),
      ],
    );
  }
}

/// Utility class for network-aware operations
class NetworkUtils {
  /// Check if device has network connectivity
  static Future<bool> hasConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    return !result.contains(ConnectivityResult.none);
  }

  /// Show a network error snackbar
  static void showNetworkError(BuildContext context) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('⚠️ No internet connection. Please try again.'),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 3),
      ),
    );
  }

  /// Get user-friendly error message from exception
  static String getUserFriendlyError(dynamic error) {
    final errorStr = error.toString().toLowerCase();
    
    if (errorStr.contains('permission') || errorStr.contains('denied')) {
      return 'You don\'t have permission to perform this action.';
    }
    if (errorStr.contains('network') || errorStr.contains('timeout') || 
        errorStr.contains('connection')) {
      return 'Network error. Please check your connection and try again.';
    }
    if (errorStr.contains('not found') || errorStr.contains('does not exist')) {
      return 'This order no longer exists or was already updated.';
    }
    if (errorStr.contains('already')) {
      return 'This order was already updated by another user.';
    }
    
    return 'Failed to update order. Please try again.';
  }
}

/// Mixin for debouncing button taps to prevent double-tap issues
mixin DebounceActionMixin<T extends StatefulWidget> on State<T> {
  final Set<String> _processingActions = {};

  /// Check if an action is currently processing
  bool isProcessing(String actionId) => _processingActions.contains(actionId);

  /// Execute an action with debounce protection
  Future<void> executeWithDebounce(
    String actionId,
    Future<void> Function() action,
  ) async {
    if (_processingActions.contains(actionId)) return;
    
    _processingActions.add(actionId);
    if (mounted) setState(() {});
    
    try {
      await action();
    } finally {
      _processingActions.remove(actionId);
      if (mounted) setState(() {});
    }
  }
}

/// Safe data extraction helpers for order documents
class OrderDataHelper {
  final Map<String, dynamic> data;
  
  OrderDataHelper(this.data);
  
  /// Factory constructor for DocumentSnapshot
  factory OrderDataHelper.fromSnapshot(DocumentSnapshot snapshot) {
    final data = snapshot.data();
    if (data is Map<String, dynamic>) {
      return OrderDataHelper(data);
    }
    return OrderDataHelper({});
  }

  /// Get string value with fallback
  String getString(String key, [String fallback = '']) {
    final value = data[key];
    if (value == null) return fallback;
    return value.toString();
  }

  /// Get double value with fallback
  double getDouble(String key, [double fallback = 0.0]) {
    final value = data[key];
    if (value == null) return fallback;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? fallback;
  }

  /// Get int value with fallback
  int getInt(String key, [int fallback = 0]) {
    final value = data[key];
    if (value == null) return fallback;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }

  /// Get items list safely
  List<Map<String, dynamic>> getItems() {
    final rawItems = data['items'];
    if (rawItems is! List) return [];
    return rawItems
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  /// Get timestamp as DateTime
  DateTime? getTimestamp(String key) {
    final value = data[key];
    if (value is Timestamp) return value.toDate();
    return null;
  }

  /// Get nested map value
  Map<String, dynamic>? getMap(String key) {
    final value = data[key];
    if (value is Map<String, dynamic>) return value;
    return null;
  }

  /// Get branch ID with multiple fallback strategies
  String? getBranchId() {
    // Try direct branchId
    final branchId = data['branchId']?.toString();
    if (branchId != null && branchId.isNotEmpty) return branchId;

    // Try branchIds array
    final branchIds = data['branchIds'];
    if (branchIds is List && branchIds.isNotEmpty) {
      return branchIds.first.toString();
    }

    // Try items array fallback
    final items = data['items'];
    if (items is List && items.isNotEmpty) {
      final firstItem = items.first;
      if (firstItem is Map && firstItem['branchId'] != null) {
        return firstItem['branchId'].toString();
      }
    }

    return null;
  }

  /// Check if order has a pending refund request
  bool hasPendingRefund() {
    final refund = getMap('refundRequest');
    if (refund == null) return false;
    return refund['status']?.toString() == 'pending';
  }

  /// Check if order is an exchange
  bool isExchange() {
    return data['isExchange'] == true;
  }
}
