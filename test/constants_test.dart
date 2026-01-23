// test/constants_test.dart
// Unit tests for AppConstants class - order status and order type utilities

import 'package:flutter_test/flutter_test.dart';
import 'package:mdd/constants.dart';

void main() {
  group('AppConstants - Status Normalization', () {
    test('normalizeStatus handles null', () {
      expect(AppConstants.normalizeStatus(null), '');
    });

    test('normalizeStatus handles legacy pickedup', () {
      expect(AppConstants.normalizeStatus('pickedup'), 'pickedUp');
      expect(AppConstants.normalizeStatus('PICKEDUP'), 'pickedUp');
    });

    test('normalizeStatus returns original for non-legacy statuses', () {
      expect(AppConstants.normalizeStatus('pending'), 'pending');
      expect(AppConstants.normalizeStatus('preparing'), 'preparing');
      expect(AppConstants.normalizeStatus('delivered'), 'delivered');
    });
  });

  group('AppConstants - Status Comparison', () {
    test('statusEquals handles legacy format comparison', () {
      expect(AppConstants.statusEquals('pickedup', 'pickedUp'), true);
      expect(AppConstants.statusEquals('pickedUp', 'pickedUp'), true);
    });

    test('statusEquals returns false for different statuses', () {
      expect(AppConstants.statusEquals('pending', 'preparing'), false);
      expect(AppConstants.statusEquals('delivered', 'cancelled'), false);
    });

    test('statusEquals handles null values', () {
      expect(AppConstants.statusEquals(null, 'pending'), false);
      expect(AppConstants.statusEquals(null, null), true);
    });
  });

  group('AppConstants - Terminal Status Check', () {
    test('isTerminalStatus identifies terminal statuses', () {
      expect(AppConstants.isTerminalStatus('delivered'), true);
      expect(AppConstants.isTerminalStatus('cancelled'), true);
      expect(AppConstants.isTerminalStatus('paid'), true);
      expect(AppConstants.isTerminalStatus('collected'), true);
    });

    test('isTerminalStatus identifies non-terminal statuses', () {
      expect(AppConstants.isTerminalStatus('pending'), false);
      expect(AppConstants.isTerminalStatus('preparing'), false);
      expect(AppConstants.isTerminalStatus('prepared'), false);
    });

    test('isTerminalStatus handles legacy pickedUp', () {
      expect(AppConstants.isTerminalStatus('pickedup'), true);
      expect(AppConstants.isTerminalStatus('pickedUp'), true);
    });
  });

  group('AppConstants - Order Type Normalization', () {
    test('normalizeOrderType handles null and empty', () {
      expect(AppConstants.normalizeOrderType(null), 'delivery');
      expect(AppConstants.normalizeOrderType(''), 'delivery');
    });

    test('normalizeOrderType handles dine-in variations', () {
      expect(AppConstants.normalizeOrderType('dine-in'), 'dine_in');
      expect(AppConstants.normalizeOrderType('dine_in'), 'dine_in');
      expect(AppConstants.normalizeOrderType('DineIn'), 'dine_in');
      expect(AppConstants.normalizeOrderType('Dine In'), 'dine_in');
      expect(AppConstants.normalizeOrderType('dine'), 'dine_in');
    });

    test('normalizeOrderType handles pickup variations', () {
      expect(AppConstants.normalizeOrderType('pickup'), 'pickup');
      expect(AppConstants.normalizeOrderType('pick_up'), 'pickup');
    });

    test('normalizeOrderType handles takeaway variations', () {
      expect(AppConstants.normalizeOrderType('takeaway'), 'takeaway');
      expect(AppConstants.normalizeOrderType('take_away'), 'takeaway');
    });

    test('normalizeOrderType preserves delivery', () {
      expect(AppConstants.normalizeOrderType('delivery'), 'delivery');
    });
  });

  group('AppConstants - Order Type Checks', () {
    test('isDeliveryOrder correctly identifies delivery', () {
      expect(AppConstants.isDeliveryOrder('delivery'), true);
      expect(AppConstants.isDeliveryOrder(null), true); // Default
      expect(AppConstants.isDeliveryOrder('dine_in'), false);
      expect(AppConstants.isDeliveryOrder('takeaway'), false);
    });

    test('isDineInOrder correctly identifies dine-in', () {
      expect(AppConstants.isDineInOrder('dine_in'), true);
      expect(AppConstants.isDineInOrder('dine-in'), true);
      expect(AppConstants.isDineInOrder('delivery'), false);
    });

    test('isPickupOrder correctly identifies pickup and takeaway', () {
      expect(AppConstants.isPickupOrder('pickup'), true);
      expect(AppConstants.isPickupOrder('takeaway'), true);
      expect(AppConstants.isPickupOrder('take_away'), true);
      expect(AppConstants.isPickupOrder('delivery'), false);
    });

    test('isTakeawayOrder correctly identifies takeaway only', () {
      expect(AppConstants.isTakeawayOrder('takeaway'), true);
      expect(AppConstants.isTakeawayOrder('take_away'), true);
      expect(AppConstants.isTakeawayOrder('pickup'), false);
    });

    test('requiresRider returns true only for delivery', () {
      expect(AppConstants.requiresRider('delivery'), true);
      expect(AppConstants.requiresRider('takeaway'), false);
      expect(AppConstants.requiresRider('dine_in'), false);
      expect(AppConstants.requiresRider('pickup'), false);
    });
  });

  group('AppConstants - Status Flow Logic', () {
    test('getNextStatusAfterPreparing returns correct status', () {
      expect(
        AppConstants.getNextStatusAfterPreparing('delivery'),
        'needs_rider_assignment',
      );
      expect(AppConstants.getNextStatusAfterPreparing('takeaway'), 'prepared');
      expect(AppConstants.getNextStatusAfterPreparing('dine_in'), 'prepared');
      expect(AppConstants.getNextStatusAfterPreparing('pickup'), 'prepared');
    });

    test('getNextStatusAfterPrepared returns correct status', () {
      expect(AppConstants.getNextStatusAfterPrepared('dine_in'), 'served');
      expect(AppConstants.getNextStatusAfterPrepared('pickup'), 'collected');
      expect(AppConstants.getNextStatusAfterPrepared('takeaway'), 'paid');
    });
  });

  group('AppConstants - Payment Method Helpers', () {
    test('isCashPayment correctly identifies cash payments', () {
      expect(AppConstants.isCashPayment('cash'), true);
      expect(AppConstants.isCashPayment('cod'), true);
      expect(AppConstants.isCashPayment('cash_on_delivery'), true);
      expect(AppConstants.isCashPayment(null), true); // Default
      expect(AppConstants.isCashPayment(''), true);
      expect(AppConstants.isCashPayment('online'), false);
    });

    test('isPrepaidPayment correctly identifies prepaid', () {
      expect(AppConstants.isPrepaidPayment('online'), true);
      expect(AppConstants.isPrepaidPayment('card'), true);
      expect(AppConstants.isPrepaidPayment('prepaid'), true);
      expect(AppConstants.isPrepaidPayment('apple_pay'), true);
      expect(AppConstants.isPrepaidPayment('google_pay'), true);
      expect(AppConstants.isPrepaidPayment('wallet'), true);
      expect(AppConstants.isPrepaidPayment('cash'), false);
      expect(AppConstants.isPrepaidPayment(null), false);
    });

    test('getPaymentDisplayText returns correct display text', () {
      expect(AppConstants.getPaymentDisplayText('cash'), 'CASH');
      expect(AppConstants.getPaymentDisplayText('online'), 'PREPAID');
      expect(AppConstants.getPaymentDisplayText('apple_pay'), 'APPLE PAY');
      expect(AppConstants.getPaymentDisplayText(null), 'CASH');
    });
  });
}

