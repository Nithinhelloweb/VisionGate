class PeriodSlotTiming {
  final String type; // 'period' or 'break'
  final int periodNumber;
  final String label;
  final String startTime;
  final String endTime;
  final String start24h;
  final String end24h;
  final int durationMins;

  bool get isBreak => type == 'break';

  const PeriodSlotTiming({
    required this.type,
    required this.periodNumber,
    required this.label,
    required this.startTime,
    required this.endTime,
    required this.start24h,
    required this.end24h,
    this.durationMins = 50,
  });

  factory PeriodSlotTiming.fromJson(Map<String, dynamic> json) {
    return PeriodSlotTiming(
      type: json['type']?.toString() ?? 'period',
      periodNumber: (json['period_number'] as num?)?.toInt() ?? 1,
      label: json['label']?.toString() ?? 'Period',
      startTime: json['start_time']?.toString() ?? '',
      endTime: json['end_time']?.toString() ?? '',
      start24h: json['start_24h']?.toString() ?? '',
      end24h: json['end_24h']?.toString() ?? '',
      durationMins: (json['duration_mins'] as num?)?.toInt() ?? 50,
    );
  }
}

class PeriodTimingHelper {
  static List<PeriodSlotTiming> computeTimeline({
    required String startTime,
    required int totalPeriods,
    required int periodDurationMins,
    required List<Map<String, dynamic>> breaks,
  }) {
    final parts = startTime.split(':');
    int startHour = int.tryParse(parts.isNotEmpty ? parts[0] : '8') ?? 8;
    int startMin = int.tryParse(parts.length > 1 ? parts[1] : '45') ?? 45;

    DateTime current = DateTime(2026, 1, 1, startHour, startMin);

    final Map<int, Map<String, dynamic>> breaksByPeriod = {};
    for (final b in breaks) {
      final afterP = (b['after_period'] as num?)?.toInt() ?? 0;
      if (afterP > 0) {
        breaksByPeriod[afterP] = b;
      }
    }

    final List<PeriodSlotTiming> timeline = [];

    for (int p = 1; p <= totalPeriods; p++) {
      final end = current.add(Duration(minutes: periodDurationMins));
      timeline.add(PeriodSlotTiming(
        type: 'period',
        periodNumber: p,
        label: 'Period $p',
        startTime: _formatTime(current),
        endTime: _formatTime(end),
        start24h: _format24h(current),
        end24h: _format24h(end),
        durationMins: periodDurationMins,
      ));
      current = end;

      if (breaksByPeriod.containsKey(p)) {
        final b = breaksByPeriod[p]!;
        final bDur = (b['duration_mins'] as num?)?.toInt() ?? 15;
        final bTitle = b['title']?.toString() ?? 'Break';
        final bEnd = current.add(Duration(minutes: bDur));

        timeline.add(PeriodSlotTiming(
          type: 'break',
          periodNumber: p,
          label: bTitle,
          startTime: _formatTime(current),
          endTime: _formatTime(bEnd),
          start24h: _format24h(current),
          end24h: _format24h(bEnd),
          durationMins: bDur,
        ));
        current = bEnd;
      }
    }

    return timeline;
  }

  static String _formatTime(DateTime dt) {
    int hour = dt.hour;
    final isPm = hour >= 12;
    if (hour > 12) hour -= 12;
    if (hour == 0) hour = 12;
    final min = dt.minute.toString().padLeft(2, '0');
    final period = isPm ? 'PM' : 'AM';
    return '$hour:$min $period';
  }

  static String _format24h(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
