/**
 * El borrado de un requerimiento, de punta a punta.
 *
 * Hermana de support_case_delete.test.js y por el mismo motivo: borrar un
 * documento con subcolección es un lote, y un lote se rechaza entero si una
 * sola de sus escrituras no pasa. En los casos de soporte ese hueco hizo que
 * borrar nunca funcionara y además fallara en silencio. Aquí se prueba antes
 * de que pase.
 *
 * Run:
 *   1) npx firebase-tools emulators:start --only firestore
 *   2) cd test/rules && node requirement_delete.test.js
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
const CON_PERMISO = "adminConReq";
const SIN_PERMISO = "trabajadorSinReq";

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
    await db.doc(`users/${CON_PERMISO}`).set({
      role: "admin_equipo",
      empresaId: EMPRESA,
      permissions: { manageRequirements: true },
    });
    await db.doc(`users/${SIN_PERMISO}`).set({
      role: "trabajador_normal",
      empresaId: EMPRESA,
      permissions: {},
    });
    for (const n of ["req1", "req2", "req3"]) {
      await db.doc(`requirements/${n}`).set({
        empresaId: EMPRESA,
        requirementNumber: 1,
        status: "Recibido",
      });
      // Todo requerimiento nace con su evento "Requerimiento creado."
      await db.doc(`requirements/${n}/events/e1`).set({
        type: "created",
        text: "Requerimiento creado.",
      });
    }
  });

  const conPermiso = testEnv.authenticatedContext(CON_PERMISO).firestore();
  const sinPermiso = testEnv.authenticatedContext(SIN_PERMISO).firestore();

  console.log("· sin manageRequirements no se puede borrar");
  await assertFails(sinPermiso.doc("requirements/req1").delete());

  console.log("· ni sus eventos, que son el historial de otros");
  await assertFails(sinPermiso.doc("requirements/req1/events/e1").delete());

  console.log("· con el permiso sí se borra el requerimiento");
  await assertSucceeds(conPermiso.doc("requirements/req2").delete());

  console.log("· y el lote real —eventos + requerimiento— también pasa");
  const lote = conPermiso.batch();
  lote.delete(conPermiso.doc("requirements/req3/events/e1"));
  lote.delete(conPermiso.doc("requirements/req3"));
  await assertSucceeds(lote.commit());

  await testEnv.clearFirestore();
  await testEnv.cleanup();
  console.log("\nTodo pasó.");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
