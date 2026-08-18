import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow_executive/core/utils/snackbar_utils.dart';

/// Regression tests for the error mapper.
///
/// This function hid two real bugs in one day: a missing Firestore index and
/// an attachment upload that had been failing for two weeks. Both surfaced as
/// the same "ocurrió un error inesperado", because the mapper only knew
/// sign-in codes. The cases below pin down the part that matters — that an
/// unrecognised failure still tells you *what* failed.
void main() {
  String msg(Object e) => SnackbarUtils.firebaseErrorMessage(e);

  group('mensajes conocidos', () {
    test('credenciales inválidas', () {
      expect(msg(FirebaseException(plugin: 'firebase_auth', code: 'wrong-password')),
          'Email o contraseña incorrectos');
    });

    test('Firestore permission-denied y Storage unauthorized dicen lo mismo', () {
      const esperado = 'No tienes permisos para realizar esta acción';
      expect(msg(FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied')), esperado);
      expect(msg(FirebaseException(plugin: 'firebase_storage', code: 'unauthorized')), esperado);
    });

    test('sin conexión', () {
      expect(msg(FirebaseException(plugin: 'firebase_auth', code: 'network-request-failed')),
          'Error de conexión. Revisa tu internet');
    });
  });

  group('código desconocido: nunca se pierde la información', () {
    test('incluye plugin/código de una FirebaseException', () {
      final texto = msg(FirebaseException(plugin: 'firebase_storage', code: 'quota-something'));
      expect(texto, contains('firebase_storage/quota-something'));
    });

    test('lo extrae también de un error que solo lo imprime', () {
      final texto = msg('[firebase_storage/unknown] Algo salió mal');
      expect(texto, contains('firebase_storage/unknown'));
    });

    test('un error sin código no rompe: cae al mensaje genérico', () {
      expect(msg(StateError('boom')), 'Ocurrió un error inesperado. Intenta nuevamente');
    });
  });

  test('el índice faltante de Firestore ya no es invisible', () {
    // El fallo exacto de las etiquetas: failed-precondition.
    final texto = msg(FirebaseException(plugin: 'cloud_firestore', code: 'failed-precondition'));
    expect(texto, isNot(contains('inesperado')));
    expect(texto, contains('administrador'));
  });
}
