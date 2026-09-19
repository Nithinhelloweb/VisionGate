import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/college_ip_config.dart';
import '../services/api_client.dart';
import '../services/location_tracking_service.dart';
import '../services/session_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/quick_access_stat_card.dart';
import '../widgets/face_registration_widget.dart';
import '../widgets/attendance_pie_chart.dart';
import '../widgets/thirukkural_banner.dart';
import '../widgets/user_settings_tab.dart';
import '../widgets/leave_request_widget.dart';
import '../widgets/location_permission_enforcer.dart';
import '../widgets/service_health_card.dart';
import '../utils/responsive.dart';
import '../utils/api_response_utils.dart';
import '../services/leave_balance_notifier.dart';
import '../services/pre_verification_service.dart';
import 'attendance_log_page.dart';


String get API_URL => CollegeIPConfig.defaultURL;

class OtherStaffLoginPage extends StatefulWidget {
  const OtherStaffLoginPage({super.key});

  @override
  State<OtherStaffLoginPage> createState() => _OtherStaffLoginPageState();
}

class _OtherStaffLoginPageState extends State<OtherStaffLoginPage> {
  final usernameCtrl = TextEditingController();
  final passwordCtrl = TextEditingController();
  bool isLoading = false;
  String errorMsg = '';

  @override
  void dispose() {
    usernameCtrl.dispose();
    passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (usernameCtrl.text.isEmpty || passwordCtrl.text.isEmpty) {
      setState(() => errorMsg = 'Please enter username and password');
      return;
    }

    setState(() {
      isLoading = true;
      errorMsg = '';
    });

    try {
      final deviceSessionId = 'dev_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999)}';
      final response = await http.post(
        Uri.parse('$API_URL/other_staff/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': usernameCtrl.text,
          'password': passwordCtrl.text,
          'device_id': deviceSessionId,
        }),
      );

      if (response.statusCode == 200) {
        final data = ApiResponseUtils.tryParseJson(response.body);
        if (data == null) {
          setState(
            () => errorMsg =
                'Login failed: invalid server response. Please verify backend URL/server status.',
          );
          return;
        }
        final user = data['user'];
        final role = user['role']?.toString().toLowerCase() ?? '';
        await sessionService.saveSession(
          SessionData(
            token: data['token'],
            user: user,
            role: role,
            loginTime: DateTime.now(),
            deviceSessionId: deviceSessionId,
          ),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => OtherStaffDashboardPage(
              token: data['token'],
              user: data['user'],
            ),
          ),
        );
      } else {
        final data = ApiResponseUtils.tryParseJson(response.body);
        setState(() {
          errorMsg =
              data?['detail'] ??
              data?['message'] ??
              data?['error'] ??
              ApiResponseUtils.nonJsonErrorMessage(
                response.statusCode,
                response.body,
              );
          passwordCtrl.clear();
        });
      }
    } catch (e) {
      setState(() => errorMsg = ApiResponseUtils.sanitize(e));
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 600;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panelAccent = const Color(0xFF4F46E5);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [const Color(0xFF0F172A), const Color(0xFF1E293B)]
                : [const Color(0xFF3730A3), const Color(0xFF4F46E5), const Color(0xFF6366F1)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(isMobile ? 20 : 32),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: isMobile ? double.infinity : 420,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isDark ? 0.5 : 0.12,
                        ),
                        blurRadius: 30,
                        offset: const Offset(0, 15),
                      ),
                    ],
                  ),
                  padding: EdgeInsets.all(isMobile ? 24 : 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF4F46E5), Color(0xFF6366F1)],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF4F46E5).withValues(alpha: 0.4),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.admin_panel_settings,
                          size: 50,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        'Other Staff Portal',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF1A1A2E),
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Principal / Placement / Lab Tech / Admin Login',
                        style: TextStyle(
                          color: isDark ? Colors.white60 : Colors.grey[600],
                          fontSize: 15,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      TextField(
                        controller: usernameCtrl,
                        decoration: InputDecoration(
                          labelText: 'Username',
                          labelStyle: TextStyle(
                            color: isDark ? Colors.white60 : Colors.grey[600],
                            fontSize: 16,
                          ),
                          floatingLabelStyle: TextStyle(
                            color: panelAccent,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          prefixIcon: Container(
                            margin: const EdgeInsets.all(12),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: panelAccent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.person_outline,
                              color: panelAccent,
                              size: 22,
                            ),
                          ),
                          filled: true,
                          fillColor: isDark
                              ? const Color(0xFF2C2C2E)
                              : const Color(0xFFF2F2F7),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: isDark
                                  ? Colors.grey.shade800
                                  : Colors.grey.shade200,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: panelAccent,
                              width: 2,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 18,
                            horizontal: 16,
                          ),
                        ),
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: passwordCtrl,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          labelStyle: TextStyle(
                            color: isDark ? Colors.white60 : Colors.grey[600],
                            fontSize: 16,
                          ),
                          floatingLabelStyle: TextStyle(
                            color: panelAccent,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          prefixIcon: Container(
                            margin: const EdgeInsets.all(12),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: panelAccent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.lock_outline,
                              color: panelAccent,
                              size: 22,
                            ),
                          ),
                          filled: true,
                          fillColor: isDark
                              ? const Color(0xFF2C2C2E)
                              : const Color(0xFFF2F2F7),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: isDark
                                  ? Colors.grey.shade800
                                  : Colors.grey.shade200,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: panelAccent,
                              width: 2,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 18,
                            horizontal: 16,
                          ),
                        ),
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontSize: 16,
                        ),
                      ),
                      if (errorMsg.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF3D1A1A)
                                : Colors.red.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDark
                                  ? const Color(0xFF5D2A2A)
                                  : Colors.red.shade200,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: Colors.red.shade400,
                                size: 22,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  errorMsg,
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.red.shade300
                                        : Colors.red.shade700,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 28),
                      Container(
                        width: double.infinity,
                        height: 54,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: isLoading
                              ? null
                              : const LinearGradient(
                                  colors: [Color(0xFF4F46E5), Color(0xFF6366F1)],
                                ),
                          boxShadow: isLoading
                              ? null
                              : [
                                  BoxShadow(
                                    color: const Color(0xFF4F46E5).withValues(alpha: 0.35),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                        ),
                        child: ElevatedButton(
                          onPressed: isLoading ? null : _login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                          child: isLoading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Login as Other Staff',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(
                          'Back to Home',
                          style: TextStyle(
                            color: isDark ? Colors.white70 : Colors.grey[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OtherStaffDashboardPage extends StatefulWidget {
  final String token;
  final Map<String, dynamic> user;

  const OtherStaffDashboardPage({
    super.key,
    required this.token,
    required this.user,
  });

  @override
  State<OtherStaffDashboardPage> createState() =>
      _OtherStaffDashboardPageState();
}

class _OtherStaffDashboardPageState extends State<OtherStaffDashboardPage> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  StreamSubscription<String>? _warningSub;
  Map<String, dynamic>? dashboardData;
  bool isLoading = true;
  int presentDays = 0;
  int absentDays = 0;

  final List<Widget> _pages = [];
  final List<String> _titles = [
    'Dashboard',
    'Mark Attendance',
    'My Face',
    'Leave Requests',
    'Attendance Log',
    'Settings',
  ];

  void _onTabSelected(int index) {
    setState(() {
      _selectedIndex = index;
    });
    if (index == 3) {
      LeaveBalanceNotifier.instance.notifyBalanceChanged();
    }
  }

  void _checkOfflineViolations() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if (prefs.getBool('offline_rules_violated') == true) {
      final msg = prefs.getString('offline_violation_message') ?? 'Rule violation detected during offline tracking. You have been marked absent.';
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Row(
              children: const [
                Icon(Icons.warning_amber_rounded, color: Colors.red),
                SizedBox(width: 10),
                Text('Rule Violation Warning'),
              ],
            ),
            content: Text(msg),
            actions: [
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await prefs.remove('offline_rules_violated');
                  await prefs.remove('offline_violation_message');
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkOfflineViolations();
    if (!kIsWeb) {
      LocationTrackingService.instance.startTracking(
        token: widget.token,
        user: widget.user,
      );
      _warningSub = LocationTrackingService.instance.warningStream.listen((warning) {
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => _BoundaryBreachDialog(message: warning),
          );
        }
      });
    }
    final accent = roleAccentColor;
    _pages.addAll([
      OtherStaffDashboardTab(
        token: widget.token,
        user: widget.user,
        onTabSelected: _onTabSelected,
        accentColor: accent,
      ),
      OtherStaffMarkAttendanceTab(
        token: widget.token,
        user: widget.user,
        accentColor: accent,
      ),
      OtherStaffFaceRegisterTab(
        token: widget.token,
        user: widget.user,
        accentColor: accent,
      ),
      StaffLeaveRequestTab(token: widget.token, accentColor: accent),
      AttendanceLogTab(token: widget.token, user: widget.user),
      UserSettingsTab(
        title: 'Settings',
        token: widget.token,
        accentColor: accent,
      ),
    ]);
    _loadDashboard();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !kIsWeb) {
      LocationTrackingService.instance.ensureTrackingActive();
    }
  }

  void _loadDashboard() {
    // Dashboard loaded
  }

  void _logout() async {
    if (!kIsWeb) {
      await _warningSub?.cancel();
      await LocationTrackingService.instance.stopTracking();
    }
    await sessionService.clearSession();
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (!kIsWeb) {
      _warningSub?.cancel();
    }
    super.dispose();
  }

  String get userRole => widget.user['role'] ?? 'Unknown';

  Color get roleAccentColor {
    switch (userRole.toLowerCase()) {
      case 'principal':
        return const Color(0xFF4F46E5);
      case 'placement_staff':
      case 'placement':
        return const Color(0xFF0D9488);
      case 'lab_technician':
      case 'lab_tech':
      case 'labtech':
        return const Color(0xFF0284C7);
      case 'system_admin':
      case 'systemadmin':
        return const Color(0xFF7C3AED);
      case 'office_staff':
        return const Color(0xFF1D4ED8);
      default:
        return const Color(0xFF4F46E5);
    }
  }

  String get roleDisplayName {
    switch (userRole.toLowerCase()) {
      case 'principal':
        return 'Principal';
      case 'placement_staff':
      case 'placement':
        return 'Placement Staff';
      case 'lab_technician':
      case 'lab_tech':
      case 'labtech':
        return 'Lab Technician';
      case 'system_admin':
      case 'systemadmin':
        return 'System Admin';
      case 'office_staff':
        return 'Office Staff';
      default:
        return userRole;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = roleAccentColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final scaffold = AdaptiveScaffold(
      title: _titles[_selectedIndex],
      selectedIndex: _selectedIndex,
      onDestinationSelected: (index) {
        setState(() => _selectedIndex = index);
        if (index == 3) {
          LeaveBalanceNotifier.instance.notifyBalanceChanged();
        }
      },
      destinations: const [
        NavDestination(
          icon: Icons.dashboard_outlined,
          selectedIcon: Icons.dashboard_rounded,
          label: 'Dashboard',
          sectionHeader: 'Main',
        ),
        NavDestination(
          icon: Icons.assignment_turned_in_outlined,
          selectedIcon: Icons.assignment_turned_in_rounded,
          label: 'Attend',
          sectionHeader: 'Attendance & Face',
        ),
        NavDestination(
          icon: Icons.face_outlined,
          selectedIcon: Icons.face_rounded,
          label: 'My Face',
        ),
        NavDestination(
          icon: Icons.event_note_outlined,
          selectedIcon: Icons.event_note_rounded,
          label: 'Leave',
          sectionHeader: 'Leave & Records',
        ),
        NavDestination(
          icon: Icons.history_edu_outlined,
          selectedIcon: Icons.history_edu_rounded,
          label: 'Logs',
        ),
        NavDestination(
          icon: Icons.settings_outlined,
          selectedIcon: Icons.settings_rounded,
          label: 'Settings',
          sectionHeader: 'System',
        ),
      ],
      accentColor: accentColor,
      drawer: _buildDrawer(context),
      onLogout: _logout,
      body: Stack(
        children: [
          if (!kIsWeb) ...[
            Positioned(
              top: -120,
              left: -120,
              child: Container(
                width: 400,
                height: 400,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF6366F1).withValues(alpha: isDark ? 0.22 : 0.12),
                      const Color(0xFF6366F1).withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 50,
              right: -150,
              child: Container(
                width: 500,
                height: 500,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFFEC4899).withValues(alpha: isDark ? 0.18 : 0.08),
                      const Color(0xFFEC4899).withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 300,
              right: 120,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF10B981).withValues(alpha: isDark ? 0.12 : 0.05),
                      const Color(0xFF10B981).withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -100,
              left: 100,
              child: Container(
                width: 350,
                height: 350,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF8B5CF6).withValues(alpha: isDark ? 0.15 : 0.06),
                      const Color(0xFF8B5CF6).withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ],
          RefreshIndicator(
            onRefresh: () async {
              setState(() {
                _pages.clear();
                _pages.addAll([
                  OtherStaffDashboardTab(
                    token: widget.token,
                    user: widget.user,
                    onTabSelected: _onTabSelected,
                    accentColor: accentColor,
                  ),
                  OtherStaffMarkAttendanceTab(
                    token: widget.token,
                    user: widget.user,
                    accentColor: accentColor,
                  ),
                  OtherStaffFaceRegisterTab(
                    token: widget.token,
                    user: widget.user,
                    accentColor: accentColor,
                  ),
                  StaffLeaveRequestTab(
                    token: widget.token,
                    accentColor: accentColor,
                  ),
                  AttendanceLogTab(token: widget.token, user: widget.user),
                  UserSettingsTab(
                    title: 'Settings',
                    token: widget.token,
                    accentColor: accentColor,
                  ),
                ]);
              });
              await Future.delayed(const Duration(milliseconds: 100));
            },
            color: accentColor,
            child: _pages[_selectedIndex],
          ),
        ],
      ),
    );

    return kIsWeb ? scaffold : LocationPermissionEnforcer(child: scaffold);
  }

  Widget _buildDrawer(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = roleAccentColor;

    return Drawer(
      child: Container(
        color: isDark ? const Color(0xFF000000) : Colors.white,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 20,
                bottom: 24,
                left: 20,
                right: 20,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [const Color(0xFF1C1C1E), const Color(0xFF2C2C2E)]
                      : [accent, accent.withValues(alpha: 0.7)],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.person,
                      size: 36,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Other Staff Portal',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.user['name'] ?? 'Staff',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 180),
                      child: Text(
                        roleDisplayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _buildDrawerSectionHeader('Main', isDark),
            _buildDrawerItem(
              0,
              Icons.dashboard_rounded,
              'Dashboard',
              Icons.dashboard_outlined,
            ),
            _buildDrawerSectionHeader('Attendance & Face', isDark),
            _buildDrawerItem(
              1,
              Icons.assignment_turned_in_rounded,
              'Mark Attendance',
              Icons.assignment_turned_in_outlined,
            ),
            _buildDrawerItem(
              2,
              Icons.face_rounded,
              'My Face',
              Icons.face_outlined,
            ),
            _buildDrawerSectionHeader('Leave & Records', isDark),
            _buildDrawerItem(
              3,
              Icons.event_note_rounded,
              'Leave Requests',
              Icons.event_note_outlined,
            ),
            _buildDrawerItem(
              4,
              Icons.history_edu_rounded,
              'Attendance Log',
              Icons.history_edu_outlined,
            ),
            _buildDrawerSectionHeader('System', isDark),
            _buildDrawerItem(
              5,
              Icons.settings_rounded,
              'Settings',
              Icons.settings_outlined,
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Divider(
                color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF3D1A1A)
                        : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.logout,
                    color: Colors.red.shade400,
                    size: 22,
                  ),
                ),
                title: Text(
                  'Logout',
                  style: TextStyle(
                    color: Colors.red.shade400,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: _logout,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerSectionHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: isDark ? Colors.white38 : Colors.grey.shade500,
        ),
      ),
    );
  }

  Widget _buildDrawerItem(
    int index,
    IconData selectedIcon,
    String title,
    IconData unselectedIcon,
  ) {
    final isSelected = _selectedIndex == index;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = roleAccentColor;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: isSelected ? accent.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            setState(() => _selectedIndex = index);
            Navigator.pop(context);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? accent
                        : (isDark
                              ? const Color(0xFF1C1C1E)
                              : Colors.grey.shade100),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isSelected ? selectedIcon : unselectedIcon,
                    color: isSelected
                        ? Colors.white
                        : (isDark ? Colors.white60 : Colors.grey.shade600),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.w500,
                      color: isSelected
                          ? accent
                          : (isDark ? Colors.white : Colors.grey.shade700),
                      fontSize: 15,
                    ),
                  ),
                ),
                if (isSelected)
                  Icon(Icons.chevron_right, color: accent, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Other Staff Dashboard Tab
class OtherStaffDashboardTab extends StatefulWidget {
  final String token;
  final Map<String, dynamic> user;
  final Function(int)? onTabSelected;
  final Color accentColor;

  const OtherStaffDashboardTab({
    super.key,
    required this.token,
    required this.user,
    this.onTabSelected,
    this.accentColor = const Color(0xFF007AFF),
  });

  @override
  State<OtherStaffDashboardTab> createState() => _OtherStaffDashboardTabState();
}

class _OtherStaffDashboardTabState extends State<OtherStaffDashboardTab> {
  Map<String, dynamic>? data;
  bool isLoading = true;
  double presentDays = 0.0;
  double absentDays = 0.0;
  int? _quickAccessIndex;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadQuickAccessIndex();
    fetchDashboard();
    _startAutoRefresh();
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      fetchMyAttendance();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  String _formatTimestamp(dynamic raw) {
    final ts = raw?.toString().trim() ?? '';
    if (ts.isEmpty) return '';
    
    DateTime? dt;
    if (ts.contains('T')) {
      dt = DateTime.tryParse(ts);
    } else {
      dt = DateTime.tryParse(ts.replaceAll(' ', 'T'));
    }

    String formatted = ts;
    if (ts.contains('T')) {
      final parts = ts.split('T');
      final date = parts[0];
      final time = parts[1].split('.').first;
      formatted = '$date $time';
    }

    if (dt != null) {
      final session = dt.hour < 13 ? 'FN' : 'AN';
      return '0.5 $session • $formatted';
    }
    return formatted;
  }

  // Available drawer items for quick access
  final List<DrawerItem> _drawerItems = const [
    DrawerItem(
      index: 1,
      icon: Icons.assignment_turned_in_rounded,
      title: 'Mark Attendance',
    ),
    DrawerItem(index: 2, icon: Icons.face_rounded, title: 'My Face'),
    DrawerItem(
      index: 3,
      icon: Icons.event_note_rounded,
      title: 'Leave Requests',
    ),
    DrawerItem(index: 4, icon: Icons.settings_rounded, title: 'Settings'),
  ];

  // Handle quick access widget tap - navigate to the selected tab
  void _onQuickAccessWidgetTap(int index) {
    if (widget.onTabSelected != null) {
      widget.onTabSelected!(index);
    }
  }

  // Load persisted quick access index from storage
  Future<void> _loadQuickAccessIndex() async {
    final storedIndex = await sessionService.getQuickAccessIndex();
    if (storedIndex != null && mounted) {
      setState(() {
        _quickAccessIndex = storedIndex;
      });
    }
  }

  // Save quick access index to storage
  Future<void> _saveQuickAccessIndex(int index) async {
    await sessionService.saveQuickAccessIndex(index);
  }

  Future<void> fetchDashboard() async {
    setState(() => isLoading = true);
    try {
      final response = await apiClient.get(
        '$API_URL/other_staff/dashboard',
        token: widget.token,
        cacheKey: 'other_staff_dashboard_${widget.token.hashCode}',
        cacheDuration: const Duration(minutes: 1),
      );
      if (response.statusCode == 200) {
        setState(() => data = jsonDecode(response.body));
      }

      await fetchMyAttendance();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${ApiResponseUtils.sanitize(e)}')),
        );
      }
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> fetchMyAttendance() async {
    try {
      final response = await apiClient.get(
        '$API_URL/other_staff/attendance',
        token: widget.token,
        cacheKey: 'other_staff_attendance_${widget.token.hashCode}',
        cacheDuration: const Duration(minutes: 10),
      );
      if (response.statusCode == 200) {
        final attendanceData = jsonDecode(response.body);
        final records = attendanceData['attendance'] ?? [];

        double? newPresent = attendanceData['present_days'] != null ? (attendanceData['present_days'] as num).toDouble() : null;
        double? newAbsent = attendanceData['absent_days'] != null ? (attendanceData['absent_days'] as num).toDouble() : null;

        if (newPresent == null || newAbsent == null) {
          final Set<String> uniqueDates = {};
          for (var record in records) {
            final timestamp = record['timestamp']?.toString() ?? '';
            if (timestamp.isNotEmpty) {
              final date = timestamp.contains(' ')
                  ? timestamp.split(' ')[0]
                  : (timestamp.contains('T')
                        ? timestamp.split('T')[0]
                        : timestamp);
              uniqueDates.add(date);
            }
          }

          final now = DateTime.now();
          newPresent = uniqueDates.length.toDouble();
          newAbsent = (now.day - newPresent).clamp(0, 30).toDouble();
        }

        if (mounted) {
          setState(() {
            presentDays = newPresent ?? 0.0;
            absentDays = newAbsent ?? 0.0;
          });
        }
      }
    } catch (e) {
      // Silently fail
    }
  }

  String get roleDisplayName {
    final role = widget.user['role']?.toString() ?? 'Unknown';
    switch (role.toLowerCase()) {
      case 'principal':
        return 'Principal';
      case 'placement_staff':
      case 'placement':
        return 'Placement Staff';
      case 'lab_technician':
      case 'lab_tech':
      case 'labtech':
        return 'Lab Technician';
      case 'system_admin':
      case 'systemadmin':
        return 'System Admin';
      case 'office_staff':
        return 'Office Staff';
      default:
        return role;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 400;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = widget.accentColor;

    if (isLoading) {
      return Center(child: CircularProgressIndicator(color: accent));
    }

    final stats = data?['stats'] ?? {};
    final recentAttendance = data?['recent_attendance'] ?? [];

    final pagePadding = Breakpoints.pagePadding(screenWidth);
    final gridSpacing = Breakpoints.gridSpacing(screenWidth);
    final isWide = screenWidth >= 900;

    // Bento glass card helper
    Widget bentoCard({
      required Widget child,
      Color? accentColor,
      double? height,
      VoidCallback? onTap,
    }) {
      final cardAccent = accentColor ?? accent;
      return Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.05),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: cardAccent.withValues(alpha: isDark ? 0.08 : 0.01),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(24),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isDark
                          ? [
                              Colors.white.withValues(alpha: 0.09),
                              Colors.white.withValues(alpha: 0.02),
                            ]
                          : [
                              Colors.white.withValues(alpha: 0.75),
                              Colors.white.withValues(alpha: 0.35),
                            ],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.15)
                          : Colors.white.withValues(alpha: 0.65),
                      width: 1.5,
                    ),
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget welcomeCard() {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [const Color(0xFF1C1C1E), const Color(0xFF2C2C2E)]
                : [accent, const Color(0xFF7986CB)],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.waving_hand,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Welcome back,',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'OTHER STAFF',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.user['name'] ?? 'Staff',
                        style: TextStyle(
                          fontSize: isSmallScreen ? 18 : 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.work,
                        color: Colors.white.withValues(alpha: 0.9),
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Role: ${widget.user['role']?.toUpperCase() ?? 'STAFF'}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.badge,
                        color: Colors.white.withValues(alpha: 0.9),
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'ID: ${widget.user['reg_no'] ?? ''}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    Widget attendanceProgressBento() {
      // Use historical breakdown from daily_attendance_status for pie chart
      final double fullDay = (stats['hist_full_day_count'] as num? ?? presentDays).toDouble();
      final double halfDay = (stats['hist_half_day_count'] as num? ?? 0.0).toDouble();
      final double absent  = (stats['hist_absent_count']   as num? ?? absentDays).toDouble();
      final double onLeave = (stats['hist_leave_count']    as num? ?? 0.0).toDouble();

      // Today's status from server
      final String? todayStatus      = stats['today_status'] as String?;
      final String? todayFirstHalf   = stats['today_first_half'] as String?;
      final String? todaySecondHalf  = stats['today_second_half'] as String?;

      Color _statusColor(String? s) {
        switch (s) {
          case 'Present': return const Color(0xFF10B981);
          case 'Absent':  return const Color(0xFFEF4444);
          case 'Leave':   return const Color(0xFF8B5CF6);
          default:        return Colors.grey;
        }
      }

      return bentoCard(
        accentColor: Colors.teal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Attendance Health',
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black54,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            // Today's half-day status pills
            if (todayFirstHalf != null || todaySecondHalf != null) ...[  
              const SizedBox(height: 6),
              Row(
                children: [
                  if (todayFirstHalf != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: _statusColor(todayFirstHalf).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _statusColor(todayFirstHalf), width: 0.8),
                      ),
                      child: Text(
                        '1st: $todayFirstHalf',
                        style: TextStyle(
                          color: _statusColor(todayFirstHalf),
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (todaySecondHalf != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _statusColor(todaySecondHalf).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _statusColor(todaySecondHalf), width: 0.8),
                      ),
                      child: Text(
                        '2nd: $todaySecondHalf',
                        style: TextStyle(
                          color: _statusColor(todaySecondHalf),
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 4),
            Expanded(
              child: Center(
                child: AttendancePieChart(
                  fullDay: fullDay.toInt(),
                  halfDay: halfDay.toInt(),
                  absent: absent.toInt(),
                  onLeave: onLeave.toInt(),
                  centerLabel: 'Days',
                  centerSpaceRadius: 36,
                ),
              ),
            ),
            if (todayStatus != null) ...[  
              const SizedBox(height: 4),
              Text(
                'Today: $todayStatus',
                style: TextStyle(
                  color: _statusColor(todayStatus),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      );
    }

    Widget recentAttendancePanel() {
      return Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Activity Beacons',
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.refresh, color: accent),
                    onPressed: fetchDashboard,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            recentAttendance.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(40),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.history, size: 40, color: isDark ? Colors.white30 : Colors.grey[400]),
                          const SizedBox(height: 12),
                          Text(
                            'No logs recorded recently',
                            style: TextStyle(color: isDark ? Colors.white60 : Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: recentAttendance.length,
                    separatorBuilder: (context, index) => Divider(
                      height: 1,
                      color: isDark ? Colors.white12 : Colors.grey.shade200,
                    ),
                    itemBuilder: (context, index) {
                      final record = recentAttendance[index];
                      final when = _formatTimestamp(record['timestamp']);
                      final isAbsent = record['status'] == 'Absent' ||
                          record['punch_type'] == 'absent' ||
                          record['punch_type'] == 'system_marked_absent' ||
                          record['is_absent'] == true;
                      final punchType = record['punch_type'] as String? ?? (isAbsent ? 'absent' : 'check_in');
                      final isCheckOut = punchType == 'check_out';

                      final punchColor = isAbsent
                          ? const Color(0xFFEF4444)
                          : isCheckOut
                              ? Colors.orange
                              : const Color(0xFF10B981);

                      final punchIcon = isAbsent
                          ? Icons.cancel_rounded
                          : isCheckOut
                              ? Icons.logout_rounded
                              : Icons.login_rounded;

                      final punchLabel = isAbsent
                          ? 'Absent'
                          : isCheckOut
                              ? 'Check Out'
                              : 'Check In';

                      final regNo = record['reg_no'] ?? record['regNo'] ?? '';
                      final dept = record['dept'] ?? record['department'] ?? '';
                      final regAndDept = [if (regNo.toString().isNotEmpty) regNo, if (dept.toString().isNotEmpty) dept].join(' • ');
                      final reason = record['absent_reason'] ?? record['reason'] ?? (isAbsent ? 'System marked absent' : null);
                      final session = record['session_label'] ?? record['session'] ?? record['session_type'];
                      final timeText = (session != null && session.toString().isNotEmpty) ? '$session • $when' : when;

                      final avatarRadius = isSmallScreen ? 14.0 : 18.0;
                      final avatarIconSize = isSmallScreen ? 14.0 : 18.0;
                      final titleSize = isSmallScreen ? 13.0 : 14.0;
                      final subtitleSize = isSmallScreen ? 11.0 : 12.0;

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        leading: CircleAvatar(
                          radius: avatarRadius,
                          backgroundColor: punchColor.withValues(alpha: 0.12),
                          child: Icon(
                            punchIcon,
                            size: avatarIconSize,
                            color: punchColor,
                          ),
                        ),
                        title: Text(
                          record['name'] ?? 'Unknown',
                          style: TextStyle(
                            fontSize: titleSize,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          isAbsent
                              ? '$regAndDept\nReason: $reason'
                              : regAndDept,
                          style: TextStyle(
                            fontSize: subtitleSize,
                            color: isDark ? Colors.white60 : Colors.grey.shade600,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: isAbsent ? 2 : 1,
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: punchColor.withValues(alpha: isDark ? 0.22 : 0.10),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: punchColor.withValues(alpha: 0.35),
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                punchLabel,
                                style: TextStyle(
                                  color: punchColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              timeText,
                              style: TextStyle(
                                color: isDark ? Colors.white54 : Colors.grey[600],
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ],
        ),
      );
    }

    Widget bentoGrid() {
      if (isWide) {
        // Desktop Bento Grid
        return Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    children: [
                      SizedBox(
                        height: 225,
                        child: welcomeCard(),
                      ),
                      const SizedBox(height: 16),
                      const ThirukkuralBanner(),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 270,
                    child: attendanceProgressBento(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SizedBox(
                    height: 180,
                    child: bentoCard(
                      accentColor: Colors.green,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.check_circle_rounded, color: Colors.green, size: 36),
                          const Spacer(),
                          Text(
                            'Present Cycles',
                            style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontSize: 13),
                          ),
                          Text(
                            presentDays % 1 == 0 ? presentDays.toInt().toString() : presentDays.toString(),
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: SizedBox(
                    height: 180,
                    child: bentoCard(
                      accentColor: Colors.red,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.cancel_rounded, color: Colors.red, size: 36),
                          const Spacer(),
                          Text(
                            'Absent Cycles',
                            style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontSize: 13),
                          ),
                          Text(
                            absentDays % 1 == 0 ? absentDays.toInt().toString() : absentDays.toString(),
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: SizedBox(
                    height: 180,
                    child: bentoCard(
                      accentColor: accent,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.calendar_month_rounded, color: accent, size: 36),
                          const Spacer(),
                          Text(
                            'Aggregated Shifts',
                            style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontSize: 13),
                          ),
                          Text(
                            (presentDays + absentDays).toString(),
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: SizedBox(
                    height: 180,
                    child: QuickAccessStatCard(
                      availableItems: _drawerItems,
                      selectedIndex: _quickAccessIndex,
                      onItemSelected: (index) {
                        setState(() => _quickAccessIndex = index);
                        _saveQuickAccessIndex(index);
                      },
                      onRemove: () {
                        setState(() => _quickAccessIndex = null);
                        sessionService.clearQuickAccessIndex();
                      },
                      onWidgetTap: _onQuickAccessWidgetTap,
                      accentColor: accent,
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      } else {
        // Mobile Bento Grid
        return Column(
          children: [
            welcomeCard(),
            const SizedBox(height: 16),
            const ThirukkuralBanner(),
            const ServiceHealthCard(),
            const SizedBox(height: 16),
            SizedBox(
              height: 270,
              child: attendanceProgressBento(),
            ),
            const SizedBox(height: 16),
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: 2,
              crossAxisSpacing: gridSpacing,
              mainAxisSpacing: gridSpacing,
              childAspectRatio: 1.65,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                bentoCard(
                  accentColor: Colors.green,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Present',
                            style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                          const Icon(Icons.check_circle_rounded, color: Colors.green, size: 18),
                        ],
                      ),
                      Text(
                        presentDays.toString(),
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                bentoCard(
                  accentColor: Colors.red,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Absent',
                            style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                          const Icon(Icons.cancel_rounded, color: Colors.red, size: 18),
                        ],
                      ),
                      Text(
                        absentDays.toString(),
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                bentoCard(
                  accentColor: accent,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total Shifts',
                            style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                          Icon(Icons.calendar_month_rounded, color: accent, size: 18),
                        ],
                      ),
                      Text(
                        (presentDays + absentDays).toString(),
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                QuickAccessStatCard(
                  availableItems: _drawerItems,
                  selectedIndex: _quickAccessIndex,
                  onItemSelected: (index) {
                    setState(() => _quickAccessIndex = index);
                    _saveQuickAccessIndex(index);
                  },
                  onRemove: () {
                    setState(() => _quickAccessIndex = null);
                    sessionService.clearQuickAccessIndex();
                  },
                  onWidgetTap: _onQuickAccessWidgetTap,
                  accentColor: accent,
                ),
              ],
            ),
          ],
        );
      }
    }

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.all(pagePadding),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: Breakpoints.contentMaxWidth(screenWidth),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              bentoGrid(),
              const SizedBox(height: 24),
              recentAttendancePanel(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Modern responsive stat card with gradient accent and glass effect
class ModernOtherStaffStatCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color color;

  const ModernOtherStaffStatCard({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 400;
    final isMobile = screenWidth < 600;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final iconSize = isSmallScreen ? 18.0 : (isMobile ? 20.0 : 22.0);
    final titleSize = isSmallScreen ? 13.0 : 14.0;
    final valueSize = isSmallScreen ? 26.0 : 28.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF1E293B).withValues(alpha: 0.85)
                : Colors.white.withValues(alpha: 0.90),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? color.withValues(alpha: 0.25)
                  : color.withValues(alpha: 0.15),
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: isDark ? 0.12 : 0.08),
                blurRadius: 15,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                top: 12,
                right: 12,
                child: Icon(
                  icon,
                  size: iconSize,
                  color: color.withOpacity(0.8),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: titleSize,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: valueSize,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : color,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Other Staff Mark Attendance Tab
class OtherStaffMarkAttendanceTab extends StatefulWidget {
  final String token;
  final Map<String, dynamic> user;
  final Color accentColor;

  const OtherStaffMarkAttendanceTab({
    super.key,
    required this.token,
    required this.user,
    this.accentColor = const Color(0xFF007AFF),
  });

  @override
  State<OtherStaffMarkAttendanceTab> createState() =>
      _OtherStaffMarkAttendanceTabState();
}

class _OtherStaffMarkAttendanceTabState
    extends State<OtherStaffMarkAttendanceTab> {
  bool _isRegistered = false;
  bool _isLoading = true;
  String _message = '';

  bool _isWindowAllowed = false;
  bool _isHoliday = false;
  bool _isSpecialOccasion = false;
  String? _holidayTitle;
  String? _holidayReason;
  String _dayType = 'WORKING_DAY';
  String _activeSlotType = 'check_in';
  String _activeSlotHalf = 'full_day';
  bool _alreadyMarkedCurrentSlot = false;
  String? _checkInTime;
  String? _checkOutTime;
  String? _fnInTime;
  String? _fnOutTime;
  String? _anInTime;
  String? _anOutTime;
  Map<String, dynamic>? _nextSlot;
  String? _windowMessage;
  bool _isCheckedIn = false;
  bool _isCheckedOut = false;
  String _todayAttendanceStatus = '';
  Timer? _windowTimer;

  @override
  void initState() {
    super.initState();
    _checkFaceStatus();
    _checkTodayAttendance();
    PreVerificationService.instance.forceRefresh();
    _windowTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) {
        _checkTodayAttendance();
      }
    });
  }

  @override
  void dispose() {
    _windowTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkFaceStatus() async {
    try {
      final response = await http.get(
        Uri.parse("$API_URL/other_staff/face/status"),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _isRegistered = data['face_registered'] ?? false;
        });
      }
    } catch (e) {
      setState(() {
        _message = "Error checking face status: ${ApiResponseUtils.sanitize(e)}";
      });
    }
  }

  Future<void> _checkTodayAttendance() async {
    try {
      final regNo = widget.user['regNo'] ?? widget.user['reg_no'] ?? '';
      final checkUri = regNo.toString().isNotEmpty
          ? Uri.parse("$API_URL/admin/attendance/duration/check?reg_no=$regNo")
          : Uri.parse("$API_URL/admin/attendance/duration/check");
      final slotResponse = await http.get(
        checkUri,
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      
      bool allowed = false;
      String slotType = 'check_in';
      String slotHalf = 'full_day';
      bool isHol = false;
      bool isSpecial = false;
      String? holTitle;
      String? holReason;
      String dayType = 'WORKING_DAY';
      Map<String, dynamic>? nextSlot;
      String? windowMsg;
      List<Map<String, dynamic>> activeSlots = [];
      
      if (slotResponse.statusCode == 200) {
        final slotData = jsonDecode(slotResponse.body);
        allowed = slotData['allowed'] ?? false;
        slotType = slotData['slot_type'] ?? 'check_in';
        slotHalf = slotData['slot_half'] ?? 'full_day';
        isHol = slotData['is_holiday'] == true;
        isSpecial = slotData['is_special_occasion'] == true;
        holTitle = slotData['holiday_title']?.toString() ?? slotData['occasion_title']?.toString();
        holReason = slotData['holiday_reason']?.toString() ?? slotData['reason']?.toString() ?? slotData['message']?.toString();
        dayType = slotData['day_type']?.toString() ?? 'WORKING_DAY';
        if (slotData['next_slot'] is Map<String, dynamic>) {
          nextSlot = Map<String, dynamic>.from(slotData['next_slot']);
        }
        windowMsg = slotData['message']?.toString();
        if (slotData['active_slots'] is List) {
          activeSlots = (slotData['active_slots'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }
      }

      String? fnIn;
      String? fnOut;
      String? anIn;
      String? anOut;
      String? inTime;
      String? outTime;
      String statusStr = '';
      final today = DateTime.now().toString().split(' ')[0];

      // Query personal attendance endpoint for comprehensive daily attendance status
      final response = await http.get(
        Uri.parse("$API_URL/api/attendance/personal?start_date=$today&end_date=$today"),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final records = (data['attendance'] as List? ?? data['records'] as List? ?? []);
        final todayRecord = records.firstWhere(
          (r) => r['date']?.toString().startsWith(today) == true || r['timestamp']?.toString().startsWith(today) == true,
          orElse: () => null,
        );

        if (todayRecord != null) {
          statusStr = todayRecord['status']?.toString() ?? 'Present';
          fnIn = todayRecord['first_half_in_time']?.toString();
          fnOut = todayRecord['first_half_out_time']?.toString();
          anIn = todayRecord['second_half_in_time']?.toString();
          anOut = todayRecord['second_half_out_time']?.toString();
          inTime = todayRecord['in_time']?.toString() ?? fnIn ?? anIn;
          outTime = todayRecord['out_time']?.toString() ?? anOut ?? fnOut;
        }
      }

      // Fallback check on other_staff attendance table
      if (fnIn == null && inTime == null) {
        final response = await http.get(
          Uri.parse("$API_URL/other_staff/attendance?date=$today"),
          headers: {'Authorization': 'Bearer ${widget.token}'},
        );
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final attendance = data['attendance'] as List? ?? [];
          final userRecords = attendance.where((record) => record['reg_no'] == regNo).toList();
          for (var r in userRecords) {
            final st = r['status']?.toString().toLowerCase();
            final ts = r['timestamp']?.toString() ?? '';
            final timePart = ts.contains(' ') ? ts.split(' ')[1] : (ts.contains('T') ? ts.split('T')[1] : ts);
            final cleanTime = timePart.length >= 5 ? timePart.substring(0, 5) : timePart;
            if (st == 'check_in' || st == 'present') {
              inTime ??= cleanTime;
            } else if (st == 'check_out') {
              outTime ??= cleanTime;
            }
          }
        }
      }

      // If multiple slots are active concurrently (e.g. check-in grace period + check-out window active)
      if (activeSlots.length > 1) {
        final bool userHasCin = (slotHalf == 'first_half')
            ? fnIn != null
            : (slotHalf == 'second_half')
                ? anIn != null
                : (inTime != null || fnIn != null || anIn != null);

        Map<String, dynamic>? coutMatch;
        Map<String, dynamic>? cinMatch;
        for (final s in activeSlots) {
          if (s['slot_type'] == 'check_out' && coutMatch == null) {
            coutMatch = s;
          } else if (s['slot_type'] == 'check_in' && cinMatch == null) {
            cinMatch = s;
          }
        }

        if (userHasCin && coutMatch != null) {
          slotType = coutMatch['slot_type']?.toString() ?? 'check_out';
          slotHalf = coutMatch['slot_half']?.toString() ?? slotHalf;
        } else if (cinMatch != null) {
          slotType = cinMatch['slot_type']?.toString() ?? 'check_in';
          slotHalf = cinMatch['slot_half']?.toString() ?? slotHalf;
        }
      }

      // Calculate slot-specific alreadyMarked
      bool alreadyMarked = false;
      if (slotHalf == 'first_half') {
        if (slotType == 'check_in') {
          alreadyMarked = fnIn != null;
        } else if (slotType == 'check_out') {
          alreadyMarked = fnOut != null;
        }
      } else if (slotHalf == 'second_half') {
        if (slotType == 'check_in') {
          alreadyMarked = anIn != null;
        } else if (slotType == 'check_out') {
          alreadyMarked = anOut != null;
        }
      } else {
        // Full day mode
        if (slotType == 'check_in') {
          alreadyMarked = inTime != null;
        } else if (slotType == 'check_out') {
          alreadyMarked = outTime != null;
        }
      }

      setState(() {
        _isWindowAllowed = allowed;
        _isHoliday = isHol;
        _isSpecialOccasion = isSpecial;
        _holidayTitle = holTitle;
        _holidayReason = holReason;
        _dayType = dayType;
        _activeSlotType = slotType;
        _activeSlotHalf = slotHalf;
        _nextSlot = nextSlot;
        _windowMessage = windowMsg;
        _alreadyMarkedCurrentSlot = alreadyMarked;
        _fnInTime = fnIn;
        _fnOutTime = fnOut;
        _anInTime = anIn;
        _anOutTime = anOut;
        _checkInTime = inTime;
        _checkOutTime = outTime;
        _isCheckedIn = inTime != null || fnIn != null || anIn != null;
        _isCheckedOut = outTime != null;
        _todayAttendanceStatus = statusStr;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _navigateToMarkAttendance() {
    if (!_isRegistered) {
      setState(
        () => _message =
            "Please register your face first before marking attendance.",
      );
      return;
    }

    final regNo = widget.user['regNo'] ?? widget.user['reg_no'] ?? '';
    final name = widget.user['name'] ?? '';
    final dept =
        widget.user['dept'] ??
        widget.user['department'] ??
        widget.user['dept_name'] ??
        '';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FaceVerificationWidget(
          token: widget.token,
          regNo: regNo,
          name: name,
          dept: dept,
          onVerifiedData: (data) {
            final isCheckout = data['action'] == 'check_out' || data['slot_type'] == 'check_out' || _activeSlotType == 'check_out';
            final msg = data['message']?.toString() ?? (isCheckout ? 'Check-Out marked successfully!' : 'Attendance marked successfully!');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(isCheckout ? Icons.check_circle_outline : Icons.task_alt, color: Colors.white),
                    const SizedBox(width: 10),
                    Expanded(child: Text(msg)),
                  ],
                ),
                backgroundColor: isCheckout ? const Color(0xFF059669) : widget.accentColor,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            );
            _checkTodayAttendance();
            LocationTrackingService.instance.onAttendanceMarked();
          },
          onVerified: () {
            _checkTodayAttendance();
            LocationTrackingService.instance.onAttendanceMarked();
          },
          onCancel: () => Navigator.pop(context),
        ),
      ),
    );
  }

  void _navigateToFaceRegistration() {
    final regNo = widget.user['regNo'] ?? widget.user['reg_no'] ?? '';
    final name = widget.user['name'] ?? '';
    final dept =
        widget.user['dept'] ??
        widget.user['department'] ??
        widget.user['dept_name'] ??
        '';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FaceRegistrationWidget(
          token: widget.token,
          role: widget.user['role'] ?? 'other_staff',
          initialRegNo: regNo,
          initialName: name,
          initialDept: dept,
          registerEndpoint: '/other_staff/face/register',
          onSuccess: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Face registered successfully!')),
            );
            _checkFaceStatus();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E1E24) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final isCheckOutSlot = _activeSlotType == 'check_out';
    final isCurrentSlotCompleted = _alreadyMarkedCurrentSlot;

    // Check-out requires prior check-in for the active session
    bool canCheckOutCurrentSession = true;
    if (isCheckOutSlot) {
      if (_activeSlotHalf == 'first_half') {
        canCheckOutCurrentSession = _fnInTime != null;
      } else if (_activeSlotHalf == 'second_half') {
        canCheckOutCurrentSession = _anInTime != null;
      } else {
        canCheckOutCurrentSession = _isCheckedIn;
      }
    }

    final isButtonEnabled = _isRegistered &&
        _isWindowAllowed &&
        !isCurrentSlotCompleted &&
        (!isCheckOutSlot || canCheckOutCurrentSession) &&
        !_isHoliday &&
        !_isSpecialOccasion;

    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: widget.accentColor));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: (isCurrentSlotCompleted ? const Color(0xFF10B981) : widget.accentColor).withValues(alpha: 0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isCurrentSlotCompleted
                                ? const [Color(0xFF10B981), Color(0xFF059669)]
                                : (_isHoliday
                                    ? const [Color(0xFF2563EB), Color(0xFF3B82F6)]
                                    : (_isSpecialOccasion
                                        ? const [Color(0xFF7C3AED), Color(0xFF8B5CF6)]
                                        : [widget.accentColor, widget.accentColor.withValues(alpha: 0.7)])),
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          isCurrentSlotCompleted
                              ? Icons.check_circle_rounded
                              : (_isHoliday
                                  ? Icons.beach_access_rounded
                                  : (_isSpecialOccasion
                                      ? Icons.emoji_events_rounded
                                      : Icons.qr_code_scanner)),
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isCurrentSlotCompleted
                                  ? '${_activeSlotHalf == 'first_half' ? 'FN ' : _activeSlotHalf == 'second_half' ? 'AN ' : ''}${isCheckOutSlot ? 'Check-Out' : 'Check-In'} Completed'
                                  : (_isHoliday
                                      ? (_holidayTitle?.isNotEmpty == true ? "Declared Holiday — $_holidayTitle" : "Declared Institutional Holiday")
                                      : (_isSpecialOccasion
                                          ? (_holidayTitle?.isNotEmpty == true ? "Special Occasion — $_holidayTitle" : "Special Institutional Occasion")
                                          : (!_isWindowAllowed
                                              ? 'Attendance Window Closed'
                                              : (isCheckOutSlot && !canCheckOutCurrentSession
                                                  ? 'Check-In Required'
                                                  : 'Mark Your Attendance')))),
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              isCurrentSlotCompleted
                                  ? "Marked at ${isCheckOutSlot ? (_activeSlotHalf == 'first_half' ? _fnOutTime : (_activeSlotHalf == 'second_half' ? _anOutTime : _checkOutTime)) : (_activeSlotHalf == 'first_half' ? _fnInTime : (_activeSlotHalf == 'second_half' ? _anInTime : _checkInTime))}. Attendance recorded."
                                  : (_isHoliday
                                      ? (_holidayReason?.isNotEmpty == true ? _holidayReason! : "Institutional Holiday — No biometric attendance required today.")
                                      : (_isSpecialOccasion
                                          ? (_holidayReason?.isNotEmpty == true ? _holidayReason! : "Special Institutional Occasion — Regular attendance suspended.")
                                          : (!_isWindowAllowed
                                              ? (_windowMessage ?? (_nextSlot != null ? "Next: ${_nextSlot!['start_time']} (${_nextSlot!['effective_duration_minutes'] ?? _nextSlot!['duration_minutes']} min)" : "Outside active attendance window"))
                                              : (isCheckOutSlot && !canCheckOutCurrentSession
                                                  ? "Please scan check-in first before checking out for this session."
                                                  : "Active: ${_activeSlotHalf == 'first_half' ? 'FN ' : _activeSlotHalf == 'second_half' ? 'AN ' : ''}${isCheckOutSlot ? 'Check-Out' : 'Check-In'} Slot — Tap to mark")))),
                              style: TextStyle(
                                fontSize: 13,
                                color: isCurrentSlotCompleted
                                    ? Colors.green[700]
                                    : (_isHoliday
                                        ? const Color(0xFF1D4ED8)
                                        : (_isSpecialOccasion
                                            ? const Color(0xFF6D28D9)
                                            : (!_isWindowAllowed
                                                ? Colors.red[700]
                                                : (isCheckOutSlot && !canCheckOutCurrentSession ? Colors.orange[800] : Colors.orange[700])))),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2A2A30) : const Color(0xFFF8F5FF),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: (isCurrentSlotCompleted ? const Color(0xFF10B981) : widget.accentColor).withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildInfoRow(Icons.person_outline, "Name", widget.user['name'] ?? 'N/A'),
                        const SizedBox(height: 10),
                        _buildInfoRow(Icons.badge_outlined, "ID", widget.user['regNo'] ?? widget.user['reg_no'] ?? 'N/A'),
                        const SizedBox(height: 10),
                        _buildInfoRow(Icons.school_outlined, "Department", widget.user['dept'] ?? widget.user['department'] ?? widget.user['dept_name'] ?? 'N/A'),
                        if (_isCheckedIn || _isCheckedOut || _fnInTime != null || _anInTime != null) ...[
                          const Divider(height: 20),
                          if (_fnInTime != null || _fnOutTime != null || _anInTime != null || _anOutTime != null) ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text("FN Session", style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                    const SizedBox(height: 2),
                                    Text(
                                      "${_fnInTime ?? '--'} / ${_fnOutTime ?? '--'}",
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Text("AN Session", style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                    const SizedBox(height: 2),
                                    Text(
                                      "${_anInTime ?? '--'} / ${_anOutTime ?? '--'}",
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text("Status", style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                    const SizedBox(height: 2),
                                    Text(
                                      _todayAttendanceStatus.isNotEmpty ? _todayAttendanceStatus : (_isCheckedIn ? "Present" : "Pending"),
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _isCheckedIn ? Colors.green.shade700 : Colors.orange.shade700),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ] else ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text("Check-In", style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                    const SizedBox(height: 2),
                                    Text(_checkInTime ?? (_isCheckedIn ? "Present" : "--"), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text("Check-Out", style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                    const SizedBox(height: 2),
                                    Text(_checkOutTime ?? (_isCheckedOut ? "Completed" : "--"), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _isCheckedOut ? Colors.green.shade700 : null)),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text("Status", style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                    const SizedBox(height: 2),
                                    Text(
                                      _todayAttendanceStatus.isNotEmpty ? _todayAttendanceStatus : (_isCheckedIn ? "Present" : "Pending"),
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _isCheckedIn ? Colors.green.shade700 : Colors.orange.shade700),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity, height: 56,
                    child: ElevatedButton.icon(
                      onPressed: isButtonEnabled ? _navigateToMarkAttendance : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isCurrentSlotCompleted
                            ? const Color(0xFF059669)
                            : (_isHoliday
                                ? const Color(0xFF2563EB)
                                : (_isSpecialOccasion ? const Color(0xFF7C3AED) : widget.accentColor)),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: isCurrentSlotCompleted
                            ? const Color(0xFF10B981).withValues(alpha: 0.25)
                            : (_isHoliday
                                ? const Color(0xFF2563EB).withValues(alpha: 0.2)
                                : (_isSpecialOccasion
                                    ? const Color(0xFF8B5CF6).withValues(alpha: 0.2)
                                    : null)),
                        disabledForegroundColor: isCurrentSlotCompleted
                            ? const Color(0xFF047857)
                            : (_isHoliday
                                ? const Color(0xFF1D4ED8)
                                : (_isSpecialOccasion
                                    ? const Color(0xFF6D28D9)
                                    : null)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: (isCurrentSlotCompleted || _isHoliday || _isSpecialOccasion) ? 0 : 8,
                        shadowColor: const Color(0xFF007AFF).withValues(alpha: 0.4),
                      ),
                      icon: Icon(isCurrentSlotCompleted
                          ? Icons.check_circle_rounded
                          : (_isHoliday
                              ? Icons.beach_access_rounded
                              : (_isSpecialOccasion ? Icons.emoji_events_rounded : Icons.qr_code_scanner))),
                      label: Text(
                        _isHoliday
                            ? (_holidayTitle?.isNotEmpty == true ? "Holiday: $_holidayTitle" : "Institutional Holiday")
                            : (_isSpecialOccasion
                                ? (_holidayTitle?.isNotEmpty == true ? "Special: $_holidayTitle" : "Special Occasion")
                                : (!_isWindowAllowed
                                    ? (_nextSlot != null ? "Next: ${_nextSlot!['start_time']}" : "Outside Window")
                                    : (isCurrentSlotCompleted
                                        ? "Already Marked"
                                        : (isCheckOutSlot && !canCheckOutCurrentSession
                                            ? "Check-In Required First"
                                            : "Mark ${_activeSlotHalf == 'first_half' ? 'FN ' : _activeSlotHalf == 'second_half' ? 'AN ' : ''}${isCheckOutSlot ? 'Check-Out' : 'Check-In'}")))),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (!_isRegistered) ...[
            Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.orange.withValues(alpha: 0.15), blurRadius: 20, offset: const Offset(0, 8))],
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.orange.withValues(alpha: 0.2) : Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 28),
                        ),
                        const SizedBox(width: 14),
                        Expanded(child: Text('Face Not Registered', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor))),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.orange.withValues(alpha: 0.2) : Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.orange.shade700, size: 20),
                          const SizedBox(width: 10),
                          Expanded(child: Text('Please register your face to enable attendance marking.', style: TextStyle(fontSize: 14, color: Colors.orange.shade800))),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity, height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _navigateToFaceRegistration,
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 6, shadowColor: Colors.orange.withValues(alpha: 0.4)),
                        icon: const Icon(Icons.face), label: const Text("Register Face"),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 2))]),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: widget.accentColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                        child: Icon(Icons.info_outline, color: widget.accentColor, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Text('Instructions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildInstructionTile(Icons.person_outline, 'Ensure your face is visible and well-lit'),
                  _buildInstructionTile(Icons.camera_alt_outlined, 'Position your face in the camera frame'),
                  _buildInstructionTile(Icons.check_circle_outline, 'Tap capture when ready'),
                  _buildInstructionTile(Icons.access_time_outlined, 'Attendance is marked once verified'),
                ],
              ),
            ),
          ),
          if (_message.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red.withValues(alpha: 0.3))),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_message, style: const TextStyle(color: Colors.red))),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Icon(icon, size: 18, color: widget.accentColor),
        const SizedBox(width: 10),
        Text('$label: ', style: TextStyle(fontSize: 14, color: isDark ? Colors.white60 : const Color(0xFF666666), fontWeight: FontWeight.w500)),
        Expanded(child: Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isDark ? Colors.white : null), overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  Widget _buildInstructionTile(IconData icon, String text) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: widget.accentColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: widget.accentColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(text, style: TextStyle(fontSize: 14, color: isDark ? Colors.white70 : const Color(0xFF333333), height: 1.4)),
            ),
          ),
        ],
      ),
    );
  }
}

// Other Staff Face Registration Tab
class OtherStaffFaceRegisterTab extends StatefulWidget {
  final String token;
  final Map<String, dynamic> user;
  final Color accentColor;

  const OtherStaffFaceRegisterTab({
    super.key,
    required this.token,
    required this.user,
    this.accentColor = const Color(0xFF007AFF),
  });

  @override
  State<OtherStaffFaceRegisterTab> createState() =>
      _OtherStaffFaceRegisterTabState();
}

class _OtherStaffFaceRegisterTabState extends State<OtherStaffFaceRegisterTab> {
  bool _isRegistered = false;
  bool _isLoading = true;
  bool _hasPendingRequest = false;
  bool _canReregister = false;
  String _message = '';

  @override
  void initState() {
    super.initState();
    _checkFaceStatus();
  }

  Future<void> _checkFaceStatus() async {
    try {
      final response = await http.get(
        Uri.parse("$API_URL/other_staff/face/status"),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _isRegistered = data['face_registered'] ?? false;
          _hasPendingRequest = data['has_pending_request'] ?? false;
          _canReregister = data['can_reregister'] ?? false;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _message = "Error checking face status: ${ApiResponseUtils.sanitize(e)}";
        _isLoading = false;
      });
    }
  }

  Future<void> _requestReregister() async {
    try {
      final response = await http.post(
        Uri.parse("$API_URL/other_staff/face/reregister/request"),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Request submitted! Waiting for Admin approval.'),
            backgroundColor: Color(0xFF8BC34A),
          ),
        );
        _checkFaceStatus();
      } else {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['detail'] ?? 'Failed to submit request'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Widget _buildActionButton() {
    if (!_isRegistered) {
      return ElevatedButton.icon(
        onPressed: _navigateToFaceRegistration,
        icon: const Icon(Icons.face),
        label: const Text("Register Face"),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          minimumSize: const Size(double.infinity, 56),
        ),
      );
    }

    if (_canReregister) {
      return ElevatedButton.icon(
        onPressed: _navigateToFaceRegistration,
        icon: const Icon(Icons.refresh),
        label: const Text("Re-register Face"),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.orange,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          minimumSize: const Size(double.infinity, 56),
        ),
      );
    }

    if (_hasPendingRequest) {
      return ElevatedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.hourglass_empty),
        label: const Text("Request Pending"),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.grey,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          minimumSize: const Size(double.infinity, 56),
        ),
      );
    }

    return ElevatedButton.icon(
      onPressed: _requestReregister,
      icon: const Icon(Icons.request_page),
      label: const Text("Request Re-registration"),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        minimumSize: const Size(double.infinity, 56),
      ),
    );
  }

  void _navigateToFaceRegistration() {
    final regNo =
        widget.user['regNo'] ??
        widget.user['reg_no'] ??
        widget.user['registration_no'] ??
        '';
    final name = widget.user['name'] ?? '';
    final dept =
        widget.user['dept'] ??
        widget.user['department'] ??
        widget.user['dept_name'] ??
        widget.user['department_name'] ??
        '';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FaceRegistrationWidget(
          token: widget.token,
          role: widget.user['role'] ?? 'other_staff',
          initialRegNo: regNo,
          initialName: name,
          initialDept: dept,
          registerEndpoint: '/other_staff/face/register',
          onSuccess: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Face registered successfully!')),
            );
            _checkFaceStatus();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E1E24) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: const Color(0xFF007AFF)));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: widget.accentColor.withValues(alpha: 0.1), blurRadius: 20, offset: const Offset(0, 8))]),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(_isRegistered ? Icons.check_circle : Icons.warning_amber_rounded, color: _isRegistered ? Colors.green : Colors.orange, size: 48),
                  const SizedBox(height: 16),
                  Text('Your Face Registration', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor), textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(_isRegistered ? 'Your face is registered' : 'Face not registered yet', style: TextStyle(fontSize: 14, color: _isRegistered ? Colors.green[700] : Colors.orange[700]), textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity, padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: isDark ? const Color(0xFF2A2A30) : const Color(0xFFF8F5FF), borderRadius: BorderRadius.circular(14), border: Border.all(color: widget.accentColor.withValues(alpha: 0.2))),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildInfoRow(Icons.person_outline, 'Name', widget.user['name'] ?? 'N/A'),
                        const SizedBox(height: 10),
                        _buildInfoRow(Icons.badge_outlined, 'ID', widget.user['regNo'] ?? widget.user['reg_no'] ?? 'N/A'),
                        const SizedBox(height: 10),
                        _buildInfoRow(Icons.school_outlined, 'Department', widget.user['dept'] ?? widget.user['department'] ?? widget.user['dept_name'] ?? 'N/A'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(width: double.infinity, height: 56, child: _buildActionButton()),
                  if (_hasPendingRequest) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue)),
                      child: Row(
                        children: [
                          const Icon(Icons.hourglass_empty, color: Colors.blue),
                          const SizedBox(width: 8),
                          Expanded(child: Text('Your re-registration request is pending approval from Admin.', style: TextStyle(color: Colors.blue[700]))),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 2))]),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: widget.accentColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                        child: Icon(Icons.info_outline, color: widget.accentColor, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Text('Instructions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildInstructionTile(Icons.person_outline, 'This section is for registering YOUR own face only'),
                  _buildInstructionTile(Icons.camera_alt_outlined, 'Position your face in the camera frame'),
                  _buildInstructionTile(Icons.check_circle_outline, 'Tap capture when face is detected'),
                  _buildInstructionTile(Icons.save_outlined, 'Confirm registration'),
                ],
              ),
            ),
          ),
          if (_message.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red.withValues(alpha: 0.3))),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_message, style: const TextStyle(color: Colors.red))),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Icon(icon, size: 18, color: widget.accentColor),
        const SizedBox(width: 10),
        Text('$label: ', style: TextStyle(fontSize: 14, color: isDark ? Colors.white60 : const Color(0xFF666666), fontWeight: FontWeight.w500)),
        Expanded(child: Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isDark ? Colors.white : null), overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  Widget _buildInstructionTile(IconData icon, String text) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: widget.accentColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: widget.accentColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(text, style: TextStyle(fontSize: 14, color: isDark ? Colors.white70 : const Color(0xFF333333), height: 1.4)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Boundary Breach Alert Dialog ───────────────────────────────────────────
class _BoundaryBreachDialog extends StatefulWidget {
  final String message;
  const _BoundaryBreachDialog({required this.message});

  @override
  State<_BoundaryBreachDialog> createState() => _BoundaryBreachDialogState();
}

class _BoundaryBreachDialogState extends State<_BoundaryBreachDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ScaleTransition(
        scale: _pulseAnim,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1A0000), Color(0xFF3D0000)],
            ),
            border: Border.all(color: const Color(0xFFFF3333), width: 2),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF3333).withValues(alpha: 0.45),
                blurRadius: 32,
                spreadRadius: 4,
              ),
            ],
          ),
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFF3333).withValues(alpha: 0.15),
                  border: Border.all(color: const Color(0xFFFF3333), width: 2),
                ),
                child: const Icon(
                  Icons.location_off_rounded,
                  color: Color(0xFFFF3333),
                  size: 42,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                '⚠ Boundary Breach Detected',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFFF6666),
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF3333).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFF3333).withValues(alpha: 0.4)),
                ),
                child: Text(
                  widget.message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your attendance may be affected. Please return to the designated area immediately.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFAAAAAA),
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                  label: const Text(
                    'I Understand',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF3333),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
