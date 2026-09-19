import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/admin_theme.dart';
import '../../widgets/admin_design_system.dart';

class StudentAcademicRangesCard extends StatefulWidget {
  final List<Map<String, dynamic>> ranges;
  final String activeAcademicYear;
  final ValueChanged<String> onAcademicYearChanged;
  final ValueChanged<List<Map<String, dynamic>>> onRangesChanged;
  final VoidCallback onSave;
  final bool isSaving;

  const StudentAcademicRangesCard({
    super.key,
    required this.ranges,
    required this.activeAcademicYear,
    required this.onAcademicYearChanged,
    required this.onRangesChanged,
    required this.onSave,
    this.isSaving = false,
  });

  @override
  State<StudentAcademicRangesCard> createState() => _StudentAcademicRangesCardState();
}

class _StudentAcademicRangesCardState extends State<StudentAcademicRangesCard> {
  late TextEditingController _yearCtrl;

  @override
  void initState() {
    super.initState();
    _yearCtrl = TextEditingController(text: widget.activeAcademicYear);
  }

  @override
  void didUpdateWidget(covariant StudentAcademicRangesCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeAcademicYear != widget.activeAcademicYear) {
      _yearCtrl.text = widget.activeAcademicYear;
    }
  }

  @override
  void dispose() {
    _yearCtrl.dispose();
    super.dispose();
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return 'Not Set';
    return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  int _calculateDays(String? start, String? end) {
    if (start == null || end == null || start.isEmpty || end.isEmpty) return 0;
    try {
      final s = DateTime.parse(start);
      final e = DateTime.parse(end);
      return e.difference(s).inDays + 1;
    } catch (_) {
      return 0;
    }
  }

  int _estimateSundays(String? start, String? end) {
    if (start == null || end == null || start.isEmpty || end.isEmpty) return 0;
    try {
      final s = DateTime.parse(start);
      final e = DateTime.parse(end);
      int count = 0;
      var curr = s;
      while (!curr.isAfter(e)) {
        if (curr.weekday == DateTime.sunday) count++;
        curr = curr.add(const Duration(days: 1));
      }
      return count;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _openRangeDialog({Map<String, dynamic>? initialRange, int? editIndex}) async {
    final nameCtrl = TextEditingController(text: initialRange?['name'] ?? 'Odd Semester');
    String semesterType = initialRange?['semester_type'] ?? 'odd';
    DateTime? startDate = initialRange?['start'] != null ? DateTime.tryParse(initialRange!['start']) : DateTime.now();
    DateTime? endDate = initialRange?['end'] != null ? DateTime.tryParse(initialRange!['end']) : DateTime.now().add(const Duration(days: 150));
    final targetDaysCtrl = TextEditingController(text: (initialRange?['target_working_days'] ?? 90).toString());
    bool isActive = initialRange?['is_active'] ?? true;
    final Set<int> selectedYears = Set<int>.from(initialRange?['applicable_years'] ?? [1, 2, 3, 4]);

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          final totalDays = (startDate != null && endDate != null && !startDate!.isAfter(endDate!))
              ? endDate!.difference(startDate!).inDays + 1
              : 0;

          return AlertDialog(
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
                  child: const Icon(Icons.date_range_rounded, color: AdminColors.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  editIndex != null ? 'Edit Academic Range' : 'Add Academic Range',
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 18),
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
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Range / Term Name',
                        hintText: 'e.g. Odd Semester (Sem 1, 3, 5, 7)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.label_outline_rounded),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: semesterType,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Semester Type',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'odd', child: Text('Odd Semester (I, III, V, VII)', overflow: TextOverflow.ellipsis)),
                              DropdownMenuItem(value: 'even', child: Text('Even Semester (II, IV, VI, VIII)', overflow: TextOverflow.ellipsis)),
                              DropdownMenuItem(value: 'summer', child: Text('Summer Term / Fast Track', overflow: TextOverflow.ellipsis)),
                            ],
                            onChanged: (v) {
                              if (v != null) setDlgState(() => semesterType = v);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: targetDaysCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Target Working Days',
                              hintText: '90',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.check_circle_outline_rounded),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Date pickers row
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
                              if (picked != null) {
                                setDlgState(() => startDate = picked);
                              }
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Start Date',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.calendar_today_rounded),
                              ),
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
                              if (picked != null) {
                                setDlgState(() => endDate = picked);
                              }
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'End Date',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.event_rounded),
                              ),
                              child: Text(_formatDate(endDate)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Duration Summary Pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AdminColors.primarySoft,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, size: 16, color: AdminColors.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Duration: $totalDays calendar days (~${totalDays - (totalDays ~/ 7)} potential instructional days)',
                            style: const TextStyle(fontSize: 12, color: AdminColors.primary, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Applicable Years of Study:',
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [1, 2, 3, 4].map((y) {
                        final isSel = selectedYears.contains(y);
                        return FilterChip(
                          selected: isSel,
                          label: Text('Year $y'),
                          selectedColor: AdminColors.primary.withValues(alpha: 0.2),
                          checkmarkColor: AdminColors.primary,
                          onSelected: (selected) {
                            setDlgState(() {
                              if (selected) {
                                selectedYears.add(y);
                              } else if (selectedYears.length > 1) {
                                selectedYears.remove(y);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Mark as Currently Active Range'),
                      value: isActive,
                      activeThumbColor: AdminColors.primary,
                      onChanged: (v) => setDlgState(() => isActive = v),
                    ),
                  ],
                ),
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
                  if (startDate == null || endDate == null) return;
                  if (startDate!.isAfter(endDate!)) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Start date cannot be after end date!')),
                    );
                    return;
                  }
                  Navigator.pop(ctx, {
                    'id': initialRange?['id'] ?? 'range_${DateTime.now().millisecondsSinceEpoch}',
                    'name': nameCtrl.text.trim(),
                    'semester_type': semesterType,
                    'start': _formatDate(startDate),
                    'end': _formatDate(endDate),
                    'target_working_days': int.tryParse(targetDaysCtrl.text.trim()) ?? 90,
                    'applicable_years': selectedYears.toList()..sort(),
                    'is_active': isActive,
                  });
                },
                child: const Text('Save Range'),
              ),
            ],
          );
        },
      ),
    );

    if (result != null) {
      final updated = List<Map<String, dynamic>>.from(widget.ranges);
      if (editIndex != null && editIndex < updated.length) {
        updated[editIndex] = result;
      } else {
        updated.add(result);
      }
      widget.onRangesChanged(updated);
    }
  }

  void _deleteRange(int index) {
    if (widget.ranges.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('At least one academic range is required.')),
      );
      return;
    }
    final updated = List<Map<String, dynamic>>.from(widget.ranges);
    updated.removeAt(index);
    widget.onRangesChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Active Academic Year Global Control
        AdminCard(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 650;

              final titleInfo = Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AdminColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.school_rounded, color: AdminColors.primary, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Institutional Academic Year', style: AdminTextStyles.titleMd(isDark)),
                        const SizedBox(height: 2),
                        Text(
                          'Global academic session identifier applied across student records',
                          style: AdminTextStyles.labelSm(isDark),
                        ),
                      ],
                    ),
                  ),
                ],
              );

              final yearField = SizedBox(
                width: isNarrow ? double.infinity : 180,
                child: TextField(
                  controller: _yearCtrl,
                  onChanged: widget.onAcademicYearChanged,
                  decoration: const InputDecoration(
                    hintText: '2025-2026',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    prefixIcon: Icon(Icons.calendar_month_rounded, size: 18),
                  ),
                ),
              );

              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    titleInfo,
                    const SizedBox(height: 14),
                    yearField,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: titleInfo),
                  const SizedBox(width: 14),
                  yearField,
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 20),

        // Academic Ranges Table & List
        AdminCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 650;

                  final titleSection = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Semester Term Ranges', style: AdminTextStyles.titleMd(isDark)),
                      const SizedBox(height: 2),
                      Text(
                        'Define semester durations, target instructional working days, and applicable years of study',
                        style: AdminTextStyles.labelSm(isDark),
                      ),
                    ],
                  );

                  final buttonsWrap = Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _openRangeDialog(),
                        icon: const Icon(Icons.add_rounded, size: 16),
                        label: const Text('Add Range'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AdminColors.primary,
                          side: const BorderSide(color: AdminColors.primary),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: widget.isSaving ? null : widget.onSave,
                        icon: widget.isSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.save_rounded, size: 16),
                        label: const Text('Save Changes'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AdminColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        ),
                      ),
                    ],
                  );

                  if (isNarrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        titleSection,
                        const SizedBox(height: 12),
                        buttonsWrap,
                      ],
                    );
                  }

                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: titleSection),
                      const SizedBox(width: 12),
                      buttonsWrap,
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              if (widget.ranges.isEmpty)
                Container(
                  padding: const EdgeInsets.all(32),
                  alignment: Alignment.center,
                  child: Column(
                    children: [
                      Icon(Icons.date_range_outlined, size: 48, color: AdminColors.getTextMuted(isDark)),
                      const SizedBox(height: 10),
                      Text('No academic ranges configured', style: AdminTextStyles.bodySm(isDark)),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: () => _openRangeDialog(),
                        icon: const Icon(Icons.add_rounded, size: 16),
                        label: const Text('Create First Range'),
                      ),
                    ],
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: widget.ranges.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final r = widget.ranges[index];
                    final String name = r['name'] ?? 'Semester Range';
                    final String semType = r['semester_type'] ?? 'odd';
                    final String start = r['start'] ?? '';
                    final String end = r['end'] ?? '';
                    final int targetDays = r['target_working_days'] ?? 90;
                    final bool isActive = r['is_active'] ?? true;
                    final List years = r['applicable_years'] ?? [1, 2, 3, 4];
                    final int totalDays = _calculateDays(start, end);
                    final int sundays = _estimateSundays(start, end);

                    final Color typeColor = semType == 'odd'
                        ? const Color(0xFF4F46E5)
                        : (semType == 'even' ? const Color(0xFF059669) : const Color(0xFFD97706));

                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final isNarrow = constraints.maxWidth < 600;

                        final rangeDetails = Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: typeColor.withValues(alpha: isDark ? 0.2 : 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                semType == 'odd' ? Icons.looks_one_rounded : Icons.looks_two_rounded,
                                color: typeColor,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        name,
                                        style: GoogleFonts.inter(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: AdminColors.getTextPrimary(isDark),
                                        ),
                                      ),
                                      if (isActive)
                                        const AdminBadge(label: 'CURRENT TERM', color: AdminColors.success)
                                      else
                                        const AdminBadge(label: 'UPCOMING', color: Colors.grey),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 14,
                                    runSpacing: 6,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.date_range_rounded, size: 14, color: Colors.grey),
                                          const SizedBox(width: 4),
                                          Text(
                                            '$start  →  $end',
                                            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500),
                                          ),
                                        ],
                                      ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.timelapse_rounded, size: 14, color: Colors.grey),
                                          const SizedBox(width: 4),
                                          Text(
                                            '$totalDays Calendar Days ($sundays Sundays)',
                                            style: GoogleFonts.inter(fontSize: 12, color: AdminColors.getTextSecondary(isDark)),
                                          ),
                                        ],
                                      ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.flag_circle_rounded, size: 14, color: Colors.grey),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Target: $targetDays Working Days',
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: typeColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.group_outlined, size: 14, color: Colors.grey),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Years: ${years.map((y) => 'Yr $y').join(', ')}',
                                            style: GoogleFonts.inter(fontSize: 12, color: AdminColors.getTextSecondary(isDark)),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );

                        final actionButtons = Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_rounded, size: 20),
                              tooltip: 'Edit Range',
                              onPressed: () => _openRangeDialog(initialRange: r, editIndex: index),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AdminColors.danger),
                              tooltip: 'Delete Range',
                              onPressed: () => _deleteRange(index),
                            ),
                          ],
                        );

                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AdminColors.getCardTinted(isDark),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isActive ? AdminColors.primary.withValues(alpha: 0.5) : AdminColors.getBorder(isDark),
                              width: isActive ? 1.5 : 1.0,
                            ),
                          ),
                          child: isNarrow
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    rangeDetails,
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: actionButtons,
                                    ),
                                  ],
                                )
                              : Row(
                                  children: [
                                    Expanded(child: rangeDetails),
                                    const SizedBox(width: 8),
                                    actionButtons,
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
