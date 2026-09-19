import 'dart:async';
import 'dart:ui';
import 'dart:math' as math;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_dragmarker/flutter_map_dragmarker.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../config/college_ip_config.dart';
import '../utils/wifi_check.dart';
import '../services/api_client.dart';
import '../services/session_service.dart';
import '../services/theme_service.dart';
import '../widgets/thirukkural_banner.dart';
import '../utils/api_response_utils.dart';
import '../utils/validators.dart';
import '../widgets/advanced_stat_card.dart';
import '../widgets/face_registration_widget.dart';
import '../widgets/attendance_pie_chart.dart';
import '../widgets/leave_request_widget.dart';
import '../widgets/three_option_toggle.dart';
import 'academics_settings_page.dart';
import 'attendance_duration_settings.dart';
import 'cl_management_page.dart';
import 'ccl_management_page.dart';
import 'attendance_log_page.dart';
import '../widgets/student_attendance_log_widget.dart';
import '../widgets/student_management/student_management_tab.dart';
import '../widgets/academic_schedule/academic_schedule_tab.dart';
import '../widgets/academic_schedule/venue_management_view.dart';
import '../widgets/student_academics/student_academics_settings_tab.dart';
import '../widgets/student_leave_od_management_tab.dart';
import '../widgets/student_face_requests_management_tab.dart';
import '../widgets/class_session_history_widget.dart';
import 'attendance_corrections_page.dart';
import 'system_reports_page.dart';
import 'security_hub_page.dart';
import 'holiday_calendar_page.dart';
import 'student_grievance_page.dart';
import 'substitute_management_page.dart';
import '../widgets/campus_movement_alerts_tab.dart';
import 'package:file_picker/file_picker.dart';

import '../utils/file_saver.dart';
import '../theme/admin_theme.dart';
import '../theme/admin_breakpoints.dart';
import '../widgets/admin_design_system.dart';

// ============================================
// ERROR CLEANING HELPERS
// ============================================

String cleanAdminErrorMessage(dynamic e) {
  final errorStr = e.toString();
  final errorLower = errorStr.toLowerCase();
  
  if (errorLower.contains('socketexception') ||
      errorLower.contains('failed host lookup') ||
      errorLower.contains('connection refused') ||
      errorLower.contains('clientexception')) {
    return 'Unable to connect to the server. Please check your network connection.';
  } else if (errorLower.contains('timeout') || errorLower.contains('time out')) {
    return 'Connection timed out. Please check your connection and try again.';
  } else if (errorLower.contains('formatexception') || errorLower.contains('unexpected character')) {
    return 'Invalid response format from server.';
  } else if (errorLower.contains('unauthorized') ||
             errorLower.contains('401') ||
             errorLower.contains('token expired')) {
    return 'Session expired or unauthorized. Please log in again.';
  } else if (errorLower.contains('403')) {
    return 'Access denied. You do not have permission to perform this action.';
  } else if (errorLower.contains('404')) {
    return 'Requested resource not found.';
  } else if (errorLower.contains('500') ||
             errorLower.contains('internal server error') ||
             errorLower.contains('502') ||
             errorLower.contains('503')) {
    return 'An internal server error occurred. Please contact the administrator.';
  }
  
  if (errorLower.contains('table') ||
      errorLower.contains('column') ||
      errorLower.contains('relation') ||
      errorLower.contains('database') ||
      errorLower.contains('sql') ||
      errorLower.contains('select ') ||
      errorLower.contains('insert ') ||
      errorLower.contains('update ') ||
      errorLower.contains('delete ') ||
      errorLower.contains('postgresql') ||
      errorLower.contains('mysql') ||
      errorLower.contains('sqlite') ||
      errorLower.contains('query') ||
      errorLower.contains('foreign key') ||
      errorLower.contains('constraint') ||
      errorLower.contains('syntax error')) {
    return 'A database operation error occurred. Details have been logged securely.';
  }

  if (errorStr.contains('\n') || errorStr.contains('Stacktrace') || errorStr.contains('Exception:')) {
    return 'An unexpected error occurred. Please try again.';
  }

  return errorStr.replaceAll(RegExp(r'(Exception:\s*|Error:\s*)', caseSensitive: false), '');
}

// ============================================
// BULK UPLOAD HELPER
// ============================================

Future<void> downloadTemplateHelper(BuildContext context, String token, String type, String format) async {
  final endpoint = '${CollegeIPConfig.defaultURL}/admin/templates/$type/$format';
  final filename = '${type}_template.${format == "excel" ? "xlsx" : "json"}';
  try {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    final response = await http.get(
      Uri.parse(endpoint),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (context.mounted) {
      Navigator.pop(context);
    }

    if (response.statusCode == 200) {
      await saveFile(response.bodyBytes, filename);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$filename downloaded successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      throw Exception('Server returned status code ${response.statusCode}');
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error downloading template: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

Future<void> downloadUsersHelper(BuildContext context, String token, String format) async {
  final endpoint = '${CollegeIPConfig.defaultURL}/admin/users/export/$format';
  final filename = 'all_users.${format == "excel" ? "xlsx" : "json"}';
  try {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    final response = await http.get(
      Uri.parse(endpoint),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (context.mounted) {
      Navigator.pop(context);
    }

    if (response.statusCode == 200) {
      await saveFile(response.bodyBytes, filename);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$filename downloaded successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      throw Exception('Server returned status code ${response.statusCode}');
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error downloading users: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}



Future<void> performBulkUpload(BuildContext context, String token, String endpointUrl, VoidCallback onSuccess) async {
  try {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls', 'json'],
    );

    if (result == null || result.files.isEmpty) {
      return;
    }

    final file = result.files.first;
    
    // Show loading indicator dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    var request = http.MultipartRequest('POST', Uri.parse(endpointUrl));
    request.headers['Authorization'] = 'Bearer $token';

    if (kIsWeb) {
      if (file.bytes != null) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'file',
            file.bytes!,
            filename: file.name,
          ),
        );
      } else {
        throw Exception("File bytes are null on web");
      }
    } else {
      if (file.path != null) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'file',
            file.path!,
          ),
        );
      } else if (file.bytes != null) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'file',
            file.bytes!,
            filename: file.name,
          ),
        );
      } else {
        throw Exception("File path and bytes are both null");
      }
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    // Dismiss loading indicator
    Navigator.pop(context);

    if (response.statusCode == 200) {
      final responseData = jsonDecode(response.body);
      final successMsg = responseData['message'] ?? 'Bulk upload completed successfully.';
      final data = responseData['data'] ?? {};
      final createdCount = data['created_count'] ?? 0;
      final failedCount = data['failed_count'] ?? 0;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Upload Status'),
          content: Text(
            '$successMsg\n\n'
            'Created/Synced: $createdCount\n'
            'Failed: $failedCount'
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                onSuccess();
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } else {
      final errorData = jsonDecode(response.body);
      final errorDetail = errorData['detail'] ?? 'An error occurred during bulk upload.';
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Upload Failed'),
          content: Text(errorDetail.toString()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  } catch (e) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(e.toString()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

// ============================================
// GEO FENCE EDITOR WIDGET
// ============================================

class GeoFenceEditor extends StatefulWidget {
  final String token;

  const GeoFenceEditor({super.key, required this.token});

  @override
  State<GeoFenceEditor> createState() => _GeoFenceEditorState();
}

class _GeoFenceEditorState extends State<GeoFenceEditor> {
  List<List<double>> _outerPolygon = [
    [11.040730, 77.073717],
    [11.040865, 77.075121],
    [11.039733, 77.075201],
    [11.039529, 77.075786],
    [11.038500, 77.075892],
    [11.038551, 77.073616],
  ];
  List<List<double>> _innerPolygon = [
    [11.039537, 77.075328],
    [11.039554, 77.075895],
    [11.038858, 77.075912],
    [11.038501, 77.074908],
  ];
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;
  String _tapTarget = 'none';
  String _editMode = 'none';
  final List<Map<String, dynamic>> _history = [];

  void _saveToHistory() {
    _history.add({
      'outer': List<List<double>>.from(_outerPolygon.map((p) => List<double>.from(p))),
      'inner': List<List<double>>.from(_innerPolygon.map((p) => List<double>.from(p))),
      'limit_range': List<List<double>>.from(_limitRangePolygon.map((p) => List<double>.from(p))),
      'outer_store': List<List<List<double>>>.from(_outerPolygonsStore.map((poly) => List<List<double>>.from(poly.map((p) => List<double>.from(p))))),
      'inner_store': List<List<List<double>>>.from(_innerPolygonsStore.map((poly) => List<List<double>>.from(poly.map((p) => List<double>.from(p))))),
      'limit_range_store': List<List<List<double>>>.from(_limitRangePolygonsStore.map((poly) => List<List<double>>.from(poly.map((p) => List<double>.from(p))))),
    });
    if (_history.length > 50) {
      _history.removeAt(0);
    }
  }

  List<List<List<double>>> _outerPolygonsStore = [];
  List<List<List<double>>> _innerPolygonsStore = [];
  List<List<List<double>>> _limitRangePolygonsStore = [];
  List<List<double>> _limitRangePolygon = [
    [11.040730, 77.073717],
    [11.040865, 77.075121],
    [11.039733, 77.075201],
  ];
  int _selectedOuterBoundary = 0;
  int _selectedInnerBoundary = 0;
  int _selectedLimitRangeBoundary = 0;
  bool _useSatelliteView = false;
  bool _isMapExpanded = false;
  final MapController _editorMapController = MapController();
  bool _outerPointsExpanded = false;
  bool _innerPointsExpanded = false;
  bool _limitPointsExpanded = false;

  @override
  void initState() {
    super.initState();
    _outerPolygonsStore = [List<List<double>>.from(_outerPolygon)];
    _innerPolygonsStore = [List<List<double>>.from(_innerPolygon)];
    _limitRangePolygonsStore = [List<List<double>>.from(_limitRangePolygon)];
    _loadGeoFenceCoordinates();
  }

  static List<List<List<double>>> _parsePolygonsStore(dynamic raw) {
    if (raw == null || raw is! List) return [];
    final result = <List<List<double>>>[];
    for (final poly in raw) {
      if (poly is List) {
        final polygon = <List<double>>[];
        for (final pt in poly) {
          if (pt is List && pt.length >= 2) {
            try {
              final lat = (pt[0] as num).toDouble();
              final lng = (pt[1] as num).toDouble();
              polygon.add([lat, lng]);
            } catch (_) {}
          }
        }
        if (polygon.length >= 3) {
          result.add(polygon);
        }
      }
    }
    return result;
  }

  static List<List<double>> _parseSinglePolygon(dynamic raw) {
    if (raw == null || raw is! List) return [];
    final polygon = <List<double>>[];
    for (final pt in raw) {
      if (pt is List && pt.length >= 2) {
        try {
          final lat = (pt[0] as num).toDouble();
          final lng = (pt[1] as num).toDouble();
          polygon.add([lat, lng]);
        } catch (_) {}
      }
    }
    return polygon;
  }

  Future<void> _loadGeoFenceCoordinates() async {
    try {
      final url = '${CollegeIPConfig.defaultURL}/admin/geo-fence';
      final response = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final parsedOuter = _parsePolygonsStore(data['data']['outer_polygons']);
          final parsedInner = _parsePolygonsStore(data['data']['inner_polygons']);
          final parsedLimit = _parsePolygonsStore(data['data']['limit_range_polygons']);

          setState(() {
            if (parsedOuter.isNotEmpty) {
              _outerPolygonsStore = parsedOuter;
              _selectedOuterBoundary = 0;
              _outerPolygon = List<List<double>>.from(_outerPolygonsStore[0]);
            } else if (data['data']['outer_polygon'] != null) {
              final single = _parseSinglePolygon(data['data']['outer_polygon']);
              if (single.isNotEmpty) {
                _outerPolygon = single;
                _outerPolygonsStore = [List<List<double>>.from(single)];
                _selectedOuterBoundary = 0;
              }
            }

            if (parsedInner.isNotEmpty) {
              _innerPolygonsStore = parsedInner;
              _selectedInnerBoundary = 0;
              _innerPolygon = List<List<double>>.from(_innerPolygonsStore[0]);
            } else if (data['data']['inner_polygon'] != null) {
              final single = _parseSinglePolygon(data['data']['inner_polygon']);
              if (single.isNotEmpty) {
                _innerPolygon = single;
                _innerPolygonsStore = [List<List<double>>.from(single)];
                _selectedInnerBoundary = 0;
              }
            }

            if (parsedLimit.isNotEmpty) {
              _limitRangePolygonsStore = parsedLimit;
              _selectedLimitRangeBoundary = 0;
              _limitRangePolygon = List<List<double>>.from(_limitRangePolygonsStore[0]);
            } else if (data['data']['limit_range_polygon'] != null) {
              final single = _parseSinglePolygon(data['data']['limit_range_polygon']);
              if (single.isNotEmpty) {
                _limitRangePolygon = single;
                _limitRangePolygonsStore = [List<List<double>>.from(single)];
                _selectedLimitRangeBoundary = 0;
              }
            }
            _errorMessage = null;
          });
        } else {
          setState(() {
            _errorMessage = data['error'] ?? 'Failed to load coordinates';
          });
        }
      } else {
        setState(() {
          _errorMessage = 'Server error: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage =
            'Unable to connect to server. Using default coordinates.';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveGeoFenceCoordinates() async {
    setState(() => _isSaving = true);
    try {
      _persistCurrentPolygons();
      final url = '${CollegeIPConfig.defaultURL}/admin/geo-fence';
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'outer_polygons': _outerPolygonsStore,
          'inner_polygons': _innerPolygonsStore,
          'limit_range_polygons': _limitRangePolygonsStore,
          'outer_polygon': _outerPolygon,
          'inner_polygon': _innerPolygon,
          'limit_range_polygon': _limitRangePolygon,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Geo fence coordinates updated successfully'),
              ),
            );
          }
          await CollegeIPConfig.loadGeoFenceCoordinates();
        } else {
          throw Exception(data['error'] ?? 'Unknown error');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save: ${cleanAdminErrorMessage(e)}')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _addPoint(String type) {
    _saveToHistory();
    setState(() {
      if (type == 'outer') {
        final last = _outerPolygon.isNotEmpty ? _outerPolygon.last : [11.040730, 77.073717];
        _outerPolygon = [
          ..._outerPolygon,
          [last[0] + 0.0001, last[1] + 0.0001],
        ];
        if (_selectedOuterBoundary < _outerPolygonsStore.length) {
          _outerPolygonsStore[_selectedOuterBoundary] = List<List<double>>.from(_outerPolygon);
        }
      } else if (type == 'inner') {
        final last = _innerPolygon.isNotEmpty ? _innerPolygon.last : [11.039537, 77.075328];
        _innerPolygon = [
          ..._innerPolygon,
          [last[0] + 0.0001, last[1] + 0.0001],
        ];
        if (_selectedInnerBoundary < _innerPolygonsStore.length) {
          _innerPolygonsStore[_selectedInnerBoundary] = List<List<double>>.from(_innerPolygon);
        }
      } else {
        final last = _limitRangePolygon.isNotEmpty ? _limitRangePolygon.last : [11.040730, 77.073717];
        _limitRangePolygon = [
          ..._limitRangePolygon,
          [last[0] + 0.0001, last[1] + 0.0001],
        ];
        if (_selectedLimitRangeBoundary < _limitRangePolygonsStore.length) {
          _limitRangePolygonsStore[_selectedLimitRangeBoundary] = List<List<double>>.from(_limitRangePolygon);
        }
      }
    });
  }

  void _removePoint(int index, String type) {
    _saveToHistory();
    setState(() {
      if (type == 'outer' && _outerPolygon.length > 3) {
        final list = List<List<double>>.from(_outerPolygon);
        list.removeAt(index);
        _outerPolygon = list;
        if (_selectedOuterBoundary < _outerPolygonsStore.length) {
          _outerPolygonsStore[_selectedOuterBoundary] = list;
        }
      } else if (type == 'inner' && _innerPolygon.length > 3) {
        final list = List<List<double>>.from(_innerPolygon);
        list.removeAt(index);
        _innerPolygon = list;
        if (_selectedInnerBoundary < _innerPolygonsStore.length) {
          _innerPolygonsStore[_selectedInnerBoundary] = list;
        }
      } else if (type == 'limit_range' && _limitRangePolygon.length > 3) {
        final list = List<List<double>>.from(_limitRangePolygon);
        list.removeAt(index);
        _limitRangePolygon = list;
        if (_selectedLimitRangeBoundary < _limitRangePolygonsStore.length) {
          _limitRangePolygonsStore[_selectedLimitRangeBoundary] = list;
        }
      }
    });
  }

  void _updatePoint(int index, double lat, double lng, String type) {
    setState(() {
      if (type == 'outer' && index < _outerPolygon.length) {
        final list = List<List<double>>.from(_outerPolygon);
        list[index] = [lat, lng];
        _outerPolygon = list;
        if (_selectedOuterBoundary < _outerPolygonsStore.length) {
          _outerPolygonsStore[_selectedOuterBoundary] = list;
        }
      } else if (type == 'inner' && index < _innerPolygon.length) {
        final list = List<List<double>>.from(_innerPolygon);
        list[index] = [lat, lng];
        _innerPolygon = list;
        if (_selectedInnerBoundary < _innerPolygonsStore.length) {
          _innerPolygonsStore[_selectedInnerBoundary] = list;
        }
      } else if (type == 'limit_range' && index < _limitRangePolygon.length) {
        final list = List<List<double>>.from(_limitRangePolygon);
        list[index] = [lat, lng];
        _limitRangePolygon = list;
        if (_selectedLimitRangeBoundary < _limitRangePolygonsStore.length) {
          _limitRangePolygonsStore[_selectedLimitRangeBoundary] = list;
        }
      }
    });
  }

  void _persistCurrentPolygons() {
    if (_outerPolygonsStore.isEmpty) {
      _outerPolygonsStore = [List<List<double>>.from(_outerPolygon)];
      _selectedOuterBoundary = 0;
    } else if (_selectedOuterBoundary < _outerPolygonsStore.length) {
      _outerPolygonsStore[_selectedOuterBoundary] = List<List<double>>.from(
        _outerPolygon,
      );
    }

    if (_innerPolygonsStore.isEmpty) {
      _innerPolygonsStore = [List<List<double>>.from(_innerPolygon)];
      _selectedInnerBoundary = 0;
    } else if (_selectedInnerBoundary < _innerPolygonsStore.length) {
      _innerPolygonsStore[_selectedInnerBoundary] = List<List<double>>.from(
        _innerPolygon,
      );
    }

    if (_limitRangePolygonsStore.isEmpty) {
      _limitRangePolygonsStore = [List<List<double>>.from(_limitRangePolygon)];
      _selectedLimitRangeBoundary = 0;
    } else if (_selectedLimitRangeBoundary < _limitRangePolygonsStore.length) {
      _limitRangePolygonsStore[_selectedLimitRangeBoundary] = List<List<double>>.from(
        _limitRangePolygon,
      );
    }
  }

  void _selectOuterBoundary(int index) {
    _persistCurrentPolygons();
    if (index < 0 || index >= _outerPolygonsStore.length) return;
    setState(() {
      _selectedOuterBoundary = index;
      _outerPolygon = List<List<double>>.from(_outerPolygonsStore[index]);
    });
    try {
      _editorMapController.move(_editorCenter(), 18.0);
    } catch (_) {}
  }

  void _selectInnerBoundary(int index) {
    _persistCurrentPolygons();
    if (index < 0 || index >= _innerPolygonsStore.length) return;
    setState(() {
      _selectedInnerBoundary = index;
      _innerPolygon = List<List<double>>.from(_innerPolygonsStore[index]);
    });
    try {
      final center = _toPolygonCenter(_innerPolygon);
      if (center != null) _editorMapController.move(center, 18.0);
    } catch (_) {}
  }

  void _selectLimitRangeBoundary(int index) {
    _persistCurrentPolygons();
    if (index < 0 || index >= _limitRangePolygonsStore.length) return;
    setState(() {
      _selectedLimitRangeBoundary = index;
      _limitRangePolygon = List<List<double>>.from(_limitRangePolygonsStore[index]);
    });
    try {
      final center = _toPolygonCenter(_limitRangePolygon);
      if (center != null) _editorMapController.move(center, 18.0);
    } catch (_) {}
  }

  void _addOuterBoundary() {
    _saveToHistory();
    _persistCurrentPolygons();
    final center = _editorCenter();
    final lat = center.latitude;
    final lng = center.longitude;
    setState(() {
      _outerPolygonsStore.add([
        [lat + 0.0006, lng - 0.0006],
        [lat + 0.0006, lng + 0.0006],
        [lat - 0.0006, lng + 0.0006],
        [lat - 0.0006, lng - 0.0006],
      ]);
      _selectedOuterBoundary = _outerPolygonsStore.length - 1;
      _outerPolygon = List<List<double>>.from(
        _outerPolygonsStore[_selectedOuterBoundary],
      );
      _tapTarget = 'outer';
    });
  }

  void _addInnerBoundary() {
    _saveToHistory();
    _persistCurrentPolygons();
    final center = _editorCenter();
    final lat = center.latitude;
    final lng = center.longitude;
    setState(() {
      _innerPolygonsStore.add([
        [lat + 0.0003, lng - 0.0003],
        [lat + 0.0003, lng + 0.0003],
        [lat - 0.0003, lng + 0.0003],
        [lat - 0.0003, lng - 0.0003],
      ]);
      _selectedInnerBoundary = _innerPolygonsStore.length - 1;
      _innerPolygon = List<List<double>>.from(
        _innerPolygonsStore[_selectedInnerBoundary],
      );
      _tapTarget = 'inner';
    });
  }

  void _deleteCurrentOuterBoundary() {
    if (_outerPolygonsStore.length <= 1) return;
    _saveToHistory();
    _persistCurrentPolygons();
    setState(() {
      _outerPolygonsStore.removeAt(_selectedOuterBoundary);
      if (_selectedOuterBoundary >= _outerPolygonsStore.length) {
        _selectedOuterBoundary = _outerPolygonsStore.length - 1;
      }
      _outerPolygon = List<List<double>>.from(
        _outerPolygonsStore[_selectedOuterBoundary],
      );
    });
  }

  void _deleteCurrentInnerBoundary() {
    if (_innerPolygonsStore.length <= 1) return;
    _saveToHistory();
    _persistCurrentPolygons();
    setState(() {
      _innerPolygonsStore.removeAt(_selectedInnerBoundary);
      if (_selectedInnerBoundary >= _innerPolygonsStore.length) {
        _selectedInnerBoundary = _innerPolygonsStore.length - 1;
      }
      _innerPolygon = List<List<double>>.from(
        _innerPolygonsStore[_selectedInnerBoundary],
      );
    });
  }

  void _addLimitRangeBoundary() {
    _saveToHistory();
    _persistCurrentPolygons();
    final center = _editorCenter();
    final lat = center.latitude;
    final lng = center.longitude;
    setState(() {
      _limitRangePolygonsStore.add([
        [lat + 0.0008, lng - 0.0008],
        [lat + 0.0008, lng + 0.0008],
        [lat - 0.0008, lng + 0.0008],
        [lat - 0.0008, lng - 0.0008],
      ]);
      _selectedLimitRangeBoundary = _limitRangePolygonsStore.length - 1;
      _limitRangePolygon = List<List<double>>.from(
        _limitRangePolygonsStore[_selectedLimitRangeBoundary],
      );
      _tapTarget = 'limit_range';
    });
  }

  void _deleteCurrentLimitRangeBoundary() {
    if (_limitRangePolygonsStore.length <= 1) return;
    _saveToHistory();
    _persistCurrentPolygons();
    setState(() {
      _limitRangePolygonsStore.removeAt(_selectedLimitRangeBoundary);
      if (_selectedLimitRangeBoundary >= _limitRangePolygonsStore.length) {
        _selectedLimitRangeBoundary = _limitRangePolygonsStore.length - 1;
      }
      _limitRangePolygon = List<List<double>>.from(
        _limitRangePolygonsStore[_selectedLimitRangeBoundary],
      );
    });
  }

  List<List<List<double>>> _effectiveOuterPolygons() {
    _persistCurrentPolygons();
    return _outerPolygonsStore;
  }

  List<List<List<double>>> _effectiveInnerPolygons() {
    _persistCurrentPolygons();
    return _innerPolygonsStore;
  }

  List<List<List<double>>> _effectiveLimitRangePolygons() {
    _persistCurrentPolygons();
    return _limitRangePolygonsStore;
  }

  List<LatLng> _toLatLng(List<List<double>> polygon) {
    return polygon.map((p) => LatLng(p[0], p[1])).toList();
  }

  LatLng? _toPolygonCenter(List<List<double>> source) {
    if (source.isEmpty) return null;
    final lat = source.fold<double>(0, (sum, p) => sum + p[0]) / source.length.toDouble();
    final lng = source.fold<double>(0, (sum, p) => sum + p[1]) / source.length.toDouble();
    return LatLng(lat, lng);
  }

  LatLng _editorCenter() {
    final source = _outerPolygon.isNotEmpty ? _outerPolygon : _innerPolygon;
    if (source.isEmpty) {
      return const LatLng(11.040730, 77.073717);
    }
    final lat =
        source.fold<double>(0, (sum, p) => sum + p[0]) /
        source.length.toDouble();
    final lng =
        source.fold<double>(0, (sum, p) => sum + p[1]) /
        source.length.toDouble();
    return LatLng(lat, lng);
  }

  void _addPointFromMap(LatLng point) {
    if (_editMode == 'none') return;
    _saveToHistory();
    setState(() {
      if (_tapTarget == 'outer') {
        _outerPolygon = [
          ..._outerPolygon,
          [point.latitude, point.longitude],
        ];
        if (_selectedOuterBoundary < _outerPolygonsStore.length) {
          _outerPolygonsStore[_selectedOuterBoundary] = List<List<double>>.from(_outerPolygon);
        }
      } else if (_tapTarget == 'inner') {
        _innerPolygon = [
          ..._innerPolygon,
          [point.latitude, point.longitude],
        ];
        if (_selectedInnerBoundary < _innerPolygonsStore.length) {
          _innerPolygonsStore[_selectedInnerBoundary] = List<List<double>>.from(_innerPolygon);
        }
      } else if (_tapTarget == 'limit_range') {
        _limitRangePolygon = [
          ..._limitRangePolygon,
          [point.latitude, point.longitude],
        ];
        if (_selectedLimitRangeBoundary < _limitRangePolygonsStore.length) {
          _limitRangePolygonsStore[_selectedLimitRangeBoundary] = List<List<double>>.from(_limitRangePolygon);
        }
      }
    });
  }

  void _undoLastChange() {
    if (_history.isNotEmpty) {
      setState(() {
        final lastState = _history.removeLast();
        _outerPolygon = List<List<double>>.from(lastState['outer'].map((p) => List<double>.from(p)));
        _innerPolygon = List<List<double>>.from(lastState['inner'].map((p) => List<double>.from(p)));
        _limitRangePolygon = List<List<double>>.from(lastState['limit_range'].map((p) => List<double>.from(p)));
        _outerPolygonsStore = List<List<List<double>>>.from(lastState['outer_store'].map((poly) => List<List<double>>.from(poly.map((p) => List<double>.from(p)))));
        _innerPolygonsStore = List<List<List<double>>>.from(lastState['inner_store'].map((poly) => List<List<double>>.from(poly.map((p) => List<double>.from(p)))));
        _limitRangePolygonsStore = List<List<List<double>>>.from(lastState['limit_range_store'].map((poly) => List<List<double>>.from(poly.map((p) => List<double>.from(p)))));
      });
    }
  }

  // Builds a single editable point row
  Widget _buildPointRow(
    int index,
    List<double> point,
    String type,
    bool canDelete,
    bool isDark,
    Color cardBg,
    Color borderColor,
    Color labelColor,
    Color textColor,
  ) {
    final themeColor = type == 'outer'
        ? Colors.deepPurple
        : (type == 'inner' ? Colors.teal : Colors.orange);

    return Container(
      key: ValueKey('${type}_$index'),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 5,
                color: themeColor,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: themeColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'POINT ${index + 1}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                color: themeColor,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                          const Spacer(),
                          if (canDelete)
                            IconButton(
                              onPressed: () => _removePoint(index, type),
                              icon: const Icon(
                                Icons.delete_rounded,
                                color: Colors.redAccent,
                                size: 18,
                              ),
                              tooltip: 'Delete point',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              initialValue: point[0].toStringAsFixed(6),
                              style: TextStyle(
                                fontSize: 13,
                                color: textColor,
                                fontWeight: FontWeight.w500,
                              ),
                              decoration: InputDecoration(
                                labelText: 'Latitude',
                                labelStyle: TextStyle(fontSize: 11, color: labelColor),
                                filled: true,
                                fillColor: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.grey.shade50,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                isDense: true,
                              ),
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                                signed: true,
                              ),
                              onChanged: (value) {
                                final lat = double.tryParse(value) ?? point[0];
                                _updatePoint(index, lat, point[1], type);
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              initialValue: point[1].toStringAsFixed(6),
                              style: TextStyle(
                                fontSize: 13,
                                color: textColor,
                                fontWeight: FontWeight.w500,
                              ),
                              decoration: InputDecoration(
                                labelText: 'Longitude',
                                labelStyle: TextStyle(fontSize: 11, color: labelColor),
                                filled: true,
                                fillColor: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.grey.shade50,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                isDense: true,
                              ),
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                                signed: true,
                              ),
                              onChanged: (value) {
                                final lng = double.tryParse(value) ?? point[1];
                                _updatePoint(index, point[0], lng, type);
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPillTab(
    String mode,
    String label,
    IconData icon,
    bool isDark,
    Color activeColor,
    bool isSmall,
  ) {
    final isSelected = _editMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _editMode = mode;
            _tapTarget = mode == 'none' ? 'none' : mode;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected 
                ? activeColor 
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: activeColor.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    )
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected 
                    ? Colors.white 
                    : (isDark ? Colors.white60 : Colors.black54),
              ),
              if (!isSmall) ...[
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isSelected 
                        ? Colors.white 
                        : (isDark ? Colors.white70 : Colors.black87),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMapFloatingButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    required bool isDark,
    bool active = false,
  }) {
    final isEnabled = onPressed != null;
    return ClipOval(
      child: Material(
        color: active 
            ? Colors.deepPurple 
            : (isDark ? const Color(0xFF1E1E24) : Colors.white).withValues(alpha: 0.9),
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(
              icon,
              size: 20,
              color: !isEnabled 
                  ? Colors.grey.withValues(alpha: 0.4) 
                  : (active ? Colors.white : (isDark ? Colors.white70 : Colors.black87)),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMobile = MediaQuery.of(context).size.width < 600;
    final scaffoldBg = isDark
        ? const Color(0xFF1C1C1E)
        : const Color(0xFFF2F2F7);
    final cardBg = isDark ? const Color(0xFF2C2C2E) : Colors.white;
    final sectionBg = isDark ? const Color(0xFF252528) : Colors.white;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.grey.shade200;
    final labelColor = isDark ? Colors.white54 : Colors.grey.shade600;
    final textColor = isDark ? Colors.white : Colors.black87;
    final headingColor = isDark ? Colors.white : Colors.grey.shade800;
    final subtitleColor = isDark ? Colors.white54 : Colors.grey.shade600;
    final canSave =
        _effectiveOuterPolygons().isNotEmpty &&
        _effectiveInnerPolygons().isNotEmpty &&
        _effectiveOuterPolygons().every((p) => p.length >= 3) &&
        _effectiveInnerPolygons().every((p) => p.length >= 3);

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: const Text('Edit Geo Fence'),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: canSave ? _saveGeoFenceCoordinates : null,
              child: Text(
                'Save (${_outerPolygon.length}/${_innerPolygon.length})',
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Header ──────────────────────────────────
                Text(
                  'Geo Fence Coordinates',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: headingColor,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Define geographical boundaries for attendance marking.',
                  style: TextStyle(fontSize: 14, color: subtitleColor),
                ),
                const SizedBox(height: 4),
                Text(
                  'Outer boundaries: ${_effectiveOuterPolygons().length}  •  '
                  'Inner boundaries: ${_effectiveInnerPolygons().length}  •  '
                  'Save ${canSave ? 'enabled ✓' : 'disabled (need ≥3 pts each)'}',
                  style: TextStyle(
                    fontSize: 12,
                    color: canSave ? Colors.green : Colors.orange,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                // ── Error banner ─────────────────────────────
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.orange.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.orange,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: Colors.orange,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                Container(
                  decoration: BoxDecoration(
                    color: sectionBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: borderColor),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.map_rounded,
                              size: 20,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Map-Based Point Editor',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          padding: const EdgeInsets.all(4),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final isSmall = constraints.maxWidth < 400;
                              final primaryColor = Theme.of(context).colorScheme.primary;
                              return Row(
                                children: [
                                  _buildPillTab('none', 'View', Icons.visibility_rounded, isDark, primaryColor, isSmall),
                                  _buildPillTab('outer', 'Outer', Icons.crop_free_rounded, isDark, Colors.deepPurple, isSmall),
                                  _buildPillTab('inner', 'Inner', Icons.wifi_off_rounded, isDark, Colors.teal, isSmall),
                                  _buildPillTab('limit_range', 'Limit', Icons.space_bar_rounded, isDark, Colors.orange, isSmall),
                                ],
                              );
                            }
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          height: isMobile
                              ? (_isMapExpanded ? MediaQuery.of(context).size.height * 0.70 : 420)
                              : (_isMapExpanded ? MediaQuery.of(context).size.height * 0.75 : 360),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: borderColor),
                          ),
                          clipBehavior: Clip.antiAlias,
                           child: FlutterMap(
                             mapController: _editorMapController,
                             options: MapOptions(
                               initialCenter: _editorCenter(),
                               initialZoom: 18,
                               minZoom: 3,
                               maxZoom: _useSatelliteView ? 21 : 20,
                                interactionOptions: const InteractionOptions(
                                  flags: InteractiveFlag.all,
                                ),
                               onTap: (_, point) => _addPointFromMap(point),
                               cameraConstraint: CameraConstraint.unconstrained(),
                             ),
                            children: [
                               TileLayer(
                                  key: ValueKey('map_tiles_${_useSatelliteView ? 'satellite' : 'standard'}'),
                                  urlTemplate: _useSatelliteView
                                      ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                                      : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                  fallbackUrl: _useSatelliteView
                                      ? 'https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                                      : 'https://a.tile.openstreetmap.org/{z}/{x}/{y}.png',
                                  userAgentPackageName: kIsWeb
                                      ? 'web.visiongate.app'
                                      : 'com.visiongate.app',
                                  tileProvider: NetworkTileProvider(),
                                  maxNativeZoom: _useSatelliteView ? 18 : 19,
                                  maxZoom: _useSatelliteView ? 21 : 20,
                                  minZoom: 3,
                                  keepBuffer: 12,
                                  panBuffer: 3,
                                  errorImage: const AssetImage('assets/images/map_error.png'),
                                ),
                              PolygonLayer(
                                polygons: [
                                  ..._effectiveOuterPolygons()
                                      .where((p) => p.length >= 3)
                                      .map(
                                        (poly) => Polygon(
                                          points: _toLatLng(poly),
                                          color: Colors.deepPurple.withValues(
                                            alpha: 0.20,
                                          ),
                                          borderColor: Colors.deepPurple,
                                          borderStrokeWidth: 3,
                                        ),
                                      ),
                                  ..._effectiveInnerPolygons()
                                      .where((p) => p.length >= 3)
                                      .map(
                                        (poly) => Polygon(
                                          points: _toLatLng(poly),
                                          color: Colors.teal.withValues(
                                            alpha: 0.22,
                                          ),
                                          borderColor: Colors.teal,
                                          borderStrokeWidth: 3,
                                        ),
                                      ),
                                  ..._effectiveLimitRangePolygons()
                                      .where((p) => p.length >= 3)
                                      .map(
                                        (poly) => Polygon(
                                          points: _toLatLng(poly),
                                          color: Colors.orange.withValues(
                                            alpha: 0.18,
                                          ),
                                          borderColor: Colors.orange,
                                          borderStrokeWidth: 3,
                                        ),
                                      ),
                                ],
                              ),
                              DragMarkers(
                                markers: [
                                  if (_editMode == 'outer')
                                    ..._outerPolygon.asMap().entries.map((entry) {
                                      final i = entry.key;
                                      final p = entry.value;
                                      return DragMarker(
                                        point: LatLng(p[0], p[1]),
                                        size: const Size(36, 36),
                                        builder: (context, _, isDragging) {
                                          return AnimatedContainer(
                                            duration: const Duration(
                                              milliseconds: 100,
                                            ),
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                              color: Colors.deepPurple,
                                              borderRadius: BorderRadius.circular(
                                                isDragging ? 20 : 18,
                                              ),
                                              border: Border.all(
                                                color: Colors.white,
                                                width: 2,
                                              ),
                                            ),
                                            child: Text(
                                              '${i + 1}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          );
                                        },
                                        onDragStart: (_, __) => _saveToHistory(),
                                        onDragUpdate: (_, latLng) {
                                          _updatePoint(
                                            i,
                                            latLng.latitude,
                                            latLng.longitude,
                                            'outer',
                                          );
                                        },
                                        onDragEnd: (_, latLng) {
                                          _updatePoint(
                                            i,
                                            latLng.latitude,
                                            latLng.longitude,
                                            'outer',
                                          );
                                        },
                                      );
                                    }),
                                  if (_editMode == 'inner')
                                    ..._innerPolygon.asMap().entries.map((entry) {
                                      final i = entry.key;
                                      final p = entry.value;
                                      return DragMarker(
                                        point: LatLng(p[0], p[1]),
                                        size: const Size(36, 36),
                                        builder: (context, _, isDragging) {
                                          return AnimatedContainer(
                                            duration: const Duration(
                                              milliseconds: 100,
                                            ),
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                              color: Colors.teal,
                                              borderRadius: BorderRadius.circular(
                                                isDragging ? 20 : 18,
                                              ),
                                              border: Border.all(
                                                color: Colors.white,
                                                width: 2,
                                              ),
                                            ),
                                            child: Text(
                                              '${i + 1}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          );
                                        },
                                        onDragStart: (_, __) => _saveToHistory(),
                                        onDragUpdate: (_, latLng) {
                                          _updatePoint(
                                            i,
                                            latLng.latitude,
                                            latLng.longitude,
                                            'inner',
                                          );
                                        },
                                        onDragEnd: (_, latLng) {
                                          _updatePoint(
                                            i,
                                            latLng.latitude,
                                            latLng.longitude,
                                            'inner',
                                          );
                                        },
                                      );
                                    }),
                                  if (_editMode == 'limit_range')
                                    ..._limitRangePolygon.asMap().entries.map((entry) {
                                      final i = entry.key;
                                      final p = entry.value;
                                      return DragMarker(
                                        point: LatLng(p[0], p[1]),
                                        size: const Size(36, 36),
                                        builder: (context, _, isDragging) {
                                          return AnimatedContainer(
                                            duration: const Duration(
                                              milliseconds: 100,
                                            ),
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                              color: Colors.orange,
                                              borderRadius: BorderRadius.circular(
                                                isDragging ? 20 : 18,
                                              ),
                                              border: Border.all(
                                                color: Colors.white,
                                                width: 2,
                                              ),
                                            ),
                                            child: Text(
                                              '${i + 1}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          );
                                        },
                                        onDragStart: (_, __) => _saveToHistory(),
                                        onDragUpdate: (_, latLng) {
                                          _updatePoint(
                                            i,
                                            latLng.latitude,
                                            latLng.longitude,
                                            'limit_range',
                                          );
                                        },
                                        onDragEnd: (_, latLng) {
                                          _updatePoint(
                                            i,
                                            latLng.latitude,
                                            latLng.longitude,
                                            'limit_range',
                                          );
                                        },
                                      );
                                    }),
                                ],
                              ),
                               Positioned(
                                 top: 10,
                                 right: 10,
                                 child: Column(
                                   mainAxisSize: MainAxisSize.min,
                                   children: [
                                     _buildMapFloatingButton(
                                       icon: Icons.my_location_rounded,
                                       tooltip: 'Recenter Map',
                                       onPressed: () {
                                         _editorMapController.move(_editorCenter(), 18.0);
                                       },
                                       isDark: isDark,
                                     ),
                                     const SizedBox(height: 8),
                                     _buildMapFloatingButton(
                                       icon: _useSatelliteView ? Icons.satellite_alt_rounded : Icons.map_rounded,
                                       tooltip: 'Toggle Satellite View',
                                       onPressed: () {
                                         setState(() {
                                           _useSatelliteView = !_useSatelliteView;
                                         });
                                       },
                                       isDark: isDark,
                                       active: _useSatelliteView,
                                     ),
                                     const SizedBox(height: 8),
                                     _buildMapFloatingButton(
                                       icon: Icons.undo_rounded,
                                       tooltip: 'Undo Last Change',
                                       onPressed: _history.isNotEmpty ? _undoLastChange : null,
                                       isDark: isDark,
                                     ),
                                     const SizedBox(height: 8),
                                     _buildMapFloatingButton(
                                       icon: _isMapExpanded ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                                       tooltip: _isMapExpanded ? 'Normal Size' : 'Full Size',
                                       onPressed: () {
                                         setState(() {
                                           _isMapExpanded = !_isMapExpanded;
                                         });
                                       },
                                       isDark: isDark,
                                     ),
                                   ],
                                 ),
                               ),
                               Positioned(
                                 bottom: 10,
                                 right: 10,
                                 child: Container(
                                   padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                   color: Colors.black.withValues(alpha: 0.6),
                                   child: Text(
                                     _useSatelliteView 
                                       ? '© Esri, DigitalGlobe' 
                                       : '© OpenStreetMap contributors',
                                     style: const TextStyle(
                                       color: Colors.white,
                                       fontSize: 9,
                                     ),
                                   ),
                                 ),
                               ),
                             ],
                           ),
                         ),
                        const SizedBox(height: 8),
                        Text(
                          'Tap on map to add point to selected polygon. '
                          'Drag numbered markers to move points. '
                          'Outer is purple and inner is teal.',
                          style: TextStyle(
                            fontSize: 12,
                            color: subtitleColor,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ── Outer Polygon Section ────────────────────
                Container(
                  decoration: BoxDecoration(
                    color: sectionBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Section header
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.deepPurple.withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.crop_square_rounded,
                                color: Colors.deepPurple,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Outer Boundary',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: textColor,
                                    ),
                                  ),
                                  Text(
                                    'Main campus area  •  ${_outerPolygon.length} points',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: subtitleColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () => _addPoint('outer'),
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Add'),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.deepPurple,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 12, 12),
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: borderColor),
                                color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.grey.shade50,
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<int>(
                                  value: _selectedOuterBoundary,
                                  icon: const Icon(Icons.arrow_drop_down, size: 20, color: Colors.deepPurple),
                                  style: TextStyle(
                                    color: textColor,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                  dropdownColor: cardBg,
                                  items: List.generate(
                                    _outerPolygonsStore.isEmpty ? 1 : _outerPolygonsStore.length,
                                    (i) => DropdownMenuItem(
                                      value: i,
                                      child: Text('Outer ${i + 1}'),
                                    ),
                                  ),
                                  onChanged: (value) {
                                    if (value != null) {
                                      _selectOuterBoundary(value);
                                    }
                                  },
                                ),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: _addOuterBoundary,
                              icon: const Icon(Icons.add_rounded, size: 16),
                              label: const Text('New Outer'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.deepPurple,
                                side: const BorderSide(color: Colors.deepPurple, width: 1),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: _deleteCurrentOuterBoundary,
                              icon: const Icon(Icons.delete_outline_rounded, size: 16),
                              label: const Text('Delete'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.redAccent,
                                side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.5), width: 1),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                            ),
                          ],
                        ),
                      ),
                       const Divider(height: 1),
                      InkWell(
                        onTap: () {
                          setState(() {
                            _outerPointsExpanded = !_outerPointsExpanded;
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Outer Boundary Points',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: textColor.withValues(alpha: 0.8),
                                ),
                              ),
                              Icon(
                                _outerPointsExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                size: 20,
                                color: subtitleColor,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_outerPointsExpanded) ...[
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (int i = 0; i < _outerPolygon.length; i++)
                                _buildPointRow(
                                  i,
                                  _outerPolygon[i],
                                  'outer',
                                  _outerPolygon.length > 3,
                                  isDark,
                                  cardBg,
                                  borderColor,
                                  labelColor,
                                  textColor,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── Inner Polygon Section ─────────────────────
                Container(
                  decoration: BoxDecoration(
                    color: sectionBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Section header
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.teal.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.wifi_off_rounded,
                                color: Colors.teal,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Inner Area',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: textColor,
                                    ),
                                  ),
                                  Text(
                                    'Low WiFi coverage zone  •  ${_innerPolygon.length} points',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: subtitleColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () => _addPoint('inner'),
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Add'),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.teal,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 12, 12),
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: borderColor),
                                color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.grey.shade50,
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<int>(
                                  value: _selectedInnerBoundary,
                                  icon: const Icon(Icons.arrow_drop_down, size: 20, color: Colors.teal),
                                  style: TextStyle(
                                    color: textColor,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                  dropdownColor: cardBg,
                                  items: List.generate(
                                    _innerPolygonsStore.isEmpty ? 1 : _innerPolygonsStore.length,
                                    (i) => DropdownMenuItem(
                                      value: i,
                                      child: Text('Inner ${i + 1}'),
                                    ),
                                  ),
                                  onChanged: (value) {
                                    if (value != null) {
                                      _selectInnerBoundary(value);
                                    }
                                  },
                                ),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: _addInnerBoundary,
                              icon: const Icon(Icons.add_rounded, size: 16),
                              label: const Text('New Inner'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.teal,
                                side: const BorderSide(color: Colors.teal, width: 1),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: _deleteCurrentInnerBoundary,
                              icon: const Icon(Icons.delete_outline_rounded, size: 16),
                              label: const Text('Delete'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.redAccent,
                                side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.5), width: 1),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                            ),
                          ],
                        ),
                      ),
                       const Divider(height: 1),
                      InkWell(
                        onTap: () {
                          setState(() {
                            _innerPointsExpanded = !_innerPointsExpanded;
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Inner Boundary Points',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: textColor.withValues(alpha: 0.8),
                                ),
                              ),
                              Icon(
                                _innerPointsExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                size: 20,
                                color: subtitleColor,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_innerPointsExpanded) ...[
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (int i = 0; i < _innerPolygon.length; i++)
                                _buildPointRow(
                                  i,
                                  _innerPolygon[i],
                                  'inner',
                                  _innerPolygon.length > 3,
                                  isDark,
                                  cardBg,
                                  borderColor,
                                  labelColor,
                                  textColor,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                const SizedBox(height: 16),

                // ── Movement Limit Polygon Section ────────────
                Container(
                  decoration: BoxDecoration(
                    color: sectionBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.space_bar_rounded,
                                color: Colors.orange,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Movement Limit',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: textColor,
                                    ),
                                  ),
                                  Text(
                                    'Allowed boundary limits  •  ${_limitRangePolygon.length} points',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: subtitleColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () {
                                setState(() {
                                  _limitRangePolygon = [
                                    ..._limitRangePolygon,
                                    [_limitRangePolygon.last[0] + 0.0001, _limitRangePolygon.last[1] + 0.0001],
                                  ];
                                });
                              },
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Add'),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.orange,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 12, 12),
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: borderColor),
                                color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.grey.shade50,
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<int>(
                                  value: _selectedLimitRangeBoundary,
                                  icon: const Icon(Icons.arrow_drop_down, size: 20, color: Colors.orange),
                                  style: TextStyle(
                                    color: textColor,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                  dropdownColor: cardBg,
                                  items: List.generate(
                                    _limitRangePolygonsStore.isEmpty ? 1 : _limitRangePolygonsStore.length,
                                    (i) => DropdownMenuItem(
                                      value: i,
                                      child: Text('Limit ${i + 1}'),
                                    ),
                                  ),
                                  onChanged: (value) {
                                    if (value != null) {
                                      _selectLimitRangeBoundary(value);
                                    }
                                  },
                                ),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: _addLimitRangeBoundary,
                              icon: const Icon(Icons.add_rounded, size: 16),
                              label: const Text('New Limit'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.orange,
                                side: const BorderSide(color: Colors.orange, width: 1),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: _deleteCurrentLimitRangeBoundary,
                              icon: const Icon(Icons.delete_outline_rounded, size: 16),
                              label: const Text('Delete'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.redAccent,
                                side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.5), width: 1),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                            ),
                          ],
                        ),
                      ),
                       const Divider(height: 1),
                      InkWell(
                        onTap: () {
                          setState(() {
                            _limitPointsExpanded = !_limitPointsExpanded;
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Limit Range Points',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: textColor.withValues(alpha: 0.8),
                                ),
                              ),
                              Icon(
                                _limitPointsExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                size: 20,
                                color: subtitleColor,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_limitPointsExpanded) ...[
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (int i = 0; i < _limitRangePolygon.length; i++)
                                _buildPointRow(
                                  i,
                                  _limitRangePolygon[i],
                                  'limit_range',
                                  _limitRangePolygon.length > 3,
                                  isDark,
                                  cardBg,
                                  borderColor,
                                  labelColor,
                                  textColor,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // ── Info card ────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: isDark ? 0.12 : 0.07),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.blue.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: Colors.blue,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Use Google Maps → right-click → "What\'s here?" to get lat/lng.\n'
                          'Outer boundary = main campus. Inner area = low-WiFi zone.\n'
                          'Each polygon needs at least 3 points.',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? Colors.white70
                                : Colors.blueGrey.shade700,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ── Save button at bottom ────────────────────
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: canSave && !_isSaving
                        ? _saveGeoFenceCoordinates
                        : null,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_rounded),
                    label: Text(_isSaving ? 'Saving…' : 'Save Geo Fence'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
    );
  }
}

// ============================================
// GLASSMORPHIC WIDGETS
// ============================================

/// A glassmorphic container widget that provides frosted glass effect
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double opacity;
  final double blur;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? borderColor;
  final double borderWidth;
  final Gradient? gradient;
  final List<BoxShadow>? boxShadow;

  const GlassContainer({
    super.key,
    required this.child,
    this.opacity = 0.15,
    this.blur = 10.0,
    this.borderRadius = 20.0,
    this.padding,
    this.margin,
    this.borderColor,
    this.borderWidth = 1.5,
    this.gradient,
    this.boxShadow,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.black : Colors.white;
    final defaultBorderColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.indigo.withValues(alpha: 0.12);

    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              gradient:
                  gradient ??
                  LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      baseColor.withValues(alpha: opacity),
                      baseColor.withValues(alpha: opacity * 0.5),
                    ],
                  ),
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(
                color: borderColor ?? defaultBorderColor,
                width: borderWidth,
              ),
              boxShadow:
                  boxShadow ??
                  [
                    BoxShadow(
                      color: isDark ? Colors.black.withValues(alpha: 0.3) : Colors.indigo.withValues(alpha: 0.05),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// A glassmorphic card with enhanced styling
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final VoidCallback? onTap;
  final Color? accentColor;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = 16.0,
    this.onTap,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? Colors.deepPurple;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: margin ?? const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.06),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: accent.withValues(alpha: isDark ? 0.08 : 0.02),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(borderRadius),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(borderRadius),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                padding: padding ?? const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isDark
                        ? [
                            Colors.white.withValues(alpha: 0.09),
                            Colors.white.withValues(alpha: 0.02),
                          ]
                        : [
                            Colors.white.withValues(alpha: 0.65),
                            Colors.white.withValues(alpha: 0.25),
                          ],
                  ),
                  borderRadius: BorderRadius.circular(borderRadius),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.15)
                        : Colors.white.withValues(alpha: 0.65),
                    width: 1.5,
                  ),
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A glassmorphic list tile for staff items
class GlassListTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? leading;
  final List<Widget>? trailing;
  final VoidCallback? onTap;
  final Color? accentColor;

  const GlassListTile({
    super.key,
    required this.title,
    required this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 12)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

/// Glassmorphic button
class GlassButton extends StatelessWidget {
  final String text;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Color? color;
  final bool isLoading;

  const GlassButton({
    super.key,
    required this.text,
    this.icon,
    this.onPressed,
    this.color,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final buttonColor = color ?? Colors.deepPurple;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isLoading ? null : onPressed,
        borderRadius: BorderRadius.circular(12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    buttonColor.withValues(alpha: 0.8),
                    buttonColor.withValues(alpha: 0.6),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[
                          Icon(icon, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          text,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// Custom Calendar Widget for Date Range Selection
class CustomDateRangeCalendar extends StatefulWidget {
  final DateTime? startDate;
  final DateTime? endDate;
  final Function(DateTime, DateTime) onDateRangeSelected;
  final DateTime? firstDate;
  final DateTime? lastDate;

  /// List of {start, end} DateTime ranges. Dates outside all ranges appear dull and unselectable.
  final List<Map<String, DateTime>>? academicRanges;

  const CustomDateRangeCalendar({
    super.key,
    this.startDate,
    this.endDate,
    required this.onDateRangeSelected,
    this.firstDate,
    this.lastDate,
    this.academicRanges,
  });

  @override
  State<CustomDateRangeCalendar> createState() =>
      _CustomDateRangeCalendarState();
}

class _CustomDateRangeCalendarState extends State<CustomDateRangeCalendar> {
  late DateTime _currentMonth;
  DateTime? _selectingStartDate;
  DateTime? _selectingEndDate;
  bool _isSelectingStart = true;

  @override
  void initState() {
    super.initState();
    // Start with the month of the start date or current month
    if (widget.startDate != null) {
      _currentMonth = DateTime(widget.startDate!.year, widget.startDate!.month);
      _selectingStartDate = widget.startDate;
    } else {
      _currentMonth = DateTime(DateTime.now().year, DateTime.now().month);
    }
    if (widget.endDate != null) {
      _selectingEndDate = widget.endDate;
    }
  }

  void _goToPreviousMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
    });
  }

  void _goToNextMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);
    });
  }

  bool _isInAcademicRanges(DateTime date) {
    final ranges = widget.academicRanges;
    if (ranges == null || ranges.isEmpty) return true;
    for (final r in ranges) {
      final start = r['start']!;
      final end = r['end']!;
      if (!date.isBefore(start) && !date.isAfter(end)) return true;
    }
    return false;
  }

  void _onDateTap(DateTime date) {
    final lastDate = widget.lastDate ?? DateTime.now();
    if (date.isAfter(lastDate)) return;
    if (!_isInAcademicRanges(date)) return;

    setState(() {
      if (_isSelectingStart) {
        _selectingStartDate = date;
        _selectingEndDate = null;
        _isSelectingStart = false;
      } else {
        if (date.isBefore(_selectingStartDate!)) {
          // If selected date is before start date, reset and start new selection
          _selectingStartDate = date;
          _selectingEndDate = null;
          _isSelectingStart = false;
        } else {
          _selectingEndDate = date;
          _isSelectingStart = true;
          // Notify parent of selection
          widget.onDateRangeSelected(_selectingStartDate!, _selectingEndDate!);
        }
      }
    });
  }

  bool _isInRange(DateTime date) {
    if (_selectingStartDate == null || _selectingEndDate == null) return false;
    return date.isAfter(_selectingStartDate!) &&
        date.isBefore(_selectingEndDate!);
  }

  bool _isStartOrEnd(DateTime date) {
    if (_selectingStartDate == null) return false;
    if (_selectingEndDate != null) {
      return _isSameDay(date, _selectingStartDate!) ||
          _isSameDay(date, _selectingEndDate!);
    }
    return _isSameDay(date, _selectingStartDate!);
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  @override
  Widget build(BuildContext context) {
    final firstDayOfMonth = DateTime(
      _currentMonth.year,
      _currentMonth.month,
      1,
    );
    final lastDayOfMonth = DateTime(
      _currentMonth.year,
      _currentMonth.month + 1,
      0,
    );
    final firstWeekday = firstDayOfMonth.weekday;
    final daysInMonth = lastDayOfMonth.day;

    final lastDate = widget.lastDate ?? DateTime.now();
    final firstAvailableDate = widget.firstDate ?? DateTime(2020);

    final monthNames = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    final weekDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Month Navigation Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: _goToPreviousMonth,
                icon: const Icon(Icons.chevron_left),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.deepPurple.withValues(alpha: 0.1),
                  foregroundColor: Colors.deepPurple,
                ),
                tooltip: 'Previous Month',
              ),
              Text(
                '${monthNames[_currentMonth.month - 1]} ${_currentMonth.year}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple,
                ),
              ),
              IconButton(
                onPressed:
                    _currentMonth.isBefore(
                      DateTime(lastDate.year, lastDate.month),
                    )
                    ? _goToNextMonth
                    : null,
                icon: const Icon(Icons.chevron_right),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.deepPurple.withValues(alpha: 0.1),
                  foregroundColor: Colors.deepPurple,
                ),
                tooltip: 'Next Month',
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Selection Status
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _isSelectingStart
                  ? Colors.deepPurple.withValues(alpha: 0.1)
                  : Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isSelectingStart ? Icons.touch_app : Icons.check_circle,
                  color: _isSelectingStart ? Colors.deepPurple : Colors.green,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  _isSelectingStart
                      ? 'Tap to select START date'
                      : 'Tap to select END date',
                  style: TextStyle(
                    color: _isSelectingStart ? Colors.deepPurple : Colors.green,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Week Day Headers
          Row(
            children: weekDays
                .map(
                  (day) => Expanded(
                    child: Center(
                      child: Text(
                        day,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 8),

          // Calendar Grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1,
            ),
            itemCount: 42, // 6 weeks
            itemBuilder: (context, index) {
              final dayOffset = index - (firstWeekday - 1);
              if (dayOffset < 0 || dayOffset >= daysInMonth) {
                return const SizedBox();
              }

              final date = DateTime(
                _currentMonth.year,
                _currentMonth.month,
                dayOffset + 1,
              );
              final isDisabled = date.isAfter(lastDate);
              final isBeforeFirst = date.isBefore(firstAvailableDate);
              final outsideAcademic = !_isInAcademicRanges(date);
              final isInRange = _isInRange(date);
              final isStartOrEnd = _isStartOrEnd(date);

              Color? bgColor;
              Color? textColor;

              if (isDisabled || isBeforeFirst || outsideAcademic) {
                textColor = Colors.grey[300];
              } else if (isStartOrEnd) {
                bgColor = Colors.deepPurple;
                textColor = Colors.white;
              } else if (isInRange) {
                bgColor = Colors.deepPurple.withValues(alpha: 0.2);
                textColor = Colors.deepPurple;
              } else {
                textColor = Colors.black87;
              }

              return GestureDetector(
                onTap: (isDisabled || isBeforeFirst || outsideAcademic)
                    ? null
                    : () => _onDateTap(date),
                child: Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 1,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      '${dayOffset + 1}',
                      style: TextStyle(
                        color: textColor,
                        fontWeight: isStartOrEnd
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

          // Selected Dates Display
          if (_selectingStartDate != null || _selectingEndDate != null) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildSelectedDateChip(
                  'Start Date',
                  _selectingStartDate,
                  Colors.deepPurple,
                ),
                const Icon(Icons.arrow_forward, color: Colors.grey),
                _buildSelectedDateChip(
                  'End Date',
                  _selectingEndDate,
                  _selectingEndDate != null ? Colors.green : Colors.grey,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSelectedDateChip(String label, DateTime? date, Color color) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color),
          ),
          child: Text(
            date != null
                ? '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}'
                : 'Not selected',
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

// Quick select chip widget
class _QuickSelectChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color color;

  const _QuickSelectChip({
    required this.label,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

class AdminLoginPage extends StatefulWidget {
  const AdminLoginPage({super.key});

  @override
  State<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends State<AdminLoginPage> {
  final usernameCtrl = TextEditingController();
  final passwordCtrl = TextEditingController();
  bool isLoading = false;
  bool obscurePassword = true;
  String errorMsg = '';

  @override
  void dispose() {
    usernameCtrl.dispose();
    passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (usernameCtrl.text.isEmpty || passwordCtrl.text.isEmpty) {
      setState(() => errorMsg = 'Please enter username and password');
      return;
    }

    setState(() {
      isLoading = true;
      errorMsg = '';
    });

    try {
      final response = await http.post(
        Uri.parse('$API_URL/admin/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': usernameCtrl.text,
          'password': passwordCtrl.text,
        }),
      );

      if (response.statusCode == 200) {
        final data = ApiResponseUtils.tryParseJson(response.body);
        if (data == null) {
          setState(
            () => errorMsg =
                'Login failed: invalid server response. Please verify backend URL/server status.',
          );
          return;
        }
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) =>
                AdminDashboardPage(token: data['token'], user: data['user']),
          ),
        );
      } else {
        final data = ApiResponseUtils.tryParseJson(response.body);
        setState(
          () =>
              errorMsg =
                  data?['detail'] ??
                  data?['message'] ??
                  data?['error'] ??
                  ApiResponseUtils.nonJsonErrorMessage(
                    response.statusCode,
                    response.body,
                  ),
        );
      }
    } catch (e) {
      setState(() => errorMsg = 'Connection error: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final double screenWidth = MediaQuery.of(context).size.width;
    final double pagePadding = AdminBreakpoints.pagePadding(screenWidth);

    return Scaffold(
      backgroundColor: AdminColors.getSurface(isDark),
      body: Stack(
        children: [
          // Background Ambient Orbs
          Positioned(
            top: -100,
            left: -80,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AdminColors.primary.withOpacity(isDark ? 0.25 : 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -120,
            right: -100,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AdminColors.rose.withOpacity(isDark ? 0.2 : 0.08),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Main Center Card
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(pagePadding),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: AdminCard(
                    padding: EdgeInsets.all(screenWidth < AdminBreakpoints.xs ? 16 : 28),
                    borderRadius: AdminRadii.xxl,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // App Logo Hero
                        Center(
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(AdminRadii.xl),
                              boxShadow: AdminShadows.glow(AdminColors.primary, opacity: 0.3),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(AdminRadii.xl),
                              child: Image.asset(
                                'assets/images/logo.png',
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return const Icon(
                                    Icons.admin_panel_settings_rounded,
                                    size: 44,
                                    color: Colors.white,
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Title & Subtitle
                        Text(
                          'VisionGate Admin',
                          textAlign: TextAlign.center,
                          style: AdminTextStyles.displayLg(isDark).copyWith(
                            fontSize: screenWidth < AdminBreakpoints.xs ? 22 : 26,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Administrative Access Portal',
                          textAlign: TextAlign.center,
                          style: AdminTextStyles.bodyMd(
                            isDark,
                            color: AdminColors.getTextSecondary(isDark),
                          ),
                        ),
                        const SizedBox(height: 32),

                        // Username Field
                        TextField(
                          controller: usernameCtrl,
                          textInputAction: TextInputAction.next,
                          style: AdminTextStyles.bodyMd(isDark),
                          decoration: InputDecoration(
                            labelText: 'Username',
                            labelStyle: AdminTextStyles.labelSm(isDark),
                            prefixIcon: const Icon(
                              Icons.person_rounded,
                              color: AdminColors.primary,
                              size: 20,
                            ),
                            filled: true,
                            fillColor: AdminColors.getCardTinted(isDark),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AdminRadii.md),
                              borderSide: BorderSide(color: AdminColors.getBorder(isDark)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AdminRadii.md),
                              borderSide: BorderSide(color: AdminColors.getBorder(isDark)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AdminRadii.md),
                              borderSide: const BorderSide(color: AdminColors.primary, width: 1.5),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Password Field
                        TextField(
                          controller: passwordCtrl,
                          obscureText: obscurePassword,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _login(),
                          style: AdminTextStyles.bodyMd(isDark),
                          decoration: InputDecoration(
                            labelText: 'Password',
                            labelStyle: AdminTextStyles.labelSm(isDark),
                            prefixIcon: const Icon(
                              Icons.lock_rounded,
                              color: AdminColors.primary,
                              size: 20,
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                obscurePassword
                                    ? Icons.visibility_off_rounded
                                    : Icons.visibility_rounded,
                                color: AdminColors.getTextMuted(isDark),
                                size: 20,
                              ),
                              onPressed: () {
                                setState(() => obscurePassword = !obscurePassword);
                              },
                            ),
                            filled: true,
                            fillColor: AdminColors.getCardTinted(isDark),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AdminRadii.md),
                              borderSide: BorderSide(color: AdminColors.getBorder(isDark)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AdminRadii.md),
                              borderSide: BorderSide(color: AdminColors.getBorder(isDark)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AdminRadii.md),
                              borderSide: const BorderSide(color: AdminColors.primary, width: 1.5),
                            ),
                          ),
                        ),

                        // Error Banner
                        if (errorMsg.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: AdminColors.dangerSoft,
                              borderRadius: BorderRadius.circular(AdminRadii.md),
                              border: Border.all(color: AdminColors.danger.withOpacity(0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline_rounded, color: AdminColors.danger, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    errorMsg,
                                    style: const TextStyle(
                                      color: AdminColors.danger,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 28),

                        // Sign In Action Button
                        AdminActionButton(
                          label: 'Sign In to Dashboard',
                          icon: Icons.login_rounded,
                          isLoading: isLoading,
                          onPressed: _login,
                          variant: ButtonVariant.primary,
                        ),
                        const SizedBox(height: 16),

                        // Back to Home Ghost Link
                        TextButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: Icon(
                            Icons.arrow_back_rounded,
                            size: 16,
                            color: AdminColors.getTextSecondary(isDark),
                          ),
                          label: Text(
                            'Back to User Home',
                            style: AdminTextStyles.labelSm(
                              isDark,
                              color: AdminColors.getTextSecondary(isDark),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Security Footer Badge
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.security_rounded,
                              size: 14,
                              color: AdminColors.getTextMuted(isDark),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Encrypted Administrative Session',
                              style: AdminTextStyles.micro(isDark),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminNavEntry {
  final int index;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String? sectionHeader;

  const _AdminNavEntry({
    required this.index,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    this.sectionHeader,
  });
}

class AdminDashboardPage extends StatefulWidget {
  final String token;
  final Map<String, dynamic> user;

  const AdminDashboardPage({
    super.key,
    required this.token,
    required this.user,
  });

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  int _selectedIndex = 0;
  Key _analysisTabKey = UniqueKey();

  static const List<_AdminNavEntry> _adminNavEntries = [
    // MAIN
    _AdminNavEntry(
      index: 0,
      label: 'Dashboard',
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard_rounded,
      sectionHeader: 'Main',
    ),

    // ACADEMIC MANAGEMENT
    _AdminNavEntry(
      index: 1,
      label: 'Departments',
      icon: Icons.business_outlined,
      selectedIcon: Icons.business_rounded,
      sectionHeader: 'Academic Management',
    ),
    _AdminNavEntry(
      index: 2,
      label: 'Students',
      icon: Icons.people_alt_outlined,
      selectedIcon: Icons.people_alt_rounded,
    ),
    _AdminNavEntry(
      index: 12,
      label: 'Student Academics',
      icon: Icons.auto_stories_outlined,
      selectedIcon: Icons.auto_stories_rounded,
    ),
    _AdminNavEntry(
      index: 13,
      label: 'Staff Academics',
      icon: Icons.school_outlined,
      selectedIcon: Icons.school_rounded,
    ),
    _AdminNavEntry(
      index: 14,
      label: 'Timetable',
      icon: Icons.calendar_month_outlined,
      selectedIcon: Icons.calendar_month_rounded,
    ),
    _AdminNavEntry(
      index: 15,
      label: 'Halls & Labs',
      icon: Icons.domain_outlined,
      selectedIcon: Icons.domain_rounded,
    ),

    // USER & BIOMETRICS
    _AdminNavEntry(
      index: 5,
      label: 'Other Users',
      icon: Icons.apartment_outlined,
      selectedIcon: Icons.apartment_rounded,
      sectionHeader: 'User & Biometrics',
    ),
    _AdminNavEntry(
      index: 4,
      label: 'Face Requests',
      icon: Icons.face_outlined,
      selectedIcon: Icons.face_rounded,
    ),
    _AdminNavEntry(
      index: 10,
      label: 'Student Face Requests',
      icon: Icons.face_retouching_natural_outlined,
      selectedIcon: Icons.face_retouching_natural_rounded,
    ),
    _AdminNavEntry(
      index: 11,
      label: 'Live Locations',
      icon: Icons.location_on_outlined,
      selectedIcon: Icons.location_on_rounded,
    ),
    _AdminNavEntry(
      index: 26,
      label: 'Campus Alerts',
      icon: Icons.notification_important_outlined,
      selectedIcon: Icons.notification_important_rounded,
    ),

    // LEAVE & ON-DUTY
    _AdminNavEntry(
      index: 6,
      label: 'Leave Management',
      icon: Icons.event_note_outlined,
      selectedIcon: Icons.event_note_rounded,
      sectionHeader: 'Leave & On-Duty',
    ),
    _AdminNavEntry(
      index: 7,
      label: 'Casual Leave',
      icon: Icons.beach_access_outlined,
      selectedIcon: Icons.beach_access_rounded,
    ),
    _AdminNavEntry(
      index: 8,
      label: 'CCL Management',
      icon: Icons.more_time_outlined,
      selectedIcon: Icons.more_time_rounded,
    ),
    _AdminNavEntry(
      index: 9,
      label: 'Student Leave & OD',
      icon: Icons.assignment_turned_in_outlined,
      selectedIcon: Icons.assignment_turned_in_rounded,
    ),

    // INSTITUTIONAL OPERATIONS
    _AdminNavEntry(
      index: 19,
      label: 'Attendance Disputes',
      icon: Icons.edit_calendar_outlined,
      selectedIcon: Icons.edit_calendar_rounded,
      sectionHeader: 'Institutional Operations',
    ),
    _AdminNavEntry(
      index: 21,
      label: 'Substitute Allocator',
      icon: Icons.swap_horiz_outlined,
      selectedIcon: Icons.swap_horiz_rounded,
    ),
    _AdminNavEntry(
      index: 22,
      label: 'Holiday Calendar',
      icon: Icons.celebration_outlined,
      selectedIcon: Icons.celebration_rounded,
    ),
    _AdminNavEntry(
      index: 23,
      label: 'Student Grievances',
      icon: Icons.feedback_outlined,
      selectedIcon: Icons.feedback_rounded,
    ),
    _AdminNavEntry(
      index: 24,
      label: 'Security & 2FA Hub',
      icon: Icons.security_outlined,
      selectedIcon: Icons.security_rounded,
    ),

    // REPORTS & AUDIT LOGS
    _AdminNavEntry(
      index: 3,
      label: 'Analysis',
      icon: Icons.analytics_outlined,
      selectedIcon: Icons.analytics_rounded,
      sectionHeader: 'Reports & Audit Logs',
    ),
    _AdminNavEntry(
      index: 16,
      label: 'Attendance Log',
      icon: Icons.history_edu_outlined,
      selectedIcon: Icons.history_edu_rounded,
    ),
    _AdminNavEntry(
      index: 17,
      label: 'Student Log',
      icon: Icons.person_search_outlined,
      selectedIcon: Icons.person_search_rounded,
    ),
    _AdminNavEntry(
      index: 18,
      label: 'Class Sessions',
      icon: Icons.playlist_add_check_circle_outlined,
      selectedIcon: Icons.playlist_add_check_circle_rounded,
    ),
    _AdminNavEntry(
      index: 20,
      label: 'System Reports & Export',
      icon: Icons.analytics_outlined,
      selectedIcon: Icons.analytics_rounded,
    ),

    // SYSTEM & SETTINGS
    _AdminNavEntry(
      index: 25,
      label: 'Settings',
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings_rounded,
      sectionHeader: 'System',
    ),
  ];

  final List<Widget> _pages = [];
  final List<String> _titles = [
    'Dashboard',
    'Departments',
    'Students',
    'Analysis',
    'Face Requests',
    'Other User Departments',
    'Leave Management',
    'Casual Leave',
    'CCL Management',
    'Student Leave & OD',
    'Student Face Requests',
    'Live Locations',
    'Student Academics',
    'Staff Academics',
    'Timetable',
    'Halls & Labs',
    'Attendance Log',
    'Student Log',
    'Class Sessions',
    'Attendance Regularisation & Disputes',
    'Institutional Reports & Analytics',
    'Substitute Faculty Management',
    'Academic Holiday Calendar',
    'Student Grievances & Feedback',
    'Security & Session Control',
    'Settings',
    'Campus Movement Warnings',
  ];


  @override
  void initState() {
    super.initState();
    _pages.addAll([
      DashboardTab(token: widget.token, user: widget.user),
      DepartmentsTab(token: widget.token, user: widget.user),
      StudentManagementTab(
        token: widget.token,
        user: widget.user,
        isAdmin: true,
        onNavigateToTab: (idx) => setState(() => _selectedIndex = idx),
      ),
      AnalysisTab(token: widget.token),
      AdminFaceRequestsTab(token: widget.token),
      OtherStaffAttendanceTab(token: widget.token),
      AdminLeaveManagement(token: widget.token),
      CLManagementPage(token: widget.token),
      CCLManagementPage(token: widget.token),
      StudentLeaveODManagementTab(
        token: widget.token,
        user: widget.user,
        isAdmin: true,
      ),
      StudentFaceRequestsManagementTab(
        token: widget.token,
        user: widget.user,
        isAdmin: true,
        isHod: false,
        isStaff: false,
      ),
      LiveLocationsTab(token: widget.token),
      StudentAcademicsSettingsTab(token: widget.token, user: widget.user),
      AcademicsSettingsPage(token: widget.token, showAppBar: false),
      AcademicScheduleTab(
        token: widget.token,
        userRole: 'admin',
        userDept: 'CSE',
      ),
      VenueManagementView(
        token: widget.token,
        userRole: 'admin',
        userDept: 'GLOBAL',
        currentSelectedDept: 'ALL',
      ),
      AttendanceLogTab(token: widget.token, user: widget.user),
      StudentAttendanceLogWidget(
        token: widget.token,
        user: widget.user,
        isAdmin: true,
      ),
      ClassSessionHistoryWidget(
        token: widget.token,
        user: widget.user,
        isHod: false,
      ),
      AttendanceCorrectionsPage(
        token: widget.token,
        user: widget.user,
        isAdminOrHod: true,
      ),
      SystemReportsPage(
        token: widget.token,
        user: widget.user,
      ),
      SubstituteManagementPage(
        token: widget.token,
        user: widget.user,
        isAdminOrHod: true,
      ),
      HolidayCalendarPage(
        token: widget.token,
        isAdmin: true,
      ),
      StudentGrievancePage(
        token: widget.token,
        user: widget.user,
        isAdmin: true,
      ),
      SecurityHubPage(
        token: widget.token,
        user: widget.user,
      ),
      SettingsTab(token: widget.token),
      CampusMovementAlertsTab(token: widget.token, user: widget.user),
    ]);
  }


  void _logout() async {
    await sessionService.clearSession();
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaSize = MediaQuery.of(context).size;
    final width = mediaSize.width;
    final height = mediaSize.height;

    // Guard against collapsed/minimized window states (e.g. desktop minimize to taskbar)
    if (width < 50 || height < 50) {
      return const SizedBox.shrink();
    }

    final useDrawerNavigation = width < 768; // Mobile & small tablets
    final shouldExtendRail = width >= AdminBreakpoints.xxl; // Desktop 1280dp+
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget currentPage = _selectedIndex == 3
        ? AnalysisTab(key: _analysisTabKey, token: widget.token)
        : (_selectedIndex >= 0 && _selectedIndex < _pages.length
            ? _pages[_selectedIndex]
            : (_pages.isNotEmpty ? _pages.first : const SizedBox.shrink()));

    Widget pageBody = Stack(
      children: [
        // Background Ambient Mesh Orbs
        Positioned(
          top: -120,
          left: -120,
          child: Container(
            width: 400,
            height: 400,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AdminColors.primary.withOpacity(isDark ? 0.18 : 0.08),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -150,
          right: -150,
          child: Container(
            width: 500,
            height: 500,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AdminColors.rose.withOpacity(isDark ? 0.15 : 0.05),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        
        // Active Tab Page View
        Positioned.fill(
          child: RefreshIndicator(
            onRefresh: () async {
              setState(() {
                if (_selectedIndex == 3) {
                  _analysisTabKey = UniqueKey();
                } else {
                  _pages.clear();
                  _pages.addAll([
                    DashboardTab(token: widget.token, user: widget.user),
                    DepartmentsTab(token: widget.token, user: widget.user),
                    StudentManagementTab(
                      token: widget.token,
                      user: widget.user,
                      isAdmin: true,
                      onNavigateToTab: (idx) => setState(() => _selectedIndex = idx),
                    ),
                    AnalysisTab(token: widget.token),
                    AdminFaceRequestsTab(token: widget.token),
                    OtherStaffAttendanceTab(token: widget.token),
                    AdminLeaveManagement(token: widget.token),
                    CLManagementPage(token: widget.token),
                    CCLManagementPage(token: widget.token),
                    StudentLeaveODManagementTab(
                      token: widget.token,
                      user: widget.user,
                      isAdmin: true,
                    ),
                    StudentFaceRequestsManagementTab(
                      token: widget.token,
                      user: widget.user,
                      isAdmin: true,
                      isHod: false,
                      isStaff: false,
                    ),
                    LiveLocationsTab(token: widget.token),
                    StudentAcademicsSettingsTab(token: widget.token, user: widget.user),
                    AcademicsSettingsPage(token: widget.token, showAppBar: false),
                    AcademicScheduleTab(
                      token: widget.token,
                      userRole: 'admin',
                      userDept: 'CSE',
                    ),
                    VenueManagementView(
                      token: widget.token,
                      userRole: 'admin',
                      userDept: 'GLOBAL',
                      currentSelectedDept: 'ALL',
                    ),
                    AttendanceLogTab(token: widget.token, user: widget.user),
                    StudentAttendanceLogWidget(
                      token: widget.token,
                      user: widget.user,
                      isAdmin: true,
                    ),
                    ClassSessionHistoryWidget(
                      token: widget.token,
                      user: widget.user,
                      isHod: false,
                    ),
                    AttendanceCorrectionsPage(
                      token: widget.token,
                      user: widget.user,
                      isAdminOrHod: true,
                    ),
                    SystemReportsPage(
                      token: widget.token,
                      user: widget.user,
                    ),
                    SubstituteManagementPage(
                      token: widget.token,
                      user: widget.user,
                      isAdminOrHod: true,
                    ),
                    HolidayCalendarPage(
                      token: widget.token,
                      isAdmin: true,
                    ),
                    StudentGrievancePage(
                      token: widget.token,
                      user: widget.user,
                      isAdmin: true,
                    ),
                    SecurityHubPage(
                      token: widget.token,
                      user: widget.user,
                    ),
                    SettingsTab(token: widget.token),
                    CampusMovementAlertsTab(token: widget.token, user: widget.user),
                  ]);

                }
              });
              await Future.delayed(const Duration(milliseconds: 100));
            },
            color: AdminColors.primary,
            child: currentPage,
          ),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: AdminColors.getSurface(isDark),
      appBar: AppBar(
        centerTitle: false,
        title: Text(
          (_selectedIndex >= 0 && _selectedIndex < _titles.length)
              ? _titles[_selectedIndex]
              : 'Admin Dashboard',
          style: (width < 600
                  ? AdminTextStyles.titleMd(isDark)
                  : AdminTextStyles.titleLg(isDark))
              .copyWith(fontWeight: FontWeight.w700),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        backgroundColor: AdminColors.getCard(isDark),
        elevation: 0,
        scrolledUnderElevation: 0.5,
        leading: useDrawerNavigation
            ? Builder(
                builder: (context) => FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AdminColors.getCardTinted(isDark),
                      borderRadius: BorderRadius.circular(AdminRadii.md),
                    ),
                    child: IconButton(
                      icon: Icon(
                        Icons.menu_rounded,
                        color: AdminColors.getTextPrimary(isDark),
                        size: 20,
                      ),
                      onPressed: () => Scaffold.of(context).openDrawer(),
                      tooltip: 'Menu',
                    ),
                  ),
                ),
              )
            : null,
        actions: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Refresh button for Analysis tab
                if (_selectedIndex == 3)
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: () {
                      setState(() {
                        _analysisTabKey = UniqueKey();
                      });
                    },
                    tooltip: 'Refresh Analysis',
                  ),

                // Logout Action Button
                Container(
                  margin: const EdgeInsets.only(right: 12, left: 4),
                  decoration: BoxDecoration(
                    color: AdminColors.dangerSoft,
                    borderRadius: BorderRadius.circular(AdminRadii.md),
                  ),
                  child: IconButton(
                    icon: const Icon(
                      Icons.logout_rounded,
                      color: AdminColors.danger,
                      size: 20,
                    ),
                    onPressed: _logout,
                    tooltip: 'Logout',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      drawer: useDrawerNavigation ? _buildDrawer(context) : null,
      body: SafeArea(
        child: useDrawerNavigation
            ? pageBody
            : Row(
                children: [
                  // Desktop / Tablet Custom Sidebar Navigation Rail
                  Container(
                    width: AdminBreakpoints.navRailWidth(width),
                    color: AdminColors.getCard(isDark),
                    child: Column(
                      children: [
                        // Extended Header Info (when wide desktop)
                        if (shouldExtendRail) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                                    ),
                                    borderRadius: BorderRadius.circular(AdminRadii.md),
                                  ),
                                  child: const Icon(
                                    Icons.admin_panel_settings_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'VisionGate',
                                        style: AdminTextStyles.titleMd(isDark),
                                      ),
                                      Text(
                                        'Admin Panel',
                                        style: AdminTextStyles.micro(isDark),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Divider(color: AdminColors.getBorder(isDark), height: 1),
                        ],
                        Expanded(
                          child: ListView.builder(
                            padding: EdgeInsets.symmetric(
                              horizontal: shouldExtendRail ? 10 : 6,
                              vertical: 8,
                            ),
                            itemCount: _adminNavEntries.length,
                            itemBuilder: (context, index) {
                              final item = _adminNavEntries[index];
                              final isSelected = _selectedIndex == item.index;

                              Widget? headerWidget;
                              if (item.sectionHeader != null) {
                                if (shouldExtendRail) {
                                  headerWidget = Padding(
                                    padding: const EdgeInsets.only(
                                      left: 10,
                                      right: 10,
                                      top: 14,
                                      bottom: 6,
                                    ),
                                    child: Text(
                                      item.sectionHeader!.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.8,
                                        color: AdminColors.getTextMuted(isDark),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                } else {
                                  headerWidget = Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 6),
                                    child: Divider(
                                      color: AdminColors.getBorder(isDark),
                                      thickness: 1,
                                      indent: 8,
                                      endIndent: 8,
                                    ),
                                  );
                                }
                              }

                              final itemTile = shouldExtendRail
                                  ? Container(
                                      margin: const EdgeInsets.symmetric(vertical: 2),
                                      child: Material(
                                        color: isSelected
                                            ? AdminColors.primary.withValues(alpha: isDark ? 0.2 : 0.1)
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(10),
                                        child: InkWell(
                                          onTap: () => setState(() => _selectedIndex = item.index),
                                          borderRadius: BorderRadius.circular(10),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 9,
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  isSelected ? item.selectedIcon : item.icon,
                                                  color: isSelected
                                                      ? AdminColors.primary
                                                      : AdminColors.getTextMuted(isDark),
                                                  size: 19,
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Text(
                                                    item.label,
                                                    style: TextStyle(
                                                      fontSize: 12.5,
                                                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                                      color: isSelected
                                                          ? AdminColors.primary
                                                          : (isDark ? Colors.white70 : Colors.grey.shade800),
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                  : Container(
                                      margin: const EdgeInsets.symmetric(vertical: 2),
                                      child: Tooltip(
                                        message: item.label,
                                        preferBelow: false,
                                        child: Material(
                                          color: isSelected
                                              ? AdminColors.primary.withValues(alpha: isDark ? 0.25 : 0.12)
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(10),
                                          child: InkWell(
                                            onTap: () => setState(() => _selectedIndex = item.index),
                                            borderRadius: BorderRadius.circular(10),
                                            child: SizedBox(
                                              width: 48,
                                              height: 42,
                                              child: Icon(
                                                isSelected ? item.selectedIcon : item.icon,
                                                color: isSelected
                                                    ? AdminColors.primary
                                                    : AdminColors.getTextMuted(isDark),
                                                size: 20,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    );

                              if (headerWidget != null) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    headerWidget,
                                    itemTile,
                                  ],
                                );
                              }
                              return itemTile;
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: AdminColors.getBorder(isDark),
                  ),
                  Expanded(child: pageBody),
                ],
              ),
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final String adminName = widget.user['name'] ?? 'System Admin';

    return Drawer(
      backgroundColor: AdminColors.getCard(isDark),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Drawer Gradient Header
          Container(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 20,
              bottom: 24,
              left: 20,
              right: 20,
            ),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: AdminShadows.sm,
                      ),
                      child: Center(
                        child: Text(
                          adminName.isNotEmpty ? adminName[0].toUpperCase() : 'A',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AdminColors.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            adminName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          const AdminBadge(
                            label: 'System Administrator',
                            color: Colors.white,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Drawer Nav Options with Categorized Section Sub-Headings
          for (final item in _adminNavEntries) ...[
            if (item.sectionHeader != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                child: Text(
                  item.sectionHeader!.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: AdminColors.getTextMuted(isDark),
                  ),
                ),
              ),
            _buildDrawerItem(
              item.index,
              item.selectedIcon,
              item.label,
              item.icon,
            ),
          ],


          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Divider(color: AdminColors.getBorder(isDark)),
          ),

          // Logout Action
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AdminColors.dangerSoft,
                borderRadius: BorderRadius.circular(AdminRadii.md),
              ),
              child: const Icon(
                Icons.logout_rounded,
                color: AdminColors.danger,
                size: 20,
              ),
            ),
            title: const Text(
              'Sign Out',
              style: TextStyle(
                color: AdminColors.danger,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            onTap: () {
              Navigator.pop(context);
              _logout();
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildDrawerItem(
    int index,
    IconData selectedIcon,
    String label,
    IconData unselectedIcon,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSelected = _selectedIndex == index;
    const accent = AdminColors.primary;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: isSelected
            ? accent.withValues(alpha: isDark ? 0.2 : 0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          setState(() => _selectedIndex = index);
          Navigator.pop(context);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? accent
                      : (isDark
                            ? const Color(0xFF1C1C1E)
                            : Colors.grey.shade100),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isSelected ? selectedIcon : unselectedIcon,
                  color: isSelected
                      ? Colors.white
                      : (isDark ? Colors.white60 : Colors.grey.shade600),
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.w500,
                    color: isSelected
                        ? accent
                        : (isDark ? Colors.white : Colors.grey.shade700),
                    fontSize: 15,
                  ),
                ),
              ),
              if (isSelected)
                const Icon(Icons.chevron_right, color: accent, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

// Admin Staff Management Tab
class AdminStaffTab extends StatefulWidget {
  final String token;

  const AdminStaffTab({super.key, required this.token});

  @override
  State<AdminStaffTab> createState() => _AdminStaffTabState();
}

class _AdminStaffTabState extends State<AdminStaffTab> {
  List<dynamic> staff = [];
  bool isLoading = true;
  String? selectedDept;
  List<String> departments = [];
  final _formKey = GlobalKey<FormState>();

  final usernameCtrl = TextEditingController();
  final passwordCtrl = TextEditingController();
  final nameCtrl = TextEditingController();
  String? selectedRole;

  @override
  void initState() {
    super.initState();
    fetchStaff();
  }

  @override
  void dispose() {
    usernameCtrl.dispose();
    passwordCtrl.dispose();
    nameCtrl.dispose();
    super.dispose();
  }

  Future<void> fetchStaff() async {
    setState(() => isLoading = true);
    try {
      // Fetch departments from backend (with caching - 15 minutes for slow networks)
      final deptResponse = await apiClient.get(
        '$API_URL/admin/departments',
        token: widget.token,
        cacheKey: 'admin_departments',
        cacheDuration: const Duration(minutes: 15),
      );

      List<String> deptList = [];
      if (deptResponse.statusCode == 200) {
        final deptData = jsonDecode(deptResponse.body);
        deptList =
            (deptData['departments'] as List)
                .map((d) => d['name'].toString())
                .toList()
              ..sort();
      }

      // Fetch staff (with caching - 3 minutes)
      final response = await apiClient.get(
        '$API_URL/admin/users?role=staff',
        token: widget.token,
        cacheKey: 'admin_staff_list',
        cacheDuration: const Duration(minutes: 3),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          staff = data['users'];
          // Use departments from backend, fallback to extracting from staff
          if (deptList.isNotEmpty) {
            departments = deptList;
          } else {
            // Extract unique departments from staff if API fails
            final depts = <String>{};
            for (var s in staff) {
              if (s['dept'] != null && s['dept'].toString().isNotEmpty) {
                depts.add(s['dept'].toString());
              }
            }
            departments = depts.toList()..sort();
          }
          if (departments.isNotEmpty && selectedDept == null) {
            selectedDept = departments.first;
          }
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${cleanAdminErrorMessage(e)}')));
    } finally {
      setState(() => isLoading = false);
    }
  }

  List<dynamic> get filteredStaff {
    if (selectedDept == null) return staff;
    return staff.where((s) => s['dept'] == selectedDept).toList();
  }

  void _registerStaffFace(Map<String, dynamic> member) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FaceRegistrationWidget(
          token: widget.token,
          role: 'staff',
          initialRegNo: member['reg_no'],
          initialName: member['name'],
          initialDept: member['dept'],
          registerEndpoint: '/admin/face/register',
          onSuccess: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Face registered successfully!')),
            );
            fetchStaff();
          },
        ),
      ),
    );
  }

  Future<void> _grantPermission(String regNo, String name) async {
    try {
      final response = await http.post(
        Uri.parse('$API_URL/admin/face/permission/$regNo'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Permission granted to $name')));
        fetchStaff();
      } else {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['detail'] ?? 'Failed to grant permission'),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${cleanAdminErrorMessage(e)}')));
    }
  }

  Future<void> _revokePermission(String regNo, String name) async {
    try {
      final response = await http.delete(
        Uri.parse('$API_URL/admin/face/permission/$regNo'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Permission revoked for $name')));
        fetchStaff();
      } else {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['detail'] ?? 'Failed to revoke permission'),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${cleanAdminErrorMessage(e)}')));
    }
  }

  Future<void> _toggleKioskPermission(String regNo, String name, bool currentStatus) async {
    try {
      final response = await http.post(
        Uri.parse('$API_URL/admin/staff/$regNo/kiosk-toggle'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json'
        },
      );
      if (response.statusCode == 200) {
        final newStatus = !currentStatus;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kiosk permission ${newStatus ? 'granted to' : 'revoked from'} $name')),
        );
        fetchStaff();
      } else {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['detail'] ?? 'Failed to toggle kiosk permission')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${cleanAdminErrorMessage(e)}')),
      );
    }
  }


  Future<void> _editStaff(Map<String, dynamic> staffMember) async {
    final nameCtrl = TextEditingController(text: staffMember['name']);
    final usernameCtrl = TextEditingController(text: staffMember['username']);
    String? selectedDept = staffMember['dept'];

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Staff'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: usernameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              if (departments.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.deepPurple),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButton<String>(
                    value: selectedDept,
                    isExpanded: true,
                    underline: const SizedBox(),
                    hint: const Text('Select Department'),
                    items: departments
                        .map(
                          (dept) =>
                              DropdownMenuItem(value: dept, child: Text(dept)),
                        )
                        .toList(),
                    onChanged: (value) {
                      selectedDept = value;
                    },
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context, {
                'name': nameCtrl.text,
                'username': usernameCtrl.text,
                'dept': selectedDept,
              });
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == null) return;

    // Call API to update staff
    try {
      final response = await http.put(
        Uri.parse('$API_URL/admin/users/${staffMember['id']}'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(result),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Staff updated successfully')),
        );
        fetchStaff();
      } else {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['detail'] ?? 'Failed to update staff')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${cleanAdminErrorMessage(e)}')));
    }
  }

  Future<void> deleteStaff(int staffId, String username) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Staff'),
        content: Text('Are you sure you want to delete $username?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final response = await http.delete(
        Uri.parse('$API_URL/admin/users/$staffId'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Staff deleted successfully')),
        );
        fetchStaff();
      } else {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['detail'] ?? 'Failed to delete staff')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${cleanAdminErrorMessage(e)}')));
    }
  }

  void _clearForm() {
    usernameCtrl.clear();
    passwordCtrl.clear();
    nameCtrl.clear();
    selectedRole = null;
  }

  Future<void> _showStaffAttendanceDetails(
    Map<String, dynamic> staffMember,
  ) async {
    final regNo = staffMember['reg_no'];
    final name = staffMember['name'];

    showDialog(
      context: context,
      builder: (context) =>
          _StaffAttendanceDialog(token: widget.token, regNo: regNo, name: name),
    );
  }

  Future<void> createStaff() async {
    if (!_formKey.currentState!.validate()) return;
    if (selectedRole == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a role')));
      return;
    }

    try {
      final response = await http.post(
        Uri.parse('$API_URL/admin/users/create'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'username': usernameCtrl.text,
          'password': passwordCtrl.text,
          'name': nameCtrl.text,
          'role': selectedRole,
          'dept': selectedDept ?? departments.first,
        }),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Staff created successfully')),
        );
        fetchStaff();
        _clearForm();
        Navigator.pop(context);
      } else {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['detail'] ?? 'Failed to create staff')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${cleanAdminErrorMessage(e)}')));
    }
  }

  void _showCreateStaffDialog() {
    selectedRole = 'staff';
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add New Staff'),
          content: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: usernameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Username',
                      prefixIcon: const Icon(Icons.person),
                      filled: true,
                      fillColor: Colors.grey[100],
                    ),
                    validator: Validators.validateUsername,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(
                        Validators.maxUsernameLength,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: passwordCtrl,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock),
                      filled: true,
                      fillColor: Colors.grey[100],
                    ),
                    obscureText: true,
                    validator: Validators.validatePassword,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(
                        Validators.maxPasswordLength,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Full Name',
                      prefixIcon: const Icon(Icons.text_fields),
                      filled: true,
                      fillColor: Colors.grey[100],
                    ),
                    validator: (v) =>
                        Validators.validateName(v, fieldName: 'Name'),
                    inputFormatters: [LengthLimitingTextInputFormatter(100)],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.deepPurple),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButton<String>(
                      value: selectedRole,
                      isExpanded: true,
                      underline: const SizedBox(),
                      hint: const Text('Select Role'),
                      items: ['staff', 'hod']
                          .map(
                            (role) => DropdownMenuItem(
                              value: role,
                              child: Text(role.toUpperCase()),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setDialogState(() => selectedRole = value);
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (departments.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.deepPurple),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButton<String>(
                        value: selectedDept ?? departments.first,
                        isExpanded: true,
                        underline: const SizedBox(),
                        hint: const Text('Select Department'),
                        items: departments
                            .map(
                              (dept) => DropdownMenuItem(
                                value: dept,
                                child: Text(dept),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          setState(() => selectedDept = value);
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _clearForm();
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: createStaff,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
              ),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Department selector
              if (departments.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.deepPurple),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButton<String>(
                    value: selectedDept,
                    hint: const Text('Select Department'),
                    isExpanded: true,
                    underline: const SizedBox(),
                    icon: const Icon(
                      Icons.arrow_drop_down,
                      color: Colors.deepPurple,
                    ),
                    items: departments.map((dept) {
                      final count = staff
                          .where((s) => s['dept'] == dept)
                          .length;
                      return DropdownMenuItem(
                        value: dept,
                        child: Text('$dept ($count staff)'),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() => selectedDept = value);
                    },
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (isMobile)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selectedDept != null
                          ? '$selectedDept Staff (${filteredStaff.length})'
                          : 'All Staff (${staff.length})',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: _showCreateStaffDialog,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.deepPurple,
                          ),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add Staff'),
                        ),
                        PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'upload') {
                              performBulkUpload(
                                context,
                                widget.token,
                                '${CollegeIPConfig.defaultURL}/admin/users/bulk-upload',
                                fetchStaff,
                              );
                            } else if (value == 'excel') {
                              downloadTemplateHelper(context, widget.token, 'users', 'excel');
                            } else if (value == 'json') {
                              downloadTemplateHelper(context, widget.token, 'users', 'json');
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'upload',
                              child: Row(
                                children: [
                                  Icon(Icons.upload_file, color: Colors.indigo),
                                  SizedBox(width: 8),
                                  Text('Upload File'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'excel',
                              child: Row(
                                children: [
                                  Icon(Icons.download, color: Colors.green),
                                  SizedBox(width: 8),
                                  Text('Download Excel Template'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'json',
                              child: Row(
                                children: [
                                  Icon(Icons.download, color: Colors.amber),
                                  SizedBox(width: 8),
                                  Text('Download JSON Template'),
                                ],
                              ),
                            ),
                          ],
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.indigo,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.upload_file, size: 18, color: Colors.white),
                                SizedBox(width: 8),
                                Text('Bulk Upload', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: fetchStaff,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Refresh'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.deepPurple,
                            side: const BorderSide(color: Colors.deepPurple),
                          ),
                        ),
                      ],
                    ),
                  ],
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        selectedDept != null
                            ? '$selectedDept Staff (${filteredStaff.length})'
                            : 'All Staff (${staff.length})',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _showCreateStaffDialog,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                      ),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add'),
                    ),
                    const SizedBox(width: 8),
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'upload') {
                          performBulkUpload(
                            context,
                            widget.token,
                            '${CollegeIPConfig.defaultURL}/admin/users/bulk-upload',
                            fetchStaff,
                          );
                        } else if (value == 'excel') {
                          downloadTemplateHelper(context, widget.token, 'users', 'excel');
                        } else if (value == 'json') {
                          downloadTemplateHelper(context, widget.token, 'users', 'json');
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'upload',
                          child: Row(
                            children: [
                              Icon(Icons.upload_file, color: Colors.indigo),
                              SizedBox(width: 8),
                              Text('Upload File'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'excel',
                          child: Row(
                            children: [
                              Icon(Icons.download, color: Colors.green),
                              SizedBox(width: 8),
                              Text('Download Excel Template'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'json',
                          child: Row(
                            children: [
                              Icon(Icons.download, color: Colors.amber),
                              SizedBox(width: 8),
                              Text('Download JSON Template'),
                            ],
                          ),
                        ),
                      ],
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.indigo,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.upload_file, size: 18, color: Colors.white),
                            SizedBox(width: 8),
                            Text('Bulk Upload', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: fetchStaff,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                      ),
                      icon: const Icon(Icons.refresh, color: Colors.white),
                    ),
                  ],
                ),
            ],
          ),
        ),
        Expanded(
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : filteredStaff.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.people_outline,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No staff members',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _showCreateStaffDialog,
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                        ),
                        icon: const Icon(Icons.add),
                        label: const Text('Add First Staff'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 8 : 16,
                    vertical: 8,
                  ),
                  itemCount: filteredStaff.length,
                  itemBuilder: (context, index) {
                    final member = filteredStaff[index];
                    final faceRegistered = member['face_registered'] == true;
                    final canReregister = member['can_reregister'] == true;
                    final kioskEnabled = member['kiosk_enabled'] == true;
                    return _StaffCard(
                      member: member,
                      faceRegistered: faceRegistered,
                      canReregister: canReregister,
                      kioskEnabled: kioskEnabled,
                      isMobile: isMobile,
                      onTap: () => _showStaffAttendanceDetails(member),
                      onRegisterFace: () => _registerStaffFace(member),
                      onTogglePermission: () {
                        if (canReregister) {
                          _revokePermission(member['reg_no'], member['name']);
                        } else {
                          _grantPermission(member['reg_no'], member['name']);
                        }
                      },
                      onToggleKioskPermission: () {
                        _toggleKioskPermission(member['reg_no'], member['name'], kioskEnabled);
                      },
                      onEdit: () => _editStaff(member),
                      onDelete: () =>
                          deleteStaff(member['id'], member['username']),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// Responsive Staff Card Widget
class _StaffCard extends StatelessWidget {
  final Map<String, dynamic> member;
  final bool faceRegistered;
  final bool canReregister;
  final bool kioskEnabled;
  final bool isMobile;
  final VoidCallback onTap;
  final VoidCallback onRegisterFace;
  final VoidCallback onTogglePermission;
  final VoidCallback onToggleKioskPermission;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const _StaffCard({
    required this.member,
    required this.faceRegistered,
    required this.canReregister,
    required this.kioskEnabled,
    required this.isMobile,
    required this.onTap,
    required this.onRegisterFace,
    required this.onTogglePermission,
    required this.onToggleKioskPermission,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    if (isMobile) {
      return _buildMobileCard(context);
    } else {
      return _buildDesktopCard(context);
    }
  }

  Widget _buildMobileCard(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row with avatar and name
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: faceRegistered
                        ? Colors.green.withOpacity(0.1)
                        : Colors.orange.withOpacity(0.1),
                    child: Icon(
                      faceRegistered ? Icons.check_circle : Icons.person,
                      color: faceRegistered ? Colors.green : Colors.deepPurple,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          member['name'] ?? 'Unknown',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          member['username'] ?? '',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Role badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: member['role'] == 'hod'
                          ? Colors.teal[100]
                          : Colors.orange[100],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      (member['role'] ?? 'staff').toString().toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: member['role'] == 'hod'
                            ? Colors.teal
                            : Colors.orange[800],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Info chips
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildChip(Icons.badge, member['reg_no'] ?? 'N/A'),
                  _buildChip(Icons.business, member['dept'] ?? 'N/A'),
                  if (member['face_registered'] == true)
                    _buildChip(
                      Icons.face,
                      'Face Registered',
                      color: Colors.green,
                    ),
                  if (member['can_reregister'] == true)
                    _buildChip(
                      Icons.refresh,
                      'Can Re-register',
                      color: Colors.orange,
                    ),
                  if (kioskEnabled)
                    _buildChip(
                      Icons.camera_front,
                      'Kiosk Mode',
                      color: Colors.blue,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: onTap,
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: const Text('Attendance'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.deepPurple,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: onRegisterFace,
                    icon: Icon(
                      faceRegistered
                          ? Icons.face_retouching_natural
                          : Icons.face,
                      size: 16,
                    ),
                    label: Text(
                      faceRegistered ? 'Update Face' : 'Register Face',
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: faceRegistered
                          ? Colors.green
                          : Colors.orange,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (value) {
                      if (value == 'edit') onEdit();
                      if (value == 'delete') onDelete();
                      if (value == 'permission') onTogglePermission();
                      if (value == 'kiosk') onToggleKioskPermission();
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'permission',
                        child: Row(
                          children: [
                            Icon(
                              canReregister ? Icons.block : Icons.check_circle,
                              size: 20,
                              color: canReregister ? Colors.red : Colors.green,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              canReregister
                                  ? 'Revoke Permission'
                                  : 'Grant Permission',
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'kiosk',
                        child: Row(
                          children: [
                            Icon(
                              kioskEnabled ? Icons.videocam_off : Icons.videocam,
                              size: 20,
                              color: kioskEnabled ? Colors.red : Colors.blue,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              kioskEnabled
                                  ? 'Revoke Kiosk'
                                  : 'Grant Kiosk',
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem(

                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 20, color: Colors.blue[700]),
                            const SizedBox(width: 8),
                            Text('Edit'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete,
                              size: 20,
                              color: Colors.red[700],
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Delete',
                              style: TextStyle(color: Colors.red[700]),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopCard(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: faceRegistered
              ? Colors.green.withOpacity(0.1)
              : Colors.orange.withOpacity(0.1),
          child: Icon(
            faceRegistered ? Icons.check_circle : Icons.person,
            color: faceRegistered ? Colors.green : Colors.deepPurple,
            size: 20,
          ),
        ),
        title: Text(member['name'] ?? 'Unknown'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(member['username'] ?? ''),
            Text(
              '${member['reg_no']} • ${member['dept']}',
              style: const TextStyle(fontSize: 12),
            ),
              Row(
                children: [
                  Icon(
                    faceRegistered ? Icons.face : Icons.face_outlined,
                    size: 14,
                    color: faceRegistered ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    faceRegistered ? 'Face Registered' : 'Face Not Registered',
                    style: TextStyle(
                      fontSize: 10,
                      color: faceRegistered ? Colors.green : Colors.orange,
                    ),
                  ),
                  if (kioskEnabled) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.camera_front, size: 14, color: Colors.blue),
                    const SizedBox(width: 4),
                    const Text(
                      'Kiosk Enabled',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.blue,
                      ),
                    ),
                  ]
                ],
              ),
            ],
          ),
          trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                faceRegistered ? Icons.refresh : Icons.add_a_photo,
                color: faceRegistered ? Colors.blue : Colors.green,
              ),
              onPressed: onRegisterFace,
              tooltip: faceRegistered ? 'Re-register face' : 'Register face',
            ),
            IconButton(
              icon: Icon(
                canReregister ? Icons.lock_open : Icons.lock,
                color: canReregister ? Colors.green : Colors.red,
              ),
              onPressed: onTogglePermission,
              tooltip: canReregister
                  ? 'Revoke re-register permission'
                  : 'Grant re-register permission',
            ),
            IconButton(
              icon: Icon(
                kioskEnabled ? Icons.videocam : Icons.videocam_off,
                color: kioskEnabled ? Colors.blue : Colors.grey,
              ),
              onPressed: onToggleKioskPermission,
              tooltip: kioskEnabled
                  ? 'Revoke kiosk permission'
                  : 'Grant kiosk permission',
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: member['role'] == 'hod'
                    ? Colors.teal[100]
                    : Colors.orange[100],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                member['role']?.toUpperCase() ?? '',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                  color: member['role'] == 'hod' ? Colors.teal : Colors.orange,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.blue),
              onPressed: onEdit,
              tooltip: 'Edit staff',
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(IconData icon, String label, {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (color ?? Colors.deepPurple).withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color ?? Colors.deepPurple),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color ?? Colors.deepPurple,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// Staff Attendance Dialog Widget
class _StaffAttendanceDialog extends StatefulWidget {
  final String token;
  final String regNo;
  final String name;

  const _StaffAttendanceDialog({
    required this.token,
    required this.regNo,
    required this.name,
  });

  @override
  State<_StaffAttendanceDialog> createState() => _StaffAttendanceDialogState();
}

class _StaffAttendanceDialogState extends State<_StaffAttendanceDialog> {
  List<dynamic> attendanceRecords = [];
  bool isLoading = true;
  DateTime? startDate;
  DateTime? endDate;
  Map<String, int> stats = {'present': 0, 'absent': 0, 'total': 0};
  Map<String, dynamic>? _attendanceResponseData;

  @override
  void initState() {
    super.initState();
    _loadDefaultDates();
  }

  Future<void> _loadDefaultDates() async {
    try {
      final response = await http.get(Uri.parse('$API_URL/academics/current'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final rawRanges = data['academic_ranges'] as List? ?? [];
        if (rawRanges.isNotEmpty && rawRanges[0]['start'] != null && mounted) {
          setState(() {
            startDate = DateTime.parse(rawRanges[0]['start']);
            endDate = DateTime.parse(rawRanges.last['end']);
          });
          fetchAttendance();
          return;
        }
        if (data['academic_year_start'] != null && mounted) {
          setState(() {
            startDate = DateTime.parse(data['academic_year_start']);
            endDate = DateTime.parse(data['academic_year_end']);
          });
          fetchAttendance();
          return;
        }
      }
    } catch (_) {}
    final now = DateTime.now();
    setState(() {
      startDate = DateTime(now.year, now.month, 1);
      endDate = now;
    });
    fetchAttendance();
  }

  // Quick select methods for common date ranges
  void _selectToday() {
    final now = DateTime.now();
    setState(() {
      startDate = now;
      endDate = now;
    });
    fetchAttendance();
  }

  void _selectThisWeek() {
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    setState(() {
      startDate = startOfWeek;
      endDate = now;
    });
    fetchAttendance();
  }

  void _selectThisMonth() {
    final now = DateTime.now();
    setState(() {
      startDate = DateTime(now.year, now.month, 1);
      endDate = now;
    });
    fetchAttendance();
  }

  void _selectLastMonth() {
    final now = DateTime.now();
    final lastMonth = DateTime(now.year, now.month - 1, 1);
    final lastDayOfLastMonth = DateTime(now.year, now.month, 0);
    setState(() {
      startDate = lastMonth;
      endDate = lastDayOfLastMonth;
    });
    fetchAttendance();
  }

  void _selectLast7Days() {
    final now = DateTime.now();
    setState(() {
      startDate = now.subtract(const Duration(days: 6));
      endDate = now;
    });
    fetchAttendance();
  }

  void _selectLast30Days() {
    final now = DateTime.now();
    setState(() {
      startDate = now.subtract(const Duration(days: 29));
      endDate = now;
    });
    fetchAttendance();
  }

  // Week navigation methods
  void _goToPreviousWeek() {
    if (startDate != null && endDate != null) {
      setState(() {
        startDate = startDate!.subtract(const Duration(days: 7));
        endDate = endDate!.subtract(const Duration(days: 7));
      });
      fetchAttendance();
    }
  }

  void _goToNextWeek() {
    final now = DateTime.now();
    if (startDate != null && endDate != null) {
      // Don't go beyond today
      final newEndDate = endDate!.add(const Duration(days: 7));
      if (newEndDate.isAfter(now)) {
        return;
      }
      setState(() {
        startDate = startDate!.add(const Duration(days: 7));
        endDate = newEndDate;
      });
      fetchAttendance();
    }
  }

  Future<void> _selectDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: now,
      initialDateRange: startDate != null && endDate != null
          ? DateTimeRange(start: startDate!, end: endDate!)
          : DateTimeRange(start: startDate ?? DateTime(now.year, now.month, 1), end: endDate ?? now),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(primary: Colors.deepPurple),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      // Validate date range
      if (picked.start.isAfter(picked.end)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Start date cannot be after end date'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Validate not future dates
      if (picked.end.isAfter(DateTime.now())) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Cannot select future dates'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      setState(() {
        startDate = picked.start;
        endDate = picked.end;
      });
      fetchAttendance();
    }
  }

  String _formatDate(DateTime date) {
    // For display in UI - dd/mm/yy format
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year.toString().substring(2)}';
  }

  // Format date for API - yyyy-mm-dd format (required by backend)
  String _formatDateForAPI(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> fetchAttendance() async {
    if (startDate == null || endDate == null) return;

    setState(() => isLoading = true);
    try {
      final url =
          '$API_URL/admin/attendance/staff?reg_no=${widget.regNo}&start_date=${_formatDateForAPI(startDate!)}&end_date=${_formatDateForAPI(endDate!)}';

      final response = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          attendanceRecords = data['attendance'] ?? [];
          _attendanceResponseData = data;
          _calculateStats();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${cleanAdminErrorMessage(e)}')));
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  void _calculateStats() {
    int present = 0;

    // Group by date to count unique days
    final Map<String, bool> uniqueDates = {};
    for (var record in attendanceRecords) {
      final timestamp = record['timestamp']?.toString() ?? '';
      if (timestamp.isNotEmpty) {
        // Handle both "2024-03-11 07:04:29" and "2024-03-11T07:04:29" formats
        final date = timestamp.contains(' ')
            ? timestamp.split(' ')[0]
            : (timestamp.contains('T') ? timestamp.split('T')[0] : timestamp);
        uniqueDates[date] = true;
      }
    }

    present = uniqueDates.length;
    // Use server-computed holiday-aware total/absent if available
    final int totalDays;
    final int absent;
    if (_attendanceResponseData != null &&
        _attendanceResponseData!['working_days'] != null) {
      totalDays = _attendanceResponseData!['working_days'] as int;
      absent = _attendanceResponseData!['absent_days'] as int? ?? 
               (totalDays - present).clamp(0, totalDays);
    } else {
      totalDays = (startDate != null && endDate != null)
          ? endDate!.difference(startDate!).inDays + 1
          : 0;
      absent = (totalDays - present).clamp(0, totalDays);
    }

    stats = {'present': present, 'absent': absent, 'total': present + absent};
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.deepPurple,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Attendance Details',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          widget.name,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Date range filter with week navigation
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Previous week button
                  IconButton(
                    onPressed: _goToPreviousWeek,
                    icon: const Icon(Icons.chevron_left),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.deepPurple.withValues(alpha: 0.1),
                      foregroundColor: Colors.deepPurple,
                    ),
                    tooltip: 'Previous Week',
                  ),
                  const SizedBox(width: 8),
                  // Date range selector
                  Expanded(
                    child: InkWell(
                      onTap: _selectDateRange,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.deepPurple),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.date_range, color: Colors.deepPurple),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Select Date Range',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    startDate != null && endDate != null
                                        ? '${_formatDate(startDate!)} - ${_formatDate(endDate!)}'
                                        : 'Tap to select dates',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.arrow_drop_down,
                              color: Colors.deepPurple,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Next week button
                  IconButton(
                    onPressed: _goToNextWeek,
                    icon: const Icon(Icons.chevron_right),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.deepPurple.withValues(alpha: 0.1),
                      foregroundColor: Colors.deepPurple,
                    ),
                    tooltip: 'Next Week',
                  ),
                ],
              ),
            ),

            // Quick select buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Quick Select',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _QuickSelectChip(
                          label: 'Today',
                          onTap: _selectToday,
                          color: Colors.deepPurple,
                        ),
                        const SizedBox(width: 8),
                        _QuickSelectChip(
                          label: 'This Week',
                          onTap: _selectThisWeek,
                          color: Colors.blue,
                        ),
                        const SizedBox(width: 8),
                        _QuickSelectChip(
                          label: 'This Month',
                          onTap: _selectThisMonth,
                          color: Colors.green,
                        ),
                        const SizedBox(width: 8),
                        _QuickSelectChip(
                          label: 'Last Month',
                          onTap: _selectLastMonth,
                          color: Colors.orange,
                        ),
                        const SizedBox(width: 8),
                        _QuickSelectChip(
                          label: 'Last 7 Days',
                          onTap: _selectLast7Days,
                          color: Colors.cyan,
                        ),
                        const SizedBox(width: 8),
                        _QuickSelectChip(
                          label: 'Last 30 Days',
                          onTap: _selectLast30Days,
                          color: Colors.indigo,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Stats cards
            if (!isLoading && stats['total']! > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _AttendanceStatCard(
                            label: 'Present',
                            value: stats['present'].toString(),
                            color: Colors.green,
                            icon: Icons.check_circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _AttendanceStatCard(
                            label: 'Absent',
                            value: stats['absent'].toString(),
                            color: Colors.red,
                            icon: Icons.cancel,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _AttendanceStatCard(
                            label: 'Total Days',
                            value: stats['total'].toString(),
                            color: Colors.blue,
                            icon: Icons.calendar_month,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 16),

            // Attendance list
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : attendanceRecords.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.event_busy,
                            size: 48,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No attendance records found',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: attendanceRecords.length,
                      itemBuilder: (context, index) {
                        final record = attendanceRecords[index];
                        final timestamp = record['timestamp']?.toString() ?? '';
                        // Handle both "2024-03-11 07:04:29" and "2024-03-11T07:04:29" formats
                        final datePart = timestamp.contains(' ')
                            ? timestamp.split(' ')[0]
                            : (timestamp.contains('T')
                                  ? timestamp.split('T')[0]
                                  : '');
                        final timePart = timestamp.contains(' ')
                            ? (timestamp.split(' ').length > 1
                                  ? timestamp.split(' ')[1]
                                  : '')
                            : (timestamp.contains('T')
                                  ? timestamp.split('T')[1]
                                  : '');

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.green.withOpacity(0.1),
                              child: const Icon(
                                Icons.check,
                                color: Colors.green,
                              ),
                            ),
                            title: Text(datePart),
                            subtitle: Text('Time: $timePart'),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Present',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // Close button
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                  ),
                  child: const Text('Close'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _AttendanceStatCard({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 400;
    final isMobile = screenWidth < 600;
    final iconSize = isSmallScreen ? 18.0 : (isMobile ? 20.0 : 22.0);
    final labelSize = isSmallScreen ? 13.0 : 14.0;
    final valueSize = isSmallScreen ? 26.0 : 28.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.7),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 15,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                top: 12,
                right: 12,
                child: Icon(
                  icon,
                  size: iconSize,
                  color: color.withOpacity(0.8),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: labelSize,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: valueSize,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : color,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Modern Attendance stats card widget
class ModernAttendanceStatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const ModernAttendanceStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 400;
    final isMobile = screenWidth < 600;
    final iconSize = isSmallScreen ? 18.0 : (isMobile ? 20.0 : 22.0);
    final labelSize = isSmallScreen ? 13.0 : 14.0;
    final valueSize = isSmallScreen ? 26.0 : 28.0;

    return AdminCard(
      padding: EdgeInsets.zero,
      child: Stack(
        children: [
          Positioned(
            top: 12,
            right: 12,
            child: Icon(
              icon,
              size: iconSize,
              color: color.withValues(alpha: 0.8),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AdminTextStyles.caption(isDark).copyWith(
                    fontSize: labelSize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: AdminTextStyles.h2(isDark).copyWith(
                    fontSize: valueSize,
                    color: isDark ? Colors.white : color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Admin Face Re-registration Requests Tab (Staff + Other Staff)
class AdminFaceRequestsTab extends StatefulWidget {
  final String token;
  const AdminFaceRequestsTab({super.key, required this.token});

  @override
  State<AdminFaceRequestsTab> createState() => _AdminFaceRequestsTabState();
}

class _AdminFaceRequestsTabState extends State<AdminFaceRequestsTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<dynamic> _staffRequests = [];
  List<dynamic> _otherStaffRequests = [];
  bool _isLoading = true;
  String _message = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadRequests();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadRequests() async {
    setState(() => _isLoading = true);
    try {
      final staffRes = await http.get(
        Uri.parse('$API_URL/admin/face/reregister/requests'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      final otherRes = await http.get(
        Uri.parse('$API_URL/admin/other_staff/face/reregister/requests'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (staffRes.statusCode == 200 && otherRes.statusCode == 200) {
        final staffData = jsonDecode(staffRes.body);
        final otherData = jsonDecode(otherRes.body);
        setState(() {
          _staffRequests = staffData['requests'] ?? [];
          _otherStaffRequests = otherData['requests'] ?? [];
          _isLoading = false;
        });
      } else {
        setState(() {
          _message = 'Failed to load requests';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _message = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _approve(String regNo, bool isOtherStaff) async {
    try {
      final endpoint = isOtherStaff
          ? '$API_URL/admin/other_staff/face/reregister/approve/$regNo'
          : '$API_URL/admin/face/reregister/approve/$regNo';
      final response = await http.post(
        Uri.parse(endpoint),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Request approved'),
            backgroundColor: Colors.green,
          ),
        );
        _loadRequests();
      } else {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['detail'] ?? 'Failed'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _deny(String regNo, bool isOtherStaff) async {
    try {
      final endpoint = isOtherStaff
          ? '$API_URL/admin/other_staff/face/reregister/deny/$regNo'
          : '$API_URL/admin/face/reregister/deny/$regNo';
      final response = await http.post(
        Uri.parse('$endpoint?reason=Denied+by+Admin'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Request denied'),
            backgroundColor: Colors.red,
          ),
        );
        _loadRequests();
      } else {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['detail'] ?? 'Failed'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Widget _buildRequestList(List<dynamic> requests, bool isOtherStaff) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.white.withValues(alpha: 0.85);
    final borderClr = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.grey.shade200;

    if (requests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.teal.withValues(alpha: 0.12), Colors.cyan.withValues(alpha: 0.06)],
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.verified_rounded, size: 56, color: Colors.teal),
            ),
            const SizedBox(height: 16),
            Text(
              'All Clear!',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'No pending face re-registration requests',
              style: TextStyle(fontSize: 14, color: isDark ? Colors.white54 : Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: requests.length,
      itemBuilder: (context, index) {
        final req = requests[index];
        final name = (req['staff_name'] ?? '?').toString();
        final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
        final hodApproved = req['hod_approved'] == true;

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderClr),
            boxShadow: [
              BoxShadow(
                color: Colors.teal.withValues(alpha: isDark ? 0.06 : 0.08),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // Gradient avatar
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF00BFA5), Color(0xFF26C6DA)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.teal.withValues(alpha: 0.35),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              initial,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                              ),
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
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${req['staff_reg_no'] ?? ''} • ${req['dept'] ?? ''}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.white54 : Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Pending badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.orange.withValues(alpha: 0.18), Colors.amber.withValues(alpha: 0.12)],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
                          ),
                          child: const Text(
                            '⏳ Pending',
                            style: TextStyle(
                              color: Colors.orange,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (hodApproved) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.blue.withValues(alpha: 0.15), Colors.indigo.withValues(alpha: 0.08)],
                          ),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.blue.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.verified, color: Colors.blue, size: 15),
                            const SizedBox(width: 6),
                            Text(
                              'HOD Approved',
                              style: TextStyle(
                                color: isDark ? Colors.blue.shade200 : Colors.blue.shade700,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _approve(req['staff_reg_no'], isOtherStaff),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF00C853), Color(0xFF69F0AE)],
                                ),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.green.withValues(alpha: 0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                                  SizedBox(width: 6),
                                  Text(
                                    'Approve',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _deny(req['staff_reg_no'], isOtherStaff),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.red.withValues(alpha: 0.6),
                                  width: 1.5,
                                ),
                                color: Colors.red.withValues(alpha: isDark ? 0.12 : 0.06),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.cancel_rounded, color: Colors.red.shade400, size: 18),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Deny',
                                    style: TextStyle(
                                      color: Colors.red.shade400,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0A0A0F) : const Color(0xFFF0F4FF);
    final totalPending = _staffRequests.length + _otherStaffRequests.length;

    return Container(
      color: bg,
      child: Column(
        children: [
          // ── Premium Header Banner ──────────────────────────────────────
          Container(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF00695C), const Color(0xFF006064)]
                    : [const Color(0xFF00BFA5), const Color(0xFF26C6DA)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.teal.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.face_retouching_natural, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Face Re-registration',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        totalPending > 0
                            ? '$totalPending pending request${totalPending != 1 ? 's' : ''} awaiting review'
                            : 'All requests reviewed • All clear',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                  onPressed: _loadRequests,
                  tooltip: 'Refresh',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── Glassmorphic Tab Bar ───────────────────────────────────────
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.white.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.10)
                    : Colors.teal.withValues(alpha: 0.15),
              ),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF00BFA5), Color(0xFF26C6DA)],
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.teal.withValues(alpha: 0.4),
                    blurRadius: 8,
                  ),
                ],
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelColor: Colors.white,
              unselectedLabelColor: isDark ? Colors.white60 : Colors.teal.shade700,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              tabs: [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.people_rounded, size: 16),
                      const SizedBox(width: 6),
                      const Text('Staff'),
                      if (_staffRequests.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${_staffRequests.length}',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.group_rounded, size: 16),
                      const SizedBox(width: 6),
                      const Text('Other Staff'),
                      if (_otherStaffRequests.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${_otherStaffRequests.length}',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 4),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _message.isNotEmpty
                ? Center(child: Text(_message))
                : TabBarView(
                    controller: _tabController,
                    children: [
                      RefreshIndicator(
                        onRefresh: _loadRequests,
                        child: _buildRequestList(_staffRequests, false),
                      ),
                      RefreshIndicator(
                        onRefresh: _loadRequests,
                        child: _buildRequestList(_otherStaffRequests, true),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class DashboardTab extends StatefulWidget {
  final String token;
  final Map<String, dynamic> user;

  const DashboardTab({super.key, required this.token, required this.user});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  Map<String, dynamic>? data;
  bool isLoading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    fetchDashboard();
    _startAutoRefresh();
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _fetchRecentAttendance();
    });
  }

  Future<void> _fetchRecentAttendance() async {
    try {
      final response = await http.get(
        Uri.parse('$API_URL/admin/recent-attendance'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (response.statusCode == 200) {
        final newData = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            data?['recent_attendance'] = newData['recent_attendance'] ?? [];
            final existingStats =
                data?['stats'] as Map<String, dynamic>? ?? <String, dynamic>{};
            final newStats =
                newData['stats'] as Map<String, dynamic>? ??
                <String, dynamic>{};
            data?['stats'] = <String, dynamic>{...existingStats, ...newStats};
          });
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> fetchDashboard() async {
    try {
      final response = await apiClient.get(
        '$API_URL/admin/dashboard',
        token: widget.token,
        cacheKey: 'admin_dashboard_${widget.token.hashCode}',
        cacheDuration: const Duration(minutes: 1),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          this.data = data;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${cleanAdminErrorMessage(e)}')));
    } finally {
      setState(() => isLoading = false);
    }
  }

  String _formatTimestamp(dynamic raw) {
    final ts = raw?.toString().trim() ?? '';
    if (ts.isEmpty) return '';
    
    DateTime? dt;
    if (ts.contains('T')) {
      dt = DateTime.tryParse(ts);
    } else {
      dt = DateTime.tryParse(ts.replaceAll(' ', 'T'));
    }

    String formatted = ts;
    if (ts.contains('T')) {
      final parts = ts.split('T');
      final date = parts[0];
      final time = parts[1].split('.').first;
      formatted = '$date $time';
    }

    if (dt != null) {
      final session = dt.hour < 13 ? 'FN' : 'AN';
      return '0.5 $session • $formatted';
    }
    return formatted;
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pagePadding = AdminBreakpoints.pagePadding(screenWidth);

    if (isLoading) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(pagePadding),
        child: const Column(
          children: [
            AdminShimmerLoader(height: 120, borderRadius: AdminRadii.xl),
            SizedBox(height: 16),
            AdminShimmerLoader(height: 180, borderRadius: AdminRadii.lg),
            SizedBox(height: 16),
            AdminShimmerLoader(height: 240, borderRadius: AdminRadii.lg),
          ],
        ),
      );
    }

    final stats = data?['stats'] ?? {};
    final recentAttendance = data?['recent_attendance'] ?? [];

    return SingleChildScrollView(
      padding: EdgeInsets.all(pagePadding),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: AdminBreakpoints.maxContentWidth(screenWidth),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Hero Welcome Card
              AdminGradientCard(
                gradientColors: const [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(AdminRadii.md),
                      ),
                      child: const Icon(
                        Icons.waving_hand_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Welcome back,',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 8),
                              AdminBadge(
                                label: widget.user['role']?.toString().toUpperCase() ?? 'ADMIN',
                                color: Colors.white,
                                icon: Icons.shield_rounded,
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.user['name'] ?? 'Admin',
                            style: TextStyle(
                              fontSize: screenWidth < AdminBreakpoints.sm ? 18 : 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Daily Thirukkural Banner
              const ThirukkuralBanner(),
              const SizedBox(height: 20),



              // Section Header
              const AdminSectionHeader(
                title: 'System Statistics',
                subtitle: 'Real-time overview of staff attendance & status',
                icon: Icons.analytics_rounded,
              ),
              const SizedBox(height: 8),

              // Statistics Bento Grid (2x2 grid on mobile, 4 columns on desktop)
              GridView.count(
                crossAxisCount: AdminBreakpoints.statGridColumns(screenWidth),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: screenWidth < AdminBreakpoints.lg ? 1.65 : 1.6,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                children: [
                  ModernStatCard(
                    icon: Icons.people_rounded,
                    title: 'Total Users',
                    value: stats['total_users']?.toString() ?? '0',
                    color: const Color(0xFF6366F1),
                  ),
                  ModernStatCard(
                    icon: Icons.business_rounded,
                    title: 'Departments',
                    value: stats['total_departments']?.toString() ?? '0',
                    color: const Color(0xFF10B981),
                  ),
                  ModernStatCard(
                    icon: Icons.check_circle_rounded,
                    title: 'Present Today',
                    value: stats['today_attendance']?.toString() ?? '0',
                    color: const Color(0xFFEC4899),
                  ),
                  _SystemStatusCard(token: widget.token),
                ],
              ),
              const SizedBox(height: 24),

              // Today's Attendance Breakdown Pie Chart
              AdminCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AdminSectionHeader(
                      title: "Today's Attendance Breakdown",
                      subtitle: "Distribution of full day, half day, absent, and leave staff",
                      icon: Icons.pie_chart_rounded,
                    ),
                    const SizedBox(height: 12),
                    AttendancePieChart(
                      fullDay:  (stats['today_full_day']   as num? ?? 0).toInt(),
                      halfDay:  (stats['today_half_day']   as num? ?? 0).toInt(),
                      absent:   (stats['today_absent_das'] as num? ?? 0).toInt(),
                      onLeave:  (stats['today_leave']      as num? ?? 0).toInt(),
                      centerLabel: 'Staff',
                      centerSpaceRadius: 44,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Student Academic Session & Calendar Pulse Card
              _StudentAcademicPulseCard(token: widget.token),
              const SizedBox(height: 24),

              // Recent Attendance Feed
              AdminCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AdminSectionHeader(
                      title: 'Recent Attendance',
                      subtitle: 'Live faculty check-ins and status updates',
                      icon: Icons.history_rounded,
                      trailing: IconButton(
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                        onPressed: fetchDashboard,
                        tooltip: 'Refresh Attendance',
                        color: AdminColors.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    recentAttendance.isEmpty
                        ? const AdminEmptyState(
                            icon: Icons.history_rounded,
                            title: 'No Recent Attendance',
                            message: 'Staff check-ins will appear here live once recorded.',
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: recentAttendance.length,
                            separatorBuilder: (context, index) => Divider(
                              height: 1,
                              indent: 54,
                              color: AdminColors.getBorder(isDark),
                            ),
                            itemBuilder: (context, index) {
                              final record = recentAttendance[index];
                              final when = _formatTimestamp(record['timestamp']);
                              final isAbsent = record['status'] == 'Absent' ||
                                  record['punch_type'] == 'absent' ||
                                  record['punch_type'] == 'system_marked_absent' ||
                                  record['is_absent'] == true;
                              final punchType = record['punch_type'] as String? ?? (isAbsent ? 'absent' : 'check_in');
                              final isCheckOut = punchType == 'check_out';
                              final punchColor = isAbsent
                                  ? AdminColors.danger
                                  : isCheckOut
                                      ? AdminColors.warning
                                      : AdminColors.success;
                              final punchLabel = isAbsent
                                  ? 'Absent'
                                  : isCheckOut
                                      ? 'Check Out'
                                      : 'Check In';
                              final punchIcon = isAbsent
                                  ? Icons.cancel_rounded
                                  : isCheckOut
                                      ? Icons.logout_rounded
                                      : Icons.login_rounded;

                              final regNo = record['reg_no'] ?? record['regNo'] ?? '';
                              final dept = record['dept'] ?? record['department'] ?? '';
                              final regAndDept = [if (regNo.toString().isNotEmpty) regNo, if (dept.toString().isNotEmpty) dept].join(' • ');
                              final reason = record['absent_reason'] ?? record['reason'] ?? (isAbsent ? 'System marked absent' : null);
                              final session = record['session_label'] ?? record['session'] ?? record['session_type'];
                              final timeText = (session != null && session.toString().isNotEmpty) ? '$session • $when' : when;

                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
                                leading: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: punchColor.withValues(alpha: 0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    punchIcon,
                                    size: 20,
                                    color: punchColor,
                                  ),
                                ),
                                title: Text(
                                  record['name'] ?? 'Unknown',
                                  style: AdminTextStyles.bodyMd(isDark).copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  isAbsent
                                      ? '$regAndDept\nReason: $reason'
                                      : regAndDept,
                                  style: AdminTextStyles.labelSm(isDark),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: isAbsent ? 2 : 1,
                                ),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    AdminBadge(
                                      label: punchLabel,
                                      color: punchColor,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      timeText,
                                      style: AdminTextStyles.micro(isDark),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

}


/// Modern responsive stat card with enterprise design system styling
class ModernStatCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color color;
  final String? subtitle;

  const ModernStatCard({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSmall = screenWidth < AdminBreakpoints.sm;

    return AdminCard(
      padding: EdgeInsets.symmetric(
        horizontal: isSmall ? 12.0 : 16.0,
        vertical: isSmall ? 10.0 : 14.0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  subtitle == null ? title : '$title • $subtitle',
                  style: AdminTextStyles.labelSm(isDark).copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: isSmall ? 12.0 : 13.0,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: EdgeInsets.all(isSmall ? 6 : 8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AdminRadii.md),
                ),
                child: Icon(icon, size: isSmall ? 16 : 18, color: color),
              ),
            ],
          ),
          Text(
            value,
            style: AdminTextStyles.displayLg(isDark).copyWith(
              fontSize: isSmall ? 22.0 : 28.0,
              fontWeight: FontWeight.bold,
              color: isDark ? AdminColors.dTextPrimary : color,
            ),
          ),
        ],
      ),
    );
  }
}

/// System Status Card - Shows system health and is clickable to view error logs
class _SystemStatusCard extends StatefulWidget {
  final String token;

  const _SystemStatusCard({required this.token});

  @override
  State<_SystemStatusCard> createState() => _SystemStatusCardState();
}

class _SystemStatusCardState extends State<_SystemStatusCard> {
  Map<String, dynamic>? systemStatus;
  bool isLoading = true;
  String status = 'loading';
  int errorCount = 0;

  @override
  void initState() {
    super.initState();
    fetchSystemStatus();
  }

  Future<void> fetchSystemStatus() async {
    try {
      final response = await http.get(
        Uri.parse('$API_URL/admin/system/status'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          systemStatus = data;
          status = data['status'] ?? 'unknown';
          errorCount = (data['errors'] as List?)?.length ?? 0;
          isLoading = false;
        });
      } else {
        setState(() {
          status = 'error';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        status = 'error';
        isLoading = false;
      });
    }
  }

  Color get statusColor {
    switch (status) {
      case 'healthy':
        return AdminColors.success;
      case 'warning':
        return AdminColors.warning;
      case 'error':
        return AdminColors.danger;
      default:
        return AdminColors.textMuted;
    }
  }

  IconData get statusIcon {
    switch (status) {
      case 'healthy':
        return Icons.check_circle_rounded;
      case 'warning':
        return Icons.warning_rounded;
      case 'error':
        return Icons.error_rounded;
      default:
        return Icons.help_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSmall = screenWidth < AdminBreakpoints.sm;

    return AdminCard(
      padding: EdgeInsets.symmetric(
        horizontal: isSmall ? 12.0 : 16.0,
        vertical: isSmall ? 10.0 : 14.0,
      ),
      onTap: () {
        if (systemStatus != null) {
          _showErrorLogsDialog(context);
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'System Status',
                  style: AdminTextStyles.labelSm(isDark).copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: isSmall ? 12.0 : 13.0,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: EdgeInsets.all(isSmall ? 6 : 8),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AdminRadii.md),
                ),
                child: Icon(statusIcon, size: isSmall ? 16 : 18, color: statusColor),
              ),
            ],
          ),
          isLoading
              ? const AdminShimmerLoader(height: 24, width: 70)
              : Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                        boxShadow: AdminShadows.glow(statusColor, opacity: 0.5),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      status.toUpperCase(),
                      style: AdminTextStyles.titleMd(isDark, color: statusColor).copyWith(
                        fontSize: isSmall ? 13.0 : 16.0,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
        ],
      ),
    );
  }

  void _showErrorLogsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _ErrorLogsDialog(token: widget.token),
    );
  }
}

// Error Logs Dialog
class _ErrorLogsDialog extends StatefulWidget {
  final String token;

  const _ErrorLogsDialog({required this.token});

  @override
  State<_ErrorLogsDialog> createState() => _ErrorLogsDialogState();
}

class _ErrorLogsDialogState extends State<_ErrorLogsDialog> {
  List<dynamic> logs = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchLogs();
  }

  Future<void> fetchLogs() async {
    try {
      final response = await http.get(
        Uri.parse('$API_URL/admin/system/logs?limit=50'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          logs = data['logs'] ?? [];
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red[700]),
          const SizedBox(width: 8),
          const Text('System Error Logs'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : logs.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle,
                      size: 48,
                      color: Colors.green[400],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No errors found',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                itemCount: logs.length,
                itemBuilder: (context, index) {
                  final log = logs[index];
                  final isMap = log is Map;
                  return ListTile(
                    leading: Icon(
                      (isMap ? log['type'] : null) == 'attendance_error'
                          ? Icons.person_off
                          : Icons.login,
                      color: Colors.red[400],
                    ),
                    title: Text((isMap ? log['message'] : null) ?? 'Unknown error'),
                    subtitle: Text(
                      '${(isMap ? log['timestamp'] : null) ?? ''} - ${(isMap ? log['type'] : null) ?? ''}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        TextButton(onPressed: fetchLogs, child: const Text('Refresh')),
      ],
    );
  }
}

/// Student Academic Session & Calendar Pulse Card on Admin Dashboard
class _StudentAcademicPulseCard extends StatefulWidget {
  final String token;
  const _StudentAcademicPulseCard({required this.token});

  @override
  State<_StudentAcademicPulseCard> createState() => _StudentAcademicPulseCardState();
}

class _StudentAcademicPulseCardState extends State<_StudentAcademicPulseCard> {
  Map<String, dynamic>? _stats;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchAcademicStats();
  }

  Future<void> _fetchAcademicStats() async {
    setState(() => _isLoading = true);
    final headers = {'Authorization': 'Bearer ${widget.token}'};
    final urlsToTry = [
      '$API_URL/api/v1/admin/student-academics/stats',
      '$API_URL/admin/student-academics/stats',
      '$API_URL/api/admin/student-academics/stats',
    ];

    for (final url in urlsToTry) {
      try {
        final res = await http.get(Uri.parse(url), headers: headers);
        if (res.statusCode == 200) {
          final body = jsonDecode(res.body);
          if (mounted) {
            final data = body is Map<String, dynamic>
                ? (body['data'] is Map ? Map<String, dynamic>.from(body['data']) : null)
                : null;
            if (data != null) {
              setState(() {
                _stats = data;
                _isLoading = false;
              });
              return;
            }
          }
        }
      } catch (_) {}
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeYear = _stats?['active_academic_year']?.toString() ?? '2026-2027';
    final activeRange = _stats?['active_range'] as Map<String, dynamic>?;
    final rangeName = _stats?['active_range_name']?.toString() ??
        activeRange?['name']?.toString() ??
        'Odd Semester (Active)';
    final targetDays = (_stats?['target_working_days'] as num?)?.toInt() ??
        (activeRange?['target_working_days'] as num?)?.toInt() ??
        90;
    final completedDays = (_stats?['completed_working_days'] as num?)?.toInt() ??
        (_stats?['working_days_elapsed'] as num?)?.toInt() ??
        0;
    final progressPct = (_stats?['term_progress_percentage'] as num?)?.toDouble() ??
        ((completedDays / (targetDays > 0 ? targetDays : 1)) * 100).clamp(0.0, 100.0);
    final holidays = _stats?['upcoming_holidays'] as List? ?? [];
    final nextHoliday = holidays.isNotEmpty ? holidays.first as Map<String, dynamic> : null;

    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AdminRadii.md),
                      ),
                      child: const Icon(Icons.school_rounded, color: Color(0xFF6366F1), size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Student Academic Session & Working Days',
                            style: AdminTextStyles.titleMd(isDark).copyWith(fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Academic Year $activeYear • $rangeName',
                            style: TextStyle(
                              fontSize: 12,
                              color: AdminColors.getTextSecondary(isDark),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 18),
                onPressed: _fetchAcademicStats,
                tooltip: 'Refresh Academic Pulse',
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_isLoading)
            const AdminShimmerLoader(height: 50, borderRadius: AdminRadii.md)
          else ...[
            // Progress Bar Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Instructional Term Progress',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$completedDays / $targetDays Working Days (${progressPct.toStringAsFixed(1)}%)',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF6366F1),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: (progressPct / 100).clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
              ),
            ),
            if (nextHoliday != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFFEF3C7).withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark ? Colors.amber.withValues(alpha: 0.3) : const Color(0xFFFDE68A),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.celebration_rounded, color: Colors.amber, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Upcoming Student Holiday: ${nextHoliday['title'] ?? 'Holiday'} (${nextHoliday['date'] ?? ''})',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.amber.shade200 : Colors.amber.shade900,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (nextHoliday['category'] != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${nextHoliday['category']}'.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.amber.shade200 : Colors.amber.shade900,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

// Departments Tab - Shows all departments with HOD and Staff
class DepartmentsTab extends StatefulWidget {
  final String token;
  final Map<String, dynamic>? user;

  const DepartmentsTab({super.key, required this.token, this.user});

  @override
  State<DepartmentsTab> createState() => _DepartmentsTabState();
}

class _DepartmentsTabState extends State<DepartmentsTab> {
  List<dynamic> departments = [];
  Map<String, dynamic> deptData = {};
  bool isLoading = true;
  Map<String, bool> expandedDepartments = {};
  static const Set<String> _excludedOtherUserDepartments = {
    'Administration',
    'Placement Staff',
    'Lab Technician',
    'System Admin',
    'Office Staff',
  };

  @override
  void initState() {
    super.initState();
    fetchDepartmentData();
  }

  Future<void> fetchDepartmentData() async {
    setState(() => isLoading = true);
    try {
      // Use non-cached request to ensure we get fresh data after rename
      final deptResponse = await http.get(
        Uri.parse('$API_URL/admin/departments'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );

      List<String> deptNames = [];
      if (deptResponse.statusCode == 200) {
        final deptData = jsonDecode(deptResponse.body);
        deptNames = (deptData['departments'] as List)
            .map((d) => d['name'].toString())
            .toList();
      } else {
        // No fallback - show error if API fails
        deptNames = [];
      }

      deptNames = deptNames
          .where((dept) => !_excludedOtherUserDepartments.contains(dept))
          .toList();

      // Fetch staff by department - use non-cached to get fresh data after rename
      final staffResponse = await http.get(
        Uri.parse('$API_URL/admin/users'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );

      if (staffResponse.statusCode == 200) {
        final staffData = jsonDecode(staffResponse.body);
        final users = staffData['users'] ?? [];

        for (String dept in deptNames) {
          this.deptData[dept] = {
            'hod': users
                .where((u) => u['dept'] == dept && u['role'] == 'hod')
                .toList(),
            'staff': users
                .where((u) => u['dept'] == dept && u['role'] == 'staff')
                .toList(),
          };
        }
      }

      setState(() => departments = deptNames);
    } catch (e) {
      print('[DepartmentsTab] Error: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${cleanAdminErrorMessage(e)}')));
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _createDepartment() async {
    final nameController = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create New Department'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Department Name',
            hintText: 'Enter department name',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, nameController.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (result == null || result.isEmpty) return;

    try {
      final response = await http.post(
        Uri.parse('$API_URL/admin/departments'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
        body: jsonEncode({'name': result}),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Department "$result" created successfully')),
        );
        fetchDepartmentData();
      } else {
        final error =
            jsonDecode(response.body)['detail'] ??
            'Failed to create department';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error)));
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${cleanAdminErrorMessage(e)}')));
    }
  }

  Future<void> _editDepartment(String oldName) async {
    final nameController = TextEditingController(text: oldName);

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Department'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Department Name',
            hintText: 'Enter new department name',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, nameController.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == null || result.isEmpty || result == oldName) return;

    try {
      final response = await http.put(
        Uri.parse('$API_URL/admin/departments/$oldName'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
        body: jsonEncode({'name': result}),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Department "$oldName" updated to "$result"')),
        );
        fetchDepartmentData();
      } else {
        final error =
            jsonDecode(response.body)['detail'] ??
            'Failed to update department';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error)));
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${cleanAdminErrorMessage(e)}')));
    }
  }

  Future<void> _deleteDepartment(String deptName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Department'),
        content: Text(
          'Are you sure you want to delete "$deptName"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final response = await http.delete(
        Uri.parse('$API_URL/admin/departments/$deptName'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Department "$deptName" deleted successfully'),
          ),
        );
        fetchDepartmentData();
      } else {
        final error =
            jsonDecode(response.body)['detail'] ??
            'Failed to delete department';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error)));
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${cleanAdminErrorMessage(e)}')));
    }
  }

  Future<void> deleteStaff(int staffId, String username) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Staff'),
        content: Text(
          'Are you sure you want to delete $username? This will also remove their face data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final response = await http.delete(
        Uri.parse('$API_URL/admin/users/$staffId'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Staff deleted successfully')),
        );
        fetchDepartmentData();
      } else {
        final error =
            jsonDecode(response.body)['detail'] ?? 'Failed to delete staff';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error)));
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${cleanAdminErrorMessage(e)}')));
    }
  }

  Future<void> deleteHOD(int hodId, String username) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete HOD'),
        content: Text(
          'Are you sure you want to delete $username? This will also remove their face data and they will no longer be HOD of this department.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final response = await http.delete(
        Uri.parse('$API_URL/admin/users/$hodId'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('HOD deleted successfully')),
        );
        fetchDepartmentData();
      } else {
        final error =
            jsonDecode(response.body)['detail'] ?? 'Failed to delete HOD';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error)));
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${cleanAdminErrorMessage(e)}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final pagePadding = AdminBreakpoints.pagePadding(screenWidth);
    final cardBg = isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.85);
    final borderClr = isDark ? Colors.white.withValues(alpha: 0.10) : Colors.deepPurple.withValues(alpha: 0.1);

    // All departments use the same uniform color gradient
    final palette = [
      [const Color(0xFF6C63FF), const Color(0xFF9C56B8)],
    ];

    if (isLoading) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(pagePadding),
        child: const Column(
          children: [
            AdminShimmerLoader(height: 100, borderRadius: AdminRadii.xl),
            SizedBox(height: 16),
            AdminShimmerLoader(height: 200, borderRadius: AdminRadii.lg),
          ],
        ),
      );
    }

    return Container(
      color: AdminColors.getSurface(isDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Premium Header ─────────────────────────────────────────────
          Container(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF3B0EAB), const Color(0xFF1A0078)]
                    : [const Color(0xFF6C63FF), const Color(0xFF9C56B8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.deepPurple.withValues(alpha: 0.35),
                  blurRadius: 22,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: isMobile
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.domain_rounded, color: Colors.white, size: 26),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Departments',
                                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  '${departments.length} department${departments.length != 1 ? "s" : ""} registered',
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.80), fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
                            onPressed: fetchDepartmentData,
                            tooltip: 'Refresh',
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.white.withValues(alpha: 0.15),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: _createDepartment,
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.add_rounded, color: Colors.white, size: 18),
                                    SizedBox(width: 4),
                                    Text('Add', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'upload') {
                                  performBulkUpload(
                                    context,
                                    widget.token,
                                    '${CollegeIPConfig.defaultURL}/admin/departments/bulk-upload',
                                    fetchDepartmentData,
                                  );
                                } else if (value == 'excel') {
                                  downloadTemplateHelper(context, widget.token, 'departments', 'excel');
                                } else if (value == 'json') {
                                  downloadTemplateHelper(context, widget.token, 'departments', 'json');
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'upload',
                                  child: Row(
                                    children: [
                                      Icon(Icons.upload_file, color: Colors.indigo),
                                      SizedBox(width: 8),
                                      Text('Upload File'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'excel',
                                  child: Row(
                                    children: [
                                      Icon(Icons.download, color: Colors.green),
                                      SizedBox(width: 8),
                                      Text('Download Excel Template'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'json',
                                  child: Row(
                                    children: [
                                      Icon(Icons.download, color: Colors.amber),
                                      SizedBox(width: 8),
                                      Text('Download JSON Template'),
                                    ],
                                  ),
                                ),
                              ],
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.upload_file_rounded, color: Colors.white, size: 18),
                                    SizedBox(width: 4),
                                    Text('Upload', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'excel') {
                                  downloadUsersHelper(context, widget.token, 'excel');
                                } else if (value == 'json') {
                                  downloadUsersHelper(context, widget.token, 'json');
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'excel',
                                  child: Row(
                                    children: [
                                      Icon(Icons.download, color: Colors.green),
                                      SizedBox(width: 8),
                                      Text('Download Users (Excel)'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'json',
                                  child: Row(
                                    children: [
                                      Icon(Icons.download, color: Colors.amber),
                                      SizedBox(width: 8),
                                      Text('Download Users (JSON)'),
                                    ],
                                  ),
                                ),
                              ],
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.download_rounded, color: Colors.white, size: 18),
                                    SizedBox(width: 4),
                                    Text('Users', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.domain_rounded, color: Colors.white, size: 26),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Departments',
                              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              '${departments.length} department${departments.length != 1 ? "s" : ""} registered',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.80), fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      // Add dept button
                      GestureDetector(
                        onTap: _createDepartment,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add_rounded, color: Colors.white, size: 18),
                              SizedBox(width: 4),
                              Text('Add', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Upload button
                      PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'upload') {
                            performBulkUpload(
                              context,
                              widget.token,
                              '${CollegeIPConfig.defaultURL}/admin/departments/bulk-upload',
                              fetchDepartmentData,
                            );
                          } else if (value == 'excel') {
                            downloadTemplateHelper(context, widget.token, 'departments', 'excel');
                          } else if (value == 'json') {
                            downloadTemplateHelper(context, widget.token, 'departments', 'json');
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'upload',
                            child: Row(
                              children: [
                                Icon(Icons.upload_file, color: Colors.indigo),
                                SizedBox(width: 8),
                                Text('Upload File'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'excel',
                            child: Row(
                              children: [
                                Icon(Icons.download, color: Colors.green),
                                SizedBox(width: 8),
                                Text('Download Excel Template'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'json',
                            child: Row(
                              children: [
                                Icon(Icons.download, color: Colors.amber),
                                SizedBox(width: 8),
                                Text('Download JSON Template'),
                              ],
                            ),
                          ),
                        ],
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.upload_file_rounded, color: Colors.white, size: 18),
                              SizedBox(width: 4),
                              Text('Upload', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Download Users button
                      PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'excel') {
                            downloadUsersHelper(context, widget.token, 'excel');
                          } else if (value == 'json') {
                            downloadUsersHelper(context, widget.token, 'json');
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'excel',
                            child: Row(
                              children: [
                                Icon(Icons.download, color: Colors.green),
                                SizedBox(width: 8),
                                Text('Download Users (Excel)'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'json',
                            child: Row(
                              children: [
                                Icon(Icons.download, color: Colors.amber),
                                SizedBox(width: 8),
                                Text('Download Users (JSON)'),
                              ],
                            ),
                          ),
                        ],
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.download_rounded, color: Colors.white, size: 18),
                              SizedBox(width: 4),
                              Text('Download Users', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
                        onPressed: fetchDepartmentData,
                        tooltip: 'Refresh',
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 12),

          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              itemCount: departments.length + 1,
              itemBuilder: (context, index) {
                // Item 0 is the Institutional Operations & Quick Hub
                if (index == 0) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1B4B).withValues(alpha: 0.5) : const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: const Color(0xFF6366F1).withValues(alpha: isDark ? 0.35 : 0.25),
                        width: 1.2,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.hub_rounded, color: Color(0xFF6366F1), size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Institutional Operations & Services',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: isDark ? Colors.white : const Color(0xFF1E1B4B),
                                    ),
                                  ),
                                  Text(
                                    'Direct access to regularisation approvals, reports export, substitutions, holidays, and security',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark ? Colors.white60 : Colors.indigo.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        LayoutBuilder(
                          builder: (ctx, constraints) {
                            final isNarrow = constraints.maxWidth < 750;
                            final adminUser = widget.user ?? const {'role': 'admin', 'name': 'Admin'};
                            final ops = [
                              {
                                'title': 'Dispute Approvals',
                                'desc': 'Review & regularise punches',
                                'icon': Icons.edit_calendar_rounded,
                                'color': const Color(0xFF2563EB),
                                'page': AttendanceCorrectionsPage(token: widget.token, user: adminUser, isAdminOrHod: true),
                              },
                              {
                                'title': 'Reports & Export',
                                'desc': 'Export Excel, PDF & CSV',
                                'icon': Icons.analytics_rounded,
                                'color': const Color(0xFF0D9488),
                                'page': SystemReportsPage(token: widget.token, user: adminUser),
                              },
                              {
                                'title': 'Faculty Substitution',
                                'desc': 'Assign timetable substitutes',
                                'icon': Icons.swap_horiz_rounded,
                                'color': const Color(0xFFD97706),
                                'page': SubstituteManagementPage(token: widget.token, user: adminUser, isAdminOrHod: true),
                              },
                              {
                                'title': 'Academic Holidays',
                                'desc': 'Manage holiday calendar',
                                'icon': Icons.celebration_rounded,
                                'color': const Color(0xFF7C3AED),
                                'page': HolidayCalendarPage(token: widget.token, isAdmin: true),
                              },
                              {
                                'title': 'Student Grievances',
                                'desc': 'Review & resolve tickets',
                                'icon': Icons.feedback_rounded,
                                'color': const Color(0xFFEA580C),
                                'page': StudentGrievancePage(token: widget.token, user: adminUser, isAdmin: true),
                              },
                              {
                                'title': 'Security & 2FA Hub',
                                'desc': 'Active sessions & 2FA config',
                                'icon': Icons.security_rounded,
                                'color': const Color(0xFF4F46E5),
                                'page': SecurityHubPage(token: widget.token, user: adminUser),
                              },
                            ];

                            return GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: isNarrow ? (constraints.maxWidth < 480 ? 1 : 2) : 3,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                                mainAxisExtent: 76,
                              ),
                              itemCount: ops.length,
                              itemBuilder: (ctx, i) {
                                final op = ops[i];
                                final color = op['color'] as Color;
                                return Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (c) => op['page'] as Widget),
                                    ),
                                    borderRadius: BorderRadius.circular(14),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: isDark ? const Color(0xFF1E293B) : Colors.white,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: color.withValues(alpha: isDark ? 0.35 : 0.2),
                                          width: 1.2,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: color.withValues(alpha: 0.05),
                                            blurRadius: 6,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: color.withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: Icon(op['icon'] as IconData, color: color, size: 20),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Text(
                                                  op['title'] as String,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12.5,
                                                    color: isDark ? Colors.white : Colors.black87,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  op['desc'] as String,
                                                  style: TextStyle(
                                                    fontSize: 10.5,
                                                    color: isDark ? Colors.white60 : Colors.grey.shade600,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                          ),
                                          Icon(Icons.chevron_right_rounded, size: 16, color: color),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  );
                }

                final deptIndex = index - 1;
                final dept = departments[deptIndex];
                final data = deptData[dept] ?? {};
                final hodCount = (data['hod'] ?? []).length;
                final staffCount = (data['staff'] ?? []).length;
                final gradColors = palette[deptIndex % palette.length];
                final isExpanded = expandedDepartments[dept] == true;
                final hodName = hodCount > 0
                    ? (data['hod'] ?? [])[0]['name'] as String? ?? 'Unknown'
                    : null;

                return Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: borderClr),
                    boxShadow: [
                      BoxShadow(
                        color: gradColors[0].withValues(alpha: 0.10),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Column(
                        children: [
                          // ── Department header row ──
                          InkWell(
                            onTap: () => setState(() {
                              expandedDepartments[dept] = !isExpanded;
                            }),
                            borderRadius: BorderRadius.circular(18),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      // Gradient dept icon
                                      Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: gradColors,
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          borderRadius: BorderRadius.circular(14),
                                          boxShadow: [
                                            BoxShadow(
                                              color: gradColors[0].withValues(alpha: 0.4),
                                              blurRadius: 8,
                                              offset: const Offset(0, 3),
                                            ),
                                          ],
                                        ),
                                        child: Center(
                                          child: Text(
                                            dept.isNotEmpty ? dept[0].toUpperCase() : 'D',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 20,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              dept,
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: isDark ? Colors.white : Colors.black87,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 2),
                                            Row(
                                              children: [
                                                Icon(Icons.person_pin_rounded, size: 13, color: isDark ? Colors.white54 : Colors.grey[500]),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Text(
                                                    hodName != null ? 'HOD: $hodName' : 'HOD: Not Assigned',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: hodName != null
                                                          ? (isDark ? Colors.white60 : Colors.grey[600])
                                                          : Colors.orange,
                                                    ),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Action buttons
                                      if (!isMobile) ...[
                                        IconButton(
                                          icon: Icon(Icons.edit_rounded, size: 18, color: gradColors[0]),
                                          tooltip: 'Edit',
                                          onPressed: () => _editDepartment(dept),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                                          tooltip: 'Delete',
                                          onPressed: () => _deleteDepartment(dept),
                                        ),
                                      ] else
                                        PopupMenuButton<String>(
                                          icon: Icon(Icons.more_vert, color: isDark ? Colors.white54 : Colors.grey),
                                          onSelected: (v) {
                                            if (v == 'edit') _editDepartment(dept);
                                            if (v == 'delete') _deleteDepartment(dept);
                                          },
                                          itemBuilder: (_) => const [
                                            PopupMenuItem(value: 'edit', child: Text('Edit')),
                                            PopupMenuItem(value: 'delete', child: Text('Delete')),
                                          ],
                                        ),
                                      AnimatedRotation(
                                        turns: isExpanded ? 0.5 : 0.0,
                                        duration: const Duration(milliseconds: 220),
                                        child: Icon(
                                          Icons.keyboard_arrow_down_rounded,
                                          color: isDark ? Colors.white38 : Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  // Stat chips row
                                  Row(
                                    children: [
                                      _buildDeptStatChip(Icons.admin_panel_settings_rounded, hodCount, 'HOD', const Color(0xFFE74C3C), isDark),
                                      const SizedBox(width: 10),
                                      _buildDeptStatChip(Icons.people_alt_rounded, staffCount, 'Staff', const Color(0xFFF39C12), isDark),
                                      const Spacer(),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: gradColors[0].withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(color: gradColors[0].withValues(alpha: 0.3)),
                                        ),
                                        child: Text(
                                          '${hodCount + staffCount} members',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: gradColors[0],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // ── Expanded section ──
                          if (isExpanded) ...[
                            Divider(
                              height: 1,
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.deepPurple.withValues(alpha: 0.1),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                              child: Column(
                                children: [
                                  _buildModernExpandableSection(
                                    context: context,
                                    title: 'Head of Department',
                                    count: hodCount,
                                    gradColors: [const Color(0xFFE74C3C), const Color(0xFFFF6B6B)],
                                    icon: Icons.admin_panel_settings_rounded,
                                    isDark: isDark,
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => DepartmentHODPage(
                                          token: widget.token,
                                          department: dept,
                                          hodList: data['hod'] ?? [],
                                        ),
                                      ),
                                    ).then((_) => fetchDepartmentData()),
                                  ),
                                  const SizedBox(height: 10),
                                  _buildModernExpandableSection(
                                    context: context,
                                    title: 'Staff Members',
                                    count: staffCount,
                                    gradColors: [const Color(0xFFF39C12), const Color(0xFFFFD700)],
                                    icon: Icons.people_alt_rounded,
                                    isDark: isDark,
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => DepartmentStaffPage(
                                          token: widget.token,
                                          department: dept,
                                          staffList: data['staff'] ?? [],
                                        ),
                                      ),
                                    ).then((_) => fetchDepartmentData()),
                                  ),
                                ],
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
          ),
        ],
      ),
    );
  }

  Widget _buildDeptStatChip(IconData icon, int count, String label, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.15 : 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            '$count $label',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }



  Widget _buildModernExpandableSection({
    required BuildContext context,
    required String title,
    required int count,
    required List<Color> gradColors,
    required IconData icon,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              gradColors[0].withValues(alpha: isDark ? 0.14 : 0.09),
              gradColors[1].withValues(alpha: isDark ? 0.07 : 0.04),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: gradColors[0].withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: gradColors),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(color: gradColors[0].withValues(alpha: 0.35), blurRadius: 6),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: gradColors[0],
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    '$count ${title.toLowerCase().contains('hod') ? (count == 1 ? 'HOD' : 'HODs') : 'members'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white54 : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, color: gradColors[0], size: 14),
          ],
        ),
      ),
    );
  }


}

// Department HOD List Page - Shows only HODs for a specific department
// Enhanced with Attendance, Face Registration, and Edit functions
class DepartmentHODPage extends StatefulWidget {
  final String token;
  final String department;
  final List<dynamic> hodList;

  const DepartmentHODPage({
    super.key,
    required this.token,
    required this.department,
    required this.hodList,
  });

  @override
  State<DepartmentHODPage> createState() => _DepartmentHODPageState();
}

class _DepartmentHODPageState extends State<DepartmentHODPage> {
  late List<dynamic> hodList;
  final _formKey = GlobalKey<FormState>();
  final usernameCtrl = TextEditingController();
  final passwordCtrl = TextEditingController();
  final nameCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    hodList = widget.hodList;
  }

  @override
  void dispose() {
    usernameCtrl.dispose();
    passwordCtrl.dispose();
    nameCtrl.dispose();
    super.dispose();
  }

  void _clearForm() {
    usernameCtrl.clear();
    passwordCtrl.clear();
    nameCtrl.clear();
  }

  Future<void> _showCreateHODDialog() async {
    _clearForm();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E1E22) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(
            'Add HOD to ${widget.department}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          content: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: usernameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Username',
                      prefixIcon: const Icon(Icons.person_rounded),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    validator: (v) => v!.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: passwordCtrl,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_rounded),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    obscureText: true,
                    validator: (v) => v!.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Full Name',
                      prefixIcon: const Icon(Icons.text_fields_rounded),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    validator: (v) => v!.isEmpty ? 'Required' : null,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _clearForm();
                Navigator.pop(context);
              },
              child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.grey.shade700)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!_formKey.currentState!.validate()) return;
                Navigator.pop(context);
                await createHOD();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> createHOD() async {
    try {
      final response = await http.post(
        Uri.parse('$API_URL/admin/users/create'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'username': usernameCtrl.text.trim(),
          'password': passwordCtrl.text.trim(),
          'name': nameCtrl.text.trim(),
          'role': 'hod',
          'dept': widget.department,
        }),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('HOD created successfully')),
          );
          // Refresh by going back
          Navigator.pop(context);
        }
      } else {
        final data = jsonDecode(response.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(data['detail'] ?? 'Failed to create HOD')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${cleanAdminErrorMessage(e)}')));
      }
    }
  }

  void _registerHODFace(Map<String, dynamic> member) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FaceRegistrationWidget(
          token: widget.token,
          role: 'hod',
          initialRegNo: member['reg_no'],
          initialName: member['name'],
          initialDept: member['dept'],
          registerEndpoint: '/admin/face/register',
          onSuccess: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Face registered successfully!')),
            );
            Future.delayed(const Duration(milliseconds: 500), () {
              if (mounted) {
                Navigator.of(context).pop();
                Navigator.of(context).pop();
              }
            });
          },
        ),
      ),
    );
  }

  void _showHODAttendanceDetails(Map<String, dynamic> hodMember) {
    final regNo = hodMember['reg_no'];
    final name = hodMember['name'];

    showDialog(
      context: context,
      builder: (context) =>
          _StaffAttendanceDialog(token: widget.token, regNo: regNo, name: name),
    );
  }

  Future<void> _editHOD(Map<String, dynamic> hodMember) async {
    final nameCtrl = TextEditingController(text: hodMember['name']);
    final usernameCtrl = TextEditingController(text: hodMember['username']);
    final passwordCtrl = TextEditingController();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E22) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'Edit HOD Profile',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: 'Name',
                  prefixIcon: const Icon(Icons.person_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: usernameCtrl,
                decoration: InputDecoration(
                  labelText: 'Username',
                  prefixIcon: const Icon(Icons.alternate_email_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'New Password (optional)',
                  prefixIcon: const Icon(Icons.lock_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  hintText: 'Leave empty to keep current',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.grey.shade700)),
          ),
          ElevatedButton(
            onPressed: () {
              final payload = {
                'name': nameCtrl.text.trim(),
                'username': usernameCtrl.text.trim(),
                'role': 'hod',
                'dept': widget.department,
              };
              final password = passwordCtrl.text.trim();
              if (password.isNotEmpty) {
                payload['password'] = password;
              }
              Navigator.pop(context, payload);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );

    if (result == null) return;

    try {
      final response = await http.put(
        Uri.parse('$API_URL/admin/users/${hodMember['id']}'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(result),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('HOD updated successfully')),
        );
        setState(() {
          final index = hodList.indexWhere((h) => h['id'] == hodMember['id']);
          if (index != -1) {
            hodList[index]['name'] = result['name'];
            hodList[index]['username'] = result['username'];
          }
        });
      } else {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['detail'] ?? 'Failed to update HOD')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${cleanAdminErrorMessage(e)}')));
    }
  }

  Future<void> deleteHOD(int hodId, String username) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete HOD'),
        content: Text(
          'Are you sure you want to delete $username? This will also remove their face data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.grey.shade700)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final response = await http.delete(
        Uri.parse('$API_URL/admin/users/$hodId'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('HOD deleted successfully')),
          );
          setState(() {
            hodList = hodList.where((h) => h['id'] != hodId).toList();
          });
        }
      } else {
        final error =
            jsonDecode(response.body)['detail'] ?? 'Failed to delete HOD';
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(error)));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
      ).showSnackBar(SnackBar(content: Text('Error: ${cleanAdminErrorMessage(e)}')));
      }
    }
  }

  Future<void> _toggleHODSuspension(Map<String, dynamic> hod) async {
    final isSuspended = hod['suspended'] == true;
    final actionText = isSuspended ? 'unsuspend' : 'suspend';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${isSuspended ? "Unsuspend" : "Suspend"} HOD'),
        content: Text('Are you sure you want to $actionText HOD ${hod['name']}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: isSuspended ? Colors.green : Colors.red),
            child: Text(isSuspended ? 'Unsuspend' : 'Suspend'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final response = await http.put(
        Uri.parse('$API_URL/admin/users/${hod['id']}'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'suspended': !isSuspended}),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('HOD ${isSuspended ? "unsuspended" : "suspended"} successfully')),
          );
          setState(() {
            final index = hodList.indexWhere((h) => h['id'] == hod['id']);
            if (index != -1) {
              hodList[index]['suspended'] = !isSuspended;
            }
          });
        }
      } else {
        final data = jsonDecode(response.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(data['detail'] ?? 'Failed to update status')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${cleanAdminErrorMessage(e)}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? const Color(0xFF0F0F12) : const Color(0xFFF8F9FB);
    final cardBg = isDark ? const Color(0xFF1E1E22) : Colors.white;
    final borderColor = isDark ? Colors.white.withOpacity(0.08) : Colors.grey.shade200;

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: Text('${widget.department} - HODs', style: const TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark 
                ? [const Color(0xFF2C0B0E), const Color(0xFF1E1E22)]
                : [Colors.red.shade100, Colors.red.shade50],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateHODDialog(),
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add HOD'),
      ),
      body: hodList.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.admin_panel_settings_rounded,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No HOD assigned to this department',
                    style: TextStyle(color: Colors.grey[600], fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => _showCreateHODDialog(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add First HOD'),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: hodList.length,
              itemBuilder: (context, index) {
                final hod = hodList[index];
                final faceRegistered = hod['face_registered'] == true;

                return Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: borderColor),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.02),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Colors.red.shade400, Colors.red.shade700],
                                ),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                hod['name'] != null && hod['name'].isNotEmpty 
                                  ? hod['name'][0].toUpperCase() 
                                  : 'H',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (hod['name'] ?? 'Unknown') + (hod['suspended'] == true ? ' (Suspended)' : ''),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: hod['suspended'] == true 
                                        ? Colors.red 
                                        : (isDark ? Colors.white : Colors.red.shade900),
                                      decoration: hod['suspended'] == true ? TextDecoration.lineThrough : null,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${hod['username']} • ID: ${hod['reg_no'] ?? 'N/A'}',
                                    style: TextStyle(
                                      color: isDark ? Colors.white60 : Colors.grey.shade600,
                                      fontSize: 12,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: faceRegistered 
                                  ? Colors.green.withOpacity(0.12) 
                                  : Colors.orange.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: faceRegistered 
                                    ? Colors.green.withOpacity(0.3) 
                                    : Colors.orange.withOpacity(0.3),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    faceRegistered ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                                    color: faceRegistered ? Colors.green : Colors.orange,
                                    size: 14,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    faceRegistered ? 'Verified' : 'No Face',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: faceRegistered ? Colors.green : Colors.orange,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Divider(height: 1, thickness: 0.5),
                        const SizedBox(height: 12),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _buildActionButton(
                                icon: Icons.calendar_today_rounded,
                                label: 'Attendance',
                                color: Colors.indigo,
                                isDark: isDark,
                                onTap: () => _showHODAttendanceDetails(hod),
                              ),
                              const SizedBox(width: 8),
                              _buildActionButton(
                                icon: faceRegistered ? Icons.face_retouching_natural_rounded : Icons.face_rounded,
                                label: faceRegistered ? 'Update Face' : 'Register Face',
                                color: faceRegistered ? Colors.teal : Colors.green,
                                isDark: isDark,
                                onTap: () => _registerHODFace(hod),
                              ),
                              const SizedBox(width: 8),
                              _buildActionButton(
                                icon: Icons.edit_rounded,
                                label: 'Edit Info',
                                color: Colors.blue,
                                isDark: isDark,
                                onTap: () => _editHOD(hod),
                              ),
                              const SizedBox(width: 8),
                              _buildActionButton(
                                icon: hod['suspended'] == true ? Icons.play_arrow_rounded : Icons.block_rounded,
                                label: hod['suspended'] == true ? 'Unsuspend' : 'Suspend',
                                color: hod['suspended'] == true ? Colors.green : Colors.orange.shade800,
                                isDark: isDark,
                                onTap: () => _toggleHODSuspension(hod),
                              ),
                              const SizedBox(width: 8),
                              _buildActionButton(
                                icon: Icons.delete_outline_rounded,
                                label: 'Delete',
                                color: Colors.red,
                                isDark: isDark,
                                onTap: () => deleteHOD(hod['id'], hod['username']),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(isDark ? 0.08 : 0.04),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10, 
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Department Staff List Page - Shows only Staff for a specific department
// This page provides direct access to staff management functions from the Department tab
class DepartmentStaffPage extends StatefulWidget {
  final String token;
  final String department;
  final List<dynamic> staffList;

  const DepartmentStaffPage({
    super.key,
    required this.token,
    required this.department,
    required this.staffList,
  });

  @override
  State<DepartmentStaffPage> createState() => _DepartmentStaffPageState();
}

class _DepartmentStaffPageState extends State<DepartmentStaffPage> {
  late List<dynamic> staffList;
  final _formKey = GlobalKey<FormState>();
  final usernameCtrl = TextEditingController();
  final passwordCtrl = TextEditingController();
  final nameCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    staffList = widget.staffList;
  }

  @override
  void dispose() {
    usernameCtrl.dispose();
    passwordCtrl.dispose();
    nameCtrl.dispose();
    super.dispose();
  }

  void _clearForm() {
    usernameCtrl.clear();
    passwordCtrl.clear();
    nameCtrl.clear();
  }

  Future<void> _showCreateStaffDialog() async {
    _clearForm();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E1E22) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(
            'Add Staff to ${widget.department}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          content: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: usernameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Username',
                      prefixIcon: const Icon(Icons.person_rounded),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    validator: (v) => v!.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: passwordCtrl,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_rounded),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    obscureText: true,
                    validator: (v) => v!.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Full Name',
                      prefixIcon: const Icon(Icons.text_fields_rounded),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    validator: (v) => v!.isEmpty ? 'Required' : null,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _clearForm();
                Navigator.pop(context);
              },
              child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.grey.shade700)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!_formKey.currentState!.validate()) return;
                Navigator.pop(context);
                await createStaff();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> createStaff() async {
    try {
      final response = await http.post(
        Uri.parse('$API_URL/admin/users/create'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'username': usernameCtrl.text,
          'password': passwordCtrl.text,
          'name': nameCtrl.text,
          'role': 'staff',
          'dept': widget.department,
        }),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Staff created successfully')),
        );
        // Refresh the staff list by going back
        Navigator.pop(context);
      } else {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['detail'] ?? 'Failed to create staff')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${cleanAdminErrorMessage(e)}')));
    }
  }

  void _registerStaffFace(Map<String, dynamic> member) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FaceRegistrationWidget(
          token: widget.token,
          role: 'staff',
          initialRegNo: member['reg_no'],
          initialName: member['name'],
          initialDept: member['dept'],
          registerEndpoint: '/admin/face/register',
          onSuccess: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Face registered successfully!')),
            );
            Future.delayed(const Duration(milliseconds: 500), () {
              if (mounted) {
                Navigator.of(context).pop();
                Navigator.of(context).pop();
              }
            });
          },
        ),
      ),
    );
  }

  Future<void> _grantPermission(String regNo, String name) async {
    try {
      final response = await http.post(
        Uri.parse('$API_URL/admin/face/permission/$regNo'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Permission granted to $name')));
        setState(() {
          final index = staffList.indexWhere((s) => s['reg_no'] == regNo);
          if (index != -1) {
            staffList[index]['can_reregister'] = true;
          }
        });
      } else {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['detail'] ?? 'Failed to grant permission'),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${cleanAdminErrorMessage(e)}')));
    }
  }

  Future<void> _revokePermission(String regNo, String name) async {
    try {
      final response = await http.delete(
        Uri.parse('$API_URL/admin/face/permission/$regNo'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Permission revoked for $name')));
        setState(() {
          final index = staffList.indexWhere((s) => s['reg_no'] == regNo);
          if (index != -1) {
            staffList[index]['can_reregister'] = false;
          }
        });
      } else {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['detail'] ?? 'Failed to revoke permission'),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${cleanAdminErrorMessage(e)}')));
    }
  }

  Future<void> _editStaff(Map<String, dynamic> staffMember) async {
    final nameCtrl = TextEditingController(text: staffMember['name']);
    final usernameCtrl = TextEditingController(text: staffMember['username']);
    final passwordCtrl = TextEditingController();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E22) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'Edit Staff Profile',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: 'Name',
                  prefixIcon: const Icon(Icons.person_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: usernameCtrl,
                decoration: InputDecoration(
                  labelText: 'Username',
                  prefixIcon: const Icon(Icons.alternate_email_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'New Password (optional)',
                  prefixIcon: const Icon(Icons.lock_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  hintText: 'Leave empty to keep current',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.grey.shade700)),
          ),
          ElevatedButton(
            onPressed: () {
              final payload = {
                'name': nameCtrl.text.trim(),
                'username': usernameCtrl.text.trim(),
                'role': 'staff',
                'dept': widget.department,
              };
              final password = passwordCtrl.text.trim();
              if (password.isNotEmpty) {
                payload['password'] = password;
              }
              Navigator.pop(context, payload);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );

    if (result == null) return;

    try {
      final response = await http.put(
        Uri.parse('$API_URL/admin/users/${staffMember['id']}'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(result),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Staff updated successfully')),
        );
        setState(() {
          final index = staffList.indexWhere(
            (s) => s['id'] == staffMember['id'],
          );
          if (index != -1) {
            staffList[index]['name'] = result['name'];
            staffList[index]['username'] = result['username'];
          }
        });
      } else {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['detail'] ?? 'Failed to update staff')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${cleanAdminErrorMessage(e)}')));
    }
  }

  void _showStaffAttendanceDetails(Map<String, dynamic> staffMember) {
    final regNo = staffMember['reg_no'];
    final name = staffMember['name'];

    showDialog(
      context: context,
      builder: (context) =>
          _StaffAttendanceDialog(token: widget.token, regNo: regNo, name: name),
    );
  }

  Future<void> deleteStaff(int staffId, String username) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Staff'),
        content: Text(
          'Are you sure you want to delete $username? This will also remove their face data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.grey.shade700)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final response = await http.delete(
        Uri.parse('$API_URL/admin/users/$staffId'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Staff deleted successfully')),
          );
          setState(() {
            staffList = staffList.where((s) => s['id'] != staffId).toList();
          });
        }
      } else {
        final error =
            jsonDecode(response.body)['detail'] ?? 'Failed to delete staff';
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(error)));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
      ).showSnackBar(SnackBar(content: Text('Error: ${cleanAdminErrorMessage(e)}')));
      }
    }
  }

  Future<void> _toggleStaffSuspension(Map<String, dynamic> staff) async {
    final isSuspended = staff['suspended'] == true;
    final actionText = isSuspended ? 'unsuspend' : 'suspend';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${isSuspended ? "Unsuspend" : "Suspend"} Staff'),
        content: Text('Are you sure you want to $actionText staff member ${staff['name']}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: isSuspended ? Colors.green : Colors.red),
            child: Text(isSuspended ? 'Unsuspend' : 'Suspend'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final response = await http.put(
        Uri.parse('$API_URL/admin/users/${staff['id']}'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'suspended': !isSuspended}),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Staff ${isSuspended ? "unsuspended" : "suspended"} successfully')),
          );
          setState(() {
            final index = staffList.indexWhere((s) => s['id'] == staff['id']);
            if (index != -1) {
              staffList[index]['suspended'] = !isSuspended;
            }
          });
        }
      } else {
        final data = jsonDecode(response.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(data['detail'] ?? 'Failed to update status')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${cleanAdminErrorMessage(e)}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? const Color(0xFF0F0F12) : const Color(0xFFF8F9FB);
    final cardBg = isDark ? const Color(0xFF1E1E22) : Colors.white;
    final borderColor = isDark ? Colors.white.withOpacity(0.08) : Colors.grey.shade200;

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: Text('${widget.department} - Staff Management', style: const TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark 
                ? [const Color(0xFF2C160B), const Color(0xFF1E1E22)]
                : [Colors.orange.shade100, Colors.orange.shade50],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateStaffDialog(),
        backgroundColor: Colors.orange.shade700,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Staff'),
      ),
      body: staffList.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.people_outline_rounded,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No staff members assigned to this department',
                    style: TextStyle(color: Colors.grey[600], fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => _showCreateStaffDialog(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade700,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add First Staff'),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: staffList.length,
              itemBuilder: (context, index) {
                final staff = staffList[index];
                final faceRegistered = staff['face_registered'] == true;
                final canReregister = staff['can_reregister'] == true;

                return Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: borderColor),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.02),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Colors.orange.shade400, Colors.orange.shade700],
                                ),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                staff['name'] != null && staff['name'].isNotEmpty 
                                  ? staff['name'][0].toUpperCase() 
                                  : 'S',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (staff['name'] ?? 'Unknown') + (staff['suspended'] == true ? ' (Suspended)' : ''),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: staff['suspended'] == true 
                                        ? Colors.red 
                                        : (isDark ? Colors.white : Colors.orange.shade900),
                                      decoration: staff['suspended'] == true ? TextDecoration.lineThrough : null,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${staff['username']} • ID: ${staff['reg_no'] ?? 'N/A'}',
                                    style: TextStyle(
                                      color: isDark ? Colors.white60 : Colors.grey.shade600,
                                      fontSize: 12,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            // Face registration badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: faceRegistered 
                                  ? Colors.green.withOpacity(0.12) 
                                  : Colors.orange.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: faceRegistered 
                                    ? Colors.green.withOpacity(0.3) 
                                    : Colors.orange.withOpacity(0.3),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    faceRegistered ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                                    color: faceRegistered ? Colors.green : Colors.orange,
                                    size: 14,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    faceRegistered ? 'Verified' : 'No Face',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: faceRegistered ? Colors.green : Colors.orange,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (canReregister) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(isDark ? 0.12 : 0.06),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue.withOpacity(0.2)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.refresh_rounded, size: 14, color: Colors.blue),
                                SizedBox(width: 6),
                                Text(
                                  'Allowed to Re-register Face',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.blue),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        const Divider(height: 1, thickness: 0.5),
                        const SizedBox(height: 12),
                        // Action buttons in a row for responsiveness
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _buildActionButton(
                                icon: Icons.calendar_month_rounded,
                                label: 'Attendance',
                                color: Colors.indigo,
                                isDark: isDark,
                                onTap: () => _showStaffAttendanceDetails(staff),
                              ),
                              const SizedBox(width: 8),
                              _buildActionButton(
                                icon: faceRegistered ? Icons.face_retouching_natural_rounded : Icons.face_rounded,
                                label: faceRegistered ? 'Update Face' : 'Register Face',
                                color: faceRegistered ? Colors.teal : Colors.green,
                                isDark: isDark,
                                onTap: () => _registerStaffFace(staff),
                              ),
                              const SizedBox(width: 8),
                              _buildActionButton(
                                icon: canReregister ? Icons.block_rounded : Icons.check_circle_outline_rounded,
                                label: canReregister ? 'Revoke Perm' : 'Grant Perm',
                                color: canReregister ? Colors.amber.shade700 : Colors.blueGrey,
                                isDark: isDark,
                                onTap: () {
                                  if (canReregister) {
                                    _revokePermission(
                                      staff['reg_no'],
                                      staff['name'],
                                    );
                                  } else {
                                    _grantPermission(
                                      staff['reg_no'],
                                      staff['name'],
                                    );
                                  }
                                },
                              ),
                              const SizedBox(width: 8),
                              _buildActionButton(
                                icon: Icons.edit_rounded,
                                label: 'Edit Info',
                                color: Colors.blue,
                                isDark: isDark,
                                onTap: () => _editStaff(staff),
                              ),
                              const SizedBox(width: 8),
                              _buildActionButton(
                                icon: staff['suspended'] == true ? Icons.play_arrow_rounded : Icons.block_rounded,
                                label: staff['suspended'] == true ? 'Unsuspend' : 'Suspend',
                                color: staff['suspended'] == true ? Colors.green : Colors.orange.shade800,
                                isDark: isDark,
                                onTap: () => _toggleStaffSuspension(staff),
                              ),
                              const SizedBox(width: 8),
                              _buildActionButton(
                                icon: Icons.delete_outline_rounded,
                                label: 'Delete',
                                color: Colors.red,
                                isDark: isDark,
                                onTap: () => deleteStaff(staff['id'], staff['username']),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(isDark ? 0.08 : 0.04),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10, 
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Department Students List Page - Shows only Students for a specific department
class DepartmentStudentsPage extends StatefulWidget {
  final String token;
  final String department;
  final List<dynamic> studentList;

  const DepartmentStudentsPage({
    super.key,
    required this.token,
    required this.department,
    required this.studentList,
  });

  @override
  State<DepartmentStudentsPage> createState() => _DepartmentStudentsPageState();
}

class _DepartmentStudentsPageState extends State<DepartmentStudentsPage> {
  late List<dynamic> studentList;

  @override
  void initState() {
    super.initState();
    studentList = widget.studentList;
  }

  Future<void> deleteStudent(String regNo, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Student'),
        content: Text(
          'Are you sure you want to delete $name ($regNo)? This will also remove their face data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final response = await http.delete(
        Uri.parse('$API_URL/admin/students/$regNo'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Student deleted successfully')),
          );
          setState(() {
            studentList = studentList
                .where((s) => s['reg_no'] != regNo)
                .toList();
          });
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to delete student')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${cleanAdminErrorMessage(e)}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.department} - Students'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: studentList.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.school_outlined,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No students in this department',
                    style: TextStyle(color: Colors.grey[600], fontSize: 16),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: studentList.length,
              itemBuilder: (context, index) {
                final student = studentList[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.green.withOpacity(0.1),
                      child: const Icon(Icons.person, color: Colors.green),
                    ),
                    title: Text(
                      student['name'] ?? 'Unknown',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(student['reg_no'] ?? ''),
                        Text(
                          'Year: ${student['year'] ?? 'N/A'}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () =>
                          deleteStudent(student['reg_no'], student['name']),
                      tooltip: 'Remove Student',
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class StudentsManagementTab extends StatefulWidget {
  final String token;

  const StudentsManagementTab({super.key, required this.token});

  @override
  State<StudentsManagementTab> createState() => _StudentsManagementTabState();
}

class _StudentsManagementTabState extends State<StudentsManagementTab> {
  List<dynamic> students = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchStudents();
  }

  Future<void> fetchStudents() async {
    setState(() => isLoading = true);
    try {
      // Students with caching (10 minutes for slow networks)
      final response = await apiClient.get(
        '$API_URL/admin/students',
        token: widget.token,
        cacheKey: 'admin_students',
        cacheDuration: const Duration(minutes: 10),
      );
      if (response.statusCode == 200) {
        setState(() => students = jsonDecode(response.body)['students']);
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${cleanAdminErrorMessage(e)}')));
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> deleteStudent(String regNo, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Student'),
        content: Text(
          'Are you sure you want to delete $name ($regNo)? This will also remove their face data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final response = await http.delete(
        Uri.parse('$API_URL/admin/students/$regNo'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Student deleted successfully')),
        );
        fetchStudents();
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete student')));
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${cleanAdminErrorMessage(e)}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'All Students (${students.length})',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              IconButton.filled(
                onPressed: fetchStudents,
                style: IconButton.styleFrom(backgroundColor: Colors.deepPurple),
                icon: const Icon(Icons.refresh, color: Colors.white),
              ),
            ],
          ),
        ),
        Expanded(
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : students.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.school_outlined,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No students registered',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: students.length,
                  itemBuilder: (context, index) {
                    final student = students[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          radius: 20,
                          backgroundColor: Colors.green.withOpacity(0.1),
                          child: const Icon(
                            Icons.person,
                            color: Colors.green,
                            size: 20,
                          ),
                        ),
                        title: Text(student['name'] ?? 'Unknown'),
                        subtitle: Text(
                          '${student['reg_no']} • ${student['dept']}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () =>
                              deleteStudent(student['reg_no'], student['name']),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class AttendanceRecordsTab extends StatefulWidget {
  final String token;

  const AttendanceRecordsTab({super.key, required this.token});

  @override
  State<AttendanceRecordsTab> createState() => _AttendanceRecordsTabState();
}

class _AttendanceRecordsTabState extends State<AttendanceRecordsTab> {
  List<dynamic> attendance = [];
  bool isLoading = true;
  String? selectedDate;

  @override
  void initState() {
    super.initState();
    fetchAttendance();
  }

  Future<void> fetchAttendance() async {
    setState(() => isLoading = true);
    try {
      final url = selectedDate != null
          ? Uri.parse('$API_URL/admin/attendance?date=$selectedDate')
          : Uri.parse('$API_URL/admin/attendance');
      final response = await apiClient.get(
        url.toString(),
        token: widget.token,
        cacheKey: 'admin_attendance',
        cacheDuration: const Duration(minutes: 5),
      );
      if (response.statusCode == 200) {
        setState(() => attendance = jsonDecode(response.body)['attendance']);
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${cleanAdminErrorMessage(e)}')));
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> deleteRecord(int recordId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Record'),
        content: const Text(
          'Are you sure you want to delete this attendance record?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final response = await http.delete(
        Uri.parse('$API_URL/admin/attendance/$recordId'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Record deleted successfully')),
        );
        fetchAttendance();
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete record')));
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${cleanAdminErrorMessage(e)}')));
    }
  }

  Future<void> _selectDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: selectedDate != null ? DateTime.parse(selectedDate!) : now,
      firstDate: DateTime(2024),
      lastDate: now,
    );
    if (date != null) {
      setState(() {
        selectedDate =
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      });
      fetchAttendance();
    }
  }

  // Week navigation for single date
  void _goToPreviousDay() {
    if (selectedDate != null) {
      final current = DateTime.parse(selectedDate!);
      final previous = current.subtract(const Duration(days: 1));
      setState(() {
        selectedDate =
            '${previous.year}-${previous.month.toString().padLeft(2, '0')}-${previous.day.toString().padLeft(2, '0')}';
      });
      fetchAttendance();
    }
  }

  void _goToNextDay() {
    final now = DateTime.now();
    if (selectedDate != null) {
      final current = DateTime.parse(selectedDate!);
      final next = current.add(const Duration(days: 1));
      // Don't go beyond today
      if (next.isAfter(now)) return;
      setState(() {
        selectedDate =
            '${next.year}-${next.month.toString().padLeft(2, '0')}-${next.day.toString().padLeft(2, '0')}';
      });
      fetchAttendance();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Attendance Records (${attendance.length})',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Previous day button
                      IconButton(
                        onPressed: selectedDate != null
                            ? _goToPreviousDay
                            : null,
                        icon: const Icon(Icons.chevron_left),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.deepPurple.withValues(
                            alpha: 0.1,
                          ),
                          foregroundColor: Colors.deepPurple,
                        ),
                        tooltip: 'Previous Day',
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _selectDate,
                        style: FilledButton.styleFrom(
                          backgroundColor: selectedDate != null
                              ? Colors.deepPurple
                              : Colors.grey,
                        ),
                        icon: const Icon(Icons.date_range, size: 18),
                        label: Text(selectedDate ?? 'Filter Date'),
                      ),
                      if (selectedDate != null) ...[
                        const SizedBox(width: 8),
                        IconButton.filled(
                          onPressed: () {
                            setState(() => selectedDate = null);
                            fetchAttendance();
                          },
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                          icon: const Icon(
                            Icons.clear,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ],
                      const SizedBox(width: 8),
                      // Next day button
                      IconButton(
                        onPressed: selectedDate != null ? _goToNextDay : null,
                        icon: const Icon(Icons.chevron_right),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.deepPurple.withValues(
                            alpha: 0.1,
                          ),
                          foregroundColor: Colors.deepPurple,
                        ),
                        tooltip: 'Next Day',
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : attendance.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.assignment_outlined,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        selectedDate != null
                            ? 'No records for $selectedDate'
                            : 'No attendance records found',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: attendance.length,
                  itemBuilder: (context, index) {
                    final record = attendance[index];
                    final timestamp = record['timestamp']?.toString() ?? '';
                    // Handle both "2024-03-11 07:04:29" and "2024-03-11T07:04:29" formats
                    final datePart = timestamp.contains(' ')
                        ? timestamp.split(' ')[0]
                        : (timestamp.contains('T')
                              ? timestamp.split('T')[0]
                              : '');
                    final timePart = timestamp.contains(' ')
                        ? (timestamp.split(' ').length > 1
                              ? timestamp.split(' ')[1]
                              : '')
                        : (timestamp.contains('T')
                              ? timestamp.split('T')[1]
                              : '');

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          radius: 20,
                          backgroundColor: Colors.orange.withOpacity(0.1),
                          child: const Icon(
                            Icons.access_time,
                            color: Colors.orange,
                            size: 20,
                          ),
                        ),
                        title: Text(record['name'] ?? 'Unknown'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(record['reg_no']),
                            Text(
                              '${record['dept']}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                        trailing: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              timePart,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              datePart,
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                        onLongPress: () => deleteRecord(record['id']),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// Admin Staff Attendance Tab - View all staff attendance records
class AdminStaffAttendanceTab extends StatefulWidget {
  final String token;

  const AdminStaffAttendanceTab({super.key, required this.token});

  @override
  State<AdminStaffAttendanceTab> createState() =>
      _AdminStaffAttendanceTabState();
}

class _AdminStaffAttendanceTabState extends State<AdminStaffAttendanceTab> {
  List<dynamic> staffAttendance = [];
  bool isLoading = true;
  String? selectedDate;

  @override
  void initState() {
    super.initState();
    fetchStaffAttendance();
  }

  Future<void> fetchStaffAttendance() async {
    setState(() => isLoading = true);
    try {
      final url = selectedDate != null
          ? Uri.parse('$API_URL/admin/attendance/staff?date=$selectedDate')
          : Uri.parse('$API_URL/admin/attendance/staff');
      final response = await apiClient.get(
        url.toString(),
        token: widget.token,
        cacheKey: 'admin_staff_attendance',
        cacheDuration: const Duration(minutes: 5),
      );
      if (response.statusCode == 200) {
        setState(
          () => staffAttendance = jsonDecode(response.body)['attendance'],
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${cleanAdminErrorMessage(e)}')));
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _selectDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: selectedDate != null ? DateTime.parse(selectedDate!) : now,
      firstDate: DateTime(2024),
      lastDate: now,
    );
    if (date != null) {
      setState(() {
        selectedDate =
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      });
      fetchStaffAttendance();
    }
  }

  // Week navigation for single date
  void _goToPreviousDay() {
    if (selectedDate != null) {
      final current = DateTime.parse(selectedDate!);
      final previous = current.subtract(const Duration(days: 1));
      setState(() {
        selectedDate =
            '${previous.year}-${previous.month.toString().padLeft(2, '0')}-${previous.day.toString().padLeft(2, '0')}';
      });
      fetchStaffAttendance();
    }
  }

  void _goToNextDay() {
    final now = DateTime.now();
    if (selectedDate != null) {
      final current = DateTime.parse(selectedDate!);
      final next = current.add(const Duration(days: 1));
      // Don't go beyond today
      if (next.isAfter(now)) return;
      setState(() {
        selectedDate =
            '${next.year}-${next.month.toString().padLeft(2, '0')}-${next.day.toString().padLeft(2, '0')}';
      });
      fetchStaffAttendance();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isMobile)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Staff Attendance (${staffAttendance.length})',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        IconButton(
                          onPressed: selectedDate != null
                              ? _goToPreviousDay
                              : null,
                          icon: const Icon(Icons.chevron_left),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.deepPurple.withValues(
                              alpha: 0.1,
                            ),
                            foregroundColor: Colors.deepPurple,
                          ),
                          tooltip: 'Previous Day',
                        ),
                        FilledButton.icon(
                          onPressed: _selectDate,
                          style: FilledButton.styleFrom(
                            backgroundColor: selectedDate != null
                                ? Colors.deepPurple
                                : Colors.grey,
                          ),
                          icon: const Icon(Icons.date_range, size: 18),
                          label: Text(
                            selectedDate ?? 'Filter Date',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (selectedDate != null)
                          IconButton.filled(
                            onPressed: () {
                              setState(() => selectedDate = null);
                              fetchStaffAttendance();
                            },
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                            icon: const Icon(
                              Icons.clear,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        IconButton(
                          onPressed: selectedDate != null ? _goToNextDay : null,
                          icon: const Icon(Icons.chevron_right),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.deepPurple.withValues(
                              alpha: 0.1,
                            ),
                            foregroundColor: Colors.deepPurple,
                          ),
                          tooltip: 'Next Day',
                        ),
                      ],
                    ),
                  ],
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        'Staff Attendance (${staffAttendance.length})',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Previous day button
                        IconButton(
                          onPressed: selectedDate != null
                              ? _goToPreviousDay
                              : null,
                          icon: const Icon(Icons.chevron_left),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.deepPurple.withValues(
                              alpha: 0.1,
                            ),
                            foregroundColor: Colors.deepPurple,
                          ),
                          tooltip: 'Previous Day',
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: _selectDate,
                          style: FilledButton.styleFrom(
                            backgroundColor: selectedDate != null
                                ? Colors.deepPurple
                                : Colors.grey,
                          ),
                          icon: const Icon(Icons.date_range, size: 18),
                          label: Text(
                            selectedDate ?? 'Filter Date',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (selectedDate != null) ...[
                          const SizedBox(width: 8),
                          IconButton.filled(
                            onPressed: () {
                              setState(() => selectedDate = null);
                              fetchStaffAttendance();
                            },
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                            icon: const Icon(
                              Icons.clear,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ],
                        const SizedBox(width: 8),
                        // Next day button
                        IconButton(
                          onPressed: selectedDate != null ? _goToNextDay : null,
                          icon: const Icon(Icons.chevron_right),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.deepPurple.withValues(
                              alpha: 0.1,
                            ),
                            foregroundColor: Colors.deepPurple,
                          ),
                          tooltip: 'Next Day',
                        ),
                      ],
                    ),
                  ],
                ),
            ],
          ),
        ),
        Expanded(
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : staffAttendance.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.badge_outlined,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        selectedDate != null
                            ? 'No staff attendance for $selectedDate'
                            : 'No staff attendance records',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: staffAttendance.length,
                  itemBuilder: (context, index) {
                    final record = staffAttendance[index];
                    final timestamp = record['timestamp']?.toString() ?? '';
                    // Handle both "2024-03-11 07:04:29" and "2024-03-11T07:04:29" formats
                    final datePart = timestamp.contains(' ')
                        ? timestamp.split(' ')[0]
                        : (timestamp.contains('T')
                              ? timestamp.split('T')[0]
                              : '');
                    final timePart = timestamp.contains(' ')
                        ? (timestamp.split(' ').length > 1
                              ? timestamp.split(' ')[1]
                              : '')
                        : (timestamp.contains('T')
                              ? timestamp.split('T')[1]
                              : '');

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          radius: 20,
                          backgroundColor: Colors.deepPurple.withOpacity(0.1),
                          child: const Icon(
                            Icons.person,
                            color: Colors.deepPurple,
                            size: 20,
                          ),
                        ),
                        title: Text(record['name'] ?? 'Unknown'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(record['reg_no'] ?? ''),
                            Text(
                              '${record['dept']}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                        trailing: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              timePart,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              datePart,
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// Admin Face Registration Tab - Only for self-registration
class AdminFaceRegisterTab extends StatefulWidget {
  final String token;
  final Map<String, dynamic> user;

  const AdminFaceRegisterTab({
    super.key,
    required this.token,
    required this.user,
  });

  @override
  State<AdminFaceRegisterTab> createState() => _AdminFaceRegisterTabState();
}

class _AdminFaceRegisterTabState extends State<AdminFaceRegisterTab> {
  bool _isRegistered = false;
  bool _isLoading = true;
  String _message = '';

  @override
  void initState() {
    super.initState();
    _checkFaceStatus();
  }

  Future<void> _checkFaceStatus() async {
    try {
      final response = await http.get(
        Uri.parse("$API_URL/face/status/${widget.user['regNo']}"),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _isRegistered = data['face_registered'] ?? false;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _message = "Error checking status: $e";
        _isLoading = false;
      });
    }
  }

  void _navigateToFaceRegistration() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FaceRegistrationWidget(
          token: widget.token,
          role: 'admin',
          initialRegNo: widget.user['regNo'],
          initialName: widget.user['name'],
          initialDept: widget.user['dept'],
          registerEndpoint: '/admin/face/register',
          onSuccess: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Face registered successfully!')),
            );
            _checkFaceStatus();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _isRegistered ? Icons.check_circle : Icons.warning,
                        color: _isRegistered ? Colors.green : Colors.orange,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Your Face Registration',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              _isRegistered
                                  ? "Your face is registered"
                                  : "Face not registered yet",
                              style: TextStyle(
                                fontSize: 14,
                                color: _isRegistered
                                    ? Colors.green[700]
                                    : Colors.orange[700],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Name: ${widget.user['name']}",
                          style: const TextStyle(fontSize: 14),
                        ),
                        Text(
                          "ID: ${widget.user['regNo']}",
                          style: const TextStyle(fontSize: 14),
                        ),
                        Text(
                          "Dept: ${widget.user['dept']}",
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _navigateToFaceRegistration,
                      icon: Icon(_isRegistered ? Icons.refresh : Icons.face),
                      label: Text(
                        _isRegistered ? "Re-register Face" : "Register Face",
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Instructions',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _buildInstructionTile(
                    Icons.person,
                    'This section is for registering YOUR own face only',
                  ),
                  _buildInstructionTile(
                    Icons.camera_alt,
                    'Position your face in the camera frame',
                  ),
                  _buildInstructionTile(
                    Icons.check_circle,
                    'Tap capture when face is detected',
                  ),
                  _buildInstructionTile(Icons.save, 'Confirm registration'),
                ],
              ),
            ),
          ),
          if (_message.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_message, style: const TextStyle(color: Colors.red)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInstructionTile(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.deepPurple),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class AdminReportsTab extends StatefulWidget {
  final String token;

  const AdminReportsTab({super.key, required this.token});

  @override
  State<AdminReportsTab> createState() => _AdminReportsTabState();
}

class _AdminReportsTabState extends State<AdminReportsTab> {
  List<dynamic> reportData = [];
  List<String> departments = [];
  String? selectedReportType;
  String? selectedDepartment;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchDepartments();
  }

  Future<void> _fetchDepartments() async {
    try {
      final response = await http.get(
        Uri.parse('$API_URL/admin/departments'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          departments =
              (data['departments'] as List)
                  .map((d) => d['name'].toString())
                  .toList()
                ..sort();
        });
      }
    } catch (e) {
      // Handle error silently for now
    }
  }

  Future<void> _generateReport() async {
    if (selectedReportType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a report type')),
      );
      return;
    }

    setState(() => isLoading = true);
    try {
      String endpoint;
      switch (selectedReportType) {
        case 'attendance_summary':
          endpoint = '/admin/reports/attendance-summary';
          break;
        case 'staff_attendance':
          endpoint = '/admin/reports/staff-attendance';
          break;
        case 'department_wise':
          endpoint = '/admin/reports/department-wise';
          break;
        default:
          endpoint = '/admin/reports/attendance-summary';
      }

      final uri = selectedDepartment != null
          ? Uri.parse(
              '$API_URL$endpoint?department=${Uri.encodeComponent(selectedDepartment!)}',
            )
          : Uri.parse('$API_URL$endpoint');

      final response = await apiClient.get(
        uri.toString(),
        token: widget.token,
        cacheKey: 'admin_attendance_filtered',
        cacheDuration: const Duration(minutes: 2),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          reportData = data['report'] ?? [];
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to generate report')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${cleanAdminErrorMessage(e)}')));
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Report Configuration
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Report Configuration',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  // Report Type Dropdown
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.deepPurple),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButton<String>(
                      value: selectedReportType,
                      isExpanded: true,
                      underline: const SizedBox(),
                      hint: const Text('Select Report Type'),
                      items: const [
                        DropdownMenuItem(
                          value: 'attendance_summary',
                          child: Text('Attendance Summary'),
                        ),
                        DropdownMenuItem(
                          value: 'department_wise',
                          child: Text('Department-wise Report'),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() => selectedReportType = value);
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Department Filter (optional)
                  if (departments.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.deepPurple),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButton<String>(
                        value: selectedDepartment,
                        isExpanded: true,
                        underline: const SizedBox(),
                        hint: const Text('All Departments'),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('All Departments'),
                          ),
                          ...departments.map(
                            (dept) => DropdownMenuItem(
                              value: dept,
                              child: Text(dept),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() => selectedDepartment = value);
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  // Generate Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isLoading ? null : _generateReport,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                      ),
                      child: isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('Generate Report'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Report Results
          if (reportData.isNotEmpty) ...[
            const Text(
              'Report Results',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Card(
                child: ListView.builder(
                  itemCount: reportData.length,
                  itemBuilder: (context, index) {
                    final item = reportData[index];
                    return ListTile(
                      title: Text(item['title'] ?? 'Report Item ${index + 1}'),
                      subtitle: Text(item['description'] ?? ''),
                      trailing: Text(item['value']?.toString() ?? ''),
                    );
                  },
                ),
              ),
            ),
          ] else if (!isLoading) ...[
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.assessment, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text(
                      'Select report type and generate to view results',
                      style: TextStyle(color: Colors.grey[600], fontSize: 16),
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
}

// Analysis Tab - For analyzing HOD and Staff attendance by Admin
class AnalysisTab extends StatefulWidget {
  final String token;

  const AnalysisTab({super.key, required this.token});

  @override
  State<AnalysisTab> createState() => _AnalysisTabState();
}

class _AnalysisTabState extends State<AnalysisTab> {
  List<String> departments = [];
  List<String> otherStaffDepartments = []; // New: Other staff departments
  String departmentType =
      'regular'; // 'regular' or 'other' - to track which department type is selected
  List<dynamic> hods = [];
  List<dynamic> staff = [];
  List<dynamic> otherStaff = []; // New: Other staff list

  String? selectedDepartment;
  String? selectedRole; // 'hod' or 'staff'
  dynamic selectedPerson;

  DateTime? startDate;
  DateTime? endDate;

  bool isLoading = false;
  Map<String, dynamic>? attendanceStats;
  Map<String, dynamic>? clStatus;
  List<dynamic>? attendanceRecords;
  List<String>? datesPresent;
  List<Map<String, DateTime>> academicRanges = [];

  // Report generation state
  bool isGeneratingReport = false;
  bool isDownloadingReport = false;

  // All staff analysis state
  bool isAnalyzingAllStaff = false;
  List<Map<String, dynamic>>? allStaffAttendanceStats;

  // All staff PDF generation state
  bool isGeneratingAllStaffPdf = false;
  Map<String, dynamic>? allStaffGeneratedReport;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() => isLoading = true);
    try {
      // Fetch all initial data concurrently in parallel
      final results = await Future.wait([
        apiClient.get(
          '$API_URL/admin/departments',
          token: widget.token,
          cacheKey: 'admin_departments',
          cacheDuration: const Duration(minutes: 5),
        ),
        apiClient.get(
          '$API_URL/admin/other_staff',
          token: widget.token,
          cacheKey: 'admin_other_staff',
          cacheDuration: const Duration(minutes: 3),
        ),
        apiClient.get(
          '$API_URL/admin/attendance/hods',
          token: widget.token,
          cacheKey: 'admin_hods',
          cacheDuration: const Duration(minutes: 3),
        ),
        apiClient.get(
          '$API_URL/academics/current',
          cacheKey: 'academics_current',
          cacheDuration: const Duration(minutes: 10),
        ),
        apiClient.get(
          '$API_URL/admin/attendance/staff-list',
          token: widget.token,
          cacheKey: 'admin_staff_attendance_list',
          cacheDuration: const Duration(minutes: 3),
        ),
      ]);

      final deptResponse = results[0];
      final otherStaffResponse = results[1];
      final hodResponse = results[2];
      final acadResponse = results[3];
      final staffResponse = results[4];

      // Parse departments
      if (deptResponse.statusCode == 200) {
        final deptData = jsonDecode(deptResponse.body);
        departments =
            (deptData['departments'] as List)
                .map((d) => d['name'].toString())
                .toList()
              ..sort();
      }

      // Parse other staff & departments
      if (otherStaffResponse.statusCode == 200) {
        final otherData = jsonDecode(otherStaffResponse.body);
        final staffList = otherData['other_staff'] ?? [];
        final Set<String> uniqueDepts = {};
        for (final s in staffList) {
          final dept = (s['dept']?.toString().trim().isNotEmpty ?? false)
              ? s['dept'].toString().trim()
              : 'Unassigned';
          uniqueDepts.add(dept);
        }
        otherStaffDepartments = uniqueDepts.toList()..sort();
        otherStaff = staffList;
      }

      // Parse HODs
      if (hodResponse.statusCode == 200) {
        final hodData = jsonDecode(hodResponse.body);
        hods = hodData['hods'] ?? [];
      }

      // Parse academic ranges
      if (acadResponse.statusCode == 200) {
        try {
          final acadData = jsonDecode(acadResponse.body);
          final rawRanges = acadData['academic_ranges'] as List? ?? [];
          final parsed = <Map<String, DateTime>>[];
          for (final r in rawRanges) {
            final s = DateTime.tryParse(r['start']?.toString() ?? '');
            final e = DateTime.tryParse(r['end']?.toString() ?? '');
            if (s != null && e != null) {
              parsed.add({'start': s, 'end': e});
            }
          }
          if (parsed.isNotEmpty) {
            academicRanges = parsed;
          }
        } catch (_) {}
      }

      // Parse staff list
      if (staffResponse.statusCode == 200) {
        final staffData = jsonDecode(staffResponse.body);
        staff = staffData['staff'] ?? [];
      }

      setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading data: $e')));
      }
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _fetchAttendance() async {
    if (selectedPerson == null || startDate == null || endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select person and date range')),
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      final regNo = selectedPerson['reg_no'];
      final startDateStr =
          '${startDate!.year}-${startDate!.month.toString().padLeft(2, '0')}-${startDate!.day.toString().padLeft(2, '0')}';
      final endDateStr =
          '${endDate!.year}-${endDate!.month.toString().padLeft(2, '0')}-${endDate!.day.toString().padLeft(2, '0')}';

      // Use different API based on department type
      String apiUrl;
      if (departmentType == 'other') {
        apiUrl =
            '$API_URL/admin/other_staff/attendance?reg_no=$regNo&start_date=$startDateStr&end_date=$endDateStr';
      } else {
        apiUrl =
            '$API_URL/admin/attendance/person-details?reg_no=$regNo&start_date=$startDateStr&end_date=$endDateStr';
      }

      final response = await http.get(
        Uri.parse(apiUrl),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('Attendance data received: $data');

        // Handle both API response formats
        List<String> datesList = [];
        List<dynamic> records = [];

        if (departmentType == 'other') {
          // Other staff API returns 'attendance' array
          records = data['attendance'] ?? [];
          // Extract unique dates from attendance records
          final Set<String> uniqueDates = {};
          for (var record in records) {
            final timestamp = record['timestamp']?.toString() ?? '';
            if (timestamp.isNotEmpty) {
              // Handle both "2024-03-11 07:04:29" and "2024-03-11T07:04:29" formats
              final date = timestamp.contains(' ')
                  ? timestamp.split(' ')[0]
                  : (timestamp.contains('T')
                        ? timestamp.split('T')[0]
                        : timestamp);
              uniqueDates.add(date);
            }
          }
          datesList = uniqueDates.toList();
        } else {
          // Regular API returns 'dates_present' and 'attendance_records'
          datesList = List<String>.from(data['dates_present'] ?? []);
          records = data['attendance_records'] ?? [];
        }

        debugPrint('Dates present: $datesList');
        setState(() {
          datesPresent = datesList;
          attendanceRecords = records;

          // Calculate total days in range
          final totalDays = endDate!.difference(startDate!).inDays + 1;
          final presentDays = datesList.length;
          final absentDays = totalDays - presentDays;

          // Determine role display
          String roleDisplay;
          if (departmentType == 'other') {
            roleDisplay = selectedPerson['role']?.toString() ?? 'Other Staff';
          } else {
            roleDisplay = selectedRole == 'hod' ? 'HOD' : 'Staff';
          }

          attendanceStats = {
            'total_days': totalDays,
            'present_days': presentDays,
            'absent_days': absentDays,
            'person_name': selectedPerson['name'],
            'person_role': roleDisplay,
            'department': selectedPerson['dept'],
            'reg_no': selectedPerson['reg_no'],
          };
        });

        // Generate and download PDF for individual staff
        await _generateAndDownloadIndividualPdf();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to fetch attendance')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${cleanAdminErrorMessage(e)}')));
      }
    } finally {
      setState(() => isLoading = false);
    }
  }

  // Method to generate and download PDF for individual staff
  Future<void> _generateAndDownloadIndividualPdf() async {
    if (attendanceStats == null) return;

    setState(() => isGeneratingReport = true);

    // Fetch CL status
    Map<String, dynamic>? clData;
    try {
      final regNo = attendanceStats!['reg_no'].toString();
      final clResponse = await http.get(
        Uri.parse('$API_URL/cl/status/$regNo'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (clResponse.statusCode == 200) {
        final clJson = json.decode(clResponse.body);
        if (clJson['success'] == true) {
          clData = clJson['data'];
        }
      }
    } catch (e) {
      // CL fetch failed, continue without CL data
    }

    try {
      final personName = attendanceStats!['person_name'].toString().replaceAll(
        ' ',
        '_',
      );
      final regNo = selectedPerson['reg_no'].toString();
      final startDateStr =
          '${startDate!.year}${startDate!.month.toString().padLeft(2, '0')}${startDate!.day.toString().padLeft(2, '0')}';
      final endDateStr =
          '${endDate!.year}${endDate!.month.toString().padLeft(2, '0')}${endDate!.day.toString().padLeft(2, '0')}';
      final filename =
          'attendance_report_${personName}_${regNo}_${startDateStr}_to_$endDateStr.pdf';

      final pdf = pw.Document();

      final totalDays = attendanceStats!['total_days'] as int;
      final presentDays = attendanceStats!['present_days'] as int;
      final absentDays = attendanceStats!['absent_days'] as int;
      final percentage = totalDays > 0
          ? (presentDays / totalDays * 100).toStringAsFixed(2)
          : '0.00';

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (context) => [
            // Header
            pw.Header(
              level: 0,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'INDIVIDUAL ATTENDANCE REPORT',
                    style: pw.TextStyle(
                      fontSize: 24,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Generated: ${DateTime.now().toIso8601String()}',
                    style: const pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.grey700,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 20),

            // Person Information Section
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.deepPurple),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'PERSON INFORMATION',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.deepPurple,
                    ),
                  ),
                  pw.Divider(color: PdfColors.deepPurple200),
                  pw.SizedBox(height: 8),
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 4),
                    child: pw.Row(
                      children: [
                        pw.SizedBox(
                          width: 120,
                          child: pw.Text(
                            'Name:',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Text(attendanceStats!['person_name'].toString()),
                      ],
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 4),
                    child: pw.Row(
                      children: [
                        pw.SizedBox(
                          width: 120,
                          child: pw.Text(
                            'Registration No:',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Text(regNo),
                      ],
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 4),
                    child: pw.Row(
                      children: [
                        pw.SizedBox(
                          width: 120,
                          child: pw.Text(
                            'Role:',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Text(attendanceStats!['person_role'].toString()),
                      ],
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 4),
                    child: pw.Row(
                      children: [
                        pw.SizedBox(
                          width: 120,
                          child: pw.Text(
                            'Department:',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Text(attendanceStats!['department'].toString()),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),

            // Analysis Period Section
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.blue),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'ANALYSIS PERIOD',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blue,
                    ),
                  ),
                  pw.Divider(color: PdfColors.blue200),
                  pw.SizedBox(height: 8),
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 4),
                    child: pw.Row(
                      children: [
                        pw.SizedBox(
                          width: 100,
                          child: pw.Text(
                            'Start Date:',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Text(
                          '${startDate!.year}-${startDate!.month.toString().padLeft(2, '0')}-${startDate!.day.toString().padLeft(2, '0')}',
                        ),
                      ],
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 4),
                    child: pw.Row(
                      children: [
                        pw.SizedBox(
                          width: 100,
                          child: pw.Text(
                            'End Date:',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Text(
                          '${endDate!.year}-${endDate!.month.toString().padLeft(2, '0')}-${endDate!.day.toString().padLeft(2, '0')}',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),

            // Attendance Summary Section
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.green),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'ATTENDANCE SUMMARY',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.green,
                    ),
                  ),
                  pw.Divider(color: PdfColors.green200),
                  pw.SizedBox(height: 8),
                  pw.Row(
                    children: [
                      pw.Expanded(
                        child: pw.Container(
                          padding: const pw.EdgeInsets.all(8),
                          decoration: pw.BoxDecoration(
                            color: PdfColors.grey100,
                            borderRadius: pw.BorderRadius.circular(4),
                          ),
                          child: pw.Column(
                            children: [
                              pw.Text(
                                'Total Days',
                                style: const pw.TextStyle(
                                  fontSize: 10,
                                  color: PdfColors.grey700,
                                ),
                              ),
                              pw.SizedBox(height: 4),
                              pw.Text(
                                totalDays.toString(),
                                style: pw.TextStyle(
                                  fontSize: 16,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      pw.SizedBox(width: 8),
                      pw.Expanded(
                        child: pw.Container(
                          padding: const pw.EdgeInsets.all(8),
                          decoration: pw.BoxDecoration(
                            color: PdfColors.green100,
                            borderRadius: pw.BorderRadius.circular(4),
                          ),
                          child: pw.Column(
                            children: [
                              pw.Text(
                                'Present',
                                style: const pw.TextStyle(
                                  fontSize: 10,
                                  color: PdfColors.green700,
                                ),
                              ),
                              pw.SizedBox(height: 4),
                              pw.Text(
                                presentDays.toString(),
                                style: pw.TextStyle(
                                  fontSize: 16,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.green,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      pw.SizedBox(width: 8),
                      pw.Expanded(
                        child: pw.Container(
                          padding: const pw.EdgeInsets.all(8),
                          decoration: pw.BoxDecoration(
                            color: PdfColors.red100,
                            borderRadius: pw.BorderRadius.circular(4),
                          ),
                          child: pw.Column(
                            children: [
                              pw.Text(
                                'Absent',
                                style: const pw.TextStyle(
                                  fontSize: 10,
                                  color: PdfColors.red700,
                                ),
                              ),
                              pw.SizedBox(height: 4),
                              pw.Text(
                                absentDays.toString(),
                                style: pw.TextStyle(
                                  fontSize: 16,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.red,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      pw.SizedBox(width: 8),
                      pw.Expanded(
                        child: pw.Container(
                          padding: const pw.EdgeInsets.all(8),
                          decoration: pw.BoxDecoration(
                            color: PdfColors.blue100,
                            borderRadius: pw.BorderRadius.circular(4),
                          ),
                          child: pw.Column(
                            children: [
                              pw.Text(
                                'Percentage',
                                style: const pw.TextStyle(
                                  fontSize: 10,
                                  color: PdfColors.blue700,
                                ),
                              ),
                              pw.SizedBox(height: 4),
                              pw.Text(
                                '$percentage%',
                                style: pw.TextStyle(
                                  fontSize: 16,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.blue,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),

            // Casual Leave Summary Section (only if CL data available)
            if (clData != null)
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.orange),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'CASUAL LEAVE STATUS',
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.orange,
                      ),
                    ),
                    pw.Divider(color: PdfColors.orange200),
                    pw.SizedBox(height: 8),
                    pw.Row(
                      children: [
                        pw.Expanded(
                          child: pw.Container(
                            padding: const pw.EdgeInsets.all(8),
                            decoration: pw.BoxDecoration(
                              color: PdfColors.orange100,
                              borderRadius: pw.BorderRadius.circular(4),
                            ),
                            child: pw.Column(
                              children: [
                                pw.Text(
                                  'This Month',
                                  style: const pw.TextStyle(
                                    fontSize: 10,
                                    color: PdfColors.orange700,
                                  ),
                                ),
                                pw.SizedBox(height: 4),
                                pw.Text(
                                  clData['current_month_cl_available']
                                      .toString(),
                                  style: pw.TextStyle(
                                    fontSize: 16,
                                    fontWeight: pw.FontWeight.bold,
                                    color: PdfColors.orange,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        pw.SizedBox(width: 8),
                        pw.Expanded(
                          child: pw.Container(
                            padding: const pw.EdgeInsets.all(8),
                            decoration: pw.BoxDecoration(
                              color: PdfColors.purple100,
                              borderRadius: pw.BorderRadius.circular(4),
                            ),
                            child: pw.Column(
                              children: [
                                pw.Text(
                                  'Accumulated',
                                  style: const pw.TextStyle(
                                    fontSize: 10,
                                    color: PdfColors.purple700,
                                  ),
                                ),
                                pw.SizedBox(height: 4),
                                pw.Text(
                                  clData['accumulated_cl'].toString(),
                                  style: pw.TextStyle(
                                    fontSize: 16,
                                    fontWeight: pw.FontWeight.bold,
                                    color: PdfColors.purple,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        pw.SizedBox(width: 8),
                        pw.Expanded(
                          child: pw.Container(
                            padding: const pw.EdgeInsets.all(8),
                            decoration: pw.BoxDecoration(
                              color: PdfColors.red100,
                              borderRadius: pw.BorderRadius.circular(4),
                            ),
                            child: pw.Column(
                              children: [
                                pw.Text(
                                  'Used',
                                  style: const pw.TextStyle(
                                    fontSize: 10,
                                    color: PdfColors.red700,
                                  ),
                                ),
                                pw.SizedBox(height: 4),
                                pw.Text(
                                  clData['cl_used_current_month'].toString(),
                                  style: pw.TextStyle(
                                    fontSize: 16,
                                    fontWeight: pw.FontWeight.bold,
                                    color: PdfColors.red,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        pw.SizedBox(width: 8),
                        pw.Expanded(
                          child: pw.Container(
                            padding: const pw.EdgeInsets.all(8),
                            decoration: pw.BoxDecoration(
                              color: PdfColors.green100,
                              borderRadius: pw.BorderRadius.circular(4),
                            ),
                            child: pw.Column(
                              children: [
                                pw.Text(
                                  'Total Available',
                                  style: const pw.TextStyle(
                                    fontSize: 10,
                                    color: PdfColors.green700,
                                  ),
                                ),
                                pw.SizedBox(height: 4),
                                pw.Text(
                                  clData['total_cl_available'].toString(),
                                  style: pw.TextStyle(
                                    fontSize: 16,
                                    fontWeight: pw.FontWeight.bold,
                                    color: PdfColors.green,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      );

      await Printing.sharePdf(bytes: await pdf.save(), filename: filename);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PDF report downloaded successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => isGeneratingReport = false);
    }
  }

  // Method to analyze all staff in the selected department
  Future<void> _analyzeAllStaffInDepartment() async {
    if (selectedDepartment == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a department first')),
      );
      return;
    }

    if (startDate == null || endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select date range first')),
      );
      return;
    }

    setState(() => isAnalyzingAllStaff = true);

    try {
      // Get all staff in the selected department based on department type
      List<dynamic> departmentStaff;
      if (departmentType == 'other') {
        departmentStaff = otherStaff
            .where((s) => s['dept'] == selectedDepartment)
            .toList();
      } else {
        // Combine staff and hods for the selected department
        final staffInDept = staff
            .where((s) => s['dept'] == selectedDepartment)
            .toList();
        final hodsInDept = hods
            .where((h) => h['dept'] == selectedDepartment)
            .toList();
        departmentStaff = [...staffInDept, ...hodsInDept];
      }

      if (departmentStaff.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No staff found in the selected department'),
            ),
          );
        }
        return;
      }

      final startDateStr =
          '${startDate!.year}-${startDate!.month.toString().padLeft(2, '0')}-${startDate!.day.toString().padLeft(2, '0')}';
      final endDateStr =
          '${endDate!.year}-${endDate!.month.toString().padLeft(2, '0')}-${endDate!.day.toString().padLeft(2, '0')}';

      // Fetch all staff members' attendance & CL status in parallel
      final List<Map<String, dynamic>> allStats = await Future.wait(
        departmentStaff.map((person) async {
          final regNo = person['reg_no'];
          String apiUrl;
          if (departmentType == 'other') {
            apiUrl =
                '$API_URL/admin/other_staff/attendance?reg_no=$regNo&start_date=$startDateStr&end_date=$endDateStr';
          } else {
            apiUrl =
                '$API_URL/admin/attendance/person-details?reg_no=$regNo&start_date=$startDateStr&end_date=$endDateStr';
          }

          // Fetch attendance and CL status concurrently for this person
          final personResponses = await Future.wait([
            apiClient.get(apiUrl, token: widget.token),
            apiClient.get(
              '$API_URL/cl/status/$regNo',
              token: widget.token,
              cacheKey: 'cl_status_$regNo',
              cacheDuration: const Duration(minutes: 2),
            ),
          ]);

          final attResponse = personResponses[0];
          final clResponse = personResponses[1];

          List<String> datesPresent = [];
          List<dynamic> records = [];
          int? serverTotalDays;
          int? serverAbsentDays;

          if (attResponse.statusCode == 200) {
            final data = jsonDecode(attResponse.body);
            if (departmentType == 'other') {
              records = data['attendance'] ?? [];
              serverTotalDays = data['working_days'] as int?;
              serverAbsentDays = data['absent_days'] as int?;
              final Set<String> uniqueDates = {};
              for (var record in records) {
                final timestamp = record['timestamp']?.toString() ?? '';
                if (timestamp.isNotEmpty) {
                  final date = timestamp.contains(' ')
                      ? timestamp.split(' ')[0]
                      : (timestamp.contains('T')
                            ? timestamp.split('T')[0]
                            : timestamp);
                  uniqueDates.add(date);
                }
              }
              datesPresent = uniqueDates.toList();
            } else {
              datesPresent = List<String>.from(data['dates_present'] ?? []);
              records = data['attendance_records'] ?? [];
              serverTotalDays = data['working_days'] as int?;
              serverAbsentDays = data['absent_days'] as int?;
            }
          }

          // Calculate total days in range
          final int totalDays =
              serverTotalDays ?? endDate!.difference(startDate!).inDays + 1;
          final int presentDays = datesPresent.length;
          final int absentDays = serverAbsentDays ?? totalDays - presentDays;

          // Determine role display
          String roleDisplay;
          if (departmentType == 'other') {
            roleDisplay = person['role']?.toString() ?? 'Other Staff';
          } else {
            final isHod = hods.any((h) => h['reg_no'] == regNo);
            roleDisplay = isHod ? 'HOD' : 'Staff';
          }

          // Parse CL status
          int totalCLAvailable = 0;
          int clUsedCurrentMonth = 0;
          if (clResponse.statusCode == 200) {
            try {
              final clJson = json.decode(clResponse.body);
              if (clJson['success'] == true && clJson['data'] != null) {
                totalCLAvailable =
                    (clJson['data']['total_cl_available'] as num? ?? 0).toInt();
                clUsedCurrentMonth =
                    (clJson['data']['cl_used_current_month'] as num? ?? 0)
                        .toInt();
              }
            } catch (_) {}
          }

          return {
            'person_name': person['name'],
            'person_reg_no': regNo,
            'person_role': roleDisplay,
            'department': person['dept'],
            'total_days': totalDays,
            'present_days': presentDays,
            'absent_days': absentDays,
            'attendance_percentage': totalDays > 0
                ? (presentDays / totalDays * 100).toStringAsFixed(2)
                : '0.00',
            'dates_present': datesPresent,
            'attendance_records': records,
            'total_cl_available': totalCLAvailable,
            'cl_used_current_month': clUsedCurrentMonth,
          };
        }),
      );

      setState(() {
        allStaffAttendanceStats = allStats;
        allStaffGeneratedReport = null; // Clear previous generated report
      });

      // Generate and download PDF report automatically
      await _generateAndDownloadDepartmentPdf();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Analyzed ${allStats.length} staff in $selectedDepartment',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error analyzing staff: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => isAnalyzingAllStaff = false);
    }
  }

  // Method to generate and download PDF report for all staff in department
  Future<void> _generateAndDownloadDepartmentPdf() async {
    if (allStaffAttendanceStats == null || allStaffAttendanceStats!.isEmpty) {
      return;
    }

    setState(() => isGeneratingAllStaffPdf = true);

    try {
      final staffStats = allStaffAttendanceStats!;
      final deptName = selectedDepartment?.replaceAll(' ', '_') ?? 'Department';
      final startDateStr =
          '${startDate!.year}${startDate!.month.toString().padLeft(2, '0')}${startDate!.day.toString().padLeft(2, '0')}';
      final endDateStr =
          '${endDate!.year}${endDate!.month.toString().padLeft(2, '0')}${endDate!.day.toString().padLeft(2, '0')}';
      final filename =
          'attendance_report_${deptName}_${startDateStr}_to_$endDateStr.pdf';

      final pdf = pw.Document();

      // Calculate summary statistics
      double totalAttendance = 0;
      for (final staff in staffStats) {
        totalAttendance +=
            double.tryParse(staff['attendance_percentage'].toString()) ?? 0;
      }
      final avgAttendance = staffStats.isNotEmpty
          ? (totalAttendance / staffStats.length)
          : 0.0;

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (context) => [
            // Header
            pw.Header(
              level: 0,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'DEPARTMENT ATTENDANCE REPORT',
                    style: pw.TextStyle(
                      fontSize: 24,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Generated: ${DateTime.now().toIso8601String()}',
                    style: const pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.grey700,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 20),

            // Department Information Section
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.deepPurple),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'DEPARTMENT INFORMATION',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.deepPurple,
                    ),
                  ),
                  pw.Divider(color: PdfColors.deepPurple200),
                  pw.SizedBox(height: 8),
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 4),
                    child: pw.Row(
                      children: [
                        pw.SizedBox(
                          width: 100,
                          child: pw.Text(
                            'Department:',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Text(selectedDepartment ?? ''),
                      ],
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 4),
                    child: pw.Row(
                      children: [
                        pw.SizedBox(
                          width: 100,
                          child: pw.Text(
                            'Total Staff:',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Text(staffStats.length.toString()),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),

            // Analysis Period Section
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.blue),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'ANALYSIS PERIOD',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blue,
                    ),
                  ),
                  pw.Divider(color: PdfColors.blue200),
                  pw.SizedBox(height: 8),
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 4),
                    child: pw.Row(
                      children: [
                        pw.SizedBox(
                          width: 100,
                          child: pw.Text(
                            'Start Date:',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Text(
                          '${startDate!.year}-${startDate!.month.toString().padLeft(2, '0')}-${startDate!.day.toString().padLeft(2, '0')}',
                        ),
                      ],
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 4),
                    child: pw.Row(
                      children: [
                        pw.SizedBox(
                          width: 100,
                          child: pw.Text(
                            'End Date:',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Text(
                          '${endDate!.year}-${endDate!.month.toString().padLeft(2, '0')}-${endDate!.day.toString().padLeft(2, '0')}',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),

            // Summary Section
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.green),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'SUMMARY',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.green,
                    ),
                  ),
                  pw.Divider(color: PdfColors.green200),
                  pw.SizedBox(height: 8),
                  pw.Row(
                    children: [
                      pw.Expanded(
                        child: pw.Container(
                          padding: const pw.EdgeInsets.all(8),
                          decoration: pw.BoxDecoration(
                            color: PdfColors.grey100,
                            borderRadius: pw.BorderRadius.circular(4),
                          ),
                          child: pw.Column(
                            children: [
                              pw.Text(
                                'Total Staff',
                                style: const pw.TextStyle(
                                  fontSize: 10,
                                  color: PdfColors.grey700,
                                ),
                              ),
                              pw.SizedBox(height: 4),
                              pw.Text(
                                staffStats.length.toString(),
                                style: pw.TextStyle(
                                  fontSize: 16,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      pw.SizedBox(width: 8),
                      pw.Expanded(
                        child: pw.Container(
                          padding: const pw.EdgeInsets.all(8),
                          decoration: pw.BoxDecoration(
                            color: PdfColors.blue100,
                            borderRadius: pw.BorderRadius.circular(4),
                          ),
                          child: pw.Column(
                            children: [
                              pw.Text(
                                'Average Attendance',
                                style: const pw.TextStyle(
                                  fontSize: 10,
                                  color: PdfColors.blue700,
                                ),
                              ),
                              pw.SizedBox(height: 4),
                              pw.Text(
                                '${avgAttendance.toStringAsFixed(1)}%',
                                style: pw.TextStyle(
                                  fontSize: 16,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.blue,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 20),

            // Staff Details Table
            pw.Text(
              'STAFF ATTENDANCE DETAILS',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),

            // Table header
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.deepPurple,
              ),
              cellHeight: 25,
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.center,
                3: pw.Alignment.center,
                4: pw.Alignment.center,
                5: pw.Alignment.center,
                6: pw.Alignment.center,
                7: pw.Alignment.center,
              },
              headers: [
                'Name',
                'Reg No',
                'Pre',
                'Abs',
                'Total',
                'Percentage',
                'Used CL',
                'TCL',
              ],
              data: staffStats
                  .map<List<String>>(
                    (staff) => [
                      staff['person_name'].toString(),
                      staff['person_reg_no'].toString(),
                      staff['present_days'].toString(),
                      staff['absent_days'].toString(),
                      staff['total_days'].toString(),
                      '${staff['attendance_percentage']}%',
                      staff['cl_used_current_month']?.toString() ?? '-',
                      staff['total_cl_available']?.toString() ?? '-',
                    ],
                  )
                  .toList(),
            ),
          ],
        ),
      );

      // Generate and download PDF directly without preview
      await Printing.sharePdf(bytes: await pdf.save(), filename: filename);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PDF report generated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => isGeneratingAllStaffPdf = false);
    }
  }

  Future<void> _selectDateRange() async {
    // Show custom calendar in a bottom sheet
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Select Date Range',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepPurple,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.grey[200],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Custom Calendar
            Expanded(
              child: SingleChildScrollView(
                child: CustomDateRangeCalendar(
                  startDate: startDate,
                  endDate: endDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                  academicRanges: academicRanges.isNotEmpty ? academicRanges : null,
                  onDateRangeSelected: (DateTime newStart, DateTime newEnd) {
                    setState(() {
                      startDate = newStart;
                      endDate = newEnd;
                      attendanceStats = null;
                      attendanceRecords = null;
                      datesPresent = null;
                    });
                    Navigator.pop(context);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Week navigation methods for Analysis tab
  void _goToPreviousWeek() {
    if (startDate != null && endDate != null) {
      setState(() {
        startDate = startDate!.subtract(const Duration(days: 7));
        endDate = endDate!.subtract(const Duration(days: 7));
        attendanceStats = null;
        attendanceRecords = null;
        datesPresent = null;
      });
    }
  }

  void _goToNextWeek() {
    final now = DateTime.now();
    if (startDate != null && endDate != null) {
      final newEndDate = endDate!.add(const Duration(days: 7));
      if (newEndDate.isAfter(now)) {
        return;
      }
      setState(() {
        startDate = startDate!.add(const Duration(days: 7));
        endDate = newEndDate;
        attendanceStats = null;
        attendanceRecords = null;
        datesPresent = null;
      });
    }
  }

  List<dynamic> get filteredPersons {
    List<dynamic> persons;

    // If other staff department type is selected, use otherStaff list
    if (departmentType == 'other') {
      persons = otherStaff;
    } else {
      persons = selectedRole == 'hod' ? hods : staff;
    }

    if (selectedDepartment != null) {
      persons = persons.where((p) => p['dept'] == selectedDepartment).toList();
    }

    return persons;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final pagePadding = AdminBreakpoints.pagePadding(screenWidth);
    final cardBg = isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.90);
    final borderClr = isDark ? Colors.white.withValues(alpha: 0.10) : Colors.indigo.withValues(alpha: 0.12);

    return Container(
      color: AdminColors.getSurface(isDark),
      child: Column(
        children: [
          // Scrollable content
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.all(pagePadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Premium Header Banner ──────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isDark
                              ? [const Color(0xFF1A0078), const Color(0xFF00695C)]
                              : [const Color(0xFF3949AB), const Color(0xFF00ACC1)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.indigo.withValues(alpha: 0.35),
                            blurRadius: 22,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.analytics_rounded, color: Colors.white, size: 26),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Attendance Analysis',
                                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  'Select department, role and person to analyze',
                                  style: TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // ── Glassmorphic Filter Panel ────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: borderClr),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.indigo.withValues(alpha: 0.06),
                            blurRadius: 14,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Filter label
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFF3949AB), Color(0xFF00ACC1)],
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(Icons.tune_rounded, color: Colors.white, size: 15),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Analysis Filters',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: isDark ? Colors.white : Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),

                              // Department Type & Department dropdowns
                              isMobile
                                  ? Column(
                                      children: [
                                        _buildStyledDropdown(
                                          child: DropdownButton<String>(
                                            value: departmentType,
                                            isExpanded: true,
                                            underline: const SizedBox(),
                                            hint: const Text('Dept Type'),
                                            items: const [
                                              DropdownMenuItem(value: 'regular', child: Text('Regular Depts')),
                                              DropdownMenuItem(value: 'other', child: Text('Other Staff Depts')),
                                            ],
                                            onChanged: (value) {
                                              setState(() {
                                                departmentType = value ?? 'regular';
                                                selectedDepartment = null;
                                                selectedRole = null;
                                                selectedPerson = null;
                                                attendanceStats = null;
                                              });
                                            },
                                          ),
                                          isDark: isDark,
                                        ),
                                        const SizedBox(height: 10),
                                        _buildStyledDropdown(
                                          child: DropdownButton<String>(
                                            value: selectedDepartment,
                                            isExpanded: true,
                                            underline: const SizedBox(),
                                            hint: const Text('Department'),
                                            items: [
                                              const DropdownMenuItem(value: null, child: Text('All Departments')),
                                              ...(departmentType == 'regular' ? departments : otherStaffDepartments)
                                                  .map((dept) => DropdownMenuItem(value: dept, child: Text(dept))),
                                            ],
                                            onChanged: (value) {
                                              setState(() {
                                                selectedDepartment = value;
                                                selectedPerson = null;
                                                attendanceStats = null;
                                              });
                                            },
                                          ),
                                          isDark: isDark,
                                        ),
                                        if (departmentType == 'regular') ...[
                                          const SizedBox(height: 10),
                                          _buildStyledDropdown(
                                            child: DropdownButton<String>(
                                              value: selectedRole,
                                              isExpanded: true,
                                              underline: const SizedBox(),
                                              hint: const Text('Role'),
                                              items: const [
                                                DropdownMenuItem(value: 'hod', child: Text('HOD')),
                                                DropdownMenuItem(value: 'staff', child: Text('Staff')),
                                              ],
                                              onChanged: (value) {
                                                setState(() {
                                                  selectedRole = value;
                                                  selectedPerson = null;
                                                  attendanceStats = null;
                                                });
                                              },
                                            ),
                                            isDark: isDark,
                                          ),
                                        ],
                                      ],
                                    )
                                  : Row(
                                      children: [
                                        Expanded(
                                          child: _buildStyledDropdown(
                                            child: DropdownButton<String>(
                                              value: departmentType,
                                              isExpanded: true,
                                              underline: const SizedBox(),
                                              hint: const Text('Type'),
                                              items: const [
                                                DropdownMenuItem(value: 'regular', child: Text('Regular Depts')),
                                                DropdownMenuItem(value: 'other', child: Text('Other Staff Depts')),
                                              ],
                                              onChanged: (value) {
                                                setState(() {
                                                  departmentType = value ?? 'regular';
                                                  selectedDepartment = null;
                                                  selectedRole = null;
                                                  selectedPerson = null;
                                                  attendanceStats = null;
                                                });
                                              },
                                            ),
                                            isDark: isDark,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: _buildStyledDropdown(
                                            child: DropdownButton<String>(
                                              value: selectedDepartment,
                                              isExpanded: true,
                                              underline: const SizedBox(),
                                              hint: const Text('Department'),
                                              items: [
                                                const DropdownMenuItem(value: null, child: Text('All Departments')),
                                                ...(departmentType == 'regular' ? departments : otherStaffDepartments)
                                                    .map((dept) => DropdownMenuItem(value: dept, child: Text(dept))),
                                              ],
                                              onChanged: (value) {
                                                setState(() {
                                                  selectedDepartment = value;
                                                  selectedPerson = null;
                                                  attendanceStats = null;
                                                });
                                              },
                                            ),
                                            isDark: isDark,
                                          ),
                                        ),
                                        if (departmentType == 'regular') ...[
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: _buildStyledDropdown(
                                              child: DropdownButton<String>(
                                                value: selectedRole,
                                                isExpanded: true,
                                                underline: const SizedBox(),
                                                hint: const Text('Role'),
                                                items: const [
                                                  DropdownMenuItem(value: 'hod', child: Text('HOD')),
                                                  DropdownMenuItem(value: 'staff', child: Text('Staff')),
                                                ],
                                                onChanged: (value) {
                                                  setState(() {
                                                    selectedRole = value;
                                                    selectedPerson = null;
                                                    attendanceStats = null;
                                                  });
                                                },
                                              ),
                                              isDark: isDark,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),

                              const SizedBox(height: 12),

                              // Person & Date row
                              isMobile
                                  ? Column(
                                      children: [
                                        _buildStyledDropdown(
                                          child: DropdownButton<dynamic>(
                                            value: selectedPerson,
                                            isExpanded: true,
                                            underline: const SizedBox(),
                                            hint: const Text('Select Person'),
                                            items: filteredPersons.map((person) {
                                              return DropdownMenuItem(
                                                value: person,
                                                child: Text(
                                                  '${person['name']} (${person['reg_no']})',
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              );
                                            }).toList(),
                                            onChanged: (value) {
                                              setState(() {
                                                selectedPerson = value;
                                                attendanceStats = null;
                                              });
                                            },
                                          ),
                                          isDark: isDark,
                                        ),
                                        const SizedBox(height: 10),
                                        InkWell(
                                          onTap: _selectDateRange,
                                          child: _buildDateRangeDisplay(isDark),
                                        ),
                                      ],
                                    )
                                  : Row(
                                      children: [
                                        Expanded(
                                          child: _buildStyledDropdown(
                                            child: DropdownButton<dynamic>(
                                              value: selectedPerson,
                                              isExpanded: true,
                                              underline: const SizedBox(),
                                              hint: const Text('Select Person'),
                                              items: filteredPersons.map((person) {
                                                return DropdownMenuItem(
                                                  value: person,
                                                  child: Text(
                                                    '${person['name']} (${person['reg_no']})',
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                );
                                              }).toList(),
                                              onChanged: (value) {
                                                setState(() {
                                                  selectedPerson = value;
                                                  attendanceStats = null;
                                                });
                                              },
                                            ),
                                            isDark: isDark,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Row(
                                            children: [
                                              IconButton(
                                                onPressed: _goToPreviousWeek,
                                                icon: const Icon(Icons.chevron_left_rounded),
                                                style: IconButton.styleFrom(
                                                  backgroundColor: Colors.indigo.withValues(alpha: 0.12),
                                                  foregroundColor: Colors.indigo,
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                                ),
                                                tooltip: 'Previous Week',
                                              ),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: InkWell(
                                                  onTap: _selectDateRange,
                                                  child: _buildDateRangeDisplay(isDark),
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              IconButton(
                                                onPressed: _goToNextWeek,
                                                icon: const Icon(Icons.chevron_right_rounded),
                                                style: IconButton.styleFrom(
                                                  backgroundColor: Colors.indigo.withValues(alpha: 0.12),
                                                  foregroundColor: Colors.indigo,
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                                ),
                                                tooltip: 'Next Week',
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Analyze button
                    _buildAnalyzeButton(isMobile),

                    const SizedBox(height: 20),

                    // Results Section
                    isLoading || isAnalyzingAllStaff
                        ? const Padding(
                            padding: EdgeInsets.all(32),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        : allStaffAttendanceStats != null &&
                              allStaffAttendanceStats!.isNotEmpty
                        ? _buildAllStaffAttendanceStats()
                        : attendanceStats != null
                        ? _buildAttendanceStats()
                        : _buildEmptyState(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStyledDropdown({required Widget child, required bool isDark}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.indigo.withValues(alpha: isDark ? 0.30 : 0.25)),
        borderRadius: BorderRadius.circular(10),
        color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white.withValues(alpha: 0.6),
      ),
      child: child,
    );
  }

  Widget _buildDateRangeDisplay(bool isDark) {
    final dateStr = startDate != null && endDate != null
        ? '${startDate!.day.toString().padLeft(2, '0')}/${startDate!.month.toString().padLeft(2, '0')}/${startDate!.year.toString().substring(2)} – ${endDate!.day.toString().padLeft(2, '0')}/${endDate!.month.toString().padLeft(2, '0')}/${endDate!.year.toString().substring(2)}'
        : 'Select Date Range';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.indigo.withValues(alpha: isDark ? 0.30 : 0.25)),
        borderRadius: BorderRadius.circular(10),
        color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white.withValues(alpha: 0.6),
      ),
      child: Row(
        children: [
          Icon(Icons.date_range_rounded, color: Colors.indigo.withValues(alpha: 0.7), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              dateStr,
              style: TextStyle(
                color: startDate != null
                    ? (isDark ? Colors.white : Colors.black87)
                    : (isDark ? Colors.white38 : Colors.grey[500]),
                fontSize: 13,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // Helper method to build context-sensitive analyze button
  Widget _buildAnalyzeButton(bool isMobile) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Determine which analysis type is selected based on dropdowns
    final bool isIndividualMode = selectedPerson != null;
    final bool isDepartmentMode = selectedDepartment != null && selectedPerson == null;

    // Determine button properties based on mode
    String buttonText;
    List<Color> gradColors;
    IconData buttonIcon;
    VoidCallback? onPressed;
    bool isLoadingBtn;

    if (isIndividualMode && startDate != null && endDate != null) {
      buttonText = 'Analyze Individual';
      gradColors = [const Color(0xFF3949AB), const Color(0xFF1E88E5)];
      buttonIcon = Icons.person_search_rounded;
      onPressed = _fetchAttendance;
      isLoadingBtn = this.isLoading;
    } else if (isDepartmentMode && startDate != null && endDate != null) {
      buttonText = 'Analyze Department';
      gradColors = [const Color(0xFFE65100), const Color(0xFFFF8F00)];
      buttonIcon = Icons.groups_rounded;
      onPressed = _analyzeAllStaffInDepartment;
      isLoadingBtn = isAnalyzingAllStaff;
    } else {
      buttonText = 'Select Dept, Person & Date';
      gradColors = [Colors.grey.shade400, Colors.grey.shade500];
      buttonIcon = Icons.touch_app_rounded;
      onPressed = null;
      isLoadingBtn = false;
    }

    return GestureDetector(
      onTap: isLoadingBtn ? null : onPressed,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: isMobile ? 14 : 16),
        decoration: BoxDecoration(
          gradient: onPressed != null
              ? LinearGradient(colors: gradColors, begin: Alignment.centerLeft, end: Alignment.centerRight)
              : null,
          color: onPressed == null ? (isDark ? Colors.white12 : Colors.grey.shade200) : null,
          borderRadius: BorderRadius.circular(14),
          boxShadow: onPressed != null
              ? [
                  BoxShadow(
                    color: gradColors[0].withValues(alpha: 0.40),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoadingBtn)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
              )
            else
              Icon(buttonIcon, color: onPressed != null ? Colors.white : Colors.grey, size: 22),
            const SizedBox(width: 10),
            Text(
              isLoadingBtn
                  ? (isIndividualMode ? 'Analyzing...' : 'Analyzing Staff...')
                  : buttonText,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: onPressed != null ? Colors.white : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.indigo.withValues(alpha: 0.12), Colors.cyan.withValues(alpha: 0.06)],
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.analytics_rounded, size: 56, color: Colors.indigo.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 18),
          Text(
            'Ready to Analyze',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Select department, person & date range',
            style: TextStyle(fontSize: 14, color: isDark ? Colors.white54 : Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'then tap Analyze to view attendance statistics',
            style: TextStyle(fontSize: 12, color: isDark ? Colors.white38 : Colors.grey[500]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceStats() {
    final stats = attendanceStats!;
    final presentPercent = stats['total_days'] > 0
        ? (stats['present_days'] / stats['total_days'] * 100).toStringAsFixed(1)
        : '0.0';
    final absentPercent = stats['total_days'] > 0
        ? (stats['absent_days'] / stats['total_days'] * 100).toStringAsFixed(1)
        : '0.0';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 400;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Person Info Card - Responsive
              Card(
                elevation: 2,
                child: Padding(
                  padding: EdgeInsets.all(isMobile ? 10 : 16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.deepPurple,
                        radius: isMobile ? 20 : 24,
                        child: Text(
                          stats['person_name'][0].toString().toUpperCase(),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isMobile ? 16 : 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      SizedBox(width: isMobile ? 10 : 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              stats['person_name'],
                              style: TextStyle(
                                fontSize: isMobile ? 16 : 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '${stats['person_role']} - ${stats['department']}',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: isMobile ? 12 : 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: isMobile ? 12 : 16),

              // Statistics Cards - Small and equal size
              Row(
                children: [
                  Expanded(
                    child: AnimatedStatCard(
                      title: 'Total Days',
                      value: stats['total_days'].toString(),
                      icon: Icons.calendar_month,
                      color: Colors.blue,
                      index: 0,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AnimatedStatCard(
                      title: 'Present',
                      value: stats['present_days'].toString(),
                      subtitle: '$presentPercent%',
                      icon: Icons.check_circle,
                      color: Colors.green,
                      index: 1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AnimatedStatCard(
                      title: 'Absent',
                      value: stats['absent_days'].toString(),
                      subtitle: '$absentPercent%',
                      icon: Icons.cancel,
                      color: Colors.red,
                      index: 2,
                    ),
                  ),
                ],
              ),
              SizedBox(height: isMobile ? 12 : 16),

              // Progress Bar - Responsive
              Card(
                child: Padding(
                  padding: EdgeInsets.all(isMobile ? 12 : 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Attendance Overview',
                        style: TextStyle(
                          fontSize: isMobile ? 14 : 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: isMobile ? 12 : 16),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: stats['present_days'] / stats['total_days'],
                          minHeight: isMobile ? 20 : 24,
                          backgroundColor: Colors.red.withOpacity(0.3),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Colors.green,
                          ),
                        ),
                      ),
                      SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Present: ${stats['present_days']} days',
                            style: TextStyle(
                              color: Colors.green,
                              fontSize: isMobile ? 11 : 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: isMobile ? 12 : 16),

              // Calendar View - Responsive
              Card(
                child: Padding(
                  padding: EdgeInsets.all(isMobile ? 10 : 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Calendar View',
                        style: TextStyle(
                          fontSize: isMobile ? 14 : 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: isMobile ? 8 : 12),
                      _buildCalendarGrid(isMobile: isMobile),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // Widget to display all staff attendance stats in the department
  Widget _buildAllStaffAttendanceStats() {
    final staffStats = allStaffAttendanceStats!;

    // Calculate summary statistics
    int totalStaff = staffStats.length;
    double totalAttendance = 0;
    int totalPresent = 0;
    int totalAbsent = 0;

    for (final staff in staffStats) {
      totalAttendance +=
          double.tryParse(staff['attendance_percentage'].toString()) ?? 0;
      totalPresent += staff['present_days'] as int;
      totalAbsent += staff['absent_days'] as int;
    }

    final avgAttendance = totalStaff > 0 ? (totalAttendance / totalStaff) : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Card
          Card(
            elevation: 2,
            color: Colors.deepPurple,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const CircleAvatar(
                    backgroundColor: Colors.white,
                    radius: 24,
                    child: Icon(
                      Icons.group,
                      color: Colors.deepPurple,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$selectedDepartment Department',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          '$totalStaff Staff Members Analyzed',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Summary Stats Row
          Row(
            children: [
              Expanded(
                child: AnimatedStatCard(
                  title: 'Avg Attendance',
                  value: '${avgAttendance.toStringAsFixed(1)}%',
                  icon: Icons.percent,
                  color: Colors.green,
                  index: 0,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AnimatedStatCard(
                  title: 'Total Present',
                  value: totalPresent.toString(),
                  icon: Icons.check_circle,
                  color: Colors.blue,
                  index: 1,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AnimatedStatCard(
                  title: 'Total Absent',
                  value: totalAbsent.toString(),
                  icon: Icons.cancel,
                  color: Colors.red,
                  index: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Date Range Info
          if (startDate != null && endDate != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.date_range, color: Colors.deepPurple),
                  const SizedBox(width: 8),
                  Text(
                    'Analysis: ${startDate!.day}/${startDate!.month}/${startDate!.year} - ${endDate!.day}/${endDate!.month}/${endDate!.year}',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),

          // Staff List
          const Text(
            'Staff Details',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          ...staffStats.map((staff) {
            final percentage =
                double.tryParse(staff['attendance_percentage'].toString()) ?? 0;

            Color percentageColor;
            if (percentage >= 90) {
              percentageColor = Colors.green;
            } else if (percentage >= 75) {
              percentageColor = Colors.orange;
            } else {
              percentageColor = Colors.red;
            }

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.deepPurple[100],
                  child: Text(
                    staff['person_name'][0].toString().toUpperCase(),
                    style: const TextStyle(
                      color: Colors.deepPurple,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                title: Text(
                  staff['person_name'],
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  '${staff['person_reg_no']} | Present: ${staff['present_days']} | Absent: ${staff['absent_days']}${staff['total_cl_available'] != null ? ' | CL: ${staff['total_cl_available']}' : ''}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: percentageColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: percentageColor),
                  ),
                  child: Text(
                    '${staff['attendance_percentage']}%',
                    style: TextStyle(
                      color: percentageColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildCalendarGrid({bool isMobile = false}) {
    if (startDate == null || endDate == null) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth > 0
            ? constraints.maxWidth
            : 350;
        final cellWidth = ((availableWidth - 8) / 7).floor().toDouble();
        final cellHeight = cellWidth * 1.2;

        final presentSet = datesPresent?.toSet() ?? {};

        // Build full month calendar grid from startDate's month to endDate's month
        final gridStart = DateTime(startDate!.year, startDate!.month, 1);
        final gridEnd = DateTime(endDate!.year, endDate!.month + 1, 0);

        // Build all cells for the grid using proper weekday alignment
        final List<List<Widget>> allWeeks = [];
        List<Widget> currentWeek = [];

        // weekday: 1=Mon, 2=Tue, ..., 6=Sat, 7=Sun
        // Calendar column order: Sun(0), Mon(1), Tue(2), Wed(3), Thu(4), Fri(5), Sat(6)
        int startColumn = gridStart.weekday % 7;

        // Add empty cells before the first day of the month
        for (var i = 0; i < startColumn; i++) {
          currentWeek.add(SizedBox(width: cellWidth, height: cellHeight));
        }

        // Iterate through every day from gridStart to gridEnd
        for (var d = 0; d <= gridEnd.difference(gridStart).inDays; d++) {
          final currentDate = gridStart.add(Duration(days: d));
          final isInRange =
              !currentDate.isBefore(startDate!) &&
              !currentDate.isAfter(endDate!);

          if (!isInRange) {
            // Add empty cell for dates outside the selected range
            currentWeek.add(SizedBox(width: cellWidth, height: cellHeight));
          } else {
            final dateStr =
                '${currentDate.year}-${currentDate.month.toString().padLeft(2, '0')}-${currentDate.day.toString().padLeft(2, '0')}';
            final isPresent = presentSet.contains(dateStr);
            final isSunday = currentDate.weekday == 7;

            currentWeek.add(
              Container(
                width: cellWidth,
                height: cellHeight,
                margin: const EdgeInsets.all(1),
                decoration: BoxDecoration(
                  color: isPresent
                      ? Colors.green
                      : isSunday
                      ? Colors.grey[300]
                      : Colors.red[100],
                  borderRadius: BorderRadius.circular(4),
                ),
                padding: EdgeInsets.symmetric(
                  vertical: cellHeight * 0.1,
                  horizontal: 0,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      currentDate.day.toString(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: cellWidth * 0.28,
                        color: isPresent
                            ? Colors.white
                            : (isSunday ? Colors.grey[600] : Colors.red[800]),
                      ),
                    ),
                    Text(
                      isPresent ? 'P' : (isSunday ? 'W' : 'A'),
                      style: TextStyle(
                        fontSize: cellWidth * 0.18,
                        fontWeight: FontWeight.w500,
                        color: isPresent
                            ? Colors.white70
                            : (isSunday ? Colors.grey[500] : Colors.red[400]),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // Start a new week after Saturday (column 6)
          if (currentWeek.length == 7) {
            allWeeks.add(currentWeek);
            currentWeek = [];
          }
        }

        // Add remaining cells to complete the last week
        if (currentWeek.isNotEmpty) {
          while (currentWeek.length < 7) {
            currentWeek.add(SizedBox(width: cellWidth, height: cellHeight));
          }
          allWeeks.add(currentWeek);
        }

        final dayHeaders = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
        final headerWidgets = dayHeaders
            .map(
              (day) => SizedBox(
                width: cellWidth,
                child: Text(
                  day,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: cellWidth * 0.22,
                    color: Colors.black87,
                  ),
                ),
              ),
            )
            .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: headerWidgets,
            ),
            const SizedBox(height: 4),
            // Calendar grid with explicit rows for proper column alignment
            ...allWeeks.map(
              (week) => Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: week,
              ),
            ),
          ],
        );
      },
    );
  }
}

class OtherStaffAttendanceTab extends StatefulWidget {
  final String token;

  const OtherStaffAttendanceTab({super.key, required this.token});

  @override
  State<OtherStaffAttendanceTab> createState() =>
      _OtherStaffAttendanceTabState();
}

class _OtherStaffAttendanceTabState extends State<OtherStaffAttendanceTab> {
  List<dynamic> otherStaff = [];
  Map<String, List<dynamic>> groupedStaff = {};
  Map<String, bool> expandedDepartments = {};
  bool isLoading = true;
  String searchQuery = '';
  final TextEditingController searchCtrl = TextEditingController();

  bool _asBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == 'true' || normalized == '1' || normalized == 'yes';
    }
    return false;
  }

  Map<String, dynamic> _normalizeOtherStaffMember(dynamic rawStaff) {
    final member = Map<String, dynamic>.from(
      (rawStaff ?? const <String, dynamic>{}) as Map,
    );
    return {
      ...member,
      'reg_no': (member['reg_no'] ?? member['regNo'] ?? '').toString().trim(),
      'can_reregister': _asBool(member['can_reregister']),
      'face_registered': _asBool(member['face_registered']),
    };
  }

  String _memberRegNo(Map<String, dynamic> member) {
    return (member['reg_no'] ?? member['regNo'] ?? '').toString().trim();
  }

  int? _memberId(Map<String, dynamic> member) {
    final raw = member['id'] ?? member['staff_id'];
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '');
  }

  @override
  void initState() {
    super.initState();
    fetchOtherStaffDepartments();
  }

  @override
  void dispose() {
    super.dispose();
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'principal':
        return 'Principal';
      case 'placement_staff':
        return 'Placement Staff';
      case 'lab_technician':
        return 'Lab Technician';
      case 'system_admin':
        return 'System Admin';
      case 'office_staff':
        return 'Office Staff';
      default:
        return role;
    }
  }

  Future<void> fetchOtherStaffDepartments() async {
    setState(() => isLoading = true);
    try {
      final response = await http.get(
        Uri.parse('$API_URL/admin/other_staff'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final rawStaffList = data['other_staff'] ?? [];
        final staffList = (rawStaffList as List)
            .map<Map<String, dynamic>>(
              (staff) => _normalizeOtherStaffMember(staff),
            )
            .toList();
        final grouped = <String, List<dynamic>>{};
        for (final staff in staffList) {
          final dept = (staff['dept']?.toString().trim().isNotEmpty ?? false)
              ? staff['dept'].toString().trim()
              : 'Unassigned';
          grouped.putIfAbsent(dept, () => []);
          grouped[dept]!.add(staff);
        }
        final sortedDeptKeys = grouped.keys.toList()..sort();
        final sortedGrouped = <String, List<dynamic>>{};
        final expanded = <String, bool>{};
        for (final dept in sortedDeptKeys) {
          final deptStaff = grouped[dept]!
            ..sort(
              (a, b) => (a['name'] ?? '').toString().compareTo(
                (b['name'] ?? '').toString(),
              ),
            );
          sortedGrouped[dept] = deptStaff;
          expanded[dept] = expandedDepartments[dept] ?? false;
        }

        setState(() {
          otherStaff = staffList;
          groupedStaff = sortedGrouped;
          expandedDepartments = expanded;
        });
      } else {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data['detail'] ?? 'Failed to fetch other staff departments',
            ),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${cleanAdminErrorMessage(e)}')));
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _registerFace(Map<String, dynamic> member) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FaceRegistrationWidget(
          token: widget.token,
          role: member['role'] ?? 'office_staff',
          initialRegNo: _memberRegNo(member),
          initialName: member['name'],
          initialDept: member['dept'],
          registerEndpoint: '/admin/other_staff/face/register',
          onSuccess: fetchOtherStaffDepartments,
        ),
      ),
    );
  }

  Future<void> _togglePermission(Map<String, dynamic> member) async {
    final regNo = _memberRegNo(member);
    if (regNo.isEmpty) return;
    final canReregister = _asBool(member['can_reregister']);
    try {
      final uri = Uri.parse(
        '$API_URL/admin/other_staff/face/permission/$regNo',
      );
      final response = canReregister
          ? await http.delete(
              uri,
              headers: {'Authorization': 'Bearer ${widget.token}'},
            )
          : await http.post(
              uri,
              headers: {'Authorization': 'Bearer ${widget.token}'},
            );
      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                canReregister ? 'Permission revoked' : 'Permission granted',
              ),
            ),
          );
        }
        fetchOtherStaffDepartments();
      } else {
        final data = jsonDecode(response.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['detail'] ?? 'Failed to update permission'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${cleanAdminErrorMessage(e)}')));
      }
    }
  }

  // Map roles to their departments
  String _getRoleDepartment(String role) {
    switch (role) {
      case 'principal':
        return 'Administration';
      case 'office_staff':
        return 'Office';
      case 'placement_staff':
        return 'Placement';
      case 'lab_technician':
        return 'Lab';
      case 'system_admin':
        return 'IT';
      default:
        return 'Office';
    }
  }

  // Auto-generate registration number for other staff
  String _generateOtherStaffRegNo(String role) {
    final prefix = {
      'principal': 'PRINCIPAL',
      'placement_staff': 'PLACE',
      'lab_technician': 'LAB',
      'system_admin': 'SYS',
      'office_staff': 'OFFICE',
    }[role] ?? 'OS';

    final count = otherStaff.where((s) => s['role'] == role).length + 1;
    return '${prefix}_${count.toString().padLeft(4, '0')}';
  }

  Future<void> _editOtherStaff(Map<String, dynamic> member) async {
    final nameCtrl = TextEditingController(text: member['name'] ?? '');
    final usernameCtrl = TextEditingController(text: member['username'] ?? '');
    final regNoCtrl = TextEditingController(text: _memberRegNo(member));
    String selectedRole = member['role'] ?? 'office_staff';

    // Auto-calculate department based on role
    String autoDept = _getRoleDepartment(selectedRole);

    final passwordCtrl = TextEditingController();
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Update department when role changes
          autoDept = _getRoleDepartment(selectedRole);
          return Dialog(
            insetPadding: EdgeInsets.zero,
            backgroundColor: Colors.transparent,
            child: SizedBox.expand(
              child: Scaffold(
                appBar: AppBar(
                  title: const Text('Edit Other User'),
                  leading: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(dialogContext),
                  ),
                ),
                body: SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        TextField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Name',
                            prefixIcon: Icon(Icons.person),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: usernameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Username',
                            prefixIcon: Icon(Icons.alternate_email),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: regNoCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Reg No',
                            prefixIcon: Icon(Icons.badge),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: passwordCtrl,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText:
                                'New Password (leave empty to keep current)',
                            prefixIcon: Icon(Icons.lock),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: selectedRole,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Role (Department)',
                            prefixIcon: Icon(Icons.work),
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'principal',
                              child: Text(
                                'Principal - Administration',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'office_staff',
                              child: Text(
                                'Office Staff - Office',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'placement_staff',
                              child: Text(
                                'Placement Staff - Placement',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'lab_technician',
                              child: Text(
                                'Lab Technician - Lab',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'system_admin',
                              child: Text(
                                'System Admin - IT',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            setDialogState(() {
                              selectedRole = value ?? 'office_staff';
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        // Display auto-calculated department (read-only)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey[300]!),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.business, color: Colors.grey[600]),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Department (Auto)',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                    Text(
                                      autoDept,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
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
                bottomNavigationBar: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.pop(dialogContext, {
                              'name': nameCtrl.text.trim(),
                              'username': usernameCtrl.text.trim(),
                              'reg_no': regNoCtrl.text.trim(),
                              'dept': autoDept,
                              'role': selectedRole,
                              'password': passwordCtrl.text.trim(),
                            }),
                            child: const Text('Save'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );

    if (result == null) return;
    final memberId = _memberId(member);
    if (memberId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid user id. Please refresh and try again.'),
          ),
        );
      }
      return;
    }
    try {
      final updatedName = (result['name'] ?? '').toString().trim();
      final updatedUsername = (result['username'] ?? '').toString().trim();
      final updatedRegNo = (result['reg_no'] ?? '').toString().trim();
      final safeName = updatedName.isEmpty
          ? (member['name'] ?? '').toString().trim()
          : updatedName;
      final safeUsername = updatedUsername.isEmpty
          ? (member['username'] ?? '').toString().trim()
          : updatedUsername;
      final safeRegNo = updatedRegNo.isEmpty
          ? _memberRegNo(member)
          : updatedRegNo;

      if (safeName.isEmpty || safeUsername.isEmpty || safeRegNo.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Name, username, and reg no are required.'),
            ),
          );
        }
        return;
      }

      final normalizedUsername = safeUsername.toLowerCase();
      final duplicateUsername = otherStaff.any((staff) {
        final staffMap = Map<String, dynamic>.from(staff as Map);
        final staffId = _memberId(staffMap);
        if (staffId == memberId) return false;
        final staffUsername = (staffMap['username'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        return staffUsername == normalizedUsername;
      });

      if (duplicateUsername) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Username already exists.')),
          );
        }
        return;
      }

      final Map<String, dynamic> updateBody = {
        'name': safeName,
        'username': safeUsername,
        'reg_no': safeRegNo,
        'dept': result['dept'],
        'role': result['role'],
      };
      final newPassword = (result['password'] ?? '').toString().trim();
      if (newPassword.isNotEmpty) {
        updateBody['password'] = newPassword;
      }
      final response = await http.put(
        Uri.parse('$API_URL/admin/other_staff/$memberId'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(updateBody),
      );
      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User updated successfully')),
          );
        }
        fetchOtherStaffDepartments();
      } else {
        final data = jsonDecode(response.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(data['detail'] ?? 'Failed to update user')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${cleanAdminErrorMessage(e)}')));
      }
    }
  }

  Future<void> _deleteOtherStaff(Map<String, dynamic> member) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.red[700]),
            const SizedBox(width: 12),
            const Text('Delete User'),
          ],
        ),
        content: Text('Are you sure you want to delete ${member['name']}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final memberId = _memberId(member);
    if (memberId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid user id. Please refresh and try again.'),
          ),
        );
      }
      return;
    }

    try {
      final response = await http.delete(
        Uri.parse('$API_URL/admin/other_staff/$memberId'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User deleted successfully')),
          );
        }
        fetchOtherStaffDepartments();
      } else {
        final data = jsonDecode(response.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(data['detail'] ?? 'Failed to delete user')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${cleanAdminErrorMessage(e)}')));
      }
    }
  }

  // Show add/edit dialog for other staff
  void _showStaffDialog({Map<String, dynamic>? existingStaff}) {
    final isEditing = existingStaff != null;
    final nameCtrl = TextEditingController(text: existingStaff?['name'] ?? '');
    final usernameCtrl = TextEditingController(
      text: existingStaff?['username'] ?? '',
    );
    final regNoCtrl = TextEditingController(
      text: existingStaff?['reg_no'] ?? _generateOtherStaffRegNo('office_staff'),
    );
    final passwordCtrl = TextEditingController();
    String selectedRole = existingStaff?['role'] ?? 'office_staff';

    // Auto-calculate department based on role
    String autoDept =
        existingStaff?['dept'] ?? _getRoleDepartment(selectedRole);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Update department when role changes
          autoDept = _getRoleDepartment(selectedRole);

          return Dialog(
            insetPadding: EdgeInsets.zero,
            backgroundColor: Colors.transparent,
            child: SizedBox.expand(
              child: Scaffold(
                appBar: AppBar(
                  title: Text(isEditing ? 'Edit Other User' : 'Add New Staff'),
                  leading: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                body: SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        TextField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Name',
                            prefixIcon: Icon(Icons.person),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: usernameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Username',
                            prefixIcon: Icon(Icons.alternate_email),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: regNoCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Registration No',
                            prefixIcon: Icon(Icons.badge),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: passwordCtrl,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: isEditing
                                ? 'New Password (leave empty to keep current)'
                                : 'Password',
                            prefixIcon: const Icon(Icons.lock),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: selectedRole,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Role (Department)',
                            prefixIcon: Icon(Icons.work),
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'principal',
                              child: Text(
                                'Principal - Administration',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'office_staff',
                              child: Text(
                                'Office Staff - Office',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'placement_staff',
                              child: Text(
                                'Placement Staff - Placement',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'lab_technician',
                              child: Text(
                                'Lab Technician - Lab',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'system_admin',
                              child: Text(
                                'System Admin - IT',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            setDialogState(() {
                              selectedRole = value ?? 'office_staff';
                              if (!isEditing) {
                                regNoCtrl.text = _generateOtherStaffRegNo(selectedRole);
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 12),

                        // Display auto-calculated department (read-only)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey[300]!),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.business, color: Colors.grey[600]),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Department (Auto)',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                    Text(
                                      autoDept,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
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
                bottomNavigationBar: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () async {
                              if (nameCtrl.text.isEmpty ||
                                  usernameCtrl.text.isEmpty ||
                                  (!isEditing &&
                                      passwordCtrl.text.trim().isEmpty)) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Please fill all fields'),
                                  ),
                                );
                                return;
                              }

                              Navigator.pop(context);

                              final body = {
                                'name': nameCtrl.text,
                                'username': usernameCtrl.text,
                                'reg_no': regNoCtrl.text,
                                'role': selectedRole,
                                'dept': autoDept,
                              };
                              final password = passwordCtrl.text.trim();
                              if (password.isNotEmpty) {
                                body['password'] = password;
                              }

                              try {
                                http.Response response;

                                if (isEditing) {
                                  final memberId = _memberId(existingStaff);

                                  response = await http.put(
                                    Uri.parse(
                                      '$API_URL/admin/other_staff/$memberId',
                                    ),
                                    headers: {
                                      'Authorization': 'Bearer ${widget.token}',
                                      'Content-Type': 'application/json',
                                    },
                                    body: jsonEncode(body),
                                  );
                                } else {
                                  response = await http.post(
                                    Uri.parse(
                                      '$API_URL/admin/other_staff/create',
                                    ),
                                    headers: {
                                      'Authorization': 'Bearer ${widget.token}',
                                      'Content-Type': 'application/json',
                                    },
                                    body: jsonEncode(body),
                                  );
                                }

                                if (response.statusCode == 200 ||
                                    response.statusCode == 201) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          isEditing
                                              ? 'Staff updated successfully'
                                              : 'Staff added successfully',
                                        ),
                                      ),
                                    );
                                    fetchOtherStaffDepartments();
                                  }
                                } else {
                                  final data = jsonDecode(response.body);
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          data['detail'] ??
                                              'Failed to save staff',
                                        ),
                                      ),
                                    );
                                  }
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Error: ${cleanAdminErrorMessage(e)}')),
                                  );
                                }
                              }
                            },
                            child: Text(isEditing ? 'Update' : 'Add'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = searchQuery.trim().toLowerCase();
    final Map<String, List<dynamic>> displayedGroupedStaff = {};
    if (normalizedQuery.isEmpty) {
      displayedGroupedStaff.addAll(groupedStaff);
    } else {
      for (final entry in groupedStaff.entries) {
        final dept = entry.key;
        final staffList = entry.value;
        final deptMatches = dept.toLowerCase().contains(normalizedQuery);
        if (deptMatches) {
          displayedGroupedStaff[dept] = List<dynamic>.from(staffList);
          continue;
        }
        final filtered = staffList.where((staff) {
          final member = Map<String, dynamic>.from(staff as Map);
          final haystack = [
            (member['name'] ?? '').toString(),
            (member['username'] ?? '').toString(),
            (member['reg_no'] ?? '').toString(),
            (member['role'] ?? '').toString(),
            (member['dept'] ?? '').toString(),
          ].join(' ').toLowerCase();
          return haystack.contains(normalizedQuery);
        }).toList();
        if (filtered.isNotEmpty) {
          displayedGroupedStaff[dept] = filtered;
        }
      }
    }
    final displayedStaffCount = displayedGroupedStaff.values.fold<int>(
      0,
      (sum, list) => sum + list.length,
    );
    final displayedDeptCount = displayedGroupedStaff.length;

    // Plain white background
    return Container(
      color: Colors.grey[50],
      child: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isNarrow = constraints.maxWidth < 650;

                          final titleBlock = Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.deepPurple.withValues(alpha: 0.8),
                                      Colors.purple.withValues(alpha: 0.6),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.deepPurple.withValues(
                                        alpha: 0.3,
                                      ),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.apartment,
                                  color: Colors.white,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Other User Departments',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Departments: $displayedDeptCount • Staff: $displayedStaffCount',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey[600],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );

                          final actionsBlock = Row(
                            mainAxisSize: isNarrow ? MainAxisSize.max : MainAxisSize.min,
                            mainAxisAlignment: isNarrow ? MainAxisAlignment.end : MainAxisAlignment.start,
                            children: [
                              // Refresh button
                              IconButton(
                                onPressed: fetchOtherStaffDepartments,
                                tooltip: 'Refresh',
                                icon: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.deepPurple.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.refresh,
                                    color: Colors.deepPurple,
                                    size: 20,
                                  ),
                                ),
                              ),
                              // Add button
                              IconButton(
                                onPressed: () => _showStaffDialog(),
                                tooltip: 'Add Staff',
                                icon: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.add,
                                    color: Colors.green,
                                    size: 20,
                                  ),
                                ),
                              ),
                              // Bulk Upload button
                              PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'upload') {
                                    performBulkUpload(
                                      context,
                                      widget.token,
                                      '${CollegeIPConfig.defaultURL}/admin/other_staff/bulk-upload',
                                      fetchOtherStaffDepartments,
                                    );
                                  } else if (value == 'excel') {
                                    downloadTemplateHelper(context, widget.token, 'other_staff', 'excel');
                                  } else if (value == 'json') {
                                    downloadTemplateHelper(context, widget.token, 'other_staff', 'json');
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'upload',
                                    child: Row(
                                      children: [
                                        Icon(Icons.upload_file, color: Colors.blue),
                                        SizedBox(width: 8),
                                        Text('Upload File'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'excel',
                                    child: Row(
                                      children: [
                                        Icon(Icons.download, color: Colors.green),
                                        SizedBox(width: 8),
                                        Text('Download Excel Template'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'json',
                                    child: Row(
                                      children: [
                                        Icon(Icons.download, color: Colors.amber),
                                        SizedBox(width: 8),
                                        Text('Download JSON Template'),
                                      ],
                                    ),
                                  ),
                                ],
                                child: Tooltip(
                                  message: 'Bulk Upload / Templates',
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.upload_file,
                                      color: Colors.blue,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );

                          if (isNarrow) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                titleBlock,
                                const SizedBox(height: 10),
                                actionsBlock,
                              ],
                            );
                          }

                          return Row(
                            children: [
                              Expanded(child: titleBlock),
                              actionsBlock,
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: searchCtrl,
                        decoration: InputDecoration(
                          labelText: 'Search Users',
                          hintText: 'Name / Reg / Username / Role / Department',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: searchQuery.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.close),
                                  onPressed: () {
                                    searchCtrl.clear();
                                    setState(() => searchQuery = '');
                                  },
                                ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Colors.grey[50],
                        ),
                        onChanged: (value) {
                          setState(() => searchQuery = value);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (isLoading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: CircularProgressIndicator(color: Colors.deepPurple),
                ),
              )
            else if (displayedGroupedStaff.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.group_off,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          normalizedQuery.isEmpty
                              ? 'No other users found'
                              : 'No users match your search',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final dept = displayedGroupedStaff.keys.elementAt(index);
                    final deptStaff = displayedGroupedStaff[dept] ?? [];

                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 15,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Theme(
                        data: Theme.of(
                          context,
                        ).copyWith(dividerColor: Colors.grey[200]),
                        child: ExpansionTile(
                          key: PageStorageKey('other_user_dept_$dept'),
                          initiallyExpanded: expandedDepartments[dept] == true,
                          onExpansionChanged: (expanded) {
                            setState(
                              () => expandedDepartments[dept] = expanded,
                            );
                          },
                          backgroundColor: Colors.white,
                          collapsedBackgroundColor: Colors.white,
                          iconColor: Colors.deepPurple,
                          collapsedIconColor: Colors.grey[600],
                          textColor: Colors.black87,
                          collapsedTextColor: Colors.grey[700],
                          title: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: _getDepartmentColor(
                                    dept,
                                  ).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  _getDepartmentIcon(dept),
                                  color: _getDepartmentColor(dept),
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '$dept (${deptStaff.length})',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.grey[50],
                                borderRadius: const BorderRadius.only(
                                  bottomLeft: Radius.circular(16),
                                  bottomRight: Radius.circular(16),
                                ),
                              ),
                              child: Column(
                                children: deptStaff.map((staff) {
                                  final staffMember = Map<String, dynamic>.from(
                                    staff as Map,
                                  );
                                  final faceRegistered = _asBool(
                                    staffMember['face_registered'],
                                  );
                                  final canReregister = _asBool(
                                    staffMember['can_reregister'],
                                  );

                                  return Container(
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.grey[200]!,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.04,
                                          ),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Name and Role in single line
                                        Row(
                                          children: [
                                            CircleAvatar(
                                              backgroundColor:
                                                  _getDepartmentColor(
                                                    dept,
                                                  ).withValues(alpha: 0.15),
                                              radius: 22,
                                              child: Text(
                                                (staffMember['name'] ?? '')
                                                    .toString()
                                                    .substring(0, 1)
                                                    .toUpperCase(),
                                                style: TextStyle(
                                                  color: _getDepartmentColor(
                                                    dept,
                                                  ),
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    staffMember['name'] ?? '',
                                                    style: const TextStyle(
                                                      color: Colors.black87,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    '${_memberRegNo(staffMember)} • ${_roleLabel(staffMember['role']?.toString() ?? '')}',
                                                    style: TextStyle(
                                                      color: Colors.grey[600],
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 16),
                                        // Action buttons below
                                        Wrap(
                                          alignment: WrapAlignment.spaceEvenly,
                                          runAlignment: WrapAlignment.center,
                                          spacing: 2,
                                          runSpacing: 4,
                                          children: [
                                            _buildActionButton(
                                              icon: faceRegistered
                                                  ? Icons
                                                        .face_retouching_natural
                                                  : Icons.face,
                                              label: faceRegistered
                                                  ? 'Update Face'
                                                  : 'Register Face',
                                              color: Colors.green,
                                              onPressed: () =>
                                                  _registerFace(staffMember),
                                            ),
                                            _buildActionButton(
                                              icon: canReregister
                                                  ? Icons.block
                                                  : Icons.verified,
                                              label: canReregister
                                                  ? 'Revoke'
                                                  : 'Grant',
                                              color: canReregister
                                                  ? Colors.red
                                                  : Colors.orange,
                                              onPressed: () =>
                                                  _togglePermission(
                                                    staffMember,
                                                  ),
                                            ),
                                            _buildActionButton(
                                              icon: Icons.edit,
                                              label: 'Edit',
                                              color: Colors.blueAccent,
                                              onPressed: () =>
                                                  _editOtherStaff(staffMember),
                                            ),
                                            _buildActionButton(
                                              icon: Icons.delete,
                                              label: 'Delete',
                                              color: Colors.redAccent,
                                              onPressed: () =>
                                                  _deleteOtherStaff(
                                                    staffMember,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }, childCount: displayedGroupedStaff.keys.length),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Build action button with label below
  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(minWidth: 60),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 44,
              height: 38,
              child: TextButton(
                onPressed: onPressed,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  backgroundColor: color.withValues(alpha: 0.12),
                  foregroundColor: color,
                ),
                child: Icon(icon, color: color, size: 20),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Get department-specific color
  Color _getDepartmentColor(String dept) {
    final deptLower = dept.toLowerCase();
    if (deptLower.contains('principal') || deptLower.contains('office')) {
      return Colors.purple;
    } else if (deptLower.contains('placement')) {
      return Colors.orange;
    } else if (deptLower.contains('lab')) {
      return Colors.teal;
    } else if (deptLower.contains('system') || deptLower.contains('admin')) {
      return Colors.indigo;
    } else if (deptLower.contains('unassigned')) {
      return Colors.grey;
    }
    return Colors.deepPurple;
  }

  /// Get department-specific icon
  IconData _getDepartmentIcon(String dept) {
    final deptLower = dept.toLowerCase();
    if (deptLower.contains('principal')) {
      return Icons.school;
    } else if (deptLower.contains('placement')) {
      return Icons.work;
    } else if (deptLower.contains('lab')) {
      return Icons.science;
    } else if (deptLower.contains('system')) {
      return Icons.computer;
    } else if (deptLower.contains('office')) {
      return Icons.business_center;
    } else if (deptLower.contains('unassigned')) {
      return Icons.person_off;
    }
    return Icons.apartment;
  }
}

class _OtherStaffAttendanceDialog extends StatefulWidget {
  final String token;
  final String regNo;
  final String name;

  const _OtherStaffAttendanceDialog({
    required this.token,
    required this.regNo,
    required this.name,
  });

  @override
  State<_OtherStaffAttendanceDialog> createState() =>
      _OtherStaffAttendanceDialogState();
}

class _OtherStaffAttendanceDialogState
    extends State<_OtherStaffAttendanceDialog> {
  List<dynamic> records = [];
  bool isLoading = true;
  DateTime? startDate;
  DateTime? endDate;
  Map<String, int> stats = {'present': 0, 'absent': 0, 'total': 0};
  Map<String, dynamic>? _attendanceResponseData;

  @override
  void initState() {
    super.initState();
    _loadDefaultDates();
  }

  Future<void> _loadDefaultDates() async {
    try {
      final response = await http.get(Uri.parse('$API_URL/academics/current'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final rawRanges = data['academic_ranges'] as List? ?? [];
        if (rawRanges.isNotEmpty && rawRanges[0]['start'] != null && mounted) {
          setState(() {
            startDate = DateTime.parse(rawRanges[0]['start']);
            endDate = DateTime.parse(rawRanges.last['end']);
          });
          fetchAttendance();
          return;
        }
        if (data['academic_year_start'] != null && mounted) {
          setState(() {
            startDate = DateTime.parse(data['academic_year_start']);
            endDate = DateTime.parse(data['academic_year_end']);
          });
          fetchAttendance();
          return;
        }
      }
    } catch (_) {}
    final now = DateTime.now();
    setState(() {
      startDate = DateTime(now.year, now.month, 1);
      endDate = now;
    });
    fetchAttendance();
  }

  // Quick select methods for common date ranges
  void _selectToday() {
    final now = DateTime.now();
    setState(() {
      startDate = now;
      endDate = now;
    });
    fetchAttendance();
  }

  void _selectThisWeek() {
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    setState(() {
      startDate = startOfWeek;
      endDate = now;
    });
    fetchAttendance();
  }

  void _selectThisMonth() {
    final now = DateTime.now();
    setState(() {
      startDate = DateTime(now.year, now.month, 1);
      endDate = now;
    });
    fetchAttendance();
  }

  void _selectLastMonth() {
    final now = DateTime.now();
    final lastMonth = DateTime(now.year, now.month - 1, 1);
    final lastDayOfLastMonth = DateTime(now.year, now.month, 0);
    setState(() {
      startDate = lastMonth;
      endDate = lastDayOfLastMonth;
    });
    fetchAttendance();
  }

  void _selectLast7Days() {
    final now = DateTime.now();
    setState(() {
      startDate = now.subtract(const Duration(days: 6));
      endDate = now;
    });
    fetchAttendance();
  }

  void _selectLast30Days() {
    final now = DateTime.now();
    setState(() {
      startDate = now.subtract(const Duration(days: 29));
      endDate = now;
    });
    fetchAttendance();
  }

  // Week navigation methods
  void _goToPreviousWeek() {
    if (startDate != null && endDate != null) {
      setState(() {
        startDate = startDate!.subtract(const Duration(days: 7));
        endDate = endDate!.subtract(const Duration(days: 7));
      });
      fetchAttendance();
    }
  }

  void _goToNextWeek() {
    final now = DateTime.now();
    if (startDate != null && endDate != null) {
      // Don't go beyond today
      final newEndDate = endDate!.add(const Duration(days: 7));
      if (newEndDate.isAfter(now)) {
        return;
      }
      setState(() {
        startDate = startDate!.add(const Duration(days: 7));
        endDate = newEndDate;
      });
      fetchAttendance();
    }
  }

  Future<void> _selectDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: now,
      initialDateRange: startDate != null && endDate != null
          ? DateTimeRange(start: startDate!, end: endDate!)
          : DateTimeRange(start: startDate ?? DateTime(now.year, now.month, 1), end: endDate ?? now),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(primary: Colors.deepPurple),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      // Validate date range
      if (picked.start.isAfter(picked.end)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Start date cannot be after end date'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Validate not future dates
      if (picked.end.isAfter(DateTime.now())) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Cannot select future dates'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      setState(() {
        startDate = picked.start;
        endDate = picked.end;
      });
      fetchAttendance();
    }
  }

  String _formatDate(DateTime date) {
    // For display in UI - dd/mm/yy format
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year.toString().substring(2)}';
  }

  // Format date for API - yyyy-mm-dd format (required by backend)
  String _formatDateForAPI(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> fetchAttendance() async {
    if (startDate == null || endDate == null) return;

    setState(() => isLoading = true);
    try {
      final url =
          '$API_URL/admin/other_staff/attendance?reg_no=${widget.regNo}&start_date=${_formatDateForAPI(startDate!)}&end_date=${_formatDateForAPI(endDate!)}';

      final response = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          records = data['attendance'] ?? [];
          _attendanceResponseData = data;
          _calculateStats();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${cleanAdminErrorMessage(e)}')));
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  void _calculateStats() {
    int present = 0;

    // Group by date to count unique days
    final Map<String, bool> uniqueDates = {};
    for (var record in records) {
      final timestamp = record['timestamp']?.toString() ?? '';
      if (timestamp.isNotEmpty) {
        // Handle both "2024-03-11 07:04:29" and "2024-03-11T07:04:29" formats
        final date = timestamp.contains(' ')
            ? timestamp.split(' ')[0]
            : (timestamp.contains('T') ? timestamp.split('T')[0] : timestamp);
        uniqueDates[date] = true;
      }
    }

    present = uniqueDates.length;
    // Use server-computed holiday-aware total/absent if available
    final int totalDays;
    final int absent;
    if (_attendanceResponseData != null &&
        _attendanceResponseData!['working_days'] != null) {
      totalDays = _attendanceResponseData!['working_days'] as int;
      absent = _attendanceResponseData!['absent_days'] as int? ?? 
               (totalDays - present).clamp(0, totalDays);
    } else {
      totalDays = (startDate != null && endDate != null)
          ? endDate!.difference(startDate!).inDays + 1
          : 0;
      absent = (totalDays - present).clamp(0, totalDays);
    }

    stats = {'present': present, 'absent': absent, 'total': present + absent};
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.deepPurple,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Attendance Details',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          widget.name,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Date range filter with week navigation
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Previous week button
                  IconButton(
                    onPressed: _goToPreviousWeek,
                    icon: const Icon(Icons.chevron_left),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.deepPurple.withValues(alpha: 0.1),
                      foregroundColor: Colors.deepPurple,
                    ),
                    tooltip: 'Previous Week',
                  ),
                  const SizedBox(width: 8),
                  // Date range selector
                  Expanded(
                    child: InkWell(
                      onTap: _selectDateRange,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.deepPurple),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.date_range, color: Colors.deepPurple),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Select Date Range',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    startDate != null && endDate != null
                                        ? '${_formatDate(startDate!)} - ${_formatDate(endDate!)}'
                                        : 'Tap to select dates',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.arrow_drop_down,
                              color: Colors.deepPurple,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Next week button
                  IconButton(
                    onPressed: _goToNextWeek,
                    icon: const Icon(Icons.chevron_right),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.deepPurple.withValues(alpha: 0.1),
                      foregroundColor: Colors.deepPurple,
                    ),
                    tooltip: 'Next Week',
                  ),
                ],
              ),
            ),

            // Quick select buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Quick Select',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _QuickSelectChip(
                          label: 'Today',
                          onTap: _selectToday,
                          color: Colors.deepPurple,
                        ),
                        const SizedBox(width: 8),
                        _QuickSelectChip(
                          label: 'This Week',
                          onTap: _selectThisWeek,
                          color: Colors.blue,
                        ),
                        const SizedBox(width: 8),
                        _QuickSelectChip(
                          label: 'This Month',
                          onTap: _selectThisMonth,
                          color: Colors.green,
                        ),
                        const SizedBox(width: 8),
                        _QuickSelectChip(
                          label: 'Last Month',
                          onTap: _selectLastMonth,
                          color: Colors.orange,
                        ),
                        const SizedBox(width: 8),
                        _QuickSelectChip(
                          label: 'Last 7 Days',
                          onTap: _selectLast7Days,
                          color: Colors.cyan,
                        ),
                        const SizedBox(width: 8),
                        _QuickSelectChip(
                          label: 'Last 30 Days',
                          onTap: _selectLast30Days,
                          color: Colors.indigo,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Stats cards
            if (!isLoading && stats['total']! > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: _AttendanceStatCard(
                        label: 'Present',
                        value: stats['present'].toString(),
                        color: Colors.green,
                        icon: Icons.check_circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _AttendanceStatCard(
                        label: 'Absent',
                        value: stats['absent'].toString(),
                        color: Colors.red,
                        icon: Icons.cancel,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _AttendanceStatCard(
                        label: 'Total Days',
                        value: stats['total'].toString(),
                        color: Colors.blue,
                        icon: Icons.calendar_month,
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 16),

            // Attendance list
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : records.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.event_busy,
                            size: 48,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No attendance records found',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: records.length,
                      itemBuilder: (context, index) {
                        final record = records[index];
                        final timestamp = record['timestamp']?.toString() ?? '';
                        // Handle both "2024-03-11 07:04:29" and "2024-03-11T07:04:29" formats
                        final datePart = timestamp.contains(' ')
                            ? timestamp.split(' ')[0]
                            : (timestamp.contains('T')
                                  ? timestamp.split('T')[0]
                                  : '');
                        final timePart = timestamp.contains(' ')
                            ? (timestamp.split(' ').length > 1
                                  ? timestamp.split(' ')[1]
                                  : '')
                            : (timestamp.contains('T')
                                  ? timestamp.split('T')[1]
                                  : '');

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.green.withOpacity(0.1),
                              child: const Icon(
                                Icons.check,
                                color: Colors.green,
                              ),
                            ),
                            title: Text(datePart),
                            subtitle: Text('Time: $timePart'),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Present',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // Close button
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                  ),
                  child: const Text('Close'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _AttendanceStatCard({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 400;
    final isMobile = screenWidth < 600;
    final iconContainerSize = isSmallScreen ? 30.0 : (isMobile ? 34.0 : 36.0);
    final iconSize = isSmallScreen ? 15.0 : (isMobile ? 17.0 : 19.0);
    final labelSize = isSmallScreen ? 12.0 : 13.0;
    final valueSize = isSmallScreen ? 15.0 : (isMobile ? 16.0 : 18.0);
    final padding = isSmallScreen ? 11.0 : (isMobile ? 12.0 : 13.0);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: isDark ? 0.15 : 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: padding,
          vertical: padding - 1,
        ),
        child: Row(
          children: [
            Container(
              width: iconContainerSize,
              height: iconContainerSize,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    color.withValues(alpha: 0.15),
                    color.withValues(alpha: 0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon, color: color, size: iconSize),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: labelSize,
                  color: isDark ? Colors.white70 : Colors.grey[700],
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: valueSize,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Other Staffs Tab - For managing Principal and non-teaching staff
class OtherStaffsTab extends StatefulWidget {
  final String token;

  const OtherStaffsTab({super.key, required this.token});

  @override
  State<OtherStaffsTab> createState() => _OtherStaffsTabState();
}

class _OtherStaffsTabState extends State<OtherStaffsTab> {
  List<dynamic> otherStaff = [];
  bool isLoading = true;
  String? selectedRoleFilter;
  String searchQuery = '';
  final _formKey = GlobalKey<FormState>();

  final nameCtrl = TextEditingController();
  final passwordCtrl = TextEditingController();
  final usernameCtrl = TextEditingController();
  final regNoCtrl = TextEditingController();
  final searchCtrl = TextEditingController();
  String? selectedRole;
  DateTime? selectedDOB;

  // Role options for the dropdown
  final List<Map<String, String>> roleOptions = [
    {'value': 'principal', 'label': 'Principal'},
    {'value': 'placement_staff', 'label': 'Placement Staff'},
    {'value': 'lab_technician', 'label': 'Lab Technician'},
    {'value': 'system_admin', 'label': 'System Admin'},
    {'value': 'office_staff', 'label': 'Office Staff'},
  ];

  // Filter options for all other staff roles
  final List<String> filterOptions = [
    'All',
    'principal',
    'placement_staff',
    'lab_technician',
    'system_admin',
    'office_staff',
  ];

  @override
  void initState() {
    super.initState();
    fetchOtherStaff();
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    passwordCtrl.dispose();
    usernameCtrl.dispose();
    regNoCtrl.dispose();
    searchCtrl.dispose();
    super.dispose();
  }

  Future<void> fetchOtherStaff({String? role}) async {
    setState(() => isLoading = true);
    try {
      String url = '$API_URL/admin/other_staff';
      if (role != null && role.isNotEmpty && role != 'All') {
        url += '?role=$role';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          otherStaff = data['other_staff'] ?? [];
        });
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load other staff')));
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${cleanAdminErrorMessage(e)}')));
    } finally {
      setState(() => isLoading = false);
    }
  }

  // Get principal from the list
  Map<String, dynamic>? get principal {
    try {
      return otherStaff.firstWhere((s) => s['role'] == 'principal');
    } catch (e) {
      return null;
    }
  }

  // Get filtered and sorted staff list (principal + other staff)
  List<dynamic> get filteredTechnicalStaffs {
    final selectedFilter = selectedRoleFilter ?? 'All';
    final normalizedQuery = searchQuery.trim().toLowerCase();

    final filtered = otherStaff.where((staff) {
      final roleMatch =
          selectedFilter == 'All' || staff['role'] == selectedFilter;
      if (!roleMatch) return false;
      if (normalizedQuery.isEmpty) return true;

      final haystack = [
        (staff['name'] ?? '').toString(),
        (staff['username'] ?? '').toString(),
        (staff['reg_no'] ?? '').toString(),
        _getRoleLabel((staff['role'] ?? '').toString()),
      ].join(' ').toLowerCase();

      return haystack.contains(normalizedQuery);
    }).toList();

    filtered.sort((a, b) {
      final aRole = (a['role'] ?? '').toString();
      final bRole = (b['role'] ?? '').toString();
      if (aRole == 'principal' && bRole != 'principal') return -1;
      if (aRole != 'principal' && bRole == 'principal') return 1;
      final aName = (a['name'] ?? '').toString().toLowerCase();
      final bName = (b['name'] ?? '').toString().toLowerCase();
      return aName.compareTo(bName);
    });

    return filtered;
  }

  // Generate username based on role
  String _generateUsername(String role) {
    final rolePrefix =
        {
          'principal': 'principal',
          'placement_staff': 'place',
          'lab_technician': 'lab',
          'system_admin': 'sysadmin',
          'office_staff': 'office',
        }[role] ??
        'staff';

    final count = otherStaff.where((s) => s['role'] == role).length + 1;
    return '$rolePrefix$count';
  }

  // Auto-generate registration number based on role
  String _generateRegNo(String role) {
    final prefix = {
      'principal': 'PRINCIPAL',
      'placement_staff': 'PLACE',
      'lab_technician': 'LAB',
      'system_admin': 'SYS',
      'office_staff': 'OFFICE',
    }[role] ?? 'OS';

    final count = otherStaff.where((s) => s['role'] == role).length + 1;
    return '${prefix}_${count.toString().padLeft(4, '0')}';
  }

  // Show add/edit dialog
  void _showStaffDialog({
    Map<String, dynamic>? existingStaff,
    bool isPrincipal = false,
  }) {
    final isEditing = existingStaff != null;

    // Debug log to validate data being loaded
    debugPrint(
      'OtherStaffsTab: _showStaffDialog called - isEditing: $isEditing',
    );
    if (isEditing) {
      debugPrint(
        'OtherStaffsTab: Editing staff - name: ${existingStaff['name']}, username: ${existingStaff['username']}, reg_no: ${existingStaff['reg_no']}, role: ${existingStaff['role']}, dob: ${existingStaff['dob']}',
      );
    }

    if (isEditing) {
      // Clear password field first to avoid retaining old values
      passwordCtrl.clear();
      nameCtrl.text = existingStaff['name'] ?? '';
      usernameCtrl.text = existingStaff['username'] ?? '';
      regNoCtrl.text = existingStaff['reg_no'] ?? '';
      selectedRole = existingStaff['role'];
      if (existingStaff['dob'] != null) {
        try {
          selectedDOB = DateTime.parse(existingStaff['dob']);
          debugPrint('OtherStaffsTab: Parsed DOB: $selectedDOB');
        } catch (e) {
          selectedDOB = null;
          debugPrint(
            'OtherStaffsTab: Failed to parse DOB: ${existingStaff['dob']}',
          );
        }
      } else {
        selectedDOB = null;
      }
    } else {
      _clearForm();
      selectedRole = isPrincipal ? 'principal' : 'office_staff';
      usernameCtrl.text = _generateUsername(selectedRole!);
      regNoCtrl.text = _generateRegNo(selectedRole!);
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            isEditing
                ? 'Edit Staff'
                : (isPrincipal ? 'Add Principal' : 'Add Other Staff'),
          ),
          content: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Full Name',
                      prefixIcon: const Icon(Icons.person),
                      filled: true,
                      fillColor: Colors.grey[100],
                    ),
                    validator: (v) => v!.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: usernameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Username',
                      prefixIcon: const Icon(Icons.alternate_email),
                      filled: true,
                      fillColor: Colors.grey[100],
                    ),
                    validator: (v) => v!.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: passwordCtrl,
                    decoration: InputDecoration(
                      labelText: isEditing
                          ? 'New Password (leave empty to keep current)'
                          : 'Password',
                      prefixIcon: const Icon(Icons.lock),
                      filled: true,
                      fillColor: Colors.grey[100],
                    ),
                    obscureText: true,
                    validator: (v) =>
                        isEditing ? null : (v!.isEmpty ? 'Required' : null),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.deepPurple),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButton<String>(
                      value: selectedRole,
                      isExpanded: true,
                      underline: const SizedBox(),
                      hint: const Text('Select Role'),
                      items: roleOptions
                          .map(
                            (role) => DropdownMenuItem(
                              value: role['value'],
                              child: Text(role['label']!),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setDialogState(() {
                          selectedRole = value;
                          if (!isEditing) {
                            usernameCtrl.text = _generateUsername(value!);
                            regNoCtrl.text = _generateRegNo(value);
                          }
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: selectedDOB ?? DateTime(1990),
                        firstDate: DateTime(1950),
                        lastDate: DateTime.now().subtract(
                          const Duration(days: 365 * 18),
                        ),
                      );
                      if (date != null) {
                        setDialogState(() => selectedDOB = date);
                      }
                    },
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Date of Birth',
                        prefixIcon: const Icon(Icons.calendar_today),
                        filled: true,
                        fillColor: Colors.grey[100],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        selectedDOB != null
                            ? '${selectedDOB!.day}/${selectedDOB!.month}/${selectedDOB!.year}'
                            : 'Select Date',
                        style: TextStyle(
                          color: selectedDOB != null
                              ? Colors.black
                              : Colors.grey,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: regNoCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Registration Number *',
                      hintText: 'Enter registration number',
                      prefixIcon: Icon(Icons.badge),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _clearForm();
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => isEditing
                  ? updateStaff(existingStaff['id'])
                  : createStaff(isPrincipal: isPrincipal),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
              ),
              child: Text(isEditing ? 'Update' : 'Create'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> createStaff({bool isPrincipal = false}) async {
    if (!_formKey.currentState!.validate()) return;
    if (selectedRole == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a role')));
      return;
    }

    try {
      final regNo = regNoCtrl.text.trim();
      final response = await http.post(
        Uri.parse('$API_URL/admin/other_staff/create'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'username': usernameCtrl.text,
          'password': passwordCtrl.text,
          'name': nameCtrl.text,
          'role': selectedRole,
          'reg_no': regNo,
          'dob': selectedDOB != null
              ? '${selectedDOB!.year}-${selectedDOB!.month.toString().padLeft(2, '0')}-${selectedDOB!.day.toString().padLeft(2, '0')}'
              : null,
        }),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Staff created successfully')),
        );
        fetchOtherStaff();
        _clearForm();
        Navigator.pop(context);
      } else {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['detail'] ?? 'Failed to create staff')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${cleanAdminErrorMessage(e)}')));
    }
  }

  Future<void> updateStaff(int staffId) async {
    if (!_formKey.currentState!.validate()) return;

    try {
      // Build the update payload
      final Map<String, dynamic> updateData = {
        'name': nameCtrl.text,
        'username': usernameCtrl.text,
        'reg_no': regNoCtrl.text,
        'role': selectedRole,
        'dob': selectedDOB != null
            ? '${selectedDOB!.year}-${selectedDOB!.month.toString().padLeft(2, '0')}-${selectedDOB!.day.toString().padLeft(2, '0')}'
            : null,
      };

      // Only include password if it's not empty (optional password change)
      final password = passwordCtrl.text.trim();
      if (password.isNotEmpty) {
        updateData['password'] = password;
      }

      final response = await http.put(
        Uri.parse('$API_URL/admin/other_staff/$staffId'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(updateData),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Staff updated successfully')),
        );
        fetchOtherStaff();
        _clearForm();
        Navigator.pop(context);
      } else {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['detail'] ?? 'Failed to update staff')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${cleanAdminErrorMessage(e)}')));
    }
  }

  Future<void> deleteStaff(int staffId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Staff'),
        content: Text('Are you sure you want to delete $name?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final response = await http.delete(
        Uri.parse('$API_URL/admin/other_staff/$staffId'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Staff deleted successfully')),
        );
        fetchOtherStaff();
      } else {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['detail'] ?? 'Failed to delete staff')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${cleanAdminErrorMessage(e)}')));
    }
  }

  Future<void> _toggleOtherStaffSuspension(Map<String, dynamic> staff) async {
    final isSuspended = staff['suspended'] == true;
    final actionText = isSuspended ? 'unsuspend' : 'suspend';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${isSuspended ? "Unsuspend" : "Suspend"} Other Staff'),
        content: Text('Are you sure you want to $actionText other staff member ${staff['name']}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: isSuspended ? Colors.green : Colors.red),
            child: Text(isSuspended ? 'Unsuspend' : 'Suspend'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final response = await http.put(
        Uri.parse('$API_URL/admin/other_staff/${staff['id']}'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'suspended': !isSuspended}),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Staff ${isSuspended ? "unsuspended" : "suspended"} successfully')),
        );
        setState(() {
          final index = otherStaff.indexWhere((s) => s['id'] == staff['id']);
          if (index != -1) {
            otherStaff[index]['suspended'] = !isSuspended;
          }
        });
      } else {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['detail'] ?? 'Failed to update status')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${cleanAdminErrorMessage(e)}')),
      );
    }
  }

  void _clearForm() {
    nameCtrl.clear();
    passwordCtrl.clear();
    usernameCtrl.clear();
    regNoCtrl.clear();
    selectedRole = null;
    selectedDOB = null;
  }

  String _getRoleLabel(String role) {
    return roleOptions.firstWhere(
      (r) => r['value'] == role,
      orElse: () => {'label': role},
    )['label']!;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMobile = MediaQuery.of(context).size.width < 600;
    final bg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderClr = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    final totalOtherStaff = otherStaff.length;
    final principalCount = otherStaff.where((s) => s['role'] == 'principal').length;
    final displayedStaff = filteredTechnicalStaffs;

    return Container(
      color: bg,
      child: RefreshIndicator(
        onRefresh: () => fetchOtherStaff(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Premium Header Banner ──────────────────────────────────
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [const Color(0xFF0F172A), const Color(0xFF1E293B)]
                        : [const Color(0xFF3730A3), const Color(0xFF4F46E5), const Color(0xFF6366F1)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: isDark ? Border.all(color: const Color(0xFF4F46E5).withValues(alpha: 0.35)) : null,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4F46E5).withValues(alpha: 0.30),
                      blurRadius: 22,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.manage_accounts_rounded, color: Colors.white, size: 26),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Other Staff',
                                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                '$totalOtherStaff member${totalOtherStaff != 1 ? 's' : ''} • $principalCount principal',
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.80), fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
                          onPressed: fetchOtherStaff,
                          tooltip: 'Refresh',
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white.withValues(alpha: 0.15),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // Stats row
                    Row(
                      children: [
                        _buildHeaderStat('Total', '$totalOtherStaff', Icons.groups_rounded),
                        const SizedBox(width: 10),
                        _buildHeaderStat('Principal', '$principalCount', Icons.school_rounded),
                        const SizedBox(width: 10),
                        _buildHeaderStat('Showing', '${displayedStaff.length}', Icons.visibility_rounded),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // ── Controls toolbar ────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderClr),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                      blurRadius: 12,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // Role filter
                        Container(
                          width: isMobile ? 140 : 175,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFF4F46E5).withValues(alpha: 0.35)),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: selectedRoleFilter ?? 'All',
                              isExpanded: true,
                              hint: const Text('Role'),
                              items: filterOptions.map((role) {
                                return DropdownMenuItem(
                                  value: role,
                                  child: Text(
                                    role == 'All' ? 'All Roles' : _getRoleLabel(role),
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                );
                              }).toList(),
                              onChanged: (value) => setState(() => selectedRoleFilter = value),
                            ),
                          ),
                        ),
                        // Search field
                        SizedBox(
                          width: isMobile ? 180 : 240,
                          child: TextField(
                            controller: searchCtrl,
                            decoration: InputDecoration(
                              hintText: 'Search name / reg / role...',
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              prefixIcon: const Icon(Icons.search_rounded, size: 18),
                              suffixIcon: searchQuery.isEmpty ? null : IconButton(
                                icon: const Icon(Icons.close_rounded, size: 18),
                                onPressed: () {
                                  searchCtrl.clear();
                                  setState(() => searchQuery = '');
                                },
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: const Color(0xFF4F46E5).withValues(alpha: 0.35)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: const Color(0xFF4F46E5).withValues(alpha: 0.25)),
                              ),
                            ),
                            style: const TextStyle(fontSize: 13),
                            onChanged: (v) => setState(() => searchQuery = v),
                          ),
                        ),
                        // Add Staff button
                        GestureDetector(
                          onTap: () => _showStaffDialog(),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF4F46E5), Color(0xFF6366F1)],
                              ),
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF4F46E5).withValues(alpha: 0.30),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add_rounded, color: Colors.white, size: 18),
                                SizedBox(width: 6),
                                Text('Add Staff', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                              ],
                            ),
                          ),
                        ),
                        if (principal == null)
                          GestureDetector(
                            onTap: () => _showStaffDialog(isPrincipal: true),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF3730A3), Color(0xFF4F46E5)],
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.school_rounded, color: Colors.white, size: 18),
                                  SizedBox(width: 6),
                                  Text('Add Principal', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // ── Staff list ──────────────────────────────────────────────
              if (isLoading)
                const SizedBox(
                  height: 260,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (displayedStaff.isEmpty)
                Container(
                  height: 260,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderClr),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.engineering_rounded, size: 56, color: const Color(0xFF4F46E5).withValues(alpha: 0.35)),
                      const SizedBox(height: 12),
                      Text(
                        'No staff found',
                        style: TextStyle(color: isDark ? Colors.white54 : Colors.grey[600], fontSize: 16),
                      ),
                      const SizedBox(height: 14),
                      GestureDetector(
                        onTap: () => _showStaffDialog(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [Color(0xFF4F46E5), Color(0xFF6366F1)]),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text('+ Add Staff', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                )
              else
                ...displayedStaff.asMap().entries.map((entry) {
                  return _buildStaffCard(entry.value, isMobile, isDark, cardBg, borderClr);
                }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderStat(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white70, size: 16),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
            Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.70), fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _buildStaffCard(Map<String, dynamic> staff, bool isMobile, [bool isDark = false, Color? cardBg, Color? borderClr]) {
    final displayName = (staff['name'] ?? 'Unknown').toString();
    final displayRegNo = (staff['reg_no'] ?? '').toString();
    final displayUsername = (staff['username'] ?? '').toString();
    final displayRole = _getRoleLabel((staff['role'] ?? '').toString());
    final roleStr = (staff['role'] ?? '').toString();
    final nameInitial = displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U';
    final isPrincipal = roleStr == 'principal';

    // Role-based gradient colors
    final roleGradient = {
      'principal': [const Color(0xFF3730A3), const Color(0xFF4F46E5)],
      'placement_staff': [const Color(0xFF0D9488), const Color(0xFF14B8A6)],
      'lab_technician': [const Color(0xFF0284C7), const Color(0xFF06B6D4)],
      'system_admin': [const Color(0xFF7C3AED), const Color(0xFFA855F7)],
      'office_staff': [const Color(0xFF1D4ED8), const Color(0xFF3B82F6)],
    };
    final gradColors = roleGradient[roleStr] ?? [const Color(0xFF4F46E5), const Color(0xFF6366F1)];

    final bg = cardBg ?? Colors.white;
    final border = borderClr ?? Colors.grey.shade200;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: gradColors[0].withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Gradient avatar with initial
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: gradColors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: gradColors[0].withValues(alpha: 0.40),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      nameInitial,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Info section
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              displayName + (staff['suspended'] == true ? ' (Suspended)' : ''),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: staff['suspended'] == true 
                                  ? Colors.red 
                                  : (isDark ? Colors.white : Colors.black87),
                                decoration: staff['suspended'] == true ? TextDecoration.lineThrough : null,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isPrincipal)
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                '★ Principal',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(Icons.badge_rounded, size: 12, color: isDark ? Colors.white38 : Colors.grey[500]),
                          const SizedBox(width: 4),
                          Text(displayRegNo, style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.grey[600])),
                          if (!isMobile) ...[
                            const SizedBox(width: 8),
                            Icon(Icons.alternate_email_rounded, size: 12, color: isDark ? Colors.white38 : Colors.grey[500]),
                            const SizedBox(width: 2),
                            Text('@$displayUsername', style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.grey[600])),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: gradColors[0].withValues(alpha: isDark ? 0.20 : 0.10),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: gradColors[0].withValues(alpha: 0.35)),
                        ),
                        child: Text(
                          displayRole,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: gradColors[0],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Action buttons
                Column(
                  children: [
                    IconButton(
                      onPressed: () => _showStaffDialog(existingStaff: staff),
                      icon: Icon(Icons.edit_rounded, size: 19, color: gradColors[0]),
                      tooltip: 'Edit',
                      style: IconButton.styleFrom(
                        backgroundColor: gradColors[0].withValues(alpha: 0.10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.all(6),
                        minimumSize: const Size(34, 34),
                      ),
                    ),
                    const SizedBox(height: 6),
                    IconButton(
                      onPressed: () => _toggleOtherStaffSuspension(staff),
                      icon: Icon(
                        staff['suspended'] == true ? Icons.play_arrow_rounded : Icons.block_rounded,
                        size: 19,
                        color: staff['suspended'] == true ? Colors.green : Colors.orange.shade800,
                      ),
                      tooltip: staff['suspended'] == true ? 'Unsuspend' : 'Suspend',
                      style: IconButton.styleFrom(
                        backgroundColor: (staff['suspended'] == true ? Colors.green : Colors.orange.shade800).withValues(alpha: 0.10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.all(6),
                        minimumSize: const Size(34, 34),
                      ),
                    ),
                    const SizedBox(height: 6),
                    IconButton(
                      onPressed: () => deleteStaff(staff['id'], staff['name']),
                      icon: const Icon(Icons.delete_outline_rounded, size: 19, color: Colors.red),
                      tooltip: 'Delete',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.red.withValues(alpha: 0.10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.all(6),
                        minimumSize: const Size(34, 34),
                      ),
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

}

class LiveLocationsTab extends StatefulWidget {
  final String token;
  const LiveLocationsTab({super.key, required this.token});

  @override
  State<LiveLocationsTab> createState() => _LiveLocationsTabState();
}

class _LiveLocationsTabState extends State<LiveLocationsTab> {
  bool _isLoading = true;
  String? _error;
  List<dynamic> _locations = [];
  List<dynamic> _filteredLocations = [];
  Timer? _refreshTimer;
  bool _useSatelliteView = false;
  bool _isMapExpanded = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final MapController _mapController = MapController();

  // Trail & Permission States
  String? _selectedUserRegNo;
  List<LatLng> _trailPoints = [];
  bool _isTrailLoading = false;
  bool _outPermissionEnabledForSelected = false;
  bool _isTrackingInstant = false;

  // New Filters
  String _selectedDepartment = 'All Departments';
  bool _onlyBreaches = false;
  DateTime _selectedDate = DateTime.now();

  // Multi-user trails & date awareness
  Map<String, List<LatLng>> _allUserTrails = {};
  bool _isLoadingAllTrails = false;
  List<List<LatLng>> _campusPolygons = [];
  String _filterRole = 'all'; // 'all', 'today', 'students', 'staff'

  bool get _isViewingToday {
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  Color _colorForRegNo(String regNo) {
    const palette = [
      Color(0xFF0284C7), // sky
      Color(0xFF0D9488), // teal
      Color(0xFFF59E0B), // amber
      Color(0xFF8B5CF6), // violet
      Color(0xFFEC4899), // pink
      Color(0xFF10B981), // emerald
      Color(0xFF6366F1), // indigo
      Color(0xFFF97316), // orange
    ];
    final hash = regNo.hashCode.abs();
    return palette[hash % palette.length];
  }

  @override
  void initState() {
    super.initState();
    _filteredLocations = [];
    _fetchLocations();
    _refreshTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      if (_isViewingToday) {
        _fetchLocations(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchAllTrailsForDate(DateTime date) async {
    final dateStr = "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
    setState(() => _isLoadingAllTrails = true);
    try {
      final response = await apiClient.get(
        '$API_URL/admin/locations/all-trails?date=$dateStr&limit_per_user=250',
        token: widget.token,
      );
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final trails = body['trails'] as List? ?? [];
        final Map<String, List<LatLng>> parsedTrails = {};
        for (final t in trails) {
          final reg = t['reg_no']?.toString();
          final pts = (t['points'] as List? ?? []).map((p) {
            double? lat = double.tryParse(p['latitude'].toString());
            double? lng = double.tryParse(p['longitude'].toString());
            if (lat != null && lng != null) return LatLng(lat, lng);
            return null;
          }).whereType<LatLng>().toList();
          if (reg != null && pts.isNotEmpty) {
            parsedTrails[reg] = pts;
          }
        }
        if (mounted) {
          setState(() {
            _allUserTrails = parsedTrails;
          });
        }
      }
    } catch (_) {}
    finally {
      if (mounted) setState(() => _isLoadingAllTrails = false);
    }
  }

  Future<void> _fetchLocations({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    final dateStr = "${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}";
    final dateQuery = _isViewingToday ? '' : '&date=$dateStr';

    try {
      final response = await apiClient.get(
        '$API_URL/admin/locations/live?include_stale=true&inside_outer_only=false$dateQuery',
        token: widget.token,
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (mounted) {
          List<List<LatLng>> parsedCampus = [];
          if (body['campus_polygons'] is List) {
            final rawPolys = body['campus_polygons'] as List;
            parsedCampus = rawPolys.map((poly) {
              if (poly is List) {
                return poly.map((pt) {
                  if (pt is List && pt.length >= 2) {
                    final lat = double.tryParse(pt[0].toString());
                    final lng = double.tryParse(pt[1].toString());
                    if (lat != null && lng != null) return LatLng(lat, lng);
                  }
                  return null;
                }).whereType<LatLng>().toList();
              }
              return <LatLng>[];
            }).where((p) => p.isNotEmpty).toList();
          }
          if (parsedCampus.isEmpty) {
            parsedCampus = CollegeIPConfig.geoFencePolygons.map((p) => p.map((pt) => LatLng(pt[0], pt[1])).toList()).toList();
          }

          setState(() {
            _locations = body['locations'] ?? [];
            _campusPolygons = parsedCampus;
            _filterLocations();
            _isLoading = false;
            _error = null;
          });
          // Refresh out permission state if selected user is loaded
          if (_selectedUserRegNo != null) {
            final selectedUser = _locations.firstWhere(
              (loc) => loc['reg_no'] == _selectedUserRegNo,
              orElse: () => null,
            );
            if (selectedUser != null) {
              setState(() {
                _outPermissionEnabledForSelected = selectedUser['out_permission_enabled'] == true;
              });
            }
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _error = 'Failed to load locations (${response.statusCode})';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Failed to load locations: $e';
        });
      }
    }
  }

  void _fitMapBounds() {
    final List<LatLng> pointsToFit = [];
    for (final poly in _campusPolygons) {
      pointsToFit.addAll(poly);
    }
    for (final loc in _filteredLocations) {
      double? lat = double.tryParse(loc['latitude'].toString());
      double? lng = double.tryParse(loc['longitude'].toString());
      if (lat != null && lng != null) pointsToFit.add(LatLng(lat, lng));
    }
    if (_trailPoints.isNotEmpty) {
      pointsToFit.addAll(_trailPoints);
    }
    if (pointsToFit.isNotEmpty) {
      try {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(pointsToFit),
            padding: const EdgeInsets.all(36),
          ),
        );
      } catch (_) {
        _mapController.move(_mapCenter(), 15.0);
      }
    } else {
      _mapController.move(_mapCenter(), 15.0);
    }
  }

  void _filterLocations() {
    var temp = List.from(_locations);

    if (_filterRole == 'today') {
      temp = temp.where((item) => item['is_today'] == true).toList();
    } else if (_filterRole == 'students') {
      temp = temp.where((item) => item['role']?.toString().toLowerCase() == 'student').toList();
    } else if (_filterRole == 'staff') {
      temp = temp.where((item) => item['role']?.toString().toLowerCase() != 'student').toList();
    }

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      temp = temp.where((item) {
        final name = (item['name']?.toString() ?? '').toLowerCase();
        final regNo = (item['reg_no']?.toString() ?? '').toLowerCase();
        return name.contains(query) || regNo.contains(query);
      }).toList();
    }

    if (_selectedDepartment != 'All Departments') {
      temp = temp.where((item) => item['dept']?.toString() == _selectedDepartment).toList();
    }

    if (_onlyBreaches) {
      temp = temp.where((item) => item['boundary_warning'] == true).toList();
    }

    setState(() {
      _filteredLocations = temp;
    });
  }

  List<String> _getDepartments() {
    final depts = _locations
        .map((loc) => loc['dept']?.toString())
        .whereType<String>()
        .where((d) => d.isNotEmpty)
        .toSet()
        .toList();
    depts.sort();
    return ['All Departments', ...depts];
  }

  Future<void> _selectUser(Map<String, dynamic> item) async {
    final regNo = item['reg_no']?.toString();
    if (regNo == null) return;
    
    final preloadedTrail = _allUserTrails[regNo] ?? [];

    setState(() {
      _selectedUserRegNo = regNo;
      _outPermissionEnabledForSelected = item['out_permission_enabled'] == true;
      _trailPoints = preloadedTrail;
      _isTrailLoading = preloadedTrail.isEmpty;
    });

    double? lat = double.tryParse(item['latitude'].toString());
    double? lng = double.tryParse(item['longitude'].toString());
    if (lat != null && lng != null) {
      _mapController.move(LatLng(lat, lng), 16.0);
    }

    await _fetchUserHistory(regNo);
  }

  Future<void> _fetchUserHistory(String regNo) async {
    final dateStr = "${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}";
    try {
      final response = await apiClient.get(
        '$API_URL/admin/locations/history?reg_no=$regNo&date=$dateStr&limit=1000',
        token: widget.token,
      );
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final history = body['history'] as List? ?? [];
        final points = history.map((h) {
          double? lat = double.tryParse(h['latitude'].toString());
          double? lng = double.tryParse(h['longitude'].toString());
          if (lat != null && lng != null) {
            return LatLng(lat, lng);
          }
          return null;
        }).whereType<LatLng>().toList();
        
        if (points.isNotEmpty && mounted) {
          setState(() {
            _trailPoints = points.reversed.toList();
          });
        }
      }
    } catch (_) {
    } finally {
      setState(() {
        _isTrailLoading = false;
      });
    }
  }

  Future<void> _toggleOutPermission(String regNo, bool enabled) async {
    try {
      final response = await apiClient.post(
        '$API_URL/admin/user/out-permission',
        token: widget.token,
        body: jsonEncode({
          'reg_no': regNo,
          'enabled': enabled,
        }),
      );
      if (response.statusCode == 200) {
        setState(() {
          _outPermissionEnabledForSelected = enabled;
          final idx = _locations.indexWhere((loc) => loc['reg_no'] == regNo);
          if (idx != -1) {
            _locations[idx]['out_permission_enabled'] = enabled;
            _filterLocations();
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(enabled ? 'Outing permission granted successfully' : 'Outing permission revoked'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _trackUserInstant(String regNo) async {
    if (_isTrackingInstant) return;
    setState(() {
      _isTrackingInstant = true;
    });

    try {
      final response = await apiClient.post(
        '$API_URL/admin/locations/force-update/$regNo',
        token: widget.token,
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Instant location update requested! Contacting device...'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 4),
          ),
        );

        // Poll for updates every 3 seconds for 15 seconds
        int attempts = 0;
        Timer.periodic(const Duration(seconds: 3), (timer) async {
          attempts++;
          if (attempts >= 5 || !mounted) {
            timer.cancel();
            if (mounted) {
              setState(() {
                _isTrackingInstant = false;
              });
            }
            return;
          }
          await _fetchLocations(silent: true);
        });
      } else {
        setState(() {
          _isTrackingInstant = false;
        });
        final bodyData = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to request update: ${bodyData['detail'] ?? response.body}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isTrackingInstant = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  LatLng _mapCenter() {
    if (_trailPoints.isNotEmpty) {
      return _trailPoints.last;
    }
    if (_filteredLocations.isNotEmpty) {
      final first = _filteredLocations.first;
      double? lat = double.tryParse(first['latitude'].toString());
      double? lng = double.tryParse(first['longitude'].toString());
      return LatLng(lat ?? 11.041641245255384, lng ?? 77.07418338092796);
    }
    return const LatLng(11.041641245255384, 77.07418338092796);
  }

  List<Marker> _buildMarkers() {
    final list = _filteredLocations
        .map((item) {
          double? lat;
          double? lng;
          if (item['latitude'] is num) {
            lat = (item['latitude'] as num).toDouble();
          } else {
            lat = double.tryParse(item['latitude'].toString());
          }
          if (item['longitude'] is num) {
            lng = (item['longitude'] as num).toDouble();
          } else {
            lng = double.tryParse(item['longitude'].toString());
          }
          if (lat == null || lng == null) return null;

          final name = item['name']?.toString() ?? item['reg_no']?.toString() ?? 'User';
          final role = (item['role']?.toString() ?? 'student').toLowerCase();
          final Color roleColor = switch (role) {
            'staff' => const Color(0xFF4F46E5),
            'hod' => const Color(0xFFD97706),
            'other_staff' => const Color(0xFF0D9488),
            _ => const Color(0xFF2563EB),
          };
          final isWarning = item['boundary_warning'] == true;
          final isSelected = item['reg_no'] == _selectedUserRegNo;
          final lastSeenRel = item['last_seen_relative']?.toString() ?? '';

          return Marker(
            point: LatLng(lat, lng),
            width: 130,
            height: 64,
            child: GestureDetector(
              onTap: () => _selectUser(item),
              child: Tooltip(
                message: isWarning 
                    ? '$name ($role) • $lastSeenRel • BREACH: ${item['warning_message'] ?? 'Outside boundary!'}'
                    : '$name ($role) • $lastSeenRel',
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected 
                            ? Colors.deepPurpleAccent.shade700 
                            : (isWarning ? Colors.redAccent.shade700 : roleColor.withValues(alpha: 0.90)),
                        borderRadius: BorderRadius.circular(12),
                        border: isSelected 
                            ? Border.all(color: Colors.amberAccent, width: 2) 
                            : (isWarning ? Border.all(color: Colors.white, width: 1.5) : null),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Icon(
                      isWarning ? Icons.warning_rounded : Icons.location_on,
                      color: isSelected 
                          ? Colors.amberAccent 
                          : (isWarning ? Colors.redAccent.shade700 : roleColor),
                      size: 28,
                    ),
                  ],
                ),
              ),
            ),
          );
        })
        .whereType<Marker>()
        .toList();

    if (_trailPoints.isNotEmpty) {
      list.add(
        Marker(
          point: _trailPoints.first,
          width: 32,
          height: 32,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.green.shade700,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 18),
          ),
        ),
      );
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _fetchLocations,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              )
            ],
          ),
        ),
      );
    }

    final markers = _buildMarkers();
    final isWide = MediaQuery.of(context).size.width >= 900;

    Widget filtersPanel() {
      final depts = _getDepartments();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _searchController,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              hintText: 'Search by name or ID...',
              hintStyle: TextStyle(color: isDark ? Colors.white60 : Colors.black45),
              prefixIcon: Icon(Icons.search, color: primaryColor),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear, color: isDark ? Colors.white54 : Colors.black54),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                        _filterLocations();
                      },
                    )
                  : null,
              filled: true,
              fillColor: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            onChanged: (value) {
              setState(() => _searchQuery = value);
              _filterLocations();
            },
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  label: Text('All (${_locations.length})', style: const TextStyle(fontSize: 12)),
                  selected: _filterRole == 'all',
                  onSelected: (val) {
                    if (val) {
                      setState(() => _filterRole = 'all');
                      _filterLocations();
                    }
                  },
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: Text(
                    'Active Today (${_locations.where((l) => l['is_today'] == true).length})',
                    style: const TextStyle(fontSize: 12),
                  ),
                  selected: _filterRole == 'today',
                  onSelected: (val) {
                    if (val) {
                      setState(() => _filterRole = 'today');
                      _filterLocations();
                    }
                  },
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: Text(
                    'Students (${_locations.where((l) => (l['role']?.toString().toLowerCase() == 'student')).length})',
                    style: const TextStyle(fontSize: 12),
                  ),
                  selected: _filterRole == 'students',
                  onSelected: (val) {
                    if (val) {
                      setState(() => _filterRole = 'students');
                      _filterLocations();
                    }
                  },
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: Text(
                    'Staff (${_locations.where((l) => (l['role']?.toString().toLowerCase() != 'student')).length})',
                    style: const TextStyle(fontSize: 12),
                  ),
                  selected: _filterRole == 'staff',
                  onSelected: (val) {
                    if (val) {
                      setState(() => _filterRole = 'staff');
                      _filterLocations();
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: false,
                      value: _selectedDepartment,
                      dropdownColor: isDark ? const Color(0xFF1E1E24) : Colors.white,
                      style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
                      items: depts.map((d) => DropdownMenuItem(
                        value: d,
                        child: Text(d.toUpperCase(), overflow: TextOverflow.ellipsis),
                      )).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedDepartment = val);
                          _filterLocations();
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Breaches Only', style: TextStyle(fontSize: 12)),
                  selected: _onlyBreaches,
                  selectedColor: Colors.redAccent.withValues(alpha: 0.25),
                  checkmarkColor: Colors.redAccent,
                  labelStyle: TextStyle(color: _onlyBreaches ? Colors.redAccent : (isDark ? Colors.white70 : Colors.black87)),
                  onSelected: (val) {
                    setState(() => _onlyBreaches = val);
                    _filterLocations();
                  },
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text(
                    "${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}",
                    style: const TextStyle(fontSize: 12),
                  ),
                  selected: !_isViewingToday,
                  selectedColor: primaryColor.withValues(alpha: 0.25),
                  checkmarkColor: primaryColor,
                  avatar: Icon(Icons.calendar_month_rounded, size: 16, color: primaryColor),
                  labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
                  onSelected: (val) async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime.now().subtract(const Duration(days: 90)),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setState(() {
                        _selectedDate = picked;
                        _selectedUserRegNo = null;
                        _trailPoints = [];
                        _allUserTrails = {};
                      });
                      await _fetchLocations();
                      final isPickedToday = picked.year == DateTime.now().year &&
                          picked.month == DateTime.now().month &&
                          picked.day == DateTime.now().day;
                      if (!isPickedToday) {
                        await _fetchAllTrailsForDate(picked);
                      }
                    }
                  },
                ),
                if (!_isViewingToday) ...[
                  const SizedBox(width: 8),
                  ActionChip(
                    avatar: const Icon(Icons.today_rounded, size: 16, color: Colors.deepPurpleAccent),
                    label: const Text('Back to Today', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.deepPurpleAccent)),
                    backgroundColor: Colors.deepPurpleAccent.withValues(alpha: 0.15),
                    onPressed: () async {
                      setState(() {
                        _selectedDate = DateTime.now();
                        _selectedUserRegNo = null;
                        _trailPoints = [];
                        _allUserTrails = {};
                      });
                      await _fetchLocations();
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      );
    }

    Widget mapCanvas() {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.1),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _mapCenter(),
                initialZoom: 15,
                minZoom: 3,
                maxZoom: _useSatelliteView ? 21 : 20,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all,
                ),
                cameraConstraint: CameraConstraint.unconstrained(),
              ),
              children: [
                TileLayer(
                  key: ValueKey('live_map_tiles_${_useSatelliteView ? 'satellite' : 'standard'}'),
                  urlTemplate: _useSatelliteView
                      ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                      : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  fallbackUrl: _useSatelliteView
                      ? 'https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                      : 'https://a.tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: kIsWeb ? 'web.visiongate.app' : 'com.visiongate.app',
                  tileProvider: NetworkTileProvider(),
                  maxNativeZoom: _useSatelliteView ? 18 : 19,
                  maxZoom: _useSatelliteView ? 21 : 20,
                  minZoom: 3,
                  keepBuffer: 12,
                  panBuffer: 3,
                  errorImage: const AssetImage('assets/images/map_error.png'),
                ),
                // Render campus boundary polygon (geofence area)
                if (_campusPolygons.isNotEmpty)
                  PolygonLayer(
                    polygons: _campusPolygons.map((pts) => Polygon(
                      points: pts,
                      color: const Color(0xFF10B981).withValues(alpha: 0.12),
                      borderColor: const Color(0xFF059669),
                      borderStrokeWidth: 2.2,
                    )).toList(),
                  ),
                PolylineLayer(
                  polylines: [
                    // Render multi-user historical trails for the selected date
                    for (final entry in _allUserTrails.entries)
                      if (entry.key != _selectedUserRegNo && entry.value.length > 1)
                        Polyline(
                          points: entry.value,
                          strokeWidth: 3.2,
                          color: _colorForRegNo(entry.key).withValues(alpha: 0.70),
                          borderStrokeWidth: 0.8,
                          borderColor: Colors.black26,
                        ),
                    // Render selected user trail highlighted on top
                    if (_trailPoints.length > 1)
                      Polyline(
                        points: _trailPoints,
                        strokeWidth: 5.0,
                        color: Colors.deepPurpleAccent,
                        borderStrokeWidth: 2.0,
                        borderColor: Colors.white,
                      ),
                  ],
                ),
                MarkerLayer(markers: markers),
                Positioned(
                  bottom: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    color: Colors.black.withValues(alpha: 0.6),
                    child: Text(
                      _useSatelliteView ? '© Esri, DigitalGlobe' : '© OpenStreetMap contributors',
                      style: const TextStyle(color: Colors.white, fontSize: 9),
                    ),
                  ),
                ),
              ],
            ),
            if (_filteredLocations.isEmpty)
              Positioned(
                top: 56,
                left: 16,
                right: 16,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.82),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.shield_outlined, color: Color(0xFF10B981), size: 16),
                        const SizedBox(width: 8),
                        const Text(
                          'Campus boundary loaded • No users active in this filter',
                          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => _fetchLocations(),
                          child: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 16),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (!_isViewingToday)
              Positioned(
                top: 12,
                left: 12,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.82),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.history_toggle_off_rounded, color: Colors.amberAccent, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'History: ${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year} (${_filteredLocations.length} Tracked)',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        if (_isLoadingAllTrails) ...[
                          const SizedBox(width: 8),
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amberAccent),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 12,
              right: 12,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.7),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Fit All Markers & Campus',
                          icon: Icon(Icons.crop_free_rounded, color: primaryColor, size: 20),
                          onPressed: _fitMapBounds,
                        ),
                        Container(
                          width: 1,
                          height: 24,
                          color: (isDark ? Colors.white24 : Colors.black12),
                        ),
                        IconButton(
                          tooltip: 'Recenter Map',
                          icon: Icon(Icons.my_location, color: primaryColor, size: 20),
                          onPressed: () {
                            _mapController.move(_mapCenter(), 15.0);
                          },
                        ),
                        Container(
                          width: 1,
                          height: 24,
                          color: (isDark ? Colors.white24 : Colors.black12),
                        ),
                        TextButton.icon(
                          onPressed: () => setState(() => _useSatelliteView = !_useSatelliteView),
                          icon: Icon(_useSatelliteView ? Icons.satellite_alt : Icons.map, size: 16, color: primaryColor),
                          label: Text(
                            _useSatelliteView ? 'Sat' : 'Map',
                            style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 12),
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 24,
                          color: (isDark ? Colors.white24 : Colors.black12),
                        ),
                        IconButton(
                          tooltip: _isMapExpanded ? 'Normal Size' : 'Full Size',
                          icon: Icon(_isMapExpanded ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded, color: primaryColor, size: 20),
                          onPressed: () {
                            setState(() => _isMapExpanded = !_isMapExpanded);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_selectedUserRegNo != null)
              Positioned(
                bottom: 12,
                left: 12,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.75),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.gesture_rounded, color: Colors.tealAccent, size: 16),
                        const SizedBox(width: 6),
                        const Text(
                          'Showing Trail Path',
                          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.close, color: Colors.redAccent, size: 16),
                          onPressed: () {
                            setState(() {
                              _selectedUserRegNo = null;
                              _trailPoints = [];
                            });
                          },
                        )
                      ],
                    ),
                  ),
                ),
              )
          ],
        ),
      );
    }

    Widget usersCanvas() {
      return ListView(
        physics: const BouncingScrollPhysics(),
        children: [
          Row(
            children: [
              Icon(Icons.radar_rounded, color: primaryColor, size: 28),
              const SizedBox(width: 8),
              Text(
                _isViewingToday ? 'Live Terminals' : 'Historical Tracking',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _isViewingToday ? '${_filteredLocations.length} Online' : '${_filteredLocations.length} Tracked',
                  style: TextStyle(
                    color: primaryColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          filtersPanel(),
          const SizedBox(height: 16),
          if (_filteredLocations.isEmpty)
            GlassCard(
              accentColor: primaryColor,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.search_off_rounded, color: isDark ? Colors.white54 : Colors.black54, size: 40),
                    const SizedBox(height: 12),
                    Text(
                      _searchQuery.isNotEmpty
                          ? 'No active terminals match your filters.'
                          : (_isViewingToday
                              ? 'No active terminals are currently transmitting coordinate beacons.'
                              : 'No location tracking records found for this date.'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
                    ),
                  ],
                ),
              ),
            ),
          ..._filteredLocations.map((item) {
            final name = item['name']?.toString() ?? '-';
            final regNo = item['reg_no']?.toString() ?? '-';
            final dept = item['dept']?.toString() ?? '-';
            final role = item['role']?.toString() ?? '-';
            final lat = item['latitude']?.toString() ?? '-';
            final lng = item['longitude']?.toString() ?? '-';
            final seen = item['last_seen_at']?.toString() ?? '-';
            final accuracy = item['accuracy_meters']?.toString() ?? 'n/a';

            final isWarning = item['boundary_warning'] == true;
            final isOutPermissionEnabled = item['out_permission_enabled'] == true;
            final warningMsg = item['warning_message']?.toString() ?? 'Outside movement limit';
            final isSelected = _selectedUserRegNo == regNo;
            final totalPoints = item['total_points'] is num ? (item['total_points'] as num).toInt() : 1;

            return GestureDetector(
              onTap: () => _selectUser(item),
              child: GlassCard(
                margin: const EdgeInsets.only(bottom: 12),
                accentColor: isSelected 
                    ? Colors.deepPurpleAccent 
                    : (isOutPermissionEnabled 
                        ? Colors.blueAccent 
                        : (isWarning ? Colors.redAccent.shade700 : primaryColor)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: (isOutPermissionEnabled 
                            ? Colors.blue 
                            : (isWarning ? Colors.redAccent : Colors.green)).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isOutPermissionEnabled 
                            ? Icons.directions_run_rounded 
                            : (isWarning ? Icons.warning_rounded : Icons.circle),
                        color: isOutPermissionEnabled 
                            ? Colors.blue 
                            : (isWarning ? Colors.redAccent : Colors.green),
                        size: 14,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  name,
                                  style: TextStyle(
                                    color: isDark ? Colors.white : Colors.black87,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              if (totalPoints > 1)
                                Container(
                                  margin: const EdgeInsets.only(right: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.purple.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '$totalPoints pts',
                                    style: const TextStyle(
                                      color: Colors.purpleAccent,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              if (isOutPermissionEnabled)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade700,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Text(
                                    'EXEMPTED',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                )
                              else if (isWarning)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent.shade700,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Text(
                                    'BREACH',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          Text(
                            '$regNo • $role ($dept)',
                            style: TextStyle(
                              color: isDark ? Colors.white60 : Colors.black54,
                              fontSize: 13,
                            ),
                          ),
                          if (isWarning && !isOutPermissionEnabled) ...[
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.redAccent.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.2)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.warning_amber_rounded, size: 14, color: Colors.redAccent),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      warningMsg,
                                      style: const TextStyle(
                                        color: Colors.redAccent,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (isSelected) ...[
                            const SizedBox(height: 12),
                            Divider(color: isDark ? Colors.white24 : Colors.black12, height: 1),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.directions_walk_rounded, size: 16, color: isDark ? Colors.tealAccent : Colors.teal),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Allow Going Out',
                                      style: TextStyle(
                                        fontSize: 12, 
                                        fontWeight: FontWeight.w600,
                                        color: isDark ? Colors.white70 : Colors.black87,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(
                                  height: 24,
                                  child: Switch(
                                    value: _outPermissionEnabledForSelected,
                                    activeColor: Colors.deepPurpleAccent,
                                    onChanged: (newValue) async {
                                      await _toggleOutPermission(regNo, newValue);
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            // Navigation Button to User Details page
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                _isTrackingInstant
                                    ? const Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 12),
                                        child: SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.deepPurpleAccent),
                                        ),
                                      )
                                    : TextButton.icon(
                                        onPressed: () => _trackUserInstant(regNo),
                                        icon: const Icon(Icons.gps_fixed, size: 16, color: Colors.teal),
                                        label: const Text(
                                          'Track Instant',
                                          style: TextStyle(fontSize: 12, color: Colors.teal, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                const SizedBox(width: 8),
                                TextButton.icon(
                                  onPressed: () async {
                                    final dynamic result = await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => UserTrackingDetailPage(
                                          user: item,
                                          token: widget.token,
                                        ),
                                      ),
                                    );
                                    if (result is bool) {
                                      // Sync back out permission if modified on detail screen
                                      setState(() {
                                        _outPermissionEnabledForSelected = result;
                                        final idx = _locations.indexWhere((loc) => loc['reg_no'] == regNo);
                                        if (idx != -1) {
                                          _locations[idx]['out_permission_enabled'] = result;
                                          _filterLocations();
                                        }
                                      });
                                    }
                                  },
                                  icon: const Icon(Icons.analytics_outlined, size: 16, color: Colors.deepPurpleAccent),
                                  label: const Text(
                                    'Detail Tracking Page',
                                    style: TextStyle(fontSize: 12, color: Colors.deepPurpleAccent, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            if (_isTrailLoading)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8.0),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.deepPurpleAccent),
                                    ),
                                    SizedBox(width: 8),
                                    Text('Loading route trail...', style: TextStyle(fontSize: 12, color: Colors.tealAccent)),
                                  ],
                                ),
                              )
                            else if (_trailPoints.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4.0),
                                child: Text(
                                  'Route Trail: ${_trailPoints.length} segments visible on map',
                                  style: TextStyle(
                                    fontSize: 12, 
                                    color: isDark ? Colors.tealAccent : Colors.teal.shade700, 
                                    fontWeight: FontWeight.bold
                                  ),
                                ),
                              ),
                          ],
                          const SizedBox(height: 8),
                          Divider(color: isDark ? Colors.white10 : Colors.black12, height: 1),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.location_on_outlined, size: 14, color: primaryColor),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  'Coordinates: $lat, $lng',
                                  style: TextStyle(
                                    color: isDark ? Colors.white70 : Colors.black54,
                                    fontSize: 12,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.gps_fixed_rounded, size: 14, color: primaryColor),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  'Precision: ±$accuracy m | Beacons: $seen',
                                  style: TextStyle(
                                    color: isDark ? Colors.white60 : Colors.black54,
                                    fontSize: 12,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      );
    }

    if (isWide) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 45,
              child: mapCanvas(),
            ),
            const SizedBox(width: 24),
            Expanded(
              flex: 55,
              child: usersCanvas(),
            ),
          ],
        ),
      );
    } else {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SizedBox(
              height: _isMapExpanded ? MediaQuery.of(context).size.height * 0.70 : 420,
              width: double.infinity,
              child: mapCanvas(),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: usersCanvas(),
            ),
          ],
        ),
      );
    }
  }
}

// ── Dedicated Separate User Details Page ──────────────────────
class UserTrackingDetailPage extends StatefulWidget {
  final Map<String, dynamic> user;
  final String token;

  const UserTrackingDetailPage({
    super.key,
    required this.user,
    required this.token,
  });

  @override
  State<UserTrackingDetailPage> createState() => _UserTrackingDetailPageState();
}

class _UserTrackingDetailPageState extends State<UserTrackingDetailPage> {
  bool _isLoading = true;
  String? _error;
  List<dynamic> _history = [];
  List<LatLng> _trailPoints = [];
  double _totalDistance = 0.0;
  int _breachCount = 0;
  bool _outPermissionEnabled = false;
  bool _useSatelliteView = false;
  final MapController _mapController = MapController();
  
  // Playback States
  int _playbackIndex = -1;
  bool _isPlaying = false;
  Timer? _playbackTimer;
  List<dynamic> _chronologicalHistory = [];

  @override
  void initState() {
    super.initState();
    _outPermissionEnabled = widget.user['out_permission_enabled'] == true;
    _fetchHistory();
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchHistory() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final regNo = widget.user['reg_no'] ?? widget.user['regNo'];
      final response = await apiClient.get(
        '$API_URL/admin/locations/history?reg_no=$regNo&limit=1000',
        token: widget.token,
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final list = body['history'] as List? ?? [];
        
        final reversedList = list.reversed.toList();
        final points = <LatLng>[];
        final validChronological = <dynamic>[];
        double distance = 0.0;
        int breaches = 0;

        for (int i = 0; i < reversedList.length; i++) {
          final h = reversedList[i];
          double? lat = double.tryParse(h['latitude'].toString());
          double? lng = double.tryParse(h['longitude'].toString());
          if (lat != null && lng != null) {
            final pt = LatLng(lat, lng);
            points.add(pt);
            validChronological.add(h);

            if (points.length > 1) {
              final prev = points[points.length - 2];
              distance += _calculateDistance(prev.latitude, prev.longitude, pt.latitude, pt.longitude);
            }

            if (h['boundary_warning'] == true) {
              breaches++;
            }
          }
        }

        if (mounted) {
          setState(() {
            _history = list;
            _chronologicalHistory = validChronological;
            _trailPoints = points;
            _totalDistance = distance;
            _breachCount = breaches;
            _playbackIndex = -1;
            _isPlaying = false;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _error = 'Failed to load history (${response.statusCode})';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load history: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _startPlayback() {
    if (_trailPoints.isEmpty) return;
    
    setState(() {
      _isPlaying = true;
      if (_playbackIndex == -1 || _playbackIndex >= _trailPoints.length - 1) {
        _playbackIndex = 0;
      }
    });

    _playbackTimer?.cancel();
    _playbackTimer = Timer.periodic(const Duration(milliseconds: 600), (timer) {
      if (_playbackIndex < _trailPoints.length - 1) {
        setState(() {
          _playbackIndex++;
        });
        double zoom = 15.0;
        try {
          zoom = _mapController.camera.zoom;
        } catch (_) {}
        _mapController.move(_trailPoints[_playbackIndex], zoom);
      } else {
        _pausePlayback();
      }
    });
  }

  void _pausePlayback() {
    _playbackTimer?.cancel();
    setState(() {
      _isPlaying = false;
    });
  }

  void _resetPlayback() {
    _pausePlayback();
    setState(() {
      _playbackIndex = -1;
    });
    if (_trailPoints.isNotEmpty) {
      double zoom = 15.0;
      try {
        zoom = _mapController.camera.zoom;
      } catch (_) {}
      _mapController.move(_trailPoints.last, zoom);
    }
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295;
    final a = 0.5 - math.cos((lat2 - lat1) * p) / 2 +
        math.cos(lat1 * p) * math.cos(lat2 * p) *
        (1 - math.cos((lon2 - lon1) * p)) / 2;
    return 12742 * math.asin(math.sqrt(a)) * 1000;
  }

  Future<void> _toggleOutPermission(bool enabled) async {
    final regNo = widget.user['reg_no'] ?? widget.user['regNo'];
    try {
      final response = await apiClient.post(
        '$API_URL/admin/user/out-permission',
        token: widget.token,
        body: jsonEncode({
          'reg_no': regNo,
          'enabled': enabled,
        }),
      );
      if (response.statusCode == 200) {
        setState(() {
          _outPermissionEnabled = enabled;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(enabled ? 'Outing permission granted successfully' : 'Outing permission revoked'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {}
  }

  LatLng _currentLocation() {
    if (_trailPoints.isNotEmpty) {
      return _trailPoints.last;
    }
    double? lat = double.tryParse(widget.user['latitude']?.toString() ?? '');
    double? lng = double.tryParse(widget.user['longitude']?.toString() ?? '');
    return LatLng(lat ?? 11.041641245255384, lng ?? 77.07418338092796);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E1E24) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? Colors.white70 : Colors.black54;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.user['name'] ?? 'User'} Trails'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context, _outPermissionEnabled),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 900;

                    Widget mapPart() {
                      final log = (_playbackIndex >= 0 && _playbackIndex < _chronologicalHistory.length) 
                          ? _chronologicalHistory[_playbackIndex] 
                          : null;
                      final dt = log != null ? DateTime.tryParse(log['captured_at']?.toString() ?? '') : null;
                      final istDt = dt?.toUtc().add(const Duration(hours: 5, minutes: 30));
                      final timeStr = istDt != null
                          ? '${istDt.hour.toString().padLeft(2, '0')}:${istDt.minute.toString().padLeft(2, '0')}'
                          : 'n/a';
                      final speedVal = log != null 
                          ? (double.tryParse(log['speed_mps']?.toString() ?? '') ?? 0.0) 
                          : 0.0;
                      final speedKmh = (speedVal * 3.6).toStringAsFixed(1);

                      return Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          children: [
                            FlutterMap(
                              mapController: _mapController,
                              options: MapOptions(
                                initialCenter: _currentLocation(),
                                initialZoom: 16,
                                minZoom: 3,
                                maxZoom: _useSatelliteView ? 21 : 20,
                                interactionOptions: const InteractionOptions(
                                  flags: InteractiveFlag.all,
                                ),
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate: _useSatelliteView
                                      ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                                      : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                  fallbackUrl: _useSatelliteView
                                      ? 'https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                                      : 'https://a.tile.openstreetmap.org/{z}/{x}/{y}.png',
                                  userAgentPackageName: 'com.visiongate.app',
                                  tileProvider: NetworkTileProvider(),
                                  maxZoom: 21,
                                ),
                                if (_trailPoints.isNotEmpty)
                                  PolylineLayer(
                                    polylines: [
                                      Polyline(
                                        points: _playbackIndex == -1 
                                            ? _trailPoints 
                                            : _trailPoints.sublist(0, _playbackIndex + 1),
                                        strokeWidth: 5.0,
                                        color: Colors.deepPurpleAccent,
                                        borderStrokeWidth: 2.0,
                                        borderColor: Colors.white,
                                      ),
                                    ],
                                  ),
                                MarkerLayer(
                                  markers: [
                                    if (_trailPoints.isNotEmpty) ...[
                                      Marker(
                                        point: _trailPoints.first,
                                        width: 32,
                                        height: 32,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: Colors.green,
                                            shape: BoxShape.circle,
                                            border: Border.all(color: Colors.white, width: 2),
                                          ),
                                          child: const Icon(Icons.play_arrow, color: Colors.white, size: 16),
                                        ),
                                      ),
                                      if (_playbackIndex == -1)
                                        Marker(
                                          point: _trailPoints.last,
                                          width: 40,
                                          height: 40,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: _history.first['boundary_warning'] == true ? Colors.red : Colors.deepPurpleAccent,
                                              shape: BoxShape.circle,
                                              border: Border.all(color: Colors.white, width: 2.5),
                                              boxShadow: const [
                                                BoxShadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 3)),
                                              ],
                                            ),
                                            child: const Icon(Icons.person, color: Colors.white, size: 20),
                                          ),
                                        ),
                                      if (_playbackIndex != -1 && _playbackIndex < _trailPoints.length)
                                        Marker(
                                          point: _trailPoints[_playbackIndex],
                                          width: 80,
                                          height: 80,
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.black87,
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  timeStr,
                                                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Container(
                                                width: 32,
                                                height: 32,
                                                decoration: BoxDecoration(
                                                  color: Colors.orange,
                                                  shape: BoxShape.circle,
                                                  border: Border.all(color: Colors.white, width: 2),
                                                  boxShadow: const [
                                                    BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                                                  ],
                                                ),
                                                child: const Icon(Icons.directions_walk_rounded, color: Colors.white, size: 18),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ]
                                  ],
                                ),
                              ],
                            ),
                            Positioned(
                              top: 12,
                              right: 12,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black87,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: IconButton(
                                  icon: Icon(
                                    _useSatelliteView ? Icons.satellite_alt : Icons.map,
                                    color: Colors.white,
                                  ),
                                  onPressed: () => setState(() => _useSatelliteView = !_useSatelliteView),
                                ),
                              ),
                            ),
                            if (_trailPoints.isNotEmpty)
                              Positioned(
                                bottom: 12,
                                left: 12,
                                right: 12,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: BackdropFilter(
                                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: (isDark ? const Color(0xFF1E1E24) : Colors.white).withOpacity(0.85),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                _playbackIndex == -1 ? 'Full Location Trail' : 'Timeline Playback',
                                                style: TextStyle(
                                                  fontSize: 12, 
                                                  fontWeight: FontWeight.bold,
                                                  color: textColor,
                                                ),
                                              ),
                                              if (_playbackIndex != -1)
                                                Text(
                                                  '$timeStr • $speedKmh km/h',
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.deepPurpleAccent,
                                                  ),
                                                ),
                                            ],
                                          ),
                                          Row(
                                            children: [
                                              IconButton(
                                                icon: Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.deepPurpleAccent),
                                                onPressed: _isPlaying ? _pausePlayback : _startPlayback,
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.replay_rounded, color: Colors.deepPurpleAccent),
                                                onPressed: _resetPlayback,
                                              ),
                                              Expanded(
                                                child: SliderTheme(
                                                  data: SliderTheme.of(context).copyWith(
                                                    activeTrackColor: Colors.deepPurpleAccent,
                                                    inactiveTrackColor: isDark ? Colors.white10 : Colors.black12,
                                                    thumbColor: Colors.deepPurpleAccent,
                                                    overlayColor: Colors.deepPurpleAccent.withOpacity(0.12),
                                                  ),
                                                  child: Slider(
                                                    min: 0,
                                                    max: (_trailPoints.length - 1).toDouble() < 0 ? 0 : (_trailPoints.length - 1).toDouble(),
                                                    value: _playbackIndex == -1 
                                                        ? (_trailPoints.isEmpty ? 0.0 : (_trailPoints.length - 1).toDouble()) 
                                                        : _playbackIndex.toDouble().clamp(0.0, _trailPoints.isEmpty ? 0.0 : (_trailPoints.length - 1).toDouble()),
                                                    onChanged: _trailPoints.isEmpty ? null : (val) {
                                                      _pausePlayback();
                                                      setState(() {
                                                        _playbackIndex = val.toInt();
                                                      });
                                                      double zoom = 15.0;
                                                      try {
                                                        zoom = _mapController.camera.zoom;
                                                      } catch (_) {}
                                                      _mapController.move(_trailPoints[_playbackIndex], zoom);
                                                    },
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    }

                    Widget detailsPart() {
                      return ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _buildStatCard(
                                  'Distance Traveled',
                                  '${(_totalDistance / 1000).toStringAsFixed(2)} km',
                                  Icons.directions_walk_rounded,
                                  Colors.blueAccent,
                                  cardBg,
                                  textColor,
                                  subtitleColor,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildStatCard(
                                  'Boundary Breaches',
                                  '$_breachCount Alerts',
                                  Icons.warning_amber_rounded,
                                  _breachCount > 0 ? Colors.redAccent : Colors.green,
                                  cardBg,
                                  textColor,
                                  subtitleColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Card(
                            color: cardBg,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
                            ),
                            child: SwitchListTile(
                              title: const Text('Allow Going Out Today'),
                              subtitle: const Text('Exempts this user from geofence boundary limits.'),
                              value: _outPermissionEnabled,
                              activeColor: Colors.deepPurpleAccent,
                              onChanged: _toggleOutPermission,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Location Log Timeline (${_history.length} Beacons)',
                            style: TextStyle(
                              color: textColor,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_history.isEmpty)
                            const Center(child: Text('No historical tracking coordinates today.'))
                          else
                            ..._history.map((log) {
                              final dt = DateTime.tryParse(log['captured_at']?.toString() ?? '');
                              final istDt = dt?.toUtc().add(const Duration(hours: 5, minutes: 30));
                              final time = istDt != null
                                  ? '${istDt.hour.toString().padLeft(2, '0')}:${istDt.minute.toString().padLeft(2, '0')}'
                                  : 'n/a';
                              final accuracy = log['accuracy_meters']?.toString() ?? 'n/a';
                              final speedVal = double.tryParse(log['speed_mps']?.toString() ?? '') ?? 0.0;
                              final speedKmh = (speedVal * 3.6).toStringAsFixed(1);
                              final isBreached = log['boundary_warning'] == true;

                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                color: isBreached 
                                    ? (isDark ? const Color(0xFF3B1A1A) : Colors.red.shade50)
                                    : cardBg,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                    color: isBreached ? Colors.redAccent : (isDark ? Colors.white10 : Colors.black12),
                                  ),
                                ),
                                child: ListTile(
                                  leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: (isBreached ? Colors.red : Colors.deepPurple).withValues(alpha: 0.12),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      isBreached ? Icons.warning_rounded : Icons.location_history_rounded,
                                      color: isBreached ? Colors.red : Colors.deepPurpleAccent,
                                      size: 18,
                                    ),
                                  ),
                                  title: Text(
                                    isBreached ? 'Boundary Breach Alert' : 'Beacon Ping Received',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: isBreached ? Colors.redAccent : textColor,
                                      fontSize: 14,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'Time: $time | Speed: $speedKmh km/h | Accuracy: ±$accuracy m',
                                    style: TextStyle(color: subtitleColor, fontSize: 12),
                                  ),
                                  trailing: Icon(
                                    log['is_mocked'] == true ? Icons.phonelink_setup_rounded : Icons.gps_fixed_rounded,
                                    color: log['is_mocked'] == true ? Colors.orange : Colors.green,
                                    size: 16,
                                  ),
                                ),
                              );
                            }),
                        ],
                      );
                    }

                    if (isWide) {
                      return Row(
                        children: [
                          Expanded(flex: 45, child: mapPart()),
                          const SizedBox(width: 24),
                          Expanded(flex: 55, child: detailsPart()),
                        ],
                      );
                    } else {
                      return Column(
                        children: [
                          SizedBox(height: 320, child: mapPart()),
                          const SizedBox(height: 16),
                          Expanded(child: detailsPart()),
                        ],
                      );
                    }
                  },
                ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
    Color bg,
    Color textCol,
    Color subCol,
  ) {
    return Card(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: subCol, fontSize: 11)),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      color: textCol,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}// Settings Tab - Admin configuration for attendance settings
class SettingsTab extends StatefulWidget {
  final String token;

  const SettingsTab({super.key, required this.token});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  bool _allowAnyNetwork = false;
  bool _enforceGeoFence = true;
  bool _enforceAppGeoFence = true;
  bool _enforceVpnBlocking = true;
  bool _multiUserKioskMode = false;
  bool _enableThirukkural = true;
  bool _isThemeExpanded = false;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isChangingPassword = false;
  bool _showProfilePasswordOption = false;
  bool get _ssidRequiredForAttendance => !_allowAnyNetwork;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final url = '${CollegeIPConfig.defaultURL}/admin/settings';
      final response = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['settings'] != null) {
          setState(() {
            _allowAnyNetwork = data['settings']['allow_any_network'] ?? false;
            _enforceGeoFence = data['settings']['enforce_geo_fence'] ?? true;
            _enforceAppGeoFence =
                data['settings']['enforce_app_geo_fence'] ?? true;
            _enforceVpnBlocking =
                data['settings']['enforce_vpn_blocking'] ?? true;
            _multiUserKioskMode =
                data['settings']['multi_user_kiosk_mode'] ?? false;
            _enableThirukkural =
                data['settings']['enable_thirukkural'] ?? true;
          });
        }
      }
    } catch (e) {
      print('Error loading settings: ${e}');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<bool> _performSave(String profilePassword) async {
    try {
      final url = '${CollegeIPConfig.defaultURL}/admin/settings';
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'allow_any_network': _allowAnyNetwork,
          'enforce_geo_fence': _enforceGeoFence,
          'enforce_app_geo_fence': _enforceAppGeoFence,
          'enforce_vpn_blocking': _enforceVpnBlocking,
          'multi_user_kiosk_mode': _multiUserKioskMode,
          'enable_thirukkural': _enableThirukkural,
          'profile_password': profilePassword,
        }),
      );

      if (response.statusCode == 200) {
        await AppSettings.refreshSettings();
        return true;
      }
      return false;
    } catch (e) {
      print('Error saving settings: $e');
      return false;
    }
  }

  Future<void> _saveSettings({
    required String title,
    required VoidCallback onConfirmedStateChange,
    required VoidCallback onCancelledStateChange,
    required String successMsg,
  }) async {
    final passwordCtrl = TextEditingController();
    bool isVerifying = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        const accent = Color(0xFF007AFF);

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1E1E22) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              title: Text(
                'Confirm Action',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              content: SizedBox(
                width: MediaQuery.of(context).size.width > 480
                    ? 400
                    : MediaQuery.of(context).size.width * 0.9,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Please enter the profile password to confirm changes.',
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.white70 : Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: passwordCtrl,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'Profile Password',
                          prefixIcon: const Icon(Icons.security, color: accent),
                          filled: true,
                          fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.withOpacity(0.05),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isVerifying
                      ? null
                      : () {
                          onCancelledStateChange();
                          Navigator.pop(context);
                        },
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: isDark ? Colors.white70 : Colors.grey[700]),
                  ),
                ),
                ElevatedButton(
                  onPressed: isVerifying
                      ? null
                      : () async {
                          final password = passwordCtrl.text;
                          if (password.isEmpty) return;

                          setDialogState(() {
                            isVerifying = true;
                          });

                          final success = await _performSave(password);
                          if (success) {
                            onConfirmedStateChange();
                            if (context.mounted) {
                              Navigator.pop(context);
                            }
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(successMsg),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          } else {
                            setDialogState(() {
                              isVerifying = false;
                            });
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Invalid profile password or save failed'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: isVerifying
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text('Confirm'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showChangePasswordDialog() async {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        const accent = Color(0xFF007AFF);
        String? errorText;

        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1E1E22) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.admin_panel_settings_rounded, color: accent, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Change Password',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: MediaQuery.of(context).size.width > 480
                  ? 400
                  : MediaQuery.of(context).size.width * 0.9,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildDialogTextField(
                      label: 'Current Password',
                      controller: currentCtrl,
                      icon: Icons.lock_outline_rounded,
                      isDark: isDark,
                      accentColor: accent,
                    ),
                    const SizedBox(height: 14),
                    _buildDialogTextField(
                      label: 'New Password',
                      controller: newCtrl,
                      icon: Icons.lock_rounded,
                      isDark: isDark,
                      accentColor: accent,
                    ),
                    const SizedBox(height: 14),
                    _buildDialogTextField(
                      label: 'Confirm New Password',
                      controller: confirmCtrl,
                      icon: Icons.check_circle_outline_rounded,
                      isDark: isDark,
                      accentColor: accent,
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.withOpacity(0.3)),
                        ),
                        child: Text(
                          errorText!,
                          style: const TextStyle(color: Colors.red, fontSize: 13),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: _isChangingPassword
                    ? null
                    : () => Navigator.pop(context),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: isDark ? Colors.white70 : Colors.grey[700]),
                ),
              ),
              ElevatedButton(
                onPressed: _isChangingPassword
                    ? null
                    : () async {
                        final current = currentCtrl.text.trim();
                        final newPass = newCtrl.text.trim();
                        final confirm = confirmCtrl.text.trim();

                        if (current.isEmpty ||
                            newPass.isEmpty ||
                            confirm.isEmpty) {
                          setDialogState(() {
                            errorText = 'All fields are required.';
                          });
                          return;
                        }
                        if (newPass.length < 6) {
                          setDialogState(() {
                            errorText = 'New password must be at least 6 characters.';
                          });
                          return;
                        }
                        if (newPass != confirm) {
                          setDialogState(() {
                            errorText = 'New passwords do not match.';
                          });
                          return;
                        }
                        if (current == newPass) {
                          setDialogState(() {
                            errorText = 'New password must be different.';
                          });
                          return;
                        }

                        setState(() => _isChangingPassword = true);
                        try {
                          final response = await http.post(
                            Uri.parse('$API_URL/user/change_password'),
                            headers: {
                              'Authorization': 'Bearer ${widget.token}',
                              'Content-Type': 'application/json',
                            },
                            body: jsonEncode({
                              'current_password': current,
                              'new_password': newPass,
                              'confirm_password': confirm,
                            }),
                          );

                          if (response.statusCode == 200) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Password changed. Please login again.',
                                  ),
                                ),
                              );
                            }
                            if (context.mounted) {
                              Navigator.pop(context);
                            }
                          } else {
                            String message = 'Failed to change password.';
                            try {
                              final data = jsonDecode(response.body);
                              message = data['detail'] ?? message;
                            } catch (_) {}
                            setDialogState(() {
                              errorText = message;
                            });
                          }
                        } catch (e) {
                          setDialogState(() {
                            errorText = 'Error: $e';
                          });
                        } finally {
                          if (mounted) {
                            setState(() => _isChangingPassword = false);
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isChangingPassword
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text('Update Password'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showChangeProfilePasswordDialog() async {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool isChanging = false;

    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        String? errorText;

        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1E1E22) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.admin_panel_settings_rounded, color: Colors.orange, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Change Profile Password',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: MediaQuery.of(context).size.width > 480
                  ? 400
                  : MediaQuery.of(context).size.width * 0.9,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildDialogTextField(
                      label: 'Current Profile Password',
                      controller: currentCtrl,
                      icon: Icons.lock_outline_rounded,
                      isDark: isDark,
                      accentColor: Colors.orange,
                    ),
                    const SizedBox(height: 14),
                    _buildDialogTextField(
                      label: 'New Profile Password',
                      controller: newCtrl,
                      icon: Icons.lock_rounded,
                      isDark: isDark,
                      accentColor: Colors.orange,
                    ),
                    const SizedBox(height: 14),
                    _buildDialogTextField(
                      label: 'Confirm New Profile Password',
                      controller: confirmCtrl,
                      icon: Icons.check_circle_outline_rounded,
                      isDark: isDark,
                      accentColor: Colors.orange,
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.withOpacity(0.3)),
                        ),
                        child: Text(
                          errorText!,
                          style: const TextStyle(color: Colors.red, fontSize: 13),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isChanging
                    ? null
                    : () => Navigator.pop(context),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: isDark ? Colors.white70 : Colors.grey[700]),
                ),
              ),
              ElevatedButton(
                onPressed: isChanging
                    ? null
                    : () async {
                        final current = currentCtrl.text.trim();
                        final newPass = newCtrl.text.trim();
                        final confirm = confirmCtrl.text.trim();

                        if (current.isEmpty ||
                            newPass.isEmpty ||
                            confirm.isEmpty) {
                          setDialogState(() {
                            errorText = 'All fields are required.';
                          });
                          return;
                        }
                        if (newPass.length < 6) {
                          setDialogState(() {
                            errorText = 'New password must be at least 6 characters.';
                          });
                          return;
                        }
                        if (newPass != confirm) {
                          setDialogState(() {
                            errorText = 'New passwords do not match.';
                          });
                          return;
                        }
                        if (current == newPass) {
                          setDialogState(() {
                            errorText = 'New password must be different.';
                          });
                          return;
                        }

                        setDialogState(() => isChanging = true);
                        try {
                          final response = await http.post(
                            Uri.parse('${CollegeIPConfig.defaultURL}/admin/change_profile_password'),
                            headers: {
                              'Authorization': 'Bearer ${widget.token}',
                              'Content-Type': 'application/json',
                            },
                            body: jsonEncode({
                              'current_password': current,
                              'new_password': newPass,
                            }),
                          );

                          if (response.statusCode == 200) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Profile password updated successfully.',
                                  ),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                            if (context.mounted) {
                              Navigator.pop(context);
                            }
                          } else {
                            String message = 'Failed to change profile password.';
                            try {
                              final data = jsonDecode(response.body);
                              message = data['detail'] ?? message;
                            } catch (_) {}
                            setDialogState(() {
                              errorText = message;
                            });
                          }
                        } catch (e) {
                          setDialogState(() {
                            errorText = 'Error: $e';
                          });
                        } finally {
                          setDialogState(() => isChanging = false);
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: isChanging
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text('Update Profile Password'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDialogTextField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required bool isDark,
    required Color accentColor,
  }) {
    return TextField(
      controller: controller,
      obscureText: true,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: isDark ? Colors.white60 : Colors.grey[600],
        ),
        prefixIcon: Icon(icon, color: accentColor, size: 20),
        filled: true,
        fillColor: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.grey.withValues(alpha: 0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.grey.shade200,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: accentColor, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 16,
          horizontal: 16,
        ),
      ),
      style: TextStyle(
        color: isDark ? Colors.white : Colors.black87,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListenableBuilder(
      listenable: themeService,
      builder: (context, _) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final iOSBlue = const Color(0xFF007AFF);
        final screenWidth = MediaQuery.sizeOf(context).width;
        final isCompact = screenWidth < 360;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  GestureDetector(
                    onLongPress: () {
                      setState(() {
                        _showProfilePasswordOption = true;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Profile password options enabled!'),
                          backgroundColor: Colors.blue,
                        ),
                      );
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: iOSBlue.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.admin_panel_settings_rounded,
                        color: iOSBlue,
                        size: 24,
                      ),
                    ),
                  ),
                  Text(
                    'Attendance Settings',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: iOSBlue,
                      letterSpacing: 0.2,
                    ),
                  ),
                  if (_isSaving) ...[
                    const SizedBox(width: 12),
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 20),

              // Network Settings Card
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Colors.deepPurple, Colors.indigo],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.deepPurple.withValues(alpha: 0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.wifi_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Attendance Marking Criteria',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.grey[800],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _ssidRequiredForAttendance
                                    ? 'Staff must be on fixed College Wifi to mark attendance'
                                    : 'Staff can mark attendance from any network',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: _ssidRequiredForAttendance
                                      ? Colors.orange[700]
                                      : Colors.green,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Divider(color: isDark ? Colors.white12 : Colors.grey[200]),
                    const SizedBox(height: 16),

                    // Wi-Fi Toggle Switch
                    _buildSleekToggleRow(
                      title: 'Require College Wifi',
                      subtitle: _ssidRequiredForAttendance ? 'ON' : 'OFF',
                      value: _ssidRequiredForAttendance,
                      isDark: isDark,
                      onChanged: _isSaving
                          ? null
                          : (value) {
                              final prevVal = _allowAnyNetwork;
                              setState(() {
                                _allowAnyNetwork = !value;
                              });
                              _saveSettings(
                                title: 'Require College Wifi',
                                onConfirmedStateChange: () {},
                                onCancelledStateChange: () {
                                  setState(() {
                                    _allowAnyNetwork = prevVal;
                                  });
                                },
                                successMsg: value
                                    ? 'College Wi-Fi requirement enabled.'
                                    : 'College Wi-Fi requirement disabled.',
                              );
                            },
                    ),

                    const SizedBox(height: 16),
                    Divider(color: isDark ? Colors.white12 : Colors.grey[200]),
                    const SizedBox(height: 16),

                    // Geo-fence Toggle (Web Only)
                    _buildSleekToggleRow(
                      title: 'Require Geo-fence (Web)',
                      subtitle: _enforceGeoFence ? 'ON' : 'OFF',
                      value: _enforceGeoFence,
                      isDark: isDark,
                      onChanged: _isSaving
                          ? null
                          : (value) {
                              final prevVal = _enforceGeoFence;
                              setState(() {
                                _enforceGeoFence = value;
                              });
                              _saveSettings(
                                title: 'Require Geo-fence (Web)',
                                onConfirmedStateChange: () {},
                                onCancelledStateChange: () {
                                  setState(() {
                                    _enforceGeoFence = prevVal;
                                  });
                                },
                                successMsg: value
                                    ? 'Web geo-fence enforcement enabled.'
                                    : 'Web geo-fence enforcement disabled.',
                              );
                            },
                    ),

                    const SizedBox(height: 16),
                    Divider(color: isDark ? Colors.white12 : Colors.grey[200]),
                    const SizedBox(height: 16),

                    // Geo-fence Toggle (App Only)
                    _buildSleekToggleRow(
                      title: 'Require Geo-fence (App)',
                      subtitle: _enforceAppGeoFence ? 'ON' : 'OFF',
                      value: _enforceAppGeoFence,
                      isDark: isDark,
                      onChanged: _isSaving
                          ? null
                          : (value) {
                              final prevVal = _enforceAppGeoFence;
                              setState(() {
                                _enforceAppGeoFence = value;
                              });
                              _saveSettings(
                                title: 'Require Geo-fence (App)',
                                onConfirmedStateChange: () {},
                                onCancelledStateChange: () {
                                  setState(() {
                                    _enforceAppGeoFence = prevVal;
                                  });
                                },
                                successMsg: value
                                    ? 'App geo-fence enforcement enabled.'
                                    : 'App geo-fence enforcement disabled.',
                              );
                            },
                    ),

                    const SizedBox(height: 16),
                    Divider(color: isDark ? Colors.white12 : Colors.grey[200]),
                    const SizedBox(height: 16),

                    // VPN Blocking Toggle
                    _buildSleekToggleRow(
                      title: 'Block VPN Connections',
                      subtitle: _enforceVpnBlocking ? 'ON' : 'OFF',
                      value: _enforceVpnBlocking,
                      isDark: isDark,
                      onChanged: _isSaving
                          ? null
                          : (value) {
                              final prevVal = _enforceVpnBlocking;
                              setState(() {
                                _enforceVpnBlocking = value;
                              });
                              _saveSettings(
                                title: 'Block VPN Connections',
                                onConfirmedStateChange: () {},
                                onCancelledStateChange: () {
                                  setState(() {
                                    _enforceVpnBlocking = prevVal;
                                  });
                                },
                                successMsg: value
                                    ? 'VPN blocking enabled.'
                                    : 'VPN blocking disabled.',
                              );
                            },
                    ),
                    const SizedBox(height: 16),
                    // Multi-User Kiosk Mode Toggle
                    _buildSleekToggleRow(
                      title: 'Multi-User Kiosk Mode',
                      subtitle: _multiUserKioskMode ? 'ON' : 'OFF',
                      value: _multiUserKioskMode,
                      isDark: isDark,
                      onChanged: _isSaving
                          ? null
                          : (value) {
                              final prevVal = _multiUserKioskMode;
                              setState(() {
                                _multiUserKioskMode = value;
                              });
                              _saveSettings(
                                title: 'Multi-User Kiosk Mode',
                                onConfirmedStateChange: () {},
                                onCancelledStateChange: () {
                                  setState(() {
                                    _multiUserKioskMode = prevVal;
                                  });
                                },
                                successMsg: value
                                    ? 'Multi-User Kiosk Mode enabled.'
                                    : 'Multi-User Kiosk Mode disabled.',
                              );
                            },
                    ),
                    const SizedBox(height: 16),
                    Divider(color: isDark ? Colors.white12 : Colors.grey[200]),
                    const SizedBox(height: 16),

                    // Thirukkural Banner Toggle
                    _buildSleekToggleRow(
                      title: 'Enable Thirukkural Daily Banner',
                      subtitle: _enableThirukkural ? 'ON' : 'OFF',
                      value: _enableThirukkural,
                      isDark: isDark,
                      onChanged: _isSaving
                          ? null
                          : (value) {
                              final prevVal = _enableThirukkural;
                              setState(() {
                                _enableThirukkural = value;
                              });
                              _saveSettings(
                                title: 'Enable Thirukkural Daily Banner',
                                onConfirmedStateChange: () {},
                                onCancelledStateChange: () {
                                  setState(() {
                                    _enableThirukkural = prevVal;
                                  });
                                },
                                successMsg: value
                                    ? 'Thirukkural banner enabled.'
                                    : 'Thirukkural banner disabled.',
                              );
                            },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Geo Fence Editor Button
              GlassCard(
                child: InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            GeoFenceEditor(token: widget.token),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Colors.blue, Colors.lightBlue],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blue.withValues(alpha: 0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.map_rounded, color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Edit Geo Fence Coordinates',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.grey[800],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Configure the geographical boundaries for attendance marking',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.white60 : Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: isDark ? Colors.white38 : Colors.grey[400],
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Attendance Duration Section
              Text(
                'Attendance Duration',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 16),

              // Duration Settings Button
              GlassCard(
                child: InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            AttendanceDurationSettings(token: widget.token),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Colors.teal, Colors.greenAccent],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.teal.withValues(alpha: 0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.timer_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Duration Settings',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.grey[800],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Configure when staff can mark attendance',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.white60 : Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: isDark ? Colors.white38 : Colors.grey[400],
                        size: 24,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Security Section Header
              Text(
                'Security',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: iOSBlue,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 16),

              ModernGlassCard(
                accentColor: iOSBlue,
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    ModernSettingTile(
                      icon: Icons.lock_rounded,
                      iconColor: iOSBlue,
                      title: 'Change Password',
                      subtitle: 'Update your admin password',
                      onTap: _showChangePasswordDialog,
                    ),
                    if (_showProfilePasswordOption) ...[
                      Divider(color: isDark ? Colors.white12 : Colors.grey[200]),
                      ModernSettingTile(
                        icon: Icons.admin_panel_settings_rounded,
                        iconColor: Colors.orange,
                        title: 'Change Profile Password',
                        subtitle: 'Update settings profile password',
                        onTap: _showChangeProfilePasswordDialog,
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Institutional Operations & Advanced Modules Section Header
              Text(
                'Institutional Modules & Operations',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: iOSBlue,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 16),

              ModernGlassCard(
                accentColor: iOSBlue,
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    ModernSettingTile(
                      icon: Icons.edit_calendar_rounded,
                      iconColor: Colors.blue,
                      title: 'Attendance Regularisation & Disputes',
                      subtitle: 'Review dispute tickets and adjust submission windows',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (ctx) => AttendanceCorrectionsPage(
                              token: widget.token,
                              user: const {'role': 'admin', 'name': 'Administrator'},
                              isAdminOrHod: true,
                            ),
                          ),
                        );
                      },
                    ),
                    Divider(color: isDark ? Colors.white12 : Colors.grey[200]),
                    ModernSettingTile(
                      icon: Icons.analytics_rounded,
                      iconColor: Colors.indigo,
                      title: 'Advanced Reports & Export Suite',
                      subtitle: 'Daily register, heatmap, leave utilisation, and PDF/Excel export',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (ctx) => SystemReportsPage(
                              token: widget.token,
                              user: const {'role': 'admin', 'name': 'Administrator'},
                            ),
                          ),
                        );
                      },
                    ),
                    Divider(color: isDark ? Colors.white12 : Colors.grey[200]),
                    ModernSettingTile(
                      icon: Icons.security_rounded,
                      iconColor: Colors.redAccent,
                      title: 'Security, Sessions & 2FA Hub',
                      subtitle: 'Active device sessions, audit logs, and two-factor auth',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (ctx) => SecurityHubPage(
                              token: widget.token,
                              user: const {'role': 'admin', 'name': 'Administrator'},
                            ),
                          ),
                        );
                      },
                    ),
                    Divider(color: isDark ? Colors.white12 : Colors.grey[200]),
                    ModernSettingTile(
                      icon: Icons.celebration_rounded,
                      iconColor: Colors.purple,
                      title: 'Academic Holiday Calendar',
                      subtitle: 'Manage national, state, and college holiday schedules',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (ctx) => HolidayCalendarPage(
                              token: widget.token,
                              isAdmin: true,
                            ),
                          ),
                        );
                      },
                    ),
                    Divider(color: isDark ? Colors.white12 : Colors.grey[200]),
                    ModernSettingTile(
                      icon: Icons.mark_chat_unread_rounded,
                      iconColor: Colors.teal,
                      title: 'Student Grievances & Feedback',
                      subtitle: 'Track and resolve student academic and campus tickets',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (ctx) => StudentGrievancePage(
                              token: widget.token,
                              user: const {'role': 'admin', 'name': 'Administrator'},
                              isAdmin: true,
                            ),
                          ),
                        );
                      },
                    ),
                    Divider(color: isDark ? Colors.white12 : Colors.grey[200]),
                    ModernSettingTile(
                      icon: Icons.swap_horiz_rounded,
                      iconColor: Colors.amber.shade800,
                      title: 'Timetable & Substitute Faculty',
                      subtitle: 'Schedule lecture substitutions and avoid period clashes',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (ctx) => SubstituteManagementPage(
                              token: widget.token,
                              user: const {'role': 'admin', 'name': 'Administrator'},
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Appearance Section Header
              Text(
                'Appearance',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: iOSBlue,
                  letterSpacing: 0.2,
                ),
              ),

              const SizedBox(height: 16),

              ModernGlassCard(
                accentColor: iOSBlue,
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    ModernSettingTile(
                      icon: themeService.isSystemMode
                          ? Icons.settings_suggest_rounded
                          : (isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded),
                      iconColor: iOSBlue,
                      title: 'Theme',
                      subtitle: themeService.isSystemMode
                          ? 'Following system theme'
                          : (isDark ? 'Dark theme' : 'Light theme'),
                      trailing: AnimatedRotation(
                        turns: _isThemeExpanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: isDark ? Colors.white60 : Colors.grey[400],
                          size: 26,
                        ),
                      ),
                      onTap: () {
                        setState(() {
                          _isThemeExpanded = !_isThemeExpanded;
                        });
                      },
                    ),
                    AnimatedCrossFade(
                      firstChild: const SizedBox.shrink(),
                      secondChild: _buildInlineThemeSelector(isDark, isCompact),
                      crossFadeState: _isThemeExpanded
                          ? CrossFadeState.showSecond
                          : CrossFadeState.showFirst,
                      duration: const Duration(milliseconds: 200),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const ThirukkuralBanner(),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSleekToggleRow({
    required String title,
    required String subtitle,
    required bool value,
    required bool isDark,
    required ValueChanged<bool>? onChanged,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.grey[800],
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: value
                      ? Colors.green.withValues(alpha: 0.1)
                      : Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: value
                        ? Colors.green.withValues(alpha: 0.25)
                        : Colors.orange.withValues(alpha: 0.25),
                  ),
                ),
                child: Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: value ? Colors.green : Colors.orange[700],
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        Transform.scale(
          scale: 1.0,
          child: Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.green,
            activeTrackColor: Colors.green.withValues(alpha: 0.3),
            inactiveThumbColor: Colors.grey[400],
            inactiveTrackColor: Colors.grey[200],
          ),
        ),
      ],
    );
  }

  Widget _buildInlineThemeSelector(bool isDark, bool isCompact) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ThreeOptionToggle<ThemeMode>(
            options: const [
              ThreeToggleOption(
                value: ThemeMode.light,
                label: 'Light',
                icon: Icons.light_mode_rounded,
              ),
              ThreeToggleOption(
                value: ThemeMode.dark,
                label: 'Dark',
                icon: Icons.dark_mode_rounded,
              ),
              ThreeToggleOption(
                value: ThemeMode.system,
                label: 'System',
                icon: Icons.settings_suggest_rounded,
              ),
            ],
            selectedValue: themeService.themeMode,
            onChanged: themeService.setThemeMode,
            isDark: isDark,
            showLabels: !isCompact,
          ),
        ],
      ),
    );
  }
}

class ModernGlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final VoidCallback? onTap;
  final Color? accentColor;

  const ModernGlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = 20.0,
    this.onTap,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = accentColor ?? const Color(0xFF007AFF);

    return Container(
      margin: margin ?? const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: accent.withValues(alpha: isDark ? 0.08 : 0.03),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(borderRadius),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(borderRadius),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                padding: padding ?? const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isDark
                        ? [
                            Colors.white.withValues(alpha: 0.10),
                            Colors.white.withValues(alpha: 0.03),
                            Colors.white.withValues(alpha: 0.01),
                          ]
                        : [
                            Colors.white.withValues(alpha: 0.70),
                            Colors.white.withValues(alpha: 0.35),
                            Colors.white.withValues(alpha: 0.15),
                          ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                  borderRadius: BorderRadius.circular(borderRadius),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.15)
                        : Colors.white.withValues(alpha: 0.7),
                    width: 1.5,
                  ),
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ModernSettingTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback onTap;

  const ModernSettingTile({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    iconColor,
                    iconColor.withValues(alpha: 0.7),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: iconColor.withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white60 : Colors.grey[600],
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            trailing ?? Icon(
              Icons.chevron_right_rounded,
              color: isDark ? Colors.white38 : Colors.grey[400],
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}

// End of admin panel
