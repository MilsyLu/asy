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

## android/app/src/main/res/drawable-*dpi/ic_notification.png (Sprint 7.3.3)

Icono de notificación de Android (barra de estado), derivado de
`logo_checu.png`. **No es el launcher icon ni un asset nuevo**: Android
exige que los iconos de notificación sean una silueta monocromática
(blanco puro sobre fondo transparente) — el sistema ignora el color real
de los píxeles y solo usa el canal alfa para pintar el icono (con un tinte
configurable vía `default_notification_color` / `notification_gold` en
`colors.xml`, aplicado en la bandeja expandida). Usar directamente
`logo_checu.png` (a todo color) producía un bloque blanco sin forma
reconocible en la barra de estado.

Generado con un script Dart de un solo uso (`package:image`, no es una
dependencia del proyecto) que:

1. Convierte el trazo navy (`#1A234A`) del logo en blanco sólido sobre
   transparencia, usando luminancia para conservar el anti-aliasing.
2. Separa por componentes conexos y descarta el anillo exterior fino del
   logo (el aro "insignia" que rodea el círculo+check) — a 24-96px ambos
   círculos concéntricos colapsan en una mancha ilegible, así que solo se
   conserva el glifo interior (círculo + check).
3. Recorta y centra ese glifo en un lienzo cuadrado con ~17% de margen
   transparente por lado (convención de Android para iconos pequeños:
   contenido ≈66% del lienzo).
4. Exporta a los 5 buckets de densidad: `drawable-mdpi` (24px),
   `-hdpi` (36px), `-xhdpi` (48px), `-xxhdpi` (72px), `-xxxhdpi` (96px).

Usado por `com.google.firebase.messaging.default_notification_icon`
(`AndroidManifest.xml`) y por los 3 sitios de `notification_service.dart`
que referencian `@drawable/ic_notification` (inicialización de
`flutter_local_notifications`, notificación en foreground, recordatorio
programado) — los tres deben apuntar siempre al mismo recurso. Si el logo
oficial cambia, regenerar repitiendo el mismo proceso (luminancia → mayor
componente conexo descartado → recorte centrado con margen ~17%) sobre el
nuevo `logo_checu.png`.

## Pendiente

- El ícono adaptativo de Android (foreground/background separados) no se usa
  porque el proyecto no lo tenía configurado antes y el logo es una sola
  imagen ya aplanada; si se quiere adaptativo en el futuro, se necesitará un
  foreground separado (solo el ícono, sin el fondo redondeado) entregado por
  quien diseñe la marca.
