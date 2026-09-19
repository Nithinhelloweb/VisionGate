import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../config/college_ip_config.dart';
import 'student_card.dart';
import 'student_details_dialog.dart';
import 'student_edit_dialog.dart';
import '../student/student_registration_dialog.dart';
import '../class_session_roll_sheet.dart';

/// Hallmark-compliant Staff Handled Classes & Teaching Subjects View
/// Designed with:
/// - 100% Roman upright headings (font-style: normal)
/// - Locked semantic color tokens (primaryBlue, emeraldGreen, slate900)
/// - 8-State interactive design coverage
/// - Authentic college domain copy and interactive drilldown
class StaffHandledClassesView extends StatefulWidget {
  final String token;
  final Map<String, dynamic> user;
  final List<dynamic> teachingAllocations;
  final Function(Map<String, dynamic>)? onClassSelected;
  final VoidCallback? onRefresh;
  final VoidCallback? onSwitchToAdvisedTab;

  const StaffHandledClassesView({
    super.key,
    required this.token,
    required this.user,
    required this.teachingAllocations,
    this.onClassSelected,
    this.onRefresh,
    this.onSwitchToAdvisedTab,
  });

  @override
  State<StaffHandledClassesView> createState() => _StaffHandledClassesViewState();
}

class _StaffHandledClassesViewState extends State<StaffHandledClassesView> {
  static const Color primaryBlue = Color(0xFF2563EB);
  static const Color emeraldGreen = Color(0xFF10B981);
  static const Color amberWarning = Color(0xFFF59E0B);
  static const Color roseError = Color(0xFFEF4444);
  static const Color indigoAccent = Color(0xFF6366F1);

  // Selected class by unique key: "dept|batch|semester|section"
  String? _selectedClassKey;
  int _selectedSubjectIndex = 0;
  List<dynamic> _classStudents = [];
  bool _isLoadingStudents = false;
  String? _studentError;
  String _searchQuery = '';
  String _studentFilter = 'ALL'; // 'ALL', 'ENROLLED', 'PENDING'
  String _selectedDeptFilter = 'ALL';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Helper to build class-grouped allocations
  Map<String, List<Map<String, dynamic>>> _buildClassGroups(List<dynamic> allocations) {
    final Map<String, List<Map<String, dynamic>>> groups = {};
    for (final a in allocations) {
      final alloc = a as Map<String, dynamic>;
      final dept = alloc['dept']?.toString() ?? '';
      final batch = alloc['batch']?.toString() ?? '';
      final semester = alloc['semester']?.toString() ?? '';
      final section = alloc['section']?.toString() ?? '';
      final key = '$dept|$batch|$semester|$section';
      groups.putIfAbsent(key, () => []).add(alloc);
    }
    return groups;
  }

  // Returns representative allocation for a class group key
  Map<String, dynamic>? _groupRepresentative(String key) {
    final groups = _buildClassGroups(widget.teachingAllocations);
    return groups[key]?.first;
  }

  // All subjects taught by this staff member in the currently selected class
  List<Map<String, dynamic>> get _selectedClassSubjects {
    if (_selectedClassKey == null) return [];
    final groups = _buildClassGroups(widget.teachingAllocations);
    return groups[_selectedClassKey] ?? [];
  }

  // Active subject allocation based on _selectedSubjectIndex
  Map<String, dynamic>? get _activeSubject {
    final list = _selectedClassSubjects;
    if (list.isEmpty) return null;
    if (_selectedSubjectIndex < 0 || _selectedSubjectIndex >= list.length) {
      return list.first;
    }
    return list[_selectedSubjectIndex];
  }

  // Active allocation for student panel, quick roll-call, and dialogs
  Map<String, dynamic>? get _selectedAllocation =>
      _activeSubject ?? (_selectedClassKey != null ? _groupRepresentative(_selectedClassKey!) : null);

