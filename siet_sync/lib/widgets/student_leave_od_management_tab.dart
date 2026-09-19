import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../config/college_ip_config.dart';

class StudentLeaveODManagementTab extends StatefulWidget {
  final String token;
  final Map<String, dynamic> user;
  final bool isAdmin;
  final bool isHod;
  final bool isStaff;
  final String? defaultDept;

  const StudentLeaveODManagementTab({
    super.key,
    required this.token,
    required this.user,
    this.isAdmin = false,
    this.isHod = false,
    this.isStaff = false,
    this.defaultDept,
  });

  @override
  State<StudentLeaveODManagementTab> createState() =>
      _StudentLeaveODManagementTabState();
}

class _StudentLeaveODManagementTabState
    extends State<StudentLeaveODManagementTab> {
  // Theme Colors
  static const Color primaryBlue = Color(0xFF2563EB);
  static const Color secondaryIndigo = Color(0xFF4F46E5);
  static const Color emeraldGreen = Color(0xFF10B981);
  static const Color amberWarning = Color(0xFFF59E0B);
  static const Color roseDanger = Color(0xFFEF4444);
  static const Color violetAccent = Color(0xFF8B5CF6);

  List<dynamic> _requests = [];
  Map<String, dynamic> _analytics = {};
  bool _isLoading = true;
  String? _errorMessage;

  // Sub-Section Control: 0 = Pending Approvals, 1 = History & Past Records
  int _currentSubTab = 0;
  String _historyStatusFilter = 'ALL';

  // Filters
  String _selectedDept = 'ALL';
  String _selectedBatch = 'ALL';
  String _selectedStatus = 'ALL';
  String _selectedType = 'ALL';
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  // Multi-select for Bulk Admin Actions
  final Set<int> _selectedIds = {};
  bool _isBulkProcessing = false;

  final List<String> _departments = [
    'ALL',
    'CSE',
    'ECE',
    'EEE',
    'MECH',
    'CIVIL',
    'IT',
    'AIDS',
    'AIML',
    'CSBS',
    'BME',
    'AGRI',
  ];

  final List<String> _batches = [
    'ALL',
    '2021-2025',
    '2022-2026',
    '2023-2027',
    '2024-2028',
    '2025-2029',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.isHod && widget.defaultDept != null && widget.defaultDept!.isNotEmpty) {
      _selectedDept = widget.defaultDept!.toUpperCase().trim();
    } else if (widget.isStaff && widget.defaultDept != null && widget.defaultDept!.isNotEmpty) {
      _selectedDept = widget.defaultDept!.toUpperCase().trim();
    }
    _fetchData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (widget.isAdmin) {
        await Future.wait([
          _fetchAdminList(),
          _fetchAdminAnalytics(),
        ]);
      } else if (widget.isHod) {
        await _fetchHodList();
      } else {
        await _fetchStaffList();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = "Failed to load leave & OD data: $e";
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _fetchAdminList() async {
    final statusParam = _currentSubTab == 1
        ? (_historyStatusFilter == 'ALL' ? 'HISTORY' : _historyStatusFilter)
        : (_selectedStatus == 'ALL' ? 'PENDING_ADVISOR' : _selectedStatus);

    final queryParams = <String, String>{
      'dept': _selectedDept,
      'batch': _selectedBatch,
      'status': statusParam,
      'req_type': _selectedType,
      'limit': '200',
    };
    if (_searchQuery.trim().isNotEmpty) {
      queryParams['search'] = _searchQuery.trim();
    }

    final uri = Uri.parse('${CollegeIPConfig.defaultURL}/admin/student-leave-od/list')
        .replace(queryParameters: queryParams);

    final res = await http.get(uri, headers: {
      'Authorization': 'Bearer ${widget.token}',
    });

    if (res.statusCode == 200) {
      final d = jsonDecode(res.body);
      _requests = d['requests'] ?? [];
    } else {
      throw Exception("Server returned ${res.statusCode}");
    }
  }

  Future<void> _fetchAdminAnalytics() async {
    final uri = Uri.parse('${CollegeIPConfig.defaultURL}/admin/student-leave-od/analytics');
    final res = await http.get(uri, headers: {
      'Authorization': 'Bearer ${widget.token}',
    });
    if (res.statusCode == 200) {
      _analytics = jsonDecode(res.body);
    }
  }

  Future<void> _fetchHodList() async {
    final queryParams = <String, String>{
      'limit': '150',
    };
    if (_selectedBatch != 'ALL') queryParams['batch'] = _selectedBatch;
    if (_historyStatusFilter != 'ALL' && _currentSubTab == 1) {
      queryParams['status'] = _historyStatusFilter;
    }
    if (_searchQuery.trim().isNotEmpty) {
      queryParams['search'] = _searchQuery.trim();
    }

    final path = _currentSubTab == 0
        ? '/hod/student-leave-od/pending'
        : '/hod/student-leave-od/history';

    final uri = Uri.parse('${CollegeIPConfig.defaultURL}$path')
        .replace(queryParameters: queryParams);
    final res = await http.get(uri, headers: {
      'Authorization': 'Bearer ${widget.token}',
    });
    if (res.statusCode == 200) {
      final d = jsonDecode(res.body);
      _requests = d['requests'] ?? [];
    } else {
      throw Exception("HOD request returned ${res.statusCode}");
    }
  }

  Future<void> _fetchStaffList() async {
    final queryParams = <String, String>{
      'limit': '100',
    };
    if (_selectedBatch != 'ALL') queryParams['batch'] = _selectedBatch;
    if (_historyStatusFilter != 'ALL' && _currentSubTab == 1) {
      queryParams['status'] = _historyStatusFilter;
    }
    if (_searchQuery.trim().isNotEmpty) {
      queryParams['search'] = _searchQuery.trim();
    }

    final path = _currentSubTab == 0
        ? '/staff/student-leave-od/pending'
        : '/staff/student-leave-od/history';

    final uri = Uri.parse('${CollegeIPConfig.defaultURL}$path')
        .replace(queryParameters: queryParams);
    final res = await http.get(uri, headers: {
      'Authorization': 'Bearer ${widget.token}',
    });
    if (res.statusCode == 200) {
      final d = jsonDecode(res.body);
      _requests = d['requests'] ?? [];
    } else {
      throw Exception("Staff request returned ${res.statusCode}");
    }
  }

  // ─────────────────────────────────────────────────────────
  // ACTION HANDLERS
  // ─────────────────────────────────────────────────────────
  Future<void> _handleStaffReview(int requestId, String action, String remarks) async {
    try {
      final res = await http.post(
        Uri.parse('${CollegeIPConfig.defaultURL}/staff/student-leave-od/review'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
        body: jsonEncode({
          'request_id': requestId,
          'action': action,
          'remarks': remarks,
        }),
      );

      if (res.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                action == 'RECOMMEND'
                    ? '✅ Request Recommended to HOD'
                    : '❌ Request Rejected',
              ),
              backgroundColor: action == 'RECOMMEND' ? emeraldGreen : roseDanger,
            ),
          );
        }
        _fetchData();
      } else {
        final err = jsonDecode(res.body)['detail'] ?? 'Action failed';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $err'), backgroundColor: roseDanger),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Network error: $e'), backgroundColor: roseDanger),
        );
      }
    }
  }

  Future<void> _handleHodAction(int requestId, String action, String remarks) async {
    try {
      final res = await http.post(
        Uri.parse('${CollegeIPConfig.defaultURL}/hod/student-leave-od/action'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
        body: jsonEncode({
          'request_id': requestId,
          'action': action,
          'remarks': remarks,
        }),
      );

      if (res.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                action == 'APPROVE'
                    ? '✅ Approved! Attendance automatically credited.'
                    : (action == 'REJECT'
                        ? '❌ Request Rejected'
                        : '🔄 Referred back to Advisor'),
              ),
              backgroundColor: action == 'APPROVE'
                  ? emeraldGreen
                  : (action == 'REJECT' ? roseDanger : amberWarning),
            ),
          );
        }
        _fetchData();
      } else {
        final err = jsonDecode(res.body)['detail'] ?? 'Action failed';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $err'), backgroundColor: roseDanger),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Network error: $e'), backgroundColor: roseDanger),
        );
      }
    }
  }

  Future<void> _handleAdminAction(List<int> requestIds, String action, String remarks) async {
    setState(() => _isBulkProcessing = true);
    try {
      final res = await http.post(
        Uri.parse('${CollegeIPConfig.defaultURL}/admin/student-leave-od/action'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
        body: jsonEncode({
          'request_ids': requestIds,
          'action': action,
          'remarks': remarks,
        }),
      );

      if (res.statusCode == 200) {
        _selectedIds.clear();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Successfully processed ${requestIds.length} request(s)'),
              backgroundColor: emeraldGreen,
            ),
          );
        }
        _fetchData();
      } else {
        final err = jsonDecode(res.body)['detail'] ?? 'Action failed';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $err'), backgroundColor: roseDanger),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Network error: $e'), backgroundColor: roseDanger),
        );
      }
    } finally {
      if (mounted) setState(() => _isBulkProcessing = false);
    }
  }

  Future<void> _exportCsv() async {
    try {
      final uri = Uri.parse(
          '${CollegeIPConfig.defaultURL}/admin/student-leave-od/export?dept=$_selectedDept');
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to download CSV: $e'), backgroundColor: roseDanger),
        );
      }
    }
  }

  void _showActionDialog({
    required int requestId,
    required String studentName,
    required String requestType,
    required String dates,
    required bool isStaffReview,
    required bool isHodReview,
    required bool isAdminReview,
  }) {
    final remarksCtrl = TextEditingController();
    String selectedAction = isStaffReview
        ? 'RECOMMEND'
        : (isHodReview ? 'APPROVE' : 'APPROVE');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: primaryBlue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.rate_review_rounded, color: primaryBlue, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isStaffReview
                        ? 'Class Advisor Endorsement'
                        : (isHodReview ? 'HOD Decision' : 'Admin Decision'),
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 17),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          studentName,
                          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$requestType • $dates',
                          style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Select Action:',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  if (isStaffReview) ...[
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'RECOMMEND',
                          label: Text('Recommend'),
                          icon: Icon(Icons.check_circle_outline, color: emeraldGreen),
                        ),
                        ButtonSegment(
                          value: 'REJECT',
                          label: Text('Reject'),
                          icon: Icon(Icons.cancel_outlined, color: roseDanger),
                        ),
                      ],
                      selected: {selectedAction},
                      onSelectionChanged: (set) => setDialogState(() => selectedAction = set.first),
                    ),
                  ] else if (isHodReview) ...[
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'APPROVE',
                          label: Text('Approve'),
                          icon: Icon(Icons.verified_outlined, color: emeraldGreen),
                        ),
                        ButtonSegment(
                          value: 'REFER_BACK',
                          label: Text('Refer Back'),
                          icon: Icon(Icons.replay_rounded, color: amberWarning),
                        ),
                        ButtonSegment(
                          value: 'REJECT',
                          label: Text('Reject'),
                          icon: Icon(Icons.block_rounded, color: roseDanger),
                        ),
                      ],
                      selected: {selectedAction},
                      onSelectionChanged: (set) => setDialogState(() => selectedAction = set.first),
                    ),
                  ] else ...[
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'APPROVE',
                          label: Text('Override Approve'),
                          icon: Icon(Icons.check_circle_rounded, color: emeraldGreen),
                        ),
                        ButtonSegment(
                          value: 'REJECT',
                          label: Text('Reject'),
                          icon: Icon(Icons.cancel_rounded, color: roseDanger),
                        ),
                      ],
                      selected: {selectedAction},
                      onSelectionChanged: (set) => setDialogState(() => selectedAction = set.first),
                    ),
                  ],
                  const SizedBox(height: 14),
                  TextField(
                    controller: remarksCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Remarks / Feedback Notes',
                      hintText: isStaffReview
                          ? 'e.g. Verified symposium certificate, good attendance record.'
                          : 'e.g. Approved for state-level hackathon. Attendance credited.',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: selectedAction == 'APPROVE' || selectedAction == 'RECOMMEND'
                      ? emeraldGreen
                      : (selectedAction == 'REFER_BACK' ? amberWarning : roseDanger),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  final rem = remarksCtrl.text.trim();
                  if (isStaffReview) {
                    _handleStaffReview(requestId, selectedAction, rem);
                  } else if (isHodReview) {
                    _handleHodAction(requestId, selectedAction, rem);
                  } else {
                    _handleAdminAction([requestId], selectedAction, rem);
                  }
                },
                child: Text('Confirm $selectedAction'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // UI BUILDERS
  // ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return RefreshIndicator(
      onRefresh: _fetchData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Header Banner
            _buildRoleHeaderBanner(isDark),
            const SizedBox(height: 16),

            // 2. Admin KPI Analytics Cards (if Admin)
            if (widget.isAdmin && _analytics.isNotEmpty) ...[
              _buildKpiMetricsGrid(isDark),
              const SizedBox(height: 16),
            ],

            // 3. Sub-Section Switcher (Pending Approvals vs History Records)
            _buildSubSectionBar(isDark),
            const SizedBox(height: 14),

            // 4. History Quick Status Chips (if in History mode)
            if (_currentSubTab == 1) ...[
              _buildHistoryFilterChips(isDark),
              const SizedBox(height: 14),
            ],

            // 5. Search & Filter Bar
            _buildFilterBar(isDark),
            const SizedBox(height: 16),

            // 6. Requests List or Empty State
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: CircularProgressIndicator(color: primaryBlue),
                ),
              )
            else if (_errorMessage != null)
              _buildErrorBanner(isDark)
            else if (_requests.isEmpty)
              _buildEmptyState(isDark)
            else
              ..._requests.map((r) => _buildRequestCard(r, isDark)),
          ],
        ),
      ),
    );
  }

  Widget _buildSubSectionBar(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade300),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: _buildSubTabButton(
              index: 0,
              title: 'Pending Approvals',
              icon: Icons.pending_actions_rounded,
              color: amberWarning,
              isDark: isDark,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildSubTabButton(
              index: 1,
              title: 'History & Records',
              icon: Icons.history_edu_rounded,
              color: primaryBlue,
              isDark: isDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubTabButton({
    required int index,
    required String title,
    required IconData icon,
    required Color color,
    required bool isDark,
  }) {
    final isSelected = _currentSubTab == index;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        if (_currentSubTab != index) {
          setState(() {
            _currentSubTab = index;
            _selectedIds.clear();
          });
          _fetchData();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? const Color(0xFF334155) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? color : (isDark ? Colors.white60 : Colors.grey.shade600),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected
                      ? (isDark ? Colors.white : Colors.black87)
                      : (isDark ? Colors.white60 : Colors.grey.shade600),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryFilterChips(bool isDark) {
    final filters = [
      {'label': 'All History', 'value': 'ALL'},
      {'label': 'Approved', 'value': 'APPROVED'},
      if (widget.isStaff || widget.isAdmin) {'label': 'Recommended', 'value': 'RECOMMENDED'},
      {'label': 'Rejected', 'value': 'REJECTED'},
      if (widget.isHod || widget.isAdmin) {'label': 'Referred Back', 'value': 'REFERRED_BACK'},
      {'label': 'Cancelled', 'value': 'CANCELLED'},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((f) {
          final isSelected = _historyStatusFilter == f['value'];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(f['label']!),
              selected: isSelected,
              onSelected: (sel) {
                if (sel) {
                  setState(() => _historyStatusFilter = f['value']!);
                  _fetchData();
                }
              },
              selectedColor: primaryBlue,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.grey.shade700),
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 11.5,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _showTimelineDialog(int requestId, String studentName, String reqType) async {
    showDialog(
      context: context,
      builder: (ctx) => _LeaveODTimelineDialog(
        token: widget.token,
        requestId: requestId,
        studentName: studentName,
        requestType: reqType,
        isAdmin: widget.isAdmin,
      ),
    );
  }

  Widget _buildRoleHeaderBanner(bool isDark) {
    String title = "Student Leave & On-Duty Management";
    String subtitle = "Institutional multi-level approval pipeline with automatic attendance sync.";
    IconData icon = Icons.approval_rounded;

    if (widget.isStaff) {
      title = "Class Advisor • Leave & OD Endorsement";
      subtitle = "Review and recommend applications submitted by students in your class.";
      icon = Icons.assignment_ind_rounded;
    } else if (widget.isHod) {
      title = "HOD • Departmental Leave & OD Decision";
      subtitle = "Authorize departmental ODs and Leaves with instant attendance crediting.";
      icon = Icons.verified_user_rounded;
    } else if (widget.isAdmin) {
      title = "Central Administration • Student Leave & OD Hub";
      subtitle = "Cross-departmental oversight, bulk processing, and attendance audits.";
      icon = Icons.account_balance_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
              : [primaryBlue, secondaryIndigo],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: primaryBlue.withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (widget.isAdmin) ...[
            IconButton(
              icon: const Icon(Icons.download_rounded, color: Colors.white),
              tooltip: 'Export CSV',
              onPressed: _exportCsv,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildKpiMetricsGrid(bool isDark) {
    final total = _analytics['total_requests'] ?? 0;
    final pendAdv = _analytics['pending_advisor'] ?? 0;
    final pendHod = _analytics['pending_hod'] ?? 0;
    final approved = _analytics['total_approved'] ?? 0;
    final activeOd = _analytics['active_od_today'] ?? 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 700;

        return GridView.count(
          crossAxisCount: isNarrow ? 2 : 5,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: isNarrow ? 1.7 : 2.0,
          children: [
            _buildMetricTile('Total Submissions', '$total', Icons.folder_open_rounded, primaryBlue, isDark),
            _buildMetricTile('Pending Advisor', '$pendAdv', Icons.hourglass_top_rounded, amberWarning, isDark),
            _buildMetricTile('Pending HOD', '$pendHod', Icons.pending_actions_rounded, secondaryIndigo, isDark),
            _buildMetricTile('Active ODs Today', '$activeOd', Icons.directions_walk_rounded, violetAccent, isDark),
            _buildMetricTile('Total Approved', '$approved', Icons.check_circle_rounded, emeraldGreen, isDark),
          ],
        );
      },
    );
  }

  Widget _buildMetricTile(String label, String value, IconData icon, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: color),
                ),
                Text(
                  label,
                  style: GoogleFonts.inter(fontSize: 10.5, color: Colors.grey.shade500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
      ),
      child: Column(
        children: [
          // Search Box & Actions
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search student name, reg no, or reason...',
                    hintStyle: GoogleFonts.inter(fontSize: 13),
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _searchQuery = '');
                              _fetchData();
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300),
                    ),
                  ),
                  onSubmitted: (v) {
                    setState(() => _searchQuery = v);
                    _fetchData();
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Refresh',
                onPressed: _fetchData,
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Dropdown Filters
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (widget.isAdmin)
                _buildDropdownFilter(
                  label: 'Dept',
                  value: _selectedDept,
                  items: _departments,
                  onChanged: (v) {
                    setState(() => _selectedDept = v!);
                    _fetchData();
                  },
                  isDark: isDark,
                ),
              _buildDropdownFilter(
                label: 'Batch',
                value: _selectedBatch,
                items: _batches,
                onChanged: (v) {
                  setState(() => _selectedBatch = v!);
                  _fetchData();
                },
                isDark: isDark,
              ),
              _buildDropdownFilter(
                label: 'Type',
                value: _selectedType,
                items: const ['ALL', 'ON_DUTY', 'MEDICAL_LEAVE', 'CASUAL_LEAVE', 'EMERGENCY_LEAVE'],
                onChanged: (v) {
                  setState(() => _selectedType = v!);
                  _fetchData();
                },
                isDark: isDark,
              ),
              if (widget.isAdmin)
                _buildDropdownFilter(
                  label: 'Hierarchy Status',
                  value: _selectedStatus,
                  items: const ['ALL', 'PENDING_ADVISOR', 'PENDING_HOD', 'APPROVED', 'REJECTED'],
                  onChanged: (v) {
                    setState(() => _selectedStatus = v!);
                    _fetchData();
                  },
                  isDark: isDark,
                ),
            ],
          ),

          // Bulk Actions for Admin
          if (widget.isAdmin && _selectedIds.isNotEmpty) ...[
            const Divider(height: 20),
            Row(
              children: [
                Text(
                  '${_selectedIds.length} item(s) selected',
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: emeraldGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  icon: const Icon(Icons.check_circle_rounded, size: 16),
                  label: const Text('Bulk Approve'),
                  onPressed: _isBulkProcessing
                      ? null
                      : () => _handleAdminAction(
                            _selectedIds.toList(),
                            'APPROVE',
                            'Bulk Approved by Central Admin',
                          ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: roseDanger,
                    side: const BorderSide(color: roseDanger),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  icon: const Icon(Icons.cancel_rounded, size: 16),
                  label: const Text('Bulk Reject'),
                  onPressed: _isBulkProcessing
                      ? null
                      : () => _handleAdminAction(
                            _selectedIds.toList(),
                            'REJECT',
                            'Bulk Rejected by Central Admin',
                          ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDropdownFilter({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black87,
          ),
          items: items
              .map((it) => DropdownMenuItem(
                    value: it,
                    child: Text('$label: ${it.replaceAll('_', ' ')}'),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildRequestCard(dynamic r, bool isDark) {
    final reqId = (r['id'] ?? 0) as int;
    final name = (r['student_name'] ?? 'Student').toString();
    final regNo = (r['student_reg_no'] ?? '').toString();
    final dept = (r['dept'] ?? 'CSE').toString();
    final batch = (r['batch'] ?? '').toString();
    final sem = (r['semester'] ?? '').toString();
    final sec = (r['section'] ?? 'A').toString();

    final reqType = (r['request_type'] ?? 'ON_DUTY').toString();
    final category = (r['category'] ?? 'General').toString();
    final startDate = (r['start_date'] ?? '').toString();
    final endDate = (r['end_date'] ?? startDate).toString();
    final sessionHalf = (r['session_half'] ?? 'FULL_DAY').toString();
    final reason = (r['reason'] ?? '').toString();
    final docUrl = (r['document_proof_url'] ?? '').toString();

    final mentorStatus = (r['mentor_status'] ?? 'PENDING').toString();
    final mentorName = (r['mentor_name'] ?? 'Class Advisor').toString();
    final mentorRemarks = (r['mentor_remarks'] ?? '').toString();

    final hodStatus = (r['hod_status'] ?? 'PENDING').toString();
    final hodName = (r['hod_name'] ?? 'Head of Department').toString();
    final hodRemarks = (r['hod_remarks'] ?? '').toString();

    final adminStatus = (r['admin_status'] ?? 'PENDING').toString();
    final isCredited = r['is_attendance_credited'] == true || hodStatus == 'APPROVED' || adminStatus == 'APPROVED';
    final attPct = double.tryParse((r['attendance_percentage'] ?? 100.0).toString()) ?? 100.0;

    final isSelected = _selectedIds.contains(reqId);

    // Color theme based on request type
    Color typeColor = primaryBlue;
    if (reqType == 'MEDICAL_LEAVE') {
      typeColor = emeraldGreen;
    } else if (reqType == 'CASUAL_LEAVE') {
      typeColor = amberWarning;
    } else if (reqType == 'EMERGENCY_LEAVE') {
      typeColor = roseDanger;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected
              ? primaryBlue
              : (isDark ? Colors.white12 : Colors.grey.shade200),
          width: isSelected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card Top Banner (Student Details + Type Badge)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: typeColor.withValues(alpha: isDark ? 0.12 : 0.06),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(19)),
            ),
            child: Row(
              children: [
                if (widget.isAdmin) ...[
                  Checkbox(
                    value: isSelected,
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _selectedIds.add(reqId);
                        } else {
                          _selectedIds.remove(reqId);
                        }
                      });
                    },
                  ),
                ],
                CircleAvatar(
                  radius: 18,
                  backgroundColor: typeColor.withValues(alpha: 0.2),
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : 'S',
                    style: TextStyle(fontWeight: FontWeight.bold, color: typeColor, fontSize: 14),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      Text(
                        '$regNo • $dept - Sem $sem ($sec) • $batch',
                        style: GoogleFonts.inter(fontSize: 11.5, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                // Attendance Standing Pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (attPct >= 75 ? emeraldGreen : roseDanger).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$attPct% Attd',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: attPct >= 75 ? emeraldGreen : roseDanger,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Card Body
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Request Type & Date Span
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: typeColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: typeColor.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        '${reqType.replaceAll('_', ' ')} ($category)',
                        style: TextStyle(color: typeColor, fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.date_range_rounded, size: 13, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(
                            startDate == endDate ? startDate : '$startDate to $endDate',
                            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '• $sessionHalf',
                            style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                    ),
                    if (isCredited)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: emeraldGreen.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_circle_rounded, size: 12, color: emeraldGreen),
                            const SizedBox(width: 4),
                            Text(
                              'Attendance Credited',
                              style: GoogleFonts.inter(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: emeraldGreen,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),

                // Reason
                Text(
                  'Reason: $reason',
                  style: GoogleFonts.inter(fontSize: 13, height: 1.35),
                ),
                if (docUrl.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () async {
                      try {
                        await launchUrl(Uri.parse(docUrl), mode: LaunchMode.externalApplication);
                      } catch (e) {
                        debugPrint("Error opening URL: $e");
                      }
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.attachment_rounded, size: 14, color: primaryBlue),
                        const SizedBox(width: 4),
                        Text(
                          'View Supporting Proof / Letter',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: primaryBlue,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),

                // ─────────────────────────────────────────────────────────
                // 3-STAGE HIERARCHY PIPELINE STEPPER
                // ─────────────────────────────────────────────────────────
                _buildHierarchyStepper(
                  mentorStatus: mentorStatus,
                  mentorName: mentorName,
                  mentorRemarks: mentorRemarks,
                  hodStatus: hodStatus,
                  hodName: hodName,
                  hodRemarks: hodRemarks,
                  adminStatus: adminStatus,
                  isCredited: isCredited,
                  isDark: isDark,
                ),
                const SizedBox(height: 14),

                // ─────────────────────────────────────────────────────────
                // ACTION BUTTONS (Role-Aware & Sub-Section Aware)
                // ─────────────────────────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // View Full Audit Trail Button
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: primaryBlue,
                        side: BorderSide(color: primaryBlue.withValues(alpha: 0.4)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      ),
                      icon: const Icon(Icons.timeline_rounded, size: 15),
                      label: const Text('Audit Trail', style: TextStyle(fontSize: 12)),
                      onPressed: () => _showTimelineDialog(reqId, name, reqType),
                    ),

                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_currentSubTab == 0) ...[
                          if (widget.isStaff && mentorStatus == 'PENDING') ...[
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: roseDanger,
                                side: const BorderSide(color: roseDanger),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.cancel_outlined, size: 16),
                              label: const Text('Reject'),
                              onPressed: () => _showActionDialog(
                                requestId: reqId,
                                studentName: name,
                                requestType: reqType,
                                dates: startDate == endDate ? startDate : '$startDate to $endDate',
                                isStaffReview: true,
                                isHodReview: false,
                                isAdminReview: false,
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: emeraldGreen,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.check_circle_outline, size: 16),
                              label: const Text('Recommend to HOD'),
                              onPressed: () => _showActionDialog(
                                requestId: reqId,
                                studentName: name,
                                requestType: reqType,
                                dates: startDate == endDate ? startDate : '$startDate to $endDate',
                                isStaffReview: true,
                                isHodReview: false,
                                isAdminReview: false,
                              ),
                            ),
                          ] else if (widget.isHod && hodStatus == 'PENDING') ...[
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: amberWarning,
                                side: const BorderSide(color: amberWarning),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: () => _showActionDialog(
                                requestId: reqId,
                                studentName: name,
                                requestType: reqType,
                                dates: startDate == endDate ? startDate : '$startDate to $endDate',
                                isStaffReview: false,
                                isHodReview: true,
                                isAdminReview: false,
                              ),
                              child: const Text('Refer Back'),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: roseDanger,
                                side: const BorderSide(color: roseDanger),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: () => _showActionDialog(
                                requestId: reqId,
                                studentName: name,
                                requestType: reqType,
                                dates: startDate == endDate ? startDate : '$startDate to $endDate',
                                isStaffReview: false,
                                isHodReview: true,
                                isAdminReview: false,
                              ),
                              child: const Text('Reject'),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: emeraldGreen,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.verified_rounded, size: 16),
                              label: const Text('Approve & Credit'),
                              onPressed: () => _showActionDialog(
                                requestId: reqId,
                                studentName: name,
                                requestType: reqType,
                                dates: startDate == endDate ? startDate : '$startDate to $endDate',
                                isStaffReview: false,
                                isHodReview: true,
                                isAdminReview: false,
                              ),
                            ),
                          ] else if (widget.isAdmin) ...[
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primaryBlue,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.admin_panel_settings_rounded, size: 16),
                              label: const Text('Admin Decision'),
                              onPressed: () => _showActionDialog(
                                requestId: reqId,
                                studentName: name,
                                requestType: reqType,
                                dates: startDate == endDate ? startDate : '$startDate to $endDate',
                                isStaffReview: false,
                                isHodReview: false,
                                isAdminReview: true,
                              ),
                            ),
                          ],
                        ] else ...[
                          // History Resolution Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: (hodStatus == 'APPROVED' || adminStatus == 'APPROVED'
                                      ? emeraldGreen
                                      : (mentorStatus == 'REJECTED' || hodStatus == 'REJECTED' || adminStatus == 'REJECTED'
                                          ? roseDanger
                                          : (mentorStatus == 'RECOMMENDED'
                                              ? secondaryIndigo
                                              : (mentorStatus == 'CANCELLED' || hodStatus == 'CANCELLED'
                                                  ? Colors.grey
                                                  : amberWarning))))
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              hodStatus == 'APPROVED' || adminStatus == 'APPROVED'
                                  ? '✓ Processed & Approved'
                                  : (mentorStatus == 'REJECTED' || hodStatus == 'REJECTED' || adminStatus == 'REJECTED'
                                      ? '✗ Rejected Record'
                                      : (mentorStatus == 'RECOMMENDED'
                                          ? '→ Endorsed to HOD'
                                          : (mentorStatus == 'CANCELLED' || hodStatus == 'CANCELLED'
                                              ? '🚫 Cancelled'
                                              : 'Status: $hodStatus'))),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: hodStatus == 'APPROVED' || adminStatus == 'APPROVED'
                                    ? emeraldGreen
                                    : (mentorStatus == 'REJECTED' || hodStatus == 'REJECTED' || adminStatus == 'REJECTED'
                                        ? roseDanger
                                        : (mentorStatus == 'RECOMMENDED'
                                            ? secondaryIndigo
                                            : (mentorStatus == 'CANCELLED' || hodStatus == 'CANCELLED'
                                                ? Colors.grey
                                                : amberWarning))),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHierarchyStepper({
    required String mentorStatus,
    required String mentorName,
    required String mentorRemarks,
    required String hodStatus,
    required String hodName,
    required String hodRemarks,
    required String adminStatus,
    required bool isCredited,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'APPROVAL HIERARCHY STATUS',
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.6,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              // Step 1: Student Submission
              _buildStepItem(
                stepNo: '1',
                title: 'Student',
                status: 'Applied',
                statusColor: emeraldGreen,
                isCompleted: true,
              ),
              _buildStepConnector(isCompleted: true),

              // Step 2: Class Advisor
              _buildStepItem(
                stepNo: '2',
                title: 'Advisor',
                subtitle: mentorName,
                status: mentorStatus,
                remarks: mentorRemarks,
                statusColor: mentorStatus == 'RECOMMENDED'
                    ? emeraldGreen
                    : (mentorStatus == 'REJECTED' ? roseDanger : amberWarning),
                isCompleted: mentorStatus == 'RECOMMENDED',
              ),
              _buildStepConnector(isCompleted: mentorStatus == 'RECOMMENDED'),

              // Step 3: Head of Department
              _buildStepItem(
                stepNo: '3',
                title: 'HOD',
                subtitle: hodName,
                status: hodStatus,
                remarks: hodRemarks,
                statusColor: hodStatus == 'APPROVED'
                    ? emeraldGreen
                    : (hodStatus == 'REJECTED'
                        ? roseDanger
                        : (hodStatus == 'REFERRED_BACK' ? amberWarning : Colors.grey)),
                isCompleted: hodStatus == 'APPROVED',
              ),
              _buildStepConnector(isCompleted: isCredited),

              // Step 4: Attendance Credited
              _buildStepItem(
                stepNo: '4',
                title: 'Attendance',
                status: isCredited ? 'Credited' : 'Pending',
                statusColor: isCredited ? emeraldGreen : Colors.grey,
                isCompleted: isCredited,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStepItem({
    required String stepNo,
    required String title,
    String? subtitle,
    required String status,
    String? remarks,
    required Color statusColor,
    required bool isCompleted,
  }) {
    return Expanded(
      child: Tooltip(
        message: remarks != null && remarks.isNotEmpty
            ? '$title remarks: "$remarks"'
            : '$title: $status',
        child: Column(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isCompleted ? statusColor : statusColor.withValues(alpha: 0.15),
                border: Border.all(color: statusColor, width: 1.5),
              ),
              child: Center(
                child: isCompleted
                    ? const Icon(Icons.check, size: 12, color: Colors.white)
                    : Text(
                        stepNo,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              status.replaceAll('_', ' '),
              style: GoogleFonts.inter(
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                color: statusColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepConnector({required bool isCompleted}) {
    return Container(
      width: 14,
      height: 2,
      color: isCompleted ? emeraldGreen : Colors.grey.shade300,
      margin: const EdgeInsets.only(bottom: 18),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 20),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.assignment_turned_in_outlined, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            'No Student Leave or OD Requests Found',
            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'All submitted student applications are currently cleared.',
            style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: roseDanger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: roseDanger.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: roseDanger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorMessage ?? 'An error occurred',
              style: const TextStyle(color: roseDanger, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: _fetchData,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _LeaveODTimelineDialog extends StatefulWidget {
  final String token;
  final int requestId;
  final String studentName;
  final String requestType;
  final bool isAdmin;

  const _LeaveODTimelineDialog({
    required this.token,
    required this.requestId,
    required this.studentName,
    required this.requestType,
    required this.isAdmin,
  });

  @override
  State<_LeaveODTimelineDialog> createState() => _LeaveODTimelineDialogState();
}

class _LeaveODTimelineDialogState extends State<_LeaveODTimelineDialog> {
  bool _isLoading = true;
  String? _error;
  List<dynamic> _timeline = [];

  @override
  void initState() {
    super.initState();
    _fetchTimeline();
  }

  Future<void> _fetchTimeline() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final endpoint = widget.isAdmin
          ? '${CollegeIPConfig.defaultURL}/admin/student-leave-od/${widget.requestId}/audit-trail'
          : '${CollegeIPConfig.defaultURL}/staff/student-leave-od/${widget.requestId}/timeline';

      final res = await http.get(
        Uri.parse(endpoint),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );

      if (res.statusCode == 200) {
        final d = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            _timeline = (d['timeline'] ?? d['audit_trail'] ?? []) as List<dynamic>;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _error = 'Failed to load timeline (Status: ${res.statusCode})';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Network error: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 650),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.timeline_rounded, color: Color(0xFF2563EB), size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Audit Trail & Lifecycle Timeline',
                        style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 17),
                      ),
                      Text(
                        '${widget.studentName} • ${widget.requestType.replaceAll('_', ' ')} (Req #${widget.requestId})',
                        style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),

            // Content
            Flexible(
              child: _isLoading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: CircularProgressIndicator(color: Color(0xFF2563EB)),
                      ),
                    )
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(_error!, style: const TextStyle(color: Color(0xFFEF4444))),
                          ),
                        )
                      : _timeline.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(30),
                                child: Text(
                                  'No audit records found for this request.',
                                  style: GoogleFonts.inter(color: Colors.grey.shade500),
                                ),
                              ),
                            )
                          : SingleChildScrollView(
                              child: Column(
                                children: _timeline.asMap().entries.map((entry) {
                                  final idx = entry.key;
                                  final item = entry.value;
                                  final isLast = idx == _timeline.length - 1;
                                  return _buildTimelineStepItem(idx + 1, item, isLast, isDark);
                                }).toList(),
                              ),
                            ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineStepItem(int stepNo, dynamic item, bool isLast, bool isDark) {
    final action = (item['action'] ?? '').toString();
    final role = (item['actor_role'] ?? '').toString();
    final actorName = (item['actor_name'] ?? 'System').toString();
    final remarks = (item['remarks'] ?? '').toString();
    final timestamp = (item['timestamp'] ?? item['created_at'] ?? '').toString();

    Color stepColor = const Color(0xFF2563EB);
    IconData stepIcon = Icons.info_outline_rounded;

    if (action.contains('SUBMIT')) {
      stepColor = const Color(0xFF4F46E5);
      stepIcon = Icons.send_rounded;
    } else if (action.contains('RECOMMEND')) {
      stepColor = const Color(0xFF10B981);
      stepIcon = Icons.recommend_rounded;
    } else if (action.contains('APPROVED')) {
      stepColor = const Color(0xFF10B981);
      stepIcon = Icons.verified_rounded;
    } else if (action.contains('ATTENDANCE_CREDITED')) {
      stepColor = const Color(0xFF059669);
      stepIcon = Icons.event_available_rounded;
    } else if (action.contains('REJECT')) {
      stepColor = const Color(0xFFEF4444);
      stepIcon = Icons.cancel_rounded;
    } else if (action.contains('REFER')) {
      stepColor = const Color(0xFFF59E0B);
      stepIcon = Icons.replay_rounded;
    } else if (action.contains('CANCEL')) {
      stepColor = const Color(0xFF6B7280);
      stepIcon = Icons.block_rounded;
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step Icon and Connecting Line
          Column(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: stepColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: stepColor, width: 2),
                ),
                child: Center(
                  child: Icon(stepIcon, size: 16, color: stepColor),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: Colors.grey.shade300,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),

          // Details Card
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: stepColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          action.replaceAll('_', ' '),
                          style: TextStyle(
                            color: stepColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      Text(
                        timestamp.length > 19 ? timestamp.substring(0, 19) : timestamp,
                        style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.person_outline_rounded, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        '$actorName ($role)',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12),
                      ),
                    ],
                  ),
                  if (remarks.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Remarks: "$remarks"',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
