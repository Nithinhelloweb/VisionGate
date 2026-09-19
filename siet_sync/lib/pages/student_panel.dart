import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/college_ip_config.dart';
import '../services/session_service.dart';
import '../services/theme_service.dart';
import '../services/face_verification_service.dart';
import '../services/client_face_prefilter.dart';
import '../services/location_tracking_service.dart';
import '../widgets/location_permission_enforcer.dart';
import '../widgets/service_health_card.dart';
import '../utils/face_recognition_helper.dart';
import '../utils/api_response_utils.dart';
import '../widgets/thirukkural_banner.dart';
import '../main.dart' show cameras;
import 'student_grievance_page.dart';
import 'holiday_calendar_page.dart';
import '../widgets/academic_schedule/date_timetable_view.dart';
import '../services/api_client.dart';

class _StudentNavEntry {
  final int index;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String? sectionHeader;

  const _StudentNavEntry({
    required this.index,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    this.sectionHeader,
  });
}

class StudentDashboardPage extends StatefulWidget {
  final String token;
  final Map<String, dynamic> user;

  const StudentDashboardPage({
    super.key,
    required this.token,
    required this.user,
  });

  @override
  State<StudentDashboardPage> createState() => _StudentDashboardPageState();
}

class _StudentDashboardPageState extends State<StudentDashboardPage> with WidgetsBindingObserver {
  static const Color primaryBlue = Color(0xFF2563EB); // Royal Blue
  static const Color roseRed = Color(0xFFEF4444);

  static const List<_StudentNavEntry> _studentNavEntries = [
    // MAIN
    _StudentNavEntry(
      index: 0,
      label: 'Dashboard',
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard_rounded,
      sectionHeader: 'Main',
    ),
    _StudentNavEntry(
      index: 1,
      label: 'Mark Attendance',
      icon: Icons.camera_alt_outlined,
      selectedIcon: Icons.camera_alt_rounded,
    ),

    // ACADEMIC & SCHEDULE
    _StudentNavEntry(
      index: 3,
      label: 'Timetable',
      icon: Icons.calendar_today_outlined,
      selectedIcon: Icons.calendar_today_rounded,
      sectionHeader: 'Academic & Schedule',
    ),

    // BIOMETRICS & LOGS
    _StudentNavEntry(
      index: 2,
      label: 'Face Registration',
      icon: Icons.face_retouching_natural_outlined,
      selectedIcon: Icons.face_retouching_natural_rounded,
      sectionHeader: 'Biometrics & Logs',
    ),
    _StudentNavEntry(
      index: 4,
      label: 'Attendance Logs',
      icon: Icons.history_outlined,
      selectedIcon: Icons.history_rounded,
    ),
    _StudentNavEntry(
      index: 6,
      label: 'Analytics',
      icon: Icons.analytics_outlined,
      selectedIcon: Icons.analytics_rounded,
    ),

    // INSTITUTIONAL SERVICES
    _StudentNavEntry(
      index: 5,
      label: 'Leave & OD',
      icon: Icons.assignment_outlined,
      selectedIcon: Icons.assignment_rounded,
      sectionHeader: 'Institutional Services',
    ),
    _StudentNavEntry(
      index: 7,
      label: 'Holiday Calendar',
      icon: Icons.celebration_outlined,
      selectedIcon: Icons.celebration_rounded,
    ),
    _StudentNavEntry(
      index: 8,
      label: 'Grievances',
      icon: Icons.feedback_outlined,
      selectedIcon: Icons.feedback_rounded,
    ),

    // PROFILE
    _StudentNavEntry(
      index: 9,
      label: 'Student ID',
      icon: Icons.badge_outlined,
      selectedIcon: Icons.badge_rounded,
      sectionHeader: 'Profile',
    ),
  ];

  int _selectedIndex = 0;
  Map<String, dynamic> _summary = {};
  Map<String, dynamic> _profile = {};
  Map<String, dynamic> _analytics = {};
  Map<String, dynamic> _todaySchedule = {};
  Map<String, dynamic> _faceRegStatus = {};
  List<dynamic> _notifications = [];
  bool _isLoading = true;
  StreamSubscription<String>? _warningSub;

