import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// 🚀 알림 클릭 시 화면 이동을 위한 전역 키
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

const AndroidNotificationChannel channel = AndroidNotificationChannel(
  'high_importance_channel',
  'High Importance Notifications',
  description: '이 채널은 중요 알림을 위해 사용됩니다.',
  importance: Importance.high,
);

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 1. 파이어베이스 초기화
  if (kIsWeb) {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyCYbjqUiY2ljMYSzA-nPp9ExuYCFOkfQmk",
        appId: "1:574487045582:web:f051d7c0c53910d76e379f",
        messagingSenderId: "574487045582",
        projectId: "safetymonitor-44947",
      ),
    );
  } else {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyCYbjqUiY2ljMYSzA-nPp9ExuYCFOkfQmk",
        appId: "1:574487045582:android:b65b74964d9183496e379f",
        messagingSenderId: "574487045582",
        projectId: "safetymonitor-44947",
      ),
    );
  }

  // 2. 알림 채널 등록
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  runApp(const SafetyMonitorApp());

  // 3. 푸시 권한 및 토큰 처리
  FirebaseMessaging messaging = FirebaseMessaging.instance;
  NotificationSettings settings = await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  if (settings.authorizationStatus == AuthorizationStatus.authorized) {
    try {
      String? token = await messaging.getToken(
        vapidKey: "BKabOVRnVrWaIpYATVD-pdFjGEJeASJ96PdXndOejGqg2a01VaWbHvXMtwfkqJH7kFWJtOnU6IC8tZ_HMdIzKc4",
      );
      if (token != null) {
        print('내 기기의 FCM 토큰 주소: $token');
        _sendTokenToServer(token); // 토큰 서버 전송
      }
    } catch (e) {
      print('🚨 토큰 처리 중 에러 발생: $e');
    }
  }

  // 4. 알림 클릭 시 이동 설정
  setupInteractedMessage();

  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    print('🔥 포그라운드 알림 도착');
  });
}

// 알림 클릭 핸들러
void setupInteractedMessage() async {
  RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) {
    _handleMessage(initialMessage);
  }
  FirebaseMessaging.onMessageOpenedApp.listen(_handleMessage);
}

void _handleMessage(RemoteMessage message) {
  if (message.data.isNotEmpty) {
    final alert = AlertModel(
      id: message.data['id'] ?? '0',
      workerName: message.data['workerName'] ?? '확인 불가',
      issue: message.data['issue'] ?? '위반 발생',
      time: message.data['time'] ?? '방금 전',
      statusColor: Colors.red,
      imageUrl: message.data['imageUrl'] ?? 'http://192.168.0.4:5000/static/images/test.jpg',
    );

    navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (context) => AlertDetailScreen(alertData: alert)),
    );
  }
}

void _sendTokenToServer(String token) async {
  try {
    final response = await http.post(
      Uri.parse('http://192.168.0.4:5000/api/token'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'token': token}),
    ).timeout(const Duration(seconds: 5));

    if (response.statusCode == 200) {
      print('✅ 최신 토큰을 서버 DB에 자동 저장했습니다!');
    }
  } catch (e) {
    print('🚨 서버 전송 실패: $e');
  }
}

// 모델 클래스들
class AlertModel {
  final String id;
  final String workerName;
  final String issue;
  final String time;
  final Color statusColor;
  final String imageUrl;

  AlertModel({
    required this.id, required this.workerName, required this.issue,
    required this.time, required this.statusColor, required this.imageUrl,
  });

  factory AlertModel.fromJson(Map<String, dynamic> json) {
    Color color = Colors.grey;
    if (json['statusColor'] == 'orange') color = Colors.orange;
    if (json['statusColor'] == 'red') color = Colors.red;

    return AlertModel(
      id: json['id'].toString(),
      workerName: json['workerName'],
      issue: json['issue'],
      time: json['time'],
      statusColor: color,
      imageUrl: json['imageUrl'] ?? '',
    );
  }
}

class WorkerModel {
  final String name;
  final int violationCount;
  final String lastViolation;

  WorkerModel({required this.name, required this.violationCount, required this.lastViolation});

  factory WorkerModel.fromJson(Map<String, dynamic> json) {
    return WorkerModel(
      name: json['name'],
      violationCount: json['violationCount'],
      lastViolation: json['lastViolation'] ?? '기록 없음',
    );
  }
}

class SafetyMonitorApp extends StatelessWidget {
  const SafetyMonitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blueGrey),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  final List<Widget> _pages = [
    const MainDashboard(),
    const WorkerListScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        selectedItemColor: const Color(0xFF1A237E),
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: '홈'),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: '작업자 관리'),
        ],
      ),
    );
  }
}

