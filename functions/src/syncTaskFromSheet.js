const { onRequest } = require("firebase-functions/v2/https");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

/**
 * HTTPS bridge for the Google Sheets integration (see
 * `apps-script/checu-sheet-sync.gs`) — a spreadsheet with one tab per
 * weekday, where each row is a task. Apps Script's `onEdit` trigger POSTs
 * the row here on every edit; this creates a new `tasks/{id}` doc (which
 * `onTaskCreate.js` then notifies about, same as any in-app creation) or
 * updates an already-synced one (which `onTaskUpdate.js` notifies about if
 * the date/hour changed — same as any in-app reschedule).
 *
 * Auth: a shared secret in the `X-Sheet-Secret` header, checked against
 * `SHEET_SYNC_SECRET` (set in `functions/.env`, never committed — see
 * `.gitignore`). Apps Script isn't a Firebase Auth client, so this is a
 * simple bearer-secret instead of a Firebase ID token; anyone who knows the
 * secret can create/update tasks, so it must stay only in the sheet's
 * Script Properties, never pasted into the script body itself.
 *
 * Names (assignedUserName, groupName, statusName, taskTypeName) are
 * resolved to Firestore ids by an exact, case-insensitive match against
 * each collection's `name` field — the spreadsheet's dropdown lists must
 * be kept identical to CheCu's actual Equipos/Estados/Tipos de tarea/
 * Usuarios names for this to work, by design (see the conversation this
 * shipped from — Michel chose "rename the sheet to match CheCu" over
 * building a separate mapping table).
 *
 * Multi-tenant: this endpoint is single-tenant by design — it's wired to
 * one shared secret for one Apps Script (VinApp's), so it's scoped to a
 * single `SHEET_SYNC_EMPRESA_ID` (set in `functions/.env`, VinApp's real
 * empresaId) rather than accepting one from the request body. This was
 * ADDED after the multi-tenant migration — this file predates it and, until
 * fixed, created tasks with no `empresaId` at all (invisible in the app,
 * since every read is `where('empresaId', '==', ...)`) and resolved
 * users/groups/statuses/taskTypes across every tenant instead of just
 * VinApp's. If Michel ever sells the Sheets integration to a second empresa,
 * this needs a real per-sheet empresaId (e.g. a second secret+id pair, or a
 * signed value baked into that sheet's Script Properties) — not just a
 * second env var, since both sheets would hit the same URL.
 */
const syncTaskFromSheet = onRequest(async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }

  const expectedSecret = process.env.SHEET_SYNC_SECRET;
  const providedSecret = req.get("X-Sheet-Secret");
  if (!expectedSecret || !providedSecret || providedSecret !== expectedSecret) {
    res.status(401).json({ error: "Unauthorized" });
    return;
  }

  const empresaId = process.env.SHEET_SYNC_EMPRESA_ID;
  if (!empresaId) {
    console.error("[SHEET_SYNC][ERROR] SHEET_SYNC_EMPRESA_ID is not configured");
    res.status(500).json({ error: "Internal error" });
    return;
  }

  const body = req.body || {};
  const {
    taskId,
    clientName,
    clientPhone,
    date,
    hour,
    assignedUserName,
    taskTypeName,
    observations,
    statusName,
    groupName,
  } = body;

  if (!clientName || !date || !hour || !assignedUserName) {
    res.status(400).json({
      error: "Missing required fields: clientName, date, hour, assignedUserName",
    });
    return;
  }

  const db = getFirestore();

  try {
    const [usersSnap, groupsSnap, statusesSnap, taskTypesSnap] = await Promise.all([
      db.collection("users").where("empresaId", "==", empresaId).get(),
      db.collection("groups").where("empresaId", "==", empresaId).get(),
      db.collection("statuses").where("empresaId", "==", empresaId).get(),
      db.collection("taskTypes").where("empresaId", "==", empresaId).get(),
    ]);

    const findIdByName = (snap, name) => {
      if (!name) return null;
      const target = String(name).trim().toLowerCase();
      const match = snap.docs.find(
        (d) => String(d.get("name") || "").trim().toLowerCase() === target
      );
      return match ? match.id : null;
    };

    const assignedUserId = findIdByName(usersSnap, assignedUserName);
    if (!assignedUserId) {
      res.status(400).json({ error: `No se encontró el usuario "${assignedUserName}" en CheCu` });
      return;
    }

    const groupId = findIdByName(groupsSnap, groupName || "SOPORTE");
    const taskTypeId = findIdByName(taskTypesSnap, taskTypeName);
    const statusId =
      findIdByName(statusesSnap, statusName) || findIdByName(statusesSnap, "Pendiente");

    const fields = {
      hour,
      date,
      assignedUserId,
      clientName,
      clientPhone: clientPhone || "",
      observations: observations || "",
      groupId,
      taskTypeId,
      statusId,
      empresaId,
    };

    let resultTaskId = taskId || null;

    if (resultTaskId) {
      const ref = db.collection("tasks").doc(resultTaskId);
      const existing = await ref.get();
      if (existing.exists && existing.get("empresaId") === empresaId) {
        await ref.update(fields);
      } else {
        // Stale id (task deleted in CheCu since the sheet last synced this
        // row) or, defensively, a doc that doesn't belong to this empresa —
        // either way, fall through to creating a fresh one instead of
        // touching it.
        resultTaskId = null;
      }
    }

    if (!resultTaskId) {
      const ref = await db.collection("tasks").add({
        ...fields,
        visibleToAllGroups: false,
        rescheduledCount: 0,
        reminderSent: false,
        isDeleted: false,
        createdAt: Timestamp.now(),
      });
      resultTaskId = ref.id;
    }

    console.log(`[SHEET_SYNC] Task ${taskId ? "updated" : "created"}: ${resultTaskId}`);
    res.status(200).json({ taskId: resultTaskId });
  } catch (e) {
    console.error(`[SHEET_SYNC][ERROR] ${e}`);
    res.status(500).json({ error: "Internal error" });
  }
});

module.exports = { syncTaskFromSheet };
