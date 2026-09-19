import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import '../config/college_ip_config.dart';
import '../theme/admin_theme.dart';
import '../utils/api_response_utils.dart';

class AcademicsSettingsPage extends StatefulWidget {
  final String token;
  final bool showAppBar;

  const AcademicsSettingsPage({
    super.key,
    required this.token,
    this.showAppBar = true,
  });

  @override
  State<AcademicsSettingsPage> createState() => _AcademicsSettingsPageState();
}

class _AcademicsSettingsPageState extends State<AcademicsSettingsPage>
    with SingleTickerProviderStateMixin {
  List<Map<String, DateTime?>> _academicRanges = [];
  final Map<String, Map<String, dynamic>> _holidayOverrides = {};
  List<Map<String, dynamic>> _holidays = [];
  bool _isLoading = true;
  bool _isSaving = false;
  String _searchQuery = '';
  String _filterStatus = 'holiday';
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut);
    _loadAcademics();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAcademics() async {
    try {
      final response = await http.get(
        Uri.parse('${CollegeIPConfig.defaultURL}/admin/academics'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'] ?? {};
        if (!mounted) return;
        setState(() {
          final rawRanges = data['academic_ranges'] as List? ?? [];
          if (rawRanges.isNotEmpty) {
            _academicRanges = rawRanges.map<Map<String, DateTime?>>((r) {
              return {
                'start': DateTime.tryParse(r['start']?.toString() ?? ''),
                'end': DateTime.tryParse(r['end']?.toString() ?? ''),
              };
            }).toList();
          } else {
            final s = _parseDate(data['academic_year_start']);
            final e = _parseDate(data['academic_year_end']);
            _academicRanges = [
              if (s != null || e != null) {'start': s, 'end': e},
            ];
          }
          _holidayOverrides.clear();
          final overrides = Map<String, dynamic>.from(data['holiday_overrides'] ?? {});
          overrides.forEach((key, value) {
            _holidayOverrides[key] = Map<String, dynamic>.from(value as Map);
          });
          _holidays = (data['holidays'] as List? ?? [])
              .map<Map<String, dynamic>>((e) {
                final m = Map<String, dynamic>.from(e as Map);
                m['status'] = m['status'] ?? m['effective_status'] ?? 'working_day';
                return m;
              })
              .toList();
        });
        _animCtrl.forward(from: 0);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          if (_academicRanges.isEmpty) {
            _academicRanges.add({'start': null, 'end': null});
          }
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null || value.toString().isEmpty) return null;
    return DateTime.tryParse(value.toString());
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Not set';
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _fmtShort(DateTime date) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  Future<void> _pickRangeStart(int index) async {
    final current = _academicRanges[index]['start'];
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() => _academicRanges[index]['start'] = picked);
    }
  }

  Future<void> _pickRangeEnd(int index) async {
    final current = _academicRanges[index]['end'];
    final start = _academicRanges[index]['start'] ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? start,
      firstDate: start,
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() => _academicRanges[index]['end'] = picked);
    }
  }

  void _addRange() {
    setState(() {
      _academicRanges.add({'start': null, 'end': null});
    });
  }

  void _removeRange(int index) {
    if (_academicRanges.length <= 1) return;
    setState(() {
      _academicRanges.removeAt(index);
    });
  }

  bool get _hasValidRanges {
    if (_academicRanges.isEmpty) return false;
    for (final r in _academicRanges) {
      if (r['start'] == null || r['end'] == null) return false;
    }
    return true;
  }

  Future<void> _addHoliday() async {
    if (!_hasValidRanges) {
      _showSnack('Set at least one academic range first.');
      return;
    }
    final firstRange = _academicRanges.firstWhere((r) => r['start'] != null);
    final picked = await showDatePicker(
      context: context,
      initialDate: firstRange['start'] ?? DateTime.now(),
      firstDate: firstRange['start'] ?? DateTime(2000),
      lastDate: firstRange['end'] ?? DateTime(2100),
    );
    if (picked == null || !mounted) return;

    final reasonCtrl = TextEditingController();
    final status = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Add Holiday Override'),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(
            labelText: 'Reason',
            hintText: 'Optional reason for this holiday',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'holiday'),
            child: const Text('Mark Holiday'),
          ),
        ],
      ),
    );
    if (status == null || !mounted) return;

    setState(() {
      _holidayOverrides[_formatDate(picked)] = {
        'status': status,
        'reason': reasonCtrl.text.trim(),
      };
      _refreshHolidayList();
    });
  }

  void _refreshHolidayList() {
    if (!_hasValidRanges) return;
    final next = <Map<String, dynamic>>[];
    for (final range in _academicRanges) {
      final start = range['start'];
      final end = range['end'];
      if (start == null || end == null) continue;
      var day = DateTime(start.year, start.month, start.day);
      while (!day.isAfter(end)) {
        final key = _formatDate(day);
        final isSunday = day.weekday == DateTime.sunday;
        final override = _holidayOverrides[key];
        final status = (override?['status']?.toString() ?? (isSunday ? 'holiday' : 'working_day'));
        next.add({
          'date': key,
          'is_sunday': isSunday,
          'status': status,
          'reason': override?['reason']?.toString() ?? '',
        });
        day = day.add(const Duration(days: 1));
      }
    }
    _holidays = next;
  }

  Future<void> _save() async {
    if (!_hasValidRanges) {
      _showSnack('Please set all academic range dates first.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      final rangesJson = _academicRanges.map((r) {
        return {
          'start': _formatDate(r['start']),
          'end': _formatDate(r['end']),
        };
      }).toList();

      final response = await http.post(
        Uri.parse('${CollegeIPConfig.defaultURL}/admin/academics'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'academic_ranges': rangesJson,
          'holiday_overrides': _holidayOverrides,
        }),
      );
      if (response.statusCode == 200) {
        if (mounted) _showSnack('Academic settings saved successfully', isError: false);
        await _loadAcademics();
      } else {
        throw Exception('Failed to save');
      }
    } catch (e) {
      if (mounted) _showSnack('Error: ${ApiResponseUtils.sanitize(e)}');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _toggleHoliday(String date, String currentStatus) {
    setState(() {
      final nextStatus = currentStatus == 'holiday' ? 'working_day' : 'holiday';
      _holidayOverrides[date] = {
        'status': nextStatus,
        'reason': _holidayOverrides[date]?['reason'] ?? '',
      };
      _refreshHolidayList();
    });
  }

  Future<void> _editHolidayOverride(String date) async {
    final current = _holidayOverrides[date] ?? {'status': 'holiday', 'reason': ''};
    final reasonCtrl = TextEditingController(text: current['reason']?.toString() ?? '');
    String status = current['status']?.toString() ?? 'holiday';

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Edit Override: $date'),
        content: StatefulBuilder(
          builder: (ctx, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: status,
                items: const [
                  DropdownMenuItem(value: 'holiday', child: Text('Holiday')),
                  DropdownMenuItem(value: 'working_day', child: Text('Working Day')),
                ],
                onChanged: (v) {
                  if (v != null) setDialogState(() => status = v);
                },
                decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                decoration: const InputDecoration(labelText: 'Reason', border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, {'status': status, 'reason': reasonCtrl.text.trim()}),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == null || !mounted) return;
    setState(() {
      _holidayOverrides[date] = {
        'status': result['status'] ?? 'holiday',
        'reason': result['reason'] ?? '',
      };
      _refreshHolidayList();
    });
  }

  void _deleteHolidayOverride(String date) {
    if (!mounted) return;
    setState(() {
      _holidayOverrides.remove(date);
      _refreshHolidayList();
    });
  }

  void _showSnack(String msg, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(12),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isWide = w >= 900;
    final isTablet = w >= 600;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: AdminColors.getSurface(isDark),
      extendBodyBehindAppBar: widget.showAppBar,
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('Academics', style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5)),
              centerTitle: false,
              flexibleSpace: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1A237E), Color(0xFF3949AB), Color(0xFF5C6BC0)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
              foregroundColor: Colors.white,
              elevation: 0,
              actions: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: IconButton(
                    onPressed: _isSaving ? null : _save,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.save_rounded),
                    tooltip: 'Save',
                  ),
                ),
              ],
            )
          : null,
      body: _isLoading ? _buildShimmer(isTablet) : _buildBody(isWide, isTablet, isDark),
      bottomNavigationBar: _isLoading ? null : _buildBottomBar(isTablet, isDark),
    );
  }

  Widget _buildTopHeader(bool isDark, bool isTablet, bool isWide) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AdminColors.getCard(isDark),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AdminColors.getBorder(isDark)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AdminColors.primarySoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.school_rounded, color: AdminColors.primary, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Academic Year & Holiday Management',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AdminColors.getTextPrimary(isDark),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Configure institutional academic ranges, active semesters, and dynamic holiday overrides',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AdminColors.getTextSecondary(isDark),
                      ),
                    ),
                  ],
                ),
              ),
              if (isWide) ...[
                OutlinedButton.icon(
                  onPressed: _addRange,
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Add Range'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AdminColors.primary,
                    side: const BorderSide(color: AdminColors.primary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _addHoliday,
                  icon: const Icon(Icons.event_available_rounded, size: 16),
                  label: const Text('Add Holiday'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AdminColors.danger,
                    side: const BorderSide(color: AdminColors.danger),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _loadAcademics,
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: 'Refresh Academics',
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _isSaving ? null : _save,
                  icon: _isSaving
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
                  ),
                ),
              ],
            ],
          ),
          if (!isWide) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _addRange,
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Add Range'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AdminColors.primary,
                    side: const BorderSide(color: AdminColors.primary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _addHoliday,
                  icon: const Icon(Icons.event_available_rounded, size: 16),
                  label: const Text('Add Holiday'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AdminColors.danger,
                    side: const BorderSide(color: AdminColors.danger),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                IconButton(
                  onPressed: _loadAcademics,
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: 'Refresh Academics',
                ),
                ElevatedButton.icon(
                  onPressed: _isSaving ? null : _save,
                  icon: _isSaving
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
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildShimmer(bool isTablet) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFF5F7FA), Color(0xFFE8ECF1)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(
          isTablet ? 32 : 16,
          widget.showAppBar ? (kToolbarHeight + 24) : 16,
          isTablet ? 32 : 16,
          16,
        ),
        itemCount: 6,
        itemBuilder: (_, i) => AnimatedContainer(
          duration: const Duration(milliseconds: 600),
          margin: const EdgeInsets.only(bottom: 16),
          height: 100,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(bool isWide, bool isTablet, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark ? [const Color(0xFF121212), const Color(0xFF1A1A2E)] : [const Color(0xFFF5F7FA), const Color(0xFFE8ECF1)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: FadeTransition(
        opacity: _fadeAnim,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                isTablet ? 32 : 16,
                widget.showAppBar ? (kToolbarHeight + 24) : 16,
                isTablet ? 32 : 16,
                24,
              ),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  if (!widget.showAppBar)
                    _buildTopHeader(isDark, isTablet, isWide),
                  if (isWide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 5, child: _buildRangesCard(isTablet, isDark)),
                        const SizedBox(width: 20),
                        Expanded(flex: 7, child: _buildHolidayCard(isTablet, isDark)),
                      ],
                    )
                  else ...[
                    _buildRangesCard(isTablet, isDark),
                    const SizedBox(height: 20),
                    _buildHolidayCard(isTablet, isDark),
                  ],
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(bool isTablet, bool isDark) {
    return Container(
      padding: EdgeInsets.fromLTRB(isTablet ? 32 : 16, 8, isTablet ? 32 : 16, MediaQuery.of(context).padding.bottom + 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark ? [const Color(0xFF121212), const Color(0xFF1A1A2E)] : [const Color(0xFFF5F7FA), const Color(0xFFE8ECF1)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: _ActionChip(
                icon: Icons.add_circle_outline,
                label: 'Add Range',
                onTap: _addRange,
                color: const Color(0xFF3949AB),
                expand: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionChip(
                icon: Icons.event_available,
                label: 'Add Holiday',
                onTap: _addHoliday,
                color: const Color(0xFFE53935),
                expand: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- RANGES CARD ----------
  Widget _buildRangesCard(bool isTablet, bool isDark) {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF3949AB).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.calendar_month_rounded, color: Color(0xFF3949AB), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Academic Ranges',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: 0.3, color: isDark ? Colors.white : null)),
                    const SizedBox(height: 2),
                    Text('${_academicRanges.length} range${_academicRanges.length == 1 ? '' : 's'} defined',
                        style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey.shade500)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('Add one or more date ranges (e.g. semesters).',
              style: TextStyle(fontSize: 12, color: isDark ? Colors.white38 : Colors.grey.shade400)),
          const SizedBox(height: 16),
          if (_academicRanges.isEmpty)
            _emptyBox('No ranges defined. Tap "Add Range" below.', isDark)
          else
            ..._academicRanges.asMap().entries.map((entry) => _buildRangeTile(entry.key, entry.value, isTablet, isDark)),
        ],
      ),
    );
  }

  Widget _emptyBox(String msg, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Text(msg, style: TextStyle(color: isDark ? Colors.white38 : Colors.grey.shade400, fontSize: 13)),
      ),
    );
  }

  Widget _buildRangeTile(int index, Map<String, DateTime?> range, bool isTablet, bool isDark) {
    final start = range['start'];
    final end = range['end'];
    final hasStart = start != null;
    final hasEnd = end != null;
    final isValid = hasStart && hasEnd && !start.isAfter(end);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isValid
            ? (isDark ? const Color(0xFF1E1E30) : const Color(0xFFF0F4FF))
            : (isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade50),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isValid
            ? const Color(0xFF3949AB).withValues(alpha: 0.2)
            : (isDark ? Colors.white12 : Colors.grey.shade200)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF3949AB), Color(0xFF5C6BC0)]),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text('${index + 1}',
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isValid ? '${_fmtShort(start)} - ${_fmtShort(end)}' : (hasStart || hasEnd ? 'Incomplete' : 'New Range'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isValid ? (isDark ? Colors.white : Colors.black87) : Colors.grey,
                    ),
                  ),
                ),
                if (_academicRanges.length > 1)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18, color: Colors.red),
                      onPressed: () => _removeRange(index),
                      tooltip: 'Remove range',
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _DateField(
                    label: 'Start',
                    date: start,
                    onTap: () => _pickRangeStart(index),
                    isSet: hasStart,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward_rounded, size: 18, color: isDark ? Colors.white38 : Colors.grey.shade400),
                ),
                Expanded(
                  child: _DateField(
                    label: 'End',
                    date: end,
                    onTap: () => _pickRangeEnd(index),
                    isSet: hasEnd,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------- HOLIDAY CARD ----------
  Widget _buildHolidayCard(bool isTablet, bool isDark) {
    final holidayCount = _holidays.where((d) => d['status'] == 'holiday').length;
    final overrideCount = _holidayOverrides.length;

    List<Map<String, dynamic>> filtered;
    if (_searchQuery.isEmpty && _filterStatus == 'all') {
      filtered = _holidays;
    } else {
      filtered = _holidays.where((h) {
        final matchesSearch = _searchQuery.isEmpty || h['date'].toString().contains(_searchQuery);
        final matchesFilter = _filterStatus == 'all' ||
            (_filterStatus == 'holiday' && h['status'] == 'holiday') ||
            (_filterStatus == 'working_day' && h['status'] == 'working_day') ||
            (_filterStatus == 'overridden' && _holidayOverrides.containsKey(h['date']));
        return matchesSearch && matchesFilter;
      }).toList();
    }

    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE53935).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.event_busy_rounded, color: Color(0xFFE53935), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Holiday Calendar',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: 0.3, color: isDark ? Colors.white : null)),
                    const SizedBox(height: 2),
                    Text('$holidayCount holidays · ${_holidays.length} total days · $overrideCount overrides',
                        style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey.shade500)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('Sundays are holidays by default. Toggle any date to override.',
              style: TextStyle(fontSize: 12, color: isDark ? Colors.white38 : Colors.grey.shade400)),
          const SizedBox(height: 12),
          // Search & filter
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    onChanged: (v) => setState(() => _searchQuery = v),
                    style: TextStyle(color: isDark ? Colors.white : null),
                    decoration: InputDecoration(
                      hintText: 'Search dates...',
                      hintStyle: TextStyle(fontSize: 13, color: isDark ? Colors.white38 : Colors.grey.shade400),
                      prefixIcon: Icon(Icons.search, size: 18, color: isDark ? Colors.white38 : Colors.grey.shade400),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      filled: true,
                      fillColor: isDark ? const Color(0xFF2A2A30) : Colors.grey.shade100,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _FilterDropdown(
                value: _filterStatus,
                onChanged: (v) => setState(() => _filterStatus = v!),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_holidays.isEmpty)
            _emptyBox('Set academic ranges to generate the holiday calendar.', isDark)
          else
            _buildHolidayGrid(filtered, isTablet),
        ],
      ),
    );
  }

  Widget _buildHolidayGrid(List<Map<String, dynamic>> items, bool isTablet) {
    final crossAxisCount = isTablet ? 4 : 2;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: 1.5,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final h = items[i];
        final date = h['date'].toString();
        final status = h['status'].toString();
        final isHoliday = status == 'holiday';
        final hasOverride = _holidayOverrides.containsKey(date);
        return _HolidayTile(
          date: date,
          isHoliday: isHoliday,
          hasOverride: hasOverride,
          onToggle: () => _toggleHoliday(date, status),
          onEdit: () => _editHolidayOverride(date),
          onDelete: hasOverride ? () => _deleteHolidayOverride(date) : null,
        );
      },
    );
  }
}

