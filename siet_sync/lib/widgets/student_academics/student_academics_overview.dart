import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/admin_theme.dart';
import '../../widgets/admin_design_system.dart';

class StudentAcademicsOverview extends StatelessWidget {
  final Map<String, dynamic> stats;
  final Map<String, dynamic> settings;
  final List<dynamic> batches;
  final bool isLoading;
  final VoidCallback onRefresh;
  final VoidCallback onGoToRanges;
  final VoidCallback onGoToCalendar;
  final VoidCallback onGoToBatches;
  final VoidCallback onGoToPolicies;
  final VoidCallback onAddHoliday;

  const StudentAcademicsOverview({
    super.key,
    required this.stats,
    required this.settings,
    required this.batches,
    required this.isLoading,
    required this.onRefresh,
    required this.onGoToRanges,
    required this.onGoToCalendar,
    required this.onGoToBatches,
    required this.onGoToPolicies,
    required this.onAddHoliday,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 960;

    final String activeYear = stats['active_academic_year'] ?? settings['active_academic_year'] ?? '2025-2026';
    final int totalStudents = stats['total_students'] ?? 0;
    final int totalDepts = stats['total_departments'] ?? 0;
    final int totalWorkingDays = stats['total_working_days'] ?? 0;
    final int workingDaysElapsed = stats['working_days_elapsed'] ?? 0;
    final int totalHolidays = stats['total_holidays'] ?? 0;
    final double minAtt = (stats['attendance_min_percentage'] ?? 75.0).toDouble();
    final List<dynamic> upcomingHolidays = stats['upcoming_holidays'] ?? [];
    final List<dynamic> milestones = stats['milestones'] ?? settings['milestones'] ?? [];

    final double progress = totalWorkingDays > 0
        ? (workingDaysElapsed / totalWorkingDays).clamp(0.0, 1.0)
        : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Hero Banner Card
        AdminGradientCard(
          gradientColors: const [Color(0xFF4F46E5), Color(0xFF7C3AED), Color(0xFF2563EB)],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                    ),
                    child: const Icon(Icons.school_rounded, color: Colors.white, size: 32),
                  ),
                  const SizedBox(width: 16),
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
                              'Academic Year $activeYear',
                              style: GoogleFonts.inter(
                                fontSize: isWide ? 24 : 18,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: -0.5,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AdminColors.success.withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  const Text(
                                    'ACTIVE TERM',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Comprehensive Student Academic Range, Holiday Calendar & Batch Lifecycle System',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isWide)
                    OutlinedButton.icon(
                      onPressed: onAddHoliday,
                      icon: const Icon(Icons.event_available_rounded, size: 16, color: Colors.white),
                      label: const Text('Add Holiday', style: TextStyle(color: Colors.white)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              // Working Days Progress Bar
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Instructional Days Progress: $workingDaysElapsed of $totalWorkingDays Days Elapsed',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${(progress * 100).toStringAsFixed(1)}%',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 10,
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // 4 KPI Metric Cards
        LayoutBuilder(
          builder: (context, constraints) {
            final is4Col = constraints.maxWidth >= 800;
            final is2Col = constraints.maxWidth >= 460;
            final double cardWidth = is4Col
                ? (constraints.maxWidth - 3 * 16) / 4
                : (is2Col ? (constraints.maxWidth - 16) / 2 : constraints.maxWidth);
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _buildKpiCard(
                  width: cardWidth,
                  title: 'Total Enrolled Students',
                  value: '$totalStudents',
                  subtitle: '$totalDepts Departments',
                  icon: Icons.people_alt_rounded,
                  accentColor: const Color(0xFF4F46E5),
                  isDark: isDark,
                  onTap: onGoToBatches,
                ),
                _buildKpiCard(
                  width: cardWidth,
                  title: 'Target Working Days',
                  value: '$totalWorkingDays',
                  subtitle: '$workingDaysElapsed Completed',
                  icon: Icons.calendar_today_rounded,
                  accentColor: const Color(0xFF059669),
                  isDark: isDark,
                  onTap: onGoToRanges,
                ),
                _buildKpiCard(
                  width: cardWidth,
                  title: 'Academic Holidays',
                  value: '$totalHolidays',
                  subtitle: 'Includes Sundays & Festivals',
                  icon: Icons.beach_access_rounded,
                  accentColor: const Color(0xFFE11D48),
                  isDark: isDark,
                  onTap: onGoToCalendar,
                ),
                _buildKpiCard(
                  width: cardWidth,
                  title: 'Min Attendance Policy',
                  value: '${minAtt.toStringAsFixed(0)}%',
                  subtitle: 'Exam Eligibility Cutoff',
                  icon: Icons.verified_user_rounded,
                  accentColor: const Color(0xFFD97706),
                  isDark: isDark,
                  onTap: onGoToPolicies,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),

        // Lower Two Columns: Upcoming Holidays & Academic Milestones
        if (isWide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: _buildUpcomingHolidaysCard(upcomingHolidays, isDark),
              ),
              const SizedBox(width: 20),
              Expanded(
                flex: 7,
                child: _buildAcademicMilestonesCard(milestones, isDark),
              ),
            ],
          )
        else ...[
          _buildUpcomingHolidaysCard(upcomingHolidays, isDark),
          const SizedBox(height: 20),
          _buildAcademicMilestonesCard(milestones, isDark),
        ],

        const SizedBox(height: 24),
        // Active Batches Grid Preview
        _buildBatchesOverviewCard(batches, isDark),
      ],
    );
  }

  Widget _buildKpiCard({
    required double width,
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: width,
      child: AdminCard(
        onTap: onTap,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: isDark ? 0.2 : 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: accentColor, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AdminTextStyles.labelSm(isDark).copyWith(
                      color: AdminColors.getTextSecondary(isDark),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AdminColors.getTextPrimary(isDark),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AdminTextStyles.labelSm(isDark).copyWith(
                      fontSize: 11,
                      color: accentColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUpcomingHolidaysCard(List<dynamic> holidays, bool isDark) {
    return AdminCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AdminColors.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.event_note_rounded, color: AdminColors.danger, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Upcoming Holidays',
                        style: AdminTextStyles.titleMd(isDark),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onGoToCalendar,
                child: const Text('View Calendar', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (holidays.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              alignment: Alignment.center,
              child: Column(
                children: [
                  Icon(Icons.calendar_today_outlined, size: 36, color: AdminColors.getTextMuted(isDark)),
                  const SizedBox(height: 8),
                  Text('No upcoming holidays scheduled', style: AdminTextStyles.bodySm(isDark)),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: holidays.length,
              separatorBuilder: (context, index) => Divider(color: AdminColors.getBorder(isDark), height: 16),
              itemBuilder: (context, i) {
                final h = holidays[i];
                final String dateStr = h['date'] ?? '';
                final String title = h['title'] ?? 'Holiday';
                final String category = h['category'] ?? 'Holiday';
                final bool isSun = h['is_sunday'] == true;

                return Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: (isSun ? Colors.grey : AdminColors.danger).withValues(alpha: isDark ? 0.2 : 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: (isSun ? Colors.grey : AdminColors.danger).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        dateStr,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isSun ? Colors.grey.shade400 : AdminColors.danger,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AdminColors.getTextPrimary(isDark),
                            ),
                          ),
                          Text(
                            category,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: AdminColors.getTextSecondary(isDark),
                            ),
                          ),
                        ],
                      ),
                    ),
                    AdminBadge(
                      label: isSun ? 'Sunday' : 'Holiday',
                      color: isSun ? Colors.grey : AdminColors.danger,
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildAcademicMilestonesCard(List<dynamic> milestones, bool isDark) {
    return AdminCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AdminColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.flag_rounded, color: AdminColors.primary, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Semester Milestones & Exam Windows',
                        style: AdminTextStyles.titleMd(isDark),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onGoToRanges,
                child: const Text('Configure Ranges', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (milestones.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              alignment: Alignment.center,
              child: Text('No academic milestones configured yet.', style: AdminTextStyles.bodySm(isDark)),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: milestones.length,
              separatorBuilder: (context, index) => Divider(color: AdminColors.getBorder(isDark), height: 16),
              itemBuilder: (context, i) {
                final m = milestones[i];
                final String name = m['name'] ?? 'Milestone';
                final String start = m['start'] ?? m['date'] ?? '';
                final String end = m['end'] ?? '';
                final String cat = m['category'] ?? 'Academic';

                return Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AdminColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.event_available_rounded, color: AdminColors.primary, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AdminColors.getTextPrimary(isDark),
                            ),
                          ),
                          Text(
                            end.isNotEmpty ? '$start  →  $end' : start,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: AdminColors.getTextSecondary(isDark),
                            ),
                          ),
                        ],
                      ),
                    ),
                    AdminBadge(label: cat, color: AdminColors.primary),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildBatchesOverviewCard(List<dynamic> batchesList, bool isDark) {
    return AdminCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AdminColors.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.groups_rounded, color: AdminColors.success, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Batch Lifecycle & Semester Mapping',
                        style: AdminTextStyles.titleMd(isDark),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: onGoToBatches,
                icon: const Icon(Icons.upgrade_rounded, size: 16),
                label: const Text('Promote Batches'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AdminColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (batchesList.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              alignment: Alignment.center,
              child: Text('No batches found.', style: AdminTextStyles.bodySm(isDark)),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final isW = constraints.maxWidth >= 750;
                final isTablet = constraints.maxWidth >= 500;
                final double itemWidth = isW
                    ? (constraints.maxWidth - 3 * 12) / 4
                    : (isTablet ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth);

                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: batchesList.map((b) {
                    final String batchName = b['batch'] ?? '';
                    final int count = b['student_count'] ?? 0;
                    final int year = b['year_of_study'] ?? 1;
                    final int sem = b['semester'] ?? 1;
                    final String status = b['status'] ?? 'active';

                    return SizedBox(
                      width: itemWidth,
                      child: Container(
                        padding: const EdgeInsets.all(14),
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
                                    batchName,
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: AdminColors.getTextPrimary(isDark),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                AdminBadge(
                                  label: status.toUpperCase(),
                                  color: status == 'active' ? AdminColors.success : Colors.grey,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Year $year • Semester $sem',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AdminColors.primary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$count Students Enrolled',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: AdminColors.getTextSecondary(isDark),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
        ],
      ),
    );
  }
}
