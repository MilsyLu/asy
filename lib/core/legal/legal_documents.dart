/// Los textos legales de CheCu y su versión.
///
/// Viven en el código y no en Firestore a propósito: la versión que una
/// persona aceptó tiene que poder leerse tal como estaba el día que la
/// aceptó. Un texto editable en la base de datos se puede cambiar después
/// sin dejar rastro, y entonces el registro de aceptación deja de probar
/// nada — que es justo para lo que existe.
///
/// Para cambiar un documento: se edita el texto **y** se sube su versión.
/// Al subirla, a todo el mundo le vuelve a aparecer la pantalla de
/// aceptación, y queda un registro nuevo por cada persona.
library;

/// Quién responde legalmente por los datos.
///
/// Mientras CustoDesk no esté constituida como sociedad, el responsable del
/// tratamiento es una persona natural que opera bajo ese nombre comercial.
/// Es válido ante la Ley 1581 de 2012 — la ley habla de "personas naturales
/// o jurídicas" — y es la forma correcta de usar la firma CustoDesk sin
/// afirmar que existe una empresa que todavía no existe.
///
/// El día que se constituya la sociedad: se cambian estos cinco datos, se
/// sube la versión de los dos documentos y la app vuelve a pedir la
/// aceptación. No hay que tocar nada más.
abstract final class LegalResponsable {
  /// Nombre completo de la persona natural responsable.
  static const String nombre = '[PENDIENTE: nombre completo]';

  /// Cédula de ciudadanía. Identifica al responsable sin ambigüedad, que es
  /// lo que la ley pide; no es un dato sensible y va en la política.
  static const String documento = '[PENDIENTE: cédula]';

  /// La firma con la que salen los productos.
  static const String nombreComercial = 'CustoDesk';

  /// Domicilio. Fija ante qué autoridad y en qué ciudad se atiende un
  /// reclamo.
  static const String ciudad = '[PENDIENTE: ciudad]';

  /// El canal de atención al titular. Tiene que existir de verdad y ser
  /// revisado: la ley da plazos para contestar y empiezan a correr desde
  /// que llega el mensaje.
  static const String correo = '[PENDIENTE: correo de contacto]';

  /// Si falta algo por llenar. La pantalla legal lo usa para no publicar un
  /// documento a medias: una política con corchetes sin llenar es peor que
  /// no tenerla — dice por escrito que no se sabe quién responde.
  static bool get completo =>
      !nombre.startsWith('[') &&
      !documento.startsWith('[') &&
      !ciudad.startsWith('[') &&
      !correo.startsWith('[');
}

/// Un documento legal con su versión.
class LegalDoc {
  const LegalDoc({
    required this.id,
    required this.titulo,
    required this.version,
    required this.vigenteDesde,
    required this.cuerpo,
  });

  /// La clave con la que se guarda la aceptación. No cambia nunca.
  final String id;

  final String titulo;

  /// Subirla obliga a todo el mundo a aceptar de nuevo.
  final String version;

  final String vigenteDesde;

  /// El texto. `## ` abre un título, `- ` una viñeta, lo demás es párrafo
  /// (ver `legal_page.dart`).
  final String cuerpo;

  /// Cómo se identifica una aceptación concreta: documento y versión.
  String get clave => '${id}_v$version';
}

abstract final class LegalDocs {
  static const String idPolitica = 'politica_datos';
  static const String idTerminos = 'terminos_uso';

