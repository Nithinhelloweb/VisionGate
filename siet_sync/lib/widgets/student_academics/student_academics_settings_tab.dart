import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../../config/college_ip_config.dart';
import '../../theme/admin_theme.dart';
import '../../utils/api_response_utils.dart';
import 'student_academics_overview.dart';
import 'student_academic_ranges_card.dart';
import 'student_holiday_calendar_view.dart';
import 'student_batch_promotion_card.dart';
import 'student_attendance_policy_card.dart';

class StudentAcademicsSettingsTab extends StatefulWidget {
  final String token;
  final Map<String, dynamic> user;

  const StudentAcademicsSettingsTab({
    super.key,
    required this.token,
    required this.user,
  });

  @override
  State<StudentAcademicsSettingsTab> createState() => _StudentAcademicsSettingsTabState();
}

class _StudentAcademicsSettingsTabState extends State<StudentAcademicsSettingsTab> {
  int _activeTabIndex = 0;
  bool _isLoading = true;
  bool _isSaving = false;

  Map<String, dynamic> _settings = {};
  Map<String, dynamic> _stats = {};
  List<Map<String, dynamic>> _calendarList = [];
  Map<String, dynamic> _calendarStats = {};
  List<dynamic> _batches = [];

  List<Map<String, dynamic>> _ranges = [];
  String _activeAcademicYear = '2025-2026';
  Map<String, dynamic> _holidayOverrides = {};
  Map<String, dynamic> _batchConfigs = {};
  Map<String, dynamic> _attendancePolicy = {};
  List<dynamic> _milestones = [];

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${widget.token}',
        'Content-Type': 'application/json',
      };

  String get _baseUrl => CollegeIPConfig.defaultURL;

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    try {
      await Future.wait([
        _fetchSettings(),
        _fetchStats(),
        _fetchCalendar(),
        _fetchBatches(),
      ]);
    } catch (e) {
      if (mounted) {
        _showSnack('Failed to load academic data: ${ApiResponseUtils.sanitize(e)}', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchSettings() async {
    final res = await http.get(
      Uri.parse('$_baseUrl/api/v1/admin/student-academics/settings'),
      headers: _headers,
    );
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body);
      final data = body['data'] ?? {};
      if (mounted) {
        setState(() {
          _settings = data;
          _activeAcademicYear = data['active_academic_year'] ?? '2025-2026';
          _ranges = (data['academic_ranges'] as List? ?? [])
              .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _holidayOverrides = Map<String, dynamic>.from(data['holiday_overrides'] ?? {});
          _batchConfigs = Map<String, dynamic>.from(data['batch_configs'] ?? {});
          _attendancePolicy = Map<String, dynamic>.from(data['attendance_policy'] ?? {});
          _milestones = List<dynamic>.from(data['milestones'] ?? []);
        });
      }
    }
  }

  Future<void> _fetchStats() async {
    final res = await http.get(
      Uri.parse('$_baseUrl/api/v1/admin/student-academics/stats'),
      headers: _headers,
    );
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body);
      if (mounted) {
        setState(() => _stats = body['data'] ?? {});
      }
    }
  }

  Future<void> _fetchCalendar() async {
    final res = await http.get(
      Uri.parse('$_baseUrl/api/v1/admin/student-academics/calendar'),
      headers: _headers,
    );
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body);
      final data = body['data'] ?? {};
      if (mounted) {
        setState(() {
          _calendarList = (data['calendar'] as List? ?? [])
              .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _calendarStats = Map<String, dynamic>.from(data['stats'] ?? {});
        });
      }
    }
  }

  Future<void> _fetchBatches() async {
    final res = await http.get(
      Uri.parse('$_baseUrl/api/v1/admin/student-academics/batches'),
      headers: _headers,
    );
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body);
      if (mounted) {
        setState(() => _batches = body['data'] ?? []);
      }
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    try {
      final payload = {
        'active_academic_year': _activeAcademicYear,
        'academic_ranges': _ranges,
        'holiday_overrides': _holidayOverrides,
        'batch_configs': _batchConfigs,
        'attendance_policy': _attendancePolicy,
        'milestones': _milestones,
      };

      final res = await http.post(
        Uri.parse('$_baseUrl/api/v1/admin/student-academics/settings'),
        headers: _headers,
        body: jsonEncode(payload),
      );

      if (res.statusCode == 200) {
        if (mounted) {
          _showSnack('Student Academic Settings saved successfully!', isError: false);
          await _loadAllData();
        }
      } else {
        throw Exception(res.body);
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Error saving settings: ${ApiResponseUtils.sanitize(e)}', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _setCalendarOverride(String date, String status, String title, String category, String reason) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/api/v1/admin/student-academics/calendar/override'),
        headers: _headers,
        body: jsonEncode({
          'date': date,
          'status': status,
          'title': title,
          'category': category,
          'reason': reason,
        }),
      );
      if (res.statusCode == 200) {
        if (mounted) {
          _showSnack('Calendar status updated for $date', isError: false);
          await _loadAllData();
        }
      }
    } catch (e) {
      if (mounted) _showSnack('Failed to update calendar date: $e', isError: true);
    }
  }

  Future<void> _setCalendarRangeOverride(String startDate, String endDate, String status, String title, String category, String reason) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/api/v1/admin/student-academics/calendar/range-override'),
        headers: _headers,
        body: jsonEncode({
          'start_date': startDate,
          'end_date': endDate,
          'status': status,
          'title': title,
          'category': category,
          'reason': reason,
        }),
      );
      if (res.statusCode == 200) {
        if (mounted) {
          _showSnack('Vacation/Holiday range applied ($startDate to $endDate)', isError: false);
          await _loadAllData();
        }
      }
    } catch (e) {
      if (mounted) _showSnack('Failed to apply range: $e', isError: true);
    }
  }

  Future<void> _deleteCalendarOverride(String date) async {
    try {
      final res = await http.delete(
        Uri.parse('$_baseUrl/api/v1/admin/student-academics/calendar/override/$date'),
        headers: _headers,
      );
      if (res.statusCode == 200) {
        if (mounted) {
          _showSnack('Override cleared for $date', isError: false);
          await _loadAllData();
        }
      }
    } catch (e) {
      if (mounted) _showSnack('Failed to clear override: $e', isError: true);
    }
  }

  void _showSnack(String msg, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: isError ? AdminColors.danger : AdminColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 900;

    final tabs = [
      {'label': 'Overview', 'icon': Icons.dashboard_outlined, 'selectedIcon': Icons.dashboard_rounded},
      {'label': 'Academic Ranges', 'icon': Icons.date_range_outlined, 'selectedIcon': Icons.date_range_rounded},
      {'label': 'Holiday Calendar', 'icon': Icons.calendar_month_outlined, 'selectedIcon': Icons.calendar_month_rounded},
      {'label': 'Batch Promotion', 'icon': Icons.upgrade_outlined, 'selectedIcon': Icons.upgrade_rounded},
      {'label': 'Attendance Policy', 'icon': Icons.rule_outlined, 'selectedIcon': Icons.rule_rounded},
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(isWide ? 32 : 16, 20, isWide ? 32 : 16, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Navigation Strip & Section Switcher
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: AdminColors.getCard(isDark),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AdminColors.getBorder(isDark)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: List.generate(tabs.length, (index) {
                                final isSelected = _activeTabIndex == index;
                                final t = tabs[index];

                                return Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: InkWell(
                                    onTap: () => setState(() => _activeTabIndex = index),
                                    borderRadius: BorderRadius.circular(8),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 180),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? AdminColors.primary
                                            : (isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF1F5F9)),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: isSelected
                                              ? AdminColors.primary
                                              : AdminColors.getBorder(isDark).withValues(alpha: 0.5),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            isSelected ? (t['selectedIcon'] as IconData) : (t['icon'] as IconData),
                                            size: 13,
                                            color: isSelected ? Colors.white : AdminColors.getTextSecondary(isDark),
                                          ),
                                          const SizedBox(width: 5),
                                          Text(
                                            t['label'] as String,
                                            style: GoogleFonts.inter(
                                              fontSize: 11.5,
                                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                              color: isSelected ? Colors.white : AdminColors.getTextPrimary(isDark),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          tooltip: 'Refresh Academics',
                          padding: const EdgeInsets.all(6),
                          constraints: const BoxConstraints(),
                          onPressed: _loadAllData,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Active Section Sub-View
                  IndexedStack(
                    index: _activeTabIndex,
                    children: [
                      StudentAcademicsOverview(
                        stats: _stats,
                        settings: _settings,
                        batches: _batches,
                        isLoading: _isLoading,
                        onRefresh: _loadAllData,
                        onGoToRanges: () => setState(() => _activeTabIndex = 1),
                        onGoToCalendar: () => setState(() => _activeTabIndex = 2),
                        onGoToBatches: () => setState(() => _activeTabIndex = 3),
                        onGoToPolicies: () => setState(() => _activeTabIndex = 4),
                        onAddHoliday: () => setState(() => _activeTabIndex = 2),
                      ),
                      StudentAcademicRangesCard(
                        ranges: _ranges,
                        activeAcademicYear: _activeAcademicYear,
                        onAcademicYearChanged: (y) => _activeAcademicYear = y,
                        onRangesChanged: (r) => setState(() => _ranges = r),
                        onSave: _saveSettings,
                        isSaving: _isSaving,
                      ),
                      StudentHolidayCalendarView(
                        calendarList: _calendarList,
                        calendarStats: _calendarStats,
                        holidayOverrides: _holidayOverrides,
                        onSetOverride: _setCalendarOverride,
                        onSetRangeOverride: _setCalendarRangeOverride,
                        onDeleteOverride: _deleteCalendarOverride,
                        onRefresh: _loadAllData,
                        isLoading: _isLoading,
                      ),
                      StudentBatchPromotionCard(
                        token: widget.token,
                        batches: _batches,
                        batchConfigs: _batchConfigs,
                        onBatchConfigsChanged: (b) {
                          setState(() => _batchConfigs = b);
                          _saveSettings();
                        },
                        onRefreshBatches: _fetchBatches,
                      ),
                      StudentAttendancePolicyCard(
                        policy: _attendancePolicy,
                        milestones: _milestones,
                        onPolicyChanged: (p) => _attendancePolicy = p,
                        onMilestonesChanged: (m) => setState(() => _milestones = m),
                        onSave: _saveSettings,
                        isSaving: _isSaving,
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}
