import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/theme/theme_colors.dart';
import '../core/utils/validators.dart';
import '../models/client_model.dart';

/// A client-name field that suggests existing clients as you type.
///
/// Extracted from `ClientPickerField`, which pairs the name with the client's
/// own phone and fills both when one is picked. A support case cannot use that
/// pairing: the phone on a case belongs to the contact person, not to the
/// client. What both screens do share is this — the suggestions, the dropdown,
/// and how a client is shown in it — so that is what lives here, and each
/// screen decides for itself what picking one should fill in.
class ClientNameAutocomplete extends StatelessWidget {
  const ClientNameAutocomplete({
    super.key,
    required this.clients,
    required this.controller,
    required this.focusNode,
    required this.onSelected,
    this.label = 'Cliente',
    this.validator,
  });

  final List<ClientModel> clients;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<ClientModel> onSelected;
  final String label;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return RawAutocomplete<ClientModel>(
      textEditingController: controller,
      focusNode: focusNode,
      optionsBuilder: (textValue) {
        final query = textValue.text.trim().toLowerCase();
        if (query.isEmpty) return const Iterable<ClientModel>.empty();
        return clients
            .where((c) => c.name.toLowerCase().contains(query))
            .take(6);
      },
      displayStringForOption: (c) => c.name,
      onSelected: onSelected,
      fieldViewBuilder: (context, textController, node, onFieldSubmitted) {
        return TextFormField(
          controller: textController,
          focusNode: node,
          style: TextStyle(color: colors.textPrimary),
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(LucideIcons.userCircle, color: colors.primary),
          ),
          validator: validator,
        );
      },
      optionsViewBuilder: (context, onOptionSelected, options) {
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
                    title: Text(
                      option.name,
                      style: TextStyle(color: colors.textPrimary),
                    ),
                    subtitle: option.phone.isEmpty
                        ? null
                        : Text(
                            Validators.formatPhone(option.phone),
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                    onTap: () => onOptionSelected(option),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
