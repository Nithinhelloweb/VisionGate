import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/college_ip_config.dart';
import '../services/session_service.dart';
import '../services/leave_request_service.dart';
import '../services/leave_balance_notifier.dart';
import 'staff_alternate_leave_widget.dart';


/// Helper function to format date as yyyy-MM-dd
String _formatDate(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

/// Leave Request Form Widget - for employees to submit leave requests
class LeaveRequestForm extends StatefulWidget {
  final String token;
  final VoidCallback? onRequestSubmitted;

  const LeaveRequestForm({
    super.key,
    required this.token,
    this.onRequestSubmitted,
  });

  @override
  State<LeaveRequestForm> createState() => _LeaveRequestFormState();
}

class _LeaveRequestFormState extends State<LeaveRequestForm> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();

  String _selectedLeaveType = 'sick';
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isHalfDay = false;
  String _whichHalf = 'first'; // 'first' or 'second'
  bool _isLoading = false;
  String? _errorMessage;
  
  double? _availableCL;
  double? _availableCCL;
  bool _loadingBalances = false;

  final List<Map<String, String>> _leaveTypes = [
    {'value': 'sick', 'label': 'Sick Leave'},
    {'value': 'casual', 'label': 'Casual Leave'},
    {'value': 'earned', 'label': 'Earned Leave'},
    {'value': 'od', 'label': 'On Duty (OD)'},
    {'value': 'paternity', 'label': 'Paternity Leave'},
    {'value': 'maternity', 'label': 'Maternity Leave'},
    {'value': 'unpaid', 'label': 'Unpaid Leave'},
    {'value': 'other', 'label': 'Other'},
  ];

  @override
  void initState() {
    super.initState();
    _fetchBalances();
    LeaveBalanceNotifier.instance.addListener(_fetchBalances);
  }



  Future<void> _fetchBalances() async {
    if (!mounted) return;
    setState(() => _loadingBalances = true);
    try {
      final session = await sessionService.getSession();
      String? regNo = session?.user['regNo'] ?? session?.user['reg_no'];

      // Fallback: If session user is not found or regNo is null, decode registration number from token
      if (regNo == null && widget.token.isNotEmpty) {
        try {
          final parts = widget.token.split('.');
          // The token here is base64(username:password) or a standard JWT
          if (parts.length == 3) {
            // It's a JWT token
            final payload = utf8.decode(base64.decode(base64.normalize(parts[1])));
            final payloadMap = json.decode(payload);
            regNo = payloadMap['sub'] ?? payloadMap['username'] ?? payloadMap['regNo'] ?? payloadMap['reg_no'];
          } else {
            // It's standard base64(username:password)
            final decoded = utf8.decode(base64.decode(base64.normalize(widget.token)));
            regNo = decoded.split(':').first;
          }
          print('Fetched regNo from token fallback: $regNo');
        } catch (e) {
          print('Error decoding token fallback: $e');
        }
      }

      if (regNo != null && regNo.isNotEmpty) {
        print('Fetching leave balances for regNo: $regNo');
        
        // Fetch CL Status
        final clUrl = '${CollegeIPConfig.defaultURL}/cl/status/$regNo';
        final clResponse = await http.get(
          Uri.parse(clUrl),
          headers: {'Authorization': 'Bearer ${widget.token}'},
        );

        if (clResponse.statusCode == 200) {
          final clData = json.decode(clResponse.body);
          if (clData['success'] == true && clData['data'] != null) {
            if (mounted) {
              setState(() {
                _availableCL = (clData['data']['total_cl_available'] as num?)?.toDouble() ?? 0.0;
              });
            }
            print('CL Balance fetched: $_availableCL');
          }
        } else {
          print('CL API responded with status: ${clResponse.statusCode}');
        }

        // Fetch CCL/EL Status
        final cclUrl = '${CollegeIPConfig.defaultURL}/ccl/status/$regNo';
        final cclResponse = await http.get(
          Uri.parse(cclUrl),
          headers: {'Authorization': 'Bearer ${widget.token}'},
        );

        if (cclResponse.statusCode == 200) {
          final cclData = json.decode(cclResponse.body);
          if (cclData['success'] == true && cclData['data'] != null) {
            if (mounted) {
              setState(() {
                _availableCCL = (cclData['data']['earned_leave_available'] as num?)?.toDouble() ?? 0.0;
              });
            }
            print('EL Balance fetched: $_availableCCL');
          }
        } else {
          print('EL API responded with status: ${cclResponse.statusCode}');
        }
      } else {
        print('Could not retrieve a valid regNo for leave balance fetch');
      }
    } catch (e) {
      print('Error fetching balances: $e');
    } finally {
      if (mounted) {
        setState(() => _loadingBalances = false);
      }
    }
  }

  int _calculateWorkingDays() {
    if (_startDate == null || _endDate == null) return 0;
    int workingDays = 0;
    DateTime temp = _startDate!;
    while (temp.isBefore(_endDate!) || temp.isAtSameMomentAs(_endDate!)) {
      if (temp.weekday != DateTime.saturday && temp.weekday != DateTime.sunday) {
        workingDays++;
      }
      temp = temp.add(const Duration(days: 1));
    }
    return workingDays;
  }

  @override
  void dispose() {
    LeaveBalanceNotifier.instance.removeListener(_fetchBalances);
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _selectStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked;
        // Reset end date if it's before start date
        if (_endDate != null && _endDate!.isBefore(picked)) {
          _endDate = null;
        }
      });
    }
  }

  Future<void> _selectEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate ?? DateTime.now(),
      firstDate: _startDate ?? DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _endDate = picked;
      });
    }
  }

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) return;

    if (_startDate == null || _endDate == null) {
      setState(() {
        _errorMessage = 'Please select both start and end dates';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await LeaveRequestService.submitLeaveRequest(
      token: widget.token,
      leaveType: _selectedLeaveType,
      startDate: _formatDate(_startDate!),
      endDate: _formatDate(_isHalfDay ? _startDate! : _endDate!),
      reason: _reasonController.text.trim(),
      isHalfDay: _isHalfDay,
      whichHalf: _isHalfDay ? _whichHalf : null,
    );

    setState(() {
      _isLoading = false;
    });

    if (result['success'] == true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Leave request submitted successfully!'),
            backgroundColor: Colors.green,
          ),
        );

        // Clear form
        _reasonController.clear();
        setState(() {
          _startDate = null;
          _endDate = null;
          _selectedLeaveType = 'sick';
        });

        // Notify balance changed
        LeaveBalanceNotifier.instance.notifyBalanceChanged();

        widget.onRequestSubmitted?.call();
      }
    } else {
      setState(() {
        _errorMessage = result['message'] ?? 'Unable to send leave request';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Leave Type Dropdown
            Text(
              'Leave Type',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _selectedLeaveType,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: isDark ? Colors.grey[800] : Colors.grey[100],
              ),
              items: _leaveTypes.map((type) {
                return DropdownMenuItem(
                  value: type['value'],
                  child: Text(type['label']!),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedLeaveType = value!;
                });
              },
            ),

            const SizedBox(height: 12),
            if (_loadingBalances)
              const LinearProgressIndicator(color: Color(0xFF0067B8))
            else ...[
              Builder(
                builder: (context) {
                  final clVal = _availableCL ?? 0.0;
                  final cclVal = _availableCCL ?? 0.0;
                  final clStr = clVal % 1 == 0 ? clVal.toInt().toString() : clVal.toString();
                  final cclStr = cclVal % 1 == 0 ? cclVal.toInt().toString() : cclVal.toString();
                  return Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Casual Leaves Left', style: TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.w500)),
                              const SizedBox(height: 4),
                              Text('$clStr CL', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0067B8).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF0067B8).withValues(alpha: 0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Earned Leaves Left', style: TextStyle(fontSize: 12, color: Color(0xFF0067B8), fontWeight: FontWeight.w500)),
                              const SizedBox(height: 4),
                              Text('$cclStr EL', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0067B8))),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],

            const SizedBox(height: 16),

            // Half Day Switch & Selector
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[850] : Colors.deepPurple.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.2)),
              ),
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Apply for Half Day',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    subtitle: const Text(
                      'Request leave for only one half of a day (0.5 day deduction)',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: _isHalfDay,
                    onChanged: (val) {
                      setState(() {
                        _isHalfDay = val;
                        if (val && _startDate != null) {
                          _endDate = _startDate;
                        }
                      });
                    },
                    activeColor: Colors.deepPurple,
                  ),
                  if (_isHalfDay) ...[
                    const Divider(),
                    Row(
                      children: [
                        const Text(
                          'Session:',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(
                                value: 'first',
                                label: Text('First Half'),
                                icon: Icon(Icons.wb_sunny_outlined, size: 16),
                              ),
                              ButtonSegment(
                                value: 'second',
                                label: Text('Second Half'),
                                icon: Icon(Icons.nights_stay_outlined, size: 16),
                              ),
                            ],
                            selected: {_whichHalf},
                            onSelectionChanged: (Set<String> newSelection) {
                              setState(() {
                                _whichHalf = newSelection.first;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Date Selection
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Start Date',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: _selectStartDate,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(12),
                            color: isDark ? Colors.grey[800] : Colors.grey[100],
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                _startDate != null
                                    ? _formatDate(_startDate!)
                                    : 'Select Date',
                                style: TextStyle(
                                  color: _startDate != null
                                      ? (isDark ? Colors.white : Colors.black87)
                                      : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'End Date',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: _selectEndDate,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(12),
                            color: isDark ? Colors.grey[800] : Colors.grey[100],
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                _endDate != null
                                    ? _formatDate(_endDate!)
                                    : 'Select Date',
                                style: TextStyle(
                                  color: _endDate != null
                                      ? (isDark ? Colors.white : Colors.black87)
                                      : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Reason Text Field
            Text(
              'Reason for Leave',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _reasonController,
              maxLines: 5,
              maxLength: LeaveRequestService.MAX_REASON_LENGTH,
              decoration: InputDecoration(
                hintText:
                    'Please provide detailed reason for your leave request...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: isDark ? Colors.grey[800] : Colors.grey[100],
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please provide a reason for your leave';
                }
                if (value.trim().length < 10) {
                  return 'Reason must be at least 10 characters';
                }
                return null;
              },
            ),

            // Character count
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '${_reasonController.text.length}/${LeaveRequestService.MAX_REASON_LENGTH}',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),

            const SizedBox(height: 20),

            // Error Message
            if (_errorMessage != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),

            // Balance Warnings
            if (_startDate != null && _endDate != null) ...[
              Builder(
                builder: (context) {
                  final requestedDays = _calculateWorkingDays();
                  bool showCLWarning = _selectedLeaveType == 'casual' && requestedDays > (_availableCL ?? 0.0);
                  bool showCCLWarning = _selectedLeaveType == 'earned' && requestedDays > (_availableCCL ?? 0.0);
                  
                  if (showCLWarning) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: Colors.red),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Warning: Selected range requires $requestedDays working days, but you only have ${_availableCL ?? 0.0} Casual Leaves available.',
                              style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  
                  if (showCCLWarning) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: Colors.red),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Warning: Selected range requires $requestedDays working days, but you only have ${_availableCCL ?? 0.0} Earned Leaves available.',
                              style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  
                  return const SizedBox.shrink();
                },
              ),
            ],

            const SizedBox(height: 20),

            // Submit Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submitRequest,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                  backgroundColor: const Color(0xFF3949AB),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Text(
                        'Submit Leave Request',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Leave Request List Widget - shows user's leave requests
class LeaveRequestList extends StatefulWidget {
  final String token;
  final bool showActions;

  const LeaveRequestList({
    super.key,
    required this.token,
    this.showActions = false,
  });

  @override
  State<LeaveRequestList> createState() => _LeaveRequestListState();
}

class _LeaveRequestListState extends State<LeaveRequestList> {
  List<dynamic> _requests = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() {
      _isLoading = true;
    });

    final result = await LeaveRequestService.getMyLeaveRequests(widget.token);

    setState(() {
      _isLoading = false;
      if (result['success'] == true) {
        _requests = result['requests'] ?? [];
      }
    });
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'pending':
        return Icons.hourglass_empty;
      case 'approved':
        return Icons.check_circle;
      case 'rejected':
        return Icons.cancel;
      default:
        return Icons.help;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_requests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_busy, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No leave requests found',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRequests,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _requests.length,
        itemBuilder: (context, index) {
          final request = _requests[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header with status
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        request['leave_type']?.toString().toUpperCase() ??
                            'LEAVE',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _getStatusColor(
                            request['status'] ?? 'pending',
                          ).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _getStatusIcon(request['status'] ?? 'pending'),
                              size: 16,
                              color: _getStatusColor(
                                request['status'] ?? 'pending',
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              (request['status'] ?? 'pending')
                                  .toString()
                                  .toUpperCase(),
                              style: TextStyle(
                                color: _getStatusColor(
                                  request['status'] ?? 'pending',
                                ),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Dates
                  Row(
                    children: [
                      const Icon(
                        Icons.date_range,
                        size: 16,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${request['start_date']} to ${request['end_date']}',
                        style: TextStyle(
                          color: isDark ? Colors.grey[300] : Colors.grey[700],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // Submission date
                  Row(
                    children: [
                      const Icon(Icons.schedule, size: 16, color: Colors.grey),
                      const SizedBox(width: 8),
                      Text(
                        'Submitted: ${request['submission_date']}',
                        style: TextStyle(
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Reason
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[800] : Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      request['reason'] ?? '',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),

                  // Admin comment (if any)
                  if (request['admin_comment'] != null &&
                      request['admin_comment'].toString().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue[200]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Admin Comment:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(request['admin_comment'] ?? ''),
                        ],
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

/// Admin Leave Management Widget
class AdminLeaveManagement extends StatefulWidget {
  final String token;

  const AdminLeaveManagement({super.key, required this.token});

  @override
  State<AdminLeaveManagement> createState() => _AdminLeaveManagementState();
}

class _AdminLeaveManagementState extends State<AdminLeaveManagement>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 400;

    return Column(
      children: [
        TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF3949AB),
          unselectedLabelColor: Colors.grey,
          isScrollable: true,
          labelStyle: isSmallScreen ? const TextStyle(fontSize: 12) : null,
          tabs: const [
            Tab(text: 'All Requests'),
            Tab(text: 'Pending'),
            Tab(text: 'Expired Leaves'),
            Tab(text: 'Staff Alternate Leaves'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              AdminLeaveRequestList(token: widget.token),
              AdminPendingRequestList(token: widget.token),
              ExpiredLeavesList(token: widget.token),
              AdminStaffLeaveTab(
                token: widget.token,
                accentColor: const Color(0xFF3949AB),
              ),
            ],
          ),
        ),
      ],
    );
  }
}


/// Admin Leave Request List
class AdminLeaveRequestList extends StatefulWidget {
  final String token;
  final bool showPendingOnly;

  const AdminLeaveRequestList({
    super.key,
    required this.token,
    this.showPendingOnly = false,
  });

  @override
  State<AdminLeaveRequestList> createState() => _AdminLeaveRequestListState();
}

class _AdminLeaveRequestListState extends State<AdminLeaveRequestList> {
  List<dynamic> _requests = [];
  bool _isLoading = true;
  String? _statusFilter;
  String? _deptFilter;
  String _searchQuery = '';
  String _sortBy = 'submission_date';
  String _sortOrder = 'desc';

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() {
      _isLoading = true;
    });

    final result = await LeaveRequestService.adminGetLeaveRequests(
      token: widget.token,
      status: _statusFilter,
      dept: _deptFilter,
      search: _searchQuery.isNotEmpty ? _searchQuery : null,
      sortBy: _sortBy,
      sortOrder: _sortOrder,
    );

    setState(() {
      _isLoading = false;
      if (result['success'] == true) {
        _requests = result['requests'] ?? [];
      }
    });
  }

  void _showRequestDetails(dynamic request) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => LeaveRequestDetailSheet(
        token: widget.token,
        request: request,
        onActionCompleted: _loadRequests,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 400;

    return Column(
      children: [
        // Filters
        Padding(
          padding: EdgeInsets.all(isSmallScreen ? 8 : 16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 350;
              return Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: isNarrow
                            ? 'Search...'
                            : 'Search by name or reg no...',
                        prefixIcon: Icon(isNarrow ? null : Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: isDark ? Colors.grey[800] : Colors.grey[100],
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: isSmallScreen ? 12 : 16,
                          vertical: 10,
                        ),
                      ),
                      style: TextStyle(fontSize: isSmallScreen ? 13 : 14),
                      onChanged: (value) {
                        _searchQuery = value;
                        _loadRequests();
                      },
                    ),
                  ),
                  SizedBox(width: isSmallScreen ? 4 : 8),
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.filter_list,
                      size: isSmallScreen ? 20 : 24,
                    ),
                    onSelected: (value) {
                      setState(() {
                        _statusFilter = value == 'all' ? null : value;
                      });
                      _loadRequests();
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'all', child: Text('All')),
                      const PopupMenuItem(
                        value: 'pending',
                        child: Text('Pending'),
                      ),
                      const PopupMenuItem(
                        value: 'approved',
                        child: Text('Approved'),
                      ),
                      const PopupMenuItem(
                        value: 'rejected',
                        child: Text('Rejected'),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),

        // Request List
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _requests.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.inbox,
                        size: 64,
                        color: isDark ? Colors.grey[500] : Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No requests found',
                        style: TextStyle(
                          fontSize: 18,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadRequests,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isSmallScreen = constraints.maxWidth < 400;
                      final horizontalPadding = isSmallScreen ? 8.0 : 12.0;
                      return ListView.builder(
                        padding: EdgeInsets.symmetric(
                          horizontal: horizontalPadding,
                          vertical: 8,
                        ),
                        itemCount: _requests.length,
                        itemBuilder: (context, index) {
                          final request = _requests[index];
                          return _buildRequestCard(
                            request,
                            isDark,
                            isSmallScreen,
                          );
                        },
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildRequestCard(dynamic request, bool isDark, bool isSmallScreen) {
    Color statusColor;
    switch (request['status']) {
      case 'pending':
        statusColor = Colors.orange;
        break;
      case 'approved':
        statusColor = Colors.green;
        break;
      case 'rejected':
        statusColor = Colors.red;
        break;
      default:
        statusColor = Colors.grey;
    }

    final cardPadding = isSmallScreen ? 12.0 : 16.0;
    final iconSize = isSmallScreen ? 14.0 : 16.0;
    final fontSize = isSmallScreen ? 12.0 : 14.0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _showRequestDetails(request),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.all(cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          request['user_name'] ?? '',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: fontSize + 2,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          request['user_reg_no'] ?? '',
                          style: TextStyle(
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: isSmallScreen ? 8 : 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      (request['status'] ?? 'pending').toString().toUpperCase(),
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Department and date row - wrapped for smaller screens
              if (isSmallScreen)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.business,
                          size: iconSize,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            request['dept'] ?? '',
                            style: TextStyle(
                              color: isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.date_range,
                          size: iconSize,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${request['start_date']} - ${request['end_date']}',
                            style: TextStyle(
                              color: isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    const Icon(Icons.business, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        request['dept'] ?? '',
                        style: TextStyle(
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Icon(Icons.date_range, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '${request['start_date']} - ${request['end_date']}',
                        style: TextStyle(
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 8),
              Text(
                'Submitted: ${request['submission_date']}',
                style: TextStyle(
                  color: isDark ? Colors.grey[400] : Colors.grey[500],
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Admin Pending Request List
class AdminPendingRequestList extends StatefulWidget {
  final String token;

  const AdminPendingRequestList({super.key, required this.token});

  @override
  State<AdminPendingRequestList> createState() =>
      _AdminPendingRequestListState();
}

class _AdminPendingRequestListState extends State<AdminPendingRequestList> {
  List<dynamic> _requests = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() {
      _isLoading = true;
    });

    final result = await LeaveRequestService.adminGetPendingRequests(
      widget.token,
    );

    setState(() {
      _isLoading = false;
      if (result['success'] == true) {
        _requests = result['requests'] ?? [];
      }
    });
  }

  void _showRequestDetails(dynamic request) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => LeaveRequestDetailSheet(
        token: widget.token,
        request: request,
        onActionCompleted: _loadRequests,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_requests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 64,
              color: isDark ? Colors.green[400] : Colors.green[300],
            ),
            const SizedBox(height: 16),
            Text(
              'No pending requests',
              style: TextStyle(
                fontSize: 18,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRequests,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: _requests.length,
        itemBuilder: (context, index) {
          final request = _requests[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: isDark ? Colors.orange[400]! : Colors.orange[200]!,
                width: 2,
              ),
            ),
            child: InkWell(
              onTap: () => _showRequestDetails(request),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                request['user_name'] ?? '',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                request['user_reg_no'] ?? '',
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.grey[400]
                                      : Colors.grey[600],
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange[100],
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.hourglass_empty,
                                size: 14,
                                color: Colors.orange[700],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'PENDING',
                                style: TextStyle(
                                  color: Colors.orange[700],
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Department and date row - using Flexible for responsive behavior
                    Row(
                      children: [
                        const Icon(
                          Icons.business,
                          size: 14,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            request['dept'] ?? '',
                            style: TextStyle(
                              color: isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Icon(
                          Icons.date_range,
                          size: 14,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '${request['start_date']} - ${request['end_date']}',
                            style: TextStyle(
                              color: isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Submitted: ${request['submission_date']}',
                      style: TextStyle(
                        color: isDark ? Colors.grey[400] : Colors.grey[500],
                        fontSize: 12,
                      ),
                    ),
                    if (!(request['is_read'] ?? false)) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue[100],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'NEW',
                          style: TextStyle(
                            color: Colors.blue,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Leave Request Detail Sheet - for admin to approve/reject
class LeaveRequestDetailSheet extends StatefulWidget {
  final String token;
  final dynamic request;
  final VoidCallback? onActionCompleted;

  const LeaveRequestDetailSheet({
    super.key,
    required this.token,
    required this.request,
    this.onActionCompleted,
  });

  @override
  State<LeaveRequestDetailSheet> createState() =>
      _LeaveRequestDetailSheetState();
}

class _LeaveRequestDetailSheetState extends State<LeaveRequestDetailSheet> {
  final _commentController = TextEditingController();
  bool _isLoading = false;

  double? _userAvailableCL;
  double? _userAvailableEL;
  bool _loadingUserBalances = false;

  @override
  void initState() {
    super.initState();
    _fetchUserBalances();
  }

  Future<void> _fetchUserBalances() async {
    final regNo = widget.request['user_reg_no'];
    if (regNo == null) return;
    if (!mounted) return;
    setState(() => _loadingUserBalances = true);
    try {
      // CL Status
      final clResponse = await http.get(
        Uri.parse('${CollegeIPConfig.defaultURL}/cl/status/$regNo'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (clResponse.statusCode == 200) {
        final clData = json.decode(clResponse.body);
        if (clData['success'] == true) {
          _userAvailableCL = (clData['data']['total_cl_available'] as num?)?.toDouble();
        }
      }

      // EL Status
      final cclResponse = await http.get(
        Uri.parse('${CollegeIPConfig.defaultURL}/ccl/status/$regNo'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (cclResponse.statusCode == 200) {
        final cclData = json.decode(cclResponse.body);
        if (cclData['success'] == true) {
          _userAvailableEL = (cclData['data']['earned_leave_available'] as num?)?.toDouble();
        }
      }
    } catch (e) {
      print('Error fetching requester balances: $e');
    } finally {
      if (mounted) {
        setState(() => _loadingUserBalances = false);
      }
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _approveRequest() async {
    setState(() {
      _isLoading = true;
    });

    final result = await LeaveRequestService.adminApproveRequest(
      token: widget.token,
      requestId: widget.request['id'],
      comment: _commentController.text.trim(),
    );

    setState(() {
      _isLoading = false;
    });

    if (result['success'] == true) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Leave request approved!'),
            backgroundColor: Colors.green,
          ),
        );
        LeaveBalanceNotifier.instance.notifyBalanceChanged();
        widget.onActionCompleted?.call();
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Failed to approve request'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _rejectRequest() async {
    if (_commentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please provide a reason for rejection'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final result = await LeaveRequestService.adminRejectRequest(
      token: widget.token,
      requestId: widget.request['id'],
      comment: _commentController.text.trim(),
    );

    setState(() {
      _isLoading = false;
    });

    if (result['success'] == true) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Leave request rejected!'),
            backgroundColor: Colors.red,
          ),
        );
        LeaveBalanceNotifier.instance.notifyBalanceChanged();
        widget.onActionCompleted?.call();
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Failed to reject request'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final request = widget.request;
    final isPending = request['status'] == 'pending';

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: ListView(
            controller: scrollController,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Header
              Text(
                'Leave Request Details',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 20),

              // User Info
              _buildInfoRow('Employee', request['user_name'] ?? ''),
              _buildInfoRow('Reg No', request['user_reg_no'] ?? ''),
              _buildInfoRow('Department', request['dept'] ?? ''),
              _buildInfoRow('Leave Type', request['leave_type'] ?? ''),
              _buildInfoRow('Start Date', request['start_date'] ?? ''),
              _buildInfoRow('End Date', request['end_date'] ?? ''),
              _buildInfoRow('Submitted', request['submission_date'] ?? ''),

              // Available Balances for this user
              const SizedBox(height: 8),
              if (_loadingUserBalances)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Center(
                    child: SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: const Color(0xFF0067B8)),
                    ),
                  ),
                )
              else ...[
                _buildInfoRow('Available CL', _userAvailableCL != null ? '$_userAvailableCL CL' : 'Loading...'),
                _buildInfoRow('Available EL', _userAvailableEL != null ? '$_userAvailableEL EL' : 'Loading...'),
              ],


              // Status
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _getStatusColor(
                    request['status'] ?? 'pending',
                  ).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      _getStatusIcon(request['status'] ?? 'pending'),
                      color: _getStatusColor(request['status'] ?? 'pending'),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      (request['status'] ?? 'pending').toString().toUpperCase(),
                      style: TextStyle(
                        color: _getStatusColor(request['status'] ?? 'pending'),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              // Reason
              const SizedBox(height: 20),
              Text(
                'Reason:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[800] : Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  request['reason'] ?? '',
                  style: const TextStyle(fontSize: 14),
                ),
              ),

              // Admin Comment (if any)
              if (request['admin_comment'] != null &&
                  request['admin_comment'].toString().isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Admin Comment:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Text(request['admin_comment'] ?? ''),
                ),
              ],

              // Comment field (for pending requests)
              if (isPending) ...[
                const SizedBox(height: 20),
                Text(
                  'Add Comment:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _commentController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText:
                        'Optional comment for approval, required for rejection...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: isDark ? Colors.grey[800] : Colors.grey[100],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Action buttons (for pending requests)
              if (isPending)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isLoading ? null : _rejectRequest,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.all(16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Reject'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _approveRequest,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.all(16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : const Text('Approve'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey[600],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'pending':
        return Icons.hourglass_empty;
      case 'approved':
        return Icons.check_circle;
      case 'rejected':
        return Icons.cancel;
      default:
        return Icons.help;
    }
  }
}

/// Admin Notifications Widget
class AdminNotificationsWidget extends StatefulWidget {
  final String token;

  const AdminNotificationsWidget({super.key, required this.token});

  @override
  State<AdminNotificationsWidget> createState() =>
      _AdminNotificationsWidgetState();
}

/// Staff Leave Request Tab — Unified single leave interface:
///   1. Apply Leave (Smart form with CL/EL balance, class detection, and alternate picker)
///   2. My Requests (Live status tracking, cancellation, re-nomination)
///   3. Coverage Requests (Incoming nominations with live badge and countdown)
///   4. Expired Leaves (History list)
///   5. Dept Staff Approvals (HOD) / All Staff Approvals (Admin)
class StaffLeaveRequestTab extends StatefulWidget {
  final String token;
  final Color accentColor;
  final bool isHod;
  final bool isAdmin;

  const StaffLeaveRequestTab({
    super.key,
    required this.token,
    this.accentColor = const Color(0xFF007AFF),
    this.isHod = false,
    this.isAdmin = false,
  });

  @override
  State<StaffLeaveRequestTab> createState() => _StaffLeaveRequestTabState();
}

class _StaffLeaveRequestTabState extends State<StaffLeaveRequestTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _altBadge = 0;

  int get _tabCount => (widget.isHod || widget.isAdmin) ? 5 : 4;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabCount, vsync: this);
    _loadBadge();
  }

  Future<void> _loadBadge() async {
    try {
      final res = await http.get(
        Uri.parse('${CollegeIPConfig.defaultURL}/staff/leave/alternate/pending'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (mounted) {
          setState(() {
            _altBadge = ((data['pending_nominations'] as List?)?.length ?? 0);
          });
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isMobile = screenWidth < 650;

    final List<Widget> tabs = [
      Tab(text: isMobile ? 'Apply' : 'Apply Leave'),
      Tab(text: isMobile ? 'Requests' : 'My Requests'),
      Tab(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(isMobile ? 'Coverage' : 'Coverage Requests'),
            if (_altBadge > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _altBadge > 99 ? '99+' : _altBadge.toString(),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ],
        ),
      ),
      Tab(text: isMobile ? 'History' : 'Expired Leaves'),
    ];

    if (widget.isHod) {
      tabs.add(Tab(text: isMobile ? 'Approvals' : 'Dept Staff Approvals'));
    } else if (widget.isAdmin) {
      tabs.add(Tab(text: isMobile ? 'Approvals' : 'All Staff Approvals'));
    }

    final List<Widget> tabViews = [
      StaffSubmitRequestPane(
        token: widget.token,
        onSubmitted: () {
          _tabController.animateTo(1);
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
      ExpiredLeavesList(token: widget.token),
    ];

    if (widget.isHod) {
      tabViews.add(
        HodStaffLeaveReviewTab(
          token: widget.token,
          accentColor: widget.accentColor,
        ),
      );
    } else if (widget.isAdmin) {
      tabViews.add(
        AdminStaffLeaveTab(
          token: widget.token,
          accentColor: widget.accentColor,
        ),
      );
    }

    return Column(
      children: [
        TabBar(
          controller: _tabController,
          labelColor: widget.accentColor,
          unselectedLabelColor: Colors.grey,
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
          tabs: tabs,
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: tabViews,
          ),
        ),
      ],
    );
  }
}

/// Expired Leaves List Widget - displays historical list of expired leaves with search & department filters
class ExpiredLeavesList extends StatefulWidget {
  final String token;

  const ExpiredLeavesList({super.key, required this.token});

  @override
  State<ExpiredLeavesList> createState() => _ExpiredLeavesListState();
}

class _ExpiredLeavesListState extends State<ExpiredLeavesList> {
  List<dynamic> _expiredLeaves = [];
  bool _isLoading = true;
  String? _error;
  String _searchQuery = '';
  String _selectedDept = 'All';
  List<String> _departments = ['All'];

  String _selectedLeaveType = 'All';
  final List<String> _leaveTypeOptions = [
    'All',
    'Casual Leave (CL)',
    'Earned Leave (EL)',
    'Sick Leave',
    'Other'
  ];

  @override
  void initState() {
    super.initState();
    _loadDepartments();
    _loadExpiredLeaves();
  }

  Future<void> _loadDepartments() async {
    try {
      final res = await http.get(
        Uri.parse('${CollegeIPConfig.defaultURL}/admin/departments'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data['success'] == true && data['departments'] != null) {
          final depts = (data['departments'] as List).map((d) => d['name'].toString()).toList();
          setState(() {
            _departments = ['All', ...depts];
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _loadExpiredLeaves() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final res = await LeaveRequestService.getExpiredLeaves(
      widget.token,
      dept: _selectedDept,
    );

    if (mounted) {
      setState(() {
        _isLoading = false;
        if (res['success'] == true) {
          _expiredLeaves = res['expired_leaves'] ?? [];
        } else {
          _error = res['message'] ?? 'Failed to load expired leaves';
        }
      });
    }
  }

  List<dynamic> get _filteredLeaves {
    return _expiredLeaves.where((item) {
      final leaveType = (item['leave_type'] ?? '').toString();
      
      // Filter by Leave Type
      if (_selectedLeaveType != 'All') {
        if (_selectedLeaveType == 'Casual Leave (CL)' && !leaveType.contains('Casual')) return false;
        if (_selectedLeaveType == 'Earned Leave (EL)' && !leaveType.contains('Earned') && !leaveType.contains('CCL')) return false;
        if (_selectedLeaveType == 'Sick Leave' && !leaveType.contains('Sick')) return false;
        if (_selectedLeaveType == 'Other' && (leaveType.contains('Casual') || leaveType.contains('Earned') || leaveType.contains('CCL') || leaveType.contains('Sick'))) return false;
      }

      // Filter by Search Query
      if (_searchQuery.trim().isNotEmpty) {
        final query = _searchQuery.toLowerCase().trim();
        final name = (item['user_name'] ?? '').toString().toLowerCase();
        final regNo = (item['reg_no'] ?? '').toString().toLowerCase();
        final lType = leaveType.toLowerCase();
        final dept = (item['dept'] ?? '').toString().toLowerCase();
        return name.contains(query) || regNo.contains(query) || lType.contains(query) || dept.contains(query);
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final displayedList = _filteredLeaves;

    return Column(
      children: [
        // Filter Header Bar
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade100,
            border: Border(bottom: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  // Search Input
                  Expanded(
                    child: TextField(
                      onChanged: (val) => setState(() => _searchQuery = val),
                      decoration: InputDecoration(
                        hintText: 'Search staff name, reg no...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF2C2C2C) : Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Department Dropdown Filter
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2C2C2C) : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _departments.contains(_selectedDept) ? _selectedDept : 'All',
                        icon: const Icon(Icons.filter_list, size: 18),
                        onChanged: (newDept) {
                          if (newDept != null) {
                            setState(() => _selectedDept = newDept);
                            _loadExpiredLeaves();
                          }
                        },
                        items: _departments.map((dept) {
                          return DropdownMenuItem<String>(
                            value: dept,
                            child: Text(
                              dept == 'All' ? 'All Depts' : dept,
                              style: const TextStyle(fontSize: 13),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.category_outlined, size: 16, color: Colors.grey),
                  const SizedBox(width: 6),
                  const Text('Leave Type: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _leaveTypeOptions.map((type) {
                          final isSelected = _selectedLeaveType == type;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: FilterChip(
                              selected: isSelected,
                              label: Text(type, style: TextStyle(fontSize: 11, color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87))),
                              selectedColor: const Color(0xFF007AFF),
                              backgroundColor: isDark ? const Color(0xFF2C2C2C) : Colors.grey.shade200,
                              onSelected: (selected) {
                                setState(() {
                                  _selectedLeaveType = type;
                                });
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),


        // Body List / Loader / Empty State
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF007AFF)))
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(_error!, style: const TextStyle(color: Colors.red)),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: _loadExpiredLeaves,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : displayedList.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.history_toggle_off_rounded, size: 64, color: isDark ? Colors.white30 : Colors.grey[400]),
                              const SizedBox(height: 16),
                              Text(
                                'No expired leaves found',
                                style: TextStyle(fontSize: 16, color: isDark ? Colors.white60 : Colors.grey[600]),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadExpiredLeaves,
                          color: const Color(0xFF007AFF),
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: displayedList.length,
                            itemBuilder: (context, index) {
                              final item = displayedList[index];
                              final leaveType = item['leave_type'] ?? 'Leave';
                              final amount = item['expired_amount'] ?? 0.0;
                              final date = item['expiry_date'] ?? '';
                              final reason = item['reason'] ?? 'Expired';
                              final userName = item['user_name'] ?? '';
                              final regNo = item['reg_no'] ?? '';
                              final dept = item['dept'] ?? '';

                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
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
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color: Colors.red.withValues(alpha: 0.1),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: const Icon(Icons.timer_off_rounded, color: Colors.red, size: 20),
                                              ),
                                              const SizedBox(width: 12),
                                              Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    leaveType,
                                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                                  ),
                                                  if (userName.isNotEmpty)
                                                    Text(
                                                      '$userName ($regNo • $dept)',
                                                      style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey[600]),
                                                    ),
                                                ],
                                              ),
                                            ],
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.red.shade50,
                                              borderRadius: BorderRadius.circular(20),
                                              border: Border.all(color: Colors.red.shade200),
                                            ),
                                            child: Text(
                                              '-$amount Days',
                                              style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold, fontSize: 12),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      const Divider(height: 1),
                                      const SizedBox(height: 8),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(Icons.event_outlined, size: 14, color: isDark ? Colors.white54 : Colors.grey[600]),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Expiry Date: $date',
                                                style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.grey[700]),
                                              ),
                                            ],
                                          ),
                                          Text(
                                            reason,
                                            style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: isDark ? Colors.white54 : Colors.grey[600]),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }
}



class _AdminNotificationsWidgetState extends State<AdminNotificationsWidget> {
  List<dynamic> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() {
      _isLoading = true;
    });

    final result = await LeaveRequestService.getAdminNotifications(
      widget.token,
    );

    setState(() {
      _isLoading = false;
      if (result['success'] == true) {
        _notifications = result['notifications'] ?? [];
      }
    });
  }

  Future<void> _markAsRead(int notificationId) async {
    await LeaveRequestService.markNotificationRead(
      widget.token,
      notificationId,
    );
    _loadNotifications();
  }

  Future<void> _markAllAsRead() async {
    await LeaveRequestService.markAllNotificationsRead(widget.token);
    _loadNotifications();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        // Header with mark all as read button
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Notifications',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              TextButton.icon(
                onPressed: _markAllAsRead,
                icon: const Icon(Icons.done_all),
                label: const Text('Mark all as read'),
              ),
            ],
          ),
        ),

        // Notifications List
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _notifications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.notifications_none,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No notifications',
                        style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadNotifications,
                  child: ListView.builder(
                    itemCount: _notifications.length,
                    itemBuilder: (context, index) {
                      final notification = _notifications[index];
                      return _buildNotificationCard(notification, isDark);
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildNotificationCard(dynamic notification, bool isDark) {
    final isRead = notification['is_read'] ?? false;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: isRead ? null : Colors.blue[50],
      child: InkWell(
        onTap: () => _markAsRead(notification['id']),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _getNotificationIcon(notification['type']),
                  color: Colors.blue[700],
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification['title'] ?? '',
                      style: TextStyle(
                        fontWeight: isRead
                            ? FontWeight.normal
                            : FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notification['message'] ?? '',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notification['created_at'] ?? '',
                      style: TextStyle(color: Colors.grey[400], fontSize: 10),
                    ),
                  ],
                ),
              ),
              if (!isRead)
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getNotificationIcon(String? type) {
    switch (type) {
      case 'leave_request':
        return Icons.event_note;
      default:
        return Icons.notifications;
    }
  }
}
