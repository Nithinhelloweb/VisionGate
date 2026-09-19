import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../../config/college_ip_config.dart';
import '../../theme/admin_theme.dart';
import 'period_timing_helper.dart';

class PeriodConfigDialog extends StatefulWidget {
  final String token;
  final String dept;
  final String? batch;
  final int? semester;
  final String? section;
  final VoidCallback onSaved;

  const PeriodConfigDialog({
    super.key,
    required this.token,
    required this.dept,
    this.batch,
    this.semester,
    this.section,
    required this.onSaved,
  });

  @override
  State<PeriodConfigDialog> createState() => _PeriodConfigDialogState();
}

class _PeriodConfigDialogState extends State<PeriodConfigDialog> {
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isResetting = false;

  String _startTime = '08:45';
  int _totalPeriods = 7;
  int _periodDurationMins = 50;
  List<String> _workingDays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];
  List<Map<String, dynamic>> _breaks = [];

  bool _isCustomizedForClass = false;
  String _configScope = 'default';
  String _saveScope = 'class'; // 'class', 'semester', 'dept'

  final List<String> _allWeekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    setState(() => _isLoading = true);
    try {
      final batch = widget.batch ?? 'all';
      final sem = widget.semester ?? 0;
      final sec = widget.section ?? 'all';
      final url = '${CollegeIPConfig.defaultURL}/api/v1/academics/period-config?dept=${Uri.encodeComponent(widget.dept)}&batch=${Uri.encodeComponent(batch)}&semester=$sem&section=${Uri.encodeComponent(sec)}';

      final res = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        _startTime = data['start_time'] ?? '08:45';
        _totalPeriods = (data['total_periods'] as num?)?.toInt() ?? 7;
        _periodDurationMins = (data['period_duration_mins'] as num?)?.toInt() ?? 50;
        _workingDays = List<String>.from(data['working_days'] ?? ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday']);
        _breaks = List<Map<String, dynamic>>.from(data['breaks'] ?? []);
        _isCustomizedForClass = data['is_customized_for_class'] == true;
        _configScope = data['config_scope'] ?? 'default';
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  void _addBreak() {
    setState(() {
      _breaks.add({
        'title': 'Break ${_breaks.length + 1}',
        'after_period': 2,
        'duration_mins': 15,
      });
    });
  }

  void _removeBreak(int index) {
    setState(() {
      _breaks.removeAt(index);
    });
  }

  Future<void> _saveConfig() async {
    setState(() => _isSaving = true);
    try {
      final res = await http.post(
        Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/academics/period-config/save'),
        headers: {'Authorization': 'Bearer ${widget.token}', 'Content-Type': 'application/json'},
        body: jsonEncode({
          'dept': widget.dept,
          'batch': widget.batch ?? 'all',
          'semester': widget.semester ?? 0,
          'section': widget.section ?? 'all',
          'scope': _saveScope,
          'semester_type': 'all',
          'start_time': _startTime,
          'total_periods': _totalPeriods,
          'period_duration_mins': _periodDurationMins,
          'working_days': _workingDays,
          'breaks': _breaks,
        }),
      );
      if (res.statusCode == 200 && mounted) {
        final scopeLabel = _saveScope == 'class'
            ? '${widget.dept} Sem ${widget.semester ?? 1} Sec ${widget.section ?? 'A'}'
            : (_saveScope == 'semester' ? '${widget.dept} Sem ${widget.semester ?? 1} (All Sections)' : '${widget.dept} Department Template');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Timetable period & break timings saved for $scopeLabel!'), backgroundColor: AdminColors.success),
        );
        widget.onSaved();
        Navigator.pop(context);
      } else if (mounted) {
        final err = jsonDecode(res.body)['detail'] ?? 'Failed to save configuration';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err.toString()), backgroundColor: AdminColors.danger));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving: $e'), backgroundColor: AdminColors.danger));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _resetConfig() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Revert to Department Template?', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        content: Text(
          'This will delete the customized periods & break timings specifically configured for ${widget.dept} Batch ${widget.batch ?? ''} Sem ${widget.semester ?? 1} Sec ${widget.section ?? 'A'}, and revert to the department defaults.',
          style: GoogleFonts.inter(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AdminColors.danger, foregroundColor: Colors.white),
            child: const Text('Revert to Default'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isResetting = true);
    try {
      final res = await http.post(
        Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/academics/period-config/reset'),
        headers: {'Authorization': 'Bearer ${widget.token}', 'Content-Type': 'application/json'},
        body: jsonEncode({
          'dept': widget.dept,
          'batch': widget.batch ?? 'all',
          'semester': widget.semester ?? 0,
          'section': widget.section ?? 'all',
          'semester_type': 'all',
        }),
      );
      if (res.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reverted to department default timings!'), backgroundColor: AdminColors.success),
        );
        await _loadConfig();
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error resetting: $e'), backgroundColor: AdminColors.danger));
    } finally {
      if (mounted) setState(() => _isResetting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final timeline = PeriodTimingHelper.computeTimeline(
      startTime: _startTime,
      totalPeriods: _totalPeriods,
      periodDurationMins: _periodDurationMins,
      breaks: _breaks,
    );

    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 740;

    return Dialog(
      backgroundColor: AdminColors.getCard(isDark),
      insetPadding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: isMobile ? double.infinity : 720,
        padding: EdgeInsets.all(isMobile ? 16 : 24),
        child: _isLoading
            ? const Center(heightFactor: 5, child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: AdminColors.primarySoft, borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Icons.schedule_rounded, color: AdminColors.primary, size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Customize Periods & Break Structure',
                                style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: AdminColors.getTextPrimary(isDark)),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${widget.dept} • Batch ${widget.batch ?? '2022-2026'} • Sem ${widget.semester ?? 1} Sec ${widget.section ?? 'A'}',
                                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AdminColors.getTextSecondary(isDark)),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded, size: 20),
                          tooltip: 'Close',
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Inheritance & Custom Status Banner
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: _isCustomizedForClass
                            ? AdminColors.successSoft
                            : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _isCustomizedForClass ? AdminColors.success : AdminColors.getBorder(isDark),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _isCustomizedForClass ? Icons.verified_rounded : Icons.info_outline_rounded,
                            size: 18,
                            color: _isCustomizedForClass ? AdminColors.success : AdminColors.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _isCustomizedForClass
                                      ? 'Class-Specific Schedule Active'
                                      : 'Inherited from ${_configScope == "semester" ? "Semester Template" : (_configScope == "batch" ? "Batch Template" : "Department Default (${widget.dept})")}',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: _isCustomizedForClass ? AdminColors.success : AdminColors.getTextPrimary(isDark),
                                  ),
                                ),
                                Text(
                                  _isCustomizedForClass
                                      ? 'This class runs on its own customized period count and break timings.'
                                      : 'Saving changes below will apply specifically to this class or chosen scope.',
                                  style: GoogleFonts.inter(fontSize: 11, color: AdminColors.getTextSecondary(isDark)),
                                ),
                              ],
                            ),
                          ),
                          if (_isCustomizedForClass) ...[
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: _isResetting ? null : _resetConfig,
                              icon: _isResetting
                                  ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.refresh_rounded, size: 14),
                              label: const Text('Revert'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AdminColors.danger,
                                side: const BorderSide(color: AdminColors.danger),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                textStyle: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Target Application Scope Selector
                    Text('Target Application Scope', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AdminColors.getTextPrimary(isDark))),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildScopeChip(
                          scopeKey: 'class',
                          label: '🎯 This Class (${widget.dept} Sem ${widget.semester ?? 1} Sec ${widget.section ?? 'A'})',
                          subtitle: 'Custom separate schedule for this class only',
                          isDark: isDark,
                        ),
                        if (widget.semester != null)
                          _buildScopeChip(
                            scopeKey: 'semester',
                            label: '👥 All Sections in Sem ${widget.semester}',
                            subtitle: 'Apply to all sections in this semester',
                            isDark: isDark,
                          ),
                        _buildScopeChip(
                          scopeKey: 'dept',
                          label: '🏢 Department Template (${widget.dept})',
                          subtitle: 'Update fallback template for entire department',
                          isDark: isDark,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Timings Parameters
                    if (isMobile) ...[
                      _buildParamDropdown(
                        isDark,
                        label: 'Day Start Time',
                        value: _startTime,
                        options: ['08:00', '08:30', '08:45', '09:00', '09:15', '09:30'],
                        onChanged: (v) => setState(() => _startTime = v ?? '08:45'),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildParamDropdown(
                              isDark,
                              label: 'Period Duration',
                              value: '$_periodDurationMins mins',
                              options: ['40 mins', '45 mins', '50 mins', '55 mins', '60 mins'],
                              onChanged: (v) {
                                final n = int.tryParse(v?.replaceAll(' mins', '') ?? '50') ?? 50;
                                setState(() => _periodDurationMins = n);
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildParamDropdown(
                              isDark,
                              label: 'Total Periods / Day',
                              value: '$_totalPeriods Periods',
                              options: ['5 Periods', '6 Periods', '7 Periods', '8 Periods', '9 Periods'],
                              onChanged: (v) {
                                final n = int.tryParse(v?.replaceAll(' Periods', '') ?? '7') ?? 7;
                                setState(() => _totalPeriods = n);
                              },
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      Row(
                        children: [
                          Expanded(
                            child: _buildParamDropdown(
                              isDark,
                              label: 'Day Start Time',
                              value: _startTime,
                              options: ['08:00', '08:30', '08:45', '09:00', '09:15', '09:30'],
                              onChanged: (v) => setState(() => _startTime = v ?? '08:45'),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildParamDropdown(
                              isDark,
                              label: 'Period Duration',
                              value: '$_periodDurationMins mins',
                              options: ['40 mins', '45 mins', '50 mins', '55 mins', '60 mins'],
                              onChanged: (v) {
                                final n = int.tryParse(v?.replaceAll(' mins', '') ?? '50') ?? 50;
                                setState(() => _periodDurationMins = n);
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildParamDropdown(
                              isDark,
                              label: 'Total Periods / Day',
                              value: '$_totalPeriods Periods',
                              options: ['5 Periods', '6 Periods', '7 Periods', '8 Periods', '9 Periods'],
                              onChanged: (v) {
                                final n = int.tryParse(v?.replaceAll(' Periods', '') ?? '7') ?? 7;
                                setState(() => _totalPeriods = n);
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 18),

                    // Working Days Chips
                    Text('Active Working Days', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AdminColors.getTextPrimary(isDark))),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _allWeekdays.map((day) {
                        final isSel = _workingDays.contains(day);
                        return FilterChip(
                          label: Text(day),
                          selected: isSel,
                          selectedColor: AdminColors.primarySoft,
                          checkmarkColor: AdminColors.primary,
                          labelStyle: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                            color: isSel ? AdminColors.primary : AdminColors.getTextPrimary(isDark),
                          ),
                          onSelected: (val) {
                            setState(() {
                              if (val) {
                                _workingDays.add(day);
                              } else if (_workingDays.length > 1) {
                                _workingDays.remove(day);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),

                    // Breaks Management
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Break Intervals & Recesses', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AdminColors.getTextPrimary(isDark))),
                            Text('${_breaks.length} break intervals configured', style: GoogleFonts.inter(fontSize: 11, color: AdminColors.getTextSecondary(isDark))),
                          ],
                        ),
                        TextButton.icon(
                          onPressed: _addBreak,
                          icon: const Icon(Icons.add_rounded, size: 16),
                          label: const Text('Add Break'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ..._breaks.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final b = entry.value;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AdminColors.getBorder(isDark)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextFormField(
                                initialValue: b['title']?.toString() ?? 'Break',
                                decoration: const InputDecoration(labelText: 'Break Title', isDense: true, border: InputBorder.none),
                                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
                                onChanged: (v) => b['title'] = v,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<int>(
                                  isExpanded: true,
                                  value: (b['after_period'] as num?)?.toInt() ?? 2,
                                  items: List.generate(_totalPeriods, (i) => i + 1).map((p) {
                                    return DropdownMenuItem<int>(value: p, child: Text('After P$p', style: GoogleFonts.inter(fontSize: 12)));
                                  }).toList(),
                                  onChanged: (v) => setState(() => b['after_period'] = v ?? 2),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<int>(
                                  isExpanded: true,
                                  value: (b['duration_mins'] as num?)?.toInt() ?? 15,
                                  items: [10, 15, 20, 25, 30, 40, 45, 50, 60].map((d) {
                                    return DropdownMenuItem<int>(value: d, child: Text('$d mins', style: GoogleFonts.inter(fontSize: 12)));
                                  }).toList(),
                                  onChanged: (v) => setState(() => b['duration_mins'] = v ?? 15),
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => _removeBreak(idx),
                              icon: const Icon(Icons.close_rounded, size: 18, color: AdminColors.danger),
                              tooltip: 'Remove Break',
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 16),

                    // Live Schedule Preview
                    Text('Live Schedule Preview (${timeline.length} Slots)', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AdminColors.getTextPrimary(isDark))),
                    const SizedBox(height: 8),
                    Container(
                      height: 56,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        itemCount: timeline.length,
                        separatorBuilder: (_, index) => const SizedBox(width: 6),
                        itemBuilder: (ctx, i) {
                          final slot = timeline[i];
                          final isBrk = slot.isBreak;
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isBrk ? Colors.amber[100] : (isDark ? const Color(0xFF1E293B) : Colors.white),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: isBrk ? Colors.amber[700]! : AdminColors.getBorder(isDark)),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(slot.label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: isBrk ? Colors.amber[900] : AdminColors.primary)),
                                Text('${slot.startTime} - ${slot.endTime}', style: GoogleFonts.inter(fontSize: 9, color: Colors.blueGrey)),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Action Buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text('Cancel', style: GoogleFonts.inter(color: AdminColors.getTextSecondary(isDark))),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: _isSaving ? null : _saveConfig,
                          icon: _isSaving
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.check_rounded, size: 18),
                          label: Text(_saveScope == 'class' ? 'Save for This Class' : 'Save Timetable Timings'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AdminColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildScopeChip({
    required String scopeKey,
    required String label,
    required String subtitle,
    required bool isDark,
  }) {
    final isSelected = _saveScope == scopeKey;
    return InkWell(
      onTap: () => setState(() => _saveScope = scopeKey),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AdminColors.primarySoft
              : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC)),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AdminColors.primary : AdminColors.getBorder(isDark),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  size: 14,
                  color: isSelected ? AdminColors.primary : AdminColors.getTextSecondary(isDark),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                    color: isSelected ? AdminColors.primary : AdminColors.getTextPrimary(isDark),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.only(left: 20),
              child: Text(
                subtitle,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  color: AdminColors.getTextSecondary(isDark),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildParamDropdown(
    bool isDark, {
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AdminColors.getTextSecondary(isDark))),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AdminColors.getBorder(isDark)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: options.contains(value) ? value : options.first,
              items: options.map((opt) => DropdownMenuItem(value: opt, child: Text(opt, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)))).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}
