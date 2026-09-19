import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/college_ip_config.dart';
import 'class_session_roll_sheet.dart';

String get _API => CollegeIPConfig.defaultURL;

/// Comprehensive Classroom Attendance Sessions Audit & History Widget
/// For Admin (College-wide) and HOD (Department-scoped).
class ClassSessionHistoryWidget extends StatefulWidget {
  final String token;
  final Map<String, dynamic> user;
  final bool isHod;

  const ClassSessionHistoryWidget({
    super.key,
    required this.token,
    required this.user,
    this.isHod = false,
  });

  @override
  State<ClassSessionHistoryWidget> createState() => _ClassSessionHistoryWidgetState();
}

class _ClassSessionHistoryWidgetState extends State<ClassSessionHistoryWidget> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _sessions = [];
  int _totalSessions = 0;

  DateTime _fromDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime _toDate = DateTime.now();
  String _selectedDept = 'ALL';
  final TextEditingController _searchCtrl = TextEditingController();

  final List<String> _departments = [
    'ALL', 'CSE', 'ECE', 'EEE', 'MECH', 'CIVIL', 'IT', 'AI&DS', 'BME'
  ];

  Map<String, String> get _headers => {
    'Authorization': widget.token.startsWith('Bearer ') ? widget.token : 'Bearer ${widget.token}',
    'Content-Type': 'application/json',
  };

  String get _hodDept => (widget.user['dept'] ?? widget.user['department'] ?? '').toString().trim();

  @override
  void initState() {
    super.initState();
    if (widget.isHod && _hodDept.isNotEmpty) {
      _selectedDept = _hodDept;
    }
    _fetchSessions();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _formatDate(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  Future<void> _fetchSessions() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final deptParam = (widget.isHod || _selectedDept != 'ALL') ? _selectedDept : '';
      final url = '$_API/api/v1/class-session/history?from_date=${_formatDate(_fromDate)}&to_date=${_formatDate(_toDate)}${deptParam.isNotEmpty ? '&dept=$deptParam' : ''}';

      final res = await http.get(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final List<dynamic> list = data['sessions'] ?? [];
        setState(() {
          _sessions = list.map((e) => Map<String, dynamic>.from(e)).toList();
          _totalSessions = data['total'] ?? _sessions.length;
          _isLoading = false;
        });
      } else {
        setState(() { _error = 'Server error ${res.statusCode}'; _isLoading = false; });
      }
    } catch (e) {
      setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  List<Map<String, dynamic>> get _filteredSessions {
    final q = _searchCtrl.text.toLowerCase().trim();
    if (q.isEmpty) return _sessions;
    return _sessions.where((s) {
      final sub = (s['subject_name'] ?? '').toLowerCase();
      final staff = (s['staff_name'] ?? '').toLowerCase();
      final staffRno = (s['staff_reg_no'] ?? '').toLowerCase();
      final dept = (s['dept'] ?? '').toLowerCase();
      return sub.contains(q) || staff.contains(q) || staffRno.contains(q) || dept.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Container(
      color: bgColor,
      child: Column(
        children: [
          // ── Header & Filter Bar ───────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              border: Border(bottom: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E3A8A).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.playlist_add_check_circle_rounded, color: Color(0xFF1E3A8A), size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.isHod ? '$_hodDept Class Attendance Sessions' : 'Classroom Attendance Sessions',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: textColor,
                              fontStyle: FontStyle.normal,
                            ),
                          ),
                          Text(
                            '$_totalSessions sessions recorded in selected date range',
                            style: TextStyle(fontSize: 12, color: subColor),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded),
                      tooltip: 'Refresh',
                      onPressed: _fetchSessions,
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // Date Filters + Dept Dropdown
                Row(
                  children: [
                    // From Date
                    Expanded(
                      child: _buildDateBtn(
                        label: 'From: ${_formatDate(_fromDate)}',
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _fromDate,
                            firstDate: DateTime(2024, 1, 1),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) {
                            setState(() => _fromDate = picked);
                            _fetchSessions();
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    // To Date
                    Expanded(
                      child: _buildDateBtn(
                        label: 'To: ${_formatDate(_toDate)}',
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _toDate,
                            firstDate: _fromDate,
                            lastDate: DateTime.now().add(const Duration(days: 1)),
                          );
                          if (picked != null) {
                            setState(() => _toDate = picked);
                            _fetchSessions();
                          }
                        },
                      ),
                    ),
                    if (!widget.isHod) ...[
                      const SizedBox(width: 8),
                      // Dept Dropdown
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedDept,
                            dropdownColor: cardBg,
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textColor),
                            items: _departments.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                            onChanged: (v) {
                              if (v != null) {
                                setState(() => _selectedDept = v);
                                _fetchSessions();
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 10),

                // Search Bar
                TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(fontSize: 13, color: textColor),
                  decoration: InputDecoration(
                    hintText: 'Search by subject, faculty name, or staff ID…',
                    hintStyle: TextStyle(fontSize: 13, color: subColor),
                    prefixIcon: Icon(Icons.search_rounded, size: 18, color: subColor),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),

          // ── Session Cards List ────────────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline_rounded, size: 40, color: Colors.red),
                            const SizedBox(height: 8),
                            Text(_error!, style: TextStyle(color: subColor)),
                            const SizedBox(height: 12),
                            FilledButton(onPressed: _fetchSessions, child: const Text('Retry')),
                          ],
                        ),
                      )
                    : _filteredSessions.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.event_note_rounded, size: 48, color: subColor.withOpacity(0.5)),
                                const SizedBox(height: 12),
                                Text('No class attendance sessions found', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: textColor)),
                                const SizedBox(height: 4),
                                Text('Try adjusting the date range or search query.', style: TextStyle(fontSize: 13, color: subColor)),
                              ],
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _filteredSessions.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (_, i) => _buildSessionCard(_filteredSessions[i], isDark, cardBg, textColor, subColor),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateBtn({required String label, required VoidCallback onTap}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.calendar_today_rounded, size: 14, color: Color(0xFF1E3A8A)),
            const SizedBox(width: 6),
            Flexible(child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionCard(
    Map<String, dynamic> sess,
    bool isDark,
    Color cardBg,
    Color textColor,
    Color subColor,
  ) {
    final subName = sess['subject_name'] ?? 'Session';
    final dept = sess['dept'] ?? '';
    final batch = sess['batch'] ?? '';
    final sem = sess['semester'] ?? 1;
    final sec = sess['section'] ?? 'A';
    final periods = (sess['period_numbers'] as List<dynamic>?)?.join(', ') ?? '1';
    final staffName = sess['staff_name'] ?? sess['staff_reg_no'] ?? '';
    final date = sess['date'] ?? '';
    final status = sess['status'] ?? 'closed';
    final presentCount = sess['present_count'] ?? 0;
    final absentCount = sess['absent_count'] ?? 0;
    final totalRoll = sess['total_roll'] ?? (presentCount + absentCount);
    final sessionId = sess['session_id'] ?? '';
    final classSummary = '$dept / $batch / Sem $sem / Sec $sec';

    final isLive = status == 'checkin_open' || status == 'checkout_open';
    final statusColor = isLive
        ? const Color(0xFF059669)
        : status == 'checkin_closed'
            ? const Color(0xFFD97706)
            : const Color(0xFF64748B);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isLive ? const Color(0xFF059669) : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)), width: isLive ? 2 : 1),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Date + Period Badge + Live/Closed Pill
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E3A8A).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('Period $periods', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF1E3A8A))),
                ),
                const SizedBox(width: 8),
                Text(date, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: subColor)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    isLive ? '● LIVE' : status == 'checkin_closed' ? 'Check-In Closed' : 'Completed',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Row 2: Subject & Class Group
            Text(subName, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: textColor)),
            const SizedBox(height: 2),
            Text('$classSummary  ·  Faculty: $staffName', style: TextStyle(fontSize: 12, color: subColor)),

            const SizedBox(height: 12),

            // Row 3: Counts & View Roll CTA
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF059669).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('$presentCount Present', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF059669))),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDC2626).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('$absentCount Absent', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFDC2626))),
                      ),
                      Text('($totalRoll total enrolled)', style: TextStyle(fontSize: 11, color: subColor)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.list_alt_rounded, size: 14),
                  label: const Text('View Roll', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  onPressed: () => ClassSessionRollSheet.show(
                    context,
                    token: widget.token,
                    sessionId: sessionId,
                    subjectName: subName,
                    classSummary: classSummary,
                    canOverride: true,
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
