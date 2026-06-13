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
