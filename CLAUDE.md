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

## Despliegue y actualización de CheCu

Firebase project id: **`chhecu`** (Hosting URL: `https://chhecu.web.app`). No
`.firebaserc` is committed, so every command below is explicit with
`--project chhecu`.

**Autenticación (desde 2026-07-22):** este equipo tiene una cuenta de
servicio de Google Cloud (`checu-deploy@chhecu.iam.gserviceaccount.com`, rol
**Firebase Hosting Admin** únicamente — no acceso total al proyecto) con su
clave JSON guardada fuera del repo en
`C:\Users\ASUS\.checu-deploy\service-account.json`, y la variable de entorno
de usuario `GOOGLE_APPLICATION_CREDENTIALS` apuntando a esa ruta. Con eso,
`firebase deploy` se autentica solo — **ya no hace falta pasar `--token` ni
pedirle un token a Michel en cada sesión.** Ese archivo `.json` es una
credencial: nunca debe copiarse dentro del repo ni subirse a ningún lado. Si
en algún momento deja de funcionar (p. ej. equipo nuevo), hay que repetir el
flujo de creación de cuenta de servicio en
`https://console.cloud.google.com/iam-admin/serviceaccounts?project=chhecu`
y volver a apuntar la variable de entorno al nuevo archivo — no volver al
flujo de token CI salvo que Michel lo pida explícitamente.

### 1. Flujo de despliegue

Orden correcto, de punta a punta:

1. **Bump de versión en el código** — editar
   `AppConstants.appVersion` en
   [`lib/core/constants/app_constants.dart`](lib/core/constants/app_constants.dart:66)
   (ej. `'1.0'` → `'1.1'`). Esta es la versión que el propio cliente reporta y
   compara contra Firestore — **no** confundir con el campo `version:` de
   `pubspec.yaml` (ese solo alimenta el `version.json` autogenerado por
   Flutter y **no** participa en la lógica de actualización).
2. **Compilar la versión Web:**
   ```bash
   flutter build web --release
   ```
3. **Desplegar Firebase Hosting:**
   ```bash
   firebase deploy --only hosting --project chhecu
   ```
   Esto sube el contenido de `build/web/`, incluyendo el
   `flutter_service_worker.js` recién generado (su contenido cambia con cada
   build porque incluye un hash de los assets — eso es lo que el navegador de
   cada cliente detecta como "hay una versión nueva").
4. **Actualizar la versión remota en Firestore** —
   documento `systemConfig/settings`, campo `appVersion` (string), mismo valor
   que el paso 1 (ej. `'1.1'`). Hoy **no existe una pantalla en la app** para
   editar este campo — se hace desde la **Firebase Console** (Firestore
   Database → `systemConfig` → `settings` → editar/crear el campo `appVersion`)
   o vía Admin SDK/script. (Sí es editable por un `super_admin` a través del
   SDK cliente si se automatiza — `firestore.rules` permite
   `write` en `systemConfig/*` a `isSuperAdmin()` — pero no hay UI para eso
   todavía.) **Este paso es un acelerador, no un requisito**: si se omite, los
   clientes ya abiertos igual detectan la actualización por el Service Worker
   en un máximo de 5 minutos (ver sección 2).
5. **Verificar:** abrir `https://chhecu.web.app` en una pestaña nueva/incógnito
   y confirmar que **Configuración → Acerca de** (`_AboutRow(label: 'Versión', …)`
   en
   [`settings_page.dart`](lib/screens/profile/settings_page.dart:801)) y el pie
   del sidebar (`AppConstants.appVersion` en `main_shell.dart`) muestran la
   versión nueva.

### 2. Cómo funciona el botón "Actualizar ahora"

El mecanismo vive en tres archivos:
[`lib/services/app_update_service.dart`](lib/services/app_update_service.dart)
(orquestación Dart, con doc-comment detallado ya en el propio archivo),
[`lib/services/app_update_web.dart`](lib/services/app_update_web.dart) /
[`app_update_stub.dart`](lib/services/app_update_stub.dart) (puente JS
interop condicional — el stub es un no-op en Android/iOS/desktop) y
[`web/index.html`](web/index.html) (el script que realmente habla con el
Service Worker del navegador). `UpdateBanner`
([`lib/widgets/update_banner.dart`](lib/widgets/update_banner.dart)) es solo
presentación: escucha `AppUpdateService` vía `Provider` y no contiene lógica
de actualización.

**Detección — dos capas independientes, cualquiera de las dos puede disparar el banner:**

