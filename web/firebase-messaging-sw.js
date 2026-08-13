// CheCu — FCM Background Push Service Worker
// Official FlutterFire pattern: firebase-messaging-compat SDK.

importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyB3vZ7n8gFrh_H6pRcUwoRsul1X-mWl35g',
  authDomain: 'chhecu.firebaseapp.com',
  projectId: 'chhecu',
  storageBucket: 'chhecu.firebasestorage.app',
  messagingSenderId: '1065136957290',
  appId: '1:1065136957290:web:6014aa111c59097b69a713',
});

const messaging = firebase.messaging();

// Chrome auto-displays the push's `notification` payload for background
// tabs on its own (independent of this handler) — the Cloud Functions
// payload now carries `webpush.notification.icon` (see
// functions/src/notifications.js) so that auto-displayed notification
// already shows the logo. Calling `showNotification` here too used to
// produce a *second*, icon-less notification for every push; this handler
// is kept only in case future custom background handling is needed, and
// intentionally does not display anything itself.
messaging.onBackgroundMessage((payload) => {
  console.log('[FCM] Background message received (auto-displayed by the browser):', payload);
});

// The Cloud Functions layer (functions/src/notifications.js) sets
// data.url = "<origin>/?openTask=<taskId>" (or "?openCase=<caseId>" for
// Casos de Soporte) on every business push. The app reads that query param
// at startup (main_shell.dart) and opens the task/case detail, then strips
// it from the URL bar.
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const target = (event.notification.data && event.notification.data.url)
    || self.location.origin + '/';
  event.waitUntil(
    clients
      .matchAll({ type: 'window', includeUncontrolled: true })
      .then((windowClients) => {
        for (const client of windowClients) {
          if ('focus' in client) {
            // Reuse the already-open tab instead of opening a new one — but
            // it also needs to actually load the new URL (the app doesn't
            // poll for query-param changes), not just regain focus.
            if ('navigate' in client) {
              return client.navigate(target).then((c) => (c || client).focus());
            }
            return client.focus();
          }
        }
        return clients.openWindow(target);
      })
  );
});
