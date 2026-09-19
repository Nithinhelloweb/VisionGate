import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/face_verification_service.dart';

class StudentFaceRequestsManagementTab extends StatefulWidget {
  final String token;
  final Map<String, dynamic> user;
  final bool isAdmin;
  final bool isHod;
  final bool isStaff;
  final String? defaultDept;

  const StudentFaceRequestsManagementTab({
    super.key,
    required this.token,
    required this.user,
    this.isAdmin = false,
    this.isHod = false,
    this.isStaff = true,
    this.defaultDept,
  });

  @override
  State<StudentFaceRequestsManagementTab> createState() =>
      _StudentFaceRequestsManagementTabState();
}

class _StudentFaceRequestsManagementTabState
    extends State<StudentFaceRequestsManagementTab> {
  // Theme Palette
  static const Color primaryBlue = Color(0xFF2563EB);
  static const Color secondaryIndigo = Color(0xFF4F46E5);
  static const Color emeraldGreen = Color(0xFF10B981);
  static const Color amberWarning = Color(0xFFF59E0B);
  static const Color roseDanger = Color(0xFFEF4444);
  static const Color violetAccent = Color(0xFF8B5CF6);

  List<dynamic> _requests = [];
  Map<String, dynamic> _stats = {
    'total_pending': 0,
    'approved_today': 0,
    'total_rejected': 0,
    'total_students_requested': 0,
  };
  bool _isLoading = true;
  String? _errorMessage;

  // Filters
  String _selectedStatus = 'ALL';
  String _selectedType = 'ALL';
  String _selectedDept = 'ALL';
  String _selectedBatch = 'ALL';
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  // Multi-Selection
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
    if ((widget.isHod || widget.isStaff) &&
        widget.defaultDept != null &&
        widget.defaultDept!.isNotEmpty) {
      _selectedDept = widget.defaultDept!.toUpperCase().trim();
    }
    _fetchRequests();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchRequests() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await FaceVerificationService.getStaffStudentFaceRequests(
        token: widget.token,
        status: _selectedStatus,
        requestType: _selectedType,
        search: _searchQuery,
        dept: _selectedDept,
        batch: _selectedBatch,
        limit: 200,
      );

      if (!mounted) return;
      if (res['success'] == true || res.containsKey('requests')) {
        setState(() {
          _requests = (res['requests'] as List?) ?? [];
          if (res['stats'] != null && res['stats'] is Map) {
            _stats = Map<String, dynamic>.from(res['stats']);
          }
          _selectedIds.clear();
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = res['error'] ?? res['message'] ?? 'Failed to load face requests';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error loading face requests: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _handleReview({
    required int requestId,
    required String action,
    String? feedback,
    String? studentName,
  }) async {
    try {
      final res = await FaceVerificationService.reviewStudentFaceRequest(
        token: widget.token,
        requestId: requestId,
        action: action,
        feedback: feedback,
      );

      if (!mounted) return;
      if (res['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              res['message'] ??
                  'Request #$requestId ${action == 'APPROVE' ? 'approved' : 'rejected'}.',
            ),
            backgroundColor:
                action == 'APPROVE' ? emeraldGreen : roseDanger,
            behavior: SnackBarBehavior.floating,
          ),
        );
        _fetchRequests();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message'] ?? 'Action failed.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error reviewing request: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _handleBulkReview(String action) async {
    if (_selectedIds.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          action == 'APPROVE'
              ? 'Bulk Approve ${_selectedIds.length} Requests?'
              : 'Bulk Reject ${_selectedIds.length} Requests?',
        ),
        content: Text(
          action == 'APPROVE'
              ? 'This will immediately unlock face re-registration permission for all ${_selectedIds.length} selected students.'
              : 'This will decline all ${_selectedIds.length} selected face requests.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  action == 'APPROVE' ? emeraldGreen : roseDanger,
              foregroundColor: Colors.white,
            ),
            child: Text(action == 'APPROVE' ? 'Approve All' : 'Reject All'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isBulkProcessing = true);
    try {
      final res = await FaceVerificationService.bulkReviewStudentFaceRequests(
        token: widget.token,
        requestIds: _selectedIds.toList(),
        action: action,
        feedback: action == 'APPROVE'
            ? 'Batch approved by Class Advisor / Department'
            : 'Batch declined by Class Advisor / Department',
      );

      if (!mounted) return;
      if (res['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message'] ?? 'Bulk review completed.'),
            backgroundColor:
                action == 'APPROVE' ? emeraldGreen : roseDanger,
            behavior: SnackBarBehavior.floating,
          ),
        );
        _fetchRequests();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message'] ?? 'Bulk review failed.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Bulk action error: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isBulkProcessing = false);
      }
    }
  }

  void _showReviewFeedbackModal(Map<String, dynamic> request) {
    final reqId = request['id'] as int;
    final name = (request['student_name'] ?? 'Student').toString();
    final regNo = (request['student_reg_no'] ?? '').toString();
    final type = (request['request_type'] ?? 'REREGISTRATION_PERMISSION').toString();
    final notes = (request['student_notes'] ?? '').toString();
    final feedbackCtrl = TextEditingController(text: request['advisor_feedback'] ?? '');

    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Title & Student
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: primaryBlue.withValues(alpha: 0.12),
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : 'S',
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: primaryBlue,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: GoogleFonts.outfit(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          'Reg No: $regNo • Dept: ${request['dept']} • Sem: ${request['semester'] ?? '-'} (${request['section'] ?? '-'})',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white60 : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Student Request details box
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? Colors.white10 : Colors.grey.shade200,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          type == 'IN_PERSON_SESSION'
                              ? Icons.co_present_rounded
                              : Icons.face_retouching_natural_rounded,
                          size: 16,
                          color: type == 'IN_PERSON_SESSION' ? violetAccent : primaryBlue,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          type == 'IN_PERSON_SESSION'
                              ? 'In-Person Advisor Session Request'
                              : 'Re-Registration Permission (Self-Scan)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: type == 'IN_PERSON_SESSION' ? violetAccent : primaryBlue,
                          ),
                        ),
                      ],
                    ),
                    if (notes.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Student Reason:',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white70 : Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '“$notes”',
                        style: TextStyle(
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Advisor Remarks Input
              Text(
                'Advisor Feedback / Instructions:',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: feedbackCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'e.g. Approved. Please capture in good daylight with clear background.',
                  hintStyle: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white38 : Colors.grey.shade400,
                  ),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: isDark ? Colors.white12 : Colors.grey.shade300,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _handleReview(
                          requestId: reqId,
                          action: 'REJECT',
                          feedback: feedbackCtrl.text.trim(),
                          studentName: name,
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: roseDanger,
                        side: const BorderSide(color: roseDanger),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('Decline Request'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _handleReview(
                          requestId: reqId,
                          action: 'APPROVE',
                          feedback: feedbackCtrl.text.trim(),
                          studentName: name,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: emeraldGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 2,
                      ),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Grant Permission'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B1120) : const Color(0xFFF8FAFC),
      body: RefreshIndicator(
        onRefresh: _fetchRequests,
        color: primaryBlue,
        child: CustomScrollView(
          slivers: [
            // Top App Bar / Hero Header
            SliverToBoxAdapter(
              child: _buildHeader(isDark),
            ),

            // KPI Summary Row
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: _buildKPIRow(isDark),
              ),
            ),

            // Filter & Search Toolbar
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: _buildFilterToolbar(isDark),
              ),
            ),

            // Bulk Action Bar (if active)
            if (_selectedIds.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: _buildBulkActionBar(isDark),
                ),
              ),

            // Request List or Empty / Error State
            _buildContentSliver(isDark),

            const SliverToBoxAdapter(
              child: SizedBox(height: 80),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white10 : Colors.grey.shade200,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [primaryBlue, secondaryIndigo],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: primaryBlue.withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.face_retouching_natural_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Advisor Face Requests Hub',
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Review biometric re-registration permissions and in-person registration requests.',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white60 : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Refresh Requests',
                onPressed: _fetchRequests,
                color: primaryBlue,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKPIRow(bool isDark) {
    final pendingCount = _stats['total_pending'] ?? 0;
    final approvedToday = _stats['approved_today'] ?? 0;
    final rejectedCount = _stats['total_rejected'] ?? 0;
    final totalRequested = _stats['total_students_requested'] ?? 0;

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final isNarrow = constraints.maxWidth < 600;
        final cardWidth = isNarrow
            ? (constraints.maxWidth - 12) / 2
            : (constraints.maxWidth - 36) / 4;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _buildKPICard(
              title: 'Pending Review',
              count: '$pendingCount',
              icon: Icons.hourglass_top_rounded,
              color: amberWarning,
              isDark: isDark,
              width: cardWidth,
              isActive: _selectedStatus == 'PENDING',
              onTap: () {
                setState(() {
                  _selectedStatus = _selectedStatus == 'PENDING' ? 'ALL' : 'PENDING';
                });
                _fetchRequests();
              },
            ),
            _buildKPICard(
              title: 'Approved Today',
              count: '$approvedToday',
              icon: Icons.check_circle_rounded,
              color: emeraldGreen,
              isDark: isDark,
              width: cardWidth,
              isActive: _selectedStatus == 'APPROVED',
              onTap: () {
                setState(() {
                  _selectedStatus = _selectedStatus == 'APPROVED' ? 'ALL' : 'APPROVED';
                });
                _fetchRequests();
              },
            ),
            _buildKPICard(
              title: 'Declined',
              count: '$rejectedCount',
              icon: Icons.cancel_rounded,
              color: roseDanger,
              isDark: isDark,
              width: cardWidth,
              isActive: _selectedStatus == 'REJECTED',
              onTap: () {
                setState(() {
                  _selectedStatus = _selectedStatus == 'REJECTED' ? 'ALL' : 'REJECTED';
                });
                _fetchRequests();
              },
            ),
            _buildKPICard(
              title: 'Total Students',
              count: '$totalRequested',
              icon: Icons.people_alt_rounded,
              color: primaryBlue,
              isDark: isDark,
              width: cardWidth,
              isActive: _selectedStatus == 'ALL',
              onTap: () {
                setState(() {
                  _selectedStatus = 'ALL';
                });
                _fetchRequests();
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildKPICard({
    required String title,
    required String count,
    required IconData icon,
    required Color color,
    required bool isDark,
    required double width,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isActive ? color : (isDark ? Colors.white10 : Colors.grey.shade200),
            width: isActive ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: isActive ? 0.15 : 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    count,
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white60 : Colors.grey.shade600,
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

  Widget _buildFilterToolbar(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search Input
          TextField(
            controller: _searchCtrl,
            onChanged: (val) {
              _searchQuery = val;
              _fetchRequests();
            },
            decoration: InputDecoration(
              hintText: 'Search student name, register number, notes...',
              hintStyle: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white38 : Colors.grey.shade400,
              ),
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _searchQuery = '');
                        _fetchRequests();
                      },
                    )
                  : null,
              filled: true,
              fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Filters Row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildStatusDropdown(isDark),
                const SizedBox(width: 8),
                _buildTypeDropdown(isDark),
                if (widget.isAdmin || widget.isHod) ...[
                  const SizedBox(width: 8),
                  _buildDeptDropdown(isDark),
                ],
                const SizedBox(width: 8),
                _buildBatchDropdown(isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusDropdown(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedStatus,
          isDense: true,
          dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black87,
          ),
          items: const [
            DropdownMenuItem(value: 'ALL', child: Text('Status: All')),
            DropdownMenuItem(value: 'PENDING', child: Text('Status: Pending ⏳')),
            DropdownMenuItem(value: 'APPROVED', child: Text('Status: Approved ✓')),
            DropdownMenuItem(value: 'REJECTED', child: Text('Status: Declined ✕')),
          ],
          onChanged: (val) {
            if (val != null) {
              setState(() => _selectedStatus = val);
              _fetchRequests();
            }
          },
        ),
      ),
    );
  }

  Widget _buildTypeDropdown(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedType,
          isDense: true,
          dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black87,
          ),
          items: const [
            DropdownMenuItem(value: 'ALL', child: Text('Type: All Requests')),
            DropdownMenuItem(
              value: 'REREGISTRATION_PERMISSION',
              child: Text('Type: Self Re-Registration 🔄'),
            ),
            DropdownMenuItem(
              value: 'IN_PERSON_SESSION',
              child: Text('Type: In-Person Session 🏢'),
            ),
          ],
          onChanged: (val) {
            if (val != null) {
              setState(() => _selectedType = val);
              _fetchRequests();
            }
          },
        ),
      ),
    );
  }

  Widget _buildDeptDropdown(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedDept,
          isDense: true,
          dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black87,
          ),
          items: _departments
              .map((d) => DropdownMenuItem(
                    value: d,
                    child: Text('Dept: $d'),
                  ))
              .toList(),
          onChanged: (val) {
            if (val != null) {
              setState(() => _selectedDept = val);
              _fetchRequests();
            }
          },
        ),
      ),
    );
  }

  Widget _buildBatchDropdown(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedBatch,
          isDense: true,
          dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black87,
          ),
          items: _batches
              .map((b) => DropdownMenuItem(
                    value: b,
                    child: Text('Batch: $b'),
                  ))
              .toList(),
          onChanged: (val) {
            if (val != null) {
              setState(() => _selectedBatch = val);
              _fetchRequests();
            }
          },
        ),
      ),
    );
  }

  Widget _buildBulkActionBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: primaryBlue,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: primaryBlue.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.checklist_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Text(
            '${_selectedIds.length} Selected',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => setState(() => _selectedIds.clear()),
            child: const Text(
              'Clear',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          const SizedBox(width: 6),
          ElevatedButton.icon(
            onPressed: _isBulkProcessing ? null : () => _handleBulkReview('REJECT'),
            style: ElevatedButton.styleFrom(
              backgroundColor: roseDanger,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.close_rounded, size: 14),
            label: const Text('Reject', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _isBulkProcessing ? null : () => _handleBulkReview('APPROVE'),
            style: ElevatedButton.styleFrom(
              backgroundColor: emeraldGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.check_rounded, size: 14),
            label: const Text('Approve All', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildContentSliver(bool isDark) {
    if (_isLoading) {
      return const SliverFillRemaining(
        child: Center(
          child: CircularProgressIndicator(color: primaryBlue),
        ),
      );
    }

    if (_errorMessage != null) {
      return SliverFillRemaining(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline_rounded, size: 48, color: roseDanger),
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black87,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _fetchRequests,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_requests.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  size: 56,
                  color: isDark ? Colors.white24 : Colors.grey.shade400,
                ),
                const SizedBox(height: 14),
                Text(
                  'No Face Registration Requests',
                  style: GoogleFonts.outfit(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white70 : Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _selectedStatus == 'ALL'
                      ? 'No student face requests found for this scope.'
                      : 'No $_selectedStatus requests currently found.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white38 : Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (ctx, idx) {
            final req = _requests[idx] as Map<String, dynamic>;
            return _buildRequestCard(req, isDark);
          },
          childCount: _requests.length,
        ),
      ),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> req, bool isDark) {
    final reqId = req['id'] as int;
    final name = (req['student_name'] ?? 'Student').toString();
    final regNo = (req['student_reg_no'] ?? '').toString();
    final rollNo = (req['roll_no'] ?? '').toString();
    final dept = (req['dept'] ?? '').toString();
    final batch = (req['batch'] ?? '').toString();
    final sem = req['semester']?.toString() ?? '';
    final sec = (req['section'] ?? '').toString();
    final type = (req['request_type'] ?? 'REREGISTRATION_PERMISSION').toString();
    final status = (req['status'] ?? 'PENDING').toString().toUpperCase();
    final notes = (req['student_notes'] ?? '').toString();
    final feedback = (req['advisor_feedback'] ?? '').toString();
    final createdAt = (req['created_at'] ?? '').toString();
    final canReregister = (req['can_reregister'] == true);
    final hasFace = (req['has_enrolled_face'] == true);

    final isSelected = _selectedIds.contains(reqId);
    final isPending = status == 'PENDING';
    final isApproved = status == 'APPROVED';
    final isRejected = status == 'REJECTED';

    Color statusColor = amberWarning;
    if (isApproved) statusColor = emeraldGreen;
    if (isRejected) statusColor = roseDanger;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected
              ? primaryBlue
              : (isPending
                  ? amberWarning.withValues(alpha: 0.4)
                  : (isDark ? Colors.white10 : Colors.grey.shade200)),
          width: isSelected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: (isPending ? amberWarning : Colors.black).withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Avatar, Student Info, Checkbox
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Checkbox for bulk actions
                if (isPending)
                  Padding(
                    padding: const EdgeInsets.only(right: 8, top: 4),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: Checkbox(
                        value: isSelected,
                        activeColor: primaryBlue,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _selectedIds.add(reqId);
                            } else {
                              _selectedIds.remove(reqId);
                            }
                          });
                        },
                      ),
                    ),
                  ),

                // Avatar
                CircleAvatar(
                  radius: 20,
                  backgroundColor: statusColor.withValues(alpha: 0.12),
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : 'S',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Student Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: GoogleFonts.outfit(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                              ),
                            ),
                          ),
                          _buildStatusBadge(status, statusColor),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Reg No: $regNo${rollNo.isNotEmpty ? ' • Roll: $rollNo' : ''}',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white60 : Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _buildChip('$dept • Sem $sem ($sec)', primaryBlue, isDark),
                          _buildChip(batch, Colors.grey.shade600, isDark),
                          if (hasFace)
                            _buildChip('Enrolled ✓', emeraldGreen, isDark)
                          else
                            _buildChip('No Face Data', Colors.orange, isDark),
                          if (canReregister)
                            _buildChip('Unlocked 🔓', amberWarning, isDark),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Request Type & Student Note Callout
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark ? Colors.white10 : Colors.grey.shade200,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        type == 'IN_PERSON_SESSION'
                            ? Icons.co_present_rounded
                            : Icons.face_retouching_natural_rounded,
                        size: 16,
                        color: type == 'IN_PERSON_SESSION' ? violetAccent : primaryBlue,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          type == 'IN_PERSON_SESSION'
                              ? 'In-Person Face Enrollment Session'
                              : 'Face Re-Registration Permission (Self-Scan)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: type == 'IN_PERSON_SESSION' ? violetAccent : primaryBlue,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        createdAt,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white38 : Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                  if (notes.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      '“$notes”',
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ],
                  if (feedback.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: (isApproved ? emeraldGreen : roseDanger).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isApproved ? Icons.verified_rounded : Icons.info_outline_rounded,
                            size: 14,
                            color: isApproved ? emeraldGreen : roseDanger,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Advisor: $feedback',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: isApproved ? emeraldGreen : roseDanger,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Action Buttons Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
            child: Row(
              children: [
                if (isPending) ...[
                  // Quick Reject
                  OutlinedButton.icon(
                    onPressed: () => _handleReview(
                      requestId: reqId,
                      action: 'REJECT',
                      studentName: name,
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: roseDanger,
                      side: const BorderSide(color: roseDanger),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.close_rounded, size: 14),
                    label: const Text('Decline', style: TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: 8),

                  // Review with custom remarks
                  OutlinedButton.icon(
                    onPressed: () => _showReviewFeedbackModal(req),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primaryBlue,
                      side: const BorderSide(color: primaryBlue),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.rate_review_outlined, size: 14),
                    label: const Text('Remarks', style: TextStyle(fontSize: 12)),
                  ),
                  const Spacer(),

                  // Quick 1-Tap Approve
                  ElevatedButton.icon(
                    onPressed: () => _handleReview(
                      requestId: reqId,
                      action: 'APPROVE',
                      studentName: name,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: emeraldGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 1,
                    ),
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: const Text(
                      '⚡ Quick Approve',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ] else ...[
                  // If already approved or rejected
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: () => _showReviewFeedbackModal(req),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isDark ? Colors.white70 : Colors.black87,
                      side: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.edit_note_rounded, size: 16),
                    label: const Text('Update Decision', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status, Color color) {
    String label = status;
    IconData icon = Icons.hourglass_top_rounded;
    if (status == 'APPROVED') {
      label = 'Approved ✓';
      icon = Icons.check_circle_rounded;
    } else if (status == 'REJECTED') {
      label = 'Declined ✕';
      icon = Icons.cancel_rounded;
    } else if (status == 'PENDING') {
      label = 'Pending Review';
      icon = Icons.access_time_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChip(String label, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
