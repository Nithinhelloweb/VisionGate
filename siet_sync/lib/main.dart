import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'utils/vpn_check.dart';

import 'config/college_ip_config.dart';
import 'pages/admin_panel.dart';
import 'pages/login_page.dart';
import 'pages/hod_panel.dart';
import 'pages/staff_panel.dart';
import 'pages/other_staff_login.dart';
import 'pages/student_panel.dart';
import 'services/theme_service.dart';
import 'services/background_service_handler.dart';
import 'services/pre_verification_service.dart';

import 'utils/platform_utils.dart';

// Use centralized IP configuration
String get API_URL => CollegeIPConfig.defaultURL;

late List<CameraDescription> cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (AppPlatform.isAndroid) {
    await BackgroundLocationService.initialize();
  }

  // For web deployment, set your server IP here:
  // Uncomment the line below and change the IP to your backend server
  // CollegeIPConfig.setRuntimeURL('http://YOUR_SERVER_IP:8001');

  try {
    if (kIsWeb) {
      // On Web, run availableCameras() asynchronously so it doesn't block startup
      cameras = [];
      availableCameras().then((val) {
        cameras = val;
      }).catchError((e) {
        debugPrint("Warning: Web cameras query failed: $e");
      });
    } else {
      cameras = await availableCameras();
    }
  } catch (e) {
    debugPrint("Warning: Could not initialize cameras: $e");
    cameras = [];
  }
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _isVpnActive = false;
  Timer? _vpnTimer;
  bool _checkingVpn = true;

  @override
  void initState() {
    super.initState();
    _startVpnCheck();
    // Start background location/geofence/WiFi pre-verification immediately
    // so credentials are ready by the time the user tries to mark attendance.
    PreVerificationService.instance.start();
  }

  void _startVpnCheck() {
    _checkVpn();
    _vpnTimer = Timer.periodic(const Duration(seconds: 5), (_) => _checkVpn());
  }

  Future<void> _checkVpn() async {
    try {
      final active = await VpnChecker.isVpnActive();
      if (mounted && active != _isVpnActive) {
        setState(() {
          _isVpnActive = active;
          _checkingVpn = false;
        });
      } else if (mounted && _checkingVpn) {
        setState(() {
          _checkingVpn = false;
        });
      }
    } catch (_) {
      if (mounted && _checkingVpn) {
        setState(() {
          _checkingVpn = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _vpnTimer?.cancel();
    PreVerificationService.instance.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeService,
      builder: (context, _) {
        return MaterialApp(
          builder: (context, child) {
            if (_isVpnActive) {
              return VpnBlockedScreen(
                onRetry: () async {
                  setState(() => _checkingVpn = true);
                  await _checkVpn();
                },
                checking: _checkingVpn,
              );
            }
            return child!;
          },
          debugShowCheckedModeBanner: false,
          title: 'VisionGate',
          themeMode: themeService.themeMode,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            primaryColor: const Color(0xFF6366F1), // Indigo
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF6366F1),
              brightness: Brightness.light,
              primary: const Color(0xFF6366F1),
              secondary: const Color(0xFF8B5CF6), // Violet
              error: const Color(0xFFEF4444),
              surface: const Color(0xFFFFFFFF),
              onSurface: const Color(0xFF0F172A),
            ),
            scaffoldBackgroundColor: const Color(0xFFF8FAFC), // Premium Slate White
            cardTheme: CardThemeData(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              color: const Color(0xFFFFFFFF),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0xFFFFFFFF),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: Color(0xFF6366F1),
                  width: 2,
                ),
              ),
              prefixIconColor: const Color(0xFF6366F1),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                minimumSize: const Size(64, 48),
                elevation: 0,
              ),
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFFFFFFFF),
              foregroundColor: Color(0xFF0F172A),
              elevation: 0,
              centerTitle: true,
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            primaryColor: const Color(0xFF6366F1),
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF6366F1),
              brightness: Brightness.dark,
              primary: const Color(0xFF818CF8), // Light indigo
              secondary: const Color(0xFFA78BFA), // Light violet
              error: const Color(0xFFF87171),
              surface: const Color(0xFF1E293B), // Slate dark
              onSurface: const Color(0xFFF8FAFC),
            ),
            scaffoldBackgroundColor: const Color(0xFF0F172A), // Deep Slate Dark
            cardTheme: CardThemeData(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              color: const Color(0xFF1E293B),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0xFF1E293B),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.grey.shade800),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.grey.shade800),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: Color(0xFF818CF8),
                  width: 2,
                ),
              ),
              prefixIconColor: const Color(0xFF818CF8),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                minimumSize: const Size(64, 48),
                elevation: 0,
              ),
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF0F172A),
              foregroundColor: Color(0xFFF8FAFC),
              elevation: 0,
              centerTitle: true,
            ),
            iconTheme: const IconThemeData(color: Colors.white70),
            dividerColor: Colors.white24,
            dialogTheme: DialogThemeData(
              backgroundColor: const Color(0xFF1E293B),
              titleTextStyle: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              contentTextStyle: const TextStyle(color: Colors.white70),
            ),
            snackBarTheme: SnackBarThemeData(
              backgroundColor: const Color(0xFF334155),
              contentTextStyle: const TextStyle(color: Colors.white),
              actionTextColor: const Color(0xFF818CF8),
            ),
            chipTheme: ChipThemeData(
              backgroundColor: const Color(0xFF1E293B),
              labelStyle: const TextStyle(color: Colors.white),
              secondaryLabelStyle: const TextStyle(color: Colors.white70),
            ),
            listTileTheme: const ListTileThemeData(
              textColor: Colors.white,
              iconColor: Colors.white70,
            ),
          ),
          home: const LoginPage(),
          routes: {
            '/admin': (context) => AdminDashboardPage(
              token: '',
              user: {
                'id': 0,
                'username': 'admin',
                'name': 'Admin',
                'role': 'admin',
                'dept': 'Administration',
                'regNo': 'ADMIN001',
              },
            ),
            '/hod': (context) => HODDashboardPage(
              token: '',
              user: {
                'id': 0,
                'username': 'hod',
                'name': 'HOD',
                'role': 'hod',
                'dept': 'Computer Science',
                'regNo': 'HOD001',
              },
            ),
            '/staff': (context) => StaffDashboardPage(
              token: '',
              user: {
                'id': 0,
                'username': 'staff',
                'name': 'Staff',
                'role': 'staff',
                'dept': 'Computer Science',
                'regNo': 'STAFF001',
              },
            ),
            '/other_staff': (context) => const OtherStaffLoginPage(),
            '/student': (context) => const StudentDashboardPage(
              token: '',
              user: {
                'id': 0,
                'username': 'student',
                'name': 'Student',
                'role': 'student',
                'dept': 'CSE',
                'regNo': 'STUDENT001',
              },
            ),
          },
        );
      },
    );
  }
}

class VpnBlockedScreen extends StatelessWidget {
  final VoidCallback onRetry;
  final bool checking;

  const VpnBlockedScreen({
    super.key,
    required this.onRetry,
    required this.checking,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: (isDark ? const Color(0xFF1E293B) : Colors.white),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withValues(alpha: 0.2),
                        blurRadius: 30,
                        spreadRadius: 10,
                      )
                    ],
                  ),
                  child: const Icon(
                    Icons.security_rounded,
                    size: 80,
                    color: Colors.redAccent,
                  ),
                ),
                const SizedBox(height: 40),
                Text(
                  'VPN Connection Detected',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                    letterSpacing: 0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Text(
                    'For security reasons, you cannot use Faculty Sphere while connected to a VPN. Please disconnect from your VPN and try again.',
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      color: isDark ? Colors.white70 : Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 48),
                SizedBox(
                  width: 200,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: checking ? null : onRetry,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: checking
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.refresh_rounded, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Retry Connection',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
