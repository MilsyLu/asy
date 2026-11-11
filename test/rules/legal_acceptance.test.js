/**
 * Reglas de `legalAcceptances` — la prueba de que cada persona autorizó el
 * tratamiento de sus datos (Ley 1581 de 2012).
 *
 * Lo que se verifica aquí no es un detalle: si la regla rechaza la
 * escritura, nadie puede pasar de la pantalla de aceptación y el equipo
 * entero se queda sin poder entrar a trabajar. Y si la regla deja editar o
 * borrar un registro, el registro no prueba nada.
 *
 * Correr:
 *   1) npx firebase-tools emulators:start --only firestore   (desde la raíz)
 *   2) cd test/rules && npm install && node legal_acceptance.test.js
 */
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require("@firebase/rules-unit-testing");
const fs = require("fs");
const path = require("path");

const PROJECT_ID = "checu-legal-rules-test";

const EMPRESA_A = "empresaA";
const EMPRESA_B = "empresaB";
const SUPER_A = "superA";
const SUPER_B = "superB";
const WORKER_A = "workerA";
const OTRO_A = "otroA";

let testEnv;
const results = [];

async function run(name, fn) {
  try {
    await fn();
    results.push({ name, ok: true });
  } catch (e) {
    results.push({ name, ok: false, error: e.message });
  }
}

/** Lo que la app escribe de verdad (ver LegalRepository.aceptar). */
function aceptacion(uid, empresaId, documentoId = "politica_datos", version = "1.0") {
  return {
    userId: uid,
    userName: "Quien Sea",
    userEmail: "quien@test.com",
    documentoId,
    documentoTitulo: "Política de Tratamiento de Datos Personales",
    version,
    empresaId,
    origen: "web",
    aceptadoEn: new Date(),
  };
}

/**
 * El id tiene que salir igual que en LegalRepository.idDe: empieza por el
 * uid y termina en el instante, para que cada aceptación sea un registro
 * nuevo y ninguna pise a la anterior.
 */
function idDe(uid, documentoId = "politica_datos", version = "1.0", cuando = 1) {
  return `${uid}__${documentoId}_v${version}__${cuando}`;
}

async function seed() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    for (const [uid, empresaId, role] of [
      [SUPER_A, EMPRESA_A, "super_admin"],
      [SUPER_B, EMPRESA_B, "super_admin"],
      [WORKER_A, EMPRESA_A, "trabajador_normal"],
      [OTRO_A, EMPRESA_A, "trabajador_normal"],
    ]) {
      await db.collection("users").doc(uid).set({
        email: `${uid}@test.com`,
        role,
        empresaId,
        groupIds: [],
        managedGroupIds: [],
        permissions: {},
        isActive: true,
      });
    }
    // Una aceptación ya existente, para probar lectura y borrado.
    await db
      .collection("legalAcceptances")
      .doc(idDe(WORKER_A))
      .set(aceptacion(WORKER_A, EMPRESA_A));
  });
}

async function main() {
  const rulesPath = path.resolve(__dirname, "../../firestore.rules");
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(rulesPath, "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
  });

  await seed();

  const ctx = (uid) => testEnv.authenticatedContext(uid).firestore();

  // ---- lo que tiene que funcionar ----
  await run("alguien puede registrar SU propia aceptación", async () => {
    await assertSucceeds(
      ctx(OTRO_A)
        .collection("legalAcceptances")
        .doc(idDe(OTRO_A))
        .set(aceptacion(OTRO_A, EMPRESA_A))
    );
  });

  await run("puede registrar los dos documentos", async () => {
    await assertSucceeds(
      ctx(OTRO_A)
        .collection("legalAcceptances")
        .doc(idDe(OTRO_A, "terminos_uso"))
        .set(aceptacion(OTRO_A, EMPRESA_A, "terminos_uso"))
    );
  });

  await run("aceptar dos veces lo mismo no falla y no pisa el primero", async () => {
    await assertSucceeds(
      ctx(OTRO_A)
        .collection("legalAcceptances")
        .doc(idDe(OTRO_A, "politica_datos", "1.0", 2))
        .set(aceptacion(OTRO_A, EMPRESA_A))
    );
  });

  await run("puede leer la suya", async () => {
    await assertSucceeds(
      ctx(WORKER_A).collection("legalAcceptances").doc(idDe(WORKER_A)).get()
    );
  });

  await run("el super_admin de su empresa puede leerla", async () => {
    await assertSucceeds(
      ctx(SUPER_A).collection("legalAcceptances").doc(idDe(WORKER_A)).get()
    );
  });

  // ---- lo que NO puede pasar ----
  await run("nadie registra una aceptación a nombre de otro", async () => {
    await assertFails(
      ctx(OTRO_A)
        .collection("legalAcceptances")
        .doc(idDe(WORKER_A, "terminos_uso"))
        .set(aceptacion(WORKER_A, EMPRESA_A, "terminos_uso"))
    );
  });

  await run("ni poniendo su propio uid adentro pero el id de otro", async () => {
    await assertFails(
      ctx(OTRO_A)
        .collection("legalAcceptances")
        .doc(idDe(WORKER_A, "terminos_uso"))
        .set(aceptacion(OTRO_A, EMPRESA_A, "terminos_uso"))
    );
  });

  await run("el titular NO puede modificar su aceptación", async () => {
    await assertFails(
      ctx(WORKER_A)
        .collection("legalAcceptances")
        .doc(idDe(WORKER_A))
        .update({ version: "9.9" })
    );
  });

  await run("el titular NO puede borrar su aceptación", async () => {
    await assertFails(
      ctx(WORKER_A).collection("legalAcceptances").doc(idDe(WORKER_A)).delete()
    );
  });

  await run("el super_admin tampoco puede borrarla", async () => {
    await assertFails(
      ctx(SUPER_A).collection("legalAcceptances").doc(idDe(WORKER_A)).delete()
    );
  });

  await run("el super_admin tampoco puede modificarla", async () => {
    await assertFails(
      ctx(SUPER_A)
        .collection("legalAcceptances")
        .doc(idDe(WORKER_A))
        .update({ userName: "Otro Nombre" })
    );
  });

  await run("un super_admin de OTRA empresa no puede leerla", async () => {
    await assertFails(
      ctx(SUPER_B).collection("legalAcceptances").doc(idDe(WORKER_A)).get()
    );
  });

  await run("sin sesión no se registra nada", async () => {
    await assertFails(
      testEnv
        .unauthenticatedContext()
        .firestore()
        .collection("legalAcceptances")
        .doc(idDe("cualquiera"))
        .set(aceptacion("cualquiera", EMPRESA_A))
    );
  });

  await testEnv.cleanup();

  const failed = results.filter((r) => !r.ok);
  for (const r of results) {
    console.log(`${r.ok ? "PASS" : "FAIL"} - ${r.name}${r.ok ? "" : `\n       ${r.error}`}`);
  }
  console.log(`\n${results.length - failed.length}/${results.length} passed`);
  if (failed.length > 0) process.exit(1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
