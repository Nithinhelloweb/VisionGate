import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/admin_theme.dart';
import '../../widgets/admin_design_system.dart';

class StudentHolidayCalendarView extends StatefulWidget {
  final List<Map<String, dynamic>> calendarList;
  final Map<String, dynamic> calendarStats;
  final Map<String, dynamic> holidayOverrides;
  final Function(String date, String status, String title, String category, String reason) onSetOverride;
  final Function(String startDate, String endDate, String status, String title, String category, String reason) onSetRangeOverride;
  final Function(String date) onDeleteOverride;
  final VoidCallback onRefresh;
  final bool isLoading;

  const StudentHolidayCalendarView({
    super.key,
    required this.calendarList,
    required this.calendarStats,
    required this.holidayOverrides,
    required this.onSetOverride,
    required this.onSetRangeOverride,
    required this.onDeleteOverride,
    required this.onRefresh,
    this.isLoading = false,
  });

  @override
  State<StudentHolidayCalendarView> createState() => _StudentHolidayCalendarViewState();
}

class _StudentHolidayCalendarViewState extends State<StudentHolidayCalendarView> {
  DateTime _currentMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  bool _isGridView = true;
  String _searchQuery = '';
  String _selectedCategory = 'ALL';

  final List<String> _categories = [
    'ALL',
    'National',
    'Festival',
    'Vacation',
    'Exam',
    'Institutional',
    'Emergency',
  ];

