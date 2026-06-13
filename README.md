# TaskFlow Executive

App de agendamiento de tareas para equipos de trabajo, con panel ejecutivo
oscuro, roles, notificaciones push y reportes con exportación a CSV.

- **Plataformas:** Android, iOS (y opcionalmente Web/PWA)
- **Stack:** Flutter + Provider, Firebase (Auth, Firestore, Cloud Messaging),
  Cloud Functions (Node.js)

---

## Tabla de contenidos

1. [Requisitos previos](#1-requisitos-previos)
2. [Configurar el proyecto de Firebase](#2-configurar-el-proyecto-de-firebase)
3. [Conectar la app con Firebase (FlutterFire CLI)](#3-conectar-la-app-con-firebase-flutterfire-cli)
4. [Reglas e índices de Firestore](#4-reglas-e-índices-de-firestore)
5. [Cloud Functions](#5-cloud-functions)
6. [Datos iniciales (seed)](#6-datos-iniciales-seed)
7. [Notificaciones push (Android e iOS)](#7-notificaciones-push-android-e-ios)
8. [Ejecutar la app](#8-ejecutar-la-app)
9. [Estructura del proyecto](#9-estructura-del-proyecto)
10. [Modelo de datos (Firestore)](#10-modelo-de-datos-firestore)
11. [Roles y privacidad](#11-roles-y-privacidad)
12. [Comandos útiles](#12-comandos-útiles)

---

## 1. Requisitos previos

- [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.41.x / Dart ^3.11.1
- [Node.js](https://nodejs.org/) 20.x (para Cloud Functions y el script de seed)
- [Firebase CLI](https://firebase.google.com/docs/cli): `npm install -g firebase-tools`
- [FlutterFire CLI](https://firebase.google.com/docs/flutter/setup):
  `dart pub global activate flutterfire_cli`
- Una cuenta de Firebase con un proyecto creado (plan **Blaze** es necesario
  para que las Cloud Functions puedan hacer llamadas salientes y usar
  `onSchedule`)
- Xcode (para compilar/ejecutar en iOS) y Android Studio / SDK (para Android)

---

## 2. Configurar el proyecto de Firebase

En la [consola de Firebase](https://console.firebase.google.com/):

1. **Crea un proyecto** (o usa uno existente).
2. **Authentication** → pestaña *Sign-in method* → habilita **Correo
   electrónico/contraseña**.
3. **Firestore Database** → crea la base de datos en modo **producción**
   (las reglas de seguridad incluidas en este repo controlan el acceso).
4. **Cloud Messaging** → no requiere configuración adicional para Android.
   Para iOS, sube tu **clave APNs** (Project settings → Cloud Messaging →
   Apple app configuration).
5. Anota el **ID del proyecto**, lo necesitarás para `firebase use`.

---

## 3. Conectar la app con Firebase (FlutterFire CLI)

El archivo [`lib/firebase_options.dart`](lib/firebase_options.dart) incluido
en este repo contiene **valores de ejemplo** (placeholders) para que el
proyecto compile sin errores. Antes de ejecutar la app contra tu proyecto
real, regenera ese archivo:

```bash
firebase login
flutterfire configure
```

Selecciona tu proyecto de Firebase y las plataformas **Android** e **iOS**
(y **Web** si vas a usar la PWA). Esto:

- Sobrescribe `lib/firebase_options.dart` con tus credenciales reales.
- Descarga `android/app/google-services.json`.
- Descarga `ios/Runner/GoogleService-Info.plist`.

> El proyecto Android ya tiene aplicado el plugin
> `com.google.gms.google-services` (ver
> [`android/app/build.gradle.kts`](android/app/build.gradle.kts)) y
> `minSdk = 23` (requerido por Firebase Auth), por lo que solo necesitas
> colocar el `google-services.json` generado.
>
> Para iOS, agrega `GoogleService-Info.plist` al target **Runner** desde
> Xcode (clic derecho sobre la carpeta `Runner` → *Add Files to "Runner"*),
> asegurándote de marcar la casilla **Copy items if needed** y el target
> **Runner**.

---

## 4. Reglas e índices de Firestore

Este repo incluye [`firestore.rules`](firestore.rules) y
[`firestore.indexes.json`](firestore.indexes.json), referenciados desde
[`firebase.json`](firebase.json).

```bash
firebase use <tu-project-id>
firebase deploy --only firestore:rules,firestore:indexes
```

Las reglas reflejan exactamente la lógica de privacidad por grupo del
cliente (`lib/core/utils/task_visibility.dart`):

- Un `super_admin` **sin grupo** ve y administra todo.
- Un usuario con `groupId` solo ve tareas asignadas a usuarios de su mismo
  grupo.
- Un usuario sin `groupId` (y que no es super admin) solo ve sus propias
  tareas.

---

## 5. Cloud Functions

El código está en [`functions/`](functions). Funciones incluidas:

- **`onTaskCreate`** (Firestore trigger): al crear una tarea, envía una
  notificación push al usuario asignado.
- **`checkReminders`** (Cloud Scheduler, cada 1 minuto): revisa tareas con
  `reminderTime` vencido y `reminderSent == false`, y envía el recordatorio
  push correspondiente.

Instalación y despliegue:

```bash
cd functions
npm install
cd ..
firebase deploy --only functions
```

Para probar localmente con el emulador:

```bash
cd functions
npm run serve
```

---

## 6. Datos iniciales (seed)

El script en [`scripts/seed/`](scripts/seed) crea los catálogos base
(`taskTypes`, `statuses`, `availableHours`, `groups`) y, opcionalmente, el
primer usuario `super_admin`.

1. En la consola de Firebase: **Project settings → Service accounts →
   Generate new private key**. Guarda el archivo como
   `scripts/seed/serviceAccountKey.json` (este archivo está en
   `.gitignore`, **nunca lo subas al repositorio**).
2. Instala dependencias y ejecuta:

   ```bash
   cd scripts/seed
   npm install

   # Opcional: crear también el primer super_admin
   # PowerShell:
   $env:SEED_ADMIN_EMAIL="admin@taskflow.com"
   $env:SEED_ADMIN_PASSWORD="CambiaEstaClave123!"
   $env:SEED_ADMIN_NAME="Administrador"

   npm run seed
   ```

El script es idempotente: si vuelves a ejecutarlo, omite los catálogos que
ya existen (comparando por `name` / `hour`) y reutiliza el usuario de Auth
si el correo del admin ya está registrado.

Catálogos creados por defecto:

| Colección        | Valores |
|-------------------|---------|
| `taskTypes`       | Instalación, Mantenimiento, Soporte, Visita técnica |
| `statuses`        | Pendiente, Completada, Reprogramada, Cancelada |
| `availableHours`  | 08:00 a 18:00 (cada hora) |
| `groups`          | Grupo Norte, Grupo Sur |

Puedes editar/ampliar estos catálogos después desde el **Panel de
administración** dentro de la app (solo `super_admin`).

---

## 7. Notificaciones push (Android e iOS)

### Android

Ya configurado en este repo:

- Permiso `POST_NOTIFICATIONS` (Android 13+) en
  [`AndroidManifest.xml`](android/app/src/main/AndroidManifest.xml).
- Canal de notificación por defecto (`taskflow_high_importance`), ícono y
  color (`@color/notification_gold`) para notificaciones FCM en segundo
  plano.

Solo falta colocar `google-services.json` (paso 3).

### iOS

1. En Xcode, abre `ios/Runner.xcworkspace`.
2. Selecciona el target **Runner** → pestaña **Signing & Capabilities**.
3. Agrega la capacidad **Push Notifications**.
4. Agrega la capacidad **Background Modes** y marca **Remote
   notifications** (esto ya está declarado en
   [`Info.plist`](ios/Runner/Info.plist), pero Xcode debe reconocer la
   capacidad para firmar correctamente).
5. El archivo [`ios/Runner/Runner.entitlements`](ios/Runner/Runner.entitlements)
   ya está creado y referenciado (`CODE_SIGN_ENTITLEMENTS`) para Debug,
   Release y Profile. Si usas un *provisioning profile* de producción,
   cambia `aps-environment` de `development` a `production`.
6. Sube tu **clave APNs** (.p8) al proyecto de Firebase (paso 2).

---

## 8. Ejecutar la app

```bash
flutter pub get
flutter run
```

Para web (PWA opcional):

```bash
flutter run -d chrome
```

---

## 9. Estructura del proyecto

```
lib/
  core/
    constants/      # nombres de colecciones, roles, estados/tipos conocidos
    theme/           # paleta de colores y ThemeData (modo oscuro ejecutivo)
    utils/           # fechas, validaciones, CSV, visibilidad de tareas
  models/            # AppUser, TaskModel, GroupModel, TaskTypeModel, ...
  services/          # AuthService, repos de Firestore, NotificationService
  providers/         # AuthProvider, CatalogProvider (Provider/ChangeNotifier)
  screens/
    auth/            # login, recuperar contraseña
    home/            # tareas de hoy, alta/edición de tarea
    calendar/        # vista mensual con conteo de tareas
    week/            # grilla hora x día (LUN-DOM)
    profile/         # estadísticas, racha, próximas tareas
    admin/           # grupos, tipos de tarea, estados, horarios, usuarios
    reports/         # 5 reportes + exportación CSV (solo super_admin)
  widgets/           # botones, diálogos, drawer, indicadores reutilizables

functions/           # Cloud Functions (onTaskCreate, checkReminders)
scripts/seed/        # script de datos iniciales (Node.js + firebase-admin)
firestore.rules
firestore.indexes.json
firebase.json
```

---

## 10. Modelo de datos (Firestore)

| Colección        | Descripción |
|-------------------|-------------|
| `users`           | Perfil, rol (`super_admin` / `trabajador_normal`), `groupId`, tokens FCM, racha de ingresos |
| `tasks`           | Tareas agendadas: fecha, hora, cliente, tipo, estado, usuario asignado, recordatorio |
| `groups`          | Grupos de trabajo (privacidad de tareas) |
| `taskTypes`       | Catálogo de tipos de tarea (ej. Instalación) |
| `statuses`        | Catálogo de estados (ej. Pendiente, Completada, Reprogramada) |
| `availableHours`  | Horarios disponibles para agendar tareas |

Consulta los modelos en [`lib/models/`](lib/models) para los campos exactos
de cada documento.

---

## 11. Roles y privacidad

- **`super_admin`**: acceso al panel de administración y a los reportes.
  - Sin `groupId`: ve y gestiona **todas** las tareas y usuarios.
  - Con `groupId`: ve las tareas de su grupo (igual que un trabajador, pero
    conserva acceso al panel de administración y reportes).
- **`trabajador_normal`**:
  - Con `groupId`: ve las tareas de todos los usuarios de su grupo.
  - Sin `groupId`: ve únicamente sus propias tareas.

Esta lógica está implementada en
[`lib/core/utils/task_visibility.dart`](lib/core/utils/task_visibility.dart)
(cliente) y reflejada en [`firestore.rules`](firestore.rules) (servidor).

---

## 12. Comandos útiles

```bash
# Análisis estático
flutter analyze

# Tests
flutter test

# Compilar APK de release
flutter build apk --release

# Compilar para iOS (requiere macOS + Xcode)
flutter build ios --release

# Desplegar reglas, índices y funciones
firebase deploy --only firestore:rules,firestore:indexes,functions
```
