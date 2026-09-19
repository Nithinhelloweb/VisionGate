import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/admin_theme.dart';
import '../../widgets/admin_design_system.dart';

class StudentAttendancePolicyCard extends StatefulWidget {
  final Map<String, dynamic> policy;
  final List<dynamic> milestones;
  final ValueChanged<Map<String, dynamic>> onPolicyChanged;
  final ValueChanged<List<dynamic>> onMilestonesChanged;
  final VoidCallback onSave;
  final bool isSaving;

  const StudentAttendancePolicyCard({
    super.key,
    required this.policy,
    required this.milestones,
    required this.onPolicyChanged,
    required this.onMilestonesChanged,
    required this.onSave,
    this.isSaving = false,
  });

  @override
  State<StudentAttendancePolicyCard> createState() => _StudentAttendancePolicyCardState();
}

class _StudentAttendancePolicyCardState extends State<StudentAttendancePolicyCard> {
  late double _minAttendance;
  late double _condonationMin;
  late double _condonationMax;
  late int _maxOdCredits;
  late int _maxMedicalCredits;
  late bool _lockPastSemesters;
  late bool _autoEligibility;
  late double _warningThreshold;

  @override
  void initState() {
    super.initState();
    _loadFromPolicy();
  }

  void _loadFromPolicy() {
    _minAttendance = (widget.policy['min_percentage'] ?? 75.0).toDouble();
    _condonationMin = (widget.policy['condonation_min'] ?? 65.0).toDouble();
    _condonationMax = (widget.policy['condonation_max'] ?? 74.9).toDouble();
    _maxOdCredits = widget.policy['max_od_credits'] ?? 10;
    _maxMedicalCredits = widget.policy['max_medical_credits'] ?? 15;
    _lockPastSemesters = widget.policy['lock_past_semesters'] ?? true;
    _autoEligibility = widget.policy['auto_calculate_eligibility'] ?? true;
    _warningThreshold = (widget.policy['notification_threshold'] ?? 80.0).toDouble();
  }

