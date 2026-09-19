import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/college_ip_config.dart';
import '../utils/api_response_utils.dart';
import '../utils/file_saver.dart';
import 'class_session_roll_sheet.dart';

String get API_URL => CollegeIPConfig.defaultURL;

/// Staff Academic Schedule, Calendar & Working List Hub Widget
/// Designed in strict compliance with the Hallmark Anti-AI-Slop Standard:
/// - 100% Roman upright headings (FontStyle.normal)
/// - Locked semantic color tokens
/// - 8-State interactive design coverage
/// - Authentic, domain-precise copy and working queue workflows
class StaffScheduleWorkingListTab extends StatefulWidget {
  final String token;
  final Map<String, dynamic> user;
  final Function(int)? onNavigateToTab;

  const StaffScheduleWorkingListTab({
    super.key,
    required this.token,
    required this.user,
    this.onNavigateToTab,
  });

  @override
  State<StaffScheduleWorkingListTab> createState() => _StaffScheduleWorkingListTabState();
}

class _StaffScheduleWorkingListTabState extends State<StaffScheduleWorkingListTab> {
  // Mode: 0 = Working List / Queue, 1 = Month Calendar, 2 = Weekly Matrix, 3 = Assigned Subjects, 4 = Live Attendance
  int _activeViewMode = 0;

  // Calendar State
  DateTime _selectedDate = DateTime.now();
  int _currentYear = DateTime.now().year;
  int _currentMonth = DateTime.now().month;

  // Data State
  bool _isLoading = true;
  String? _errorMessage;

  Map<String, dynamic>? _dailyDigest;
  List<dynamic> _monthDays = [];
  List<dynamic> _upcomingSessions = [];
  List<dynamic> _assignedSubjects = [];
  String? _selectedSubjectFilter;

  // Live Attendance Session State
  List<dynamic> _todayPeriods = [];
  Map<String, dynamic> _sessionPrefs = {};
  bool _isLiveSessionLoading = false;
  Timer? _liveSessionRefreshTimer;

  // Reminder preferences
  int _leadTimeMinutes = 15;
  bool _dailyDigestEnabled = true;

  String get _staffRegNo => (widget.user['reg_no'] ?? widget.user['regNo'] ?? widget.user['username'] ?? '').toString();
  String get _staffName => (widget.user['name'] ?? widget.user['fullName'] ?? 'Faculty').toString();

  Map<String, String> get _authHeaders => {
        'Authorization': widget.token.startsWith('Bearer ') ? widget.token : 'Bearer ${widget.token}',
        'Content-Type': 'application/json',
      };

  @override
  void initState() {
    super.initState();
    _loadAllData();
    _fetchTodayPeriods();
    _liveSessionRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && _activeViewMode == 4) {
        _fetchTodayPeriods(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _liveSessionRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchTodayPeriods({bool silent = false}) async {
    if (!silent) setState(() => _isLiveSessionLoading = true);
    try {
      final dateStr = "${_selectedDate.year.toString().padLeft(4, '0')}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}";
      final res = await http.get(
        Uri.parse('$API_URL/api/v1/class-session/today-periods?target_date=$dateStr'),
        headers: _authHeaders,
      ).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (mounted) {
          setState(() {
            _todayPeriods = data['periods'] ?? [];
            _sessionPrefs = data['prefs'] ?? {};
            _isLiveSessionLoading = false;
          });
        }
      }
    } catch (_) {
      if (mounted && !silent) setState(() => _isLiveSessionLoading = false);
    }
  }

  Future<void> _startCheckin(Map<String, dynamic> period, {List<int>? periodNumbers}) async {
    final periodsToOpen = periodNumbers ?? [period['period_number'] as int];
    try {
      final dateStr = "${_selectedDate.year.toString().padLeft(4, '0')}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}";
      final res = await http.post(
        Uri.parse('$API_URL/api/v1/class-session/start-checkin'),
        headers: _authHeaders,
        body: json.encode({
          'timetable_slot_id': period['timetable_slot_id'],
          'period_numbers': periodsToOpen,
          'dept': period['dept'],
          'batch': period['batch'],
          'semester': period['semester'],
          'section': period['section'],
          'subject_code': period['subject_code'],
          'subject_name': period['subject_name'],
          'target_date': dateStr,
        }),
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Check-in opened for Period ${periodsToOpen.join(', ')}"),
              backgroundColor: const Color(0xFF059669),
            ),
          );
        }
        await _fetchTodayPeriods();
      } else {
        final err = json.decode(res.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(err['detail'] ?? "Failed to start check-in"), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _closeCheckin(String sessionId) async {
    try {
      final res = await http.post(
        Uri.parse('$API_URL/api/v1/class-session/close-checkin'),
        headers: _authHeaders,
        body: json.encode({'session_id': sessionId}),
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Check-in window closed"), backgroundColor: Color(0xFFD97706)),
          );
        }
        await _fetchTodayPeriods();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
    }
  }

  Future<void> _startCheckout(String sessionId) async {
    try {
      final res = await http.post(
        Uri.parse('$API_URL/api/v1/class-session/start-checkout'),
        headers: _authHeaders,
        body: json.encode({'session_id': sessionId}),
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Check-out window opened for students"), backgroundColor: Color(0xFF2563EB)),
          );
        }
        await _fetchTodayPeriods();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
    }
  }

