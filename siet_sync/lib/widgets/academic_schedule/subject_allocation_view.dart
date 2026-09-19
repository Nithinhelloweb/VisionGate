import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../../config/college_ip_config.dart';
import '../../theme/admin_theme.dart';

class SubjectAllocationView extends StatefulWidget {
  final String token;
  final String dept;
  final String batch;
  final int semester;
  final String section;
  final List<Map<String, dynamic>> allocations;
  final List<Map<String, dynamic>> facultyPool;
  final List<String> availableDepartments;
  final VoidCallback onAllocationUpdated;

  const SubjectAllocationView({
    super.key,
    required this.token,
    required this.dept,
    required this.batch,
    required this.semester,
    required this.section,
    required this.allocations,
    required this.facultyPool,
    this.availableDepartments = const [],
    required this.onAllocationUpdated,
  });

  @override
  State<SubjectAllocationView> createState() => _SubjectAllocationViewState();
}

class _SubjectAllocationViewState extends State<SubjectAllocationView> {
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
          
          final filteredFaculty = widget.facultyPool.where((f) {
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
                                Text('Select Faculty for Subject', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AdminColors.getTextPrimary(isDark))),
                                Text('Cross-department staff access enabled', style: GoogleFonts.inter(fontSize: 12, color: AdminColors.getTextSecondary(isDark))),
                              ],
                            ),
                          ),
                          IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        decoration: InputDecoration(
                          hintText: 'Search by name, ID, or department...',
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

  void _openSubjectPickerModal(BuildContext context, ValueChanged<Map<String, dynamic>> onSelect) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    String searchQuery = '';
    List<Map<String, dynamic>> deptSubjects = [];
    bool isLoadingSubjs = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          if (isLoadingSubjs) {
            http.get(
              Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/academics/subjects?dept=${Uri.encodeComponent(widget.dept)}&semester=${widget.semester}'),
              headers: {'Authorization': 'Bearer ${widget.token}'},
            ).then((res) {
              if (res.statusCode == 200) {
                final data = jsonDecode(res.body);
                setModalState(() {
                  deptSubjects = List<Map<String, dynamic>>.from(data['subjects'] ?? []);
                  isLoadingSubjs = false;
                });
              } else {
                setModalState(() => isLoadingSubjs = false);
              }
            }).catchError((_) {
              setModalState(() => isLoadingSubjs = false);
            });
          }

          final filteredSubjects = deptSubjects.where((s) {
            final code = (s['subject_code'] ?? '').toString().toLowerCase();
            final name = (s['subject_name'] ?? '').toString().toLowerCase();
            final short = (s['short_name'] ?? '').toString().toLowerCase();
            final q = searchQuery.toLowerCase().trim();
            return q.isEmpty || code.contains(q) || name.contains(q) || short.contains(q);
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
                            child: const Icon(Icons.menu_book_rounded, color: AdminColors.primary, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Pick from Department Curriculum', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AdminColors.getTextPrimary(isDark))),
                                Text('${widget.dept} • Sem ${widget.semester}', style: GoogleFonts.inter(fontSize: 12, color: AdminColors.getTextSecondary(isDark))),
                              ],
                            ),
                          ),
                          IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        decoration: InputDecoration(
                          hintText: 'Search curriculum by code or title (e.g. CS3492, DBMS)...',
                          prefixIcon: const Icon(Icons.search_rounded, size: 18),
                          isDense: true,
                          filled: true,
                          fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                        onChanged: (v) => setModalState(() => searchQuery = v),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: isLoadingSubjs
                      ? const Center(child: CircularProgressIndicator())
                      : filteredSubjects.isEmpty
                          ? Center(
                              child: Text(
                                'No subjects found in ${widget.dept} Sem ${widget.semester} catalog.',
                                style: GoogleFonts.inter(fontSize: 13, color: AdminColors.getTextSecondary(isDark)),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              itemCount: filteredSubjects.length,
                              itemBuilder: (ctx, i) {
                                final s = filteredSubjects[i];
                                final isLab = s['is_lab'] == true || (s['subject_type'] ?? '').toString().toLowerCase().contains('lab');

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: AdminColors.getBorder(isDark)),
                                  ),
                                  child: ListTile(
                                    dense: true,
                                    leading: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isLab ? Colors.purple.withValues(alpha: 0.12) : AdminColors.primarySoft,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        s['subject_code'] ?? '',
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: isLab ? Colors.purple : AdminColors.primary,
                                        ),
                                      ),
                                    ),
                                    title: Text(
                                      s['subject_name'] ?? '',
                                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AdminColors.getTextPrimary(isDark)),
                                    ),
                                    subtitle: Text(
                                      '${s['subject_type']} • ${s['credits']} Credits • ${s['weekly_hours']} hrs/wk',
                                      style: GoogleFonts.inter(fontSize: 11, color: AdminColors.getTextSecondary(isDark)),
                                    ),
                                    trailing: const Icon(Icons.check_circle_outline_rounded, color: AdminColors.primary, size: 18),
                                    onTap: () {
                                      onSelect(s);
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

  void _openAddEditDialog([Map<String, dynamic>? item]) {
    final codeCtrl = TextEditingController(text: item?['subject_code'] ?? '');
    final nameCtrl = TextEditingController(text: item?['subject_name'] ?? '');
    final hoursCtrl = TextEditingController(text: item?['weekly_hours']?.toString() ?? '4');
    String type = item?['subject_type'] ?? 'Theory';
    String? facultyRegNo = item?['staff_reg_no'];
    String? facultyName = item?['staff_name'];
    String? facultyDept = item?['staff_dept'];
    bool isHod = item?['is_hod'] == true;
    bool isSaving = false;

    if (facultyRegNo != null && facultyName == null) {
      final f = widget.facultyPool.firstWhere(
        (e) => (e['reg_no']?.toString() ?? '').toLowerCase() == facultyRegNo!.toLowerCase(),
        orElse: () => {},
      );
      if (f.isNotEmpty) {
        facultyName = f['name']?.toString();
        facultyDept = f['dept']?.toString();
        isHod = f['is_hod'] == true;
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          return AlertDialog(
            backgroundColor: AdminColors.getCard(isDark),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: AdminColors.primarySoft, borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.menu_book_rounded, color: AdminColors.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Text(item == null ? 'Add Subject Allocation' : 'Edit Subject Allocation', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AdminColors.getTextPrimary(isDark))),
              ],
            ),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Curriculum Subject Selection Card
                    Text('Subject from Curriculum Catalog *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AdminColors.getTextSecondary(isDark))),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () => _openSubjectPickerModal(context, (s) {
                        setDlgState(() {
                          codeCtrl.text = s['subject_code'] ?? '';
                          nameCtrl.text = s['subject_name'] ?? '';
                          type = s['subject_type'] ?? 'Theory';
                          hoursCtrl.text = (s['weekly_hours'] ?? 4).toString();
                        });
                      }),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: codeCtrl.text.isNotEmpty ? AdminColors.primary : AdminColors.getBorder(isDark)),
                        ),
                        child: codeCtrl.text.isNotEmpty
                            ? Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: type.toLowerCase().contains('lab')
                                          ? Colors.purple.withValues(alpha: 0.15)
                                          : AdminColors.primarySoft,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      codeCtrl.text,
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: type.toLowerCase().contains('lab') ? Colors.purple : AdminColors.primary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          nameCtrl.text,
                                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AdminColors.getTextPrimary(isDark)),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          '$type • ${widget.dept} Sem ${widget.semester}',
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
                                  const Icon(Icons.auto_stories_rounded, size: 18, color: AdminColors.primary),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Click to Choose Subject from ${widget.dept} Sem ${widget.semester} Curriculum...',
                                      style: GoogleFonts.inter(fontSize: 12.5, color: AdminColors.getTextSecondary(isDark)),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const Icon(Icons.arrow_drop_down_rounded),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text('Assigned Faculty / Teacher *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AdminColors.getTextSecondary(isDark))),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () => _openFacultyPickerModal(context, (f) {
                        setDlgState(() {
                          facultyRegNo = f['reg_no']?.toString();
                          facultyName = f['name']?.toString();
                          facultyDept = f['dept']?.toString();
                          isHod = f['is_hod'] == true;
                        });
                      }),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: facultyRegNo != null ? AdminColors.primary : AdminColors.getBorder(isDark)),
                        ),
                        child: facultyRegNo != null
                            ? Row(
                                children: [
                                  CircleAvatar(
                                    radius: 12,
                                    backgroundColor: isHod ? Colors.amber[100] : AdminColors.primarySoft,
                                    child: Text((facultyName?.isNotEmpty == true ? facultyName![0] : 'F').toUpperCase(), style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: AdminColors.primary)),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '${facultyName ?? facultyRegNo} (${facultyDept ?? ""})${isHod ? " [HOD]" : ""}',
                                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(color: AdminColors.primarySoft, borderRadius: BorderRadius.circular(4)),
                                    child: Text('Change', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: AdminColors.primary)),
                                  ),
                                ],
                              )
                            : Row(
                                children: [
                                  const Icon(Icons.person_search_rounded, size: 16, color: AdminColors.primary),
                                  const SizedBox(width: 6),
                                  Text('Click to Choose Faculty (Search all depts)...', style: GoogleFonts.inter(fontSize: 12, color: AdminColors.getTextSecondary(isDark))),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: hoursCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: 'Weekly Periods / Hours', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), isDense: true),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: GoogleFonts.inter(color: AdminColors.getTextSecondary(isDark)))),
              ElevatedButton(
                onPressed: (isSaving || facultyRegNo == null || codeCtrl.text.trim().isEmpty || nameCtrl.text.trim().isEmpty)
                    ? null
                    : () async {
                        setDlgState(() => isSaving = true);
                        try {
                          final res = await http.post(
                            Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/academics/subject-allocations/save'),
                            headers: {'Authorization': 'Bearer ${widget.token}', 'Content-Type': 'application/json'},
                            body: jsonEncode({
                              'dept': widget.dept,
                              'batch': widget.batch,
                              'semester': widget.semester,
                              'section': widget.section,
                              'subject_code': codeCtrl.text.trim(),
                              'subject_name': nameCtrl.text.trim(),
                              'subject_type': type,
                              'staff_reg_no': facultyRegNo,
                              'weekly_hours': int.tryParse(hoursCtrl.text.trim()) ?? 4,
                            }),
                          );
                          if (res.statusCode == 200 && ctx.mounted) {
                            widget.onAllocationUpdated();
                            Navigator.pop(ctx);
                          }
                        } catch (_) {}
                      },
                style: ElevatedButton.styleFrom(backgroundColor: AdminColors.primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                child: const Text('Save Allocation'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deleteAllocation(int id) async {
    try {
      final res = await http.delete(
        Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/academics/subject-allocations/$id'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (res.statusCode == 200) widget.onAllocationUpdated();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Subject-Faculty Allocations', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: AdminColors.getTextPrimary(isDark))),
                  Text('${widget.dept} | Batch ${widget.batch} | Sem ${widget.semester} (${widget.section}) — ${widget.allocations.length} Subjects Assigned', style: GoogleFonts.inter(fontSize: 13, color: AdminColors.getTextSecondary(isDark))),
                ],
              ),
              ElevatedButton.icon(
                onPressed: () => _openAddEditDialog(),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Allocate Subject'),
                style: ElevatedButton.styleFrom(backgroundColor: AdminColors.primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (widget.allocations.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text('No subject allocations configured for this section yet.', style: GoogleFonts.inter(fontSize: 14, color: AdminColors.getTextMuted(isDark))),
              ),
            )
          else
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: widget.allocations.map((a) {
                final isLab = (a['subject_type'] ?? '').toString().toLowerCase() == 'lab';
                final isHod = a['is_hod'] == true;
                return Container(
                  width: 340,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AdminColors.getCard(isDark),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AdminColors.getBorder(isDark)),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 3))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: isLab ? Colors.purple.withValues(alpha: 0.1) : AdminColors.primarySoft, borderRadius: BorderRadius.circular(6)),
                            child: Text(a['subject_code'] ?? '', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, color: isLab ? Colors.purple[700] : AdminColors.primary)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(4)),
                            child: Text('${a['weekly_hours'] ?? 4} hrs/wk', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: AdminColors.getTextSecondary(isDark))),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(a['subject_name'] ?? '', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AdminColors.getTextPrimary(isDark)), maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 8),
                      const Divider(height: 1),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(isHod ? Icons.stars_rounded : Icons.person_rounded, size: 14, color: isHod ? Colors.amber[700] : AdminColors.primary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${a['staff_name'] ?? a['staff_reg_no']}${isHod ? ' [HOD]' : ''}',
                              style: GoogleFonts.inter(fontSize: 12, fontWeight: isHod ? FontWeight.w700 : FontWeight.w500, color: isHod ? Colors.amber[900] : AdminColors.getTextPrimary(isDark)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            onPressed: () => _openAddEditDialog(a),
                            icon: const Icon(Icons.edit_outlined, size: 16, color: AdminColors.primary),
                            tooltip: 'Edit',
                          ),
                          IconButton(
                            onPressed: () => _deleteAllocation(a['id']),
                            icon: const Icon(Icons.delete_outline_rounded, size: 16, color: AdminColors.danger),
                            tooltip: 'Delete',
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}
