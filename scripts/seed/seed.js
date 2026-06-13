"use strict";

/**
 * One-time Firestore seed script for TaskFlow Executive.
 *
 * Populates the catalog collections (`taskTypes`, `statuses`,
 * `availableHours`, `groups`) with sensible defaults and, optionally,
 * creates the first `super_admin` user.
 *
 * Setup:
 *   1. cd scripts/seed
 *   2. npm install
 *   3. Download a service account key from
 *      Firebase Console > Project settings > Service accounts > Generate new
 *      private key, and save it as scripts/seed/serviceAccountKey.json
 *      (this file is git-ignored and must never be committed).
 *   4. (Optional) to also create a super admin user, set:
 *        SEED_ADMIN_EMAIL, SEED_ADMIN_PASSWORD, SEED_ADMIN_NAME
 *   5. npm run seed
 *
 * The script is idempotent: re-running it skips catalog entries that
 * already exist (matched by `name` / `hour`) and reuses an existing
 * Auth user for the super admin if the email is already registered.
 */

const path = require("path");
const { initializeApp, cert } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");

const serviceAccountPath =
  process.env.GOOGLE_APPLICATION_CREDENTIALS ||
  path.join(__dirname, "serviceAccountKey.json");

initializeApp({
  credential: cert(require(serviceAccountPath)),
});

const db = getFirestore();
const auth = getAuth();

const TASK_TYPES = [
  { name: "Instalación", order: 1, color: "#D4AF37" },
  { name: "Mantenimiento", order: 2, color: "#4CAF50" },
  { name: "Soporte", order: 3, color: "#E4C568" },
  { name: "Visita técnica", order: 4, color: "#B0B0B0" },
];

const STATUSES = [
  { name: "Pendiente", order: 1 },
  { name: "Completada", order: 2 },
  { name: "Reprogramada", order: 3 },
  { name: "Cancelada", order: 4 },
];

const AVAILABLE_HOURS = [
  "08:00",
  "09:00",
  "10:00",
  "11:00",
  "12:00",
  "13:00",
  "14:00",
  "15:00",
  "16:00",
  "17:00",
  "18:00",
];

const GROUPS = [
  { name: "Grupo Norte", description: "Equipo de trabajo - zona norte" },
  { name: "Grupo Sur", description: "Equipo de trabajo - zona sur" },
];

/** Seeds a catalog collection, skipping documents whose `name` already exists. */
async function seedNamedCollection(collectionName, items) {
  const collection = db.collection(collectionName);
  for (const item of items) {
    const existing = await collection
      .where("name", "==", item.name)
      .limit(1)
      .get();
    if (!existing.empty) {
      console.log(`  - "${item.name}" already exists in ${collectionName}, skipping.`);
      continue;
    }
    await collection.add(item);
    console.log(`  - Created "${item.name}" in ${collectionName}.`);
  }
}

/** Seeds the `availableHours` collection, skipping hours that already exist. */
async function seedAvailableHours() {
  const collection = db.collection("availableHours");
  for (const hour of AVAILABLE_HOURS) {
    const existing = await collection.where("hour", "==", hour).limit(1).get();
    if (!existing.empty) {
      console.log(`  - "${hour}" already exists in availableHours, skipping.`);
      continue;
    }
    await collection.add({ hour });
    console.log(`  - Created "${hour}" in availableHours.`);
  }
}

/** Seeds the `groups` collection with a `createdAt` server timestamp. */
async function seedGroups() {
  await seedNamedCollection(
    "groups",
    GROUPS.map((group) => ({
      ...group,
      createdAt: FieldValue.serverTimestamp(),
    }))
  );
}

/**
 * Optionally creates the first `super_admin` user, using
 * SEED_ADMIN_EMAIL / SEED_ADMIN_PASSWORD / SEED_ADMIN_NAME env vars.
 */
async function seedSuperAdmin() {
  const email = process.env.SEED_ADMIN_EMAIL;
  const password = process.env.SEED_ADMIN_PASSWORD;
  const name = process.env.SEED_ADMIN_NAME || "Administrador";

  if (!email || !password) {
    console.log(
      "\nSEED_ADMIN_EMAIL / SEED_ADMIN_PASSWORD not set, skipping super admin creation."
    );
    return;
  }

  let userRecord;
  try {
    userRecord = await auth.getUserByEmail(email);
    console.log(`\nSuper admin "${email}" already exists (uid: ${userRecord.uid}).`);
  } catch (error) {
    if (error.code !== "auth/user-not-found") throw error;
    userRecord = await auth.createUser({
      email,
      password,
      displayName: name,
    });
    console.log(`\nCreated super admin "${email}" (uid: ${userRecord.uid}).`);
  }

  await db.collection("users").doc(userRecord.uid).set(
    {
      email,
      name,
      role: "super_admin",
      groupId: null,
      fcmTokens: [],
      lastLogin: null,
      streakDays: 0,
      maxStreakDays: 0,
      createdAt: FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
  console.log(`  - Wrote users/${userRecord.uid} (role: super_admin).`);
}

async function main() {
  console.log("Seeding taskTypes...");
  await seedNamedCollection("taskTypes", TASK_TYPES);

  console.log("\nSeeding statuses...");
  await seedNamedCollection("statuses", STATUSES);

  console.log("\nSeeding availableHours...");
  await seedAvailableHours();

  console.log("\nSeeding groups...");
  await seedGroups();

  await seedSuperAdmin();

  console.log("\nDone.");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
