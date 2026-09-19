import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

/// A reusable donut-style pie chart widget for daily attendance breakdown.
/// Shows four slices: Full Day (green), Half Day (amber), Absent (red), On Leave (violet).
/// Used across HOD, Admin, Staff, and Other Staff dashboard panels.
class AttendancePieChart extends StatefulWidget {
  /// Count of full-day present records.
  final int fullDay;

  /// Count of half-day records.
  final int halfDay;

  /// Count of absent records.
  final int absent;

  /// Count of on-leave records.
  final int onLeave;

  /// Optional override for center label (defaults to "Today").
  final String centerLabel;

  /// Whether to show the legend row below the chart.
  final bool showLegend;

  /// Radius of the chart hole in the donut.
  final double centerSpaceRadius;

  const AttendancePieChart({
    super.key,
    required this.fullDay,
    required this.halfDay,
    required this.absent,
    required this.onLeave,
    this.centerLabel = 'Today',
    this.showLegend = true,
    this.centerSpaceRadius = 42,
  });

  @override
  State<AttendancePieChart> createState() => _AttendancePieChartState();
}

class _AttendancePieChartState extends State<AttendancePieChart>
    with SingleTickerProviderStateMixin {
  int _touchedIndex = -1;
  late AnimationController _animController;

  static const Color _fullDayColor = Color(0xFF10B981); // emerald green
  static const Color _halfDayColor = Color(0xFFF59E0B); // amber
  static const Color _absentColor = Color(0xFFEF4444);  // red
  static const Color _leaveColor = Color(0xFF8B5CF6);   // violet

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(AttendancePieChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fullDay != widget.fullDay ||
        oldWidget.halfDay != widget.halfDay ||
        oldWidget.absent != widget.absent ||
        oldWidget.onLeave != widget.onLeave) {
      _animController.forward(from: 0);
    }
  }

  List<PieChartSectionData> _buildSections(bool isDark) {
    final total = widget.fullDay + widget.halfDay + widget.absent + widget.onLeave;

    // If all zero, show a grey placeholder slice.
    if (total == 0) {
      return [
        PieChartSectionData(
          value: 1,
          color: isDark ? Colors.white12 : Colors.grey.shade200,
          radius: 30,
          title: '',
          showTitle: false,
        ),
      ];
    }

    final data = [
      _SliceData(index: 0, value: widget.fullDay.toDouble(), color: _fullDayColor, label: 'Full'),
      _SliceData(index: 1, value: widget.halfDay.toDouble(), color: _halfDayColor, label: 'Half'),
      _SliceData(index: 2, value: widget.absent.toDouble(), color: _absentColor, label: 'Absent'),
      _SliceData(index: 3, value: widget.onLeave.toDouble(), color: _leaveColor, label: 'Leave'),
    ];

    return data
        .where((d) => d.value > 0)
        .map((d) {
          final isTouched = _touchedIndex == d.index;
          final pct = (d.value / total * 100).toStringAsFixed(0);
          return PieChartSectionData(
            value: d.value,
            color: d.color,
            radius: isTouched ? 36 : 30,
            title: isTouched ? '$pct%' : '',
            titleStyle: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            showTitle: isTouched,
          );
        })
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final total = widget.fullDay + widget.halfDay + widget.absent + widget.onLeave;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 120,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sections: _buildSections(isDark),
                  centerSpaceRadius: widget.centerSpaceRadius,
                  sectionsSpace: 3,
                  pieTouchData: PieTouchData(
                    touchCallback: (FlTouchEvent event, pieTouchResponse) {
                      setState(() {
                        if (!event.isInterestedForInteractions ||
                            pieTouchResponse == null ||
                            pieTouchResponse.touchedSection == null) {
                          _touchedIndex = -1;
                          return;
                        }
                        _touchedIndex =
                            pieTouchResponse.touchedSection!.touchedSectionIndex;
                      });
                    },
                  ),
                  startDegreeOffset: -90,
                ),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeInOutCubic,
              ),
              // Center text inside the donut hole
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    total == 0 ? '—' : total.toString(),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  Text(
                    widget.centerLabel,
                    style: TextStyle(
                      fontSize: 9,
                      color: isDark ? Colors.white54 : Colors.black45,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (widget.showLegend) ...[
          const SizedBox(height: 10),
          _buildLegend(isDark),
        ],
      ],
    );
  }

  Widget _buildLegend(bool isDark) {
    final items = [
      _LegendItem(color: _fullDayColor, label: 'Full', count: widget.fullDay),
      _LegendItem(color: _halfDayColor, label: 'Half', count: widget.halfDay),
      _LegendItem(color: _absentColor, label: 'Absent', count: widget.absent),
      _LegendItem(color: _leaveColor, label: 'Leave', count: widget.onLeave),
    ];

    return Wrap(
      spacing: 10,
      runSpacing: 4,
      alignment: WrapAlignment.center,
      children: items.map((item) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: item.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '${item.label}: ${item.count}',
              style: TextStyle(
                fontSize: 10,
                color: isDark ? Colors.white60 : Colors.black54,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        );
      }).toList(),
    );
  }
}

class _SliceData {
  final int index;
  final double value;
  final Color color;
  final String label;
  const _SliceData({required this.index, required this.value, required this.color, required this.label});
}

class _LegendItem {
  final Color color;
  final String label;
  final int count;
  const _LegendItem({required this.color, required this.label, required this.count});
}
