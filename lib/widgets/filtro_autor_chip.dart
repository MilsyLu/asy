import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../core/responsive/app_spacing.dart';
import '../core/theme/theme_colors.dart';
import '../core/utils/autor_tarea.dart';
import '../models/task_model.dart';
import '../providers/auth_provider.dart';
import '../providers/catalog_provider.dart';
import '../providers/filtro_autor_provider.dart';

/// El control de "Asignadas por" que comparten Calendario y Agenda.
///
/// Un solo widget y no uno por pantalla: son cuatro vistas y cuatro copias
/// es la forma más segura de que dentro de un mes tres digan una cosa y la
/// cuarta otra.
///
/// Cuando está filtrando se pone del color de la marca y aparece una X para
/// quitarlo. Es deliberado: una lista filtrada y una lista vacía se ven
/// igual, y quien no se dé cuenta va a creer que no hay tareas ese día.
class FiltroAutorChip extends StatelessWidget {
  const FiltroAutorChip({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final filtro = context.watch<FiltroAutorProvider>();
    final catalog = context.watch<CatalogProvider>();
    final yo = context.read<AuthProvider>().appUser?.id;

    String nombre(String clave) =>
        nombreAutor(clave, (id) => catalog.userById(id)?.name);

    // Las opciones salen del catalogo y no de las tareas que hay a la
    // vista: si alguien apareciera solo cuando ya tiene tareas en pantalla,
    // la pregunta "¿que asigno Natalia hoy?" no se podria ni hacer los
    // dias en que la respuesta es "nada" — y esa tambien es una respuesta.
    final claves = <String>{
      for (final u in catalog.users)
        if (u.isActive) u.id,
      AutorTarea.hoja,
      AutorTarea.sinRegistrar,
    };
    if (yo != null) claves.add(yo);
    final opciones = claves.toList()
      ..sort(
        (a, b) => nombre(a).toLowerCase().compareTo(nombre(b).toLowerCase()),
      );

    final activo = filtro.activo;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: activo
                ? colors.primary.withValues(alpha: 0.10)
                : colors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(color: activo ? colors.primary : colors.divider),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: filtro.autor,
              isDense: true,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              dropdownColor: colors.surface,
              icon: Icon(
                LucideIcons.chevronDown,
                size: 15,
                color: activo ? colors.primary : colors.textSecondary,
              ),
              style: TextStyle(color: colors.textPrimary, fontSize: 13),
              // Cerrado dice de qué filtro se trata; abierto, sólo los
              // nombres. Sin eso, un desplegable que dice "Todos" al lado
              // de otro que dice "Todos" no distingue cuál es cuál.
              selectedItemBuilder: (context) => [
                _Cerrado(texto: 'Asignadas por: todos', apagado: true),
                for (final c in opciones)
                  _Cerrado(texto: 'Asignadas por: ${nombre(c)}'),
              ],
              items: [
                DropdownMenuItem<String?>(
                  child: Text(
                    'Todos',
                    style: TextStyle(color: colors.textSecondary, fontSize: 13),
                  ),
                ),
                for (final c in opciones)
                  DropdownMenuItem<String?>(
                    value: c,
                    child: Text(
                      c == yo ? '${nombre(c)} (yo)' : nombre(c),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
              ],
              onChanged: filtro.cambiar,
            ),
          ),
        ),
        if (activo)
          IconButton(
            tooltip: 'Ver todas',
            visualDensity: VisualDensity.compact,
            icon: Icon(LucideIcons.x, size: 16, color: colors.primary),
            onPressed: filtro.limpiar,
          ),
      ],
    );
  }
}

class _Cerrado extends StatelessWidget {
  const _Cerrado({required this.texto, this.apagado = false});

  final String texto;
  final bool apagado;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        texto,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          color: apagado ? colors.textSecondary : colors.primary,
          fontWeight: apagado ? FontWeight.normal : FontWeight.w600,
        ),
      ),
    );
  }
}

/// Deja sólo las tareas del autor elegido. Sin filtro, devuelve la misma
/// lista: filtrar por nada no debería ni copiarla.
List<TaskModel> aplicarFiltroAutor(List<TaskModel> tareas, String? autor) {
  if (autor == null) return tareas;
  return [
    for (final t in tareas)
      if (claveAutor(t) == autor) t,
  ];
}
