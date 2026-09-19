import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../config/college_ip_config.dart';

class StudentEditDialog extends StatefulWidget {
  final String token;
  final Map<String, dynamic> student;
  final VoidCallback onUpdated;

  const StudentEditDialog({
    super.key,
    required this.token,
    required this.student,
    required this.onUpdated,
  });

  static Future<void> show(
    BuildContext context, {
    required String token,
    required Map<String, dynamic> student,
    required VoidCallback onUpdated,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 680),
          child: StudentEditDialog(
            token: token,
            student: student,
            onUpdated: onUpdated,
          ),
        ),
      ),
    );
  }

  @override
  State<StudentEditDialog> createState() => _StudentEditDialogState();
}

class _StudentEditDialogState extends State<StudentEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _rollNoCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _parentPhoneCtrl;
  late final TextEditingController _mentorCtrl;
  late String _selectedBatch;
  late int _selectedSemester;
  late String _selectedSection;
  late String _selectedQuota;

  bool _isSaving = false;
  String? _errorMsg;

  // Faculty pool for Class Advisor selection
  List<Map<String, dynamic>> _facultyPool = [];
  bool _isLoadingFaculty = false;
  bool _showAllDeptsStaff = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.student['name'] ?? '');
    _rollNoCtrl = TextEditingController(text: widget.student['roll_no'] ?? '');
    _phoneCtrl = TextEditingController(text: widget.student['phone_number'] ?? '');
    _parentPhoneCtrl = TextEditingController(text: widget.student['parent_phone'] ?? '');
    _mentorCtrl = TextEditingController(text: widget.student['mentor_staff_reg_no'] ?? '');
    _selectedBatch = widget.student['batch'] ?? '2022-2026';
    _selectedSemester = int.tryParse(widget.student['semester']?.toString() ?? '1') ?? 1;
    _selectedSection = widget.student['section'] ?? 'A';
    _selectedQuota = widget.student['quota'] ?? 'Govt';

    _fetchFacultyPool();
  }

  Future<void> _fetchFacultyPool() async {
    setState(() => _isLoadingFaculty = true);
    try {
      final res = await http.get(
        Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/academics/faculty-pool?include_all_depts=true'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = List<Map<String, dynamic>>.from(data['faculty'] ?? []);
        if (mounted) {
          setState(() {
            _facultyPool = list;
            _isLoadingFaculty = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoadingFaculty = false);
      }
    } catch (e) {
      debugPrint("Error fetching faculty pool: $e");
      if (mounted) setState(() => _isLoadingFaculty = false);
    }
  }

  bool _deptMatches(String staffDept, String studentDept) {
    final sd = staffDept.toLowerCase().trim();
    final td = studentDept.toLowerCase().trim();
    if (sd == td) return true;
    if (td == 'cse' && (sd.contains('computer') || sd == 'cse')) return true;
    if (td == 'it' && (sd.contains('information') || sd == 'it')) return true;
    if (td == 'ece' && (sd.contains('electronics') || sd.contains('communication') || sd == 'ece')) return true;
    if (td == 'eee' && (sd.contains('electrical') || sd == 'eee')) return true;
    if (td == 'mech' && (sd.contains('mechanical') || sd == 'mech')) return true;
    if (td == 'civil' && (sd.contains('civil') || sd == 'civil')) return true;
    if ((td == 'ai & ds' || td == 'ai & ml') && (sd.contains('ai') || sd.contains('data') || sd.contains('machine'))) return true;
    return false;
  }

  List<Map<String, dynamic>> _getFilteredFaculty() {
    if (_showAllDeptsStaff) return _facultyPool;
    final dept = (widget.student['dept'] ?? '').toString();
    return _facultyPool.where((f) {
      final fDept = (f['dept'] ?? '').toString();
      return _deptMatches(fDept, dept);
    }).toList();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _rollNoCtrl.dispose();
    _phoneCtrl.dispose();
    _parentPhoneCtrl.dispose();
    _mentorCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isSaving = true;
      _errorMsg = null;
    });

    final regNo = widget.student['reg_no'];
    final payload = {
      'name': _nameCtrl.text.trim(),
      'roll_no': _rollNoCtrl.text.trim().isEmpty ? null : _rollNoCtrl.text.trim(),
      'phone_number': _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
      'parent_phone': _parentPhoneCtrl.text.trim(),
      'mentor_staff_reg_no': _mentorCtrl.text.trim().isEmpty ? null : _mentorCtrl.text.trim(),
      'batch': _selectedBatch,
      'semester': _selectedSemester,
      'section': _selectedSection,
      'quota': _selectedQuota,
    };

    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);

    try {
      final res = await http.put(
        Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/students/$regNo'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
        body: jsonEncode(payload),
      );

      if (res.statusCode == 200) {
        nav.pop();
        messenger.showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            content: Text('Student $regNo updated successfully!'),
          ),
        );
        widget.onUpdated();
      } else {
        final err = jsonDecode(res.body);
        setState(() {
          _errorMsg = err['detail'] ?? 'Failed to update student.';
          _isSaving = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMsg = 'Network error: $e';
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final regNo = widget.student['reg_no'] ?? '';

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          elevation: 0,
          title: Text('Edit Student ($regNo)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_errorMsg != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(_errorMsg!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                  ),

                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'Student Full Name *', prefixIcon: Icon(Icons.person_outline)),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Name required' : null,
                ),
                const SizedBox(height: 14),

                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _rollNoCtrl,
                        decoration: const InputDecoration(labelText: 'Roll No', prefixIcon: Icon(Icons.pin_outlined)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedBatch,
                        decoration: const InputDecoration(labelText: 'Batch', prefixIcon: Icon(Icons.calendar_today_outlined)),
                        items: ['2021-2025', '2022-2026', '2023-2027', '2024-2028', '2025-2029']
                            .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                            .toList(),
                        onChanged: (v) => setState(() => _selectedBatch = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _selectedSemester,
                        decoration: const InputDecoration(labelText: 'Semester', prefixIcon: Icon(Icons.timeline_outlined)),
                        items: List.generate(8, (i) => i + 1)
                            .map((s) => DropdownMenuItem(value: s, child: Text('Sem $s')))
                            .toList(),
                        onChanged: (v) => setState(() => _selectedSemester = v!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedSection,
                        decoration: const InputDecoration(labelText: 'Section', prefixIcon: Icon(Icons.group_work_outlined)),
                        items: ['A', 'B', 'C', 'D']
                            .map((s) => DropdownMenuItem(value: s, child: Text('Sec $s')))
                            .toList(),
                        onChanged: (v) => setState(() => _selectedSection = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _phoneCtrl,
                        decoration: const InputDecoration(labelText: 'Student Mobile', prefixIcon: Icon(Icons.phone_iphone_outlined)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _parentPhoneCtrl,
                        decoration: const InputDecoration(labelText: 'Parent Mobile *', prefixIcon: Icon(Icons.phone_outlined)),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Parent contact required' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: _mentorCtrl.text.trim().isEmpty
                                ? ''
                                : (_facultyPool.any((f) =>
                                        (f['reg_no'] ?? '').toString() ==
                                        _mentorCtrl.text.trim())
                                    ? _mentorCtrl.text.trim()
                                    : ''),
                            decoration: InputDecoration(
                              labelText: 'Class Advisor / Mentor',
                              prefixIcon: const Icon(Icons.supervisor_account_outlined),
                              suffixIcon: _isLoadingFaculty
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: Padding(
                                        padding: EdgeInsets.all(12),
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                    )
                                  : null,
                            ),
                            isExpanded: true,
                            items: [
                              const DropdownMenuItem<String>(
                                value: '',
                                child: Text(
                                  '-- No Advisor Assigned --',
                                  style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                                ),
                              ),
                              ..._getFilteredFaculty().map((f) {
                                final regNo = (f['reg_no'] ?? '').toString();
                                final name = (f['name'] ?? '').toString();
                                final isHod = f['is_hod'] == true ||
                                    (f['role'] ?? '').toString().toLowerCase() == 'hod';
                                final dept = (f['dept'] ?? '').toString();
                                return DropdownMenuItem<String>(
                                  value: regNo,
                                  child: Text(
                                    '$name ($regNo)${isHod ? ' [HOD]' : ''}${_showAllDeptsStaff ? ' - $dept' : ''}',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: isHod ? FontWeight.bold : FontWeight.normal,
                                      fontSize: 13,
                                    ),
                                  ),
                                );
                              }),
                            ],
                            onChanged: (val) {
                              setState(() {
                                _mentorCtrl.text = val ?? '';
                              });
                            },
                          ),
                          if (_getFilteredFaculty().isEmpty && !_isLoadingFaculty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4, left: 4),
                              child: Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    'No staff in ${widget.student['dept'] ?? 'dept'}. ',
                                    style: const TextStyle(fontSize: 11, color: Colors.orange),
                                  ),
                                  GestureDetector(
                                    onTap: () => setState(() => _showAllDeptsStaff = true),
                                    child: const Text(
                                      'Show all staff',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF2563EB),
                                          fontWeight: FontWeight.bold,
                                          decoration: TextDecoration.underline),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else if (!_showAllDeptsStaff)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(50, 20),
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: () => setState(() => _showAllDeptsStaff = true),
                                child: const Text('Show all staff',
                                    style: TextStyle(fontSize: 11, color: Color(0xFF2563EB))),
                              ),
                            )
                          else
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(50, 20),
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: () => setState(() => _showAllDeptsStaff = false),
                                child: Text('Filter by ${widget.student['dept'] ?? 'dept'} only',
                                    style: const TextStyle(fontSize: 11, color: Color(0xFF2563EB))),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedQuota,
                        decoration: const InputDecoration(labelText: 'Quota', prefixIcon: Icon(Icons.account_balance_outlined)),
                        items: ['Govt', 'Management', 'Sports', 'NRI']
                            .map((q) => DropdownMenuItem(value: q, child: Text(q)))
                            .toList(),
                        onChanged: (v) => setState(() => _selectedQuota = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isSaving ? null : () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveChanges,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: _isSaving
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
