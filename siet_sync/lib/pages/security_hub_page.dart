import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/features_service.dart';

class SecurityHubPage extends StatefulWidget {
  final String token;
  final Map<String, dynamic> user;

  const SecurityHubPage({
    super.key,
    required this.token,
    required this.user,
  });

  @override
  State<SecurityHubPage> createState() => _SecurityHubPageState();
}

class _SecurityHubPageState extends State<SecurityHubPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = false;

  List<Map<String, dynamic>> _activeSessions = [];
  List<Map<String, dynamic>> _loginAttempts = [];
  List<Map<String, dynamic>> _auditLogs = [];
  int _failed24h = 0;
  int _success24h = 0;

  bool _is2faEnabled = false;
  String? _twoFaEnabledAt;
  Map<String, dynamic>? _twoFaSetupData;

  final _twoFaCodeController = TextEditingController();
  final _testCodeController = TextEditingController();
  final _disableCodeController = TextEditingController();

  String _telemetryFilter = 'all'; // 'all', 'failed', 'success', 'audit'

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _twoFaCodeController.dispose();
    _testCodeController.dispose();
    _disableCodeController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        FeaturesService.getActiveSessions(widget.token),
        FeaturesService.getLoginAttemptsData(widget.token),
        FeaturesService.getAuditLogs(widget.token),
        FeaturesService.get2FAStatus(widget.token),
      ]);

      final sessions = results[0] as List<Map<String, dynamic>>;
      final loginData = results[1] as Map<String, dynamic>;
      final audits = results[2] as List<Map<String, dynamic>>;
      final twoFaStatus = results[3] as Map<String, dynamic>;

      if (mounted) {
        setState(() {
          _activeSessions = sessions;
          _loginAttempts =
              List<Map<String, dynamic>>.from(loginData['attempts'] ?? []);
          _failed24h = (loginData['failed_24h'] as num?)?.toInt() ?? 0;
          _success24h = (loginData['success_24h'] as num?)?.toInt() ?? 0;
          _auditLogs = audits;
          _is2faEnabled = twoFaStatus['enabled'] == true ||
              twoFaStatus['is_enabled'] == true;
          _twoFaEnabledAt = twoFaStatus['enabled_at']?.toString();
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _setup2FA() async {
    setState(() => _isLoading = true);
    final data = await FeaturesService.setup2FA(widget.token);
    if (!mounted) return;
    setState(() {
      _twoFaSetupData = data;
      _isLoading = false;
    });
  }

  void _verify2FA() async {
    final code = _twoFaCodeController.text.trim();
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a 6-digit TOTP code.')),
      );
      return;
    }

    setState(() => _isLoading = true);
    final ok = await FeaturesService.verify2FA(widget.token, code);
    setState(() => _isLoading = false);

    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.green,
          content: Text('Two-factor authentication successfully enabled.'),
        ),
      );
      setState(() {
        _twoFaSetupData = null;
        _is2faEnabled = true;
      });
      _twoFaCodeController.clear();
      _loadData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text('Invalid 6-digit verification code. Please try again.'),
        ),
      );
    }
  }

  Future<void> _test2FACode() async {
    final code = _testCodeController.text.trim();
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a 6-digit code to test.')),
      );
      return;
    }

    final res = await FeaturesService.test2FACode(widget.token, code);
    if (!mounted) return;
    final isValid = res['valid'] == true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: isValid ? Colors.green.shade700 : Colors.red.shade700,
        content: Text(
          res['message'] ??
              (isValid
                  ? 'TOTP code verified successfully.'
                  : 'Invalid or expired code.'),
        ),
      ),
    );
  }

  Future<void> _confirmDisable2FA() async {
    _disableCodeController.clear();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Disable Two-Factor Authentication',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter your current 6-digit authenticator code to confirm:',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _disableCodeController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '000000',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Disable 2FA'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final code = _disableCodeController.text.trim();
      final ok = await FeaturesService.disable2FA(widget.token, code);
      if (!mounted) return;
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Two-factor authentication disabled.')),
        );
        _loadData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.red,
            content: Text('Failed to disable 2FA. Verification code was invalid.'),
          ),
        );
      }
    }
  }

  Future<void> _terminateSession(String sessionId, String deviceName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Terminate Session',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text('Are you sure you want to log out $deviceName?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Terminate'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final ok = await FeaturesService.terminateSession(widget.token, sessionId);
      if (!mounted) return;
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session revoked successfully.')),
        );
        _loadData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.red,
            content: Text('Could not terminate session.'),
          ),
        );
      }
    }
  }

  Future<void> _terminateAllOtherSessions() async {
    String? currentId;
    for (final s in _activeSessions) {
      if (s['is_current'] == true) {
        currentId = (s['session_id'] ?? s['id'])?.toString();
        break;
      }
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Terminate All Other Sessions',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'This will revoke access on all other active devices immediately. Your current session will remain active.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Terminate Others'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final ok = await FeaturesService.terminateAllExceptCurrent(
        widget.token,
        currentSessionId: currentId,
      );
      if (!mounted) return;
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.green,
            content: Text('All other sessions terminated successfully.'),
          ),
        );
        _loadData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.red,
            content: Text('Failed to terminate sessions.'),
          ),
        );
      }
    }
  }

  IconData _getDeviceIcon(String deviceInfo, String userAgent) {
    final combined = '$deviceInfo $userAgent'.toLowerCase();
    if (combined.contains('android') ||
        combined.contains('iphone') ||
        combined.contains('mobile')) {
      return Icons.phone_android_rounded;
    } else if (combined.contains('ipad') || combined.contains('tablet')) {
      return Icons.tablet_mac_rounded;
    } else if (combined.contains('mac') || combined.contains('darwin')) {
      return Icons.laptop_mac_rounded;
    } else if (combined.contains('linux')) {
      return Icons.laptop_chromebook_rounded;
    }
    return Icons.computer_rounded;
  }

  Widget _buildQrCodeImage(String rawQr) {
    try {
      String cleanBase64 = rawQr;
      if (rawQr.contains(',')) {
        cleanBase64 = rawQr.split(',').last;
      }
      final bytes = base64Decode(cleanBase64.trim());
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Image.memory(
          bytes,
          width: 170,
          height: 170,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => const Icon(
            Icons.qr_code_2_rounded,
            size: 80,
            color: Colors.grey,
          ),
        ),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Security & 2FA Hub',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Security Telemetry',
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading && _activeSessions.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: Column(
                children: [
                  _buildBentoMetrics(),
                  Container(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
                        ),
                      ),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      labelColor: Theme.of(context).colorScheme.primary,
                      unselectedLabelColor: Colors.grey,
                      indicatorColor: Theme.of(context).colorScheme.primary,
                      tabs: [
                        Tab(
                          text: 'Active Sessions (${_activeSessions.length})',
                          icon: const Icon(Icons.devices_rounded, size: 20),
                        ),
                        Tab(
                          text: _is2faEnabled ? '2FA (Active)' : 'Two-Factor Auth',
                          icon: Icon(
                            _is2faEnabled
                                ? Icons.verified_user_rounded
                                : Icons.security_rounded,
                            size: 20,
                            color: _is2faEnabled ? Colors.green : null,
                          ),
                        ),
                        Tab(
                          text: 'Audit & Telemetry (${_loginAttempts.length})',
                          icon: const Icon(Icons.shield_outlined, size: 20),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildActiveSessionsTab(),
                        _buildTwoFactorAuthTab(),
                        _buildAuditLogsTab(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildBentoMetrics() {
    final securityScore = _is2faEnabled ? 95 : 70;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 650;
          return GridView.count(
            crossAxisCount: isNarrow ? 2 : 4,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: isNarrow ? 1.9 : 2.3,
            children: [
              _buildMetricCard(
                title: 'Active Sessions',
                value: '${_activeSessions.length}',
                subtitle: 'Live devices',
                icon: Icons.devices_rounded,
                iconColor: Colors.blue,
              ),
              _buildMetricCard(
                title: '2FA Protection',
                value: _is2faEnabled ? 'Enabled' : 'Disabled',
                subtitle:
                    _is2faEnabled ? 'Account secured' : 'Action recommended',
                icon: _is2faEnabled
                    ? Icons.verified_user_rounded
                    : Icons.gpp_maybe_rounded,
                iconColor: _is2faEnabled ? Colors.green : Colors.amber,
              ),
              _buildMetricCard(
                title: '24h Failed Logins',
                value: '$_failed24h',
                subtitle: '$_success24h successful',
                icon: Icons.shield_outlined,
                iconColor: _failed24h > 0 ? Colors.orange : Colors.teal,
              ),
              _buildMetricCard(
                title: 'Security Score',
                value: '$securityScore%',
                subtitle: _is2faEnabled ? 'Optimal tier' : 'Needs TOTP 2FA',
                icon: Icons.speed_rounded,
                iconColor: securityScore >= 90 ? Colors.green : Colors.indigo,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
              Icon(icon, size: 16, color: iconColor),
            ],
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 10,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildActiveSessionsTab() {
    if (_activeSessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.devices_rounded, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text(
              'No active external sessions found.',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reload'),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_activeSessions.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_activeSessions.length} active sessions detected',
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: _terminateAllOtherSessions,
                  icon: const Icon(Icons.power_settings_new_rounded, size: 16),
                  label: const Text('Terminate All Others'),
                ),
              ],
            ),
          ),
        ..._activeSessions.map((s) {
          final sessionId =
              (s['session_id'] ?? s['id'] ?? '').toString();
          final isCurrent = s['is_current'] == true;
          final deviceInfo = s['device_info']?.toString() ?? 'Client App';
          final ip = s['ip_address']?.toString() ?? '—';
          final userAgent = s['user_agent']?.toString() ?? '';
          final userReg = s['reg_no']?.toString() ?? s['username'] ?? '—';
          final role = s['role']?.toString() ?? 'user';
          final createdAt = s['created_at']?.toString() ?? '';
          final lastActivity = s['last_activity']?.toString() ?? '';

          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: isCurrent
                  ? BorderSide(color: Colors.green.shade400, width: 1.5)
                  : BorderSide(color: Colors.grey.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CircleAvatar(
                    backgroundColor: isCurrent
                        ? Colors.green.shade50
                        : Colors.blue.shade50,
                    child: Icon(
                      _getDeviceIcon(deviceInfo, userAgent),
                      color: isCurrent ? Colors.green : Colors.blue,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                deviceInfo,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isCurrent) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade100,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Current Session',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'User: $userReg ($role) • IP: $ip',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        if (lastActivity.isNotEmpty || createdAt.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              'Active: ${lastActivity.isNotEmpty ? lastActivity : createdAt}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (!isCurrent)
                    IconButton(
                      icon: const Icon(
                        Icons.power_settings_new_rounded,
                        color: Colors.red,
                      ),
                      tooltip: 'Terminate Session',
                      onPressed: () => _terminateSession(sessionId, deviceInfo),
                    ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildTwoFactorAuthTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Two-Factor Authentication (RFC 6238 TOTP)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _is2faEnabled
                      ? Colors.green.shade50
                      : Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _is2faEnabled
                        ? Colors.green.shade300
                        : Colors.amber.shade300,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _is2faEnabled
                          ? Icons.check_circle_rounded
                          : Icons.warning_amber_rounded,
                      size: 14,
                      color: _is2faEnabled
                          ? Colors.green.shade700
                          : Colors.amber.shade700,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _is2faEnabled ? 'Protected' : 'Disabled',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _is2faEnabled
                            ? Colors.green.shade800
                            : Colors.amber.shade900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Secure your account with time-based one-time passcodes from Google Authenticator, Microsoft Authenticator, or 1Password.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 20),

          // IF 2FA IS ENABLED: show active dashboard + live tester + disable option
          if (_is2faEnabled) ...[
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.green.shade300),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Colors.green.shade100,
                          child: const Icon(
                            Icons.verified_user_rounded,
                            color: Colors.green,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Authenticator Protection Active',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              if (_twoFaEnabledAt != null &&
                                  _twoFaEnabledAt!.isNotEmpty)
                                Text(
                                  'Configured on $_twoFaEnabledAt',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    const Text(
                      'Live Authenticator Code Test',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Verify your authenticator app is in sync by testing a 6-digit code right now:',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        SizedBox(
                          width: 160,
                          child: TextField(
                            controller: _testCodeController,
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                            decoration: const InputDecoration(
                              counterText: '',
                              hintText: '000000',
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.tonal(
                          onPressed: _test2FACode,
                          child: const Text('Test Code'),
                        ),
                      ],
                    ),
                    const Divider(height: 28),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Need to switch authenticators?',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                          ),
                          onPressed: _confirmDisable2FA,
                          child: const Text('Disable 2FA'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ]

          // IF 2FA IS NOT ENABLED AND NO SETUP STARTED
          else if (_twoFaSetupData == null) ...[
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.lock_clock_rounded,
                          size: 28,
                          color: Colors.blue,
                        ),
                        SizedBox(width: 12),
                        Text(
                          'Protect Your Account',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Enabling two-factor authentication requires entering a time-sensitive 6-digit code from your phone whenever you log in.',
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _setup2FA,
                      icon: const Icon(Icons.key_rounded),
                      label: const Text('Set Up 2FA Authenticator'),
                    ),
                  ],
                ),
              ),
            ),
          ]

          // IF SETUP IN PROGRESS: display scannable QR Code and secret key
          else ...[
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '1. Scan QR Code in Authenticator App',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_twoFaSetupData!['qr_code'] != null)
                      Center(
                        child: _buildQrCodeImage(
                          _twoFaSetupData!['qr_code'].toString(),
                        ),
                      ),
                    const SizedBox(height: 16),
                    const Text(
                      'Or enter this secret key manually:',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: SelectableText(
                              _twoFaSetupData!['secret'] ?? '',
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            tooltip: 'Copy Secret Key',
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(
                                  text: _twoFaSetupData!['secret'] ?? '',
                                ),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Secret key copied to clipboard.'),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      '2. Enter 6-Digit Code from App',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _twoFaCodeController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: InputDecoration(
                        hintText: '000000',
                        counterText: '',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () =>
                              setState(() => _twoFaSetupData = null),
                          child: const Text('Cancel'),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: _verify2FA,
                          child: const Text('Verify & Activate 2FA'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAuditLogsTab() {
    List<Map<String, dynamic>> filteredAttempts;
    if (_telemetryFilter == 'failed') {
      filteredAttempts = _loginAttempts
          .where((l) => l['success'] == false || l['successful'] == false)
          .toList();
    } else if (_telemetryFilter == 'success') {
      filteredAttempts = _loginAttempts
          .where((l) => l['success'] == true || l['successful'] == true)
          .toList();
    } else {
      filteredAttempts = _loginAttempts;
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Filter Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              FilterChip(
                label: Text('All Logins (${_loginAttempts.length})'),
                selected: _telemetryFilter == 'all',
                onSelected: (_) => setState(() => _telemetryFilter = 'all'),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: Text('Failed ($_failed24h)'),
                selected: _telemetryFilter == 'failed',
                selectedColor: Colors.red.shade100,
                onSelected: (_) => setState(() => _telemetryFilter = 'failed'),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: Text('Successful ($_success24h)'),
                selected: _telemetryFilter == 'success',
                selectedColor: Colors.green.shade100,
                onSelected: (_) => setState(() => _telemetryFilter = 'success'),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: Text('System Audit (${_auditLogs.length})'),
                selected: _telemetryFilter == 'audit',
                selectedColor: Colors.blue.shade100,
                onSelected: (_) => setState(() => _telemetryFilter = 'audit'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (_telemetryFilter != 'audit') ...[
          if (filteredAttempts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  'No login attempts matching filter.',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            )
          else
            ...filteredAttempts.map((l) {
              final isSuccess =
                  l['success'] == true || l['successful'] == true;
              final user = l['username']?.toString() ?? '—';
              final ip = l['ip_address']?.toString() ?? '—';
              final time = l['attempted_at']?.toString() ??
                  l['timestamp']?.toString() ??
                  '—';
              final reason = l['reason']?.toString() ??
                  (isSuccess ? 'Authenticated' : 'Failed attempt');

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ListTile(
                  leading: Icon(
                    isSuccess
                        ? Icons.check_circle_rounded
                        : Icons.cancel_rounded,
                    color: isSuccess ? Colors.green : Colors.red,
                  ),
                  title: Text(
                    '$user (IP: $ip)',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text('$reason • $time'),
                  trailing: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isSuccess
                          ? Colors.green.shade50
                          : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isSuccess ? 'Success' : 'Denied',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isSuccess ? Colors.green.shade800 : Colors.red.shade800,
                      ),
                    ),
                  ),
                ),
              );
            }),
        ],

        if (_telemetryFilter == 'all' || _telemetryFilter == 'audit') ...[
          const SizedBox(height: 16),
          const Text(
            'Administrative Audit Trail',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 8),
          if (_auditLogs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'No administrative audit events recorded yet.',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            )
          else
            ..._auditLogs.map((a) {
              final isSuccess = a['success'] == true;
              final action = a['action_type']?.toString() ?? 'ACTION';
              final actor =
                  a['actor_name']?.toString() ?? a['actor_reg_no']?.toString() ?? 'System';
              final details = a['details']?.toString() ?? '—';
              final time = a['timestamp']?.toString() ?? '';

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ListTile(
                  title: Text(
                    '$action • $actor',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  subtitle: Text(
                    'Details: $details${time.isNotEmpty ? " • $time" : ""}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: Icon(
                    isSuccess
                        ? Icons.check_circle_outline_rounded
                        : Icons.error_outline_rounded,
                    color: isSuccess ? Colors.green : Colors.red,
                    size: 20,
                  ),
                ),
              );
            }),
        ],
      ],
    );
  }
}