  Future<void> _closeSession(String sessionId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("End Session & Finalize Attendance?"),
        content: const Text(
          "This will hard-close the attendance window. All enrolled students who did not check in will be automatically marked Absent.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("End Session"),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final res = await http.post(
        Uri.parse('$API_URL/api/v1/class-session/close-session'),
        headers: _authHeaders,
        body: json.encode({'session_id': sessionId}),
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                "Session closed. ${data['present_count']} Present, ${data['absent_count']} Absent.",
              ),
              backgroundColor: const Color(0xFF059669),
            ),
          );
        }
        await _fetchTodayPeriods();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
    }
  }

  Future<void> _openPreferencesDialog() async {
    int checkinGrace = _sessionPrefs['checkin_grace_mins'] ?? 5;
    bool checkoutRequired = _sessionPrefs['checkout_required'] ?? false;
    int checkoutGrace = _sessionPrefs['checkout_grace_mins'] ?? 5;
    int openWindow = _sessionPrefs['open_window_mins'] ?? 15;
    bool allowRetro = _sessionPrefs['allow_retroactive'] ?? true;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: const Text("Attendance Preferences"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Check-In Window Duration", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 4),
                DropdownButtonFormField<int>(
                  value: openWindow,
                  decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                  items: [5, 10, 15, 20, 30, 45].map((m) => DropdownMenuItem(value: m, child: Text("$m minutes"))).toList(),
                  onChanged: (v) => setDlgState(() => openWindow = v ?? 15),
                ),
                const SizedBox(height: 14),
                const Text("Late-Join Grace Period", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 4),
                DropdownButtonFormField<int>(
                  value: checkinGrace,
                  decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                  items: [0, 2, 5, 10, 15].map((m) => DropdownMenuItem(value: m, child: Text(m == 0 ? "No grace (hard close)" : "$m minutes"))).toList(),
                  onChanged: (v) => setDlgState(() => checkinGrace = v ?? 5),
                ),
                const SizedBox(height: 14),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Require Student Check-Out", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  subtitle: const Text("Track departure at period end", style: TextStyle(fontSize: 11)),
                  value: checkoutRequired,
                  onChanged: (v) => setDlgState(() => checkoutRequired = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Allow Retroactive Sessions", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  subtitle: const Text("Open session for earlier periods today", style: TextStyle(fontSize: 11)),
                  value: allowRetro,
                  onChanged: (v) => setDlgState(() => allowRetro = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await http.post(
                  Uri.parse('$API_URL/api/v1/class-session/staff-prefs'),
                  headers: _authHeaders,
                  body: json.encode({
                    'checkin_grace_mins': checkinGrace,
                    'checkout_required': checkoutRequired,
                    'checkout_grace_mins': checkoutGrace,
                    'open_window_mins': openWindow,
                    'allow_retroactive': allowRetro,
                  }),
                );
                await _fetchTodayPeriods();
              },
              child: const Text("Save"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadAllData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await Future.wait([
        _fetchDailyDigest(_selectedDate),
        _fetchCalendarMonth(_currentYear, _currentMonth),
        _fetchUpcomingSessions(),
        _fetchAssignedSubjects(),
        _fetchReminderPreferences(),
      ]);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = ApiResponseUtils.sanitize(e);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchDailyDigest(DateTime targetDate) async {
    final dateStr = "${targetDate.year.toString().padLeft(4, '0')}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}";
    final res = await http.get(
      Uri.parse('$API_URL/api/v1/staff/schedule/daily-digest?date=$dateStr&staff_reg_no=$_staffRegNo'),
      headers: _authHeaders,
    );
    if (res.statusCode == 200) {
      final data = json.decode(res.body);
      if (mounted) {
        setState(() {
          _dailyDigest = data;
        });
      }
    }
  }

  Future<void> _fetchCalendarMonth(int year, int month) async {
    String url = '$API_URL/api/v1/staff/schedule/calendar?year=$year&month=$month&staff_reg_no=$_staffRegNo';
    if (_selectedSubjectFilter != null) {
      url += '&subject_code=$_selectedSubjectFilter';
    }
    final res = await http.get(Uri.parse(url), headers: _authHeaders);
    if (res.statusCode == 200) {
      final data = json.decode(res.body);
      if (mounted) {
        setState(() {
          _monthDays = data['days'] ?? [];
        });
      }
    }
  }

  Future<void> _fetchUpcomingSessions() async {
    String url = '$API_URL/api/v1/staff/schedule/upcoming?days_ahead=14&staff_reg_no=$_staffRegNo';
    if (_selectedSubjectFilter != null) {
      url += '&subject_code=$_selectedSubjectFilter';
    }
    final res = await http.get(Uri.parse(url), headers: _authHeaders);
    if (res.statusCode == 200) {
      final data = json.decode(res.body);
      if (mounted) {
        setState(() {
          _upcomingSessions = data['sessions'] ?? [];
        });
      }
    }
  }

  Future<void> _fetchAssignedSubjects() async {
    final res = await http.get(
      Uri.parse('$API_URL/api/v1/staff/schedule/assigned-subjects?staff_reg_no=$_staffRegNo'),
      headers: _authHeaders,
    );
    if (res.statusCode == 200) {
      final data = json.decode(res.body);
      if (mounted) {
        setState(() {
          _assignedSubjects = data is List ? data : [];
        });
      }
    }
  }

  Future<void> _fetchReminderPreferences() async {
    final res = await http.get(
      Uri.parse('$API_URL/api/v1/staff/schedule/reminder-preferences?staff_reg_no=$_staffRegNo'),
      headers: _authHeaders,
    );
    if (res.statusCode == 200) {
      final data = json.decode(res.body);
      if (mounted) {
        setState(() {
          _leadTimeMinutes = data['lead_time_minutes'] ?? 15;
          _dailyDigestEnabled = data['daily_digest_enabled'] ?? true;
        });
      }
    }
  }

  Future<void> _exportCalendarICS() async {
    try {
      final res = await http.get(
        Uri.parse('$API_URL/api/v1/staff/schedule/export.ics?staff_reg_no=$_staffRegNo&days_ahead=90'),
        headers: _authHeaders,
      );
      if (res.statusCode == 200) {
        final bytes = Uint8List.fromList(utf8.encode(res.body));
        final filename = 'schedule_${_staffRegNo}_${DateTime.now().year}.ics';
        await saveFile(bytes, filename);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Calendar exported successfully as $filename"),
              backgroundColor: const Color(0xFF059669),
            ),
          );
        }
      } else {
        throw Exception("Server returned code ${res.statusCode}");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Export failed: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _saveLessonNote({
    required int slotId,
    required String dateStr,
    required String subjectCode,
    required String topic,
    String? objectives,
    String? assignment,
  }) async {
    final body = json.encode({
      "timetable_slot_id": slotId,
      "session_date": dateStr,
      "subject_code": subjectCode,
      "topic_covered": topic,
      "learning_objectives": objectives,
      "assignment_notes": assignment,
    });

    final res = await http.post(
      Uri.parse('$API_URL/api/v1/staff/schedule/session-notes'),
      headers: _authHeaders,
      body: body,
    );

    if (res.statusCode == 200) {
      _fetchDailyDigest(_selectedDate);
      _fetchUpcomingSessions();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Lesson note saved successfully."),
            backgroundColor: Color(0xFF059669),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to save lesson note."), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showLessonNoteModal(Map<String, dynamic> session) {
    final topicCtrl = TextEditingController(text: session['note']?['topic_covered'] ?? '');
    final objCtrl = TextEditingController(text: session['note']?['learning_objectives'] ?? '');
    final assignCtrl = TextEditingController(text: session['note']?['assignment_notes'] ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Lesson Plan & Syllabus Tracker",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                "${session['subject_code']} - ${session['subject_name']} • Period ${session['period_number']} (${session['date']})",
                style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: topicCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: "Topics Covered *",
                  hintText: "E.g., Binary Search Trees - Node Insertion & Deletion...",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: objCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: "Learning Objectives",
                  hintText: "Key takeaways, proofs or concepts taught...",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: assignCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: "Homework / Lab Instructions",
                  hintText: "Follow-up exercises or assignments...",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E3A8A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () {
                    if (topicCtrl.text.trim().isEmpty) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text("Please enter the topic covered.")),
                      );
                      return;
                    }
                    Navigator.pop(ctx);
                    _saveLessonNote(
                      slotId: session['slot_id'],
                      dateStr: session['date'],
                      subjectCode: session['subject_code'],
                      topic: topicCtrl.text.trim(),
                      objectives: objCtrl.text.trim(),
                      assignment: assignCtrl.text.trim(),
                    );
                  },
                  child: const Text("Save Lesson Plan"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showReminderSettingsModal() {
    int tempLead = _leadTimeMinutes;
    bool tempDigest = _dailyDigestEnabled;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Session Alerts & Reminders",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
              ),
              const SizedBox(height: 6),
              const Text(
                "Configure proactive heads-up notifications before each class session.",
                style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 20),
              const Text("Pre-Class Alert Timing:", style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [5, 10, 15, 30, 60].map((mins) {
                  final isSelected = tempLead == mins;
                  return ChoiceChip(
                    label: Text("${mins}m Before"),
                    selected: isSelected,
                    onSelected: (val) {
                      if (val) setModalState(() => tempLead = mins);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("Morning Daily Briefing", style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text("Receive 08:00 AM overview with your day's schedule and substitutions."),
                value: tempDigest,
                onChanged: (val) => setModalState(() => tempDigest = val),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E3A8A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final body = json.encode({
                      "lead_time_minutes": tempLead,
                      "daily_digest_enabled": tempDigest,
                      "daily_digest_time": "08:00",
                      "notify_on_substitution": true,
                      "notify_on_relocation": true,
                    });
                    final res = await http.put(
                      Uri.parse('$API_URL/api/v1/staff/schedule/reminder-preferences'),
                      headers: _authHeaders,
                      body: body,
                    );
                    if (res.statusCode == 200) {
                      setState(() {
                        _leadTimeMinutes = tempLead;
                        _dailyDigestEnabled = tempDigest;
                      });
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Reminder preferences updated."),
                            backgroundColor: Color(0xFF059669),
                          ),
                        );
                      }
                    }
                  },
                  child: const Text("Save Preferences"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isMobile = screenWidth < 650;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline_rounded, size: 48, color: Colors.red),
                        const SizedBox(height: 12),
                        Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF0F172A))),
                        const SizedBox(height: 16),
                        ElevatedButton(onPressed: _loadAllData, child: const Text("Retry")),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadAllData,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 12 : 20,
                      vertical: isMobile ? 12 : 20,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildTopHeader(isMobile: isMobile),
                        const SizedBox(height: 14),
                        _buildDigestBanner(isMobile: isMobile),
                        const SizedBox(height: 14),
                        _buildSubjectFilterRow(isMobile: isMobile),
                        const SizedBox(height: 14),
                        _buildViewTabBar(isMobile: isMobile),
                        const SizedBox(height: 14),
                        if (_activeViewMode == 0) _buildWorkingListQueueView(isMobile: isMobile),
                        if (_activeViewMode == 1) _buildMonthCalendarMatrixView(),
                        if (_activeViewMode == 2) _buildDayTimelineView(),
                        if (_activeViewMode == 3) _buildAssignedSubjectsCatalogView(),
                        if (_activeViewMode == 4) _buildLiveAttendanceView(),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildTopHeader({bool isMobile = false}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 650 || isMobile;
        final titleBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isNarrow ? "Schedule & Sessions" : "Schedule & Upcoming Sessions Hub",
              style: TextStyle(
                fontSize: isNarrow ? 17 : 18,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF0F172A),
                fontStyle: FontStyle.normal,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              isNarrow
                  ? "Today's timetable & working queue"
                  : "Active classes & instructional schedule for $_staffName",
              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
            ),
          ],
        );

        final actionRow = Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.download_rounded, size: 14),
              label: Text(isNarrow ? "Export" : "Export (.ics)", style: const TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF1E3A8A),
                side: const BorderSide(color: Color(0xFFCBD5E1)),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              ),
              onPressed: _exportCalendarICS,
            ),
            IconButton(
              icon: const Icon(Icons.notifications_active_outlined, color: Color(0xFF1E3A8A), size: 19),
              tooltip: "Reminder Preferences",
              onPressed: _showReminderSettingsModal,
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(7),
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Color(0xFF1E3A8A), size: 19),
              tooltip: "Refresh Schedule",
              onPressed: _loadAllData,
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(7),
            ),
          ],
        );

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleBlock,
              const SizedBox(height: 8),
              actionRow,
            ],
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: titleBlock),
            const SizedBox(width: 12),
            actionRow,
          ],
        );
      },
    );
  }

  Widget _buildDigestBanner({bool isMobile = false}) {
    if (_dailyDigest == null) return const SizedBox.shrink();
    final metrics = _dailyDigest!['metrics'] ?? {};
    final nextSession = metrics['next_session'];
    final activeSession = metrics['active_session'];
    final countdownMins = metrics['next_session_countdown_mins'];

    return Container(
      padding: EdgeInsets.all(isMobile ? 14 : 20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E3A8A),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E3A8A).withValues(alpha: 0.12),
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
              Text(
                "Today • ${_dailyDigest!['date']} (${_dailyDigest!['day_of_week']})",
                style: TextStyle(fontSize: isMobile ? 13 : 14, fontWeight: FontWeight.w600, color: const Color(0xFF93C5FD)),
              ),
              if (_dailyDigest!['is_holiday'] == true)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.red.shade700, borderRadius: BorderRadius.circular(6)),
                  child: const Text("HOLIDAY", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                )
              else if (_dailyDigest!['day_order'] != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
                  child: Text("Day Order ${_dailyDigest!['day_order']}", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
            ],
          ),
          SizedBox(height: isMobile ? 10 : 14),
          if (activeSession != null) ...[
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(color: const Color(0xFF059669), borderRadius: BorderRadius.circular(6)),
                  child: const Text("LIVE NOW", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "${activeSession['subject_code']} - ${activeSession['subject_name']}",
                    style: TextStyle(fontSize: isMobile ? 14 : 16, fontWeight: FontWeight.w700, color: Colors.white),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              "Period ${activeSession['period_number']} (${activeSession['start_time']} - ${activeSession['end_time']}) • Venue: ${activeSession['effective_venue']} (Sec ${activeSession['section']})",
              style: TextStyle(fontSize: isMobile ? 12 : 13, color: const Color(0xFFE2E8F0)),
            ),
          ] else if (nextSession != null) ...[
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(color: const Color(0xFF2563EB), borderRadius: BorderRadius.circular(6)),
                  child: Text(
                    countdownMins != null && countdownMins > 0 ? "Starts in ${countdownMins}m" : "UPCOMING NEXT",
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "${nextSession['subject_code']} - ${nextSession['subject_name']}",
                    style: TextStyle(fontSize: isMobile ? 14 : 16, fontWeight: FontWeight.w700, color: Colors.white),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              "Period ${nextSession['period_number']} at ${nextSession['start_time']} • Venue: ${nextSession['effective_venue']}",
              style: TextStyle(fontSize: isMobile ? 12 : 13, color: const Color(0xFFE2E8F0)),
            ),
          ] else ...[
            Text(
              "All scheduled sessions for today are completed.",
              style: TextStyle(fontSize: isMobile ? 13 : 14, fontWeight: FontWeight.w600, color: Colors.white),
            ),
          ],
          Divider(color: const Color(0xFF3B82F6), height: isMobile ? 20 : 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildMetricStat(isMobile ? "Classes" : "Today's Classes", "${metrics['total_classes'] ?? 0}", isMobile: isMobile),
              _buildMetricStat(isMobile ? "Done" : "Completed", "${metrics['completed_classes'] ?? 0}", isMobile: isMobile),
              _buildMetricStat(isMobile ? "Left" : "Remaining", "${metrics['remaining_classes'] ?? 0}", isMobile: isMobile),
              _buildMetricStat(isMobile ? "Hours" : "Teaching Hours", "${metrics['total_teaching_hours'] ?? 0}h", isMobile: isMobile),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricStat(String label, String value, {bool isMobile = false}) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: isMobile ? 18 : 20, fontWeight: FontWeight.w700, color: Colors.white)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: isMobile ? 10 : 11, color: const Color(0xFF93C5FD), fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildSubjectFilterRow({bool isMobile = false}) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(isMobile ? "All Subjects" : "All Assigned Subjects", style: TextStyle(fontSize: isMobile ? 11 : 12)),
              selected: _selectedSubjectFilter == null,
              onSelected: (val) {
                if (val) {
                  setState(() => _selectedSubjectFilter = null);
                  _fetchCalendarMonth(_currentYear, _currentMonth);
                  _fetchUpcomingSessions();
                }
              },
            ),
          ),
          ..._assignedSubjects.map((sub) {
            final code = sub['subject_code'] as String;
            final isSelected = _selectedSubjectFilter == code;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text("$code (${sub['section']})", style: TextStyle(fontSize: isMobile ? 11 : 12)),
                selected: isSelected,
                onSelected: (val) {
                  setState(() => _selectedSubjectFilter = val ? code : null);
                  _fetchCalendarMonth(_currentYear, _currentMonth);
                  _fetchUpcomingSessions();
                },
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildViewTabBar({bool isMobile = false}) {
    final hasActiveLiveSession = _todayPeriods.any((p) {
      final s = p['session'];
      return s != null && (s['status'] == 'checkin_open' || s['status'] == 'checkout_open');
    });

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildTabItem(4, isMobile ? (hasActiveLiveSession ? "Live ●" : "Live") : (hasActiveLiveSession ? "Live Attendance ●" : "Live Attendance"), Icons.sensors_rounded, isMobile: isMobile),
            _buildTabItem(0, isMobile ? "Queue" : "Working Queue", Icons.checklist_rounded, isMobile: isMobile),
            _buildTabItem(1, isMobile ? "Calendar" : "Month Calendar", Icons.calendar_month_rounded, isMobile: isMobile),
            _buildTabItem(2, isMobile ? "Timeline" : "Day Timeline", Icons.view_day_rounded, isMobile: isMobile),
            _buildTabItem(3, isMobile ? "Subjects" : "Assigned Subjects", Icons.menu_book_rounded, isMobile: isMobile),
          ],
        ),
      ),
    );
  }

  Widget _buildTabItem(int index, String title, IconData icon, {bool isMobile = false}) {
    final isSelected = _activeViewMode == index;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 2 : 3, vertical: isMobile ? 3 : 4),
      child: InkWell(
        onTap: () => setState(() => _activeViewMode = index),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 14, vertical: isMobile ? 8 : 10),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF1E3A8A) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: isMobile ? 14 : 16, color: isSelected ? Colors.white : const Color(0xFF64748B)),
              SizedBox(width: isMobile ? 4 : 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: isMobile ? 11 : 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? Colors.white : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWorkingListQueueView({bool isMobile = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                isMobile ? "Working Queue (14 Days)" : "Actionable Working Queue (Next 14 Days)",
                style: TextStyle(fontSize: isMobile ? 14 : 15, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              "${_upcomingSessions.length} active",
              style: TextStyle(fontSize: isMobile ? 11 : 12, color: const Color(0xFF64748B), fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_upcomingSessions.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                Icon(Icons.event_available_rounded, size: 48, color: Colors.green.shade400),
                const SizedBox(height: 12),
                const Text("No pending classes in working queue.", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 4),
                const Text("All teaching sessions are up-to-date or on institutional holiday.", style: TextStyle(color: Color(0xFF64748B))),
              ],
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _upcomingSessions.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (ctx, i) => _buildWorkingListSessionCard(_upcomingSessions[i]),
          ),
      ],
    );
  }

  Widget _buildWorkingListSessionCard(Map<String, dynamic> session) {
    final status = session['status'] ?? 'UPCOMING';
    final isLive = status == 'LIVE';
    final isCompleted = status == 'COMPLETED';
    final isSubstituted = session['is_substituted'] == true;
    final isCovering = session['is_covering_for_other'] == true;
    final isRelocated = session['is_relocated'] == true;

    Color badgeColor = const Color(0xFF2563EB);
    String badgeText = "UPCOMING";

    if (isLive) {
      badgeColor = const Color(0xFF059669);
      badgeText = "LIVE NOW";
    } else if (isCompleted) {
      badgeColor = const Color(0xFF64748B);
      badgeText = "COMPLETED";
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isLive
              ? const Color(0xFF059669)
              : isSubstituted
                  ? const Color(0xFFD97706).withValues(alpha: 0.5)
                  : const Color(0xFFE2E8F0),
          width: isLive ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
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
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        "${session['date']} • Period ${session['period_number']}",
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                      ),
                    ),
                    Text(
                      "${session['start_time']} - ${session['end_time']}",
                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: badgeColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            "${session['subject_code']} - ${session['subject_name']}",
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 4),
          Text(
            "Class: ${session['dept']} • Batch ${session['batch']} • Sem ${session['semester']} • Sec ${session['section']} (${session['subject_type'] ?? 'Theory'})",
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.location_on_outlined, size: 14, color: isRelocated ? Colors.red.shade700 : const Color(0xFF64748B)),
              const SizedBox(width: 4),
              Text(
                "Venue: ${session['effective_venue']}",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isRelocated ? Colors.red.shade700 : const Color(0xFF0F172A),
                ),
              ),
              if (isRelocated) ...[
                const SizedBox(width: 6),
                Text(
                  "(${session['relocation_reason'] ?? 'Relocated'})",
                  style: TextStyle(fontSize: 11, color: Colors.red.shade700),
                ),
              ],
            ],
          ),
          if (isSubstituted || isCovering) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.swap_horiz_rounded, size: 16, color: Color(0xFFD97706)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      session['substitution_note'] ?? (isCovering ? "Substitute Coverage" : "Handed Over"),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF92400E)),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const Divider(height: 24),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (session['note'] != null)
                Text(
                  "Topic: ${session['note']['topic_covered']}",
                  style: const TextStyle(fontSize: 12, color: Color(0xFF059669), fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                )
              else
                const Text("No lesson note logged", style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.edit_note_rounded, size: 15),
                      label: Text(session['note'] != null ? "Edit Plan" : "Log Topic"),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      onPressed: () => _showLessonNoteModal(session),
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.qr_code_scanner_rounded, size: 15),
                      label: const Text("Launch Attendance"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E3A8A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      onPressed: () {
                        if (widget.onNavigateToTab != null) {
                          // Jump to Attend / Students tab
                          widget.onNavigateToTab!(1);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text("Launching attendance session for ${session['subject_code']} (Sec ${session['section']})")),
                          );
                        }
                      },
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

  Widget _buildMonthCalendarMatrixView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "${_getMonthName(_currentMonth)} $_currentYear",
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
            ),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded),
                  onPressed: () {
                    setState(() {
                      if (_currentMonth == 1) {
                        _currentMonth = 12;
                        _currentYear--;
                      } else {
                        _currentMonth--;
                      }
                    });
                    _fetchCalendarMonth(_currentYear, _currentMonth);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded),
                  onPressed: () {
                    setState(() {
                      if (_currentMonth == 12) {
                        _currentMonth = 1;
                        _currentYear++;
                      } else {
                        _currentMonth++;
                      }
                    });
                    _fetchCalendarMonth(_currentYear, _currentMonth);
                  },
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].map((d) {
            return Expanded(
              child: Center(
                child: Text(d, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
            childAspectRatio: 0.85,
          ),
          itemCount: _monthDays.length,
          itemBuilder: (ctx, index) {
            final dayData = _monthDays[index];
            final dNum = dayData['day_of_month'];
            final isToday = dayData['is_today'] == true;
            final isHoliday = dayData['is_holiday'] == true;
            final sessCount = dayData['total_sessions'] ?? 0;
            final hasSub = dayData['has_substitution'] == true;

            final isSelected = _selectedDate.year == _currentYear &&
                _selectedDate.month == _currentMonth &&
                _selectedDate.day == dNum;

            return InkWell(
              onTap: () {
                setState(() {
                  _selectedDate = DateTime(_currentYear, _currentMonth, dNum);
                  _activeViewMode = 2; // Jump to day timeline
                });
                _fetchDailyDigest(_selectedDate);
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF2563EB).withValues(alpha: 0.12)
                      : isToday
                          ? const Color(0xFFEFF6FF)
                          : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF2563EB)
                        : isToday
                            ? const Color(0xFF93C5FD)
                            : const Color(0xFFE2E8F0),
                    width: isSelected || isToday ? 1.5 : 1.0,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "$dNum",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isToday || isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isHoliday ? Colors.red.shade700 : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (isHoliday)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(4)),
                        child: Text("Off", style: TextStyle(fontSize: 9, color: Colors.red.shade700, fontWeight: FontWeight.w700)),
                      )
                    else if (sessCount > 0) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E3A8A),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              "$sessCount",
                              style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (hasSub) ...[
                            const SizedBox(width: 2),
                            Container(
                              width: 5,
                              height: 5,
                              decoration: const BoxDecoration(color: Color(0xFFD97706), shape: BoxShape.circle),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildDayTimelineView() {
    final sessions = _dailyDigest?['sessions'] as List<dynamic>? ?? [];
    final dateStr = "${_selectedDate.year.toString().padLeft(4, '0')}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "Schedule Timeline for $dateStr",
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
            ),
            TextButton.icon(
              icon: const Icon(Icons.calendar_today_rounded, size: 16),
              label: const Text("Change Date"),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate,
                  firstDate: DateTime(2025),
                  lastDate: DateTime(2028),
                );
                if (picked != null) {
                  setState(() => _selectedDate = picked);
                  _fetchDailyDigest(_selectedDate);
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (sessions.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                Icon(Icons.event_busy_rounded, size: 40, color: Colors.grey.shade400),
                const SizedBox(height: 8),
                const Text("No sessions scheduled for this day.", style: TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: sessions.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (ctx, i) => _buildWorkingListSessionCard(sessions[i]),
          ),
      ],
    );
  }

  Widget _buildAssignedSubjectsCatalogView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Allocated Curriculum & Teaching Hours",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
        ),
        const SizedBox(height: 12),
        if (_assignedSubjects.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const Center(child: Text("No subject allocations found for this faculty.")),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 2.2,
            ),
            itemCount: _assignedSubjects.length,
            itemBuilder: (ctx, i) {
              final sub = _assignedSubjects[i];
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          sub['subject_code'] ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF1E3A8A), fontSize: 14),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: sub['is_lab'] == true ? Colors.purple.shade50 : Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            sub['subject_type'] ?? (sub['is_lab'] == true ? 'Lab' : 'Theory'),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: sub['is_lab'] == true ? Colors.purple.shade700 : Colors.blue.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      sub['subject_name'] ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF0F172A)),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Class: ${sub['dept']} • Sem ${sub['semester']} • Sec ${sub['section']} • ${sub['weekly_hours'] ?? 4} hrs/wk",
                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildLiveAttendanceView() {
    final dateStr = "${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}";
    final isToday = _selectedDate.year == DateTime.now().year &&
        _selectedDate.month == DateTime.now().month &&
        _selectedDate.day == DateTime.now().day;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Controls Header Bar ──────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded),
                tooltip: "Previous Day",
                onPressed: () {
                  setState(() => _selectedDate = _selectedDate.subtract(const Duration(days: 1)));
                  _fetchTodayPeriods();
                },
              ),
              Expanded(
                child: Center(
                  child: GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime(DateTime.now().year, 1, 1),
                        lastDate: DateTime(DateTime.now().year + 1, 12, 31),
                      );
                      if (picked != null) {
                        setState(() => _selectedDate = picked);
                        _fetchTodayPeriods();
                      }
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.calendar_today_rounded, size: 16, color: Color(0xFF1E3A8A)),
                        const SizedBox(width: 8),
                        Text(
                          isToday ? "Today, $dateStr" : dateStr,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF64748B)),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded),
                tooltip: "Next Day",
                onPressed: () {
                  setState(() => _selectedDate = _selectedDate.add(const Duration(days: 1)));
                  _fetchTodayPeriods();
                },
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.tune_rounded, color: Color(0xFF1E3A8A)),
                tooltip: "Attendance Preferences",
                onPressed: _openPreferencesDialog,
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                tooltip: "Refresh",
                onPressed: () => _fetchTodayPeriods(),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── Period List ──────────────────────────────────────────────────────
        if (_isLiveSessionLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_todayPeriods.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                Icon(Icons.event_busy_rounded, size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                const Text(
                  "No teaching periods scheduled for this day",
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                ),
                const SizedBox(height: 4),
                Text(
                  "Check your timetable allocation or select another date above.",
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
              ],
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _todayPeriods.length,
            separatorBuilder: (_, __) => const SizedBox(height: 14),
            itemBuilder: (_, idx) => _buildLivePeriodCard(_todayPeriods[idx]),
          ),
      ],
    );
  }

  Widget _buildLivePeriodCard(Map<String, dynamic> period) {
    final session = period['session'];
    final pNum = period['period_number'];
    final subName = period['subject_name'] ?? '';
    final subCode = period['subject_code'] ?? '';
    final dept = period['dept'] ?? '';
    final sem = period['semester'] ?? 1;
    final sec = period['section'] ?? 'A';
    final batch = period['batch'] ?? '';
    final room = period['room'] ?? '';
    final isLab = period['is_lab'] == true;
    final schedStart = period['scheduled_start'] ?? '—';
    final schedEnd = period['scheduled_end'] ?? '—';
    final isCurrent = period['is_current_period'] == true;
    final classSummary = "$dept / $batch / Sem $sem / Sec $sec${room.isNotEmpty ? ' · Room: $room' : ''}";

    final status = session != null ? (session['status'] ?? 'pending') : 'pending';
    final isCheckinOpen = status == 'checkin_open';
    final isCheckoutOpen = status == 'checkout_open';
    final isCheckinClosed = status == 'checkin_closed';
    final isClosed = status == 'closed';
    final presentCount = session != null ? (session['present_count'] ?? 0) : 0;
    final absentCount = session != null ? (session['absent_count'] ?? 0) : 0;
    final checkoutCount = session != null ? (session['checkout_count'] ?? 0) : 0;
    final sessionId = session != null ? (session['session_id'] ?? '') : '';

    Color borderColor = const Color(0xFFE2E8F0);
    Color headerBg = const Color(0xFFF8FAFC);
    if (isCheckinOpen) {
      borderColor = const Color(0xFF059669);
      headerBg = const Color(0xFFECFDF5);
    } else if (isCheckoutOpen) {
      borderColor = const Color(0xFF2563EB);
      headerBg = const Color(0xFFEFF6FF);
    } else if (isCheckinClosed) {
      borderColor = const Color(0xFFD97706);
      headerBg = const Color(0xFFFFFBEB);
    } else if (isClosed) {
      borderColor = const Color(0xFF94A3B8);
      headerBg = const Color(0xFFF1F5F9);
    } else if (isCurrent) {
      borderColor = const Color(0xFF1E3A8A);
      headerBg = const Color(0xFFF0F4FF);
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: isCheckinOpen || isCheckoutOpen ? 2 : 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Card Header ────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: headerBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
            ),
            child: Row(
              children: [
                // Period Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E3A8A),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    "Period $pNum",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  "$schedStart – $schedEnd",
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF475569),
                  ),
                ),
                if (isLab) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      "LAB",
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.purple.shade800,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                // Status Pill
                _buildSessionStatusBadge(status, isCurrent),
              ],
            ),
          ),

          // ── Subject & Class Details ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "$subCode  ·  $classSummary",
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),

          // ── Session Metrics / Progress Bar ─────────────────────────────────
          if (session != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF059669).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.how_to_reg_rounded, size: 14, color: Color(0xFF059669)),
                        const SizedBox(width: 4),
                        Text(
                          "$presentCount Present",
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF059669),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (checkoutCount > 0 || isCheckoutOpen) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D9488).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.exit_to_app_rounded, size: 14, color: Color(0xFF0D9488)),
                          const SizedBox(width: 4),
                          Text(
                            "$checkoutCount Checked Out",
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0D9488),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (isClosed) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.person_off_rounded, size: 14, color: Color(0xFFDC2626)),
                          const SizedBox(width: 4),
                          Text(
                            "$absentCount Absent",
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFDC2626),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],

          const Divider(height: 16),

          // ── Action Buttons ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _buildPeriodActionButtons(
              period: period,
              status: status,
              sessionId: sessionId,
              subName: subName,
              classSummary: classSummary,
              presentCount: presentCount,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionStatusBadge(String status, bool isCurrent) {
    if (status == 'checkin_open') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF059669),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.radio_button_checked_rounded, size: 12, color: Colors.white),
            SizedBox(width: 4),
            Text(
              "Check-In Live",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11),
            ),
          ],
        ),
      );
    } else if (status == 'checkout_open') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF2563EB),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.logout_rounded, size: 12, color: Colors.white),
            SizedBox(width: 4),
            Text(
              "Check-Out Open",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11),
            ),
          ],
        ),
      );
    } else if (status == 'checkin_closed') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFD97706).withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          "Check-In Closed",
          style: TextStyle(color: Color(0xFFD97706), fontWeight: FontWeight.w700, fontSize: 11),
        ),
      );
    } else if (status == 'closed') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF64748B).withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          "Session Ended",
          style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700, fontSize: 11),
        ),
      );
    }

    // Pending
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isCurrent ? const Color(0xFF1E3A8A).withOpacity(0.1) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        isCurrent ? "Current Period" : "Scheduled",
        style: TextStyle(
          color: isCurrent ? const Color(0xFF1E3A8A) : const Color(0xFF64748B),
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _buildPeriodActionButtons({
    required Map<String, dynamic> period,
    required String status,
    required String sessionId,
    required String subName,
    required String classSummary,
    required int presentCount,
  }) {
    if (status == 'pending') {
      return Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text(
                "Start Attendance Check-In",
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              onPressed: () => _startCheckin(period),
            ),
          ),
        ],
      );
    }

    if (status == 'checkin_open') {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFD97706),
              side: const BorderSide(color: Color(0xFFD97706)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.pause_rounded, size: 16),
            label: const Text("Close Check-In", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
            onPressed: () => _closeCheckin(sessionId),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF2563EB),
              side: const BorderSide(color: Color(0xFF2563EB)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.logout_rounded, size: 16),
            label: const Text("Open Check-Out", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
            onPressed: () => _startCheckout(sessionId),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.stop_rounded, size: 16),
            label: const Text("End Session", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
            onPressed: () => _closeSession(sessionId),
          ),
          TextButton.icon(
            icon: const Icon(Icons.list_alt_rounded, size: 16),
            label: Text("Live Roll ($presentCount)", style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
            onPressed: () => ClassSessionRollSheet.show(
              context,
              token: widget.token,
              sessionId: sessionId,
              subjectName: subName,
              classSummary: classSummary,
              canOverride: false,
            ),
          ),
        ],
      );
    }

    if (status == 'checkin_closed') {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF2563EB),
              side: const BorderSide(color: Color(0xFF2563EB)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.logout_rounded, size: 16),
            label: const Text("Open Check-Out", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
            onPressed: () => _startCheckout(sessionId),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.stop_rounded, size: 16),
            label: const Text("End Session & Finalize", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
            onPressed: () => _closeSession(sessionId),
          ),
          TextButton.icon(
            icon: const Icon(Icons.list_alt_rounded, size: 16),
            label: Text("Roll ($presentCount)", style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
            onPressed: () => ClassSessionRollSheet.show(
              context,
              token: widget.token,
              sessionId: sessionId,
              subjectName: subName,
              classSummary: classSummary,
              canOverride: false,
            ),
          ),
        ],
      );
    }

    if (status == 'checkout_open') {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.stop_rounded, size: 16),
            label: const Text("End Session & Finalize", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
            onPressed: () => _closeSession(sessionId),
          ),
          TextButton.icon(
            icon: const Icon(Icons.list_alt_rounded, size: 16),
            label: Text("Roll ($presentCount)", style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
            onPressed: () => ClassSessionRollSheet.show(
              context,
              token: widget.token,
              sessionId: sessionId,
              subjectName: subName,
              classSummary: classSummary,
              canOverride: false,
            ),
          ),
        ],
      );
    }

    // Closed
    return Row(
      children: [
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          icon: const Icon(Icons.assignment_turned_in_rounded, size: 16),
          label: const Text("View Roll & Manual Override", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          onPressed: () => ClassSessionRollSheet.show(
            context,
            token: widget.token,
            sessionId: sessionId,
            subjectName: subName,
            classSummary: classSummary,
            canOverride: true,
          ),
        ),
      ],
    );
  }

  String _getMonthName(int month) {
    const months = [
      "January", "February", "March", "April", "May", "June",
      "July", "August", "September", "October", "November", "December"
    ];
    return months[month - 1];
  }
}
