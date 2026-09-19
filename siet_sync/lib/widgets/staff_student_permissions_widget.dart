import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/college_ip_config.dart';

class StaffStudentPermissionsWidget extends StatefulWidget {
  final String staffRegNo;
  final String? staffDept;
  final String sessionToken;

  const StaffStudentPermissionsWidget({
    super.key,
    required this.staffRegNo,
    this.staffDept,
    required this.sessionToken,
  });

  @override
  State<StaffStudentPermissionsWidget> createState() =>
      _StaffStudentPermissionsWidgetState();
}

class _StaffStudentPermissionsWidgetState
    extends State<StaffStudentPermissionsWidget>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _isLoading = false;
  String? _errorMessage;

  List<dynamic> _myStudents = [];
  List<dynamic> _availableStaff = [];
  List<dynamic> _grantedPermissions = [];
  List<dynamic> _receivedPermissions = [];

  static const Color primaryColor = Color(0xFF1E3A8A);
  static const Color accentColor = Color(0xFF2563EB);

  String get _apiUrl => CollegeIPConfig.defaultURL;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${widget.sessionToken}',
      };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAllData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    int errorCount = 0;

    await Future.wait([
      _fetchMyStudents().catchError((_) {
        errorCount++;
      }),
      _fetchAvailableStaff().catchError((_) {}),
      _fetchGrantedPermissions().catchError((_) {
        errorCount++;
      }),
      _fetchReceivedPermissions().catchError((_) {
        errorCount++;
      }),
    ]);

    if (!mounted) return;

    setState(() {
      _isLoading = false;
      if (errorCount >= 3) {
        _errorMessage =
            "Unable to connect to permission server. Please check network.";
      }
    });
  }

  Future<void> _fetchMyStudents() async {
    final candidateEndpoints = [
      '$_apiUrl/staff/students/my-registered',
      '$_apiUrl/staff/students',
      '$_apiUrl/staff/registered-students',
    ];

    for (final endpoint in candidateEndpoints) {
      try {
        final response = await http
            .get(
              Uri.parse(endpoint),
              headers: _headers,
            )
            .timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          List rawStudents = [];
          if (data is List) {
            rawStudents = data;
          } else if (data is Map) {
            rawStudents = data['students'] ??
                data['registered_students'] ??
                data['my_students'] ??
                data['data'] ??
                [];
          }

          if (rawStudents.isNotEmpty && mounted) {
            setState(() {
              _myStudents = rawStudents;
            });
            break;
          }
        }
      } catch (_) {}
    }
  }

  Future<void> _fetchAvailableStaff() async {
    final candidateEndpoints = [
      '$_apiUrl/staff/list',
      '$_apiUrl/staff/all',
      '$_apiUrl/admin/attendance/staff-list',
      '$_apiUrl/hod/attendance/staff-list',
      '$_apiUrl/staff/users',
    ];

    for (final endpoint in candidateEndpoints) {
      try {
        final response = await http
            .get(
              Uri.parse(endpoint),
              headers: _headers,
            )
            .timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          List rawStaff = [];
          if (data is List) {
            rawStaff = data;
          } else if (data is Map) {
            rawStaff = data['staff'] ??
                data['staff_members'] ??
                data['staff_list'] ??
                data['users'] ??
                data['data'] ??
                data['faculty'] ??
                [];
          }

          if (rawStaff.isNotEmpty) {
            final seen = <String>{};
            final uniqueStaff = <dynamic>[];

            for (var item in rawStaff) {
              if (item is! Map) continue;
              final regNo = (item['reg_no'] ??
                      item['regNo'] ??
                      item['staff_reg_no'] ??
                      item['username'] ??
                      item['staff_id'] ??
                      item['id'] ??
                      '')
                  .toString()
                  .trim();

              final name = (item['name'] ??
                      item['full_name'] ??
                      item['username'] ??
                      item['staff_name'] ??
                      regNo)
                  .toString()
                  .trim();

              final dept = (item['dept'] ??
                      item['department'] ??
                      item['department_name'] ??
                      item['dept_name'] ??
                      '')
                  .toString()
                  .trim();

              final lowerReg = regNo.toLowerCase();
              if (regNo.isNotEmpty &&
                  lowerReg != widget.staffRegNo.trim().toLowerCase() &&
                  !seen.contains(lowerReg)) {
                seen.add(lowerReg);
                uniqueStaff.add({
                  'reg_no': regNo,
                  'name': name.isNotEmpty ? name : regNo.toUpperCase(),
                  'dept': dept.isNotEmpty ? dept.toUpperCase() : 'GENERAL',
                });
              }
            }

            if (uniqueStaff.isNotEmpty && mounted) {
              setState(() {
                _availableStaff = uniqueStaff;
              });
              break;
            }
          }
        }
      } catch (_) {}
    }
  }

  Future<void> _fetchGrantedPermissions() async {
    final candidateEndpoints = [
      '$_apiUrl/staff/permissions/granted-by-me',
      '$_apiUrl/staff/permissions/granted',
      '$_apiUrl/staff/permissions/my-granted',
    ];

    for (final endpoint in candidateEndpoints) {
      try {
        final response = await http
            .get(
              Uri.parse(endpoint),
              headers: _headers,
            )
            .timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          List rawPermissions = [];
          if (data is List) {
            rawPermissions = data;
          } else if (data is Map) {
            rawPermissions = data['granted_permissions'] ??
                data['permissions'] ??
                data['granted'] ??
                data['data'] ??
                [];
          }

          if (rawPermissions.isNotEmpty && mounted) {
            setState(() {
              _grantedPermissions = rawPermissions;
            });
            break;
          }
        }
      } catch (_) {}
    }
  }

  Future<void> _fetchReceivedPermissions() async {
    final candidateEndpoints = [
      '$_apiUrl/staff/permissions/granted-to-me',
      '$_apiUrl/staff/permissions/received',
      '$_apiUrl/staff/permissions/my-received',
    ];

    for (final endpoint in candidateEndpoints) {
      try {
        final response = await http
            .get(
              Uri.parse(endpoint),
              headers: _headers,
            )
            .timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          List rawPermissions = [];
          if (data is List) {
            rawPermissions = data;
          } else if (data is Map) {
            rawPermissions = data['received_permissions'] ??
                data['permissions'] ??
                data['received'] ??
                data['data'] ??
                [];
          }

          if (rawPermissions.isNotEmpty && mounted) {
            setState(() {
              _receivedPermissions = rawPermissions;
            });
            break;
          }
        }
      } catch (_) {}
    }
  }

  Future<void> _revokePermission(int permissionId) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_apiUrl/staff/permissions/revoke/$permissionId'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Permission revoked successfully"),
            backgroundColor: Colors.green,
          ),
        );
        _loadAllData();
      } else {
        final err = json.decode(response.body);
        throw Exception(err['detail'] ?? "Revoke failed");
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _grantPermission({
    required String granteeStaffRegNo,
    String? studentRegNo,
    int? durationDays,
  }) async {
    try {
      final body = {
        "grantee_staff_reg_no": granteeStaffRegNo,
        "student_reg_no": studentRegNo,
        "duration_days": durationDays,
      };

      final response = await http
          .post(
            Uri.parse('$_apiUrl/staff/permissions/grant'),
            headers: _headers,
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Permission delegated successfully!"),
            backgroundColor: Colors.green,
          ),
        );
        _loadAllData();
      } else {
        final err = json.decode(response.body);
        throw Exception(err['detail'] ?? "Failed to grant permission");
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showGrantPermissionDialog() {
    String? selectedGranteeRegNo;
    String? selectedStudentRegNo;
    int? selectedDurationDays;
    String? selectedDeptFilter;
    bool isFetchingStaffInDialog = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            if (_availableStaff.isEmpty && !isFetchingStaffInDialog) {
              isFetchingStaffInDialog = true;
              _fetchAvailableStaff().then((_) {
                if (context.mounted) {
                  setDialogState(() {
                    isFetchingStaffInDialog = false;
                  });
                }
              });
            }

            // Extract unique department names dynamically from _availableStaff
            final deptsSet = <String>{"ALL"};
            for (var staff in _availableStaff) {
              final d = (staff['dept'] ?? staff['department'] ?? '')
                  .toString()
                  .trim()
                  .toUpperCase();
              if (d.isNotEmpty) deptsSet.add(d);
            }
            final deptList = deptsSet.toList();

            // Filter available staff based on selected department filter
            final filteredStaff = _availableStaff.where((staff) {
              if (selectedDeptFilter == null || selectedDeptFilter == "ALL") return true;
              final d = (staff['dept'] ?? staff['department'] ?? '')
                  .toString()
                  .trim()
                  .toUpperCase();
              return d == selectedDeptFilter;
            }).toList();

            // Sort filtered staff: same department first, then alphabetically
            filteredStaff.sort((a, b) {
              final dA = (a['dept'] ?? a['department'] ?? '').toString().trim().toUpperCase();
              final dB = (b['dept'] ?? b['department'] ?? '').toString().trim().toUpperCase();
              final myDept = (widget.staffDept ?? '').trim().toUpperCase();

              final aIsMine = myDept.isNotEmpty && dA == myDept;
              final bIsMine = myDept.isNotEmpty && dB == myDept;

              if (aIsMine && !bIsMine) return -1;
              if (!aIsMine && bIsMine) return 1;
              return (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString());
            });

            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.shield_outlined, color: accentColor),
                  SizedBox(width: 10),
                  Text("Delegate Access",
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Department Filter Dropdown
                    const Text(
                      "Filter Staff by Department:",
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String?>(
                      isExpanded: true,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        filled: true,
                        fillColor: Colors.blue.shade50.withValues(alpha: 0.5),
                      ),
                      hint: const Text("Select Department"),
                      initialValue: selectedDeptFilter,
                      items: deptList.map<DropdownMenuItem<String?>>((dept) {
                        final myDept = (widget.staffDept ?? '').trim().toUpperCase();
                        final isMyDept = myDept.isNotEmpty && dept == myDept;
                        return DropdownMenuItem<String?>(
                          value: dept,
                          child: Text(
                            dept == "ALL"
                                ? (isFetchingStaffInDialog
                                    ? "Loading staff..."
                                    : "All Departments (${_availableStaff.length} Staff)")
                                : isMyDept
                                    ? "★ My Department ($dept)"
                                    : "Department: $dept",
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isMyDept ? FontWeight.bold : FontWeight.normal,
                              color: isMyDept ? primaryColor : Colors.black87,
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setDialogState(() {
                          selectedDeptFilter = val;
                          if (selectedGranteeRegNo != null) {
                            final exists = filteredStaff.any((s) =>
                                (s['reg_no'] ?? '').toString() == selectedGranteeRegNo);
                            if (!exists) selectedGranteeRegNo = null;
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 14),

                    // Target Staff Member Dropdown
                    const Text(
                      "Target Staff Member:",
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                      hint: Text(isFetchingStaffInDialog
                          ? "Loading staff members..."
                          : (filteredStaff.isEmpty
                              ? "No staff found in $selectedDeptFilter"
                              : "Select Staff Member")),
                      initialValue: selectedGranteeRegNo,
                      items: filteredStaff
                          .map<DropdownMenuItem<String>>((staff) {
                        final reg = (staff['reg_no'] ?? '').toString();
                        final name = (staff['name'] ?? reg).toString();
                        final dept = (staff['dept'] ?? staff['department'] ?? 'Other').toString();
                        final myDept = (widget.staffDept ?? '').trim().toLowerCase();
                        final isSameDept = myDept.isNotEmpty &&
                            dept.trim().toLowerCase() == myDept;

                        return DropdownMenuItem<String>(
                          value: reg,
                          child: Text(
                            "${isSameDept ? '★ [My Dept]' : '[$dept]'} $name ($reg)",
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isSameDept ? FontWeight.bold : FontWeight.normal,
                              color: isSameDept ? primaryColor : Colors.black87,
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setDialogState(() {
                          selectedGranteeRegNo = val;
                        });
                      },
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      "Student Access Scope:",
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String?>(
                      isExpanded: true,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                      initialValue: selectedStudentRegNo,
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text("ALL Registered Students",
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: accentColor)),
                        ),
                        ..._myStudents.map<DropdownMenuItem<String?>>((stu) {
                          final reg = (stu['reg_no'] ?? stu['regNo'] ?? '').toString();
                          final name = (stu['name'] ?? reg).toString();
                          return DropdownMenuItem<String?>(
                            value: reg,
                            child: Text("$name ($reg)",
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13)),
                          );
                        }),
                      ],
                      onChanged: (val) {
                        setDialogState(() {
                          selectedStudentRegNo = val;
                        });
                      },
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      "Access Duration:",
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<int?>(
                      isExpanded: true,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                      initialValue: selectedDurationDays,
                      items: const [
                        DropdownMenuItem<int?>(
                          value: null,
                          child: Text("Permanent (Until Revoked)"),
                        ),
                        DropdownMenuItem<int?>(
                          value: 1,
                          child: Text("1 Day"),
                        ),
                        DropdownMenuItem<int?>(
                          value: 7,
                          child: Text("7 Days"),
                        ),
                        DropdownMenuItem<int?>(
                          value: 30,
                          child: Text("30 Days"),
                        ),
                      ],
                      onChanged: (val) {
                        setDialogState(() {
                          selectedDurationDays = val;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text("Grant Access"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: selectedGranteeRegNo == null
                      ? null
                      : () {
                          Navigator.pop(context);
                          _grantPermission(
                            granteeStaffRegNo: selectedGranteeRegNo!,
                            studentRegNo: selectedStudentRegNo,
                            durationDays: selectedDurationDays,
                          );
                        },
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeCount =
        _grantedPermissions.where((p) => p['status'] == 'ACTIVE').length;

    return Material(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Action Banner Card
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade900, primaryColor],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.shade900.withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.shield_outlined,
                          color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Student Access Delegation",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "${_myStudents.length} Students Owned  •  $activeCount Active Delegations",
                            style: TextStyle(
                              color: Colors.blue.shade100,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add_moderator, size: 18),
                    label: const Text(
                      "Delegate Access",
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: primaryColor,
                      elevation: 1,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _showGrantPermissionDialog,
                  ),
                ),
              ],
            ),
          ),

          // Tab Bar Navigation (100% Mobile Responsive)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            height: 44,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: primaryColor,
                borderRadius: BorderRadius.circular(10),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.grey.shade700,
              labelPadding: const EdgeInsets.symmetric(horizontal: 4),
              labelStyle:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              unselectedLabelStyle:
                  const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
              tabs: [
                Tab(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text("My Students (${_myStudents.length})"),
                  ),
                ),
                Tab(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text("Granted (${_grantedPermissions.length})"),
                  ),
                ),
                Tab(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text("Received (${_receivedPermissions.length})"),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Main Content View inside Expanded
          Expanded(
            child: _isLoading
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: primaryColor),
                        SizedBox(height: 12),
                        Text("Loading permission records...",
                            style:
                                TextStyle(color: Colors.grey, fontSize: 13)),
                      ],
                    ),
                  )
                : _errorMessage != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.cloud_off,
                                  size: 48, color: Colors.grey),
                              const SizedBox(height: 12),
                              Text(
                                _errorMessage!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: Colors.grey, fontSize: 14),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.refresh),
                                label: const Text("Retry"),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryColor,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: _loadAllData,
                              ),
                            ],
                          ),
                        ),
                      )
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildMyStudentsList(),
                          _buildGrantedPermissionsList(),
                          _buildReceivedPermissionsList(),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyStudentsList() {
    if (_myStudents.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadAllData,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 80),
            Center(
              child: Column(
                children: [
                  Icon(Icons.school_outlined, size: 48, color: Colors.grey),
                  SizedBox(height: 10),
                  Text(
                    "No students registered under your staff profile.",
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadAllData,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: _myStudents.length,
        itemBuilder: (context, index) {
          final stu = _myStudents[index];
          final name = (stu['name'] ?? 'Student').toString();
          final regNo = (stu['reg_no'] ?? stu['regNo'] ?? '-').toString();
          final dept = (stu['dept'] ?? stu['department'] ?? '-').toString();
          final year = (stu['year'] ?? '').toString();

          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 1.5,
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              leading: CircleAvatar(
                backgroundColor: Colors.blue.shade100,
                child: Text(
                  name.isNotEmpty ? name.substring(0, 1).toUpperCase() : 'S',
                  style: TextStyle(
                    color: Colors.blue.shade900,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(name,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
              subtitle: Text(
                  "Reg No: $regNo • Dept: $dept ${year.isNotEmpty ? '• Year $year' : ''}"),
              trailing: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: const Text(
                  "Owner",
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.green),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGrantedPermissionsList() {
    if (_grantedPermissions.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadAllData,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 80),
            Center(
              child: Column(
                children: [
                  Icon(Icons.assignment_ind_outlined,
                      size: 48, color: Colors.grey),
                  SizedBox(height: 10),
                  Text(
                    "You haven't delegated permission to any other staff yet.",
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadAllData,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: _grantedPermissions.length,
        itemBuilder: (context, index) {
          final perm = _grantedPermissions[index];
          final isActive = perm['status'] == 'ACTIVE';
          final granteeName = (perm['grantee_name'] ??
                  perm['grantee_staff_reg_no'] ??
                  'Staff')
              .toString();
          final granteeRegNo =
              (perm['grantee_staff_reg_no'] ?? '-').toString();
          final studentName =
              (perm['student_name'] ?? 'ALL STUDENTS').toString();
          final validUntil = (perm['valid_until'] ?? 'Permanent').toString();

          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 1.5,
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              leading: CircleAvatar(
                backgroundColor:
                    isActive ? Colors.green.shade50 : Colors.grey.shade200,
                child: Icon(
                  isActive ? Icons.lock_open : Icons.lock_clock,
                  color:
                      isActive ? Colors.green.shade700 : Colors.grey.shade600,
                ),
              ),
              title: Text(
                "Granted To: $granteeName ($granteeRegNo)",
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Scope: $studentName",
                        style: const TextStyle(fontSize: 12)),
                    Text("Expires: $validUntil",
                        style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              trailing: isActive
                  ? OutlinedButton.icon(
                      icon: const Icon(Icons.cancel_outlined,
                          color: Colors.red, size: 16),
                      label: const Text("Revoke",
                          style: TextStyle(color: Colors.red, fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => _revokePermission(perm['id']),
                    )
                  : Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        "Revoked",
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildReceivedPermissionsList() {
    if (_receivedPermissions.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadAllData,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 80),
            Center(
              child: Column(
                children: [
                  Icon(Icons.vpn_key_outlined, size: 48, color: Colors.grey),
                  SizedBox(height: 10),
                  Text(
                    "No access permissions received from other staff.",
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadAllData,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: _receivedPermissions.length,
        itemBuilder: (context, index) {
          final perm = _receivedPermissions[index];
          final grantorName = (perm['grantor_name'] ??
                  perm['grantor_staff_reg_no'] ??
                  'Staff')
              .toString();
          final grantorRegNo =
              (perm['grantor_staff_reg_no'] ?? '-').toString();
          final studentName =
              (perm['student_name'] ?? 'ALL STUDENTS').toString();
          final validUntil = (perm['valid_until'] ?? 'Permanent').toString();

          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 1.5,
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              leading: CircleAvatar(
                backgroundColor: Colors.purple.shade50,
                child: Icon(Icons.vpn_key, color: Colors.purple.shade700),
              ),
              title: Text(
                "Granted By: $grantorName ($grantorRegNo)",
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Scope: $studentName",
                        style: const TextStyle(fontSize: 12)),
                    Text("Valid Until: $validUntil",
                        style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              trailing: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.purple.shade200),
                ),
                child: Text(
                  "Active Access",
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.purple.shade800),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}