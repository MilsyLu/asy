/**
 * El borrado de un caso de soporte, de punta a punta.
 *
 * Michel convirtió un caso de prueba en requerimiento tres veces: las tres
 * nació el requerimiento y las tres el caso siguió en Casos de Soporte. La
 * causa no era el permiso sino esta regla: `supportCases/{id}/history` no
 * tenía `allow delete`, y un comentario afirmaba que el borrado del caso
 * padre se encargaba de la limpieza. No es cierto — las reglas de Firestore
 * no cascadean. `SupportCaseRepository.delete` borra el historial y el caso
 * en un solo lote, y un lote se rechaza entero si una sola de sus
 * escrituras no pasa. O sea que borrar un caso nunca funcionó, ni desde el
 * botón de la papelera.
 *
 * Run:
 *   1) npx firebase-tools emulators:start --only firestore
 *   2) cd test/rules && node support_case_delete.test.js
 */
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require("@firebase/rules-unit-testing");
const fs = require("fs");
const path = require("path");

const PROJECT_ID = "checu-rules-test";
const EMPRESA = "empresaA";
const ADMIN = "adminConPermiso";
const SIN_PERMISO = "adminSinPermiso";

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      host: "127.0.0.1",
      port: 8080,
      rules: fs.readFileSync(
        path.join(__dirname, "..", "..", "firestore.rules"),
        "utf8",
      ),
    },
  });

  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.doc(`users/${ADMIN}`).set({
      role: "admin_equipo",
      empresaId: EMPRESA,
      permissions: { manageSupportCases: true },
    });
    await db.doc(`users/${SIN_PERMISO}`).set({
      role: "admin_equipo",
      empresaId: EMPRESA,
      permissions: {},
    });
    for (const n of ["caso1", "caso2"]) {
      await db.doc(`supportCases/${n}`).set({
        empresaId: EMPRESA,
        caseNumber: 1,
        status: "Nuevo",
      });
      // Todo caso tiene historial desde que nace: "Caso creado."
      await db.doc(`supportCases/${n}/history/h1`).set({
        type: "created",
        text: "Caso creado.",
      });
    }
  });

  const conPermiso = testEnv.authenticatedContext(ADMIN).firestore();
  const sinPermiso = testEnv.authenticatedContext(SIN_PERMISO).firestore();

  console.log("· sin manageSupportCases no se puede borrar el caso");
  await assertFails(sinPermiso.doc("supportCases/caso1").delete());

  console.log("· con el permiso sí se puede borrar el caso");
  await assertSucceeds(conPermiso.doc("supportCases/caso1").delete());

  console.log("· y también su historial, que es lo que fallaba");
  // El lote real de la app: historial + caso de una sola vez. Antes del
  // arreglo esta línea fallaba y se llevaba el borrado del caso con ella.
  const lote = conPermiso.batch();
  lote.delete(conPermiso.doc("supportCases/caso2/history/h1"));
  lote.delete(conPermiso.doc("supportCases/caso2"));
  await assertSucceeds(lote.commit());

  // Sin esto, los usuarios y casos de aquí se quedan en el emulador y la
  // siguiente suite cuenta de más.
  await testEnv.clearFirestore();
  await testEnv.cleanup();
  console.log("\nTodo pasó.");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
