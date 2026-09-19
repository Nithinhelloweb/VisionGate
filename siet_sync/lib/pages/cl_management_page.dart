import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/college_ip_config.dart';
import '../utils/api_response_utils.dart';

class CLManagementPage extends StatefulWidget {
  final String token;

  const CLManagementPage({super.key, required this.token});

  @override
  State<CLManagementPage> createState() => _CLManagementPageState();
}

class _CLManagementPageState extends State<CLManagementPage> {
  List<dynamic> _clData = [];
  List<dynamic> _filteredCLData = [];
  List<String> _departments = [];
  List<String> _roles = ['All'];
  List<String> _users = ['All'];
  String? _selectedDepartment = 'All';
  String? _selectedRole = 'All';
  String? _selectedUser;
  bool _isLoading = true;
  String _currentMonth = '';
  String? _error;
  String? _clExpiryDate;

  Future<void> _fetchLeaveSettings() async {
    try {
      final res = await http.get(
        Uri.parse('${CollegeIPConfig.defaultURL}/admin/leave-settings'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data['success'] == true && data['settings'] != null) {
          setState(() {
            final fetched = data['settings']['cl_expiry_date'];
            if (fetched != null && fetched.toString().isNotEmpty) {
              _clExpiryDate = fetched;
            } else {
              final default3m = DateTime.now().add(const Duration(days: 90));
              _clExpiryDate = '${default3m.year}-${default3m.month.toString().padLeft(2, '0')}-${default3m.day.toString().padLeft(2, '0')}';
            }
          });
        }
      }
    } catch (e) {
      print('Error fetching leave settings: $e');
    }
  }

