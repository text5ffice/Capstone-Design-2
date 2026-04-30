import 'dart:async';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';

/// 장시간 정지 감지 서비스
/// 가속도계 + 자이로스코프 기반으로 60초 이상 움직임 없으면 감지
class StopDetectionService {
  static const int _stopThresholdSeconds = 60;
  static const double _movementThreshold = 0.5; // m/s² 이하면 정지로 판단

  final void Function(Position position) onStopDetected;
  final void Function() onMovementResumed;

  StreamSubscription<AccelerometerEvent>? _accelSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroSubscription;
  Timer? _stopTimer;

  bool _isRunning = false;
  bool _isStopDetected = false;
  DateTime? _lastMovementTime;

  // 최근 센서값 (노이즈 필터링용 이동평균)
  final List<double> _accelBuffer = [];
  final List<double> _gyroBuffer = [];
  static const int _bufferSize = 10;

  StopDetectionService({
    required this.onStopDetected,
    required this.onMovementResumed,
  });

  /// 서비스 시작
  Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;
    _isStopDetected = false;
    _lastMovementTime = DateTime.now();

    _startSensorListening();
    _startStopTimer();
  }

  /// 서비스 중지
  void stop() {
    _isRunning = false;
    _accelSubscription?.cancel();
    _gyroSubscription?.cancel();
    _stopTimer?.cancel();
    _accelBuffer.clear();
    _gyroBuffer.clear();
  }

  void _startSensorListening() {
    // 가속도계 구독
    _accelSubscription = accelerometerEventStream(
      samplingPeriod: SensorInterval.normalInterval,
    ).listen((AccelerometerEvent event) {
      final magnitude = _calculateMagnitude(event.x, event.y, event.z);
      // 중력(9.8) 제거 후 순수 움직임 크기
      final movement = (magnitude - 9.8).abs();
      _updateBuffer(_accelBuffer, movement);

      if (_getBufferAverage(_accelBuffer) > _movementThreshold) {
        _onMovementDetected();
      }
    });

    // 자이로스코프 구독
    _gyroSubscription = gyroscopeEventStream(
      samplingPeriod: SensorInterval.normalInterval,
    ).listen((GyroscopeEvent event) {
      final magnitude = _calculateMagnitude(event.x, event.y, event.z);
      _updateBuffer(_gyroBuffer, magnitude);

      if (_getBufferAverage(_gyroBuffer) > 0.1) {
        _onMovementDetected();
      }
    });
  }

  void _startStopTimer() {
    _stopTimer?.cancel();
    _stopTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isRunning) return;
      if (_lastMovementTime == null) return;

      final elapsed = DateTime.now().difference(_lastMovementTime!).inSeconds;

      if (elapsed >= _stopThresholdSeconds && !_isStopDetected) {
        _triggerStopAlert();
      }
    });
  }

  void _onMovementDetected() {
    _lastMovementTime = DateTime.now();

    if (_isStopDetected) {
      _isStopDetected = false;
      onMovementResumed();
    }
  }

  Future<void> _triggerStopAlert() async {
    _isStopDetected = true;

    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      );
    } catch (e) {
      // GPS 실패시 마지막 알려진 위치 사용
      position = await Geolocator.getLastKnownPosition();
    }

    if (position != null) {
      onStopDetected(position);
    }
  }

  double _calculateMagnitude(double x, double y, double z) {
    return sqrt(x * x + y * y + z * z);
  }

  void _updateBuffer(List<double> buffer, double value) {
    buffer.add(value);
    if (buffer.length > _bufferSize) {
      buffer.removeAt(0);
    }
  }

  double _getBufferAverage(List<double> buffer) {
    if (buffer.isEmpty) return 0;
    return buffer.reduce((a, b) => a + b) / buffer.length;
  }

  /// 현재 정지 지속 시간 (초)
  int get currentStopDurationSeconds {
    if (_lastMovementTime == null) return 0;
    return DateTime.now().difference(_lastMovementTime!).inSeconds;
  }

  bool get isStopDetected => _isStopDetected;
  bool get isRunning => _isRunning;
}
