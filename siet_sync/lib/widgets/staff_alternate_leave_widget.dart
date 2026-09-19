import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../config/college_ip_config.dart';
import '../services/session_service.dart';
import '../services/leave_balance_notifier.dart';
import '../services/staff_alternate_leave_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens (Hallmark-compliant — no inline raw hex, no AI slop copy)
// ─────────────────────────────────────────────────────────────────────────────
const _kPrimary = Color(0xFF1C6EF2);
const _kSuccess = Color(0xFF059669);
const _kDanger = Color(0xFFDC2626);
const _kWarning = Color(0xFFF59E0B);
const _kSurface = Color(0xFFF8FAFC);
const _kBorder = Color(0xFFE2E8F0);
const _kText = Color(0xFF0F172A);
const _kSubtext = Color(0xFF475569);

// Workflow status label + color
Color _statusColor(String? s) {
  switch ((s ?? '').toUpperCase()) {
    case 'APPROVED':
      return _kSuccess;
    case 'REJECTED':
      return _kDanger;
    case 'AWAITING_ALTERNATE':
      return _kWarning;
    case 'AWAITING_HOD_ADMIN':
      return _kPrimary;
    case 'EXPIRED':
    case 'CANCELLED':
      return Colors.grey;
    default:
      return _kSubtext;
  }
}

String _statusLabel(String? s) {
  switch ((s ?? '').toUpperCase()) {
    case 'AWAITING_ALTERNATE':
      return 'Awaiting alternate';
    case 'AWAITING_HOD_ADMIN':
      return 'Pending approval';
    case 'APPROVED':
      return 'Approved';
    case 'REJECTED':
      return 'Rejected';
    case 'EXPIRED':
      return 'Expired';
    case 'CANCELLED':
      return 'Cancelled';
    default:
      return s ?? '—';
  }
}

