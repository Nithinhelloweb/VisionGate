import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../../config/college_ip_config.dart';
import '../../theme/admin_theme.dart';
import 'class_advisor_card.dart';
import 'date_timetable_view.dart';
import 'day_management_dialog.dart';
import 'period_config_dialog.dart';
import 'period_timing_helper.dart';
import 'subject_allocation_view.dart';
import 'subject_management_view.dart';
import 'timetable_grid_view.dart';
import 'weekly_timetable_builder_dialog.dart';

class AcademicScheduleTab extends StatefulWidget {
  final String token;
  final String userRole; // 'admin' or 'hod'
  final String userDept;

  const AcademicScheduleTab({
    super.key,
    required this.token,
    required this.userRole,
    required this.userDept,
  });

  @override
  State<AcademicScheduleTab> createState() => _AcademicScheduleTabState();
}

class _YearConfig {
  final int year;
  final String title;
  final String batch;
  final List<int> semesters;

  const _YearConfig({
    required this.year,
    required this.title,
    required this.batch,
    required this.semesters,
  });
}

class _AcademicScheduleTabState extends State<AcademicScheduleTab> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  late String _selectedDept;
  int _selectedYearIndex = 2; // Default 3rd Year
  String _selectedBatch = '2022-2026';
  int _selectedSemester = 6;
  String _selectedSection = 'A';

  bool _isLoading = true;
  List<PeriodSlotTiming> _timeline = [];
  List<Map<String, dynamic>> _slots = [];
  List<Map<String, dynamic>> _facultyPool = [];
  List<String> _availableDepartments = [];
  List<Map<String, dynamic>> _subjectAllocations = [];
  List<String> _workingDays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];

  final List<_YearConfig> _yearConfigs = const [
    _YearConfig(year: 1, title: '1st Year', batch: '2024-2028', semesters: [1, 2]),
    _YearConfig(year: 2, title: '2nd Year', batch: '2023-2027', semesters: [3, 4]),
    _YearConfig(year: 3, title: '3rd Year', batch: '2022-2026', semesters: [5, 6]),
    _YearConfig(year: 4, title: '4th Year', batch: '2021-2025', semesters: [7, 8]),
  ];

  final List<String> _sections = ['A', 'B', 'C', 'D'];
  final List<String> _departments = ['CSE', 'ECE', 'EEE', 'MECH', 'CIVIL', 'IT', 'AI & ML', 'Data Science'];

  int _selectedTabIndex = 0;

  bool get _isHod => widget.userRole.toLowerCase().contains('hod');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _selectedDept = (_isHod && widget.userDept.isNotEmpty) ? widget.userDept : 'CSE';
    _loadAllData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _onYearSelected(int index) {
    final cfg = _yearConfigs[index];
    setState(() {
      _selectedYearIndex = index;
      _selectedBatch = cfg.batch;
      // Default to the even semester (e.g. Sem 6 for 3rd Year) or the first
      _selectedSemester = cfg.semesters.last;
    });
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    try {
      // 1. Load timetable and computed timeline
      final uriTt = Uri.parse(
        '${CollegeIPConfig.defaultURL}/api/v1/academics/timetable?dept=${Uri.encodeComponent(_selectedDept)}&batch=${Uri.encodeComponent(_selectedBatch)}&semester=$_selectedSemester&section=${Uri.encodeComponent(_selectedSection)}',
      );
      final resTt = await http.get(uriTt, headers: {'Authorization': 'Bearer ${widget.token}'});
      if (resTt.statusCode == 200) {
        final data = jsonDecode(resTt.body);
        _slots = List<Map<String, dynamic>>.from(data['slots'] ?? []);
        final rawTimeline = (data['timeline'] as List? ?? []);
        _timeline = rawTimeline.map((t) => PeriodSlotTiming.fromJson(Map<String, dynamic>.from(t))).toList();
        final rawDays = (data['period_config']?['working_days'] as List? ?? []);
        if (rawDays.isNotEmpty) {
          _workingDays = rawDays.map((d) => d.toString()).toList();
        }
      }

      // 2. Load faculty pool across all departments
      final uriFac = Uri.parse(
        '${CollegeIPConfig.defaultURL}/api/v1/academics/faculty-pool?include_all_depts=true',
      );
      final resFac = await http.get(uriFac, headers: {'Authorization': 'Bearer ${widget.token}'});
      if (resFac.statusCode == 200) {
        final data = jsonDecode(resFac.body);
        _facultyPool = List<Map<String, dynamic>>.from(data['faculty'] ?? []);
        _availableDepartments = List<String>.from(data['departments'] ?? _departments);
      }

      // 3. Load subject allocations
      final uriAlloc = Uri.parse(
        '${CollegeIPConfig.defaultURL}/api/v1/academics/subject-allocations?dept=${Uri.encodeComponent(_selectedDept)}&batch=${Uri.encodeComponent(_selectedBatch)}&semester=$_selectedSemester&section=${Uri.encodeComponent(_selectedSection)}',
      );
      final resAlloc = await http.get(uriAlloc, headers: {'Authorization': 'Bearer ${widget.token}'});
      if (resAlloc.statusCode == 200) {
        final data = jsonDecode(resAlloc.body);
        _subjectAllocations = List<Map<String, dynamic>>.from(data['allocations'] ?? []);
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  void _openBatchPromotionDialog() {
    int targetYear = (_selectedYearIndex + 1).clamp(1, 4);
    int targetSem = (_selectedSemester + 1).clamp(1, 8);
    bool isProcessing = false;
    Map<String, dynamic>? dryRunResult;
    String? statusMsg;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.teal.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.upgrade_rounded, color: Colors.teal, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Semester Batch Promotion', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold)),
                      Text('$_selectedDept • Batch $_selectedBatch', style: GoogleFonts.inter(fontSize: 12, color: Colors.teal)),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Promote all students of batch $_selectedBatch in $_selectedDept to the next semester or academic year level.',
                      style: GoogleFonts.inter(fontSize: 12.5, color: AdminColors.getTextSecondary(isDark)),
                    ),
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, dlgConstraints) {
                        final isCompact = dlgConstraints.maxWidth < 420;

                        final yearField = DropdownButtonFormField<int>(
                          initialValue: targetYear,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'Target Year of Study',
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          items: const [
                            DropdownMenuItem(value: 1, child: Text('1st Year')),
                            DropdownMenuItem(value: 2, child: Text('2nd Year')),
                            DropdownMenuItem(value: 3, child: Text('3rd Year')),
                            DropdownMenuItem(value: 4, child: Text('4th Year (Final)')),
                          ],
                          onChanged: (v) => setDlgState(() => targetYear = v ?? targetYear),
                        );

                        final semField = DropdownButtonFormField<int>(
                          initialValue: targetSem,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'Target Semester',
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          items: List.generate(8, (i) => i + 1)
                              .map((s) => DropdownMenuItem(value: s, child: Text('Semester $s')))
                              .toList(),
                          onChanged: (v) => setDlgState(() => targetSem = v ?? targetSem),
                        );

                        if (isCompact) {
                          return Column(
                            children: [
                              yearField,
                              const SizedBox(height: 12),
                              semField,
                            ],
                          );
                        }

                        return Row(
                          children: [
                            Expanded(child: yearField),
                            const SizedBox(width: 12),
                            Expanded(child: semField),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    if (dryRunResult != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.teal.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.teal.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '✓ Eligible Students: ${dryRunResult!['eligible_students_count'] ?? 0}',
                              style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.teal),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Target: Year $targetYear, Semester $targetSem (Dept: $_selectedDept)',
                              style: GoogleFonts.inter(fontSize: 11.5),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (statusMsg != null)
                      Text(statusMsg!, style: GoogleFonts.inter(fontSize: 12, color: statusMsg!.contains('Success') ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Close', style: GoogleFonts.inter(color: AdminColors.getTextSecondary(isDark))),
              ),
              OutlinedButton(
                onPressed: isProcessing
                    ? null
                    : () async {
                        setDlgState(() {
                          isProcessing = true;
                          statusMsg = null;
                        });
                        try {
                          final res = await http.post(
                            Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/hod/student-academics/batches/promote'),
                            headers: {'Authorization': 'Bearer ${widget.token}', 'Content-Type': 'application/json'},
                            body: jsonEncode({
                              'batch': _selectedBatch,
                              'target_year': targetYear,
                              'target_semester': targetSem,
                              'dept': _selectedDept,
                              'dry_run': true,
                            }),
                          );
                          if (res.statusCode == 200) {
                            final d = jsonDecode(res.body);
                            setDlgState(() => dryRunResult = d);
                          } else {
                            setDlgState(() => statusMsg = 'Preview failed: ${res.body}');
                          }
                        } catch (e) {
                          setDlgState(() => statusMsg = 'Error: $e');
                        } finally {
                          setDlgState(() => isProcessing = false);
                        }
                      },
                child: const Text('Verify / Preview'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                onPressed: (isProcessing || dryRunResult == null)
                    ? null
                    : () async {
                        setDlgState(() {
                          isProcessing = true;
                          statusMsg = null;
                        });
                        try {
                          final res = await http.post(
                            Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/hod/student-academics/batches/promote'),
                            headers: {'Authorization': 'Bearer ${widget.token}', 'Content-Type': 'application/json'},
                            body: jsonEncode({
                              'batch': _selectedBatch,
                              'target_year': targetYear,
                              'target_semester': targetSem,
                              'dept': _selectedDept,
                              'dry_run': false,
                            }),
                          );
                          if (res.statusCode == 200) {
                            setDlgState(() => statusMsg = 'Successfully promoted students!');
                            _loadAllData();
                          } else {
                            setDlgState(() => statusMsg = 'Promotion failed: ${res.body}');
                          }
                        } catch (e) {
                          setDlgState(() => statusMsg = 'Error: $e');
                        } finally {
                          setDlgState(() => isProcessing = false);
                        }
                      },
                child: isProcessing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Execute Promotion'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openPeriodConfigDialog() {
    showDialog(
      context: context,
      builder: (ctx) => PeriodConfigDialog(
        token: widget.token,
        dept: _selectedDept,
        batch: _selectedBatch,
        semester: _selectedSemester,
        section: _selectedSection,
        onSaved: _loadAllData,
      ),
    );
  }

  void _openDayManagementDialog() {
    showDialog(
      context: context,
      builder: (ctx) => DayManagementDialog(
        token: widget.token,
        dept: _selectedDept,
        batch: _selectedBatch,
        semester: _selectedSemester,
        section: _selectedSection,
        currentWorkingDays: _workingDays,
        onUpdated: _loadAllData,
      ),
    );
  }

  void _openWeeklyBuilderDialog() {
    showDialog(
      context: context,
      builder: (ctx) => WeeklyTimetableBuilderDialog(
        token: widget.token,
        dept: _selectedDept,
        batch: _selectedBatch,
        semester: _selectedSemester,
        section: _selectedSection,
        onSaved: _loadAllData,
      ),
    );
  }

  void _openCopyTimetableDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    String srcSection = _selectedSection;
    String dstSection = _selectedSection == 'A' ? 'B' : 'A';
    bool copyAllocs = true;
    bool isCopying = false;
    String? copyStatus;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: AdminColors.getCard(isDark),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: AdminColors.primarySoft, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.copy_all_rounded, color: AdminColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Clone Timetable Matrix', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AdminColors.getTextPrimary(isDark))),
                  Text('Duplicate schedule to another class section', style: GoogleFonts.inter(fontSize: 12, color: AdminColors.getTextSecondary(isDark))),
                ],
              ),
            ],
          ),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AdminColors.getBorder(isDark)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('SOURCE CLASS', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: AdminColors.getTextMuted(isDark))),
                            const SizedBox(height: 4),
                            Text('$_selectedDept • Sem $_selectedSemester', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 6),
                            DropdownButton<String>(
                              value: srcSection,
                              isDense: true,
                              underline: const SizedBox(),
                              items: _sections.map((s) => DropdownMenuItem(value: s, child: Text('Section $s', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)))).toList(),
                              onChanged: (v) => setDlgState(() => srcSection = v ?? 'A'),
                            ),
                          ],
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(Icons.arrow_forward_rounded, color: AdminColors.primary),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('TARGET CLASS', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: AdminColors.getTextMuted(isDark))),
                            const SizedBox(height: 4),
                            Text('$_selectedDept • Sem $_selectedSemester', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 6),
                            DropdownButton<String>(
                              value: dstSection,
                              isDense: true,
                              underline: const SizedBox(),
                              items: _sections.map((s) => DropdownMenuItem(value: s, child: Text('Section $s', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)))).toList(),
                              onChanged: (v) => setDlgState(() => dstSection = v ?? 'B'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  title: Text('Also clone Subject Allocations & Faculty Mappings', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                  value: copyAllocs,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) => setDlgState(() => copyAllocs = v ?? true),
                ),
                if (srcSection == dstSection)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Source and target sections cannot be the same.', style: GoogleFonts.inter(fontSize: 11, color: AdminColors.danger, fontWeight: FontWeight.w600)),
                  ),
                if (copyStatus != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(copyStatus!, style: GoogleFonts.inter(fontSize: 11, color: copyStatus!.contains('Success') ? Colors.green : AdminColors.danger, fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: GoogleFonts.inter(color: AdminColors.getTextSecondary(isDark)))),
            ElevatedButton(
              onPressed: (isCopying || srcSection == dstSection)
                  ? null
                  : () async {
                      setDlgState(() {
                        isCopying = true;
                        copyStatus = null;
                      });
                      try {
                        final res = await http.post(
                          Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/academics/timetable/copy'),
                          headers: {'Authorization': 'Bearer ${widget.token}', 'Content-Type': 'application/json'},
                          body: jsonEncode({
                            'src_dept': _selectedDept,
                            'src_batch': _selectedBatch,
                            'src_semester': _selectedSemester,
                            'src_section': srcSection,
                            'dst_dept': _selectedDept,
                            'dst_batch': _selectedBatch,
                            'dst_semester': _selectedSemester,
                            'dst_section': dstSection,
                            'copy_allocations': copyAllocs,
                          }),
                        );
                        if (res.statusCode == 200) {
                          setDlgState(() => copyStatus = 'Successfully cloned timetable to Section $dstSection!');
                          _loadAllData();
                        } else {
                          final err = jsonDecode(res.body)['detail'] ?? 'Failed to copy timetable';
                          setDlgState(() => copyStatus = err);
                        }
                      } catch (e) {
                        setDlgState(() => copyStatus = 'Error: $e');
                      } finally {
                        setDlgState(() => isCopying = false);
                      }
                    },
              style: ElevatedButton.styleFrom(backgroundColor: AdminColors.primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: isCopying ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Execute Clone'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentYearCfg = _yearConfigs[_selectedYearIndex];
    final isCurriculumTab = _selectedTabIndex == 4;

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTopHeader(isDark, currentYearCfg, isCurriculumTab),
          _buildTabBar(isDark),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            _buildActiveTabContent(isDark),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildTabBar(bool isDark) {
    final tabs = [
      {'label': 'Weekly Timetable', 'icon': Icons.grid_view_rounded},
      {'label': 'Date View & Overrides', 'icon': Icons.calendar_month_rounded},
      {'label': 'Class Advisors', 'icon': Icons.badge_rounded},
      {'label': 'Subject Allocations', 'icon': Icons.assignment_ind_rounded},
      {'label': 'Subjects & Curriculum', 'icon': Icons.menu_book_rounded},
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AdminColors.getCard(isDark),
        border: Border(bottom: BorderSide(color: AdminColors.getBorder(isDark), width: 1)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(tabs.length, (idx) {
            final isSel = _selectedTabIndex == idx;
            final t = tabs[idx];
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                onTap: () {
                  setState(() {
                    _selectedTabIndex = idx;
                    _tabController.index = idx;
                  });
                },
                borderRadius: BorderRadius.circular(8),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: isSel ? AdminColors.primary : (isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF1F5F9)),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSel ? AdminColors.primary : AdminColors.getBorder(isDark).withValues(alpha: 0.6),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(t['icon'] as IconData, size: 14, color: isSel ? Colors.white : AdminColors.getTextSecondary(isDark)),
                      const SizedBox(width: 6),
                      Text(
                        t['label'] as String,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: isSel ? FontWeight.w600 : FontWeight.w500,
                          color: isSel ? Colors.white : AdminColors.getTextPrimary(isDark),
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
    );
  }

  Widget _buildActiveTabContent(bool isDark) {
    switch (_selectedTabIndex) {
      case 0:
        return TimetableGridView(
          key: const PageStorageKey('timetable_grid'),
          token: widget.token,
          dept: _selectedDept,
          batch: _selectedBatch,
          semester: _selectedSemester,
          section: _selectedSection,
          timeline: _timeline,
          slots: _slots,
          facultyPool: _facultyPool,
          subjectAllocations: _subjectAllocations,
          availableDepartments: _availableDepartments,
          workingDays: _workingDays,
          onSlotUpdated: _loadAllData,
        );
      case 1:
        return Padding(
          padding: const EdgeInsets.all(16),
          child: DateTimetableView(
            key: const PageStorageKey('date_timetable'),
            token: widget.token,
            dept: _selectedDept,
            batch: _selectedBatch,
            semester: _selectedSemester,
            section: _selectedSection,
            isEditableByAdmin: true,
            onScheduleChanged: _loadAllData,
          ),
        );
      case 2:
        return ClassAdvisorView(
          key: const PageStorageKey('class_advisors'),
          token: widget.token,
          dept: _selectedDept,
          batch: _selectedBatch,
          semester: _selectedSemester,
          section: _selectedSection,
          facultyPool: _facultyPool,
          availableDepartments: _availableDepartments,
          isHod: _isHod,
          onAdvisorUpdated: _loadAllData,
        );
      case 3:
        return SubjectAllocationView(
          key: const PageStorageKey('subject_allocations'),
          token: widget.token,
          dept: _selectedDept,
          batch: _selectedBatch,
          semester: _selectedSemester,
          section: _selectedSection,
          allocations: _subjectAllocations,
          facultyPool: _facultyPool,
          availableDepartments: _availableDepartments,
          onAllocationUpdated: _loadAllData,
        );
      case 4:
        return SubjectManagementView(
          key: const PageStorageKey('subject_management'),
          token: widget.token,
          userRole: widget.userRole,
          userDept: widget.userDept,
          currentSelectedDept: _selectedDept,
          onSubjectCatalogChanged: _loadAllData,
          onDepartmentChanged: (dept) {
            setState(() => _selectedDept = dept);
            _loadAllData();
          },
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildTopHeader(bool isDark, _YearConfig currentYearCfg, bool isCurriculumTab) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
      decoration: BoxDecoration(
        color: AdminColors.getCard(isDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Title & Main Action Buttons
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 900;

              final titleSection = Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isCurriculumTab ? Colors.indigo.withValues(alpha: 0.12) : AdminColors.primarySoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isCurriculumTab ? Icons.menu_book_rounded : Icons.calendar_month_rounded,
                      color: isCurriculumTab ? Colors.indigo : AdminColors.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isCurriculumTab
                              ? 'Department Curriculum & Course Catalog'
                              : 'Academic Schedule & Timetable Matrix',
                          style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: AdminColors.getTextPrimary(isDark)),
                        ),
                        Text(
                          isCurriculumTab
                              ? 'Centralized syllabus, theory & lab courses, credit framework, and degree structure'
                              : 'Interactive Weekly Timetables, Period Rules, Class Advisors, and Subject Matrix',
                          style: GoogleFonts.inter(fontSize: 12, color: AdminColors.getTextSecondary(isDark)),
                        ),
                      ],
                    ),
                  ),
                  if (isNarrow)
                    IconButton(
                      onPressed: _loadAllData,
                      icon: const Icon(Icons.refresh_rounded),
                      tooltip: 'Refresh',
                    ),
                ],
              );

              final actionsList = [
                if (!isCurriculumTab) ...[
                  OutlinedButton.icon(
                    onPressed: _openBatchPromotionDialog,
                    icon: const Icon(Icons.upgrade_rounded, size: 16, color: Colors.teal),
                    label: const Text('Promote Batch'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.teal,
                      side: const BorderSide(color: Colors.teal),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _openWeeklyBuilderDialog,
                    icon: const Icon(Icons.speed_rounded, size: 16, color: Colors.purple),
                    label: const Text('Weekly Builder'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.purple,
                      side: const BorderSide(color: Colors.purple),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _openDayManagementDialog,
                    icon: const Icon(Icons.date_range_rounded, size: 16),
                    label: const Text('Manage Days'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AdminColors.primary,
                      side: const BorderSide(color: AdminColors.primary),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _openCopyTimetableDialog,
                    icon: const Icon(Icons.copy_all_rounded, size: 16),
                    label: const Text('Clone Timetable'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AdminColors.primary,
                      side: const BorderSide(color: AdminColors.primary),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _openPeriodConfigDialog,
                    icon: const Icon(Icons.tune_rounded, size: 16),
                    label: const Text('Period & Breaks'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AdminColors.primary,
                      side: const BorderSide(color: AdminColors.primary),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (!isNarrow)
                  IconButton(
                    onPressed: _loadAllData,
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: 'Refresh',
                  ),
              ];

              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    titleSection,
                    if (!isCurriculumTab) ...[
                      const SizedBox(height: 10),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(children: actionsList),
                      ),
                    ],
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: titleSection),
                  ...actionsList,
                ],
              );
            },
          ),
          const SizedBox(height: 14),

          // Row 2: High-Tech Academic Navigation Bar (Year, Sem, Section, Dept)
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildDeptSelector(isDark),

              if (!isCurriculumTab) ...[
                // 1. Year of Study Switcher Pills
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AdminColors.getBorder(isDark)),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(_yearConfigs.length, (i) {
                        final y = _yearConfigs[i];
                        final isSel = _selectedYearIndex == i;
                        return InkWell(
                          onTap: () => _onYearSelected(i),
                          borderRadius: BorderRadius.circular(8),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                              color: isSel ? AdminColors.primary : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.school_rounded, size: 13, color: isSel ? Colors.white : AdminColors.getTextSecondary(isDark)),
                                const SizedBox(width: 4),
                                Text(
                                  y.title,
                                  style: GoogleFonts.inter(fontSize: 11.5, fontWeight: isSel ? FontWeight.w700 : FontWeight.w500, color: isSel ? Colors.white : AdminColors.getTextSecondary(isDark)),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ),

                // 2. Active Semester Selector
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AdminColors.getBorder(isDark)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: currentYearCfg.semesters.map((sem) {
                      final isSel = _selectedSemester == sem;
                      return InkWell(
                        onTap: () {
                          setState(() => _selectedSemester = sem);
                          _loadAllData();
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: isSel ? AdminColors.primary : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Sem $sem',
                            style: GoogleFonts.inter(fontSize: 11.5, fontWeight: isSel ? FontWeight.w700 : FontWeight.w500, color: isSel ? Colors.white : AdminColors.getTextSecondary(isDark)),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                // 3. Section Selector Pills
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AdminColors.getBorder(isDark)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: _sections.map((sec) {
                      final isSel = _selectedSection == sec;
                      return InkWell(
                        onTap: () {
                          setState(() => _selectedSection = sec);
                          _loadAllData();
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: isSel ? AdminColors.primary : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Sec $sec',
                            style: GoogleFonts.inter(fontSize: 11.5, fontWeight: isSel ? FontWeight.w700 : FontWeight.w500, color: isSel ? Colors.white : AdminColors.getTextSecondary(isDark)),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeptSelector(bool isDark) {
    if (_isHod) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AdminColors.primarySoft,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AdminColors.primary.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.domain_rounded, size: 16, color: AdminColors.primary),
            const SizedBox(width: 6),
            Text('Dept: $_selectedDept (HOD)', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AdminColors.primary)),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AdminColors.getBorder(isDark)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Dept: ', style: GoogleFonts.inter(fontSize: 12, color: AdminColors.getTextMuted(isDark))),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _departments.contains(_selectedDept) ? _selectedDept : _departments.first,
              items: _departments.map((e) => DropdownMenuItem(value: e, child: Text(e, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AdminColors.getTextPrimary(isDark))))).toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() => _selectedDept = v);
                  _loadAllData();
                }
              },
              dropdownColor: AdminColors.getCard(isDark),
            ),
          ),
        ],
      ),
    );
  }
}
