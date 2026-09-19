import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/features_service.dart';

class AttendanceCorrectionsPage extends StatefulWidget {
  final String token;
  final Map<String, dynamic> user;
  final bool isAdminOrHod;

  const AttendanceCorrectionsPage({
    super.key,
    required this.token,
    required this.user,
    this.isAdminOrHod = false,
  });

  @override
  State<AttendanceCorrectionsPage> createState() => _AttendanceCorrectionsPageState();
}

class _AttendanceCorrectionsPageState extends State<AttendanceCorrectionsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = false;

  List<Map<String, dynamic>> _myRequests = [];
  List<Map<String, dynamic>> _pendingRequests = [];
  List<Map<String, dynamic>> _historyRequests = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: widget.isAdminOrHod ? 3 : 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final myReqs = await FeaturesService.getMyCorrections(widget.token);
      List<Map<String, dynamic>> pending = [];
      List<Map<String, dynamic>> history = [];

      if (widget.isAdminOrHod) {
        pending = await FeaturesService.getPendingCorrections(widget.token);
        history = await FeaturesService.getCorrectionHistory(widget.token);
      }

      if (mounted) {
        setState(() {
          _myRequests = myReqs;
          _pendingRequests = pending;
          _historyRequests = history;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openCreateDisputeDialog() {
    final dateController = TextEditingController(text: DateFormat('yyyy-MM-dd').format(DateTime.now().subtract(const Duration(days: 1))));
    final inController = TextEditingController(text: '08:55');
    final outController = TextEditingController(text: '17:00');
    final reasonController = TextEditingController();
    String selectedStatus = 'Present';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),

                child: Icon(Icons.edit_calendar_rounded, color: Theme.of(context).primaryColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Attendance Dispute Request',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Submit an attendance correction request for biometric verification or punch anomalies.',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: dateController,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Dispute Date',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.calendar_today_rounded),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: DateTime.now().subtract(const Duration(days: 1)),
                            firstDate: DateTime.now().subtract(const Duration(days: 30)),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) {
                            setDialogState(() {
                              dateController.text = DateFormat('yyyy-MM-dd').format(picked);
                            });
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: inController,
                          decoration: InputDecoration(
                            labelText: 'Check-In Time',
                            hintText: '09:00',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: outController,
                          decoration: InputDecoration(
                            labelText: 'Check-Out Time',
                            hintText: '17:00',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedStatus,
                    decoration: InputDecoration(
                      labelText: 'Requested Status',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Present', child: Text('Present')),
                      DropdownMenuItem(value: 'Half Day', child: Text('Half Day')),
                      DropdownMenuItem(value: 'On Duty', child: Text('On Duty (OD)')),
                    ],
                    onChanged: (v) => setDialogState(() => selectedStatus = v ?? 'Present'),
                  ),

                  const SizedBox(height: 12),
                  TextField(
                    controller: reasonController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'Dispute Reason & Justification',
                      hintText: 'Explain the reason for manual regularisation…',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
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
              onPressed: () async {
                if (reasonController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please provide a reason for the dispute.')),
                  );
                  return;
                }
                Navigator.pop(ctx);
                setState(() => _isLoading = true);
                final res = await FeaturesService.submitAttendanceCorrection(
                  widget.token,
                  requestedDate: dateController.text,
                  requestedCheckIn: inController.text,
                  requestedCheckOut: outController.text,
                  requestedStatus: selectedStatus,
                  reason: reasonController.text.trim(),
                );
                setState(() => _isLoading = false);

                if (!mounted) return;
                if (res['success'] == true) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Correction request submitted for approval.')),
                  );
                  _loadData();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(res['detail'] ?? 'Submission failed.')),
                  );
                }
              },
              child: const Text('Submit Dispute'),
            ),
          ],
        ),
      ),
    );
  }

  void _showResolutionDialog(int correctionId, String applicantName, bool isApprove) {
    final remarksController = TextEditingController(text: isApprove ? 'Verified with department attendance records' : 'Insufficient justification provided');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          isApprove ? 'Approve Correction Request' : 'Reject Correction Request',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isApprove ? Colors.green.shade700 : Colors.red.shade700,
          ),
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Applicant: $applicantName', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              TextField(
                controller: remarksController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Remarks / Justification',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: isApprove ? Colors.green.shade700 : Colors.red.shade700,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _isLoading = true);
              final success = isApprove
                  ? await FeaturesService.approveCorrection(widget.token, correctionId, remarks: remarksController.text.trim())
                  : await FeaturesService.rejectCorrection(widget.token, correctionId, remarks: remarksController.text.trim());
              setState(() => _isLoading = false);

              if (!mounted) return;
              if (success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(isApprove ? 'Request approved and attendance status updated.' : 'Request rejected.')),
                );
                _loadData();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Action failed. Please try again.')),
                );
              }
            },
            child: Text(isApprove ? 'Confirm Approval' : 'Confirm Rejection'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    Color bg;
    Color fg;
    switch (status.toLowerCase()) {
      case 'approved':
        bg = Colors.green.shade50;
        fg = Colors.green.shade800;
        break;
      case 'rejected':
        bg = Colors.red.shade50;
        fg = Colors.red.shade800;
        break;
      default:
        bg = Colors.amber.shade50;
        fg = Colors.amber.shade900;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fg.withValues(alpha: 0.3)),
      ),
      child: Text(
        status,
        style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Regularisation & Disputes', style: TextStyle(fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            const Tab(text: 'My Requests', icon: Icon(Icons.person_rounded)),
            if (widget.isAdminOrHod) ...[
              Tab(
                text: 'Pending Approvals (${_pendingRequests.length})',
                icon: const Icon(Icons.pending_actions_rounded),
              ),
              const Tab(text: 'Dispute History', icon: Icon(Icons.history_rounded)),
            ] else
              const Tab(text: 'Guidelines & Policy', icon: Icon(Icons.info_outline_rounded)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateDisputeDialog,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Request'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                // TAB 1: My Requests
                _buildMyRequestsTab(),
                // TAB 2: Pending or Policy
                if (widget.isAdminOrHod) _buildPendingApprovalsTab() else _buildPolicyTab(),
                // TAB 3: History (if admin/HOD)
                if (widget.isAdminOrHod) _buildHistoryTab(),
              ],
            ),
    );
  }

  Widget _buildMyRequestsTab() {
    if (_myRequests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline_rounded, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text('No dispute requests recorded', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const Text('Submit a request if you notice an attendance recording error.', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _myRequests.length,
      itemBuilder: (ctx, i) {
        final r = _myRequests[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Date: ${r['requested_date']}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    _buildStatusChip(r['status'] ?? 'Pending'),
                  ],
                ),
                const Divider(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Requested Timings', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          const SizedBox(height: 2),
                          Text('${r['requested_check_in'] ?? '—'} – ${r['requested_check_out'] ?? '—'}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Target Status', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          const SizedBox(height: 2),
                          Text(r['requested_status'] ?? 'Present', style: const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text('Reason: ${r['reason'] ?? '—'}', style: const TextStyle(fontSize: 13)),
                if (r['reviewer_remarks'] != null && r['reviewer_remarks'].toString().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('Reviewer: ${r['reviewer_remarks']}', style: TextStyle(fontSize: 12, color: Colors.grey.shade800)),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPendingApprovalsTab() {
    if (_pendingRequests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.task_alt_rounded, size: 64, color: Colors.green.shade400),
            const SizedBox(height: 12),
            const Text('All caught up!', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const Text('There are no pending attendance dispute requests.', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _pendingRequests.length,
      itemBuilder: (ctx, i) {
        final r = _pendingRequests[i];
        final correctionId = r['id'] as int;
        final applicantName = r['user_name'] ?? r['reg_no'] ?? 'Staff Member';

        return Card(
          margin: const EdgeInsets.only(bottom: 14),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(applicantName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text('${r['dept'] ?? 'General'} • Reg: ${r['reg_no']}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                    _buildStatusChip('Pending'),
                  ],
                ),
                const Divider(height: 20),
                Row(
                  children: [
                    Expanded(child: Text('Dispute Date: ${r['requested_date']}', style: const TextStyle(fontWeight: FontWeight.w600))),
                    Expanded(child: Text('Requested: ${r['requested_check_in']} - ${r['requested_check_out']}')),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Reason: ${r['reason']}', style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _showResolutionDialog(correctionId, applicantName, false),
                      icon: const Icon(Icons.close_rounded, size: 18, color: Colors.red),
                      label: const Text('Reject', style: TextStyle(color: Colors.red)),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: () => _showResolutionDialog(correctionId, applicantName, true),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Approve & Regularise'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHistoryTab() {
    if (_historyRequests.isEmpty) {
      return const Center(child: Text('No historical dispute records found.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _historyRequests.length,
      itemBuilder: (ctx, i) {
        final r = _historyRequests[i];
        return ListTile(
          title: Text('${r['user_name'] ?? r['reg_no']} — ${r['requested_date']}'),
          subtitle: Text('Status: ${r['status']} • Reason: ${r['reason']}'),
          trailing: _buildStatusChip(r['status'] ?? 'Resolved'),
        );
      },
    );
  }

  Widget _buildPolicyTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Regularisation Policy Guidelines', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          const Text('1. Attendance corrections must be submitted within 5 calendar days of the disputed date.'),
          const SizedBox(height: 8),
          const Text('2. A maximum of 3 dispute requests are allowed per month per staff member.'),
          const SizedBox(height: 8),
          const Text('3. Approvals are reviewed and processed by the Head of Department or Principal.'),
          const SizedBox(height: 8),
          const Text('4. System audit logs are preserved for all approval and rejection actions.'),
        ],
      ),
    );
  }
}
