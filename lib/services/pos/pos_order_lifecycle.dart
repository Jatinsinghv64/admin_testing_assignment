import 'package:cloud_firestore/cloud_firestore.dart';
import '../../constants.dart';

class PosOrderLifecycle {
  static const String stageCompleted = 'completed';
  static const String stageCancelled = 'cancelled';
  static const String paymentPaid = 'paid';
  static const String paymentUnpaid = 'unpaid';
  static const String paymentRefunded = 'refunded';
  static const String kitchenDecisionPending = 'pending';
  static const String kitchenDecisionAccepted = 'accepted';
  static const String kitchenDecisionAutoAccepted = 'auto_accepted';
  static const String kitchenDecisionRejected = 'rejected';

  static String orderTypeFromData(Map<String, dynamic> data) {
    return AppConstants.normalizeOrderType(
      data['Order_type']?.toString() ?? data['orderType']?.toString(),
    );
  }

  static String normalizeOrderStage(String? raw) {
    final normalized = AppConstants.normalizeStatus(raw).toLowerCase();
    switch (normalized) {
      case AppConstants.statusPending:
      case AppConstants.statusPreparing:
      case AppConstants.statusPrepared:
      case AppConstants.statusServed:
        return normalized;
      case AppConstants.statusPaid:
      case AppConstants.statusCollected:
      case AppConstants.statusDelivered:
      case 'completed':
        return stageCompleted;
      case AppConstants.statusCancelled:
      case AppConstants.statusRefunded:
        return stageCancelled;
      default:
        return AppConstants.statusPending;
    }
  }

  static String stageFromData(Map<String, dynamic> data) {
    final rawOrderStage = data['orderStatus']?.toString();
    if (rawOrderStage != null && rawOrderStage.isNotEmpty) {
      return normalizeOrderStage(rawOrderStage);
    }
    return normalizeOrderStage(data['status']?.toString());
  }

  static String paymentStatusFromData(Map<String, dynamic> data) {
    final explicit = data['paymentStatus']?.toString().toLowerCase();
    if (explicit == paymentPaid ||
        explicit == paymentUnpaid ||
        explicit == paymentRefunded) {
      return explicit!;
    }

    if (data['isPaid'] == true) {
      return paymentPaid;
    }

    final normalizedStatus = AppConstants.normalizeStatus(
      data['status']?.toString(),
    );
    if (normalizedStatus == AppConstants.statusPaid ||
        normalizedStatus == AppConstants.statusCollected) {
      return paymentPaid;
    }
    if (normalizedStatus == AppConstants.statusRefunded) {
      return paymentRefunded;
    }
    return paymentUnpaid;
  }

  static bool isPaymentCaptured(Map<String, dynamic> data) {
    return paymentStatusFromData(data) == paymentPaid;
  }

  static bool isCompleted(Map<String, dynamic> data) {
    return stageFromData(data) == stageCompleted;
  }

  static bool isCancelled(Map<String, dynamic> data) {
    return stageFromData(data) == stageCancelled;
  }

  static double outstandingAmount(Map<String, dynamic> data) {
    if (isPaymentCaptured(data)) return 0;
    return (data['totalAmount'] as num?)?.toDouble() ?? 0.0;
  }

  static bool shouldFinalizeOnPayment(Map<String, dynamic> data) {
    final stage = stageFromData(data);
    final orderType = orderTypeFromData(data);

    if (stage == stageCompleted || stage == stageCancelled) {
      return false;
    }

    switch (orderType) {
      case AppConstants.orderTypeDineIn:
        return stage == AppConstants.statusServed;
      case AppConstants.orderTypeTakeaway:
      case AppConstants.orderTypePickup:
        return stage == AppConstants.statusPrepared;
      default:
        return false;
    }
  }

  static bool shouldAutoCompleteOnKitchenUpdate(
    Map<String, dynamic> data,
    String newStatus,
  ) {
    final stage = normalizeOrderStage(newStatus);
    return isPaymentCaptured(data) &&
        orderTypeFromData(data) == AppConstants.orderTypeDineIn &&
        stage == AppConstants.statusServed;
  }

  static String terminalStatusForOrderType(String orderType) {
    switch (AppConstants.normalizeOrderType(orderType)) {
      case AppConstants.orderTypePickup:
        return AppConstants.statusCollected;
      case AppConstants.orderTypeDelivery:
        return AppConstants.statusDelivered;
      case AppConstants.orderTypeDineIn:
      case AppConstants.orderTypeTakeaway:
      default:
        return AppConstants.statusPaid;
    }
  }

