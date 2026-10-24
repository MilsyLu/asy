import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow_executive/core/constants/app_constants.dart';
import 'package:taskflow_executive/models/app_user.dart';

/// Pruebas de quién tiene qué permiso.
///
/// Es la clase de regla que no se comprueba mirando la pantalla: para saber si
/// un trabajador puede llegar a Descargar Archivos habría que crear un usuario,
/// entrar con él y mirar el menú. Aquí son seis líneas.
void main() {
  AppUser usuario(String rol, {Map<String, bool> permisos = const {}}) =>
      AppUser(
        id: 'u1',
        name: 'Usuario',
        email: 'u@x.co',
        role: rol,
        permissions: permisos,
      );

  final superAdmin = usuario(AppRoles.superAdmin);
  final adminEquipo = usuario(AppRoles.adminEquipo);
  final trabajador = usuario(AppRoles.trabajadorNormal);

  group('Descargar archivos', () {
    test('todo administrador lo tiene sin que se lo marquen', () {
      // "por defecto" quiere decir exactamente esto: un admin_equipo recién
      // creado, con el mapa de permisos vacío, ya lo tiene.
      expect(superAdmin.hasPermission(AppPermissions.downloadFiles), isTrue);
      expect(adminEquipo.hasPermission(AppPermissions.downloadFiles), isTrue);
    });

    test('un trabajador no lo tiene hasta que se lo activan', () {
      expect(trabajador.hasPermission(AppPermissions.downloadFiles), isFalse);
      expect(
        usuario(
          AppRoles.trabajadorNormal,
          permisos: {AppPermissions.downloadFiles: true},
        ).hasPermission(AppPermissions.downloadFiles),
        isTrue,
      );
    });

    test('activado y luego desactivado vuelve a quedar sin acceso', () {
      expect(
        usuario(
          AppRoles.trabajadorNormal,
          permisos: {AppPermissions.downloadFiles: false},
        ).hasPermission(AppPermissions.downloadFiles),
        isFalse,
      );
    });
  });

  group('lo que un trabajador NO puede recibir', () {
    test('escribirle un permiso de administración no se lo concede', () {
      // Las reglas de Firestore dejan que un administrador de equipo edite
      // cualquier campo del documento de un trabajador suyo, `permissions`
      // incluido. Si la app honrara ese mapa entero, escribirle "manageUsers"
      // le abriría el panel de usuarios. La lista de lo concedible está
      // cerrada en el modelo justamente por eso.
      final colado = usuario(
        AppRoles.trabajadorNormal,
        permisos: {
          AppPermissions.manageUsers: true,
          AppPermissions.manageTeams: true,
          AppPermissions.viewReports: true,
        },
      );
      expect(colado.hasPermission(AppPermissions.manageUsers), isFalse);
      expect(colado.hasPermission(AppPermissions.manageTeams), isFalse);
      expect(colado.hasPermission(AppPermissions.viewReports), isFalse);
    });

    test('ninguno de los que abren un módulo es concedible', () {
      // Esta prueba decía antes "nada de lo concedible está en
      // AppPermissions.all", y se puso roja al agregar manageRequirements —
      // que sí está en las dos listas, a propósito: Michel pidió poder darle
      // la aprobación de requerimientos a quien quiera, tenga el rol que
      // tenga. El supuesto estaba mal; lo que hay que proteger no es "que no
      // esté en all", sino que nadie reciba por esta vía un permiso que abre
      // un módulo de administración entero.
      const jamas = [
        AppPermissions.manageUsers,
        AppPermissions.manageTeams,
        AppPermissions.manageCatalogs,
        AppPermissions.manageClients,
        AppPermissions.manageTasks,
        AppPermissions.viewReports,
        AppPermissions.managePrinterConfigs,
        AppPermissions.manageSupportCases,
      ];
      for (final k in jamas) {
        expect(
          AppPermissions.grantableToWorkers.contains(k),
          isFalse,
          reason:
              '$k abre un módulo de administración: no puede estar '
              'entre los que se le pueden conceder a un trabajador',
        );
      }
    });
  });

  group('los permisos de siempre no cambiaron', () {
    test('un admin_equipo sigue necesitando que se los marquen', () {
      expect(adminEquipo.hasPermission(AppPermissions.manageUsers), isFalse);
      expect(
        usuario(
          AppRoles.adminEquipo,
          permisos: {AppPermissions.manageUsers: true},
        ).hasPermission(AppPermissions.manageUsers),
        isTrue,
      );
    });

    test('un super_admin los tiene todos', () {
      for (final k in AppPermissions.all) {
        expect(superAdmin.hasPermission(k), isTrue);
      }
    });
  });
}
