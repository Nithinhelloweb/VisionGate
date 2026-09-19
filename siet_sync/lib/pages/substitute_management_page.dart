import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/features_service.dart';

class SubstituteManagementPage extends StatefulWidget {
  final String token;
  final Map<String, dynamic> user;
  final bool isAdminOrHod;

  const SubstituteManagementPage({
    super.key,
    required this.token,
    required this.user,
    this.isAdminOrHod = true,
  });


  @override
  State<SubstituteManagementPage> createState() => _SubstituteManagementPageState();
}

class _SubstituteManagementPageState extends State<SubstituteManagementPage> {
  bool _isLoading = false;
  String _selectedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
  List<Map<String, dynamic>> _assignments = [];

  @override
  void initState() {
    super.initState();
    _loadAssignments();
  }

  Future<void> _loadAssignments() async {
    setState(() => _isLoading = true);
    final list = await FeaturesService.getSubstituteAssignments(widget.token, assignmentDate: _selectedDate);
    if (mounted) {
      setState(() {
        _assignments = list;
        _isLoading = false;
      });
    }
  }

  void _openAssignSubstituteDialog() {
    final origRegController = TextEditingController();
    final subRegController = TextEditingController();
    final subjectCodeController = TextEditingController(text: 'CS301');
    final subjectNameController = TextEditingController(text: 'Data Structures');
    final reasonController = TextEditingController(text: 'Faculty on Approved Leave');
    int period = 1;
    String dept = 'CSE';
    String batch = '2024-2028';
    int sem = 3;
    String sec = 'A';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Assign Substitute Faculty', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: origRegController,
                          decoration: InputDecoration(
                            labelText: 'Original Faculty',
                            hintText: 'e.g. STF001',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: subRegController,
                          decoration: InputDecoration(
                            labelText: 'Substitute Faculty',
                            hintText: 'e.g. STF009',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: period,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'Period',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                          ),
                          items: List.generate(8, (i) => DropdownMenuItem(value: i + 1, child: Text('Period ${i + 1}', overflow: TextOverflow.ellipsis))),
                          onChanged: (v) => setDialogState(() => period = v ?? 1),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: dept,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'Department',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'CSE', child: Text('CSE', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 'ECE', child: Text('ECE', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 'EEE', child: Text('EEE', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 'MECH', child: Text('MECH', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 'CIVIL', child: Text('CIVIL', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 'IT', child: Text('IT', overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: (v) => setDialogState(() => dept = v ?? 'CSE'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: subjectCodeController,
                          decoration: InputDecoration(
                            labelText: 'Subject Code',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: subjectNameController,
                          decoration: InputDecoration(
                            labelText: 'Subject Name',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reasonController,
                    decoration: InputDecoration(
                      labelText: 'Reason for Substitution',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (origRegController.text.trim().isEmpty || subRegController.text.trim().isEmpty) return;
                Navigator.pop(ctx);
                setState(() => _isLoading = true);
                final ok = await FeaturesService.addSubstituteAssignment(
                  widget.token,
                  originalStaffRegNo: origRegController.text.trim(),
                  substituteStaffRegNo: subRegController.text.trim(),
                  assignmentDate: _selectedDate,
                  periodNumber: period,
                  dept: dept,
                  batch: batch,
                  semester: sem,
                  section: sec,
                  subjectCode: subjectCodeController.text.trim(),
                  subjectName: subjectNameController.text.trim(),
                  reason: reasonController.text.trim(),
                );
                setState(() => _isLoading = false);
                if (ok && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Substitute assignment booked successfully.')),
                  );
                  _loadAssignments();
                }
              },
              child: const Text('Confirm Assignment'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Timetable & Substitute Faculty', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today_rounded, size: 16),
            label: Text('Date: $_selectedDate'),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: DateTime.now(),
                firstDate: DateTime(2024),
                lastDate: DateTime(2028),
              );
              if (picked != null && mounted) {
                setState(() => _selectedDate = DateFormat('yyyy-MM-dd').format(picked));
                _loadAssignments();
              }
            },
          ),
          const SizedBox(width: 12),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAssignSubstituteDialog,
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Assign Substitute'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _assignments.isEmpty
              ? const Center(child: Text('No substitute assignments booked for this date.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _assignments.length,
                  itemBuilder: (ctx, i) {
                    final a = _assignments[i];
                    final assignId = a['id'] as int;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    'Period ${a['period_number']} • ${a['dept']} (Sem ${a['semester']}-${a['section']})',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                                  onPressed: () async {
                                    final messenger = ScaffoldMessenger.of(context);
                                    final ok = await FeaturesService.deleteSubstituteAssignment(widget.token, assignId);
                                    if (ok) {
                                      messenger.showSnackBar(
                                        const SnackBar(content: Text('Substitute assignment cancelled.')),
                                      );
                                      _loadAssignments();
                                    }
                                  },


                                ),
                              ],
                            ),

                            const Divider(height: 16),
                            Row(
                              children: [
                                Expanded(child: Text('Absent: ${a['original_staff_name'] ?? a['original_staff_reg_no']}', style: const TextStyle(color: Colors.red))),
                                Expanded(child: Text('Substitute: ${a['substitute_staff_name'] ?? a['substitute_staff_reg_no']}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold))),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text('Subject: ${a['subject_name']} (${a['subject_code']})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
