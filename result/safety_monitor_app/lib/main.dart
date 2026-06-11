import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_mjpeg/flutter_mjpeg.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:math' as math; 
import 'package:shared_preferences/shared_preferences.dart'; 

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

const String SERVER_URL = "http://192.168.0.8:1557";

const AndroidNotificationChannel channel = AndroidNotificationChannel(
  'emergency_alert_v1', 
  '긴급 안전 알림',
  description: '위반 발생 시 화면을 켜고 강하게 울립니다.',
  importance: Importance.max,
  enableVibration: true,
  playSound: true,
);

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyCYbjqUiY2ljMYSzA-nPp9ExuYCFOkfQmk",
      appId: "1:574487045582:android:b65b74964d9183496e379f",
      messagingSenderId: "574487045582",
      projectId: "safetymonitor-44947",
    ),
  );

  final FlutterLocalNotificationsPlugin backgroundPlugin = FlutterLocalNotificationsPlugin();
  
  var initializationSettingsAndroid = const AndroidInitializationSettings('@mipmap/ic_launcher');
  var initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
  await backgroundPlugin.initialize(settings: initializationSettings);

  await backgroundPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  if (message.data.isNotEmpty) {
    int safeNotiId = math.Random().nextInt(100000);
    // 🚀 수정: 최신 패키지 문법에 맞게 id:, title:, body: 등 이름표(Named Parameters)를 부활시켰습니다!
    backgroundPlugin.show(
      id: safeNotiId, 
      title: message.data['title']?.toString() ?? '⚠️ 안전 위반 감지',
      body: message.data['body']?.toString() ?? '${message.data['workerName'] ?? '미확인'} 작업자: ${message.data['issue'] ?? '위반 발생'}',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          icon: '@mipmap/ic_launcher',
          importance: Importance.max,
          priority: Priority.high,
          fullScreenIntent: true,
          enableVibration: true,
          timeoutAfter: 5000, 
        ),
      ),
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
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

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  var initializationSettingsAndroid = const AndroidInitializationSettings('@mipmap/ic_launcher');
  var initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
  await flutterLocalNotificationsPlugin.initialize(settings: initializationSettings);

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    if (message.data.isNotEmpty) {
      int safeNotiId = math.Random().nextInt(100000);
      // 🚀 수정: 여기도 이름표 부활!
      flutterLocalNotificationsPlugin.show(
        id: safeNotiId,
        title: message.data['title']?.toString() ?? '⚠️ 안전 위반 감지',
        body: message.data['body']?.toString() ?? '위반 사항이 발생했습니다.',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channel.id, 
            channel.name,
            channelDescription: channel.description,
            icon: '@mipmap/ic_launcher',
            importance: Importance.max, 
            priority: Priority.high,
            fullScreenIntent: true, 
            enableVibration: true,
            timeoutAfter: 5000, 
          ),
        ),
      );
    }
  });

  FirebaseMessaging messaging = FirebaseMessaging.instance;
  NotificationSettings settings = await messaging.requestPermission(alert: true, badge: true, sound: true);

  if (settings.authorizationStatus == AuthorizationStatus.authorized) {
    try {
      String? token = await messaging.getToken(vapidKey: "BKabOVRnVrWaIpYATVD-pdFjGEJeASJ96PdXndOejGqg2a01VaWbHvXMtwfkqJH7kFWJtOnU6IC8tZ_HMdIzKc4");
      if (token != null) _sendTokenToServer(token);
    } catch (e) {
      if (kDebugMode) print('🚨 토큰 처리 에러: $e');
    }
  }

  setupInteractedMessage();

  SharedPreferences prefs = await SharedPreferences.getInstance();
  String? savedRole = prefs.getString('userRole');

  runApp(SafetyMonitorApp(savedRole: savedRole));
}

void setupInteractedMessage() async {
  RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) _handleMessage(initialMessage);
  FirebaseMessaging.onMessageOpenedApp.listen(_handleMessage);
}

void _handleMessage(RemoteMessage message) {
  if (message.data.isNotEmpty) {
    final alert = AlertModel(
      id: message.data['id']?.toString() ?? '0',
      workerName: message.data['workerName']?.toString() ?? '확인 불가',
      issue: message.data['issue']?.toString() ?? '위반 발생',
      date: message.data['date']?.toString() ?? DateFormat('yyyy-MM-dd').format(DateTime.now()),
      time: message.data['time']?.toString() ?? '방금 전',
      statusColor: Colors.red,
      imageUrl: message.data['imageUrl']?.toString() ?? '$SERVER_URL/static/images/test.jpg',
      isChecked: false,
    );

    navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (context) => AlertDetailScreen(alertData: alert)),
    );
  }
}

void _sendTokenToServer(String token) async {
  try {
    await http.post(
      Uri.parse('$SERVER_URL/api/token'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'token': token}),
    ).timeout(const Duration(seconds: 5));
  } catch (e) {}
}

Future<void> _performLogout() async {
  try { await http.delete(Uri.parse('$SERVER_URL/api/token')); } catch (e) {}
  
  SharedPreferences prefs = await SharedPreferences.getInstance();
  await prefs.clear(); 
  
  navigatorKey.currentState?.pushReplacement(
    MaterialPageRoute(builder: (context) => const LoginPage()),
  );
}

class AlertModel {
  final String id;
  final String workerName;
  final String issue;
  final String date;
  final String time;
  final Color statusColor;
  final String imageUrl;
  bool isChecked;

  AlertModel({
    required this.id, required this.workerName, required this.issue,
    required this.date, required this.time, required this.statusColor, 
    required this.imageUrl, required this.isChecked
  });

  factory AlertModel.fromJson(Map<String, dynamic> json) {
    Color color = Colors.grey;
    if (json['statusColor'] == 'orange') color = Colors.orange;
    if (json['statusColor'] == 'red') color = Colors.red;

    return AlertModel(
      id: json['id'].toString(),
      workerName: json['workerName'] ?? '알 수 없음',
      issue: json['issue'] ?? '내용 없음',
      date: json['date'] ?? '날짜 없음',
      time: json['time'] ?? '시간 없음',
      statusColor: color,
      imageUrl: json['imageUrl'] ?? '',
      isChecked: json['isChecked'] == 1 || json['isChecked'] == true,
    );
  }
}

class WorkerModel {
  final int id;
  final String name;
  final String uid;
  final int violationCount;
  final String lastViolation;

  WorkerModel({
    required this.id, required this.name, required this.uid, 
    required this.violationCount, required this.lastViolation
  });

  factory WorkerModel.fromJson(Map<String, dynamic> json) {
    return WorkerModel(
      id: json['id'] ?? 0,
      name: json['name'],
      uid: json['uid'] ?? '미등록',
      violationCount: json['violationCount'],
      lastViolation: json['lastViolation'] ?? '기록 없음',
    );
  }
}

class SafetyMonitorApp extends StatelessWidget {
  final String? savedRole;

  const SafetyMonitorApp({super.key, this.savedRole});

