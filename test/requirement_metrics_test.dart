import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow_executive/core/constants/requirement_constants.dart';
import 'package:taskflow_executive/core/utils/requirement_metrics.dart';
import 'package:taskflow_executive/models/requirement_model.dart';

RequirementModel req(String estado, {String? responsable}) => RequirementModel(
  id: estado + (responsable ?? ''),
  requirementNumber: 1,
  empresaId: 'e1',
  origin: RequirementOrigin.cliente,
  clientIds: const [],
  clientNames: const [],
  type: RequirementType.mejoras,
  module: RequirementModule.otros,
  description: 'x',
  status: estado,
  priority: RequirementPriority.sinPrioridad,
  developerId: responsable,
  receivedAt: DateTime(2026, 10, 1),
  receivedById: 'u1',
  receivedByName: 'Quien sea',
);

void main() {
  test('publicado cuenta como abierto: falta avisarle al cliente', () {
    final c = RequirementCounts.of([req(RequirementStatus.publicado)]);
    expect(c.abiertos, 1);
  });

  test('comunicado, en pausa y rechazado ya no están abiertos', () {
    final c = RequirementCounts.of([
      req(RequirementStatus.comunicado),
      req(RequirementStatus.enPausa),
      req(RequirementStatus.rechazado),
    ]);
    expect(c.abiertos, 0);
  });

  test('"Por comunicar" NO cuenta los ya comunicados', () {
    // El error que lo motivó: Michel pasó el único publicado a "Comunicado
    // al cliente", el filtro por estado Publicado dio cero y la tarjeta
    // siguió marcando uno. Contaba publicados + comunicados bajo un nombre
    // que decía sólo lo primero.
    final c = RequirementCounts.of([req(RequirementStatus.comunicado)]);
    expect(c.porComunicar, 0);
  });

  test('"Por comunicar" cuenta los publicados sin avisar', () {
    final c = RequirementCounts.of([
      req(RequirementStatus.publicado),
      req(RequirementStatus.publicado),
      req(RequirementStatus.comunicado),
    ]);
    expect(c.porComunicar, 2);
  });

  test('"Por aprobar" son sólo los recibidos', () {
    final c = RequirementCounts.of([
      req(RequirementStatus.recibido),
      req(RequirementStatus.aprobado),
    ]);
    expect(c.porAprobar, 1);
  });

  test('"Sin responsable" mira sólo los abiertos', () {
    // Un rechazado sin responsable no es trabajo por repartir: ya no se va a
    // hacer. Contarlo inflaría la cifra con cosas que nadie va a asignar.
    final c = RequirementCounts.of([
      req(RequirementStatus.aprobado),
      req(RequirementStatus.aprobado, responsable: 'dev1'),
      req(RequirementStatus.rechazado),
    ]);
    expect(c.sinResponsable, 1);
  });

  test('"Desarrollo o QA" son esos dos estados y nada más', () {
    final c = RequirementCounts.of([
      req(RequirementStatus.enDesarrollo),
      req(RequirementStatus.enQa),
      req(RequirementStatus.aprobado),
      req(RequirementStatus.publicado),
    ]);
    expect(c.enDesarrolloOQa, 2);
  });

  test('sin requerimientos, todo en cero', () {
    final c = RequirementCounts.of([]);
    expect(
      [
        c.porAprobar,
        c.abiertos,
        c.sinResponsable,
        c.enDesarrolloOQa,
        c.porComunicar,
      ],
      [0, 0, 0, 0, 0],
    );
  });
}
