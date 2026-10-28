import '../constants/requirement_constants.dart';
import '../../models/requirement_model.dart';

/// Las cinco cifras del encabezado de Requerimientos.
///
/// Vivían sueltas dentro del widget, y una de ellas mentía: la tarjeta decía
/// "Publicados" pero sumaba los publicados *y* los comunicados al cliente.
/// Michel lo encontró filtrando por estado Publicado —cero resultados— con la
/// tarjeta marcando uno al lado. Aquí se pueden probar, que es la única forma
/// de que una etiqueta y su cuenta no se separen con el tiempo.
///
/// Las cinco se calculan sobre *todos* los requerimientos, no sobre los
/// filtrados: son el panorama del área, y cambiar de filtro no debería
/// cambiar cuántos hay sin aprobar.
class RequirementCounts {
  const RequirementCounts({
    required this.porAprobar,
    required this.abiertos,
    required this.sinResponsable,
    required this.enDesarrolloOQa,
    required this.porComunicar,
  });

  /// Recibidos: nadie los ha aprobado ni rechazado todavía.
  final int porAprobar;

  /// Ni comunicados al cliente, ni en pausa, ni rechazados.
  ///
  /// Publicado cuenta como abierto: publicar no es entregar, y mientras el
  /// cliente no sepa que su pedido está listo sigue faltando algo por hacer.
  final int abiertos;

  /// Abiertos sin desarrollador asignado.
  final int sinResponsable;

  /// En desarrollo o en QA: lo que está en manos del equipo técnico.
  final int enDesarrolloOQa;

  /// Publicados a los que todavía no se les ha avisado al cliente.
  ///
  /// Antes esta cifra sumaba también los ya comunicados, y así no respondía
  /// ninguna pregunta útil: era "cuántos se terminaron alguna vez", un número
  /// que sólo crece. Las otras cuatro tarjetas dicen *dónde está detenido el
  /// trabajo*, y éste es el último paso —el que más se olvida— y la razón
  /// misma de que Publicado siga contando como abierto.
  final int porComunicar;

  factory RequirementCounts.of(List<RequirementModel> todos) {
    var porAprobar = 0;
    var abiertos = 0;
    var sinResponsable = 0;
    var enDesarrolloOQa = 0;
    var porComunicar = 0;

    for (final r in todos) {
      final abierto = RequirementStatus.isOpen(r.status);
      if (abierto) {
        abiertos++;
        if (!r.estaAsignado) sinResponsable++;
      }
      if (r.status == RequirementStatus.recibido) porAprobar++;
      if (RequirementStatus.enManosDeDesarrollo(r.status)) enDesarrolloOQa++;
      if (r.status == RequirementStatus.publicado) porComunicar++;
    }

    return RequirementCounts(
      porAprobar: porAprobar,
      abiertos: abiertos,
      sinResponsable: sinResponsable,
      enDesarrolloOQa: enDesarrolloOQa,
      porComunicar: porComunicar,
    );
  }
}
