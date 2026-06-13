import '../../models/app_user.dart';
import '../../models/task_model.dart';
import '../../providers/catalog_provider.dart';

/// Centralizes the "tasks belong to a group, and may be shared across
/// groups" privacy rule. This is the single source of truth for
/// client-side task visibility — every screen/report must filter through
/// this function. `firestore.rules` (`canAccessTask()`) mirrors this exact
/// logic server-side; if you change one, change the other.
///
/// - `super_admin` sees every task, regardless of group.
/// - A task with `visibleToAllGroups == true` is visible to any signed-in
///   user.
/// - Otherwise a normal user sees the task only if `task.groupId` matches
///   their own `groupId`.
/// - Compatibility: tasks created before this feature have `groupId ==
///   null`. Those are only visible to `super_admin` until an admin assigns
///   them a group.
bool isTaskVisibleToUser({
  required TaskModel task,
  required AppUser user,
  required CatalogProvider catalog,
}) {
  if (user.isSuperAdmin) return true;

  if (task.groupId == null) return false;

  return task.visibleToAllGroups || task.groupId == user.groupId;
}
