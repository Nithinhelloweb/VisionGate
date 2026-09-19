import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/features_service.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';

class SystemReportsPage extends StatefulWidget {
  final String token;
  final Map<String, dynamic> user;

  const SystemReportsPage({
    super.key,
    required this.token,
    required this.user,
  });

  @override
  State<SystemReportsPage> createState() => _SystemReportsPageState();
}

class _SystemReportsPageState extends State<SystemReportsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = false;

  String _selectedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
  String _selectedMonth = DateFormat('yyyy-MM').format(DateTime.now());
  String _selectedDept = '';

  Map<String, dynamic>? _dailyRegisterData;
  Map<String, dynamic>? _monthlySummaryData;
  Map<String, dynamic>? _heatmapData;
  Map<String, dynamic>? _leaveUtilData;
  Map<String, dynamic>? _absenteeismData;
  List<Map<String, dynamic>> _faceFailures = [];

  final List<String> _departments = [
    'All Departments',
    'CSE',
    'ECE',
    'EEE',
    'MECH',
    'CIVIL',
    'IT',
    'AI&DS',
    'S&H',
    'Admin',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _loadCurrentTab();
      }
    });
    _loadCurrentTab();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String get _deptParam => _selectedDept == 'All Departments' || _selectedDept.isEmpty ? '' : _selectedDept;

  Future<void> _loadCurrentTab() async {
    setState(() => _isLoading = true);
    try {
      switch (_tabController.index) {
        case 0:
          final res = await FeaturesService.getDailyRegisterReport(widget.token, date: _selectedDate, dept: _deptParam);
          if (mounted) setState(() => _dailyRegisterData = res);
          break;
        case 1:
          final res = await FeaturesService.getMonthlySummaryReport(widget.token, month: _selectedMonth, dept: _deptParam);
          if (mounted) setState(() => _monthlySummaryData = res);
          break;
        case 2:
          final res = await FeaturesService.getDepartmentHeatmap(widget.token, month: _selectedMonth);
          if (mounted) setState(() => _heatmapData = res);
          break;
        case 3:
          final res = await FeaturesService.getLeaveUtilisationReport(widget.token, dept: _deptParam);
          if (mounted) setState(() => _leaveUtilData = res);
          break;
        case 4:
          final res = await FeaturesService.getAbsenteeismTrend(widget.token, days: 14, dept: _deptParam);
          if (mounted) setState(() => _absenteeismData = res);
          break;
        case 5:
          final res = await FeaturesService.getFaceRecognitionFailures(widget.token);
          if (mounted) setState(() => _faceFailures = res);
          break;
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  void _triggerExport(String format) async {
    String endpoint = '/reports/daily-register';
    Map<String, String> params = {};

    switch (_tabController.index) {
      case 0:
        endpoint = '/reports/daily-register';
        params = {'date_str': _selectedDate, if (_deptParam.isNotEmpty) 'dept': _deptParam};
        break;
      case 1:
        endpoint = '/reports/monthly-summary';
        params = {'month': _selectedMonth, if (_deptParam.isNotEmpty) 'dept': _deptParam};
        break;
      case 2:
        endpoint = '/reports/department-heatmap';
        params = {'month': _selectedMonth};
        break;
      case 3:
        endpoint = '/reports/leave-utilisation';
        params = {if (_deptParam.isNotEmpty) 'dept': _deptParam};
        break;
      case 4:
        endpoint = '/reports/absenteeism-trend';
        params = {'days': '14', if (_deptParam.isNotEmpty) 'dept': _deptParam};
        break;
      case 5:
        endpoint = '/reports/face-recognition-failures';
        params = {'limit': '100'};
        break;
    }

    final downloadUrl = FeaturesService.getReportExportUrl(endpoint, format: format, params: params);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Downloading $format report…')),
    );

    try {
      final res = await http.get(Uri.parse(downloadUrl), headers: {'Authorization': 'Bearer ${widget.token}'});
      if (!mounted) return;
      if (res.statusCode == 200) {
        if (format == 'pdf') {
          await Printing.layoutPdf(onLayout: (format) async => res.bodyBytes);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$format export downloaded successfully (${res.bodyBytes.length} bytes).')),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Export failed. Please check server connection.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download error: $e')),
        );
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Institutional Reports & Analytics', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.download_rounded),
            tooltip: 'Export Current Report',
            onSelected: _triggerExport,
            itemBuilder: (ctx) => const [
              PopupMenuItem(value: 'excel', child: Row(children: [Icon(Icons.table_chart_rounded, color: Colors.green, size: 20), SizedBox(width: 8), Text('Export to Excel (.xlsx)')])),
              PopupMenuItem(value: 'pdf', child: Row(children: [Icon(Icons.picture_as_pdf_rounded, color: Colors.red, size: 20), SizedBox(width: 8), Text('Export to PDF (.pdf)')])),
              PopupMenuItem(value: 'csv', child: Row(children: [Icon(Icons.receipt_long_rounded, color: Colors.blue, size: 20), SizedBox(width: 8), Text('Export to CSV (.csv)')])),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _loadCurrentTab,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Daily Register', icon: Icon(Icons.list_alt_rounded)),
            Tab(text: 'Monthly Summary', icon: Icon(Icons.calendar_month_rounded)),
            Tab(text: 'Dept Heatmap', icon: Icon(Icons.grid_view_rounded)),
            Tab(text: 'Leave Utilisation', icon: Icon(Icons.pie_chart_rounded)),
            Tab(text: 'Absenteeism Trend', icon: Icon(Icons.trending_down_rounded)),
            Tab(text: 'Biometric Anomalies', icon: Icon(Icons.security_update_warning_rounded)),
          ],
        ),
      ),
      body: Column(
        children: [
          // Filter Bar
          _buildFilterBar(),
          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildDailyRegisterView(),
                      _buildMonthlySummaryView(),
                      _buildHeatmapView(),
                      _buildLeaveUtilView(),
                      _buildAbsenteeismView(),
                      _buildFaceFailuresView(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          // Date / Month picker button
          Expanded(
            flex: 5,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today_rounded, size: 14),
              label: Text(
                _tabController.index == 1 || _tabController.index == 2 ? 'Month: $_selectedMonth' : 'Date: $_selectedDate',
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
              onPressed: () async {
                if (_tabController.index == 1 || _tabController.index == 2) {
                  // Month picker
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2024),
                    lastDate: DateTime(2028),
                  );
                  if (picked != null) {
                    setState(() => _selectedMonth = DateFormat('yyyy-MM').format(picked));
                    _loadCurrentTab();
                  }
                } else {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2024),
                    lastDate: DateTime(2028),
                  );
                  if (picked != null) {
                    setState(() => _selectedDate = DateFormat('yyyy-MM-dd').format(picked));
                    _loadCurrentTab();
                  }
                }
              },
            ),
          ),
          const SizedBox(width: 8),
          // Department filter dropdown
          Expanded(
            flex: 5,
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _selectedDept.isEmpty ? 'All Departments' : _selectedDept,
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                isDense: true,
              ),
              items: _departments
                  .map((d) => DropdownMenuItem(
                        value: d,
                        child: Text(
                          d,
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ))
                  .toList(),
              onChanged: (v) {
                setState(() => _selectedDept = v ?? 'All Departments');
                _loadCurrentTab();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyRegisterView() {
    final records = _dailyRegisterData?['records'] as List<dynamic>? ?? [];
    if (records.isEmpty) return const Center(child: Text('No attendance records found for this date.'));

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
          columns: const [
            DataColumn(label: Text('Reg No', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Name', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Dept', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Check In', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Check Out', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Override', style: TextStyle(fontWeight: FontWeight.bold))),
          ],
          rows: records.map<DataRow>((r) {
            String regNo = '';
            String name = '';
            String dept = '';
            String status = 'Absent';
            String checkIn = '—';
            String checkOut = '—';
            bool isManual = false;

            if (r is Map) {
              regNo = r['reg_no']?.toString() ?? '';
              name = r['name']?.toString() ?? '';
              dept = r['dept']?.toString() ?? '';
              status = r['status']?.toString() ?? 'Absent';
              checkIn = r['check_in']?.toString() ?? '—';
              checkOut = r['check_out']?.toString() ?? '—';
              isManual = r['is_manual'] == true || r['is_manual_override'] == true;
            } else if (r is List) {
              if (r.isNotEmpty) regNo = r[0]?.toString() ?? '';
              if (r.length > 1) name = r[1]?.toString() ?? '';
              if (r.length > 2) dept = r[2]?.toString() ?? '';
              if (r.length > 4) status = r[4]?.toString() ?? 'Absent';
              if (r.length > 5) checkIn = r[5]?.toString() ?? '—';
              if (r.length > 6) checkOut = r[6]?.toString() ?? '—';
              if (r.length > 7) isManual = r[7] == true || r[7] == 1;
            }

            return DataRow(cells: [
              DataCell(Text(regNo)),
              DataCell(Text(name)),
              DataCell(Text(dept)),
              DataCell(
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: status == 'Present' ? Colors.green.shade50 : (status == 'Half Day' ? Colors.amber.shade50 : Colors.red.shade50),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      color: status == 'Present' ? Colors.green.shade800 : (status == 'Half Day' ? Colors.amber.shade900 : Colors.red.shade800),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              DataCell(Text(checkIn)),
              DataCell(Text(checkOut)),
              DataCell(Text(isManual ? 'Manual Override' : 'Biometric', style: TextStyle(color: isManual ? Colors.orange.shade800 : Colors.grey))),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildMonthlySummaryView() {
    final records = _monthlySummaryData?['records'] as List<dynamic>? ?? [];
    if (records.isEmpty) return const Center(child: Text('No monthly attendance data recorded.'));

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: records.length,
      itemBuilder: (ctx, i) {
        final item = records[i];
        String name = '';
        String dept = '';
        String regNo = '';
        int presentDays = 0;
        int workingDays = 0;
        int leaveDays = 0;
        double pct = 0.0;

        if (item is Map) {
          name = item['name']?.toString() ?? '';
          dept = item['dept']?.toString() ?? '';
          regNo = item['reg_no']?.toString() ?? '';
          presentDays = int.tryParse(item['present_days']?.toString() ?? '0') ?? 0;
          workingDays = int.tryParse(item['working_days']?.toString() ?? '0') ?? 0;
          leaveDays = int.tryParse(item['leave_days']?.toString() ?? '0') ?? 0;
          pct = (item['attendance_pct'] as num?)?.toDouble() ??
              double.tryParse(item['attendance_pct']?.toString().replaceAll('%', '') ?? '0') ?? 0.0;
        } else if (item is List) {
          if (item.isNotEmpty) regNo = item[0]?.toString() ?? '';
          if (item.length > 1) name = item[1]?.toString() ?? '';
          if (item.length > 2) dept = item[2]?.toString() ?? '';
          if (item.length > 3) presentDays = int.tryParse(item[3]?.toString() ?? '0') ?? 0;
          if (item.length > 5) leaveDays = int.tryParse(item[5]?.toString() ?? '0') ?? 0;
          if (item.length > 6) {
            final p = int.tryParse(item[3]?.toString() ?? '0') ?? 0;
            final hd = int.tryParse(item[4]?.toString() ?? '0') ?? 0;
            final lv = int.tryParse(item[5]?.toString() ?? '0') ?? 0;
            final ab = int.tryParse(item[6]?.toString() ?? '0') ?? 0;
            workingDays = p + hd + lv + ab;
          }
          if (item.length > 7) {
            final rawPct = item[7]?.toString().replaceAll('%', '') ?? '0';
            pct = double.tryParse(rawPct) ?? 0.0;
          }
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15), overflow: TextOverflow.ellipsis),
                      Text('$dept • $regNo', style: const TextStyle(fontSize: 12, color: Colors.grey), overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: Column(
                    children: [
                      Text('$presentDays/$workingDays Days', style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                      Text('Leaves: $leaveDays', style: const TextStyle(fontSize: 12, color: Colors.grey), overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: pct >= 85 ? Colors.green.shade50 : (pct >= 75 ? Colors.amber.shade50 : Colors.red.shade50),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${pct.toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: pct >= 85 ? Colors.green.shade800 : (pct >= 75 ? Colors.amber.shade900 : Colors.red.shade800),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeatmapView() {
    Map<String, dynamic> grid = {};
    int daysInMonth = _heatmapData?['days_in_month'] as int? ?? 31;

    if (_heatmapData?['grid'] is Map) {
      grid = Map<String, dynamic>.from(_heatmapData!['grid'] as Map);
    } else if (_heatmapData?['data'] is List) {
      final dataList = _heatmapData!['data'] as List;
      final deptTotals = <String, Map<String, List<double>>>{};
      for (final item in dataList) {
        if (item is Map) {
          final dept = item['dept']?.toString() ?? 'General';
          final dateStr = item['date']?.toString() ?? '';
          final dayNum = dateStr.split('-').last.replaceFirst(RegExp(r'^0'), '');
          final status = item['status']?.toString() ?? '';
          deptTotals.putIfAbsent(dept, () => {});
          deptTotals[dept]!.putIfAbsent(dayNum, () => [0.0, 0.0]);
          deptTotals[dept]![dayNum]![1] += 1;
          if (status == 'Present') deptTotals[dept]![dayNum]![0] += 1;
          if (status == 'Half Day') deptTotals[dept]![dayNum]![0] += 0.5;
        }
      }
      for (final entry in deptTotals.entries) {
        grid[entry.key] = {};
        for (final dayEntry in entry.value.entries) {
          final tot = dayEntry.value[1];
          final pres = dayEntry.value[0];
          grid[entry.key][dayEntry.key] = tot > 0 ? ((pres / tot) * 100) : 0.0;
        }
      }
    }

    if (grid.isEmpty) return const Center(child: Text('Heatmap data unavailable for this month.'));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: grid.entries.map((entry) {
          final dept = entry.key;
          final daysMap = entry.value is Map ? (entry.value as Map) : <dynamic, dynamic>{};

          return Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dept, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: List.generate(daysInMonth, (dIdx) {
                    final dayNum = dIdx + 1;
                    final rawVal = daysMap[dayNum.toString()] ?? daysMap[dayNum];
                    final pct = (rawVal as num?)?.toDouble() ?? double.tryParse(rawVal?.toString() ?? '0') ?? 0.0;
                    Color cellColor;
                    if (pct >= 90) {
                      cellColor = Colors.green.shade600;
                    } else if (pct >= 75) {
                      cellColor = Colors.green.shade300;
                    } else if (pct >= 50) {
                      cellColor = Colors.amber.shade400;
                    } else if (pct > 0) {
                      cellColor = Colors.red.shade300;
                    } else {
                      cellColor = Colors.grey.shade200;
                    }

                    return Tooltip(
                      message: 'Day $dayNum: ${pct.toStringAsFixed(1)}%',
                      child: Container(
                        width: 26,
                        height: 26,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: cellColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '$dayNum',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: cellColor == Colors.grey.shade200 ? Colors.black54 : Colors.white,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildLeaveUtilView() {
    final records = _leaveUtilData?['records'] as List<dynamic>? ?? [];
    if (records.isEmpty) return const Center(child: Text('No leave utilisation records found.'));

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: records.length,
      itemBuilder: (ctx, i) {
        final item = records[i];
        String name = '';
        String dept = '';
        int clUsed = 0;
        int clBal = 12;
        int elUsed = 0;
        int elBal = 15;
        int cclUsed = 0;
        int cclBal = 5;

        if (item is Map) {
          name = item['name']?.toString() ?? '';
          dept = item['dept']?.toString() ?? '';
          clUsed = int.tryParse(item['cl_used']?.toString() ?? '0') ?? 0;
          clBal = int.tryParse(item['cl_balance']?.toString() ?? '12') ?? 12;
          elUsed = int.tryParse(item['el_used']?.toString() ?? '0') ?? 0;
          elBal = int.tryParse(item['el_balance']?.toString() ?? '15') ?? 15;
          cclUsed = int.tryParse(item['ccl_used']?.toString() ?? '0') ?? 0;
          cclBal = int.tryParse(item['ccl_balance']?.toString() ?? '5') ?? 5;
        } else if (item is List) {
          if (item.length > 1) name = item[1]?.toString() ?? '';
          if (item.length > 2) dept = item[2]?.toString() ?? '';
          if (item.length > 3) clBal = int.tryParse(item[3]?.toString() ?? '12') ?? 12;
          if (item.length > 4) clUsed = int.tryParse(item[4]?.toString() ?? '0') ?? 0;
          if (item.length > 5) elBal = int.tryParse(item[5]?.toString() ?? '15') ?? 15;
          if (item.length > 6) elUsed = int.tryParse(item[6]?.toString() ?? '0') ?? 0;
          if (item.length > 7) cclBal = int.tryParse(item[7]?.toString() ?? '5') ?? 5;
          if (item.length > 8) cclUsed = int.tryParse(item[8]?.toString() ?? '0') ?? 0;
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(dept, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
                const Divider(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildLeaveStat('Casual Leave (CL)', '$clUsed/12', '$clBal Rem'),
                    _buildLeaveStat('Earned Leave (EL)', '$elUsed/15', '$elBal Rem'),
                    _buildLeaveStat('Comp Off (CCL)', '$cclUsed/5', '$cclBal Rem'),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLeaveStat(String label, String used, String bal) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(used, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        Text(bal, style: TextStyle(fontSize: 11, color: Colors.blue.shade700)),
      ],
    );
  }

  Widget _buildAbsenteeismView() {
    final trend = _absenteeismData?['trend'] as List<dynamic>? ?? [];
    if (trend.isEmpty) return const Center(child: Text('No absenteeism trend data found.'));

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: trend.length,
      itemBuilder: (ctx, i) {
        final r = trend[i];
        String dateStr = '';
        int count = 0;

        if (r is Map) {
          dateStr = r['date']?.toString() ?? '';
          count = int.tryParse((r['absent_count'] ?? r['absent'])?.toString() ?? '0') ?? 0;
        } else if (r is List) {
          if (r.isNotEmpty) dateStr = r[0]?.toString() ?? '';
          if (r.length > 4) count = int.tryParse(r[4]?.toString() ?? '0') ?? 0;
        }

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: count > 5 ? Colors.red.shade100 : Colors.blue.shade100,
            child: Text('$count', style: TextStyle(fontWeight: FontWeight.bold, color: count > 5 ? Colors.red.shade800 : Colors.blue.shade800)),
          ),
          title: Text('Date: $dateStr'),
          subtitle: Text('Total Absent: $count staff members'),
        );
      },
    );
  }

  Widget _buildFaceFailuresView() {
    if (_faceFailures.isEmpty) {
      return const Center(child: Text('Zero face recognition anomaly failures recorded.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _faceFailures.length,
      itemBuilder: (ctx, i) {
        final r = _faceFailures[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
            title: Text('Reg: ${r['reg_no'] ?? 'Unknown'} • Confidence: ${r['confidence_score'] ?? '—'}'),
            subtitle: Text('Reason: ${r['failure_reason'] ?? 'Low threshold'} • ${r['timestamp'] ?? ''}'),
          ),
        );
      },
    );
  }
}
