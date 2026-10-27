import 'package:taskflow_executive/core/utils/date_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String a(int hora) => AppDateUtils.saludoDelDia(DateTime(2026, 10, 26, hora));

  test('las cuatro de la tarde son tarde', () {
    // El error que lo motivó: la Agenda pasaba `today`, que es el comienzo
    // del día, así que la hora era siempre 0 y saludaba "Buenas noches" a
    // cualquier hora.
    expect(a(16), 'Buenas tardes');
  });

  test('la medianoche no es "Buenas tardes"', () {
    expect(a(0), 'Buenas noches');
  });

  test('el día completo', () {
    expect(a(5), 'Buenas noches');
    expect(a(6), 'Buenos días');
    expect(a(11), 'Buenos días');
    expect(a(12), 'Buenas tardes');
    expect(a(18), 'Buenas tardes');
    expect(a(19), 'Buenas noches');
    expect(a(23), 'Buenas noches');
  });
}
