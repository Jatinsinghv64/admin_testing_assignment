import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdd/constants.dart';
import 'package:mdd/services/pos/pos_order_lifecycle.dart';

void main() {
  group('PosOrderLifecycle.stageFromData', () {
    test('treats paid and completed orders as completed stage', () {
      expect(
        PosOrderLifecycle.stageFromData({'status': AppConstants.statusPaid}),
        PosOrderLifecycle.stageCompleted,
      );
      expect(
        PosOrderLifecycle.stageFromData({'orderStatus': 'completed'}),
        PosOrderLifecycle.stageCompleted,
      );
    });

    test('preserves active kitchen stages', () {
      expect(
        PosOrderLifecycle.stageFromData(
            {'status': AppConstants.statusPrepared}),
        AppConstants.statusPrepared,
      );
      expect(
        PosOrderLifecycle.stageFromData(
            {'orderStatus': AppConstants.statusServed}),
        AppConstants.statusServed,
      );
    });
  });

  group('PosOrderLifecycle.paymentStatusFromData', () {
    test('treats explicit and legacy paid states as paid', () {
      expect(
        PosOrderLifecycle.paymentStatusFromData({'paymentStatus': 'paid'}),
        PosOrderLifecycle.paymentPaid,
      );
      expect(
        PosOrderLifecycle.paymentStatusFromData(
            {'status': AppConstants.statusCollected}),
        PosOrderLifecycle.paymentPaid,
      );
      expect(
        PosOrderLifecycle.paymentStatusFromData({'isPaid': true}),
        PosOrderLifecycle.paymentPaid,
      );
    });

    test('keeps unpaid orders outstanding', () {
      final order = {
        'status': AppConstants.statusPreparing,
        'totalAmount': 42.5,
      };
      expect(
        PosOrderLifecycle.paymentStatusFromData(order),
        PosOrderLifecycle.paymentUnpaid,
      );
      expect(PosOrderLifecycle.outstandingAmount(order), 42.5);
    });
  });

  group('PosOrderLifecycle.shouldFinalizeOnPayment', () {
    test('finishes served dine-in orders on payment', () {
      final order = {
        'Order_type': AppConstants.orderTypeDineIn,
        'status': AppConstants.statusServed,
      };
      expect(PosOrderLifecycle.shouldFinalizeOnPayment(order), isTrue);
    });

    test('does not finish unserved dine-in orders on payment', () {
      final order = {
        'Order_type': AppConstants.orderTypeDineIn,
        'status': AppConstants.statusPrepared,
      };
      expect(PosOrderLifecycle.shouldFinalizeOnPayment(order), isFalse);
    });

    test('finishes ready takeaway orders on payment', () {
      final order = {
        'Order_type': AppConstants.orderTypeTakeaway,
        'status': AppConstants.statusPrepared,
      };
      expect(PosOrderLifecycle.shouldFinalizeOnPayment(order), isTrue);
    });
  });

  group('PosOrderLifecycle.kdsPrimaryAction', () {
    test('uses accept wording for pending POS orders', () {
      final order = {
        'source': 'pos',
        'status': AppConstants.statusPending,
      };
      final action = PosOrderLifecycle.kdsPrimaryAction(order);
      expect(action?['nextStatus'], AppConstants.statusPreparing);
      expect(action?['label'], 'ACCEPT ORDER');
    });

    test('uses serve for dine-in prepared orders', () {
      final order = {
        'Order_type': AppConstants.orderTypeDineIn,
        'status': AppConstants.statusPrepared,
      };
      final action = PosOrderLifecycle.kdsPrimaryAction(order);
      expect(action?['nextStatus'], AppConstants.statusServed);
      expect(action?['label'], 'MARK SERVED');
    });

    test('blocks unpaid takeaway handoff until payment is captured', () {
      final order = {
        'Order_type': AppConstants.orderTypeTakeaway,
        'status': AppConstants.statusPrepared,
        'paymentStatus': PosOrderLifecycle.paymentUnpaid,
      };
      final action = PosOrderLifecycle.kdsPrimaryAction(order);
      expect(action?['state'], 'disabled');
      expect(action?['label'], 'AWAITING PAYMENT');
    });

    test('allows prepaid takeaway handoff from KDS', () {
      final order = {
        'Order_type': AppConstants.orderTypeTakeaway,
        'status': AppConstants.statusPrepared,
        'paymentStatus': PosOrderLifecycle.paymentPaid,
      };
      final action = PosOrderLifecycle.kdsPrimaryAction(order);
      expect(action?['nextStatus'], AppConstants.statusPaid);
      expect(action?['label'], 'HAND OFF ORDER');
    });
  });

  group('PosOrderLifecycle kitchen decision helpers', () {
    test('requires chef decision only for pending POS tickets', () {
      expect(
        PosOrderLifecycle.requiresChefDecision({
          'source': 'pos',
          'status': AppConstants.statusPending,
        }),
        isTrue,
      );
      expect(
        PosOrderLifecycle.requiresChefDecision({
          'source': 'pos',
          'status': AppConstants.statusPreparing,
        }),
        isFalse,
      );
      expect(
        PosOrderLifecycle.requiresChefDecision({
          'source': 'app',
          'status': AppConstants.statusPending,
        }),
        isFalse,
      );
    });

    test('tracks response deadline and overdue auto-accept correctly', () {
      final now = DateTime(2026, 3, 17, 10, 0, 0);

      final activeOrder = {
        'source': 'pos',
        'status': AppConstants.statusPending,
        'autoAcceptDeadline':
            Timestamp.fromDate(now.add(const Duration(seconds: 30))),
      };
      expect(
        PosOrderLifecycle.kitchenResponseSecondsRemaining(activeOrder,
            now: now),
        30,
      );
      expect(
        PosOrderLifecycle.shouldAutoAcceptPending(activeOrder, now: now),
        isFalse,
      );

      final overdueOrder = {
        'source': 'pos',
        'status': AppConstants.statusPending,
        'autoAcceptDeadline':
            Timestamp.fromDate(now.subtract(const Duration(seconds: 1))),
      };
      expect(
        PosOrderLifecycle.kitchenResponseSecondsRemaining(overdueOrder,
            now: now),
        0,
      );
      expect(
        PosOrderLifecycle.shouldAutoAcceptPending(overdueOrder, now: now),
        isTrue,
      );
    });

    test('identifies kitchen rejections from lifecycle metadata', () {
      expect(
        PosOrderLifecycle.isKitchenRejected({
          'kitchenDecisionStatus': PosOrderLifecycle.kitchenDecisionRejected,
        }),
        isTrue,
      );
      expect(
        PosOrderLifecycle.isKitchenRejected({
          'cancelledFromKitchen': true,
        }),
        isTrue,
      );
      expect(
        PosOrderLifecycle.isKitchenRejected({
          'status': AppConstants.statusCancelled,
        }),
        isFalse,
      );
    });
  });
}
