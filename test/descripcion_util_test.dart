import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow_executive/core/utils/support_case_metrics.dart';

void main() {
  test('una descripción vacía no es descripción', () {
    expect(descripcionUtil('Cambiar el menú', ''), isNull);
    expect(descripcionUtil('Cambiar el menú', '   '), isNull);
  });

  test('repetir el asunto no es describir', () {
    // El caso real: 40 de 121 casos tenían las dos cosas escritas idénticas.
    expect(
      descripcionUtil(
        'Modificar el apellido de Juan por Z',
        'Modificar el apellido de Juan por Z',
      ),
      isNull,
    );
  });

  test('ni aunque cambien las mayúsculas o sobren espacios', () {
    expect(descripcionUtil('Cambiar el menú', '  cambiar EL menú '), isNull);
  });

  test('una descripción que amplía sí se conserva', () {
    expect(
      descripcionUtil(
        'Cambiar el menú',
        'Quitar los postres y subir el precio de las bebidas.',
      ),
      'Quitar los postres y subir el precio de las bebidas.',
    );
  });

  test('se devuelve sin los espacios de los bordes', () {
    expect(descripcionUtil('Asunto', '  Algo más  '), 'Algo más');
  });

  test('una descripción que contiene el asunto no se descarta', () {
    // Sólo se descarta la copia exacta: si además dice algo, se queda.
    expect(
      descripcionUtil('Cambiar el menú', 'Cambiar el menú antes del viernes'),
      'Cambiar el menú antes del viernes',
    );
  });
}
