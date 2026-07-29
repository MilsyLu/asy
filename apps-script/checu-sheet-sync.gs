/**
 * CheCu ↔ Google Sheets bridge.
 *
 * Watches the day-of-week tabs (LUNES..VIERNES) in this spreadsheet. Every
 * time a row in one of them is edited, it sends that row to CheCu's
 * `syncTaskFromSheet` Cloud Function, which creates the task the first time
 * (column CHECU_ID is still empty) or updates the same task on later edits
 * (column CHECU_ID already has an id) — so editing a row's Fecha/Hora and
 * Estado to "Reprogramado" behaves exactly like reprogramming the task
 * inside CheCu itself, including the push notification.
 *
 * === Setup (one time) ===
 * 1. Extensions → Apps Script, paste this whole file in (replacing the
 *    default Code.gs content), save.
 * 2. Project Settings (gear icon) → Script Properties → add two properties:
 *      CHECU_FUNCTION_URL = https://us-central1-chhecu.cloudfunctions.net/syncTaskFromSheet
 *      CHECU_SHEET_SECRET  = <the secret value Claude generated — ask for it,
 *                             never paste it directly into this script body>
 * 3. In the Apps Script editor, run `installTrigger` once (Run button, pick
 *    that function) and approve the permissions Google asks for. This sets
 *    up the "on edit" listener — you only do this once, not every time you
 *    edit the sheet.
 * 4. In the spreadsheet itself, make sure each day tab (LUNES, MARTES,
 *    MIÉRCOLES, JUEVES, VIERNES) has these columns, in this exact order,
 *    starting at column A:
 *      A Cliente | B Contacto | C Fecha | D Hora | E Instala |
 *      F Comentario | G Estado | H Tipo de tarea | I Estado de sincronización
 *    Column I is filled in automatically by this script (✅/❌ + the CheCu
 *    task id) — don't type into it by hand.
 *
 * === Important ===
 * The dropdown values you use in E (Instala), G (Estado) and H (Tipo de
 * tarea) must be spelled *exactly* like the corresponding names in CheCu
 * (Panel de administración → Usuarios/Estados/Tipos de tarea) — this script
 * matches by exact name, not a fuzzy guess.
 */

const DAY_SHEETS = ['LUNES', 'MARTES', 'MIÉRCOLES', 'JUEVES', 'VIERNES'];

const COL = {
  CLIENTE: 1,
  CONTACTO: 2,
  FECHA: 3,
  HORA: 4,
  INSTALA: 5,
  COMENTARIO: 6,
  ESTADO: 7,
  TIPO_TAREA: 8,
  SYNC_STATUS: 9,
};

/** Run this once from the Apps Script editor to set up the on-edit listener. */
function installTrigger() {
  const ss = SpreadsheetApp.getActive();
  // Remove any previous installations of this trigger first, so re-running
  // this function is safe instead of stacking up duplicate triggers.
  ScriptApp.getProjectTriggers()
    .filter((t) => t.getHandlerFunction() === 'onCheCuEdit')
    .forEach((t) => ScriptApp.deleteTrigger(t));

  ScriptApp.newTrigger('onCheCuEdit').forSpreadsheet(ss).onEdit().create();
  SpreadsheetApp.getUi().alert('Listo — CheCu ya está conectado a este Excel.');
}

/** Installable onEdit trigger — fires on every cell edit, any sheet. */
function onCheCuEdit(e) {
  try {
    const sheet = e.range.getSheet();
    const sheetName = sheet.getName().toUpperCase();
    if (DAY_SHEETS.indexOf(sheetName) === -1) return;

    const row = e.range.getRow();
    if (row === 1) return; // header row

    // A single edit can span multiple rows (paste); handle each one.
    const firstRow = row;
    const lastRow = row + e.range.getNumRows() - 1;
    for (let r = firstRow; r <= lastRow; r++) {
      syncRow(sheet, r);
    }
  } catch (err) {
    console.error('onCheCuEdit failed: ' + err);
  }
}