  static final LegalDoc politica = LegalDoc(
    id: idPolitica,
    titulo: 'Política de Tratamiento de Datos Personales',
    version: '1.0',
    vigenteDesde: '11 de noviembre de 2026',
    cuerpo: '''
## 1. Quién responde por sus datos

${LegalResponsable.nombre}, persona natural identificada con cédula de ciudadanía ${LegalResponsable.documento}, con domicilio en ${LegalResponsable.ciudad}, Colombia, quien desarrolla y opera CheCu bajo el nombre comercial ${LegalResponsable.nombreComercial}, es el Responsable del Tratamiento de los datos personales que se describen en esta política.

Correo de contacto para todo lo relacionado con datos personales: ${LegalResponsable.correo}

Esta política se expide conforme a la Ley 1581 de 2012, al Decreto 1074 de 2015 y a las demás normas colombianas sobre protección de datos personales.

## 2. Qué datos tratamos

De las personas que usan CheCu:

- Nombre y correo electrónico.
- Fotografía de perfil, si la persona decide subir una.
- Equipo o equipos a los que pertenece y el rol que tiene dentro de la empresa que la registró.
- Registros de uso: fecha y hora del último ingreso, días seguidos de uso, tareas creadas y completadas, y los avisos que se le enviaron.
- Identificadores técnicos del dispositivo o del navegador, necesarios para enviarle las notificaciones que haya aceptado recibir.

De las personas registradas como clientes dentro de CheCu por una empresa usuaria:

- Nombre y número de teléfono.
- El historial de tareas, casos de soporte y requerimientos asociados a ese cliente.

CheCu no pide ni almacena datos sensibles —salud, origen étnico, creencias, datos biométricos, orientación política o sexual—, ni datos de menores de edad, ni información financiera o de tarjetas de crédito.

## 3. Para qué los usamos

- Permitir el ingreso a la plataforma y mantener la cuenta de cada persona.
- Asignar, programar y hacer seguimiento a tareas, casos de soporte y requerimientos.
- Enviar los avisos del servicio: una tarea asignada, un recordatorio, una tarea completada, un requerimiento nuevo.
- Generar los informes y estadísticas que la propia empresa usuaria consulta sobre su operación.
- Atender preguntas, reclamos y soporte técnico.
- Cumplir obligaciones legales y atender requerimientos de autoridad competente.

Los datos no se venden, no se alquilan y no se usan para publicidad, ni propia ni de terceros.

## 4. Con qué autorización

Al ingresar a CheCu por primera vez, y cada vez que esta política cambie de versión, se le muestra este documento y se le pide aceptarlo de forma expresa. Esa aceptación queda registrada con la fecha, la hora y la versión aceptada, y es la prueba de la autorización exigida por la ley.

Si no desea otorgarla, no podrá usar la plataforma, porque sin tratar esos datos no hay forma de prestar el servicio. Puede revocar la autorización en cualquier momento escribiendo al correo de contacto, con el efecto descrito en el punto 8.

## 5. Los datos que cada empresa carga sobre sus propios clientes

CheCu es una plataforma que varias empresas usan de forma independiente. Cuando una empresa usuaria registra en CheCu los datos de sus clientes, esa empresa es el Responsable del Tratamiento de esos datos, y ${LegalResponsable.nombreComercial} actúa únicamente como Encargado: los almacena y los procesa siguiendo las instrucciones de la empresa, no los usa para fines propios y no los comparte con otras empresas usuarias.

Es obligación de cada empresa usuaria contar con la autorización de sus propios clientes antes de cargar sus datos en la plataforma, y tener su propia política de tratamiento.

## 6. Dónde se guardan

CheCu funciona sobre la infraestructura de Google (Firebase y Google Cloud Platform), con servidores ubicados en los Estados Unidos de América. Esto implica una transferencia internacional de datos.

Al aceptar esta política usted autoriza expresamente esa transferencia, en los términos del artículo 26 de la Ley 1581 de 2012. Google actúa como proveedor de infraestructura y está sujeto a sus propios compromisos contractuales de seguridad y confidencialidad.

## 7. Cuánto tiempo los conservamos

Mientras la cuenta esté activa y la empresa usuaria mantenga el servicio. Cuando una cuenta se elimina, sus datos personales se eliminan de la plataforma.

Se conservan por más tiempo, únicamente, los registros de aceptación de esta política y de los términos de uso, porque son la prueba de que la autorización existió y la ley exige poder demostrarlo.

## 8. Sus derechos

Como titular de sus datos personales, usted puede:

- Conocer, actualizar y rectificar sus datos.
- Solicitar prueba de la autorización que otorgó.
- Ser informado sobre el uso que se les ha dado.
- Presentar quejas ante la Superintendencia de Industria y Comercio por infracciones a la ley.
- Revocar la autorización y solicitar la supresión de sus datos, cuando no exista un deber legal o contractual que obligue a conservarlos. Tenga en cuenta que revocar la autorización implica no poder seguir usando la plataforma.
- Acceder de forma gratuita a sus datos.

## 9. Cómo ejercerlos

Escriba a ${LegalResponsable.correo} indicando su nombre, su correo registrado y lo que solicita.

- Las **consultas** se responden en un plazo máximo de diez (10) días hábiles. Si no es posible, se le informará el motivo y la fecha de respuesta, que no superará cinco (5) días hábiles adicionales.
- Los **reclamos** se atienden en un plazo máximo de quince (15) días hábiles, prorrogables por ocho (8) días hábiles más, informándole las razones.

## 10. Seguridad

El acceso a la plataforma está protegido con contraseña o con cuenta de Google. La información viaja cifrada y el acceso a los datos de cada empresa está separado del de las demás, de modo que una empresa no puede ver la información de otra. Dentro de cada empresa, cada persona ve únicamente lo que su rol le permite.

Ningún sistema es infalible. Si llegara a ocurrir un incidente que afecte sus datos, se le informará y se reportará a la autoridad competente conforme a la ley.

## 11. Menores de edad

CheCu es una herramienta de trabajo y no está dirigida a menores de edad. No se recogen intencionalmente sus datos.

## 12. Cambios a esta política

Esta política puede cambiar. Cuando cambie, se publicará la versión nueva y se le pedirá aceptarla de nuevo antes de seguir usando la plataforma, indicando desde cuándo rige.
''',
  );

