importScripts("https://www.gstatic.com/firebasejs/10.8.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.8.0/firebase-messaging-compat.js");

// 아까 메모장에 복사해둔 본인의 firebaseConfig 값으로 안의 내용을 꼭 바꿔주세요!
const firebaseConfig = {
  apiKey: "AIzaSyCYbjqUiY2ljMYSzA-nPp9ExuYCFOkfQmk",
  authDomain: "safetymonitor-44947.firebaseapp.com",
  projectId: "safetymonitor-44947",
  storageBucket: "safetymonitor-44947.firebasestorage.app",
  messagingSenderId: "574487045582",
  appId: "1:574487045582:web:f051d7c0c53910d76e379f"
};

firebase.initializeApp(firebaseConfig);
const messaging = firebase.messaging();

// 백그라운드 알림 수신 대기
messaging.onBackgroundMessage(function(payload) {
  console.log('백그라운드 메시지 수신:', payload);
  const notificationTitle = payload.notification.title;
  const notificationOptions = {
    body: payload.notification.body,
  };
  self.registration.showNotification(notificationTitle, notificationOptions);
});