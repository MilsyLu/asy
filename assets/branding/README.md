# assets/branding/

Carpeta centralizada para los recursos de marca de **CheCu**.

## logo_checu.png (Sprint 7.3.2B) — fuente oficial

Logo oficial (1146×1146, PNG con esquinas redondeadas transparentes, relleno
`#F5F1E8`, trazo `#1A234A`). Es la única fuente de imagen de la marca. Se usa
directamente para:

- `flutter_launcher_icons` (`pubspec.yaml`) → Android (`mipmap-*`) e iOS
  (`ios/Runner/Assets.xcassets/AppIcon.appiconset`). Para iOS se aplana el
  canal alfa (`remove_alpha_ios` + `background_color_ios: "#F5F1E8"`), ya que
  Apple no acepta íconos con transparencia.
- `lib/widgets/brand_logo.dart` (`BrandLogo`) → el círculo con borde
  institucional que muestran tanto Login como `_BootSplash`
  (`lib/app.dart`), con animación tipo "moneda" en este último.

## logo_checu_splash.png y logo_checu_splash_android12.png (Sprint 7.3.2D)

**No son un logo nuevo ni un rediseño**: son copias redimensionadas de
`logo_checu.png` (mismos píxeles, mismas proporciones), generadas porque
`flutter_native_splash` no tiene ningún parámetro de tamaño/escala — su README
indica textualmente que la imagen "should be sized for 4x pixel density", y su
código calcula el tamaño lógico en pantalla como `ancho_del_PNG / 4`. Usar el
master de 1146px directamente producía un logo de ~286dp/286pt en el splash
nativo (gigante). Por eso:

- `logo_checu_splash.png` (384×384): usado en `image`/`image_dark` para
  Android legacy (`mdpi`…`xxxhdpi`) e iOS. 384/4 = 96dp/96pt, la misma
  presencia visual que `BrandLogo` en el BootSplash.
- `logo_checu_splash_android12.png` (1152×1152, logo centrado en una zona
  segura de 700×700): usado en `android_12.image`/`image_dark`. Android 12+
  enmascara automáticamente el tercio exterior del ícono del splash, así que
  necesita un margen transparente real alrededor del contenido visible —
  cosa que el master de 1146px no tiene (su contenido llega casi al borde).

Si el logo oficial cambia, regenerar todo con:

```bash
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

y volver a derivar `logo_checu_splash.png` / `logo_checu_splash_android12.png`
desde el nuevo `logo_checu.png` (resize directo a 384×384 para el primero;
logo escalado a ~700×700 centrado en un lienzo transparente de 1152×1152 para
el segundo).

## Pendiente

- El ícono adaptativo de Android (foreground/background separados) no se usa
  porque el proyecto no lo tenía configurado antes y el logo es una sola
  imagen ya aplanada; si se quiere adaptativo en el futuro, se necesitará un
  foreground separado (solo el ícono, sin el fondo redondeado) entregado por
  quien diseñe la marca.