  @override
  Widget build(BuildContext context) {
    Widget initialScreen = const LoginPage();
    if (savedRole != null && savedRole!.isNotEmpty) {
      initialScreen = MainScreen(role: savedRole!);
    }

    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF1F5F9), 
        primaryColor: const Color(0xFF0F172A),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0F172A), 
          elevation: 0.0,
          iconTheme: IconThemeData(color: Colors.white),
        ),
      ),
      home: initialScreen,
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with SingleTickerProviderStateMixin {
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _pwController = TextEditingController();
  bool _isLoading = false;
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _animController, curve: Curves.easeIn));
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() => _isLoading = true);

    try {
      final response = await http.post(
        Uri.parse('$SERVER_URL/api/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'id': _idController.text.trim(), 'password': _pwController.text}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        String userRole = data['role']; 

        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('userRole', userRole);
        
        FirebaseMessaging.instance.getToken(vapidKey: "BKabOVRnVrWaIpYATVD-pdFjGEJeASJ96PdXndOejGqg2a01VaWbHvXMtwfkqJH7kFWJtOnU6IC8tZ_HMdIzKc4").then((token) {
          if (token != null) _sendTokenToServer(token);
        });

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => MainScreen(role: userRole)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("권한이 없거나 아이디가 틀렸습니다."), backgroundColor: Colors.redAccent));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("서버 연결 실패. URL을 확인하세요."), backgroundColor: Colors.redAccent));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, 
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F172A), Color(0xFF1E293B), Color(0xFF334155)]
          )
        ),
        child: Center(
          child: SingleChildScrollView(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 32),
                padding: const EdgeInsets.all(40),
                decoration: BoxDecoration(
                  color: Colors.white, 
                  borderRadius: BorderRadius.circular(24), 
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))
                  ]
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16), 
                      decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.1), shape: BoxShape.circle), 
                      child: const Icon(Icons.shield_moon_rounded, size: 60, color: Color(0xFF0F172A))
                    ),
                    const SizedBox(height: 16),
                    const Text("AISPA", style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, letterSpacing: 2, color: Color(0xFF0F172A))),
                    const Text("AI Smart Protection Area", style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 40),
                    TextField(
                      controller: _idController, 
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.person), 
                        labelText: '사용자 ID (admin / manager)', 
                        filled: true, 
                        fillColor: Colors.grey[100], 
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16.0), borderSide: BorderSide.none)
                      )
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _pwController, 
                      obscureText: true, 
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.lock), 
                        labelText: '비밀번호', 
                        filled: true, 
                        fillColor: Colors.grey[100], 
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16.0), borderSide: BorderSide.none)
                      )
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _login, 
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F172A), 
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)), 
                          elevation: 0
                        ), 
                        child: _isLoading 
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)) 
                          : const Text('시스템 접속', style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold))
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  final String role; 
  const MainScreen({super.key, required this.role});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  final List<Widget> _pages = [];
  final List<BottomNavigationBarItem> _navItems = [];

  @override
  void initState() {
    super.initState();
    _pages.add(MainDashboard(role: widget.role));
    _navItems.add(const BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: '오늘 현황'));

    if (widget.role == '안전관리자') {
      _pages.add(const ZoneSetupScreen());
      _navItems.add(const BottomNavigationBarItem(icon: Icon(Icons.map_rounded), label: '구역 설정'));
    }

    _pages.add(const StatsHistoryTab());
    _navItems.add(const BottomNavigationBarItem(icon: Icon(Icons.analytics_rounded), label: '기록/통계'));

    if (widget.role == '안전관리자') {
      _pages.add(const WorkerListScreen());
      _navItems.add(const BottomNavigationBarItem(icon: Icon(Icons.people_alt_rounded), label: '작업자 관리'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _pages),
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const LiveCameraScreen())),
              icon: const Icon(Icons.videocam, color: Colors.white),
              label: const Text("관제 모드", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              backgroundColor: const Color(0xFFE11D48),
              elevation: 4.0,
            )
          : null,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2))]),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          selectedItemColor: const Color(0xFF0F172A),
          unselectedItemColor: Colors.grey,
          type: BottomNavigationBarType.fixed, 
          backgroundColor: Colors.white,
          onTap: (index) => setState(() => _selectedIndex = index),
          items: _navItems,
        ),
      ),
    );
  }
}

class MainDashboard extends StatefulWidget {
  final String role;
  const MainDashboard({super.key, required this.role});

  @override
  State<MainDashboard> createState() => _MainDashboardState();
}

class _MainDashboardState extends State<MainDashboard> {
  List<AlertModel> alerts = [];
  bool isLoading = true;
  bool showSummary = true;
  bool showLiveCam = true;
  bool showList = true;
  Timer? _dashboardTimer;

