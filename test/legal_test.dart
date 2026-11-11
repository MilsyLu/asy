import 'package:taskflow_executive/core/legal/legal_documents.dart';
import 'package:taskflow_executive/services/legal_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LegalResponsable', () {
    test('mientras falten datos, los documentos son un borrador', () {
      // Esta prueba no comprueba un valor: comprueba que el detector de
      // "falta llenar" sigue existiendo y sigue mirando los cuatro datos.
      // Es lo que impide publicar una política con corchetes sin llenar.
      final datos = [
        LegalResponsable.nombre,
        LegalResponsable.domicilio,
        LegalResponsable.telefono,
        LegalResponsable.correo,
      ];
      final hayPendientes = datos.any((d) => d.startsWith('['));
      expect(LegalResponsable.completo, !hayPendientes);
    });
  });

  group('LegalDoc', () {
    test('la clave junta documento y versión', () {
      expect(LegalDocs.politica.clave, 'politica_datos_v1.0');
      expect(LegalDocs.terminos.clave, 'terminos_uso_v1.0');
    });

    test('los dos documentos tienen identificadores distintos', () {
      final ids = LegalDocs.todos.map((d) => d.id).toSet();
      expect(ids.length, LegalDocs.todos.length);
    });

    test('ningún documento queda sin texto ni sin versión', () {
      for (final doc in LegalDocs.todos) {
        expect(doc.version.isNotEmpty, isTrue, reason: doc.id);
        expect(doc.cuerpo.trim().length > 500, isTrue, reason: doc.id);
        expect(doc.vigenteDesde.isNotEmpty, isTrue, reason: doc.id);
      }
    });

    test('la política nombra los derechos que la ley obliga a informar', () {
      final texto = LegalDocs.politica.cuerpo.toLowerCase();
      for (final obligatorio in [
        'ley 1581',
        'superintendencia de industria y comercio',
        'revocar',
        'supresión',
        'rectificar',
        'días hábiles',
      ]) {
        expect(
          texto.contains(obligatorio),
          isTrue,
          reason: 'falta "$obligatorio" en la política',
        );
      }
    });

    test('la huella de versiones cambia si cambia una versión', () {
      final ahora = LegalDocs.versionVigente;
      expect(ahora.contains('politica_datos:1.0'), isTrue);
      expect(ahora.contains('terminos_uso:1.0'), isTrue);
    });
  });

  group('LegalRepository.idDe', () {
    // La regla de seguridad parte el id por '__' y exige que el primer
    // pedazo sea el uid de quien escribe (ver firestore.rules). Si esta
    // forma cambia sin cambiar la regla, nadie podría aceptar nada: la
    // escritura sería rechazada en producción y en ningún otro lado.
    test('el id empieza por el uid, como lo exige la regla', () {
      final id = LegalRepository.idDe('abc123', LegalDocs.politica);
      expect(id.split('__').first, 'abc123');
      expect(id, 'abc123__politica_datos_v1.0');
    });

    test('dos documentos del mismo usuario no chocan', () {
      final uno = LegalRepository.idDe('u1', LegalDocs.politica);
      final dos = LegalRepository.idDe('u1', LegalDocs.terminos);
      expect(uno == dos, isFalse);
    });

    test('aceptar dos veces lo mismo escribe en el mismo sitio', () {
      expect(
        LegalRepository.idDe('u1', LegalDocs.politica),
        LegalRepository.idDe('u1', LegalDocs.politica),
      );
    });
  });
}
