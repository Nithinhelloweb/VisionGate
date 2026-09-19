import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:camera/camera.dart';
import '../config/college_ip_config.dart';
import '../utils/file_saver.dart';
import '../services/client_face_prefilter.dart';

String get apiBaseUrl => CollegeIPConfig.defaultURL;

/// Hallmark Anti-AI-Slop Compliant Class Session Attendance Recording Studio & Roll Sheet
/// Features:
/// - 100% Roman upright typography (font-style: normal)
/// - Locked semantic color tokens (primaryBlue, emeraldGreen, roseError, amberWarning, indigoAccent)
/// - Complete 8-State interactive design coverage
/// - Integrated Live Camera Face Scanner with real-time recognition
/// - Full Cohort Roster tracking with 1-Tap status toggle and auto absentee reconciliation
class ClassSessionRollSheet extends StatefulWidget {
  final String token;
  final String sessionId;
  final String subjectName;
  final String classSummary;
  final bool canOverride;
  final Map<String, dynamic>? allocation;

  const ClassSessionRollSheet({
    super.key,
    required this.token,
    required this.sessionId,
    required this.subjectName,
    required this.classSummary,
    this.canOverride = true,
    this.allocation,
  });

  static Future<void> show(
    BuildContext context, {
    required String token,
    required String sessionId,
    required String subjectName,
    required String classSummary,
    bool canOverride = true,
    Map<String, dynamic>? allocation,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ClassSessionRollSheet(
        token: token,
        sessionId: sessionId,
        subjectName: subjectName,
        classSummary: classSummary,
        canOverride: canOverride,
        allocation: allocation,
      ),
    );
  }

  @override
  State<ClassSessionRollSheet> createState() => _ClassSessionRollSheetState();
}