  @override
  void initState() {
    super.initState();
    _loadDashboardSettings();
    _fetchData();
    _dashboardTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _fetchData(isSilent: true);
    });
  }

  @override
  void dispose() {
    _dashboardTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDashboardSettings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      showSummary = prefs.getBool('showSummary') ?? true;
      showLiveCam = prefs.getBool('showLiveCam') ?? true;
      showList = prefs.getBool('showList') ?? true;
    });
  }

  Future<void> _saveDashboardSettings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('showSummary', showSummary);
    await prefs.setBool('showLiveCam', showLiveCam);
    await prefs.setBool('showList', showList);
  }

  Future<void> _fetchData({bool isSilent = false}) async {
    try {
      final response = await http.get(Uri.parse('$SERVER_URL/api/alerts'));
      if (response.statusCode == 200) {
        List<dynamic> jsonResponse = jsonDecode(utf8.decode(response.bodyBytes));
        if (!mounted) return;
        setState(() {
          alerts = jsonResponse.map((data) => AlertModel.fromJson(data)).toList();
          isLoading = false;
        });
      }
    } catch (e) {
      if (!isSilent && mounted) setState(() => isLoading = false);
    }
  }

  void _showDashboardConfigDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24.0))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("🛠️ 대시보드 UI 설정", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text("실시간 요약 카드 표시", style: TextStyle(fontWeight: FontWeight.bold)),
                    activeColor: const Color(0xFFE11D48),
                    value: showSummary, 
                    onChanged: (v) { setState(() => showSummary = v); setModalState(() => showSummary = v); _saveDashboardSettings(); },
                  ),
                  SwitchListTile(
                    title: const Text("미니 CCTV 뷰 표시", style: TextStyle(fontWeight: FontWeight.bold)),
                    activeColor: const Color(0xFFE11D48),
                    value: showLiveCam, 
                    onChanged: (v) { setState(() => showLiveCam = v); setModalState(() => showLiveCam = v); _saveDashboardSettings(); },
                  ),
                  SwitchListTile(
                    title: const Text("최근 위반 내역 표시", style: TextStyle(fontWeight: FontWeight.bold)),
                    activeColor: const Color(0xFFE11D48),
                    value: showList, 
                    onChanged: (v) { setState(() => showList = v); setModalState(() => showList = v); _saveDashboardSettings(); },
                  ),
                ],
              ),
            );
          }
        );
      }
    );
  }

  void _showPPESettingsDialog(BuildContext context) async {
    showDialog(context: context, barrierDismissible: false, builder: (BuildContext context) { return const PPESettingsDialog(); });
  }

  @override
  Widget build(BuildContext context) {
    String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    var todayAlerts = alerts.where((a) => a.date == today).toList();
    var unchecked = todayAlerts.where((a) => !a.isChecked).length;
    var checked = todayAlerts.where((a) => a.isChecked).length;

    return Scaffold(
      appBar: AppBar(
        title: Text('AISPA 대시보드 (${widget.role})', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.dashboard_customize_rounded, color: Colors.white), onPressed: _showDashboardConfigDialog, tooltip: 'UI 설정'),
          if (widget.role == '안전관리자') 
            IconButton(icon: const Icon(Icons.settings, color: Colors.white), onPressed: () => _showPPESettingsDialog(context), tooltip: '안전장비 감지 설정'),
          IconButton(icon: const Icon(Icons.logout, color: Colors.white), onPressed: () => _performLogout(), tooltip: '로그아웃'),
        ],
      ),
      body: isLoading 
        ? const Center(child: CircularProgressIndicator()) 
        : LayoutBuilder(
            builder: (context, constraints) {
              return RefreshIndicator(
                onRefresh: () => _fetchData(isSilent: false),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: IntrinsicHeight(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (showSummary) ...[
                              const Text('오늘 현장 요약', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(child: _buildGradientCard('총 발생', '${todayAlerts.length}건', const [Color(0xFF3B82F6), Color(0xFF2563EB)])), 
                                  const SizedBox(width: 10),
                                  Expanded(child: _buildGradientCard('미확인', '${unchecked}건', const [Color(0xFFF43F5E), Color(0xFFE11D48)])), 
                                  const SizedBox(width: 10),
                                  Expanded(child: _buildGradientCard('조치완료', '${checked}건', const [Color(0xFF10B981), Color(0xFF059669)])),
                                ],
                              ),
                              const SizedBox(height: 24),
                            ],

                            if (showLiveCam) ...[
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('실시간 CCTV 모니터링', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                                  Row(children: [
                                    const Icon(Icons.circle, color: Colors.red, size: 10), 
                                    const SizedBox(width: 4), 
                                    const Text('LIVE REC', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12))
                                  ]),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Expanded(
                                child: Card(
                                  margin: EdgeInsets.zero,
                                  elevation: 2.0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
                                  clipBehavior: Clip.antiAlias,
                                  color: Colors.black, 
                                  child: Mjpeg(
                                    isLive: true, 
                                    stream: '$SERVER_URL/api/video_feed', 
                                    fit: BoxFit.contain, 
                                    error: (context, error, stack) => const Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min, 
                                        children: [
                                          Icon(Icons.videocam_off, color: Colors.white54, size: 40), 
                                          SizedBox(height: 8), 
                                          Text("카메라 연결 대기 중", style: TextStyle(color: Colors.white54))
                                        ]
                                      )
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                            ],

                            if (showList) ...[
                              const Text('최근 위반 스냅샷', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                              const SizedBox(height: 12),
                              if (todayAlerts.isEmpty)
                                Container(
                                  padding: const EdgeInsets.all(20), 
                                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16.0)), 
                                  child: const Center(child: Text("오늘 발생한 위반 내역이 없습니다! 🎉", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)))
                                ),
                              if (todayAlerts.isNotEmpty)
                                SizedBox(
                                  height: 130, 
                                  child: ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: todayAlerts.length,
                                    itemBuilder: (context, index) {
                                      final a = todayAlerts[index];
                                      return GestureDetector(
                                        onTap: () async { 
                                          await Navigator.push(context, MaterialPageRoute(builder: (_) => AlertDetailScreen(alertData: a))); 
                                          _fetchData(isSilent: true); 
                                        },
                                        child: Container(
                                          width: 300, 
                                          margin: const EdgeInsets.only(right: 12),
                                          decoration: BoxDecoration(
                                            color: Colors.white, 
                                            borderRadius: BorderRadius.circular(16.0), 
                                            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))]
                                          ),
                                          child: Row(
                                            children: [
                                              ClipRRect(
                                                borderRadius: const BorderRadius.horizontal(left: Radius.circular(16.0)), 
                                                child: Image.network(
                                                  a.imageUrl, 
                                                  width: 110, 
                                                  height: double.infinity, 
                                                  fit: BoxFit.cover, 
                                                  errorBuilder: (c,e,s) => Container(
                                                    width: 110, 
                                                    color: Colors.grey[200], 
                                                    child: const Icon(Icons.image_not_supported, color: Colors.grey)
                                                  )
                                                )
                                              ),
                                              Expanded(
                                                child: Padding(
                                                  padding: const EdgeInsets.all(12.0),
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start, 
                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                    children: [
                                                      Text(a.workerName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                                      const SizedBox(height: 4),
                                                      Text(a.issue, style: const TextStyle(fontSize: 13, color: Color(0xFFE11D48), fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis),
                                                      const Spacer(),
                                                      Row(
                                                        mainAxisAlignment: MainAxisAlignment.spaceBetween, 
                                                        children: [
                                                          Text(a.time, style: const TextStyle(color: Colors.grey, fontSize: 12)), 
                                                          Container(
                                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                                            decoration: BoxDecoration(color: a.isChecked ? Colors.green : Colors.red, borderRadius: BorderRadius.circular(8)),
                                                            child: Text(a.isChecked ? "조치완료" : "미확인", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))
                                                          )
                                                        ]
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              )
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                            ]
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
    );
  }

  Widget _buildGradientCard(String title, String count, List<Color> colors) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight), 
        borderRadius: BorderRadius.circular(16.0), 
        boxShadow: [BoxShadow(color: colors[0].withOpacity(0.4), blurRadius: 8, offset: const Offset(0,4))]
      ),
      child: Column(
        children: [
          Text(title, style: const TextStyle(fontSize: 13, color: Colors.white70, fontWeight: FontWeight.bold)), 
          const SizedBox(height: 8),
          Text(count, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
        ],
      ),
    );
  }
}

class PPESettingsDialog extends StatefulWidget {
  const PPESettingsDialog({super.key});
  @override State<PPESettingsDialog> createState() => _PPESettingsDialogState();
}

class _PPESettingsDialogState extends State<PPESettingsDialog> {
  bool helmet = true; bool vest = true; bool mask = true; bool gloves = true; bool isLoading = true;

  @override void initState() { super.initState(); _fetchSettings(); }

  Future<void> _fetchSettings() async {
    try {
      final res = await http.get(Uri.parse('$SERVER_URL/api/settings/ppe'));
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        setState(() { helmet = data['helmet'] ?? true; vest = data['vest'] ?? true; mask = data['mask'] ?? true; gloves = data['gloves'] ?? true; isLoading = false; });
      }
    } catch (e) { setState(() => isLoading = false); }
  }

  Future<void> _saveSettings() async {
    setState(() => isLoading = true);
    try {
      await http.post(
        Uri.parse('$SERVER_URL/api/settings/ppe'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({"helmet": helmet, "vest": vest, "mask": mask, "gloves": gloves})
      );
      if (mounted) Navigator.pop(context);
    } catch (e) { setState(() => isLoading = false); }
  }

  @override Widget build(BuildContext context) {
    if (isLoading) return const AlertDialog(content: SizedBox(height: 100, child: Center(child: CircularProgressIndicator())));
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.0)),
      title: const Text('안전장비 감지 설정', style: TextStyle(fontWeight: FontWeight.bold)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('현장 규정에 맞춰 감지할 장비를 선택하세요.', style: TextStyle(fontSize: 13, color: Colors.grey)), const SizedBox(height: 10),
          SwitchListTile(title: const Text('안전모 (Helmet)', style: TextStyle(fontWeight: FontWeight.bold)), activeColor: const Color(0xFFE11D48), value: helmet, onChanged: (val) => setState(() => helmet = val)),
          SwitchListTile(title: const Text('안전조끼 (Vest)', style: TextStyle(fontWeight: FontWeight.bold)), activeColor: const Color(0xFFE11D48), value: vest, onChanged: (val) => setState(() => vest = val)),
          SwitchListTile(title: const Text('마스크 (Mask)', style: TextStyle(fontWeight: FontWeight.bold)), activeColor: const Color(0xFFE11D48), value: mask, onChanged: (val) => setState(() => mask = val)),
          SwitchListTile(title: const Text('안전장갑 (Gloves)', style: TextStyle(fontWeight: FontWeight.bold)), activeColor: const Color(0xFFE11D48), value: gloves, onChanged: (val) => setState(() => gloves = val)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소', style: TextStyle(color: Colors.grey))),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0))), onPressed: _saveSettings, child: const Text('적용하기', style: TextStyle(color: Colors.white))),
      ],
    );
  }
}

class ZoneSetupScreen extends StatefulWidget {
  const ZoneSetupScreen({super.key});
  @override State<ZoneSetupScreen> createState() => _ZoneSetupScreenState();
}

class _ZoneSetupScreenState extends State<ZoneSetupScreen> {
  List<dynamic> savedZones = [];
  List<Offset> currentPoints = [];

  @override void initState() { super.initState(); _fetchZones(); }

  Future<void> _fetchZones() async {
    try {
      final res = await http.get(Uri.parse('$SERVER_URL/api/zones'));
      if (res.statusCode == 200) { setState(() { savedZones = jsonDecode(utf8.decode(res.bodyBytes)); }); }
    } catch (e) { print(e); }
  }

  Future<void> _syncZonesToServer() async {
    try {
      await http.post(Uri.parse('$SERVER_URL/api/zones'), headers: {'Content-Type': 'application/json'}, body: jsonEncode(savedZones));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('서버 동기화 완료!')));
    } catch (e) { print(e); }
  }

  void _showZoneManagement() {
    showModalBottomSheet(
      context: context, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24.0))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('현재 설정된 위험구역', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))), const SizedBox(height: 16),
                  Expanded(
                    child: savedZones.isEmpty 
                      ? const Center(child: Text('설정된 구역이 없습니다.', style: TextStyle(color: Colors.grey))) 
                      : ListView.builder(
                          itemCount: savedZones.length,
                          itemBuilder: (c, idx) {
                            final zone = savedZones[idx];
                            return Card(
                              elevation: 0, color: Colors.grey.shade100, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
                              child: ListTile(
                                title: Text(zone['name'] ?? '이름 없음', style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text('ID: ${zone['id']} | 포인트: ${zone['inner_polygon'].length}개'),
                                trailing: IconButton(icon: const Icon(Icons.delete_forever, color: Colors.redAccent), onPressed: () { setState(() { savedZones.removeAt(idx); }); setModalState(() {}); _syncZonesToServer(); }),
                              ),
                            );
                          },
                        ),
                  ),
                ],
              ),
            );
          }
        );
      }
    );
  }

  void _promptSaveZone() {
    if (currentPoints.length < 3) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('최소 3개 이상의 꼭짓점을 찍어야 합니다.'))); return; }
    TextEditingController nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.0)), title: const Text('새 위험구역 지정', style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(controller: nameCtrl, decoration: InputDecoration(hintText: '구역 이름을 입력하세요', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소', style: TextStyle(color: Colors.grey))),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE11D48)), onPressed: () { Navigator.pop(ctx); _saveCurrentPoints(nameCtrl.text.isEmpty ? '${savedZones.length + 1}번 구역' : nameCtrl.text); }, child: const Text('저장', style: TextStyle(color: Colors.white)))
        ]
      )
    );
  }

  void _saveCurrentPoints(String name) {
    double cx = 0, cy = 0;
    for (var p in currentPoints) { cx += p.dx; cy += p.dy; }
    cx /= currentPoints.length; cy /= currentPoints.length;
    List<List<int>> inner = []; List<List<int>> outer = []; double bufferPx = 45.0;

    for (var p in currentPoints) {
      inner.add([p.dx.toInt(), p.dy.toInt()]);
      double dx = p.dx - cx; double dy = p.dy - cy; double dist = math.max(math.sqrt(dx * dx + dy * dy), 1);
      outer.add([(p.dx + dx / dist * bufferPx).toInt(), (p.dy + dy / dist * bufferPx).toInt()]);
    }
    int newId = savedZones.isNotEmpty ? savedZones.last['id'] + 1 : 1;
    savedZones.add({"id": newId, "name": name, "inner_polygon": inner, "outer_polygon": outer});
    setState(() { currentPoints.clear(); }); _syncZonesToServer();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('실시간 위험구역 맵핑', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), centerTitle: true),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), color: Colors.white,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                OutlinedButton.icon(onPressed: () => setState(() => currentPoints.clear()), icon: const Icon(Icons.refresh), label: const Text('초기화')),
                ElevatedButton.icon(onPressed: _promptSaveZone, icon: const Icon(Icons.save, color: Colors.white), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE11D48)), label: const Text('지정 완료', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                IconButton(onPressed: _showZoneManagement, icon: const Icon(Icons.layers, size: 28, color: Color(0xFF0F172A))),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1280 / 720,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Mjpeg(isLive: true, stream: '$SERVER_URL/api/video_feed', fit: BoxFit.fill, error: (context, error, stack) => const Center(child: Icon(Icons.videocam_off, color: Colors.grey, size: 60))),
                    GestureDetector(
                      onPanUpdate: (details) {
                        RenderBox box = context.findRenderObject() as RenderBox;
                        Offset localPos = details.localPosition;
                        double scaleX = 1280 / box.size.width; 
                        double scaleY = 720 / box.size.height;
                        setState(() { currentPoints.add(Offset(localPos.dx * scaleX, localPos.dy * scaleY)); });
                      },
                      onTapDown: (details) {
                        RenderBox box = context.findRenderObject() as RenderBox;
                        Offset localPos = details.localPosition;
                        double scaleX = 1280 / box.size.width; 
                        double scaleY = 720 / box.size.height;
                        setState(() { currentPoints.add(Offset(localPos.dx * scaleX, localPos.dy * scaleY)); });
                      },
                      child: Container(color: Colors.transparent, child: CustomPaint(painter: ZonePainter(savedZones, currentPoints))),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ZonePainter extends CustomPainter {
  final List<dynamic> zones; final List<Offset> currentPoints;
  ZonePainter(this.zones, this.currentPoints);

  @override void paint(Canvas canvas, Size size) {
    double scaleX = size.width / 1280; double scaleY = size.height / 720;
    Paint savedFill = Paint()..color = Colors.redAccent.withOpacity(0.25)..style = PaintingStyle.fill;
    Paint savedStroke = Paint()..color = Colors.redAccent..style = PaintingStyle.stroke..strokeWidth = 2;

    for (var zone in zones) {
      var inner = zone['inner_polygon'];
      if (inner != null && inner.isNotEmpty) {
        Path path = Path(); path.moveTo(inner[0][0] * scaleX, inner[0][1] * scaleY);
        for (int i = 1; i < inner.length; i++) { path.lineTo(inner[i][0] * scaleX, inner[i][1] * scaleY); } path.close();
        canvas.drawPath(path, savedFill); canvas.drawPath(path, savedStroke);
      }
    }

    if (currentPoints.isNotEmpty) {
      Paint curStroke = Paint()..color = Colors.blue..style = PaintingStyle.stroke..strokeWidth = 3;
      Paint curPoint = Paint()..color = Colors.yellow..style = PaintingStyle.fill;
      Path path = Path();
      path.moveTo(currentPoints[0].dx * scaleX, currentPoints[0].dy * scaleY);
      canvas.drawCircle(Offset(currentPoints[0].dx * scaleX, currentPoints[0].dy * scaleY), 5, curPoint);
      for (int i = 1; i < currentPoints.length; i++) {
        path.lineTo(currentPoints[i].dx * scaleX, currentPoints[i].dy * scaleY);
        canvas.drawCircle(Offset(currentPoints[i].dx * scaleX, currentPoints[i].dy * scaleY), 5, curPoint);
      }
      if (currentPoints.length > 2) path.close(); canvas.drawPath(path, curStroke);
    }
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class StatsHistoryTab extends StatefulWidget {
  const StatsHistoryTab({super.key});
  @override State<StatsHistoryTab> createState() => _StatsHistoryTabState();
}

class _StatsHistoryTabState extends State<StatsHistoryTab> {
  List<AlertModel> allAlerts = []; String donutFilter = '일별'; DateTime? selectedDate; 
  Timer? _statsTimer;

  @override void initState() { 
    super.initState(); 
    _fetchData(); 
    _statsTimer = Timer.periodic(const Duration(seconds: 3), (timer) { _fetchData(); });
  }

  @override void dispose() {
    _statsTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchData() async {
    final res = await http.get(Uri.parse('$SERVER_URL/api/alerts'));
    if (res.statusCode == 200) {
      final List data = jsonDecode(utf8.decode(res.bodyBytes));
      if(mounted) setState(() => allAlerts = data.map((e) => AlertModel.fromJson(e)).toList());
    }
  }

  Map<String, int> _getWeeklyChartData() {
    Map<String, int> data = {};
    for (int i = 6; i >= 0; i--) data[DateFormat('MM/dd').format(DateTime.now().subtract(Duration(days: i)))] = 0;
    for (var a in allAlerts) { String dateKey = a.date.substring(5).replaceAll('-', '/'); if (data.containsKey(dateKey)) data[dateKey] = data[dateKey]! + 1; }
    return data;
  }

  Map<String, int> _getMonthlyChartData() {
    Map<String, int> data = {};
    for (int i = 5; i >= 0; i--) data[DateFormat('MM월').format(DateTime.now().subtract(Duration(days: i * 30)))] = 0;
    for (var a in allAlerts) { DateTime? d = DateTime.tryParse(a.date); if (d != null) { String matchLabel = '${DateFormat('MM').format(d)}월'; if (data.containsKey(matchLabel)) data[matchLabel] = data[matchLabel]! + 1; } }
    return data;
  }

  String _getDonutDateRangeLabel() {
    DateTime now = DateTime.now();
    if (donutFilter == '일별') return DateFormat('yyyy.MM.dd').format(now);
    if (donutFilter == '주별') return '${DateFormat('yyyy.MM.dd').format(now.subtract(const Duration(days: 7)))} ~ ${DateFormat('yyyy.MM.dd').format(now)}';
    if (donutFilter == '월별') return '${DateFormat('yyyy.MM.dd').format(now.subtract(const Duration(days: 30)))} ~ ${DateFormat('yyyy.MM.dd').format(now)}';
    return '00:00 ~ 24:00 (전체 누적)';
  }

  Map<String, int> _getDonutData() {
    DateTime now = DateTime.now(); Iterable<AlertModel> filtered = allAlerts;
    if (donutFilter == '일별') filtered = allAlerts.where((a) => a.date == DateFormat('yyyy-MM-dd').format(now));
    else if (donutFilter == '주별') filtered = allAlerts.where((a) { DateTime? d = DateTime.tryParse(a.date); return d != null && d.isAfter(now.subtract(const Duration(days: 7))); });
    else if (donutFilter == '월별') filtered = allAlerts.where((a) { DateTime? d = DateTime.tryParse(a.date); return d != null && d.isAfter(now.subtract(const Duration(days: 30))); });
    else if (donutFilter == '시간대별') {
      Map<String, int> hourly = {'오전(00-09)': 0, '주간(09-18)': 0, '야간(18-24)': 0};
      for (var a in allAlerts) {
        try { int h = int.parse(a.time.split(':')[0]); if (h >= 9 && h < 18) { hourly['주간(09-18)'] = hourly['주간(09-18)']! + 1; } else if (h >= 18) { hourly['야간(18-24)'] = hourly['야간(18-24)']! + 1; } else { hourly['오전(00-09)'] = hourly['오전(00-09)']! + 1; } } catch(_) {}
      }
      hourly.removeWhere((key, value) => value == 0); return hourly.isEmpty ? {'데이터 없음': 1} : hourly;
    }

    Map<String, int> data = {'위험구역': 0, '안전모': 0, '조끼': 0, '마스크/장갑': 0, '낙상/기타': 0};
    for (var a in filtered) {
      if (a.issue.contains('진입') || a.issue.contains('경계')) data['위험구역'] = data['위험구역']! + 1;
      else if (a.issue.contains('안전모')) data['안전모'] = data['안전모']! + 1;
      else if (a.issue.contains('조끼')) data['조끼'] = data['조끼']! + 1;
      else if (a.issue.contains('마스크') || a.issue.contains('장갑')) data['마스크/장갑'] = data['마스크/장갑']! + 1;
      else data['낙상/기타'] = data['낙상/기타']! + 1;
    }
    data.removeWhere((key, value) => value == 0); return data.isEmpty ? {'데이터 없음': 1} : data;
  }

  @override
  Widget build(BuildContext context) {
    String thisMonth = DateFormat('yyyy-MM').format(DateTime.now()); 
    String lastMonth = DateFormat('yyyy-MM').format(DateTime.now().subtract(const Duration(days: 30)));
    int thisMonthTotal = allAlerts.where((a) => a.date.startsWith(thisMonth)).length; 
    int lastMonthTotal = allAlerts.where((a) => a.date.startsWith(lastMonth)).length; 
    int momDiff = thisMonthTotal - lastMonthTotal; 
    
    List<AlertModel> filtered = allAlerts;
    if (selectedDate != null) filtered = filtered.where((a) => a.date == DateFormat('yyyy-MM-dd').format(selectedDate!)).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('통계 및 전체 기록', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 2.0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)), 
            child: Padding(
              padding: const EdgeInsets.all(20.0), 
              child: Row(
                children: [
                  CircleAvatar(radius: 25, backgroundColor: momDiff >= 0 ? Colors.red[50] : Colors.blue[50], child: Icon(momDiff >= 0 ? Icons.trending_up : Icons.trending_down, color: momDiff >= 0 ? const Color(0xFFE11D48) : Colors.blue, size: 30)), 
                  const SizedBox(width: 16), 
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('전월 대비 증감 분석', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.grey)), const SizedBox(height: 4), Text('지난달 ($lastMonthTotal건) ➔ 이번달 ($thisMonthTotal건)', style: const TextStyle(fontSize: 13, color: Colors.black87))])), 
                  Text(momDiff >= 0 ? '+$momDiff건 증가' : '$momDiff건 감소', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: momDiff >= 0 ? const Color(0xFFE11D48) : Colors.blue))
                ]
              )
            )
          ), const SizedBox(height: 16),

          Card(
            elevation: 2.0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)), 
            child: Padding(
              padding: const EdgeInsets.all(24.0), 
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center, 
                children: [
                  const Align(alignment: Alignment.centerLeft, child: Text('📊 전체 누적 위반 유형 점유율', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF0F172A)))), const SizedBox(height: 16), 
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal, 
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.start, 
                      children: ['일별', '주별', '월별', '시간대별'].map((lbl) => Padding(
                        padding: const EdgeInsets.only(right: 8.0), 
                        child: ChoiceChip(label: Text(lbl, style: TextStyle(fontWeight: FontWeight.bold, color: donutFilter == lbl ? Colors.white : Colors.black87)), selected: donutFilter == lbl, onSelected: (val) => setState(() => donutFilter = lbl), selectedColor: const Color(0xFF0F172A), backgroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)))
                      )).toList()
                    )
                  ), const SizedBox(height: 12), 
                  Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12.0)), child: Text(_getDonutDateRangeLabel(), style: const TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.bold, fontSize: 14))), const SizedBox(height: 30), 
                  DonutChartWidget(data: _getDonutData())
                ]
              )
            )
          ), const SizedBox(height: 16),

          _buildChartContainer('최근 7일간 일별 발생량', _getWeeklyChartData(), Colors.indigoAccent), const SizedBox(height: 16), 
          _buildChartContainer('최근 6개월간 월별 발생량', _getMonthlyChartData(), Colors.blueGrey), const SizedBox(height: 24),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween, 
            children: [
              const Text('전체 상세 기록', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))), 
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF0F172A), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0))), 
                icon: const Icon(Icons.calendar_month, size: 18), 
                label: Text(selectedDate == null ? '날짜 필터' : DateFormat('MM/dd').format(selectedDate!), style: const TextStyle(fontWeight: FontWeight.bold)), 
                onPressed: () async { 
                  DateTime? picked = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2025), lastDate: DateTime.now()); 
                  if (picked != null) { setState(() => selectedDate = picked); } 
                }
              )
            ]
          ), const SizedBox(height: 12),

          if (filtered.isEmpty) 
            Container(padding: const EdgeInsets.all(30), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16.0)), child: const Center(child: Text('기록된 내역이 없습니다.', style: TextStyle(color: Colors.grey, fontSize: 16)))),
            
          ...filtered.map((a) => Card(
            elevation: 2.0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)), margin: const EdgeInsets.only(bottom: 10), 
            child: ListTile(
              contentPadding: const EdgeInsets.all(16), 
              leading: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: a.statusColor.withOpacity(0.1), shape: BoxShape.circle), child: Icon(Icons.warning_rounded, color: a.statusColor)), 
              title: Text('${a.date} ${a.time} | ${a.workerName}', style: const TextStyle(fontWeight: FontWeight.bold)), 
              subtitle: Padding(padding: const EdgeInsets.only(top: 6), child: Text(a.issue)), 
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: a.isChecked ? Colors.green : Colors.red, borderRadius: BorderRadius.circular(12)),
                child: Text(a.isChecked ? "조치완료" : "미확인", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))
              ),
              onTap: () async { 
                await Navigator.push(context, MaterialPageRoute(builder: (_) => AlertDetailScreen(alertData: a))); 
                _fetchData(); 
              }
            )
          )).toList(),
        ],
      ),
    );
  }

  Widget _buildChartContainer(String title, Map<String, int> chartData, Color barColor) { 
    int maxVal = chartData.values.isEmpty ? 1 : chartData.values.reduce(math.max); if (maxVal == 0) maxVal = 1; 
    return Card(
      elevation: 2.0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)), 
      child: Padding(
        padding: const EdgeInsets.all(20), 
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, 
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))), const SizedBox(height: 30), 
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly, crossAxisAlignment: CrossAxisAlignment.end, 
              children: chartData.entries.map((e) { 
                double ratio = e.value / maxVal; 
                return Column(
                  children: [
                    Text('${e.value}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)), const SizedBox(height: 8), 
                    AnimatedContainer(duration: const Duration(milliseconds: 500), curve: Curves.easeOutQuart, width: 24, height: math.max(ratio * 120, 4.0), decoration: BoxDecoration(color: barColor, borderRadius: BorderRadius.circular(6.0))), const SizedBox(height: 10), 
                    Text(e.key, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold))
                  ]
                ); 
              }).toList()
            )
          ]
        )
      )
    ); 
  }
}