  // Client-side instant filter on cached class student roster
  List<dynamic> get _filteredStudents {
    return _classStudents.where((s) {
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.trim().toLowerCase();
        final name = (s['name'] ?? '').toString().toLowerCase();
        final reg = (s['reg_no'] ?? '').toString().toLowerCase();
        final roll = (s['roll_no'] ?? '').toString().toLowerCase();
        if (!name.contains(q) && !reg.contains(q) && !roll.contains(q)) {
          return false;
        }
      }
      final hasFace = (s['has_face'] == true) || (((s['face_samples_count'] ?? 0) as num) > 0);
      if (_studentFilter == 'ENROLLED' && !hasFace) return false;
      if (_studentFilter == 'PENDING' && hasFace) return false;
      return true;
    }).toList();
  }

  String _romanSemester(dynamic sem) {
    final s = int.tryParse(sem.toString()) ?? 1;
    switch (s) {
      case 1: return 'Sem I';
      case 2: return 'Sem II';
      case 3: return 'Sem III';
      case 4: return 'Sem IV';
      case 5: return 'Sem V';
      case 6: return 'Sem VI';
      case 7: return 'Sem VII';
      case 8: return 'Sem VIII';
      default: return 'Sem $sem';
    }
  }

  String _academicYearLabel(dynamic sem) {
    final s = int.tryParse(sem.toString()) ?? 1;
    final year = ((s + 1) ~/ 2);
    switch (year) {
      case 1: return '1st Year';
      case 2: return '2nd Year';
      case 3: return '3rd Year';
      case 4: return 'Final Year';
      default: return 'Year $year';
    }
  }

  @override
  void initState() {
    super.initState();
    final groups = _buildClassGroups(widget.teachingAllocations);
    if (groups.isNotEmpty) {
      _selectClassKey(groups.keys.first);
    }
  }

  @override
  void didUpdateWidget(covariant StaffHandledClassesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.teachingAllocations != widget.teachingAllocations) {
      if (_selectedClassKey == null && widget.teachingAllocations.isNotEmpty) {
        final groups = _buildClassGroups(widget.teachingAllocations);
        if (groups.isNotEmpty) {
          _selectClassKey(groups.keys.first);
        }
      }
    }
  }

  void _selectClassKey(String key) {
    final rep = _groupRepresentative(key);
    setState(() {
      _selectedClassKey = key;
      _selectedSubjectIndex = 0;
      _searchQuery = '';
      _studentFilter = 'ALL';
      _searchController.clear();
    });
    if (rep != null) {
      if (widget.onClassSelected != null) {
        widget.onClassSelected!(rep);
      }
      _fetchStudentsForClass(rep);
    }
  }

  Future<void> _fetchStudentsForClass(Map<String, dynamic> alloc) async {
    setState(() {
      _isLoadingStudents = true;
      _studentError = null;
    });

    final dept = alloc['dept'] ?? '';
    final batch = alloc['batch'] ?? '';
    final semester = alloc['semester'] ?? '';
    final section = alloc['section'] ?? '';

    final queryParams = <String, String>{
      'dept': dept.toString(),
      'batch': batch.toString(),
      'semester': semester.toString(),
      'section': section.toString(),
      'scope_mode': 'teaching',
      'limit': '1000',
    };

    final uri = Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/students/list')
        .replace(queryParameters: queryParams);

    try {
      final res = await http.get(
        uri,
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _classStudents = data['students'] ?? [];
          _isLoadingStudents = false;
        });
      } else {
        final err = jsonDecode(res.body);
        setState(() {
          _studentError = err['detail'] ?? 'Failed to load class students.';
          _isLoadingStudents = false;
        });
      }
    } catch (e) {
      setState(() {
        _studentError = 'Network error: $e';
        _isLoadingStudents = false;
      });
    }
  }

  void _exportClassCSV() {
    if (_classStudents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No student records available to export for this class.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final alloc = (_activeSubject ?? (_selectedClassKey != null ? _groupRepresentative(_selectedClassKey!) : null)) ?? {};
    final buffer = StringBuffer();
    buffer.writeln('Subject Code: ${alloc['subject_code'] ?? ""}, Subject Name: ${alloc['subject_name'] ?? ""}');
    buffer.writeln('Department: ${alloc['dept'] ?? ""}, Semester: ${alloc['semester'] ?? ""}, Section: ${alloc['section'] ?? ""}');
    buffer.writeln('--------------------------------------------------');
    buffer.writeln('Reg No,Roll No,Name,Department,Batch,Semester,Section,Biometric Status,Phone,Status');

    for (final s in _classStudents) {
      final hasFace = (s['has_face'] == true) || (s['face_samples_count'] ?? 0) > 0;
      final isSuspended = (s['suspended'] == true);
      buffer.writeln(
        '${s['reg_no'] ?? ""},'
        '${s['roll_no'] ?? ""},'
        '"${s['name'] ?? ""}",'
        '${s['dept'] ?? ""},'
        '${s['batch'] ?? ""},'
        '${s['semester'] ?? ""},'
        '${s['section'] ?? ""},'
        '${hasFace ? "Face Enrolled" : "No Face ID"},'
        '${s['phone_number'] ?? ""},'
        '${isSuspended ? "Suspended" : "Active"}'
      );
    }

    final csvString = buffer.toString();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.file_download_outlined, color: primaryBlue),
            const SizedBox(width: 8),
            Text('Export Class Roster (${_classStudents.length} Students)'),
          ],
        ),
        content: SizedBox(
          width: 550,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Class roster dataset generated successfully:', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                height: 180,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    csvString,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.black87),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          ElevatedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: csvString));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Class CSV copied to clipboard!'),
                  backgroundColor: emeraldGreen,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: primaryBlue, foregroundColor: Colors.white),
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Copy to Clipboard'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleStudentStatus(String regNo) async {
    try {
      final res = await http.post(
        Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/students/$regNo/toggle-status'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (res.statusCode == 200 && _selectedAllocation != null) {
        _fetchStudentsForClass(_selectedAllocation!);
      }
    } catch (e) {
      debugPrint("Toggle status error: $e");
    }
  }

  Future<void> _confirmDeleteStudent(String regNo, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Student Deletion'),
        content: Text('Are you sure you want to delete student "$name" ($regNo)?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: roseError, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final res = await http.delete(
          Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/students/$regNo'),
          headers: {'Authorization': 'Bearer ${widget.token}'},
        );
        if (res.statusCode == 200 && _selectedAllocation != null) {
          _fetchStudentsForClass(_selectedAllocation!);
        }
      } catch (e) {
        debugPrint("Delete student error: $e");
      }
    }
  }

  Future<void> _launchRollCallSheet() async {
    if (_selectedAllocation == null) return;
    final alloc = _selectedAllocation!;
    final classSummary = '${alloc['dept']} • Sem ${alloc['semester']} • Sec ${alloc['section']}';

    String sessionId = '';
    try {
      final res = await http.post(
        Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/class-session/quick-start'),
        headers: {
          'Authorization': widget.token.startsWith('Bearer ') ? widget.token : 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'dept': alloc['dept'],
          'batch': alloc['batch'] ?? '',
          'semester': alloc['semester'],
          'section': alloc['section'],
          'subject_code': alloc['subject_code'],
          'subject_name': alloc['subject_name'],
          'period_number': 1,
        }),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        sessionId = data['session_id'] ?? '';
      }
    } catch (_) {}

    if (sessionId.isEmpty) {
      sessionId = 'cas_${alloc['dept']}_${alloc['subject_code']}_${DateTime.now().millisecondsSinceEpoch}';
    }

    if (!mounted) return;
    ClassSessionRollSheet.show(
      context,
      token: widget.token,
      sessionId: sessionId,
      subjectName: '${alloc['subject_name']} (${alloc['subject_code']})',
      classSummary: classSummary,
      canOverride: true,
      allocation: alloc,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final allocations = widget.teachingAllocations;

    // Change 8: Group allocations by unique class (dept|batch|semester|section)
    final classGroups = _buildClassGroups(allocations);

    // Collect unique departments
    final depts = <String>{'ALL'};
    for (final a in allocations) {
      if (a['dept'] != null && a['dept'].toString().isNotEmpty) {
        depts.add(a['dept'].toString());
      }
    }

    // Filter groups by selected dept
    final filteredGroups = _selectedDeptFilter == 'ALL'
        ? classGroups
        : Map.fromEntries(
            classGroups.entries.where((e) => e.value.first['dept'] == _selectedDeptFilter),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. SECTION INTRO & DEPARTMENT FILTER PILLS
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Handled Classes & Subjects',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Select any handled class to view its students and subjects',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      color: isDark ? Colors.white60 : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: primaryBlue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                // Change 8: Show unique class count, not subject count
                classGroups.isEmpty
                    ? 'No classes assigned'
                    : '${classGroups.length} ${classGroups.length == 1 ? 'Class' : 'Classes'} • ${allocations.length} Subjects',
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: primaryBlue,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // Department Filter Tabs (if teaching across multiple depts)
        if (depts.length > 2) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: depts.map((d) {
                final isSel = _selectedDeptFilter == d;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(d == 'ALL' ? 'All Departments' : d),
                    selected: isSel,
                    onSelected: (val) {
                      setState(() => _selectedDeptFilter = d);
                    },
                    selectedColor: primaryBlue.withValues(alpha: 0.18),
                    checkmarkColor: primaryBlue,
                    labelStyle: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 12,
                      color: isSel ? primaryBlue : (isDark ? Colors.white70 : const Color(0xFF475569)),
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // 2. TEACHING CLASS CARDS GRID (Change 8: one card per unique class)
        if (allocations.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                Icon(Icons.menu_book_outlined, size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 10),
                const Text(
                  'No Class Assignments Found',
                  style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  'You currently have no teaching assignments across classes.',
                  style: TextStyle(fontFamily: 'Inter', color: Colors.grey.shade500, fontSize: 12),
                ),
              ],
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 800;
              final crossAxisCount = isWide ? 3 : (constraints.maxWidth > 580 ? 2 : 1);
              final classKeys = filteredGroups.keys.toList();

              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  mainAxisExtent: 80,
                ),
                itemCount: classKeys.length,
                itemBuilder: (ctx, i) {
                  final key = classKeys[i];
                  final subjects = filteredGroups[key]!;
                  final rep = subjects.first;
                  final isSelected = _selectedClassKey == key;
                  return _buildClassGroupCard(key, rep, subjects, isSelected, isDark);
                },
              );
            },
          ),

        const SizedBox(height: 18),

        // 3. EXECUTIVE COMMAND CENTER: SELECTED CLASS WORKSPACE
        if (_selectedClassKey != null) ...[
          Builder(
            builder: (context) {
              final rep = _groupRepresentative(_selectedClassKey!)!;
              final activeAlloc = _activeSubject ?? rep;
              final subjectsInClass = _selectedClassSubjects;
              final isAdvisedClass = subjectsInClass.any((s) => s['is_advised_class'] == true);
              final totalStudents = _classStudents.length;
              final enrolledCount = _classStudents.where((s) => (s['has_face'] == true) || (((s['face_samples_count'] ?? 0) as num) > 0)).length;
              final pendingCount = totalStudents - enrolledCount;
              final enrolledPct = totalStudents > 0 ? ((enrolledCount / totalStudents) * 100).round() : 0;
              final filtered = _filteredStudents;

              return Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Cockpit: Live Status & Action Buttons
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isCompact = constraints.maxWidth < 720;

                        final headerInfo = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: primaryBlue.withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: primaryBlue.withValues(alpha: 0.25)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 7,
                                        height: 7,
                                        decoration: const BoxDecoration(
                                          color: emeraldGreen,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      const Text(
                                        'ACTIVE WORKSPACE',
                                        style: TextStyle(
                                          fontFamily: 'Inter',
                                          fontWeight: FontWeight.w700,
                                          fontSize: 10,
                                          letterSpacing: 0.8,
                                          color: primaryBlue,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isDark ? Colors.white10 : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFCBD5E1)),
                                  ),
                                  child: Text(
                                    '${rep['dept']} • ${_romanSemester(rep['semester'])} – Sec ${rep['section']}',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11.5,
                                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                                    ),
                                  ),
                                ),
                                if (rep['batch'] != null && rep['batch'].toString().isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isDark ? Colors.white10 : const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                                    ),
                                    child: Text(
                                      'Batch ${rep['batch']} • ${_academicYearLabel(rep['semester'])}',
                                      style: TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 11,
                                        color: isDark ? Colors.white60 : const Color(0xFF64748B),
                                      ),
                                    ),
                                  ),
                                if (isAdvisedClass)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: emeraldGreen.withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: emeraldGreen.withValues(alpha: 0.3)),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.stars_rounded, size: 13, color: emeraldGreen),
                                        SizedBox(width: 4),
                                        Text(
                                          'Class Advisor',
                                          style: TextStyle(
                                            fontFamily: 'Inter',
                                            fontWeight: FontWeight.w700,
                                            fontSize: 11,
                                            color: emeraldGreen,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        );

                        final actionButtons = Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: isCompact ? WrapAlignment.start : WrapAlignment.end,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (isAdvisedClass && widget.onSwitchToAdvisedTab != null)
                              OutlinedButton.icon(
                                onPressed: widget.onSwitchToAdvisedTab,
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  side: const BorderSide(color: emeraldGreen),
                                  foregroundColor: emeraldGreen,
                                ),
                                icon: const Icon(Icons.assignment_ind_rounded, size: 16),
                                label: const Text(
                                  'Manage Advisees',
                                  style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12),
                                ),
                              ),
                            OutlinedButton.icon(
                              onPressed: _exportClassCSV,
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                side: BorderSide(color: isDark ? Colors.white24 : const Color(0xFFCBD5E1)),
                              ),
                              icon: const Icon(Icons.file_download_outlined, size: 16),
                              label: const Text(
                                'Export CSV',
                                style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 12),
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: _launchRollCallSheet,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: emeraldGreen,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 0,
                              ),
                              icon: const Icon(Icons.fact_check_rounded, size: 16),
                              label: const Text(
                                'Mark Attendance',
                                style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12),
                              ),
                            ),
                          ],
                        );

                        if (isCompact) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              headerInfo,
                              const SizedBox(height: 12),
                              actionButtons,
                            ],
                          );
                        } else {
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(child: headerInfo),
                              const SizedBox(width: 14),
                              Flexible(child: actionButtons),
                            ],
                          );
                        }
                      },
                    ),

                    const SizedBox(height: 16),

                    // Multi-Subject Selector Tabs (if multiple subjects) or Course Banner (if single subject)
                    if (subjectsInClass.length > 1) ...[
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                        ),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: List.generate(subjectsInClass.length, (idx) {
                              final isSubSel = _selectedSubjectIndex == idx;
                              final subj = subjectsInClass[idx];
                              final subCode = subj['subject_code'] ?? '';
                              final subName = subj['subject_name'] ?? '';
                              final subType = subj['subject_type'] ?? 'Course';

                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: InkWell(
                                  onTap: () {
                                    setState(() {
                                      _selectedSubjectIndex = idx;
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(10),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 160),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: isSubSel
                                          ? (isDark ? const Color(0xFF1E293B) : Colors.white)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isSubSel
                                            ? primaryBlue.withValues(alpha: 0.35)
                                            : Colors.transparent,
                                      ),
                                      boxShadow: isSubSel
                                          ? [
                                              BoxShadow(
                                                color: Colors.black.withValues(alpha: 0.06),
                                                blurRadius: 6,
                                                offset: const Offset(0, 2),
                                              ),
                                            ]
                                          : null,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: isSubSel
                                                ? primaryBlue.withValues(alpha: 0.12)
                                                : (isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            subCode,
                                            style: TextStyle(
                                              fontFamily: 'Inter',
                                              fontWeight: FontWeight.w700,
                                              fontSize: 11,
                                              color: isSubSel
                                                  ? primaryBlue
                                                  : (isDark ? Colors.white70 : const Color(0xFF475569)),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          subName,
                                          style: TextStyle(
                                            fontFamily: 'Inter',
                                            fontWeight: isSubSel ? FontWeight.w700 : FontWeight.w500,
                                            fontSize: 12,
                                            color: isSubSel
                                                ? (isDark ? Colors.white : const Color(0xFF0F172A))
                                                : (isDark ? Colors.white60 : const Color(0xFF64748B)),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: isSubSel
                                                ? amberWarning.withValues(alpha: 0.15)
                                                : Colors.transparent,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            subType,
                                            style: TextStyle(
                                              fontFamily: 'Inter',
                                              fontWeight: FontWeight.w600,
                                              fontSize: 10,
                                              color: isSubSel
                                                  ? amberWarning
                                                  : (isDark ? Colors.white38 : const Color(0xFF94A3B8)),
                                            ),
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
                      const SizedBox(height: 14),
                    ] else ...[
                      // Single Subject Showcase
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: primaryBlue.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              activeAlloc['subject_code'] ?? '',
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                color: primaryBlue,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${activeAlloc['subject_name'] ?? 'Class Subject'}',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                    ],

                    // Quick Cohort Statistics Strip (3 responsive metric tiles)
                    LayoutBuilder(
                      builder: (context, metricConstraints) {
                        final isStripCompact = metricConstraints.maxWidth < 620;

                        final tile1 = _buildMetricCard(
                          icon: Icons.groups_rounded,
                          iconColor: primaryBlue,
                          value: '$totalStudents',
                          label: 'Total Students',
                          sub: 'Enrolled in section',
                          isDark: isDark,
                        );

                        final tile2 = _buildMetricCard(
                          icon: Icons.face_retouching_natural_rounded,
                          iconColor: emeraldGreen,
                          value: '$enrolledCount / $totalStudents',
                          label: 'Biometric Ready ($enrolledPct%)',
                          sub: '$pendingCount pending Face ID',
                          isDark: isDark,
                        );

                        final tile3 = _buildMetricCard(
                          icon: Icons.schedule_rounded,
                          iconColor: indigoAccent,
                          value: '${activeAlloc['weekly_hours'] ?? '4'} hrs/wk',
                          label: '${activeAlloc['subject_type'] ?? 'Course'} Allocation',
                          sub: activeAlloc['subject_code'] ?? '',
                          isDark: isDark,
                        );

                        if (isStripCompact) {
                          return Column(
                            children: [
                              tile1,
                              const SizedBox(height: 8),
                              tile2,
                              const SizedBox(height: 8),
                              tile3,
                            ],
                          );
                        } else {
                          return Row(
                            children: [
                              Expanded(child: tile1),
                              const SizedBox(width: 10),
                              Expanded(child: tile2),
                              const SizedBox(width: 10),
                              Expanded(child: tile3),
                            ],
                          );
                        }
                      },
                    ),

                    const SizedBox(height: 18),

                    // Search & Biometric Status Filter Strip
                    LayoutBuilder(
                      builder: (context, filterConstraints) {
                        final isFilterStacked = filterConstraints.maxWidth < 680;

                        final searchField = TextField(
                          controller: _searchController,
                          onChanged: (val) {
                            setState(() => _searchQuery = val);
                          },
                          decoration: InputDecoration(
                            hintText: 'Search student by name, register number or roll number…',
                            hintStyle: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12.5,
                              color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                            ),
                            prefixIcon: const Icon(Icons.search_rounded, size: 20),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.close_rounded, size: 18),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: primaryBlue, width: 1.5),
                            ),
                          ),
                        );

                        final filterChips = SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              FilterChip(
                                label: Text('All ($totalStudents)'),
                                selected: _studentFilter == 'ALL',
                                onSelected: (val) {
                                  setState(() => _studentFilter = 'ALL');
                                },
                                selectedColor: primaryBlue.withValues(alpha: 0.16),
                                checkmarkColor: primaryBlue,
                                labelStyle: TextStyle(
                                  fontFamily: 'Inter',
                                  fontWeight: _studentFilter == 'ALL' ? FontWeight.w700 : FontWeight.w500,
                                  fontSize: 11.5,
                                  color: _studentFilter == 'ALL'
                                      ? primaryBlue
                                      : (isDark ? Colors.white70 : const Color(0xFF475569)),
                                ),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              const SizedBox(width: 8),
                              FilterChip(
                                label: Text('Biometric Ready ($enrolledCount)'),
                                selected: _studentFilter == 'ENROLLED',
                                onSelected: (val) {
                                  setState(() => _studentFilter = 'ENROLLED');
                                },
                                selectedColor: emeraldGreen.withValues(alpha: 0.16),
                                checkmarkColor: emeraldGreen,
                                labelStyle: TextStyle(
                                  fontFamily: 'Inter',
                                  fontWeight: _studentFilter == 'ENROLLED' ? FontWeight.w700 : FontWeight.w500,
                                  fontSize: 11.5,
                                  color: _studentFilter == 'ENROLLED'
                                      ? emeraldGreen
                                      : (isDark ? Colors.white70 : const Color(0xFF475569)),
                                ),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              const SizedBox(width: 8),
                              FilterChip(
                                label: Text('Pending Face ID ($pendingCount)'),
                                selected: _studentFilter == 'PENDING',
                                onSelected: (val) {
                                  setState(() => _studentFilter = 'PENDING');
                                },
                                selectedColor: amberWarning.withValues(alpha: 0.16),
                                checkmarkColor: amberWarning,
                                labelStyle: TextStyle(
                                  fontFamily: 'Inter',
                                  fontWeight: _studentFilter == 'PENDING' ? FontWeight.w700 : FontWeight.w500,
                                  fontSize: 11.5,
                                  color: _studentFilter == 'PENDING'
                                      ? amberWarning
                                      : (isDark ? Colors.white70 : const Color(0xFF475569)),
                                ),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ],
                          ),
                        );

                        if (isFilterStacked) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              searchField,
                              const SizedBox(height: 10),
                              filterChips,
                            ],
                          );
                        } else {
                          return Row(
                            children: [
                              Expanded(flex: 3, child: searchField),
                              const SizedBox(width: 12),
                              Expanded(flex: 2, child: filterChips),
                            ],
                          );
                        }
                      },
                    ),

                    const SizedBox(height: 18),

                    // Student Cards Grid & Empty/Loading States
                    if (_isLoadingStudents)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 36),
                          child: CircularProgressIndicator(color: primaryBlue),
                        ),
                      )
                    else if (_studentError != null)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 30),
                          child: Column(
                            children: [
                              Text(_studentError!, style: const TextStyle(color: roseError)),
                              const SizedBox(height: 8),
                              TextButton.icon(
                                onPressed: () => _fetchStudentsForClass(rep),
                                icon: const Icon(Icons.refresh_rounded, size: 16),
                                label: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (filtered.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 32),
                          child: Column(
                            children: [
                              Icon(Icons.people_outline_rounded, size: 44, color: Colors.grey.shade400),
                              const SizedBox(height: 10),
                              Text(
                                _classStudents.isEmpty
                                    ? 'No Students Found in this Class'
                                    : 'No Students Match Current Filters',
                                style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 14),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _classStudents.isEmpty
                                    ? 'No student records are currently enrolled in this class cohort.'
                                    : 'Try searching with a different term or resetting the biometric filter.',
                                style: TextStyle(fontFamily: 'Inter', color: Colors.grey.shade500, fontSize: 12),
                              ),
                              if (_searchQuery.isNotEmpty || _studentFilter != 'ALL') ...[
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {
                                      _searchQuery = '';
                                      _studentFilter = 'ALL';
                                    });
                                  },
                                  icon: const Icon(Icons.clear_all_rounded, size: 16),
                                  label: const Text('Reset Search & Filters'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      )
                    else
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final crossAxisCount = constraints.maxWidth > 900 ? 2 : 1;
                          return GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: crossAxisCount,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              mainAxisExtent: 175,
                            ),
                            itemCount: filtered.length,
                            itemBuilder: (ctx, i) {
                              final s = filtered[i];
                              return StudentCard(
                                student: s,
                                onTap: () => StudentDetailsDialog.show(
                                  context,
                                  student: s,
                                  onEdit: () => StudentEditDialog.show(
                                    context,
                                    token: widget.token,
                                    student: s,
                                    onUpdated: () => _fetchStudentsForClass(rep),
                                  ),
                                  onReEnrollFace: () => StudentRegistrationDialog.show(
                                    context,
                                    token: widget.token,
                                    user: widget.user,
                                    initialDept: s['dept'],
                                    isDeptLocked: true,
                                    initialStudent: s,
                                    isReEnroll: true,
                                    onStudentRegistered: () => _fetchStudentsForClass(rep),
                                  ),
                                  onToggleStatus: () => _toggleStudentStatus(s['reg_no']),
                                ),
                                onEdit: () => StudentEditDialog.show(
                                  context,
                                  token: widget.token,
                                  student: s,
                                  onUpdated: () => _fetchStudentsForClass(rep),
                                ),
                                onReEnrollFace: () => StudentRegistrationDialog.show(
                                  context,
                                  token: widget.token,
                                  user: widget.user,
                                  initialDept: s['dept'],
                                  isDeptLocked: true,
                                  initialStudent: s,
                                  isReEnroll: true,
                                  onStudentRegistered: () => _fetchStudentsForClass(rep),
                                ),
                                onToggleStatus: () => _toggleStudentStatus(s['reg_no']),
                                onDelete: () => _confirmDeleteStudent(s['reg_no'], s['name']),
                              );
                            },
                          );
                        },
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  /// Compact, responsive cohort metric card
  Widget _buildMetricCard({
    required IconData icon,
    required Color iconColor,
    required String value,
    required String label,
    required String sub,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                    color: isDark ? Colors.white70 : const Color(0xFF475569),
                  ),
                ),
                Text(
                  sub,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 10,
                    color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Modern Hallmark-compliant compact class group card
  Widget _buildClassGroupCard(
    String key,
    Map<String, dynamic> rep,
    List<Map<String, dynamic>> subjects,
    bool isSelected,
    bool isDark,
  ) {
    final dept = rep['dept'] ?? 'Dept';
    final batch = rep['batch'] ?? '';
    final sem = rep['semester'] ?? 1;
    final sec = rep['section'] ?? 'A';
    final count = rep['student_count'] ?? 0;
    final isAdvisedClass = subjects.any((s) => s['is_advised_class'] == true);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _selectClassKey(key),
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? const Color(0xFF1E293B) : const Color(0xFFF0F7FF))
                : (isDark ? const Color(0xFF1E293B) : Colors.white),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? primaryBlue
                  : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
              width: isSelected ? 1.8 : 1.0,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: primaryBlue.withValues(alpha: 0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.02),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
          ),
          child: Row(
            children: [
              // Left Accent Bar (indicator for selected state)
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 3.5,
                height: 38,
                decoration: BoxDecoration(
                  color: isSelected ? primaryBlue : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 9),

              // Main Information Block
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Row 1: Cohort badge + Advisor pill + Batch
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? primaryBlue.withValues(alpha: 0.12)
                                : (isDark ? Colors.white10 : const Color(0xFFF1F5F9)),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '$dept • ${_romanSemester(sem)} – Sec $sec',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w700,
                              fontSize: 11.5,
                              color: isSelected
                                  ? primaryBlue
                                  : (isDark ? Colors.white : const Color(0xFF0F172A)),
                            ),
                          ),
                        ),
                        if (isAdvisedClass) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: emeraldGreen.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.stars_rounded, size: 11, color: emeraldGreen),
                                SizedBox(width: 3),
                                Text(
                                  'Advisor',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 9.5,
                                    color: emeraldGreen,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (batch.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Batch $batch',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 10.5,
                                color: isDark ? Colors.white54 : const Color(0xFF64748B),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),

                    const SizedBox(height: 6),

                    // Row 2: Subject tags + Student Count
                    Row(
                      children: [
                        Flexible(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ...subjects.take(1).map((s) {
                                final code = s['subject_code'] ?? '';
                                final type = s['subject_type'] ?? 'Course';
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? primaryBlue.withValues(alpha: 0.08)
                                        : (isDark ? Colors.white10 : const Color(0xFFF8FAFC)),
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(
                                      color: isSelected
                                          ? primaryBlue.withValues(alpha: 0.22)
                                          : (isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                                    ),
                                  ),
                                  child: Text(
                                    '$code • $type',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontWeight: FontWeight.w600,
                                      fontSize: 10,
                                      color: isSelected
                                          ? primaryBlue
                                          : (isDark ? Colors.white70 : const Color(0xFF475569)),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }),
                              if (subjects.length > 1) ...[
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isDark ? Colors.white10 : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(
                                    '+${subjects.length - 1} more',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontWeight: FontWeight.w600,
                                      fontSize: 9.5,
                                      color: isDark ? Colors.white54 : const Color(0xFF64748B),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),

                        const SizedBox(width: 8),

                        // Student Count
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.people_alt_outlined,
                              size: 12.5,
                              color: isDark ? Colors.white54 : const Color(0xFF64748B),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '$count',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                                color: isDark ? Colors.white70 : const Color(0xFF334155),
                              ),
                            ),
                            const SizedBox(width: 2),
                            Text(
                              'students',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 10,
                                color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Active Indicator Pill or Chevron
              if (isSelected)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: primaryBlue,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_rounded, color: Colors.white, size: 12),
                      SizedBox(width: 3),
                      Text(
                        'ACTIVE',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                          fontSize: 9.5,
                          letterSpacing: 0.4,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark ? Colors.white10 : const Color(0xFFF1F5F9),
                  ),
                  child: Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 10,
                    color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
