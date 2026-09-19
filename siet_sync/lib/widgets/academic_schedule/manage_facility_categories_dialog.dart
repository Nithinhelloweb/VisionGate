import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../../config/college_ip_config.dart';

class ManageFacilityCategoriesDialog extends StatefulWidget {
  final String token;
  final VoidCallback? onCategoriesChanged;

  const ManageFacilityCategoriesDialog({
    super.key,
    required this.token,
    this.onCategoriesChanged,
  });

  static Future<void> show(
    BuildContext context, {
    required String token,
    VoidCallback? onCategoriesChanged,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ManageFacilityCategoriesDialog(
        token: token,
        onCategoriesChanged: onCategoriesChanged,
      ),
    );
  }

  @override
  State<ManageFacilityCategoriesDialog> createState() => _ManageFacilityCategoriesDialogState();
}

class _ManageFacilityCategoriesDialogState extends State<ManageFacilityCategoriesDialog> {
  List<Map<String, dynamic>> _categories = [];
  bool _isLoading = true;
  bool _isSaving = false;
  String _searchQuery = '';

  // Form State for Add / Edit
  bool _isEditing = false;
  String? _editingCategoryCode;
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _codeCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();
  String _selectedIcon = 'domain_rounded';
  String _selectedColorHex = '#2563EB';

  final List<Map<String, dynamic>> _availableIcons = [
    {'name': 'school_rounded', 'icon': Icons.school_rounded, 'label': 'Lecture Hall'},
    {'name': 'science_rounded', 'icon': Icons.science_rounded, 'label': 'Laboratory'},
    {'name': 'tv_rounded', 'icon': Icons.tv_rounded, 'label': 'Smart Room'},
    {'name': 'theater_comedy_rounded', 'icon': Icons.theater_comedy_rounded, 'label': 'Seminar Hall'},
    {'name': 'stadium_rounded', 'icon': Icons.stadium_rounded, 'label': 'Auditorium'},
    {'name': 'precision_manufacturing_rounded', 'icon': Icons.precision_manufacturing_rounded, 'label': 'Workshop'},
    {'name': 'menu_book_rounded', 'icon': Icons.menu_book_rounded, 'label': 'Tutorial Room'},
    {'name': 'groups_3_rounded', 'icon': Icons.groups_3_rounded, 'label': 'Conference'},
    {'name': 'biotech_rounded', 'icon': Icons.biotech_rounded, 'label': 'Bio / Chemistry Lab'},
    {'name': 'computer_rounded', 'icon': Icons.computer_rounded, 'label': 'Computing Center'},
    {'name': 'memory_rounded', 'icon': Icons.memory_rounded, 'label': 'Robotics / IoT'},
    {'name': 'lightbulb_rounded', 'icon': Icons.lightbulb_rounded, 'label': 'Innovation Hub'},
    {'name': 'local_library_rounded', 'icon': Icons.local_library_rounded, 'label': 'Library / Reading'},
    {'name': 'domain_rounded', 'icon': Icons.domain_rounded, 'label': 'Facility / Venue'},
  ];

  final List<String> _availableColors = [
    '#2563EB', '#8B5CF6', '#10B981', '#F59E0B', '#EC4899', '#EA580C', '#06B6D4', '#6366F1', '#4F46E5', '#EF4444', '#14B8A6'
  ];

