// web/firebase-messaging-sw.js
importScripts('https://www.gstatic.com/firebasejs/9.10.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/9.10.0/firebase-messaging-compat.js');

firebase.initializeApp({
    apiKey: "AIzaSyBtS42vOJrBfLUxGF5viQ4GJLXBvwaf-hU",
    authDomain: "mddprod-2954f.firebaseapp.com",
    projectId: "mddprod-2954f",
    storageBucket: "mddprod-2954f.firebasestorage.app",
    messagingSenderId: "21940943998",
    appId: "1:21940943998:web:4c752c992d2ef5f4ffec2f",
    measurementId: "G-PC7F73PN6E"
});

const messaging = firebase.messaging();

// Optional: Handle background messages
messaging.onBackgroundMessage((payload) => {
    console.log('[firebase-messaging-sw.js] Received background message ', payload);
    const notificationTitle = payload.notification.title;
    const notificationOptions = {
        body: payload.notification.body,
        icon: '/favicon.png'
    };

    self.registration.showNotification(notificationTitle, notificationOptions);
});
