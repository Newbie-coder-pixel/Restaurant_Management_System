importScripts("https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js");

firebase.initializeApp({
  apiKey: "AIzaSyAdAxpxwZmZRAIy94sEbMaf3pqV-euPL1c",
  authDomain: "restaurant-management-sy-db090.firebaseapp.com",
  projectId: "restaurant-management-sy-db090",
  storageBucket: "restaurant-management-sy-db090.firebasestorage.app",
  messagingSenderId: "760099392262",
  appId: "1:760099392262:web:5a91ab21ce7a2786002c87",
  measurementId: "G-9R35JT1DX5"
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const { title, body } = payload.notification ?? {};
  if (title) {
    self.registration.showNotification(title, { body: body ?? '' });
  }
});
