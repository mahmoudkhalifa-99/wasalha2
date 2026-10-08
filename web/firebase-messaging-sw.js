/* Firebase Cloud Messaging service worker for Wasalha web. */
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyDlfpN0JCsmpCKdTyb4ZX_QN0sZbypIv48',
  authDomain: 'sada-51292.firebaseapp.com',
  projectId: 'sada-51292',
  storageBucket: 'sada-51292.firebasestorage.app',
  messagingSenderId: '821734316791',
  appId: '1:821734316791:web:a41030678e2ecaa168d1f2',
  measurementId: 'G-XZMSDBYW43'
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const title = payload?.notification?.title || payload?.data?.title || 'وصلها';
  const body = payload?.notification?.body || payload?.data?.body || '';
  self.registration.showNotification(title, {
    body,
    icon: '/assets/assets/images/icon-192.png',
    badge: '/assets/assets/images/icon-192.png'
  });
});
