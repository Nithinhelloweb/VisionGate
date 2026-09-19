import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../../config/college_ip_config.dart';
import '../../theme/admin_theme.dart';

class DayManagementDialog extends StatefulWidget {
  final String token;
  final String dept;
  final String batch;
  final int semester;
  final String section;
  final List<String> currentWorkingDays;
  final VoidCallback onUpdated;

  const DayManagementDialog({
    super.key,
    required this.token,
    required this.dept,
    required this.batch,
    required this.semester,
    required this.section,
    required this.currentWorkingDays,
    required this.onUpdated,
  });

  @override
  State<DayManagementDialog> createState() => _DayManagementDialogState();
}

class _DayManagementDialogState extends State<DayManagementDialog> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  bool _isLoading = false;
  String? _statusMessage;
  bool _isSuccess = true;

  // Tab 1: Working Days Config
  late List<String> _selectedDays;
  bool _isDayOrderMode = false;

  final List<String> _standardWeekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday'
  ];

  final List<String> _standardDayOrders = [
    'Day 1',
    'Day 2',
    'Day 3',
    'Day 4',
    'Day 5',
    'Day 6'
  ];

  // Tab 2: Day Operations
  String? _srcDay;
  String? _dstDay;
  String? _swapDayA;
  String? _swapDayB;
  String? _clearDay;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _selectedDays = List<String>.from(widget.currentWorkingDays);
    _isDayOrderMode = _selectedDays.any((d) => d.toLowerCase().startsWith('day'));

    if (_selectedDays.isNotEmpty) {
      _srcDay = _selectedDays.first;
      _dstDay = _selectedDays.length > 1 ? _selectedDays[1] : _selectedDays.first;
      _swapDayA = _selectedDays.first;
      _swapDayB = _selectedDays.length > 1 ? _selectedDays[1] : _selectedDays.first;
      _clearDay = _selectedDays.first;
    }
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  void _presetMonFri() {
    setState(() {
      _isDayOrderMode = false;
      _selectedDays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];
      _resetOperationDropdowns();
    });
  }

  void _presetMonSat() {
    setState(() {
      _isDayOrderMode = false;
      _selectedDays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
      _resetOperationDropdowns();
    });
  }

  void _presetDayOrders(int count) {
    setState(() {
      _isDayOrderMode = true;
      _selectedDays = List.generate(count, (i) => 'Day ${i + 1}');
      _resetOperationDropdowns();
    });
  }

  void _resetOperationDropdowns() {
    if (_selectedDays.isNotEmpty) {
      _srcDay = _selectedDays.first;
      _dstDay = _selectedDays.length > 1 ? _selectedDays[1] : _selectedDays.first;
      _swapDayA = _selectedDays.first;
      _swapDayB = _selectedDays.length > 1 ? _selectedDays[1] : _selectedDays.first;
      _clearDay = _selectedDays.first;
    }
  }

  Future<void> _saveWorkingDays() async {
    if (_selectedDays.isEmpty) {
      setState(() {
        _statusMessage = 'Please select at least one active working day.';
        _isSuccess = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    try {
      // 1. Fetch current config first to preserve timings & breaks
      final getRes = await http.get(
        Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/academics/period-config?dept=${Uri.encodeComponent(widget.dept)}&batch=${Uri.encodeComponent(widget.batch)}&semester=${widget.semester}&section=${Uri.encodeComponent(widget.section)}'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      Map<String, dynamic> existing = {};
      if (getRes.statusCode == 200) {
        existing = jsonDecode(getRes.body);
      }

      final postRes = await http.post(
        Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/academics/period-config/save'),
        headers: {'Authorization': 'Bearer ${widget.token}', 'Content-Type': 'application/json'},
        body: jsonEncode({
          'dept': widget.dept,
          'batch': widget.batch,
          'semester': widget.semester,
          'section': widget.section,
          'scope': 'class',
          'semester_type': 'all',
          'start_time': existing['start_time'] ?? '08:45',
          'total_periods': existing['total_periods'] ?? 7,
          'period_duration_mins': existing['period_duration_mins'] ?? 50,
          'working_days': _selectedDays,
          'breaks': existing['breaks'] ?? [],
        }),
      );

      if (postRes.statusCode == 200) {
        setState(() {
          _statusMessage = 'Working days schedule updated successfully!';
          _isSuccess = true;
        });
        widget.onUpdated();
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) Navigator.pop(context);
      } else {
        final err = jsonDecode(postRes.body)['detail'] ?? 'Failed to update working days';
        setState(() {
          _statusMessage = err.toString();
          _isSuccess = false;
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error: $e';
        _isSuccess = false;
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _copyDay() async {
    if (_srcDay == null || _dstDay == null || _srcDay == _dstDay) {
      setState(() {
        _statusMessage = 'Source and target days must be different.';
        _isSuccess = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    try {
      final res = await http.post(
        Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/academics/timetable/day/copy'),
        headers: {'Authorization': 'Bearer ${widget.token}', 'Content-Type': 'application/json'},
        body: jsonEncode({
          'dept': widget.dept,
          'batch': widget.batch,
          'semester': widget.semester,
          'section': widget.section,
          'src_day': _srcDay,
          'dst_day': _dstDay,
        }),
      );

      if (res.statusCode == 200) {
        setState(() {
          _statusMessage = 'Successfully copied schedule from $_srcDay to $_dstDay!';
          _isSuccess = true;
        });
        widget.onUpdated();
      } else {
        final err = jsonDecode(res.body)['detail'] ?? 'Failed to copy day';
        setState(() {
          _statusMessage = err.toString();
          _isSuccess = false;
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error: $e';
        _isSuccess = false;
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _swapDays() async {
    if (_swapDayA == null || _swapDayB == null || _swapDayA == _swapDayB) {
      setState(() {
        _statusMessage = 'Select two different days to swap.';
        _isSuccess = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    try {
      final res = await http.post(
        Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/academics/timetable/day/swap'),
        headers: {'Authorization': 'Bearer ${widget.token}', 'Content-Type': 'application/json'},
        body: jsonEncode({
          'dept': widget.dept,
          'batch': widget.batch,
          'semester': widget.semester,
          'section': widget.section,
          'day_a': _swapDayA,
          'day_b': _swapDayB,
        }),
      );

      if (res.statusCode == 200) {
        setState(() {
          _statusMessage = 'Successfully swapped schedules between $_swapDayA and $_swapDayB!';
          _isSuccess = true;
        });
        widget.onUpdated();
      } else {
        final err = jsonDecode(res.body)['detail'] ?? 'Failed to swap days';
        setState(() {
          _statusMessage = err.toString();
          _isSuccess = false;
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error: $e';
        _isSuccess = false;
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _clearSelectedDay() async {
    if (_clearDay == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Clear $_clearDay Schedule?'),
        content: Text('Are you sure you want to clear all period slots for $_clearDay in ${widget.dept} Sem ${widget.semester} Sec ${widget.section}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AdminColors.danger, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear Day'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    try {
      final res = await http.delete(
        Uri.parse(
          '${CollegeIPConfig.defaultURL}/api/v1/academics/timetable/day?dept=${Uri.encodeComponent(widget.dept)}&batch=${Uri.encodeComponent(widget.batch)}&semester=${widget.semester}&section=${Uri.encodeComponent(widget.section)}&day_of_week=${Uri.encodeComponent(_clearDay!)}',
        ),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );

      if (res.statusCode == 200) {
        setState(() {
          _statusMessage = 'Cleared all periods for $_clearDay.';
          _isSuccess = true;
        });
        widget.onUpdated();
      } else {
        final err = jsonDecode(res.body)['detail'] ?? 'Failed to clear day';
        setState(() {
          _statusMessage = err.toString();
          _isSuccess = false;
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error: $e';
        _isSuccess = false;
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMobile = MediaQuery.of(context).size.width < 640;

    return Dialog(
      backgroundColor: AdminColors.getCard(isDark),
      insetPadding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: isMobile ? double.infinity : 580,
        padding: EdgeInsets.all(isMobile ? 16 : 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: AdminColors.primarySoft, borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.date_range_rounded, color: AdminColors.primary, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Day Management & Scheduling Rules', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w800, color: AdminColors.getTextPrimary(isDark))),
                      Text('${widget.dept} • Batch ${widget.batch} • Sem ${widget.semester} Sec ${widget.section}', style: GoogleFonts.inter(fontSize: 12, color: AdminColors.getTextSecondary(isDark))),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Tab Bar
            Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: TabBar(
                controller: _tabCtrl,
                indicator: BoxDecoration(
                  color: AdminColors.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                labelColor: Colors.white,
                unselectedLabelColor: AdminColors.getTextSecondary(isDark),
                labelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
                unselectedLabelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500),
                tabs: const [
                  Tab(text: 'Working Days & Day Orders'),
                  Tab(text: 'Day Actions (Copy, Swap, Clear)'),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Tab Views
            SizedBox(
              height: 340,
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  _buildWorkingDaysTab(isDark),
                  _buildDayOperationsTab(isDark),
                ],
              ),
            ),

            if (_statusMessage != null)
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: _isSuccess ? Colors.green.withValues(alpha: 0.1) : AdminColors.dangerSoft,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _isSuccess ? Colors.green : AdminColors.danger),
                ),
                child: Row(
                  children: [
                    Icon(_isSuccess ? Icons.check_circle_rounded : Icons.error_rounded, size: 16, color: _isSuccess ? Colors.green : AdminColors.danger),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _statusMessage!,
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: _isSuccess ? Colors.green[800] : AdminColors.danger),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkingDaysTab(bool isDark) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('QUICK PRESETS', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: AdminColors.getTextMuted(isDark))),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                avatar: const Icon(Icons.view_week_rounded, size: 14),
                label: const Text('Mon – Fri (5 Days)'),
                onPressed: _presetMonFri,
              ),
              ActionChip(
                avatar: const Icon(Icons.calendar_view_week_rounded, size: 14),
                label: const Text('Mon – Sat (6 Days)'),
                onPressed: _presetMonSat,
              ),
              ActionChip(
                avatar: const Icon(Icons.format_list_numbered_rounded, size: 14),
                label: const Text('Day Order 1–5'),
                onPressed: () => _presetDayOrders(5),
              ),
              ActionChip(
                avatar: const Icon(Icons.format_list_numbered_rounded, size: 14),
                label: const Text('Day Order 1–6'),
                onPressed: () => _presetDayOrders(6),
              ),
            ],
          ),
          const SizedBox(height: 18),

          Text(_isDayOrderMode ? 'SELECT ACTIVE DAY ORDERS' : 'SELECT ACTIVE WORKING DAYS',
              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: AdminColors.getTextMuted(isDark))),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: (_isDayOrderMode ? _standardDayOrders : _standardWeekdays).map((day) {
              final isSel = _selectedDays.contains(day);
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
                      _selectedDays.add(day);
                    } else {
                      _selectedDays.remove(day);
                    }
                    _resetOperationDropdowns();
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          // Save Working Days Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _saveWorkingDays,
              icon: _isLoading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_rounded, size: 18),
              label: const Text('Save Working Days Configuration'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayOperationsTab(bool isDark) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Copy Day
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AdminColors.getBorder(isDark)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.copy_all_rounded, size: 16, color: AdminColors.primary),
                    const SizedBox(width: 6),
                    Text('Copy Day Schedule', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _srcDay,
                        isDense: true,
                        decoration: const InputDecoration(labelText: 'From', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                        items: _selectedDays.map((d) => DropdownMenuItem(value: d, child: Text(d, style: const TextStyle(fontSize: 12)))).toList(),
                        onChanged: (v) => setState(() => _srcDay = v),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(Icons.arrow_forward_rounded, size: 16),
                    ),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _dstDay,
                        isDense: true,
                        decoration: const InputDecoration(labelText: 'To', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                        items: _selectedDays.map((d) => DropdownMenuItem(value: d, child: Text(d, style: const TextStyle(fontSize: 12)))).toList(),
                        onChanged: (v) => setState(() => _dstDay = v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _copyDay,
                      style: ElevatedButton.styleFrom(backgroundColor: AdminColors.primary, foregroundColor: Colors.white),
                      child: const Text('Copy'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // 2. Swap Days
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AdminColors.getBorder(isDark)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.swap_horiz_rounded, size: 16, color: Colors.teal),
                    const SizedBox(width: 6),
                    Text('Swap Schedules Between Two Days', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _swapDayA,
                        isDense: true,
                        decoration: const InputDecoration(labelText: 'Day A', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                        items: _selectedDays.map((d) => DropdownMenuItem(value: d, child: Text(d, style: const TextStyle(fontSize: 12)))).toList(),
                        onChanged: (v) => setState(() => _swapDayA = v),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(Icons.compare_arrows_rounded, size: 16, color: Colors.teal),
                    ),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _swapDayB,
                        isDense: true,
                        decoration: const InputDecoration(labelText: 'Day B', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                        items: _selectedDays.map((d) => DropdownMenuItem(value: d, child: Text(d, style: const TextStyle(fontSize: 12)))).toList(),
                        onChanged: (v) => setState(() => _swapDayB = v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _swapDays,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                      child: const Text('Swap'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // 3. Clear Day
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AdminColors.getBorder(isDark)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.delete_outline_rounded, size: 16, color: AdminColors.danger),
                    const SizedBox(width: 6),
                    Text('Clear Single Day Timetable', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _clearDay,
                        isDense: true,
                        decoration: const InputDecoration(labelText: 'Select Day to Wipe', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                        items: _selectedDays.map((d) => DropdownMenuItem(value: d, child: Text(d, style: const TextStyle(fontSize: 12)))).toList(),
                        onChanged: (v) => setState(() => _clearDay = v),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _clearSelectedDay,
                      icon: const Icon(Icons.delete_sweep_rounded, size: 16),
                      label: const Text('Clear Day'),
                      style: ElevatedButton.styleFrom(backgroundColor: AdminColors.danger, foregroundColor: Colors.white),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
