const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { getFirestore } = require("firebase-admin/firestore");
const {
  sendNotificationToUsers,
  getRequirementSupervisorIds,
} = require("./notifications");

/** REQ-0042, igual que `RequirementModel.codigo` en la app. */
function codigo(numero) {
  return `REQ-${String(numero || 0).padStart(4, "0")}`;
}

/**
 * La descripcion, recortada para que quepa en un aviso del celular.
 *
 * Las descripciones de los requerimientos son especificaciones: las que
 * llegaron de la hoja pasan de 1.500 caracteres. Un aviso no es el sitio
 * para leerlas — lo que tiene que lograr es que la persona reconozca de que
 * se trata y abra el requerimiento.
 */
function resumen(texto) {
  const limpio = (texto || "").replace(/\s+/g, " ").trim();
  if (limpio.length <= 110) return limpio;
  return `${limpio.substring(0, 109)}…`;
}

/** Para quien es, en una linea. Misma regla que `RequirementModel.paraQuien`. */
function paraQuien(requerimiento) {
  const nombres = Array.isArray(requerimiento.clientNames)
    ? requerimiento.clientNames.filter((n) => typeof n === "string" && n.trim().length > 0)
    : [];
  if (nombres.length > 0) return nombres.join(", ");
  return requerimiento.origin === "interno" ? "Interno" : "General";
}

/**
 * Avisa de un requerimiento nuevo a quien le toca aprobarlo y asignarlo.
 *
 * Hasta ahora un requerimiento se creaba en silencio: ni push, ni campana,
 * ni nada. Quien tenia que actuar sobre el se enteraba la proxima vez que
 * abriera la pantalla de Requerimientos por su cuenta, que es justo lo que
 * pasaba con la hoja de calculo que este modulo vino a reemplazar.
 *
 * Quien recibe el aviso: ver [getRequirementSupervisorIds] — se decide por
 * el permiso `manageRequirements`, no por una lista aparte. Menos quien lo
 * acaba de registrar: avisarle de su propia accion es la forma mas rapida
 * de que la gente aprenda a ignorar los avisos.
 *
 * El interruptor: `users/{uid}.avisarRequerimientoNuevo`. En `false` esta
 * persona no recibe nada por este concepto — tampoco la campana, a
 * diferencia de `pushNotificationMode`, que solo calla el push y deja el
 * registro. Son dos cosas distintas a proposito: ese modo dice "no me
 * suenes el telefono", este dice "este aviso no lo quiero".
 */
const notifyRequirementCreated = onDocumentCreated(
  "requirements/{reqId}",
  async (event) => {
    const requirementId = event.params.reqId;
    const requerimiento = event.data?.data();
    if (!requerimiento) return;

    const { empresaId, receivedById, receivedByName, type, description } = requerimiento;
    if (!empresaId) {
      console.log(`[REQ] Sin empresaId, no se avisa: ${requirementId}`);
      return;
    }

    const db = getFirestore();

    try {
      const ids = (await getRequirementSupervisorIds(db, empresaId)).filter(
        (id) => id !== receivedById
      );
      if (ids.length === 0) {
        console.log(`[REQ] Nadie a quien avisar: ${requirementId}`);
        return;
      }

      // El interruptor se consulta aqui, antes de enviar, porque apaga
      // tambien el registro de la campana — y ese lo escribe
      // sendNotificationToUser pase lo que pase con el push.
      const docs = await db.getAll(...ids.map((id) => db.collection("users").doc(id)));
      const destinatarios = docs
        .filter((d) => d.exists && d.get("avisarRequerimientoNuevo") !== false)
        .map((d) => d.id);

      if (destinatarios.length === 0) {
        console.log(`[REQ] Todos lo tienen apagado: ${requirementId}`);
        return;
      }

      const quien = receivedByName || "Alguien";
      const descripcion = resumen(description);
      const cuerpo =
        `${quien} registró un requerimiento de ${type || "Mejoras"}\n` +
        `Para: ${paraQuien(requerimiento)}` +
        (descripcion ? `\n${descripcion}` : "");

      const count = await sendNotificationToUsers(destinatarios, {
        title: `📝 Nuevo requerimiento ${codigo(requerimiento.requirementNumber)}`,
        body: cuerpo,
        data: { requirementId, type: "requirement_created" },
      });

      console.log(`[REQ] Avisados: ${destinatarios.length} — push: ${count}`);
    } catch (e) {
      console.error(`[REQ][ERROR] Aviso de requerimiento ${requirementId}: ${e}`);
    }
  }
);

module.exports = { notifyRequirementCreated, resumen, paraQuien, codigo };
