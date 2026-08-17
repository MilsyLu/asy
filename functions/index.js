const { initializeApp } = require("firebase-admin/app");

initializeApp();

const { onTaskCreate } = require("./src/onTaskCreate");
const { onTaskUpdate } = require("./src/onTaskUpdate");
const { checkReminders } = require("./src/checkReminders");
const { deleteUserPermanently } = require("./src/deleteUser");
const { cleanOldNotifications } = require("./src/cleanOldNotifications");
const { syncTaskFromSheet } = require("./src/syncTaskFromSheet");
const { createEmpresa } = require("./src/createEmpresa");
const { toggleEmpresa } = require("./src/toggleEmpresa");
const { extractPrinterConfigFromImages } = require("./src/extractPrinterConfigFromImages");
const { checkSupportCaseReminders } = require("./src/checkSupportCaseReminders");
const { checkSupportCaseCustomReminders } = require("./src/checkSupportCaseCustomReminders");
const { createTeamAsScopedAdmin } = require("./src/createTeamAsScopedAdmin");
const { syncEmpresaClaim } = require("./src/syncEmpresaClaim");

exports.onTaskCreate = onTaskCreate;
exports.onTaskUpdate = onTaskUpdate;
exports.checkReminders = checkReminders;
exports.deleteUserPermanently = deleteUserPermanently;
exports.cleanOldNotifications = cleanOldNotifications;
exports.syncTaskFromSheet = syncTaskFromSheet;
exports.createEmpresa = createEmpresa;
exports.toggleEmpresa = toggleEmpresa;
exports.extractPrinterConfigFromImages = extractPrinterConfigFromImages;
exports.checkSupportCaseReminders = checkSupportCaseReminders;
exports.checkSupportCaseCustomReminders = checkSupportCaseCustomReminders;
exports.createTeamAsScopedAdmin = createTeamAsScopedAdmin;
exports.syncEmpresaClaim = syncEmpresaClaim;
