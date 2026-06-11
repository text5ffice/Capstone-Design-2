# 장시간 정지 감지 모듈

건설현장 안전관리 시스템 - 장시간 정지(60초 이상) 감지 기능

## 동작 흐름

```
가속도계/자이로 센서
       ↓
StopDetectionService (60초 타이머 모니터링)
       ↓ 60초 이상 정지 감지 시
StopDetectionController (병렬 실행)
   ├── AlertService        → 스마트폰 음성 안내 + 부저음
   ├── HardwareNotifier    → 현장 장치 삐용삐용 적색 부저
   └── PushNotifier        → 관리자 앱 푸시 알림 + 정지 위치 전송
```

## 파일 구조

```
lib/
├── services/
│   ├── stop_detection_service.dart     # 센서 감지 + 60초 타이머
│   ├── alert_service.dart              # 음성/부저 재생
│   ├── hardware_notifier.dart          # 현장 하드웨어 HTTP 신호
│   ├── push_notifier.dart              # 관리자 푸시 알림
│   └── stop_detection_controller.dart  # 전체 통합 컨트롤러
└── screens/
    └── stop_detection_screen.dart      # UI 화면
```

## 사용법

```dart
// 기본 사용 (MockPushNotifier로 테스트)
StopDetectionScreen(
  workerId: 'W001',
  workerName: '홍길동',
)

// 컨트롤러 직접 사용 시
final controller = StopDetectionController(
  workerId: 'W001',
  workerName: '홍길동',
  hardwareUrl: 'http://현장장치IP:5000',
  pushNotifier: FcmPushNotifier(           // 백엔드 준비되면 교체
    backendUrl: 'https://your-backend.com/api',
    authToken: 'your-token',
  ),
  onAlertTriggered: (event) {
    print('정지 감지: ${event.position}');
  },
);

await controller.start();
```

## TODO

- [ ] `assets/sounds/buzzer_alert.mp3` 파일 추가
- [ ] `hardwareUrl` 실제 현장 장치 IP로 변경
- [ ] 백엔드 준비 후 `MockPushNotifier` → `FcmPushNotifier` 교체
- [ ] Firebase 설정 (google-services.json / GoogleService-Info.plist)
- [ ] Android `AndroidManifest.xml` 권한 추가:
  ```xml
  <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
  <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
  ```
- [ ] iOS `Info.plist` 위치 권한 설명 추가

## 정지 감지 로직

- 가속도계: 중력 제거 후 이동 크기 < 0.5 m/s²
- 자이로스코프: 회전 크기 < 0.1 rad/s
- 두 조건 모두 10회 이동평균으로 노이즈 필터링
- 60초 이상 유지되면 감지
