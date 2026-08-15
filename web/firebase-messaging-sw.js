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

// Without this, a newly-deployed service worker sits "waiting" until every
// tab/PWA session of chhecu.web.app is fully closed and reopened — on a
// phone where the app is rarely closed outright, a click-to-open fix like
// this one could otherwise never actually take effect for a real user, even
// though it's live in production. skipWaiting + clients.claim makes every
// deploy take over immediately for already-open sessions too.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(clients.claim()));

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
  const notifData = event.notification.data || {};
  // Firebase's compat SDK auto-display path (see messaging.onBackgroundMessage
  // above) has, across versions, sometimes nested the original payload under
  // `FCM_MSG` instead of spreading it flat — checked as a fallback so a
  // click still resolves the right target either way.
  const target =
    notifData.url ||
    (notifData.FCM_MSG && notifData.FCM_MSG.data && notifData.FCM_MSG.data.url) ||
    self.location.origin + '/';

  console.log('[FCM] notificationclick, target =', target);

  event.waitUntil(
    (async () => {
      // Reuse an already-open tab instead of opening a new one when
      // possible — but this whole path is best-effort: `navigate()` on a
      // background/discarded Android tab can silently reject, and if that
      // happens with no fallback the click would otherwise just foreground
      // Chrome without ever reaching CheCu. Any failure here falls through
      // to the plain, reliable `clients.openWindow(target)` below instead.
      try {
        const windowClients = await clients.matchAll({ type: 'window', includeUncontrolled: true });
        for (const client of windowClients) {
          if ('navigate' in client) {
            const navigated = await client.navigate(target);
            await (navigated || client).focus();
            return;
          }
          if ('focus' in client) {
            await client.focus();
            return;
          }
        }
      } catch (e) {
        console.log('[FCM] notificationclick: reusing an open tab failed, opening a new one instead —', e);
      }
      await clients.openWindow(target);
    })()
  );
});
