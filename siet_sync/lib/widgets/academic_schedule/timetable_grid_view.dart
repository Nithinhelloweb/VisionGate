import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../../config/college_ip_config.dart';
import '../../theme/admin_theme.dart';
import 'period_timing_helper.dart';
import 'timetable_slot_dialog.dart';

class TimetableGridView extends StatelessWidget {
  final String token;
  final String dept;
  final String batch;
  final int semester;
  final String section;
  final List<PeriodSlotTiming> timeline;
  final List<Map<String, dynamic>> slots;
  final List<Map<String, dynamic>> facultyPool;
  final List<Map<String, dynamic>> subjectAllocations;
  final List<String> availableDepartments;
  final List<String> workingDays;
  final VoidCallback onSlotUpdated;

  const TimetableGridView({
    super.key,
    required this.token,
    required this.dept,
    required this.batch,
    required this.semester,
    required this.section,
    required this.timeline,
    required this.slots,
    required this.facultyPool,
    required this.subjectAllocations,
    this.availableDepartments = const [],
    required this.workingDays,
    required this.onSlotUpdated,
  });

  Map<String, dynamic>? _getSlot(String day, int periodNum) {
    return slots.cast<Map<String, dynamic>?>().firstWhere(
      (s) => s?['day_of_week']?.toString().toLowerCase() == day.toLowerCase() && (s?['period_number'] as num?)?.toInt() == periodNum,
      orElse: () => null,
    );
  }

  int _getScheduledHoursForSubject(String subjectCode) {
    return slots.where((s) => s['subject_code'] == subjectCode).length;
  }

  void _openSlotEditor(BuildContext context, String day, PeriodSlotTiming timing) {
    final slot = _getSlot(day, timing.periodNumber);
    showDialog(
      context: context,
      builder: (ctx) => TimetableSlotDialog(
        token: token,
        dept: dept,
        batch: batch,
        semester: semester,
        section: section,
        dayOfWeek: day,
        periodNumber: timing.periodNumber,
        periodTimeRange: '${timing.startTime} - ${timing.endTime}',
        initialSlot: slot,
        facultyPool: facultyPool,
        subjectAllocations: subjectAllocations,
        availableDepartments: availableDepartments,
        onSaved: onSlotUpdated,
      ),
    );
  }

