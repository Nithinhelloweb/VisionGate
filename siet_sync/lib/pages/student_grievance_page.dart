import 'package:flutter/material.dart';
import '../services/features_service.dart';

class StudentGrievancePage extends StatefulWidget {
  final String token;
  final Map<String, dynamic> user;
  final bool isAdmin;

  const StudentGrievancePage({
    super.key,
    required this.token,
    required this.user,
    this.isAdmin = false,
  });

  @override
  State<StudentGrievancePage> createState() => _StudentGrievancePageState();
}

class _StudentGrievancePageState extends State<StudentGrievancePage> {
  bool _isLoading = false;
  List<Map<String, dynamic>> _feedbackList = [];

  @override
  void initState() {
    super.initState();
    _loadFeedback();
  }

  Future<void> _loadFeedback() async {
    setState(() => _isLoading = true);
    try {
      final list = widget.isAdmin
          ? await FeaturesService.getAdminStudentFeedback(widget.token)
          : await FeaturesService.getMyStudentFeedback(widget.token);
      if (mounted) {
        setState(() {
          _feedbackList = list;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openSubmitDialog() {
    String category = 'Academics';
    final subjectController = TextEditingController();
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Submit Feedback / Grievance', style: TextStyle(fontWeight: FontWeight.bold)),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: category,
                  decoration: InputDecoration(
                    labelText: 'Category',
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'Academics',
                      child: Text('Academics / Curriculum', overflow: TextOverflow.ellipsis, maxLines: 1),
                    ),
                    DropdownMenuItem(
                      value: 'Attendance',
                      child: Text('Attendance & Biometrics', overflow: TextOverflow.ellipsis, maxLines: 1),
                    ),
                    DropdownMenuItem(
                      value: 'Facilities',
                      child: Text('Campus & Lab Facilities', overflow: TextOverflow.ellipsis, maxLines: 1),
                    ),
                    DropdownMenuItem(
                      value: 'Hostel',
                      child: Text('Hostel & Transport', overflow: TextOverflow.ellipsis, maxLines: 1),
                    ),
                    DropdownMenuItem(
                      value: 'General',
                      child: Text('General Grievance', overflow: TextOverflow.ellipsis, maxLines: 1),
                    ),
                  ],
                  onChanged: (v) => setDialogState(() => category = v ?? 'Academics'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: subjectController,
                  decoration: InputDecoration(
                    labelText: 'Subject',
                    hintText: 'Brief summary of the issue…',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descController,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: 'Detailed Description',
                    hintText: 'Provide complete details and context…',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (subjectController.text.trim().isEmpty || descController.text.trim().isEmpty) return;
                Navigator.pop(ctx);
                setState(() => _isLoading = true);
                final ok = await FeaturesService.submitStudentFeedback(
                  widget.token,
                  category: category,
                  subject: subjectController.text.trim(),
                  description: descController.text.trim(),
                );
                setState(() => _isLoading = false);
                if (ok && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Feedback ticket submitted to administration.')),
                  );
                  _loadFeedback();
                }
              },
              child: const Text('Submit Ticket'),
            ),
          ],
        ),
      ),
    );
  }

  void _openResolveDialog(int feedbackId, String subject) {
    final resolutionController = TextEditingController(text: 'Issue reviewed and addressed by department.');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Resolve Student Grievance', style: TextStyle(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ticket: $subject', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              TextField(
                controller: resolutionController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Resolution Action / Notes',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _isLoading = true);
              final ok = await FeaturesService.resolveStudentFeedback(
                widget.token,
                feedbackId,
                resolutionNotes: resolutionController.text.trim(),
              );
              setState(() => _isLoading = false);
              if (ok && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Grievance marked as resolved.')),
                );
                _loadFeedback();
              }

            },
            child: const Text('Resolve Grievance'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isAdmin ? 'Student Grievance & Feedback Portal' : 'My Grievances & Feedback', style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      floatingActionButton: !widget.isAdmin
          ? FloatingActionButton.extended(
              onPressed: _openSubmitDialog,
              icon: const Icon(Icons.add_comment_rounded),
              label: const Text('New Feedback'),
            )
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _feedbackList.isEmpty
              ? const Center(child: Text('No feedback or grievance tickets recorded.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _feedbackList.length,
                  itemBuilder: (ctx, i) {
                    final f = _feedbackList[i];
                    final feedbackId = f['id'] as int;
                    final isResolved = f['status'] == 'Resolved';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).primaryColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),

                                  child: Text(
                                    f['category'] ?? 'General',
                                    style: TextStyle(color: Theme.of(context).primaryColor, fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isResolved ? Colors.green.shade50 : Colors.amber.shade50,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    f['status'] ?? 'Submitted',
                                    style: TextStyle(color: isResolved ? Colors.green.shade800 : Colors.amber.shade900, fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(f['subject'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(height: 6),
                            Text(f['description'] ?? '', style: const TextStyle(fontSize: 13, color: Colors.black87)),
                            if (f['resolution_notes'] != null && f['resolution_notes'].toString().isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                                child: Text('Resolution: ${f['resolution_notes']}', style: TextStyle(fontSize: 12, color: Colors.green.shade900)),
                              ),
                            ],
                            if (widget.isAdmin && !isResolved) ...[
                              const SizedBox(height: 12),
                              Align(
                                alignment: Alignment.centerRight,
                                child: OutlinedButton.icon(
                                  onPressed: () => _openResolveDialog(feedbackId, f['subject'] ?? ''),
                                  icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                                  label: const Text('Resolve Ticket'),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