class DonutChartWidget extends StatelessWidget {
  final Map<String, int> data; const DonutChartWidget({super.key, required this.data});
  @override Widget build(BuildContext context) {
    List<Color> colors = [const Color(0xFFE11D48), const Color(0xFFF59E0B), const Color(0xFF3B82F6), const Color(0xFF10B981), const Color(0xFF8B5CF6)]; int total = data.values.fold(0, (s, v) => s + v);
    if (data.keys.length == 1 && data.keys.first == '데이터 없음') return const SizedBox(height: 200, child: Center(child: Text('해당 기간에 데이터가 없습니다.', style: TextStyle(color: Colors.grey))));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center, 
      children: [
        SizedBox(width: 220, height: 220, child: Stack(alignment: Alignment.center, children: [CustomPaint(size: const Size(220, 220), painter: DonutChartPainter(data, colors)), Column(mainAxisSize: MainAxisSize.min, children: [const Text('Total', style: TextStyle(fontSize: 16, color: Colors.grey, fontWeight: FontWeight.bold)), Text('$total', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 36, color: Color(0xFF0F172A)))])])), const SizedBox(height: 36), 
        Wrap(
          spacing: 20, runSpacing: 16, alignment: WrapAlignment.center, 
          children: data.entries.toList().asMap().entries.map((e) { 
            int idx = e.key; var entry = e.value; double pct = total == 0 ? 0 : (entry.value / total) * 100; 
            return Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.stop_circle_rounded, color: colors[idx % colors.length], size: 18), const SizedBox(width: 6), Text('${entry.key} (${pct.toStringAsFixed(1)}%)', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87))]); 
          }).toList()
        )
      ]
    );
  }
}

