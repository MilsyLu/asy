/**
 * Multi-tenant isolation tests for firestore.rules — CheCu / empresaId
 * conversion. Runs entirely against the local Firestore emulator (never
 * production). Two fake empresas (A, B) are seeded, each with its own
 * super_admin/admin_equipo/trabajador_normal and one sample doc per
 * tenant-scoped collection, then every cross-tenant get/list/create/update/
 * delete is asserted to FAIL and every same-tenant equivalent to SUCCEED.
 *
 * Run:
 *   1) npx firebase-tools emulators:start --only firestore  (from repo root)
 *   2) cd test/rules && npm install && npm test
 */
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require("@firebase/rules-unit-testing");
const fs = require("fs");
const path = require("path");
const assert = require("node:assert");

const PROJECT_ID = "checu-rules-test";

const EMPRESA_A = "empresaA";
const EMPRESA_B = "empresaB";

const SUPER_A = "superA";
const SUPER_B = "superB";
const WORKER_A = "workerA";
const OWNER_UID = "platformOwnerUid";
const OUTSIDER_UID = "noEmpresaUid"; // signed in, but no users/{uid} doc at all

let testEnv;
let results = [];

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

    await db.collection("empresas").doc(EMPRESA_A).set({ name: "Empresa A", activo: true });
    await db.collection("empresas").doc(EMPRESA_B).set({ name: "Empresa B", activo: true });
    await db.collection("platformOwners").doc(OWNER_UID).set({ email: "owner@checu.test" });

    await db.collection("users").doc(SUPER_A).set({
      email: "superA@test.com", role: "super_admin", empresaId: EMPRESA_A,
      groupId: null, managedGroupIds: [], permissions: {}, isActive: true,
    });
    await db.collection("users").doc(SUPER_B).set({
      email: "superB@test.com", role: "super_admin", empresaId: EMPRESA_B,
      groupId: null, managedGroupIds: [], permissions: {}, isActive: true,
    });
    await db.collection("users").doc(WORKER_A).set({
      email: "workerA@test.com", role: "trabajador_normal", empresaId: EMPRESA_A,
      groupId: "groupA1", managedGroupIds: [], permissions: {}, isActive: true,
    });

    for (const [empresaId, suffix] of [[EMPRESA_A, "A"], [EMPRESA_B, "B"]]) {
      await db.collection("groups").doc(`group${suffix}1`).set({ empresaId, name: `Equipo ${suffix}` });
      await db.collection("taskTypes").doc(`type${suffix}1`).set({ empresaId, name: `Tipo ${suffix}`, groupIds: [] });
      await db.collection("statuses").doc(`status${suffix}1`).set({ empresaId, name: "Completada", groupIds: [] });
      await db.collection("availableHours").doc(`hour${suffix}1`).set({ empresaId, hour: "09:00", groupIds: [] });
      await db.collection("clients").doc(`client${suffix}1`).set({ empresaId, name: `Cliente ${suffix}`, phone: "111" });
      await db.collection("tasks").doc(`task${suffix}1`).set({
        empresaId, groupId: `group${suffix}1`, assignedUserId: empresaId === EMPRESA_A ? WORKER_A : SUPER_B,
        date: "2026-08-01", hour: "09:00", visibleToAllGroups: false,
      });
    }
  });
}

function ctx(uid) {
  return testEnv.authenticatedContext(uid).firestore();
}