// Test for OrderNumberHelper
void orderNumberHelperTests() {
  group('OrderNumberHelper', () {
    test('getDisplayNumber returns order number when available', () {
      final data = {'dailyOrderNumber': 'ZKD-260107-001'};
      expect(OrderNumberHelper.getDisplayNumber(data), 'ZKD-260107-001');
    });

    test('getDisplayNumber returns loading for null data', () {
      expect(OrderNumberHelper.getDisplayNumber(null), 'Generating...');
    });

    test('getDisplayNumber returns loading for empty order number', () {
      final data = {'dailyOrderNumber': ''};
      expect(OrderNumberHelper.getDisplayNumber(data), 'Generating...');
    });

    test('isLoading returns true for null data', () {
      expect(OrderNumberHelper.isLoading(null), true);
    });

    test('isLoading returns false when order number exists', () {
      final data = {'dailyOrderNumber': 'ZKD-260107-001'};
      expect(OrderNumberHelper.isLoading(data), false);
    });
  });
}

// Test for StringExtension
void stringExtensionTests() {
  group('StringExtension', () {
    test('capitalize returns empty string for empty input', () {
      expect(''.capitalize(), '');
    });

    test('capitalize capitalizes first letter', () {
      expect('hello'.capitalize(), 'Hello');
      expect('HELLO'.capitalize(), 'HELLO');
      expect('h'.capitalize(), 'H');
    });

    test('toTitleCase capitalizes each word', () {
      expect('hello world'.toTitleCase(), 'Hello World');
      expect('one two three'.toTitleCase(), 'One Two Three');
    });
  });
}