  @override
  void initState() {
    super.initState();
    _fetchCategories();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Color _parseHexColor(dynamic hex) {
    if (hex == null || hex.toString().isEmpty) return const Color(0xFF2563EB);
    final clean = hex.toString().replaceAll('#', '').trim();
    if (clean.length == 6) {
      return Color(int.parse('FF$clean', radix: 16));
    }
    return const Color(0xFF2563EB);
  }

  IconData _getIconDataByName(String iconName) {
    final match = _availableIcons.firstWhere(
      (item) => item['name'] == iconName,
      orElse: () => {'icon': Icons.domain_rounded},
    );
    return match['icon'] as IconData;
  }

  Future<void> _fetchCategories() async {
    setState(() => _isLoading = true);
    try {
      final res = await http.get(
        Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/academics/facility-categories'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _categories = List<Map<String, dynamic>>.from(data['categories'] ?? []);
        });
      }
    } catch (e) {
      debugPrint("Error fetching facility categories: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _resetForm() {
    setState(() {
      _isEditing = false;
      _editingCategoryCode = null;
      _nameCtrl.clear();
      _codeCtrl.clear();
      _descCtrl.clear();
      _selectedIcon = 'domain_rounded';
      _selectedColorHex = '#2563EB';
    });
  }

  void _startEdit(Map<String, dynamic> cat) {
    setState(() {
      _isEditing = true;
      _editingCategoryCode = cat['category_code'] ?? '';
      _nameCtrl.text = cat['category_name'] ?? '';
      _codeCtrl.text = cat['category_code'] ?? '';
      _descCtrl.text = cat['description'] ?? '';
      _selectedIcon = cat['icon_name'] ?? 'domain_rounded';
      _selectedColorHex = cat['color_hex'] ?? '#2563EB';
    });
  }

  Future<void> _saveCategory() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _showToast('Category name is required.', isError: true);
      return;
    }

