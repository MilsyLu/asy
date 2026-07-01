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

messaging.onBackgroundMessage((payload) => {
  const notif = (payload && payload.notification) || {};
  const title = notif.title || 'CheCu';
  const body  = notif.body  || '';

  return self.registration.showNotification(title, {
    body,
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    data: { url: self.location.origin + '/', ...(payload.data || {}) },
  });
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const target = (event.notification.data && event.notification.data.url)
    || self.location.origin + '/';
  event.waitUntil(
    clients
      .matchAll({ type: 'window', includeUncontrolled: true })
      .then((windowClients) => {
        for (const client of windowClients) {
          if (client.url === target && 'focus' in client) return client.focus();
        }
        return clients.openWindow(target);
      })
  );
});