- **Capa 1 — Firestore (instantánea):** `AppUpdateService._startFirestoreWatch()`
  suscribe un stream a `systemConfig/settings`. Cada snapshot compara
  `data['appVersion']` (remoto) contra `AppConstants.appVersion` (local,
  compilado en el bundle) segmento por segmento
  (`_isRemoteNewer`, comparación numérica tipo semver simplificado). Si el
  remoto es mayor, `_markUpdate(remote)` pone `showBanner = true` de
  inmediato — no hay que esperar nada, la pestaña abierta reacciona en cuanto
  Firestore empuja el cambio.
- **Capa 2 — Service Worker (respaldo, hasta 5 min):** el script inline en
  `web/index.html` **parchea `navigator.serviceWorker.register` antes** de que
  `flutter_bootstrap.js` se cargue (por eso el `<script>` inline va primero en
  el `<body>` y el de Flutter último), para poder observar el registro del SW
  propio de Flutter (`flutter_service_worker.js`; el SW de FCM en
  `firebase-messaging-sw.js` se excluye explícitamente por scope en todos los
  puntos donde se filtra). Cuando ese SW nuevo llega a estado `installed` **y**
  ya existe un `navigator.serviceWorker.controller` (es decir, esto es una
  actualización, no la primera instalación), pone
  `window.__checu_sw_update_waiting = true`. `AppUpdateService` arranca un
  `Timer.periodic` de 5 minutos que lee ese flag (`_checkSw`), y además el
  script pide un `reg.update()` cada vez que la pestaña vuelve a foco
  (`visibilitychange`), así que en la práctica casi nunca se espera el
  timer completo — basta con volver a la pestaña.

**Qué pasa al aparecer el banner:** `UpdateBanner` reacciona al cambio de
`showBanner` con un `AnimatedSwitcher` (fade + collapse). Layout horizontal en
tablet/desktop, apilado en móvil. Muestra la versión remota si vino de
Firestore (`(v1.1)`); si vino solo del SW (`_markUpdate(null)`), el texto
omite el número de versión. El usuario puede descartarlo (`dismiss()`, solo
oculta hasta el próximo cambio de versión) o pulsar **"Actualizar ahora"**.

**Qué hace exactamente el botón:** `UpdateBanner._onUpdate` llama
`service.activateUpdate()` → en web, `activateWebUpdate()` invoca
`window.__checu_activate_update()` (definida en `index.html`). Esa función:

1. Lista todos los `ServiceWorkerRegistration` del origen.
2. Para cada uno que **no** sea el scope de FCM y tenga `reg.waiting`, le
   envía `postMessage('skipWaiting')` — el string exacto que el
   `flutter_service_worker.js` generado por Flutter ya sabe interpretar
   internamente para llamar `self.skipWaiting()`.
3. Si encontró al menos un worker esperando, se suscribe una sola vez al
   evento `controllerchange` (se dispara cuando el nuevo SW toma control de
   la página) y **entonces** hace `window.location.reload()`. Hay un
   `setTimeout` de 3 s como respaldo por si `controllerchange` nunca llega en
   algún navegador.
4. Si no había ningún worker esperando (p. ej. el SW ya se activó solo, o no
   hay SW soportado), simplemente recarga la página.

**Cuándo desaparece el banner:** al recargar, la app arranca de nuevo con el
bundle nuevo → `AppConstants.appVersion` ya coincide (o supera) el valor de
Firestore → `_isRemoteNewer` da `false` → el banner nunca se vuelve a mostrar
para esa versión.

### 3. Validación del sistema

Procedimiento para comprobar que funciona de punta a punta:

1. Abrir `https://chhecu.web.app` en una pestaña y dejarla abierta.
2. Con la app abierta ahí, hacer un deploy real: bump de
   `AppConstants.appVersion`, `flutter build web --release`,
   `firebase deploy --only hosting --project chhecu`.
3. Actualizar `systemConfig/settings.appVersion` en Firestore Console al
   mismo valor nuevo (para probar la Capa 1; para probar la Capa 2 sola,
   omitir este paso y esperar hasta 5 min o cambiar de pestaña y volver).
4. En la pestaña que quedó abierta, esperar la detección (con Firestore
   actualizado debería ser casi instantánea; solo por SW, hasta 5 min o al
   volver a la pestaña).
5. Confirmar que aparece el banner "Nueva versión disponible".
6. Pulsar "Actualizar ahora".
7. Confirmar que, **sin usar Ctrl+F5 ni limpiar caché**, la app recarga sola y
   **Configuración → Acerca de** ya muestra la versión nueva.

**Ejecutado parcialmente en esta sesión** (con autorización explícita del
usuario, usando un token CI generado por él vía `firebase login:ci`):

- Pasos 1–2 ✅: `AppConstants.appVersion` → `'1.4'`, `flutter build web
  --release` (compiló sin errores), `npx firebase-tools deploy --only
  hosting --project chhecu --token …` → `Deploy complete!`. Se verificó en
  una pestaña nueva que `https://chhecu.web.app` sirve el build nuevo (logs
  de consola `first_frame`/`startup_complete`, todos los assets — incluido
  `logo_checu.png` — responden 200).