class DonutChartPainter extends CustomPainter {
  final Map<String, int> data; final List<Color> colors; DonutChartPainter(this.data, this.colors);
  @override void paint(Canvas canvas, Size size) { 
    int total = data.values.fold(0, (s, v) => s + v); if (total == 0) return; 
    double startAngle = -math.pi / 2; final rect = Rect.fromLTWH(0, 0, size.width, size.height); int i = 0; 
    for (var entry in data.entries) { 
      double sweepAngle = (entry.value / total) * 2 * math.pi; 
      final paint = Paint()..color = colors[i % colors.length]..style = PaintingStyle.stroke..strokeWidth = 35.0..strokeCap = StrokeCap.round; 
      canvas.drawArc(rect, startAngle, sweepAngle, false, paint); startAngle += sweepAngle; i++; 
    } 
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class WorkerListScreen extends StatefulWidget {
  const WorkerListScreen({super.key});
  @override State<WorkerListScreen> createState() => _WorkerListScreenState();
}

class _WorkerListScreenState extends State<WorkerListScreen> {
  Timer? _uidPollingTimer;
  Timer? _listTimer;
  List<WorkerModel>? _workers;

  @override
  void initState() {
    super.initState();
    fetchWorkers();
    _listTimer = Timer.periodic(const Duration(seconds: 3), (timer) { fetchWorkers(); });
  }

  @override
  void dispose() {
    _uidPollingTimer?.cancel();
    _listTimer?.cancel();
    super.dispose();
  }

  Future<void> fetchWorkers() async {
    try {
      final response = await http.get(Uri.parse('$SERVER_URL/api/workers'));
      if (response.statusCode == 200) {
        if(mounted) {
          setState(() {
            _workers = (jsonDecode(utf8.decode(response.bodyBytes)) as List).map((data) => WorkerModel.fromJson(data)).toList();
          });
        }
      }
    } catch(e){}
  }

  void _deleteWorker(WorkerModel worker) async {
    final confirm = await showDialog<bool>(
      context: context, 
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.0)), 
        title: const Text('작업자 영구 삭제', style: TextStyle(fontWeight: FontWeight.bold)), 
        content: Text('[${worker.name}] 데이터와 누적 위반 기록이 전체 DB에서 완전 삭제됩니다.'), 
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')), 
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE11D48)), onPressed: () => Navigator.pop(c, true), child: const Text('삭제', style: TextStyle(color: Colors.white)))
        ]
      )
    );
    if (confirm == true) {
      final res = await http.delete(Uri.parse('$SERVER_URL/api/workers/${worker.id}'));
      if (res.statusCode == 200) { fetchWorkers(); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("삭제되었습니다."))); }
    }
  }

  void _showAddWorkerDialog() async {
    TextEditingController nameCtrl = TextEditingController(); TextEditingController uidCtrl = TextEditingController(); String selectedRole = '작업자'; 
    await http.delete(Uri.parse('$SERVER_URL/api/latest_uid'));
    showDialog(
      context: context, barrierDismissible: false, 
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setModalState) {
          _uidPollingTimer ??= Timer.periodic(const Duration(seconds: 1), (timer) async {
            try { 
              final res = await http.get(Uri.parse('$SERVER_URL/api/latest_uid')); 
              if (res.statusCode == 200) { 
                final data = jsonDecode(utf8.decode(res.bodyBytes)); String newUid = data['uid'] ?? ''; 
                if (newUid.isNotEmpty && newUid != uidCtrl.text) { setModalState(() { uidCtrl.text = newUid; }); } 
              } 
            } catch (e) {}
          });
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24.0)), title: const Text('새 작업자 등록', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A))), 
            content: Column(
              mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, 
              children: [
                TextField(controller: nameCtrl, decoration: InputDecoration(labelText: '이름', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))), const SizedBox(height: 16), 
                DropdownButtonFormField<String>(
                  value: selectedRole, decoration: InputDecoration(labelText: '역할', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))), 
                  items: ['안전관리자', '현장소장', '작업자'].map((String role) { return DropdownMenuItem<String>(value: role, child: Text(role)); }).toList(), 
                  onChanged: (newValue) { setModalState(() { selectedRole = newValue!; }); }
                ), const SizedBox(height: 16), 
                TextField(
                  controller: uidCtrl, readOnly: true, 
                  decoration: InputDecoration(labelText: 'RFID 카드 UID', hintText: '아두이노에 카드를 태그하세요...', filled: true, fillColor: Colors.grey[100], prefixIcon: const Icon(Icons.nfc_rounded, color: Colors.blueAccent), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))
                )
              ]
            ), 
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소', style: TextStyle(color: Colors.grey))), 
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), 
                onPressed: () async { 
                  if (nameCtrl.text.isEmpty || uidCtrl.text.isEmpty) return; 
                  try { 
                    await http.post(Uri.parse('$SERVER_URL/api/workers'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'name': nameCtrl.text, 'role': selectedRole, 'uid': uidCtrl.text})); 
                    if (!mounted) return; Navigator.pop(ctx); fetchWorkers(); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("신규 작업자가 등록되었습니다!"))); 
                  } catch (e) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("등록 실패"))); } 
                }, 
                child: const Text('등록 완료', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
              )
            ]
          );
        });
      }
    ).then((_) { _uidPollingTimer?.cancel(); _uidPollingTimer = null; http.delete(Uri.parse('$SERVER_URL/api/latest_uid')); });
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('현장 인력 및 카드 DB', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), centerTitle: true),
      floatingActionButton: FloatingActionButton.extended(onPressed: _showAddWorkerDialog, backgroundColor: const Color(0xFF0F172A), icon: const Icon(Icons.credit_card, color: Colors.white), label: const Text("카드 등록", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
      body: _workers == null 
        ? const Center(child: CircularProgressIndicator()) 
        : ListView.separated(
            padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 80), itemCount: _workers!.length, separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final w = _workers![index];
              return Card(
                elevation: 1.0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), leading: const CircleAvatar(radius: 25, backgroundColor: Color(0xFF0F172A), child: Icon(Icons.person, color: Colors.white, size: 30)),
                  title: Row(
                    children: [
                      Text(w.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)), const SizedBox(width: 8), 
                      if(w.uid != '미등록') Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(4)), child: Text('UID: ${w.uid}', style: const TextStyle(fontSize: 10, color: Colors.blue, fontWeight: FontWeight.bold)))
                    ]
                  ),
                  subtitle: Padding(padding: const EdgeInsets.only(top: 4), child: Text('최근 위반: ${w.lastViolation}', style: const TextStyle(color: Colors.grey))),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min, 
                    children: [
                      Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: w.violationCount > 3 ? Colors.red[50] : Colors.orange[50], borderRadius: BorderRadius.circular(20.0)), child: Text('${w.violationCount}회', style: TextStyle(color: w.violationCount > 3 ? const Color(0xFFE11D48) : Colors.orange[900], fontWeight: FontWeight.bold, fontSize: 14))), 
                      IconButton(icon: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent), onPressed: () => _deleteWorker(w))
                    ]
                  ),
                  onTap: () { Navigator.push(context, MaterialPageRoute(builder: (_) => WorkerDetailProfileScreen(worker: w))); },
                ),
              );
            },
          )
    );
  }
}