function syncRow(sheet, row) {
  const values = sheet.getRange(row, 1, 1, COL.SYNC_STATUS).getValues()[0];

  const clientName = String(values[COL.CLIENTE - 1] || '').trim();
  const clientPhone = String(values[COL.CONTACTO - 1] || '').trim();
  const fechaRaw = values[COL.FECHA - 1];
  const horaRaw = values[COL.HORA - 1];
  const assignedUserName = String(values[COL.INSTALA - 1] || '').trim();
  const observations = String(values[COL.COMENTARIO - 1] || '').trim();
  const statusName = String(values[COL.ESTADO - 1] || '').trim();
  const taskTypeName = String(values[COL.TIPO_TAREA - 1] || '').trim();
  const existingSyncStatus = String(values[COL.SYNC_STATUS - 1] || '').trim();

  // Wait until the row has the minimum needed to create/update a task.
  if (!clientName || !fechaRaw || !horaRaw || !assignedUserName) return;

  const date = formatDate(fechaRaw);
  const hour = formatHour(horaRaw);
  if (!date || !hour) return;

  // The sync-status column doubles as the "already created?" marker: once
  // synced it holds "✅ <taskId>", so the CheCu task id is parsed back out
  // of it for updates instead of needing a separate hidden column.
  const existingTaskId = parseTaskId(existingSyncStatus);

  const payload = {
    taskId: existingTaskId,
    clientName: clientName,
    clientPhone: clientPhone,
    date: date,
    hour: hour,
    assignedUserName: assignedUserName,
    observations: observations,
    statusName: statusName,
    taskTypeName: taskTypeName,
  };

  const props = PropertiesService.getScriptProperties();
  const url = props.getProperty('CHECU_FUNCTION_URL');
  const secret = props.getProperty('CHECU_SHEET_SECRET');
  if (!url || !secret) {
    sheet.getRange(row, COL.SYNC_STATUS).setValue('❌ Falta configurar CHECU_FUNCTION_URL/CHECU_SHEET_SECRET');
    return;
  }

  const response = UrlFetchApp.fetch(url, {
    method: 'post',
    contentType: 'application/json',
    headers: { 'X-Sheet-Secret': secret },
    payload: JSON.stringify(payload),
    muteHttpExceptions: true,
  });

  const status = response.getResponseCode();
  const body = JSON.parse(response.getContentText() || '{}');

  if (status === 200 && body.taskId) {
    sheet.getRange(row, COL.SYNC_STATUS).setValue('✅ ' + body.taskId);
  } else {
    sheet.getRange(row, COL.SYNC_STATUS).setValue('❌ ' + (body.error || ('HTTP ' + status)));
  }
}

/** Extracts the CheCu task id back out of a "✅ <taskId>" status cell. */
function parseTaskId(syncStatusText) {
  if (!syncStatusText || syncStatusText.indexOf('✅') !== 0) return null;
  const id = syncStatusText.replace('✅', '').trim();
  return id || null;
}

/** Cell value → "YYYY-MM-DD". Accepts a real Date (typed date cell) or text. */
function formatDate(value) {
  if (Object.prototype.toString.call(value) === '[object Date]') {
    return Utilities.formatDate(value, Session.getScriptTimeZone(), 'yyyy-MM-dd');
  }
  const text = String(value).trim();
  const m = text.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/); // DD/MM/YYYY
  if (m) {
    const day = m[1].padStart(2, '0');
    const month = m[2].padStart(2, '0');
    return `${m[3]}-${month}-${day}`;
  }
  return null;
}

/** Cell value → 24h "HH:MM". Accepts a real time/Date or "4:00 PM" text. */
function formatHour(value) {
  if (Object.prototype.toString.call(value) === '[object Date]') {
    return Utilities.formatDate(value, Session.getScriptTimeZone(), 'HH:mm');
  }
  const text = String(value).trim().toUpperCase();
  const m = text.match(/^(\d{1,2}):(\d{2})\s*(AM|PM)?$/);
  if (!m) return null;
  let hour = parseInt(m[1], 10);
  const minute = m[2];
  const meridiem = m[3];
  if (meridiem === 'PM' && hour !== 12) hour += 12;
  if (meridiem === 'AM' && hour === 12) hour = 0;
  return `${String(hour).padStart(2, '0')}:${minute}`;
}