    var code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) {
      code = name.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
    }

    setState(() => _isSaving = true);
    try {
      final payload = {
        'category_name': name,
        'category_code': code,
        'icon_name': _selectedIcon,
        'color_hex': _selectedColorHex,
        'description': _descCtrl.text.trim(),
      };

      final http.Response res;
      if (_isEditing && _editingCategoryCode != null) {
        res = await http.put(
          Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/academics/facility-categories/$_editingCategoryCode'),
          headers: {
            'Authorization': 'Bearer ${widget.token}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(payload),
        );
      } else {
        res = await http.post(
          Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/academics/facility-categories'),
          headers: {
            'Authorization': 'Bearer ${widget.token}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(payload),
        );
      }

      if (res.statusCode == 200) {
        _showToast(_isEditing ? 'Facility Category updated!' : 'New Facility Category created!', isError: false);
        _resetForm();
        await _fetchCategories();
        widget.onCategoriesChanged?.call();
      } else {
        final err = jsonDecode(res.body);
        _showToast(err['detail'] ?? 'Failed to save category.', isError: true);
      }
    } catch (e) {
      _showToast('Network error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _confirmDeleteCategory(Map<String, dynamic> cat) async {
    final code = cat['category_code'] ?? '';
    final name = cat['category_name'] ?? code;
    final venueCount = cat['venue_count'] ?? 0;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.delete_forever_rounded, color: Colors.redAccent),
            const SizedBox(width: 8),
            const Text('Delete Facility Category'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to delete category "$name" ($code)?'),
            if (venueCount > 0) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.amber.shade800, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$venueCount active venues are currently assigned to this category. The category will be safely deactivated.',
                        style: TextStyle(color: Colors.amber.shade900, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Category'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final res = await http.delete(
          Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/academics/facility-categories/$code'),
          headers: {'Authorization': 'Bearer ${widget.token}'},
        );
        if (res.statusCode == 200) {
          _showToast('Category "$name" removed successfully.', isError: false);
          await _fetchCategories();
          widget.onCategoriesChanged?.call();
        }
      } catch (e) {
        _showToast('Error deleting category: $e', isError: true);
      }
    }
  }

  Future<void> _resetCleanSlate() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clean Slate: Purge Preset Categories'),
        content: const Text(
          'This will remove any legacy pre-seeded default categories, leaving only custom facilities explicitly created by you in the database. Proceed?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Purge Legacy Presets'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final res = await http.post(
          Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/academics/facility-categories/reset-clean'),
          headers: {'Authorization': 'Bearer ${widget.token}'},
        );
        if (res.statusCode == 200) {
          _showToast('Legacy preset categories purged.', isError: false);
          await _fetchCategories();
          widget.onCategoriesChanged?.call();
        }
      } catch (e) {
        _showToast('Error resetting categories: $e', isError: true);
      }
    }
  }

  void _showToast(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: isError ? Colors.redAccent : const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const primaryBlue = Color(0xFF2563EB);
    final currentColor = _parseHexColor(_selectedColorHex);

    final filteredCategories = _categories.where((c) {
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.trim().toLowerCase();
      final name = (c['category_name'] ?? '').toString().toLowerCase();
      final code = (c['category_code'] ?? '').toString().toLowerCase();
      final desc = (c['description'] ?? '').toString().toLowerCase();
      return name.contains(q) || code.contains(q) || desc.contains(q);
    }).toList();

    final isMobile = MediaQuery.of(context).size.width < 640;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(isMobile ? 16 : 24)),
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      insetPadding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 24, vertical: isMobile ? 12 : 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960, maxHeight: 720),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Scaffold(
            backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
            appBar: AppBar(
              backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
              elevation: 0,
              leading: const Padding(
                padding: EdgeInsets.all(12),
                child: Icon(Icons.domain_verification_rounded, color: primaryBlue),
              ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Campus Facility & Category Manager',
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Text(
                    '100% Database-Driven Infrastructure • Create, Edit & Delete Facilities',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              ),
              actions: [
                OutlinedButton.icon(
                  onPressed: _resetCleanSlate,
                  icon: const Icon(Icons.cleaning_services_rounded, size: 14, color: Colors.redAccent),
                  label: const Text('Clean Slate', style: TextStyle(fontSize: 11, color: Colors.redAccent)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
                const SizedBox(width: 8),
              ],
            ),
            body: Row(
              children: [
                // -------------------------------------------------------------
                // LEFT SIDE: Category Inventory List & Search
                // -------------------------------------------------------------
                Expanded(
                  flex: 5,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border(right: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade200)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Search & Count Header
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                decoration: InputDecoration(
                                  hintText: 'Search facilities by title or code...',
                                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  isDense: true,
                                ),
                                onChanged: (v) => setState(() => _searchQuery = v),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.refresh_rounded, size: 20),
                              tooltip: 'Refresh Categories',
                              onPressed: _fetchCategories,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Count summary
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Active Facilities in DB (${filteredCategories.length})',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey.shade600),
                            ),
                            if (_isEditing)
                              TextButton(
                                onPressed: _resetForm,
                                child: const Text('+ New Facility', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // List Content
                        Expanded(
                          child: _isLoading
                              ? const Center(child: CircularProgressIndicator())
                              : filteredCategories.isEmpty
                                  ? Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.domain_disabled_rounded, size: 48, color: Colors.grey.shade400),
                                          const SizedBox(height: 8),
                                          const Text('No Facilities in Database', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                          const SizedBox(height: 4),
                                          Text('Use the form on the right to create your first facility category.', style: TextStyle(fontSize: 11, color: Colors.grey.shade500), textAlign: TextAlign.center),
                                        ],
                                      ),
                                    )
                                  : ListView.separated(
                                      itemCount: filteredCategories.length,
                                      separatorBuilder: (ctx, idx) => const SizedBox(height: 8),
                                      itemBuilder: (ctx, i) {
                                        final cat = filteredCategories[i];
                                        final code = cat['category_code'] ?? '';
                                        final name = cat['category_name'] ?? code;
                                        final iconName = cat['icon_name'] ?? 'domain_rounded';
                                        final color = _parseHexColor(cat['color_hex']);
                                        final desc = (cat['description'] ?? '').toString();
                                        final venueCount = cat['venue_count'] ?? 0;
                                        final isSel = _isEditing && _editingCategoryCode == code;

                                        return Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: isSel
                                                ? primaryBlue.withValues(alpha: 0.1)
                                                : (isDark ? const Color(0xFF1E293B) : Colors.white),
                                            borderRadius: BorderRadius.circular(14),
                                            border: Border.all(
                                              color: isSel ? primaryBlue : (isDark ? Colors.white12 : Colors.grey.shade200),
                                              width: isSel ? 1.5 : 1,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color: color.withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(10),
                                                ),
                                                child: Icon(_getIconDataByName(iconName), color: color, size: 20),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Flexible(
                                                          child: Text(
                                                            name,
                                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                                            maxLines: 1,
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                        ),
                                                        const SizedBox(width: 6),
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                                          decoration: BoxDecoration(
                                                            color: Colors.grey.shade200,
                                                            borderRadius: BorderRadius.circular(6),
                                                          ),
                                                          child: Text(code, style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Colors.black87)),
                                                        ),
                                                      ],
                                                    ),
                                                    if (desc.isNotEmpty) ...[
                                                      const SizedBox(height: 2),
                                                      Text(desc, style: TextStyle(fontSize: 11, color: Colors.grey.shade500), maxLines: 1, overflow: TextOverflow.ellipsis),
                                                    ],
                                                    const SizedBox(height: 4),
                                                    Row(
                                                      children: [
                                                        Icon(Icons.meeting_room_outlined, size: 13, color: Colors.grey.shade600),
                                                        const SizedBox(width: 4),
                                                        Text('$venueCount Venues Registered', style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.edit_outlined, size: 18),
                                                tooltip: 'Edit Facility',
                                                onPressed: () => _startEdit(cat),
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                                                tooltip: 'Delete Facility',
                                                onPressed: () => _confirmDeleteCategory(cat),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                        ),
                      ],
                    ),
                  ),
                ),

                // -------------------------------------------------------------
                // RIGHT SIDE: Create / Edit Facility Form
                // -------------------------------------------------------------
                Expanded(
                  flex: 6,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: currentColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(_getIconDataByName(_selectedIcon), color: currentColor, size: 22),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _isEditing ? 'Edit Facility Category' : 'Register New Facility',
                                    style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  Text(
                                    _isEditing ? 'Update category code, icon, color & description' : 'Define custom campus facility category stored in database',
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),

                          // Facility Name Input
                          TextField(
                            controller: _nameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Facility Title / Name *',
                              hintText: 'e.g. AI & Robotics Arena, AR/VR Studio, Smart IoT Lab',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.title_rounded),
                            ),
                            onChanged: (v) {
                              if (!_isEditing && _codeCtrl.text.isEmpty) {
                                setState(() {});
                              }
                            },
                          ),
                          const SizedBox(height: 14),

                          // Category Code Input
                          TextField(
                            controller: _codeCtrl,
                            decoration: InputDecoration(
                              labelText: 'Category Code (Unique Key)',
                              hintText: _nameCtrl.text.isNotEmpty
                                  ? _nameCtrl.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '')
                                  : 'e.g. ROBOTICS_ARENA',
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(Icons.code_rounded),
                              helperText: 'Used for system filtering and database keying.',
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Description Input
                          TextField(
                            controller: _descCtrl,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              labelText: 'Description (Optional)',
                              hintText: 'Purpose, specialized equipment, or booking notes...',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.description_outlined),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Icon Picker
                          Text('Select Facility Icon', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey.shade700)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _availableIcons.map((ic) {
                              final isSel = _selectedIcon == ic['name'];
                              return InkWell(
                                onTap: () => setState(() => _selectedIcon = ic['name'] as String),
                                borderRadius: BorderRadius.circular(10),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: isSel ? currentColor.withValues(alpha: 0.2) : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: isSel ? currentColor : Colors.grey.shade300, width: isSel ? 2 : 1),
                                  ),
                                  child: Icon(ic['icon'] as IconData, size: 22, color: isSel ? currentColor : Colors.grey.shade600),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),

                          // Color Picker
                          Text('Select Theme Accent Color', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey.shade700)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _availableColors.map((hex) {
                              final isSel = _selectedColorHex == hex;
                              final c = _parseHexColor(hex);
                              return InkWell(
                                onTap: () => setState(() => _selectedColorHex = hex),
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: c,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: isSel ? Colors.white : Colors.transparent, width: 2),
                                    boxShadow: [
                                      if (isSel) BoxShadow(color: c.withValues(alpha: 0.5), blurRadius: 8, spreadRadius: 2),
                                    ],
                                  ),
                                  child: isSel ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 24),

                          // Action Buttons
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (_isEditing) ...[
                                OutlinedButton(
                                  onPressed: _resetForm,
                                  child: const Text('Cancel Edit'),
                                ),
                                const SizedBox(width: 10),
                              ],
                              ElevatedButton.icon(
                                onPressed: _isSaving ? null : _saveCategory,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryBlue,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                icon: _isSaving
                                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : Icon(_isEditing ? Icons.save_rounded : Icons.add_rounded, size: 18),
                                label: Text(_isEditing ? 'Save Changes' : 'Create Facility', style: const TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
