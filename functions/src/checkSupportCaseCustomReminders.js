const { onSchedule } = require("firebase-functions/v2/scheduler");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");
const { sendNotificationToUser } = require("./notifications");
const { isOpen } = require("./supportCaseStatus");

/**
 * Runs every minute. Sends a push notification for every Casos de Soporte
 * case whose `reminderTime` (a one-off personal reminder someone set on that
 * case, e.g. "el lunes debo consultarle algo al equipo de tecno" — see
 * `SupportCaseRepository.setReminder`) has passed and `reminderSent` is
 * still `false`, then marks it as sent so it isn't repeated.
 *
 * Unlike `checkSupportCaseReminders.js` (the automatic 5/10/15-day
 * "días sin resolver" threshold check, which notifies the assignee plus
 * every `manageSupportCases` holder), this notifies ONLY `reminderSetBy` —
 * the one person who scheduled it, matching "si quiero que ME notifique".
 *
 * Same cross-tenant tradeoff as `checkReminders.js`: scans `supportCases`
 * globally without an empresaId filter, but every recipient resolved here
 * is already that specific case's own `reminderSetBy` user, so it doesn't
 * leak anything across tenants.
 */
const checkSupportCaseCustomReminders = onSchedule("every 1 minutes", async () => {
  const db = getFirestore();
  const now = Timestamp.now();

  const snap = await db
    .collection("supportCases")
    .where("reminderSent", "==", false)
    .where("reminderTime", "<=", now)
    .get();

  if (snap.empty) return;

  await Promise.all(
    snap.docs.map(async (doc) => {
      try {
        const c = doc.data();
        const { reminderSetBy, reminderNote, clientName, caseNumber } = c;
        const caseLabel = `CS-${String(caseNumber || 0).padStart(4, "0")}`;

        // Un caso ya resuelto no necesita que le recuerden nada. El
        // recordatorio se marca como consumido igual, para que no se vuelva a
        // leer cada minuto para siempre — su momento ya pasó, y si el caso se
        // reabre lo que corresponde es programar uno nuevo.
        //
        // Se descarta aquí, al dispararse, y no al resolver el caso: así no
        // depende de acordarse de limpiarlo en cada sitio desde donde se puede
        // resolver uno —el desplegable del detalle, arrastrar en el Kanban, o
        // lo que se agregue después—. Es el mismo punto único por el que pasa
        // `checkReminders.js` con las tareas completadas.
        if (!isOpen(c.status)) {
          await doc.ref.update({ reminderSent: true });
          console.log(
            `[SUPPORT_CASE_CUSTOM_REMINDER] ${caseLabel} ya está en "${c.status}" — se descarta`
          );
          return;
        }

        if (reminderSetBy) {
          const count = await sendNotificationToUser(reminderSetBy, {
            title: `Recordatorio · Caso ${caseLabel}`,
            body: reminderNote?.trim()
              ? `${clientName || "Cliente"} — ${reminderNote.trim()}`
              : `${clientName || "Cliente"}`,
            data: {
              type: "support_case_custom_reminder",
              caseId: doc.id,
              empresaId: c.empresaId || "",
            },
          });
          console.log(`[SUPPORT_CASE_CUSTOM_REMINDER] ${caseLabel} notified: ${reminderSetBy}`);
          console.log(`[SUPPORT_CASE_CUSTOM_REMINDER] Push sent: ${count}`);
        }

        await doc.ref.update({ reminderSent: true });
      } catch (e) {
        console.error(`[SUPPORT_CASE_CUSTOM_REMINDER][ERROR] ${doc.id}: ${e}`);
      }
    })
  );
});

module.exports = { checkSupportCaseCustomReminders };