  Future<void> _updateCLExpiryDate(String? newDate) async {
    try {
      final res = await http.post(
        Uri.parse('${CollegeIPConfig.defaultURL}/admin/leave-settings'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
        body: json.encode({'cl_expiry_date': newDate ?? ''}),
      );
      if (res.statusCode == 200) {
        setState(() {
          _clExpiryDate = newDate;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(newDate != null && newDate.isNotEmpty
                  ? 'CL Expiry Date set to $newDate'
                  : 'CL Expiry Date cleared'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating CL expiry: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  List<String> _uniqueStrings(Iterable<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      final v = value.trim();
      if (v.isEmpty || seen.contains(v)) continue;
      seen.add(v);
      result.add(v);
    }
    return result;
  }

  String _normalizeManagementDept(String dept) {
    final normalized = dept.trim().toLowerCase();
    if (normalized.isEmpty) return '';
    if (normalized == 'placement staff' || normalized == 'placement') {
      return 'Placement';
    }
    if (normalized == 'lab technician' || normalized == 'lab') {
      return 'Lab';
    }
    if (normalized == 'administration') {
      return 'Administration';
    }
    if (normalized == 'system admin' || normalized == 'system_admin' || normalized == 'it') {
      return 'System Admin';
    }
    if (normalized == 'office staff' || normalized == 'office') {
      return 'Office Staff';
    }
    return dept.trim();
  }

  @override
  void initState() {
    super.initState();
    _loadCLData();
    _loadDepartments();
    _fetchLeaveSettings();
  }

  Future<void> _loadDepartments() async {
    try {
      final url = '${CollegeIPConfig.defaultURL}/admin/departments';
      final response = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _departments = ['All'];
          if (data['departments'] != null) {
            // Handle both list of strings and list of objects
            for (var dept in data['departments']) {
              if (dept is String) {
                _departments.add(dept.trim());
              } else if (dept is Map && dept['name'] != null) {
                _departments.add(dept['name'].toString().trim());
              }
            }
          }
          // Add Other User Departments
          if (!_departments.contains('Administration')) {
            _departments.add('Administration');
          }
          if (!_departments.contains('Placement')) {
            _departments.add('Placement');
          }
          if (!_departments.contains('Lab')) {
            _departments.add('Lab');
          }
          if (!_departments.contains('System Admin')) {
            _departments.add('System Admin');
          }
          if (!_departments.contains('Office Staff')) {
            _departments.add('Office Staff');
          }
          // Replace the 5 other departments with single "Management" option
          _departments.remove('Administration');
          _departments.remove('Placement');
          _departments.remove('Lab');
          _departments.remove('System Admin');
          _departments.remove('Office Staff');
          if (!_departments.contains('Management')) {
            _departments.add('Management');
          }
          _departments = _uniqueStrings(_departments);
        });
      }
    } catch (e) {
      // If department API fails, populate from CL data
      setState(() {
        _departments = ['All'];
        for (var staff in _clData) {
          final dept = staff['dept'];
          if (dept != null && !_departments.contains(dept)) {
            _departments.add(dept);
          }
        }
        // Replace the 5 other departments with single "Management" option
        _departments.remove('Administration');
        _departments.remove('Placement');
        _departments.remove('Lab');
        _departments.remove('System Admin');
        _departments.remove('Office Staff');
        if (!_departments.contains('Management')) {
          _departments.add('Management');
        }
        _departments = _uniqueStrings(_departments);
      });
    }
  }

  void _filterByDepartment(String? dept) {
    setState(() {
      _selectedDepartment = dept ?? 'All';
      _selectedRole = 'All';
      _selectedUser = null;  // Reset user selection when department changes
      // Update roles based on department selection
      _updateRolesForDepartment(_selectedDepartment);
      _updateFilteredData();
    });
  }

  void _updateRolesForDepartment(String? dept) {
    if (dept == null || dept == 'All') {
      // Show HOD and Staff when no department is selected
      _roles = ['All', 'HOD', 'Staff'];
    } else if (dept == 'Management') {
      // Show all 5 management departments as role options
      _roles = ['All', 'Administration', 'Placement', 'Lab', 'System Admin', 'Office Staff'];
    } else {
      // For regular departments, show HOD and Staff
      _roles = ['All', 'HOD', 'Staff'];
    }
    _roles = _uniqueStrings(_roles);
  }

  void _filterByRole(String? role) {
    setState(() {
      _selectedRole = role ?? 'All';
      _selectedUser = null;  // Reset user selection when role changes
      _updateFilteredData();
    });
  }

  void _filterByUser(String? user) {
    setState(() {
      _selectedUser = user;
      _updateFilteredData();
    });
  }

  void _updateFilteredData() {
    // Management departments list
    final managementDepts = [
      'Administration',
      'Placement',
      'Lab',
      'System Admin',
      'Office Staff',
    ];
    
    _filteredCLData = _clData.where((staff) {
      // Filter by department
      if (_selectedDepartment != null && _selectedDepartment != 'All') {
        if (_selectedDepartment == 'Management') {
          // For Management, include all 5 management departments
          final staffDeptNorm =
              _normalizeManagementDept((staff['dept'] ?? '').toString());
          if (!managementDepts.contains(staffDeptNorm)) {
            return false;
          }
        } else if (staff['dept'] != _selectedDepartment) {
          return false;
        }
      }
      // Filter by role
      if (_selectedRole != null && _selectedRole != 'All') {
        final staffRole = (staff['role'] ?? '').toString().toLowerCase();
        final selectedRoleLower = _selectedRole!.toLowerCase();
        if (staffRole != selectedRoleLower) {
          // Check for management staff roles
          if (managementDepts.contains(_selectedRole)) {
            final staffDeptNorm =
                _normalizeManagementDept((staff['dept'] ?? '').toString());
            if (staffDeptNorm != _selectedRole) {
              return false;
            }
          } else {
            return false;
          }
        }
      }
      // Filter by user
      if (_selectedUser != null && _selectedUser!.isNotEmpty && _selectedUser != 'All') {
        // Extract reg_no from "Name (REG001)" and match safely.
        final match = RegExp(r'\(([^()]*)\)\s*$').firstMatch(_selectedUser!);
        final selectedRegNo = (match?.group(1) ?? _selectedUser!).trim().toLowerCase();
        final staffRegNo = (staff['reg_no'] ?? '').toString().trim().toLowerCase();
        if (staffRegNo != selectedRegNo) {
          return false;
        }
      }
      return true;
    }).toList();
    
    // Update user list based on department and role (not by selected user)
    // This ensures all users are available in dropdown regardless of current selection
    _users = ['All'];
    final tempFiltered = _clData.where((staff) {
      // Filter by department (same as _filteredCLData)
      if (_selectedDepartment != null && _selectedDepartment != 'All') {
        if (_selectedDepartment == 'Management') {
          final staffDeptNorm =
              _normalizeManagementDept((staff['dept'] ?? '').toString());
          if (!managementDepts.contains(staffDeptNorm)) {
            return false;
          }
        } else if (staff['dept'] != _selectedDepartment) {
          return false;
        }
      }
      // Filter by role (same as _filteredCLData)
      if (_selectedRole != null && _selectedRole != 'All') {
        final staffRole = (staff['role'] ?? '').toString().toLowerCase();
        final selectedRoleLower = _selectedRole!.toLowerCase();
        if (staffRole != selectedRoleLower) {
          if (managementDepts.contains(_selectedRole)) {
            final staffDeptNorm =
                _normalizeManagementDept((staff['dept'] ?? '').toString());
            if (staffDeptNorm != _selectedRole) {
              return false;
            }
          } else {
            return false;
          }
        }
      }
      // DO NOT filter by user here - we want ALL users in the dropdown
      return true;
    }).toList();
    
    for (var staff in tempFiltered) {
      final regNo = staff['reg_no'];
      final name = staff['name'];
      if (regNo != null && name != null) {
        _users.add('$name ($regNo)');
      }
    }
    _users = _uniqueStrings(_users);
  }

  Future<void> _loadCLData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final url = '${CollegeIPConfig.defaultURL}/admin/cl/all';
      final response = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _clData = data['data'] ?? [];
          _currentMonth = data['current_month'] ?? '';
          _isLoading = false;
          
          // Populate departments from CL data if not loaded
          if (_departments.length <= 1) {
            if (_departments.isEmpty) {
              _departments = ['All'];
            }
            for (var staff in _clData) {
              final dept = staff['dept'];
              if (dept != null && !_departments.contains(dept)) {
                _departments.add(dept);
              }
            }
            // Replace the 5 other departments with single "Management" option
            _departments.remove('Administration');
            _departments.remove('Placement');
            _departments.remove('Lab');
            _departments.remove('System Admin');
            _departments.remove('Office Staff');
            if (!_departments.contains('Management')) {
              _departments.add('Management');
            }
            _departments = _uniqueStrings(_departments);
          }
          
          // Initialize roles based on department
          _updateRolesForDepartment(_selectedDepartment);
          
          // Initialize filtered data and users
          _updateFilteredData();
        });
      } else {
        setState(() {
          _error = 'Failed to load CL data: ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error loading CL data: ${ApiResponseUtils.sanitize(e)}';
        _isLoading = false;
      });
    }
  }

  Future<void> _adjustCL(String regNo, String name, int currentCL, int accumulatedCL, {int usedCL = 0}) async {
    int currentMonthCL = currentCL;
    int accumulated = accumulatedCL;
    int usedClValue = usedCL;

    final screenWidth = MediaQuery.of(context).size.width;
    final isWideScreen = screenWidth > 400;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    final result = await showDialog<Map<String, int>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.indigo.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.edit_calendar_rounded,
                  color: Colors.indigo,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Adjust CL Balance',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white60 : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildCLRow(
                label: 'Current Month CL',
                value: currentMonthCL,
                isWideScreen: isWideScreen,
                color: Colors.indigo,
                isDark: isDark,
                onDecrease: currentMonthCL > 0
                    ? () => setDialogState(() => currentMonthCL--)
                    : null,
                onIncrease: currentMonthCL < 2
                    ? () => setDialogState(() => currentMonthCL++)
                    : null,
              ),
              const SizedBox(height: 12),
              _buildCLRow(
                label: 'Accumulated CL',
                value: accumulated,
                isWideScreen: isWideScreen,
                color: Colors.teal,
                isDark: isDark,
                onDecrease: accumulated > 0
                    ? () => setDialogState(() => accumulated--)
                    : null,
                onIncrease: accumulated < 2
                    ? () => setDialogState(() => accumulated++)
                    : null,
              ),
              const SizedBox(height: 12),
              _buildCLRow(
                label: 'Used CL',
                value: usedClValue,
                isWideScreen: isWideScreen,
                color: Colors.orange.shade700,
                isDark: isDark,
                onDecrease: usedClValue > 0
                    ? () => setDialogState(() => usedClValue--)
                    : null,
                onIncrease: usedClValue < 20
                    ? () => setDialogState(() => usedClValue++)
                    : null,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: isDark ? Colors.white60 : Colors.grey.shade700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context, {
                  'current_month_cl_available': currentMonthCL,
                  'accumulated_cl': accumulated,
                  'used_cl': usedClValue,
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      try {
        final url = '${CollegeIPConfig.defaultURL}/admin/cl/adjust';
        final response = await http.post(
          Uri.parse(url),
          headers: {
            'Authorization': 'Bearer ${widget.token}',
            'Content-Type': 'application/json',
          },
          body: json.encode({
            'reg_no': regNo,
            ...result,
          }),
        );

        if (response.statusCode == 200) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('CL adjusted successfully'),
                backgroundColor: Colors.green,
              ),
            );
            _loadCLData();
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to adjust CL: ${response.statusCode}'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error adjusting CL: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Widget _buildCLRow({
    required String label,
    required int value,
    required bool isWideScreen,
    required VoidCallback? onDecrease,
    required VoidCallback? onIncrease,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E22) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey.shade200,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ),
          Row(
            children: [
              IconButton(
                onPressed: onDecrease,
                icon: const Icon(Icons.remove_rounded, size: 20),
                style: IconButton.styleFrom(
                  backgroundColor: onDecrease != null 
                    ? color.withOpacity(0.15) 
                    : Colors.transparent,
                  foregroundColor: color,
                  disabledForegroundColor: isDark ? Colors.white24 : Colors.grey.shade300,
                  padding: const EdgeInsets.all(8),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 44,
                alignment: Alignment.center,
                child: Text(
                  value.toString(),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: onIncrease,
                icon: const Icon(Icons.add_rounded, size: 20),
                style: IconButton.styleFrom(
                  backgroundColor: onIncrease != null 
                    ? color.withOpacity(0.15) 
                    : Colors.transparent,
                  foregroundColor: color,
                  disabledForegroundColor: isDark ? Colors.white24 : Colors.grey.shade300,
                  padding: const EdgeInsets.all(8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 400;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? const Color(0xFF0F0F12) : const Color(0xFFF8F9FB);
    final cardBg = isDark ? const Color(0xFF1E1E22) : Colors.white;
    final borderColor = isDark ? Colors.white.withOpacity(0.08) : Colors.grey.shade200;
    
    return Scaffold(
      backgroundColor: scaffoldBg,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline_rounded, size: 48, color: Colors.red[300]),
                      const SizedBox(height: 16),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _loadCLData,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Retry'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 350;
                    return ListView(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      children: [
                        // Header with Title, Month Pill, and Responsive Actions
                        Container(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Casual Leave Management',
                                          style: TextStyle(
                                            fontSize: isSmallScreen ? 18 : 20,
                                            fontWeight: FontWeight.bold,
                                            color: isDark ? Colors.white : Colors.indigo.shade900,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Allocate and track monthly CL balances',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: isDark ? Colors.white60 : Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (_currentMonth.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [Colors.indigo, Colors.deepPurple],
                                        ),
                                        borderRadius: BorderRadius.circular(20),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.indigo.withValues(alpha: 0.2),
                                            blurRadius: 8,
                                            offset: const Offset(0, 3),
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.calendar_month_rounded, color: Colors.white, size: 14),
                                          const SizedBox(width: 4),
                                          Text(
                                            _currentMonth,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () async {
                                      final current = _clExpiryDate != null && _clExpiryDate!.isNotEmpty
                                          ? DateTime.tryParse(_clExpiryDate!) ?? DateTime.now()
                                          : DateTime.now();
                                      final picked = await showDatePicker(
                                        context: context,
                                        initialDate: current,
                                        firstDate: DateTime.now().subtract(const Duration(days: 30)),
                                        lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
                                        helpText: 'SELECT CL EXPIRY DATE',
                                      );
                                      if (picked != null) {
                                        final dateStr = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                                        await _updateCLExpiryDate(dateStr);
                                      }
                                    },
                                    icon: const Icon(Icons.event_rounded, size: 14, color: Colors.indigo),
                                    label: Text(
                                      _clExpiryDate != null && _clExpiryDate!.isNotEmpty
                                          ? 'Expires: $_clExpiryDate'
                                          : 'Set Expiry Date',
                                      style: const TextStyle(fontSize: 11, color: Colors.indigo, fontWeight: FontWeight.bold),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(color: Colors.indigo),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                  if (_clExpiryDate != null && _clExpiryDate!.isNotEmpty)
                                    IconButton(
                                      icon: const Icon(Icons.clear, size: 16, color: Colors.grey),
                                      tooltip: 'Clear Expiry Date',
                                      constraints: const BoxConstraints(),
                                      padding: const EdgeInsets.all(6),
                                      onPressed: () => _updateCLExpiryDate(''),
                                    ),
                                  OutlinedButton.icon(
                                    onPressed: () async {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: const Text('Expire All CL Balances?'),
                                          content: const Text('This will set all available and accumulated Casual Leave balances to 0 immediately.'),
                                          actions: [
                                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                            ElevatedButton(
                                              onPressed: () => Navigator.pop(ctx, true),
                                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                              child: const Text('Expire All CL', style: TextStyle(color: Colors.white)),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirm == true) {
                                        try {
                                          final res = await http.post(
                                            Uri.parse('${CollegeIPConfig.defaultURL}/admin/cl/expire'),
                                            headers: {'Authorization': 'Bearer ${widget.token}'},
                                          );
                                          if (mounted && res.statusCode == 200) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('All CL balances expired successfully'), backgroundColor: Colors.red),
                                            );
                                            _loadCLData();
                                          }
                                        } catch (e) {
                                          if (mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text('Error expiring CL: $e'), backgroundColor: Colors.red),
                                            );
                                          }
                                        }
                                      }
                                    },
                                    icon: const Icon(Icons.timer_off_rounded, size: 14, color: Colors.red),
                                    label: const Text('Expire CL Now', style: TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.bold)),
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(color: Colors.red),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        
                        // Filters Container
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Container(
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: borderColor),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.02),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Department Filter
                                if (_departments.isNotEmpty) ...[
                                  DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    value: _departments.contains(_selectedDepartment) ? _selectedDepartment : 'All',
                                    decoration: InputDecoration(
                                      labelText: 'Department',
                                      prefixIcon: const Icon(Icons.business_rounded, size: 20),
                                      filled: true,
                                      fillColor: isDark ? const Color(0xFF141416) : Colors.grey.shade50,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(color: borderColor),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(color: borderColor),
                                      ),
                                    ),
                                    items: _departments.map((dept) {
                                      return DropdownMenuItem(
                                        value: dept,
                                        child: Text(dept, overflow: TextOverflow.ellipsis, maxLines: 1),
                                      );
                                    }).toList(),
                                    onChanged: _filterByDepartment,
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                
                                // Role Filter
                                DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  value: _roles.contains(_selectedRole) ? _selectedRole : 'All',
                                  decoration: InputDecoration(
                                    labelText: 'Role',
                                    prefixIcon: const Icon(Icons.badge_rounded, size: 20),
                                    filled: true,
                                    fillColor: isDark ? const Color(0xFF141416) : Colors.grey.shade50,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: borderColor),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: borderColor),
                                    ),
                                  ),
                                  items: _roles.map((role) {
                                    return DropdownMenuItem(
                                      value: role,
                                      child: Text(role, overflow: TextOverflow.ellipsis, maxLines: 1),
                                    );
                                  }).toList(),
                                  onChanged: _filterByRole,
                                ),
                                const SizedBox(height: 12),
                                
                                // User Filter
                                DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  value: _users.contains(_selectedUser) ? _selectedUser : 'All',
                                  decoration: InputDecoration(
                                    labelText: 'Staff Member',
                                    prefixIcon: const Icon(Icons.person_search_rounded, size: 20),
                                    filled: true,
                                    fillColor: isDark ? const Color(0xFF141416) : Colors.grey.shade50,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: borderColor),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: borderColor),
                                    ),
                                  ),
                                  items: _users.map((user) {
                                    return DropdownMenuItem(
                                      value: user,
                                      child: Text(user, overflow: TextOverflow.ellipsis),
                                    );
                                  }).toList(),
                                  onChanged: (value) => _filterByUser(value == 'All' ? null : value),
                                ),
                                const SizedBox(height: 8),
                                
                                // Clear Filters Button
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    icon: const Icon(Icons.clear_rounded, size: 16),
                                    label: const Text('Clear Filters'),
                                    onPressed: () {
                                      setState(() {
                                        _selectedDepartment = 'All';
                                        _selectedRole = 'All';
                                        _selectedUser = null;
                                        _updateRolesForDepartment(_selectedDepartment);
                                        _updateFilteredData();
                                      });
                                    },
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.indigo,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        
                        // Legend - hidden on small screens
                        if (!isSmallScreen)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _buildLegendItem('This Month', Colors.indigo, isDark),
                                _buildLegendItem('Accumulated', Colors.teal, isDark),
                                _buildLegendItem('Used', Colors.orange.shade700, isDark),
                              ],
                            ),
                          ),
                        const Divider(height: 1, thickness: 0.5),
                        const SizedBox(height: 8),
                        
                        // CL List
                        _filteredCLData.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(32.0),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.search_off_rounded, size: 48, color: Colors.grey.shade400),
                                      const SizedBox(height: 12),
                                      Text(
                                        'No staff records match the filters',
                                        style: TextStyle(color: Colors.grey.shade500),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                padding: EdgeInsets.zero,
                                itemCount: _filteredCLData.length,
                                itemBuilder: (context, index) {
                                  final staff = _filteredCLData[index];
                                  return _buildCLCard(staff, isSmallScreen, isNarrow);
                                },
                              ),
                      ],
                    );
                  },
                ),
    );
  }

  Widget _buildLegendItem(String label, Color color, bool isDark) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11, 
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white60 : Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildCLCard(dynamic staff, bool isSmallScreen, bool isNarrow) {
    final name = staff['name'] ?? '';
    final regNo = staff['reg_no'] ?? '';
    final dept = staff['dept'] ?? '';
    final role = staff['role'] ?? '';
    final int currentMonthCL = (staff['current_month_cl_available'] as num? ?? 0).toInt();
    final int accumulatedCL = (staff['accumulated_cl'] as num? ?? 0).toInt();
    final int clUsed = (staff['cl_used_current_month'] as num? ?? 0).toInt();
    final int totalAvailable = (staff['total_cl_available'] as num? ?? 0).toInt();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E1E22) : Colors.white;
    final borderColor = isDark ? Colors.white.withOpacity(0.08) : Colors.grey.shade200;

    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: isSmallScreen ? 8 : 16,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => _adjustCL(regNo, name, currentMonthCL, accumulatedCL, usedCL: clUsed),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.indigo.shade400, Colors.deepPurple.shade400],
                        ),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.indigo.shade900,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isNarrow ? '$regNo • $dept' : '$regNo • $dept • $role',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white54 : Colors.grey.shade600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: totalAvailable > 0 
                          ? Colors.green.withOpacity(0.12) 
                          : Colors.red.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: totalAvailable > 0 
                            ? Colors.green.withOpacity(0.3) 
                            : Colors.red.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: totalAvailable > 0 ? Colors.green : Colors.red,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '$totalAvailable CL',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: totalAvailable > 0 ? Colors.green.shade700 : Colors.red.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildCLIndicator(
                        'This Month',
                        currentMonthCL,
                        Colors.indigo,
                        isDark,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildCLIndicator(
                        'Accumulated',
                        accumulatedCL,
                        Colors.teal,
                        isDark,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildCLIndicator(
                        'Used',
                        clUsed,
                        Colors.orange.shade700,
                        isDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Tap to adjust CL balance',
                      style: TextStyle(
                        fontSize: 10,
                        color: isDark ? Colors.white30 : Colors.grey.shade400,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    Icon(
                      Icons.keyboard_arrow_right_rounded,
                      size: 14,
                      color: isDark ? Colors.white30 : Colors.grey.shade400,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCLIndicator(String label, int value, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.08 : 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.15 : 0.1),
        ),
      ),
      child: Column(
        children: [
          Text(
            value.toString(),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white60 : Colors.grey.shade700,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
