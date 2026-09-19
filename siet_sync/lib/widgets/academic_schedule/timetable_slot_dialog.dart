import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../../config/college_ip_config.dart';
import '../../theme/admin_theme.dart';

class TimetableSlotDialog extends StatefulWidget {
  final String token;
  final String dept;
  final String batch;
  final int semester;
  final String section;
  final String dayOfWeek;
  final int periodNumber;
  final String periodTimeRange;
  final Map<String, dynamic>? initialSlot;
  final List<Map<String, dynamic>> facultyPool;
  final List<Map<String, dynamic>> subjectAllocations;
  final List<String> availableDepartments;
  final VoidCallback onSaved;

  const TimetableSlotDialog({
    super.key,
    required this.token,
    required this.dept,
    required this.batch,
    required this.semester,
    required this.section,
    required this.dayOfWeek,
    required this.periodNumber,
    required this.periodTimeRange,
    this.initialSlot,
    required this.facultyPool,
    required this.subjectAllocations,
    this.availableDepartments = const [],
    required this.onSaved,
  });

  @override
  State<TimetableSlotDialog> createState() => _TimetableSlotDialogState();
}

class _TimetableSlotDialogState extends State<TimetableSlotDialog> {
  final _formKey = GlobalKey<FormState>();
  final _codeCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _roomCtrl = TextEditingController();
  final _roomFocusNode = FocusNode();

  String? _selectedFacultyRegNo;
  String? _selectedFacultyName;
  String? _selectedFacultyDept;
  bool _selectedFacultyIsHod = false;

  bool _isLab = false;
  int _spanPeriods = 1;
  String _labBatch = 'ALL';
  bool _isSaving = false;
  String? _conflictWarning;
  List<Map<String, dynamic>> _registeredVenues = [];

  @override
  void initState() {
    super.initState();
    _loadVenues();
    if (widget.initialSlot != null) {
      _codeCtrl.text = widget.initialSlot!['subject_code']?.toString() ?? '';
      _nameCtrl.text = widget.initialSlot!['subject_name']?.toString() ?? '';
      _roomCtrl.text = widget.initialSlot!['room_or_lab']?.toString() ?? '';
      _selectedFacultyRegNo = widget.initialSlot!['staff_reg_no']?.toString();
      _selectedFacultyName = widget.initialSlot!['staff_name']?.toString();
      _selectedFacultyDept = widget.initialSlot!['staff_dept']?.toString();
      _selectedFacultyIsHod = widget.initialSlot!['is_hod'] == true;
      _isLab = widget.initialSlot!['is_lab_block'] == true;
      _labBatch = widget.initialSlot!['lab_batch']?.toString() ?? 'ALL';
    }

    if (_selectedFacultyRegNo != null && _selectedFacultyName == null) {
      final f = widget.facultyPool.firstWhere(
        (e) => e['reg_no']?.toString().toLowerCase() == _selectedFacultyRegNo!.toLowerCase(),
        orElse: () => {},
      );
      if (f.isNotEmpty) {
        _selectedFacultyName = f['name']?.toString();
        _selectedFacultyDept = f['dept']?.toString();
        _selectedFacultyIsHod = f['is_hod'] == true;
      }
    }
  }

  Future<void> _loadVenues() async {
    try {
      final res = await http.get(
        Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/academics/venues'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            _registeredVenues = List<Map<String, dynamic>>.from(d['venues'] ?? []);
          });
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _roomCtrl.dispose();
    _roomFocusNode.dispose();
    super.dispose();
  }

  void _onSubjectSelected(Map<String, dynamic> sub) {
    setState(() {
      _codeCtrl.text = sub['subject_code'] ?? '';
      _nameCtrl.text = sub['subject_name'] ?? '';
      _selectedFacultyRegNo = sub['staff_reg_no'];
      _selectedFacultyName = sub['staff_name'] ?? _lookupFacultyName(sub['staff_reg_no']);
      _selectedFacultyDept = sub['staff_dept'] ?? _lookupFacultyDept(sub['staff_reg_no']);
      _selectedFacultyIsHod = sub['is_hod'] == true;
      _isLab = (sub['subject_type'] ?? '').toString().toLowerCase().contains('lab');
      if (_isLab && _spanPeriods == 1) {
        _spanPeriods = 2;
      }
    });
  }

  String _lookupFacultyName(String? regNo) {
    if (regNo == null) return '';
    final f = widget.facultyPool.firstWhere(
      (e) => e['reg_no']?.toString().toLowerCase() == regNo.toLowerCase(),
      orElse: () => {},
    );
    return f['name']?.toString() ?? regNo;
  }

  String _lookupFacultyDept(String? regNo) {
    if (regNo == null) return '';
    final f = widget.facultyPool.firstWhere(
      (e) => e['reg_no']?.toString().toLowerCase() == regNo.toLowerCase(),
      orElse: () => {},
    );
    return f['dept']?.toString() ?? '';
  }

