import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme/theme_colors.dart';
import '../../../core/utils/validators.dart';
import '../../../models/client_model.dart';

/// Combined Nombre/Teléfono fields for a task's client — the first
/// `Autocomplete` in the app. Typing in Nombre suggests existing
/// [ClientModel]s by name; picking one fills both fields and reports the
/// linked id via [onClientIdChanged]. If the user then edits either field
/// by hand, the link is cleared (`onClientIdChanged(null)`) so the task
/// never claims to be linked to a client whose current name/phone no
/// longer match what's typed — the save-time logic in
/// `add_edit_task_page.dart`/`task_create_panel.dart` then resolves-or-
/// creates a client from whatever ends up in these fields.
class ClientPickerField extends StatefulWidget {
  const ClientPickerField({
    super.key,
    required this.clients,
    required this.nameController,
    required this.phoneController,
    required this.clientId,
    required this.onClientIdChanged,
  });

  final List<ClientModel> clients;
  final TextEditingController nameController;
  final TextEditingController phoneController;
  final String? clientId;
  final ValueChanged<String?> onClientIdChanged;

  @override
  State<ClientPickerField> createState() => _ClientPickerFieldState();
}

class _ClientPickerFieldState extends State<ClientPickerField> {
  final _nameFocusNode = FocusNode();

  // The name+phone the currently-linked client had at the moment it was
  // linked, so a later manual edit to either field can be told apart from
  // Flutter merely re-syncing the same text during a rebuild.
  String? _linkedName;
  String? _linkedPhone;

  @override
  void initState() {
    super.initState();
    if (widget.clientId != null) {
      _linkedName = widget.nameController.text;
      _linkedPhone = widget.phoneController.text;
    }
    widget.nameController.addListener(_onFieldsChanged);
    widget.phoneController.addListener(_onFieldsChanged);
  }

  @override
  void dispose() {
    widget.nameController.removeListener(_onFieldsChanged);
    widget.phoneController.removeListener(_onFieldsChanged);
    _nameFocusNode.dispose();
    super.dispose();
  }

  void _onFieldsChanged() {
    if (widget.clientId == null) return;
    if (widget.nameController.text != _linkedName ||
        widget.phoneController.text != _linkedPhone) {
      widget.onClientIdChanged(null);
    }
  }

  void _pick(ClientModel client) {
    widget.nameController.text = client.name;
    widget.phoneController.text = client.phone;
    _linkedName = client.name;
    _linkedPhone = client.phone;
    widget.onClientIdChanged(client.id);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RawAutocomplete<ClientModel>(
          textEditingController: widget.nameController,
          focusNode: _nameFocusNode,
          optionsBuilder: (textValue) {
            final query = textValue.text.trim().toLowerCase();
            if (query.isEmpty) return const Iterable<ClientModel>.empty();
            return widget.clients
                .where((c) => c.name.toLowerCase().contains(query))
                .take(6);
          },
          displayStringForOption: (c) => c.name,
          onSelected: _pick,
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            return TextFormField(
              controller: controller,
              focusNode: focusNode,
              style: TextStyle(color: colors.textPrimary),
              decoration: InputDecoration(
                labelText: 'Nombre',
                prefixIcon: Icon(LucideIcons.userCircle, color: colors.primary),
              ),
              validator: (v) => Validators.required(v, fieldName: 'El nombre del cliente'),
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                color: colors.surface,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240, maxWidth: 360),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (context, index) {
                      final option = options.elementAt(index);
                      return ListTile(
                        dense: true,
                        title: Text(option.name, style: TextStyle(color: colors.textPrimary)),
                        subtitle: option.phone.isEmpty
                            ? null
                            : Text(
                                Validators.formatPhone(option.phone),
                                style: TextStyle(color: colors.textSecondary, fontSize: 12),
                              ),
                        onTap: () => onSelected(option),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: widget.phoneController,
          keyboardType: TextInputType.phone,
          style: TextStyle(color: colors.textPrimary),
          decoration: InputDecoration(
            labelText: 'Teléfono',
            prefixIcon: Icon(LucideIcons.phone, color: colors.primary),
            hintText: '300 225 7755 o +57 300 225 7755',
          ),
          validator: Validators.phone,
        ),
      ],
    );
  }
}
