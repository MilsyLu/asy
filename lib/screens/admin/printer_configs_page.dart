import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/constants/printer_config_schema.dart';
import '../../core/responsive/app_spacing.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../core/utils/validators.dart';
import '../../models/printer_config_model.dart';
import '../../services/printer_config_repository.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/printer_config_form_fields.dart';

/// Admin: list of `printerConfigs` — one record per VinApp Print installer
/// client. Unlike the other admin CRUD screens (Equipos/Usuarios/Clientes),
/// create/edit open as a full page instead of a side panel/bottom sheet —
/// the ~88-field form doesn't fit either of those comfortably.
class PrinterConfigsPage extends StatefulWidget {
  const PrinterConfigsPage({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<PrinterConfigsPage> createState() => _PrinterConfigsPageState();
}

class _PrinterConfigsPageState extends State<PrinterConfigsPage> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final repo = context.read<PrinterConfigRepository>();
    final query = _query.trim().toLowerCase();

    final body = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _searchController,
            style: TextStyle(color: colors.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Buscar',
              hintText: 'Nombre del cliente',
              prefixIcon: Icon(LucideIcons.search, color: colors.primary, size: 18),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(LucideIcons.xCircle, size: 16),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<PrinterConfigModel>>(
            stream: repo.watchAll(),
            builder: (context, snap) {
              if (!snap.hasData) return const LoadingIndicator();
              final configs = List<PrinterConfigModel>.from(snap.data!)
                ..sort((a, b) => a.clientName.compareTo(b.clientName));
              final filtered = query.isEmpty
                  ? configs
                  : configs
                      .where((c) => c.clientName.toLowerCase().contains(query))
                      .toList();
              if (filtered.isEmpty) {
                return EmptyState(
                  message: query.isEmpty
                      ? 'No hay fichas de VinApp Print todavía.'
                      : 'Ningún cliente coincide con "$query".',
                  icon: LucideIcons.printer,
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                itemCount: filtered.length,
                separatorBuilder: (context, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final config = filtered[index];
                  return _PrinterConfigCard(
                    config: config,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => _PrinterConfigFormPage(existing: config),
                    )),
                  );
                },
              );
            },
          ),
        ),
      ],
    );

    final fab = FloatingActionButton.extended(
      onPressed: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const _PrinterConfigFormPage(existing: null),
      )),
      icon: const Icon(LucideIcons.plus),
      label: const Text('Nueva ficha'),
    );

    if (!widget.showAppBar) return Scaffold(body: body, floatingActionButton: fab);
    return Scaffold(
      appBar: AppBar(title: const Text('VinApp Print')),
      body: body,
      floatingActionButton: fab,
    );
  }
}

class _PrinterConfigCard extends StatelessWidget {
  const _PrinterConfigCard({required this.config, required this.onTap});

  final PrinterConfigModel config;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.primary.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: colors.primary.withValues(alpha: 0.15),
              child: Icon(LucideIcons.printer, color: colors.primary, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    config.clientName,
                    style: TextStyle(
                        color: colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${config.fields.length} de ${PrinterConfigSchema.fields.length} campos configurados',
                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(LucideIcons.chevronRight, color: colors.textSecondary, size: 16),
          ],
        ),
      ),
    );
  }
}

/// Full-page create/edit form — [existing] null means create. Shared by
/// both flows since the form itself (name + AI picker + 7 sections) is
/// identical either way, only pre-filled values and the Eliminar button
/// differ.
class _PrinterConfigFormPage extends StatefulWidget {
  const _PrinterConfigFormPage({required this.existing});

  final PrinterConfigModel? existing;

  @override
  State<_PrinterConfigFormPage> createState() => _PrinterConfigFormPageState();
}

class _PrinterConfigFormPageState extends State<_PrinterConfigFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  late Map<String, dynamic> _values;
  bool _isSaving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.clientName ?? '');
    // A new ficha starts from Michel's "configuración básica" defaults
    // (see PrinterConfigSchema.defaultValues); editing an existing one
    // always shows its own saved values, never the defaults.
    _values = Map<String, dynamic>.from(
        widget.existing?.fields ?? PrinterConfigSchema.defaultValues);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onFieldChanged(String key, dynamic value) {
    setState(() {
      if (value == null || value == '' || value == false) {
        _values.remove(key);
      } else {
        _values[key] = value;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    final repo = context.read<PrinterConfigRepository>();
    try {
      if (_isEditing) {
        await repo.update(widget.existing!.id, _nameController.text.trim(), _values);
      } else {
        await repo.add(_nameController.text.trim(), _values);
      }
      if (mounted) {
        SnackbarUtils.showSuccess(context, _isEditing ? 'Ficha actualizada' : 'Ficha creada');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _delete() async {
    final confirm = await showConfirmDialog(
      context,
      title: 'Eliminar ficha',
      message: '¿Eliminar la configuración de "${widget.existing!.clientName}"?',
      confirmLabel: 'Eliminar',
      destructive: true,
    );
    if (!confirm || !mounted) return;
    try {
      await context.read<PrinterConfigRepository>().delete(widget.existing!.id);
      if (mounted) {
        SnackbarUtils.showSuccess(context, 'Ficha eliminada');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final repo = context.read<PrinterConfigRepository>();
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? widget.existing!.clientName : 'Nueva ficha VinApp Print'),
        actions: [
          if (_isEditing)
            IconButton(
              icon: Icon(LucideIcons.trash2, color: colors.error),
              onPressed: _isSaving ? null : _delete,
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: colors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: colors.background,
                hintText: 'Buscar un campo (ej. "mesero", "logo")',
                prefixIcon: Icon(LucideIcons.search, color: colors.primary, size: 18),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(LucideIcons.xCircle, size: 16),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusMd)),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Nombre del cliente + selector de IA comparten una sola fila
              // en pantallas anchas — antes cada uno era un bloque apilado
              // que empujaba el resto del formulario (85 campos) muy abajo.
              LayoutBuilder(
                builder: (context, constraints) {
                  final nameField = TextFormField(
                    controller: _nameController,
                    style: TextStyle(color: colors.textPrimary),
                    decoration: const InputDecoration(labelText: 'Nombre del cliente'),
                    validator: (v) => Validators.required(v, fieldName: 'El nombre del cliente'),
                  );
                  final picker = PrinterConfigImagePicker(
                    repository: repo,
                    onExtracted: (extracted) => setState(() => _values.addAll(extracted)),
                  );
                  if (constraints.maxWidth < 640) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [nameField, const SizedBox(height: AppSpacing.sm), picker],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(flex: 2, child: nameField),
                      const SizedBox(width: AppSpacing.lg),
                      Expanded(flex: 3, child: picker),
                    ],
                  );
                },
              ),
              const SizedBox(height: AppSpacing.md),
              for (final section in PrinterConfigSections.all)
                PrinterConfigSectionGroup(
                  section: section,
                  values: _values,
                  onChanged: _onFieldChanged,
                  searchQuery: _searchQuery,
                ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  child: _isSaving
                      ? const SizedBox(
                          height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Guardar cambios'),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }
}
