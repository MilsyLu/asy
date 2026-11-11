const { getFirestore } = require("firebase-admin/firestore");
const { sendNotificationToUser } = require("./notifications");

/**
 * Avisa a quien asignó la tarea cuando alguien la completa.
 *
 * El que reparte trabajo no tenía forma de enterarse de que algo se hizo
 * sin volver a abrir la agenda y revisarla tarea por tarea. Esto cierra el
 * círculo: quien mandó la tarea recibe el aviso de que ya está.
 *
 * Tres cosas que parecen detalles y no lo son:
 *
 * 1. **Dice quién la completó de verdad.** `completedBy` no siempre es el
 *    encargado — un administrador puede marcar la tarea de otro. Antes sólo
 *    se guardaba la hora, así que cualquier aviso habría tenido que suponer
 *    que fue el encargado, y acreditar a quien no fue es peor que no decir
 *    nada.
 *
 * 2. **No se avisa a uno mismo.** Quien se asigna una tarea y la completa no
 *    necesita que le cuenten lo que acaba de hacer. Misma regla que en
 *    `onTaskCreate.js`.
 *
 * 3. **La hora es la de verdad.** Se muestra cuándo la completó, no para qué
 *    hora estaba programada. Son distintas, y la diferencia entre las dos es
 *    justo el dato que le interesa a quien reparte.
 *
 * Las tareas sin `createdBy` —las viejas y las que entran por la hoja de
 * cálculo— no tienen a quién avisarle, y se dejan pasar en silencio.
 */

/** La hora como se lee en Colombia: "6:45 p. m.". */
function horaLocal(date) {
  return new Intl.DateTimeFormat("es-CO", {
    timeZone: "America/Bogota",
    hour: "numeric",
    minute: "2-digit",
  }).format(date);
}

/**
 * Cómo se cuenta lo que pasó, según quién lo hizo.
 *
 * Pura y exportada para poder probarla: es la regla que decide si el aviso
 * acredita a una persona o a otra.
 *
 * @param {string|null} completadaPor id de quien la marcó
 * @param {string|null} encargado id del encargado de la tarea
 * @param {(id: string|null) => string|null} nombreDe
 * @returns {string}
 */
function fraseDeCompletado(completadaPor, encargado, nombreDe) {
  const quien = completadaPor ? nombreDe(completadaPor) : null;
  const deQuien = encargado ? nombreDe(encargado) : null;

  // Nadie registrado: las tareas marcadas antes de que se guardara el dato,
  // o desde fuera de la app. Se dice lo que sí se sabe.
  if (!quien) return "Se completó la tarea";

  if (completadaPor === encargado || !deQuien) return `${quien} completó la tarea`;

  return `${quien} marcó como completada la tarea de ${deQuien}`;
}

/**
 * @param {string} taskId
 * @param {Record<string, any>} before
 * @param {Record<string, any>} after
 */
async function notifyTaskCompleted(taskId, before, after) {
  // Sólo la transición. `onDocumentUpdated` se dispara con cualquier
  // escritura —un comentario, una etiqueta—, y sin esto el aviso se
  // repetiría cada vez que alguien toque una tarea ya completada.
  if (!after.statusId || after.statusId === before.statusId) return;
  if (after.isDeleted) return;

  const db = getFirestore();
  // El estado se reconoce por su nombre, igual que en toda la app: los
  // estados los crea cada empresa y no llevan una clave fija. Se lee el
  // estado nuevo de la tarea, en vez de buscar "Completada" dentro de la
  // empresa, que son dos consultas para la misma respuesta.
  const estadoSnap = await db.collection("statuses").doc(after.statusId).get();
  const nombreEstado = (estadoSnap.exists ? estadoSnap.get("name") || "" : "")
    .trim()
    .toLowerCase();
  if (nombreEstado !== "completada") return;

  const destinatario = after.createdBy;
  if (!destinatario) {
    console.log(`[FCM] Completada ${taskId}: sin quien la asignara, no hay a quien avisar`);
    return;
  }

  const completadaPor = after.completedBy || null;
  if (completadaPor && completadaPor === destinatario) {
    console.log(`[FCM] Completada ${taskId}: la completó quien la asignó`);
    return;
  }

  const [tipoSnap, completadorSnap, encargadoSnap] = await Promise.all([
    after.taskTypeId ? db.collection("taskTypes").doc(after.taskTypeId).get() : null,
    completadaPor ? db.collection("users").doc(completadaPor).get() : null,
    after.assignedUserId ? db.collection("users").doc(after.assignedUserId).get() : null,
  ]);

  const nombres = new Map();
  if (completadorSnap && completadorSnap.exists) {
    nombres.set(completadaPor, completadorSnap.get("name") || null);
  }
  if (encargadoSnap && encargadoSnap.exists) {
    nombres.set(after.assignedUserId, encargadoSnap.get("name") || null);
  }
  const nombreDe = (id) => nombres.get(id) || null;

  const tipo = tipoSnap && tipoSnap.exists ? tipoSnap.get("name") || "Tarea" : "Tarea";
  const frase = fraseDeCompletado(completadaPor, after.assignedUserId, nombreDe);

  // La hora en que se completó, no la hora para la que estaba.
  const completadaEn = after.completedAt?.toDate?.() || new Date();

  const cliente = after.clientName ? `\nCliente: ${after.clientName}` : "";
  const body = `${frase}\n${tipo}${cliente}\nCompletada a las ${horaLocal(completadaEn)}`;

  const enviados = await sendNotificationToUser(destinatario, {
    title: "✅ Tarea completada",
    body,
    data: {
      taskId,
      type: "task_completed_creator",
      assignedUserId: after.assignedUserId || "",
      groupId: after.groupId || "",
    },
  });
  console.log(`[FCM] Completada ${taskId}: avisado ${destinatario} (push: ${enviados})`);
}

module.exports = { notifyTaskCompleted, fraseDeCompletado, horaLocal };
