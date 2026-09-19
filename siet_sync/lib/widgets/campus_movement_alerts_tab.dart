import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../config/college_ip_config.dart';

class CampusMovementAlertsTab extends StatefulWidget {
  final String token;
  final Map<String, dynamic> user;

  const CampusMovementAlertsTab({
    super.key,
    required this.token,
    required this.user,
  });

  @override
  State<CampusMovementAlertsTab> createState() => _CampusMovementAlertsTabState();
}

class _CampusMovementAlertsTabState extends State<CampusMovementAlertsTab> {
  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _alerts = [];
  Map<String, dynamic> _stats = {
    'active_count': 0,
    'resolved_count': 0,
    'total_count': 0,
  };

  // Filter states
  String _selectedStatus = 'all'; // 'all', 'ACTIVE', 'RESOLVED'
  String _selectedRole = 'all'; // 'all', 'student', 'staff', 'hod', 'other_staff'
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _fetchAlerts();
    // Auto-poll alerts every 20 seconds for real-time safety monitoring
    _pollingTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) _fetchAlerts(silent: true);
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchAlerts({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final queryParams = <String, String>{};
      if (_selectedStatus != 'all') queryParams['status'] = _selectedStatus;
      if (_selectedRole != 'all') queryParams['role'] = _selectedRole;
      queryParams['limit'] = '100';

      final uri = Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/campus-alerts')
          .replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final List rawAlerts = data['alerts'] as List? ?? [];
          final Map<String, dynamic> rawStats = data['stats'] as Map<String, dynamic>? ?? {};

          if (mounted) {
            setState(() {
              _alerts = rawAlerts.map((e) => Map<String, dynamic>.from(e)).toList();
              _stats = rawStats;
              _isLoading = false;
              _errorMessage = null;
            });
          }
        } else {
          throw Exception(data['detail'] ?? 'Failed to load alerts');
        }
      } else {
        throw Exception('Server returned HTTP ${response.statusCode}');
      }
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _acknowledgeAlert(int alertId) async {
    try {
      final uri = Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/campus-alerts/$alertId/acknowledge');
      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Alert #$alertId acknowledged successfully.'),
              backgroundColor: const Color(0xFF107C41),
              behavior: SnackBarBehavior.floating,
            ),
          );
          _fetchAlerts(silent: true);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not acknowledge: $e'),
            backgroundColor: const Color(0xFFD13438),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _openGoogleMaps(double? lat, double? lng) async {
    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Coordinates not available for this alert.')),
      );
      return;
    }
    final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(url);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Location: $lat, $lng')),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filteredAlerts {
    if (_searchQuery.trim().isEmpty) return _alerts;
    final query = _searchQuery.toLowerCase().trim();
    return _alerts.where((alert) {
      final name = (alert['user_name'] ?? '').toString().toLowerCase();
      final regNo = (alert['user_reg_no'] ?? '').toString().toLowerCase();
      final dept = (alert['dept'] ?? '').toString().toLowerCase();
      final title = (alert['title'] ?? '').toString().toLowerCase();
      return name.contains(query) || regNo.contains(query) || dept.contains(query) || title.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMobile = MediaQuery.of(context).size.width < 700;
    final activeCount = _stats['active_count'] ?? 0;
    final resolvedCount = _stats['resolved_count'] ?? 0;
    final totalCount = _stats['total_count'] ?? _alerts.length;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      body: RefreshIndicator(
        onRefresh: () => _fetchAlerts(),
        color: const Color(0xFF0067B8),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // 1. Top Header Banner
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  isMobile ? 12 : 24,
                  isMobile ? 12 : 20,
                  isMobile ? 12 : 24,
                  8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: activeCount > 0
                                ? const Color(0xFFD13438).withValues(alpha: 0.12)
                                : const Color(0xFF0067B8).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: activeCount > 0
                                  ? const Color(0xFFD13438).withValues(alpha: 0.3)
                                  : const Color(0xFF0067B8).withValues(alpha: 0.3),
                            ),
                          ),
                          child: Icon(
                            Icons.notification_important_rounded,
                            size: isMobile ? 22 : 26,
                            color: activeCount > 0
                                ? const Color(0xFFD13438)
                                : const Color(0xFF0067B8),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Campus Movement Warnings',
                                style: TextStyle(
                                  fontSize: isMobile ? 18 : 22,
                                  fontWeight: FontWeight.bold,
                                  fontStyle: FontStyle.normal,
                                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                activeCount > 0
                                    ? '$activeCount individual(s) currently outside campus boundary'
                                    : 'All students & staff accounted within campus perimeters',
                                style: TextStyle(
                                  fontSize: isMobile ? 11.5 : 13,
                                  color: activeCount > 0
                                      ? const Color(0xFFD13438)
                                      : (isDark ? Colors.white60 : Colors.grey.shade600),
                                  fontWeight: activeCount > 0 ? FontWeight.w600 : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh_rounded),
                          tooltip: 'Refresh Alerts',
                          onPressed: () => _fetchAlerts(),
                          color: const Color(0xFF0067B8),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 2. Summary KPI Metrics Cards
                    Row(
                      children: [
                        Expanded(
                          child: _buildMetricTile(
                            label: isMobile ? 'Outside' : 'Outside Campus',
                            value: '$activeCount',
                            accentColor: const Color(0xFFD13438),
                            icon: Icons.person_off_rounded,
                            isDark: isDark,
                            isMobile: isMobile,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildMetricTile(
                            label: isMobile ? 'Returned' : 'Returned to Campus',
                            value: '$resolvedCount',
                            accentColor: const Color(0xFF107C41),
                            icon: Icons.assignment_turned_in_rounded,
                            isDark: isDark,
                            isMobile: isMobile,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildMetricTile(
                            label: isMobile ? 'Total Today' : 'Total Alerts',
                            value: '$totalCount',
                            accentColor: const Color(0xFF0067B8),
                            icon: Icons.shield_outlined,
                            isDark: isDark,
                            isMobile: isMobile,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // 3. Search & Filter Bar
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 10 : 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark ? Colors.white10 : Colors.grey.shade200,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Search Box
                          TextField(
                            controller: _searchController,
                            onChanged: (val) => setState(() => _searchQuery = val),
                            style: TextStyle(fontSize: isMobile ? 12.5 : 14),
                            decoration: InputDecoration(
                              hintText: 'Search by name, reg no, or department...',
                              hintStyle: TextStyle(
                                fontSize: isMobile ? 12 : 13,
                                color: isDark ? Colors.white38 : Colors.grey.shade400,
                              ),
                              prefixIcon: Icon(
                                Icons.search,
                                size: isMobile ? 18 : 20,
                                color: isDark ? Colors.white54 : Colors.grey.shade500,
                              ),
                              suffixIcon: _searchQuery.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 16),
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() => _searchQuery = '');
                                      },
                                    )
                                  : null,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(vertical: 8),
                              border: InputBorder.none,
                            ),
                          ),
                          const Divider(height: 14),

                          // Filter Chips Row
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _buildFilterChip(
                                  label: 'All Alerts',
                                  isSelected: _selectedStatus == 'all',
                                  onSelected: () {
                                    setState(() => _selectedStatus = 'all');
                                    _fetchAlerts();
                                  },
                                  isDark: isDark,
                                ),
                                const SizedBox(width: 8),
                                _buildFilterChip(
                                  label: 'Active Outside',
                                  isSelected: _selectedStatus == 'ACTIVE',
                                  color: const Color(0xFFD13438),
                                  onSelected: () {
                                    setState(() => _selectedStatus = 'ACTIVE');
                                    _fetchAlerts();
                                  },
                                  isDark: isDark,
                                ),
                                const SizedBox(width: 8),
                                _buildFilterChip(
                                  label: 'Returned',
                                  isSelected: _selectedStatus == 'RESOLVED',
                                  color: const Color(0xFF107C41),
                                  onSelected: () {
                                    setState(() => _selectedStatus = 'RESOLVED');
                                    _fetchAlerts();
                                  },
                                  isDark: isDark,
                                ),
                                const SizedBox(width: 14),
                                Container(width: 1, height: 20, color: Colors.grey.shade300),
                                const SizedBox(width: 14),
                                _buildFilterChip(
                                  label: 'Students',
                                  isSelected: _selectedRole == 'student',
                                  onSelected: () {
                                    setState(() => _selectedRole = _selectedRole == 'student' ? 'all' : 'student');
                                    _fetchAlerts();
                                  },
                                  isDark: isDark,
                                ),
                                const SizedBox(width: 8),
                                _buildFilterChip(
                                  label: 'Staff',
                                  isSelected: _selectedRole == 'staff',
                                  onSelected: () {
                                    setState(() => _selectedRole = _selectedRole == 'staff' ? 'all' : 'staff');
                                    _fetchAlerts();
                                  },
                                  isDark: isDark,
                                ),
                                const SizedBox(width: 8),
                                _buildFilterChip(
                                  label: 'HOD',
                                  isSelected: _selectedRole == 'hod',
                                  onSelected: () {
                                    setState(() => _selectedRole = _selectedRole == 'hod' ? 'all' : 'hod');
                                    _fetchAlerts();
                                  },
                                  isDark: isDark,
                                ),
                                const SizedBox(width: 8),
                                _buildFilterChip(
                                  label: 'Other Users',
                                  isSelected: _selectedRole == 'other_staff',
                                  onSelected: () {
                                    setState(() => _selectedRole = _selectedRole == 'other_staff' ? 'all' : 'other_staff');
                                    _fetchAlerts();
                                  },
                                  isDark: isDark,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 4. Content Area
            if (_isLoading)
              const SliverFillRemaining(
                child: Center(
                  child: CircularProgressIndicator(color: Color(0xFF0067B8)),
                ),
              )
            else if (_errorMessage != null)
              SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded, size: 48, color: Color(0xFFD13438)),
                        const SizedBox(height: 12),
                        Text(
                          'Unable to load movement alerts',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12.5, color: Colors.grey),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () => _fetchAlerts(),
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Try Again'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0067B8),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (_filteredAlerts.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: const Color(0xFF107C41).withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check_circle_outline_rounded,
                            size: 48,
                            color: Color(0xFF107C41),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No Boundary Breach Warnings',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _searchQuery.isNotEmpty
                              ? 'No records matching your current search query.'
                              : 'All assigned students, staff, and personnel are safely within bounds.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: isDark ? Colors.white54 : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 12 : 24,
                  vertical: 8,
                ),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final alert = _filteredAlerts[index];
                      return _buildAlertCard(alert, isDark: isDark, isMobile: isMobile);
                    },
                    childCount: _filteredAlerts.length,
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required Color accentColor,
    required IconData icon,
    required bool isDark,
    required bool isMobile,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 10 : 16,
        vertical: isMobile ? 10 : 14,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: isMobile ? 14 : 18, color: accentColor),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: isMobile ? 18 : 22,
                  fontWeight: FontWeight.bold,
                  fontStyle: FontStyle.normal,
                  color: accentColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: isMobile ? 10.5 : 12,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white60 : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onSelected,
    required bool isDark,
    Color color = const Color(0xFF0067B8),
  }) {
    return InkWell(
      onTap: onSelected,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.15)
              : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade100),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : (isDark ? Colors.white12 : Colors.grey.shade300),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? color : (isDark ? Colors.white70 : Colors.grey.shade700),
          ),
        ),
      ),
    );
  }

  Widget _buildAlertCard(
    Map<String, dynamic> alert, {
    required bool isDark,
    required bool isMobile,
  }) {
    final status = (alert['status'] ?? 'ACTIVE').toString().toUpperCase();
    final isActive = status == 'ACTIVE';
    final isResolved = status == 'RESOLVED';
    final userRole = (alert['user_role'] ?? 'student').toString().toLowerCase();
    final userName = alert['user_name'] ?? 'User';
    final userReg = alert['user_reg_no'] ?? '';
    final dept = alert['dept'] ?? '';
    final semester = alert['semester'];
    final section = alert['section'];
    final advisorName = alert['advisor_name'] ?? '';
    final advisorReg = alert['advisor_reg_no'] ?? '';
    final hodName = alert['hod_name'] ?? '';
    final message = alert['message'] ?? '';
    final leftAt = alert['left_at']?.toString() ?? '';
    final resolvedAt = alert['resolved_at']?.toString();
    final lat = alert['latitude'] is num ? (alert['latitude'] as num).toDouble() : null;
    final lng = alert['longitude'] is num ? (alert['longitude'] as num).toDouble() : null;
    final alertId = alert['id'] as int? ?? 0;

    final primaryAlertColor = isActive
        ? const Color(0xFFD13438)
        : (isResolved ? const Color(0xFF107C41) : const Color(0xFF0067B8));

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: primaryAlertColor.withValues(alpha: isActive ? 0.4 : 0.2),
          width: isActive ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: primaryAlertColor.withValues(alpha: isActive ? 0.08 : 0.02),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Status Pill & Time Indicator
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: primaryAlertColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: primaryAlertColor.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: primaryAlertColor,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isActive
                            ? 'OUT OF CAMPUS'
                            : (isResolved ? 'RETURNED TO CAMPUS' : 'ACKNOWLEDGED'),
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: primaryAlertColor,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (leftAt.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.access_time_rounded,
                        size: 13,
                        color: isDark ? Colors.white38 : Colors.grey.shade500,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatTimeString(leftAt),
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white54 : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Row 2: User Identity & Role
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: isMobile ? 20 : 22,
                  backgroundColor: _roleColor(userRole).withValues(alpha: 0.15),
                  child: Text(
                    userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _roleColor(userRole),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              userName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: isMobile ? 14 : 15.5,
                                fontWeight: FontWeight.bold,
                                fontStyle: FontStyle.normal,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _roleColor(userRole).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              userRole.toUpperCase(),
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: _roleColor(userRole),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$userReg • $dept${semester != null ? ' • Sem $semester-$section' : ''}',
                        style: TextStyle(
                          fontSize: isMobile ? 11.5 : 12.5,
                          color: isDark ? Colors.white60 : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Row 3: Alert Message Content
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.04)
                    : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark ? Colors.white10 : Colors.grey.shade200,
                ),
              ),
              child: Text(
                message,
                style: TextStyle(
                  fontSize: isMobile ? 12 : 12.5,
                  height: 1.4,
                  color: isDark ? Colors.white70 : Colors.grey.shade800,
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Row 4: Notification Recipient Badges
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (userRole == 'student')
                  _buildRecipientBadge(
                    label: advisorName.isNotEmpty ? 'Advisor: $advisorName' : 'Advisor: ${advisorReg.isNotEmpty ? advisorReg : 'Assigned'}',
                    isDark: isDark,
                  ),
                if (hodName.isNotEmpty || userRole != 'hod')
                  _buildRecipientBadge(
                    label: hodName.isNotEmpty ? 'HOD: $hodName' : 'Dept HOD',
                    isDark: isDark,
                  ),
                _buildRecipientBadge(
                  label: 'Admin (Logged)',
                  isDark: isDark,
                  color: const Color(0xFF5C2D91),
                ),
                if (isResolved && resolvedAt != null)
                  _buildRecipientBadge(
                    label: 'Returned: ${_formatTimeString(resolvedAt)}',
                    isDark: isDark,
                    color: const Color(0xFF107C41),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Row 5: Action Footer
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // GPS Coordinates button
                if (lat != null && lng != null)
                  InkWell(
                    onTap: () => _openGoogleMaps(lat, lng),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.location_on_outlined, size: 15, color: Color(0xFF0067B8)),
                          SizedBox(width: 4),
                          Text(
                            'View on Maps',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF0067B8),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  const SizedBox.shrink(),

                // Acknowledge Button
                if (isActive)
                  ElevatedButton.icon(
                    onPressed: () => _acknowledgeAlert(alertId),
                    icon: const Icon(Icons.check, size: 14),
                    label: const Text('Acknowledge'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                      foregroundColor: isDark ? Colors.white : const Color(0xFF0F172A),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecipientBadge({
    required String label,
    required bool isDark,
    Color color = const Color(0xFF0067B8),
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.notifications_active_outlined, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Color _roleColor(String role) {
    switch (role.toLowerCase()) {
      case 'student':
        return const Color(0xFF0067B8);
      case 'staff':
        return const Color(0xFF107C41);
      case 'hod':
        return const Color(0xFF5C2D91);
      default:
        return const Color(0xFFD97706);
    }
  }

  String _formatTimeString(String dtStr) {
    try {
      final dt = DateTime.parse(dtStr);
      final hour = dt.hour.toString().padLeft(2, '0');
      final minute = dt.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    } catch (_) {
      if (dtStr.contains(' ')) {
        final timePart = dtStr.split(' ')[1];
        return timePart.length >= 5 ? timePart.substring(0, 5) : timePart;
      }
      return dtStr.length > 5 ? dtStr.substring(0, 5) : dtStr;
    }
  }
}
