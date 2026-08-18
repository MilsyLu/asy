/**
 * Concurrency tests for the Casos de Soporte number counter, run against the
 * local Firestore emulator with the real firestore.rules loaded.
 *
 * WHAT THIS COVERS, AND WHAT IT DOES NOT
 *
 * `lib/services/support_case_repository.dart` allocates each case number
 * inside a Firestore transaction: read `supportCaseCounters/{empresaId}`, add one, write
 * both the counter and the new case atomically. Whether that is *enough* under
 * concurrency is a property of Firestore's transaction semantics, not of Dart
 * — so it can be proven here, and it is the question that actually matters:
 * if two people press "Nuevo caso" at the same instant, do they get two
 * numbers or the same one twice?
 *
 * What this does NOT do is execute the Dart repository. `cloud_firestore` is a
 * Flutter plugin that needs platform channels, so `flutter test` cannot drive
 * it (verified: PlatformException channel-error). These tests reproduce the
 * same transaction shape faithfully; a future change that silently drops the
 * transaction in the Dart code would NOT be caught here. Testing the Dart
 * itself would need integration_test plus chromedriver.
 *
 * Run:
 *   npx firebase-tools emulators:exec --only firestore --project demo-checu \
 *     "cd test/rules && node counters.test.js"
 */
const {
  initializeTestEnvironment,
  assertFails,
} = require("@firebase/rules-unit-testing");
const fs = require("fs");
const path = require("path");
const assert = require("node:assert");

const PROJECT_ID = "checu-counter-test";
const EMPRESA = "empresaA";
const ADMIN = "adminA";

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

/** The exact allocation the Dart repository performs, one case. */
async function crearCaso(db, subject) {
  const counterRef = db.collection("supportCaseCounters").doc(EMPRESA);
  const caseRef = db.collection("supportCases").doc();
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(counterRef);
    const next = ((snap.data() || {}).value || 0) + 1;
    tx.set(counterRef, { value: next, empresaId: EMPRESA }, { merge: true });
    tx.set(caseRef, {
      caseNumber: next,
      empresaId: EMPRESA,
      clientName: "Cliente",
      subject,
      status: "nuevo",
      priority: "media",
      createdBy: ADMIN,
    });
  });
}

async function main() {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(path.resolve(__dirname, "../../firestore.rules"), "utf8"),
      host: "localhost",
      port: 8080,
    },
  });

  // Seed: one empresa with an admin who may manage support cases.
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.collection("empresas").doc(EMPRESA).set({ nombre: "A", activo: true });
    await db.collection("users").doc(ADMIN).set({
      empresaId: EMPRESA,
      role: "super_admin",
      name: "Admin",
      email: "a@a.com",
      isActive: true,
      groupIds: [],
      managedGroupIds: [],
      permissions: { manageSupportCases: true },
    });
  });

  const admin = testEnv.authenticatedContext(ADMIN).firestore();

  await run("dos creaciones seguidas dan números 1 y 2", async () => {
    await crearCaso(admin, "primero");
    await crearCaso(admin, "segundo");
    const snap = await admin.collection("supportCases").where("empresaId", "==", EMPRESA).get();
    const numeros = snap.docs.map((d) => d.get("caseNumber")).sort((a, b) => a - b);
    assert.deepStrictEqual(numeros, [1, 2]);
  });

  await run("10 creaciones SIMULTÁNEAS no repiten ningún número", async () => {
    // El escenario real: varias personas tocando "Nuevo caso" a la vez. Sin
    // transacción, todas leerían el mismo contador y saldrían con el mismo
    // número — que es justamente el bug que la transacción existe para evitar.
    await testEnv.clearFirestore();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.collection("empresas").doc(EMPRESA).set({ nombre: "A", activo: true });
      await db.collection("users").doc(ADMIN).set({
        empresaId: EMPRESA, role: "super_admin", name: "Admin", email: "a@a.com",
        isActive: true, groupIds: [], managedGroupIds: [],
        permissions: { manageSupportCases: true },
      });
    });
    const db = testEnv.authenticatedContext(ADMIN).firestore();

    await Promise.all(
      Array.from({ length: 10 }, (_, i) => crearCaso(db, `simultaneo-${i}`))
    );

    const snap = await db.collection("supportCases").where("empresaId", "==", EMPRESA).get();
    const numeros = snap.docs.map((d) => d.get("caseNumber")).sort((a, b) => a - b);
    assert.strictEqual(numeros.length, 10, `se crearon ${numeros.length} casos, se esperaban 10`);
    assert.strictEqual(new Set(numeros).size, 10, `números repetidos: ${numeros.join(",")}`);
    assert.deepStrictEqual(numeros, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
  });

  await run("el contador queda en el último número entregado", async () => {
    const snap = await admin.collection("supportCaseCounters").doc(EMPRESA).get();
    assert.strictEqual(snap.get("value"), 10);
  });

  await run("un usuario de OTRA empresa no puede tocar el contador", async () => {
    // El contador es un documento como cualquier otro: si no estuviera
    // protegido, alguien de otra empresa podría reiniciarlo y provocar
    // números repetidos en la empresa afectada.
    const intruso = testEnv.authenticatedContext("intrusoB").firestore();
    await assertFails(
      intruso.collection("supportCaseCounters").doc(EMPRESA).set({ value: 0 })
    );
  });

  await run("sin sesión tampoco se puede tocar el contador", async () => {
    const anonimo = testEnv.unauthenticatedContext().firestore();
    await assertFails(
      anonimo.collection("supportCaseCounters").doc(EMPRESA).set({ value: 0 })
    );
  });

  await testEnv.cleanup();

  let ok = 0;
  for (const r of results) {
    console.log(`${r.ok ? "PASS" : "FALLA"} - ${r.name}${r.ok ? "" : `\n        ${r.error}`}`);
    if (r.ok) ok++;
  }
  console.log(`\n${ok}/${results.length} passed`);
  process.exit(ok === results.length ? 0 : 1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
