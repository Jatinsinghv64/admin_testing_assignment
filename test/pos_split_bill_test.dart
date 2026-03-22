import 'package:flutter_test/flutter_test.dart';
import 'package:mdd/services/pos/pos_models.dart';
import 'package:mdd/services/pos/pos_service.dart';

void main() {
  group('PosPayment', () {
    test('derives applied amount from tendered cash and change', () {
      final payment = PosPayment(
        method: 'cash',
        label: 'Guest 1',
        amount: 50,
        change: 7.5,
      );

      expect(payment.appliedAmount, 42.5);
      expect(payment.label, 'Guest 1');
      expect(payment.isSplit, isFalse);
    });
  });

  group('PosService.allocatePaymentAcrossAmountsForTesting', () {
    test('preserves split guest payments for a single order', () {
      final payment = PosPayment(
        method: 'split',
        amount: 100,
        change: 0,
        appliedAmount: 100,
        splits: [
          PosPayment(
            method: 'card',
            label: 'Guest 1',
            amount: 45,
            appliedAmount: 45,
          ),
          PosPayment(
            method: 'cash',
            label: 'Guest 2',
            amount: 55,
            appliedAmount: 55,
          ),
        ],
      );

      final allocations = PosService.allocatePaymentAcrossAmountsForTesting(
        payment: payment,
        dueAmounts: const [100],
      );

      expect(allocations, hasLength(1));
      expect(allocations.first.isSplit, isTrue);
      expect(allocations.first.splits, hasLength(2));
      expect(allocations.first.splits.first.label, 'Guest 1');
      expect(allocations.first.splits.last.label, 'Guest 2');
    });

    test('allocates split bill cleanly across multiple orders', () {
      final payment = PosPayment(
        method: 'split',
        amount: 110,
        change: 10,
        appliedAmount: 100,
        splits: [
          PosPayment(
            method: 'card',
            label: 'Guest 1',
            amount: 30,
            appliedAmount: 30,
          ),
          PosPayment(
            method: 'cash',
            label: 'Guest 2',
            amount: 80,
            change: 10,
            appliedAmount: 70,
          ),
        ],
      );

      final allocations = PosService.allocatePaymentAcrossAmountsForTesting(
        payment: payment,
        dueAmounts: const [40, 60],
      );

      expect(allocations, hasLength(2));

      expect(allocations[0].method, 'split');
      expect(allocations[0].amount, 40);
      expect(allocations[0].change, 0);
      expect(allocations[0].appliedAmount, 40);
      expect(allocations[0].splits, hasLength(2));
      expect(allocations[0].splits[0].label, 'Guest 1');
      expect(allocations[0].splits[0].amount, 30);
      expect(allocations[0].splits[1].label, 'Guest 2');
      expect(allocations[0].splits[1].amount, 10);

      expect(allocations[1].method, 'cash');
      expect(allocations[1].amount, 70);
      expect(allocations[1].change, 10);
      expect(allocations[1].appliedAmount, 60);
      expect(allocations[1].label, 'Guest 2');
    });

    test('rejects mismatched split totals', () {
      final payment = PosPayment(
        method: 'split',
        amount: 60,
        appliedAmount: 60,
        splits: [
          PosPayment(
            method: 'card',
            label: 'Guest 1',
            amount: 60,
            appliedAmount: 60,
          ),
        ],
      );

      expect(
        () => PosService.allocatePaymentAcrossAmountsForTesting(
          payment: payment,
          dueAmounts: const [50],
        ),
        throwsException,
      );
    });
  });
}
