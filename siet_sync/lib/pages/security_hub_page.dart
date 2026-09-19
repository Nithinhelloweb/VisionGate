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

class _SecurityHubPageState extends State<SecurityHubPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = false;

  List<Map<String, dynamic>> _activeSessions = [];
  List<Map<String, dynamic>> _loginAttempts = [];
  List<Map<String, dynamic>> _auditLogs = [];

  Map<String, dynamic>? _twoFaSetupData;
  final _twoFaCodeController = TextEditingController();

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
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final sessions = await FeaturesService.getActiveSessions(widget.token);
      final logins = await FeaturesService.getLoginAttempts(widget.token);
      final audits = await FeaturesService.getAuditLogs(widget.token);

      if (mounted) {
        setState(() {
          _activeSessions = sessions;
          _loginAttempts = logins;
          _auditLogs = audits;
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
        const SnackBar(content: Text('Two-factor authentication successfully enabled!')),
      );
      setState(() => _twoFaSetupData = null);
      _twoFaCodeController.clear();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid 6-digit verification code.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Security & Access Control', style: TextStyle(fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Active Sessions', icon: Icon(Icons.devices_rounded)),
            Tab(text: 'Two-Factor Auth', icon: Icon(Icons.security_rounded)),
            Tab(text: 'Audit & Telemetry', icon: Icon(Icons.shield_outlined)),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildActiveSessionsTab(),
                _buildTwoFactorAuthTab(),
                _buildAuditLogsTab(),
              ],
            ),
    );
  }

  Widget _buildActiveSessionsTab() {
    if (_activeSessions.isEmpty) {
      return const Center(child: Text('No active external sessions found.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _activeSessions.length,
      itemBuilder: (ctx, i) {
        final s = _activeSessions[i];
        final sessionId = s['id'] as int;
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: const CircleAvatar(
              child: Icon(Icons.laptop_chromebook_rounded),
            ),
            title: Text('${s['device_info'] ?? 'Web / Mobile Client'} (IP: ${s['ip_address'] ?? '—'})'),
            subtitle: Text('User: ${s['reg_no']} • Created: ${s['created_at'] ?? ''}'),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
              tooltip: 'Terminate Session',
              onPressed: () async {
                final ok = await FeaturesService.terminateSession(widget.token, sessionId);
                if (ok && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Session revoked.')),
                  );
                  _loadData();
                }
              },
            ),
          ),
        );
      },

    );
  }

  Widget _buildTwoFactorAuthTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Two-Factor Authentication (TOTP)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
            'Enhance your account security using Google Authenticator, Microsoft Authenticator, or 1Password.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 24),
          if (_twoFaSetupData == null)
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.lock_clock_rounded, size: 28, color: Colors.blue),
                        SizedBox(width: 12),
                        Text('Protect Your Account', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text('Requires a 6-digit TOTP code at login in addition to password.'),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _setup2FA,
                      icon: const Icon(Icons.key_rounded),
                      label: const Text('Setup 2FA Authenticator'),
                    ),
                  ],
                ),
              ),
            )
          else
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('1. Enter Secret Key in Authenticator App', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        children: [
                          Expanded(
                            child: SelectableText(
                              _twoFaSetupData!['secret'] ?? '',
                              style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy_rounded),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: _twoFaSetupData!['secret'] ?? ''));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Secret key copied to clipboard.')),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text('2. Enter 6-Digit Code from App', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _twoFaCodeController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: InputDecoration(
                        hintText: '000000',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => setState(() => _twoFaSetupData = null),
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
      ),
    );
  }

  Widget _buildAuditLogsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_loginAttempts.isNotEmpty) ...[
          const Text('Recent Authentication Attempts', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          ..._loginAttempts.take(5).map((l) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(
                    l['successful'] == true ? Icons.check_circle_rounded : Icons.cancel_rounded,
                    color: l['successful'] == true ? Colors.green : Colors.red,
                  ),
                  title: Text('${l['username']} (${l['ip_address'] ?? '—'})'),
                  subtitle: Text('Device: ${l['user_agent'] ?? 'Mobile/Web'} • ${l['timestamp']}'),
                ),
              )),
          const SizedBox(height: 16),
        ],
        const Text('Administrative Audit Log', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 8),
        ..._auditLogs.map((a) => Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                title: Text('${a['action_type']} • ${a['actor_name'] ?? a['actor_reg_no']}'),
                subtitle: Text('Details: ${a['details'] ?? '—'} • ${a['timestamp']}'),
                trailing: Icon(
                  a['success'] == true ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
                  color: a['success'] == true ? Colors.green : Colors.red,
                ),
              ),
            )),
      ],
    );
  }

}