- Paso 3 ⏳ **pendiente**: no se pudo actualizar
  `systemConfig/settings.appVersion` de forma programática. El token de
  `login:ci` es un *refresh token* de OAuth de firebase-tools, no un access
  token utilizable directamente contra la API REST de Firestore
  (`ACCESS_TOKEN_TYPE_UNSUPPORTED` al intentarlo) — firebase-tools lo
  intercambia internamente, pero no expone ese intercambio como comando
  suelto, y el proyecto no tiene `scripts/seed/serviceAccountKey.json`
  (gitignored) para usar el Admin SDK. Queda para quien lea esto: entrar a
  Firebase Console → Firestore Database → `systemConfig` → `settings` →
  poner `appVersion` = `"1.4"` (string), o generar la service account key y
  usar el Admin SDK.
- Pasos 4–7 ⏳ **no observados en vivo**: no había una pestaña *previa* al
  deploy (con la versión vieja) para observar la transición banner → clic →
  recarga en tiempo real. La Capa 2 (Service Worker) debería seguir
  disparando el banner igual dentro de los primeros 5 minutos para cualquier
  pestaña que ya estuviera abierta antes de este deploy, sin necesidad del
  paso 3 — pero eso no se confirmó por observación directa.

### 4. Problema encontrado

Revisando el código para escribir esta documentación encontré una
inconsistencia menor (no un bug funcional confirmado, pero sí un defecto real
de consistencia):

- **Causa raíz:** en `web/index.html`, la función `watchReg()` y el listener
  de `visibilitychange` excluyen explícitamente el scope de FCM
  (`firebase-cloud-messaging-push-scope`) al recorrer
  `getRegistrations()`, pero `window.__checu_activate_update()` **no** tenía
  ese mismo filtro — recorría *todos* los registros y enviaba
  `postMessage('skipWaiting')` a cualquiera con `.waiting`, incluido en
  teoría el Service Worker de FCM si alguna vez tuviera una versión esperando
  al mismo tiempo. En la práctica es casi seguro inofensivo (el SW de FCM
  generado por Firebase no registra un listener de `message` para strings
  arbitrarios, así que el mensaje se pierde sin efecto), pero es una
  inconsistencia real frente al resto del archivo y una fuente de bugs
  sutiles si el SW de FCM cambia en el futuro.
- **Archivo corregido:** [`web/index.html`](web/index.html) — se añadió el
  mismo filtro de scope dentro de `__checu_activate_update()`.
- **Cómo se verificó:** revisión de código únicamente (lectura línea por
  línea de las tres capas del mecanismo). **No se ejecutó la validación en
  vivo** descrita en la sección 3 — eso requiere un deploy real a producción,
  que no se hizo en esta sesión.

**Segundo hallazgo, más importante — cache HTTP en `main.dart.js` /
`index.html` / `/` (confirmado en producción, no solo por lectura de código):**

Después del primer deploy de esta sesión, el usuario reportó en vivo que
`chhecu.web.app` seguía mostrando el diseño viejo incluso después de pulsar
"Actualizar ahora" **y** hacer Ctrl+Shift+R / Ctrl+F5 varias veces.

- **Verificación:** se descargó `main.dart.js` directamente desde
  `https://chhecu.web.app/main.dart.js` (fuera de cualquier navegador/caché
  de usuario) y sí contenía el código nuevo (strings únicos del rediseño
  como `"Listado de órdenes"` y `"CONTACTO"` aparecían en el bundle). Esto
  descartó un problema de build/deploy — el servidor tenía lo correcto.
- **Causa raíz:** `firebase.json` solo declaraba `Cache-Control: no-cache`
  para `flutter_service_worker.js` y `firebase-messaging-sw.js`. Ni
  `main.dart.js`, ni `index.html`, ni la ruta raíz `/` tenían esa cabecera —
  Firebase Hosting los servía con su default (`Cache-Control: max-age=3600`,
  confirmado con `Invoke-WebRequest -Method Head` contra producción). El
  `flutter_service_worker.js` que genera esta versión de Flutter para este
  proyecto **no** es el service worker clásico con precacheo — es el
  "placeholder" que Flutter emite cuando no hay estrategia de PWA real: en
  `install` llama `self.skipWaiting()` de inmediato (nunca queda en estado
  `waiting` esperando confirmación) y en `activate` se auto-desregistra y
  fuerza `client.navigate()` en todas las pestañas abiertas. Sin ningún
  service worker real cacheando contenido, la única capa de cacheo que queda
  es la caché HTTP normal del navegador — y con `max-age=3600` sin la
  cabecera correcta, `main.dart.js`/`index.html` podían servirse desde esa
  caché hasta por una hora. Combinado con un service worker *residual* de un
  deploy anterior aún activo en el navegador del usuario (que sí puede
  interceptar peticiones **antes** de que el navegador consulte la caché
  HTTP o la red, ignorando incluso Ctrl+F5), esto explica el síntoma
  reportado.
