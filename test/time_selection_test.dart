import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow_executive/core/utils/time_selection.dart';
import 'package:taskflow_executive/models/group_model.dart';
import 'package:taskflow_executive/models/system_config_model.dart';

/// Pruebas de cuándo el formulario pide la hora libre y cuándo franjas.
///
/// Prueban la función real que usan los dos formularios de tarea. Antes la
/// regla estaba escrita en los dos por separado y las dos copias tenían el
/// mismo fallo; ahora es una.
void main() {
  GroupModel equipo(String id, {required bool libre}) => GroupModel(
    id: id,
    name: id,
    timeSelectionMode: libre
        ? SystemConfigModel.modeFree
        : SystemConfigModel.modeCatalog,
  );

  final soporte = equipo('soporte', libre: true);
  final onboarding = equipo('onboarding', libre: true);
  final instalaciones = equipo('instalaciones', libre: false);

  test('con equipo elegido manda el modo de ese equipo', () {
    final equipos = [soporte, instalaciones];
    expect(useFreeHours(equipos, 'soporte'), isTrue);
    expect(useFreeHours(equipos, 'instalaciones'), isFalse);
  });

  test('sin equipo, si todos son libres no se piden franjas', () {
    // El caso que reportó Michel: entró como super usuario —que no pertenece a
    // ningún equipo— y le salió la rejilla de horas aunque SOPORTE y
    // ONBOARDING, los dos únicos equipos, están en horario libre.
    expect(useFreeHours([soporte, onboarding], null), isTrue);
  });

  test('sin equipo, basta con que uno use franjas para pedirlas', () {
    // Con un equipo que sí las usa, la rejilla le corresponde a alguien: se
    // muestra, y al elegir equipo se ajusta.
    expect(useFreeHours([soporte, instalaciones], null), isFalse);
  });

  test('un equipo que ya no existe se trata como si no hubiera equipo', () {
    // Una tarea vieja de un equipo eliminado no debe decidir el modo con un
    // dato que ya no está.
    expect(useFreeHours([soporte, onboarding], 'equipo-borrado'), isTrue);
    expect(useFreeHours([soporte, instalaciones], 'equipo-borrado'), isFalse);
  });

  test('sin equipos cargados todavía es libre, no franjas', () {
    // El catálogo llega por stream: durante el primer dibujo la lista está
    // vacía. Pedir franjas ahí obliga a elegir una hora antes de saber si
    // siquiera aplican.
    expect(useFreeHours(const [], null), isTrue);
  });

  group('initialRescheduleHour', () {
    const franjas = ['10:00', '12:00', '14:00', '16:00'];

    test('en horario libre no le cambia la hora a la tarea', () {
      // El fallo que reportó Michel: abrir "Reprogramar" en una tarea de las
      // 15:30 de un equipo libre la ponía en 10:00 sin tocar nada, porque
      // 15:30 no es ninguna de las cuatro franjas.
      expect(
        initialRescheduleHour(
          libre: true,
          currentHour: '15:30',
          catalogHours: franjas,
        ),
        '15:30',
      );
    });

    test('con franjas respeta la hora si es una de ellas', () {
      expect(
        initialRescheduleHour(
          libre: false,
          currentHour: '12:00',
          catalogHours: franjas,
        ),
        '12:00',
      );
    });

    test('con franjas cae en la primera si la hora ya no existe', () {
      // Pasa cuando se quita una franja del catálogo, o cuando la tarea entró
      // por la hoja de cálculo con una hora cualquiera. El desplegable no
      // puede mostrar un valor que no está entre sus opciones.
      expect(
        initialRescheduleHour(
          libre: false,
          currentHour: '15:30',
          catalogHours: franjas,
        ),
        '10:00',
      );
    });

    test('sin franjas configuradas se queda con la de la tarea', () {
      expect(
        initialRescheduleHour(
          libre: false,
          currentHour: '15:30',
          catalogHours: const [],
        ),
        '15:30',
      );
    });
  });

  test('el valor por defecto de un equipo sigue siendo franjas', () {
    // Lo contrario cambiaría en silencio el comportamiento de los equipos que
    // nunca eligieron modo.
    expect(GroupModel(id: 'x', name: 'x').useFreePicker, isFalse);
  });
}