class _ClassSessionRollSheetState extends State<ClassSessionRollSheet>
    with SingleTickerProviderStateMixin {
  // Locked Semantic Tokens
  static const Color primaryBlue = Color(0xFF2563EB);
  static const Color emeraldGreen = Color(0xFF059669);
  static const Color roseError = Color(0xFFDC2626);
  static const Color amberWarning = Color(0xFFD97706);
  static const Color indigoAccent = Color(0xFF4F46E5);

  late String _activeSessionId;
  bool _isLoading = true;
  String? _error;

  // Session Data & Meta
  Map<String, dynamic> _meta = {};
  List<Map<String, dynamic>> _roll = [];
  int _totalStudents = 0;
  int _presentCount = 0;
  int _absentCount = 0;
  int _pendingCount = 0;
  int _odCount = 0;
  int _checkedOutCount = 0;

  // Filter & Search
  String _filterStatus = 'ALL';
  final TextEditingController _searchCtrl = TextEditingController();

  // Camera & Face Scanner State
  bool _isCameraOpen = false;
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isCameraReady = false;
  bool _isCameraInitializing = false;
  bool _isScanningFace = false;
  String _scanStatusMessage = '';
  Timer? _autoScanTimer;
  late AnimationController _scannerAnimController;

  // Session Timer
  Timer? _sessionDurationTimer;
  Timer? _periodicStatusCheckTimer;
  int _sessionElapsedSeconds = 0;

  // Real-Time WebSocket Channel
  io.WebSocket? _wsClient;
  StreamSubscription? _wsSubscription;

  Map<String, String> get _headers => {
        'Authorization': widget.token.startsWith('Bearer ')
            ? widget.token
            : 'Bearer ${widget.token}',
        'Content-Type': 'application/json',
      };

  @override
  void initState() {
    super.initState();
    _activeSessionId = widget.sessionId;
    _scannerAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _loadRoll();
    _initWebSocket();

    _sessionDurationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _isRecordingActive) {
        setState(() => _sessionElapsedSeconds++);
      }
    });

    // Check every 15s if session was automatically closed after 10-min post-period grace
    _periodicStatusCheckTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && _isRecordingActive) {
        _loadRoll(silent: true);
      }
    });
  }

  void _initWebSocket() {
    if (kIsWeb) return;
    try {
      final base = apiBaseUrl.trim();
      final wsBase = base.startsWith('https://')
          ? base.replaceFirst('https://', 'wss://')
          : base.replaceFirst('http://', 'ws://');
      final uri = Uri.parse('$wsBase/ws/class-session/$_activeSessionId');

      io.WebSocket.connect(uri.toString()).then((socket) {
        if (!mounted) {
          socket.close();
          return;
        }
        _wsClient = socket;
        _wsSubscription = socket.listen((data) {
          try {
            if (data is String) {
              final payload = json.decode(data);
              if (payload is Map<String, dynamic>) {
                final event = payload['event'];
                if (event == 'student_checked_in' && mounted) {
                  final stuReg = (payload['student_reg_no'] ?? '').toString();
                  _onStudentCheckedInRealtime(stuReg);
                } else if (event == 'student_checked_out' && mounted) {
                  final stuReg = (payload['student_reg_no'] ?? '').toString();
                  final coTime = (payload['checkout_time'] ?? '').toString();
                  _onStudentCheckedOutRealtime(stuReg, coTime);
                } else if (event == 'session_closed' && mounted) {
                  _loadRoll(silent: true);
                }
              }
            }
          } catch (_) {}
        }, onError: (_) {}, onDone: () {});
      }).catchError((_) {});
    } catch (_) {}
  }

  void _onStudentCheckedInRealtime(String stuReg) {
    if (stuReg.isEmpty) return;
    bool found = false;
    for (int i = 0; i < _roll.length; i++) {
      if ((_roll[i]['reg_no'] ?? '').toString().toLowerCase() == stuReg.toLowerCase()) {
        if (_roll[i]['status'] != 'Present') {
          _roll[i]['status'] = 'Present';
          _roll[i]['marked_by'] = 'Live Check-In';
          found = true;
        }
        break;
      }
    }
    if (found && mounted) {
      _recalculateRollCounts();
    }
  }

  void _onStudentCheckedOutRealtime(String stuReg, String checkoutTime) {
    if (stuReg.isEmpty) return;
    bool found = false;
    for (int i = 0; i < _roll.length; i++) {
      if ((_roll[i]['reg_no'] ?? '').toString().toLowerCase() == stuReg.toLowerCase()) {
        _roll[i]['checkout_time'] = checkoutTime.isNotEmpty ? checkoutTime : DateTime.now().toIso8601String();
        if (_roll[i]['status'] != 'Present') {
          _roll[i]['status'] = 'Present';
        }
        found = true;
        break;
      }
    }
    if (found && mounted) {
      _recalculateRollCounts();
    }
  }

  void _recalculateRollCounts() {
    int p = 0;
    int a = 0;
    int pend = 0;
    int od = 0;
    int co = 0;
    for (final r in _roll) {
      final st = (r['status'] ?? 'Pending').toString();
      if (st == 'Present') {
        p++;
      } else if (st == 'Absent') {
        a++;
      } else if (st == 'On-Duty') {
        od++;
      } else {
        pend++;
      }
      if (r['checkout_time'] != null && r['checkout_time'].toString().trim().isNotEmpty) {
        co++;
      }
    }
    setState(() {
      _presentCount = p;
      _absentCount = a;
      _pendingCount = pend;
      _odCount = od;
      _checkedOutCount = co;
    });
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    _wsClient?.close();
    _sessionDurationTimer?.cancel();
    _periodicStatusCheckTimer?.cancel();
    _autoScanTimer?.cancel();
    _scannerAnimController.dispose();
    _cameraController?.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  bool get _isRecordingActive {
    final status = (_meta['status'] ?? 'checkin_open').toString();
    return status == 'checkin_open' || status == 'checkout_open';
  }

  bool get _isSessionClosed {
    final status = (_meta['status'] ?? '').toString();
    return status == 'closed';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DATA ACTIONS
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _loadRoll({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    try {
      final res = await http
          .get(
            Uri.parse('$apiBaseUrl/api/v1/class-session/session-roll?session_id=$_activeSessionId'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final List<dynamic> rawRoll = data['roll'] ?? [];
        final rollList = rawRoll.map((r) => Map<String, dynamic>.from(r)).toList();

        if (mounted) {
          final wasRecording = _isRecordingActive;
          final Map<String, dynamic> newMeta = data['meta'] is Map
              ? (data['meta'] as Map).map((k, v) => MapEntry(k.toString(), v))
              : <String, dynamic>{};
          final newStatus = (newMeta['status'] ?? '').toString();

          setState(() {
            _roll = rollList;
            _meta = newMeta;
            _totalStudents = data['total_students'] ?? rollList.length;
            _presentCount = data['present_count'] ?? 0;
            _absentCount = data['absent_count'] ?? 0;
            _pendingCount = data['pending_count'] ?? 0;
            _odCount = data['od_count'] ?? 0;
            _checkedOutCount = data['checked_out_count'] ??
                rollList.where((r) => r['checkout_time'] != null && r['checkout_time'].toString().trim().isNotEmpty).length;
            _isLoading = false;
          });

          if (wasRecording && newStatus == 'closed') {
            _stopCamera();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('🔒 Class session automatically closed (10 minutes after period ended). Attendance finalized.'),
                backgroundColor: Color(0xFF0F172A),
                duration: Duration(seconds: 5),
              ),
            );
          }
        }
      } else {
        if (mounted && !silent) {
          setState(() {
            _error = 'Failed to load session roll (${res.statusCode})';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _startCheckout() async {
    setState(() => _isLoading = true);
    try {
      final res = await http.post(
        Uri.parse('$apiBaseUrl/api/v1/class-session/start-checkout'),
        headers: _headers,
        body: json.encode({'session_id': _activeSessionId}),
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Check-Out window is now OPEN for students!'),
              backgroundColor: Color(0xFF0D9488),
            ),
          );
        }
        await _loadRoll();
      } else {
        final err = json.decode(res.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(err['detail'] ?? 'Failed to start check-out'), backgroundColor: roseError),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Check-Out Error: $e'), backgroundColor: roseError),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _startRecording() async {
    setState(() => _isLoading = true);
    try {
      final alloc = widget.allocation;
      final res = await http.post(
        Uri.parse('$apiBaseUrl/api/v1/class-session/quick-start'),
        headers: _headers,
        body: json.encode({
          'dept': _meta['dept'] ?? alloc?['dept'] ?? '',
          'batch': _meta['batch'] ?? alloc?['batch'] ?? '',
          'semester': _meta['semester'] ?? alloc?['semester'] ?? 1,
          'section': _meta['section'] ?? alloc?['section'] ?? 'A',
          'subject_code': _meta['subject_code'] ?? alloc?['subject_code'] ?? '',
          'subject_name': _meta['subject_name'] ?? alloc?['subject_name'] ?? widget.subjectName,
          'period_number': 1,
        }),
      );

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        _activeSessionId = data['session_id'] ?? _activeSessionId;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Attendance Recording Started! Student check-in & camera scanning enabled.'),
              backgroundColor: emeraldGreen,
            ),
          );
        }
        await _loadRoll();
      } else {
        final err = json.decode(res.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(err['detail'] ?? 'Failed to start recording'), backgroundColor: roseError),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Start Error: $e'), backgroundColor: roseError),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _stopRecordingAndFinalize() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Finalize Class Attendance',
          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Are you sure you want to stop recording and close this session?\n\n'
          '• Present students: $_presentCount\n'
          '• Unrecorded students: $_pendingCount (will be marked Absent)\n'
          '• Approved OD/Leaves: $_odCount\n\n'
          'This will reconcile and lock the official register.',
          style: const TextStyle(fontFamily: 'Inter', fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Continue Recording'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: roseError,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.stop_rounded, size: 18),
            label: const Text('Stop & Finalize'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      final res = await http.post(
        Uri.parse('$apiBaseUrl/api/v1/class-session/close-session'),
        headers: _headers,
        body: json.encode({'session_id': _activeSessionId}),
      );

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (_isCameraOpen) _stopCamera();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '✅ Session Closed! ${data['present_count']} Present, ${data['absent_count']} Absent reconciled.',
              ),
              backgroundColor: emeraldGreen,
            ),
          );
        }
        await _loadRoll();
      } else {
        final err = json.decode(res.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(err['detail'] ?? 'Failed to finalize session'), backgroundColor: roseError),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Close Error: $e'), backgroundColor: roseError),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _setStudentStatus(String regNo, String targetStatus, {String? reason}) async {
    try {
      final res = await http.post(
        Uri.parse('$apiBaseUrl/api/v1/class-session/manual-override'),
        headers: _headers,
        body: json.encode({
          'session_id': _activeSessionId,
          'student_reg_no': regNo,
          'new_status': targetStatus,
          'reason': reason ?? 'Faculty 1-Tap Toggle',
        }),
      );

      if (res.statusCode == 200) {
        await _loadRoll(silent: true);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Update failed (${res.statusCode})'), backgroundColor: roseError),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: roseError),
        );
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LIVE CAMERA FACE SCANNER
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _toggleCameraScanner() async {
    if (_isCameraOpen) {
      await _stopCamera();
    } else {
      await _startCamera();
    }
  }

  Future<void> _startCamera() async {
    setState(() {
      _isCameraOpen = true;
      _isCameraInitializing = true;
      _scanStatusMessage = 'Initializing camera scanner...';
    });

    try {
      if (_cameras.isEmpty) {
        _cameras = await availableCameras().timeout(
          const Duration(seconds: 3),
          onTimeout: () => [],
        );
      }

      if (_cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _isCameraInitializing = false;
            _scanStatusMessage = '❌ No camera device detected.';
          });
        }
        return;
      }

      final frontCam = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras.first,
      );

      final ctrl = CameraController(
        frontCam,
        ResolutionPreset.medium,
        imageFormatGroup: kIsWeb ? null : ImageFormatGroup.jpeg,
        enableAudio: false,
      );

      await ctrl.initialize();

      if (mounted) {
        setState(() {
          _cameraController = ctrl;
          _isCameraReady = true;
          _isCameraInitializing = false;
          _scanStatusMessage = 'Ready. Position student face in center oval.';
        });

        // Start auto-capture every 1.8 seconds while camera is open
        _autoScanTimer?.cancel();
        _autoScanTimer = Timer.periodic(const Duration(milliseconds: 1800), (_) {
          if (mounted && _isCameraOpen && _isCameraReady && !_isScanningFace && _isRecordingActive) {
            _captureAndScanFace();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCameraInitializing = false;
          _isCameraReady = false;
          _scanStatusMessage = '❌ Camera Error: $e';
        });
      }
    }
  }

  Future<void> _stopCamera() async {
    _autoScanTimer?.cancel();
    _autoScanTimer = null;
    await _cameraController?.dispose();
    _cameraController = null;
    if (mounted) {
      setState(() {
        _isCameraOpen = false;
        _isCameraReady = false;
        _isCameraInitializing = false;
      });
    }
  }

  Future<void> _captureAndScanFace() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized || _isScanningFace) {
      return;
    }

    setState(() {
      _isScanningFace = true;
      _scanStatusMessage = 'Scanning face...';
    });

    try {
      final xfile = await _cameraController!.takePicture();

      // On-device Google ML Kit edge pre-filter (fast mobile check)
      final prefilter = await ClientFacePreFilterService.evaluateImagePath(xfile.path);
      if (!prefilter.isValid) {
        if (mounted) {
          setState(() {
            _scanStatusMessage = prefilter.message ?? 'Align face inside center oval.';
            _isScanningFace = false;
          });
        }
        return;
      }

      final bytes = await xfile.readAsBytes();
      final b64 = await compute(base64Encode, bytes);

      final res = await http.post(
        Uri.parse('$apiBaseUrl/api/v1/class-session/scan-face'),
        headers: _headers,
        body: json.encode({
          'session_id': _activeSessionId,
          'image_base64': b64,
        }),
      );

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data['matched'] == true) {
          final stu = data['student'];
          if (mounted) {
            setState(() {
              _scanStatusMessage = '✅ Marked Present: ${stu['name']} (${stu['reg_no']})';
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Text('Marked Present: ${stu['name']} (${stu['reg_no']})',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
                backgroundColor: emeraldGreen,
                duration: const Duration(seconds: 2),
              ),
            );
          }
          await _loadRoll(silent: true);
        } else {
          if (mounted) {
            setState(() {
              _scanStatusMessage = data['detail'] ?? 'Face not recognized in this class roster.';
            });
          }
        }
      } else {
        final err = json.decode(res.body);
        if (mounted) {
          setState(() {
            _scanStatusMessage = err['detail'] ?? 'Face scan verification failed.';
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _scanStatusMessage = 'Scanner ready.');
    } finally {
      if (mounted) setState(() => _isScanningFace = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CSV EXPORT
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _exportCSV() async {
    final buffer = StringBuffer();
    buffer.writeln('SIET ATTENDANCE SYSTEM - CLASS SESSION ROLL REPORT');
    buffer.writeln('Subject,${widget.subjectName}');
    buffer.writeln('Class,${widget.classSummary}');
    buffer.writeln('Session ID,$_activeSessionId');
    buffer.writeln('Date,${_meta['date'] ?? DateTime.now().toString().split(' ')[0]}');
    buffer.writeln('Status,${_meta['status'] ?? 'Closed'}');
    buffer.writeln('Total Students,$_totalStudents');
    buffer.writeln('Present,$_presentCount');
    buffer.writeln('Checked Out,$_checkedOutCount');
    buffer.writeln('Absent,$_absentCount');
    buffer.writeln('On-Duty,$_odCount');
    buffer.writeln('');
    buffer.writeln('S.No,Roll No,Register No,Student Name,Status,Check-In Time,Check-Out Time,Marked By');

    for (int i = 0; i < _roll.length; i++) {
      final r = _roll[i];
      buffer.writeln(
        '${i + 1},"${r['roll_no'] ?? ''}","${r['reg_no']}","${r['name']}","${r['status']}","${r['checkin_time'] ?? '—'}","${r['checkout_time'] ?? '—'}","${r['marked_by'] ?? ''}"',
      );
    }

    final bytes = Uint8List.fromList(utf8.encode(buffer.toString()));
    final filename = 'Attendance_${_meta['dept'] ?? 'Class'}_${_meta['subject_code'] ?? 'Session'}_${DateTime.now().millisecondsSinceEpoch}.csv';
    await saveFile(bytes, filename);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ Attendance report exported: $filename'), backgroundColor: emeraldGreen),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FILTERED ROSTER
  // ─────────────────────────────────────────────────────────────────────────

  List<Map<String, dynamic>> get _filteredRoll {
    final q = _searchCtrl.text.toLowerCase().trim();
    return _roll.where((r) {
      final matchSearch = q.isEmpty ||
          (r['name'] ?? '').toString().toLowerCase().contains(q) ||
          (r['reg_no'] ?? '').toString().toLowerCase().contains(q) ||
          (r['roll_no'] ?? '').toString().toLowerCase().contains(q);

      final status = (r['status'] ?? 'Pending').toString();
      final hasCheckout = r['checkout_time'] != null && r['checkout_time'].toString().trim().isNotEmpty;

      bool matchFilter = true;
      if (_filterStatus == 'PRESENT') matchFilter = status == 'Present';
      if (_filterStatus == 'CHECKED_OUT') matchFilter = hasCheckout;
      if (_filterStatus == 'IN_ONLY') matchFilter = status == 'Present' && !hasCheckout;
      if (_filterStatus == 'ABSENT') matchFilter = status == 'Absent';
      if (_filterStatus == 'PENDING') matchFilter = status == 'Pending';
      if (_filterStatus == 'ON-DUTY') matchFilter = status == 'On-Duty' || status == 'Leave';

      return matchSearch && matchFilter;
    }).toList();
  }

  String _fmtTime(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso.length > 16 ? iso.substring(11, 16) : iso;
    }
  }

  String _formatElapsed(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UI BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F172A) : Colors.white;
    final surfaceColor = isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    final attendancePct = _totalStudents > 0
        ? ((_presentCount + _odCount) / _totalStudents * 100).toStringAsFixed(1)
        : '0.0';

    return DraggableScrollableSheet(
      initialChildSize: 0.90,
      minChildSize: 0.55,
      maxChildSize: 0.98,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          children: [
            // Grab Handle
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: subColor.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header & Recording Control Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title + Live Status Bar + Close
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _isRecordingActive
                              ? emeraldGreen.withValues(alpha: 0.15)
                              : primaryBlue.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _isRecordingActive ? Icons.fiber_smart_record_rounded : Icons.assignment_turned_in_rounded,
                          color: _isRecordingActive ? emeraldGreen : primaryBlue,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  widget.subjectName,
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: textColor,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _buildStatusBadge(),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.classSummary,
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 12,
                                color: subColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(context),
                        tooltip: 'Close Sheet',
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Action Buttons: Start Recording / Open Check-Out / Stop & Finalize / Face Camera / Export CSV
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (!_isRecordingActive)
                        FilledButton.icon(
                          onPressed: _isLoading ? null : _startRecording,
                          style: FilledButton.styleFrom(
                            backgroundColor: emeraldGreen,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.play_arrow_rounded, size: 18),
                          label: const Text('Start Recording',
                              style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12)),
                        )
                      else ...[
                        if ((_meta['status'] ?? '').toString() != 'checkout_open')
                          OutlinedButton.icon(
                            onPressed: _isLoading ? null : _startCheckout,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF0D9488),
                              side: const BorderSide(color: Color(0xFF0D9488)),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.logout_rounded, size: 16),
                            label: const Text('Open Check-Out',
                                style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12)),
                          ),
                        FilledButton.icon(
                          onPressed: _isLoading ? null : _stopRecordingAndFinalize,
                          style: FilledButton.styleFrom(
                            backgroundColor: roseError,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.stop_rounded, size: 18),
                          label: const Text('Stop Recording & Finalize',
                              style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12)),
                        ),
                      ],

                      OutlinedButton.icon(
                        onPressed: _toggleCameraScanner,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          side: BorderSide(color: _isCameraOpen ? indigoAccent : subColor.withValues(alpha: 0.4)),
                          foregroundColor: _isCameraOpen ? indigoAccent : textColor,
                          backgroundColor: _isCameraOpen ? indigoAccent.withValues(alpha: 0.1) : null,
                        ),
                        icon: Icon(_isCameraOpen ? Icons.videocam_off_rounded : Icons.center_focus_strong_rounded, size: 16),
                        label: Text(_isCameraOpen ? 'Close Camera' : 'Face Scan Camera',
                            style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 12)),
                      ),

                      OutlinedButton.icon(
                        onPressed: _exportCSV,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.file_download_outlined, size: 16),
                        label: const Text('Export CSV',
                            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 12)),
                      ),

                      IconButton(
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        onPressed: () => _loadRoll(),
                        tooltip: 'Refresh Roster',
                      ),
                    ],
                  ),

                  // Collapsible Face Scanner Tray
                  if (_isCameraOpen) ...[
                    const SizedBox(height: 12),
                    _buildCameraScannerTray(isDark),
                  ],

                  const SizedBox(height: 12),

                  // Summary Metric Strip
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: surfaceColor,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _metricPill('Total', '$_totalStudents', primaryBlue),
                          const SizedBox(width: 8),
                          _metricPill('Present', '$_presentCount', emeraldGreen),
                          const SizedBox(width: 8),
                          _metricPill('Checked Out', '$_checkedOutCount', const Color(0xFF0D9488)),
                          const SizedBox(width: 8),
                          _metricPill('Absent', '$_absentCount', roseError),
                          const SizedBox(width: 8),
                          _metricPill('Pending', '$_pendingCount', amberWarning),
                          const SizedBox(width: 8),
                          _metricPill('OD/Leave', '$_odCount', indigoAccent),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: emeraldGreen.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$attendancePct% Attended',
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                color: emeraldGreen,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Search + Filter Chips Row
                  Column(
                    children: [
                      TextField(
                        controller: _searchCtrl,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Search by student name, roll number, or reg no...',
                          hintStyle: TextStyle(fontFamily: 'Inter', color: subColor, fontSize: 12),
                          prefixIcon: Icon(Icons.search_rounded, color: subColor, size: 16),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                          filled: true,
                          fillColor: surfaceColor,
                          contentPadding: const EdgeInsets.symmetric(vertical: 8),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _filterTab('ALL', 'All ($_totalStudents)'),
                            _filterTab('PRESENT', 'Present ($_presentCount)'),
                            _filterTab('CHECKED_OUT', 'Checked Out ($_checkedOutCount)'),
                            _filterTab('IN_ONLY', 'In Only (${math.max(0, _presentCount - _checkedOutCount)})'),
                            _filterTab('ABSENT', 'Absent ($_absentCount)'),
                            _filterTab('PENDING', 'Pending ($_pendingCount)'),
                            _filterTab('ON-DUTY', 'OD ($_odCount)'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Student Roster List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: primaryBlue))
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.error_outline_rounded, color: roseError, size: 36),
                              const SizedBox(height: 8),
                              Text(_error!, style: TextStyle(fontFamily: 'Inter', color: subColor)),
                              const SizedBox(height: 12),
                              FilledButton(onPressed: _loadRoll, child: const Text('Retry')),
                            ],
                          ),
                        )
                      : _filteredRoll.isEmpty
                          ? Center(
                              child: Text(
                                'No students match the current filter',
                                style: TextStyle(fontFamily: 'Inter', color: subColor, fontSize: 13),
                              ),
                            )
                          : ListView.builder(
                              controller: scrollCtrl,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                              itemCount: _filteredRoll.length,
                              itemBuilder: (_, i) => _buildStudentRosterRow(_filteredRoll[i], isDark, textColor, subColor),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge() {
    if (_isRecordingActive) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: emeraldGreen.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: emeraldGreen.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(color: emeraldGreen, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(
              'RECORDING • ${_formatElapsed(_sessionElapsedSeconds)}',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                fontSize: 10,
                color: emeraldGreen,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF64748B).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _isSessionClosed ? 'FINALIZED' : 'STANDBY',
        style: const TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w700,
          fontSize: 10,
          color: Color(0xFF64748B),
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _buildCameraScannerTray(bool isDark) {
    return Container(
      height: 180,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: indigoAccent.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (_isCameraReady && _cameraController != null && _cameraController!.value.isInitialized && !_isCameraInitializing)
            CameraPreview(_cameraController!)
          else
            const Center(child: CircularProgressIndicator(color: indigoAccent)),

          // HUD Scanner Overlay
          AnimatedBuilder(
            animation: _scannerAnimController,
            builder: (context, _) => CustomPaint(
              size: const Size(double.infinity, 180),
              painter: _HUDScannerOverlayPainter(progress: _scannerAnimController.value),
            ),
          ),

          // Status bar on bottom of camera
          Positioned(
            bottom: 8,
            left: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  if (_isScanningFace)
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  else
                    const Icon(Icons.face_retouching_natural_rounded, color: emeraldGreen, size: 14),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _scanStatusMessage,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  InkWell(
                    onTap: _captureAndScanFace,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: indigoAccent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Scan Now',
                        style: TextStyle(fontFamily: 'Inter', color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentRosterRow(
    Map<String, dynamic> r,
    bool isDark,
    Color textColor,
    Color subColor,
  ) {
    final status = (r['status'] ?? 'Pending').toString();
    final isPresent = status == 'Present';
    final isAbsent = status == 'Absent';
    final isOD = status == 'On-Duty' || status == 'Leave';

    Color statusColor = amberWarning;
    if (isPresent) statusColor = emeraldGreen;
    if (isAbsent) statusColor = roseError;
    if (isOD) statusColor = indigoAccent;

    final rollNo = r['roll_no'] != null && r['roll_no'].toString().isNotEmpty ? 'Roll: ${r['roll_no']}' : '';
    final hasCheckout = r['checkout_time'] != null && r['checkout_time'].toString().trim().isNotEmpty;
    final checkinStr = r['checkin_time'] != null && r['checkin_time'].toString().trim().isNotEmpty
        ? 'In: ${_fmtTime(r['checkin_time'].toString())}'
        : '';
    final checkoutStr = hasCheckout ? 'Out: ${_fmtTime(r['checkout_time'].toString())}' : '';
    final timeStr = [checkinStr, checkoutStr].where((s) => s.isNotEmpty).join(' • ');

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasCheckout
              ? const Color(0xFF0D9488).withValues(alpha: 0.4)
              : (isPresent
                  ? emeraldGreen.withValues(alpha: 0.3)
                  : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0))),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: statusColor.withValues(alpha: 0.15),
            child: Text(
              (r['name'] ?? '?').substring(0, 1).toUpperCase(),
              style: TextStyle(fontFamily: 'Inter', color: statusColor, fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        r['name'] ?? r['reg_no'] ?? '—',
                        style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, color: textColor, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (r['face_registered'] == true) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.verified_rounded, size: 12, color: emeraldGreen),
                    ],
                  ],
                ),
                Text(
                  [r['reg_no'], rollNo, timeStr].where((s) => s.isNotEmpty).join(' • '),
                  style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: subColor),
                ),
              ],
            ),
          ),

          if (hasCheckout) ...[
            Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF0D9488).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF0D9488).withValues(alpha: 0.3)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.exit_to_app_rounded, size: 11, color: Color(0xFF0D9488)),
                  SizedBox(width: 3),
                  Text(
                    'Checked Out',
                    style: TextStyle(fontFamily: 'Inter', fontSize: 10, color: Color(0xFF0D9488), fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],

          // Status Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: statusColor.withValues(alpha: 0.3)),
            ),
            child: Text(
              status,
              style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: statusColor, fontWeight: FontWeight.w700),
            ),
          ),

          if (widget.canOverride) ...[
            const SizedBox(width: 8),
            // 1-Tap Toggle Actions
            IconButton(
              icon: Icon(
                isPresent ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded,
                color: isPresent ? emeraldGreen : subColor.withValues(alpha: 0.6),
                size: 20,
              ),
              tooltip: 'Mark Present',
              onPressed: () => _setStudentStatus(r['reg_no'], 'Present'),
            ),
            IconButton(
              icon: Icon(
                isAbsent ? Icons.cancel_rounded : Icons.cancel_outlined,
                color: isAbsent ? roseError : subColor.withValues(alpha: 0.6),
                size: 20,
              ),
              tooltip: 'Mark Absent',
              onPressed: () => _setStudentStatus(r['reg_no'], 'Absent'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _metricPill(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: color, fontWeight: FontWeight.w500)),
          Text(value, style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: color, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _filterTab(String key, String label) {
    final selected = _filterStatus == key;
    return GestureDetector(
      onTap: () => setState(() => _filterStatus = key),
      child: Container(
        margin: const EdgeInsets.only(left: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? primaryBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: primaryBlue.withValues(alpha: selected ? 1 : 0.3)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : primaryBlue,
          ),
        ),
      ),
    );
  }
}

class _HUDScannerOverlayPainter extends CustomPainter {
  final double progress;
  _HUDScannerOverlayPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final ovalW = math.min(size.width * 0.45, 140.0);
    final ovalH = math.min(size.height * 0.75, 120.0);

    final rect = Rect.fromCenter(center: center, width: ovalW, height: ovalH);

    final bgPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(rect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, bgPaint);

    final borderPaint = Paint()
      ..color = const Color(0xFF10B981)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawOval(rect, borderPaint);

    // Scanning horizontal laser beam
    final scanY = rect.top + (rect.height * progress);
    final laserPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Colors.transparent, Color(0xFF10B981), Colors.transparent],
      ).createShader(Rect.fromLTWH(rect.left, scanY, rect.width, 2))
      ..strokeWidth = 2.0;
    canvas.drawLine(Offset(rect.left + 10, scanY), Offset(rect.right - 10, scanY), laserPaint);
  }

  @override
  bool shouldRepaint(covariant _HUDScannerOverlayPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
