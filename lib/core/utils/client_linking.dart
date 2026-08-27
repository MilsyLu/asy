import '../../models/client_model.dart';
import '../../providers/catalog_provider.dart';
import '../../services/catalog_repository.dart';
import 'validators.dart';

/// Todo cliente de [clients] cuyo nombre coincide con [name], sin distinguir
/// mayúsculas y sin espacios de sobra.
///
/// Función libre y no un método de `CatalogProvider` para que se pueda probar:
/// el provider abre Firestore en su constructor. Es la misma separación que se
/// hizo con las métricas del Dashboard — la decisión es pura, sólo estaba
/// enterrada detrás de algo que no se puede construir en una prueba.
///
/// Devuelve una lista y no un cliente: dos negocios reales pueden llamarse
/// igual, y quien llame tiene que decidir qué hacer con eso en vez de recibir
/// uno cualquiera de los dos.
List<ClientModel> clientsMatchingName(List<ClientModel> clients, String name) {
  final n = name.trim().toLowerCase();
  if (n.isEmpty) return const [];
  return [
    for (final c in clients)
      if (c.name.trim().toLowerCase() == n) c,
  ];
}

/// Links what somebody typed to a real `clients/{id}` record, creating one if
/// there is nothing to link to.
///
/// This is what makes the client list fill itself from ordinary work instead
/// of having to be maintained by hand: every task — and now every support
/// case — leaves its client behind as a record.
///
/// It lived twice, copy-pasted into `add_edit_task_page.dart` and
/// `task_create_panel.dart`. Support cases needed it too, and a third copy is
/// how the three drift apart.
abstract final class ClientLinking {
  /// Task flow: an existing client is reused only when **name and phone**
  /// both match.
  ///
  /// Two businesses can genuinely share a name, and in a task the phone is
  /// the client's own, so it tells them apart.
  static Future<String?> forTask({
    required CatalogProvider catalog,
    required CatalogRepository repository,
    String? linkedId,
    required String name,
    required String phone,
  }) async {
    if (linkedId != null) return linkedId;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;

    final cleanPhone = Validators.cleanPhone(phone);
    final existing = catalog.clientByNameAndPhone(trimmed, cleanPhone);
    if (existing != null) return existing.id;
    return repository.addClient(trimmed, cleanPhone);
  }

  /// Support-case flow: matched by **name alone**.
  ///
  /// The phone on a case belongs to the contact person — "Ana at Little
  /// Italy" — not to the client. Matching on it the way tasks do would file a
  /// second "Little Italy" every time a different person reported something,
  /// which is exactly the split that made the Dashboard and Reportes disagree
  /// about the top client until it was fixed.
  ///
  /// A new client is created with the contact's phone anyway: a client record
  /// with no number at all is half a record, and that number is genuinely a
  /// way to reach them. When several clients already share the name, none is
  /// picked — guessing between two real businesses is worse than leaving the
  /// case unlinked, and the suggestions list lets the user choose exactly.
  static Future<String?> forSupportCase({
    required CatalogProvider catalog,
    required CatalogRepository repository,
    String? linkedId,
    required String clientName,
    required String contactPhone,
  }) async {
    if (linkedId != null) return linkedId;
    final trimmed = clientName.trim();
    if (trimmed.isEmpty) return null;

    final matches = catalog.clientsByName(trimmed);
    if (matches.length == 1) return matches.first.id;
    if (matches.length > 1) return null;

    return repository.addClient(trimmed, Validators.cleanPhone(contactPhone));
  }
}
