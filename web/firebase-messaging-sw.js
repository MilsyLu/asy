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

// IMPORTANT: this listener does NOT run for pushes sent through FCM.
//
// `firebase.messaging()` above installs the SDK's own `notificationclick`
// listener, and that one begins with `event.stopImmediatePropagation()` for
// any notification it recognises as its own — which silently prevents every
// listener registered after it, including this one, from ever executing.
// Clicks on FCM notifications are therefore handled entirely by the SDK,
// which navigates to `webpush.fcmOptions.link` (set in
// functions/src/notifications.js). That is the setting to change if the
// destination is ever wrong; editing the code below will have no effect.
//
// This handler is kept only for notifications this worker might display
// itself in the future, outside the FCM path.
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
      // This worker is registered at `/firebase-cloud-messaging-push-scope`
      // (see web/index.html) while the app itself lives at `/`, so it
      // controls no window clients at all. That rules out `client.navigate()`
      // — the spec has it reject with TypeError for any client this worker
      // doesn't control, which here means *every* client, on every click.
      //
      // `focus()` and `postMessage()` carry no such restriction, so the tab is
      // brought forward here and then told where to go; index.html listens for
      // this message and performs the navigation from the page side, where it
      // is an ordinary same-origin navigation. `openWindow` stays as the
      // fallback for when no CheCu tab is open at all.
      try {
        const windowClients = await clients.matchAll({ type: 'window', includeUncontrolled: true });
        const existing = windowClients.find((c) => c.url.startsWith(self.location.origin));
        if (existing) {
          // focus() resolves successfully even when the browser declines to
          // act on it — restoring a *minimized* Chrome window on Windows is
          // the case that silently does nothing, which is precisely the
          // symptom this handler exists to fix. So the result is verified
          // rather than trusted: if the tab did not actually come forward,
          // fall through to openWindow, which does raise the browser
          // reliably (at the cost of a second tab).
          const focused = (await existing.focus()) || existing;
          if (focused.visibilityState === 'visible') {
            focused.postMessage({ type: 'checu-notification-click', url: target });
            console.log('[FCM] notificationclick: focused existing tab and sent it', target);
            return;
          }
          console.log(
            '[FCM] notificationclick: focus() did not surface the tab (visibilityState=' +
              focused.visibilityState + ') — falling back to openWindow'
          );
        }
      } catch (e) {
        console.log('[FCM] notificationclick: focusing an open tab failed, opening a new one —', e);
      }
      console.log('[FCM] notificationclick: opening a new window at', target);
      await clients.openWindow(target);
    })()
  );
});
