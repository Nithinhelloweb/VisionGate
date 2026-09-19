import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/college_ip_config.dart';
import '../services/leave_balance_notifier.dart';

class CCLManagementPage extends StatefulWidget {
  final String token;

  const CCLManagementPage({super.key, required this.token});

  @override
  State<CCLManagementPage> createState() => _CCLManagementPageState();
}

class _CCLManagementPageState extends State<CCLManagementPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // Custom Dates State
  Map<String, dynamic> _customDatesMap = {};
  bool _savingCustomDates = false;
  DateTimeRange? _selectedCustomDateRange;
  List<DateTime> _selectedMultipleDates = [];
  bool _isRangeMode = true;
  DateTime _calendarMonth = DateTime.now();
  
  bool _customEarlyEnabled = false;
  bool _customLateEnabled = false;
  TimeOfDay _customEarlyStart = const TimeOfDay(hour: 7, minute: 0);
  TimeOfDay _customEarlyEnd = const TimeOfDay(hour: 8, minute: 0);
  int _customEarlyDuration = 60;
  TimeOfDay _customLateStart = const TimeOfDay(hour: 17, minute: 0);
  TimeOfDay _customLateEnd = const TimeOfDay(hour: 18, minute: 0);
  int _customLateDuration = 60;


  // History Tab State
  List<dynamic> _history = [];
  bool _loadingHistory = false;
  String? _historyError;


  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        if (_tabController.index == 2) {
          _loadHistory();
        }
      }
    });
    // Use addPostFrameCallback so loads run AFTER the widget is mounted
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadCustomDates();
        _loadHistory();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  TimeOfDay _parseTimeStr(String timeStr) {
    try {
      final parts = timeStr.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    } catch (_) {
      return const TimeOfDay(hour: 8, minute: 0);
    }
  }

  Future<void> _loadCustomDates() async {
    try {
      final response = await http.get(
        Uri.parse('${CollegeIPConfig.defaultURL}/admin/ccl/custom-dates'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (response.statusCode == 200) {
        final res = json.decode(response.body);
        if (res['success'] == true) {
          final List<dynamic> datesList = res['data'] ?? [];
          final Map<String, dynamic> datesMap = {};
          for (var item in datesList) {
            final dateKey = item['date']?.toString();
            if (dateKey != null) {
              datesMap[dateKey] = item;
            }
          }
          setState(() {
            _customDatesMap = datesMap;
          });
        }
      }
    } catch (e) {
      _showSnackBar('Error loading custom dates: $e', Colors.red);
    }
  }

  Future<void> _saveCustomDates() async {
    List<String> datesToSave = [];
    if (_isRangeMode) {
      if (_selectedCustomDateRange == null) {
        _showSnackBar('Please select a date range first.', Colors.orange);
        return;
      }
      var start = _selectedCustomDateRange!.start;
      var end = _selectedCustomDateRange!.end;
      for (var d = start; d.isBefore(end) || d.isAtSameMomentAs(end); d = d.add(const Duration(days: 1))) {
        datesToSave.add("${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}");
      }
    } else {
      if (_selectedMultipleDates.isEmpty) {
        _showSnackBar('Please select at least one date.', Colors.orange);
        return;
      }
      for (var d in _selectedMultipleDates) {
        datesToSave.add("${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}");
      }
    }

    setState(() => _savingCustomDates = true);
    try {
      final response = await http.post(
        Uri.parse('${CollegeIPConfig.defaultURL}/admin/ccl/custom-dates'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
        body: json.encode({
          'dates': datesToSave,
          'early_enabled': _customEarlyEnabled,
          'early_start': _formatTimeOfDay(_customEarlyStart),
          'early_end': _formatTimeOfDay(_customEarlyEnd),
          'early_duration': _customEarlyDuration,
          'late_enabled': _customLateEnabled,
          'late_start': _formatTimeOfDay(_customLateStart),
          'late_end': _formatTimeOfDay(_customLateEnd),
          'late_duration': _customLateDuration,
        }),
      );

      final res = json.decode(response.body);
      if (response.statusCode == 200 && res['success'] == true) {
        _showSnackBar('Custom dates saved successfully!', Colors.green);
        _loadCustomDates();
        setState(() {
          _selectedCustomDateRange = null;
          _selectedMultipleDates = [];
        });
      } else {
        _showSnackBar(res['detail'] ?? 'Failed to save custom dates', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Error saving custom dates: $e', Colors.red);
    } finally {
      setState(() => _savingCustomDates = false);
    }
  }

  Future<void> _deleteCustomDate(String dateStr) async {
    try {
      final response = await http.delete(
        Uri.parse('${CollegeIPConfig.defaultURL}/admin/ccl/custom-dates/$dateStr'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (response.statusCode == 200) {
        final res = json.decode(response.body);
        if (res['success'] == true) {
          _showSnackBar('Custom settings for $dateStr deleted.', Colors.green);
          _loadCustomDates();
        }
      } else {
        _showSnackBar('Failed to delete custom date settings.', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Error deleting custom date: $e', Colors.red);
    }
  }

  Future<void> _updateSingleCustomDate(
    String dateStr,
    bool earlyEnabled,
    TimeOfDay earlyStart,
    TimeOfDay earlyEnd,
    int earlyDur,
    bool lateEnabled,
    TimeOfDay lateStart,
    TimeOfDay lateEnd,
    int lateDur,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('${CollegeIPConfig.defaultURL}/admin/ccl/custom-dates'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
        body: json.encode({
          'dates': [dateStr],
          'early_enabled': earlyEnabled,
          'early_start': _formatTimeOfDay(earlyStart),
          'early_end': _formatTimeOfDay(earlyEnd),
          'early_duration': earlyDur,
          'late_enabled': lateEnabled,
          'late_start': _formatTimeOfDay(lateStart),
          'late_end': _formatTimeOfDay(lateEnd),
          'late_duration': lateDur,
        }),
      );
      final res = json.decode(response.body);
      if (response.statusCode == 200 && res['success'] == true) {
        _showSnackBar('Updated successfully for $dateStr!', Colors.green);
        _loadCustomDates();
      } else {
        _showSnackBar(res['detail'] ?? 'Failed to update custom date', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Error updating custom date: $e', Colors.red);
    }
  }


  Future<void> _loadHistory() async {
    if (!mounted) return;
    setState(() => _loadingHistory = true);
    try {
      final response = await http.get(
        Uri.parse('${CollegeIPConfig.defaultURL}/admin/ccl/history'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      ).timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final res = json.decode(response.body);
        if (res['success'] == true) {
          if (mounted) setState(() { _history = res['data'] ?? []; _historyError = null; });
        } else {
          if (mounted) setState(() => _historyError = res['detail'] ?? 'Failed to load history');
        }
      } else {
        String errMsg;
        try {
          final res = json.decode(response.body);
          errMsg = res['detail'] ?? 'Server error ${response.statusCode}';
        } catch (_) {
          errMsg = 'Server error ${response.statusCode}';
        }
        if (mounted) setState(() => _historyError = errMsg);
      }
    } catch (e) {
      if (mounted) setState(() => _historyError = 'Connection error: $e');
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }



  void _showSnackBar(String msg, Color color) {
    if (mounted) {
      try {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: color, duration: const Duration(seconds: 4)),
        );
      } catch (_) {
        // context not ready - silently ignore
      }
    }
  }



  // UI Renderers
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF202020) : const Color(0xFFF3F3F3),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Container(
          color: isDark ? const Color(0xFF2D2D2D) : Colors.white,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TabBar(
                controller: _tabController,
                indicatorColor: const Color(0xFF0078D4),
                indicatorSize: TabBarIndicatorSize.label,
                labelColor: isDark ? Colors.white : const Color(0xFF202020),
                unselectedLabelColor: Colors.grey,
                dividerColor: Colors.transparent,
                labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                tabs: const [
                  Tab(text: 'Rules & Settings'),
                  Tab(text: 'CCL Balance'),
                  Tab(text: 'Earnings History'),
                ],
              ),
              Divider(height: 1, color: isDark ? const Color(0xFF3F3F3F) : const Color(0xFFE5E5E5)),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSettingsTab(isDark),
          _CclLeaveBalancesTab(token: widget.token),
          _buildHistoryTab(isDark),
        ],
      ),
    );
  }

  Widget _buildSettingsTab(bool isDark) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.95, end: 1.0),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      builder: (context, val, child) {
        return Opacity(
          opacity: val,
          child: Transform.translate(
            offset: Offset(0, 15 * (1.0 - val)),
            child: child,
          ),
        );
      },
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: isMobile ? 0.0 : 16.0, vertical: isMobile ? 0.0 : 24.0),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 650),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2D2D2D) : Colors.white,
              borderRadius: isMobile ? BorderRadius.zero : BorderRadius.circular(8),
              border: isMobile
                  ? null
                  : Border.all(
                      color: isDark ? const Color(0xFF3F3F3F) : const Color(0xFFE5E5E5),
                      width: 1.0,
                    ),
            ),
            padding: EdgeInsets.all(isMobile ? 16.0 : 24.0),
            child: _buildCustomDatesSection(isDark),
          ),
        ),
      ),
    );
  }

  Widget _buildCustomDatesSection(bool isDark) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),
        const Text(
          'Customized Date Settings',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          'Setup timing rules for specific dates.',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
        const Divider(height: 32),
        
        Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: isDark ? const Color(0xFF202020) : const Color(0xFFF9F9F9),
          shape: RoundedRectangleBorder(
            side: isMobile ? BorderSide.none : BorderSide(color: isDark ? const Color(0xFF3F3F3F) : const Color(0xFFE5E5E5)),
            borderRadius: isMobile ? BorderRadius.zero : BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Define Date Rules',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.grey[300] : Colors.black87),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text('Range', style: TextStyle(fontSize: 12, color: _isRangeMode ? const Color(0xFF0078D4) : Colors.grey)),
                        Switch(
                          value: !_isRangeMode,
                          activeThumbColor: const Color(0xFF0078D4),
                          activeTrackColor: const Color(0xFF0078D4).withValues(alpha: 0.5),
                          onChanged: (val) {
                            setState(() {
                              _isRangeMode = !val;
                            });
                          },
                        ),
                        Text('Specific Dates', style: TextStyle(fontSize: 12, color: !_isRangeMode ? const Color(0xFF0078D4) : Colors.grey)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                if (_isRangeMode)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0078D4),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    onPressed: () async {
                      final range = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime.now().subtract(const Duration(days: 365)),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                        initialDateRange: _selectedCustomDateRange,
                      );
                      if (range != null) {
                        setState(() {
                          _selectedCustomDateRange = range;
                        });
                      }
                    },
                    icon: const Icon(Icons.date_range, size: 18),
                    label: Text(_selectedCustomDateRange == null 
                      ? 'Select Date Range' 
                      : '${_selectedCustomDateRange!.start.toString().split(' ')[0]} to ${_selectedCustomDateRange!.end.toString().split(' ')[0]}'),
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0078D4),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime.now().subtract(const Duration(days: 365)),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (date != null) {
                            if (!_selectedMultipleDates.any((d) => d.year == date.year && d.month == date.month && d.day == date.day)) {
                              setState(() {
                                _selectedMultipleDates.add(date);
                              });
                            }
                          }
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Add Specific Date'),
                      ),
                      if (_selectedMultipleDates.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: _selectedMultipleDates.map((d) {
                            final dStr = "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
                            return Chip(
                              label: Text(dStr),
                              onDeleted: () {
                                setState(() {
                                  _selectedMultipleDates.remove(d);
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                const SizedBox(height: 20),
                
                CheckboxListTile(
                  title: const Text('Early Check-In', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: _customEarlyEnabled
                    ? InkWell(
                        onTap: () => _showTimingConfigDialog(true, isDark),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                            'Timing: ${_customEarlyStart.format(context)} - ${_customEarlyEnd.format(context)}\nTap to change settings',
                            style: const TextStyle(color: Color(0xFF0078D4), fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                      )
                    : const Text('Disabled', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  value: _customEarlyEnabled,
                  activeColor: const Color(0xFF0078D4),
                  onChanged: (val) {
                    setState(() {
                      _customEarlyEnabled = val ?? false;
                    });
                    if (_customEarlyEnabled) {
                      _showTimingConfigDialog(true, isDark);
                    }
                  },
                ),
                const SizedBox(height: 10),
                
                CheckboxListTile(
                  title: const Text('Late Check-Out', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: _customLateEnabled
                    ? InkWell(
                        onTap: () => _showTimingConfigDialog(false, isDark),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                            'Timing: ${_customLateStart.format(context)} - ${_customLateEnd.format(context)}\nTap to change settings',
                            style: const TextStyle(color: Color(0xFF0078D4), fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                      )
                    : const Text('Disabled', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  value: _customLateEnabled,
                  activeColor: const Color(0xFF0078D4),
                  onChanged: (val) {
                    setState(() {
                      _customLateEnabled = val ?? false;
                    });
                    if (_customLateEnabled) {
                      _showTimingConfigDialog(false, isDark);
                    }
                  },
                ),
                
                const SizedBox(height: 24),
                Center(
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _savingCustomDates ? null : _saveCustomDates,
                      icon: _savingCustomDates 
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save, color: Colors.white, size: 18),
                      label: const Text('Apply Rules to Dates', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0078D4),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 24),
        Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: isDark ? const Color(0xFF202020) : const Color(0xFFF9F9F9),
          shape: RoundedRectangleBorder(
            side: isMobile ? BorderSide.none : BorderSide(color: isDark ? const Color(0xFF3F3F3F) : const Color(0xFFE5E5E5)),
            borderRadius: isMobile ? BorderRadius.zero : BorderRadius.circular(8),
          ),
          child: ExpansionTile(
            leading: const Icon(Icons.calendar_month, color: Color(0xFF0078D4)),
            title: const Text(
              'Show Calendar View',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text('View and interact with dates on a monthly calendar schedule.'),
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: _buildCalendarWidget(isDark),
              ),
            ],
          ),
        ),
      ],
    );
  }



  void _showTimingConfigDialog(bool isEarly, bool isDark) {
    TimeOfDay tempStart = isEarly ? _customEarlyStart : _customLateStart;
    TimeOfDay tempEnd = isEarly ? _customEarlyEnd : _customLateEnd;
    int tempDur = isEarly ? _customEarlyDuration : _customLateDuration;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateLocal) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              title: Text(
                isEarly ? 'Configure Early Check-In' : 'Configure Late Check-Out',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              content: SizedBox(
                width: MediaQuery.of(context).size.width < 600 ? double.infinity : 450,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (MediaQuery.of(context).size.width < 600) ...[
                      _buildTimePickerTile('Start Time', tempStart, () async {
                        final picked = await showTimePicker(context: context, initialTime: tempStart);
                        if (picked != null) {
                          setStateLocal(() => tempStart = picked);
                        }
                      }, isDark),
                      const SizedBox(height: 12),
                      _buildTimePickerTile('End Time', tempEnd, () async {
                        final picked = await showTimePicker(context: context, initialTime: tempEnd);
                        if (picked != null) {
                          setStateLocal(() => tempEnd = picked);
                        }
                      }, isDark),
                    ] else ...[
                      Row(
                        children: [
                          Expanded(
                            child: _buildTimePickerTile('Start Time', tempStart, () async {
                              final picked = await showTimePicker(context: context, initialTime: tempStart);
                              if (picked != null) {
                                setStateLocal(() => tempStart = picked);
                              }
                            }, isDark),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildTimePickerTile('End Time', tempEnd, () async {
                              final picked = await showTimePicker(context: context, initialTime: tempEnd);
                              if (picked != null) {
                                setStateLocal(() => tempEnd = picked);
                              }
                            }, isDark),
                          ),
                        ],
                      ),
                    ]
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0078D4),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  onPressed: () {
                    setState(() {
                      if (isEarly) {
                        _customEarlyStart = tempStart;
                        _customEarlyEnd = tempEnd;
                        _customEarlyDuration = tempDur;
                      } else {
                        _customLateStart = tempStart;
                        _customLateEnd = tempEnd;
                        _customLateDuration = tempDur;
                      }
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildTimePickerTile(String label, TimeOfDay time, VoidCallback onTap, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
        ),
        const SizedBox(height: 6),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark ? const Color(0xFF3F3F3F) : const Color(0xFFE5E5E5),
                  width: 1.0,
                ),
                color: isDark ? const Color(0xFF202020) : const Color(0xFFF9F9F9),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.access_time_rounded,
                    color: Color(0xFF0078D4),
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      time.format(context),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.edit_rounded,
                    color: Colors.grey[400],
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
  Widget _buildHistoryTab(bool isDark) {
    if (_loadingHistory) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF0078D4)));
    }

    if (_historyError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
              const SizedBox(height: 16),
              Text(
                _historyError!,
                style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadHistory,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0078D4),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_history.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_toggle_off_rounded, size: 56, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text('No CCL points earned yet.', style: TextStyle(color: isDark ? Colors.white54 : Colors.black45)),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _loadHistory,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh'),
            ),
          ],
        ),
      );
    }

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.96, end: 1.0),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      builder: (context, val, child) {
        return Opacity(
          opacity: val,
          child: Transform.translate(
            offset: Offset(0, 10 * (1.0 - val)),
            child: child,
          ),
        );
      },
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _history.length,
        separatorBuilder: (context, index) => Divider(height: 1, color: isDark ? const Color(0xFF3F3F3F) : const Color(0xFFE5E5E5)),
        itemBuilder: (context, idx) {
          final item = _history[idx];
          final isEarly = item['slot_type'] == 'early_check_in';
          return ListTile(
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isEarly ? const Color(0xFF107C41).withValues(alpha: 0.1) : const Color(0xFFD83B01).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(
                isEarly ? Icons.login : Icons.logout,
                color: isEarly ? const Color(0xFF107C41) : const Color(0xFFD83B01),
                size: 18,
              ),
            ),
            title: Text(item['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            subtitle: Text(
              '${item['reg_no']} • ${item['dept']}\nEarned on ${item['date']} at ${item['time']}',
              style: const TextStyle(fontSize: 11),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '+${item['earned_points']} EL',
                  style: const TextStyle(color: Color(0xFF107C41), fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  isEarly ? 'Early Check-In' : 'Late Check-Out',
                  style: const TextStyle(fontSize: 9, color: Colors.grey),
                )
              ],
            ),
          );
        },
      ),
    );
  }


  Widget _buildCalendarWidget(bool isDark) {
    final year = _calendarMonth.year;
    final month = _calendarMonth.month;
    final daysInMonth = _getDaysInMonth(year, month);
    final firstDayOffset = DateTime(year, month, 1).weekday % 7;
    
    final daysOfWeek = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () {
                setState(() {
                  _calendarMonth = DateTime(year, month - 1);
                });
              },
            ),
            Text(
              '${_monthNames[month - 1]} $year',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () {
                setState(() {
                  _calendarMonth = DateTime(year, month + 1);
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: daysOfWeek.map((day) => Expanded(
            child: Center(
              child: Text(
                day,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
            ),
          )).toList(),
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
          ),
          itemCount: daysInMonth + firstDayOffset,
          itemBuilder: (context, index) {
            if (index < firstDayOffset) {
              return const SizedBox.shrink();
            }
            final day = index - firstDayOffset + 1;
            final dateStr = '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
            
            final customRule = _customDatesMap[dateStr];
            
            final targetDate = DateTime(year, month, day);
            final isSelected = !_isRangeMode && _selectedMultipleDates.any((d) => d.year == targetDate.year && d.month == targetDate.month && d.day == targetDate.day);
            
            final hasRule = customRule != null;
            final isToday = DateTime.now().year == year && 
                            DateTime.now().month == month && 
                            DateTime.now().day == day;
                            
            bool early = hasRule && (customRule['early_enabled'] ?? false);
            bool late = hasRule && (customRule['late_enabled'] ?? false);
            
            return InkWell(
              onTap: () {
                if (hasRule) {
                  _showCustomRuleDetailsDialog(customRule, isDark);
                } else {
                  setState(() {
                    _isRangeMode = false;
                    final existingIdx = _selectedMultipleDates.indexWhere((d) => d.year == targetDate.year && d.month == targetDate.month && d.day == targetDate.day);
                    if (existingIdx != -1) {
                      _selectedMultipleDates.removeAt(existingIdx);
                      _showSnackBar('Deselected $dateStr.', const Color(0xFF0078D4));
                    } else {
                      _selectedMultipleDates.add(targetDate);
                      _showSnackBar('Selected $dateStr to configure below.', const Color(0xFF0078D4));
                    }
                  });
                }
              },
              borderRadius: BorderRadius.circular(4),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isSelected
                      ? const Color(0xFF0078D4)
                      : (hasRule 
                          ? const Color(0xFF0078D4).withValues(alpha: 0.5) 
                          : (isToday ? const Color(0xFF0078D4).withValues(alpha: 0.3) : Colors.transparent)),
                    width: 1.5,
                  ),
                  color: isSelected
                    ? const Color(0xFF0078D4).withValues(alpha: 0.2)
                    : (hasRule
                        ? const Color(0xFF0078D4).withValues(alpha: 0.1)
                        : (isToday ? const Color(0xFF0078D4).withValues(alpha: 0.05) : Colors.transparent)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$day',
                      style: TextStyle(
                        fontWeight: isSelected || hasRule || isToday ? FontWeight.bold : FontWeight.normal,
                        color: isSelected || hasRule 
                          ? const Color(0xFF0078D4)
                          : (isDark ? Colors.white : Colors.black87),
                      ),
                    ),
                    if (hasRule) ...[
                      const SizedBox(height: 2),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (early)
                            Container(
                              width: 5,
                              height: 5,
                              decoration: const BoxDecoration(
                                color: Color(0xFF107C41),
                                shape: BoxShape.circle,
                              ),
                            ),
                          if (early && late) const SizedBox(width: 2),
                          if (late)
                            Container(
                              width: 5,
                              height: 5,
                              decoration: const BoxDecoration(
                                color: Color(0xFFD83B01),
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  int _getDaysInMonth(int year, int month) {
    if (month == 12) {
      return DateTime(year + 1, 1, 0).day;
    }
    return DateTime(year, month + 1, 0).day;
  }

  static const List<String> _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  void _showCustomRuleDetailsDialog(dynamic customRule, bool isDark) {
    final String dateStr = customRule['date'];
    showDialog(
      context: context,
      builder: (context) {
        bool earlyEnabled = customRule['early_enabled'] ?? false;
        TimeOfDay earlyStart = _parseTimeStr(customRule['early_start'] ?? '07:00');
        TimeOfDay earlyEnd = _parseTimeStr(customRule['early_end'] ?? '08:00');
        int earlyDur = customRule['early_duration'] ?? 60;
        
        bool lateEnabled = customRule['late_enabled'] ?? false;
        TimeOfDay lateStart = _parseTimeStr(customRule['late_start'] ?? '17:00');
        TimeOfDay lateEnd = _parseTimeStr(customRule['late_end'] ?? '18:00');
        int lateDur = customRule['late_duration'] ?? 60;
        
        return StatefulBuilder(
          builder: (context, setStateLocal) {
            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Rules for $dateStr',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CheckboxListTile(
                      title: const Text('Early Check-In', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      value: earlyEnabled,
                      activeColor: const Color(0xFF0078D4),
                      onChanged: (val) {
                        setStateLocal(() {
                          earlyEnabled = val ?? false;
                        });
                      },
                    ),
                    if (earlyEnabled)
                      Builder(
                        builder: (context) {
                          final isMobile = MediaQuery.of(context).size.width < 600;
                          final children = [
                            _buildTimePickerTile('Start', earlyStart, () async {
                              final picked = await showTimePicker(context: context, initialTime: earlyStart);
                              if (picked != null) {
                                setStateLocal(() {
                                  earlyStart = picked;
                                });
                              }
                            }, isDark),
                            const SizedBox(width: 8, height: 8),
                            _buildTimePickerTile('End', earlyEnd, () async {
                              final picked = await showTimePicker(context: context, initialTime: earlyEnd);
                              if (picked != null) {
                                setStateLocal(() {
                                  earlyEnd = picked;
                                });
                              }
                            }, isDark),
                          ];
                          return isMobile
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: children,
                                )
                              : Row(
                                  children: [
                                    Expanded(child: children[0]),
                                    children[1],
                                    Expanded(child: children[2]),
                                  ],
                                );
                        },
                      ),
                    const Divider(height: 24),
                    CheckboxListTile(
                      title: const Text('Late Check-Out', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      value: lateEnabled,
                      activeColor: const Color(0xFF0078D4),
                      onChanged: (val) {
                        setStateLocal(() {
                          lateEnabled = val ?? false;
                        });
                      },
                    ),
                    if (lateEnabled)
                      Builder(
                        builder: (context) {
                          final isMobile = MediaQuery.of(context).size.width < 600;
                          final children = [
                            _buildTimePickerTile('Start', lateStart, () async {
                              final picked = await showTimePicker(context: context, initialTime: lateStart);
                              if (picked != null) {
                                setStateLocal(() {
                                  lateStart = picked;
                                });
                              }
                            }, isDark),
                            const SizedBox(width: 8, height: 8),
                            _buildTimePickerTile('End', lateEnd, () async {
                              final picked = await showTimePicker(context: context, initialTime: lateEnd);
                              if (picked != null) {
                                setStateLocal(() {
                                  lateEnd = picked;
                                });
                              }
                            }, isDark),
                          ];
                          return isMobile
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: children,
                                )
                              : Row(
                                  children: [
                                    Expanded(child: children[0]),
                                    children[1],
                                    Expanded(child: children[2]),
                                  ],
                                );
                        },
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _deleteCustomDate(dateStr);
                  },
                  icon: const Icon(Icons.delete, color: Colors.red),
                  label: const Text('Delete', style: TextStyle(color: Colors.red)),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _updateSingleCustomDate(
                      dateStr,
                      earlyEnabled,
                      earlyStart,
                      earlyEnd,
                      earlyDur,
                      lateEnabled,
                      lateStart,
                      lateEnd,
                      lateDur,
                    );
                  },
                  icon: const Icon(Icons.save),
                  label: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Self-contained Leave Balances Tab Widget
// Manages its own data loading so it is never affected by parent widget timing
// ─────────────────────────────────────────────────────────────────────────────
class _CclLeaveBalancesTab extends StatefulWidget {
  final String token;
  const _CclLeaveBalancesTab({required this.token});

  @override
  State<_CclLeaveBalancesTab> createState() => _CclLeaveBalancesTabState();
}

class _CclLeaveBalancesTabState extends State<_CclLeaveBalancesTab> {
  List<dynamic> _balances = [];
  List<dynamic> _filteredBalances = [];
  bool _loading = true;
  String? _error;
  String _search = '';
  String _deptFilter = 'All';
  List<String> _departments = ['All'];
  bool _syncing = false;
  late VoidCallback _leaveListener;
  String? _elExpiryDate;

  Future<void> _fetchELSettings() async {
    try {
      final res = await http.get(
        Uri.parse('${CollegeIPConfig.defaultURL}/admin/leave-settings'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data['success'] == true && data['settings'] != null) {
          setState(() {
            final fetched = data['settings']['el_expiry_date'];
            if (fetched != null && fetched.toString().isNotEmpty) {
              _elExpiryDate = fetched;
            } else {
              final default3m = DateTime.now().add(const Duration(days: 90));
              _elExpiryDate = '${default3m.year}-${default3m.month.toString().padLeft(2, '0')}-${default3m.day.toString().padLeft(2, '0')}';
            }
          });
        }
      }
    } catch (e) {
      print('Error fetching EL settings: $e');
    }
  }

  Future<void> _updateELExpiryDate(String? newDate) async {
    try {
      final res = await http.post(
        Uri.parse('${CollegeIPConfig.defaultURL}/admin/leave-settings'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
        body: json.encode({'el_expiry_date': newDate ?? ''}),
      );
      if (res.statusCode == 200) {
        setState(() {
          _elExpiryDate = newDate;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(newDate != null && newDate.isNotEmpty
                  ? 'EL Expiry Date set to $newDate'
                  : 'EL Expiry Date cleared'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating EL expiry: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _leaveListener = () { if (mounted) _load(); };
    LeaveBalanceNotifier.instance.addListener(_leaveListener);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _load();
        _fetchELSettings();
      }
    });
  }

  @override
  void dispose() {
    LeaveBalanceNotifier.instance.removeListener(_leaveListener);
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final response = await http.get(
        Uri.parse('${CollegeIPConfig.defaultURL}/admin/ccl/balances'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      ).timeout(const Duration(seconds: 20));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        if (body['success'] == true) {
          final data = List<dynamic>.from(body['data'] ?? []);
          final depts = <String>{'All'};
          for (final b in data) {
            final d = b['dept']?.toString().trim() ?? '';
            if (d.isNotEmpty) depts.add(d);
          }
          setState(() {
            _balances = data;
            _departments = depts.toList()..sort();
            _error = null;
            _applyFilter();
          });
        } else {
          setState(() => _error = body['detail'] ?? 'Server returned failure');
        }
      } else {
        String msg;
        try {
          msg = json.decode(response.body)['detail'] ?? 'Server error ${response.statusCode}';
        } catch (_) {
          msg = 'Server error ${response.statusCode}';
        }
        setState(() => _error = msg);
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not connect: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sync() async {
    if (!mounted) return;
    setState(() => _syncing = true);
    try {
      final response = await http.post(
        Uri.parse('${CollegeIPConfig.defaultURL}/admin/ccl/sync'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
      ).timeout(const Duration(seconds: 30));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(body['message'] ?? 'Balances synced!'),
            backgroundColor: Colors.green,
          ));
        }
        LeaveBalanceNotifier.instance.notifyBalanceChanged();
        await _load();
      } else {
        String msg;
        try { msg = json.decode(response.body)['detail'] ?? 'Sync failed'; }
        catch (_) { msg = 'Sync failed'; }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  void _applyFilter() {
    final q = _search.toLowerCase();
    setState(() {
      _filteredBalances = _balances.where((b) {
        final name = b['name']?.toString().toLowerCase() ?? '';
        final reg = b['reg_no']?.toString().toLowerCase() ?? '';
        final dept = b['dept']?.toString() ?? '';
        final matchSearch = q.isEmpty || name.contains(q) || reg.contains(q);
        final matchDept = _deptFilter == 'All' || dept == _deptFilter;
        return matchSearch && matchDept;
      }).toList();
    });
  }

  Future<void> _showAdjust(Map item) async {
    final ctrl = TextEditingController(text: item['balance']?.toString() ?? '0');
    final isDark = Theme.of(context).brightness == Brightness.dark;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2D2D2D) : Colors.white,
        title: Text('Adjust Balance — ${item['name']}',
            style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'New CCL Balance',
            labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
            border: const OutlineInputBorder(),
          ),
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final newBal = double.tryParse(ctrl.text);
              if (newBal == null) return;
              try {
                final res = await http.post(
                  Uri.parse('${CollegeIPConfig.defaultURL}/admin/ccl/adjust'),
                  headers: {
                    'Content-Type': 'application/json',
                    'Authorization': 'Bearer ${widget.token}',
                  },
                  body: json.encode({
                    'reg_no': item['reg_no'],
                    'new_balance': newBal,
                    'reason': 'Manual admin adjustment',
                  }),
                );
                if (!mounted) return;
                if (res.statusCode == 200) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Balance updated!'), backgroundColor: Colors.green,
                  ));
                  LeaveBalanceNotifier.instance.notifyBalanceChanged();
                  _load();
                } else {
                  String msg;
                  try { msg = json.decode(res.body)['detail'] ?? 'Failed'; }
                  catch (_) { msg = 'Failed'; }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(msg), backgroundColor: Colors.red),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0078D4), foregroundColor: Colors.white,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _showDeleteConfirm(Map item) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2D2D2D) : Colors.white,
        title: Text('Delete Record',
            style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16, fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to delete/reset the Compensatory Casual Leave record for ${item['name']}? This will remove their current balance entry.',
            style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final res = await http.delete(
                  Uri.parse('${CollegeIPConfig.defaultURL}/admin/ccl/balances/${item['reg_no']}'),
                  headers: {'Authorization': 'Bearer ${widget.token}'},
                );
                if (!mounted) return;
                if (res.statusCode == 200) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Record deleted/reset successfully!'), backgroundColor: Colors.green,
                  ));
                  LeaveBalanceNotifier.instance.notifyBalanceChanged();
                  _load();
                } else {
                  String msg;
                  try { msg = json.decode(res.body)['detail'] ?? 'Failed'; }
                  catch (_) { msg = 'Failed'; }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(msg), backgroundColor: Colors.red),
                  );
                }
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF202020) : const Color(0xFFF3F3F3);

    return Container(
      color: bg,
      child: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF0078D4)))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline, size: 52, color: Colors.red[300]),
                        const SizedBox(height: 16),
                        Text(_error!, textAlign: TextAlign.center,
                            style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0078D4),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // ── Search + Filter + Sync ─────────────────────────
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            constraints: const BoxConstraints(maxWidth: 320),
                            child: TextField(
                              onChanged: (v) {
                                _search = v;
                                _applyFilter();
                              },
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                                hintText: 'Search by name or ID…',
                                filled: true,
                                fillColor: isDark ? const Color(0xFF2D2D2D) : Colors.white,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                      color: isDark ? const Color(0xFF3F3F3F) : const Color(0xFFE5E5E5)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                      color: isDark ? const Color(0xFF3F3F3F) : const Color(0xFFE5E5E5)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(color: Color(0xFF0078D4), width: 1.5),
                                ),
                                contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                              ),
                            ),
                          ),
                          // Dept filter
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF2D2D2D) : Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isDark ? const Color(0xFF3F3F3F) : const Color(0xFFE5E5E5),
                              ),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _departments.contains(_deptFilter) ? _deptFilter : 'All',
                                dropdownColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black87,
                                  fontWeight: FontWeight.w600,
                                ),
                                icon: const Icon(Icons.filter_list_rounded, color: Colors.grey),
                                items: _departments
                                    .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                                    .toList(),
                                onChanged: (v) {
                                  if (v != null) {
                                    setState(() => _deptFilter = v);
                                    _applyFilter();
                                  }
                                },
                              ),
                            ),
                          ),
                          // Sync button
                          ElevatedButton.icon(
                            onPressed: _syncing ? null : _sync,
                            icon: _syncing
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.sync, size: 18),
                            label: Text(_syncing ? 'Syncing...' : 'Sync Balances'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0078D4),
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: Colors.grey,
                            ),
                          ),
                          // Set EL Expiry Date button
                          OutlinedButton.icon(
                            onPressed: () async {
                              final current = _elExpiryDate != null && _elExpiryDate!.isNotEmpty
                                  ? DateTime.tryParse(_elExpiryDate!) ?? DateTime.now()
                                  : DateTime.now();
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: current,
                                firstDate: DateTime.now().subtract(const Duration(days: 30)),
                                lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
                                helpText: 'SELECT EL EXPIRY DATE',
                              );
                              if (picked != null) {
                                final dateStr = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                                await _updateELExpiryDate(dateStr);
                              }
                            },
                            icon: const Icon(Icons.event_rounded, size: 18, color: Color(0xFF0078D4)),
                            label: Text(
                              _elExpiryDate != null && _elExpiryDate!.isNotEmpty
                                  ? 'Expires: $_elExpiryDate'
                                  : 'Set Expiry Date',
                              style: const TextStyle(color: Color(0xFF0078D4), fontWeight: FontWeight.bold),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFF0078D4)),
                            ),
                          ),
                          if (_elExpiryDate != null && _elExpiryDate!.isNotEmpty) ...[
                            IconButton(
                              icon: const Icon(Icons.clear, size: 18, color: Colors.grey),
                              tooltip: 'Clear Expiry Date',
                              onPressed: () => _updateELExpiryDate(''),
                            ),
                          ],
                          // Expire EL button
                          OutlinedButton.icon(
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Expire All Earned Leave Balances?'),
                                  content: const Text('This will set all Earned Leave (CCL) balances to 0.0 immediately.'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                    ElevatedButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                      child: const Text('Expire All EL', style: TextStyle(color: Colors.white)),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                try {
                                  final res = await http.post(
                                    Uri.parse('${CollegeIPConfig.defaultURL}/admin/el/expire'),
                                    headers: {'Authorization': 'Bearer ${widget.token}'},
                                  );
                                  if (mounted && res.statusCode == 200) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('All Earned Leave balances expired successfully'), backgroundColor: Colors.red),
                                    );
                                    _load();
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Error expiring EL: $e'), backgroundColor: Colors.red),
                                    );
                                  }
                                }
                              }
                            },
                            icon: const Icon(Icons.timer_off_rounded, size: 18, color: Colors.red),
                            label: const Text('Expire EL Now', style: TextStyle(color: Colors.red)),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.red),
                            ),
                          ),


                        ],
                      ),
                      const SizedBox(height: 16),
                      // ── List ──────────────────────────────────────────
                      Expanded(
                        child: _filteredBalances.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.account_balance_wallet_outlined,
                                        size: 56, color: Colors.grey[400]),
                                    const SizedBox(height: 12),
                                    Text(
                                      _balances.isEmpty
                                          ? 'No staff records found'
                                          : 'No results match your search',
                                      style: TextStyle(
                                          color: isDark ? Colors.white54 : Colors.black45),
                                    ),
                                    const SizedBox(height: 16),
                                    TextButton.icon(
                                      onPressed: _load,
                                      icon: const Icon(Icons.refresh, size: 18),
                                      label: const Text('Reload'),
                                    ),
                                  ],
                                ),
                              )
                            : Container(
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF2D2D2D) : Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: isDark
                                          ? const Color(0xFF3F3F3F)
                                          : const Color(0xFFE5E5E5)),
                                  boxShadow: [
                                    if (!isDark)
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.04),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      )
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: RefreshIndicator(
                                    onRefresh: _load,
                                    child: ListView.separated(
                                      physics: const AlwaysScrollableScrollPhysics(),
                                      itemCount: _filteredBalances.length,
                                      separatorBuilder: (_, __) => Divider(
                                        height: 1,
                                        color: isDark
                                            ? const Color(0xFF3F3F3F)
                                            : const Color(0xFFE5E5E5),
                                      ),
                                      itemBuilder: (ctx, i) {
                                        final item = _filteredBalances[i];
                                        final bal = (item['balance'] as num?)?.toDouble() ?? 0.0;
                                        final balColor = bal > 0
                                            ? const Color(0xFF0078D4)
                                            : Colors.grey;
                                        return ListTile(
                                          contentPadding: const EdgeInsets.symmetric(
                                              horizontal: 16, vertical: 4),
                                          leading: CircleAvatar(
                                            backgroundColor:
                                                const Color(0xFF0078D4).withValues(alpha: 0.12),
                                            child: Text(
                                              (item['name']?.toString().isNotEmpty == true
                                                      ? item['name'].toString()[0]
                                                      : '?')
                                                  .toUpperCase(),
                                              style: const TextStyle(
                                                  color: Color(0xFF0078D4),
                                                  fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                          title: Text(
                                            item['name'] ?? '—',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: isDark ? Colors.white : Colors.black87,
                                            ),
                                          ),
                                          subtitle: Text(
                                            '${item['reg_no']} · ${item['dept'] ?? '—'} · ${item['role'] ?? '—'}',
                                            style: TextStyle(
                                                color: isDark ? Colors.white54 : Colors.black45,
                                                fontSize: 12),
                                          ),
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                    horizontal: 10, vertical: 5),
                                                decoration: BoxDecoration(
                                                  color: balColor.withValues(alpha: 0.1),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  '${bal.toStringAsFixed(1)} EL',
                                                  style: TextStyle(
                                                    color: balColor,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.edit_outlined,
                                                    color: Color(0xFF0078D4), size: 20),
                                                tooltip: 'Adjust balance',
                                                onPressed: () => _showAdjust(
                                                    Map<String, dynamic>.from(item as Map)),
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.delete_outline_rounded,
                                                    color: Colors.red, size: 20),
                                                tooltip: 'Delete/Reset record',
                                                onPressed: () => _showDeleteConfirm(
                                                    Map<String, dynamic>.from(item as Map)),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
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
