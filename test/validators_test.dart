import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow_executive/core/utils/validators.dart';

void main() {
  group('Validators.email', () {
    test('rejects empty values', () {
      expect(Validators.email(''), isNotNull);
      expect(Validators.email(null), isNotNull);
    });

    test('rejects malformed addresses', () {
      expect(Validators.email('not-an-email'), isNotNull);
    });

    test('accepts a valid address', () {
      expect(Validators.email('user@example.com'), isNull);
    });
  });

  group('Validators.phone', () {
    test('rejects empty values', () {
      expect(Validators.phone(''), isNotNull);
    });

    test('rejects letters', () {
      expect(Validators.phone('abc123'), isNotNull);
    });

    test('accepts digits, "+" and spaces', () {
      expect(Validators.phone('+56 9 1234 5678'), isNull);
    });

    test('accepts a Colombian number without country code', () {
      expect(Validators.phone('3002257755'), isNull);
    });

    test('accepts a Colombian number with country code', () {
      expect(Validators.phone('+573002257755'), isNull);
    });

    test('rejects numbers with fewer than 10 digits', () {
      expect(Validators.phone('300225'), isNotNull);
    });
  });

  group('Validators.cleanPhone', () {
    test('removes spaces from a local number', () {
      expect(Validators.cleanPhone('300 225 7755'), '3002257755');
    });

    test('removes spaces but keeps the leading "+"', () {
      expect(Validators.cleanPhone('+57 300 225 7755'), '+573002257755');
    });
  });

  group('Validators.formatPhone', () {
    test('groups a local Colombian number as XXX XXX XXXX', () {
      expect(Validators.formatPhone('3002257755'), '300 225 7755');
    });

    test('groups a number with country code as +CC XXX XXX XXXX', () {
      expect(Validators.formatPhone('+573002257755'), '+57 300 225 7755');
    });
  });

  group('Validators.password', () {
    test('rejects passwords shorter than 6 characters', () {
      expect(Validators.password('123'), isNotNull);
    });

    test('accepts passwords with 6+ characters', () {
      expect(Validators.password('123456'), isNull);
    });
  });

  group('Validators.isReminderValid', () {
    final taskDate = DateTime(2026, 6, 11);

    test('allows a null reminder', () {
      expect(
        Validators.isReminderValid(taskDate: taskDate, taskHour: '14:00'),
        isTrue,
      );
    });

    test('allows a reminder before the task time', () {
      expect(
        Validators.isReminderValid(
          taskDate: taskDate,
          taskHour: '14:00',
          reminderDateTime: DateTime(2026, 6, 11, 13, 59),
        ),
        isTrue,
      );
    });

    test('rejects a reminder at or after the task time', () {
      expect(
        Validators.isReminderValid(
          taskDate: taskDate,
          taskHour: '14:00',
          reminderDateTime: DateTime(2026, 6, 11, 14, 0),
        ),
        isFalse,
      );
    });

    test('allows a reminder on a previous day', () {
      expect(
        Validators.isReminderValid(
          taskDate: taskDate,
          taskHour: '08:00',
          reminderDateTime: DateTime(2026, 6, 10, 23, 59),
        ),
        isTrue,
      );
    });
  });
}
