import 'package:flutter_test/flutter_test.dart';
import 'package:mdd/Widgets/timings/working_hours_utils.dart';

void main() {
  group('WorkingHoursUtils', () {
    test('creates a default schedule for every day', () {
      final schedule = WorkingHoursUtils.createDefaultWorkingHours();

      expect(schedule.keys, orderedEquals(WorkingHoursUtils.orderedDays));
      for (final day in WorkingHoursUtils.orderedDays) {
        final dayData = Map<String, dynamic>.from(schedule[day] as Map);
        expect(dayData['isOpen'], isTrue);
        expect(dayData['slots'], isNotEmpty);
      }
    });

    test('normalizes valid times and preserves overnight shifts', () {
      final result = WorkingHoursUtils.validateWorkingHours({
        'monday': {
          'isOpen': true,
          'slots': [
            {'open': '21:00', 'close': '02:00'}
          ],
        },
      });

      expect(result.isValid, isTrue);
      final monday = Map<String, dynamic>.from(
          result.normalizedWorkingHours['monday'] as Map);
      final slot = (monday['slots'] as List).single as Map<String, dynamic>;
      expect(slot['open'], '21:00');
      expect(slot['close'], '02:00');
      expect(WorkingHoursUtils.calculateSlotDurationMinutes(slot), 300);
    });

    test('detects same-day overlapping shifts', () {
      final result = WorkingHoursUtils.validateWorkingHours({
        'monday': {
          'isOpen': true,
          'slots': [
            {'open': '09:00', 'close': '14:00'},
            {'open': '13:30', 'close': '16:00'},
          ],
        },
      });

      expect(result.isValid, isFalse);
      expect(
        result.issues.any((issue) => issue.code == 'same_day_overlap'),
        isTrue,
      );
    });

    test('detects cross-day overlap from overnight shifts', () {
      final result = WorkingHoursUtils.validateWorkingHours({
        'monday': {
          'isOpen': true,
          'slots': [
            {'open': '22:00', 'close': '02:00'},
          ],
        },
        'tuesday': {
          'isOpen': true,
          'slots': [
            {'open': '01:00', 'close': '05:00'},
          ],
        },
      });

      expect(result.isValid, isFalse);
      expect(
        result.issues.any((issue) => issue.code == 'cross_day_overlap'),
        isTrue,
      );
    });

    test('allows overnight shifts when the next day is closed', () {
      final result = WorkingHoursUtils.validateWorkingHours({
        'monday': {
          'isOpen': true,
          'slots': [
            {'open': '22:00', 'close': '02:00'},
          ],
        },
        'tuesday': {
          'isOpen': false,
          'slots': [
            {'open': '01:00', 'close': '05:00'},
          ],
        },
      });

      expect(result.isValid, isTrue);
    });

    test('does not validate stored slots for closed days', () {
      final result = WorkingHoursUtils.validateWorkingHours({
        'monday': {
          'isOpen': false,
          'slots': [
            {'open': '99:99', 'close': '18:00'},
            {'open': '10:00', 'close': '11:00'},
          ],
        },
      });

      expect(result.isValid, isTrue);
    });

    test('flags open days without shifts', () {
      final result = WorkingHoursUtils.validateWorkingHours({
        'monday': {
          'isOpen': true,
          'slots': [],
        },
      });

      expect(result.isValid, isFalse);
      expect(
        result.issues.any((issue) => issue.code == 'open_day_without_slots'),
        isTrue,
      );
    });
  });
}
