import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/date_timetable_service.dart';
import '../../theme/admin_theme.dart';

/// Modal dialog for Admins and HODs to map calendar dates to timetable days,
/// assign Day Orders (1..6), or declare College/Dept Holidays.
class AcademicCalendarOverrideDialog extends StatefulWidget {
  final String token;
  final DateTime initialDate;
  final VoidCallback onSaved;

  const AcademicCalendarOverrideDialog({
    super.key,
    required this.token,
    required this.initialDate,
    required this.onSaved,
  });

  @override
  State<AcademicCalendarOverrideDialog> createState() =>
      _AcademicCalendarOverrideDialogState();
}

class _AcademicCalendarOverrideDialogState
    extends State<AcademicCalendarOverrideDialog> {
  late DateTime _selectedDate;
  String _dayType = 'WORKING_DAY';
  String _mappedDay = 'Monday';
  int? _dayOrder;
  final _titleCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();

  bool _loading = false;
  bool _deleting = false;
  String? _error;
  bool _existingOverride = false;

  final List<String> _daysOfWeek = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
  ];

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
    _mappedDay = DateFormat('EEEE').format(_selectedDate);
    if (!_daysOfWeek.contains(_mappedDay)) _mappedDay = 'Monday';
    _fetchExisting();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchExisting() async {
    setState(() => _loading = true);
    final fmt = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final res = await DateTimetableService.getDateOverrides(
      token: widget.token,
      startDate: fmt,
      endDate: fmt,
    );
    if (!mounted) return;

    final overrides = (res['overrides'] as List? ?? []);
    if (overrides.isNotEmpty) {
      final o = overrides.first as Map<String, dynamic>;
      setState(() {
        _existingOverride = true;
        _dayType = (o['day_type'] as String? ?? 'WORKING_DAY').toUpperCase();
        _mappedDay = o['mapped_day_of_week'] as String? ?? _mappedDay;
        _dayOrder = (o['day_order'] as num?)?.toInt();
        _titleCtrl.text = o['title'] as String? ?? '';
        _reasonCtrl.text = o['reason'] as String? ?? '';
      });
    } else {
      setState(() {
        _existingOverride = false;
        _dayType = 'WORKING_DAY';
        _mappedDay = DateFormat('EEEE').format(_selectedDate);
        if (!_daysOfWeek.contains(_mappedDay)) _mappedDay = 'Monday';
        _dayOrder = null;
        _titleCtrl.clear();
        _reasonCtrl.clear();
      });
    }
    setState(() => _loading = false);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 90)),
      lastDate: DateTime.now().add(const Duration(days: 180)),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _fetchExisting();
    }
  }

  Future<void> _save() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final fmt = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final res = await DateTimetableService.saveDateOverride(
      token: widget.token,
      overrideDate: fmt,
      dayType: _dayType,
      mappedDayOfWeek: _mappedDay,
      dayOrder: _dayOrder,
      title: _titleCtrl.text.trim().isNotEmpty ? _titleCtrl.text.trim() : null,
      reason: _reasonCtrl.text.trim().isNotEmpty ? _reasonCtrl.text.trim() : null,
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (res['success'] == true) {
      widget.onSaved();
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res['message'] ?? 'Date override saved.'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
    } else {
      setState(() => _error = res['message'] ?? 'Failed to save override.');
    }
  }

  Future<void> _delete() async {
    setState(() {
      _deleting = true;
      _error = null;
    });

    final fmt = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final res = await DateTimetableService.deleteDateOverride(
      token: widget.token,
      overrideDate: fmt,
    );

    if (!mounted) return;
    setState(() => _deleting = false);

    if (res['success'] == true) {
      widget.onSaved();
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res['message'] ?? 'Override removed.'),
          backgroundColor: Colors.blueGrey,
        ),
      );
    } else {
      setState(() => _error = res['message'] ?? 'Failed to remove override.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dateStr = DateFormat('EEEE, d MMMM yyyy').format(_selectedDate);

    final isMobile = MediaQuery.of(context).size.width < 580;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      insetPadding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 24, vertical: 24),
      child: Container(
        width: isMobile ? double.infinity : 520,
        padding: EdgeInsets.all(isMobile ? 16 : 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AdminColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.event_note_rounded,
                      color: AdminColors.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Academic Date Schedule Mapping',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : AdminColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Configure timetable day or holiday status for a specific date.',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white60 : AdminColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Date Selector
              Text(
                'Target Calendar Date',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : AdminColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: isDark ? Colors.white24 : Colors.grey.shade300,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    color: isDark ? const Color(0xFF0F172A) : Colors.grey.shade50,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month_rounded,
                          size: 18, color: AdminColors.primary),
                      const SizedBox(width: 10),
                      Text(
                        dateStr,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      const Spacer(),
                      const Text(
                        'Change',
                        style: TextStyle(
                          fontSize: 12,
                          color: AdminColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Day Type Selector
              Text(
                'Date Classification',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : AdminColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  _buildTypeChip('WORKING_DAY', 'Working Day', Icons.school_rounded),
                  _buildTypeChip('HOLIDAY', 'Holiday / Off', Icons.beach_access_rounded),
                  _buildTypeChip('EXAM_DAY', 'Exam Day', Icons.quiz_rounded),
                  _buildTypeChip('EVENT_DAY', 'College Event', Icons.celebration_rounded),
                ],
              ),

              if (_dayType != 'HOLIDAY') ...[
                const SizedBox(height: 16),

                // Mapped Timetable Day
                Text(
                  'Follow Timetable Of (Day Schedule)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : AdminColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: _mappedDay,
                  decoration: InputDecoration(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  items: _daysOfWeek
                      .map((d) => DropdownMenuItem(value: d, child: Text('$d Timetable')))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _mappedDay = v);
                  },
                ),

                const SizedBox(height: 16),

                // Day Order (Optional)
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Day Order (Optional)',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white70 : AdminColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<int?>(
                            initialValue: _dayOrder,
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            items: [
                              const DropdownMenuItem(value: null, child: Text('No Day Order')),
                              ...List.generate(6, (i) => i + 1).map(
                                (n) => DropdownMenuItem(value: n, child: Text('Day Order $n')),
                              ),
                            ],
                            onChanged: (v) => setState(() => _dayOrder = v),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 16),

              // Title / Description
              Text(
                'Schedule Title / Notice',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : AdminColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _titleCtrl,
                decoration: InputDecoration(
                  hintText: _dayType == 'HOLIDAY'
                      ? 'e.g. Gandhi Jayanti / Deepavali Holiday'
                      : 'e.g. Compensatory Working Day (Monday Schedule)',
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // Reason
              Text(
                'Administrative Remarks / Reason',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : AdminColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _reasonCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'Optional internal reason or circular reference',
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Action Buttons
              Row(
                children: [
                  if (_existingOverride)
                    TextButton.icon(
                      onPressed: _deleting ? null : _delete,
                      icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                      label: Text(
                        _deleting ? 'Removing...' : 'Reset Default',
                        style: const TextStyle(color: Colors.red, fontSize: 13),
                      ),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AdminColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: _loading ? null : _save,
                    child: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Save Schedule Mapping'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypeChip(String typeKey, String label, IconData icon) {
    final isSelected = _dayType == typeKey;
    return ChoiceChip(
      selected: isSelected,
      avatar: Icon(icon, size: 16, color: isSelected ? Colors.white : AdminColors.textPrimary),
      label: Text(label),
      selectedColor: typeKey == 'HOLIDAY' ? Colors.red.shade600 : AdminColors.primary,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : AdminColors.textPrimary,
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
      onSelected: (sel) {
        if (sel) setState(() => _dayType = typeKey);
      },
    );
  }
}
