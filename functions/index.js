const { initializeApp } = require("firebase-admin/app");

initializeApp();

const { onTaskCreate } = require("./src/onTaskCreate");
const { onTaskUpdate } = require("./src/onTaskUpdate");
const { checkReminders } = require("./src/checkReminders");
const { deleteUserPermanently } = require("./src/deleteUser");
const { cleanOldNotifications } = require("./src/cleanOldNotifications");
const { syncTaskFromSheet } = require("./src/syncTaskFromSheet");

exports.onTaskCreate = onTaskCreate;
exports.onTaskUpdate = onTaskUpdate;
exports.checkReminders = checkReminders;
exports.deleteUserPermanently = deleteUserPermanently;
exports.cleanOldNotifications = cleanOldNotifications;
exports.syncTaskFromSheet = syncTaskFromSheet;
