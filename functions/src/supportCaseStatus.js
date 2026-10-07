/**
 * Which support-case statuses count as still open.
 *
 * Single definition shared by the reminder functions. It was written out in
 * `checkSupportCaseReminders.js` and simply missing from
 * `checkSupportCaseCustomReminders.js`, which is how a reminder kept arriving
 * for a case that had already been resolved. Two copies of a rule is how the
 * third one ends up forgotten; one copy cannot drift.
 *
 * These are the literal strings stored on each document — the same values as
 * `SupportCaseStatus` on the Dart side, where the display label was changed to
 * "Pendiente" while the stored value stayed "Nuevo" precisely so this list
 * would keep matching.
 */
const OPEN_STATUSES = ["Nuevo", "En proceso", "Reportado", "Esperando cliente"];

/** Whether [status] is one a case can still be worked on. */
function isOpen(status) {
  return OPEN_STATUSES.includes(status);
}

module.exports = { OPEN_STATUSES, isOpen };
