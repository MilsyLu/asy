# assets/branding/

Carpeta centralizada para los recursos de marca de **CheCu** (Sprint 7.3.2A).

## Pendiente para el Sprint 7.3.2B

- `logo.png` (o `.svg`): logo oficial de CheCu. Reemplazará el círculo con el
  ícono `Icons.task_alt_rounded` usado hoy como marcador de posición en
  `lib/screens/auth/login_page.dart`.
- Variantes de resolución si se usa PNG (`logo@2x.png`, `logo@3x.png`).
- El ícono de launcher (Android `android/app/src/main/res/mipmap-*`) y el
  Splash screen se actualizan aparte, en ese mismo sprint — no en esta carpeta.

## Cómo registrar el archivo cuando exista

Agregar la ruta en `pubspec.yaml` bajo `flutter: assets:`, por ejemplo:

```yaml
flutter:
  assets:
    - assets/branding/logo.png
```

No se generan ni inventan imágenes en el Sprint 7.3.2A; esta carpeta solo
deja preparada la ubicación.