  static bool isPosOrder(Map<String, dynamic> data) {
    final source = data['source']?.toString().toLowerCase();
    return source == 'pos' || data['posOrder'] == true;
  }

  static bool requiresChefDecision(Map<String, dynamic> data) {
    return isPosOrder(data) &&
        stageFromData(data) == AppConstants.statusPending;
  }

  static DateTime? kitchenResponseDeadlineFromData(Map<String, dynamic> data) {
    final raw = data['autoAcceptDeadline'] ?? data['kitchenResponseDeadline'];
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);

    try {
      final converted = (raw as dynamic).toDate();
      if (converted is DateTime) return converted;
    } catch (_) {
      // Ignore incompatible legacy values.
    }
    return null;
  }

  static Duration? kitchenResponseTimeRemaining(
    Map<String, dynamic> data, {
    DateTime? now,
  }) {
    final deadline = kitchenResponseDeadlineFromData(data);
    if (deadline == null) return null;
    final remaining = deadline.difference(now ?? DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  static int? kitchenResponseSecondsRemaining(
    Map<String, dynamic> data, {
    DateTime? now,
  }) {
    final remaining = kitchenResponseTimeRemaining(data, now: now);
    if (remaining == null) return null;
    final wholeSeconds = remaining.inSeconds;
    if (remaining.inMilliseconds > 0 && wholeSeconds == 0) {
      return 1;
    }
    return wholeSeconds;
  }

  static bool shouldAutoAcceptPending(
    Map<String, dynamic> data, {
    DateTime? now,
  }) {
    final remaining = kitchenResponseTimeRemaining(data, now: now);
    return requiresChefDecision(data) &&
        remaining != null &&
        remaining == Duration.zero;
  }

  static bool isKitchenRejected(Map<String, dynamic> data) {
    final decision = data['kitchenDecisionStatus']?.toString().toLowerCase();
    return decision == kitchenDecisionRejected ||
        data['cancelledFromKitchen'] == true;
  }

  static Map<String, String>? kdsPrimaryAction(
    Map<String, dynamic> data, {
    bool isRecall = false,
  }) {
    final stage = stageFromData(data);
    final orderType = orderTypeFromData(data);
    final isPaid = isPaymentCaptured(data);
    final paymentMethod = data['paymentMethod']?.toString();

    if (isRecall) {
      return {
        'label': 'RECALL TO KITCHEN',
        'nextStatus': AppConstants.statusPreparing,
        'state': 'warning',
      };
    }

    if (stage == stageCancelled) {
      return {
        'label': 'DISMISS CANCELLED',
        'nextStatus': 'dismiss_cancelled',
        'state': 'danger',
      };
    }

    if (stage == AppConstants.statusPending) {
      return {
        'label': 'ACCEPT ORDER',
        'nextStatus': AppConstants.statusPreparing,
        'state': 'success',
      };
    }

    if (stage == AppConstants.statusPreparing) {
      return {
        'label': 'MARK READY',
        'nextStatus': AppConstants.statusPrepared,
        'state': 'primary',
      };
    }

    if (stage != AppConstants.statusPrepared) {
      return null;
    }

    switch (orderType) {
      case AppConstants.orderTypeDineIn:
        return {
          'label': 'MARK SERVED',
          'nextStatus': AppConstants.statusServed,
          'state': 'success',
        };
      case AppConstants.orderTypeTakeaway:
        if (isPaid) {
          return {
            'label': 'HAND OFF ORDER',
            'nextStatus': AppConstants.statusPaid,
            'state': 'success',
          };
        }
        return {
          'label': 'AWAITING PAYMENT',
          'nextStatus': '',
          'state': 'disabled',
        };
      case AppConstants.orderTypePickup:
        final isPrepaid =
            isPaid || AppConstants.isPrepaidPayment(paymentMethod);
        if (isPrepaid) {
          return {
            'label': 'MARK COLLECTED',
            'nextStatus': AppConstants.statusCollected,
            'state': 'success',
          };
        }
        return {
          'label': 'AWAITING PAYMENT',
          'nextStatus': '',
          'state': 'disabled',
        };
      default:
        return null;
    }
  }
}
