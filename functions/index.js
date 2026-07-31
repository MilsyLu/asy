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

exports.onTaskCreate = onTaskCreate;
exports.onTaskUpdate = onTaskUpdate;
exports.checkReminders = checkReminders;
exports.deleteUserPermanently = deleteUserPermanently;
exports.cleanOldNotifications = cleanOldNotifications;
exports.syncTaskFromSheet = syncTaskFromSheet;
exports.createEmpresa = createEmpresa;
exports.toggleEmpresa = toggleEmpresa;
exports.extractPrinterConfigFromImages = extractPrinterConfigFromImages;
