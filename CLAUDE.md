# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

TaskFlow Executive: a Flutter + Firebase task-scheduling app for work teams, with a
dark "executive dashboard" theme, role-based access (`super_admin` /
`trabajador_normal`), push notifications, and CSV reports. Spanish is the primary
app locale (`es`).

## Commands

```bash
# Install dependencies
flutter pub get

# Static analysis (must report "No issues found!")
flutter analyze

# Run all tests
flutter test

# Run a single test file
flutter test test/validators_test.dart

# Run the app (mobile/emulator)
flutter run

# Run as web/PWA
flutter run -d chrome

# Release builds
flutter build apk --release
flutter build ios --release   # requires macOS + Xcode
```

### Cloud Functions (`functions/`)

```bash
cd functions
npm install
npm run serve        # local emulator
firebase deploy --only functions
```

### Firestore rules / indexes

```bash
firebase use <project-id>
firebase deploy --only firestore:rules,firestore:indexes
```

### Seed script (`scripts/seed/`)

Creates base catalogs (`taskTypes`, `statuses`, `availableHours`, `groups`) and,
optionally, the first `super_admin` user. Requires
`scripts/seed/serviceAccountKey.json` (gitignored, generated from Firebase Console
→ Project settings → Service accounts).

```bash
cd scripts/seed
npm install
npm run seed   # idempotent: skips catalog entries that already exist by name/hour
```

## Architecture

### Dependency injection (`lib/app.dart`)

`TaskFlowApp` wires repositories and providers via `MultiProvider`:

- Plain `Provider<T>`: `AuthService`, `UserRepository`, `TaskRepository`,
  `CatalogRepository` — stateless Firestore/Auth wrappers.
- `ChangeNotifierProvider<AuthProvider>` — tracks `firebaseUser`/`appUser`
  (Firestore `users/{uid}` doc), `isLoading`, `isAuthenticated`, `isSuperAdmin`,
  and registers/cleans up the FCM token on login/logout.

**`CatalogProvider` scoping (important gotcha):** `CatalogProvider` (caches
`groups`/`taskTypes`/`statuses`/`availableHours`/`users` for ID→name lookups) is
provided from `MaterialApp`'s `builder` callback, *wrapping the Navigator*, keyed
by `ValueKey(user.id)` and only created once `AuthProvider.appUser` is non-null.

This is deliberate: `home` and any `Navigator.push`'d route are **sibling**
Overlay entries, not ancestor/descendant — a provider placed inside `home` (e.g.
under `AuthGate`/`MainShell`) is invisible to pushed pages like
`AddEditTaskPage`, `GroupsPage`, `StatusesPage`, `TaskTypesPage`,
`AvailableHoursPage`, `UsersPage`, etc. Wrapping the Navigator via `builder` is
the only placement that covers `home` *and* every pushed route/dialog. The
`ValueKey(user.id)` rebuilds (and disposes/recreates) `CatalogProvider` across
login/logout/user switches. Do not move `CatalogProvider` back under `home` or
re-add a separate instance higher up (e.g. in `main.dart`) — that previously
caused duplicate, auth-lifecycle-disconnected instances and "Could not find the
correct Provider<CatalogProvider>" errors on pushed admin/task screens.

### Repository pattern (`lib/services/`)

Each Firestore collection has a thin repository (`TaskRepository`,
`CatalogRepository`, `UserRepository`) exposing `watchX()` streams and
CRUD/query methods built on `FirebaseFirestore.instance`. `AuthService` wraps
`firebase_auth`. `NotificationService` (singleton, `.instance`) wraps
`flutter_local_notifications` + FCM token/foreground-message handling.

Collection names live in `lib/core/constants/firestore_paths.dart`
(`FirestoreCollections`). Well-known catalog *values* used by business logic
(not just display) live in `lib/core/constants/app_constants.dart`:

- `AppRoles.superAdmin` / `AppRoles.trabajadorNormal`
- `AppStatusNames.pendiente` / `.completada` / `.reprogramada` — matched
  case-insensitively against `statuses` docs via `CatalogProvider.statusByName()`
  to get `pendingStatusId` / `completedStatusId` / `rescheduledStatusId`
- `AppTaskTypeNames.instalacion`

### Role/group task visibility

`lib/core/utils/task_visibility.dart` (`isTaskVisibleToUser`) is the single
source of truth for the client-side privacy rule:

- `super_admin` with no `groupId` → sees every task.
- Any user with a `groupId` → sees tasks assigned to members of that same group
  (resolved via `CatalogProvider.userById`).
- User with no `groupId` (non-admin) → sees only their own tasks.

`firestore.rules` (`canAccessTask()`) mirrors this exact logic server-side for
`tasks` reads/writes. **If you change one, change the other** — the rules are
the enforcement layer; the Dart function is what drives UI filtering.

### Navigation / screens

`MainShell` (`lib/screens/main_shell.dart`) is the post-login root: a
`Scaffold` with `AppDrawer`, a bottom nav (`IndexedStack` of Home/Calendar/Week/
[Reports if `isSuperAdmin`]/Profile), and tab titles computed with an
admin-dependent index offset since the Reports tab is conditionally inserted.
Admin-only screens (`lib/screens/admin/*`: groups, task types, statuses,
available hours, users) and `AddEditTaskPage` are reached via `Navigator.push`
from the drawer/home — see the `CatalogProvider` note above before changing how
these are presented (e.g. switching to named routes, nested navigators, etc.).

### Firebase setup specifics

- `lib/firebase_options.dart` ships with placeholder values; regenerate via
  `flutterfire configure` before running against a real project.
- Android: `minSdk = 23` (Firebase Auth requirement);
  `isCoreLibraryDesugaringEnabled = true` + `coreLibraryDesugaring` dependency in
  `android/app/build.gradle.kts` (required by `flutter_local_notifications`).
  FCM notification channel id is `taskflow_high_importance`.
- iOS: `Runner.entitlements` (APNs) is wired via `CODE_SIGN_ENTITLEMENTS` in
  `project.pbxproj` for Debug/Release/Profile on the Runner target; Background
  Modes → Remote notifications must also be enabled in Xcode.
- `functions/` (Cloud Functions v2, `firebase-admin` modular SDK):
  `onTaskCreate` pushes a notification to the assigned user on task creation;
  `checkReminders` (`onSchedule`, every minute) sends reminders for tasks where
  `reminderTime` has passed and `reminderSent == false`.

### Theme

`lib/core/theme/app_colors.dart` / `app_theme.dart` define the dark
gold-accented palette (`AppColors.background`, `.gold`, etc.) used throughout
`AppTheme.darkTheme`, the only theme (the app is always dark mode).
