import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../config/college_ip_config.dart';
import '../utils/file_saver.dart';

/// Unified Student Attendance Log, Day & Period Matrix (Periods 1 to 8), and Report Suite
/// Applicable across Staff Panel, HOD Panel, and Admin Panel.
class StudentAttendanceLogWidget extends StatefulWidget {
  final Map<String, dynamic> user;
  final String token;
  final bool isHod;
  final bool isAdmin;
  final String? defaultDept;

  const StudentAttendanceLogWidget({
    super.key,
    required this.user,
    required this.token,
    this.isHod = false,
    this.isAdmin = false,
    this.defaultDept,
  });

  @override
  State<StudentAttendanceLogWidget> createState() =>
      _StudentAttendanceLogWidgetState();
}

class _StudentAttendanceLogWidgetState
    extends State<StudentAttendanceLogWidget> {
  // Locked Design Tokens
  static const Color brandBlue = Color(0xFF1E3A8A);
  static const Color accentBlue = Color(0xFF3B82F6);
  static const Color primaryNavy = Color(0xFF0F172A);
  static const Color emeraldSuccess = Color(0xFF059669);
  static const Color amberWarning = Color(0xFFD97706);
  static const Color roseDanger = Color(0xFFDC2626);
  static const Color purpleAccent = Color(0xFF7C3AED);
  static const Color slateBg = Color(0xFFF8FAFC);
  static const Color cardBorder = Color(0xFFE2E8F0);

  // Date Filters
  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _endDate = DateTime.now();

  // Multi-Level Filter State
  String _selectedDept = "ALL";
  String _selectedPeriod = "ALL";
  String _selectedStatus = "ALL";
  String _selectedDegree = "ALL";
  String _selectedYear = "ALL";
  String _selectedSemester = "ALL";
  String _selectedSection = "ALL";
  String _selectedBatch = "ALL";
  String _selectedMethod = "ALL";
  String _searchQuery = "";
  final TextEditingController _searchController = TextEditingController();

  bool _isAdvancedFiltersOpen = false;
  String _viewMode = "matrix"; // "matrix", "table", or "cards"
  String _sortColumn = "date";
  bool _sortAscending = false;

  List<dynamic> _logs = [];
  List<dynamic> _matrix = [];
  Map<String, dynamic> _summary = {};
  Map<String, dynamic> _periodStats = {};
  List<String> _departments = ["ALL"];
  List<int> _availablePeriods = [1, 2, 3, 4, 5, 6, 7, 8];

  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? _academicSettings;

  int get _activeFiltersCount {
    int count = 0;
    if (_selectedDept != "ALL" && !widget.isHod) count++;
    if (_selectedPeriod != "ALL") count++;
    if (_selectedStatus != "ALL") count++;
    if (_selectedDegree != "ALL") count++;
    if (_selectedYear != "ALL") count++;
    if (_selectedSemester != "ALL") count++;
    if (_selectedSection != "ALL") count++;
    if (_selectedBatch != "ALL") count++;
    if (_selectedMethod != "ALL") count++;
    if (_searchQuery.isNotEmpty) count++;
    return count;
  }

  void _resetAllFilters() {
    setState(() {
      if (!widget.isHod) {
        _selectedDept = "ALL";
      }
      _selectedPeriod = "ALL";
      _selectedStatus = "ALL";
      _selectedDegree = "ALL";
      _selectedYear = "ALL";
      _selectedSemester = "ALL";
      _selectedSection = "ALL";
      _selectedBatch = "ALL";
      _selectedMethod = "ALL";
      _searchQuery = "";
      _searchController.clear();
      _startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
      _endDate = DateTime.now();
    });
    _fetchLogs();
  }

  @override
  void initState() {
    super.initState();
    final initialDept = (widget.defaultDept ??
            widget.user['dept'] ??
            widget.user['department'] ??
            '')
        .toString()
        .trim();
    if (widget.isHod && initialDept.isNotEmpty) {
      _selectedDept = initialDept;
    }
    if (_selectedDept.isNotEmpty && !_departments.contains(_selectedDept)) {
      _departments.add(_selectedDept);
    }
    _fetchDepartments();
    _fetchAcademicSettings();
    _fetchLogs();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${widget.token}',
      };

  String get _apiUrl => CollegeIPConfig.defaultURL;

  Future<void> _fetchAcademicSettings() async {
    try {
      final res = await http.get(
        Uri.parse('$_apiUrl/settings/academic'),
        headers: _headers,
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (mounted) {
          setState(() {
            _academicSettings = data;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchDepartments() async {
    try {
      final res = await http.get(
        Uri.parse('$_apiUrl/admin/departments'),
        headers: _headers,
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        List<dynamic> list = [];
        if (data is List) {
          list = data;
        } else if (data is Map && data['departments'] is List) {
          list = data['departments'];
        }
        if (list.isNotEmpty && mounted) {
          final fetched = list
              .map((d) => (d is Map ? (d['name'] ?? d['code'] ?? d['dept']) : d)
                  .toString()
                  .trim())
              .where((d) => d.isNotEmpty && d != 'null' && d != 'ALL')
              .toList();
          final uniqueSorted = fetched.toSet().toList()..sort((a, b) => a.compareTo(b));
          setState(() {
            _departments = ["ALL", ...uniqueSorted];
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchLogs() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final startStr = DateFormat('yyyy-MM-dd').format(_startDate);
      final endStr = DateFormat('yyyy-MM-dd').format(_endDate);

      final queryParams = <String, String>{
        'start_date': startStr,
        'end_date': endStr,
        'dept': _selectedDept,
        'period_number': _selectedPeriod,
        'status': _selectedStatus,
        'degree': _selectedDegree,
        'year_of_study': _selectedYear,
        'semester': _selectedSemester,
        'section': _selectedSection,
        'batch': _selectedBatch,
        'method': _selectedMethod,
        'search': _searchQuery,
      };

      final uri = Uri.parse('$_apiUrl/student/attendance/logs')
          .replace(queryParameters: queryParams);

      final response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) {
          final List<dynamic> allLogs = data['logs'] ?? [];
          final List<dynamic> matrixData = data['matrix'] ?? [];
          final Map<String, dynamic> rawSummary =
              Map<String, dynamic>.from(data['summary'] ?? {});
          final Map<String, dynamic> periodStats =
              Map<String, dynamic>.from(rawSummary['period_stats'] ?? {});

          // Dynamically parse available periods (fused with class timetable)
          final List<dynamic> rawAvail = data['available_periods'] ?? [];
          List<int> parsedPeriods = rawAvail
              .map((p) => int.tryParse(p.toString()))
              .whereType<int>()
              .where((p) => p > 0)
              .toList();

          if (parsedPeriods.isEmpty) {
            final discovered = <int>{};
            for (final m in matrixData) {
              if (m is Map && m['periods'] is Map) {
                for (final k in (m['periods'] as Map).keys) {
                  final pi = int.tryParse(k.toString());
                  if (pi != null && pi > 0) discovered.add(pi);
                }
              }
            }
            parsedPeriods = discovered.isNotEmpty
                ? (discovered.toList()..sort())
                : [1, 2, 3, 4, 5, 6, 7, 8];
          }

          // Dynamically merge any departments present in response or records
          final Set<String> discoveredDepts = {};
          if (data['departments'] is List) {
            for (final d in (data['departments'] as List)) {
              final dName = (d is Map ? (d['name'] ?? d['code'] ?? d['dept']) : d).toString().trim();
              if (dName.isNotEmpty && dName != 'null' && dName != 'ALL') {
                discoveredDepts.add(dName);
              }
            }
          }
          for (final m in matrixData) {
            if (m is Map && m['dept'] != null && m['dept'].toString().trim().isNotEmpty) {
              discoveredDepts.add(m['dept'].toString().trim());
            }
          }
          if (discoveredDepts.isNotEmpty) {
            final mergedDepts = {
              ..._departments.where((d) => d != 'ALL'),
              ...discoveredDepts
            }.toList()
              ..sort();
            _departments = ["ALL", ...mergedDepts];
          }

          // Exclude staff members from student logs
          final List<dynamic> rawLogs = allLogs.where((log) {
            if (log is! Map) return false;
            final role = (log['role'] ??
                    log['user_type'] ??
                    log['type'] ??
                    '')
                .toString()
                .toLowerCase();
            final regNo = (log['reg_no'] ?? log['staff_id'] ?? '')
                .toString()
                .toUpperCase();
            if (role == 'staff' ||
                role == 'admin' ||
                role == 'hod' ||
                role == 'other_staff' ||
                regNo.startsWith('STAFF_')) {
              return false;
            }
            return true;
          }).toList();

          _sortLogsList(rawLogs);
          _sortMatrixList(matrixData);

          setState(() {
            _logs = rawLogs;
            _matrix = matrixData;
            _summary = rawSummary;
            _periodStats = periodStats;
            _availablePeriods = parsedPeriods;
            _isLoading = false;
          });
        }
      } else {
        throw Exception("Server returned status ${response.statusCode}");
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Failed to load student attendance records. $e";
        });
      }
    }
  }

  void _sortLogsList(List<dynamic> list) {
    list.sort((a, b) {
      if (a is! Map || b is! Map) return 0;
      dynamic valA = a[_sortColumn];
      dynamic valB = b[_sortColumn];

      if (_sortColumn == 'date') {
        valA = "${a['date'] ?? ''}_${a['period_number'] ?? ''}";
        valB = "${b['date'] ?? ''}_${b['period_number'] ?? ''}";
      } else if (_sortColumn == 'period') {
        valA = a['period_number'] ?? 0;
        valB = b['period_number'] ?? 0;
      }

      int res = 0;
      if (valA == null && valB == null) {
        res = 0;
      } else if (valA == null) {
        res = -1;
      } else if (valB == null) {
        res = 1;
      } else {
        res = valA.toString().compareTo(valB.toString());
      }
      return _sortAscending ? res : -res;
    });
  }

  void _sortMatrixList(List<dynamic> list) {
    list.sort((a, b) {
      if (a is! Map || b is! Map) return 0;
      dynamic valA = a[_sortColumn];
      dynamic valB = b[_sortColumn];

      if (_sortColumn == 'date') {
        valA = "${a['date'] ?? ''}_${a['roll_no'] ?? ''}";
        valB = "${b['date'] ?? ''}_${b['roll_no'] ?? ''}";
      } else if (_sortColumn == 'percentage') {
        valA = a['day_percentage'] ?? 0.0;
        valB = b['day_percentage'] ?? 0.0;
      }

      int res = 0;
      if (valA == null && valB == null) {
        res = 0;
      } else if (valA == null) {
        res = -1;
      } else if (valB == null) {
        res = 1;
      } else if (valA is num && valB is num) {
        res = valA.compareTo(valB);
      } else {
        res = valA.toString().compareTo(valB.toString());
      }
      return _sortAscending ? res : -res;
    });
  }

  // -------------------------------------------------------------
  // QUICK DATE RANGE PRESETS
  // -------------------------------------------------------------
  void _selectDatePreset(String preset) {
    final now = DateTime.now();
    DateTime start = now;
    DateTime end = now;

    switch (preset) {
      case 'today':
        start = DateTime(now.year, now.month, now.day);
        end = now;
        break;
      case 'yesterday':
        final yest = now.subtract(const Duration(days: 1));
        start = DateTime(yest.year, yest.month, yest.day);
        end = DateTime(yest.year, yest.month, yest.day, 23, 59, 59);
        break;
      case 'this_week':
        final weekday = now.weekday; // 1 = Mon, 7 = Sun
        start = now.subtract(Duration(days: weekday - 1));
        start = DateTime(start.year, start.month, start.day);
        end = now;
        break;
      case 'last_7_days':
        start = now.subtract(const Duration(days: 6));
        start = DateTime(start.year, start.month, start.day);
        end = now;
        break;
      case 'this_month':
        start = DateTime(now.year, now.month, 1);
        end = now;
        break;
      case 'active_semester':
        final ranges =
            _academicSettings?['student_academic_settings']?['academic_ranges']
                as List<dynamic>?;
        if (ranges != null && ranges.isNotEmpty) {
          final activeRange = ranges.firstWhere(
            (r) => r['is_active'] == true,
            orElse: () => ranges.first,
          );
          if (activeRange != null) {
            try {
              start = DateTime.parse(activeRange['start']);
              end = DateTime.parse(activeRange['end']);
            } catch (_) {}
          }
        } else {
          start = DateTime(now.year, now.month >= 7 ? 7 : 1, 1);
          end = now;
        }
        break;
    }

    setState(() {
      _startDate = start;
      _endDate = end;
    });
    _fetchLogs();
  }

  Future<void> _pickCustomDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: brandBlue,
              onPrimary: Colors.white,
              onSurface: primaryNavy,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _fetchLogs();
    }
  }

  // -------------------------------------------------------------
  // PDF REPORT GENERATOR (Institutional Day & Period Matrix)
  // -------------------------------------------------------------
  Future<void> _generatePdfReport() async {
    final isMatrixMode = _viewMode == "matrix" && _matrix.isNotEmpty;
    if (_logs.isEmpty && _matrix.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("No records available to generate PDF report."),
          backgroundColor: amberWarning,
        ),
      );
      return;
    }

    final doc = pw.Document();
    final font = await PdfGoogleFonts.interRegular();
    final fontBold = await PdfGoogleFonts.interBold();

    final dateRangeStr =
        "${DateFormat('dd MMM yyyy').format(_startDate)} - ${DateFormat('dd MMM yyyy').format(_endDate)}";
    final genTimeStr =
        DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now());
    final userName =
        widget.user['name'] ?? widget.user['username'] ?? 'Administrator';
    final userRole = widget.isHod
        ? "HOD (${widget.defaultDept ?? 'Department'})"
        : (widget.isAdmin ? "System Administrator" : "Faculty Member");

    final totalRec = _summary['total_records'] ?? _logs.length;
    final totalStudentDays = _summary['total_student_days'] ?? _matrix.length;
    final presentCnt = _summary['present_count'] ?? 0;
    final absentCnt = _summary['absent_count'] ?? 0;
    final odCnt = _summary['od_count'] ?? 0;
    final leaveCnt = _summary['leave_count'] ?? 0;
    final pct = _summary['present_percentage'] ?? 0.0;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context context) {
          return [
            // Institutional Header Banner
            pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#0F172A'),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        "SRI SHAKTHI INSTITUTE OF ENGINEERING AND TECHNOLOGY",
                        style: pw.TextStyle(
                          font: fontBold,
                          color: PdfColors.white,
                          fontSize: 12,
                          letterSpacing: 0.5,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        isMatrixMode
                            ? "STUDENT ATTENDANCE DAY & PERIOD MATRIX REPORT (${_availablePeriods.isNotEmpty ? 'PERIODS P${_availablePeriods.first} TO P${_availablePeriods.last}' : 'TIMETABLE SCHEDULE'})"
                            : "STUDENT ATTENDANCE COMPREHENSIVE AUDIT & LOG REPORT",
                        style: pw.TextStyle(
                          font: fontBold,
                          color: PdfColor.fromHex('#38BDF8'),
                          fontSize: 9.5,
                        ),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        "Generated: $genTimeStr",
                        style: pw.TextStyle(
                          font: font,
                          color: PdfColor.fromHex('#E2E8F0'),
                          fontSize: 8,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        "Auditor: $userName ($userRole)",
                        style: pw.TextStyle(
                          font: font,
                          color: PdfColor.fromHex('#94A3B8'),
                          fontSize: 8,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 8),

            // Active Filters Box
            pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 10),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#F8FAFC'),
                borderRadius: pw.BorderRadius.circular(4),
                border: pw.Border.all(
                    color: PdfColor.fromHex('#E2E8F0'), width: 0.8),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("Date Range: $dateRangeStr",
                      style: pw.TextStyle(
                          font: fontBold,
                          fontSize: 8,
                          color: PdfColor.fromHex('#0F172A'))),
                  pw.Text("Dept: $_selectedDept",
                      style: pw.TextStyle(
                          font: font,
                          fontSize: 8,
                          color: PdfColor.fromHex('#475569'))),
                  pw.Text("Period Filter: $_selectedPeriod",
                      style: pw.TextStyle(
                          font: font,
                          fontSize: 8,
                          color: PdfColor.fromHex('#475569'))),
                  pw.Text("Status: $_selectedStatus",
                      style: pw.TextStyle(
                          font: font,
                          fontSize: 8,
                          color: PdfColor.fromHex('#475569'))),
                  pw.Text("Year/Sem: $_selectedYear / Sem $_selectedSemester",
                      style: pw.TextStyle(
                          font: font,
                          fontSize: 8,
                          color: PdfColor.fromHex('#475569'))),
                  pw.Text("Batch/Sec: $_selectedBatch / Sec $_selectedSection",
                      style: pw.TextStyle(
                          font: font,
                          fontSize: 8,
                          color: PdfColor.fromHex('#475569'))),
                ],
              ),
            ),
            pw.SizedBox(height: 8),

            // 6-Box Summary Metric KPI Strip
            pw.Row(
              children: [
                _buildPdfStatBox(
                    fontBold,
                    font,
                    isMatrixMode ? "STUDENT-DAYS" : "TOTAL LOGS",
                    isMatrixMode ? "$totalStudentDays" : "$totalRec",
                    '#1E3A8A',
                    '#EFF6FF'),
                pw.SizedBox(width: 5),
                _buildPdfStatBox(fontBold, font, "ATTENDANCE RATE", "$pct%",
                    '#059669', '#ECFDF5'),
                pw.SizedBox(width: 5),
                _buildPdfStatBox(fontBold, font, "PRESENT", "$presentCnt",
                    '#059669', '#ECFDF5'),
                pw.SizedBox(width: 5),
                _buildPdfStatBox(fontBold, font, "ABSENT", "$absentCnt",
                    '#DC2626', '#FEF2F2'),
                pw.SizedBox(width: 5),
                _buildPdfStatBox(fontBold, font, "ON-DUTY (OD)", "$odCnt",
                    '#2563EB', '#EFF6FF'),
                pw.SizedBox(width: 5),
                _buildPdfStatBox(fontBold, font, "ON LEAVE", "$leaveCnt",
                    '#7C3AED', '#F5F3FF'),
              ],
            ),
            pw.SizedBox(height: 10),

            // Main Table: Matrix vs Log Stream
            if (isMatrixMode)
              _buildPdfMatrixTable(fontBold, font)
            else
              _buildPdfLogStreamTable(fontBold, font),

            pw.SizedBox(height: 16),

            // Signatures
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(
                        width: 140,
                        height: 1,
                        color: PdfColor.fromHex('#CBD5E1')),
                    pw.SizedBox(height: 3),
                    pw.Text("Class Advisor / Faculty Signature",
                        style: pw.TextStyle(
                            font: fontBold,
                            fontSize: 7.5,
                            color: PdfColor.fromHex('#0F172A'))),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text(
                        "Status Key: P = Present | A = Absent | OD = On-Duty | L = Leave | H = Holiday | -- = Free",
                        style: pw.TextStyle(
                            font: font,
                            fontSize: 7,
                            color: PdfColors.grey700)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Container(
                        width: 140,
                        height: 1,
                        color: PdfColor.fromHex('#CBD5E1')),
                    pw.SizedBox(height: 3),
                    pw.Text("HOD / Academic Dean Signature",
                        style: pw.TextStyle(
                            font: fontBold,
                            fontSize: 7.5,
                            color: PdfColor.fromHex('#0F172A'))),
                  ],
                ),
              ],
            ),
          ];
        },
        footer: (pw.Context context) {
          return pw.Container(
            alignment: pw.Alignment.centerRight,
            margin: const pw.EdgeInsets.only(top: 8),
            child: pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount} • Official College Record • Attenda System',
              style: pw.TextStyle(
                  font: font, fontSize: 7, color: PdfColors.grey600),
            ),
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name:
          'Student_Period_Matrix_Report_${DateFormat('yyyyMMdd').format(_startDate)}.pdf',
    );
  }

  pw.Widget _buildPdfMatrixTable(pw.Font fontBold, pw.Font font) {
    final headers = [
      "#",
      "Date",
      "Reg No",
      "Roll No",
      "Student Name",
      "Dept",
      "Sem-Sec",
      ..._availablePeriods.map((p) => "P$p"),
      "Att/Tot",
      "Day %",
      "Status",
    ];

    final rows = <List<String>>[];
    for (int i = 0; i < _matrix.length; i++) {
      final item = _matrix[i];
      if (item is! Map) continue;
      final periods = (item['periods'] as Map?) ?? {};

      String getP(int p) {
        final pData = periods[p.toString()];
        if (pData is Map) {
          final isSched = pData['is_scheduled'] != false;
          final st = (pData['status'] ?? '--').toString();
          if (st == 'Present') return 'P';
          if (st == 'Absent') return 'A';
          if (st.contains('OD') || st.contains('On-Duty')) return 'OD';
          if (st.contains('Leave') || st.contains('Medical')) return 'L';
          if (st.contains('Holiday')) return 'H';
          if (!isSched) return '-';
          return '--';
        }
        return '--';
      }

      rows.add([
        "${i + 1}",
        "${item['date'] ?? '--'}",
        "${item['reg_no'] ?? '--'}",
        "${item['roll_no'] ?? '--'}",
        "${item['name'] ?? '--'}",
        "${item['dept'] ?? '--'}",
        "S${item['semester'] ?? '-'}-${item['section'] ?? '-'}",
        ..._availablePeriods.map((p) => getP(p)),
        "${item['attended_periods'] ?? 0}/${item['total_periods'] ?? 0}",
        "${item['day_percentage'] ?? 0}%",
        "${item['day_status'] ?? '--'}",
      ]);
    }

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      border: pw.TableBorder.all(
          color: PdfColor.fromHex('#CBD5E1'), width: 0.5),
      headerStyle: pw.TextStyle(
        font: fontBold,
        fontSize: 6.5,
        color: PdfColors.white,
      ),
      headerDecoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#1E3A8A'),
      ),
      cellStyle: pw.TextStyle(
        font: font,
        fontSize: 6.5,
        color: PdfColor.fromHex('#0F172A'),
      ),
      cellAlignment: pw.Alignment.center,
      cellPadding:
          const pw.EdgeInsets.symmetric(horizontal: 2.5, vertical: 3.5),
      rowDecoration: const pw.BoxDecoration(
        color: PdfColors.white,
      ),
      oddRowDecoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#F8FAFC'),
      ),
    );
  }

  pw.Widget _buildPdfLogStreamTable(pw.Font fontBold, pw.Font font) {
    final headers = [
      "#",
      "Date",
      "Reg No",
      "Roll No",
      "Student Name",
      "Dept",
      "Period",
      "Subject",
      "Faculty",
      "Status",
      "Time",
      "Method",
    ];

    final rows = <List<String>>[];
    for (int i = 0; i < _logs.length; i++) {
      final log = _logs[i];
      if (log is! Map) continue;
      rows.add([
        "${i + 1}",
        "${log['date'] ?? '--'}",
        "${log['reg_no'] ?? '--'}",
        "${log['roll_no'] ?? '--'}",
        "${log['name'] ?? '--'}",
        "${log['dept'] ?? '--'}",
        "P${log['period_number'] ?? 1}",
        "${log['subject_code'] ?? '--'}",
        "${log['faculty_name'] ?? '--'}",
        "${log['status'] ?? '--'}",
        "${log['entry_time'] ?? '--'}",
        "${log['method'] ?? 'Face'}",
      ]);
    }

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      border: pw.TableBorder.all(
          color: PdfColor.fromHex('#CBD5E1'), width: 0.5),
      headerStyle: pw.TextStyle(
        font: fontBold,
        fontSize: 6.5,
        color: PdfColors.white,
      ),
      headerDecoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#1E3A8A'),
      ),
      cellStyle: pw.TextStyle(
        font: font,
        fontSize: 6.5,
        color: PdfColor.fromHex('#0F172A'),
      ),
      cellAlignment: pw.Alignment.centerLeft,
      cellPadding:
          const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3.5),
      rowDecoration: const pw.BoxDecoration(
        color: PdfColors.white,
      ),
      oddRowDecoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#F8FAFC'),
      ),
    );
  }

  pw.Widget _buildPdfStatBox(pw.Font fontBold, pw.Font font, String title,
      String value, String colorHex, String bgHex) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 4),
        decoration: pw.BoxDecoration(
          color: PdfColor.fromHex(bgHex),
          borderRadius: pw.BorderRadius.circular(4),
          border: pw.Border.all(color: PdfColor.fromHex(colorHex), width: 0.6),
        ),
        child: pw.Column(
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(
                font: font,
                fontSize: 6.5,
                color: PdfColor.fromHex('#64748B'),
              ),
            ),
            pw.SizedBox(height: 1),
            pw.Text(
              value,
              style: pw.TextStyle(
                font: fontBold,
                fontSize: 9.5,
                color: PdfColor.fromHex(colorHex),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // CSV / EXCEL SPREADSHEET EXPORT (Period 1 to 8 Matrix)
  // -------------------------------------------------------------
  Future<void> _exportCsvSpreadsheet() async {
    final isMatrix = _viewMode == "matrix" && _matrix.isNotEmpty;
    if (_logs.isEmpty && _matrix.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("No records available to export CSV."),
          backgroundColor: amberWarning,
        ),
      );
      return;
    }

    final StringBuffer buffer = StringBuffer();
    // Add UTF-8 BOM for Microsoft Excel compatibility
    buffer.write('\uFEFF');

    if (isMatrix) {
      final periodCols = _availablePeriods.map((p) => '"Period $p"').join(',');
      buffer.writeln(
          '"S.No","Date","Register Number","Roll Number","Student Name","Degree","Department","Year","Semester","Section","Batch",$periodCols,"Total Scheduled Periods","Attended Periods","Day Attendance %","Day Status"');

      for (int i = 0; i < _matrix.length; i++) {
        final item = _matrix[i];
        if (item is! Map) continue;
        final periods = (item['periods'] as Map?) ?? {};

        String getPDesc(int p) {
          final pData = periods[p.toString()];
          if (pData is Map) {
            final isSched = pData['is_scheduled'] != false;
            final st = (pData['status'] ?? '--').toString();
            final code = (pData['subject_code'] ?? '').toString();
            if (st != '--') {
              return code.isNotEmpty ? '"$st ($code)"' : '"$st"';
            }
            if (!isSched) return '"Free"';
          }
          return '"--"';
        }

        final pRowVals = _availablePeriods.map((p) => getPDesc(p)).join(',');
        buffer.writeln(
            '${i + 1},"${item['date'] ?? ''}","${item['reg_no'] ?? ''}","${item['roll_no'] ?? ''}","${item['name'] ?? ''}","${item['degree'] ?? ''}","${item['dept'] ?? ''}",${item['year_of_study'] ?? ''},${item['semester'] ?? ''},"${item['section'] ?? ''}","${item['batch'] ?? ''}",$pRowVals,${item['total_periods'] ?? 0},${item['attended_periods'] ?? 0},"${item['day_percentage'] ?? 0}%","${item['day_status'] ?? ''}"');
      }
    } else {
      buffer.writeln(
          '"S.No","Date","Register Number","Roll Number","Student Name","Degree","Department","Year","Semester","Section","Batch","Period Number","Session Label","Subject Code","Subject Name","Faculty Name","Faculty ID","Hall/Lab","Status","Entry Time","Exit Time","Confidence Score","Verification Method","Day Type","Remarks"');

      for (int i = 0; i < _logs.length; i++) {
        final log = _logs[i];
        if (log is! Map) continue;
        buffer.writeln(
            '${i + 1},"${log['date'] ?? ''}","${log['reg_no'] ?? ''}","${log['roll_no'] ?? ''}","${log['name'] ?? ''}","${log['degree'] ?? ''}","${log['dept'] ?? ''}",${log['year_of_study'] ?? ''},${log['semester'] ?? ''},"${log['section'] ?? ''}","${log['batch'] ?? ''}",${log['period_number'] ?? 1},"${log['period_label'] ?? log['session'] ?? ''}","${log['subject_code'] ?? ''}","${log['subject_name'] ?? ''}","${log['faculty_name'] ?? ''}","${log['faculty_reg_no'] ?? ''}","${log['hall_name'] ?? ''}","${log['status'] ?? ''}","${log['entry_time'] ?? ''}","${log['exit_time'] ?? ''}",${log['confidence_score'] ?? 1.0},"${log['method'] ?? ''}","${log['day_type'] ?? 'NORMAL'}","${log['remarks'] ?? ''}"');
      }
    }

    final bytes = Uint8List.fromList(utf8.encode(buffer.toString()));
    final fileName = isMatrix
        ? "Student_Period_Matrix_${DateFormat('yyyyMMdd').format(_startDate)}.csv"
        : "Student_Attendance_Logs_${DateFormat('yyyyMMdd').format(_startDate)}.csv";

    await saveFile(bytes, fileName);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isMatrix
              ? "Student Day & Period Matrix exported to CSV successfully."
              : "Student Attendance Logs exported to CSV successfully."),
          backgroundColor: emeraldSuccess,
        ),
      );
    }
  }

  // -------------------------------------------------------------
  // PERIOD DETAIL MODAL (Inspect Single Period Cell)
  // -------------------------------------------------------------
  void _showPeriodDetailModal(
      Map<String, dynamic> studentDay, int periodNum, Map<String, dynamic> pData) {
    final status = (pData['status'] ?? '--').toString();
    final subjectCode = (pData['subject_code'] ?? '--').toString();
    final subjectName = (pData['subject_name'] ?? '--').toString();
    final facultyName = (pData['faculty_name'] ?? '--').toString();
    final entryTime = (pData['entry_time'] ?? '--').toString();
    final exitTime = (pData['exit_time'] ?? '--').toString();
    final method = (pData['method'] ?? '--').toString();
    final remarks = (pData['remarks'] ?? '').toString();
    final conf = pData['confidence_score'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Modal Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: brandBlue,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          "Period $periodNum",
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        "${studentDay['name']} (${studentDay['roll_no']})",
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: primaryNavy,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(height: 20),

              // Status Banner
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _getStatusBgColor(status),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: _getStatusColor(status).withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(_getStatusIcon(status),
                        color: _getStatusColor(status), size: 22),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Status: $status",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: _getStatusColor(status),
                          ),
                        ),
                        Text(
                          "Date: ${studentDay['date']} • Dept: ${studentDay['dept']}",
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Session Info Grid
              _buildModalDetailGrid([
                {"label": "Subject Code", "val": subjectCode},
                {"label": "Subject Name", "val": subjectName},
                {"label": "Faculty In-Charge", "val": facultyName},
                {"label": "Verification Method", "val": method},
                {"label": "Check-in Time", "val": entryTime},
                {"label": "Check-out Time", "val": exitTime},
                if (conf != null)
                  {
                    "label": "AI Confidence",
                    "val": "${((conf as num) * 100).toStringAsFixed(1)}%"
                  },
                if (remarks.isNotEmpty)
                  {"label": "Remarks / Notes", "val": remarks},
              ]),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  // -------------------------------------------------------------
  // STUDENT DETAIL MODAL (Inspect Full Student Day)
  // -------------------------------------------------------------
  void _showStudentDetailModal(Map<String, dynamic> item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final periods = (item['periods'] as Map?) ?? {};
        final dayPct = item['day_percentage'] ?? 0.0;

        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['name'] ?? 'Student Profile',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: primaryNavy,
                          ),
                        ),
                        Text(
                          "Reg No: ${item['reg_no']} • Roll: ${item['roll_no']}",
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const Divider(height: 20),

                // Day KPI Summary
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: slateBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: cardBorder),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildMetricSummaryItem(
                          "Date", "${item['date']}", primaryNavy),
                      _buildMetricSummaryItem("Day %", "$dayPct%",
                          dayPct >= 75.0 ? emeraldSuccess : roseDanger),
                      _buildMetricSummaryItem(
                          "Attended",
                          "${item['attended_periods']} / ${item['total_periods']}",
                          brandBlue),
                      _buildMetricSummaryItem(
                          "Status", "${item['day_status']}", primaryNavy),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Student Demographics
                _buildModalDetailGrid([
                  {"label": "Department", "val": "${item['dept']}"},
                  {"label": "Degree", "val": "${item['degree']}"},
                  {
                    "label": "Year / Sem",
                    "val": "Year ${item['year_of_study']} / Sem ${item['semester']}"
                  },
                  {"label": "Section / Batch", "val": "Sec ${item['section']} (${item['batch']})"},
                ]),
                const SizedBox(height: 14),

                // Period Breakdown dynamically based on class timetable
                Text(
                  "Period Breakdown (${_availablePeriods.isNotEmpty ? 'Periods P${_availablePeriods.first} to P${_availablePeriods.last}' : 'Periods'})",
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: primaryNavy,
                  ),
                ),
                const SizedBox(height: 8),
                ..._availablePeriods.map((pNum) {
                  final pData = periods[pNum.toString()] as Map? ?? {};
                  final isSched = pData['is_scheduled'] == true;
                  final pStatus = (pData['status'] ?? '--').toString();
                  final pSubCode = (pData['subject_code'] ?? '--').toString();
                  final pSubName = (pData['subject_name'] ?? '--').toString();
                  final pFac = (pData['faculty_name'] ?? '--').toString();
                  final pTime = (pData['entry_time'] ?? '--').toString();

                  String titleText = "Period $pNum (Free Period)";
                  if (pStatus != '--') {
                    titleText = pSubName != '--' ? "$pSubCode • $pSubName" : "Period $pNum Session";
                  } else if (isSched) {
                    titleText = pSubName != '--' ? "$pSubCode • $pSubName (Scheduled)" : "Period $pNum (Scheduled)";
                  }

                  String subText = isSched
                      ? (pStatus != '--' ? "Faculty: $pFac • Time: $pTime" : "Faculty: $pFac • Session not marked")
                      : "Not in class timetable for ${item['day_of_week'] ?? 'this day'}";

                  final badgeColor = pStatus != '--'
                      ? _getStatusColor(pStatus)
                      : (isSched ? accentBlue : Colors.grey.shade500);

                  final badgeBg = pStatus != '--'
                      ? _getStatusBgColor(pStatus)
                      : (isSched ? const Color(0xFFEFF6FF) : Colors.grey.shade100);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: badgeColor.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: badgeColor,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            "P$pNum",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                titleText,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: primaryNavy,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                subText,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: badgeColor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            pStatus != '--' ? pStatus : (isSched ? "Scheduled" : "Free"),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMetricSummaryItem(String label, String val, Color valColor) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
        const SizedBox(height: 2),
        Text(
          val,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: valColor,
          ),
        ),
      ],
    );
  }

  Widget _buildModalDetailGrid(List<Map<String, String>> items) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: slateBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cardBorder),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        children: items.map((item) {
          return SizedBox(
            width: (MediaQuery.of(context).size.width - 76) / 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['label']!,
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 1),
                Text(
                  item['val']!,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: primaryNavy,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // -------------------------------------------------------------
  // MAIN BUILD METHOD
  // -------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Material(
      color: slateBg,
      child: RefreshIndicator(
        onRefresh: _fetchLogs,
        child: Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Header Action Banner
                _buildHeaderBanner(),

                // 2. Multi-Level Filter Suite
                _buildFilterSuite(),
                const SizedBox(height: 12),

                // 3. Period-wise KPI Analytics Bar (Periods 1 to 8)
                if (_periodStats.isNotEmpty) _buildPeriodKpiStrip(),
                if (_periodStats.isNotEmpty) const SizedBox(height: 12),

                // 4. 6-Box Summary Metric Strip
                _buildSummaryMetricsStrip(),
                const SizedBox(height: 12),

                // 5. View Mode Switcher & Log Content Section
                _buildLogsContentSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // HEADER ACTION BANNER
  // -------------------------------------------------------------
  Widget _buildHeaderBanner() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [brandBlue, accentBlue],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: brandBlue.withValues(alpha: 0.2),
            blurRadius: 10,
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
                child: const Icon(Icons.grid_view_rounded,
                    color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Student Attendance Log & Period Matrix",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Day & Period Matrix (P1–P8), Granular Logs & Institutional Reports",
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Export Action Buttons
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.picture_as_pdf,
                    size: 16, color: Colors.white),
                label: const Text("Export Matrix PDF",
                    style: TextStyle(fontSize: 12, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _generatePdfReport,
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.table_view,
                    size: 16, color: Colors.white),
                label: const Text("Export Matrix CSV",
                    style: TextStyle(fontSize: 12, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _exportCsvSpreadsheet,
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh, size: 16, color: Colors.white),
                label: const Text("Refresh",
                    style: TextStyle(fontSize: 12, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _fetchLogs,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // PERIOD-WISE KPI ANALYTICS BAR (Periods 1 to 8)
  // -------------------------------------------------------------
  Widget _buildPeriodKpiStrip() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.schedule, size: 16, color: brandBlue),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  "Period Attendance Performance (${_availablePeriods.isNotEmpty ? 'P${_availablePeriods.first}–P${_availablePeriods.last}' : 'Periods'})",
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: primaryNavy,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                "Active Range",
                style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _availablePeriods.map((pNum) {
                final pStat = _periodStats[pNum.toString()] as Map? ?? {};
                final pTot = (pStat['total'] ?? 0) as int;
                final pPres = (pStat['present'] ?? 0) as int;
                final pOd = (pStat['od'] ?? 0) as int;
                final pAbs = (pStat['absent'] ?? 0) as int;
                final pPct = (pStat['pct'] ?? 100.0) as num;

                Color cardColor = pTot == 0
                    ? Colors.grey.shade500
                    : (pPct >= 75.0
                        ? emeraldSuccess
                        : (pPct >= 65.0 ? amberWarning : roseDanger));

                return Container(
                  width: 96,
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: slateBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: cardColor.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "P$pNum",
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: primaryNavy,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: cardColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              pTot > 0 ? "${pPct.toStringAsFixed(0)}%" : "--",
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: cardColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        pTot > 0 ? "P:${pPres + pOd} | A:$pAbs" : "No Sessions",
                        style: TextStyle(
                          fontSize: 9,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // MULTI-LEVEL FILTER SUITE
  // -------------------------------------------------------------
  Widget _buildFilterSuite() {
    final activeFilters = _activeFiltersCount;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Row 1: Quick Date Presets
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildDatePresetChip("Active Semester", "active_semester"),
                const SizedBox(width: 6),
                _buildDatePresetChip("This Month", "this_month"),
                const SizedBox(width: 6),
                _buildDatePresetChip("Today", "today"),
                const SizedBox(width: 6),
                _buildDatePresetChip("Yesterday", "yesterday"),
                const SizedBox(width: 6),
                _buildDatePresetChip("This Week", "this_week"),
                const SizedBox(width: 6),
                _buildDatePresetChip("Last 7 Days", "last_7_days"),
                const SizedBox(width: 6),
                ActionChip(
                  avatar: const Icon(Icons.date_range,
                      size: 14, color: brandBlue),
                  label: Text(
                    "${DateFormat('dd MMM').format(_startDate)} - ${DateFormat('dd MMM').format(_endDate)}",
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: brandBlue),
                  ),
                  backgroundColor: slateBg,
                  side: const BorderSide(color: cardBorder),
                  onPressed: _pickCustomDateRange,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Row 2: Primary Filters (Dept, Period, Status, Search)
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 600;
              return Column(
                children: [
                  Row(
                    children: [
                      // Department
                      Expanded(
                        flex: isNarrow ? 1 : 2,
                        child: _buildDeptDropdown(),
                      ),
                      const SizedBox(width: 8),
                      // Period
                      Expanded(
                        flex: 1,
                        child: _buildPeriodDropdown(),
                      ),
                      const SizedBox(width: 8),
                      // Status
                      Expanded(
                        flex: 1,
                        child: _buildStatusDropdown(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      // Search Query Field
                      Expanded(
                        child: _buildSearchField(),
                      ),
                      const SizedBox(width: 8),
                      // Advanced Filters Toggle Button
                      OutlinedButton.icon(
                        icon: Icon(
                          _isAdvancedFiltersOpen
                              ? Icons.filter_list_off
                              : Icons.tune,
                          size: 16,
                          color: _isAdvancedFiltersOpen || activeFilters > 0
                              ? brandBlue
                              : primaryNavy,
                        ),
                        label: Text(
                          activeFilters > 0
                              ? "Filters ($activeFilters)"
                              : "More",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _isAdvancedFiltersOpen || activeFilters > 0
                                ? brandBlue
                                : primaryNavy,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 12),
                          side: BorderSide(
                            color: _isAdvancedFiltersOpen || activeFilters > 0
                                ? brandBlue
                                : cardBorder,
                          ),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () {
                          setState(() {
                            _isAdvancedFiltersOpen = !_isAdvancedFiltersOpen;
                          });
                        },
                      ),
                      if (activeFilters > 0) ...[
                        const SizedBox(width: 6),
                        IconButton(
                          icon: const Icon(Icons.restart_alt,
                              size: 20, color: roseDanger),
                          tooltip: "Reset All Filters",
                          onPressed: _resetAllFilters,
                        ),
                      ],
                    ],
                  ),
                ],
              );
            },
          ),

          // Row 3: Collapsible Advanced Filters (Degree, Year, Sem, Sec, Batch, Method)
          if (_isAdvancedFiltersOpen) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: slateBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Advanced Academic Filters",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: primaryNavy,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      SizedBox(width: 110, child: _buildDegreeDropdown()),
                      SizedBox(width: 90, child: _buildYearDropdown()),
                      SizedBox(width: 90, child: _buildSemesterDropdown()),
                      SizedBox(width: 90, child: _buildSectionDropdown()),
                      SizedBox(width: 120, child: _buildBatchDropdown()),
                      SizedBox(width: 140, child: _buildMethodDropdown()),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDatePresetChip(String label, String preset) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      backgroundColor: slateBg,
      side: const BorderSide(color: cardBorder),
      onPressed: () => _selectDatePreset(preset),
    );
  }

  // -------------------------------------------------------------
  // 6-BOX SUMMARY METRICS STRIP
  // -------------------------------------------------------------
  Widget _buildSummaryMetricsStrip() {
    final isMatrixMode = _viewMode == "matrix";
    final totalRec = _summary['total_records'] ?? _logs.length;
    final totalStudentDays = _summary['total_student_days'] ?? _matrix.length;
    final presentCnt = _summary['present_count'] ?? 0;
    final absentCnt = _summary['absent_count'] ?? 0;
    final odCnt = _summary['od_count'] ?? 0;
    final leaveCnt = _summary['leave_count'] ?? 0;
    final pct = _summary['present_percentage'] ?? 0.0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 600;
          final width = isNarrow
              ? (constraints.maxWidth - 12) / 2
              : (constraints.maxWidth - 40) / 6;

          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildMetricCard(
                isMatrixMode ? "Student-Days" : "Total Logs",
                isMatrixMode ? "$totalStudentDays" : "$totalRec",
                brandBlue,
                Icons.people_outline,
                width,
              ),
              _buildMetricCard(
                "Present Rate",
                "$pct%",
                emeraldSuccess,
                Icons.check_circle_outline,
                width,
              ),
              _buildMetricCard(
                "Present",
                "$presentCnt",
                emeraldSuccess,
                Icons.done_all,
                width,
              ),
              _buildMetricCard(
                "Absent",
                "$absentCnt",
                roseDanger,
                Icons.highlight_off,
                width,
              ),
              _buildMetricCard(
                "On-Duty",
                "$odCnt",
                accentBlue,
                Icons.badge_outlined,
                width,
              ),
              _buildMetricCard(
                "On Leave",
                "$leaveCnt",
                purpleAccent,
                Icons.beach_access_outlined,
                width,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMetricCard(
      String title, String val, Color color, IconData icon, double width) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              const SizedBox(width: 4),
              Icon(icon, size: 14, color: color),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            val,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // VIEW MODE SWITCHER & LOG CONTENT SECTION
  // -------------------------------------------------------------
  Widget _buildLogsContentSection() {
    if (_isLoading) {
      return Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(40),
        alignment: Alignment.center,
        child: const Column(
          children: [
            CircularProgressIndicator(strokeWidth: 3, color: brandBlue),
            SizedBox(height: 12),
            Text("Loading student attendance records...",
                style: TextStyle(fontSize: 12, color: primaryNavy)),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: roseDanger.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            const Icon(Icons.error_outline, color: roseDanger, size: 28),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: const TextStyle(fontSize: 12, color: roseDanger),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _fetchLogs,
              style: ElevatedButton.styleFrom(backgroundColor: brandBlue),
              child: const Text("Try Again",
                  style: TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ],
        ),
      );
    }

    final isEmpty = _viewMode == "matrix" ? _matrix.isEmpty : _logs.isEmpty;

    if (isEmpty) {
      return Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cardBorder),
        ),
        alignment: Alignment.center,
        child: Column(
          children: [
            Icon(Icons.event_busy, size: 36, color: Colors.grey.shade400),
            const SizedBox(height: 10),
            const Text(
              "No student attendance records found for selected filters.",
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: primaryNavy,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Try expanding the date range or selecting 'All Departments'.",
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.restart_alt, size: 16),
              label: const Text("Reset Filters", style: TextStyle(fontSize: 12)),
              onPressed: _resetAllFilters,
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Section Title & 3-Way View Switcher
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _viewMode == "matrix"
                    ? "Day & Period Matrix (${_matrix.length} Student-Days)"
                    : (_viewMode == "table"
                        ? "Data Table View (${_logs.length} Records)"
                        : "Card View (${_logs.length} Records)"),
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: primaryNavy,
                ),
              ),
              // View Switcher (Matrix / Table / Cards)
              Container(
                decoration: BoxDecoration(
                  color: slateBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cardBorder),
                ),
                child: Row(
                  children: [
                    _buildViewModeButton(
                      mode: "matrix",
                      icon: Icons.grid_on,
                      label: "Period Matrix",
                    ),
                    _buildViewModeButton(
                      mode: "table",
                      icon: Icons.table_chart_outlined,
                      label: "Table",
                    ),
                    _buildViewModeButton(
                      mode: "cards",
                      icon: Icons.view_agenda_outlined,
                      label: "Cards",
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Content rendering based on _viewMode
          if (_viewMode == "matrix")
            _buildPeriodMatrixView()
          else if (_viewMode == "table")
            _buildDenseDataTable()
          else
            _buildCardsListView(),
        ],
      ),
    );
  }

  Widget _buildViewModeButton({
    required String mode,
    required IconData icon,
    required String label,
  }) {
    final isSelected = _viewMode == mode;
    return InkWell(
      onTap: () {
        setState(() {
          _viewMode = mode;
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? brandBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected ? Colors.white : primaryNavy,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.white : primaryNavy,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // PERIOD MATRIX VIEW (Periods 1 to 8 Side-by-Side)
  // -------------------------------------------------------------
  Widget _buildPeriodMatrixView() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorder),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F5F9)),
          headingTextStyle: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: primaryNavy,
          ),
          dataTextStyle: const TextStyle(
            fontSize: 11,
            color: primaryNavy,
          ),
          columnSpacing: 10,
          horizontalMargin: 12,
          columns: [
            const DataColumn(label: Text("#")),
            DataColumn(
              label: const Text("Date"),
              onSort: (idx, asc) {
                setState(() {
                  _sortColumn = "date";
                  _sortAscending = asc;
                });
                _sortMatrixList(_matrix);
              },
            ),
            const DataColumn(label: Text("Roll No")),
            DataColumn(
              label: const Text("Student Name"),
              onSort: (idx, asc) {
                setState(() {
                  _sortColumn = "name";
                  _sortAscending = asc;
                });
                _sortMatrixList(_matrix);
              },
            ),
            const DataColumn(label: Text("Dept")),
            const DataColumn(label: Text("Sem-Sec")),
            ..._availablePeriods.map((p) => DataColumn(
              label: Text("P$p"),
              tooltip: "Period $p",
            )),
            const DataColumn(label: Text("Att / Tot")),
            DataColumn(
              label: const Text("Day %"),
              onSort: (idx, asc) {
                setState(() {
                  _sortColumn = "percentage";
                  _sortAscending = asc;
                });
                _sortMatrixList(_matrix);
              },
            ),
            const DataColumn(label: Text("Status")),
            const DataColumn(label: Text("Action")),
          ],
          rows: _matrix.asMap().entries.map((entry) {
            final idx = entry.key;
            final item = entry.value as Map<String, dynamic>;
            final periods = (item['periods'] as Map?) ?? {};
            final dayPct = (item['day_percentage'] ?? 0.0) as num;
            final dayStatus = (item['day_status'] ?? '--').toString();

            return DataRow(
              cells: [
                DataCell(Text("${idx + 1}")),
                DataCell(Text("${item['date'] ?? '--'}")),
                DataCell(Text(
                  "${item['roll_no'] ?? '--'}",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                )),
                DataCell(InkWell(
                  onTap: () => _showStudentDetailModal(item),
                  child: Text(
                    "${item['name'] ?? '--'}",
                    style: const TextStyle(
                      color: brandBlue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )),
                DataCell(Text("${item['dept'] ?? '--'}")),
                DataCell(Text("S${item['semester'] ?? '-'}-${item['section'] ?? '-'}")),
                ..._availablePeriods.map((p) => DataCell(_buildPeriodBadge(item, p, periods['$p']))),
                DataCell(Text(
                  "${item['attended_periods'] ?? 0} / ${item['total_periods'] ?? 0}",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                )),
                DataCell(
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: (dayPct >= 75.0
                              ? emeraldSuccess
                              : (dayPct >= 65.0 ? amberWarning : roseDanger))
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      "${dayPct.toStringAsFixed(1)}%",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 10.5,
                        color: dayPct >= 75.0
                            ? emeraldSuccess
                            : (dayPct >= 65.0 ? amberWarning : roseDanger),
                      ),
                    ),
                  ),
                ),
                DataCell(_buildStatusPill(dayStatus)),
                DataCell(
                  IconButton(
                    icon: const Icon(Icons.info_outline,
                        size: 16, color: brandBlue),
                    tooltip: "Inspect Full Student Day",
                    onPressed: () => _showStudentDetailModal(item),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildPeriodBadge(
      Map<String, dynamic> studentDay, int periodNum, dynamic pData) {
    if (pData is! Map) {
      return Container(
        width: 28,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          "--",
          style: TextStyle(fontSize: 9, color: Colors.grey.shade500),
        ),
      );
    }

    final isScheduled = pData['is_scheduled'] == true;
    final status = (pData['status'] ?? '--').toString();
    final subCode = (pData['subject_code'] ?? '--').toString();
    final subName = (pData['subject_name'] ?? '--').toString();
    final faculty = (pData['faculty_name'] ?? '--').toString();
    final room = (pData['room_or_lab'] ?? '').toString();

    String label = "--";
    if (status == 'Present') {
      label = "P";
    } else if (status == 'Absent') {
      label = "A";
    } else if (status.contains('OD') || status.contains('On-Duty')) {
      label = "OD";
    } else if (status.contains('Leave') || status.contains('Medical')) {
      label = "L";
    } else if (status.contains('Holiday')) {
      label = "H";
    }

    Color color;
    Color bgColor;
    String tooltipMsg;

    if (status != '--') {
      color = _getStatusColor(status);
      bgColor = _getStatusBgColor(status);
      tooltipMsg = "P$periodNum: $status\nSubject: $subName ($subCode)\nFaculty: $faculty${room.isNotEmpty ? '\nRoom: $room' : ''}";
    } else if (isScheduled) {
      color = accentBlue;
      bgColor = const Color(0xFFEFF6FF);
      tooltipMsg = "P$periodNum: Scheduled Class\nSubject: $subName ($subCode)\nFaculty: $faculty${room.isNotEmpty ? '\nRoom: $room' : ''}\nStatus: Session pending / not marked";
    } else {
      color = Colors.grey.shade500;
      bgColor = Colors.grey.shade100;
      tooltipMsg = "Period $periodNum: Free Period\n(Not in timetable for ${studentDay['day_of_week'] ?? 'this day'})";
    }

    return InkWell(
      onTap: () => _showPeriodDetailModal(
          studentDay, periodNum, Map<String, dynamic>.from(pData)),
      borderRadius: BorderRadius.circular(4),
      child: Tooltip(
        message: tooltipMsg,
        child: Container(
          width: 28,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isScheduled && status == '--'
                  ? accentBlue.withValues(alpha: 0.5)
                  : color.withValues(alpha: 0.4),
              width: 0.8,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // DENSE DATA TABLE VIEW (Granular Period Logs)
  // -------------------------------------------------------------
  Widget _buildDenseDataTable() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorder),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F5F9)),
          headingTextStyle: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: primaryNavy,
          ),
          dataTextStyle: const TextStyle(
            fontSize: 11,
            color: primaryNavy,
          ),
          columnSpacing: 12,
          horizontalMargin: 12,
          columns: [
            const DataColumn(label: Text("#")),
            DataColumn(
              label: const Text("Date"),
              onSort: (idx, asc) {
                setState(() {
                  _sortColumn = "date";
                  _sortAscending = asc;
                });
                _sortLogsList(_logs);
              },
            ),
            const DataColumn(label: Text("Roll No")),
            DataColumn(
              label: const Text("Student Name"),
              onSort: (idx, asc) {
                setState(() {
                  _sortColumn = "name";
                  _sortAscending = asc;
                });
                _sortLogsList(_logs);
              },
            ),
            const DataColumn(label: Text("Dept")),
            const DataColumn(label: Text("Period")),
            const DataColumn(label: Text("Subject")),
            const DataColumn(label: Text("Faculty")),
            DataColumn(
              label: const Text("Status"),
              onSort: (idx, asc) {
                setState(() {
                  _sortColumn = "status";
                  _sortAscending = asc;
                });
                _sortLogsList(_logs);
              },
            ),
            const DataColumn(label: Text("Time")),
            const DataColumn(label: Text("Method")),
            const DataColumn(label: Text("Action")),
          ],
          rows: _logs.asMap().entries.map((entry) {
            final idx = entry.key;
            final log = entry.value as Map<String, dynamic>;
            final status = (log['status'] ?? '--').toString();

            return DataRow(
              cells: [
                DataCell(Text("${idx + 1}")),
                DataCell(Text("${log['date'] ?? '--'}")),
                DataCell(Text(
                  "${log['roll_no'] ?? '--'}",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                )),
                DataCell(Text(
                  "${log['name'] ?? '--'}",
                  style: const TextStyle(
                    color: brandBlue,
                    fontWeight: FontWeight.bold,
                  ),
                )),
                DataCell(Text("${log['dept'] ?? '--'}")),
                DataCell(Text("P${log['period_number'] ?? 1}")),
                DataCell(Text(
                  "${log['subject_code'] ?? '--'}",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                )),
                DataCell(Text("${log['faculty_name'] ?? '--'}")),
                DataCell(_buildStatusPill(status)),
                DataCell(Text("${log['entry_time'] ?? '--'}")),
                DataCell(Text("${log['method'] ?? 'Face'}")),
                DataCell(
                  IconButton(
                    icon: const Icon(Icons.info_outline,
                        size: 16, color: brandBlue),
                    onPressed: () {
                      _showPeriodDetailModal(
                        log,
                        log['period_number'] ?? 1,
                        log,
                      );
                    },
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // CARD STREAM VIEW
  // -------------------------------------------------------------
  Widget _buildCardsListView() {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _logs.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final log = _logs[index] as Map<String, dynamic>;
        return _buildLogCard(log, index);
      },
    );
  }

  Widget _buildLogCard(Map<String, dynamic> log, int index) {
    final status = (log['status'] ?? 'Present').toString();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: brandBlue.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  "P${log['period_number'] ?? 1}",
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: brandBlue,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      log['name'] ?? 'Student Name',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: primaryNavy,
                      ),
                    ),
                    Text(
                      "Reg: ${log['reg_no']} • Roll: ${log['roll_no']} • Dept: ${log['dept']}",
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              _buildStatusPill(status),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: slateBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Subject: ${log['subject_code'] ?? '--'} • ${log['subject_name'] ?? '--'}",
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: primaryNavy,
                  ),
                ),
                Text(
                  "Time: ${log['entry_time'] ?? '--'}",
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // STATUS PILL & COLOR HELPERS
  // -------------------------------------------------------------
  Widget _buildStatusPill(String status) {
    final color = _getStatusColor(status);
    final bgColor = _getStatusBgColor(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    final s = status.toLowerCase();
    if (s.contains('present') || s.contains('late')) return emeraldSuccess;
    if (s.contains('absent')) return roseDanger;
    if (s.contains('od') || s.contains('on-duty')) return accentBlue;
    if (s.contains('leave') || s.contains('medical')) return purpleAccent;
    if (s.contains('holiday')) return amberWarning;
    return Colors.grey.shade600;
  }

  Color _getStatusBgColor(String status) {
    final s = status.toLowerCase();
    if (s.contains('present') || s.contains('late')) return const Color(0xFFECFDF5);
    if (s.contains('absent')) return const Color(0xFFFEF2F2);
    if (s.contains('od') || s.contains('on-duty')) return const Color(0xFFEFF6FF);
    if (s.contains('leave') || s.contains('medical')) return const Color(0xFFF5F3FF);
    if (s.contains('holiday')) return const Color(0xFFFFFBEB);
    return Colors.grey.shade100;
  }

  IconData _getStatusIcon(String status) {
    final s = status.toLowerCase();
    if (s.contains('present')) return Icons.check_circle;
    if (s.contains('absent')) return Icons.cancel;
    if (s.contains('od')) return Icons.badge;
    if (s.contains('leave')) return Icons.beach_access;
    if (s.contains('holiday')) return Icons.celebration;
    return Icons.help_outline;
  }

  // -------------------------------------------------------------
  // DROPDOWN FILTER BUILDERS
  // -------------------------------------------------------------
  Widget _buildDeptDropdown() {
    final validDept = _departments.contains(_selectedDept) ? _selectedDept : "ALL";
    return DropdownButtonFormField<String>(
      key: ValueKey("dept_${validDept}_${_departments.length}"),
      isExpanded: true,
      initialValue: validDept,
      decoration: InputDecoration(
        labelText: "Department",
        floatingLabelBehavior: FloatingLabelBehavior.always,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
      items: _departments.map((d) {
        return DropdownMenuItem<String>(
          value: d,
          child: Text(
            d == "ALL" ? "All Depts" : d,
            style: const TextStyle(fontSize: 12),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        );
      }).toList(),
      onChanged: widget.isHod
          ? null
          : (val) {
              if (val != null) {
                setState(() {
                  _selectedDept = val;
                });
                _fetchLogs();
              }
            },
    );
  }

  Widget _buildPeriodDropdown() {
    final periods = ["ALL", ..._availablePeriods.map((p) => p.toString())];
    final validPeriod = periods.contains(_selectedPeriod) ? _selectedPeriod : "ALL";
    return DropdownButtonFormField<String>(
      key: ValueKey("period_${validPeriod}_${_availablePeriods.length}"),
      isExpanded: true,
      initialValue: validPeriod,
      decoration: InputDecoration(
        labelText: "Period",
        floatingLabelBehavior: FloatingLabelBehavior.always,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
      items: periods.map((p) {
        return DropdownMenuItem<String>(
          value: p,
          child: Text(
            p == "ALL" ? "All" : "P$p",
            style: const TextStyle(fontSize: 12),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        );
      }).toList(),
      onChanged: (val) {
        if (val != null) {
          setState(() {
            _selectedPeriod = val;
          });
          _fetchLogs();
        }
      },
    );
  }

  Widget _buildStatusDropdown() {
    final statuses = [
      "ALL",
      "Present",
      "Absent",
      "On-Duty",
      "Leave",
      "Medical Leave",
      "Holiday"
    ];
    return DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: _selectedStatus,
      decoration: InputDecoration(
        labelText: "Status",
        floatingLabelBehavior: FloatingLabelBehavior.always,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
      items: statuses.map((s) {
        return DropdownMenuItem<String>(
          value: s,
          child: Text(
            s == "ALL" ? "All" : s,
            style: const TextStyle(fontSize: 12),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        );
      }).toList(),
      onChanged: (val) {
        if (val != null) {
          setState(() {
            _selectedStatus = val;
          });
          _fetchLogs();
        }
      },
    );
  }

  Widget _buildDegreeDropdown() {
    final degrees = ["ALL", "B.E", "B.Tech", "M.E", "MBA", "MCA"];
    return DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: _selectedDegree,
      decoration: InputDecoration(
        labelText: "Degree",
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      items: degrees.map((d) {
        return DropdownMenuItem<String>(
          value: d,
          child: Text(d, style: const TextStyle(fontSize: 11)),
        );
      }).toList(),
      onChanged: (val) {
        if (val != null) {
          setState(() {
            _selectedDegree = val;
          });
          _fetchLogs();
        }
      },
    );
  }

  Widget _buildYearDropdown() {
    final years = ["ALL", "1", "2", "3", "4"];
    return DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: _selectedYear,
      decoration: InputDecoration(
        labelText: "Year",
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      items: years.map((y) {
        return DropdownMenuItem<String>(
          value: y,
          child: Text(y == "ALL" ? "All" : "Yr $y",
              style: const TextStyle(fontSize: 11)),
        );
      }).toList(),
      onChanged: (val) {
        if (val != null) {
          setState(() {
            _selectedYear = val;
          });
          _fetchLogs();
        }
      },
    );
  }

  Widget _buildSemesterDropdown() {
    final sems = ["ALL", "1", "2", "3", "4", "5", "6", "7", "8"];
    return DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: _selectedSemester,
      decoration: InputDecoration(
        labelText: "Semester",
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      items: sems.map((s) {
        return DropdownMenuItem<String>(
          value: s,
          child: Text(s == "ALL" ? "All" : "Sem $s",
              style: const TextStyle(fontSize: 11)),
        );
      }).toList(),
      onChanged: (val) {
        if (val != null) {
          setState(() {
            _selectedSemester = val;
          });
          _fetchLogs();
        }
      },
    );
  }

  Widget _buildSectionDropdown() {
    final secs = ["ALL", "A", "B", "C", "D"];
    return DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: _selectedSection,
      decoration: InputDecoration(
        labelText: "Section",
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      items: secs.map((s) {
        return DropdownMenuItem<String>(
          value: s,
          child: Text(s == "ALL" ? "All" : "Sec $s",
              style: const TextStyle(fontSize: 11)),
        );
      }).toList(),
      onChanged: (val) {
        if (val != null) {
          setState(() {
            _selectedSection = val;
          });
          _fetchLogs();
        }
      },
    );
  }

  Widget _buildBatchDropdown() {
    final batches = [
      "ALL",
      "2022-2026",
      "2023-2027",
      "2024-2028",
      "2025-2029",
      "2026-2030"
    ];
    return DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: _selectedBatch,
      decoration: InputDecoration(
        labelText: "Batch",
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      items: batches.map((b) {
        return DropdownMenuItem<String>(
          value: b,
          child: Text(b, style: const TextStyle(fontSize: 11)),
        );
      }).toList(),
      onChanged: (val) {
        if (val != null) {
          setState(() {
            _selectedBatch = val;
          });
          _fetchLogs();
        }
      },
    );
  }

  Widget _buildMethodDropdown() {
    final methods = [
      "ALL",
      "Face Recognition",
      "Biometric Kiosk",
      "Faculty Roll Sheet",
      "Approved Leave/OD",
      "System Auto",
    ];
    return DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: _selectedMethod,
      decoration: InputDecoration(
        labelText: "Method",
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      items: methods.map((m) {
        return DropdownMenuItem<String>(
          value: m,
          child: Text(m, style: const TextStyle(fontSize: 11)),
        );
      }).toList(),
      onChanged: (val) {
        if (val != null) {
          setState(() {
            _selectedMethod = val;
          });
          _fetchLogs();
        }
      },
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        labelText: "Search Name / Reg No / Roll No",
        prefixIcon: const Icon(Icons.search, size: 18),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 16),
                onPressed: () {
                  _searchController.clear();
                  setState(() {
                    _searchQuery = "";
                  });
                  _fetchLogs();
                },
              )
            : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      onSubmitted: (val) {
        setState(() {
          _searchQuery = val.trim();
        });
        _fetchLogs();
      },
    );
  }
}
