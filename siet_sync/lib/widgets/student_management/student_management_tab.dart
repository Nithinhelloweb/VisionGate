import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../config/college_ip_config.dart';
import '../student/student_registration_dialog.dart';
import '../student/student_bulk_import_dialog.dart';
import 'student_filter_bar.dart';
import 'student_card.dart';
import 'student_details_dialog.dart';
import 'student_edit_dialog.dart';
import 'staff_handled_classes_view.dart';

/// Hallmark-compliant Student Directory & Management Hub
/// Designed with:
/// - Role-based access scoping (Admin, HOD, and Staff with dual-section separation)
/// - Section 1: My Advised Class (Class Advisor & Co-Advisor Management)
/// - Section 2: My Handled Classes & Subjects (Subject Teaching Allocations Drilldown)
/// - 100% Roman upright headings (font-style: normal)
/// - Locked semantic color tokens
/// - 8-State interactive design coverage
class StudentManagementTab extends StatefulWidget {
  final String token;
  final Map<String, dynamic> user;
  final bool isAdmin;
  final bool isHod;
  final bool isStaff;
  final String? defaultDept;
  final String? staffRegNo;
  final void Function(int tabIndex)? onNavigateToTab;

  const StudentManagementTab({
    super.key,
    required this.token,
    required this.user,
    this.isAdmin = false,
    this.isHod = false,
    this.isStaff = false,
    this.defaultDept,
    this.staffRegNo,
    this.onNavigateToTab,
  });

  @override
  State<StudentManagementTab> createState() => _StudentManagementTabState();
}

class _StudentManagementTabState extends State<StudentManagementTab> {
  static const Color primaryBlue = Color(0xFF2563EB);
  static const Color emeraldGreen = Color(0xFF10B981);
  static const Color indigoAccent = Color(0xFF6366F1);
  static const Color roseError = Color(0xFFEF4444);

  // Staff Dual-Section State (0: My Advised Class, 1: My Handled Classes & Subjects)
  int _staffActiveSection = 0;
  Map<String, dynamic>? _staffAllocationsBundle;
  bool _isLoadingStaffBundle = false;
  int _selectedAdvisedClassIndex = 0;

  List<dynamic> _students = [];
  bool _isLoading = true;
  String? _errorMessage;
  List<String> _availableBatches = [];

  // Filters
  String _selectedDept = 'ALL';
  String _selectedBatch = 'ALL';
  int? _selectedSemester;
  String _selectedSemesterType = 'ALL'; // 'ALL', 'ODD', 'EVEN'
  String _selectedSection = 'ALL';
  String _selectedFaceStatus = 'ALL'; // 'ALL', 'ENROLLED', 'MISSING'
  String _selectedAccountStatus = 'ALL'; // 'ALL', 'ACTIVE', 'SUSPENDED'
  bool _myClassOnly = false;
  String _searchQuery = '';

  String get _currentStaffRegNo => (widget.staffRegNo ?? widget.user['reg_no'] ?? widget.user['regNo'] ?? '').toString();

  @override
  void initState() {
    super.initState();
    if (widget.isHod && widget.defaultDept != null) {
      _selectedDept = widget.defaultDept!.trim();
      _fetchStudents();
    } else if (widget.isStaff) {
      _selectedDept = (widget.defaultDept ?? widget.user['dept'] ?? 'CSE').toString().trim();
      _myClassOnly = true;
      _initStaffView();
    } else {
      _fetchStudents();
    }
  }

  Future<void> _initStaffView() async {
    await _fetchStaffAllocations();
    await _fetchStudents();
  }

  Future<void> _fetchStaffAllocations() async {
    setState(() => _isLoadingStaffBundle = true);
    try {
      final res = await http.get(
        Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/staff/student-hub/allocations'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            _staffAllocationsBundle = data;
            _isLoadingStaffBundle = false;
            // Align advisee class filter if present
            final adv = (data['advised_classes'] as List?) ?? [];
            if (adv.isNotEmpty) {
              if (_selectedAdvisedClassIndex >= adv.length) {
                _selectedAdvisedClassIndex = 0;
              }
              final activeAdv = adv[_selectedAdvisedClassIndex];
              _selectedDept = (activeAdv['dept'] ?? _selectedDept).toString();
              _selectedBatch = (activeAdv['batch'] ?? _selectedBatch).toString();
              _selectedSemester = activeAdv['semester'] is int ? activeAdv['semester'] : int.tryParse(activeAdv['semester'].toString());
              _selectedSection = (activeAdv['section'] ?? _selectedSection).toString();
            }
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingStaffBundle = false);
    }
  }

