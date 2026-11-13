/**
 * Reglas del recordatorio de una tarea.
 *
 * El recordatorio dejó de tener regla propia: quien puede editar la tarea
 * puede ponerle o quitarle el aviso, sea o no el encargado. Antes solo
 * podían el encargado y un super_admin, y eso dejaba por fuera el caso más
 * común — quien registra una tarea para otra persona y quiere ponerle un
 * recordatorio para que no se le pase.
 *
 * Lo que estas pruebas cuidan es que al quitar esa restricción no se haya
 * abierto nada más: un compañero de otro equipo, o alguien de otra empresa,
 * siguen sin poder tocar la tarea.
 *
 * Correr:
 *   1) npx firebase-tools emulators:start --only firestore   (desde la raíz)
 *   2) cd test/rules && node reminder.test.js
 */
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require("@firebase/rules-unit-testing");
const fs = require("fs");
const path = require("path");

const PROJECT_ID = "checu-reminder-rules-test";

const EMPRESA_A = "empresaA";
const EMPRESA_B = "empresaB";

const SUPER_A = "superA";
const ENCARGADA = "encargadaA"; // hace la tarea
const QUIEN_REGISTRO = "registradoraA"; // la creó, mismo equipo, no la hace
const OTRO_EQUIPO = "otroEquipoA"; // misma empresa, equipo distinto
const DE_OTRA_EMPRESA = "trabajadorB";

const TAREA = "tareaDeLaEncargada";

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

async function seed() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const usuarios = [
      [SUPER_A, EMPRESA_A, "super_admin", []],
      [ENCARGADA, EMPRESA_A, "trabajador_normal", ["grupoA1"]],
      [QUIEN_REGISTRO, EMPRESA_A, "trabajador_normal", ["grupoA1"]],
      [OTRO_EQUIPO, EMPRESA_A, "trabajador_normal", ["grupoA2"]],
      [DE_OTRA_EMPRESA, EMPRESA_B, "trabajador_normal", ["grupoB1"]],
    ];
    for (const [uid, empresaId, role, groupIds] of usuarios) {
      await db.collection("users").doc(uid).set({
        email: `${uid}@test.com`,
        role,
        empresaId,
        groupIds,
        managedGroupIds: [],
        permissions: {},
        isActive: true,
      });
    }
    await db.collection("groups").doc("grupoA1").set({ empresaId: EMPRESA_A, name: "Equipo A1" });
    await db.collection("groups").doc("grupoA2").set({ empresaId: EMPRESA_A, name: "Equipo A2" });

    await db.collection("tasks").doc(TAREA).set({
      empresaId: EMPRESA_A,
      groupId: "grupoA1",
      assignedUserId: ENCARGADA,
      createdBy: QUIEN_REGISTRO,
      date: "2026-11-13",
      hour: "16:00",
      visibleToAllGroups: false,
      reminderTime: new Date("2026-11-13T20:45:00Z"),
      reminderSent: false,
    });
  });
}

/** Mover el recordatorio al día que quedó la tarea. */
const nuevoRecordatorio = {
  reminderTime: new Date("2026-11-17T20:45:00Z"),
  reminderSent: false,
};

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
  const tarea = (uid) => ctx(uid).collection("tasks").doc(TAREA);

  // ---- lo que Michel pidió ----
  await run("quien registró la tarea puede cambiar el recordatorio sin ser la encargada", async () => {
    await assertSucceeds(tarea(QUIEN_REGISTRO).update(nuevoRecordatorio));
  });

  await run("y puede quitarlo", async () => {
    await assertSucceeds(
      tarea(QUIEN_REGISTRO).update({ reminderTime: null, reminderSent: false })
    );
  });

  await run("la encargada sigue pudiendo cambiar el suyo", async () => {
    await assertSucceeds(tarea(ENCARGADA).update(nuevoRecordatorio));
  });

  await run("un super_admin también", async () => {
    await assertSucceeds(tarea(SUPER_A).update(nuevoRecordatorio));
  });

  await run("cambiar la hora y el recordatorio a la vez, en una sola escritura", async () => {
    await assertSucceeds(
      tarea(QUIEN_REGISTRO).update({
        date: "2026-11-17",
        hour: "16:00",
        ...nuevoRecordatorio,
      })
    );
  });

  // ---- lo que no se abrió ----
  await run("alguien de otro equipo NO puede tocar la tarea", async () => {
    await assertFails(tarea(OTRO_EQUIPO).update(nuevoRecordatorio));
  });

  await run("alguien de otra empresa NO puede tocar la tarea", async () => {
    await assertFails(tarea(DE_OTRA_EMPRESA).update(nuevoRecordatorio));
  });

  await run("sin sesión no se toca nada", async () => {
    await assertFails(
      testEnv
        .unauthenticatedContext()
        .firestore()
        .collection("tasks")
        .doc(TAREA)
        .update(nuevoRecordatorio)
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