  @override
  void didUpdateWidget(covariant StudentAttendancePolicyCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.policy != widget.policy) {
      _loadFromPolicy();
    }
  }

  void _notifyPolicyChanged() {
    widget.onPolicyChanged({
      'min_percentage': _minAttendance,
      'condonation_min': _condonationMin,
      'condonation_max': _condonationMax,
      'max_od_credits': _maxOdCredits,
      'max_medical_credits': _maxMedicalCredits,
      'lock_past_semesters': _lockPastSemesters,
      'auto_calculate_eligibility': _autoEligibility,
      'notification_threshold': _warningThreshold,
    });
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '';
    return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  Future<void> _openMilestoneDialog({Map<String, dynamic>? initial, int? editIndex}) async {
    final nameCtrl = TextEditingController(text: initial?['name'] ?? '');
    String category = initial?['category'] ?? 'Exam';
    DateTime? startDate = initial?['start'] != null ? DateTime.tryParse(initial!['start']) : (initial?['date'] != null ? DateTime.tryParse(initial!['date']) : DateTime.now());
    DateTime? endDate = initial?['end'] != null ? DateTime.tryParse(initial!['end']) : startDate;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: AdminColors.getCard(isDark),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AdminColors.primarySoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.flag_rounded, color: AdminColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                editIndex != null ? 'Edit Academic Milestone' : 'Add Academic Milestone',
                style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Milestone Name',
                    hintText: 'e.g. CIA Test 1 Window, Model Exam',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Exam', child: Text('Internal Examination (CIA / Model)', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'University', child: Text('University Theory / Practical Exam', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'Instructional', child: Text('Instructional / Last Working Day', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'Event', child: Text('Symposium / College Event', overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) {
                    if (v != null) setDlgState(() => category = v);
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: startDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2035),
                          );
                          if (picked != null) setDlgState(() => startDate = picked);
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(labelText: 'Start Date', border: OutlineInputBorder()),
                          child: Text(_formatDate(startDate)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: endDate ?? startDate ?? DateTime.now(),
                            firstDate: startDate ?? DateTime(2020),
                            lastDate: DateTime(2035),
                          );
                          if (picked != null) setDlgState(() => endDate = picked);
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(labelText: 'End Date', border: OutlineInputBorder()),
                          child: Text(_formatDate(endDate)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AdminColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty || startDate == null) return;
                Navigator.pop(ctx, {
                  'id': initial?['id'] ?? 'm_${DateTime.now().millisecondsSinceEpoch}',
                  'name': nameCtrl.text.trim(),
                  'category': category,
                  'start': _formatDate(startDate),
                  'end': endDate != null ? _formatDate(endDate) : _formatDate(startDate),
                });
              },
              child: const Text('Save Milestone'),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      final updated = List<dynamic>.from(widget.milestones);
      if (editIndex != null && editIndex < updated.length) {
        updated[editIndex] = result;
      } else {
        updated.add(result);
      }
      widget.onMilestonesChanged(updated);
    }
  }

  void _deleteMilestone(int index) {
    final updated = List<dynamic>.from(widget.milestones);
    updated.removeAt(index);
    widget.onMilestonesChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Attendance Threshold Policy Card
        AdminCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 600;

                  final titleSection = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Student Attendance Eligibility Rules', style: AdminTextStyles.titleMd(isDark)),
                      const SizedBox(height: 2),
                      Text(
                        'Set minimum attendance percentage criteria for end-semester university exam hall ticket issuance',
                        style: AdminTextStyles.labelSm(isDark),
                      ),
                    ],
                  );

                  final saveButton = ElevatedButton.icon(
                    onPressed: widget.isSaving ? null : widget.onSave,
                    icon: widget.isSaving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save_rounded, size: 16),
                    label: const Text('Save Policy'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AdminColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    ),
                  );

                  if (isNarrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        titleSection,
                        const SizedBox(height: 12),
                        saveButton,
                      ],
                    );
                  }

                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: titleSection),
                      const SizedBox(width: 12),
                      saveButton,
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),

              // Mandatory Minimum Attendance Slider
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AdminColors.getCardTinted(isDark),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AdminColors.getBorder(isDark)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Minimum Mandatory Attendance Threshold',
                            style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AdminColors.primary,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${_minAttendance.toStringAsFixed(0)}%',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Slider(
                      value: _minAttendance,
                      min: 50.0,
                      max: 90.0,
                      divisions: 40,
                      activeColor: AdminColors.primary,
                      onChanged: (v) {
                        setState(() => _minAttendance = v);
                        _notifyPolicyChanged();
                      },
                    ),
                    Text(
                      'Students with attendance >= ${_minAttendance.toStringAsFixed(0)}% are directly eligible for exams.',
                      style: AdminTextStyles.labelSm(isDark),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Condonation Brackets & OD allowances
              LayoutBuilder(
                builder: (context, constraints) {
                  final isStacked = constraints.maxWidth < 600;

                  final condonationCard = Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AdminColors.getCardTinted(isDark),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AdminColors.getBorder(isDark)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.medical_services_outlined, size: 18, color: AdminColors.warning),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text('Condonation Window', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Allowed Range: ${_condonationMin.toStringAsFixed(0)}% to ${_condonationMax.toStringAsFixed(0)}%',
                          style: AdminTextStyles.bodySm(isDark),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Students in this range require medical certificate or authorized condonation fee.',
                          style: AdminTextStyles.labelSm(isDark).copyWith(fontSize: 11),
                        ),
                      ],
                    ),
                  );

                  final odCard = Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AdminColors.getCardTinted(isDark),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AdminColors.getBorder(isDark)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.assignment_turned_in_outlined, size: 18, color: AdminColors.success),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text('On-Duty (OD) / Medical Cap', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Max OD: $_maxOdCredits Days • Max Medical: $_maxMedicalCredits Days',
                          style: AdminTextStyles.bodySm(isDark),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Attendance credit will be granted up to these maximum thresholds per semester.',
                          style: AdminTextStyles.labelSm(isDark).copyWith(fontSize: 11),
                        ),
                      ],
                    ),
                  );

                  if (isStacked) {
                    return Column(
                      children: [
                        condonationCard,
                        const SizedBox(height: 12),
                        odCard,
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(child: condonationCard),
                      const SizedBox(width: 16),
                      Expanded(child: odCard),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),

              // Policy Switches
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Lock Past Semester Attendance Records'),
                subtitle: const Text('Prevents retrospective modifications to attendance after semester completion'),
                value: _lockPastSemesters,
                activeThumbColor: AdminColors.primary,
                onChanged: (v) {
                  setState(() => _lockPastSemesters = v);
                  _notifyPolicyChanged();
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Auto-Calculate Exam Eligibility in Real-Time'),
                subtitle: const Text('Generates live eligibility flags on student portal and staff grade reports'),
                value: _autoEligibility,
                activeThumbColor: AdminColors.primary,
                onChanged: (v) {
                  setState(() => _autoEligibility = v);
                  _notifyPolicyChanged();
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Academic Milestones Manager Card
        AdminCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 600;

                  final titleSection = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Institutional Academic Milestones', style: AdminTextStyles.titleMd(isDark)),
                      const SizedBox(height: 2),
                      Text(
                        'Configure internal assessment dates, model examinations, and university exam schedules',
                        style: AdminTextStyles.labelSm(isDark),
                      ),
                    ],
                  );

                  final addBtn = OutlinedButton.icon(
                    onPressed: () => _openMilestoneDialog(),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Add Milestone'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AdminColors.primary,
                      side: const BorderSide(color: AdminColors.primary),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  );

                  if (isNarrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        titleSection,
                        const SizedBox(height: 12),
                        addBtn,
                      ],
                    );
                  }

                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: titleSection),
                      const SizedBox(width: 12),
                      addBtn,
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),

              if (widget.milestones.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  alignment: Alignment.center,
                  child: Text('No academic milestones configured yet.', style: AdminTextStyles.bodySm(isDark)),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: widget.milestones.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final m = widget.milestones[i];
                    final String name = m['name'] ?? 'Milestone';
                    final String start = m['start'] ?? m['date'] ?? '';
                    final String end = m['end'] ?? '';
                    final String cat = m['category'] ?? 'Academic';

                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final isItemNarrow = constraints.maxWidth < 560;

                        if (isItemNarrow) {
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AdminColors.getCardTinted(isDark),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AdminColors.getBorder(isDark)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(7),
                                      decoration: BoxDecoration(
                                        color: AdminColors.primary.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(Icons.flag_rounded, color: AdminColors.primary, size: 18),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        name,
                                        style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13.5),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    AdminBadge(label: cat, color: AdminColors.primary),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Icon(Icons.date_range_rounded, size: 14, color: AdminColors.getTextSecondary(isDark)),
                                    const SizedBox(width: 5),
                                    Expanded(
                                      child: Text(
                                        end.isNotEmpty ? '$start  →  $end' : start,
                                        style: AdminTextStyles.bodySm(isDark),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.edit_rounded, size: 17),
                                      tooltip: 'Edit Milestone',
                                      padding: const EdgeInsets.all(6),
                                      constraints: const BoxConstraints(),
                                      onPressed: () => _openMilestoneDialog(initial: m, editIndex: i),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline_rounded, size: 17, color: AdminColors.danger),
                                      tooltip: 'Delete Milestone',
                                      padding: const EdgeInsets.all(6),
                                      constraints: const BoxConstraints(),
                                      onPressed: () => _deleteMilestone(i),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }

                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AdminColors.getCardTinted(isDark),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AdminColors.getBorder(isDark)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AdminColors.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.flag_rounded, color: AdminColors.primary, size: 20),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      end.isNotEmpty ? '$start  →  $end' : start,
                                      style: AdminTextStyles.bodySm(isDark),
                                    ),
                                  ],
                                ),
                              ),
                              AdminBadge(label: cat, color: AdminColors.primary),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.edit_rounded, size: 18),
                                tooltip: 'Edit Milestone',
                                onPressed: () => _openMilestoneDialog(initial: m, editIndex: i),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AdminColors.danger),
                                tooltip: 'Delete Milestone',
                                onPressed: () => _deleteMilestone(i),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}