  Future<void> _fetchStudents() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final queryParams = <String, String>{
      'limit': '10000',
      'offset': '0',
    };

    if (widget.isStaff && _staffActiveSection == 0) {
      final advList = (_staffAllocationsBundle?['advised_classes'] as List?) ?? [];
      if (advList.isNotEmpty) {
        final safeIdx = _selectedAdvisedClassIndex.clamp(0, advList.length - 1);
        final activeAdv = advList[safeIdx] as Map<String, dynamic>;
        if (activeAdv['dept'] != null && activeAdv['dept'].toString().isNotEmpty) {
          _selectedDept = activeAdv['dept'].toString();
          queryParams['dept'] = _selectedDept;
        }
        if (activeAdv['batch'] != null && activeAdv['batch'].toString().isNotEmpty) {
          _selectedBatch = activeAdv['batch'].toString();
          queryParams['batch'] = _selectedBatch;
        }
        if (activeAdv['section'] != null && activeAdv['section'].toString().isNotEmpty) {
          _selectedSection = activeAdv['section'].toString();
          queryParams['section'] = _selectedSection;
        }
      }
      queryParams['scope_mode'] = 'advised';
      queryParams['my_class_only'] = 'true';
      if (_currentStaffRegNo.isNotEmpty) {
        queryParams['mentor'] = _currentStaffRegNo;
      }
    } else {
      if (_selectedDept != 'ALL') {
        queryParams['dept'] = _selectedDept;
      }
      if (_selectedBatch != 'ALL') {
        queryParams['batch'] = _selectedBatch;
      }
      if (_selectedSemester != null) {
        queryParams['semester'] = '$_selectedSemester';
      } else if (_selectedSemesterType != 'ALL') {
        queryParams['semester_type'] = _selectedSemesterType.toLowerCase();
      }
      if (_selectedSection != 'ALL') {
        queryParams['section'] = _selectedSection;
      }
    }

