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
  static const Color indigoAccent = Color(0xFF6366F1);
  static const Color amberWarning = Color(0xFFF59E0B);
  static const Color roseError = Color(0xFFEF4444);

  Map<String, dynamic>? _selectedAllocation;
  List<dynamic> _classStudents = [];
  bool _isLoadingStudents = false;
  String? _studentError;
  String _searchQuery = '';
  String _selectedDeptFilter = 'ALL';

  @override
  void initState() {
    super.initState();
    if (widget.teachingAllocations.isNotEmpty) {
      _selectAllocation(widget.teachingAllocations.first as Map<String, dynamic>);
    }
  }

  @override
  void didUpdateWidget(covariant StaffHandledClassesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.teachingAllocations != widget.teachingAllocations) {
      if (_selectedAllocation == null && widget.teachingAllocations.isNotEmpty) {
        _selectAllocation(widget.teachingAllocations.first as Map<String, dynamic>);
      }
    }
  }

  void _selectAllocation(Map<String, dynamic> alloc) {
    setState(() {
      _selectedAllocation = alloc;
      _searchQuery = '';
    });
    if (widget.onClassSelected != null) {
      widget.onClassSelected!(alloc);
    }
    _fetchStudentsForClass(alloc);
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

    if (_searchQuery.trim().isNotEmpty) {
      queryParams['search'] = _searchQuery.trim();
    }

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

    final alloc = _selectedAllocation ?? {};
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

    // Collect unique departments
    final depts = <String>{'ALL'};
    for (final a in allocations) {
      if (a['dept'] != null && a['dept'].toString().isNotEmpty) {
        depts.add(a['dept'].toString());
      }
    }

    final filteredAllocations = _selectedDeptFilter == 'ALL'
        ? allocations
        : allocations.where((a) => a['dept'] == _selectedDeptFilter).toList();

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
                    'Select any handled class to view students and manage attendance',
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
                '${allocations.length} Subjects Assigned',
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

        // 2. TEACHING ALLOCATIONS CARDS GRID
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
                  'No Subject Allocations Found',
                  style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  'You currently have no teaching subjects allocated across departments.',
                  style: TextStyle(fontFamily: 'Inter', color: Colors.grey.shade500, fontSize: 12),
                ),
              ],
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 800;
              final crossAxisCount = isWide ? 3 : (constraints.maxWidth > 550 ? 2 : 1);

              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  mainAxisExtent: 145,
                ),
                itemCount: filteredAllocations.length,
                itemBuilder: (ctx, i) {
                  final alloc = filteredAllocations[i] as Map<String, dynamic>;
                  final isSelected = _selectedAllocation != null &&
                      _selectedAllocation!['dept'] == alloc['dept'] &&
                      _selectedAllocation!['semester'] == alloc['semester'] &&
                      _selectedAllocation!['section'] == alloc['section'] &&
                      _selectedAllocation!['subject_code'] == alloc['subject_code'];

                  return _buildAllocationCard(alloc, isSelected, isDark);
                },
              );
            },
          ),

        const SizedBox(height: 24),

        // 3. ENROLLED STUDENTS SECTION FOR SELECTED CLASS
        if (_selectedAllocation != null) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Selected Class Header Banner
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isCompact = constraints.maxWidth < 750;

                    final classInfo = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: primaryBlue.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${_selectedAllocation!['dept']} • Sem ${_selectedAllocation!['semester']} • Sec ${_selectedAllocation!['section']}',
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                  color: primaryBlue,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: emeraldGreen.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${_classStudents.length} Students',
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                  color: emeraldGreen,
                                ),
                              ),
                            ),
                            if (_selectedAllocation!['is_advised_class'] == true)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: emeraldGreen.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: emeraldGreen.withValues(alpha: 0.3)),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.assignment_ind_rounded, size: 12, color: emeraldGreen),
                                    SizedBox(width: 4),
                                    Text(
                                      'Your Advisee Class',
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
                        const SizedBox(height: 8),
                        Text(
                          '${_selectedAllocation!['subject_name']} (${_selectedAllocation!['subject_code']})',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    );

                    final actionButtons = Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: isCompact ? WrapAlignment.start : WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (_selectedAllocation!['is_advised_class'] == true && widget.onSwitchToAdvisedTab != null)
                          OutlinedButton.icon(
                            onPressed: widget.onSwitchToAdvisedTab,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              side: const BorderSide(color: emeraldGreen),
                              foregroundColor: emeraldGreen,
                            ),
                            icon: const Icon(Icons.assignment_ind_rounded, size: 16),
                            label: const Text('Manage Advisees', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12)),
                          ),
                        OutlinedButton.icon(
                          onPressed: _exportClassCSV,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.file_download_outlined, size: 16),
                          label: const Text('Export CSV', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 12)),
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
                          label: const Text('Mark Class Attendance', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12)),
                        ),
                      ],
                    );

                    if (isCompact) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          classInfo,
                          const SizedBox(height: 14),
                          actionButtons,
                        ],
                      );
                    } else {
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(child: classInfo),
                          const SizedBox(width: 16),
                          Flexible(child: actionButtons),
                        ],
                      );
                    }
                  },
                ),

                const SizedBox(height: 16),

                // Search Box
                TextField(
                  onChanged: (val) {
                    setState(() => _searchQuery = val);
                    _fetchStudentsForClass(_selectedAllocation!);
                  },
                  decoration: InputDecoration(
                    hintText: 'Search student by name, register number or roll number...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Student Cards Grid
                if (_isLoadingStudents)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 30),
                      child: CircularProgressIndicator(color: primaryBlue),
                    ),
                  )
                else if (_studentError != null)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 30),
                      child: Text(_studentError!, style: const TextStyle(color: roseError)),
                    ),
                  )
                else if (_classStudents.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 30),
                      child: Column(
                        children: [
                          Icon(Icons.people_outline_rounded, size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 8),
                          const Text(
                            'No Students Found in this Class',
                            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'No student records matched the class filter criteria.',
                            style: TextStyle(fontFamily: 'Inter', color: Colors.grey.shade500, fontSize: 12),
                          ),
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
                        itemCount: _classStudents.length,
                        itemBuilder: (ctx, i) {
                          final s = _classStudents[i];
                          return StudentCard(
                            student: s,
                            onTap: () => StudentDetailsDialog.show(
                              context,
                              student: s,
                              onEdit: () => StudentEditDialog.show(
                                context,
                                token: widget.token,
                                student: s,
                                onUpdated: () => _fetchStudentsForClass(_selectedAllocation!),
                              ),
                              onReEnrollFace: () => StudentRegistrationDialog.show(
                                context,
                                token: widget.token,
                                user: widget.user,
                                initialDept: s['dept'],
                                isDeptLocked: true,
                                initialStudent: s,
                                isReEnroll: true,
                                onStudentRegistered: () => _fetchStudentsForClass(_selectedAllocation!),
                              ),
                              onToggleStatus: () => _toggleStudentStatus(s['reg_no']),
                            ),
                            onEdit: () => StudentEditDialog.show(
                              context,
                              token: widget.token,
                              student: s,
                              onUpdated: () => _fetchStudentsForClass(_selectedAllocation!),
                            ),
                            onReEnrollFace: () => StudentRegistrationDialog.show(
                              context,
                              token: widget.token,
                              user: widget.user,
                              initialDept: s['dept'],
                              isDeptLocked: true,
                              initialStudent: s,
                              isReEnroll: true,
                              onStudentRegistered: () => _fetchStudentsForClass(_selectedAllocation!),
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
          ),
        ],
      ],
    );
  }

  Widget _buildAllocationCard(Map<String, dynamic> alloc, bool isSelected, bool isDark) {
    final dept = alloc['dept'] ?? 'Dept';
    final sem = alloc['semester'] ?? 1;
    final sec = alloc['section'] ?? 'A';
    final code = alloc['subject_code'] ?? '';
    final name = alloc['subject_name'] ?? 'Subject';
    final type = alloc['subject_type'] ?? 'Theory';
    final hours = alloc['weekly_hours'] ?? 4;
    final count = alloc['student_count'] ?? 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _selectAllocation(alloc),
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected
                ? primaryBlue.withValues(alpha: isDark ? 0.22 : 0.08)
                : (isDark ? const Color(0xFF1E293B) : Colors.white),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? primaryBlue
                  : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
              width: isSelected ? 2.0 : 1.0,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: primaryBlue.withValues(alpha: 0.15),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: primaryBlue.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$dept • Sem $sem • Sec $sec',
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                              color: primaryBlue,
                            ),
                          ),
                        ),
                        if (alloc['is_advised_class'] == true)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: emeraldGreen.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.assignment_ind_rounded, size: 10, color: emeraldGreen),
                                SizedBox(width: 3),
                                Text(
                                  'Advised',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 9,
                                    color: emeraldGreen,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (isSelected)
                    const Icon(Icons.check_circle_rounded, color: primaryBlue, size: 18)
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: (type == 'Practical' || type == 'Lab' ? indigoAccent : amberWarning)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        type,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                          fontSize: 10,
                          color: type == 'Practical' || type == 'Lab' ? indigoAccent : amberWarning,
                        ),
                      ),
                    ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    code,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: isSelected ? primaryBlue : (isDark ? Colors.white70 : const Color(0xFF475569)),
                    ),
                  ),
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$hours Hrs/Week',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11,
                      color: isDark ? Colors.white54 : const Color(0xFF64748B),
                    ),
                  ),
                  Row(
                    children: [
                      Icon(Icons.people_alt_outlined, size: 14, color: isDark ? Colors.white54 : const Color(0xFF64748B)),
                      const SizedBox(width: 4),
                      Text(
                        '$count Students',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                          color: isDark ? Colors.white70 : const Color(0xFF334155),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