class WorkerDetailProfileScreen extends StatefulWidget {
  final WorkerModel worker; 
  const WorkerDetailProfileScreen({super.key, required this.worker});
  @override State<WorkerDetailProfileScreen> createState() => _WorkerDetailProfileScreenState();
}

class _WorkerDetailProfileScreenState extends State<WorkerDetailProfileScreen> {
  List<dynamic> logs = []; bool loading = true;
  Timer? _detailTimer;

  @override void initState() { 
    super.initState(); 
    _loadLogs(); 
    _detailTimer = Timer.periodic(const Duration(seconds: 3), (timer) { _loadLogs(); });
  }

  @override void dispose() {
    _detailTimer?.cancel();
    super.dispose();
  }
  
  Future<void> _loadLogs() async { 
    final res = await http.get(Uri.parse('$SERVER_URL/api/workers/${widget.worker.id}/logs')); 
    if (res.statusCode == 200) { 
      if(mounted) setState(() { logs = jsonDecode(utf8.decode(res.bodyBytes)); loading = false; }); 
    } else { 
      if(mounted) setState(() => loading = false); 
    } 
  }

  Future<void> _deleteAllLogs() async {
    final res = await http.delete(Uri.parse('$SERVER_URL/api/workers/${widget.worker.id}/logs/all'));
    if (res.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('전체 기록이 삭제되었습니다.')));
      _loadLogs();
    }
  }
  
  Map<String, int> _getPersonalTypeStats() {
    Map<String, int> data = {'안전모': 0, '조끼': 0, '마스크/장갑': 0, '구역위반': 0, '낙상/기타': 0};
    for (var log in logs) { 
      String issue = log['issue']; 
      if (issue.contains('안전모')) { data['안전모'] = data['안전모']! + 1; } 
      else if (issue.contains('조끼')) { data['조끼'] = data['조끼']! + 1; } 
      else if (issue.contains('마스크') || issue.contains('장갑')) { data['마스크/장갑'] = data['마스크/장갑']! + 1; } 
      else if (issue.contains('진입') || issue.contains('경계')) { data['구역위반'] = data['구역위반']! + 1; } 
      else { data['낙상/기타'] = data['낙상/기타']! + 1; } 
    } 
    data.removeWhere((key, value) => value == 0); return data.isEmpty ? {'데이터 없음': 1} : data;
  }
  
  @override Widget build(BuildContext context) {
    var personalStats = _getPersonalTypeStats();
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.worker.name} 개인 리포트', style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep, color: Colors.white), 
            tooltip: '전체 기록 삭제',
            onPressed: () {
              showDialog(
                context: context, 
                builder: (_) => AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.0)), 
                  title: const Text("위반 기록 초기화", style: TextStyle(fontWeight: FontWeight.bold)), 
                  content: Text("[${widget.worker.name}] 작업자의 모든 위반 기록을 삭제하시겠습니까?"), 
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text("취소")), 
                    ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE11D48)), onPressed: () { Navigator.pop(context); _deleteAllLogs(); }, child: const Text("삭제", style: TextStyle(color: Colors.white)))
                  ]
                )
              ); 
            }
          )
        ],
      ),
      body: loading ? const Center(child: CircularProgressIndicator()) : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(16.0)), 
            child: Column(
              children: [
                const CircleAvatar(radius: 40, backgroundColor: Colors.white12, child: Icon(Icons.engineering_rounded, size: 50, color: Colors.white)), const SizedBox(height: 16), 
                Text(widget.worker.name, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)), const SizedBox(height: 8), 
                Text('총 위반 누적: ${logs.length}회', style: const TextStyle(color: Colors.orangeAccent, fontSize: 16, fontWeight: FontWeight.bold))
              ]
            )
          ), const SizedBox(height: 16),
          
          if (personalStats.isNotEmpty && !personalStats.containsKey('데이터 없음')) 
            Card(
              elevation: 2.0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)), 
              child: Padding(
                padding: const EdgeInsets.all(24.0), 
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center, 
                  children: [
                    const Text('📊 개인 주요 취약 통계', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF0F172A))), const SizedBox(height: 30), 
                    DonutChartWidget(data: personalStats)
                  ]
                )
              )
            ), const SizedBox(height: 16),
          
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0), 
            child: Text('상세 발생 타임라인', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)))
          ),
          if (logs.isEmpty) 
            Container(
              padding: const EdgeInsets.all(30), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16.0)), 
              child: const Center(child: Text('위반 기록이 없습니다. 🎉', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)))
            ),
            
          ...logs.map((log) {
            bool isChecked = log['isChecked'] == 1 || log['isChecked'] == true;
            return Card(
              elevation: 2.0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)), margin: const EdgeInsets.only(bottom: 10), 
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), 
                leading: Container(
                  padding: const EdgeInsets.all(10), 
                  decoration: BoxDecoration(color: log['statusColor'] == 'red' ? Colors.red.withOpacity(0.1) : Colors.orange.withOpacity(0.1), shape: BoxShape.circle), 
                  child: Icon(Icons.warning_rounded, color: log['statusColor'] == 'red' ? Colors.red : Colors.orange)
                ), 
                title: Text(log['issue'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)), 
                subtitle: Padding(padding: const EdgeInsets.only(top: 6), child: Text('${log['date']} | ${log['time']}')), 
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: isChecked ? Colors.green : Colors.red, borderRadius: BorderRadius.circular(12)),
                  child: Text(isChecked ? "조치완료" : "미확인", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))
                ),
                onTap: () async { 
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => AlertDetailScreen(alertData: AlertModel(
                    id: log['id'].toString(), workerName: widget.worker.name, issue: log['issue'], date: log['date'], time: log['time'], statusColor: log['statusColor'] == 'red' ? Colors.red : Colors.orange, 
                    imageUrl: log['imageUrl'] ?? '', isChecked: isChecked 
                  )))); 
                  await _loadLogs(); 
                }
              )
            );
          }).toList(),
        ],
      ),
    );
  }
}

