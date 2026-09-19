import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../config/college_ip_config.dart';

class AttendanceDurationSettings extends StatefulWidget {
  final String token;

  const AttendanceDurationSettings({super.key, required this.token});

  @override
  State<AttendanceDurationSettings> createState() => _AttendanceDurationSettingsState();
}

class _AttendanceDurationSettingsState extends State<AttendanceDurationSettings> {
  List<Map<String, dynamic>> _slots = [];
  bool _isLoading = true;
  bool _isSaving = false;

  // Master Session Boundaries
  String _fhStart = '08:30';
  String _fhEnd = '13:00';
  String _shStart = '13:00';
  String _shEnd = '17:30';

  // Location Tracking Duration
  String _locationTrackingStart = '08:30';
  String _locationTrackingEnd = '17:30';

  // Auto-extension settings
  bool _autoExpandCheckinEnabled = true;
  bool _autoExpandCheckoutEnabled = true;
  bool _requireFnCheckOut = false;
  int _autoExpandFnMins = 5;
  int _autoExpandAnMins = 5;
  int _autoExpandMins = 5;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final url = '${CollegeIPConfig.defaultURL}/admin/attendance/duration';
      final response = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['session_boundaries'] != null) {
          final sb = data['session_boundaries'];
          _fhStart = sb['first_half_start'] ?? '08:30';
          _fhEnd = sb['first_half_end'] ?? '13:00';
          _shStart = sb['second_half_start'] ?? '13:00';
          _shEnd = sb['second_half_end'] ?? '17:30';
        }
        if (data['location_tracking'] != null) {
          final loc = data['location_tracking'];
          _locationTrackingStart = loc['start_time'] ?? '08:30';
          _locationTrackingEnd = loc['end_time'] ?? '17:30';
        }
        if (data['auto_expansion'] != null) {
          final ae = data['auto_expansion'];
          _autoExpandCheckinEnabled = ae['auto_expand_checkin_enabled'] ?? true;
          _autoExpandCheckoutEnabled = ae['auto_expand_checkout_enabled'] ?? true;
          _requireFnCheckOut = ae['require_fn_check_out'] ?? false;
          _autoExpandFnMins = ae['auto_expand_fn_minutes'] ?? 5;
          _autoExpandAnMins = ae['auto_expand_an_minutes'] ?? 5;
          _autoExpandMins = ae['auto_expand_minutes'] ?? 5;
        }

        if (data['data'] != null && (data['data'] as List).isNotEmpty) {
          setState(() {
            _slots = (data['data'] as List).map((e) {
              final map = Map<String, dynamic>.from(e);
              map['slot_type'] = map['slot_type'] ?? 'check_in';
              map['slot_half'] = map['slot_half'] ?? 'full_day';
              return map;
            }).toList();
          });
        } else {
          // Initialize with default slots
          _slots = [
            {'slot_number': 1, 'start_time': '09:00', 'duration_minutes': 30, 'is_enabled': true, 'slot_type': 'check_in', 'slot_half': 'first_half'},
            {'slot_number': 2, 'start_time': '14:00', 'duration_minutes': 30, 'is_enabled': true, 'slot_type': 'check_out', 'slot_half': 'second_half'},
          ];
        }
      } else {
        _slots = [
          {'slot_number': 1, 'start_time': '09:00', 'duration_minutes': 30, 'is_enabled': true, 'slot_type': 'check_in', 'slot_half': 'first_half'},
          {'slot_number': 2, 'start_time': '14:00', 'duration_minutes': 30, 'is_enabled': true, 'slot_type': 'check_out', 'slot_half': 'second_half'},
        ];
      }
    } catch (e) {
      print('Error loading duration settings: $e');
      _slots = [
        {'slot_number': 1, 'start_time': '09:00', 'duration_minutes': 30, 'is_enabled': true, 'slot_type': 'check_in', 'slot_half': 'first_half'},
        {'slot_number': 2, 'start_time': '14:00', 'duration_minutes': 30, 'is_enabled': true, 'slot_type': 'check_out', 'slot_half': 'second_half'},
      ];
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  int _timeToMinutes(String timeStr) {
    try {
      final parts = timeStr.split(':');
      return int.parse(parts[0]) * 60 + int.parse(parts[1]);
    } catch (_) {
      return 0;
    }
  }

  String _minutesToTime(int totalMinutes) {
    final clamped = totalMinutes < 0 ? 0 : totalMinutes;
    final h = (clamped ~/ 60) % 24;
    final m = clamped % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  int _calculateSlotEffectiveDuration(Map<String, dynamic> slot) {
    final dur = (slot['duration_minutes'] as num?)?.toInt() ?? 30;
    final slotType = slot['slot_type'] ?? 'check_in';
    final slotHalf = slot['slot_half'] ?? 'full_day';

    int ext = 0;
    if (slotType == 'check_in' && _autoExpandCheckinEnabled) {
      if (slotHalf == 'first_half') {
        ext = _autoExpandFnMins;
      } else if (slotHalf == 'second_half') {
        ext = _autoExpandAnMins;
      } else {
        ext = _autoExpandMins;
      }
    } else if (slotType == 'check_out' && _autoExpandCheckoutEnabled) {
      if (slotHalf == 'first_half') {
        ext = _autoExpandFnMins;
      } else if (slotHalf == 'second_half') {
        ext = _autoExpandAnMins;
      } else {
        ext = _autoExpandMins;
      }
    }
    return dur + ext;
  }

  Map<int, List<String>> _getSlotConflicts() {
    final Map<int, List<String>> slotConflicts = {};
    final fhStartMin = _timeToMinutes(_fhStart);
    final fhEndMin = _timeToMinutes(_fhEnd);
    final shStartMin = _timeToMinutes(_shStart);
    final shEndMin = _timeToMinutes(_shEnd);

    for (int i = 0; i < _slots.length; i++) {
      slotConflicts[i] = [];
      final slot = _slots[i];
      final isEnabled = slot['is_enabled'] ?? true;
      if (!isEnabled) continue;

      final slotHalf = slot['slot_half'] ?? 'full_day';
      final dur = (slot['duration_minutes'] as num?)?.toInt() ?? 30;

      if (dur < 1 || dur > 120) {
        slotConflicts[i]!.add('Duration must be between 1 and 120 minutes (currently $dur min).');
      }

      final startMin = _timeToMinutes(slot['start_time'] ?? '09:00');
      // Extra time (auto-extension) is a grace buffer; schedule containment is based on base duration
      final baseEndMin = startMin + dur;

      if (slotHalf == 'first_half') {
        if (startMin < fhStartMin || baseEndMin > fhEndMin) {
          slotConflicts[i]!.add(
            'Window (${slot['start_time']} - ${_minutesToTime(baseEndMin)}) exceeds First Half session boundary ($_fhStart - $_fhEnd).',
          );
        }
      } else if (slotHalf == 'second_half') {
        if (startMin < shStartMin || baseEndMin > shEndMin) {
          slotConflicts[i]!.add(
            'Window (${slot['start_time']} - ${_minutesToTime(baseEndMin)}) exceeds Second Half session boundary ($_shStart - $_shEnd).',
          );
        }
      }
    }

    // Cross-slot checks for enabled slots
    for (int i = 0; i < _slots.length; i++) {
      if (!(_slots[i]['is_enabled'] ?? true)) continue;
      final startI = _timeToMinutes(_slots[i]['start_time'] ?? '09:00');
      final durI = (_slots[i]['duration_minutes'] as num?)?.toInt() ?? 30;
      final baseEndI = startI + durI;
      final typeI = _slots[i]['slot_type'] ?? 'check_in';
      final halfI = _slots[i]['slot_half'] ?? 'full_day';

      for (int j = i + 1; j < _slots.length; j++) {
        if (!(_slots[j]['is_enabled'] ?? true)) continue;
        final startJ = _timeToMinutes(_slots[j]['start_time'] ?? '09:00');
        final durJ = (_slots[j]['duration_minutes'] as num?)?.toInt() ?? 30;
        final baseEndJ = startJ + durJ;
        final typeJ = _slots[j]['slot_type'] ?? 'check_in';
        final halfJ = _slots[j]['slot_half'] ?? 'full_day';

        // Check full_day vs half_day mix
        if ((halfI == 'full_day' && (halfJ == 'first_half' || halfJ == 'second_half')) ||
            (halfJ == 'full_day' && (halfI == 'first_half' || halfI == 'second_half'))) {
          slotConflicts[i]!.add('Cannot mix Full Day (Slot ${i + 1}) with Half Day (Slot ${j + 1}).');
          slotConflicts[j]!.add('Cannot mix Full Day (Slot ${i + 1}) with Half Day (Slot ${j + 1}).');
        }

        // Mutual time window overlap based on base duration:
        // Extra time / auto-extension is an extension grace buffer and does NOT constitute a conflict
        if (startI < baseEndJ && startJ < baseEndI) {
          slotConflicts[i]!.add('Time window overlaps with Slot ${j + 1} (${_slots[j]['start_time']} - ${_minutesToTime(baseEndJ)}).');
          slotConflicts[j]!.add('Time window overlaps with Slot ${i + 1} (${_slots[i]['start_time']} - ${_minutesToTime(baseEndI)}).');
        }

        // Ordering: Check-In before Check-Out within same session
        if (halfI == halfJ) {
          if (typeI == 'check_in' && typeJ == 'check_out') {
            if (startI >= startJ) {
              slotConflicts[i]!.add('Check-In (Slot ${i + 1}) must start before Check-Out (Slot ${j + 1}).');
              slotConflicts[j]!.add('Check-Out (Slot ${j + 1}) must start after Check-In (Slot ${i + 1}).');
            } else if (baseEndI > startJ) {
              slotConflicts[i]!.add('Check-In (Slot ${i + 1}) base time ends after Check-Out (Slot ${j + 1}) starts.');
              slotConflicts[j]!.add('Check-Out (Slot ${j + 1}) starts before Check-In (Slot ${i + 1}) base time ends.');
            }
          } else if (typeI == 'check_out' && typeJ == 'check_in') {
            if (startJ >= startI) {
              slotConflicts[j]!.add('Check-In (Slot ${j + 1}) must start before Check-Out (Slot ${i + 1}).');
              slotConflicts[i]!.add('Check-Out (Slot ${i + 1}) must start after Check-In (Slot ${j + 1}).');
            } else if (baseEndJ > startI) {
              slotConflicts[j]!.add('Check-In (Slot ${j + 1}) base time ends after Check-Out (Slot ${i + 1}) starts.');
              slotConflicts[i]!.add('Check-Out (Slot ${i + 1}) starts before Check-In (Slot ${j + 1}) base time ends.');
            }
          }
        }
      }
    }

    return slotConflicts;
  }

  List<String> _validateAllSettings() {
    final List<String> errors = [];
    final fhStartMin = _timeToMinutes(_fhStart);
    final fhEndMin = _timeToMinutes(_fhEnd);
    final shStartMin = _timeToMinutes(_shStart);
    final shEndMin = _timeToMinutes(_shEnd);

    if (fhStartMin >= fhEndMin) {
      errors.add('First Half start time ($_fhStart) must be earlier than First Half end time ($_fhEnd).');
    }
    if (shStartMin >= shEndMin) {
      errors.add('Second Half start time ($_shStart) must be earlier than Second Half end time ($_shEnd).');
    }
    if (shStartMin < fhEndMin) {
      errors.add('Second Half start time ($_shStart) cannot overlap First Half end time ($_fhEnd).');
    }

    if (_autoExpandCheckinEnabled || _autoExpandCheckoutEnabled) {
      if (_autoExpandFnMins > 60) {
        errors.add('FN Extension Duration cannot exceed 60 minutes.');
      }
      if (_autoExpandAnMins > 60) {
        errors.add('AN Extension Duration cannot exceed 60 minutes.');
      }
    }

    final slotConflicts = _getSlotConflicts();
    slotConflicts.forEach((slotIdx, conflicts) {
      for (final conflict in conflicts) {
        final entry = 'Slot ${slotIdx + 1}: $conflict';
        if (!errors.contains(entry)) {
          errors.add(entry);
        }
      }
    });

    return errors;
  }

  Future<void> _saveSettings() async {
    final conflicts = _validateAllSettings();
    if (conflicts.isNotEmpty) {
      _showConflictDialog(conflicts.join('\n\n'));
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final url = '${CollegeIPConfig.defaultURL}/admin/attendance/duration';
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'settings': _slots,
          'session_boundaries': {
            'first_half_start': _fhStart,
            'first_half_end': _fhEnd,
            'second_half_start': _shStart,
            'second_half_end': _shEnd,
          },
          'location_tracking': {
            'start_time': _locationTrackingStart,
            'end_time': _locationTrackingEnd,
          },
          'auto_expansion': {
            'auto_expand_checkin_enabled': _autoExpandCheckinEnabled,
            'auto_expand_checkout_enabled': _autoExpandCheckoutEnabled,
            'require_fn_check_out': _requireFnCheckOut,
            'auto_expand_fn_minutes': _autoExpandFnMins,
            'auto_expand_an_minutes': _autoExpandAnMins,
            'auto_expand_minutes': _autoExpandMins,
          },

        }),
      );





      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Duration settings saved successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        String errorMsg = 'Failed to save settings';
        try {
          final errorData = jsonDecode(response.body);
          if (errorData is Map && errorData.containsKey('detail')) {
            errorMsg = errorData['detail'].toString();
          } else if (errorData is Map && errorData.containsKey('message')) {
            errorMsg = errorData['message'].toString();
          }
        } catch (_) {}

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMsg),
              backgroundColor: Colors.red,
            ),
          );
          if (response.statusCode == 400) {
            _showConflictDialog(errorMsg);
          }
        }
      }
    } catch (e) {
      print('Error saving duration settings: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  void _showConflictDialog(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 28),
              const SizedBox(width: 8),
              const Text('Timing Conflict Detected', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: Text(
            message,
            style: const TextStyle(fontSize: 14, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Understand',
                style: TextStyle(color: isDark ? Colors.white70 : Colors.deepPurple, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBoundaryTimePicker(String label, String timeStr, Function(String) onPicked) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        InkWell(
          onTap: () async {
            final parts = timeStr.split(':');
            final initial = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
            final picked = await showTimePicker(context: context, initialTime: initial);
            if (picked != null) {
              onPicked('${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[850] : Colors.white,
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(timeStr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const Icon(Icons.access_time, size: 16, color: Colors.grey),
              ],
            ),
          ),
        ),
      ],
    );
  }


  Future<void> _selectTime(int index) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.parse(_slots[index]['start_time'].split(':')[0]),
        minute: int.parse(_slots[index]['start_time'].split(':')[1]),
      ),
    );

    if (picked != null) {
      setState(() {
        _slots[index]['start_time'] = 
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      });
    }
  }

  void _addSlot() {
    if (_slots.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Maximum 5 slots allowed'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _slots.add({
        'slot_number': _slots.length + 1,
        'start_time': '09:00',
        'duration_minutes': 30,
        'is_enabled': true,
        'slot_type': 'check_in',
      });
    });
  }

  void _removeSlot(int index) {
    if (_slots.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('At least one slot is required'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _slots.removeAt(index);
      // Renumber slots
      for (int i = 0; i < _slots.length; i++) {
        _slots[i]['slot_number'] = i + 1;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Duration'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _saveSettings,
              tooltip: 'Save Settings',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Master Session Boundaries Card
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.schedule, color: Colors.deepPurple, size: 24),
                              const SizedBox(width: 8),
                              const Text(
                                'Overall Half Session Boundaries',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Define master operating hours for First Half and Second Half. Check-in/out slots must stay strictly within their session boundary.',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 16),

                          // First Half Boundary Controls
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.wb_sunny_outlined, color: Colors.amber, size: 18),
                                    SizedBox(width: 8),
                                    Text('First Half Session Boundary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildBoundaryTimePicker('Start Time', _fhStart, (newTime) {
                                        setState(() => _fhStart = newTime);
                                      }),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildBoundaryTimePicker('End Time', _fhEnd, (newTime) {
                                        setState(() => _fhEnd = newTime);
                                      }),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Second Half Boundary Controls
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.indigo.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.indigo.withValues(alpha: 0.3)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.nights_stay_outlined, color: Colors.indigo, size: 18),
                                    SizedBox(width: 8),
                                    Text('Second Half Session Boundary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildBoundaryTimePicker('Start Time', _shStart, (newTime) {
                                        setState(() => _shStart = newTime);
                                      }),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildBoundaryTimePicker('End Time', _shEnd, (newTime) {
                                        setState(() => _shEnd = newTime);
                                      }),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Location Tracking Boundaries Card
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.location_on, color: Colors.teal, size: 24),
                              const SizedBox(width: 8),
                              const Text(
                                'Location Tracking Window',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Define the permitted window when staff locations will be tracked and recorded by the system. Ping operations outside these bounds will be dropped.',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.teal.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.teal.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _buildBoundaryTimePicker('Start Time', _locationTrackingStart, (newTime) {
                                    setState(() => _locationTrackingStart = newTime);
                                  }),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildBoundaryTimePicker('End Time', _locationTrackingEnd, (newTime) {
                                    setState(() => _locationTrackingEnd = newTime);
                                  }),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Auto Slot Extension Card (Check-In & Check-Out for FN / AN)
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.more_time_rounded, color: Color(0xFF007AFF), size: 22),
                              SizedBox(width: 10),
                              Text(
                                'Auto Slot Extensions (FN & AN)',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Automatically extends active Check-In and Check-Out slots by the configured duration to prevent sudden window cut-offs for staff during FN & AN sessions.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).brightness == Brightness.dark ? Colors.white60 : Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Divider(height: 1),
                          const SizedBox(height: 8),

                          // Check-In Toggle
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.login_rounded, color: Colors.green, size: 18),
                                  SizedBox(width: 8),
                                  Text(
                                    'Extend Check-In Slots',
                                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                  ),
                                ],
                              ),
                              Switch(
                                value: _autoExpandCheckinEnabled,
                                activeColor: const Color(0xFF007AFF),
                                onChanged: (val) {
                                  setState(() => _autoExpandCheckinEnabled = val);
                                },
                              ),
                            ],
                          ),

                          // Check-Out Toggle
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.logout_rounded, color: Colors.orange, size: 18),
                                  SizedBox(width: 8),
                                  Text(
                                    'Extend Check-Out Slots',
                                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                  ),
                                ],
                              ),
                              Switch(
                                value: _autoExpandCheckoutEnabled,
                                activeColor: const Color(0xFF007AFF),
                                onChanged: (val) {
                                  setState(() => _autoExpandCheckoutEnabled = val);
                                },
                              ),
                            ],
                          ),

                          const SizedBox(height: 8),
                          const Divider(height: 1),
                          const SizedBox(height: 8),

                          // Require FN Check-Out Toggle
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Require Morning (FN) Check-Out',
                                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'When OFF, staff do not need to scan Check-Out for FN session',
                                      style: TextStyle(fontSize: 11, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: _requireFnCheckOut,
                                activeColor: const Color(0xFF007AFF),
                                onChanged: (val) {
                                  setState(() => _requireFnCheckOut = val);
                                },
                              ),
                            ],
                          ),


                          if (_autoExpandCheckinEnabled || _autoExpandCheckoutEnabled) ...[
                            const SizedBox(height: 12),
                            const Divider(height: 1),
                            const SizedBox(height: 10),
                            const Text(
                              'Custom Extension Durations',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('FN Extension', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 4),
                                      TextFormField(
                                        initialValue: _autoExpandFnMins.toString(),
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                        decoration: InputDecoration(
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                          suffixText: 'mins',
                                          isDense: true,
                                          errorText: _autoExpandFnMins > 60 ? 'Max 60 mins' : null,
                                        ),
                                        onChanged: (val) {
                                          final parsed = int.tryParse(val.trim()) ?? 0;
                                          setState(() => _autoExpandFnMins = parsed);
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('AN Extension', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 4),
                                      TextFormField(
                                        initialValue: _autoExpandAnMins.toString(),
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                        decoration: InputDecoration(
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                          suffixText: 'mins',
                                          isDense: true,
                                          errorText: _autoExpandAnMins > 60 ? 'Max 60 mins' : null,
                                        ),
                                        onChanged: (val) {
                                          final parsed = int.tryParse(val.trim()) ?? 0;
                                          setState(() => _autoExpandAnMins = parsed);
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Live Timing Conflicts Warning Card
                  Builder(
                    builder: (context) {
                      final allConflicts = _validateAllSettings();
                      if (allConflicts.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      final isDark = Theme.of(context).brightness == Brightness.dark;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 20),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF3B1E1E) : const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFEF4444), width: 1.5),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 22),
                                const SizedBox(width: 8),
                                Text(
                                  'Timing Conflicts Detected (${allConflicts.length})',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: isDark ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'The following timing configuration conflicts must be resolved before settings can be saved:',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white70 : const Color(0xFF7F1D1D),
                              ),
                            ),
                            const SizedBox(height: 10),
                            ...allConflicts.map((c) => Padding(
                              padding: const EdgeInsets.only(bottom: 5),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('• ', style: TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.bold)),
                                  Expanded(
                                    child: Text(
                                      c,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark ? Colors.white : const Color(0xFF450A0A),
                                        height: 1.3,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )),
                          ],
                        ),
                      );
                    },
                  ),

                  // Slots List
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _slots.length,
                    itemBuilder: (context, index) {
                      final slotConflictsMap = _getSlotConflicts();
                      final thisSlotConflicts = slotConflictsMap[index] ?? [];
                      final hasConflict = thisSlotConflicts.isNotEmpty && (_slots[index]['is_enabled'] ?? true);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: hasConflict
                              ? const BorderSide(color: Color(0xFFDC2626), width: 1.5)
                              : BorderSide.none,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: hasConflict
                                          ? const Color(0xFFFEE2E2)
                                          : Colors.deepPurple.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      'Slot ${index + 1}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: hasConflict
                                            ? const Color(0xFFDC2626)
                                            : Colors.deepPurple,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  Switch(
                                    value: _slots[index]['is_enabled'] ?? true,
                                    onChanged: (value) {
                                      setState(() {
                                        _slots[index]['is_enabled'] = value;
                                      });
                                    },
                                    activeColor: Colors.green,
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    onPressed: () => _removeSlot(index),
                                    tooltip: 'Remove Slot',
                                  ),
                                ],
                              ),
                              if (hasConflict) ...[
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF2F2),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFFFCA5A5)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: thisSlotConflicts.map((err) => Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 16),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            err,
                                            style: const TextStyle(
                                              color: Color(0xFF991B1B),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ],
                                    )).toList(),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 16),

                              // Slot Type & Slot Half Selector
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Slot Type (Purpose)',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12),
                                          decoration: BoxDecoration(
                                            border: Border.all(color: Colors.grey[300]!),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: DropdownButton<String>(
                                            value: _slots[index]['slot_type'] ?? 'check_in',
                                            isExpanded: true,
                                            underline: const SizedBox(),
                                            items: const [
                                              DropdownMenuItem(
                                                value: 'check_in',
                                                child: Text('Check-In Attendance'),
                                              ),
                                              DropdownMenuItem(
                                                value: 'check_out',
                                                child: Text('Check-Out Attendance'),
                                              ),
                                            ],
                                            onChanged: (value) {
                                              if (value != null) {
                                                setState(() {
                                                  _slots[index]['slot_type'] = value;
                                                });
                                              }
                                            },
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
                                        const Text(
                                          'Session / Half Split',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12),
                                          decoration: BoxDecoration(
                                            border: Border.all(color: Colors.grey[300]!),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: DropdownButton<String>(
                                            value: _slots[index]['slot_half'] ?? 'full_day',
                                            isExpanded: true,
                                            underline: const SizedBox(),
                                            items: const [
                                              DropdownMenuItem(
                                                value: 'full_day',
                                                child: Text('Full Day / Standard'),
                                              ),
                                              DropdownMenuItem(
                                                value: 'first_half',
                                                child: Text('First Half Slot'),
                                              ),
                                              DropdownMenuItem(
                                                value: 'second_half',
                                                child: Text('Second Half Slot'),
                                              ),
                                            ],
                                            onChanged: (value) {
                                              if (value != null) {
                                                setState(() {
                                                  _slots[index]['slot_half'] = value;
                                                });
                                              }
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 16),

                              // Start Time
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Start Time',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        InkWell(
                                          onTap: () => _selectTime(index),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 12,
                                            ),
                                            decoration: BoxDecoration(
                                              border: Border.all(color: Colors.grey[300]!),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text(
                                                  _slots[index]['start_time'] ?? '09:00',
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                                Icon(Icons.access_time, color: Colors.grey[600]),
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
                                        const Text(
                                          'Duration (minutes)',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        TextFormField(
                                          initialValue: (_slots[index]['duration_minutes'] ?? 30).toString(),
                                          keyboardType: TextInputType.number,
                                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                          decoration: InputDecoration(
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                            suffixText: 'mins',
                                            errorText: ((_slots[index]['duration_minutes'] ?? 30) > 120) ? 'Max 120 mins' : null,
                                          ),
                                          onChanged: (val) {
                                            final parsed = int.tryParse(val.trim()) ?? 0;
                                            setState(() {
                                              _slots[index]['duration_minutes'] = parsed;
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 12),

                              // End Time Display
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.event_available, 
                                         color: Colors.green[700], size: 20),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Attendance window: ${_slots[index]['start_time']} - ${_calculateEndTime(_slots[index])}',
                                      style: TextStyle(
                                        color: Colors.grey[700],
                                        fontWeight: FontWeight.w500,
                                      ),
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

                  const SizedBox(height: 16),

                  // Add Slot Button
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: _addSlot,
                      icon: const Icon(Icons.add),
                      label: const Text('Add Time Slot'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // FN/AN Half-Day Info Card
                  Card(
                    color: Colors.amber[50],
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.wb_sunny_outlined, color: Colors.amber[800]),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'FN / AN Half-Day Attendance',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amber[900],
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '• Assign each slot to FN (Morning) or AN (Afternoon) session.\n'
                                  '• FN slot marks morning attendance = 0.5 value.\n'
                                  '• AN slot marks afternoon attendance = 0.5 value.\n'
                                  '• Both FN + AN = Full Day = 1.0 value.\n'
                                  '• The system auto-enables Half-Day mode when any FN/AN slot exists.',
                                  style: TextStyle(
                                    color: Colors.amber[900],
                                    fontSize: 12,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // How it works card
                  Card(
                    color: Colors.blue[50],
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue[700]),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'How it works',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue[700],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '• Staff can only mark attendance during the configured time windows.\n'
                                  '• The slot\'s start time + duration defines the window.\n'
                                  '• Slots must stay within their assigned session boundary.\n'
                                  '• Maximum 5 slots allowed.',
                                  style: TextStyle(
                                    color: Colors.blue[700],
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  String _calculateEndTime(Map<String, dynamic> slot) {
    try {
      final startTime = slot['start_time'] ?? '09:00';
      final baseDuration = (slot['duration_minutes'] as num?)?.toInt() ?? 30;
      final effectiveDuration = _calculateSlotEffectiveDuration(slot);
      final ext = effectiveDuration - baseDuration;

      final startMin = _timeToMinutes(startTime);
      final baseEnd = _minutesToTime(startMin + baseDuration);
      final effEnd = _minutesToTime(startMin + effectiveDuration);

      if (ext > 0) {
        return '$baseEnd (+$ext min auto-ext = $effEnd)';
      }
      return baseEnd;
    } catch (e) {
      return '09:30';
    }
  }
}
