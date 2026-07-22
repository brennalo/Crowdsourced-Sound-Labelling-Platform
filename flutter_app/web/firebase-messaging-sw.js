// Deploy this at the web root: web/firebase-messaging-sw.js (same folder as
// web/index.html). Firebase Hosting will serve it at
// https://your-app.web.app/firebase-messaging-sw.js automatically — no
// hosting config changes needed, it just needs to exist in that folder
// before your next `flutter build web` + deploy.

importScripts(
  'https://www.gstatic.com/firebasejs/10.12.0/firebase-app-compat.js',
);
importScripts(
  'https://www.gstatic.com/firebasejs/10.12.0/firebase-messaging-compat.js',
);

// Copy these 6 values verbatim from lib/firebase_options.dart, the `web:`
// FirebaseOptions block (flutterfire configure already generated it for
// you). They are safe to be public in this file — they identify the
// project, they are not secret keys.
firebase.initializeApp({
  apiKey: 'AIzaSyBFc6AL2t4EVCL9hMWjnNxvWO0-1WBp1lI',
  appId: '1:841974142704:web:061dc3037c5d0e9cfb9435',
  messagingSenderId: '841974142704',
  projectId: 'crowdsourced-sound-labelling',
  authDomain: 'crowdsourced-sound-labelling.firebaseapp.com',
  storageBucket: 'crowdsourced-sound-labelling.firebasestorage.app',
});

const messaging = firebase.messaging();

// Handles pushes while the tab isn't focused/open. Foreground pushes (tab
// open and focused) are instead handled in Dart via FirebaseMessaging.onMessage
// in push_service.dart — this file only covers the background case.
messaging.onBackgroundMessage((payload) => {
  const { title, body } = payload.notification || {};
  if (!title) return; // data-only pushes (no visible notification) — nothing to show
  self.registration.showNotification(title, {
    body: body || '',
    icon: '/icons/Icon-192.png',
  });
});