class AlertDetailScreen extends StatefulWidget {
  final AlertModel alertData; 
  const AlertDetailScreen({super.key, required this.alertData});
  @override State<AlertDetailScreen> createState() => _AlertDetailScreenState();
}

class _AlertDetailScreenState extends State<AlertDetailScreen> {
  Future<void> _markAsChecked() async { 
    await http.put(Uri.parse('$SERVER_URL/api/alerts/${widget.alertData.id}/check')); 
    if (mounted) Navigator.pop(context, true); 
  }
  
  Future<void> _deleteRecord() async { 
    await http.delete(Uri.parse('$SERVER_URL/api/alerts/${widget.alertData.id}')); 
    if (mounted) Navigator.pop(context, true); 
  }
  
  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9), appBar: AppBar(title: const Text('위반 상세 보고서'), centerTitle: true),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, 
          children: [
            Container(
              width: double.infinity, color: const Color(0xFF0F172A), 
              child: widget.alertData.imageUrl.isEmpty 
                ? const SizedBox(height: 350, child: Center(child: Text("이미지 데이터가 없습니다.", style: TextStyle(color: Colors.white54)))) 
                : Image.network(widget.alertData.imageUrl, fit: BoxFit.contain, height: 350, errorBuilder: (c,e,s) => const SizedBox(height: 350, child: Center(child: Text("이미지 로드 실패", style: TextStyle(color: Colors.white54)))))
            ),
            Padding(
              padding: const EdgeInsets.all(24.0), 
              child: Container(
                padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16.0), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))]), 
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, 
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start, 
                      children: [
                        Expanded(child: Text(widget.alertData.issue, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFFE11D48), height: 1.3))), 
                        Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: widget.alertData.isChecked ? Colors.green : Colors.red, borderRadius: BorderRadius.circular(20.0)), child: Text(widget.alertData.isChecked ? "조치완료" : "미확인", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))
                      ]
                    ), 
                    const Divider(height: 40, thickness: 1), 
                    _infoRow(Icons.person_rounded, "대상 작업자", widget.alertData.workerName), 
                    _infoRow(Icons.calendar_today_rounded, "발생 일자", widget.alertData.date), 
                    _infoRow(Icons.access_time_rounded, "발생 시간", widget.alertData.time), 
                    const SizedBox(height: 40), 
                    if (!widget.alertData.isChecked) 
                      ElevatedButton.icon(icon: const Icon(Icons.check_circle_outline, color: Colors.white), label: const Text("관리자 조치 완료 처리", style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), minimumSize: const Size(double.infinity, 55), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0))), onPressed: _markAsChecked), 
                    const SizedBox(height: 12), 
                    OutlinedButton.icon(
                      icon: const Icon(Icons.delete_outline, color: Color(0xFFE11D48)), label: const Text("이 기록 영구 삭제", style: TextStyle(fontSize: 16, color: Color(0xFFE11D48), fontWeight: FontWeight.bold)), 
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFFE11D48)), minimumSize: const Size(double.infinity, 55), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0))), 
                      onPressed: () { 
                        showDialog(
                          context: context, builder: (_) => AlertDialog(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.0)), title: const Text("삭제 경고", style: TextStyle(fontWeight: FontWeight.bold)), content: const Text("이 기록을 완전히 삭제하시겠습니까?"), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("취소")), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE11D48)), onPressed: () { Navigator.pop(context); _deleteRecord(); }, child: const Text("삭제", style: TextStyle(color: Colors.white)))])
                        ); 
                      }
                    )
                  ]
                )
              )
            )
          ]
        ),
      ),
    );
  }
  
  Widget _infoRow(IconData icon, String title, String value) { 
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0), 
      child: Row(
        children: [
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.blueGrey.shade50, borderRadius: BorderRadius.circular(8.0)), child: Icon(icon, color: const Color(0xFF0F172A), size: 24)), 
          const SizedBox(width: 16), Text(title, style: const TextStyle(fontSize: 15, color: Colors.grey, fontWeight: FontWeight.bold)), 
          const Spacer(), Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.black87))
        ]
      )
    ); 
  }
}

