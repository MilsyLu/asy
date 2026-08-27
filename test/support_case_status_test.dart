import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow_executive/core/constants/support_case_constants.dart';

/// Separa lo que se guarda de lo que se muestra.
///
/// La columna del Kanban decía "Nuevo" y tenía casos de once días. La etiqueta
/// cambió a "Pendiente", pero el valor guardado no puede moverse: está escrito
/// en cada documento de `supportCases` y en `checkSupportCaseReminders.js`,
/// que decide a quién recordarle. Cambiar la constante dejaría los casos
/// existentes en un estado que la app ya no reconoce, sin que nada falle al
/// compilar.
void main() {
  test('el valor guardado sigue siendo "Nuevo"', () {
    expect(
      SupportCaseStatus.nuevo,
      'Nuevo',
      reason: 'es la cadena que está en la base de datos y en la Cloud '
          'Function de recordatorios; cambiarla rompe los casos existentes',
    );
  });

  test('lo que se muestra dice "Pendiente"', () {
    expect(SupportCaseStatus.labelFor(SupportCaseStatus.nuevo), 'Pendiente');
    expect(
      SupportCaseStatus.columnLabelFor(SupportCaseStatus.nuevo),
      'Pendientes',
      reason: 'la columna agrupa varios, y coincide con el filtro rápido',
    );
  });

  test('los demás estados se muestran tal como están guardados', () {
    for (final s in [
      SupportCaseStatus.enProceso,
      SupportCaseStatus.esperandoCliente,
      SupportCaseStatus.resuelto,
    ]) {
      expect(SupportCaseStatus.labelFor(s), s);
      expect(SupportCaseStatus.columnLabelFor(s), s);
    }
  });

  test('un estado desconocido se muestra tal cual en vez de desaparecer', () {
    // Un documento viejo o escrito por fuera de la app no debe dejar la
    // insignia en blanco.
    expect(SupportCaseStatus.labelFor('Otro'), 'Otro');
  });

  test('"Nuevo" sigue contando como caso abierto', () {
    expect(SupportCaseStatus.isOpen(SupportCaseStatus.nuevo), isTrue);
  });
}
