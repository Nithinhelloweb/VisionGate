import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/features_service.dart';

class HolidayCalendarPage extends StatefulWidget {
  final String? token;
  final bool isAdmin;

  const HolidayCalendarPage({
    super.key,
    this.token,
    this.isAdmin = false,
  });

  @override
  State<HolidayCalendarPage> createState() => _HolidayCalendarPageState();
}

class _HolidayCalendarPageState extends State<HolidayCalendarPage> {
  bool _isLoading = false;
  List<Map<String, dynamic>> _holidays = [];
  String _selectedYear = '2026-2027';

  @override
  void initState() {
    super.initState();
    _loadHolidays();
  }

  Future<void> _loadHolidays() async {
    setState(() => _isLoading = true);
    final holidays = await FeaturesService.getHolidays(academicYear: _selectedYear);
    if (mounted) {
      setState(() {
        _holidays = holidays;
        _isLoading = false;
      });
    }
  }

  void _openAddHolidayDialog() {
    final dateController = TextEditingController(text: DateFormat('yyyy-MM-dd').format(DateTime.now()));
    final nameController = TextEditingController();
    String type = 'National';
    bool isOptional = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Add Academic Holiday', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: dateController,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: 'Holiday Date',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.calendar_today_rounded),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2024),
                          lastDate: DateTime(2030),
                        );
                        if (picked != null) {
                          setDialogState(() {
                            dateController.text = DateFormat('yyyy-MM-dd').format(picked);
                          });
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: 'Holiday Name',
                    hintText: 'e.g. Independence Day, Diwali',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: InputDecoration(
                    labelText: 'Holiday Classification',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),

                  items: const [
                    DropdownMenuItem(value: 'National', child: Text('National Holiday')),
                    DropdownMenuItem(value: 'State', child: Text('State Holiday')),
                    DropdownMenuItem(value: 'Institutional', child: Text('Institutional / College')),
                    DropdownMenuItem(value: 'Festival', child: Text('Festival Holiday')),
                  ],
                  onChanged: (v) => setDialogState(() => type = v ?? 'National'),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  title: const Text('Optional / Restricted Holiday'),
                  value: isOptional,
                  onChanged: (v) => setDialogState(() => isOptional = v ?? false),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) return;
                Navigator.pop(ctx);
                if (widget.token == null) return;
                setState(() => _isLoading = true);
                final ok = await FeaturesService.addHoliday(
                  widget.token!,
                  holidayDate: dateController.text,
                  holidayName: nameController.text.trim(),
                  holidayType: type,
                  isOptional: isOptional,
                  academicYear: _selectedYear,
                );
                setState(() => _isLoading = false);
                if (ok && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Holiday added to calendar.')),
                  );
                  _loadHolidays();
                }
              },
              child: const Text('Save Holiday'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Academic Holiday Calendar', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          DropdownButton<String>(
            value: _selectedYear,
            underline: const SizedBox(),
            items: const [
              DropdownMenuItem(value: '2025-2026', child: Text('2025-2026')),
              DropdownMenuItem(value: '2026-2027', child: Text('2026-2027')),
              DropdownMenuItem(value: '2027-2028', child: Text('2027-2028')),
            ],
            onChanged: (v) {
              if (v != null) {
                setState(() => _selectedYear = v);
                _loadHolidays();
              }
            },
          ),
          const SizedBox(width: 12),
        ],
      ),
      floatingActionButton: widget.isAdmin
          ? FloatingActionButton.extended(
              onPressed: _openAddHolidayDialog,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Holiday'),
            )
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _holidays.isEmpty
              ? const Center(child: Text('No academic holidays scheduled for this year.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _holidays.length,
                  itemBuilder: (ctx, i) {
                    final h = _holidays[i];
                    final holidayId = h['id'] as int?;
                    final isOpt = h['is_optional'] == true;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.12),
                          child: Icon(Icons.celebration_rounded, color: Theme.of(context).primaryColor),
                        ),
                        title: Text(h['holiday_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        subtitle: Text('Date: ${h['holiday_date']} • Type: ${h['holiday_type'] ?? 'National'}${isOpt ? ' (Optional)' : ''}'),
                        trailing: widget.isAdmin && holidayId != null
                            ? IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                                onPressed: () async {
                                  if (widget.token == null) return;
                                  final messenger = ScaffoldMessenger.of(context);
                                  final ok = await FeaturesService.deleteHoliday(widget.token!, holidayId);
                                  if (ok) {
                                    messenger.showSnackBar(
                                      const SnackBar(content: Text('Holiday removed.')),
                                    );
                                    _loadHolidays();
                                  }
                                },


                              )
                            : null,
                      ),
                    );
                  },
                ),
    );

  }
}
