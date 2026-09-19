import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/date_timetable_service.dart';
import '../../theme/admin_theme.dart';
import 'academic_calendar_override_dialog.dart';

/// Universal Date-Aware Timetable View Widget.
/// Displays the exact instructional schedule for any chosen calendar date,
/// dynamically resolving Day Orders, holidays, staff leave substitutions, and venue relocations.
class DateTimetableView extends StatefulWidget {
  final String token;
  final String? dept;
  final String? batch;
  final int? semester;
  final String? section;
  final String? staffRegNo;
  final bool isEditableByAdmin;
  final VoidCallback? onScheduleChanged;

  const DateTimetableView({
    super.key,
    required this.token,
    this.dept,
    this.batch,
    this.semester,
    this.section,
    this.staffRegNo,
    this.isEditableByAdmin = false,
    this.onScheduleChanged,
  });

  @override
  State<DateTimetableView> createState() => _DateTimetableViewState();
}

class _DateTimetableViewState extends State<DateTimetableView> {
  DateTime _selectedDate = DateTime.now();
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _timetableData = {};

  @override
  void initState() {
    super.initState();
    _loadDateTimetable();
  }

  @override
  void didUpdateWidget(covariant DateTimetableView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dept != widget.dept ||
        oldWidget.batch != widget.batch ||
        oldWidget.semester != widget.semester ||
        oldWidget.section != widget.section ||
        oldWidget.staffRegNo != widget.staffRegNo) {
      _loadDateTimetable();
    }
  }

  Future<void> _loadDateTimetable() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final fmt = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final res = await DateTimetableService.getTimetableForDate(
      token: widget.token,
      date: fmt,
      dept: widget.dept,
      batch: widget.batch,
      semester: widget.semester,
      section: widget.section,
      staffRegNo: widget.staffRegNo,
    );

    if (!mounted) return;
    setState(() {
      _loading = false;
      _timetableData = res;
      if (res['success'] == false && res['message'] != null) {
        _error = res['message'].toString();
      }
    });
  }

  void _onDateSelected(DateTime dt) {
    if (DateUtils.isSameDay(_selectedDate, dt)) return;
    setState(() => _selectedDate = dt);
    _loadDateTimetable();
  }

  Future<void> _pickCustomDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 90)),
      lastDate: DateTime.now().add(const Duration(days: 180)),
    );
    if (picked != null) {
      _onDateSelected(picked);
    }
  }

  void _openOverrideDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AcademicCalendarOverrideDialog(
        token: widget.token,
        initialDate: _selectedDate,
        onSaved: () {
          _loadDateTimetable();
          widget.onScheduleChanged?.call();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final periods = (_timetableData['periods'] as List? ?? []).cast<Map<String, dynamic>>();
    final isHoliday = _timetableData['is_holiday'] == true;
    final isOverride = _timetableData['is_override'] == true;
    final mappedDay = _timetableData['mapped_day_of_week'] ?? DateFormat('EEEE').format(_selectedDate);
    final dayOrder = _timetableData['day_order'];
    final scheduleTitle = _timetableData['title'] ?? '$mappedDay Schedule';
    final holidayReason = _timetableData['reason'] ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── TOP DATE NAVIGATOR BAR ──────────────────────────────────────────
        _buildDateNavigator(isDark),

        const SizedBox(height: 12),

        // ── DATE SCHEDULE STATUS BANNER ─────────────────────────────────────
        _buildScheduleHeaderCard(
          isDark: isDark,
          isHoliday: isHoliday,
          isOverride: isOverride,
          mappedDay: mappedDay,
          dayOrder: dayOrder,
          title: scheduleTitle,
          reason: holidayReason,
        ),

        const SizedBox(height: 14),

        // ── PERIOD LIST / HOLIDAY / EMPTY VIEW ──────────────────────────────
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: CircularProgressIndicator(),
            ),
          )
        else if (_error != null)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: Colors.red, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                  ),
                ),
              ],
            ),
          )
        else if (isHoliday)
          _buildHolidayCard(isDark, scheduleTitle, holidayReason)
        else if (periods.isEmpty)
          _buildEmptyCard(isDark)
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: periods.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (ctx, i) => _buildPeriodCard(periods[i], isDark),
          ),
      ],
    );
  }

  Widget _buildDateNavigator(bool isDark) {
    final now = DateTime.now();
    final isToday = DateUtils.isSameDay(_selectedDate, now);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        children: [
          // Control row
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded, size: 22),
                tooltip: 'Previous Day',
                onPressed: () => _onDateSelected(
                  _selectedDate.subtract(const Duration(days: 1)),
                ),
              ),
              Expanded(
                child: Center(
                  child: InkWell(
                    onTap: _pickCustomDate,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.calendar_month_rounded,
                            size: 16,
                            color: isToday ? AdminColors.primary : AdminColors.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              DateFormat('EEE, d MMM yyyy').format(_selectedDate),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: isDark ? Colors.white : AdminColors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_drop_down_rounded, size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded, size: 22),
                tooltip: 'Next Day',
                onPressed: () => _onDateSelected(
                  _selectedDate.add(const Duration(days: 1)),
                ),
              ),
              if (!isToday) ...[
                const SizedBox(width: 4),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    side: const BorderSide(color: AdminColors.primary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _onDateSelected(now),
                  child: const Text('Today', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
              if (widget.isEditableByAdmin) ...[
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.tune_rounded, size: 20, color: AdminColors.primary),
                  tooltip: 'Configure Date Mapping / Holiday',
                  onPressed: _openOverrideDialog,
                ),
              ],
            ],
          ),

          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 8),

          // Horizontal 7-Day Strip
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(7, (idx) {
                final dayOffset = idx - 3;
                final date = _selectedDate.add(Duration(days: dayOffset));
                final isSelected = DateUtils.isSameDay(date, _selectedDate);
                final isCurrentDay = DateUtils.isSameDay(date, now);
                final dayNameShort = DateFormat('E').format(date);
                final dayNum = date.day.toString();

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: InkWell(
                    onTap: () => _onDateSelected(date),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: 52,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AdminColors.primary
                            : isCurrentDay
                                ? AdminColors.primary.withValues(alpha: 0.1)
                                : isDark
                                    ? const Color(0xFF0F172A)
                                    : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? AdminColors.primary
                              : isCurrentDay
                                  ? AdminColors.primary.withValues(alpha: 0.4)
                                  : isDark
                                      ? Colors.white10
                                      : Colors.grey.shade200,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            dayNameShort,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              color: isSelected
                                  ? Colors.white
                                  : isDark
                                      ? Colors.white60
                                      : AdminColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            dayNum,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: isSelected
                                  ? Colors.white
                                  : isDark
                                      ? Colors.white
                                      : AdminColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleHeaderCard({
    required bool isDark,
    required bool isHoliday,
    required bool isOverride,
    required String mappedDay,
    required dynamic dayOrder,
    required String title,
    required String reason,
  }) {
    if (isHoliday) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.beach_access_rounded, color: Colors.red, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.red,
                    ),
                  ),
                  if (reason.isNotEmpty)
                    Text(
                      reason,
                      style: TextStyle(fontSize: 11, color: Colors.red.shade700),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isOverride
            ? Colors.amber.withValues(alpha: 0.08)
            : AdminColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isOverride
              ? Colors.amber.withValues(alpha: 0.4)
              : AdminColors.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isOverride ? Icons.sync_alt_rounded : Icons.schedule_rounded,
            color: isOverride ? Colors.amber.shade800 : AdminColors.primary,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: isOverride ? Colors.amber.shade900 : AdminColors.primary,
                      ),
                    ),
                    if (dayOrder != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AdminColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Day Order $dayOrder',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AdminColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (isOverride && reason.isNotEmpty)
                  Text(
                    reason,
                    style: TextStyle(fontSize: 11, color: Colors.amber.shade900),
                  ),
              ],
            ),
          ),
          if (widget.isEditableByAdmin)
            GestureDetector(
              onTap: _openOverrideDialog,
              child: const Text(
                'Edit Mapping',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AdminColors.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPeriodCard(Map<String, dynamic> p, bool isDark) {
    final pNum = p['period_number'];
    final startTime = p['start_time'] ?? '';
    final endTime = p['end_time'] ?? '';
    final subName = p['subject_name'] ?? '—';
    final subCode = p['subject_code'] ?? '';
    final isLab = p['is_lab_block'] == true;
    final status = p['status'] ?? 'UPCOMING';

    final isSubstituted = p['is_substituted'] == true;
    final effectiveFaculty = p['effective_faculty_name'] ?? 'Faculty';
    final origFaculty = p['original_faculty_name'] ?? '';

    final isRelocated = p['is_relocated'] == true;
    final effectiveVenue = p['effective_venue'] ?? 'Unassigned';
    final origVenue = p['original_venue'] ?? '';
    final relocationReason = p['relocation_reason'] ?? '';

    final classGroup = '${p['dept']} · Sem ${p['semester']}-${p['section']}';

    Color statusColor = Colors.grey;
    String statusLabel = 'UPCOMING';
    if (status == 'LIVE') {
      statusColor = const Color(0xFF10B981);
      statusLabel = 'LIVE NOW';
    } else if (status == 'COMPLETED') {
      statusColor = Colors.blueGrey;
      statusLabel = 'COMPLETED';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: status == 'LIVE'
              ? const Color(0xFF10B981)
              : isDark
                  ? Colors.white12
                  : Colors.grey.shade200,
          width: status == 'LIVE' ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Period Header + Status + Timing
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (isLab ? Colors.purple : AdminColors.primary).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Period $pNum',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: isLab ? Colors.purple : AdminColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (startTime.isNotEmpty && endTime.isNotEmpty)
                Text(
                  '$startTime – $endTime',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white60 : AdminColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (status == 'LIVE') ...[
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Color(0xFF10B981),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                    ],
                    Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Row 2: Subject Info
          Row(
            children: [
              Expanded(
                child: Text(
                  subName,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: isDark ? Colors.white : AdminColors.textPrimary,
                  ),
                ),
              ),
              if (subCode.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    subCode,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 4),
          Text(
            classGroup,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white60 : AdminColors.textSecondary,
            ),
          ),

          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),

          // Row 3: Faculty & Venue with Substitution / Relocation indicators
          Row(
            children: [
              // Faculty
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      isSubstituted ? Icons.published_with_changes_rounded : Icons.person_outline_rounded,
                      size: 16,
                      color: isSubstituted ? Colors.amber.shade800 : AdminColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            effectiveFaculty,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSubstituted ? FontWeight.bold : FontWeight.w500,
                              color: isSubstituted ? Colors.amber.shade900 : null,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (isSubstituted)
                            Text(
                              'Alternate for $origFaculty',
                              style: TextStyle(fontSize: 10, color: Colors.amber.shade800),
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // Venue
              Row(
                children: [
                  Icon(
                    isRelocated ? Icons.edit_location_alt_rounded : Icons.meeting_room_outlined,
                    size: 16,
                    color: isRelocated ? const Color(0xFF2563EB) : AdminColors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        effectiveVenue,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isRelocated ? FontWeight.bold : FontWeight.w500,
                          color: isRelocated ? const Color(0xFF2563EB) : null,
                        ),
                      ),
                      if (isRelocated)
                        Text(
                          'From $origVenue',
                          style: const TextStyle(fontSize: 10, color: Color(0xFF2563EB)),
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),

          if (isRelocated && relocationReason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Reason: $relocationReason',
              style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Color(0xFF2563EB)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHolidayCard(bool isDark, String title, String reason) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.grey.shade200,
        ),
      ),
      child: Center(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.beach_access_rounded, size: 36, color: Colors.red),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: isDark ? Colors.white : AdminColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              reason.isNotEmpty ? reason : 'No classes scheduled on this holiday.',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white60 : AdminColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyCard(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.grey.shade200,
        ),
      ),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.event_available_rounded,
              size: 40,
              color: isDark ? Colors.white30 : Colors.grey.shade400,
            ),
            const SizedBox(height: 10),
            Text(
              'No Scheduled Classes for this Date',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: isDark ? Colors.white70 : AdminColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'There are no instructional timetable periods allocated on this day.',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white38 : AdminColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
