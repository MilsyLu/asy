const { onSchedule } = require("firebase-functions/v2/scheduler");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { sendNotificationToUsers, getSupportCaseSupervisorIds } = require("./notifications");

/** Same "today, Bogotá calendar day" convention as `checkReminders.js`. */
function todayDateKey() {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "America/Bogota" }).format(new Date());
}

function dateKeyFor(date) {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "America/Bogota" }).format(date);
}

/** Whole-day difference between two `YYYY-MM-DD` keys (a - b). */
function dayDiff(dateKeyA, dateKeyB) {
  const a = new Date(`${dateKeyA}T00:00:00Z`);
  const b = new Date(`${dateKeyB}T00:00:00Z`);
  return Math.round((a - b) / 86400000);
}

const OPEN_STATUSES = ["Nuevo", "En proceso", "Esperando cliente"];
const THRESHOLDS = [5, 10, 15];
const THRESHOLD_META = {
  5: { emoji: "🟠", label: "dar seguimiento" },
  10: { emoji: "🔴", label: "atrasado" },
  15: { emoji: "🔥", label: "atención urgente" },
};

/**
 * Runs once a day (9am Bogotá). For every open Casos de Soporte case, checks
 * whether the days since `reportedAt` (the "días sin resolver" clock — see
 * `SupportCaseModel.daysOpen()` on the client, same rule here) exactly
 * crossed 5, 10 or 15 today, and if so notifies the assignee (if any) plus
 * every `manageSupportCases` holder in that case's empresa — same
 * "encargado + supervisión" shape `onTaskCreate.js` already uses for tasks.
 *
 * `remindersSent` (array of ints already notified) on the case doc stops a
 * threshold from re-firing every day once it's been crossed.
 *
 * Scans `supportCases` without an empresaId filter — same tradeoff
 * `checkReminders.js` already makes for `tasks`: every recipient resolved
 * below is already scoped to that specific case's own empresa, so this
 * doesn't leak anything across tenants, it's just not the most efficient
 * query at scale (fine until that's actually a problem).
 *
 * Deliberately does NOT deep-link the notification to the case yet (no
 * `data.url` the way task pushes get one) — flagged as a follow-up, not
 * done this round.
 */
const checkSupportCaseReminders = onSchedule(
  { schedule: "every day 09:00", timeZone: "America/Bogota" },
  async () => {
    const db = getFirestore();
    const today = todayDateKey();

    const snap = await db.collection("supportCases").where("status", "in", OPEN_STATUSES).get();
    if (snap.empty) return;

    const supervisorCache = new Map();
    async function supervisorsFor(empresaId) {
      if (!empresaId) return [];
      if (!supervisorCache.has(empresaId)) {
        supervisorCache.set(empresaId, await getSupportCaseSupervisorIds(db, empresaId));
      }
      return supervisorCache.get(empresaId);
    }

    await Promise.all(
      snap.docs.map(async (doc) => {
        try {
          const c = doc.data();
          const reportedAt = c.reportedAt?.toDate?.();
          if (!reportedAt) return;

          const daysOpen = dayDiff(today, dateKeyFor(reportedAt));
          const crossed = THRESHOLDS.find((t) => t === daysOpen);
          if (!crossed) return;

          const alreadySent = Array.isArray(c.remindersSent) ? c.remindersSent : [];
          if (alreadySent.includes(crossed)) return;

          const recipientIds = new Set();
          if (c.assignedUserId) recipientIds.add(c.assignedUserId);
          for (const id of await supervisorsFor(c.empresaId)) recipientIds.add(id);
          if (recipientIds.size === 0) return;

          const meta = THRESHOLD_META[crossed];
          const caseLabel = `CS-${String(c.caseNumber || 0).padStart(4, "0")}`;

          const count = await sendNotificationToUsers([...recipientIds], {
            title: `${meta.emoji} Caso ${caseLabel} sin resolver (${crossed} días)`,
            body: `${c.clientName || "Cliente"} · ${meta.label}: ${c.subject || ""}`,
            data: {
              type: "support_case_reminder",
              caseId: doc.id,
              empresaId: c.empresaId || "",
              threshold: String(crossed),
            },
          });

          await doc.ref.update({ remindersSent: FieldValue.arrayUnion(crossed) });

          console.log(`[SUPPORT_CASE_REMINDER] ${caseLabel} crossed ${crossed}d, notified ${recipientIds.size}, push sent ${count}`);
        } catch (e) {
          console.error(`[SUPPORT_CASE_REMINDER][ERROR] ${doc.id}: ${e}`);
        }
      })
    );
  }
);

module.exports = { checkSupportCaseReminders };