  static final LegalDoc terminos = LegalDoc(
    id: idTerminos,
    titulo: 'Términos de Uso',
    version: '1.0',
    vigenteDesde: '11 de noviembre de 2026',
    cuerpo: '''
## 1. Qué es CheCu

CheCu es una plataforma de asignación y seguimiento de tareas, casos de soporte y requerimientos, desarrollada y operada por ${LegalResponsable.nombre}, bajo el nombre comercial ${LegalResponsable.nombreComercial}.

Estos términos regulan su uso. Al ingresar, usted los acepta.

## 2. Las cuentas

Las cuentas las crea la empresa que contrata el servicio, desde su propio panel de administración. No hay registro abierto al público.

Cada persona es responsable de su contraseña y de lo que se haga desde su cuenta. Si sospecha que alguien más tiene acceso, debe cambiarla y avisar al administrador de su empresa.

## 3. Uso aceptable

Al usar CheCu usted se compromete a no:

- Cargar información de terceros sin tener autorización para hacerlo.
- Intentar acceder a datos de otra empresa usuaria o de personas cuyo rol no se lo permite.
- Usar la plataforma para actividades ilegales, ni para almacenar contenido que no corresponda a la operación de su empresa.
- Interferir con el funcionamiento del servicio o intentar vulnerar sus medidas de seguridad.

## 4. La información que usted carga

La información que una empresa usuaria carga en CheCu sigue siendo suya. ${LegalResponsable.nombreComercial} no la usa para fines propios, no la comparte con otras empresas usuarias y no la vende.

Cada empresa usuaria es responsable de tener la autorización de las personas cuyos datos registra, en los términos de la Política de Tratamiento de Datos Personales.

## 5. Disponibilidad del servicio

Se trabaja para que CheCu esté disponible de forma continua, pero no se garantiza un funcionamiento ininterrumpido: puede haber mantenimientos, fallas de los proveedores de infraestructura o causas de fuerza mayor.

Se recomienda a cada empresa usuaria exportar periódicamente la información que considere crítica.

## 6. Responsabilidad

CheCu es una herramienta de organización del trabajo. Las decisiones que se tomen con la información que muestra son de quien las toma.

Dentro de lo permitido por la ley colombiana, la responsabilidad de ${LegalResponsable.nombreComercial} se limita a prestar el servicio de forma diligente, y no cubre lucro cesante ni perjuicios indirectos derivados del uso o de la imposibilidad de uso de la plataforma.

Nada en estos términos excluye la responsabilidad por dolo o culpa grave.

## 7. Terminación

Una empresa usuaria puede dejar de usar el servicio cuando quiera. También puede suspenderse el acceso de una cuenta que incumpla estos términos, informando el motivo.

Al terminar el servicio, la empresa usuaria puede solicitar la exportación de su información antes de que se elimine.

## 8. Cambios

Estos términos pueden cambiar. Cuando cambien, se publicará la versión nueva y se pedirá aceptarla antes de seguir usando la plataforma.

## 9. Ley aplicable

Estos términos se rigen por la ley colombiana. Cualquier controversia se someterá a los jueces de la República de Colombia.
''',
  );

  /// Los dos, en el orden en que se muestran.
  static List<LegalDoc> get todos => [politica, terminos];

  /// La huella de lo que hay vigente ahora mismo. Si cambia, hay que volver
  /// a aceptar: se compara contra lo que la persona aceptó la última vez.
  static String get versionVigente =>
      todos.map((d) => '${d.id}:${d.version}').join('|');
}