    if (_selectedFaceStatus != 'ALL') {
      queryParams['face_status'] = _selectedFaceStatus.toLowerCase();
    }
    if (_selectedAccountStatus != 'ALL') {
      queryParams['status'] = _selectedAccountStatus.toLowerCase();
    }
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
        final meta = data['academic_meta'] as Map<String, dynamic>?;
        if (mounted) {
          setState(() {
            _students = data['students'] ?? [];
            if (meta != null && meta['batches'] is List) {
              _availableBatches = (meta['batches'] as List).map((e) => e.toString()).toList();
            }
            _isLoading = false;
          });
        }
      } else {
        final err = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            _errorMessage = err['detail'] ?? 'Failed to load students.';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Network error: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _openRegisterDialog() {
    StudentRegistrationDialog.show(
      context,
      token: widget.token,
      user: widget.user,
      initialDept: widget.isHod || widget.isStaff ? (widget.defaultDept ?? widget.user['dept']) : null,
      isDeptLocked: widget.isHod || widget.isStaff,
      onStudentRegistered: () {
        _fetchStudents();
        if (widget.isStaff) _fetchStaffAllocations();
      },
    );
  }

  void _openBulkImportDialog() {
    StudentBulkImportDialog.show(
      context,
      token: widget.token,
      user: widget.user,
      isAdmin: widget.isAdmin,
      isHod: widget.isHod,
      isStaff: widget.isStaff,
      initialDept: _selectedDept == 'ALL' ? (widget.defaultDept ?? widget.user['dept'] ?? 'CSE') : _selectedDept,
      initialBatch: _selectedBatch == 'ALL' ? '2024-2028' : _selectedBatch,
      initialSection: _selectedSection == 'ALL' ? 'A' : _selectedSection,
      onStudentsImported: () {
        _fetchStudents();
        if (widget.isStaff) _fetchStaffAllocations();
      },
    );
  }

  Future<void> _toggleStudentStatus(String regNo) async {
    try {
      final res = await http.post(
        Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/students/$regNo/toggle-status'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (res.statusCode == 200) {
        _fetchStudents();
      }
    } catch (e) {
      debugPrint("Toggle status error: $e");
    }
  }

  Future<void> _toggleStudentReregisterPermission(String regNo) async {
    try {
      final res = await http.post(
        Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/students/$regNo/toggle-reregister-permission'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (res.statusCode == 200) {
        _fetchStudents();
      }
    } catch (e) {
      debugPrint("Toggle re-registration error: $e");
    }
  }

  Future<void> _confirmDeleteStudent(String regNo, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Student Deletion'),
        content: Text('Are you sure you want to permanently delete student "$name" ($regNo) and all associated face biometric profiles?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: roseError, foregroundColor: Colors.white),
            child: const Text('Delete Student'),
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
        if (res.statusCode == 200) {
          _fetchStudents();
        }
      } catch (e) {
        debugPrint("Delete student error: $e");
      }
    }
  }

  void _exportStudentsToCSV() {
    if (_students.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No student records available to export.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final buffer = StringBuffer();
    buffer.writeln('Reg No,Roll No,Name,Department,Degree,Batch,Semester,Section,Biometric Status,Phone,Status');

    for (final s in _students) {
      final hasFace = (s['has_face'] == true) || (s['face_samples_count'] ?? 0) > 0;
      final isSuspended = (s['suspended'] == true);
      buffer.writeln(
        '${s['reg_no'] ?? ""},'
        '${s['roll_no'] ?? ""},'
        '"${s['name'] ?? ""}",'
        '${s['dept'] ?? ""},'
        '${s['degree'] ?? ""},'
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
            Text('Export Student Directory (${_students.length} records)'),
          ],
        ),
        content: SizedBox(
          width: 550,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Filtered CSV dataset generated successfully. You can copy it directly to clipboard:', style: TextStyle(fontSize: 13)),
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
                  content: Text('CSV data copied to clipboard!'),
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isMobile = screenWidth < 650;
    final totalStudents = _students.length;
    final faceEnrolledCount = _students.where((s) => s['has_face'] == true || (s['face_samples_count'] ?? 0) > 0).length;
    final activeCount = _students.where((s) => s['suspended'] != true).length;
    final facePct = totalStudents > 0 ? ((faceEnrolledCount / totalStudents) * 100).toStringAsFixed(1) : '0.0';

    final advisedClasses = (_staffAllocationsBundle?['advised_classes'] as List?) ?? [];
    final teachingAllocations = (_staffAllocationsBundle?['teaching_allocations'] as List?) ?? [];

    return RefreshIndicator(
      onRefresh: () async {
        if (widget.isStaff) await _fetchStaffAllocations();
        await _fetchStudents();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 12 : 20,
          vertical: isMobile ? 12 : 20,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // TOP HEADER: Title, Count, & Register Action
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 650;
                final headerText = widget.isAdmin
                    ? 'University Student Directory'
                    : (widget.isHod
                        ? '${widget.defaultDept ?? widget.user['dept'] ?? 'Dept'} Students'
                        : 'Advisee Class Roster');

                return isWide
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                headerText,
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 20,
                                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.isStaff
                                    ? 'Advisee class students & biometric status'
                                    : (widget.isHod
                                        ? 'Manage department students, multi-semester scoping, and biometric profiles'
                                        : 'Manage enrolled university students, multi-semester scoping, and biometric profiles'),
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  color: isDark ? Colors.white60 : const Color(0xFF64748B),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: _exportStudentsToCSV,
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                                icon: const Icon(Icons.file_download_outlined, size: 18),
                                label: const Text('Export CSV', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700)),
                              ),
                              OutlinedButton.icon(
                                onPressed: _openBulkImportDialog,
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  side: const BorderSide(color: primaryBlue),
                                  foregroundColor: primaryBlue,
                                ),
                                icon: const Icon(Icons.file_upload_outlined, size: 18),
                                label: const Text('Bulk Import', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700)),
                              ),
                              if (!widget.isStaff)
                                ElevatedButton.icon(
                                  onPressed: _openRegisterDialog,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: primaryBlue,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
                                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                                  label: const Text('Register Student', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700)),
                                ),
                            ],
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            headerText,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w700,
                              fontSize: 17,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.isStaff
                                ? 'Advisee class students & biometric status'
                                : (widget.isHod
                                    ? 'Department students & biometric profiles'
                                    : 'Manage enrolled students'),
                            style: TextStyle(
                              fontFamily: 'Inter',
                              color: isDark ? Colors.white60 : const Color(0xFF64748B),
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: _exportStudentsToCSV,
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                icon: const Icon(Icons.file_download_outlined, size: 15),
                                label: const Text('Export CSV', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              ),
                              OutlinedButton.icon(
                                onPressed: _openBulkImportDialog,
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  side: const BorderSide(color: primaryBlue),
                                  foregroundColor: primaryBlue,
                                ),
                                icon: const Icon(Icons.file_upload_outlined, size: 15),
                                label: const Text('Bulk Import', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              ),
                              if (!widget.isStaff)
                                ElevatedButton.icon(
                                  onPressed: _openRegisterDialog,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: primaryBlue,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 15),
                                  label: const Text('Register Student', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                ),
                            ],
                          ),
                        ],
                      );
              },
            ),

            const SizedBox(height: 14),

            // -------------------------------------------------------------
            // STAFF DUAL-SECTION SEGMENTED SWITCHER (Exclusive to Staff Role)
            // -------------------------------------------------------------
            if (widget.isStaff) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    // Section 1: My Advised Class
                    Expanded(
                      child: _buildStaffSectionTab(
                        index: 0,
                        title: isMobile ? 'Advised Class' : 'My Advised Class',
                        subtitle: advisedClasses.isNotEmpty
                            ? '${(advisedClasses[_selectedAdvisedClassIndex.clamp(0, advisedClasses.length - 1)] as Map<String, dynamic>)['dept']} • Sec ${(advisedClasses[_selectedAdvisedClassIndex.clamp(0, advisedClasses.length - 1)] as Map<String, dynamic>)['section']}'
                            : 'Class Advisor',
                        icon: Icons.assignment_ind_rounded,
                        countBadge: advisedClasses.length,
                        isSelected: _staffActiveSection == 0,
                        isDark: isDark,
                        isMobile: isMobile,
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Section 2: My Handled Classes & Subjects
                    Expanded(
                      child: _buildStaffSectionTab(
                        index: 1,
                        title: isMobile ? 'Handled Classes' : 'Handled Classes & Subjects',
                        subtitle: isMobile ? '${teachingAllocations.length} Subjects' : '${teachingAllocations.length} Subjects Assigned',
                        icon: Icons.menu_book_rounded,
                        countBadge: teachingAllocations.length,
                        isSelected: _staffActiveSection == 1,
                        isDark: isDark,
                        isMobile: isMobile,
                      ),
                    ),
                  ],
                ),
              ),
              if (_isLoadingStaffBundle) ...[
                const SizedBox(height: 8),
                const LinearProgressIndicator(
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(primaryBlue),
                ),
              ],
              const SizedBox(height: 14),
            ],

            // -------------------------------------------------------------
            // SECTION CONTENT BRANCHING
            // -------------------------------------------------------------
            if (widget.isStaff && _staffActiveSection == 1) ...[
              // Section 2: Handled Classes & Teaching Subjects View
              StaffHandledClassesView(
                token: widget.token,
                user: widget.user,
                teachingAllocations: teachingAllocations,
                onRefresh: () async {
                  await _fetchStaffAllocations();
                },
                onSwitchToAdvisedTab: () {
                  setState(() {
                    _staffActiveSection = 0;
                  });
                  _fetchStudents();
                },
              ),
            ] else ...[
              // Section 1: Advised Class (Or Standard View for Admin / HOD)

              // Advised Class Banner for Staff
              if (widget.isStaff && advisedClasses.isNotEmpty) ...[
                _buildAdvisedClassBanner(advisedClasses, isDark, isMobile: isMobile),
                const SizedBox(height: 14),
              ],

              // Metric Summary Strip
              Row(
                children: [
                  Expanded(
                    child: _buildMetricTile(
                      isMobile ? 'Advisees' : (widget.isStaff ? 'Advisees Enrolled' : 'Total Enrolled'),
                      '$totalStudents',
                      Icons.groups_outlined,
                      primaryBlue,
                      isDark,
                      isMobile: isMobile,
                    ),
                  ),
                  SizedBox(width: isMobile ? 8 : 10),
                  Expanded(
                    child: _buildMetricTile(
                      isMobile ? 'Biometric' : 'Biometric Ready',
                      '$facePct%',
                      Icons.face_rounded,
                      emeraldGreen,
                      isDark,
                      isMobile: isMobile,
                    ),
                  ),
                  SizedBox(width: isMobile ? 8 : 10),
                  Expanded(
                    child: _buildMetricTile(
                      isMobile ? 'Active' : 'Active Records',
                      '$activeCount',
                      Icons.verified_user_outlined,
                      indigoAccent,
                      isDark,
                      isMobile: isMobile,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Filter Bar
              StudentFilterBar(
                isAdmin: widget.isAdmin,
                isHod: widget.isHod,
                isStaff: widget.isStaff,
                selectedDept: _selectedDept,
                selectedBatch: _selectedBatch,
                selectedSemester: _selectedSemester,
                selectedSemesterType: _selectedSemesterType,
                selectedSection: _selectedSection,
                selectedFaceStatus: _selectedFaceStatus,
                selectedAccountStatus: _selectedAccountStatus,
                myClassOnly: _myClassOnly,
                searchQuery: _searchQuery,
                availableBatches: _availableBatches,
                onDeptChanged: (v) {
                  setState(() => _selectedDept = v);
                  _fetchStudents();
                },
                onBatchChanged: (v) {
                  setState(() => _selectedBatch = v);
                  _fetchStudents();
                },
                onSemesterChanged: (v) {
                  setState(() => _selectedSemester = v);
                  _fetchStudents();
                },
                onSemesterTypeChanged: (v) {
                  setState(() => _selectedSemesterType = v);
                  _fetchStudents();
                },
                onSectionChanged: (v) {
                  setState(() => _selectedSection = v);
                  _fetchStudents();
                },
                onFaceStatusChanged: (v) {
                  setState(() => _selectedFaceStatus = v);
                  _fetchStudents();
                },
                onAccountStatusChanged: (v) {
                  setState(() => _selectedAccountStatus = v);
                  _fetchStudents();
                },
                onMyClassOnlyChanged: (v) {
                  setState(() => _myClassOnly = v);
                  _fetchStudents();
                },
                onSearchChanged: (v) {
                  setState(() => _searchQuery = v);
                  _fetchStudents();
                },
                onClearFilters: () {
                  setState(() {
                    _selectedDept = widget.isAdmin ? 'ALL' : (widget.defaultDept ?? 'CSE');
                    _selectedBatch = 'ALL';
                    _selectedSemester = null;
                    _selectedSemesterType = 'ALL';
                    _selectedSection = 'ALL';
                    _selectedFaceStatus = 'ALL';
                    _selectedAccountStatus = 'ALL';
                    _searchQuery = '';
                    if (widget.isStaff) _myClassOnly = true;
                  });
                  _fetchStudents();
                },
              ),
              const SizedBox(height: 16),

              // Student Grid Content
              if (_isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: CircularProgressIndicator(color: primaryBlue),
                  ),
                )
              else if (_errorMessage != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Text(_errorMessage!, style: const TextStyle(color: roseError)),
                  ),
                )
              else if (_students.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      children: [
                        Icon(Icons.person_search_outlined, size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        Text(
                          widget.isStaff
                              ? 'No Advised Class Students Found'
                              : 'No Students Found',
                          style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 16),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.isStaff
                              ? 'You have no students listed under this advisee class, or try adjusting the filters.'
                              : 'Try adjusting your search criteria or register a new student.',
                          style: TextStyle(fontFamily: 'Inter', color: Colors.grey.shade500, fontSize: 13),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          alignment: WrapAlignment.center,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _openBulkImportDialog,
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: primaryBlue),
                                foregroundColor: primaryBlue,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              icon: const Icon(Icons.file_upload_outlined, size: 18),
                              label: const Text('Bulk Import (CSV / Excel)', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700)),
                            ),
                            if (!widget.isStaff)
                              ElevatedButton.icon(
                                onPressed: _openRegisterDialog,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryBlue,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                icon: const Icon(Icons.add_rounded, size: 18),
                                label: const Text('Register New Student', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700)),
                              ),
                          ],
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
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                        mainAxisExtent: 175,
                      ),
                      itemCount: _students.length,
                      itemBuilder: (ctx, i) {
                        final s = _students[i];
                        return StudentCard(
                          student: s,
                          onTap: () => StudentDetailsDialog.show(
                            context,
                            student: s,
                            onEdit: () => StudentEditDialog.show(
                              context,
                              token: widget.token,
                              student: s,
                              onUpdated: _fetchStudents,
                            ),
                            onReEnrollFace: () => StudentRegistrationDialog.show(
                              context,
                              token: widget.token,
                              user: widget.user,
                              initialDept: s['dept'],
                              isDeptLocked: widget.isHod || widget.isStaff,
                              initialStudent: s,
                              isReEnroll: true,
                              onStudentRegistered: _fetchStudents,
                            ),
                            onToggleStatus: () => _toggleStudentStatus(s['reg_no']),
                            onToggleReregisterPermission: () => _toggleStudentReregisterPermission(s['reg_no']),
                          ),
                          onEdit: () => StudentEditDialog.show(
                            context,
                            token: widget.token,
                            student: s,
                            onUpdated: _fetchStudents,
                          ),
                          onReEnrollFace: () => StudentRegistrationDialog.show(
                            context,
                            token: widget.token,
                            user: widget.user,
                            initialDept: s['dept'],
                            isDeptLocked: widget.isHod || widget.isStaff,
                            initialStudent: s,
                            isReEnroll: true,
                            onStudentRegistered: _fetchStudents,
                          ),
                          onToggleStatus: () => _toggleStudentStatus(s['reg_no']),
                          onDelete: () => _confirmDeleteStudent(s['reg_no'], s['name']),
                        );
                      },
                    );
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStaffSectionTab({
    required int index,
    required String title,
    required String subtitle,
    required IconData icon,
    required int countBadge,
    required bool isSelected,
    required bool isDark,
    bool isMobile = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            _staffActiveSection = index;
          });
          if (index == 0) {
            _fetchStudents();
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 8 : 14,
            vertical: isMobile ? 8 : 10,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? const Color(0xFF0F172A) : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(isMobile ? 6 : 8),
                decoration: BoxDecoration(
                  color: (isSelected ? primaryBlue : (isDark ? Colors.white12 : Colors.grey.shade300))
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(isMobile ? 8 : 10),
                ),
                child: Icon(
                  icon,
                  size: isMobile ? 16 : 20,
                  color: isSelected ? primaryBlue : (isDark ? Colors.white60 : Colors.grey.shade700),
                ),
              ),
              SizedBox(width: isMobile ? 6 : 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w700,
                        fontSize: isMobile ? 12 : 13,
                        color: isSelected
                            ? (isDark ? Colors.white : const Color(0xFF0F172A))
                            : (isDark ? Colors.white60 : const Color(0xFF64748B)),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: isMobile ? 10 : 11,
                        color: isSelected ? primaryBlue : (isDark ? Colors.white38 : Colors.grey.shade500),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (countBadge > 0)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: isMobile ? 6 : 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: (isSelected ? primaryBlue : Colors.grey).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$countBadge',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      fontSize: isMobile ? 10 : 11,
                      color: isSelected ? primaryBlue : Colors.grey.shade600,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAdvisedClassBanner(List<dynamic> advisedClasses, bool isDark, {bool isMobile = false}) {
    final activeAdv = advisedClasses[_selectedAdvisedClassIndex.clamp(0, advisedClasses.length - 1)] as Map<String, dynamic>;
    final dept = (activeAdv['dept'] ?? _selectedDept).toString();
    final batch = (activeAdv['batch'] ?? _selectedBatch).toString();
    final sec = (activeAdv['section'] ?? _selectedSection).toString();
    final advisorType = (activeAdv['advisor_type'] ?? 'primary').toString().replaceAll('_', ' ').toUpperCase();

    // Dynamically resolve active semester from loaded advisees or allocation metadata
    dynamic resolvedSem = activeAdv['semester'];
    if (_students.isNotEmpty) {
      for (final s in _students) {
        if (s['semester'] != null) {
          resolvedSem = s['semester'];
          break;
        }
      }
    }
    final sem = resolvedSem ?? _selectedSemester ?? 1;
    final studentCount = _students.length;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(isMobile ? 16 : 20),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFBFDBFE),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(isMobile ? 8 : 12),
            decoration: BoxDecoration(
              color: primaryBlue.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(isMobile ? 10 : 14),
            ),
            child: Icon(Icons.school_rounded, color: primaryBlue, size: isMobile ? 22 : 28),
          ),
          SizedBox(width: isMobile ? 10 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: emeraldGreen.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        advisorType.contains('CO') ? 'CO-ADVISOR' : 'PRIMARY ADVISOR',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                          fontSize: 9,
                          color: emeraldGreen,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    Text(
                      '• Batch $batch',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: isMobile ? 11 : 12,
                        color: isDark ? Colors.white60 : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  isMobile
                      ? '$dept • Sem $sem-$sec • $studentCount Advisees'
                      : 'Department of $dept • Semester $sem-$sec • $studentCount Advisees',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w700,
                    fontSize: isMobile ? 14 : 16,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (activeAdv['is_teaching_in_this_class'] == true &&
                    (activeAdv['taught_subjects'] as List?)?.isNotEmpty == true) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: primaryBlue.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: primaryBlue.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.menu_book_rounded, size: 12, color: primaryBlue),
                            const SizedBox(width: 4),
                            Text(
                              isMobile
                                  ? 'Teaching: ${(activeAdv['taught_subjects'] as List).map((s) => s['subject_code']).join(', ')}'
                                  : 'Also Teaching: ${(activeAdv['taught_subjects'] as List).map((s) => '${s['subject_code']} - ${s['subject_name']}').join(' • ')}',
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                                color: primaryBlue,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ],
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          setState(() {
                            _staffActiveSection = 1;
                          });
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white10 : Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isDark ? Colors.white24 : const Color(0xFFBFDBFE),
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Subject View',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                  color: primaryBlue,
                                ),
                              ),
                              SizedBox(width: 3),
                              Icon(Icons.arrow_forward_rounded, size: 12, color: primaryBlue),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (advisedClasses.length > 1) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark ? Colors.white24 : const Color(0xFFBFDBFE),
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _selectedAdvisedClassIndex.clamp(0, advisedClasses.length - 1),
                  isDense: true,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                    fontSize: isMobile ? 11 : 12,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: primaryBlue),
                  items: List.generate(advisedClasses.length, (idx) {
                    final c = advisedClasses[idx] as Map<String, dynamic>;
                    final batchStr = c['batch'] != null && c['batch'].toString().isNotEmpty ? ' (${c['batch']})' : '';
                    return DropdownMenuItem<int>(
                      value: idx,
                      child: Text('${c['dept']} - Sec ${c['section']}$batchStr'),
                    );
                  }),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedAdvisedClassIndex = val;
                        final sel = advisedClasses[val];
                        _selectedDept = (sel['dept'] ?? _selectedDept).toString();
                        _selectedBatch = (sel['batch'] ?? _selectedBatch).toString();
                        _selectedSemester = sel['semester'] is int ? sel['semester'] : int.tryParse(sel['semester'].toString());
                        _selectedSection = (sel['section'] ?? _selectedSection).toString();
                      });
                      _fetchStudents();
                    }
                  },
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricTile(String label, String value, IconData icon, Color color, bool isDark, {bool isMobile = false}) {
    if (isMobile) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 16),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white60 : const Color(0xFF64748B),
                fontSize: 11,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    color: isDark ? Colors.white60 : const Color(0xFF64748B),
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