  void _nextMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 1);
    });
  }

  void _prevMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1);
    });
  }

  String _formatDate(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  String _monthName(int m) {
    const names = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return names[m - 1];
  }

  Future<void> _openDayEditDialog(DateTime date, Map<String, dynamic>? existingDay) async {
    final dateStr = _formatDate(date);
    final isSun = date.weekday == DateTime.sunday;
    final String currentStatus = existingDay?['status'] ?? (isSun ? 'holiday' : 'working_day');
    final String currentTitle = existingDay?['title'] ?? (isSun ? 'Sunday' : 'Instructional Working Day');
    final String currentCategory = existingDay?['category'] ?? (isSun ? 'Weekend' : 'Institutional');
    final String currentReason = existingDay?['reason'] ?? '';
    final bool hasOverride = widget.holidayOverrides.containsKey(dateStr);

    String status = currentStatus;
    String category = currentCategory;
    final titleCtrl = TextEditingController(text: currentTitle == 'Instructional Working Day' || currentTitle == 'Sunday' ? '' : currentTitle);
    final reasonCtrl = TextEditingController(text: currentReason);

    final isDark = Theme.of(context).brightness == Brightness.dark;

    await showDialog<String>(
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
                  color: (status == 'holiday' ? AdminColors.danger : AdminColors.success).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  status == 'holiday' ? Icons.beach_access_rounded : Icons.check_circle_rounded,
                  color: status == 'holiday' ? AdminColors.danger : AdminColors.success,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dateStr,
                      style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    Text(
                      '${_monthName(date.month)} ${date.day}, ${date.year} (${_getDayName(date.weekday)})',
                      style: AdminTextStyles.labelSm(isDark),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Day Classification', style: AdminTextStyles.labelSm(isDark)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle_outline_rounded, size: 16),
                              SizedBox(width: 6),
                              Text('Working Day'),
                            ],
                          ),
                          selected: status == 'working_day',
                          selectedColor: AdminColors.success.withValues(alpha: 0.2),
                          onSelected: (v) {
                            if (v) setDlgState(() => status = 'working_day');
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ChoiceChip(
                          label: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.beach_access_rounded, size: 16),
                              SizedBox(width: 6),
                              Text('Holiday'),
                            ],
                          ),
                          selected: status == 'holiday',
                          selectedColor: AdminColors.danger.withValues(alpha: 0.2),
                          onSelected: (v) {
                            if (v) setDlgState(() => status = 'holiday');
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: ['National', 'Festival', 'Vacation', 'Exam', 'Institutional', 'Emergency'].contains(category)
                        ? category
                        : 'Institutional',
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Institutional', child: Text('Institutional / Academic', overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(value: 'Festival', child: Text('Festival Holiday', overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(value: 'National', child: Text('National Public Holiday', overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(value: 'Vacation', child: Text('Vacation / Term Break', overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(value: 'Exam', child: Text('Exam Preparation / Study Holiday', overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(value: 'Emergency', child: Text('Emergency / Weather Holiday', overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) {
                      if (v != null) setDlgState(() => category = v);
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Holiday / Event Title',
                      hintText: 'e.g. Pongal Celebration, Internal Review',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.title_rounded),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: reasonCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Reason / Description (Optional)',
                      hintText: 'Add context or official order reference',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (hasOverride) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, size: 16, color: Colors.amber),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'This date has a custom override applied.',
                              style: TextStyle(fontSize: 11, color: Colors.amber, fontWeight: FontWeight.bold),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              widget.onDeleteOverride(dateStr);
                              Navigator.pop(ctx);
                            },
                            child: const Text('Reset', style: TextStyle(color: AdminColors.danger, fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                  ],
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
                backgroundColor: status == 'holiday' ? AdminColors.danger : AdminColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                widget.onSetOverride(
                  dateStr,
                  status,
                  titleCtrl.text.trim().isEmpty
                      ? (status == 'holiday' ? 'Holiday' : 'Instructional Day')
                      : titleCtrl.text.trim(),
                  category,
                  reasonCtrl.text.trim(),
                );
                Navigator.pop(ctx, 'saved');
              },
              child: const Text('Apply Status'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openRangeVacationDialog() async {
    DateTime? startDate = _currentMonth;
    DateTime? endDate = _currentMonth.add(const Duration(days: 7));
    String category = 'Vacation';
    String status = 'holiday';
    final titleCtrl = TextEditingController(text: 'Semester Break / Vacation');
    final reasonCtrl = TextEditingController();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          final count = (startDate != null && endDate != null && !startDate!.isAfter(endDate!))
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
                    color: AdminColors.danger.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.date_range_rounded, color: AdminColors.danger, size: 22),
                ),
                const SizedBox(width: 12),
                Text(
                  'Bulk Holiday / Vacation Range',
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ],
            ),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Apply holiday or working day overrides across consecutive days (e.g. Winter Break, Pongal Holidays).',
                      style: AdminTextStyles.labelSm(isDark),
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
                              if (picked != null) {
                                setDlgState(() => startDate = picked);
                              }
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'From Date',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.calendar_today_rounded),
                              ),
                              child: Text(startDate != null ? _formatDate(startDate!) : 'Select Date'),
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
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'To Date',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.event_rounded),
                              ),
                              child: Text(endDate != null ? _formatDate(endDate!) : 'Select Date'),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AdminColors.primarySoft,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Targeting $count consecutive calendar days',
                        style: const TextStyle(fontSize: 12, color: AdminColors.primary, fontWeight: FontWeight.w600),
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
                        DropdownMenuItem(value: 'Vacation', child: Text('Vacation / Term Break', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'Festival', child: Text('Festival Celebration', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'Exam', child: Text('Examination Period', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'Institutional', child: Text('Institutional Event', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'Emergency', child: Text('Emergency Weather Closure', overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) {
                        if (v != null) setDlgState(() => category = v);
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Title / Event Label',
                        hintText: 'e.g. Winter Semester Break',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: reasonCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Reason (Optional)',
                        hintText: 'Official academic schedule order',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AdminColors.danger,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  if (startDate == null || endDate == null || startDate!.isAfter(endDate!)) {
                    return;
                  }
                  widget.onSetRangeOverride(
                    _formatDate(startDate!),
                    _formatDate(endDate!),
                    status,
                    titleCtrl.text.trim().isEmpty ? 'Vacation' : titleCtrl.text.trim(),
                    category,
                    reasonCtrl.text.trim(),
                  );
                  Navigator.pop(ctx, true);
                },
                child: const Text('Apply Multi-Day Holiday'),
              ),
            ],
          );
        },
      ),
    );
  }

  String _getDayName(int weekday) {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return days[weekday - 1];
  }

  Color _getCategoryColor(String cat) {
    final l = cat.toLowerCase();
    if (l.contains('national')) return const Color(0xFFDC2626);
    if (l.contains('festival')) return const Color(0xFFD97706);
    if (l.contains('vacation')) return const Color(0xFF0284C7);
    if (l.contains('exam')) return const Color(0xFF7C3AED);
    if (l.contains('emergency')) return const Color(0xFFE11D48);
    if (l.contains('weekend')) return Colors.grey;
    return AdminColors.primary;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Filter calendar items
    final monthPrefix = '${_currentMonth.year.toString().padLeft(4, '0')}-${_currentMonth.month.toString().padLeft(2, '0')}';
    final monthItems = widget.calendarList.where((item) {
      final date = item['date']?.toString() ?? '';
      return date.startsWith(monthPrefix);
    }).toList();

    // Stats for current month
    final int monthTotal = monthItems.length;
    final int monthWorking = monthItems.where((i) => i['status'] == 'working_day').length;
    final int monthHolidays = monthItems.where((i) => i['status'] == 'holiday').length;
    final int monthSundays = monthItems.where((i) => i['is_sunday'] == true).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top Month Switcher & Action Toolbar
        AdminCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 650;

                  final monthSwitcher = Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: _prevMonth,
                        icon: const Icon(Icons.chevron_left_rounded),
                        tooltip: 'Previous Month',
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${_monthName(_currentMonth.month)} ${_currentMonth.year}',
                        style: GoogleFonts.inter(
                          fontSize: isNarrow ? 15 : 18,
                          fontWeight: FontWeight.w800,
                          color: AdminColors.getTextPrimary(isDark),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        onPressed: _nextMonth,
                        icon: const Icon(Icons.chevron_right_rounded),
                        tooltip: 'Next Month',
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () => setState(() => _currentMonth = DateTime(DateTime.now().year, DateTime.now().month, 1)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Today', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  );

                  final viewActions = Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: AdminColors.getCardTinted(isDark),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AdminColors.getBorder(isDark)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(Icons.grid_view_rounded, size: 18, color: _isGridView ? AdminColors.primary : Colors.grey),
                              onPressed: () => setState(() => _isGridView = true),
                              tooltip: 'Monthly Grid View',
                            ),
                            IconButton(
                              icon: Icon(Icons.format_list_bulleted_rounded, size: 18, color: !_isGridView ? AdminColors.primary : Colors.grey),
                              onPressed: () => setState(() => _isGridView = false),
                              tooltip: 'List View',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _openRangeVacationDialog,
                        icon: const Icon(Icons.beach_access_rounded, size: 16, color: AdminColors.danger),
                        label: const Text('Add Vacation Range', style: TextStyle(color: AdminColors.danger)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AdminColors.danger),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  );

                  if (isNarrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: monthSwitcher,
                        ),
                        const SizedBox(height: 10),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: viewActions,
                        ),
                      ],
                    );
                  }

                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      monthSwitcher,
                      viewActions,
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              // Search and Filter Strip
              LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 500;
                  final searchField = TextField(
                    onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
                    decoration: const InputDecoration(
                      hintText: 'Search holiday title or reason...',
                      prefixIcon: Icon(Icons.search_rounded, size: 18),
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  );

                  final categoryDropdown = DropdownButtonFormField<String>(
                    initialValue: _selectedCategory,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _selectedCategory = v);
                    },
                  );

                  if (isNarrow) {
                    return Column(
                      children: [
                        searchField,
                        const SizedBox(height: 10),
                        categoryDropdown,
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(child: searchField),
                      const SizedBox(width: 12),
                      SizedBox(width: 160, child: categoryDropdown),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Monthly Stats Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AdminColors.getCard(isDark),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AdminColors.getBorder(isDark)),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: _buildMonthStat('Calendar Days', '$monthTotal', Colors.blueGrey, isDark),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: _buildMonthStat('Instructional Days', '$monthWorking', AdminColors.success, isDark),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: _buildMonthStat('Total Holidays', '$monthHolidays', AdminColors.danger, isDark),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: _buildMonthStat('Sundays', '$monthSundays', Colors.grey, isDark),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),

        // Content Area: Grid View or List View
        if (_isGridView)
          _buildMonthGrid(isDark)
        else
          _buildListView(monthItems, isDark),
      ],
    );
  }

  Widget _buildMonthStat(String label, String value, Color color, bool isDark) {
    return Column(
      children: [
        Text(value, style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: AdminTextStyles.labelSm(isDark).copyWith(fontSize: 11)),
      ],
    );
  }

  Widget _buildMonthGrid(bool isDark) {
    final year = _currentMonth.year;
    final month = _currentMonth.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final firstDayWeekday = DateTime(year, month, 1).weekday; // 1 = Mon, 7 = Sun

    // Create lookup map for this month
    final Map<String, Map<String, dynamic>> dateLookup = {};
    for (var item in widget.calendarList) {
      if (item['date'] != null) {
        dateLookup[item['date']] = item;
      }
    }

    final List<Widget> dayHeaders = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].map((d) {
      final isSun = d == 'Sun';
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        child: Text(
          d,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isSun ? AdminColors.danger : AdminColors.getTextSecondary(isDark),
          ),
        ),
      );
    }).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;
        final double cellAspect = isMobile ? 0.70 : 1.15;
        final double spacing = isMobile ? 4.0 : 8.0;

        final List<Widget> gridCells = [];

        // Empty offset cells before day 1
        for (int i = 1; i < firstDayWeekday; i++) {
          gridCells.add(
            Container(
              decoration: BoxDecoration(
                color: AdminColors.getCardTinted(isDark).withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          );
        }

        // Days 1 .. daysInMonth
        for (int day = 1; day <= daysInMonth; day++) {
          final date = DateTime(year, month, day);
          final dateStr = _formatDate(date);
          final item = dateLookup[dateStr];
          final isSunday = date.weekday == DateTime.sunday;
          final String status = item?['status'] ?? (isSunday ? 'holiday' : 'working_day');
          final String title = item?['title'] ?? (isSunday ? 'Sunday' : 'Instructional Day');
          final String category = item?['category'] ?? (isSunday ? 'Weekend' : 'Institutional');
          final bool hasOverride = widget.holidayOverrides.containsKey(dateStr);
          final bool isToday = dateStr == _formatDate(DateTime.now());

          final Color catColor = _getCategoryColor(category);

          gridCells.add(
            InkWell(
              onTap: () => _openDayEditDialog(date, item),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: isMobile
                    ? const EdgeInsets.symmetric(horizontal: 3, vertical: 4)
                    : const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isToday
                      ? AdminColors.primary.withValues(alpha: isDark ? 0.25 : 0.1)
                      : AdminColors.getCard(isDark),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isToday
                        ? AdminColors.primary
                        : (hasOverride
                            ? Colors.amber.withValues(alpha: 0.8)
                            : AdminColors.getBorder(isDark)),
                    width: isToday || hasOverride ? 1.5 : 1.0,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '$day',
                          style: GoogleFonts.inter(
                            fontSize: isMobile ? 12 : 14,
                            fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                            color: isSunday ? AdminColors.danger : AdminColors.getTextPrimary(isDark),
                          ),
                        ),
                        if (hasOverride)
                          Container(
                            width: 5,
                            height: 5,
                            decoration: const BoxDecoration(
                              color: Colors.amber,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    if (status == 'holiday')
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(horizontal: isMobile ? 2 : 6, vertical: isMobile ? 2 : 3),
                        decoration: BoxDecoration(
                          color: catColor.withValues(alpha: isDark ? 0.25 : 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: isMobile ? 8 : 10,
                            fontWeight: FontWeight.bold,
                            color: catColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      )
                    else
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(horizontal: isMobile ? 2 : 6, vertical: isMobile ? 2 : 3),
                        decoration: BoxDecoration(
                          color: AdminColors.success.withValues(alpha: isDark ? 0.2 : 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Working',
                          style: TextStyle(
                            fontSize: isMobile ? 7.5 : 9,
                            fontWeight: FontWeight.w600,
                            color: AdminColors.success,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        }

        return AdminCard(
          padding: EdgeInsets.all(isMobile ? 10 : 16),
          child: Column(
            children: [
              Row(
                children: dayHeaders.map((h) => Expanded(child: h)).toList(),
              ),
              const SizedBox(height: 6),
              GridView.count(
                crossAxisCount: 7,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: spacing,
                mainAxisSpacing: spacing,
                childAspectRatio: cellAspect,
                children: gridCells,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildListView(List<dynamic> items, bool isDark) {
    var filtered = items.where((i) {
      if (_selectedCategory != 'ALL') {
        final cat = i['category']?.toString().toLowerCase() ?? '';
        if (!cat.contains(_selectedCategory.toLowerCase())) return false;
      }
      if (_searchQuery.isNotEmpty) {
        final t = (i['title']?.toString() ?? '').toLowerCase();
        final r = (i['reason']?.toString() ?? '').toLowerCase();
        if (!t.contains(_searchQuery) && !r.contains(_searchQuery)) return false;
      }
      return true;
    }).toList();

    if (filtered.isEmpty) {
      return AdminCard(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.event_busy_rounded, size: 40, color: AdminColors.getTextMuted(isDark)),
              const SizedBox(height: 8),
              Text('No days match your filter criteria.', style: AdminTextStyles.bodySm(isDark)),
            ],
          ),
        ),
      );
    }

    return AdminCard(
      padding: const EdgeInsets.all(16),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: filtered.length,
        separatorBuilder: (context, index) => Divider(color: AdminColors.getBorder(isDark), height: 12),
        itemBuilder: (context, i) {
          final item = filtered[i];
          final String dateStr = item['date'] ?? '';
          final String status = item['status'] ?? 'working_day';
          final String title = item['title'] ?? (status == 'holiday' ? 'Holiday' : 'Working Day');
          final String cat = item['category'] ?? (status == 'holiday' ? 'Holiday' : 'Instructional');
          final bool hasOverride = item['is_override'] == true;

          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: (status == 'holiday' ? AdminColors.danger : AdminColors.success).withValues(alpha: isDark ? 0.2 : 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                dateStr,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: status == 'holiday' ? AdminColors.danger : AdminColors.success,
                ),
              ),
            ),
            title: Row(
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                if (hasOverride) ...[
                  const SizedBox(width: 8),
                  const AdminBadge(label: 'OVERRIDE', color: Colors.amber),
                ],
              ],
            ),
            subtitle: Text(
              '$cat • ${item['day_of_week'] ?? ''}',
              style: AdminTextStyles.labelSm(isDark),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.edit_rounded, size: 18),
              tooltip: 'Edit Status',
              onPressed: () {
                final dt = DateTime.tryParse(dateStr);
                if (dt != null) _openDayEditDialog(dt, item);
              },
            ),
          );
        },
      ),
    );
  }
}
