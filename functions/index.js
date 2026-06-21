const { initializeApp } = require("firebase-admin/app");

initializeApp();

const { onTaskCreate } = require("./src/onTaskCreate");
const { checkReminders } = require("./src/checkReminders");
const { deleteUserPermanently } = require("./src/deleteUser");
const { cleanOldNotifications } = require("./src/cleanOldNotifications");

exports.onTaskCreate = onTaskCreate;
exports.checkReminders = checkReminders;
exports.deleteUserPermanently = deleteUserPermanently;
exports.cleanOldNotifications = cleanOldNotifications;