// ---------- HELPER WIDGETS ----------

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E).withValues(alpha: 0.9) : Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? date;
  final VoidCallback onTap;
  final bool isSet;

  const _DateField({
    required this.label,
    required this.date,
    required this.onTap,
    required this.isSet,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final greyBg = isDark ? const Color(0xFF2A2A30) : Colors.grey.shade100;
    final greyBorder = isDark ? Colors.white12 : Colors.grey.shade200;
    final greyLabel = isDark ? Colors.white38 : Colors.grey.shade500;
    final greyIcon = isDark ? Colors.white38 : Colors.grey.shade400;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSet ? const Color(0xFF3949AB).withValues(alpha: isDark ? 0.15 : 0.06) : greyBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSet ? const Color(0xFF3949AB).withValues(alpha: 0.2) : greyBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: greyLabel)),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.calendar_today_rounded, size: 13, color: isSet ? const Color(0xFF3949AB) : greyIcon),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    date != null ? '${date!.day.toString().padLeft(2, '0')}/${date!.month.toString().padLeft(2, '0')}/${date!.year}' : 'Select',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSet ? FontWeight.w600 : FontWeight.normal,
                      color: isSet ? (isDark ? Colors.white : Colors.black87) : greyLabel,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  final bool expand;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.color,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.8)]),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 3))],
          ),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class _HolidayTile extends StatelessWidget {
  final String date;
  final bool isHoliday;
  final bool hasOverride;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;

  const _HolidayTile({
    required this.date,
    required this.isHoliday,
    required this.hasOverride,
    required this.onToggle,
    required this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isHoliday
        ? (isDark ? const Color(0xFF3A1A1A) : const Color(0xFFFFF0F0))
        : (isDark ? const Color(0xFF2A2A30) : Colors.grey.shade50);
    final borderColor = isHoliday
        ? const Color(0xFFE53935).withValues(alpha: 0.25)
        : (isDark ? Colors.white12 : Colors.grey.shade200);
    final iconColor = isHoliday ? const Color(0xFFE53935) : (isDark ? Colors.white38 : Colors.grey.shade400);
    final labelColor = isHoliday ? Colors.red.shade400 : (isDark ? Colors.white60 : Colors.grey.shade500);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(isHoliday ? Icons.event_busy_rounded : Icons.event_available_rounded,
                        size: 16, color: iconColor),
                    const Spacer(),
                    SizedBox(
                      height: 20,
                      child: Switch(
                        value: isHoliday,
                        onChanged: (_) => onToggle(),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        activeTrackColor: const Color(0xFFE53935).withValues(alpha: 0.35),
                        activeColor: const Color(0xFFE53935),
                        inactiveTrackColor: Colors.grey.shade200,
                        inactiveThumbColor: Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(date.length >= 10 ? date.substring(5) : date,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                        color: isHoliday ? Colors.red.shade700 : (isDark ? Colors.white70 : Colors.grey.shade600))),
                const SizedBox(height: 2),
                Text(
                  isHoliday ? 'Holiday' : 'Working',
                  style: TextStyle(fontSize: 9, color: labelColor),
                ),
                if (hasOverride)
                  Row(
                    children: [
                      Icon(Icons.edit_note_rounded, size: 12, color: Colors.orange.shade400),
                      const SizedBox(width: 2),
                      Text('Override', style: TextStyle(fontSize: 8, color: Colors.orange.shade400)),
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

class _FilterDropdown extends StatelessWidget {
  final String value;
  final ValueChanged<String?> onChanged;

  const _FilterDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A30) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          dropdownColor: isDark ? const Color(0xFF1E1E24) : null,
          style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.grey.shade700),
          items: const [
            DropdownMenuItem(value: 'all', child: Text('All')),
            DropdownMenuItem(value: 'holiday', child: Text('Holidays')),
            DropdownMenuItem(value: 'working_day', child: Text('Working')),
            DropdownMenuItem(value: 'overridden', child: Text('Overridden')),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}