  // Live Gated Session State
  Map<String, dynamic>? _activeClassSession;
  Timer? _sessionPollTimer;

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
    _fetchStudentData();
    _pollActiveClassSession();
    _startSessionPollTimer();
  }

  void _startSessionPollTimer() {
    _sessionPollTimer?.cancel();
    _sessionPollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _pollActiveClassSession();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _sessionPollTimer?.cancel();
      _sessionPollTimer = null;
    } else if (state == AppLifecycleState.resumed) {
      _pollActiveClassSession();
      _startSessionPollTimer();
      if (!kIsWeb) {
        LocationTrackingService.instance.ensureTrackingActive();
      }
    }
  }

  void _checkOfflineViolations() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if (prefs.getBool('offline_rules_violated') == true) {
      final msg = prefs.getString('offline_violation_message') ??
          'Rule violation detected during offline tracking. You have been marked absent.';
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

  Future<void> _pollActiveClassSession() async {
    try {
      final res = await http.get(
        Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/class-session/active'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200 && mounted) {
        final data = json.decode(res.body);
        setState(() => _activeClassSession = data);
      }
    } catch (_) {}
  }

  Widget _buildActiveClassSessionBanner() {
    final sess = _activeClassSession;
    if (sess == null || sess['session_active'] != true) return const SizedBox.shrink();

    final subName = sess['subject_name'] ?? 'Class Session';
    final periods = (sess['period_numbers'] as List<dynamic>?)?.join(', ') ?? '1';
    final staffName = sess['staff_name'] ?? 'Faculty';
    final isCheckinOpen = sess['checkin_open'] == true;
    final isCheckoutOpen = sess['checkout_open'] == true;
    final alreadyIn = sess['already_checked_in'] == true;
    final alreadyOut = sess['already_checked_out'] == true;

    // If checkin open and not yet marked
    if (isCheckinOpen && !alreadyIn) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF059669),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF059669).withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.radio_button_checked_rounded, color: Colors.white, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Attendance Window Open · Period $periods",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    "$subName  ·  $staffName",
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF059669),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => _navigateToTab(1),
              child: const Text("Mark Now", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
            ),
          ],
        ),
      );
    }

    // If checkin open and already marked
    if (isCheckinOpen && alreadyIn) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF059669).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Color(0xFF059669), size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "✓ Attendance registered for $subName (Period $periods)",
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF059669),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // If checkout open and not yet checked out
    if (isCheckoutOpen && !alreadyOut) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF2563EB),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2563EB).withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.logout_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Check-Out Window Open · $subName",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    "Record your departure for Period $periods",
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF2563EB),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => _navigateToTab(1),
              child: const Text("Face Check-Out", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
            ),
          ],
        ),
      );
    }

    // If checkout open and already checked out
    if (isCheckoutOpen && alreadyOut) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF0D9488).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF0D9488).withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Color(0xFF0D9488), size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "✓ Check-Out registered for $subName (Period $periods)",
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0D9488),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sessionPollTimer?.cancel();
    if (!kIsWeb) {
      _warningSub?.cancel();
    }
    super.dispose();
  }

  Future<void> _fetchStudentData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final url = CollegeIPConfig.defaultURL;

    try {
      // 1. Try single high-speed composite bootstrap endpoint
      final bootRes = await apiClient.get(
        '$url/student/bootstrap',
        token: widget.token,
        timeout: const Duration(seconds: 8),
      );

      if (bootRes.statusCode == 200) {
        final data = jsonDecode(bootRes.body);
        if (data is Map<String, dynamic> && data['success'] == true) {
          if (mounted) {
            setState(() {
              _profile = data['profile'] ?? {};
              _summary = data['summary'] ?? {};
              _analytics = data['analytics'] ?? {};
              _todaySchedule = data['today_schedule'] ?? {};
              _faceRegStatus = data['face_reg_status'] ?? {};
              _notifications = data['notifications'] ?? [];
              if (data['active_session'] != null) {
                _activeClassSession = data['active_session'];
              }
              _isLoading = false;
            });
          }
          return;
        }
      }

      // 2. High-speed parallel fallback using Future.wait
      final results = await Future.wait([
        apiClient.get('$url/student/attendance/summary', token: widget.token),
        apiClient.get('$url/student/profile', token: widget.token),
        apiClient.get('$url/student/analytics/detailed', token: widget.token),
        apiClient.get('$url/student/timetable/today', token: widget.token),
        apiClient.get('$url/student/face-registration/status', token: widget.token),
        apiClient.get('$url/student/notifications', token: widget.token),
      ]);

      if (results[0].statusCode == 200) _summary = jsonDecode(results[0].body);
      if (results[1].statusCode == 200) {
        final d = jsonDecode(results[1].body);
        _profile = d['profile'] ?? {};
      }
      if (results[2].statusCode == 200) _analytics = jsonDecode(results[2].body);
      if (results[3].statusCode == 200) _todaySchedule = jsonDecode(results[3].body);
      if (results[4].statusCode == 200) _faceRegStatus = jsonDecode(results[4].body);
      if (results[5].statusCode == 200) {
        final nd = jsonDecode(results[5].body);
        _notifications = nd['notifications'] ?? [];
      }
    } catch (e) {
      debugPrint("Error fetching student data: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _navigateToTab(int index) {
    if (mounted) {
      setState(() => _selectedIndex = index);
    }
  }

  void _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out of the Student Portal?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: roseRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (!kIsWeb) {
        await _warningSub?.cancel();
        await LocationTrackingService.instance.stopTracking();
      }
      await sessionService.clearSession();
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isWide = MediaQuery.of(context).size.width >= 900;

    final titles = [
      'Student Dashboard',
      'Mark Attendance',
      'Face Registration',
      'Timetable & Schedule',
      'Attendance Logs',
      'Leave & On-Duty',
      'Attendance Analytics',
      'Academic Holiday Calendar',
      'Grievances & Support',
      'Digital ID & Profile',
    ];


    Widget bodyContent = _isLoading
        ? const Center(child: CircularProgressIndicator(color: primaryBlue))
        : IndexedStack(
            index: _selectedIndex,
            children: [
              _StudentHomeTab(
                token: widget.token,
                user: widget.user,
                summary: _summary,
                profile: _profile,
                todaySchedule: _todaySchedule,
                activeSession: _activeClassSession,
                faceRegStatus: _faceRegStatus,
                notifications: _notifications,
                onRefresh: _fetchStudentData,
                onGoToMarkAttendance: () => _navigateToTab(1),
                onGoToFaceRegister: () => _navigateToTab(2),
              ),
              _StudentMarkAttendanceTab(
                token: widget.token,
                user: widget.user,
                profile: _profile,
                summary: _summary,
                todaySchedule: _todaySchedule,
                activeSession: _activeClassSession,
                isActive: _selectedIndex == 1,
                onAttendanceMarked: _fetchStudentData,
                onNavigateToTab: _navigateToTab,
              ),

              _StudentFaceRegistrationTab(
                token: widget.token,
                user: widget.user,
                profile: _profile,
                faceRegStatus: _faceRegStatus,
                isActive: _selectedIndex == 2,
                onRefresh: _fetchStudentData,
              ),
              _StudentTimetableTab(
                token: widget.token,
                user: widget.user,
                profile: _profile,
                todaySchedule: _todaySchedule,
                onRefresh: _fetchStudentData,
              ),
              _StudentAttendanceLogsTab(
                token: widget.token,
                user: widget.user,
              ),
              _StudentLeaveODTab(
                token: widget.token,
                user: widget.user,
              ),
              _StudentAnalyticsTab(
                token: widget.token,
                user: widget.user,
                summary: _summary,
                analytics: _analytics,
                onRefresh: _fetchStudentData,
              ),
              HolidayCalendarPage(
                token: widget.token,
                isAdmin: false,
              ),
              StudentGrievancePage(
                token: widget.token,
                user: widget.user,
                isAdmin: false,
              ),
              _StudentProfileTab(
                token: widget.token,
                user: widget.user,
                profile: _profile,
                faceRegStatus: _faceRegStatus,
                onLogout: _logout,
                onPasswordChanged: _fetchStudentData,
                onGoToFaceRegister: () => _navigateToTab(2),
              ),
            ],
          );


    final scaffold = Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        elevation: 0,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu_rounded, size: 24),
            tooltip: 'Open Menu',
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: Text(
          titles[_selectedIndex],
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: Icon(
              isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
            ),
            tooltip: 'Toggle Theme',
            onPressed: () => themeService.toggleTheme(),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Data',
            onPressed: _fetchStudentData,
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: roseRed),
            tooltip: 'Sign Out',
            onPressed: _logout,
          ),
        ],
      ),
      drawer: _buildStudentDrawer(context),
      body: Row(
        children: [
          if (isWide)
            Container(
              width: 220,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                border: Border(
                  right: BorderSide(
                    color: isDark ? Colors.white12 : Colors.grey.shade200,
                  ),
                ),
              ),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                itemCount: _studentNavEntries.length,
                itemBuilder: (context, index) {
                  final item = _studentNavEntries[index];
                  final isSelected = _selectedIndex == item.index;

                  Widget? headerWidget;
                  if (item.sectionHeader != null) {
                    headerWidget = Padding(
                      padding: const EdgeInsets.only(
                        left: 10,
                        right: 10,
                        top: 14,
                        bottom: 6,
                      ),
                      child: Text(
                        item.sectionHeader!.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: isDark ? Colors.white38 : Colors.grey.shade500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }

                  final itemTile = Container(
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    child: Material(
                      color: isSelected
                          ? primaryBlue.withValues(alpha: isDark ? 0.2 : 0.1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        onTap: () => setState(() => _selectedIndex = item.index),
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 9,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isSelected ? item.selectedIcon : item.icon,
                                color: isSelected
                                    ? primaryBlue
                                    : (isDark ? Colors.white60 : Colors.grey.shade600),
                                size: 19,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  item.label,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                    color: isSelected
                                        ? primaryBlue
                                        : (isDark ? Colors.white70 : Colors.grey.shade800),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );

                  if (headerWidget != null) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        headerWidget,
                        itemTile,
                      ],
                    );
                  }
                  return itemTile;
                },
              ),
            ),
          Expanded(
            child: Column(
              children: [
                _buildActiveClassSessionBanner(),
                Expanded(child: bodyContent),
              ],
            ),
          ),
        ],
      ),
    );

    return kIsWeb ? scaffold : LocationPermissionEnforcer(child: scaffold);
  }

  Widget _buildStudentDrawer(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final name = (_profile['name'] ?? widget.user['name'] ?? 'Student').toString();
    final regNo = (_profile['reg_no'] ?? widget.user['reg_no'] ?? '').toString();
    final rollNo = (_profile['roll_no'] ?? widget.user['roll_no'] ?? '').toString();
    final dept = (_profile['dept'] ?? widget.user['dept'] ?? 'CSE').toString();
    final degree = (_profile['degree'] ?? widget.user['degree'] ?? 'B.E.').toString();
    final sem = (_profile['semester'] ?? widget.user['semester'] ?? '6').toString();
    final sec = (_profile['section'] ?? widget.user['section'] ?? 'A').toString();
    final batch = (_profile['batch'] ?? widget.user['batch'] ?? '2022-2026').toString();
    final isFaceEnrolled = (_faceRegStatus['face_registration']?['is_enrolled'] == true) ||
        (_profile['face_prototype_ready'] == true);

    final nowHour = DateTime.now().hour;
    final activeSession = nowHour < 13 ? "FN Open" : "AN Open";

    return Drawer(
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      child: Column(
        children: [
          // Modern Student Profile Banner
          Container(
            width: double.infinity,
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 16,
              bottom: 18,
              left: 18,
              right: 18,
            ),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF2563EB), Color(0xFF4F46E5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : 'S',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: (isFaceEnrolled ? const Color(0xFF10B981) : Colors.amber).withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: (isFaceEnrolled ? const Color(0xFF10B981) : Colors.amber).withValues(alpha: 0.6),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isFaceEnrolled ? Icons.verified_rounded : Icons.pending_actions_rounded,
                            size: 13,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isFaceEnrolled ? 'Face ID Ready' : 'Setup Face ID',
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  name,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '$regNo ${rollNo.isNotEmpty ? '• ($rollNo)' : ''}',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$degree $dept',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Sem $sem ($sec)',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        batch,
                        style: const TextStyle(color: Colors.white, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Drawer Navigation Items List
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              children: [
                _buildDrawerSectionHeader('MAIN', isDark),
                _buildDrawerItem(
                  index: 0,
                  title: 'Dashboard & Overview',
                  icon: Icons.dashboard_rounded,
                  color: const Color(0xFF2563EB),
                  isDark: isDark,
                ),
                _buildDrawerItem(
                  index: 1,
                  title: 'Mark Attendance',
                  icon: Icons.camera_alt_rounded,
                  color: const Color(0xFF4F46E5),
                  badge: activeSession,
                  badgeColor: const Color(0xFF10B981),
                  isDark: isDark,
                ),

                const SizedBox(height: 10),
                _buildDrawerSectionHeader('ACADEMIC & SCHEDULE', isDark),
                _buildDrawerItem(
                  index: 3,
                  title: 'Timetable & Schedule',
                  icon: Icons.calendar_today_rounded,
                  color: const Color(0xFFEA580C),
                  isDark: isDark,
                ),

                const SizedBox(height: 10),
                _buildDrawerSectionHeader('BIOMETRICS & LOGS', isDark),
                _buildDrawerItem(
                  index: 2,
                  title: 'Face ID Registration',
                  icon: Icons.face_retouching_natural_rounded,
                  color: const Color(0xFF0D9488),
                  badge: isFaceEnrolled ? 'Active' : 'Required',
                  badgeColor: isFaceEnrolled ? const Color(0xFF10B981) : Colors.orange,
                  isDark: isDark,
                ),
                _buildDrawerItem(
                  index: 4,
                  title: 'Attendance Logs',
                  icon: Icons.history_rounded,
                  color: const Color(0xFF0284C7),
                  isDark: isDark,
                ),
                _buildDrawerItem(
                  index: 6,
                  title: 'Attendance Analytics',
                  icon: Icons.analytics_rounded,
                  color: const Color(0xFF7C3AED),
                  isDark: isDark,
                ),

                const SizedBox(height: 10),
                _buildDrawerSectionHeader('INSTITUTIONAL SERVICES', isDark),
                _buildDrawerItem(
                  index: 5,
                  title: 'Leave & On-Duty (OD)',
                  icon: Icons.assignment_rounded,
                  color: const Color(0xFF059669),
                  isDark: isDark,
                ),
                _buildDrawerItem(
                  index: 7,
                  title: 'Holiday Calendar',
                  icon: Icons.celebration_rounded,
                  color: const Color(0xFF8B5CF6),
                  isDark: isDark,
                ),
                _buildDrawerItem(
                  index: 8,
                  title: 'Grievances & Support',
                  icon: Icons.feedback_rounded,
                  color: const Color(0xFFF97316),
                  isDark: isDark,
                ),

                const SizedBox(height: 10),
                _buildDrawerSectionHeader('PROFILE', isDark),
                _buildDrawerItem(
                  index: 9,
                  title: 'Digital ID & Profile',
                  icon: Icons.badge_rounded,
                  color: const Color(0xFF2563EB),
                  isDark: isDark,
                ),
              ],
            ),

          ),

          // Drawer Footer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
              border: Border(
                top: BorderSide(
                  color: isDark ? Colors.white12 : Colors.grey.shade200,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _logout();
                    },
                    icon: const Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 18),
                    label: const Text(
                      'Sign Out',
                      style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      alignment: Alignment.centerLeft,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                    size: 20,
                  ),
                  tooltip: 'Toggle Theme',
                  onPressed: () => themeService.toggleTheme(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerSectionHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 6, top: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: isDark ? Colors.white38 : Colors.grey.shade500,
        ),
      ),
    );
  }

  Widget _buildDrawerItem({
    required int index,
    required String title,
    required IconData icon,
    required Color color,
    required bool isDark,
    String? badge,
    Color? badgeColor,
  }) {
    final isSelected = _selectedIndex == index;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: isSelected
            ? color.withValues(alpha: isDark ? 0.2 : 0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () {
            Navigator.pop(context);
            _navigateToTab(index);
          },
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: isSelected
                  ? Border.all(color: color.withValues(alpha: 0.4), width: 1.2)
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? color
                        : (isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade100),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    size: 18,
                    color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.grey.shade700),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected
                          ? (isDark ? Colors.white : color)
                          : (isDark ? Colors.white70 : Colors.black87),
                    ),
                  ),
                ),
                if (badge != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: (badgeColor ?? color).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: (badgeColor ?? color).withValues(alpha: 0.4),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(
                        color: badgeColor ?? color,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// TAB 0: STUDENT HOME & DASHBOARD
// ─────────────────────────────────────────────────────────
class _StudentHomeTab extends StatelessWidget {
  final String token;
  final Map<String, dynamic> user;
  final Map<String, dynamic> summary;
  final Map<String, dynamic> profile;
  final Map<String, dynamic> todaySchedule;
  final Map<String, dynamic>? activeSession;
  final Map<String, dynamic> faceRegStatus;
  final List<dynamic> notifications;
  final VoidCallback onRefresh;
  final VoidCallback onGoToMarkAttendance;
  final VoidCallback onGoToFaceRegister;

  const _StudentHomeTab({
    required this.token,
    required this.user,
    required this.summary,
    required this.profile,
    required this.todaySchedule,
    this.activeSession,
    required this.faceRegStatus,
    required this.notifications,
    required this.onRefresh,
    required this.onGoToMarkAttendance,
    required this.onGoToFaceRegister,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final name = (profile['name'] ?? user['name'] ?? 'Student').toString();
    final regNo = (profile['reg_no'] ?? user['reg_no'] ?? user['regNo'] ?? '').toString();
    final dept = (profile['dept'] ?? user['dept'] ?? 'CSE').toString();
    final sem = (profile['semester'] ?? user['semester'] ?? '6').toString();
    final sec = (profile['section'] ?? user['section'] ?? 'A').toString();
    final batch = (profile['batch'] ?? user['batch'] ?? '2022-2026').toString();
    final rollNo = (profile['roll_no'] ?? user['roll_no'] ?? '').toString();

    final pct = double.tryParse((summary['attendance_percentage'] ?? 100.0).toString()) ?? 100.0;
    final isShortage = pct < 75.0;
    final todayStatus = (summary['today_status'] ?? 'Not Marked').toString();

    final isFaceEnrolled = (faceRegStatus['face_registration']?['is_enrolled'] == true) ||
        (profile['face_prototype_ready'] == true);

    final bool isOffDay = todaySchedule['is_off_day'] == true || todaySchedule['is_holiday'] == true || todaySchedule['is_special_occasion'] == true;
    final String leaveLabel = (todaySchedule['off_type'] == 'APPROVED_OD'
        ? 'On-Duty'
        : (todaySchedule['off_type'] == 'APPROVED_MEDICAL'
            ? 'Medical Leave'
            : (todaySchedule['off_type'] == 'SPECIAL_EVENT' || todaySchedule['off_type'] == 'SPECIAL_OCCASION' || todaySchedule['is_special_occasion'] == true
                ? (todaySchedule['holiday_title']?.toString().isNotEmpty == true
                    ? todaySchedule['holiday_title'].toString()
                    : (todaySchedule['holiday_reason']?.toString().isNotEmpty == true
                        ? todaySchedule['holiday_reason'].toString()
                        : 'Special Occasion'))
                : (todaySchedule['holiday_title']?.toString().isNotEmpty == true
                    ? todaySchedule['holiday_title'].toString()
                    : (todaySchedule['holiday_reason']?.toString().isNotEmpty == true
                        ? todaySchedule['holiday_reason'].toString()
                        : 'College Holiday')))));


    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Student Identity Header Banner
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2563EB), Color(0xFF4F46E5)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    child: const Icon(Icons.person, color: Colors.white, size: 38),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '$regNo ${rollNo.isNotEmpty ? '($rollNo)' : ''} | $dept - Sem $sem ($sec)',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'Batch: $batch',
                                style: const TextStyle(color: Colors.white, fontSize: 11),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                color: (todayStatus == 'Present' ? const Color(0xFF10B981) : Colors.amber)
                                    .withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    todayStatus == 'Present' ? Icons.check_circle : Icons.schedule,
                                    color: Colors.white,
                                    size: 12,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Today: $todayStatus',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 2. QUICK SHORTCUT HERO CARDS (Mark Attendance & Face Registration)
            Builder(
              builder: (context) {
                final bool isSessionLive = activeSession != null &&
                    activeSession!['session_active'] == true &&
                    activeSession!['checkin_open'] == true;
                final String sessSubject = (activeSession?['subject_name'] ?? '').toString();
                final String liveStatusText = isSessionLive
                    ? (sessSubject.isNotEmpty ? 'Live • $sessSubject' : 'Recording Live')
                    : 'Waiting for Faculty';
                final Color cardAccentColor = isOffDay
                    ? const Color(0xFF3B82F6)
                    : (isSessionLive ? const Color(0xFF10B981) : const Color(0xFF64748B));

                return Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: onGoToMarkAttendance,
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: isDark
                                  ? (isOffDay
                                      ? [const Color(0xFF1E293B), const Color(0xFF1E3A8A)]
                                      : (isSessionLive
                                          ? [const Color(0xFF1E293B), const Color(0xFF064E3B)]
                                          : [const Color(0xFF1E293B), const Color(0xFF0F172A)]))
                                  : (isSessionLive
                                      ? [Colors.white, const Color(0xFFECFDF5)]
                                      : [Colors.white, const Color(0xFFF8FAFC)]),
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: cardAccentColor.withValues(alpha: isSessionLive ? 0.45 : 0.25),
                              width: isSessionLive ? 1.5 : 1.0,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: cardAccentColor.withValues(alpha: isSessionLive ? 0.15 : 0.05),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: cardAccentColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      isOffDay
                                          ? Icons.beach_access_rounded
                                          : (isSessionLive ? Icons.camera_alt_rounded : Icons.lock_clock_rounded),
                                      color: cardAccentColor,
                                      size: 20,
                                    ),
                                  ),
                                  Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    size: 14,
                                    color: cardAccentColor,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                isOffDay ? 'Academic Leave' : (isSessionLive ? 'Mark Attendance' : 'Attendance Locked'),
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isOffDay ? 'Excused • $leaveLabel' : liveStatusText,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: cardAccentColor,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: onGoToFaceRegister,
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: isDark
                                  ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                                  : [Colors.white, const Color(0xFFF0FDF4)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFF10B981).withValues(alpha: 0.3),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF10B981).withValues(alpha: 0.08),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      isFaceEnrolled ? Icons.face_retouching_natural_rounded : Icons.face_rounded,
                                      color: const Color(0xFF10B981),
                                      size: 20,
                                    ),
                                  ),
                                  const Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    size: 14,
                                    color: Color(0xFF10B981),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Face ID Profile',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isFaceEnrolled ? 'Biometric Active' : 'Enroll Face ID',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isFaceEnrolled ? const Color(0xFF10B981) : Colors.amber.shade700,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.apps_rounded,
                  size: 15,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
                const SizedBox(width: 8),
                Text(
                  'Institutional Services & Support',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (ctx) => StudentGrievancePage(
                            token: token,
                            user: user,
                            isAdmin: false,
                          ),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.teal.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.teal.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.feedback_outlined, color: Colors.teal, size: 18),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Grievances', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                Text('Raise Ticket', style: TextStyle(fontSize: 11, color: Colors.teal)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (ctx) => HolidayCalendarPage(
                            token: token,
                            isAdmin: false,
                          ),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : Colors.purple.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.purple.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.celebration_outlined, color: Colors.purple, size: 18),
                          ),

                          const SizedBox(width: 10),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Holidays', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                Text('View Dates', style: TextStyle(fontSize: 11, color: Colors.purple)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 3. Daily Thirukkural Quote Banner
            const ThirukkuralBanner(),
            const ServiceHealthCard(),
            const SizedBox(height: 16),


            // 4. Attendance Standing & Circular Gauge
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.grey.shade200,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text(
                          'Overall Attendance Standing',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: (isShortage ? const Color(0xFFEF4444) : const Color(0xFF10B981))
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          isShortage ? 'Shortage Alert' : 'Eligible for Exams',
                          style: TextStyle(
                            color: isShortage ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 90,
                            height: 90,
                            child: CircularProgressIndicator(
                              value: (pct / 100.0).clamp(0.0, 1.0),
                              strokeWidth: 9,
                              backgroundColor: Colors.grey.withValues(alpha: 0.15),
                              color: isShortage
                                  ? const Color(0xFFEF4444)
                                  : (pct >= 85 ? const Color(0xFF10B981) : const Color(0xFF2563EB)),
                            ),
                          ),
                          Text(
                            '$pct%',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isShortage
                                  ? 'Attendance Shortage Risk!'
                                  : (pct >= 85 ? 'Excellent Attendance' : 'Good Standing'),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: isShortage ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isShortage
                                  ? 'Your attendance is below the 75% threshold. Apply for OD or attend upcoming sessions.'
                                  : 'Above 75% minimum required for semester examinations.',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white70 : Colors.grey.shade600,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 5. Metric Stat Cards Grid
            Row(
              children: [
                Expanded(
                  child: _buildMetricCard(
                    title: 'Present Sessions',
                    count: '${summary['present_count'] ?? 0}',
                    icon: Icons.check_circle_outline_rounded,
                    color: const Color(0xFF10B981),
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMetricCard(
                    title: 'On-Duty (OD)',
                    count: '${summary['on_duty_count'] ?? 0}',
                    icon: Icons.work_outline_rounded,
                    color: const Color(0xFF2563EB),
                    isDark: isDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildMetricCard(
                    title: 'Medical Leaves',
                    count: '${summary['medical_count'] ?? 0}',
                    icon: Icons.local_hospital_outlined,
                    color: const Color(0xFFF59E0B),
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMetricCard(
                    title: 'Absent Sessions',
                    count: '${summary['absent_count'] ?? 0}',
                    icon: Icons.cancel_outlined,
                    color: const Color(0xFFEF4444),
                    isDark: isDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 6. Today's Class Schedule Preview
            if (todaySchedule['periods'] != null && (todaySchedule['periods'] as List).isNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Today's Class Schedule",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Text(
                    todaySchedule['day_of_week'] ?? 'Today',
                    style: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...((todaySchedule['periods'] as List).take(3)).map((p) {
                if (p['type'] == 'break') {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B).withValues(alpha: 0.5) : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.coffee_rounded, size: 16, color: Colors.orange),
                        const SizedBox(width: 8),
                        Text(
                          '${p['title']} (${p['display_time']})',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  );
                }

                final isLive = p['status'] == 'LIVE NOW';
                final isFree = p['is_free'] == true ||
                    (p['subject_code'] ?? '').toString().isEmpty ||
                    (p['subject_name'] ?? '').toString() == 'Free Period';

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isLive
                          ? const Color(0xFF2563EB)
                          : (isDark ? Colors.white12 : Colors.grey.shade200),
                      width: isLive ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: (isLive
                                  ? const Color(0xFF2563EB)
                                  : (isFree ? Colors.grey.shade400 : const Color(0xFF4F46E5)))
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'P${p['period_number']}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isLive
                                ? const Color(0xFF2563EB)
                                : (isFree ? Colors.grey : const Color(0xFF4F46E5)),
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isFree
                                  ? 'Free Period'
                                  : '${p['subject_code']} - ${p['subject_name']}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: isFree
                                    ? (isDark ? Colors.white60 : Colors.grey.shade700)
                                    : null,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isFree
                                  ? 'Self Study / Library Slot'
                                  : '${p['faculty']}${(p['room'] ?? '').toString().isNotEmpty ? ' • ${p['room']}' : ''}',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? Colors.white60 : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            p['display_time'] ?? '',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                          if (isLive)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2563EB),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'LIVE',
                                style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String count,
    required IconData icon,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  count,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white60 : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// TAB 1: DEDICATED SEPARATE TAB - MARK ATTENDANCE
// ─────────────────────────────────────────────────────────
class _StudentMarkAttendanceTab extends StatefulWidget {
  final String token;
  final Map<String, dynamic> user;
  final Map<String, dynamic> profile;
  final Map<String, dynamic> summary;
  final Map<String, dynamic> todaySchedule;
  final Map<String, dynamic>? activeSession;
  final bool isActive;
  final VoidCallback onAttendanceMarked;
  final Function(int)? onNavigateToTab;

  const _StudentMarkAttendanceTab({
    required this.token,
    required this.user,
    required this.profile,
    required this.summary,
    this.todaySchedule = const {},
    this.activeSession,
    this.isActive = true,
    required this.onAttendanceMarked,
    this.onNavigateToTab,
  });

  @override
  State<_StudentMarkAttendanceTab> createState() => _StudentMarkAttendanceTabState();
}

class _StudentMarkAttendanceTabState extends State<_StudentMarkAttendanceTab> with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isCameraReady = false;
  bool _isInitializingCamera = false;
  bool _isPermissionDenied = false;
  bool _isProcessing = false;
  String _statusMessage = "Position face inside frame";
  String _errorMessage = "";
  Map<String, dynamic>? _lastMarkedReceipt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.isActive) {
      final isOff = widget.todaySchedule['is_off_day'] == true ||
          widget.todaySchedule['is_holiday'] == true ||
          widget.todaySchedule['attendance_required'] == false;
      if (!isOff) {
        _initCamera();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _disposeCamera();
    } else if (state == AppLifecycleState.resumed) {
      if (widget.isActive) {
        final isOff = widget.todaySchedule['is_off_day'] == true ||
            widget.todaySchedule['is_holiday'] == true ||
            widget.todaySchedule['attendance_required'] == false;
        if (!isOff && !_isCameraReady && !_isInitializingCamera) {
          _initCamera();
        }
      }
    }
  }

  @override
  void didUpdateWidget(_StudentMarkAttendanceTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        final isOff = widget.todaySchedule['is_off_day'] == true ||
            widget.todaySchedule['is_holiday'] == true ||
            widget.todaySchedule['attendance_required'] == false;
        if (!isOff && !_isCameraReady && !_isInitializingCamera) {
          _initCamera();
        }
      } else {
        _disposeCamera();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeCameraSync();
    super.dispose();
  }

  void _disposeCameraSync() {
    final ctrl = _cameraController;
    _cameraController = null;
    ctrl?.dispose();
    _isCameraReady = false;
    _isInitializingCamera = false;
  }

  Future<void> _disposeCamera() async {
    if (_cameraController != null) {
      try {
        final ctrl = _cameraController;
        _cameraController = null;
        await ctrl?.dispose();
      } catch (e) {
        debugPrint("Attendance camera disposal error: $e");
      }
    }
    if (mounted) {
      setState(() {
        _isCameraReady = false;
        _isInitializingCamera = false;
      });
    }
  }

  Future<void> _initCamera() async {
    if (_isInitializingCamera) return;
    if (!widget.isActive) return;

    setState(() {
      _isInitializingCamera = true;
      _errorMessage = "";
      _isPermissionDenied = false;
    });

    try {
      // 1. Permission check (non-web)
      if (!kIsWeb) {
        var status = await Permission.camera.status;
        if (!status.isGranted) {
          status = await Permission.camera.request();
          if (!status.isGranted) {
            if (mounted) {
              setState(() {
                _isPermissionDenied = true;
                _errorMessage = "Camera permission is required to verify face and mark attendance.";
                _isInitializingCamera = false;
                _isCameraReady = false;
              });
            }
            return;
          }
        }
      }

      // 2. Fetch available cameras
      try {
        _cameras = await availableCameras().timeout(const Duration(seconds: 4));
      } catch (_) {
        if (cameras.isNotEmpty) {
          _cameras = cameras;
        }
      }

      if (_cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _errorMessage = "No camera found on this device.";
            _isInitializingCamera = false;
            _isCameraReady = false;
          });
        }
        return;
      }

      // 3. Strictly select Front Camera
      final frontCamera = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras.first,
      );

      // 4. Dispose previous controller if any
      if (_cameraController != null) {
        final old = _cameraController;
        _cameraController = null;
        await old?.dispose();
      }

      // 5. Create new controller strictly with Front Camera
      final ctrl = CameraController(
        frontCamera,
        kIsWeb ? ResolutionPreset.medium : ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await ctrl.initialize().timeout(const Duration(seconds: 8));

      if (!mounted || !widget.isActive) {
        await ctrl.dispose();
        return;
      }

      setState(() {
        _cameraController = ctrl;
        _isCameraReady = true;
        _isInitializingCamera = false;
        _isPermissionDenied = false;
        _errorMessage = "";
        _statusMessage = "Position face inside frame";
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCameraReady = false;
          _isInitializingCamera = false;
          _errorMessage = "Camera initialization error: ${ApiResponseUtils.sanitize(e)}";
        });
      }
    }
  }

  Future<void> _captureAndMark() async {
    if (_isProcessing || _cameraController == null || !_cameraController!.value.isInitialized) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = "Verifying biometric face & campus geofence...";
      _errorMessage = "";
    });

    try {
      final XFile? captured = await FaceRecognitionHelper.captureBestFrame(_cameraController!, maxFrames: 3);
      if (captured == null) {
        setState(() {
          _isProcessing = false;
          _errorMessage = "Could not capture clear image. Hold phone steady.";
        });
        return;
      }

      final isCheckout = _isCheckoutOpen;
      final sessionId = widget.activeSession?['session_id']?.toString();

      final result = isCheckout
          ? await FaceVerificationService.markStudentCheckout(
              token: widget.token,
              imageFile: captured,
              sessionId: sessionId,
              onError: (err) {
                if (mounted) {
                  setState(() {
                    _isProcessing = false;
                    _errorMessage = err;
                  });
                }
              },
            )
          : await FaceVerificationService.markStudentAttendance(
              token: widget.token,
              imageFile: captured,
              onError: (err) {
                if (mounted) {
                  setState(() {
                    _isProcessing = false;
                    _errorMessage = err;
                  });
                }
              },
            );

      if (result['success'] == true) {
        // Link to active class session if open for check-in
        if (!isCheckout &&
            widget.activeSession != null &&
            widget.activeSession!['session_active'] == true &&
            widget.activeSession!['checkin_open'] == true) {
          try {
            await http.post(
              Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/class-session/student-checkin'),
              headers: {
                'Authorization': 'Bearer ${widget.token}',
                'Content-Type': 'application/json',
              },
              body: json.encode({
                'session_id': widget.activeSession!['session_id'],
                'face_verified': true,
              }),
            ).timeout(const Duration(seconds: 10));
          } catch (_) {}
        }

        if (mounted) {
          final successMsg = result['message']?.toString() ??
              (isCheckout
                  ? "✅ Check-Out successfully verified with face recognition!"
                  : "✅ Attendance successfully verified!");
          setState(() {
            _isProcessing = false;
            _lastMarkedReceipt = result;
            _statusMessage = successMsg;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(
                    isCheckout ? Icons.exit_to_app_rounded : Icons.check_circle_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      successMsg,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                ],
              ),
              backgroundColor: isCheckout ? const Color(0xFF0D9488) : const Color(0xFF059669),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              duration: const Duration(seconds: 4),
            ),
          );
          widget.onAttendanceMarked();
          LocationTrackingService.instance.onAttendanceMarked();
        }
      } else {
        if (mounted) {
          setState(() {
            _isProcessing = false;
            _errorMessage = result['error'] ?? "Face verification failed";
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _errorMessage = "Verification error: ${ApiResponseUtils.sanitize(e)}";
        });
      }
    }
  }

  Widget _buildExemptionPoint({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required bool isDark,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white60 : Colors.grey.shade600,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLeaveExemptionScreen(BuildContext context, bool isDark) {
    final offType = widget.todaySchedule['off_type'] ?? (widget.todaySchedule['is_special_occasion'] == true ? 'SPECIAL_OCCASION' : 'HOLIDAY');
    final holidayReason = widget.todaySchedule['holiday_reason'] ?? widget.todaySchedule['holiday_title'] ?? widget.todaySchedule['reason'] ?? widget.todaySchedule['message'] ?? 'Academic Leave / Holiday';
    final isOD = offType == 'APPROVED_OD';
    final isMedical = offType == 'APPROVED_MEDICAL';
    final isLeave = offType == 'APPROVED_LEAVE';
    final isSpecial = offType == 'SPECIAL_EVENT' || offType == 'SPECIAL_OCCASION' || widget.todaySchedule['is_special_occasion'] == true;

    final IconData iconData = isOD
        ? Icons.badge_rounded
        : (isMedical
            ? Icons.medical_services_rounded
            : (isLeave
                ? Icons.assignment_turned_in_rounded
                : (isSpecial ? Icons.emoji_events_rounded : Icons.beach_access_rounded)));

    final String title = isOD
        ? 'On-Duty Leave Active'
        : (isMedical
            ? 'Medical Leave Active'
            : (isLeave
                ? 'Approved Leave Active'
                : (isSpecial
                    ? (widget.todaySchedule['holiday_title']?.toString().isNotEmpty == true
                        ? widget.todaySchedule['holiday_title'].toString()
                        : 'Special Institutional Occasion')
                    : (widget.todaySchedule['holiday_title']?.toString().isNotEmpty == true
                        ? widget.todaySchedule['holiday_title'].toString()
                        : 'Academic Holiday'))));

    final Color badgeColor = isOD
        ? const Color(0xFF0EA5E9)
        : (isMedical
            ? const Color(0xFF10B981)
            : (isLeave
                ? const Color(0xFF8B5CF6)
                : (isSpecial ? const Color(0xFF7C3AED) : const Color(0xFF2563EB))));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Top Exemption Hero Card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                    : [badgeColor.withValues(alpha: 0.1), Colors.white],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
              boxShadow: [
                BoxShadow(
                  color: badgeColor.withValues(alpha: 0.1),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: badgeColor.withValues(alpha: 0.3), width: 2),
                  ),
                  child: Icon(iconData, size: 48, color: badgeColor),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'ATTENDANCE NOT REQUIRED',
                    style: TextStyle(
                      color: badgeColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  holidayReason.toString(),
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white70 : Colors.grey.shade700,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 2. Status Points Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Academic Exemption Details',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 14),
                _buildExemptionPoint(
                  icon: Icons.check_circle_rounded,
                  color: const Color(0xFF10B981),
                  title: 'Official Leave Credited',
                  subtitle: 'This session is automatically recognized and recorded as Leave in your attendance ledger.',
                  isDark: isDark,
                ),
                const SizedBox(height: 12),
                _buildExemptionPoint(
                  icon: Icons.shield_rounded,
                  color: const Color(0xFF2563EB),
                  title: 'Percentage Protected',
                  subtitle: 'Your overall attendance percentage is not penalized for this declared leave.',
                  isDark: isDark,
                ),
                const SizedBox(height: 12),
                _buildExemptionPoint(
                  icon: Icons.sensors_off_rounded,
                  color: const Color(0xFFF59E0B),
                  title: 'Biometrics Suppressed',
                  subtitle: 'Face scanning and geofence marking are temporarily turned off for today.',
                  isDark: isDark,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 3. Quick Action Buttons
          if (widget.onNavigateToTab != null)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => widget.onNavigateToTab!(3), // Timetable tab
                    icon: const Icon(Icons.calendar_month_rounded, size: 18),
                    label: const Text('View Timetable'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => widget.onNavigateToTab!(4), // Leave / OD tab
                    icon: const Icon(Icons.assignment_rounded, size: 18),
                    label: const Text('Leave History'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: badgeColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSafeCameraPreview(CameraController ctrl) {
    final size = ctrl.value.previewSize;
    if (size == null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: CameraPreview(ctrl),
      );
    }
    final double previewW = kIsWeb ? size.width : (size.height < size.width ? size.height : size.width);
    final double previewH = kIsWeb ? size.height : (size.height < size.width ? size.width : size.height);

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: previewW,
            height: previewH,
            child: CameraPreview(ctrl),
          ),
        ),
      ),
    );
  }

  Widget _buildCameraViewfinderCard({required bool isDark, required double height}) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.black87,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: _isProcessing
              ? Colors.amber
              : (_lastMarkedReceipt != null
                  ? const Color(0xFF10B981)
                  : (_errorMessage.isNotEmpty
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF2563EB))),
          width: 2.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (_lastMarkedReceipt != null
                    ? const Color(0xFF10B981)
                    : (_isProcessing ? Colors.amber : const Color(0xFF2563EB)))
                .withValues(alpha: 0.15),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            if (_isCameraReady && _cameraController != null && _cameraController!.value.isInitialized) ...[
              _buildSafeCameraPreview(_cameraController!),
              CustomPaint(
                painter: _BiometricViewfinderPainter(
                  isProcessing: _isProcessing,
                  isSuccess: _lastMarkedReceipt != null,
                ),
              ),
            ] else if (_isPermissionDenied)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.videocam_off_rounded, color: Colors.redAccent, size: 40),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        "Camera Access Required",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Camera permission is needed to verify your face for attendance.",
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () => _initCamera(),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.refresh_rounded, size: 16),
                            label: const Text("Grant Permission"),
                          ),
                          if (!kIsWeb) ...[
                            const SizedBox(width: 10),
                            OutlinedButton.icon(
                              onPressed: () => openAppSettings(),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white38),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              icon: const Icon(Icons.settings_rounded, size: 16),
                              label: const Text("Settings"),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              )
            else if (_errorMessage.isNotEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 40),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        "Camera Unavailable",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _errorMessage,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () => _initCamera(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text("Retry Camera"),
                      ),
                    ],
                  ),
                ),
              )
            else
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Color(0xFF2563EB)),
                    const SizedBox(height: 16),
                    Text(
                      "Starting camera...",
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13),
                    ),
                  ],
                ),
              ),

            // Top-right controls: Reconnect camera
            if (_isCameraReady)
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 18),
                    tooltip: "Reconnect Camera",
                    onPressed: () => _initCamera(),
                  ),
                ),
              ),

            // Processing Loading Indicator in center
            if (_isProcessing)
              Container(
                color: Colors.black.withValues(alpha: 0.35),
                child: const Center(
                  child: CircularProgressIndicator(strokeWidth: 3, color: Colors.amber),
                ),
              ),

            // Success Confirmation Overlay
            if (_lastMarkedReceipt != null)
              Container(
                color: const Color(0xFF10B981).withValues(alpha: 0.2),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: Color(0xFF10B981),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_rounded, color: Colors.white, size: 36),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  bool get _isSessionOpen {
    final sess = widget.activeSession;
    return sess != null &&
        sess['session_active'] == true &&
        (sess['checkin_open'] == true ||
            sess['checkout_open'] == true ||
            sess['status'] == 'checkout_open' ||
            sess['status'] == 'checkin_open');
  }

  bool get _isCheckoutOpen {
    final sess = widget.activeSession;
    return sess != null &&
        sess['session_active'] == true &&
        (sess['checkout_open'] == true || sess['status'] == 'checkout_open');
  }

  Widget _buildCleanStatusChip(bool isDark) {
    final bool isMarked = _lastMarkedReceipt != null;
    final bool sessionOpen = _isSessionOpen;
    final bool isCheckout = _isCheckoutOpen;

    final color = isMarked
        ? const Color(0xFF10B981)
        : (_isProcessing
            ? Colors.amber
            : (_errorMessage.isNotEmpty
                ? const Color(0xFFEF4444)
                : (isCheckout
                    ? const Color(0xFF0D9488)
                    : (sessionOpen ? const Color(0xFF059669) : const Color(0xFF64748B)))));

    final icon = isMarked
        ? Icons.check_circle_rounded
        : (_isProcessing
            ? Icons.hourglass_top_rounded
            : (_errorMessage.isNotEmpty
                ? Icons.error_outline_rounded
                : (isCheckout
                    ? Icons.exit_to_app_rounded
                    : (sessionOpen ? Icons.face_retouching_natural_rounded : Icons.lock_clock_rounded))));

    final message = _errorMessage.isNotEmpty
        ? _errorMessage
        : (_isProcessing
            ? (isCheckout ? "Verifying check-out biometrics..." : "Verifying biometrics & campus geofence...")
            : (isMarked
                ? (_lastMarkedReceipt?['message'] ?? (isCheckout ? "Check-Out Verified Successfully" : "Attendance Verified Successfully"))
                : (isCheckout
                    ? "Faculty Check-Out Window Open • Align Face to Check Out"
                    : (sessionOpen
                        ? (_statusMessage.isNotEmpty ? _statusMessage : "Faculty Recording Live • Position face inside frame")
                        : "Attendance Recording Inactive • Waiting for Faculty"))));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_isProcessing)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          else
            Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              message,
              style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMarkAttendanceButton(String activeSession, bool isDark) {
    if (!_isSessionOpen) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFCBD5E1)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline_rounded, size: 20, color: isDark ? Colors.white60 : const Color(0xFF64748B)),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                'Waiting for Staff to Start Attendance...',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: isDark ? Colors.white70 : const Color(0xFF475569),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }

    final bool canMark = _isCameraReady && !_isProcessing;
    final bool isCheckout = _isCheckoutOpen;
    final subj = (widget.activeSession?['subject_name'] ?? '').toString();
    final buttonLabel = _isProcessing
        ? (isCheckout ? 'Verifying Check-Out Biometrics...' : 'Verifying Biometrics...')
        : (isCheckout
            ? (subj.isNotEmpty ? 'Scan Face & Check Out ($subj)' : 'Scan Face & Check Out ($activeSession)')
            : (subj.isNotEmpty ? 'Scan Face & Mark Attendance ($subj)' : 'Scan Face & Mark Attendance ($activeSession)'));

    final buttonColor = isCheckout ? const Color(0xFF0D9488) : const Color(0xFF059669);

    return ElevatedButton.icon(
      onPressed: canMark ? _captureAndMark : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: buttonColor,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        elevation: 2,
        shadowColor: buttonColor.withValues(alpha: 0.3),
      ),
      icon: _isProcessing
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : Icon(isCheckout ? Icons.exit_to_app_rounded : Icons.verified_user_rounded, size: 22),
      label: Text(
        buttonLabel,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
      ),
    );
  }

  Widget _buildActiveFacultySessionCard(bool isDark) {
    final bool sessionOpen = _isSessionOpen;
    final String subjName = (widget.activeSession?['subject_name'] ?? 'Class Session').toString();
    final String periods = (widget.activeSession?['period_numbers'] as List<dynamic>?)?.join(', ') ?? '1';
    final String staffName = (widget.activeSession?['staff_name'] ?? 'Faculty').toString();

    if (sessionOpen) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [const Color(0xFF064E3B), const Color(0xFF0F172A)]
                : [const Color(0xFFECFDF5), Colors.white],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF10B981).withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.radio_button_checked_rounded, color: Color(0xFF10B981), size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'RECORDING LIVE',
                          style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Period $periods',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : const Color(0xFF065F46),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subjName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Faculty: $staffName',
                    style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF64748B).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.lock_clock_rounded, color: Color(0xFF64748B), size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Attendance Recording Closed',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  'Faculty has not started attendance recording for your class yet.',
                  style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGeofenceSessionCard(bool isDark, String activeSession, {bool compact = false}) {
    return Container(
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.location_on_rounded, color: Color(0xFF10B981), size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Campus Geofence Radar',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Inside SIET Campus Boundary',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Color(0xFF10B981),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  activeSession,
                  style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceReceiptCard(bool isDark, String studentName, String regNo, String activeSession) {
    final bool isCheckoutReceipt = _lastMarkedReceipt?['is_checkout'] == true ||
        _lastMarkedReceipt?['checkout_time'] != null ||
        (_lastMarkedReceipt?['message']?.toString().toLowerCase().contains('check-out') ?? false);
    final themeColor = isCheckoutReceipt ? const Color(0xFF0D9488) : const Color(0xFF10B981);
    final cardTitle = isCheckoutReceipt ? 'Check-Out Recorded Successfully!' : 'Attendance Recorded Successfully!';
    final timeStr = isCheckoutReceipt
        ? 'Checked out at ${_lastMarkedReceipt!['checkout_time'] ?? _lastMarkedReceipt!['time'] ?? DateFormat('hh:mm a').format(DateTime.now())}'
        : 'Checked in at ${_lastMarkedReceipt!['time'] ?? DateFormat('hh:mm a').format(DateTime.now())}';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: themeColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: themeColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: themeColor,
              shape: BoxShape.circle,
            ),
            child: Icon(isCheckoutReceipt ? Icons.exit_to_app_rounded : Icons.check_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cardTitle,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: themeColor),
                ),
                const SizedBox(height: 3),
                Text(
                  '$studentName ($regNo) • ${_lastMarkedReceipt!['session_display'] ?? activeSession}',
                  style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87),
                ),
                Text(
                  timeStr,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickInfoCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.shield_outlined, color: Color(0xFF2563EB), size: 18),
              SizedBox(width: 8),
              Text(
                'Biometric Attendance Guidelines',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildInfoRow(Icons.face_retouching_natural_rounded, 'Face directly towards the camera in good lighting.', isDark),
          const SizedBox(height: 8),
          _buildInfoRow(Icons.location_on_outlined, 'Ensure you are inside the SIET campus boundary.', isDark),
          const SizedBox(height: 8),
          _buildInfoRow(Icons.verified_outlined, 'Single-tap instant face verification & logging.', isDark),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text, bool isDark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: const Color(0xFF2563EB)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.grey.shade700, height: 1.3),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isOffDay = widget.todaySchedule['is_off_day'] == true ||
        widget.todaySchedule['is_holiday'] == true ||
        widget.todaySchedule['attendance_required'] == false;

    if (isOffDay) {
      return _buildLeaveExemptionScreen(context, isDark);
    }

    final nowHour = DateTime.now().hour;
    final activeSession = nowHour < 13 ? "Forenoon (FN)" : "Afternoon (AN)";
    final studentName = (widget.profile['name'] ?? widget.user['name'] ?? 'Student').toString();
    final regNo = (widget.profile['reg_no'] ?? widget.user['reg_no'] ?? '').toString();
    final isWide = MediaQuery.of(context).size.width >= 900;

    if (isWide) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Column: Hero Viewfinder & Main Controls
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildActiveFacultySessionCard(isDark),
                  const SizedBox(height: 14),
                  _buildCameraViewfinderCard(isDark: isDark, height: 400),
                  const SizedBox(height: 14),
                  _buildCleanStatusChip(isDark),
                  const SizedBox(height: 14),
                  _buildMarkAttendanceButton(activeSession, isDark),
                ],
              ),
            ),
            const SizedBox(width: 24),
            // Right Column: Session Info, Receipt & Guidelines
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildGeofenceSessionCard(isDark, activeSession),
                  const SizedBox(height: 16),
                  if (_lastMarkedReceipt != null) ...[
                    _buildAttendanceReceiptCard(isDark, studentName, regNo, activeSession),
                    const SizedBox(height: 16),
                  ],
                  _buildQuickInfoCard(isDark),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Mobile View (Single Column, Preview-First)
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildActiveFacultySessionCard(isDark),
          const SizedBox(height: 14),
          _buildGeofenceSessionCard(isDark, activeSession, compact: true),
          const SizedBox(height: 14),
          _buildCameraViewfinderCard(isDark: isDark, height: 360),
          const SizedBox(height: 12),
          _buildCleanStatusChip(isDark),
          const SizedBox(height: 14),
          _buildMarkAttendanceButton(activeSession, isDark),
          if (_lastMarkedReceipt != null) ...[
            const SizedBox(height: 14),
            _buildAttendanceReceiptCard(isDark, studentName, regNo, activeSession),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// TAB 2: DEDICATED SEPARATE TAB - FACE REGISTRATION
// ─────────────────────────────────────────────────────────
class _StudentFaceRegistrationTab extends StatefulWidget {
  final String token;
  final Map<String, dynamic> user;
  final Map<String, dynamic> profile;
  final Map<String, dynamic> faceRegStatus;
  final bool isActive;
  final VoidCallback onRefresh;

  const _StudentFaceRegistrationTab({
    required this.token,
    required this.user,
    required this.profile,
    required this.faceRegStatus,
    this.isActive = true,
    required this.onRefresh,
  });

  @override
  State<_StudentFaceRegistrationTab> createState() => _StudentFaceRegistrationTabState();
}

class _StudentFaceRegistrationTabState extends State<_StudentFaceRegistrationTab> with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isCameraReady = false;
  bool _isInitializingCamera = false;
  bool _isPermissionDenied = false;
  bool _isCapturing = false;
  bool _isSubmitting = false;
  int _currentStep = 0; // 0 = Front, 1 = Angle, 2 = Smile
  final List<XFile> _capturedPoses = [];
  String _uploadStatus = "";
  String _uploadError = "";
  String _errorMessage = "";

  final List<String> _stepTitles = [
    "Front Pose (Neutral)",
    "Slight Angle (Tilt Head)",
    "Natural Smile / Expression",
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.isActive) {
      _initCamera();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _disposeCamera();
    } else if (state == AppLifecycleState.resumed) {
      if (widget.isActive && !_isCameraReady && !_isInitializingCamera) {
        _initCamera();
      }
    }
  }

  @override
  void didUpdateWidget(_StudentFaceRegistrationTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        if (!_isCameraReady && !_isInitializingCamera) {
          _initCamera();
        }
      } else {
        _disposeCamera();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeCameraSync();
    super.dispose();
  }

  void _disposeCameraSync() {
    final ctrl = _cameraController;
    _cameraController = null;
    ctrl?.dispose();
    _isCameraReady = false;
    _isInitializingCamera = false;
  }

  Future<void> _disposeCamera() async {
    if (_cameraController != null) {
      try {
        final ctrl = _cameraController;
        _cameraController = null;
        await ctrl?.dispose();
      } catch (e) {
        debugPrint("Face registration camera disposal error: $e");
      }
    }
    if (mounted) {
      setState(() {
        _isCameraReady = false;
        _isInitializingCamera = false;
      });
    }
  }

  Future<void> _initCamera() async {
    if (_isInitializingCamera) return;
    if (!widget.isActive) return;

    setState(() {
      _isInitializingCamera = true;
      _errorMessage = "";
      _isPermissionDenied = false;
    });

    try {
      if (!kIsWeb) {
        var status = await Permission.camera.status;
        if (!status.isGranted) {
          status = await Permission.camera.request();
          if (!status.isGranted) {
            if (mounted) {
              setState(() {
                _isPermissionDenied = true;
                _errorMessage = "Camera permission is required for face registration.";
                _isInitializingCamera = false;
                _isCameraReady = false;
              });
            }
            return;
          }
        }
      }

      try {
        _cameras = await availableCameras().timeout(const Duration(seconds: 4));
      } catch (_) {
        if (cameras.isNotEmpty) {
          _cameras = cameras;
        }
      }

      if (_cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _errorMessage = "No camera found on this device.";
            _isInitializingCamera = false;
            _isCameraReady = false;
          });
        }
        return;
      }

      // Strictly select Front Camera
      final frontCamera = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras.first,
      );

      if (_cameraController != null) {
        final old = _cameraController;
        _cameraController = null;
        await old?.dispose();
      }

      final ctrl = CameraController(
        frontCamera,
        kIsWeb ? ResolutionPreset.medium : ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await ctrl.initialize().timeout(const Duration(seconds: 8));

      if (!mounted || !widget.isActive) {
        await ctrl.dispose();
        return;
      }

      setState(() {
        _cameraController = ctrl;
        _isCameraReady = true;
        _isInitializingCamera = false;
        _isPermissionDenied = false;
        _errorMessage = "";
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCameraReady = false;
          _isInitializingCamera = false;
          _errorMessage = "Camera error: ${ApiResponseUtils.sanitize(e)}";
        });
      }
    }
  }

  Future<void> _captureCurrentPose() async {
    if (_isCapturing || _cameraController == null || !_cameraController!.value.isInitialized) return;

    setState(() {
      _isCapturing = true;
      _errorMessage = "";
    });
    try {
      final XFile? frame = await FaceRecognitionHelper.captureBestFrame(_cameraController!, maxFrames: 2);
      if (frame != null) {
        final targetPose = _currentStep == 0
            ? FaceTargetPose.front
            : (_currentStep == 1 ? FaceTargetPose.left : FaceTargetPose.right);

        // Validate pose with on-device Google ML Kit
        final prefilter = await ClientFacePreFilterService.evaluateImagePath(
          frame.path,
          targetPose: targetPose,
          allowMultipleFaces: false,
        );

        if (!prefilter.isValid) {
          if (mounted) {
            setState(() {
              _errorMessage = prefilter.message ?? "Face alignment issue. Please adjust your pose.";
            });
          }
          return;
        }

        setState(() {
          _capturedPoses.add(frame);
          _errorMessage = "";
          if (_currentStep < 2) {
            _currentStep++;
          }
        });
      }
    } catch (e) {
      debugPrint("Capture error: $e");
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  void _resetPoses() {
    setState(() {
      _capturedPoses.clear();
      _currentStep = 0;
      _uploadStatus = "";
      _uploadError = "";
    });
  }

  Future<void> _submitFaceRegistration({required bool isFirstTime}) async {
    if (_capturedPoses.isEmpty) return;

    setState(() {
      _isSubmitting = true;
      _uploadStatus = isFirstTime 
          ? "Extracting InsightFace embeddings & activating Face ID..."
          : "Updating biometric centroid with advisor approval...";
      _uploadError = "";
    });

    final res = await FaceVerificationService.submitStudentFaceRegistration(
      token: widget.token,
      imageFiles: _capturedPoses,
      requestType: isFirstTime ? 'FIRST_TIME_SELF_ENROLLMENT' : 'REREGISTRATION_UPDATE',
      notes: isFirstTime ? "First-time self-service face biometric registration" : "Re-registration face update with advisor permission",
      onError: (err) {
        if (mounted) {
          setState(() {
            _isSubmitting = false;
            _uploadError = err;
            _uploadStatus = "";
          });
        }
      },
    );

    if (res['success'] == true) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _uploadStatus = isFirstTime
              ? "Face Biometrics enrolled successfully! Face ID is now active."
              : "Face Profile successfully re-registered and locked.";
          _capturedPoses.clear();
          _currentStep = 0;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isFirstTime
                        ? "Face ID activated! You can now mark attendance with your face."
                        : "Face ID profile re-registered and secured.",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        );

        widget.onRefresh();
      }
    } else {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _uploadError = res['error'] ?? "Face registration failed.";
          _uploadStatus = "";
        });
      }
    }
  }

  void _showRequestReregistrationDialog(String advisorName) {
    final notesCtrl = TextEditingController(text: "Appearance changed / Need to re-capture face angles");

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.lock_reset_rounded, color: Color(0xFF2563EB), size: 22),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Request Re-Registration',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your biometric Face ID is currently active and locked. To re-register your face, your Class Advisor ($advisorName) must grant permission.',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            const Text(
              'Reason for re-registration:',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: notesCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'e.g. Changed spectacles/hairstyle, camera quality improved...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final messenger = ScaffoldMessenger.of(context);
              final res = await FaceVerificationService.requestFaceReregistrationPermission(
                token: widget.token,
                reason: notesCtrl.text.trim(),
              );
              if (res['success'] == true) {
                messenger.showSnackBar(
                  SnackBar(
                    backgroundColor: const Color(0xFF10B981),
                    content: Text(res['message'] ?? 'Permission request submitted to $advisorName.'),
                  ),
                );
                widget.onRefresh();
              } else {
                messenger.showSnackBar(
                  SnackBar(
                    backgroundColor: const Color(0xFFEF4444),
                    content: Text(res['message'] ?? 'Failed to send request.'),
                  ),
                );
              }
            },
            icon: const Icon(Icons.send_rounded, size: 16),
            label: const Text('Submit Request'),
          ),
        ],
      ),
    );
  }

  void _showRequestAdvisorDialog(String advisorName) {
    final notesCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Request In-Person Session'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'If you face camera/device issues, you can request an in-person face enrollment session with your Class Advisor ($advisorName).',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: notesCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Notes / Preferred Time',
                hintText: 'e.g. Can visit staff room during break hours',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final messenger = ScaffoldMessenger.of(context);
              final res = await FaceVerificationService.requestAdvisorEnrollmentSession(
                token: widget.token,
                notes: notesCtrl.text.trim(),
              );
              if (res['success'] == true) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('Session request sent to Class Advisor!')),
                );
                widget.onRefresh();
              }
            },
            child: const Text('Send Request'),
          ),
        ],
      ),
    );
  }

  Widget _buildSafeCameraPreview(CameraController ctrl) {
    final size = ctrl.value.previewSize;
    if (size == null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: CameraPreview(ctrl),
      );
    }
    final double previewW = kIsWeb ? size.width : (size.height < size.width ? size.height : size.width);
    final double previewH = kIsWeb ? size.height : (size.height < size.width ? size.width : size.height);

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: previewW,
            height: previewH,
            child: CameraPreview(ctrl),
          ),
        ),
      ),
    );
  }

  Widget _buildStepProgressBar(bool isDark) {
    return Row(
      children: List.generate(3, (idx) {
        final isDone = idx < _capturedPoses.length;
        final isCurrent = idx == _currentStep && !isDone;
        final color = isDone
            ? const Color(0xFF10B981)
            : (isCurrent ? const Color(0xFF2563EB) : (isDark ? Colors.white12 : Colors.grey.shade200));
        final textColor = isDone || isCurrent ? Colors.white : Colors.grey;

        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: idx < 2 ? 8 : 0),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isDone ? Icons.check_circle_rounded : (isCurrent ? Icons.camera_alt_rounded : Icons.circle_outlined),
                  color: textColor,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Text(
                  'Angle ${idx + 1}',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildStepGuidanceBanner(bool isDark) {
    final List<String> instructions = [
      "Angle 1 of 3: Look directly at the camera with a neutral expression",
      "Angle 2 of 3: Tilt your head slightly to capture 3D contour",
      "Angle 3 of 3: Smile naturally or show normal facial expression",
    ];
    final text = _capturedPoses.length < 3
        ? instructions[_currentStep]
        : "All 3 Angles Captured! Tap 'Complete Registration' below.";

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: (_capturedPoses.length < 3 ? const Color(0xFF2563EB) : const Color(0xFF10B981)).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: (_capturedPoses.length < 3 ? const Color(0xFF2563EB) : const Color(0xFF10B981)).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _capturedPoses.length < 3 ? Icons.tips_and_updates_rounded : Icons.check_circle_rounded,
            color: _capturedPoses.length < 3 ? const Color(0xFF2563EB) : const Color(0xFF10B981),
            size: 18,
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                color: _capturedPoses.length < 3 ? const Color(0xFF2563EB) : const Color(0xFF10B981),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegistrationCameraCard({required bool isDark, required double height}) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.black87,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: _errorMessage.isNotEmpty
              ? const Color(0xFFEF4444)
              : const Color(0xFF2563EB).withValues(alpha: 0.5),
          width: 2.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            if (_isCameraReady && _cameraController != null && _cameraController!.value.isInitialized) ...[
              _buildSafeCameraPreview(_cameraController!),
              CustomPaint(
                painter: _BiometricViewfinderPainter(
                  isProcessing: _isCapturing || _isSubmitting,
                  isSuccess: _capturedPoses.length == 3,
                ),
              ),
            ] else if (_isPermissionDenied)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.videocam_off_rounded, color: Colors.redAccent, size: 36),
                      const SizedBox(height: 10),
                      const Text(
                        "Camera Permission Required",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Enable camera to capture biometric face angles.",
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () => _initCamera(),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            icon: const Icon(Icons.refresh_rounded, size: 14),
                            label: const Text("Grant Permission", style: TextStyle(fontSize: 12)),
                          ),
                          if (!kIsWeb) ...[
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: () => openAppSettings(),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white38),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                              icon: const Icon(Icons.settings_rounded, size: 14),
                              label: const Text("Settings", style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              )
            else if (_errorMessage.isNotEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 36),
                      const SizedBox(height: 10),
                      const Text(
                        "Camera Unavailable",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _errorMessage,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: () => _initCamera(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        icon: const Icon(Icons.refresh_rounded, size: 14),
                        label: const Text("Retry Camera", style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ),
              )
            else
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Color(0xFF2563EB)),
                    const SizedBox(height: 12),
                    Text(
                      "Starting camera...",
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12),
                    ),
                  ],
                ),
              ),

            // Top-right controls: Reconnect camera
            if (_isCameraReady)
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 16),
                    tooltip: "Reconnect Camera",
                    onPressed: () => _initCamera(),
                  ),
                ),
              ),

            // Capturing Spinner
            if (_isCapturing)
              Container(
                color: Colors.black.withValues(alpha: 0.35),
                child: const Center(
                  child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF2563EB)),
                ),
              ),

            // Submitting Spinner
            if (_isSubmitting)
              Container(
                color: Colors.black.withValues(alpha: 0.45),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF10B981)),
                      SizedBox(height: 12),
                      Text(
                        "Processing Biometrics...",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCapturedPosesRow(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Captured Angles (${_capturedPoses.length}/3)',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              if (_capturedPoses.isNotEmpty)
                TextButton.icon(
                  onPressed: _resetPoses,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.restart_alt_rounded, size: 14, color: Color(0xFFEF4444)),
                  label: const Text('Retake', style: TextStyle(color: Color(0xFFEF4444), fontSize: 12, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(3, (idx) {
              final XFile? file = idx < _capturedPoses.length ? _capturedPoses[idx] : null;
              return _BiometricThumbnail(
                file: file,
                stepIndex: idx,
                title: _stepTitles[idx],
                isCurrent: idx == _currentStep && file == null,
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildCaptureActionButton(bool isFirstTime) {
    if (_capturedPoses.length < 3) {
      return ElevatedButton.icon(
        onPressed: (_isCameraReady && !_isCapturing && !_isSubmitting) ? _captureCurrentPose : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF2563EB),
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 2,
        ),
        icon: _isCapturing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.camera_alt_rounded, size: 20),
        label: Text(
          'Capture Angle ${_capturedPoses.length + 1} (${_stepTitles[_currentStep]})',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      );
    } else {
      return ElevatedButton.icon(
        onPressed: !_isSubmitting ? () => _submitFaceRegistration(isFirstTime: isFirstTime) : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF10B981),
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 3,
          shadowColor: const Color(0xFF10B981).withValues(alpha: 0.3),
        ),
        icon: _isSubmitting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.check_circle_rounded, size: 22),
        label: Text(
          isFirstTime ? '⚡ Complete Registration & Activate Face ID' : 'Update Biometrics & Relock Profile',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
      );
    }
  }

  Widget _buildBiometricProfileCard(
    bool isDark,
    bool isEnrolled,
    bool canReregister,
    dynamic sampleCount,
    dynamic qualityScore,
    dynamic enrolledDate,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: (isEnrolled ? const Color(0xFF10B981) : const Color(0xFF2563EB)).withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: (isEnrolled ? const Color(0xFF10B981) : const Color(0xFF2563EB)).withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: (isEnrolled ? const Color(0xFF10B981) : const Color(0xFF2563EB)).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        isEnrolled ? Icons.face_retouching_natural_rounded : Icons.face_unlock_rounded,
                        color: isEnrolled ? const Color(0xFF10B981) : const Color(0xFF2563EB),
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEnrolled ? 'Biometric Face ID Active' : 'Face ID Setup Required',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            isEnrolled ? (canReregister ? 'Unlocked for Update' : 'Locked & Protected') : 'First-Time Instant Setup',
                            style: TextStyle(
                              fontSize: 11,
                              color: isEnrolled ? (canReregister ? const Color(0xFF10B981) : Colors.grey.shade500) : const Color(0xFF2563EB),
                              fontWeight: isEnrolled && canReregister ? FontWeight.bold : FontWeight.normal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (isEnrolled ? const Color(0xFF10B981) : const Color(0xFF2563EB)).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isEnrolled ? 'Enrolled' : 'Ready',
                  style: TextStyle(
                    color: isEnrolled ? const Color(0xFF10B981) : const Color(0xFF2563EB),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatCol('Samples', '$sampleCount / 3', const Color(0xFF2563EB)),
              _buildStatCol('Match Quality', isEnrolled ? '$qualityScore%' : 'Pending', const Color(0xFF10B981)),
              _buildStatCol('Enrolled On', enrolledDate.toString(), Colors.grey),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildClassAdvisorCard(bool isDark, String advisorName, String advisorReg) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: const Color(0xFF2563EB).withValues(alpha: 0.15),
            child: const Icon(Icons.person_pin_rounded, color: Color(0xFF2563EB), size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  advisorName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Class Advisor • ${advisorReg.isNotEmpty ? advisorReg : 'Department Staff'}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              side: const BorderSide(color: Color(0xFF2563EB)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => _showRequestAdvisorDialog(advisorName),
            child: const Text('Help', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildAdvisorLockCard(bool isDark, String advisorName, dynamic pendingReq) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.security_rounded, color: Colors.amber.shade800, size: 22),
              const SizedBox(width: 10),
              Text(
                'Biometric Lock Active',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: isDark ? Colors.amber.shade300 : Colors.amber.shade900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Your face profile is secured. To re-register or update face angles, request permission from your Class Advisor.',
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: isDark ? Colors.grey.shade300 : Colors.brown.shade800,
            ),
          ),
          const SizedBox(height: 14),
          if (pendingReq != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Request #${pendingReq['id']} pending review with $advisorName.',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange),
                    ),
                  ),
                ],
              ),
            )
          else
            ElevatedButton.icon(
              onPressed: () => _showRequestReregistrationDialog(advisorName),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 46),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.key_rounded, size: 16),
              label: const Text(
                'Request Advisor Permission to Re-register',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRegistrationGuidelinesCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.checklist_rounded, color: Color(0xFF2563EB), size: 18),
              SizedBox(width: 8),
              Text(
                'Enrollment Tips',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildInfoRow(Icons.camera_front_rounded, 'Angle 1: Keep head straight with neutral expression.', isDark),
          const SizedBox(height: 8),
          _buildInfoRow(Icons.rotate_90_degrees_ccw_rounded, 'Angle 2: Slightly tilt head to capture 3D depth.', isDark),
          const SizedBox(height: 8),
          _buildInfoRow(Icons.sentiment_satisfied_rounded, 'Angle 3: Smile or give normal daily expression.', isDark),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text, bool isDark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: const Color(0xFF2563EB)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.grey.shade700, height: 1.3),
          ),
        ),
      ],
    );
  }

  Widget _buildRequestsHistoryTimeline(bool isDark, List<dynamic> requests) {
    if (requests.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Request History',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 10),
        ...requests.map((req) {
          final status = (req['status'] ?? 'PENDING').toString();
          final isApp = status == 'APPROVED' || status == 'AUTO_APPROVED' || status == 'COMPLETED';
          final isRej = status == 'REJECTED';

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Icon(
                  isApp ? Icons.check_circle_rounded : (isRej ? Icons.cancel_rounded : Icons.pending_rounded),
                  color: isApp ? const Color(0xFF10B981) : (isRej ? const Color(0xFFEF4444) : Colors.orange),
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${req['request_type']} • ${req['sample_count']} Samples',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      Text(
                        'Submitted: ${req['created_at']}',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                      ),
                      if ((req['advisor_feedback'] ?? '').toString().isNotEmpty)
                        Text(
                          'Note: ${req['advisor_feedback']}',
                          style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (isApp ? const Color(0xFF10B981) : (isRej ? const Color(0xFFEF4444) : Colors.orange))
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isApp ? const Color(0xFF10B981) : (isRej ? const Color(0xFFEF4444) : Colors.orange),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final faceInfo = widget.faceRegStatus['face_registration'] ?? {};
    final isEnrolled = faceInfo['is_enrolled'] == true || widget.profile['face_prototype_ready'] == true;
    final canReregister = faceInfo['can_reregister'] == true || (widget.faceRegStatus['student']?['can_reregister'] == true);
    final isFirstTime = !isEnrolled;

    final sampleCount = faceInfo['sample_count'] ?? (isEnrolled ? 3 : 0);
    final qualityScore = faceInfo['quality_score'] ?? 98.4;
    final enrolledDate = faceInfo['enrolled_date'] ?? 'Active';
    final advisor = widget.faceRegStatus['assigned_advisor'] ?? {};
    final advisorName = advisor['name'] ?? widget.profile['mentor_name'] ?? 'Assigned Class Advisor';
    final advisorReg = advisor['reg_no'] ?? widget.profile['mentor_staff_reg_no'] ?? '';
    final requests = (widget.faceRegStatus['requests'] as List?) ?? [];
    final pendingReq = widget.faceRegStatus['pending_request'];

    final bool isCameraCaptureAllowed = isFirstTime || canReregister;
    final isWide = MediaQuery.of(context).size.width >= 900;

    if (isWide) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Column: Camera / Wizard (or Profile Status)
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isCameraCaptureAllowed) ...[
                    _buildStepProgressBar(isDark),
                    const SizedBox(height: 12),
                    _buildStepGuidanceBanner(isDark),
                    const SizedBox(height: 12),
                    _buildRegistrationCameraCard(isDark: isDark, height: 380),
                    const SizedBox(height: 12),
                    _buildCapturedPosesRow(isDark),
                    const SizedBox(height: 14),
                    _buildCaptureActionButton(isFirstTime),
                    if (_uploadStatus.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _uploadStatus,
                          style: const TextStyle(color: Color(0xFF10B981), fontSize: 12, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    if (_uploadError.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _uploadError,
                          style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ] else ...[
                    _buildBiometricProfileCard(isDark, isEnrolled, canReregister, sampleCount, qualityScore, enrolledDate),
                    const SizedBox(height: 16),
                    _buildAdvisorLockCard(isDark, advisorName, pendingReq),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 24),
            // Right Column: Guidelines, Advisor & Request History
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isCameraCaptureAllowed) ...[
                    _buildBiometricProfileCard(isDark, isEnrolled, canReregister, sampleCount, qualityScore, enrolledDate),
                    const SizedBox(height: 16),
                    _buildRegistrationGuidelinesCard(isDark),
                    const SizedBox(height: 16),
                  ],
                  _buildClassAdvisorCard(isDark, advisorName, advisorReg),
                  const SizedBox(height: 16),
                  _buildRequestsHistoryTimeline(isDark, requests),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Mobile View (Single Column, Preview-First)
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isCameraCaptureAllowed) ...[
            _buildStepProgressBar(isDark),
            const SizedBox(height: 10),
            _buildStepGuidanceBanner(isDark),
            const SizedBox(height: 12),
            _buildRegistrationCameraCard(isDark: isDark, height: 340),
            const SizedBox(height: 12),
            _buildCapturedPosesRow(isDark),
            const SizedBox(height: 14),
            _buildCaptureActionButton(isFirstTime),
            if (_uploadStatus.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _uploadStatus,
                  style: const TextStyle(color: Color(0xFF10B981), fontSize: 12, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            if (_uploadError.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _uploadError,
                  style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 16),
          ],
          _buildBiometricProfileCard(isDark, isEnrolled, canReregister, sampleCount, qualityScore, enrolledDate),
          const SizedBox(height: 14),
          _buildClassAdvisorCard(isDark, advisorName, advisorReg),
          if (isEnrolled && !canReregister) ...[
            const SizedBox(height: 14),
            _buildAdvisorLockCard(isDark, advisorName, pendingReq),
          ],
          if (requests.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildRequestsHistoryTimeline(isDark, requests),
          ],
        ],
      ),
    );
  }

  Widget _buildStatCol(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────
// REUSABLE BIOMETRIC PREVIEW & THUMBNAIL HELPERS
// ─────────────────────────────────────────────────────────
class _BiometricViewfinderPainter extends CustomPainter {
  final bool isProcessing;
  final bool isSuccess;

  const _BiometricViewfinderPainter({
    this.isProcessing = false,
    this.isSuccess = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double cornerLen = size.width * 0.08 < 24.0 ? 24.0 : size.width * 0.08;
    const double cornerRadius = 10.0;
    final Color color = isSuccess
        ? const Color(0xFF10B981)
        : (isProcessing ? Colors.amber : Colors.white.withValues(alpha: 0.85));

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final double pad = 16.0;
    final rect = Rect.fromLTWH(pad, pad, size.width - 2 * pad, size.height - 2 * pad);

    // Top-Left corner
    final pathTL = Path()
      ..moveTo(rect.left, rect.top + cornerLen)
      ..lineTo(rect.left, rect.top + cornerRadius)
      ..arcToPoint(Offset(rect.left + cornerRadius, rect.top), radius: const Radius.circular(cornerRadius))
      ..lineTo(rect.left + cornerLen, rect.top);
    canvas.drawPath(pathTL, paint);

    // Top-Right corner
    final pathTR = Path()
      ..moveTo(rect.right - cornerLen, rect.top)
      ..lineTo(rect.right - cornerRadius, rect.top)
      ..arcToPoint(Offset(rect.right, rect.top + cornerRadius), radius: const Radius.circular(cornerRadius))
      ..lineTo(rect.right, rect.top + cornerLen);
    canvas.drawPath(pathTR, paint);

    // Bottom-Left corner
    final pathBL = Path()
      ..moveTo(rect.left, rect.bottom - cornerLen)
      ..lineTo(rect.left, rect.bottom - cornerRadius)
      ..arcToPoint(Offset(rect.left + cornerRadius, rect.bottom), radius: const Radius.circular(cornerRadius))
      ..lineTo(rect.left + cornerLen, rect.bottom);
    canvas.drawPath(pathBL, paint);

    // Bottom-Right corner
    final pathBR = Path()
      ..moveTo(rect.right - cornerLen, rect.bottom)
      ..lineTo(rect.right - cornerRadius, rect.bottom)
      ..arcToPoint(Offset(rect.right, rect.bottom - cornerRadius), radius: const Radius.circular(cornerRadius))
      ..lineTo(rect.right, rect.bottom - cornerLen);
    canvas.drawPath(pathBR, paint);

    // Subtle center oval guide (clean, thin, unobtrusive, clear face area)
    final ovalWidth = size.width * 0.55;
    final ovalHeight = ovalWidth * 1.3;
    final ovalRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: ovalWidth,
      height: ovalHeight,
    );

    final ovalPaint = Paint()
      ..color = (isSuccess ? const Color(0xFF10B981) : (isProcessing ? Colors.amber : Colors.white)).withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawOval(ovalRect, ovalPaint);
  }

  @override
  bool shouldRepaint(covariant _BiometricViewfinderPainter oldDelegate) {
    return oldDelegate.isProcessing != isProcessing || oldDelegate.isSuccess != isSuccess;
  }
}

class _BiometricThumbnail extends StatelessWidget {
  final XFile? file;
  final int stepIndex;
  final String title;
  final bool isCurrent;

  const _BiometricThumbnail({
    required this.file,
    required this.stepIndex,
    required this.title,
    this.isCurrent = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = file != null;
    return Column(
      children: [
        Container(
          width: 72,
          height: 84,
          decoration: BoxDecoration(
            color: hasImage
                ? Colors.black
                : (isCurrent ? const Color(0xFF2563EB).withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1)),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hasImage
                  ? const Color(0xFF10B981)
                  : (isCurrent ? const Color(0xFF2563EB) : Colors.grey.withValues(alpha: 0.3)),
              width: isCurrent || hasImage ? 2 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: hasImage
                ? FutureBuilder<Uint8List>(
                    future: file!.readAsBytes(),
                    builder: (context, snapshot) {
                      if (snapshot.hasData) {
                        return Image.memory(snapshot.data!, fit: BoxFit.cover);
                      }
                      return const Center(
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF10B981)),
                        ),
                      );
                    },
                  )
                : Center(
                    child: Icon(
                      isCurrent ? Icons.camera_alt_rounded : Icons.person_outline_rounded,
                      color: isCurrent ? const Color(0xFF2563EB) : Colors.grey.shade400,
                      size: 24,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasImage)
              const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 12)
            else if (isCurrent)
              const Icon(Icons.radio_button_checked, color: Color(0xFF2563EB), size: 12)
            else
              Icon(Icons.radio_button_unchecked, color: Colors.grey.shade400, size: 12),
            const SizedBox(width: 4),
            Text(
              'Angle ${stepIndex + 1}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: hasImage || isCurrent ? FontWeight.bold : FontWeight.normal,
                color: hasImage ? const Color(0xFF10B981) : (isCurrent ? const Color(0xFF2563EB) : Colors.grey),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────
// TAB 3: LIVE TIMETABLE & SCHEDULE
// ─────────────────────────────────────────────────────────
// TAB 3: LIVE DATE-AWARE TIMETABLE & SCHEDULE
// ─────────────────────────────────────────────────────────
class _StudentTimetableTab extends StatefulWidget {
  final String token;
  final Map<String, dynamic> user;
  final Map<String, dynamic> profile;
  final Map<String, dynamic> todaySchedule;
  final VoidCallback onRefresh;

  const _StudentTimetableTab({
    required this.token,
    required this.user,
    required this.profile,
    required this.todaySchedule,
    required this.onRefresh,
  });

  @override
  State<_StudentTimetableTab> createState() => _StudentTimetableTabState();
}

class _StudentTimetableTabState extends State<_StudentTimetableTab> {
  @override
  Widget build(BuildContext context) {
    final dept = (widget.profile['dept'] ?? widget.user['dept'] ?? '').toString();
    final batch = (widget.profile['batch'] ?? widget.user['batch'] ?? '').toString();
    final semVal = widget.profile['semester'] ?? widget.user['semester'];
    final sem = semVal is num ? semVal.toInt() : int.tryParse(semVal?.toString() ?? '');
    final section = (widget.profile['section'] ?? widget.user['section'] ?? '').toString();

    return RefreshIndicator(
      onRefresh: () async {
        widget.onRefresh();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: DateTimetableView(
          token: widget.token,
          dept: dept.isNotEmpty ? dept : null,
          batch: batch.isNotEmpty ? batch : null,
          semester: sem,
          section: section.isNotEmpty ? section : null,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// TAB 4: COMPLETE FILTERABLE ATTENDANCE LOGS
// ─────────────────────────────────────────────────────────
class _StudentAttendanceLogsTab extends StatefulWidget {
  final String token;
  final Map<String, dynamic> user;

  const _StudentAttendanceLogsTab({required this.token, required this.user});

  @override
  State<_StudentAttendanceLogsTab> createState() => _StudentAttendanceLogsTabState();
}

class _StudentAttendanceLogsTabState extends State<_StudentAttendanceLogsTab> {
  List<dynamic> _logs = [];
  bool _isLoading = true;
  String _selectedStatus = "ALL";
  String _selectedSession = "ALL";

  @override
  void initState() {
    super.initState();
    _fetchLogs();
  }

  Future<void> _fetchLogs() async {
    setState(() => _isLoading = true);
    try {
      var urlStr = '${CollegeIPConfig.defaultURL}/student/attendance/history?';
      if (_selectedStatus != "ALL") urlStr += 'status=$_selectedStatus&';
      if (_selectedSession != "ALL") urlStr += 'session=$_selectedSession&';

      final res = await http.get(
        Uri.parse(urlStr),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body);
        _logs = d['logs'] ?? [];
      }
    } catch (e) {
      debugPrint("Error fetching logs: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _selectedStatus,
                    decoration: const InputDecoration(
                      labelText: 'Status Filter',
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'ALL', child: Text('All Statuses', overflow: TextOverflow.ellipsis, maxLines: 1)),
                      DropdownMenuItem(value: 'Present', child: Text('Present', overflow: TextOverflow.ellipsis, maxLines: 1)),
                      DropdownMenuItem(value: 'OD', child: Text('On-Duty (OD)', overflow: TextOverflow.ellipsis, maxLines: 1)),
                      DropdownMenuItem(value: 'Medical', child: Text('Medical Leave', overflow: TextOverflow.ellipsis, maxLines: 1)),
                      DropdownMenuItem(value: 'Leave', child: Text('Casual / Emergency Leave', overflow: TextOverflow.ellipsis, maxLines: 1)),
                      DropdownMenuItem(value: 'Holiday', child: Text('College Holiday', overflow: TextOverflow.ellipsis, maxLines: 1)),
                      DropdownMenuItem(value: 'Absent', child: Text('Absent', overflow: TextOverflow.ellipsis, maxLines: 1)),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _selectedStatus = v);
                        _fetchLogs();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _selectedSession,
                    decoration: const InputDecoration(
                      labelText: 'Session / Period',
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'ALL', child: Text('All Sessions & Periods', overflow: TextOverflow.ellipsis, maxLines: 1)),
                      DropdownMenuItem(value: 'FN', child: Text('Forenoon (FN)', overflow: TextOverflow.ellipsis, maxLines: 1)),
                      DropdownMenuItem(value: 'AN', child: Text('Afternoon (AN)', overflow: TextOverflow.ellipsis, maxLines: 1)),
                      DropdownMenuItem(value: '1', child: Text('Period 1', overflow: TextOverflow.ellipsis, maxLines: 1)),
                      DropdownMenuItem(value: '2', child: Text('Period 2', overflow: TextOverflow.ellipsis, maxLines: 1)),
                      DropdownMenuItem(value: '3', child: Text('Period 3', overflow: TextOverflow.ellipsis, maxLines: 1)),
                      DropdownMenuItem(value: '4', child: Text('Period 4', overflow: TextOverflow.ellipsis, maxLines: 1)),
                      DropdownMenuItem(value: '5', child: Text('Period 5', overflow: TextOverflow.ellipsis, maxLines: 1)),
                      DropdownMenuItem(value: '6', child: Text('Period 6', overflow: TextOverflow.ellipsis, maxLines: 1)),
                      DropdownMenuItem(value: '7', child: Text('Period 7', overflow: TextOverflow.ellipsis, maxLines: 1)),
                      DropdownMenuItem(value: '8', child: Text('Period 8', overflow: TextOverflow.ellipsis, maxLines: 1)),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _selectedSession = v);
                        _fetchLogs();
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _logs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.history_toggle_off_rounded, size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            const Text(
                              'No Attendance Records Found',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(20),
                        itemCount: _logs.length,
                        itemBuilder: (ctx, i) {
                          final l = _logs[i];
                          final status = (l['status'] ?? 'Present').toString();
                          final stLower = status.toLowerCase();
                          final proofUrl = l['document_proof_url']?.toString();
                          final reason = l['reason']?.toString();

                          Color statusColor;
                          IconData statusIcon;

                          if (stLower.contains('od') || stLower.contains('duty')) {
                            statusColor = const Color(0xFF2563EB);
                            statusIcon = Icons.verified_user_rounded;
                          } else if (stLower.contains('medical')) {
                            statusColor = const Color(0xFF0D9488);
                            statusIcon = Icons.medical_services_rounded;
                          } else if (stLower.contains('leave') || stLower.contains('casual')) {
                            statusColor = const Color(0xFF8B5CF6);
                            statusIcon = Icons.beach_access_rounded;
                          } else if (stLower.contains('holiday')) {
                            statusColor = const Color(0xFF64748B);
                            statusIcon = Icons.celebration_rounded;
                          } else if (stLower.contains('present')) {
                            statusColor = const Color(0xFF10B981);
                            statusIcon = Icons.check_circle_rounded;
                          } else {
                            statusColor = const Color(0xFFEF4444);
                            statusIcon = Icons.cancel_rounded;
                          }

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1E293B) : Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: statusColor.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Icon(
                                        statusIcon,
                                        color: statusColor,
                                        size: 24,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${l['date']} • ${l['session'] ?? 'FN'}${l['period_number'] != null ? ' (P${l['period_number']})' : ''}',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'In: ${l['in_time'] ?? l['marked_time'] ?? '—'}  •  Out: ${l['out_time'] ?? l['checkout_time'] ?? '—'}',
                                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : Colors.grey.shade700),
                                          ),
                                          if (l['subject_code'] != null && l['subject_code'] != '-' && l['subject_code'].toString().isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 2),
                                              child: Text(
                                                'Subject: ${l['subject_code']}',
                                                style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.grey.shade500),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: statusColor.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        status,
                                        style: TextStyle(
                                          color: statusColor,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (reason != null && reason.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Padding(
                                    padding: const EdgeInsets.only(left: 48),
                                    child: Text(
                                      'Reason: $reason',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontStyle: FontStyle.italic,
                                        color: isDark ? Colors.white60 : Colors.grey.shade600,
                                      ),
                                    ),
                                  ),
                                ],
                                if (proofUrl != null && proofUrl.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Padding(
                                    padding: const EdgeInsets.only(left: 48),
                                    child: Row(
                                      children: [
                                        Icon(Icons.attachment_rounded, size: 14, color: statusColor),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Proof Document Verified',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: statusColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// TAB 5: LEAVE & ON-DUTY (OD) REQUESTS
// ─────────────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────
// 📚 TAB 6: MODERN STUDENT LEAVE & ON-DUTY (OD) HUB
// ─────────────────────────────────────────────────────────
class _StudentLeaveODTab extends StatefulWidget {
  final String token;
  final Map<String, dynamic> user;

  const _StudentLeaveODTab({required this.token, required this.user});

  @override
  State<_StudentLeaveODTab> createState() => _StudentLeaveODTabState();
}

class _StudentLeaveODTabState extends State<_StudentLeaveODTab> {
  static const Color primaryBlue = Color(0xFF2563EB);
  static const Color secondaryIndigo = Color(0xFF4F46E5);
  static const Color emeraldGreen = Color(0xFF10B981);
  static const Color amberWarning = Color(0xFFF59E0B);
  static const Color roseDanger = Color(0xFFEF4444);
  static const Color violetAccent = Color(0xFF8B5CF6);

  List<dynamic> _requests = [];
  bool _isLoading = true;
  int _currentSubTab = 0; // 0 = Active Applications, 1 = History & Records
  String _selectedFilter = 'ALL';

  @override
  void initState() {
    super.initState();
    _fetchRequests();
  }

  Future<void> _showTimelineDialog(int requestId, String reqType) async {
    showDialog(
      context: context,
      builder: (ctx) => _StudentLeaveODTimelineDialog(
        token: widget.token,
        requestId: requestId,
        requestType: reqType,
      ),
    );
  }

  Future<void> _fetchRequests() async {
    setState(() => _isLoading = true);
    try {
      final res = await http.get(
        Uri.parse('${CollegeIPConfig.defaultURL}/student/leave-od/my-requests'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body);
        _requests = d['requests'] ?? [];
      }
    } catch (e) {
      debugPrint("Error fetching requests: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showApplyDialog() {
    final reasonCtrl = TextEditingController();
    final docUrlCtrl = TextEditingController();
    DateTime startDate = DateTime.now();
    DateTime endDate = DateTime.now();
    String reqType = "ON_DUTY";
    String category = "Symposium / Hackathon";
    String sessionHalf = "FULL_DAY";
    String? reasonError;
    bool isSubmitting = false;

    final List<String> odCategories = [
      "Symposium / Hackathon",
      "Paper Presentation / Conference",
      "Placement / Internship Drive",
      "Sports / Athletic Meet",
      "Culturals & Competitions",
      "Industrial Visit / Project",
      "Other Official Work",
    ];

    final List<String> leaveCategories = [
      "Medical / Hospitalization",
      "Casual / Family Function",
      "Sick Leave",
      "Emergency Leave",
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final categories = reqType == 'ON_DUTY' ? odCategories : leaveCategories;
          if (!categories.contains(category)) {
            category = categories.first;
          }

          final totalDays = endDate.difference(startDate).inDays + 1;
          final dateDisplay = startDate == endDate
              ? '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}'
              : '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')} → ${endDate.year}-${endDate.month.toString().padLeft(2, '0')}-${endDate.day.toString().padLeft(2, '0')}';

          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: primaryBlue.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.edit_calendar_rounded, color: primaryBlue, size: 22),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Apply Leave / On-Duty',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              Text(
                                'Submit for Advisor & HOD Endorsement',
                                style: TextStyle(fontSize: 11.5, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.pop(context),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'Close',
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Application Type
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: reqType,
                      decoration: InputDecoration(
                        labelText: 'Application Type',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'ON_DUTY',
                          child: Text('On-Duty (OD - Event / Symposium)', overflow: TextOverflow.ellipsis, maxLines: 1),
                        ),
                        DropdownMenuItem(
                          value: 'MEDICAL_LEAVE',
                          child: Text('Medical Leave', overflow: TextOverflow.ellipsis, maxLines: 1),
                        ),
                        DropdownMenuItem(
                          value: 'CASUAL_LEAVE',
                          child: Text('Casual Leave', overflow: TextOverflow.ellipsis, maxLines: 1),
                        ),
                        DropdownMenuItem(
                          value: 'EMERGENCY_LEAVE',
                          child: Text('Emergency Leave', overflow: TextOverflow.ellipsis, maxLines: 1),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setDialogState(() {
                            reqType = v;
                            category = (reqType == 'ON_DUTY' ? odCategories : leaveCategories).first;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),

                    // Category
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: category,
                      decoration: InputDecoration(
                        labelText: 'Category / Purpose Group',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: categories
                          .map((c) => DropdownMenuItem(
                                value: c,
                                child: Text(c, overflow: TextOverflow.ellipsis, maxLines: 1),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setDialogState(() => category = v);
                      },
                    ),
                    const SizedBox(height: 12),

                    // Date Selection Card
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFF1E293B)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white12
                              : Colors.grey.shade300,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.date_range_rounded, color: primaryBlue, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  dateDisplay,
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                                Text(
                                  '$totalDays ${totalDays == 1 ? 'Day' : 'Days'} Duration',
                                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: primaryBlue.withValues(alpha: 0.15),
                              foregroundColor: primaryBlue,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              elevation: 0,
                            ),
                            onPressed: () async {
                              final picked = await showDateRangePicker(
                                context: context,
                                firstDate: DateTime.now().subtract(const Duration(days: 14)),
                                lastDate: DateTime.now().add(const Duration(days: 90)),
                                initialDateRange: DateTimeRange(start: startDate, end: endDate),
                              );
                              if (picked != null) {
                                setDialogState(() {
                                  startDate = picked.start;
                                  endDate = picked.end;
                                });
                              }
                            },
                            child: const Text('Change Date', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Session Half
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: sessionHalf,
                      decoration: InputDecoration(
                        labelText: 'Session Half',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'FULL_DAY', child: Text('Full Day', overflow: TextOverflow.ellipsis, maxLines: 1)),
                        DropdownMenuItem(value: 'FN', child: Text('Forenoon (FN Half)', overflow: TextOverflow.ellipsis, maxLines: 1)),
                        DropdownMenuItem(value: 'AN', child: Text('Afternoon (AN Half)', overflow: TextOverflow.ellipsis, maxLines: 1)),
                      ],
                      onChanged: (v) {
                        if (v != null) setDialogState(() => sessionHalf = v);
                      },
                    ),
                    const SizedBox(height: 12),

                    // Reason Field
                    TextField(
                      controller: reasonCtrl,
                      maxLines: 3,
                      minLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Reason & Justification *',
                        hintText: 'e.g. Presenting paper at conference, medical fever...',
                        hintStyle: const TextStyle(fontSize: 12, color: Colors.grey),
                        errorText: reasonError,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onChanged: (_) {
                        if (reasonError != null) setDialogState(() => reasonError = null);
                      },
                    ),
                    const SizedBox(height: 12),

                    // Proof URL Field
                    TextField(
                      controller: docUrlCtrl,
                      decoration: InputDecoration(
                        labelText: 'Supporting Document URL (Optional)',
                        hintText: 'https://drive.google.com/...',
                        hintStyle: const TextStyle(fontSize: 12, color: Colors.grey),
                        prefixIcon: const Icon(Icons.link_rounded, size: 18),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Action Buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: isSubmitting ? null : () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 10),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: primaryBlue,
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: isSubmitting
                              ? null
                              : () async {
                                  final reason = reasonCtrl.text.trim();
                                  if (reason.isEmpty) {
                                    setDialogState(() {
                                      reasonError = 'Please enter a reason for your request';
                                    });
                                    return;
                                  }
                                  final scaffoldMessenger = ScaffoldMessenger.of(context);
                                  final nav = Navigator.of(context);
                                  setDialogState(() => isSubmitting = true);
                                  try {
                                    final res = await http.post(
                                      Uri.parse('${CollegeIPConfig.defaultURL}/student/leave-od/apply'),
                                      headers: {
                                        'Content-Type': 'application/json',
                                        'Authorization': 'Bearer ${widget.token}',
                                      },
                                      body: jsonEncode({
                                        'request_type': reqType,
                                        'category': category,
                                        'start_date':
                                            '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}',
                                        'end_date':
                                            '${endDate.year}-${endDate.month.toString().padLeft(2, '0')}-${endDate.day.toString().padLeft(2, '0')}',
                                        'session_half': sessionHalf,
                                        'reason': reason,
                                        'document_proof_url': docUrlCtrl.text.trim(),
                                      }),
                                    ).timeout(const Duration(seconds: 15));

                                    nav.pop();
                                    if (res.statusCode == 200 || res.statusCode == 201) {
                                      scaffoldMessenger.showSnackBar(
                                        const SnackBar(
                                          content: Text('✅ Leave / OD request submitted successfully!'),
                                          backgroundColor: emeraldGreen,
                                        ),
                                      );
                                    } else {
                                      final body = json.decode(res.body);
                                      scaffoldMessenger.showSnackBar(
                                        SnackBar(
                                          content: Text(body['detail'] ?? 'Submission failed'),
                                          backgroundColor: roseDanger,
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    nav.pop();
                                    scaffoldMessenger.showSnackBar(
                                      SnackBar(
                                        content: Text('Error: ${ApiResponseUtils.sanitize(e)}'),
                                        backgroundColor: roseDanger,
                                      ),
                                    );
                                  }
                                  _fetchRequests();
                                },
                          child: isSubmitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : const Text('Submit Application', style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Partition into Active vs History
    final activeRequests = _requests.where((r) {
      final mSt = (r['mentor_status'] ?? '').toString();
      final hSt = (r['hod_status'] ?? '').toString();
      final aSt = (r['admin_status'] ?? '').toString();
      final isHistory = hSt == 'APPROVED' ||
          aSt == 'APPROVED' ||
          mSt == 'REJECTED' ||
          hSt == 'REJECTED' ||
          aSt == 'REJECTED' ||
          hSt == 'REFERRED_BACK' ||
          mSt == 'CANCELLED' ||
          hSt == 'CANCELLED';
      return !isHistory;
    }).toList();

    final historyRequests = _requests.where((r) {
      final mSt = (r['mentor_status'] ?? '').toString();
      final hSt = (r['hod_status'] ?? '').toString();
      final aSt = (r['admin_status'] ?? '').toString();
      return hSt == 'APPROVED' ||
          aSt == 'APPROVED' ||
          mSt == 'REJECTED' ||
          hSt == 'REJECTED' ||
          aSt == 'REJECTED' ||
          hSt == 'REFERRED_BACK' ||
          mSt == 'CANCELLED' ||
          hSt == 'CANCELLED';
    }).toList();

    final currentPool = _currentSubTab == 0 ? activeRequests : historyRequests;

    final filteredRequests = currentPool.where((r) {
      if (_selectedFilter == 'ALL') return true;
      if (_selectedFilter == 'ON_DUTY') return r['request_type'] == 'ON_DUTY';
      if (_selectedFilter == 'LEAVE') return r['request_type'] != 'ON_DUTY';
      if (_selectedFilter == 'APPROVED') return r['hod_status'] == 'APPROVED' || r['admin_status'] == 'APPROVED';
      if (_selectedFilter == 'REJECTED') {
        return r['mentor_status'] == 'REJECTED' ||
            r['hod_status'] == 'REJECTED' ||
            r['admin_status'] == 'REJECTED';
      }
      if (_selectedFilter == 'CANCELLED') {
        return r['mentor_status'] == 'CANCELLED' || r['hod_status'] == 'CANCELLED';
      }
      if (_selectedFilter == 'PENDING') return r['hod_status'] == 'PENDING';
      return true;
    }).toList();

    int totalCount = _requests.length;
    int approvedCount = _requests.where((r) => r['hod_status'] == 'APPROVED' || r['admin_status'] == 'APPROVED').length;
    int activeCount = activeRequests.length;
    int historyCount = historyRequests.length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showApplyDialog,
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Apply OD / Leave'),
      ),
      body: RefreshIndicator(
        onRefresh: _fetchRequests,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Header Metrics Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                        : [primaryBlue, secondaryIndigo],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Leave & On-Duty Hub',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Advisor & HOD Approvals',
                            style: GoogleFonts.inter(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildStatPill('Total', '$totalCount', Colors.white.withValues(alpha: 0.2)),
                    const SizedBox(width: 5),
                    _buildStatPill('Active', '$activeCount', amberWarning.withValues(alpha: 0.3)),
                    const SizedBox(width: 5),
                    _buildStatPill('Approved', '$approvedCount', emeraldGreen.withValues(alpha: 0.3)),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 2. Sub-Section Switcher (Active Applications vs History Records)
              _buildStudentSubSectionBar(isDark, activeCount, historyCount),
              const SizedBox(height: 12),

              // 3. Filter Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _currentSubTab == 0
                      ? [
                          _buildFilterChip('All Active', 'ALL'),
                          _buildFilterChip('On-Duty (OD)', 'ON_DUTY'),
                          _buildFilterChip('Leave', 'LEAVE'),
                        ]
                      : [
                          _buildFilterChip('All History', 'ALL'),
                          _buildFilterChip('Approved', 'APPROVED'),
                          _buildFilterChip('Rejected', 'REJECTED'),
                          _buildFilterChip('Cancelled', 'CANCELLED'),
                          _buildFilterChip('On-Duty (OD)', 'ON_DUTY'),
                          _buildFilterChip('Leave', 'LEAVE'),
                        ],
                ),
              ),
              const SizedBox(height: 14),

              // 4. Requests List
              if (_isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: CircularProgressIndicator(color: primaryBlue),
                  ),
                )
              else if (filteredRequests.isEmpty)
                _buildEmptyState(isDark)
              else
                ...filteredRequests.map((r) => _buildStudentRequestCard(r, isDark)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStudentSubSectionBar(bool isDark, int activeCount, int historyCount) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade300),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: _buildStudentSubTabButton(
              index: 0,
              title: 'Active ($activeCount)',
              icon: Icons.bolt_rounded,
              color: amberWarning,
              isDark: isDark,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildStudentSubTabButton(
              index: 1,
              title: 'History ($historyCount)',
              icon: Icons.history_edu_rounded,
              color: primaryBlue,
              isDark: isDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentSubTabButton({
    required int index,
    required String title,
    required IconData icon,
    required Color color,
    required bool isDark,
  }) {
    final isSelected = _currentSubTab == index;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        if (_currentSubTab != index) {
          setState(() {
            _currentSubTab = index;
            _selectedFilter = 'ALL';
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? const Color(0xFF334155) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? color : (isDark ? Colors.white60 : Colors.grey.shade600),
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  color: isSelected
                      ? (isDark ? Colors.white : Colors.black87)
                      : (isDark ? Colors.white60 : Colors.grey.shade600),
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatPill(String label, String count, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            count,
            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
          ),
          Text(
            label,
            style: GoogleFonts.inter(color: Colors.white70, fontSize: 9),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (selected) {
          if (selected) setState(() => _selectedFilter = value);
        },
        selectedColor: primaryBlue,
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : Colors.grey.shade700,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildStudentRequestCard(dynamic r, bool isDark) {
    final reqId = r['id'] ?? 0;
    final reqType = r['request_type'] ?? 'ON_DUTY';
    final category = r['category'] ?? '';
    final reason = r['reason'] ?? '';
    final startDate = r['start_date'] ?? '';
    final endDate = r['end_date'] ?? '';
    final totalDays = r['total_days'] ?? 1;
    final sessionHalf = r['session_half'] ?? 'FULL_DAY';
    final mentorStatus = r['mentor_status'] ?? 'PENDING';
    final mentorName = r['mentor_name'] ?? 'Class Advisor';
    final mentorRemarks = r['mentor_remarks'] ?? '';
    final hodStatus = r['hod_status'] ?? 'PENDING';
    final hodName = r['hod_name'] ?? 'HOD';
    final hodRemarks = r['hod_remarks'] ?? '';
    final isCredited = r['is_credited'] == 1 || r['is_credited'] == true;
    final docUrl = r['document_url'] ?? '';
    final createdAt = (r['created_at'] ?? '').toString();

    final isOd = reqType == 'ON_DUTY';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Type & Dates
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (isOd ? secondaryIndigo : violetAccent).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isOd ? Icons.badge_outlined : Icons.event_busy_outlined,
                        size: 14,
                        color: isOd ? secondaryIndigo : violetAccent,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        isOd ? 'ON-DUTY (OD)' : 'LEAVE',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: isOd ? secondaryIndigo : violetAccent,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  startDate == endDate ? startDate : '$startDate → $endDate',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Category & Total Days
            Row(
              children: [
                Expanded(
                  child: Text(
                    category,
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14.5),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: primaryBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$totalDays Day${totalDays > 1 ? "s" : ""} • ${sessionHalf.replaceAll("_", " ")}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: primaryBlue,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Reason
            Text(
              reason,
              style: GoogleFonts.inter(fontSize: 12.5, color: isDark ? Colors.white60 : Colors.black54),
            ),
            if (createdAt.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Applied on: ${createdAt.length > 16 ? createdAt.substring(0, 16) : createdAt}',
                style: GoogleFonts.inter(fontSize: 10.5, color: Colors.grey.shade500),
              ),
            ],
            if (docUrl.isNotEmpty) ...[
              const SizedBox(height: 6),
              InkWell(
                onTap: () async {
                  try {
                    await launchUrl(Uri.parse(docUrl), mode: LaunchMode.externalApplication);
                  } catch (e) {
                    debugPrint("Error opening URL: $e");
                  }
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.attachment_rounded, size: 14, color: primaryBlue),
                    const SizedBox(width: 4),
                    Text(
                      'View Attached Document',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: primaryBlue,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),

            // 4-Stage Hierarchy Pipeline
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  _buildMiniStep('1', 'Applied\n✓ Done', emeraldGreen, true),
                  _buildMiniDivider(mentorStatus == 'RECOMMENDED'),
                  _buildMiniStep(
                    '2',
                    'Advisor\n${mentorStatus.replaceAll('_', ' ')}',
                    mentorStatus == 'RECOMMENDED'
                        ? emeraldGreen
                        : (mentorStatus == 'REJECTED' ? roseDanger : (mentorStatus == 'CANCELLED' ? Colors.grey : amberWarning)),
                    mentorStatus == 'RECOMMENDED',
                    remarks: mentorRemarks.isNotEmpty
                        ? '$mentorName remarks: "$mentorRemarks"'
                        : '$mentorName: $mentorStatus',
                  ),
                  _buildMiniDivider(hodStatus == 'APPROVED'),
                  _buildMiniStep(
                    '3',
                    'HOD\n${hodStatus.replaceAll('_', ' ')}',
                    hodStatus == 'APPROVED'
                        ? emeraldGreen
                        : (hodStatus == 'REJECTED'
                            ? roseDanger
                            : (hodStatus == 'REFERRED_BACK'
                                ? amberWarning
                                : (hodStatus == 'CANCELLED' ? Colors.grey : Colors.grey))),
                    hodStatus == 'APPROVED',
                    remarks: hodRemarks.isNotEmpty
                        ? '$hodName remarks: "$hodRemarks"'
                        : '$hodName: $hodStatus',
                  ),
                  _buildMiniDivider(isCredited),
                  _buildMiniStep(
                    '4',
                    isCredited ? 'Credited\n✓ Logged' : 'Crediting\nPending',
                    isCredited ? emeraldGreen : Colors.grey,
                    isCredited,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Bottom Actions: Timeline Button + Cancel Action
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: primaryBlue,
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.timeline_rounded, size: 14),
                  label: const Text('View Timeline', style: TextStyle(fontSize: 12)),
                  onPressed: () => _showTimelineDialog(reqId, reqType),
                ),
                if (mentorStatus == 'PENDING' && hodStatus == 'PENDING' && mentorStatus != 'CANCELLED')
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: roseDanger,
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.close_rounded, size: 14),
                    label: const Text('Cancel Request', style: TextStyle(fontSize: 12)),
                    onPressed: () async {
                      final conf = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text('Cancel Application?'),
                          content: const Text('Are you sure you want to withdraw this request?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('No')),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: roseDanger, foregroundColor: Colors.white),
                              onPressed: () => Navigator.pop(c, true),
                              child: const Text('Yes, Cancel'),
                            ),
                          ],
                        ),
                      );
                      if (conf == true) {
                        await http.post(
                          Uri.parse('${CollegeIPConfig.defaultURL}/student/leave-od/cancel/$reqId'),
                          headers: {'Authorization': 'Bearer ${widget.token}'},
                        );
                        _fetchRequests();
                      }
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniStep(String num, String text, Color color, bool isDone, {String? remarks}) {
    return Expanded(
      child: Tooltip(
        message: remarks ?? text,
        child: Column(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDone ? color : color.withValues(alpha: 0.15),
                border: Border.all(color: color, width: 1.2),
              ),
              child: Center(
                child: isDone
                    ? const Icon(Icons.check, size: 10, color: Colors.white)
                    : Text(
                        num,
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color),
                      ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              text,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 8.5,
                fontWeight: isDone ? FontWeight.bold : FontWeight.w500,
                color: color,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniDivider(bool isDone) {
    return Container(
      width: 10,
      height: 1.5,
      color: isDone ? emeraldGreen : Colors.grey.shade300,
      margin: const EdgeInsets.only(bottom: 12),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(
            _currentSubTab == 0 ? Icons.assignment_turned_in_outlined : Icons.history_edu_rounded,
            size: 54,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 10),
          Text(
            _currentSubTab == 0
                ? 'No Active Leave or On-Duty Applications'
                : 'No History Records Found',
            style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 4),
          Text(
            _currentSubTab == 0
                ? 'All your applications have been processed or you have not submitted any.'
                : 'Processed, approved, and cancelled applications will appear here.',
            style: GoogleFonts.inter(color: Colors.grey.shade500, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// STUDENT LEAVE & OD TIMELINE DIALOG
// ─────────────────────────────────────────────────────────
class _StudentLeaveODTimelineDialog extends StatefulWidget {
  final String token;
  final int requestId;
  final String requestType;

  const _StudentLeaveODTimelineDialog({
    required this.token,
    required this.requestId,
    required this.requestType,
  });

  @override
  State<_StudentLeaveODTimelineDialog> createState() => _StudentLeaveODTimelineDialogState();
}

class _StudentLeaveODTimelineDialogState extends State<_StudentLeaveODTimelineDialog> {
  bool _isLoading = true;
  String? _error;
  List<dynamic> _timeline = [];

  @override
  void initState() {
    super.initState();
    _fetchTimeline();
  }

  Future<void> _fetchTimeline() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final res = await http.get(
        Uri.parse('${CollegeIPConfig.defaultURL}/student/leave-od/${widget.requestId}/timeline'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );

      if (res.statusCode == 200) {
        final d = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            _timeline = (d['timeline'] ?? []) as List<dynamic>;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _error = 'Failed to load timeline (Status: ${res.statusCode})';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Network error: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      child: Container(
        width: 520,
        constraints: const BoxConstraints(maxHeight: 600),
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.timeline_rounded, color: Color(0xFF2563EB), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Application Timeline',
                        style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        '${widget.requestType.replaceAll('_', ' ')} • Req #${widget.requestId}',
                        style: GoogleFonts.inter(fontSize: 11.5, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // Timeline List
            Flexible(
              child: _isLoading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 30),
                        child: CircularProgressIndicator(color: Color(0xFF2563EB)),
                      ),
                    )
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(_error!, style: const TextStyle(color: Color(0xFFEF4444))),
                          ),
                        )
                      : _timeline.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  'No timeline logs found.',
                                  style: GoogleFonts.inter(color: Colors.grey.shade500),
                                ),
                              ),
                            )
                          : SingleChildScrollView(
                              child: Column(
                                children: _timeline.asMap().entries.map((entry) {
                                  final idx = entry.key;
                                  final item = entry.value;
                                  final isLast = idx == _timeline.length - 1;
                                  return _buildStep(item, isLast, isDark);
                                }).toList(),
                              ),
                            ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(dynamic item, bool isLast, bool isDark) {
    final action = (item['action'] ?? '').toString();
    final role = (item['actor_role'] ?? '').toString();
    final actorName = (item['actor_name'] ?? 'System').toString();
    final remarks = (item['remarks'] ?? '').toString();
    final timestamp = (item['timestamp'] ?? item['created_at'] ?? '').toString();

    Color color = const Color(0xFF2563EB);
    IconData icon = Icons.info_outline_rounded;

    if (action.contains('SUBMIT')) {
      color = const Color(0xFF4F46E5);
      icon = Icons.send_rounded;
    } else if (action.contains('RECOMMEND')) {
      color = const Color(0xFF10B981);
      icon = Icons.thumb_up_alt_rounded;
    } else if (action.contains('APPROVED')) {
      color = const Color(0xFF10B981);
      icon = Icons.verified_rounded;
    } else if (action.contains('ATTENDANCE_CREDITED')) {
      color = const Color(0xFF059669);
      icon = Icons.event_available_rounded;
    } else if (action.contains('REJECT')) {
      color = const Color(0xFFEF4444);
      icon = Icons.cancel_rounded;
    } else if (action.contains('REFER')) {
      color = const Color(0xFFF59E0B);
      icon = Icons.replay_rounded;
    } else if (action.contains('CANCEL')) {
      color = const Color(0xFF6B7280);
      icon = Icons.block_rounded;
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 1.5),
                ),
                child: Center(child: Icon(icon, size: 14, color: color)),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: Colors.grey.shade300,
                    margin: const EdgeInsets.symmetric(vertical: 3),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        action.replaceAll('_', ' '),
                        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11.5),
                      ),
                      Text(
                        timestamp.length > 16 ? timestamp.substring(0, 16) : timestamp,
                        style: GoogleFonts.inter(fontSize: 10, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$actorName ($role)',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 11.5),
                  ),
                  if (remarks.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      'Remarks: "$remarks"',
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        fontStyle: FontStyle.italic,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// TAB 6: ATTENDANCE ANALYTICS
// ─────────────────────────────────────────────────────────
class _StudentAnalyticsTab extends StatelessWidget {
  final String token;
  final Map<String, dynamic> user;
  final Map<String, dynamic> summary;
  final Map<String, dynamic> analytics;
  final VoidCallback onRefresh;

  const _StudentAnalyticsTab({
    required this.token,
    required this.user,
    required this.summary,
    required this.analytics,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final sum = analytics['summary'] ?? summary;
    final subjects = (analytics['subjects'] as List?) ?? [];
    final monthlyTrend = (analytics['monthly_trend'] as List?) ?? [];

    final presentCount = (sum['present_count'] ?? 0) as int;
    final odCount = (sum['on_duty_count'] ?? 0) as int;
    final medicalCount = (sum['medical_count'] ?? 0) as int;
    final absentCount = (sum['absent_count'] ?? 0) as int;
    final totalAttended = presentCount + odCount;
    final totalWorking = (sum['total_working_sessions'] ?? 0) as int;
    final currentPct = double.tryParse((sum['attendance_percentage'] ?? 100.0).toString()) ?? 100.0;
    final isEligible = currentPct >= 75.0;

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                      : [Colors.white, const Color(0xFFEFF6FF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFF2563EB).withValues(alpha: 0.3)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2563EB).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.analytics_rounded, color: Color(0xFF2563EB), size: 22),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Academic Attendance Summary',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: (isEligible ? const Color(0xFF10B981) : const Color(0xFFEF4444)).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          isEligible ? 'Exam Eligible' : 'Shortage Warning',
                          style: TextStyle(
                            color: isEligible ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 80,
                            height: 80,
                            child: CircularProgressIndicator(
                              value: (currentPct / 100.0).clamp(0.0, 1.0),
                              strokeWidth: 8,
                              backgroundColor: Colors.grey.withValues(alpha: 0.15),
                              color: isEligible
                                  ? (currentPct >= 85 ? const Color(0xFF10B981) : const Color(0xFF2563EB))
                                  : const Color(0xFFEF4444),
                            ),
                          ),
                          Text(
                            '$currentPct%',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isEligible
                                  ? 'Attendance is in Good Standing'
                                  : 'Attendance Shortage Detected',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: isEligible ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isEligible
                                  ? 'Your overall attendance is $currentPct%, satisfying the university 75% minimum semester requirement.'
                                  : 'Your attendance has dropped below 75%. Please contact your mentor or attend upcoming sessions regularly.',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white70 : Colors.grey.shade600,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildSummaryStat('Working', '$totalWorking', Colors.grey),
                      _buildSummaryStat('Attended', '$totalAttended', const Color(0xFF10B981)),
                      _buildSummaryStat('OD/Medical', '${odCount + medicalCount}', const Color(0xFF2563EB)),
                      _buildSummaryStat('Absent', '$absentCount', const Color(0xFFEF4444)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Subject-Wise Attendance Distribution',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            if (subjects.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Center(child: Text('No subject allocations found for this semester.')),
              )
            else
              ...subjects.map((sub) {
                final spct = double.tryParse((sub['percentage'] ?? 100.0).toString()) ?? 100.0;
                final isLow = spct < 75.0;
                final color = isLow
                    ? const Color(0xFFEF4444)
                    : (spct >= 85 ? const Color(0xFF10B981) : const Color(0xFFF59E0B));

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              '${sub['code']} - ${sub['name']}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '$spct%',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: color,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Faculty: ${sub['faculty'] ?? 'Faculty'}',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                          ),
                          Text(
                            '${sub['attended_hours']} / ${sub['total_hours']} hrs',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: (spct / 100.0).clamp(0.0, 1.0),
                          minHeight: 8,
                          backgroundColor: Colors.grey.withValues(alpha: 0.15),
                          color: color,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            const SizedBox(height: 20),
            if (monthlyTrend.isNotEmpty) ...[
              const Text(
                'Monthly Attendance Progression',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: monthlyTrend.map((m) {
                    final mpct = double.tryParse((m['percentage'] ?? 100.0).toString()) ?? 100.0;
                    return Column(
                      children: [
                        Text(
                          '$mpct%',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          width: 36,
                          height: (mpct * 0.7).clamp(20.0, 70.0),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF2563EB), Color(0xFF4F46E5)],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          m['month'] ?? '',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────
// TAB 7: DIGITAL STUDENT ID & PROFILE
// ─────────────────────────────────────────────────────────
class _StudentProfileTab extends StatelessWidget {
  final String token;
  final Map<String, dynamic> user;
  final Map<String, dynamic> profile;
  final Map<String, dynamic> faceRegStatus;
  final VoidCallback onLogout;
  final VoidCallback onPasswordChanged;
  final VoidCallback onGoToFaceRegister;

  const _StudentProfileTab({
    required this.token,
    required this.user,
    required this.profile,
    required this.faceRegStatus,
    required this.onLogout,
    required this.onPasswordChanged,
    required this.onGoToFaceRegister,
  });

  void _showChangePasswordDialog(BuildContext context) {
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Change Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: oldCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Current Password / DOB'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: newCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New Password (min 6 chars)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              if (newCtrl.text.length < 6) return;
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(context);
              final res = await http.post(
                Uri.parse('${CollegeIPConfig.defaultURL}/student/change-password'),
                headers: {
                  'Content-Type': 'application/json',
                  'Authorization': 'Bearer $token',
                },
                body: jsonEncode({
                  'old_password': oldCtrl.text,
                  'new_password': newCtrl.text,
                }),
              );
              if (res.statusCode == 200) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('Password updated successfully!')),
                );
                onPasswordChanged();
              }
            },
            child: const Text('Save Password'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEnrolled = (faceRegStatus['face_registration']?['is_enrolled'] == true) ||
        (profile['face_prototype_ready'] == true);
    final name = (profile['name'] ?? user['name'] ?? 'Student').toString();
    final regNo = (profile['reg_no'] ?? user['reg_no'] ?? user['regNo'] ?? '').toString();
    final rollNo = (profile['roll_no'] ?? user['roll_no'] ?? '-').toString();
    final dept = (profile['dept'] ?? user['dept'] ?? 'CSE').toString();
    final batch = (profile['batch'] ?? user['batch'] ?? '2022-2026').toString();
    final bloodGroup = (profile['blood_group'] ?? user['blood_group'] ?? 'O+').toString();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. DIGITAL STUDENT ID CARD
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E3A8A), Color(0xFF2563EB), Color(0xFF4F46E5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2563EB).withValues(alpha: 0.35),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'SRI SHAKTHI INSTITUTE',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            letterSpacing: 0.8,
                          ),
                        ),
                        Text(
                          'OF ENGINEERING AND TECHNOLOGY',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'STUDENT ID',
                        style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const Divider(color: Colors.white24, height: 24),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 36,
                      backgroundColor: Colors.white.withValues(alpha: 0.25),
                      child: const Icon(Icons.person, color: Colors.white, size: 44),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Reg No: $regNo',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12),
                          ),
                          Text(
                            'Roll No: $rollNo • Blood: $bloodGroup',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11),
                          ),
                          Text(
                            'Dept: $dept (Batch $batch)',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.qr_code_2_rounded, size: 40, color: Colors.black),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 2. Biometric Status Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (isEnrolled ? const Color(0xFF10B981) : const Color(0xFFEF4444)).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.face_retouching_natural_rounded,
                    color: isEnrolled ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isEnrolled ? 'Biometric Face ID Active' : 'Face ID Not Registered',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: isEnrolled ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                        ),
                      ),
                      Text(
                        isEnrolled
                            ? 'Enrolled with multi-angle samples. Centroid prototype active.'
                            : 'Register your face profile to enable one-tap attendance marking.',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: onGoToFaceRegister,
                  child: Text(isEnrolled ? 'Manage' : 'Register', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 3. Academic Details
          const Text('Academic & Mentor Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
            ),
            child: Column(
              children: [
                _buildRow('Degree & Program', '${profile['degree'] ?? 'B.E.'} ${profile['dept'] ?? user['dept']}'),
                _buildRow('Semester & Section', 'Sem ${profile['semester'] ?? 6} - Sec ${profile['section'] ?? 'A'}'),
                _buildRow('Class Advisor / Mentor', '${profile['mentor_name'] ?? 'Assigned Staff'}'),
                _buildRow('Parent Contact', '${profile['parent_phone'] ?? '-'}'),
                _buildRow('Email Address', '${profile['email'] ?? user['email'] ?? '-'}'),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 4. Action Buttons
          ElevatedButton.icon(
            onPressed: () => _showChangePasswordDialog(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            icon: const Icon(Icons.lock_reset_rounded),
            label: const Text('Update Account Password'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onLogout,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFEF4444),
              minimumSize: const Size(double.infinity, 50),
              side: const BorderSide(color: Color(0xFFEF4444)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sign Out of Student Portal'),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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
              // Pulsing alert icon
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
