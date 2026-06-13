const { initializeApp } = require("firebase-admin/app");

initializeApp();

const { onTaskCreate } = require("./src/onTaskCreate");
const { checkReminders } = require("./src/checkReminders");

exports.onTaskCreate = onTaskCreate;
exports.checkReminders = checkReminders;
