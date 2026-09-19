import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../../config/college_ip_config.dart';
import '../../theme/admin_theme.dart';

class ClassAdvisorView extends StatefulWidget {
  final String token;
  final String dept;
  final String batch;
  final int semester;
  final String section;
  final List<Map<String, dynamic>> facultyPool;
  final List<String> availableDepartments;
  final bool isHod;
  final VoidCallback onAdvisorUpdated;

  const ClassAdvisorView({
    super.key,
    required this.token,
    required this.dept,
    required this.batch,
    required this.semester,
    required this.section,
    this.facultyPool = const [],
    this.availableDepartments = const [],
    required this.isHod,
    required this.onAdvisorUpdated,
  });

  @override
  State<ClassAdvisorView> createState() => _ClassAdvisorViewState();
}

class _ClassAdvisorViewState extends State<ClassAdvisorView> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _advisors = [];
  List<Map<String, dynamic>> _facultyPool = [];

  @override
  void initState() {
    super.initState();
    _facultyPool = widget.facultyPool;
    _loadData();
  }

  @override
  void didUpdateWidget(covariant ClassAdvisorView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.facultyPool != widget.facultyPool) {
      _facultyPool = widget.facultyPool;
    }
    if (oldWidget.dept != widget.dept ||
        oldWidget.batch != widget.batch ||
        oldWidget.semester != widget.semester ||
        oldWidget.section != widget.section) {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final uriAdv = Uri.parse(
        '${CollegeIPConfig.defaultURL}/api/v1/academics/class-advisors?dept=${Uri.encodeComponent(widget.dept)}&batch=${Uri.encodeComponent(widget.batch)}&semester=${widget.semester}&section=${Uri.encodeComponent(widget.section)}',
      );
      final resAdv = await http.get(uriAdv, headers: {'Authorization': 'Bearer ${widget.token}'});
      if (resAdv.statusCode == 200) {
        final data = jsonDecode(resAdv.body);
        _advisors = List<Map<String, dynamic>>.from(data['class_advisors'] ?? []);
      }

      if (_facultyPool.isEmpty) {
        final uriFac = Uri.parse(
          '${CollegeIPConfig.defaultURL}/api/v1/academics/faculty-pool?include_all_depts=true',
        );
        final resFac = await http.get(uriFac, headers: {'Authorization': 'Bearer ${widget.token}'});
        if (resFac.statusCode == 200) {
          final data = jsonDecode(resFac.body);
          _facultyPool = List<Map<String, dynamic>>.from(data['faculty'] ?? []);
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  void _openFacultyPickerModal(BuildContext context, ValueChanged<Map<String, dynamic>> onSelect) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    String selectedDeptFilter = 'ALL';
    String searchQuery = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final deptsList = ['ALL', ...widget.availableDepartments.isNotEmpty ? widget.availableDepartments : ['CSE', 'ECE', 'EEE', 'MECH', 'CIVIL', 'IT', 'AI & ML', 'Data Science', 'Science & Humanities']];
          
          final filteredFaculty = _facultyPool.where((f) {
            final fDept = (f['dept'] ?? '').toString();
            final fName = (f['name'] ?? '').toString().toLowerCase();
            final fReg = (f['reg_no'] ?? '').toString().toLowerCase();
            final q = searchQuery.toLowerCase().trim();

            final matchesDept = selectedDeptFilter == 'ALL' || fDept.toLowerCase() == selectedDeptFilter.toLowerCase();
            final matchesQuery = q.isEmpty || fName.contains(q) || fReg.contains(q) || fDept.toLowerCase().contains(q);
            return matchesDept && matchesQuery;
          }).toList();

          return Container(
            height: MediaQuery.of(context).size.height * 0.75,
            decoration: BoxDecoration(
              color: AdminColors.getCard(isDark),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: AdminColors.getBorder(isDark)),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                  child: Column(
                    children: [
                      Container(width: 40, height: 4, decoration: BoxDecoration(color: AdminColors.getBorder(isDark), borderRadius: BorderRadius.circular(2))),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: AdminColors.primarySoft, borderRadius: BorderRadius.circular(10)),
                            child: const Icon(Icons.people_alt_rounded, color: AdminColors.primary, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Select Advisor / Mentor', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AdminColors.getTextPrimary(isDark))),
                                Text('Choose faculty member or HOD from any department', style: GoogleFonts.inter(fontSize: 12, color: AdminColors.getTextSecondary(isDark))),
                              ],
                            ),
                          ),
                          IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        decoration: InputDecoration(
                          hintText: 'Search by name, staff ID, or department...',
                          prefixIcon: const Icon(Icons.search_rounded, size: 18),
                          isDense: true,
                          filled: true,
                          fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                        onChanged: (v) => setModalState(() => searchQuery = v),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 36,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: deptsList.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 6),
                          itemBuilder: (ctx, i) {
                            final d = deptsList[i];
                            final isSel = selectedDeptFilter.toLowerCase() == d.toLowerCase();
                            return ChoiceChip(
                              label: Text(d == 'ALL' ? 'All Departments' : d, style: GoogleFonts.inter(fontSize: 11, fontWeight: isSel ? FontWeight.w700 : FontWeight.w500)),
                              selected: isSel,
                              selectedColor: AdminColors.primarySoft,
                              backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                              labelStyle: TextStyle(color: isSel ? AdminColors.primary : AdminColors.getTextSecondary(isDark)),
                              side: BorderSide(color: isSel ? AdminColors.primary : AdminColors.getBorder(isDark)),
                              onSelected: (_) => setModalState(() => selectedDeptFilter = d),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: filteredFaculty.isEmpty
                      ? Center(child: Text('No faculty found', style: GoogleFonts.inter(fontSize: 13, color: AdminColors.getTextSecondary(isDark))))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          itemCount: filteredFaculty.length,
                          itemBuilder: (ctx, i) {
                            final f = filteredFaculty[i];
                            final isHod = f['is_hod'] == true;
                            final reg = f['reg_no']?.toString() ?? '';
                            final name = f['name']?.toString() ?? '';
                            final dept = f['dept']?.toString() ?? '';

                            return Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AdminColors.getBorder(isDark)),
                              ),
                              child: ListTile(
                                dense: true,
                                leading: CircleAvatar(
                                  radius: 16,
                                  backgroundColor: isHod ? Colors.amber[100] : AdminColors.primarySoft,
                                  child: isHod
                                      ? Icon(Icons.stars_rounded, color: Colors.amber[800], size: 18)
                                      : Text(name.isNotEmpty ? name[0].toUpperCase() : 'F', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AdminColors.primary)),
                                ),
                                title: Text(name, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AdminColors.getTextPrimary(isDark))),
                                subtitle: Text('$dept • $reg', style: GoogleFonts.inter(fontSize: 11, color: AdminColors.getTextSecondary(isDark))),
                                trailing: isHod
                                    ? Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(color: Colors.amber[100], borderRadius: BorderRadius.circular(4)),
                                        child: Text('HOD', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber[900])),
                                      )
                                    : null,
                                onTap: () {
                                  onSelect(f);
                                  Navigator.pop(ctx);
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showAssignDialog(String advisorType) {
    String? selectedRegNo;
    String? selectedName;
    String? selectedDept;
    bool isHod = false;

    Map<String, dynamic>? currentAdv = _advisors.cast<Map<String, dynamic>?>().firstWhere(
      (a) => a?['advisor_type'] == advisorType,
      orElse: () => null,
    );
    if (currentAdv != null) {
      selectedRegNo = currentAdv['staff_reg_no']?.toString();
      selectedName = currentAdv['staff_name']?.toString();
      selectedDept = currentAdv['staff_dept']?.toString();
      isHod = currentAdv['is_hod'] == true;
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setDlgState) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          return AlertDialog(
            backgroundColor: AdminColors.getCard(isDark),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AdminColors.primarySoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.school_rounded, color: AdminColors.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  'Assign ${advisorType == 'primary' ? 'Primary Class Advisor' : 'Assistant Advisor'}',
                  style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AdminColors.getTextPrimary(isDark)),
                ),
              ],
            ),
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Class: ${widget.dept} | Batch: ${widget.batch} | Sem ${widget.semester} - Section ${widget.section}',
                    style: GoogleFonts.inter(fontSize: 13, color: AdminColors.getTextSecondary(isDark)),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Select Faculty Member / HOD *',
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AdminColors.getTextPrimary(isDark)),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () => _openFacultyPickerModal(context, (f) {
                      setDlgState(() {
                        selectedRegNo = f['reg_no']?.toString();
                        selectedName = f['name']?.toString();
                        selectedDept = f['dept']?.toString();
                        isHod = f['is_hod'] == true;
                      });
                    }),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: selectedRegNo != null ? AdminColors.primary : AdminColors.getBorder(isDark)),
                      ),
                      child: selectedRegNo != null
                          ? Row(
                              children: [
                                CircleAvatar(
                                  radius: 14,
                                  backgroundColor: isHod ? Colors.amber[100] : AdminColors.primarySoft,
                                  child: Text((selectedName?.isNotEmpty == true ? selectedName![0] : 'F').toUpperCase(), style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AdminColors.primary)),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${selectedName ?? selectedRegNo}${isHod ? " [HOD]" : ""}',
                                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        'Dept: ${selectedDept ?? "General"} • ID: $selectedRegNo',
                                        style: GoogleFonts.inter(fontSize: 11, color: AdminColors.getTextSecondary(isDark)),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(color: AdminColors.primarySoft, borderRadius: BorderRadius.circular(6)),
                                  child: Text('Change', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AdminColors.primary)),
                                ),
                              ],
                            )
                          : Row(
                              children: [
                                const Icon(Icons.person_search_rounded, size: 18, color: AdminColors.primary),
                                const SizedBox(width: 8),
                                Text('Choose Faculty (All Departments)...', style: GoogleFonts.inter(fontSize: 13, color: AdminColors.getTextSecondary(isDark))),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Note: Setting a Primary Class Advisor automatically links student mentor records for this section.',
                    style: GoogleFonts.inter(fontSize: 11, color: Colors.blueGrey, fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Cancel', style: GoogleFonts.inter(color: AdminColors.getTextSecondary(isDark))),
              ),
              ElevatedButton(
                onPressed: selectedRegNo == null
                    ? null
                    : () async {
                        Navigator.pop(ctx);
                        await _submitAssignment(selectedRegNo!, advisorType);
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AdminColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Confirm Assignment'),
              ),
            ],
          );
        });
      },
    );
  }

  Future<void> _submitAssignment(String staffRegNo, String advisorType) async {
    setState(() => _isLoading = true);
    try {
      final res = await http.post(
        Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/academics/class-advisors/assign'),
        headers: {'Authorization': 'Bearer ${widget.token}', 'Content-Type': 'application/json'},
        body: jsonEncode({
          'dept': widget.dept,
          'batch': widget.batch,
          'year_of_study': ((widget.semester + 1) ~/ 2),
          'semester': widget.semester,
          'section': widget.section,
          'staff_reg_no': staffRegNo,
          'advisor_type': advisorType,
        }),
      );
      if (res.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Class Advisor assigned successfully!'), backgroundColor: AdminColors.success),
        );
        _loadData();
        widget.onAdvisorUpdated();
      } else {
        final err = jsonDecode(res.body)['detail'] ?? 'Failed to assign';
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err), backgroundColor: AdminColors.danger));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Network error: $e'), backgroundColor: AdminColors.danger));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _removeAdvisor(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Advisor Assignment'),
        content: const Text('Are you sure you want to unassign this class advisor?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AdminColors.danger, foregroundColor: Colors.white),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      final res = await http.delete(
        Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/academics/class-advisors/$id'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (res.statusCode == 200) {
        _loadData();
        widget.onAdvisorUpdated();
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryAdv = _advisors.cast<Map<String, dynamic>?>().firstWhere((a) => a?['advisor_type'] == 'primary', orElse: () => null);
    final asstAdv = _advisors.cast<Map<String, dynamic>?>().firstWhere((a) => a?['advisor_type'] == 'assistant', orElse: () => null);

    if (_isLoading) {
      return const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
    }

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AdminColors.primarySoft, borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.badge_rounded, color: AdminColors.primary, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Class Advisors & Mentorship Hierarchy', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: AdminColors.getTextPrimary(isDark))),
                    Text('${widget.dept} | Batch ${widget.batch} | Semester ${widget.semester} - Section ${widget.section}', style: GoogleFonts.inter(fontSize: 13, color: AdminColors.getTextSecondary(isDark))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 20,
            runSpacing: 20,
            children: [
              _buildAdvisorCard(
                isDark,
                title: 'Primary Class Advisor',
                subtitle: 'Chief Class In-Charge & Student Mentor',
                advisor: primaryAdv,
                advisorType: 'primary',
                icon: Icons.workspace_premium_rounded,
                accentColor: AdminColors.primary,
              ),
              _buildAdvisorCard(
                isDark,
                title: 'Assistant Class Advisor',
                subtitle: 'Co-Mentor & Attendance Secondary In-Charge',
                advisor: asstAdv,
                advisorType: 'assistant',
                icon: Icons.person_outline_rounded,
                accentColor: AdminColors.success,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAdvisorCard(
    bool isDark, {
    required String title,
    required String subtitle,
    required Map<String, dynamic>? advisor,
    required String advisorType,
    required IconData icon,
    required Color accentColor,
  }) {
    final hasAdvisor = advisor != null;
    final isHod = advisor?['is_hod'] == true;

    return Container(
      width: 380,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AdminColors.getCard(isDark),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasAdvisor ? accentColor.withValues(alpha: 0.5) : AdminColors.getBorder(isDark),
          width: hasAdvisor ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: hasAdvisor ? accentColor.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.02),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: accentColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: accentColor, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AdminColors.getTextPrimary(isDark))),
                    Text(subtitle, style: GoogleFonts.inter(fontSize: 11, color: AdminColors.getTextSecondary(isDark))),
                  ],
                ),
              ),
              if (hasAdvisor && isHod)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.amber[100], borderRadius: BorderRadius.circular(6)),
                  child: Text('HOD', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber[900])),
                ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),
          if (hasAdvisor) ...[
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: accentColor.withValues(alpha: 0.15),
                  child: Text(
                    (advisor['staff_name'] as String? ?? 'A')[0].toUpperCase(),
                    style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: accentColor),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(advisor['staff_name'] ?? 'Faculty', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AdminColors.getTextPrimary(isDark))),
                      Text('Reg No: ${advisor['staff_reg_no']}', style: GoogleFonts.inter(fontSize: 12, color: AdminColors.getTextSecondary(isDark))),
                      Text('Dept: ${advisor['staff_dept'] ?? widget.dept}', style: GoogleFonts.inter(fontSize: 11, color: AdminColors.getTextMuted(isDark))),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showAssignDialog(advisorType),
                    icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                    label: const Text('Change Advisor'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: accentColor,
                      side: BorderSide(color: accentColor),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                  onPressed: () => _removeAdvisor(advisor['id']),
                  icon: const Icon(Icons.delete_outline_rounded, color: AdminColors.danger),
                  tooltip: 'Unassign Advisor',
                ),
              ],
            ),
          ] else ...[
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  children: [
                    Icon(Icons.person_add_disabled_rounded, size: 36, color: AdminColors.getTextMuted(isDark)),
                    const SizedBox(height: 8),
                    Text('No $title assigned yet', style: GoogleFonts.inter(fontSize: 12, color: AdminColors.getTextMuted(isDark))),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showAssignDialog(advisorType),
                icon: const Icon(Icons.person_add_rounded, size: 16),
                label: Text('Assign $title'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