async function main() {
  const rulesPath = path.join(__dirname, "..", "..", "firestore.rules");
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(rulesPath, "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
  });

  await seed();

  // ---- users ----
  await run("superA cannot GET a user from empresa B", async () => {
    await assertFails(ctx(SUPER_A).collection("users").doc(SUPER_B).get());
  });
  await run("superA CAN get a user from empresa A", async () => {
    await assertSucceeds(ctx(SUPER_A).collection("users").doc(WORKER_A).get());
  });
  await run("superA cannot LIST users filtered to empresa B", async () => {
    await assertFails(ctx(SUPER_A).collection("users").where("empresaId", "==", EMPRESA_B).get());
  });
  await run("superA CAN list users filtered to empresa A", async () => {
    const snap = await assertSucceeds(ctx(SUPER_A).collection("users").where("empresaId", "==", EMPRESA_A).get());
    assert.strictEqual(snap.size, 2, `expected 2 users in empresa A, got ${snap.size}`);
  });
  await run("superA cannot DELETE a user from empresa B", async () => {
    await assertFails(ctx(SUPER_A).collection("users").doc(SUPER_B).delete());
  });
  await run("superA cannot CREATE a user stamped with empresa B's id", async () => {
    await assertFails(ctx(SUPER_A).collection("users").doc("newUser1").set({
      email: "x@test.com", role: "trabajador_normal", empresaId: EMPRESA_B, groupId: "groupA1",
    }));
  });

  // ---- tasks ----
  await run("superA cannot GET a task from empresa B", async () => {
    await assertFails(ctx(SUPER_A).collection("tasks").doc("taskB1").get());
  });
  await run("superA cannot LIST tasks filtered to empresa B", async () => {
    await assertFails(ctx(SUPER_A).collection("tasks").where("empresaId", "==", EMPRESA_B).get());
  });
  await run("superA CAN list/read tasks in empresa A", async () => {
    const snap = await assertSucceeds(ctx(SUPER_A).collection("tasks").where("empresaId", "==", EMPRESA_A).get());
    assert.strictEqual(snap.size, 1);
  });
  await run("superA cannot UPDATE a task from empresa B", async () => {
    await assertFails(ctx(SUPER_A).collection("tasks").doc("taskB1").update({ hour: "10:00" }));
  });
  await run("superA cannot DELETE a task from empresa B", async () => {
    await assertFails(ctx(SUPER_A).collection("tasks").doc("taskB1").delete());
  });
  await run("superA cannot CREATE a task stamped with empresa B's id", async () => {
    await assertFails(ctx(SUPER_A).collection("tasks").doc("newTask1").set({
      empresaId: EMPRESA_B, groupId: "groupB1", date: "2026-08-01", hour: "09:00",
    }));
  });

  // ---- catalogs: groups / taskTypes / statuses / availableHours / clients ----
  const catalogCases = [
    ["groups", "groupB1", { name: "hacked" }],
    ["taskTypes", "typeB1", { name: "hacked" }],
    ["statuses", "statusB1", { name: "hacked" }],
    ["availableHours", "hourB1", { hour: "23:00" }],
    ["clients", "clientB1", { name: "hacked" }],
  ];
  for (const [col, docId, patch] of catalogCases) {
    await run(`superA cannot READ ${col} doc from empresa B`, async () => {
      await assertFails(ctx(SUPER_A).collection(col).doc(docId).get());
    });
    await run(`superA cannot UPDATE ${col} doc from empresa B`, async () => {
      await assertFails(ctx(SUPER_A).collection(col).doc(docId).update(patch));
    });
    await run(`superA cannot DELETE ${col} doc from empresa B`, async () => {
      await assertFails(ctx(SUPER_A).collection(col).doc(docId).delete());
    });
  }
  await run("superA CAN read own empresa's groups", async () => {
    await assertSucceeds(ctx(SUPER_A).collection("groups").doc("groupA1").get());
  });

  // ---- empresas / platformOwners ----
  await run("superA (not a platform owner) cannot LIST empresas", async () => {
    await assertFails(ctx(SUPER_A).collection("empresas").get());
  });
  await run("superA CAN read their own empresa doc", async () => {
    await assertSucceeds(ctx(SUPER_A).collection("empresas").doc(EMPRESA_A).get());
  });
  await run("superA cannot read empresa B's doc", async () => {
    await assertFails(ctx(SUPER_A).collection("empresas").doc(EMPRESA_B).get());
  });
  await run("superA cannot create a new empresa", async () => {
    await assertFails(ctx(SUPER_A).collection("empresas").doc("empresaC").set({ name: "C", activo: true }));
  });
  await run("platform owner CAN create a new empresa", async () => {
    await assertSucceeds(ctx(OWNER_UID).collection("empresas").doc("empresaC").set({ name: "C", activo: true }));
  });
  await run("platform owner CAN deactivate an empresa", async () => {
    await assertSucceeds(ctx(OWNER_UID).collection("empresas").doc(EMPRESA_B).update({ activo: false }));
    await ctx(OWNER_UID).collection("empresas").doc(EMPRESA_B).update({ activo: true }); // reset for later tests
  });
  await run("nobody can list platformOwners", async () => {
    await assertFails(ctx(OWNER_UID).collection("platformOwners").get());
  });

  // ---- systemConfig: platform-owner-only write (regression: was super_admin) ----
  await run("superA (super_admin, not platform owner) cannot write systemConfig", async () => {
    await assertFails(ctx(SUPER_A).collection("systemConfig").doc("settings").set({ appVersion: "9.9.9" }));
  });
  await run("platform owner CAN write systemConfig", async () => {
    await assertSucceeds(ctx(OWNER_UID).collection("systemConfig").doc("settings").set({ appVersion: "9.9.9" }));
  });

  // ---- signed-in user with no empresaId at all (edge case) ----
  await run("a signed-in user with no users/{uid} doc gets nothing tenant-scoped", async () => {
    await assertFails(ctx(OUTSIDER_UID).collection("tasks").where("empresaId", "==", EMPRESA_A).get());
  });

  // ---- existing within-tenant behavior must still work (regression) ----
  await run("workerA (trabajador_normal) can still read their own assigned task", async () => {
    await assertSucceeds(ctx(WORKER_A).collection("tasks").doc("taskA1").get());
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
