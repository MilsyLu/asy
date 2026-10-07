import '../../models/group_model.dart';

/// Si el formulario de tareas debe pedir la hora libre o elegirla de las
/// franjas configuradas.
///
/// El modo vive en el equipo (`GroupModel.timeSelectionMode`), así que con un
/// equipo elegido la respuesta es la suya y no hay más que decidir.
///
/// Lo que faltaba era el otro caso: **cuándo todavía no hay equipo elegido**.
/// La regla estaba escrita dos veces —en `add_edit_task_page` y en
/// `task_create_panel`— y las dos terminaban en `?? false`, es decir, franjas.
/// Un super usuario no pertenece a ningún equipo, así que abría el formulario
/// y le salía la rejilla de horas aunque los dos equipos de la empresa
/// estuvieran en horario libre: tenía que elegir una franja que no le aplica a
/// nadie.
///
/// Sin equipo, la respuesta honesta sale de los equipos que hay: sólo se
/// piden franjas si **algún** equipo las usa de verdad. Si ninguno las usa, la
/// rejilla no le corresponde a nadie y estorba. Sin equipos cargados todavía
/// —el catálogo llega por stream— también es libre, que es lo que no obliga a
/// elegir nada mientras se está cargando.
bool useFreeHours(List<GroupModel> groups, String? groupId) {
  if (groupId != null) {
    for (final g in groups) {
      if (g.id == groupId) return g.useFreePicker;
    }
  }
  return groups.every((g) => g.useFreePicker);
}

/// Con qué hora se abre el diálogo de reprogramar.
///
/// En horario libre, con la de la tarea: cualquier hora es válida, así que no
/// hay nada que corregir.
///
/// Con franjas, la de la tarea sólo si sigue siendo una de las configuradas.
/// Si no lo es —porque se la quitaron del catálogo, o porque la tarea entró
/// por la hoja de cálculo con una hora cualquiera— se abre en la primera
/// franja: el desplegable no puede mostrar un valor que no está entre sus
/// opciones.
///
/// Esto es lo que hacía que reprogramar una tarea de horario libre le
/// cambiara la hora sola nada más abrir el diálogo, sin tocar nada: las 15:30
/// de "Perro Loco" no estaban entre las cuatro franjas, así que se abría en
/// las 10:00 y eso era lo que se guardaba.
String initialRescheduleHour({
  required bool libre,
  required String currentHour,
  required List<String> catalogHours,
}) {
  if (libre) return currentHour;
  if (catalogHours.contains(currentHour)) return currentHour;
  return catalogHours.isNotEmpty ? catalogHours.first : currentHour;
}