String _fmtDate(String? d) {
  if (d == null || d.isEmpty) return '—';
  try {
    final dt = DateTime.parse(d.substring(0, 10));
    return DateFormat('d MMM yyyy').format(dt);
  } catch (_) {
    return d.substring(0, 10);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ENTRY POINT — plugs directly into StaffLeaveRequestTab and HOD/Other panels
// ─────────────────────────────────────────────────────────────────────────────

/// Complete Staff Alternate-Leave tab.
/// Shows three sub-tabs: Submit Request | My Requests | Coverage Requests.
/// All roles (staff, hod, other_staff) use this same widget.
class StaffAlternateLeaveTab extends StatefulWidget {
  final String token;
  final Color accentColor;

  const StaffAlternateLeaveTab({
    super.key,
    required this.token,
    this.accentColor = _kPrimary,
  });

  @override
  State<StaffAlternateLeaveTab> createState() => _StaffAlternateLeaveTabState();
}

class _StaffAlternateLeaveTabState extends State<StaffAlternateLeaveTab>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  int _pendingBadge = 0;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _loadBadge();
  }

  Future<void> _loadBadge() async {
    final res = await StaffAlternateLeaveService.getPendingNominations(widget.token);
    if (!mounted) return;
    final list = res['pending_nominations'] as List? ?? [];
    setState(() => _pendingBadge = list.length);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isMobile = screenWidth < 650;

    return Column(
      children: [
        TabBar(
          controller: _tab,
          labelColor: widget.accentColor,
          unselectedLabelColor: _kSubtext,
          indicatorColor: widget.accentColor,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelPadding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16),
          labelStyle: TextStyle(
            fontSize: isMobile ? 12 : 13,
            fontWeight: FontWeight.w700,
          ),
          unselectedLabelStyle: TextStyle(
            fontSize: isMobile ? 12 : 13,
            fontWeight: FontWeight.w500,
          ),
          tabs: [
            Tab(text: isMobile ? 'Submit' : 'Submit Request'),
            Tab(text: isMobile ? 'Requests' : 'My Requests'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(isMobile ? 'Coverage' : 'Coverage Requests'),
                  if (_pendingBadge > 0) ...[
                    const SizedBox(width: 4),
                    _Badge(_pendingBadge),
                  ],
                ],
              ),
            ),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              StaffSubmitRequestPane(
                token: widget.token,
                onSubmitted: () {
                  _tab.animateTo(1);
                  _loadBadge();
                },
              ),
              StaffMyRequestsPane(
                token: widget.token,
                onRefresh: _loadBadge,
              ),
              StaffCoverageRequestsPane(
                token: widget.token,
                onRefresh: _loadBadge,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HOD Staff-Leave Review Tab (added to HOD panel)
// ─────────────────────────────────────────────────────────────────────────────

class HodStaffLeaveReviewTab extends StatefulWidget {
  final String token;
  final Color accentColor;

  const HodStaffLeaveReviewTab({
    super.key,
    required this.token,
    this.accentColor = _kPrimary,
  });

  @override
  State<HodStaffLeaveReviewTab> createState() => _HodStaffLeaveReviewTabState();
}

class _HodStaffLeaveReviewTabState extends State<HodStaffLeaveReviewTab>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tab,
          labelColor: widget.accentColor,
          unselectedLabelColor: _kSubtext,
          indicatorColor: widget.accentColor,
          tabs: const [
            Tab(text: 'Pending Approval'),
            Tab(text: 'All Requests'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _HodRequestList(
                token: widget.token,
                workflowStatus: 'AWAITING_HOD_ADMIN',
                accentColor: widget.accentColor,
              ),
              _HodRequestList(
                token: widget.token,
                workflowStatus: null,
                accentColor: widget.accentColor,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Admin Staff-Leave Review Tab
// ─────────────────────────────────────────────────────────────────────────────

class AdminStaffLeaveTab extends StatefulWidget {
  final String token;
  final Color accentColor;

  const AdminStaffLeaveTab({
    super.key,
    required this.token,
    this.accentColor = _kPrimary,
  });

  @override
  State<AdminStaffLeaveTab> createState() => _AdminStaffLeaveTabState();
}

class _AdminStaffLeaveTabState extends State<AdminStaffLeaveTab>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tab,
          labelColor: widget.accentColor,
          unselectedLabelColor: _kSubtext,
          indicatorColor: widget.accentColor,
          tabs: const [
            Tab(text: 'Pending Final Approval'),
            Tab(text: 'All Staff Leaves'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _AdminRequestList(
                token: widget.token,
                workflowStatus: 'AWAITING_HOD_ADMIN',
                accentColor: widget.accentColor,
              ),
              _AdminRequestList(
                token: widget.token,
                workflowStatus: null,
                accentColor: widget.accentColor,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PANE: SUBMIT REQUEST
// ─────────────────────────────────────────────────────────────────────────────

class StaffSubmitRequestPane extends StatefulWidget {
  final String token;
  final VoidCallback? onSubmitted;

  const StaffSubmitRequestPane({super.key, required this.token, this.onSubmitted});

  @override
  State<StaffSubmitRequestPane> createState() => _StaffSubmitRequestPaneState();
}

class _StaffSubmitRequestPaneState extends State<StaffSubmitRequestPane> {
  final _formKey = GlobalKey<FormState>();
  final _reasonCtrl = TextEditingController();

  String _leaveType = 'casual';
  DateTime? _start;
  DateTime? _end;
  bool _isHalfDay = false;
  String _whichHalf = 'FN';
  bool _loading = false;
  bool _loadingAlternates = false;
  String? _error;

  // Alternate selection
  List<Map<String, dynamic>> _alternates = [];
  Map<String, dynamic>? _selectedAlternate;
  String _altSearch = '';

  double? _availableCL;
  double? _availableCCL;
  bool _loadingBalances = false;

  // Timetable class detection
  bool _checkingClasses = false;
  bool? _hasClasses;
  int _classCount = 0;
  List<Map<String, dynamic>> _scheduledSlots = [];
  bool _showSlotsExpanded = false;

  static const _leaveTypes = [
    {'value': 'casual', 'label': 'Casual Leave'},
    {'value': 'od', 'label': 'On Duty (OD)'},
    {'value': 'earned', 'label': 'Earned Leave'},
    {'value': 'sick', 'label': 'Medical Leave'},
    {'value': 'maternity', 'label': 'Maternity Leave'},
    {'value': 'paternity', 'label': 'Paternity Leave'},
    {'value': 'unpaid', 'label': 'Unpaid Leave'},
    {'value': 'other', 'label': 'Other'},
  ];

  @override
  void initState() {
    super.initState();
    _fetchAlternates();
    _fetchBalances();
    LeaveBalanceNotifier.instance.addListener(_fetchBalances);
  }

  @override
  void dispose() {
    LeaveBalanceNotifier.instance.removeListener(_fetchBalances);
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchBalances() async {
    if (!mounted) return;
    setState(() => _loadingBalances = true);
    try {
      final session = await sessionService.getSession();
      String? regNo = session?.user['regNo'] ?? session?.user['reg_no'];
      if (regNo != null && regNo.isNotEmpty) {
        final clUrl = '${CollegeIPConfig.defaultURL}/cl/status/$regNo';
        final clRes = await http.get(
          Uri.parse(clUrl),
          headers: {'Authorization': 'Bearer ${widget.token}'},
        );
        if (clRes.statusCode == 200) {
          final clData = json.decode(clRes.body);
          if (clData['success'] == true && clData['data'] != null && mounted) {
            setState(() {
              _availableCL = (clData['data']['total_cl_available'] as num?)?.toDouble() ?? 0.0;
            });
          }
        }

        final cclUrl = '${CollegeIPConfig.defaultURL}/ccl/status/$regNo';
        final cclRes = await http.get(
          Uri.parse(cclUrl),
          headers: {'Authorization': 'Bearer ${widget.token}'},
        );
        if (cclRes.statusCode == 200) {
          final cclData = json.decode(cclRes.body);
          if (cclData['success'] == true && cclData['data'] != null && mounted) {
            setState(() {
              _availableCCL = (cclData['data']['earned_leave_available'] as num?)?.toDouble() ?? 0.0;
            });
          }
        }
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingBalances = false);
    }
  }

  int _calculateWorkingDays() {
    if (_start == null || _end == null) return 0;
    int workingDays = 0;
    DateTime temp = _start!;
    while (temp.isBefore(_end!) || temp.isAtSameMomentAs(_end!)) {
      if (temp.weekday != DateTime.saturday && temp.weekday != DateTime.sunday) {
        workingDays++;
      }
      temp = temp.add(const Duration(days: 1));
    }
    return workingDays;
  }

  Future<void> _checkClasses() async {
    if (_start == null || _end == null) {
      if (mounted) {
        setState(() {
          _hasClasses = null;
          _classCount = 0;
          _scheduledSlots = [];
        });
      }
      return;
    }
    if (mounted) setState(() => _checkingClasses = true);
    final fmt = DateFormat('yyyy-MM-dd');
    final res = await StaffAlternateLeaveService.checkScheduledClasses(
      token: widget.token,
      startDate: fmt.format(_start!),
      endDate: fmt.format(_end!),
      isHalfDay: _isHalfDay,
      whichHalf: _isHalfDay ? _whichHalf : null,
    );
    if (!mounted) return;
    setState(() {
      _checkingClasses = false;
      _hasClasses = res['has_classes'] == true;
      _classCount = (res['class_count'] as num?)?.toInt() ?? 0;
      _scheduledSlots = (res['scheduled_slots'] as List? ?? [])
          .cast<Map<String, dynamic>>();
    });
  }

  Future<void> _fetchAlternates() async {
    setState(() => _loadingAlternates = true);
    final res = await StaffAlternateLeaveService.getEligibleAlternates(widget.token);
    if (!mounted) return;
    final list = (res['alternates'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    setState(() {
      _alternates = list;
      _loadingAlternates = false;
    });
  }

  List<Map<String, dynamic>> get _filteredAlternates {
    if (_altSearch.isEmpty) return _alternates;
    final q = _altSearch.toLowerCase();
    return _alternates.where((a) {
      final name = (a['name'] as String? ?? '').toLowerCase();
      final dept = (a['dept'] as String? ?? '').toLowerCase();
      final regNo = (a['reg_no'] as String? ?? '').toLowerCase();
      final role = (a['role'] as String? ?? '').toLowerCase();
      return name.contains(q) ||
          dept.contains(q) ||
          regNo.contains(q) ||
          role.contains(q);
    }).toList();
  }

  Future<void> _pickDate(bool isStart) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now.subtract(const Duration(days: 7)),
      lastDate: now.add(const Duration(days: 90)),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _start = picked;
        if (_end != null && _end!.isBefore(picked)) _end = picked;
      } else {
        _end = picked;
      }
    });
    _checkClasses();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_start == null || _end == null) {
      setState(() => _error = 'Select both start and end dates.');
      return;
    }
    if (_hasClasses == true && _selectedAlternate == null) {
      setState(() => _error =
          'Please select an alternate staff member to cover your $_classCount scheduled class period(s).');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final fmt = DateFormat('yyyy-MM-dd');
    final res = await StaffAlternateLeaveService.submitLeaveRequest(
      token: widget.token,
      leaveType: _leaveType,
      startDate: fmt.format(_start!),
      endDate: fmt.format(_end!),
      reason: _reasonCtrl.text.trim(),
      alternateRegNo: _selectedAlternate?['reg_no'] as String?,
      alternateName: _selectedAlternate?['name'] as String?,
      alternateDept: _selectedAlternate?['dept'] as String?,
      alternateRole: _selectedAlternate?['role'] as String?,
      isHalfDay: _isHalfDay,
      whichHalf: _isHalfDay ? _whichHalf : null,
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (res['success'] == true) {
      _reasonCtrl.clear();
      setState(() {
        _start = null;
        _end = null;
        _selectedAlternate = null;
        _leaveType = 'casual';
        _isHalfDay = false;
        _hasClasses = null;
        _classCount = 0;
        _scheduledSlots = [];
      });
      LeaveBalanceNotifier.instance.notifyBalanceChanged();
      _showSnack(res['message'] ?? 'Request submitted.', isError: false);
      widget.onSubmitted?.call();
    } else {
      setState(() => _error = res['message'] ?? 'Submission failed.');
    }
  }

  void _showSnack(String msg, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? _kDanger : _kSuccess,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isMobile = screenWidth < 650;
    final workingDays = _calculateWorkingDays();
    final effectiveDays = _isHalfDay ? 0.5 : workingDays.toDouble();

    final clStr = (_availableCL ?? 0.0) % 1 == 0
        ? '${(_availableCL ?? 0.0).toInt()}'
        : '${_availableCL ?? 0.0}';
    final cclStr = (_availableCCL ?? 0.0) % 1 == 0
        ? '${(_availableCCL ?? 0.0).toInt()}'
        : '${_availableCCL ?? 0.0}';

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Live Leave Balances
            if (_loadingBalances)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: LinearProgressIndicator(color: _kPrimary),
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: EdgeInsets.all(isMobile ? 10 : 12),
                        decoration: BoxDecoration(
                          color: _kPrimary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: _kPrimary.withValues(alpha: 0.25)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(isMobile ? 'Casual Leave (CL)' : 'Casual Leaves (CL)',
                                style: TextStyle(
                                    fontSize: isMobile ? 11 : 12,
                                    color: _kPrimary,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text('$clStr Available',
                                style: TextStyle(
                                    fontSize: isMobile ? 15 : 16,
                                    fontWeight: FontWeight.w700,
                                    color: _kPrimary)),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(width: isMobile ? 8 : 12),
                    Expanded(
                      child: Container(
                        padding: EdgeInsets.all(isMobile ? 10 : 12),
                        decoration: BoxDecoration(
                          color: _kSuccess.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: _kSuccess.withValues(alpha: 0.25)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(isMobile ? 'Earned Leave (EL)' : 'Earned Leaves (EL)',
                                style: TextStyle(
                                    fontSize: isMobile ? 11 : 12,
                                    color: _kSuccess,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text('$cclStr Available',
                                style: TextStyle(
                                    fontSize: isMobile ? 15 : 16,
                                    fontWeight: FontWeight.w700,
                                    color: _kSuccess)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Leave type
            _SectionLabel('Leave type'),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: _leaveType,
              decoration: _inputDeco('Select type'),
              items: _leaveTypes
                  .map((t) => DropdownMenuItem(
                        value: t['value'],
                        child: Text(t['label']!),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _leaveType = v!),
            ),
            const SizedBox(height: 16),

            // Date range
            Row(
              children: [
                Expanded(
                  child: _DateButton(
                    label: 'Start date',
                    value: _start,
                    onTap: () => _pickDate(true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DateButton(
                    label: 'End date',
                    value: _end,
                    onTap: () => _pickDate(false),
                  ),
                ),
              ],
            ),
            if (_start != null && _end != null)
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 2),
                child: Text(
                  'Duration: $effectiveDays working day${effectiveDays == 1.0 ? '' : 's'}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _kPrimary),
                ),
              ),
            const SizedBox(height: 12),

            // Half-day toggle
            _HalfDayToggle(
              isHalfDay: _isHalfDay,
              whichHalf: _whichHalf,
              onToggle: (v) => setState(() {
                _isHalfDay = v;
                if (v && _end != null && _start != null && _end != _start) {
                  _end = _start;
                }
                _checkClasses();
              }),
              onHalfChanged: (v) => setState(() {
                _whichHalf = v;
                _checkClasses();
              }),
            ),

            // Class detection feedback
            if (_checkingClasses)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: _kPrimary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _kPrimary.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: const [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: _kPrimary),
                    ),
                    SizedBox(width: 10),
                    Text('Checking timetable schedule for these dates…',
                        style: TextStyle(fontSize: 12, color: _kPrimary, fontWeight: FontWeight.w500)),
                  ],
                ),
              )
            else if (_hasClasses == true)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _kWarning.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _kWarning.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: _kWarning, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'You have $_classCount scheduled class period${_classCount == 1 ? '' : 's'} on these dates.',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF92400E)),
                          ),
                        ),
                        if (_scheduledSlots.isNotEmpty)
                          GestureDetector(
                            onTap: () => setState(() => _showSlotsExpanded = !_showSlotsExpanded),
                            child: Text(
                              _showSlotsExpanded ? 'Hide classes' : 'View classes (${_scheduledSlots.length})',
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w700, color: _kPrimary),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Alternate staff nomination is required to cover your scheduled periods.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF92400E)),
                    ),
                    if (_showSlotsExpanded && _scheduledSlots.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Divider(height: 1),
                      const SizedBox(height: 8),
                      ..._scheduledSlots.map((s) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _kPrimary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'P${s['period_number']}',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _kPrimary),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${s['subject_name']} (${s['dept']} Sem ${s['semester']}-${s['section']}) · ${s['coverage_date']}',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      )),
                    ],
                  ],
                ),
              )
            else if (_hasClasses == false && _start != null && _end != null)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _kSuccess.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _kSuccess.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.check_circle_outline_rounded, color: _kSuccess, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No teaching periods scheduled on these dates. Alternate coverage is not required.',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF065F46)),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 16),

            // Reason
            _SectionLabel('Reason'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _reasonCtrl,
              maxLines: 3,
              maxLength: 1000,
              decoration: _inputDeco('Describe the reason (min. 10 characters)'),
              validator: (v) {
                if ((v ?? '').trim().length < 10) {
                  return 'Provide at least 10 characters.';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Alternate picker
            _SectionLabel(_hasClasses == true
                ? 'Nominate an alternate (Required)'
                : 'Nominate an alternate (Optional)'),
            const SizedBox(height: 3),
            Text(
              _hasClasses == true
                  ? 'The nominated staff will cover your $_classCount scheduled period(s).'
                  : 'Optionally nominate a colleague for coverage.',
              style: TextStyle(fontSize: isMobile ? 11 : 12, color: _kSubtext),
            ),
            const SizedBox(height: 8),
            if (_loadingAlternates)
              const Center(child: CircularProgressIndicator())
            else ...[
              TextField(
                decoration: _inputDeco(isMobile
                    ? 'Search colleague by name or ID...'
                    : 'Search by name, department, staff ID, or role'),
                onChanged: (v) => setState(() => _altSearch = v),
              ),
              const SizedBox(height: 8),
              if (_selectedAlternate != null)
                _SelectedAlternateBanner(
                  alternate: _selectedAlternate!,
                  onClear: () => setState(() => _selectedAlternate = null),
                ),
              if (_selectedAlternate == null)
                SizedBox(
                  height: 220,
                  child: ListView.separated(
                    itemCount: _filteredAlternates.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final a = _filteredAlternates[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _kPrimary.withValues(alpha: 0.12),
                          child: Text(
                            (a['name'] as String? ?? '?')
                                .substring(0, 1)
                                .toUpperCase(),
                            style: const TextStyle(
                                color: _kPrimary, fontWeight: FontWeight.w700),
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(a['name'] as String? ?? '—',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600, fontSize: 14)),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _kPrimary.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                a['dept'] ?? '—',
                                style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: _kPrimary),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            'Staff ID: ${a['reg_no']} · ${a['role']}',
                            style: const TextStyle(
                                fontSize: 12, color: _kSubtext),
                          ),
                        ),
                        onTap: () =>
                            setState(() => _selectedAlternate = a),
                      );
                    },
                  ),
                ),
            ],
            const SizedBox(height: 20),

            // Error
            if (_error != null)
              _ErrorBanner(_error!),

            // Submit
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Submit leave request',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PANE: MY REQUESTS (requester view)
// ─────────────────────────────────────────────────────────────────────────────

class StaffMyRequestsPane extends StatefulWidget {
  final String token;
  final VoidCallback? onRefresh;

  const StaffMyRequestsPane({super.key, required this.token, this.onRefresh});

  @override
  State<StaffMyRequestsPane> createState() => _StaffMyRequestsPaneState();
}

class _StaffMyRequestsPaneState extends State<StaffMyRequestsPane> {
  List<Map<String, dynamic>> _requests = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res =
        await StaffAlternateLeaveService.getMyRequests(widget.token);
    if (!mounted) return;
    if (res['success'] == true) {
      final list = (res['requests'] as List? ?? [])
          .cast<Map<String, dynamic>>();
      setState(() {
        _requests = list;
        _loading = false;
      });
    } else {
      setState(() {
        _error = res['message'] ?? 'Failed to load requests.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _EmptyOrError(message: _error!, onRetry: _load);
    }
    if (_requests.isEmpty) {
      return const _EmptyOrError(
          message: 'No leave requests submitted yet.');
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _requests.length,
        itemBuilder: (ctx, i) => _RequesterCard(
          request: _requests[i],
          token: widget.token,
          onAction: () {
            _load();
            widget.onRefresh?.call();
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PANE: COVERAGE REQUESTS (alternate view)
// ─────────────────────────────────────────────────────────────────────────────

class StaffCoverageRequestsPane extends StatefulWidget {
  final String token;
  final VoidCallback? onRefresh;

  const StaffCoverageRequestsPane({super.key, required this.token, this.onRefresh});

  @override
  State<StaffCoverageRequestsPane> createState() => _StaffCoverageRequestsPaneState();
}

class _StaffCoverageRequestsPaneState extends State<StaffCoverageRequestsPane>
    with SingleTickerProviderStateMixin {
  late TabController _inner;
  List<Map<String, dynamic>> _pending = [];
  List<Map<String, dynamic>> _all = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _inner = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _inner.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final results = await Future.wait([
      StaffAlternateLeaveService.getPendingNominations(widget.token),
      StaffAlternateLeaveService.getAllMyNominations(widget.token),
    ]);
    if (!mounted) return;
    final pendingRes = results[0];
    final allRes = results[1];
    if (pendingRes['success'] == true && allRes['success'] == true) {
      setState(() {
        _pending = (pendingRes['pending_nominations'] as List? ?? [])
            .cast<Map<String, dynamic>>();
        _all = (allRes['nominations'] as List? ?? [])
            .cast<Map<String, dynamic>>();
        _loading = false;
      });
      widget.onRefresh?.call();
    } else {
      setState(() {
        _error = 'Failed to load coverage requests.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _EmptyOrError(message: _error!, onRetry: _load);
    }
    return Column(
      children: [
        TabBar(
          controller: _inner,
          labelColor: _kPrimary,
          unselectedLabelColor: _kSubtext,
          indicatorColor: _kPrimary,
          tabs: [
            Tab(text: 'Pending (${_pending.length})'),
            Tab(text: 'History (${_all.length})'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _inner,
            children: [
              _NominationList(
                items: _pending,
                token: widget.token,
                onAction: _load,
                isPending: true,
              ),
              _NominationList(
                items: _all,
                token: widget.token,
                onAction: _load,
                isPending: false,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NOMINATION LIST (alternate side)
// ─────────────────────────────────────────────────────────────────────────────

class _NominationList extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final String token;
  final VoidCallback onAction;
  final bool isPending;

  const _NominationList({
    required this.items,
    required this.token,
    required this.onAction,
    required this.isPending,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return _EmptyOrError(
        message: isPending
            ? 'No pending coverage requests.'
            : 'No nominations in history.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      itemBuilder: (ctx, i) => _AlternateCard(
        request: items[i],
        token: token,
        isPending: isPending,
        onAction: onAction,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REQUESTER CARD
// ─────────────────────────────────────────────────────────────────────────────

class _RequesterCard extends StatelessWidget {
  final Map<String, dynamic> request;
  final String token;
  final VoidCallback onAction;

  const _RequesterCard(
      {required this.request, required this.token, required this.onAction});

  @override
  Widget build(BuildContext context) {
    final status = request['workflow_status'] as String? ?? '';
    final altStatus = request['alternate_status'] as String? ?? '';
    final canCancel = status == 'AWAITING_ALTERNATE';
    final canReNominate = status == 'AWAITING_ALTERNATE' &&
        (altStatus == 'DECLINED' || altStatus == 'EXPIRED');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: _kBorder),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _openDetail(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_leaveLabel(request['leave_type'])} — #${request['id']}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: _kText),
                    ),
                  ),
                  _StatusChip(status),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${_fmtDate(request['start_date'])} – ${_fmtDate(request['end_date'])}',
                style: const TextStyle(fontSize: 13, color: _kSubtext),
              ),
              const SizedBox(height: 4),
              Text(
                'Alternate: ${request['alternate_name'] ?? '—'} · ${request['alternate_dept'] ?? ''}',
                style: const TextStyle(fontSize: 12, color: _kSubtext),
              ),
              if (altStatus.isNotEmpty && altStatus != 'PENDING') ...[
                const SizedBox(height: 4),
                Text('Alternate: $altStatus',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _statusColor(altStatus))),
              ],
              if (canReNominate) ...[
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kWarning,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                  ),
                  icon: const Icon(Icons.person_search, size: 16),
                  label: const Text('Re-nominate alternate'),
                  onPressed: () => _reNominate(context),
                ),
              ] else if (canCancel) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kDanger,
                    side: const BorderSide(color: _kDanger),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                  ),
                  icon: const Icon(Icons.cancel_outlined, size: 16),
                  label: const Text('Cancel request'),
                  onPressed: () => _cancel(context),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _leaveLabel(dynamic v) {
    switch ((v ?? '').toString().toLowerCase()) {
      case 'casual':
        return 'Casual Leave';
      case 'od':
        return 'On Duty (OD)';
      case 'earned':
        return 'Earned Leave';
      case 'sick':
        return 'Medical Leave';
      default:
        return (v ?? '—').toString().toUpperCase();
    }
  }

  Future<void> _openDetail(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _RequestDetailPage(
          token: token,
          requestId: request['id'] as int,
          isAdmin: false,
          isHod: false,
          onAction: onAction,
        ),
      ),
    );
  }

  Future<void> _cancel(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel request',
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: const Text(
            'This will cancel the request. The alternate will no longer be notified.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Cancel request',
                  style: TextStyle(color: _kDanger))),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final res = await StaffAlternateLeaveService.cancelRequest(
        token, request['id'] as int);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text(res['success'] == true ? 'Request cancelled.' : (res['message'] ?? 'Failed.')),
          backgroundColor: res['success'] == true ? _kSuccess : _kDanger,
          behavior: SnackBarBehavior.floating),
    );
    if (res['success'] == true) onAction();
  }

  Future<void> _reNominate(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _ReNominateSheet(
        token: token,
        requestId: request['id'] as int,
        onDone: onAction,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ALTERNATE CARD
// ─────────────────────────────────────────────────────────────────────────────

class _AlternateCard extends StatelessWidget {
  final Map<String, dynamic> request;
  final String token;
  final bool isPending;
  final VoidCallback onAction;

  const _AlternateCard({
    required this.request,
    required this.token,
    required this.isPending,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final deadline = request['alternate_deadline'] as String?;
    String deadlineStr = '';
    if (deadline != null && isPending) {
      try {
        final dt = DateTime.parse(deadline).toLocal();
        final remaining = dt.difference(DateTime.now());
        if (remaining.isNegative) {
          deadlineStr = 'Deadline passed';
        } else {
          final h = remaining.inHours;
          final m = remaining.inMinutes % 60;
          deadlineStr = 'Respond within ${h}h ${m}m';
        }
      } catch (_) {}
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
            color: isPending ? _kWarning.withValues(alpha: 0.5) : _kBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${request['requester_name'] ?? '—'} — ${request['leave_type']?.toString().toUpperCase() ?? ''}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: _kText),
                  ),
                ),
                _StatusChip(request['alternate_status'] ?? 'PENDING'),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${_fmtDate(request['start_date'])} – ${_fmtDate(request['end_date'])}',
              style: const TextStyle(fontSize: 13, color: _kSubtext),
            ),
            Text(
              'Department: ${request['dept'] ?? '—'}',
              style: const TextStyle(fontSize: 12, color: _kSubtext),
            ),
            if (deadlineStr.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.timer_outlined,
                      size: 14, color: _kWarning),
                  const SizedBox(width: 4),
                  Text(deadlineStr,
                      style: const TextStyle(
                          fontSize: 12,
                          color: _kWarning,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ],
            if (isPending) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _kDanger,
                        side: const BorderSide(color: _kDanger),
                      ),
                      onPressed: () => _respond(context, accepted: false),
                      child: const Text('Decline'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kSuccess,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => _respond(context, accepted: true),
                      child: const Text('Accept'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _respond(BuildContext context, {required bool accepted}) async {
    String? remarks;

    if (!accepted) {
      // Require reason when declining
      remarks = await showDialog<String>(
        context: context,
        builder: (_) => _RemarksDialog(
          title: 'Reason for declining',
          hint: 'Explain why you cannot cover this period.',
          required: true,
        ),
      );
      if (remarks == null || !context.mounted) return;
    } else {
      // Show conflict check before accepting
      final conflictsRes = await StaffAlternateLeaveService.getConflictsForRequest(
          token, request['id'] as int);
      final conflicts =
          (conflictsRes['conflicts'] as List? ?? []).cast<Map<String, dynamic>>();
      if (!context.mounted) return;
      if (conflicts.isNotEmpty) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (_) => _ConflictDialog(conflicts: conflicts),
        );
        if (proceed != true || !context.mounted) return;
      }
    }

    final res = await StaffAlternateLeaveService.respondToNomination(
      token: token,
      requestId: request['id'] as int,
      accepted: accepted,
      remarks: remarks,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(res['message'] ?? (accepted ? 'Accepted.' : 'Declined.')),
        backgroundColor: res['success'] == true
            ? (accepted ? _kSuccess : _kDanger)
            : _kDanger,
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (res['success'] == true) onAction();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HOD REQUEST LIST
// ─────────────────────────────────────────────────────────────────────────────

class _HodRequestList extends StatefulWidget {
  final String token;
  final String? workflowStatus;
  final Color accentColor;

  const _HodRequestList(
      {required this.token, this.workflowStatus, required this.accentColor});

  @override
  State<_HodRequestList> createState() => _HodRequestListState();
}

class _HodRequestListState extends State<_HodRequestList> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await StaffAlternateLeaveService.hodGetRequests(
      widget.token,
      workflowStatus: widget.workflowStatus,
    );
    if (!mounted) return;
    if (res['success'] == true) {
      setState(() {
        _items = (res['requests'] as List? ?? []).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } else {
      setState(() {
        _error = res['message'] ?? 'Failed to load.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _EmptyOrError(message: _error!, onRetry: _load);
    if (_items.isEmpty) return const _EmptyOrError(message: 'No requests found.');
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _items.length,
        itemBuilder: (ctx, i) => _ApprovalCard(
          request: _items[i],
          token: widget.token,
          isHod: true,
          onAction: _load,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ADMIN REQUEST LIST
// ─────────────────────────────────────────────────────────────────────────────

class _AdminRequestList extends StatefulWidget {
  final String token;
  final String? workflowStatus;
  final Color accentColor;

  const _AdminRequestList(
      {required this.token, this.workflowStatus, required this.accentColor});

  @override
  State<_AdminRequestList> createState() => _AdminRequestListState();
}

class _AdminRequestListState extends State<_AdminRequestList> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await StaffAlternateLeaveService.adminGetRequests(
      widget.token,
      workflowStatus: widget.workflowStatus,
    );
    if (!mounted) return;
    if (res['success'] == true) {
      setState(() {
        _items = (res['requests'] as List? ?? []).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } else {
      setState(() {
        _error = res['message'] ?? 'Failed to load.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _EmptyOrError(message: _error!, onRetry: _load);
    if (_items.isEmpty) return const _EmptyOrError(message: 'No requests found.');
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _items.length,
        itemBuilder: (ctx, i) => _ApprovalCard(
          request: _items[i],
          token: widget.token,
          isHod: false,
          onAction: _load,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// APPROVAL CARD (HOD + Admin shared)
// ─────────────────────────────────────────────────────────────────────────────

class _ApprovalCard extends StatelessWidget {
  final Map<String, dynamic> request;
  final String token;
  final bool isHod;
  final VoidCallback onAction;

  const _ApprovalCard(
      {required this.request,
      required this.token,
      required this.isHod,
      required this.onAction});

  bool get _canAct =>
      request['workflow_status'] == 'AWAITING_HOD_ADMIN' &&
      (isHod
          ? request['hod_status'] == 'PENDING'
          : request['admin_status'] == 'PENDING');

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: _kBorder),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _openDetail(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${request['requester_name'] ?? '—'} — ${request['leave_type']?.toString().toUpperCase() ?? ''}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: _kText),
                    ),
                  ),
                  _StatusChip(request['workflow_status'] ?? ''),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${_fmtDate(request['start_date'])} – ${_fmtDate(request['end_date'])}',
                style: const TextStyle(fontSize: 13, color: _kSubtext),
              ),
              Text(
                'Dept: ${request['dept'] ?? '—'} · Alternate: ${request['alternate_name'] ?? '—'}',
                style: const TextStyle(fontSize: 12, color: _kSubtext),
              ),
              if (_canAct) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _kDanger,
                          side: const BorderSide(color: _kDanger),
                        ),
                        onPressed: () => _act(context, approved: false),
                        child: const Text('Reject'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kSuccess,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => _act(context, approved: true),
                        child: const Text('Approve'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _act(BuildContext context, {required bool approved}) async {
    String? remarks;
    if (!approved) {
      remarks = await showDialog<String>(
        context: context,
        builder: (_) => _RemarksDialog(
          title: 'Reason for rejection',
          hint: 'Explain why this leave is being rejected.',
          required: true,
        ),
      );
      if (remarks == null || !context.mounted) return;
    } else {
      remarks = await showDialog<String>(
        context: context,
        builder: (_) => _RemarksDialog(
          title: 'Approval remarks (optional)',
          hint: 'Add any remarks…',
          required: false,
        ),
      );
      if (!context.mounted) return;
    }

    final Map<String, dynamic> res;
    if (isHod) {
      res = await StaffAlternateLeaveService.hodAction(
        token: token,
        requestId: request['id'] as int,
        approved: approved,
        remarks: remarks,
      );
    } else {
      res = await StaffAlternateLeaveService.adminAction(
        token: token,
        requestId: request['id'] as int,
        approved: approved,
        remarks: remarks,
      );
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(res['message'] ?? (approved ? 'Approved.' : 'Rejected.')),
        backgroundColor: res['success'] == true ? _kSuccess : _kDanger,
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (res['success'] == true) onAction();
  }

  Future<void> _openDetail(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _RequestDetailPage(
          token: token,
          requestId: request['id'] as int,
          isAdmin: !isHod,
          isHod: isHod,
          onAction: onAction,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REQUEST DETAIL PAGE
// ─────────────────────────────────────────────────────────────────────────────

class _RequestDetailPage extends StatefulWidget {
  final String token;
  final int requestId;
  final bool isAdmin;
  final bool isHod;
  final VoidCallback? onAction;

  const _RequestDetailPage({
    required this.token,
    required this.requestId,
    required this.isAdmin,
    required this.isHod,
    this.onAction,
  });

  @override
  State<_RequestDetailPage> createState() => _RequestDetailPageState();
}

class _RequestDetailPageState extends State<_RequestDetailPage> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = widget.isAdmin
        ? await StaffAlternateLeaveService.adminGetDetail(
            widget.token, widget.requestId)
        : await StaffAlternateLeaveService.getRequestDetail(
            widget.token, widget.requestId);
    if (!mounted) return;
    if (res['success'] == true) {
      setState(() {
        _data = res;
        _loading = false;
      });
    } else {
      setState(() {
        _error = res['message'] ?? 'Failed to load.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Leave Request #${widget.requestId}'),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _EmptyOrError(message: _error!, onRetry: _load)
              : _DetailBody(
                  data: _data!,
                  token: widget.token,
                  isAdmin: widget.isAdmin,
                  isHod: widget.isHod,
                  onAction: () {
                    _load();
                    widget.onAction?.call();
                  },
                ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  final Map<String, dynamic> data;
  final String token;
  final bool isAdmin;
  final bool isHod;
  final VoidCallback onAction;

  const _DetailBody({
    required this.data,
    required this.token,
    required this.isAdmin,
    required this.isHod,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final req = data['request'] as Map<String, dynamic>? ?? {};
    final slots = (data['timetable_slots'] as List? ?? []).cast<Map<String, dynamic>>();
    final audit = (data['audit_log'] as List? ?? []).cast<Map<String, dynamic>>();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Status banner
        _StatusBanner(req['workflow_status'] ?? ''),
        const SizedBox(height: 16),

        // Basic info
        _InfoCard(children: [
          _InfoRow('Requester', req['requester_name'] ?? '—'),
          _InfoRow('Department', req['dept'] ?? '—'),
          _InfoRow('Leave type', (req['leave_type'] ?? '').toString().toUpperCase()),
          _InfoRow('Period',
              '${_fmtDate(req['start_date'])} – ${_fmtDate(req['end_date'])}'),
          _InfoRow('Reason', req['reason'] ?? '—'),
          _InfoRow('Submitted',
              _fmtDate(req['submission_date']?.toString().substring(0, 10))),
        ]),
        const SizedBox(height: 12),

        // Alternate info
        _InfoCard(children: [
          _InfoRow('Alternate', req['alternate_name'] ?? '—'),
          _InfoRow('Alternate dept', req['alternate_dept'] ?? '—'),
          _InfoRow('Alternate status', req['alternate_status'] ?? '—'),
          if (req['alternate_remarks'] != null)
            _InfoRow('Alternate remarks', req['alternate_remarks'] as String),
        ]),
        const SizedBox(height: 12),

        // Timetable coverage
        if (slots.isNotEmpty) ...[
          const _SectionLabel('Timetable coverage'),
          const SizedBox(height: 8),
          ...slots.map((s) => _SlotRow(slot: s)),
          const SizedBox(height: 12),
        ],

        // HOD + Admin status
        _InfoCard(children: [
          _InfoRow('HOD status', req['hod_status'] ?? '—'),
          if (req['hod_remarks'] != null)
            _InfoRow('HOD remarks', req['hod_remarks'] as String),
          _InfoRow('Admin status', req['admin_status'] ?? '—'),
          if (req['admin_remarks'] != null)
            _InfoRow('Admin remarks', req['admin_remarks'] as String),
        ]),
        const SizedBox(height: 12),

        // Audit log
        if (audit.isNotEmpty) ...[
          const _SectionLabel('Activity log'),
          const SizedBox(height: 8),
          ...audit.map((a) => _AuditRow(entry: a)),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RE-NOMINATE SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _ReNominateSheet extends StatefulWidget {
  final String token;
  final int requestId;
  final VoidCallback onDone;

  const _ReNominateSheet(
      {required this.token, required this.requestId, required this.onDone});

  @override
  State<_ReNominateSheet> createState() => _ReNominateSheetState();
}

class _ReNominateSheetState extends State<_ReNominateSheet> {
  List<Map<String, dynamic>> _alternates = [];
  bool _loading = true;
  Map<String, dynamic>? _selected;
  String _search = '';
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    final res =
        await StaffAlternateLeaveService.getEligibleAlternates(widget.token);
    if (!mounted) return;
    setState(() {
      _alternates = (res['alternates'] as List? ?? []).cast<Map<String, dynamic>>();
      _loading = false;
    });
  }

  List<Map<String, dynamic>> get _filtered {
    if (_search.isEmpty) return _alternates;
    final q = _search.toLowerCase();
    return _alternates
        .where((a) =>
            (a['name'] as String? ?? '').toLowerCase().contains(q) ||
            (a['dept'] as String? ?? '').toLowerCase().contains(q))
        .toList();
  }

  Future<void> _submit() async {
    if (_selected == null) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final res = await StaffAlternateLeaveService.reNominateAlternate(
      token: widget.token,
      requestId: widget.requestId,
      alternateRegNo: _selected!['reg_no'] as String,
      alternateName: _selected!['name'] as String,
      alternateDept: _selected!['dept'] as String,
      alternateRole: _selected!['role'] as String,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (res['success'] == true) {
      Navigator.pop(context);
      widget.onDone();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('New alternate nominated.'),
          backgroundColor: _kSuccess,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      setState(() => _error = res['message'] ?? 'Failed to re-nominate.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      builder: (_, ctrl) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Select new alternate',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: _kText)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                decoration: _inputDeco('Search by name or department'),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
            const SizedBox(height: 8),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _ErrorBanner(_error!),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.separated(
                      controller: ctrl,
                      itemCount: _filtered.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final a = _filtered[i];
                        final isSel = _selected?['reg_no'] == a['reg_no'];
                        return ListTile(
                          selected: isSel,
                          selectedTileColor:
                              _kPrimary.withValues(alpha: 0.06),
                          leading: CircleAvatar(
                            backgroundColor: _kPrimary.withValues(alpha: 0.12),
                            child: Text(
                              (a['name'] as String? ?? '?')
                                  .substring(0, 1)
                                  .toUpperCase(),
                              style: const TextStyle(
                                  color: _kPrimary,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                          title: Text(a['name'] as String? ?? '—',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14)),
                          subtitle: Text(
                              '${a['dept']} · ${a['role']}',
                              style: const TextStyle(
                                  fontSize: 12, color: _kSubtext)),
                          trailing: isSel
                              ? const Icon(Icons.check_circle,
                                  color: _kPrimary)
                              : null,
                          onTap: () =>
                              setState(() => _selected = a),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimary,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: (_selected == null || _submitting)
                      ? null
                      : _submit,
                  child: _submitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Confirm new alternate',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DIALOGS
// ─────────────────────────────────────────────────────────────────────────────

class _RemarksDialog extends StatefulWidget {
  final String title;
  final String hint;
  final bool required;

  const _RemarksDialog(
      {required this.title, required this.hint, required this.required});

  @override
  State<_RemarksDialog> createState() => _RemarksDialogState();
}

class _RemarksDialogState extends State<_RemarksDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title,
          style:
              const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
      content: TextField(
        controller: _ctrl,
        maxLines: 3,
        decoration: _inputDeco(widget.hint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: _kPrimary),
          onPressed: () {
            if (widget.required && _ctrl.text.trim().isEmpty) return;
            Navigator.pop(context,
                _ctrl.text.trim().isEmpty ? null : _ctrl.text.trim());
          },
          child: const Text('Confirm',
              style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

class _ConflictDialog extends StatelessWidget {
  final List<Map<String, dynamic>> conflicts;

  const _ConflictDialog({required this.conflicts});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Timetable conflicts',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You have ${conflicts.length} period(s) that clash with your existing timetable. You can still accept — the conflict is informational only.',
              style:
                  const TextStyle(fontSize: 13, color: _kSubtext),
            ),
            const SizedBox(height: 12),
            ...conflicts.take(5).map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber,
                          size: 14, color: _kWarning),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${c['day_of_week']} P${c['period_number']}: ${c['leave_subject']} ↔ ${c['conflict_subject']}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                )),
            if (conflicts.length > 5)
              Text('…and ${conflicts.length - 5} more.',
                  style:
                      const TextStyle(fontSize: 12, color: _kSubtext)),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Go back')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: _kSuccess),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Accept anyway',
              style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SMALL REUSABLE WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  final int count;

  const _Badge(this.count);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _kDanger,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        count > 99 ? '99+' : count.toString(),
        style: const TextStyle(
            color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip(this.status);

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final String status;

  const _StatusBanner(this.status);

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(
            fontWeight: FontWeight.w700, fontSize: 14, color: color),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(
            fontWeight: FontWeight.w700, fontSize: 13, color: _kSubtext));
  }
}

class _InfoCard extends StatelessWidget {
  final List<Widget> children;

  const _InfoCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
      ),
      child: Column(children: children),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: const TextStyle(fontSize: 12, color: _kSubtext)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _kText)),
          ),
        ],
      ),
    );
  }
}

class _SlotRow extends StatelessWidget {
  final Map<String, dynamic> slot;

  const _SlotRow({required this.slot});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_fmtDate(slot['coverage_date']?.toString())} · ${slot['day_of_week']} · Period ${slot['period_number']}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 12),
                ),
                Text(
                  '${slot['subject_name']} — ${slot['dept']} Sem ${slot['semester']} ${slot['section']}',
                  style:
                      const TextStyle(fontSize: 11, color: _kSubtext),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: (slot['status'] == 'ACTIVE' ? _kSuccess : _kDanger)
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              slot['status'] as String? ?? '—',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: slot['status'] == 'ACTIVE' ? _kSuccess : _kDanger),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuditRow extends StatelessWidget {
  final Map<String, dynamic> entry;

  const _AuditRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 6, right: 8),
            decoration:
                const BoxDecoration(color: _kPrimary, shape: BoxShape.circle),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry['action'] as String? ?? '—',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                ),
                Text(
                  '${entry['actor_name'] ?? '—'} (${entry['actor_role'] ?? '—'}) · ${_fmtDate(entry['created_at']?.toString().substring(0, 10))}',
                  style:
                      const TextStyle(fontSize: 11, color: _kSubtext),
                ),
                if (entry['remarks'] != null)
                  Text(
                    entry['remarks'] as String,
                    style: const TextStyle(
                        fontSize: 12,
                        color: _kSubtext,
                        fontStyle: FontStyle.italic),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectedAlternateBanner extends StatelessWidget {
  final Map<String, dynamic> alternate;
  final VoidCallback onClear;

  const _SelectedAlternateBanner(
      {required this.alternate, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _kSuccess.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kSuccess.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: _kSuccess, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(alternate['name'] as String? ?? '—',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13)),
                Text(
                    '${alternate['dept']} · ${alternate['role']}',
                    style:
                        const TextStyle(fontSize: 12, color: _kSubtext)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: _kSubtext),
            onPressed: onClear,
          ),
        ],
      ),
    );
  }
}

class _DateButton extends StatelessWidget {
  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  const _DateButton(
      {required this.label, this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fmt =
        value != null ? DateFormat('d MMM yyyy').format(value!) : null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        decoration: BoxDecoration(
          border: Border.all(color: _kBorder),
          borderRadius: BorderRadius.circular(8),
          color: Colors.white,
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined,
                size: 16,
                color: value != null ? _kPrimary : _kSubtext),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                fmt ?? label,
                style: TextStyle(
                    fontSize: 13,
                    color: value != null ? _kText : _kSubtext),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HalfDayToggle extends StatelessWidget {
  final bool isHalfDay;
  final String whichHalf;
  final ValueChanged<bool> onToggle;
  final ValueChanged<String> onHalfChanged;

  const _HalfDayToggle({
    required this.isHalfDay,
    required this.whichHalf,
    required this.onToggle,
    required this.onHalfChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Half-day leave',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          value: isHalfDay,
          activeTrackColor: _kPrimary,
          onChanged: onToggle,
        ),
        if (isHalfDay)
          Row(
            children: [
              _HalfChip(
                label: 'Forenoon (FN)',
                selected: whichHalf == 'FN',
                onTap: () => onHalfChanged('FN'),
              ),
              const SizedBox(width: 8),
              _HalfChip(
                label: 'Afternoon (AN)',
                selected: whichHalf == 'AN',
                onTap: () => onHalfChanged('AN'),
              ),
            ],
          ),
      ],
    );
  }
}

class _HalfChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _HalfChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? _kPrimary.withValues(alpha: 0.12)
              : Colors.transparent,
          border: Border.all(
              color: selected ? _kPrimary : _kBorder),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
              fontSize: 12,
              fontWeight:
                  selected ? FontWeight.w700 : FontWeight.w400,
              color: selected ? _kPrimary : _kSubtext),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner(this.message);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kDanger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kDanger.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: _kDanger, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style:
                    const TextStyle(color: _kDanger, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _EmptyOrError extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const _EmptyOrError({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              onRetry != null
                  ? Icons.error_outline
                  : Icons.inbox_outlined,
              size: 48,
              color: _kBorder,
            ),
            const SizedBox(height: 12),
            Text(message,
                style: const TextStyle(color: _kSubtext, fontSize: 14),
                textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              TextButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}

// Helper
InputDecoration _inputDeco(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: _kSubtext, fontSize: 13),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _kBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _kBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _kPrimary, width: 1.5),
      ),
      filled: true,
      fillColor: Colors.white,
    );