class LiveCameraScreen extends StatefulWidget {
  const LiveCameraScreen({super.key});
  @override State<LiveCameraScreen> createState() => _LiveCameraScreenState();
}

class _LiveCameraScreenState extends State<LiveCameraScreen> {
  Timer? _timer; 
  List<AlertModel> _liveAlerts = [];
  
  @override void initState() { super.initState(); _fetchLiveAlerts(); _timer = Timer.periodic(const Duration(seconds: 1), (timer) { _fetchLiveAlerts(); }); }
  @override void dispose() { _timer?.cancel(); super.dispose(); }
  
  Future<void> _fetchLiveAlerts() async { 
    try { 
      final response = await http.get(Uri.parse('$SERVER_URL/api/alerts')); 
      if (response.statusCode == 200) { 
        List<dynamic> jsonResponse = jsonDecode(utf8.decode(response.bodyBytes)); 
        if (!mounted) return; 
        setState(() { 
          String today = DateFormat('yyyy-MM-dd').format(DateTime.now()); 
          _liveAlerts = jsonResponse.map((data) => AlertModel.fromJson(data)).where((a) => a.date == today).toList(); 
        }); 
      } 
    } catch (e) {} 
  }
  
  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9), appBar: AppBar(title: const Text('실시간 통합 관제', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFFE11D48)),
      body: LayoutBuilder(
        builder: (context, constraints) {
          Widget videoSection = Container(
            color: Colors.black, child: Stack(
              children: [
                Center(child: Mjpeg(isLive: true, stream: '$SERVER_URL/api/video_feed', fit: BoxFit.contain, error: (context, error, stack) => const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.videocam_off, color: Colors.grey, size: 60), SizedBox(height: 10), Text("CCTV 스트리밍 대기 중...", style: TextStyle(color: Colors.grey))]))), 
                Positioned(top: 16, right: 16, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: Colors.red.withOpacity(0.8), borderRadius: BorderRadius.circular(6.0)), child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, color: Colors.white, size: 10), SizedBox(width: 6), Text("LIVE REC", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))])))
              ]
            )
          );
          
          Widget alertSection = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(padding: const EdgeInsets.all(16), width: double.infinity, color: Colors.white, child: const Text("🚨 실시간 현장 이슈", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)))), const Divider(height: 1, thickness: 1),
              Expanded(
                child: _liveAlerts.isEmpty 
                  ? const Center(child: Text("오늘 발생한 이슈가 없습니다.", style: TextStyle(color: Colors.grey))) 
                  : ListView.builder(
                      padding: const EdgeInsets.all(12), itemCount: _liveAlerts.length, 
                      itemBuilder: (context, index) { 
                        final alert = _liveAlerts[index]; 
                        return Card(
                          elevation: 2.0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)), margin: const EdgeInsets.only(bottom: 8), 
                          child: ListTile(
                            leading: ClipRRect(borderRadius: BorderRadius.circular(8.0), child: Image.network(alert.imageUrl, width: 50, height: 50, fit: BoxFit.cover, errorBuilder: (c,e,s) => const Icon(Icons.broken_image))), 
                            title: Text('${alert.workerName} | ${alert.issue}', style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text('${alert.time} 발생', style: const TextStyle(color: Colors.grey)), 
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: alert.isChecked ? Colors.green : Colors.red, borderRadius: BorderRadius.circular(12)),
                              child: Text(alert.isChecked ? "조치완료" : "미확인", style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))
                            ),
                            onTap: () async { 
                              await Navigator.push(context, MaterialPageRoute(builder: (_) => AlertDetailScreen(alertData: alert))); 
                              _fetchLiveAlerts();
                            }
                          )
                        ); 
                      }
                    )
              ),
            ],
          );
          
          if (constraints.maxWidth > 800) { 
            return Row(children: [Expanded(flex: 2, child: videoSection), Expanded(flex: 1, child: Container(color: Colors.white, child: alertSection))]); 
          } else { 
            return Column(children: [SizedBox(height: 300, child: videoSection), Expanded(child: alertSection)]); 
          }
        },
      ),
    );
  }
}