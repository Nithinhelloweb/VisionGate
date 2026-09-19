import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../../config/college_ip_config.dart';
import '../../theme/admin_theme.dart';
import 'period_timing_helper.dart';

class WeeklyTimetableBuilderDialog extends StatefulWidget {
  final String token;
  final String dept;
  final String batch;
  final int semester;
  final String section;
  final VoidCallback onSaved;

  const WeeklyTimetableBuilderDialog({
    super.key,
    required this.token,
    required this.dept,
    required this.batch,
    required this.semester,
    required this.section,
    required this.onSaved,
  });

  @override
  State<WeeklyTimetableBuilderDialog> createState() => _WeeklyTimetableBuilderDialogState();
}

class _WeeklyTimetableBuilderDialogState extends State<WeeklyTimetableBuilderDialog> {
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isAutoScheduling = false;
  String? _statusMessage;
  bool _isSuccess = true;

  // Period config
  String _startTime = '08:45';
  int _totalPeriods = 7;
  int _periodDurationMins = 50;
  List<String> _workingDays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];
  List<Map<String, dynamic>> _breaks = [];
  List<PeriodSlotTiming> _timeline = [];

  // Subject allocations
  List<Map<String, dynamic>> _allocations = [];
  Map<String, dynamic>? _selectedAlloc;
  List<Map<String, dynamic>> _registeredVenues = [];

  // Working grid matrix: Map of "${day}_${periodNumber}" -> slot data
  final Map<String, Map<String, dynamic>> _matrix = {};
  int _mobileTabIndex = 0; // 0 = Matrix Grid, 1 = Subject Allocations

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // 1. Load Timetable & Period Config
      final ttRes = await http.get(
        Uri.parse(
          '${CollegeIPConfig.defaultURL}/api/v1/academics/timetable?dept=${Uri.encodeComponent(widget.dept)}&batch=${Uri.encodeComponent(widget.batch)}&semester=${widget.semester}&section=${Uri.encodeComponent(widget.section)}',
        ),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );

      if (ttRes.statusCode == 200) {
        final ttData = jsonDecode(ttRes.body);
        final pConf = ttData['period_config'] ?? {};
        _startTime = pConf['start_time'] ?? '08:45';
        _totalPeriods = (pConf['total_periods'] as num?)?.toInt() ?? 7;
        _periodDurationMins = (pConf['period_duration_mins'] as num?)?.toInt() ?? 50;
        _workingDays = List<String>.from(pConf['working_days'] ?? ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday']);
        _breaks = List<Map<String, dynamic>>.from(pConf['breaks'] ?? []);

        _timeline = PeriodTimingHelper.computeTimeline(
          startTime: _startTime,
          totalPeriods: _totalPeriods,
          periodDurationMins: _periodDurationMins,
          breaks: _breaks,
        );

        _matrix.clear();
        final slots = List<Map<String, dynamic>>.from(ttData['slots'] ?? []);
        for (var s in slots) {
          final day = (s['day_of_week'] ?? '').toString();
          final pNum = (s['period_number'] as num?)?.toInt() ?? 1;
          _matrix['${day}_$pNum'] = Map<String, dynamic>.from(s);
        }
      }

      // 2. Load Subject Allocations
      final allocRes = await http.get(
        Uri.parse(
          '${CollegeIPConfig.defaultURL}/api/v1/academics/subject-allocations?dept=${Uri.encodeComponent(widget.dept)}&batch=${Uri.encodeComponent(widget.batch)}&semester=${widget.semester}&section=${Uri.encodeComponent(widget.section)}',
        ),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );

      if (allocRes.statusCode == 200) {
        final aData = jsonDecode(allocRes.body);
        _allocations = List<Map<String, dynamic>>.from(aData['allocations'] ?? []);
        if (_allocations.isNotEmpty && _selectedAlloc == null) {
          _selectedAlloc = _allocations.first;
        }
      }

      // 3. Load Registered Venues
      try {
        final vRes = await http.get(
          Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/academics/venues'),
          headers: {'Authorization': 'Bearer ${widget.token}'},
        );
        if (vRes.statusCode == 200) {
          final vData = jsonDecode(vRes.body);
          _registeredVenues = List<Map<String, dynamic>>.from(vData['venues'] ?? []);
        }
      } catch (_) {}
    } catch (e) {
      debugPrint('Error loading builder data: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  int _getScheduledHoursForSubject(String subjectCode) {
    int count = 0;
    _matrix.forEach((key, slot) {
      if (slot['subject_code'] == subjectCode) {
        count++;
      }
    });
    return count;
  }

  void _paintSlot(String day, int periodNumber) {
    if (_selectedAlloc == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a subject from the palette first!')),
      );
      return;
    }

    final key = '${day}_$periodNumber';
    final isLab = (_selectedAlloc!['subject_type'] ?? '').toString().toLowerCase().contains('lab');
    final matchVenue = _registeredVenues.firstWhere(
      (v) {
        final vType = (v['venue_type'] ?? '').toString().toUpperCase();
        return isLab ? (vType == 'LABORATORY' || vType == 'WORKSHOP') : (vType != 'LABORATORY' && vType != 'WORKSHOP');
      },
      orElse: () => {},
    );
    final defaultVenueCode = (matchVenue['venue_code'] ?? '').toString();

    setState(() {
      _matrix[key] = {
        'day_of_week': day,
        'period_number': periodNumber,
        'subject_code': _selectedAlloc!['subject_code'],
        'subject_name': _selectedAlloc!['subject_name'],
        'staff_reg_no': _selectedAlloc!['staff_reg_no'],
        'staff_name': _selectedAlloc!['staff_name'] ?? _selectedAlloc!['staff_reg_no'],
        'room_or_lab': defaultVenueCode.isNotEmpty ? defaultVenueCode : (isLab ? 'Lab' : 'Classroom'),
        'is_lab_block': isLab,
        'lab_batch': 'ALL',
      };
    });
  }

  void _clearSlot(String day, int periodNumber) {
    final key = '${day}_$periodNumber';
    setState(() {
      _matrix.remove(key);
    });
  }

  Future<void> _runAutoScheduler() async {
    final hasAllocations = _allocations.isNotEmpty;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.auto_awesome_rounded, color: Colors.purple),
            SizedBox(width: 8),
            Text('Run Smart Auto-Scheduler?'),
          ],
        ),
        content: Text(
          hasAllocations
              ? 'This will automatically analyze subject hours, faculty availability, and lab blocks to generate a collision-free timetable proposal.'
              : 'No manual subject allocations found. The Smart Auto-Scheduler will automatically load curriculum subjects for ${widget.dept} Sem ${widget.semester} and distribute them across the week without faculty collisions.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AdminColors.primary, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.auto_awesome_rounded, size: 16),
            label: const Text('Auto-Schedule'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isAutoScheduling = true;
      _statusMessage = null;
    });

    try {
      final res = await http.post(
        Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/academics/timetable/auto-schedule'),
        headers: {'Authorization': 'Bearer ${widget.token}', 'Content-Type': 'application/json'},
        body: jsonEncode({
          'dept': widget.dept,
          'batch': widget.batch,
          'semester': widget.semester,
          'section': widget.section,
          'preserve_existing': false,
        }),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _statusMessage = data['message'] ?? 'Timetable successfully auto-scheduled!';
          _isSuccess = true;
        });
        await _loadData();
      } else {
        String errMsg = 'Auto-scheduling failed (${res.statusCode})';
        try {
          final errObj = jsonDecode(res.body);
          errMsg = (errObj['detail'] ?? errObj['message'] ?? errMsg).toString();
        } catch (_) {
          if (res.body.isNotEmpty) errMsg = res.body;
        }
        setState(() {
          _statusMessage = errMsg;
          _isSuccess = false;
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error connecting to auto-scheduler: $e';
        _isSuccess = false;
      });
    } finally {
      if (mounted) setState(() => _isAutoScheduling = false);
    }
  }

  Future<void> _clearEntireWeek() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Entire Week?'),
        content: const Text('Are you sure you want to erase all period slots for this entire week?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AdminColors.danger, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear Entire Week'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _matrix.clear();
      _statusMessage = 'Matrix cleared. Click "Save Full Week" to apply.';
      _isSuccess = true;
    });
  }

  Future<void> _saveEntireWeek() async {
    setState(() {
      _isSaving = true;
      _statusMessage = null;
    });

    final slotsList = _matrix.values.toList();

    try {
      final res = await http.post(
        Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/academics/timetable/bulk-save'),
        headers: {'Authorization': 'Bearer ${widget.token}', 'Content-Type': 'application/json'},
        body: jsonEncode({
          'dept': widget.dept,
          'batch': widget.batch,
          'semester': widget.semester,
          'section': widget.section,
          'slots': slotsList,
          'clear_existing': true,
          'allow_override': false,
        }),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _statusMessage = data['message'] ?? 'Weekly timetable saved successfully!';
          _isSuccess = true;
        });
        widget.onSaved();
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) Navigator.pop(context);
      } else if (res.statusCode == 409) {
        final err = jsonDecode(res.body)['detail'];
        final conflicts = (err is Map && err['conflicts'] is List) ? (err['conflicts'] as List).join('\n') : err.toString();
        setState(() {
          _statusMessage = 'Conflict Detected:\n$conflicts';
          _isSuccess = false;
        });
      } else {
        final err = jsonDecode(res.body)['detail'] ?? 'Failed to save weekly timetable';
        setState(() {
          _statusMessage = err.toString();
          _isSuccess = false;
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error saving timetable: $e';
        _isSuccess = false;
      });
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildHeader(bool isDark, bool isMobile, int totalSlotsFilled, int totalSlotsAvailable) {
    if (!isMobile) {
      return Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AdminColors.primarySoft, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.speed_rounded, color: AdminColors.primary, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Full-Week Timetable Matrix Builder',
                  style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: AdminColors.getTextPrimary(isDark)),
                ),
                Text(
                  '${widget.dept} • Batch ${widget.batch} • Sem ${widget.semester} Sec ${widget.section} • $totalSlotsFilled/$totalSlotsAvailable periods scheduled',
                  style: GoogleFonts.inter(fontSize: 12, color: AdminColors.getTextSecondary(isDark)),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: _isAutoScheduling ? null : _runAutoScheduler,
            icon: _isAutoScheduling
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome_rounded, size: 16, color: Colors.purple),
            label: const Text('Smart Auto-Schedule'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.purple,
              side: const BorderSide(color: Colors.purple),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _clearEntireWeek,
            icon: const Icon(Icons.delete_sweep_rounded, size: 16, color: AdminColors.danger),
            label: const Text('Clear Week'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AdminColors.danger,
              side: const BorderSide(color: AdminColors.danger),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _isSaving ? null : _saveEntireWeek,
            icon: _isSaving
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_rounded, size: 16),
            label: const Text('Save Full Week'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AdminColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: AdminColors.primarySoft, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.speed_rounded, color: AdminColors.primary, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Weekly Timetable Matrix',
                    style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AdminColors.getTextPrimary(isDark)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${widget.dept} • Sem ${widget.semester} Sec ${widget.section} (${widget.batch})',
                    style: GoogleFonts.inter(fontSize: 11, color: AdminColors.getTextSecondary(isDark)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AdminColors.primarySoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.schedule_rounded, size: 14, color: AdminColors.primary),
                    const SizedBox(width: 6),
                    Text(
                      '$totalSlotsFilled / $totalSlotsAvailable Scheduled',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AdminColors.primary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _isAutoScheduling ? null : _runAutoScheduler,
                icon: _isAutoScheduling
                    ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_awesome_rounded, size: 14, color: Colors.purple),
                label: const Text('Auto-Build', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.purple,
                  side: const BorderSide(color: Colors.purple),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _clearEntireWeek,
                icon: const Icon(Icons.delete_sweep_rounded, size: 14, color: AdminColors.danger),
                label: const Text('Clear', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AdminColors.danger,
                  side: const BorderSide(color: AdminColors.danger),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveEntireWeek,
                icon: _isSaving
                    ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_rounded, size: 14),
                label: const Text('Save Week', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AdminColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBanner(bool isDark) {
    if (_statusMessage == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _isSuccess ? Colors.green.withValues(alpha: 0.1) : AdminColors.dangerSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _isSuccess ? Colors.green : AdminColors.danger),
      ),
      child: Row(
        children: [
          Icon(_isSuccess ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
              size: 16, color: _isSuccess ? Colors.green : AdminColors.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _statusMessage!,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _isSuccess ? Colors.green[800] : AdminColors.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileSubjectRibbon(bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AdminColors.getBorder(isDark)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.brush_rounded, size: 14, color: AdminColors.primary),
              const SizedBox(width: 6),
              Text(
                'Paint Palette',
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AdminColors.getTextPrimary(isDark)),
              ),
              const Spacer(),
              Expanded(
                child: Text(
                  _selectedAlloc != null
                      ? '${_selectedAlloc!['subject_code']} (${_selectedAlloc!['subject_name']})'
                      : 'Select subject to paint slots',
                  maxLines: 1,
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AdminColors.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (_allocations.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'No subject allocations. Tap "Auto-Build" above.',
                style: GoogleFonts.inter(fontSize: 11, color: AdminColors.getTextMuted(isDark)),
              ),
            )
          else
            SizedBox(
              height: 56,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _allocations.length,
                separatorBuilder: (_, index) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) {
                  final alloc = _allocations[i];
                  final isSel = _selectedAlloc?['subject_code'] == alloc['subject_code'];
                  final targetHrs = (alloc['weekly_hours'] as num?)?.toInt() ?? 3;
                  final scheduledHrs = _getScheduledHoursForSubject(alloc['subject_code'] ?? '');
                  final isComplete = scheduledHrs >= targetHrs;
                  final isLab = (alloc['subject_type'] ?? '').toString().toLowerCase().contains('lab');

                  return InkWell(
                    onTap: () => setState(() => _selectedAlloc = alloc),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 145,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSel
                            ? AdminColors.primarySoft
                            : (isDark ? const Color(0xFF0F172A) : Colors.white),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSel
                              ? AdminColors.primary
                              : (isComplete ? Colors.green.withValues(alpha: 0.5) : AdminColors.getBorder(isDark)),
                          width: isSel ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: isLab ? Colors.purple.withValues(alpha: 0.15) : AdminColors.primarySoft,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  alloc['subject_code'] ?? '',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: isLab ? Colors.purple : AdminColors.primary,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '$scheduledHrs/$targetHrs h',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: isComplete ? Colors.green : AdminColors.getTextSecondary(isDark),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            alloc['subject_name'] ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSubjectPalette(bool isDark, {bool fullWidth = false}) {
    return Container(
      width: fullWidth ? double.infinity : 280,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdminColors.getBorder(isDark)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.palette_rounded, size: 16, color: AdminColors.primary),
              const SizedBox(width: 6),
              Text('Subject Palette', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800)),
            ],
          ),
          Text(
            'Select a subject and click cells to paint',
            style: GoogleFonts.inter(fontSize: 11, color: AdminColors.getTextMuted(isDark)),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _allocations.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.menu_book_rounded, size: 36, color: AdminColors.primary.withValues(alpha: 0.5)),
                          const SizedBox(height: 10),
                          Text(
                            'No manual allocations yet',
                            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Click Auto-Build to load curriculum subjects and auto-populate the weekly timetable.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(fontSize: 11, color: AdminColors.getTextMuted(isDark)),
                          ),
                          const SizedBox(height: 14),
                          ElevatedButton.icon(
                            onPressed: _isAutoScheduling ? null : _runAutoScheduler,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.purple,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.auto_awesome_rounded, size: 14),
                            label: const Text('Auto-Build Now', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _allocations.length,
                    itemBuilder: (ctx, i) {
                      final alloc = _allocations[i];
                      final isSel = _selectedAlloc?['subject_code'] == alloc['subject_code'];
                      final targetHrs = (alloc['weekly_hours'] as num?)?.toInt() ?? 3;
                      final scheduledHrs = _getScheduledHoursForSubject(alloc['subject_code'] ?? '');
                      final isComplete = scheduledHrs >= targetHrs;
                      final isLab = (alloc['subject_type'] ?? '').toString().toLowerCase().contains('lab');

                      return InkWell(
                        onTap: () {
                          setState(() {
                            _selectedAlloc = alloc;
                            if (fullWidth) _mobileTabIndex = 0; // Switch back to grid on mobile
                          });
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isSel
                                ? AdminColors.primarySoft
                                : (isDark ? const Color(0xFF0F172A) : Colors.white),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSel
                                  ? AdminColors.primary
                                  : (isComplete ? Colors.green.withValues(alpha: 0.5) : AdminColors.getBorder(isDark)),
                              width: isSel ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isLab ? Colors.purple.withValues(alpha: 0.15) : AdminColors.primarySoft,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      alloc['subject_code'] ?? '',
                                      style: GoogleFonts.inter(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: isLab ? Colors.purple : AdminColors.primary,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '$scheduledHrs / $targetHrs hrs',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: isComplete ? Colors.green : AdminColors.getTextSecondary(isDark),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                alloc['subject_name'] ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
                              ),
                              Text(
                                alloc['staff_name'] ?? alloc['staff_reg_no'] ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(fontSize: 11, color: AdminColors.getTextSecondary(isDark)),
                              ),
                              const SizedBox(height: 6),
                              LinearProgressIndicator(
                                value: targetHrs > 0 ? (scheduledHrs / targetHrs).clamp(0.0, 1.0) : 0.0,
                                backgroundColor: isDark ? Colors.grey[800] : Colors.grey[200],
                                color: isComplete ? Colors.green : AdminColors.primary,
                                minHeight: 4,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMatrixGrid(bool isDark, {required bool isMobile}) {
    final dayColWidth = isMobile ? 70.0 : 90.0;
    final breakColWidth = isMobile ? 50.0 : 60.0;
    final slotColWidth = isMobile ? 100.0 : 115.0;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdminColors.getBorder(isDark)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: DataTable(
                headingRowHeight: isMobile ? 46 : 52,
                dataRowMinHeight: isMobile ? 64 : 70,
                dataRowMaxHeight: isMobile ? 72 : 76,
                horizontalMargin: isMobile ? 8 : 12,
                columnSpacing: isMobile ? 6 : 10,
                border: TableBorder.all(color: AdminColors.getBorder(isDark), width: 0.5),
                columns: [
                  DataColumn(
                    label: Container(
                      width: dayColWidth,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Day',
                        style: GoogleFonts.inter(
                          fontSize: isMobile ? 11 : 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  ..._timeline.map((t) {
                    final isBrk = t.isBreak;
                    return DataColumn(
                      label: Container(
                        width: isBrk ? breakColWidth : slotColWidth,
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              t.label,
                              style: GoogleFonts.inter(
                                fontSize: isMobile ? 10 : 11,
                                fontWeight: FontWeight.w700,
                                color: isBrk ? Colors.amber[900] : AdminColors.getTextPrimary(isDark),
                              ),
                            ),
                            Text(
                              '${t.startTime}-${t.endTime}',
                              style: GoogleFonts.inter(
                                fontSize: isMobile ? 8 : 9,
                                color: AdminColors.getTextMuted(isDark),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
                rows: _workingDays.map((day) {
                  return DataRow(
                    cells: [
                      DataCell(
                        Container(
                          width: dayColWidth,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            isMobile && day.length > 3 ? day.substring(0, 3) : day,
                            style: GoogleFonts.inter(
                              fontSize: isMobile ? 11 : 12,
                              fontWeight: FontWeight.w800,
                              color: AdminColors.getTextPrimary(isDark),
                            ),
                          ),
                        ),
                      ),
                      ..._timeline.map((t) {
                        if (t.isBreak) {
                          return DataCell(
                            Container(
                              width: breakColWidth,
                              color: isDark ? const Color(0xFF292524) : const Color(0xFFFFFBEB),
                              alignment: Alignment.center,
                              child: RotatedBox(
                                quarterTurns: 3,
                                child: Text(
                                  t.label,
                                  style: GoogleFonts.inter(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.amber[800],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }

                        final key = '${day}_${t.periodNumber}';
                        final slot = _matrix[key];
                        final isFilled = slot != null;

                        return DataCell(
                          InkWell(
                            onTap: () => _paintSlot(day, t.periodNumber),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: slotColWidth,
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: isFilled
                                    ? (slot['is_lab_block'] == true
                                        ? Colors.purple.withValues(alpha: 0.12)
                                        : AdminColors.primarySoft.withValues(alpha: 0.5))
                                    : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC)),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isFilled
                                      ? AdminColors.primary.withValues(alpha: 0.4)
                                      : AdminColors.getBorder(isDark),
                                ),
                              ),
                              child: isFilled
                                  ? Stack(
                                      children: [
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              slot['subject_code'] ?? '',
                                              style: GoogleFonts.inter(
                                                fontSize: isMobile ? 9 : 10,
                                                fontWeight: FontWeight.w800,
                                                color: AdminColors.primary,
                                              ),
                                            ),
                                            Text(
                                              slot['subject_name'] ?? '',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.inter(
                                                fontSize: isMobile ? 9 : 10,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            Text(
                                              slot['staff_name'] ?? slot['staff_reg_no'] ?? '',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.inter(
                                                fontSize: 8,
                                                color: AdminColors.getTextSecondary(isDark),
                                              ),
                                            ),
                                          ],
                                        ),
                                        Positioned(
                                          right: 0,
                                          top: 0,
                                          child: GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTap: () => _clearSlot(day, t.periodNumber),
                                            child: Container(
                                              padding: const EdgeInsets.all(3),
                                              decoration: BoxDecoration(
                                                color: AdminColors.dangerSoft,
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(
                                                Icons.close_rounded,
                                                size: 11,
                                                color: AdminColors.danger,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    )
                                  : Center(
                                      child: Icon(
                                        Icons.add_rounded,
                                        size: isMobile ? 14 : 16,
                                        color: AdminColors.getTextMuted(isDark),
                                      ),
                                    ),
                            ),
                          ),
                        );
                      }),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totalSlotsAvailable = _workingDays.length * _totalPeriods;
    final totalSlotsFilled = _matrix.length;
    final media = MediaQuery.of(context);
    final isMobile = media.size.width < 900;

    return Dialog(
      backgroundColor: AdminColors.getCard(isDark),
      insetPadding: isMobile
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 8)
          : const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(isMobile ? 14 : 20)),
      child: Container(
        width: isMobile ? double.infinity : 1200,
        height: isMobile ? double.infinity : 750,
        padding: EdgeInsets.all(isMobile ? 12 : 20),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(isDark, isMobile, totalSlotsFilled, totalSlotsAvailable),
                  const SizedBox(height: 10),
                  _buildStatusBanner(isDark),
                  if (isMobile) ...[
                    // Mobile View Switcher
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: ChoiceChip(
                              label: Center(
                                child: Text(
                                  'Matrix Grid (${_matrix.length})',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                              selected: _mobileTabIndex == 0,
                              onSelected: (val) {
                                if (val) setState(() => _mobileTabIndex = 0);
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              label: Center(
                                child: Text(
                                  'Subjects (${_allocations.length})',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                              selected: _mobileTabIndex == 1,
                              onSelected: (val) {
                                if (val) setState(() => _mobileTabIndex = 1);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_mobileTabIndex == 0) ...[
                      _buildMobileSubjectRibbon(isDark),
                      Expanded(child: _buildMatrixGrid(isDark, isMobile: true)),
                    ] else ...[
                      Expanded(child: _buildSubjectPalette(isDark, fullWidth: true)),
                    ],
                  ] else ...[
                    // Desktop side-by-side workspace
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSubjectPalette(isDark),
                          const SizedBox(width: 14),
                          Expanded(child: _buildMatrixGrid(isDark, isMobile: false)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