  Future<void> _handleDayCopy(BuildContext context, String srcDay) async {
    final otherDays = workingDays.where((d) => d.toLowerCase() != srcDay.toLowerCase()).toList();
    if (otherDays.isEmpty) return;

    String targetDay = otherDays.first;

    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (c, setDState) => AlertDialog(
          title: Text('Copy $srcDay Schedule'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Duplicate all periods from $srcDay to:'),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: targetDay,
                items: otherDays.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                onChanged: (v) {
                  if (v != null) setDState(() => targetDay = v);
                },
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AdminColors.primary, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, targetDay),
              child: const Text('Copy Schedule'),
            ),
          ],
        ),
      ),
    );

    if (selected != null) {
      try {
        final res = await http.post(
          Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/academics/timetable/day/copy'),
          headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
          body: jsonEncode({
            'dept': dept,
            'batch': batch,
            'semester': semester,
            'section': section,
            'src_day': srcDay,
            'dst_day': selected,
          }),
        );
        if (res.statusCode == 200) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Copied $srcDay schedule to $selected!'), backgroundColor: AdminColors.success),
            );
          }
          onSlotUpdated();
        } else {
          final err = jsonDecode(res.body)['detail'] ?? 'Failed to copy day';
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $err'), backgroundColor: AdminColors.danger));
          }
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AdminColors.danger));
        }
      }
    }
  }

  Future<void> _handleDaySwap(BuildContext context, String dayA) async {
    final otherDays = workingDays.where((d) => d.toLowerCase() != dayA.toLowerCase()).toList();
    if (otherDays.isEmpty) return;

    String dayB = otherDays.first;

    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (c, setDState) => AlertDialog(
          title: Text('Swap $dayA Schedule'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Swap all period allocations between $dayA and:'),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: dayB,
                items: otherDays.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                onChanged: (v) {
                  if (v != null) setDState(() => dayB = v);
                },
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, dayB),
              child: const Text('Swap Days'),
            ),
          ],
        ),
      ),
    );

    if (selected != null) {
      try {
        final res = await http.post(
          Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/academics/timetable/day/swap'),
          headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
          body: jsonEncode({
            'dept': dept,
            'batch': batch,
            'semester': semester,
            'section': section,
            'day_a': dayA,
            'day_b': selected,
          }),
        );
        if (res.statusCode == 200) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Swapped schedule between $dayA and $selected!'), backgroundColor: AdminColors.success),
            );
          }
          onSlotUpdated();
        } else {
          final err = jsonDecode(res.body)['detail'] ?? 'Failed to swap';
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $err'), backgroundColor: AdminColors.danger));
          }
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AdminColors.danger));
        }
      }
    }
  }

  Future<void> _handleDayClear(BuildContext context, String day) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Clear $day Schedule?'),
        content: Text('Are you sure you want to clear all period slots for $day in $dept Sem $semester Sec $section?'),
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

    try {
      final res = await http.delete(
        Uri.parse(
          '${CollegeIPConfig.defaultURL}/api/v1/academics/timetable/day?dept=${Uri.encodeComponent(dept)}&batch=${Uri.encodeComponent(batch)}&semester=$semester&section=${Uri.encodeComponent(section)}&day_of_week=${Uri.encodeComponent(day)}',
        ),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Cleared all slots for $day.'), backgroundColor: AdminColors.success),
          );
        }
        onSlotUpdated();
      } else {
        final err = jsonDecode(res.body)['detail'] ?? 'Failed to clear day';
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $err'), backgroundColor: AdminColors.danger));
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AdminColors.danger));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
          // Weekly Hours Tracker Chips
          if (subjectAllocations.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 20, right: 20, top: 8, bottom: 4),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: AdminColors.primarySoft, borderRadius: BorderRadius.circular(6)),
                      child: Text(
                        'Weekly Hours Tracker:',
                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: AdminColors.primary),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ...subjectAllocations.map((alloc) {
                      final code = alloc['subject_code'] ?? '';
                      final targetHrs = (alloc['weekly_hours'] as num?)?.toInt() ?? 3;
                      final filledHrs = _getScheduledHoursForSubject(code);
                      final isComplete = filledHrs >= targetHrs;
                      final isLab = (alloc['subject_type'] ?? '').toString().toLowerCase().contains('lab');

                      return Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: isComplete
                              ? Colors.green.withValues(alpha: 0.12)
                              : (isDark ? const Color(0xFF1E293B) : Colors.grey[100]),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isComplete
                                ? Colors.green
                                : (isLab ? Colors.purple.withValues(alpha: 0.4) : AdminColors.getBorder(isDark)),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              code,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: isLab ? Colors.purple : AdminColors.getTextPrimary(isDark),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '$filledHrs/$targetHrs',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isComplete ? Colors.green[800] : AdminColors.getTextSecondary(isDark),
                              ),
                            ),
                            if (isComplete) ...[
                              const SizedBox(width: 4),
                              const Icon(Icons.check_circle_rounded, size: 12, color: Colors.green),
                            ],
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),

          // Timetable Matrix Grid
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Container(
                decoration: BoxDecoration(
                  color: AdminColors.getCard(isDark),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AdminColors.getBorder(isDark)),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: DataTable(
                  horizontalMargin: 12,
                  columnSpacing: 10,
                  headingRowHeight: 56,
                  dataRowMinHeight: 74,
                  dataRowMaxHeight: 74,
                  headingRowColor: WidgetStateProperty.all(isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
                  border: TableBorder(
                    horizontalInside: BorderSide(color: AdminColors.getBorder(isDark), width: 0.8),
                    verticalInside: BorderSide(color: AdminColors.getBorder(isDark), width: 0.8),
                  ),
                  columns: [
                    DataColumn(
                      label: Container(
                        width: 120,
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.only(left: 4),
                        child: Text('DAY / OPTIONS', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: AdminColors.primary)),
                      ),
                    ),
                    ...timeline.map((slot) {
                      final isBrk = slot.isBreak;
                      return DataColumn(
                        label: Container(
                          width: isBrk ? 70 : 130,
                          alignment: Alignment.center,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(slot.label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: isBrk ? Colors.amber[900] : AdminColors.getTextPrimary(isDark))),
                              Text('${slot.startTime} - ${slot.endTime}', style: GoogleFonts.inter(fontSize: 9, color: AdminColors.getTextMuted(isDark))),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                  rows: workingDays.map((day) {
                    return DataRow(
                      cells: [
                        DataCell(
                          Container(
                            width: 120,
                            alignment: Alignment.centerLeft,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    day,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, color: AdminColors.getTextPrimary(isDark)),
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  icon: Icon(Icons.more_vert_rounded, size: 16, color: AdminColors.getTextMuted(isDark)),
                                  tooltip: 'Day Actions for $day',
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  onSelected: (val) {
                                    if (val == 'copy') {
                                      _handleDayCopy(context, day);
                                    } else if (val == 'swap') {
                                      _handleDaySwap(context, day);
                                    } else if (val == 'clear') {
                                      _handleDayClear(context, day);
                                    }
                                  },
                                  itemBuilder: (ctx) => [
                                    PopupMenuItem(
                                      value: 'copy',
                                      child: Row(
                                        children: [
                                          const Icon(Icons.copy_all_rounded, size: 16, color: AdminColors.primary),
                                          const SizedBox(width: 8),
                                          Text('Copy $day to...', style: GoogleFonts.inter(fontSize: 12)),
                                        ],
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'swap',
                                      child: Row(
                                        children: [
                                          const Icon(Icons.swap_horiz_rounded, size: 16, color: Colors.teal),
                                          const SizedBox(width: 8),
                                          Text('Swap $day with...', style: GoogleFonts.inter(fontSize: 12)),
                                        ],
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'clear',
                                      child: Row(
                                        children: [
                                          const Icon(Icons.delete_sweep_rounded, size: 16, color: AdminColors.danger),
                                          const SizedBox(width: 8),
                                          Text('Clear $day', style: GoogleFonts.inter(fontSize: 12, color: AdminColors.danger)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        ...timeline.map((timing) {
                          if (timing.isBreak) {
                            return DataCell(
                              Container(
                                width: 70,
                                color: isDark ? const Color(0xFF292524) : const Color(0xFFFFFBEB),
                                alignment: Alignment.center,
                                child: RotatedBox(
                                  quarterTurns: 3,
                                  child: Text(timing.label, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.amber[800])),
                                ),
                              ),
                            );
                          }

                          final slot = _getSlot(day, timing.periodNumber);
                          final isAssigned = slot != null;

                          return DataCell(
                            InkWell(
                              onTap: () => _openSlotEditor(context, day, timing),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                width: 130,
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: isAssigned
                                      ? (slot['is_lab_block'] == true ? Colors.purple.withValues(alpha: 0.08) : AdminColors.primarySoft.withValues(alpha: 0.4))
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: isAssigned ? _buildSlotContent(slot, isDark) : _buildEmptySlot(isDark),
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
        ],
      );
  }

  Widget _buildSlotContent(Map<String, dynamic> slot, bool isDark) {
    final isHod = slot['is_hod'] == true;
    final isLab = slot['is_lab_block'] == true;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                slot['subject_code'] ?? '',
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: isLab ? Colors.purple[700] : AdminColors.primary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (slot['room_or_lab'] != null && (slot['room_or_lab'] as String).isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(color: Colors.blueGrey[100], borderRadius: BorderRadius.circular(4)),
                child: Text(slot['room_or_lab'], style: GoogleFonts.inter(fontSize: 8, fontWeight: FontWeight.w600, color: Colors.blueGrey[900])),
              ),
          ],
        ),
        Text(
          slot['subject_name'] ?? '',
          style: GoogleFonts.inter(fontSize: 10, color: AdminColors.getTextSecondary(isDark)),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Icon(isHod ? Icons.stars_rounded : Icons.person_rounded, size: 12, color: isHod ? Colors.amber[700] : AdminColors.getTextMuted(isDark)),
            const SizedBox(width: 3),
            Expanded(
              child: Text(
                '${slot['staff_name'] ?? slot['staff_reg_no']}${isHod ? ' [HOD]' : ''}',
                style: GoogleFonts.inter(fontSize: 9, fontWeight: isHod ? FontWeight.w700 : FontWeight.w500, color: isHod ? Colors.amber[900] : AdminColors.getTextPrimary(isDark)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEmptySlot(bool isDark) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          border: Border.all(color: AdminColors.getBorder(isDark), style: BorderStyle.solid),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(Icons.add_rounded, size: 14, color: AdminColors.getTextMuted(isDark)),
      ),
    );
  }
}