- **Archivo corregido:** [`firebase.json`](firebase.json) — se agregaron
  reglas `Cache-Control: no-cache, no-store, must-revalidate` para
  `/index.html`, `/`, `/main.dart.js`, `/flutter_bootstrap.js` y
  `/version.json` (antes solo cubría los dos service workers). Nota:
  `/index.html` como patrón **no** cubre la ruta `/` en Firebase Hosting
  pese al rewrite de SPA (`"source": "**" → "/index.html"`) — el
  emparejamiento de `headers` se hace contra la ruta solicitada, no contra
  el destino del rewrite. Hay que declarar `/` explícitamente también.
- **Cómo se verificó:** redeploy de solo `hosting` (dos veces — la primera
  corrigió `main.dart.js`/`index.html`, se detectó que `/` seguía en
  `max-age=3600` y se corrigió en un segundo redeploy) y confirmación con
  `Invoke-WebRequest -Method Head` contra `https://chhecu.web.app/` y
  `https://chhecu.web.app/main.dart.js` mostrando
  `Cache-Control: no-store, must-revalidate, no-cache` en ambos.
- **Lo que esto NO arregla por sí solo:** si el navegador del usuario ya
  tiene un service worker *activo* de un deploy anterior controlando la
  página, ningún cambio de cabecera en el servidor lo va a desalojar — un
  service worker responde a `fetch` antes de que el navegador siquiera mire
  la caché HTTP o la red. Ese navegador puntual necesita una de estas dos
  acciones (ver sección 5):
  1. Abrir el sitio en una ventana de incógnito/privada (sin service worker
     registrado ahí) para confirmar que el contenido nuevo sí carga.
  2. En el navegador normal: DevTools (F12) → pestaña **Application** →
     **Service Workers** → "Unregister" sobre cualquier entrada de
     `chhecu.web.app` → recargar.

No se encontraron otros defectos funcionales en la lógica de detección o
activación por revisión de código; el patrón usado (parchear `register()`,
`postMessage('skipWaiting')`, esperar `controllerchange`) es el estándar
recomendado para Service Workers y coincide con lo que el SW generado por
Flutter espera recibir. Dado que el service worker real de Flutter está en
modo "sin caché" para este proyecto (ver hallazgo anterior), la Capa 2
(sección 2) rara vez encontrará un worker genuinamente en estado `waiting` —
en la práctica, `window.__checu_activate_update()` casi siempre caerá en su
rama de respaldo (`window.location.reload()` simple), lo cual ahora es
correcto y suficiente porque ya no hay cacheo agresivo de por medio.

### 5. Estado final

**Parcialmente confirmado — el despliegue y el arreglo de caché están en
producción; falta la confirmación visual final de un usuario real.** Esta
sesión ejecutó dos despliegues reales a `chhecu`: el primero con el
rediseño (versión `1.4`), el segundo con la corrección de `Cache-Control`.
Se confirmó por fuera del navegador (descarga directa de `main.dart.js` y
cabeceras HTTP) que el servidor sirve exactamente lo esperado. Lo único que
falta es que el usuario confirme visualmente que su navegador ya muestra el
diseño nuevo — para lo cual, si su navegador tiene un service worker
residual atascado (síntoma observado: ni el botón ni Ctrl+F5 lo resuelven),
necesita el paso manual de incógnito o "Unregister" descrito arriba antes de
que el problema de caché quede resuelto para *esa* pestaña específica. Para
cualquier visitante nuevo (o que no tuviera ya un service worker viejo
activo), el fix de `Cache-Control` debería ser suficiente sin pasos
manuales.

Falta, en orden de lo que más acerca a "confirmado":

1. Que el usuario pruebe incógnito o desregistre el service worker en su
   navegador actual, y confirme que ve el diseño nuevo.
2. Actualizar `systemConfig/settings.appVersion` a `'1.4'` en Firestore
   Console (2 minutos) — mostrado en la captura del usuario, ya podría estar
   hecho.
2. Con una pestaña de CheCu que haya estado abierta desde *antes* de este
   deploy (por ejemplo, la del propio usuario en su navegador), confirmar que
   el banner aparece y que "Actualizar ahora" recarga sola a la versión
   nueva, sin Ctrl+F5.

Los prerequisitos técnicos (headers `no-cache` en
`flutter_service_worker.js`/`firebase-messaging-sw.js` en `firebase.json`, y
el filtro de scope corregido en la sección 4) ya están en producción.
