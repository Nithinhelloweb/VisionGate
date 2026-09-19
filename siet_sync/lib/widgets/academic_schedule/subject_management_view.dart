import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../../config/college_ip_config.dart';
import '../../theme/admin_theme.dart';

class SubjectManagementView extends StatefulWidget {
  final String token;
  final String userRole;
  final String userDept;
  final String currentSelectedDept;
  final VoidCallback? onSubjectCatalogChanged;
  final ValueChanged<String>? onDepartmentChanged;

  const SubjectManagementView({
    super.key,
    required this.token,
    required this.userRole,
    required this.userDept,
    required this.currentSelectedDept,
    this.onSubjectCatalogChanged,
    this.onDepartmentChanged,
  });

  @override
  State<SubjectManagementView> createState() => _SubjectManagementViewState();
}

class _SubjectManagementViewState extends State<SubjectManagementView> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _subjects = [];
  Map<String, dynamic> _stats = {
    'total_subjects': 0,
    'theory_count': 0,
    'lab_count': 0,
    'elective_count': 0,
    'total_credits': 0.0,
  };

  late String _selectedDept;
  int _selectedSemesterFilter = 0; // 0 = ALL, 1..8
  String _selectedCategoryFilter = 'ALL';
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();
  bool _isGroupedView = false; // false = Grid Cards, true = Semester Roadmap View

  final List<String> _categories = [
    'ALL',
    'Theory',
    'Laboratory',
    'Elective',
    'Project',
    'Integrated',
    'Value Added'
  ];

  bool get _isHod => widget.userRole.toLowerCase().contains('hod');

  @override
  void initState() {
    super.initState();
    _selectedDept = (_isHod && widget.userDept.isNotEmpty) ? widget.userDept : widget.currentSelectedDept;
    _loadSubjects();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SubjectManagementView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentSelectedDept != widget.currentSelectedDept && !_isHod) {
      _selectedDept = widget.currentSelectedDept;
      _loadSubjects();
    }
  }

  Future<void> _loadSubjects() async {
    setState(() => _isLoading = true);
    try {
      // 1. Fetch subjects
      final queryParams = <String, String>{
        'dept': _selectedDept,
      };
      if (_selectedSemesterFilter > 0) {
        queryParams['semester'] = _selectedSemesterFilter.toString();
      }
      if (_selectedCategoryFilter != 'ALL') {
        queryParams['subject_type'] = _selectedCategoryFilter;
      }
      if (_searchQuery.trim().isNotEmpty) {
        queryParams['search'] = _searchQuery.trim();
      }

      final uri = Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/academics/subjects').replace(queryParameters: queryParams);
      final res = await http.get(uri, headers: {'Authorization': 'Bearer ${widget.token}'});

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        _subjects = List<Map<String, dynamic>>.from(data['subjects'] ?? []);
      }

      // 2. Fetch Stats
      final statsUri = Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/academics/subjects/stats?dept=${Uri.encodeComponent(_selectedDept)}');
      final statsRes = await http.get(statsUri, headers: {'Authorization': 'Bearer ${widget.token}'});
      if (statsRes.statusCode == 200) {
        _stats = Map<String, dynamic>.from(jsonDecode(statsRes.body));
      }
    } catch (e) {
      debugPrint('Error loading subjects: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openAddEditSubjectDialog([Map<String, dynamic>? initial, int? defaultSem]) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEditing = initial != null;

    final codeCtrl = TextEditingController(text: initial?['subject_code'] ?? '');
    final nameCtrl = TextEditingController(text: initial?['subject_name'] ?? '');
    final shortNameCtrl = TextEditingController(text: initial?['short_name'] ?? '');
    final creditsCtrl = TextEditingController(text: (initial?['credits'] ?? 3.0).toString());
    final hoursCtrl = TextEditingController(text: (initial?['weekly_hours'] ?? 4).toString());
    final regCtrl = TextEditingController(text: initial?['regulation'] ?? '2021');
    final labDetailsCtrl = TextEditingController(text: initial?['lab_details'] ?? '');

    int sem = (initial?['semester'] as num?)?.toInt() ?? defaultSem ?? (_selectedSemesterFilter > 0 ? _selectedSemesterFilter : 1);
    String type = initial?['subject_type'] ?? 'Theory';
    bool isLab = initial?['is_lab'] == true || type.toLowerCase().contains('lab');
    bool isActive = initial?['is_active'] ?? true;
    bool isSaving = false;
    String? errorMsg;

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
                child: Icon(isEditing ? Icons.edit_note_rounded : Icons.library_add_rounded, color: AdminColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isEditing ? 'Edit Curriculum Course' : 'Add Course to Curriculum',
                      style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AdminColors.getTextPrimary(isDark)),
                    ),
                    Text('Department: $_selectedDept', style: GoogleFonts.inter(fontSize: 12, color: AdminColors.getTextSecondary(isDark))),
                  ],
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (errorMsg != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: AdminColors.dangerSoft, borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, size: 16, color: AdminColors.danger),
                          const SizedBox(width: 8),
                          Expanded(child: Text(errorMsg!, style: GoogleFonts.inter(fontSize: 11, color: AdminColors.danger))),
                        ],
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: codeCtrl,
                          decoration: InputDecoration(
                            labelText: 'Subject Code *',
                            hintText: 'e.g. CS3492',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: shortNameCtrl,
                          decoration: InputDecoration(
                            labelText: 'Acronym',
                            hintText: 'e.g. DBMS',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Subject Title *',
                      hintText: 'e.g. Database Management Systems',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: sem,
                          items: List.generate(8, (i) => i + 1).map((s) => DropdownMenuItem(value: s, child: Text('Semester $s'))).toList(),
                          decoration: InputDecoration(labelText: 'Semester', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), isDense: true),
                          onChanged: (v) => setDlgState(() => sem = v ?? 1),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: ['Theory', 'Laboratory', 'Integrated', 'Elective', 'Project', 'Value Added'].contains(type) ? type : 'Theory',
                          items: ['Theory', 'Laboratory', 'Integrated', 'Elective', 'Project', 'Value Added']
                              .map((t) => DropdownMenuItem(value: t, child: Text(t, style: GoogleFonts.inter(fontSize: 12))))
                              .toList(),
                          decoration: InputDecoration(labelText: 'Category', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), isDense: true),
                          onChanged: (v) {
                            if (v != null) {
                              setDlgState(() {
                                type = v;
                                isLab = v == 'Laboratory' || v == 'Integrated';
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: creditsCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: 'Credits',
                            hintText: '3.0',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: hoursCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Weekly Periods',
                            hintText: '4',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: regCtrl,
                          decoration: InputDecoration(
                            labelText: 'Regulation',
                            hintText: '2021',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (isLab) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: labDetailsCtrl,
                      decoration: InputDecoration(
                        labelText: 'Lab Details / Room Preference',
                        hintText: 'e.g. Database Lab (Lab 2), MySQL / Oracle',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        isDense: true,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: Text('Course Active', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: Text('Inactive courses are hidden from timetable selectors', style: GoogleFonts.inter(fontSize: 11, color: AdminColors.getTextSecondary(isDark))),
                    value: isActive,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (v) => setDlgState(() => isActive = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: GoogleFonts.inter(color: AdminColors.getTextSecondary(isDark))),
            ),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      if (codeCtrl.text.trim().isEmpty || nameCtrl.text.trim().isEmpty) {
                        setDlgState(() => errorMsg = 'Subject code and title are required.');
                        return;
                      }

                      setDlgState(() {
                        isSaving = true;
                        errorMsg = null;
                      });

                      try {
                        final res = await http.post(
                          Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/academics/subjects/save'),
                          headers: {'Authorization': 'Bearer ${widget.token}', 'Content-Type': 'application/json'},
                          body: jsonEncode({
                            'id': initial?['id'],
                            'dept': _selectedDept,
                            'subject_code': codeCtrl.text.trim(),
                            'subject_name': nameCtrl.text.trim(),
                            'short_name': shortNameCtrl.text.trim().isNotEmpty ? shortNameCtrl.text.trim() : codeCtrl.text.trim(),
                            'semester': sem,
                            'subject_type': type,
                            'credits': double.tryParse(creditsCtrl.text.trim()) ?? 3.0,
                            'weekly_hours': int.tryParse(hoursCtrl.text.trim()) ?? 4,
                            'regulation': regCtrl.text.trim().isNotEmpty ? regCtrl.text.trim() : '2021',
                            'is_lab': isLab,
                            'lab_details': labDetailsCtrl.text.trim(),
                            'is_active': isActive,
                          }),
                        );

                        if (res.statusCode == 200) {
                          if (ctx.mounted) Navigator.pop(ctx);
                          _loadSubjects();
                          widget.onSubjectCatalogChanged?.call();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Saved subject ${codeCtrl.text.trim()}!'),
                                backgroundColor: AdminColors.success,
                              ),
                            );
                          }
                        } else {
                          final err = jsonDecode(res.body)['detail'] ?? 'Failed to save subject';
                          setDlgState(() => errorMsg = err.toString());
                        }
                      } catch (e) {
                        setDlgState(() => errorMsg = 'Error: $e');
                      } finally {
                        setDlgState(() => isSaving = false);
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: isSaving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(isEditing ? 'Save Changes' : 'Add Subject'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteSubject(Map<String, dynamic> subject) async {
    final subId = subject['id'];
    final subCode = subject['subject_code'];
    final subName = subject['subject_name'];

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $subCode?'),
        content: Text('Are you sure you want to remove "$subName" from the $_selectedDept curriculum catalog?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AdminColors.danger, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Course'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final res = await http.delete(
        Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/academics/subjects/$subId'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );

      if (res.statusCode == 200) {
        _loadSubjects();
        widget.onSubjectCatalogChanged?.call();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Deleted subject $subCode.'), backgroundColor: AdminColors.success),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AdminColors.danger));
      }
    }
  }

  void _openBulkImportDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final csvCtrl = TextEditingController(
      text: '# Code,Title,ShortName,Semester,Type,Credits,WeeklyHours,Regulation\n'
          'CS3452,Theory of Computation,TOC,4,Theory,3.0,4,2021\n'
          'CS3491,Artificial Intelligence and Machine Learning,AI & ML,4,Theory,4.0,4,2021\n'
          'CS3492,Database Management Systems,DBMS,4,Theory,3.0,4,2021\n'
          'CS3481,DBMS Laboratory,DBMS LAB,4,Laboratory,1.5,3,2021\n',
    );
    bool isImporting = false;
    String? status;

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
                child: const Icon(Icons.upload_file_rounded, color: AdminColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Bulk Import Department Courses', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AdminColors.getTextPrimary(isDark))),
                  Text('Paste CSV data for $_selectedDept', style: GoogleFonts.inter(fontSize: 12, color: AdminColors.getTextSecondary(isDark))),
                ],
              ),
            ],
          ),
          content: SizedBox(
            width: 580,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Format: Code, Title, ShortName, Semester, Type, Credits, WeeklyHours, Regulation',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AdminColors.getTextMuted(isDark))),
                const SizedBox(height: 8),
                TextField(
                  controller: csvCtrl,
                  maxLines: 8,
                  style: GoogleFonts.firaCode(fontSize: 11),
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                  ),
                ),
                if (status != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(status!, style: GoogleFonts.inter(fontSize: 11, color: status!.contains('Success') ? Colors.green : AdminColors.danger)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton.icon(
              onPressed: isImporting
                  ? null
                  : () async {
                      setDlgState(() => isImporting = true);
                      try {
                        final lines = csvCtrl.text.trim().split('\n');
                        final parsed = <Map<String, dynamic>>[];
                        for (var line in lines) {
                          if (line.startsWith('#') || line.trim().isEmpty) continue;
                          final parts = line.split(',');
                          if (parts.length >= 2) {
                            parsed.add({
                              'subject_code': parts[0].trim(),
                              'subject_name': parts[1].trim(),
                              'short_name': parts.length > 2 ? parts[2].trim() : parts[0].trim(),
                              'semester': parts.length > 3 ? (int.tryParse(parts[3].trim()) ?? 1) : 1,
                              'subject_type': parts.length > 4 ? parts[4].trim() : 'Theory',
                              'credits': parts.length > 5 ? (double.tryParse(parts[5].trim()) ?? 3.0) : 3.0,
                              'weekly_hours': parts.length > 6 ? (int.tryParse(parts[6].trim()) ?? 4) : 4,
                              'regulation': parts.length > 7 ? parts[7].trim() : '2021',
                              'is_lab': parts.length > 4 && parts[4].toLowerCase().contains('lab'),
                            });
                          }
                        }

                        if (parsed.isEmpty) {
                          setDlgState(() => status = 'No valid rows found to import.');
                          return;
                        }

                        final res = await http.post(
                          Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/academics/subjects/bulk-import'),
                          headers: {'Authorization': 'Bearer ${widget.token}', 'Content-Type': 'application/json'},
                          body: jsonEncode({
                            'dept': _selectedDept,
                            'subjects': parsed,
                          }),
                        );

                        if (res.statusCode == 200) {
                          final count = jsonDecode(res.body)['count'] ?? parsed.length;
                          setDlgState(() => status = 'Successfully imported $count subjects!');
                          await Future.delayed(const Duration(milliseconds: 500));
                          if (ctx.mounted) Navigator.pop(ctx);
                          _loadSubjects();
                          widget.onSubjectCatalogChanged?.call();
                        } else {
                          setDlgState(() => status = 'Failed to import subjects.');
                        }
                      } catch (e) {
                        setDlgState(() => status = 'Error: $e');
                      } finally {
                        setDlgState(() => isImporting = false);
                      }
                    },
              icon: const Icon(Icons.file_upload_rounded, size: 16),
              label: const Text('Import Subjects'),
              style: ElevatedButton.styleFrom(backgroundColor: AdminColors.primary, foregroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Map<int, int> _computeSemesterCounts() {
    final Map<int, int> counts = {};
    for (int i = 1; i <= 8; i++) {
      counts[i] = 0;
    }
    for (var s in _subjects) {
      final sem = (s['semester'] as num?)?.toInt() ?? 1;
      counts[sem] = (counts[sem] ?? 0) + 1;
    }
    return counts;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final semCounts = _computeSemesterCounts();

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final isCompactScreen = screenWidth < 768;

        return Padding(
          padding: EdgeInsets.symmetric(horizontal: isCompactScreen ? 14 : 24, vertical: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. In-Page Header Strip & Actions
              _buildHeaderActionStrip(isDark, isCompactScreen),
              const SizedBox(height: 16),

              // 2. Responsive Executive Metrics KPI Strip
              _buildResponsiveStats(isDark, screenWidth),
              const SizedBox(height: 16),

              // 3. Multi-Dimension Filters (Semesters & Categories)
              _buildFilterSection(isDark, semCounts),
              const SizedBox(height: 16),

              // 4. Main Course Content (Grid vs Grouped Roadmap)
              if (_isLoading)
                const Center(
                  heightFactor: 5,
                  child: CircularProgressIndicator(),
                )
              else if (_subjects.isEmpty)
                _buildEmptyState(isDark)
              else if (_isGroupedView)
                _buildGroupedRoadmap(isDark, screenWidth)
              else
                _buildResponsiveGrid(isDark, screenWidth),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeaderActionStrip(bool isDark, bool isCompact) {
    final semText = _selectedSemesterFilter == 0 ? 'All 8 Semesters' : 'Semester $_selectedSemesterFilter';
    final catText = _selectedCategoryFilter == 'ALL' ? 'All Course Types' : _selectedCategoryFilter;

    if (isCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: AdminColors.primarySoft, borderRadius: BorderRadius.circular(6)),
                child: Text(_selectedDept, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, color: AdminColors.primary)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Curriculum Catalog ($semText)',
                  style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, color: AdminColors.getTextPrimary(isDark)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _buildSearchBox(isDark)),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _loadSubjects,
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Refresh',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openBulkImportDialog,
                  icon: const Icon(Icons.file_upload_outlined, size: 15),
                  label: const Text('Bulk CSV'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AdminColors.primary,
                    side: const BorderSide(color: AdminColors.primary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _openAddEditSubjectDialog(),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Add Course'),
                  style: ElevatedButton.styleFrom(backgroundColor: AdminColors.primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Row(
      children: [
        // Left Title & Context
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: AdminColors.primarySoft, borderRadius: BorderRadius.circular(6)),
                    child: Text(_selectedDept, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, color: AdminColors.primary)),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Curriculum Catalog & Course Framework',
                    style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: AdminColors.getTextPrimary(isDark)),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'Displaying ${_subjects.length} courses in $semText ($catText)',
                style: GoogleFonts.inter(fontSize: 12, color: AdminColors.getTextSecondary(isDark)),
              ),
            ],
          ),
        ),

        // Right Controls
        SizedBox(width: 240, child: _buildSearchBox(isDark)),
        const SizedBox(width: 10),

        // View Mode Switcher
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AdminColors.getBorder(isDark)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildViewModeBtn(icon: Icons.grid_view_rounded, isSelected: !_isGroupedView, tooltip: 'Grid Cards View', onTap: () => setState(() => _isGroupedView = false), isDark: isDark),
              _buildViewModeBtn(icon: Icons.table_rows_rounded, isSelected: _isGroupedView, tooltip: 'Semester Roadmap View', onTap: () => setState(() => _isGroupedView = true), isDark: isDark),
            ],
          ),
        ),
        const SizedBox(width: 10),

        OutlinedButton.icon(
          onPressed: _openBulkImportDialog,
          icon: const Icon(Icons.file_upload_outlined, size: 16),
          label: const Text('Bulk Import CSV'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AdminColors.primary,
            side: const BorderSide(color: AdminColors.primary),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: () => _openAddEditSubjectDialog(),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add Course'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AdminColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
        ),
        const SizedBox(width: 6),
        IconButton(
          onPressed: _loadSubjects,
          icon: const Icon(Icons.refresh_rounded),
          tooltip: 'Refresh Catalog',
        ),
      ],
    );
  }

  Widget _buildSearchBox(bool isDark) {
    return TextField(
      controller: _searchCtrl,
      decoration: InputDecoration(
        hintText: 'Search code, title, acronym...',
        hintStyle: GoogleFonts.inter(fontSize: 12, color: AdminColors.getTextMuted(isDark)),
        prefixIcon: const Icon(Icons.search_rounded, size: 17),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear_rounded, size: 16),
                onPressed: () {
                  setState(() {
                    _searchCtrl.clear();
                    _searchQuery = '';
                  });
                  _loadSubjects();
                },
              )
            : null,
        isDense: true,
        filled: true,
        fillColor: AdminColors.getCard(isDark),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AdminColors.getBorder(isDark))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AdminColors.getBorder(isDark))),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      style: GoogleFonts.inter(fontSize: 12.5),
      onChanged: (v) {
        setState(() => _searchQuery = v);
        _loadSubjects();
      },
    );
  }

  Widget _buildViewModeBtn({required IconData icon, required bool isSelected, required String tooltip, required VoidCallback onTap, required bool isDark}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? AdminColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 16, color: isSelected ? Colors.white : AdminColors.getTextSecondary(isDark)),
      ),
    );
  }

  Widget _buildResponsiveStats(bool isDark, double screenWidth) {
    final statsList = [
      {'icon': Icons.library_books_rounded, 'label': 'Total Courses', 'val': '${_stats['total_subjects'] ?? _subjects.length}', 'color': AdminColors.primary},
      {'icon': Icons.menu_book_rounded, 'label': 'Theory Courses', 'val': '${_stats['theory_count'] ?? 0}', 'color': const Color(0xFF2563EB)},
      {'icon': Icons.biotech_rounded, 'label': 'Laboratory / Practical', 'val': '${_stats['lab_count'] ?? 0}', 'color': const Color(0xFF8B5CF6)},
      {'icon': Icons.category_rounded, 'label': 'Elective Courses', 'val': '${_stats['elective_count'] ?? 0}', 'color': const Color(0xFF0D9488)},
      {'icon': Icons.stars_rounded, 'label': 'Total Degree Credits', 'val': '${_stats['total_credits'] ?? 0}', 'color': const Color(0xFFD97706)},
    ];

    if (screenWidth > 1100) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AdminColors.getCard(isDark),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AdminColors.getBorder(isDark)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: statsList.map((st) {
            return Expanded(
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: (st['color'] as Color).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                    child: Icon(st['icon'] as IconData, size: 18, color: st['color'] as Color),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(st['val'] as String, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: AdminColors.getTextPrimary(isDark))),
                        Text(st['label'] as String, style: GoogleFonts.inter(fontSize: 11, color: AdminColors.getTextSecondary(isDark)), overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: statsList.map((st) {
        return Container(
          width: screenWidth > 600 ? (screenWidth - 70) / 3 : (screenWidth - 50) / 2,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AdminColors.getCard(isDark),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AdminColors.getBorder(isDark)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: (st['color'] as Color).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                child: Icon(st['icon'] as IconData, size: 16, color: st['color'] as Color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(st['val'] as String, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, color: AdminColors.getTextPrimary(isDark))),
                    Text(st['label'] as String, style: GoogleFonts.inter(fontSize: 10.5, color: AdminColors.getTextSecondary(isDark)), overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFilterSection(bool isDark, Map<int, int> semCounts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Semester Filter Pills
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildSemesterFilterPill(0, 'All Semesters', _subjects.length, isDark),
              ...List.generate(8, (i) {
                final sem = i + 1;
                return _buildSemesterFilterPill(sem, 'Sem $sem', semCounts[sem] ?? 0, isDark);
              }),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Category Filter Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _categories.map((cat) {
              final isSel = _selectedCategoryFilter == cat;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(cat == 'ALL' ? 'All Types' : cat),
                  selected: isSel,
                  selectedColor: AdminColors.primarySoft,
                  labelStyle: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                    color: isSel ? AdminColors.primary : AdminColors.getTextSecondary(isDark),
                  ),
                  backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                  side: BorderSide(color: isSel ? AdminColors.primary : AdminColors.getBorder(isDark)),
                  onSelected: (_) {
                    setState(() => _selectedCategoryFilter = cat);
                    _loadSubjects();
                  },
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildSemesterFilterPill(int sem, String label, int count, bool isDark) {
    final isSel = _selectedSemesterFilter == sem;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: () {
          setState(() => _selectedSemesterFilter = sem);
          _loadSubjects();
        },
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSel ? AdminColors.primary : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isSel ? AdminColors.primary : AdminColors.getBorder(isDark)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                  color: isSel ? Colors.white : AdminColors.getTextPrimary(isDark),
                ),
              ),
              if (count > 0 || sem == 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: isSel ? Colors.white.withValues(alpha: 0.25) : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: isSel ? Colors.white : AdminColors.getTextSecondary(isDark),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResponsiveGrid(bool isDark, double screenWidth) {
    int crossAxisCount = 3;
    if (screenWidth > 1400) {
      crossAxisCount = 4;
    } else if (screenWidth > 1050) {
      crossAxisCount = 3;
    } else if (screenWidth > 680) {
      crossAxisCount = 2;
    } else {
      crossAxisCount = 1;
    }

    final spacing = 14.0;
    final itemWidth = (screenWidth - (crossAxisCount - 1) * spacing - 48) / crossAxisCount;

    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      children: _subjects.map((s) {
        return SizedBox(
          width: itemWidth.clamp(280.0, 600.0),
          child: _buildSubjectCard(s, isDark),
        );
      }).toList(),
    );
  }

  Widget _buildGroupedRoadmap(bool isDark, double screenWidth) {
    // Group subjects by semester 1..8
    final Map<int, List<Map<String, dynamic>>> grouped = {};
    for (var s in _subjects) {
      final sem = (s['semester'] as num?)?.toInt() ?? 1;
      grouped.putIfAbsent(sem, () => []).add(s);
    }

    final sortedSemesters = grouped.keys.toList()..sort();

    return Column(
      children: sortedSemesters.map((sem) {
        final semCourses = grouped[sem]!;
        double semCredits = 0;
        for (var c in semCourses) {
          semCredits += (c['credits'] as num?)?.toDouble() ?? 0;
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
            color: AdminColors.getCard(isDark),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AdminColors.getBorder(isDark)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Semester Section Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                  border: Border(bottom: BorderSide(color: AdminColors.getBorder(isDark))),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: AdminColors.primary, borderRadius: BorderRadius.circular(6)),
                      child: Text('Semester $sem', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${semCourses.length} Courses • ${semCredits.toStringAsFixed(1)} Total Credits',
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AdminColors.getTextSecondary(isDark)),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => _openAddEditSubjectDialog(null, sem),
                      icon: const Icon(Icons.add_rounded, size: 15),
                      label: const Text('Add to Sem'),
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    ),
                  ],
                ),
              ),

              // Courses in this semester
              Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: semCourses.map((s) {
                    final itemWidth = screenWidth > 1100 ? (screenWidth - 80) / 3 : (screenWidth > 700 ? (screenWidth - 80) / 2 : screenWidth - 60);
                    return SizedBox(
                      width: itemWidth.clamp(280.0, 500.0),
                      child: _buildSubjectCard(s, isDark),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSubjectCard(Map<String, dynamic> s, bool isDark) {
    final isLab = s['is_lab'] == true || (s['subject_type'] ?? '').toString().toLowerCase().contains('lab');
    final isElective = (s['subject_type'] ?? '').toString().toLowerCase().contains('elective');
    final isProject = (s['subject_type'] ?? '').toString().toLowerCase().contains('project');

    Color themeColor = AdminColors.primary;
    if (isLab) themeColor = const Color(0xFF8B5CF6);
    if (isElective) themeColor = const Color(0xFF0D9488);
    if (isProject) themeColor = const Color(0xFFEA580C);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AdminColors.getCard(isDark),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminColors.getBorder(isDark)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Code Badge & Semester Tag
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: themeColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(isLab ? Icons.science_rounded : Icons.menu_book_rounded, size: 12, color: themeColor),
                    const SizedBox(width: 4),
                    Text(
                      s['subject_code'] ?? '',
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, color: themeColor),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              if (s['short_name'] != null && (s['short_name'] as String).isNotEmpty && s['short_name'] != s['subject_code'])
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    s['short_name'],
                    style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: AdminColors.getTextSecondary(isDark)),
                  ),
                ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('Sem ${s['semester']}', style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w700, color: AdminColors.getTextPrimary(isDark))),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Course Title
          Text(
            s['subject_name'] ?? '',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: AdminColors.getTextPrimary(isDark)),
          ),
          const SizedBox(height: 10),

          // Metadata Badges (Category, Credits, Weekly Hours, Regulation)
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _buildSmallBadge(s['subject_type'] ?? 'Theory', themeColor),
              _buildSmallBadge('${s['credits'] ?? 3.0} Credits', Colors.blueGrey),
              _buildSmallBadge('${s['weekly_hours'] ?? 4} hrs/wk', Colors.indigo),
              _buildSmallBadge('${s['regulation'] ?? 2021} Reg', Colors.grey),
            ],
          ),

          if (s['lab_details'] != null && (s['lab_details'] as String).isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.purple.withValues(alpha: isDark ? 0.2 : 0.07),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.purple.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.biotech_rounded, size: 12, color: Colors.purple),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      s['lab_details'],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 10, color: isDark ? Colors.purple[200] : Colors.purple[800]),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 10),
          Divider(height: 1, color: AdminColors.getBorder(isDark)),
          const SizedBox(height: 4),

          // Actions Row: Edit / Delete
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () => _openAddEditSubjectDialog(s),
                icon: const Icon(Icons.edit_rounded, size: 14),
                label: const Text('Edit'),
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: () => _deleteSubject(s),
                icon: const Icon(Icons.delete_outline_rounded, size: 16, color: AdminColors.danger),
                tooltip: 'Delete Course',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSmallBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
      child: Text(text, style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    final isFiltered = _searchQuery.isNotEmpty || _selectedSemesterFilter > 0 || _selectedCategoryFilter != 'ALL';

    return Center(
      child: Container(
        padding: const EdgeInsets.all(40),
        margin: const EdgeInsets.symmetric(vertical: 30),
        decoration: BoxDecoration(
          color: AdminColors.getCard(isDark),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AdminColors.getBorder(isDark)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: AdminColors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.menu_book_rounded, size: 36, color: AdminColors.primary),
            ),
            const SizedBox(height: 14),
            Text(
              isFiltered ? 'No courses match your filter' : 'No courses found in $_selectedDept curriculum',
              style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AdminColors.getTextPrimary(isDark)),
            ),
            const SizedBox(height: 6),
            Text(
              isFiltered
                  ? 'Try clearing the search query or selecting "All Semesters".'
                  : 'Get started by adding courses or importing syllabus CSV data.',
              style: GoogleFonts.inter(fontSize: 12, color: AdminColors.getTextSecondary(isDark)),
            ),
            const SizedBox(height: 18),
            if (isFiltered)
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _searchCtrl.clear();
                    _searchQuery = '';
                    _selectedSemesterFilter = 0;
                    _selectedCategoryFilter = 'ALL';
                  });
                  _loadSubjects();
                },
                icon: const Icon(Icons.clear_all_rounded, size: 16),
                label: const Text('Clear Filters'),
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton.icon(
                    onPressed: _openBulkImportDialog,
                    icon: const Icon(Icons.file_upload_outlined, size: 16),
                    label: const Text('Bulk Import CSV'),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: () => _openAddEditSubjectDialog(),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add Course'),
                    style: ElevatedButton.styleFrom(backgroundColor: AdminColors.primary, foregroundColor: Colors.white),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
