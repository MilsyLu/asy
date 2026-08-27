import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow_executive/core/utils/client_linking.dart';
import 'package:taskflow_executive/models/client_model.dart';

/// Pruebas de las reglas con las que un nombre escrito se convierte en un
/// cliente del catálogo.
///
/// Prueban `clientsMatchingName`, la función real que usa `ClientLinking` —
/// no una copia suya. La primera versión de este archivo reimplementaba la
/// búsqueda para poder probarla, que es exactamente la falsa confianza que
/// vengo señalando: habría seguido en verde aunque el código de producción
/// cambiara. Por eso la función se extrajo del provider, que abre Firestore en
/// su constructor y no se puede construir en una prueba.
///
/// Lo que **no** cubre: que el formulario efectivamente llame a esta lógica al
/// guardar. Ese era el fallo original —un caso guardaba el nombre del cliente
/// como texto y ahí moría— y sólo se ve usando la pantalla.
void main() {
  ClientModel cliente(String id, String nombre, [String telefono = '']) =>
      ClientModel(id: id, name: nombre, phone: telefono, notes: '');

  final catalogo = [
    cliente('c1', 'Little Italy', '3001112233'),
    cliente('c2', 'Panadería los andes'),
    cliente('c3', 'Copias', '3004445566'),
    cliente('c4', 'Copias', '3007778899'),
  ];

  test('encuentra sin importar mayúsculas ni espacios', () {
    expect(clientsMatchingName(catalogo, '  little italy ').single.id, 'c1');
  });

  test('la tilde sí cuenta, porque es el nombre guardado', () {
    // A diferencia de la búsqueda de Reportes, aquí se compara contra el
    // nombre real del cliente para decidir si se crea uno nuevo. Aflojar eso
    // enlazaría "Panaderia" con "Panadería" y sería lo correcto, pero también
    // enlazaría nombres que el usuario quiso distintos.
    expect(
      clientsMatchingName(catalogo, 'Panadería los andes').single.id,
      'c2',
    );
    expect(clientsMatchingName(catalogo, 'Panaderia los andes'), isEmpty);
  });

  test('un nombre que no existe no devuelve nada', () {
    expect(clientsMatchingName(catalogo, 'Nuevo Cliente'), isEmpty);
  });

  test('dos negocios con el mismo nombre devuelven los dos', () {
    // El caso que obliga a que esto devuelva una lista y no un cliente: con
    // dos "Copias" reales, elegir uno al azar le colgaría el caso al que no
    // era. La regla de ClientLinking es no enlazar ninguno y dejar que el
    // usuario elija desde las sugerencias.
    expect(clientsMatchingName(catalogo, 'Copias').map((c) => c.id), [
      'c3',
      'c4',
    ]);
  });

  test('un nombre vacío no engancha con nada', () {
    expect(clientsMatchingName(catalogo, '   '), isEmpty);
  });
}