  void _openCurriculumPickerModal() async {
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

          final filtered = deptSubjects.where((s) {
            final code = (s['subject_code'] ?? '').toString().toLowerCase();
            final name = (s['subject_name'] ?? '').toString().toLowerCase();
            final q = searchQuery.toLowerCase().trim();
            return q.isEmpty || code.contains(q) || name.contains(q);
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
                Padding(
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
                            child: const Icon(Icons.auto_stories_rounded, color: AdminColors.primary, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Department Curriculum Subjects', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AdminColors.getTextPrimary(isDark))),
                                Text('${widget.dept} Sem ${widget.semester}', style: GoogleFonts.inter(fontSize: 12, color: AdminColors.getTextSecondary(isDark))),
                              ],
                            ),
                          ),
                          IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        decoration: InputDecoration(
                          hintText: 'Search curriculum subjects...',
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
                      : filtered.isEmpty
                          ? Center(child: Text('No courses found in curriculum catalog.', style: GoogleFonts.inter(fontSize: 13, color: AdminColors.getTextSecondary(isDark))))
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              itemCount: filtered.length,
                              itemBuilder: (ctx, i) {
                                final s = filtered[i];
                                final isLabSub = s['is_lab'] == true || (s['subject_type'] ?? '').toString().toLowerCase().contains('lab');

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
                                        color: isLabSub ? Colors.purple.withValues(alpha: 0.12) : AdminColors.primarySoft,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(s['subject_code'] ?? '', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: isLabSub ? Colors.purple : AdminColors.primary)),
                                    ),
                                    title: Text(s['subject_name'] ?? '', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AdminColors.getTextPrimary(isDark))),
                                    subtitle: Text('${s['subject_type']} • ${s['credits']} Credits • ${s['weekly_hours']} hrs/wk', style: GoogleFonts.inter(fontSize: 11, color: AdminColors.getTextSecondary(isDark))),
                                    trailing: const Icon(Icons.check_circle_outline_rounded, color: AdminColors.primary, size: 18),
                                    onTap: () {
                                      final code = s['subject_code'] ?? '';
                                      final matchAlloc = widget.subjectAllocations.firstWhere(
                                        (a) => (a['subject_code'] ?? '').toString().toLowerCase() == code.toString().toLowerCase(),
                                        orElse: () => {},
                                      );
                                      setState(() {
                                        _codeCtrl.text = code;
                                        _nameCtrl.text = s['subject_name'] ?? '';
                                        _isLab = isLabSub;
                                        if (_isLab && _spanPeriods == 1) _spanPeriods = 2;
                                        if (matchAlloc.isNotEmpty && matchAlloc['staff_reg_no'] != null) {
                                          _selectedFacultyRegNo = matchAlloc['staff_reg_no'];
                                          _selectedFacultyName = matchAlloc['staff_name'] ?? _lookupFacultyName(matchAlloc['staff_reg_no']);
                                          _selectedFacultyDept = matchAlloc['staff_dept'] ?? _lookupFacultyDept(matchAlloc['staff_reg_no']);
                                          _selectedFacultyIsHod = matchAlloc['is_hod'] == true;
                                        }
                                      });
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

  void _openFacultyPickerModal() {
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
            height: MediaQuery.of(context).size.height * 0.78,
            decoration: BoxDecoration(
              color: AdminColors.getCard(isDark),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: AdminColors.getBorder(isDark)),
            ),
            child: Column(
              children: [
                // Modal Handle & Header
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
                                Text('Select Faculty / Teacher', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AdminColors.getTextPrimary(isDark))),
                                Text('Access all departments & HODs across college', style: GoogleFonts.inter(fontSize: 12, color: AdminColors.getTextSecondary(isDark))),
                              ],
                            ),
                          ),
                          IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Search Box
                      TextField(
                        autofocus: false,
                        decoration: InputDecoration(
                          hintText: 'Search faculty by name, ID, or subject...',
                          prefixIcon: const Icon(Icons.search_rounded, size: 18),
                          suffixIcon: searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, size: 16),
                                  onPressed: () => setModalState(() => searchQuery = ''),
                                )
                              : null,
                          isDense: true,
                          filled: true,
                          fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                        onChanged: (v) => setModalState(() => searchQuery = v),
                      ),
                      const SizedBox(height: 10),
                      // Department Chips
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
                // Faculty List
                Expanded(
                  child: filteredFaculty.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.person_off_rounded, size: 40, color: AdminColors.getTextMuted(isDark)),
                              const SizedBox(height: 8),
                              Text('No matching faculty found', style: GoogleFonts.inter(fontSize: 13, color: AdminColors.getTextSecondary(isDark))),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          itemCount: filteredFaculty.length,
                          itemBuilder: (ctx, i) {
                            final f = filteredFaculty[i];
                            final isHod = f['is_hod'] == true;
                            final reg = f['reg_no']?.toString() ?? '';
                            final name = f['name']?.toString() ?? '';
                            final dept = f['dept']?.toString() ?? '';
                            final isSelected = _selectedFacultyRegNo?.toLowerCase() == reg.toLowerCase();

                            return Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              decoration: BoxDecoration(
                                color: isSelected ? AdminColors.primarySoft.withValues(alpha: 0.5) : (isDark ? const Color(0xFF1E293B) : Colors.white),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: isSelected ? AdminColors.primary : AdminColors.getBorder(isDark)),
                              ),
                              child: ListTile(
                                dense: true,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                leading: CircleAvatar(
                                  radius: 18,
                                  backgroundColor: isHod ? Colors.amber[100] : AdminColors.primarySoft,
                                  child: isHod
                                      ? Icon(Icons.stars_rounded, color: Colors.amber[800], size: 20)
                                      : Text(
                                          name.isNotEmpty ? name[0].toUpperCase() : 'F',
                                          style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AdminColors.primary),
                                        ),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        name,
                                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AdminColors.getTextPrimary(isDark)),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (isHod)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(color: Colors.amber[100], borderRadius: BorderRadius.circular(6)),
                                        child: Text('HOD', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber[900])),
                                      ),
                                  ],
                                ),
                                subtitle: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: isDark ? Colors.grey[800] : Colors.grey[200],
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(dept, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600)),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(reg, style: GoogleFonts.inter(fontSize: 11, color: AdminColors.getTextSecondary(isDark))),
                                  ],
                                ),
                                trailing: isSelected
                                    ? const Icon(Icons.check_circle_rounded, color: AdminColors.primary, size: 20)
                                    : const Icon(Icons.chevron_right_rounded, size: 18),
                                onTap: () {
                                  setState(() {
                                    _selectedFacultyRegNo = reg;
                                    _selectedFacultyName = name;
                                    _selectedFacultyDept = dept;
                                    _selectedFacultyIsHod = isHod;
                                  });
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

  void _showQuickCreateVenueDialog({VoidCallback? onCreated}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final codeCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final blockCtrl = TextEditingController();
    final floorCtrl = TextEditingController();
    final capCtrl = TextEditingController(text: '70');
    final wsCtrl = TextEditingController(text: '0');
    String venueType = _isLab ? 'LABORATORY' : 'LECTURE_HALL';
    bool isSaving = false;
    String? errorMsg;

    showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (dlgCtx, setDlgState) {
          final isLabFacility = venueType == 'LABORATORY' || venueType == 'WORKSHOP';

          return AlertDialog(
            backgroundColor: AdminColors.getCard(isDark),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.add_business_rounded, color: Color(0xFF2563EB), size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Create Custom Venue', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold)),
                      Text('Register and assign immediately to this class slot', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: codeCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Venue Code *',
                              hintText: 'e.g. LH-401, LAB-AI',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 3,
                          child: DropdownButtonFormField<String>(
                            initialValue: venueType,
                            decoration: const InputDecoration(labelText: 'Facility Type', border: OutlineInputBorder()),
                            items: const [
                              DropdownMenuItem(value: 'LECTURE_HALL', child: Text('Lecture Hall')),
                              DropdownMenuItem(value: 'LABORATORY', child: Text('Specialized Lab')),
                              DropdownMenuItem(value: 'SMART_CLASSROOM', child: Text('Smart Classroom')),
                              DropdownMenuItem(value: 'SEMINAR_HALL', child: Text('Seminar Hall')),
                              DropdownMenuItem(value: 'AUDITORIUM', child: Text('Auditorium')),
                              DropdownMenuItem(value: 'WORKSHOP', child: Text('Workshop')),
                              DropdownMenuItem(value: 'CUSTOM_FACILITY', child: Text('Custom Facility')),
                            ],
                            onChanged: (v) => setDlgState(() => venueType = v ?? venueType),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Facility Official Name *',
                        hintText: 'e.g. Computing Lab 4 / Smart Hall 401',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: blockCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Building Block *',
                              hintText: 'e.g. Main Block, Tech Park',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: floorCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Floor / Level',
                              hintText: 'e.g. 2nd Floor',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: capCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Seating Capacity',
                              hintText: '70',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        if (isLabFacility) ...[
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: wsCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'PC Workstations',
                                hintText: '40',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (errorMsg != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(errorMsg!, style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dlgCtx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white),
                onPressed: isSaving
                    ? null
                    : () async {
                        final code = codeCtrl.text.trim().toUpperCase();
                        final name = nameCtrl.text.trim();
                        final block = blockCtrl.text.trim().isEmpty ? 'Campus Main Building' : blockCtrl.text.trim();
                        final floor = floorCtrl.text.trim().isEmpty ? '1st Floor' : floorCtrl.text.trim();

                        if (code.isEmpty || name.isEmpty) {
                          setDlgState(() => errorMsg = 'Venue code and name are required.');
                          return;
                        }

                        setDlgState(() {
                          isSaving = true;
                          errorMsg = null;
                        });

                        try {
                          final res = await http.post(
                            Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/academics/venues'),
                            headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ${widget.token}'},
                            body: jsonEncode({
                              'venue_code': code,
                              'venue_name': name,
                              'venue_type': venueType,
                              'dept': widget.dept,
                              'block_building': block,
                              'floor_number': floor,
                              'capacity': int.tryParse(capCtrl.text.trim()) ?? 70,
                              'lab_workstations': int.tryParse(wsCtrl.text.trim()) ?? 0,
                              'equipment_amenities': ['Central AC', 'Gigabit Wi-Fi'],
                            }),
                          );

                          if (res.statusCode == 200 || res.statusCode == 201) {
                            await _loadVenues();
                            if (mounted) {
                              setState(() {
                                _roomCtrl.text = code;
                                if (isLabFacility) {
                                  _isLab = true;
                                  if (_spanPeriods == 1) _spanPeriods = 2;
                                }
                              });
                            }
                            if (dlgCtx.mounted) Navigator.pop(dlgCtx);
                            onCreated?.call();
                          } else {
                            final err = jsonDecode(res.body)['detail'] ?? 'Failed to register venue';
                            setDlgState(() => errorMsg = err.toString());
                          }
                        } catch (e) {
                          setDlgState(() => errorMsg = 'Error: $e');
                        } finally {
                          setDlgState(() => isSaving = false);
                        }
                      },
                child: isSaving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save & Select Venue'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openVenuePickerModal() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    String selectedTypeFilter = _isLab ? 'LABORATORY' : 'ALL';
    String searchQuery = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final filteredVenues = _registeredVenues.where((v) {
            final vType = (v['venue_type'] ?? '').toString().toUpperCase();
            final vCode = (v['venue_code'] ?? '').toString().toLowerCase();
            final vName = (v['venue_name'] ?? '').toString().toLowerCase();
            final vBlock = (v['block_building'] ?? '').toString().toLowerCase();
            final q = searchQuery.toLowerCase().trim();

            final matchesType = selectedTypeFilter == 'ALL' ||
                vType == selectedTypeFilter ||
                (selectedTypeFilter == 'LECTURE_HALL' && (vType == 'LECTURE_HALL' || vType == 'SMART_CLASSROOM'));
            final matchesQuery = q.isEmpty || vCode.contains(q) || vName.contains(q) || vBlock.contains(q);
            return matchesType && matchesQuery;
          }).toList();

          return Container(
            height: MediaQuery.of(context).size.height * 0.78,
            decoration: BoxDecoration(
              color: AdminColors.getCard(isDark),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                // Modal Drag Handle
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2)),
                  ),
                ),

                // Modal Title
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF2563EB), Color(0xFF7C3AED)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.domain_rounded, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text('Select Campus Hall / Laboratory', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AdminColors.getTextPrimary(isDark))),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text('Global Matrix', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green)),
                                ),
                              ],
                            ),
                            Text('Institutional facilities shared across all departments & years', style: GoogleFonts.inter(fontSize: 11, color: AdminColors.getTextSecondary(isDark))),
                          ],
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () {
                          _showQuickCreateVenueDialog(
                            onCreated: () {
                              if (ctx.mounted) Navigator.pop(ctx);
                            },
                          );
                        },
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add Custom Venue'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded)),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // Search Box
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search hall code, laboratory, or building block...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      isDense: true,
                    ),
                    onChanged: (v) => setModalState(() => searchQuery = v),
                  ),
                ),

                // Filter Tabs
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        'ALL',
                        'LECTURE_HALL',
                        'LABORATORY',
                        'SMART_CLASSROOM',
                        'SEMINAR_HALL',
                      ].map((t) {
                        final isSel = selectedTypeFilter == t;
                        final label = t == 'ALL'
                            ? 'All Facilities'
                            : t == 'LECTURE_HALL'
                                ? 'Lecture Halls'
                                : t == 'LABORATORY'
                                    ? 'Specialized Labs'
                                    : t == 'SMART_CLASSROOM'
                                        ? 'Smart Rooms'
                                        : 'Seminar Halls';
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(label, style: TextStyle(fontSize: 11, color: isSel ? Colors.white : null)),
                            selected: isSel,
                            selectedColor: const Color(0xFF2563EB),
                            onSelected: (sel) {
                              if (sel) setModalState(() => selectedTypeFilter = t);
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 6),

                // Venues List
                Expanded(
                  child: filteredVenues.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.meeting_room_outlined, size: 40, color: Colors.grey.shade400),
                              const SizedBox(height: 8),
                              Text('No matching campus facilities found.', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          itemCount: filteredVenues.length,
                          itemBuilder: (ctx, i) {
                            final v = filteredVenues[i];
                            final vCode = v['venue_code'] ?? '';
                            final vName = v['venue_name'] ?? '';
                            final vType = (v['venue_type'] ?? 'LECTURE_HALL').toString().toUpperCase();
                            final isLabItem = vType == 'LABORATORY' || vType == 'WORKSHOP';
                            final isSelected = _roomCtrl.text.trim().toLowerCase() == vCode.toString().toLowerCase();

                            final typeColor = isLabItem
                                ? const Color(0xFF8B5CF6)
                                : vType == 'SMART_CLASSROOM'
                                    ? const Color(0xFF10B981)
                                    : vType == 'SEMINAR_HALL'
                                        ? const Color(0xFFF59E0B)
                                        : const Color(0xFF2563EB);

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: isSelected ? typeColor.withValues(alpha: 0.1) : (isDark ? const Color(0xFF1E293B) : Colors.white),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: isSelected ? typeColor : AdminColors.getBorder(isDark), width: isSelected ? 1.5 : 1),
                              ),
                              child: ListTile(
                                dense: true,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                leading: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: typeColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(isLabItem ? Icons.science_rounded : Icons.meeting_room_rounded, size: 14, color: typeColor),
                                      const SizedBox(width: 4),
                                      Text(
                                        vCode,
                                        style: TextStyle(
                                          color: typeColor,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                title: Text(vName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                subtitle: Text(
                                  '${v['block_building']} • ${v['floor_number']} • ${v['capacity']} seats ${isLabItem && (v['lab_workstations'] ?? 0) > 0 ? '• ${v['lab_workstations']} PCs' : ''}',
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                ),
                                trailing: isSelected
                                    ? Icon(Icons.check_circle_rounded, color: typeColor, size: 20)
                                    : const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                                onTap: () {
                                  setState(() {
                                    _roomCtrl.text = vCode;
                                    if (isLabItem) {
                                      _isLab = true;
                                      if (_spanPeriods == 1) _spanPeriods = 2;
                                    }
                                  });
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

  Future<void> _saveSlot({bool allowOverride = false}) async {
    if (_codeCtrl.text.trim().isEmpty || _nameCtrl.text.trim().isEmpty) {
      setState(() => _conflictWarning = 'Please pick a subject from the curriculum catalog.');
      return;
    }
    if (_selectedFacultyRegNo == null) {
      setState(() => _conflictWarning = 'Please choose a faculty member for this slot.');
      return;
    }

    setState(() {
      _isSaving = true;
      _conflictWarning = null;
    });

    try {
      final res = await http.post(
        Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/academics/timetable/slot'),
        headers: {'Authorization': 'Bearer ${widget.token}', 'Content-Type': 'application/json'},
        body: jsonEncode({
          'dept': widget.dept,
          'batch': widget.batch,
          'semester': widget.semester,
          'section': widget.section,
          'day_of_week': widget.dayOfWeek,
          'period_number': widget.periodNumber,
          'span_periods': _isLab ? _spanPeriods : 1,
          'subject_code': _codeCtrl.text.trim(),
          'subject_name': _nameCtrl.text.trim(),
          'staff_reg_no': _selectedFacultyRegNo,
          'room_or_lab': _roomCtrl.text.trim(),
          'is_lab_block': _isLab,
          'lab_batch': _labBatch,
          'allow_override': allowOverride,
        }),
      );

      if (res.statusCode == 200 && mounted) {
        widget.onSaved();
        Navigator.pop(context);
      } else if (res.statusCode == 409) {
        final err = jsonDecode(res.body)['detail'] ?? 'Faculty collision detected.';
        setState(() => _conflictWarning = err);
      } else {
        final err = jsonDecode(res.body)['detail'] ?? 'Failed to save slot';
        setState(() => _conflictWarning = err);
      }
    } catch (e) {
      setState(() => _conflictWarning = 'Network error: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _clearSlot() async {
    setState(() => _isSaving = true);
    try {
      final uri = Uri.parse(
        '${CollegeIPConfig.defaultURL}/api/v1/academics/timetable/slot?dept=${Uri.encodeComponent(widget.dept)}&batch=${Uri.encodeComponent(widget.batch)}&semester=${widget.semester}&section=${Uri.encodeComponent(widget.section)}&day_of_week=${Uri.encodeComponent(widget.dayOfWeek)}&period_number=${widget.periodNumber}&lab_batch=${Uri.encodeComponent(_labBatch)}',
      );
      final res = await http.delete(uri, headers: {'Authorization': 'Bearer ${widget.token}'});
      if (res.statusCode == 200 && mounted) {
        widget.onSaved();
        Navigator.pop(context);
      }
    } catch (_) {}
    if (mounted) setState(() => _isSaving = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dynamicVenues = _registeredVenues.isNotEmpty
        ? _registeredVenues
            .where((v) => _isLab ? (v['venue_type'] == 'LABORATORY' || v['venue_type'] == 'WORKSHOP') : (v['venue_type'] != 'LABORATORY' && v['venue_type'] != 'WORKSHOP'))
            .map((v) => v['venue_code']?.toString() ?? '')
            .where((c) => c.isNotEmpty)
            .toList()
        : <String>[];
    final venueSuggestions = dynamicVenues;

    return AlertDialog(
      backgroundColor: AdminColors.getCard(isDark),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: AdminColors.primarySoft, borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.edit_calendar_rounded, color: AdminColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${widget.dayOfWeek} — Period ${widget.periodNumber}', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AdminColors.getTextPrimary(isDark))),
                Text('${widget.periodTimeRange} | ${widget.dept} Sem ${widget.semester} (${widget.section})', style: GoogleFonts.inter(fontSize: 12, color: AdminColors.getTextSecondary(isDark))),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Subject Selection Header & Quick Allocation Chips
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Curriculum Subject *',
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AdminColors.getTextSecondary(isDark)),
                    ),
                    TextButton.icon(
                      onPressed: _openCurriculumPickerModal,
                      icon: const Icon(Icons.auto_stories_rounded, size: 14),
                      label: Text(
                        _codeCtrl.text.isNotEmpty ? 'Browse All Curriculum' : 'Curriculum Catalog',
                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // Quick Allocated Subjects Choice Chips (if any allocated)
                if (widget.subjectAllocations.isNotEmpty) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: widget.subjectAllocations.map((sub) {
                      final isLabSub = (sub['subject_type'] ?? '').toString().toLowerCase().contains('lab');
                      final isSelected = _codeCtrl.text.trim().toLowerCase() == (sub['subject_code'] ?? '').toString().toLowerCase();
                      return ChoiceChip(
                        avatar: Icon(
                          isLabSub ? Icons.science_rounded : Icons.menu_book_rounded,
                          size: 13,
                          color: isSelected ? Colors.white : (isLabSub ? Colors.purple : AdminColors.primary),
                        ),
                        label: Text(
                          '${sub['subject_code']}: ${sub['subject_name']}',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            color: isSelected ? Colors.white : AdminColors.getTextPrimary(isDark),
                          ),
                        ),
                        selected: isSelected,
                        selectedColor: isLabSub ? const Color(0xFF8B5CF6) : AdminColors.primary,
                        backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                        onSelected: (_) => _onSubjectSelected(sub),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),
                ],

                // 2. Selected Curriculum Subject Display Card / Picker Trigger
                InkWell(
                  onTap: _openCurriculumPickerModal,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _codeCtrl.text.isNotEmpty ? (_isLab ? Colors.purple : AdminColors.primary) : AdminColors.getBorder(isDark),
                        width: _codeCtrl.text.isNotEmpty ? 1.5 : 1,
                      ),
                    ),
                    child: _codeCtrl.text.isNotEmpty
                        ? Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _isLab ? Colors.purple.withValues(alpha: 0.15) : AdminColors.primarySoft,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _isLab ? Icons.science_rounded : Icons.menu_book_rounded,
                                      size: 13,
                                      color: _isLab ? Colors.purple : AdminColors.primary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _codeCtrl.text,
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: _isLab ? Colors.purple : AdminColors.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _nameCtrl.text,
                                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AdminColors.getTextPrimary(isDark)),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      '${_isLab ? "Laboratory / Practical" : "Theory"} • ${widget.dept} Sem ${widget.semester}',
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

                // 3. Faculty Selector Card (Supports All Departments & HODs)
                Text('Faculty / Teacher (Cross-Department Access) *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AdminColors.getTextSecondary(isDark))),
                const SizedBox(height: 6),
                InkWell(
                  onTap: _openFacultyPickerModal,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _selectedFacultyRegNo != null ? AdminColors.primary : AdminColors.getBorder(isDark)),
                    ),
                    child: _selectedFacultyRegNo != null
                        ? Row(
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: _selectedFacultyIsHod ? Colors.amber[100] : AdminColors.primarySoft,
                                child: _selectedFacultyIsHod
                                    ? Icon(Icons.stars_rounded, color: Colors.amber[800], size: 16)
                                    : Text(
                                        (_selectedFacultyName?.isNotEmpty == true ? _selectedFacultyName![0] : 'F').toUpperCase(),
                                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AdminColors.primary),
                                      ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            _selectedFacultyName ?? _selectedFacultyRegNo!,
                                            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AdminColors.getTextPrimary(isDark)),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (_selectedFacultyIsHod) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                            decoration: BoxDecoration(color: Colors.amber[100], borderRadius: BorderRadius.circular(4)),
                                            child: Text('HOD', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.amber[900])),
                                          ),
                                        ],
                                      ],
                                    ),
                                    Text(
                                      'Dept: ${_selectedFacultyDept ?? "General"} • ID: $_selectedFacultyRegNo',
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
                              Text('Click to Choose Faculty (Search any Dept)...', style: GoogleFonts.inter(fontSize: 13, color: AdminColors.getTextSecondary(isDark))),
                              const Spacer(),
                              const Icon(Icons.arrow_drop_down_rounded),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 14),

                // 4. Room & Lab Settings with Live Search Suggestions
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: RawAutocomplete<Map<String, dynamic>>(
                        textEditingController: _roomCtrl,
                        focusNode: _roomFocusNode,
                        optionsBuilder: (TextEditingValue textEditingValue) {
                          if (_registeredVenues.isEmpty) {
                            return const Iterable<Map<String, dynamic>>.empty();
                          }
                          final query = textEditingValue.text.trim().toLowerCase();
                          if (query.isEmpty) {
                            final sorted = List<Map<String, dynamic>>.from(_registeredVenues);
                            sorted.sort((a, b) {
                              final aType = (a['venue_type'] ?? '').toString().toUpperCase();
                              final bType = (b['venue_type'] ?? '').toString().toUpperCase();
                              final aIsLab = aType == 'LABORATORY' || aType == 'WORKSHOP';
                              final bIsLab = bType == 'LABORATORY' || bType == 'WORKSHOP';
                              if (_isLab) {
                                if (aIsLab && !bIsLab) return -1;
                                if (!aIsLab && bIsLab) return 1;
                              } else {
                                if (!aIsLab && bIsLab) return -1;
                                if (aIsLab && !bIsLab) return 1;
                              }
                              return (a['venue_code'] ?? '').toString().compareTo((b['venue_code'] ?? '').toString());
                            });
                            return sorted;
                          }

                          return _registeredVenues.where((v) {
                            final code = (v['venue_code'] ?? '').toString().toLowerCase();
                            final name = (v['venue_name'] ?? '').toString().toLowerCase();
                            final building = (v['block_building'] ?? '').toString().toLowerCase();
                            final type = (v['venue_type'] ?? '').toString().toLowerCase();
                            final dept = (v['dept'] ?? '').toString().toLowerCase();
                            return code.contains(query) ||
                                name.contains(query) ||
                                building.contains(query) ||
                                type.contains(query) ||
                                dept.contains(query);
                          });
                        },
                        displayStringForOption: (option) => option['venue_code']?.toString() ?? '',
                        onSelected: (option) {
                          final vCode = (option['venue_code'] ?? '').toString();
                          final vType = (option['venue_type'] ?? '').toString().toUpperCase();
                          final isLabItem = vType == 'LABORATORY' || vType == 'WORKSHOP';
                          setState(() {
                            _roomCtrl.text = vCode;
                            if (isLabItem) {
                              _isLab = true;
                              if (_spanPeriods == 1) _spanPeriods = 2;
                            } else {
                              _isLab = false;
                              _spanPeriods = 1;
                            }
                          });
                        },
                        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                          return TextFormField(
                            controller: controller,
                            focusNode: focusNode,
                            onFieldSubmitted: (_) => onFieldSubmitted(),
                            decoration: InputDecoration(
                              labelText: 'Room / Lab / Venue',
                              hintText: _registeredVenues.isNotEmpty ? 'Type to search venues...' : 'e.g. LH-101, Lab 2',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              isDense: true,
                              prefixIcon: Icon(
                                _isLab ? Icons.science_rounded : Icons.meeting_room_rounded,
                                size: 18,
                                color: _isLab ? const Color(0xFF8B5CF6) : AdminColors.primary,
                              ),
                              suffixIcon: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_roomCtrl.text.isNotEmpty)
                                    IconButton(
                                      icon: const Icon(Icons.clear_rounded, size: 16),
                                      splashRadius: 16,
                                      tooltip: 'Clear Venue',
                                      onPressed: () {
                                        setState(() {
                                          _roomCtrl.clear();
                                        });
                                      },
                                    ),
                                  IconButton(
                                    icon: Icon(
                                      _isLab ? Icons.science_rounded : Icons.meeting_room_rounded,
                                      size: 18,
                                      color: AdminColors.primary,
                                    ),
                                    tooltip: 'Browse All Registered Venues',
                                    onPressed: _openVenuePickerModal,
                                  ),
                                ],
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          );
                        },
                        optionsViewBuilder: (context, onSelected, options) {
                          final isDark = Theme.of(context).brightness == Brightness.dark;
                          final optionsList = options.toList();
                          if (optionsList.isEmpty) return const SizedBox.shrink();

                          return Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              elevation: 8,
                              shadowColor: Colors.black26,
                              borderRadius: BorderRadius.circular(12),
                              color: isDark ? const Color(0xFF1E293B) : Colors.white,
                              child: Container(
                                width: 320,
                                constraints: const BoxConstraints(maxHeight: 240),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AdminColors.getBorder(isDark)),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                                        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                                        border: Border(bottom: BorderSide(color: AdminColors.getBorder(isDark))),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.place_rounded, size: 13, color: AdminColors.primary),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Available Venues (${optionsList.length})',
                                            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AdminColors.primary),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Flexible(
                                      child: ListView.separated(
                                        padding: EdgeInsets.zero,
                                        shrinkWrap: true,
                                        itemCount: optionsList.length,
                                        separatorBuilder: (ctx, idx) => Divider(height: 1, color: AdminColors.getBorder(isDark).withValues(alpha: 0.5)),
                                        itemBuilder: (ctx, idx) {
                                          final v = optionsList[idx];
                                          final vCode = (v['venue_code'] ?? '').toString();
                                          final vName = (v['venue_name'] ?? '').toString();
                                          final vType = (v['venue_type'] ?? 'LECTURE_HALL').toString().toUpperCase();
                                          final isLabItem = vType == 'LABORATORY' || vType == 'WORKSHOP';
                                          final isSelected = _roomCtrl.text.trim().toLowerCase() == vCode.toLowerCase();

                                          final typeColor = isLabItem
                                              ? const Color(0xFF8B5CF6)
                                              : vType == 'SMART_CLASSROOM'
                                                  ? const Color(0xFF10B981)
                                                  : vType == 'SEMINAR_HALL'
                                                      ? const Color(0xFFF59E0B)
                                                      : const Color(0xFF2563EB);

                                          return InkWell(
                                            onTap: () => onSelected(v),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                              color: isSelected ? typeColor.withValues(alpha: 0.12) : Colors.transparent,
                                              child: Row(
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: typeColor.withValues(alpha: 0.15),
                                                      borderRadius: BorderRadius.circular(6),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Icon(isLabItem ? Icons.science_rounded : Icons.meeting_room_rounded, size: 12, color: typeColor),
                                                        const SizedBox(width: 4),
                                                        Text(
                                                          vCode,
                                                          style: TextStyle(color: typeColor, fontWeight: FontWeight.bold, fontSize: 11),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Text(
                                                          vName.isNotEmpty ? vName : vCode,
                                                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AdminColors.getTextPrimary(isDark)),
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                        Text(
                                                          '${v['block_building'] ?? "Building"} • ${v['floor_number'] ?? "Floor"} • ${v['capacity'] ?? 60} seats ${isLabItem && (v['lab_workstations'] ?? 0) > 0 ? "• ${v['lab_workstations']} PCs" : ""}',
                                                          style: GoogleFonts.inter(fontSize: 10, color: AdminColors.getTextSecondary(isDark)),
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  if (isSelected)
                                                    Icon(Icons.check_circle_rounded, color: typeColor, size: 16),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: CheckboxListTile(
                        title: Text('Lab / Practical', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                        value: _isLab,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (v) {
                          setState(() {
                            _isLab = v ?? false;
                            if (_isLab && _spanPeriods == 1) _spanPeriods = 2;
                          });
                        },
                      ),
                    ),
                  ],
                ),

                // 5. Multi-Period Lab Block Span
                if (_isLab) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.purple.withValues(alpha: isDark ? 0.2 : 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.timer_outlined, size: 18, color: Colors.purple),
                        const SizedBox(width: 8),
                        Text('Lab Block Duration:', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 10),
                        DropdownButton<int>(
                          value: _spanPeriods,
                          isDense: true,
                          underline: const SizedBox(),
                          items: const [
                            DropdownMenuItem(value: 1, child: Text('1 Period')),
                            DropdownMenuItem(value: 2, child: Text('2 Periods (Consecutive)')),
                            DropdownMenuItem(value: 3, child: Text('3 Periods (Full Block)')),
                          ],
                          onChanged: (v) => setState(() => _spanPeriods = v ?? 1),
                        ),
                      ],
                    ),
                  ),
                ],

                // 6. Venue Quick Chips
                if (venueSuggestions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: venueSuggestions.map((venue) {
                      final isSelected = _roomCtrl.text.trim().toLowerCase() == venue.toLowerCase();
                      return InkWell(
                        onTap: () {
                          final vObj = _registeredVenues.firstWhere(
                            (element) => (element['venue_code'] ?? '').toString().toLowerCase() == venue.toLowerCase(),
                            orElse: () => {},
                          );
                          final vType = (vObj['venue_type'] ?? '').toString().toUpperCase();
                          final isLabItem = vType == 'LABORATORY' || vType == 'WORKSHOP';
                          setState(() {
                            _roomCtrl.text = venue;
                            if (isLabItem) {
                              _isLab = true;
                              if (_spanPeriods == 1) _spanPeriods = 2;
                            }
                          });
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AdminColors.primary.withValues(alpha: 0.15)
                                : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: isSelected ? AdminColors.primary : AdminColors.getBorder(isDark)),
                          ),
                          child: Text(
                            venue,
                            style: GoogleFonts.inter(
                              fontSize: 10.5,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                              color: isSelected ? AdminColors.primary : AdminColors.getTextSecondary(isDark),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],

                // 7. Conflict Warning Display
                if (_conflictWarning != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: AdminColors.dangerSoft, borderRadius: BorderRadius.circular(8), border: Border.all(color: AdminColors.danger)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, size: 18, color: AdminColors.danger),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_conflictWarning!, style: GoogleFonts.inter(fontSize: 11, color: AdminColors.danger, fontWeight: FontWeight.w600))),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => _saveSlot(allowOverride: true),
                          style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(50, 24)),
                          child: Text('Override Conflict & Save Anyway', style: GoogleFonts.inter(fontSize: 11, color: AdminColors.danger, decoration: TextDecoration.underline)),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (widget.initialSlot != null)
          TextButton.icon(
            onPressed: _isSaving ? null : _clearSlot,
            icon: const Icon(Icons.delete_outline_rounded, size: 16, color: AdminColors.danger),
            label: const Text('Clear Slot', style: TextStyle(color: AdminColors.danger)),
          ),
        const Spacer(),
        TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: GoogleFonts.inter(color: AdminColors.getTextSecondary(isDark)))),
        ElevatedButton(
          onPressed: _isSaving ? null : () => _saveSlot(allowOverride: false),
          style: ElevatedButton.styleFrom(backgroundColor: AdminColors.primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
          child: _isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save Slot'),
        ),
      ],
    );
  }
}