class MainDashboard extends StatefulWidget {
  const MainDashboard({super.key});

  @override
  State<MainDashboard> createState() => _MainDashboardState();
}

class _MainDashboardState extends State<MainDashboard> {
  Future<List<AlertModel>> fetchAlerts() async {
    final response = await http.get(Uri.parse('http://192.168.0.4:5000/api/alerts'));
    if (response.statusCode == 200) {
      List<dynamic> jsonResponse = jsonDecode(utf8.decode(response.bodyBytes));
      return jsonResponse.map((data) => AlertModel.fromJson(data)).toList();
    } else {
      throw Exception('서버 연결 실패');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('현장 안전 모니터링', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1A237E),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() {});
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('실시간 현장 요약', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _statusCard('정상', '08', Colors.green),
                  _statusCard('주의', '02', Colors.orange),
                  _statusCard('경고', '01', Colors.red),
                ],
              ),
              const SizedBox(height: 30),
              const Text('최근 위반 알림', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Expanded(
                child: FutureBuilder<List<AlertModel>>(
                  future: fetchAlerts(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    } else if (snapshot.hasError) {
                      return const Center(child: Text('서버 연결 확인 필요'));
                    } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return const Center(child: Text('알림 데이터가 없습니다.'));
                    }
                    return ListView.builder(
                      itemCount: snapshot.data!.length,
                      itemBuilder: (context, index) => _alertTile(context, snapshot.data![index]),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusCard(String title, String count, Color color) {
    return Container(
      width: 105,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: color, width: 2),
      ),
      child: Column(
        children: [
          Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 10),
          const Text('--', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _alertTile(BuildContext context, AlertModel alert) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: alert.statusColor, child: const Icon(Icons.warning, color: Colors.white)),
        title: Text('${alert.workerName} - ${alert.issue}', style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('발생 시간: ${alert.time}'),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () {
          Navigator.push(context, MaterialPageRoute(builder: (context) => AlertDetailScreen(alertData: alert)));
        },
      ),
    );
  }
}

class WorkerListScreen extends StatefulWidget {
  const WorkerListScreen({super.key});

  @override
  State<WorkerListScreen> createState() => _WorkerListScreenState();
}

class _WorkerListScreenState extends State<WorkerListScreen> {
  Future<List<WorkerModel>> fetchWorkers() async {
    final response = await http.get(Uri.parse('http://192.168.0.4:5000/api/workers'));
    if (response.statusCode == 200) {
      List<dynamic> jsonResponse = jsonDecode(utf8.decode(response.bodyBytes));
      return jsonResponse.map((data) => WorkerModel.fromJson(data)).toList();
    } else {
      throw Exception('작업자 목록 로드 실패');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('작업자 관리', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1A237E),
        centerTitle: true,
      ),
      body: FutureBuilder<List<WorkerModel>>(
        future: fetchWorkers(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return const Center(child: Text('작업자 데이터를 불러올 수 없습니다.'));
          }

          final workers = snapshot.data!;
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: workers.length,
            separatorBuilder: (context, index) => const Divider(),
            itemBuilder: (context, index) {
              final worker = workers[index];
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(worker.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                subtitle: Text('최근 위반: ${worker.lastViolation}'),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: worker.violationCount > 3 ? Colors.red[100] : Colors.orange[100],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '위반 ${worker.violationCount}회',
                    style: TextStyle(color: worker.violationCount > 3 ? Colors.red : Colors.orange[900], fontWeight: FontWeight.bold),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class AlertDetailScreen extends StatelessWidget {
  final AlertModel alertData;
  const AlertDetailScreen({super.key, required this.alertData});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('위반 상세 정보', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1A237E),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: Image.network(
                alertData.imageUrl,
                height: 250,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  height: 250,
                  color: Colors.grey[300],
                  child: const Center(child: Icon(Icons.broken_image, size: 50, color: Colors.grey)),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('작업자: ${alertData.workerName}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.error_outline, color: alertData.statusColor),
                const SizedBox(width: 8),
                Text('위반 사항: ${alertData.issue}', style: TextStyle(fontSize: 18, color: alertData.statusColor, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 10),
            Text('발생 시간: ${alertData.time}', style: const TextStyle(fontSize: 16, color: Colors.black54)),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A237E)),
                onPressed: () => Navigator.pop(context),
                child: const Text('조치 완료', style: TextStyle(fontSize: 18, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}