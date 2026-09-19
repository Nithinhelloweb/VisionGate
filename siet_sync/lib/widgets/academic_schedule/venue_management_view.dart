import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../../config/college_ip_config.dart';
import '../../theme/admin_theme.dart';
import 'manage_facility_categories_dialog.dart';

class VenueManagementView extends StatefulWidget {
  final String token;
  final String userRole;
  final String userDept;
  final String currentSelectedDept;
  final List<Map<String, dynamic>> facultyPool;
  final VoidCallback? onVenuesChanged;

  const VenueManagementView({
    super.key,
    required this.token,
    required this.userRole,
    required this.userDept,
    required this.currentSelectedDept,
    this.facultyPool = const [],
    this.onVenuesChanged,
  });

  @override
  State<VenueManagementView> createState() => _VenueManagementViewState();
}

class _VenueManagementViewState extends State<VenueManagementView> {
  List<Map<String, dynamic>> _venues = [];
  List<Map<String, dynamic>> _facilityCategories = [];
  List<Map<String, dynamic>> _facultyList = [];
  bool _isLoading = true;
  String _selectedType = 'ALL';
  String _searchQuery = '';
  String _selectedBlock = 'ALL';
  String _selectedStatus = 'ALL';
  String _sortBy = 'CODE'; // 'CODE', 'CAPACITY', 'WORKSTATIONS', 'STATUS'

  @override
  void initState() {
    super.initState();
    _facultyList = List.from(widget.facultyPool);
    _facilityCategories = [];
    _fetchFacilityCategories();
    _fetchVenues();
    if (_facultyList.isEmpty) {
      _fetchFacultyPool();
    }
  }

  Future<void> _fetchFacilityCategories() async {
    try {
      final res = await http.get(
        Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/academics/facility-categories'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final cats = List<Map<String, dynamic>>.from(data['categories'] ?? []);
        if (mounted) {
          setState(() {
            _facilityCategories = cats;
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching categories: $e");
    }
  }

  Future<void> _fetchFacultyPool() async {
    try {
      final res = await http.get(
        Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/academics/staff-pool?dept=ALL'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            _facultyList = List<Map<String, dynamic>>.from(data['staff'] ?? []);
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching faculty: $e");
    }
  }

  // Get distinct blocks from active venues dynamically
  List<String> get _dynamicBlocks {
    final blockSet = <String>{};
    for (final v in _venues) {
      final b = (v['block_building'] ?? '').toString().trim();
      if (b.isNotEmpty) blockSet.add(b);
    }
    final sorted = blockSet.toList()..sort();
    return ['ALL', ...sorted];
  }

  // Get distinct floors from active venues dynamically
  List<String> get _dynamicFloors {
    final floorSet = <String>{};
    for (final v in _venues) {
      final f = (v['floor_number'] ?? '').toString().trim();
      if (f.isNotEmpty) floorSet.add(f);
    }
    final sorted = floorSet.toList()..sort();
    return sorted.isEmpty ? ['Ground Floor', '1st Floor', '2nd Floor', '3rd Floor'] : sorted;
  }

  Future<void> _fetchVenues() async {
    setState(() => _isLoading = true);
    try {
      var urlStr = '${CollegeIPConfig.defaultURL}/api/v1/academics/venues?dept=ALL&';
      if (_selectedType != 'ALL') urlStr += 'venue_type=${Uri.encodeComponent(_selectedType.trim())}&';
      if (_selectedBlock != 'ALL') urlStr += 'block=${Uri.encodeComponent(_selectedBlock)}&';
      if (_searchQuery.trim().isNotEmpty) urlStr += 'search=${Uri.encodeComponent(_searchQuery.trim())}&';

      final res = await http.get(
        Uri.parse(urlStr),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _venues = List<Map<String, dynamic>>.from(data['venues'] ?? []);
        });
      }
    } catch (e) {
      debugPrint("Error fetching venues: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateVenueStatus(Map<String, dynamic> venue, String newStatus) async {
    final vId = venue['id'];
    final vCode = venue['venue_code'];
    try {
      final res = await http.patch(
        Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/academics/venues/$vId/status'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ${widget.token}'},
        body: jsonEncode({'status': newStatus}),
      );
      if (res.statusCode == 200) {
        _fetchVenues();
        widget.onVenuesChanged?.call();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Venue "$vCode" status updated to $newStatus'),
              backgroundColor: newStatus == 'AVAILABLE'
                  ? Colors.green
                  : (newStatus == 'UNDER_MAINTENANCE' ? Colors.orange.shade800 : Colors.blue.shade700),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error updating status: $e');
    }
  }

  // Visual type styling helpers with robust alias matching
  static bool _matchesCategory(String venueType, String categoryCode) {
    if (categoryCode.toUpperCase() == 'ALL') return true;
    final vt = venueType.toUpperCase().replaceAll('_', '').replaceAll(' ', '');
    final cc = categoryCode.toUpperCase().replaceAll('_', '').replaceAll(' ', '');
    if (vt == cc) return true;
    if ((cc == 'LH' || cc == 'LECTUREHALL') && (vt == 'LH' || vt == 'LECTUREHALL')) return true;
    if ((cc == 'LAB' || cc == 'LABORATORY') && (vt == 'LAB' || vt == 'LABORATORY')) return true;
    if ((cc == 'SMART' || cc == 'SMARTCLASSROOM') && (vt == 'SMART' || vt == 'SMARTCLASSROOM')) return true;
    if ((cc == 'SEM' || cc == 'SEMINARHALL' || cc == 'SEMINAR') && (vt == 'SEM' || vt == 'SEMINARHALL' || vt == 'SEMINAR')) return true;
    if ((cc == 'AUD' || cc == 'AUDITORIUM') && (vt == 'AUD' || vt == 'AUDITORIUM')) return true;
    if ((cc == 'WS' || cc == 'WORKSHOP') && (vt == 'WS' || vt == 'WORKSHOP')) return true;
    if ((cc == 'TUT' || cc == 'TUTORIALROOM' || cc == 'TUTORIAL') && (vt == 'TUT' || vt == 'TUTORIALROOM' || vt == 'TUTORIAL')) return true;
    if ((cc == 'CONF' || cc == 'CONFERENCEHALL' || cc == 'CONFERENCE') && (vt == 'CONF' || vt == 'CONFERENCEHALL' || vt == 'CONFERENCE')) return true;
    return false;
  }

  Map<String, dynamic>? _findCategoryForType(String type) {
    for (final c in _facilityCategories) {
      final code = (c['category_code'] ?? '').toString();
      final name = (c['category_name'] ?? '').toString();
      if (_matchesCategory(type, code) || _matchesCategory(type, name)) {
        return c;
      }
    }
    return null;
  }

  Color _getTypeColor(String type) {
    final match = _findCategoryForType(type);
    if (match != null && match['color_hex'] != null) {
      return _parseHexColor(match['color_hex']);
    }

    switch (type.toUpperCase()) {
      case 'LAB':
      case 'LABORATORY':
        return const Color(0xFF8B5CF6);
      case 'LH':
      case 'LECTURE_HALL':
      case 'LECTURE HALL':
        return const Color(0xFF2563EB);
      case 'SMART':
      case 'SMART_CLASSROOM':
      case 'SMART CLASSROOM':
        return const Color(0xFF10B981);
      case 'SEM':
      case 'SEMINAR_HALL':
      case 'SEMINAR HALL':
        return const Color(0xFFF59E0B);
      case 'AUD':
      case 'AUDITORIUM':
        return const Color(0xFFEC4899);
      case 'WS':
      case 'WORKSHOP':
        return const Color(0xFFEA580C);
      case 'TUT':
      case 'TUTORIAL_ROOM':
      case 'TUTORIAL ROOM':
        return const Color(0xFF06B6D4);
      case 'CONF':
      case 'CONFERENCE_HALL':
      case 'CONFERENCE HALL':
        return const Color(0xFF6366F1);
      default:
        return const Color(0xFF4F46E5);
    }
  }

  IconData _getTypeIcon(String type) {
    final match = _findCategoryForType(type);
    if (match != null && match['icon_name'] != null) {
      return _getIconDataByName(match['icon_name']);
    }

    switch (type.toUpperCase()) {
      case 'LAB':
      case 'LABORATORY':
        return Icons.science_rounded;
      case 'LH':
      case 'LECTURE_HALL':
      case 'LECTURE HALL':
        return Icons.school_rounded;
      case 'SMART':
      case 'SMART_CLASSROOM':
      case 'SMART CLASSROOM':
        return Icons.tv_rounded;
      case 'SEM':
      case 'SEMINAR_HALL':
      case 'SEMINAR HALL':
        return Icons.theater_comedy_rounded;
      case 'AUD':
      case 'AUDITORIUM':
        return Icons.stadium_rounded;
      case 'WS':
      case 'WORKSHOP':
        return Icons.precision_manufacturing_rounded;
      case 'TUT':
      case 'TUTORIAL_ROOM':
      case 'TUTORIAL ROOM':
        return Icons.menu_book_rounded;
      case 'CONF':
      case 'CONFERENCE_HALL':
      case 'CONFERENCE HALL':
        return Icons.groups_3_rounded;
      default:
        return Icons.domain_rounded;
    }
  }

  String _formatTypeTitle(String type) {
    final match = _findCategoryForType(type);
    if (match != null && match['category_name'] != null) {
      return match['category_name'];
    }

    switch (type.toUpperCase()) {
      case 'LAB':
      case 'LABORATORY':
        return 'Specialized Lab';
      case 'LH':
      case 'LECTURE_HALL':
      case 'LECTURE HALL':
        return 'Lecture Hall';
      case 'SMART_CLASSROOM':
        return 'Smart Classroom';
      case 'SEMINAR_HALL':
        return 'Seminar Hall';
      case 'AUDITORIUM':
        return 'Auditorium';
      case 'WORKSHOP':
        return 'Workshop';
      case 'TUTORIAL_ROOM':
        return 'Tutorial Room';
      case 'CONFERENCE_HALL':
        return 'Conference Hall';
      case 'CUSTOM_FACILITY':
        return 'Custom Facility';
      default:
        return type.replaceAll('_', ' ');
    }
  }

  static Color _parseHexColor(String? hex, {Color defaultColor = const Color(0xFF4F46E5)}) {
    if (hex == null || hex.isEmpty) return defaultColor;
    try {
      var clean = hex.replaceAll('#', '');
      if (clean.length == 6) clean = 'FF$clean';
      return Color(int.parse('0x$clean'));
    } catch (e) {
      return defaultColor;
    }
  }

  static IconData _getIconDataByName(String iconName) {
    switch (iconName) {
      case 'school_rounded': return Icons.school_rounded;
      case 'science_rounded': return Icons.science_rounded;
      case 'tv_rounded': return Icons.tv_rounded;
      case 'cast_for_education_rounded': return Icons.cast_for_education_rounded;
      case 'theater_comedy_rounded': return Icons.theater_comedy_rounded;
      case 'stadium_rounded': return Icons.stadium_rounded;
      case 'precision_manufacturing_rounded': return Icons.precision_manufacturing_rounded;
      case 'menu_book_rounded': return Icons.menu_book_rounded;
      case 'groups_3_rounded':
      case 'groups_rounded': return Icons.groups_3_rounded;
      case 'smart_toy_rounded': return Icons.smart_toy_rounded;
      case 'biotech_rounded': return Icons.biotech_rounded;
      case 'vrpano_rounded': return Icons.vrpano_rounded;
      case 'lightbulb_rounded': return Icons.lightbulb_rounded;
      case 'sports_esports_rounded': return Icons.sports_esports_rounded;
      case 'palette_rounded': return Icons.palette_rounded;
      case 'camera_alt_rounded': return Icons.camera_alt_rounded;
      case 'fitness_center_rounded': return Icons.fitness_center_rounded;
      case 'local_library_rounded': return Icons.local_library_rounded;
      case 'wifi_rounded': return Icons.wifi_rounded;
      case 'domain_rounded':
      default: return Icons.domain_rounded;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toUpperCase()) {
      case 'AVAILABLE':
        return const Color(0xFF10B981);
      case 'UNDER_MAINTENANCE':
        return const Color(0xFFF59E0B);
      case 'RESERVED':
        return const Color(0xFF3B82F6);
      case 'OFFLINE':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF10B981);
    }
  }

  String _formatStatusLabel(String status) {
    switch (status.toUpperCase()) {
      case 'AVAILABLE':
        return 'Available';
      case 'UNDER_MAINTENANCE':
        return 'Maintenance';
      case 'RESERVED':
        return 'Reserved';
      case 'OFFLINE':
        return 'Offline';
      default:
        return status;
    }
  }

  // ==========================================
  // DEDICATED FACILITY CATEGORIES MANAGER
  // ==========================================

  void _openManageFacilitiesDialog() {
    ManageFacilityCategoriesDialog.show(
      context,
      token: widget.token,
      onCategoriesChanged: () {
        _fetchFacilityCategories();
        _fetchVenues();
        widget.onVenuesChanged?.call();
      },
    );
  }

  // ==========================================
  // VENUE CREATE & EDIT DIALOG (OVERFLOW-FREE)
  // ==========================================

  void _openVenueDialog({Map<String, dynamic>? initialVenue}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEdit = initialVenue != null;

    final codeCtrl = TextEditingController(text: initialVenue?['venue_code'] ?? '');
    final nameCtrl = TextEditingController(text: initialVenue?['venue_name'] ?? '');
    final blockCtrl = TextEditingController(text: initialVenue?['block_building'] ?? '');
    final floorCtrl = TextEditingController(text: initialVenue?['floor_number'] ?? '');
    final capacityCtrl = TextEditingController(text: '${initialVenue?['capacity'] ?? 60}');
    final labStationsCtrl = TextEditingController(text: '${initialVenue?['lab_workstations'] ?? 0}');
    final customAmenityCtrl = TextEditingController();

    String venueType = initialVenue?['venue_type'] ?? 'LECTURE_HALL';
    String dept = initialVenue?['dept'] ?? (widget.userDept.isNotEmpty ? widget.userDept : 'GLOBAL');
    String status = initialVenue?['status'] ?? 'AVAILABLE';

    String? inChargeReg = initialVenue?['in_charge_staff_reg_no'];
    String? inChargeName = initialVenue?['in_charge_staff_name'];

    List<String> amenities = List<String>.from(initialVenue?['equipment_amenities'] ?? []);
    final suggestedAmenities = [
      'Interactive Smart Display (IFP)',
      '4K Laser Projector',
      'Central AC System',
      'Gigabit Fibre LAN / Wi-Fi 6',
      'Surround PA Audio & Microphones',
      'Biometric Face Terminal',
      'GPU Workstation PCs',
      'Dual 8K LED Video Walls',
      'Smart Digital Podium',
      'Live Lecture Streaming Pod',
      'Whiteboard & Document Camera',
      'IoT Sensor Bench',
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          final isLab = (venueType == 'LABORATORY' || venueType == 'WORKSHOP');
          final typeColor = _getTypeColor(venueType);

          return AlertDialog(
            backgroundColor: AdminColors.getCard(isDark),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(_getTypeIcon(venueType), color: typeColor, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isEdit ? 'Edit Campus Facility' : 'Create Custom Campus Venue / Lab',
                        style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.bold, color: AdminColors.getTextPrimary(isDark)),
                      ),
                      Text(
                        'Full operational CRUD for campus rooms, labs, blocks & capacities',
                        style: GoogleFonts.inter(fontSize: 11, color: AdminColors.getTextSecondary(isDark)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 680,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Facility Category Selector & Inline Category Creator
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('1. Facility Category *', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12, color: AdminColors.getTextSecondary(isDark))),
                        TextButton.icon(
                          onPressed: () {
                            _openManageFacilitiesDialog();
                          },
                          icon: const Icon(Icons.settings_rounded, size: 14),
                          label: const Text('Manage Facilities', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF2563EB),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (_facilityCategories.isEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF8B5CF6).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFF8B5CF6)),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text('No facility categories in database yet.', style: TextStyle(fontSize: 12)),
                            ),
                            ElevatedButton.icon(
                              onPressed: () {
                                _openManageFacilitiesDialog();
                              },
                              icon: const Icon(Icons.add, size: 14),
                              label: const Text('Create Facility', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF8B5CF6),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _facilityCategories.map((cat) {
                          final cCode = (cat['category_code'] ?? '').toString();
                          final cName = (cat['category_name'] ?? cCode).toString();
                          final isSel = venueType.toUpperCase() == cCode.toUpperCase();
                          final c = _parseHexColor(cat['color_hex']);
                          final ic = _getIconDataByName(cat['icon_name'] ?? 'domain_rounded');

                          return InkWell(
                            onTap: () => setDlgState(() => venueType = cCode),
                            borderRadius: BorderRadius.circular(12),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                              decoration: BoxDecoration(
                                color: isSel ? c.withValues(alpha: 0.15) : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: isSel ? c : AdminColors.getBorder(isDark), width: isSel ? 1.5 : 1),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(ic, size: 15, color: isSel ? c : Colors.grey),
                                  const SizedBox(width: 6),
                                  Text(
                                    cName,
                                    style: GoogleFonts.inter(fontSize: 12, fontWeight: isSel ? FontWeight.bold : FontWeight.w500, color: isSel ? c : AdminColors.getTextPrimary(isDark)),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                    const SizedBox(height: 16),

                    // Row 1: Code & Status (Balanced 2-Column Row with isExpanded)
                    Row(
                      children: [
                        Expanded(
                          flex: 1,
                          child: TextField(
                            controller: codeCtrl,
                            enabled: !isEdit,
                            decoration: const InputDecoration(
                              labelText: 'Venue / Lab Code *',
                              hintText: 'e.g. LH-501, LAB-ROBOT-01',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 1,
                          child: DropdownButtonFormField<String>(
                            initialValue: status,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Operational Status',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'AVAILABLE', child: Text('🟢 Available')),
                              DropdownMenuItem(value: 'UNDER_MAINTENANCE', child: Text('🟠 Maintenance')),
                              DropdownMenuItem(value: 'RESERVED', child: Text('🔵 Reserved')),
                              DropdownMenuItem(value: 'OFFLINE', child: Text('⚪ Offline')),
                            ],
                            onChanged: (v) {
                              if (v != null) setDlgState(() => status = v);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Row 2: Facility Official Name (Full Width)
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Facility Official Name *',
                        hintText: 'e.g. Advanced Autonomous Systems Research Lab',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Row 3: Primary Host Department (Full Width with isExpanded)
                    DropdownButtonFormField<String>(
                      initialValue: dept,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Primary Host Department',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'GLOBAL', child: Text('Global / All Campus (Shared Facility)')),
                        DropdownMenuItem(value: 'CSE', child: Text('Computer Science & Eng (CSE)')),
                        DropdownMenuItem(value: 'ECE', child: Text('Electronics & Comm (ECE)')),
                        DropdownMenuItem(value: 'EEE', child: Text('Electrical & Electronics (EEE)')),
                        DropdownMenuItem(value: 'MECH', child: Text('Mechanical Eng (MECH)')),
                        DropdownMenuItem(value: 'CIVIL', child: Text('Civil Eng (CIVIL)')),
                        DropdownMenuItem(value: 'IT', child: Text('Information Tech (IT)')),
                        DropdownMenuItem(value: 'AI & ML', child: Text('Artificial Intelligence (AI & ML)')),
                        DropdownMenuItem(value: 'GENERAL', child: Text('Central Campus Administration')),
                      ],
                      onChanged: (v) {
                        if (v != null) setDlgState(() => dept = v);
                      },
                    ),
                    const SizedBox(height: 12),

                    // Row 4: Freeform Dynamic Campus Block & Floor with Autocomplete
                    Row(
                      children: [
                        Expanded(
                          child: Autocomplete<String>(
                            initialValue: TextEditingValue(text: blockCtrl.text),
                            optionsBuilder: (textEditingValue) {
                              final query = textEditingValue.text.toLowerCase();
                              final existing = _dynamicBlocks.where((b) => b != 'ALL');
                              return existing.where((b) => b.toLowerCase().contains(query));
                            },
                            onSelected: (val) {
                              blockCtrl.text = val;
                            },
                            fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
                              if (blockCtrl.text.isNotEmpty && textEditingController.text.isEmpty) {
                                textEditingController.text = blockCtrl.text;
                              }
                              return TextField(
                                controller: textEditingController,
                                focusNode: focusNode,
                                decoration: const InputDecoration(
                                  labelText: 'Campus Building / Block *',
                                  hintText: 'e.g. Newton Academic Block',
                                  prefixIcon: Icon(Icons.location_city_rounded, size: 18),
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (v) => blockCtrl.text = v,
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Autocomplete<String>(
                            initialValue: TextEditingValue(text: floorCtrl.text),
                            optionsBuilder: (textEditingValue) {
                              final query = textEditingValue.text.toLowerCase();
                              return _dynamicFloors.where((f) => f.toLowerCase().contains(query));
                            },
                            onSelected: (val) {
                              floorCtrl.text = val;
                            },
                            fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
                              if (floorCtrl.text.isNotEmpty && textEditingController.text.isEmpty) {
                                textEditingController.text = floorCtrl.text;
                              }
                              return TextField(
                                controller: textEditingController,
                                focusNode: focusNode,
                                decoration: const InputDecoration(
                                  labelText: 'Floor / Level / Wing *',
                                  hintText: 'e.g. Ground Floor, Level 3',
                                  prefixIcon: Icon(Icons.layers_rounded, size: 18),
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (v) => floorCtrl.text = v,
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Row 5: Capacity & Workstations
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: capacityCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Total Seating Capacity',
                              hintText: 'e.g. 70 seats',
                              prefixIcon: Icon(Icons.people_alt_outlined, size: 18),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        if (isLab) ...[
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: labStationsCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'PC / GPU Workstations',
                                hintText: 'e.g. 45 units',
                                prefixIcon: Icon(Icons.computer_rounded, size: 18),
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Row 6: In-charge staff picker (with isExpanded)
                    DropdownButtonFormField<String>(
                      initialValue: inChargeReg,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Faculty / Lab Assistant In-Charge (Optional)',
                        border: OutlineInputBorder(),
                      ),
                      hint: const Text('Assign Campus Faculty / Lab In-Charge'),
                      items: _facultyList.map((f) {
                        final reg = f['reg_no']?.toString() ?? '';
                        final n = f['name']?.toString() ?? '';
                        final d = f['dept']?.toString() ?? '';
                        return DropdownMenuItem(
                          value: reg,
                          child: Text('$n ($reg • $d)', overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (v) {
                        setDlgState(() {
                          inChargeReg = v;
                          final match = _facultyList.firstWhere(
                            (e) => e['reg_no']?.toString() == v,
                            orElse: () => {},
                          );
                          inChargeName = match['name']?.toString();
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    // Row 7: Smart Amenities & Freeform Tag Adder
                    Text('Smart Equipment & Technology Amenities', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        ...{...suggestedAmenities, ...amenities}.map((amenity) {
                          final isSel = amenities.contains(amenity);
                          return FilterChip(
                            label: Text(amenity, style: TextStyle(fontSize: 11, color: isSel ? Colors.white : null)),
                            selected: isSel,
                            selectedColor: typeColor,
                            onSelected: (selected) {
                              setDlgState(() {
                                if (selected) {
                                  amenities.add(amenity);
                                } else {
                                  amenities.remove(amenity);
                                }
                              });
                            },
                          );
                        }),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: customAmenityCtrl,
                            decoration: InputDecoration(
                              hintText: 'Type custom equipment / amenity tag...',
                              prefixIcon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onSubmitted: (val) {
                              final t = val.trim();
                              if (t.isNotEmpty && !amenities.contains(t)) {
                                setDlgState(() {
                                  amenities.add(t);
                                  customAmenityCtrl.clear();
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: () {
                            final t = customAmenityCtrl.text.trim();
                            if (t.isNotEmpty && !amenities.contains(t)) {
                              setDlgState(() {
                                amenities.add(t);
                                customAmenityCtrl.clear();
                              });
                            }
                          },
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Add Tag'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: typeColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: typeColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  final code = codeCtrl.text.trim().toUpperCase();
                  final name = nameCtrl.text.trim();
                  final block = blockCtrl.text.trim().isEmpty ? 'Main Academic Block' : blockCtrl.text.trim();
                  final floor = floorCtrl.text.trim().isEmpty ? '1st Floor' : floorCtrl.text.trim();

                  if (code.isEmpty || name.isEmpty) return;

                  Navigator.pop(ctx);
                  final payload = {
                    'venue_code': code,
                    'venue_name': name,
                    'venue_type': venueType,
                    'dept': dept,
                    'block_building': block,
                    'floor_number': floor,
                    'capacity': int.tryParse(capacityCtrl.text.trim()) ?? 60,
                    'lab_workstations': int.tryParse(labStationsCtrl.text.trim()) ?? 0,
                    'equipment_amenities': amenities,
                    'in_charge_staff_reg_no': inChargeReg,
                    'in_charge_staff_name': inChargeName,
                    'status': status,
                  };

                  if (isEdit) {
                    await http.put(
                      Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/academics/venues/${initialVenue['id']}'),
                      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ${widget.token}'},
                      body: jsonEncode(payload),
                    );
                  } else {
                    await http.post(
                      Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/academics/venues'),
                      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ${widget.token}'},
                      body: jsonEncode(payload),
                    );
                  }

                  _fetchVenues();
                  widget.onVenuesChanged?.call();
                },
                child: Text(isEdit ? 'Save Changes' : 'Create Custom Venue'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmDeleteVenue(Map<String, dynamic> venue) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final vId = venue['id'];
    final vCode = venue['venue_code'] ?? '';
    final vName = venue['venue_name'] ?? '';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminColors.getCard(isDark),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.delete_forever_rounded, color: Colors.red, size: 22),
            ),
            const SizedBox(width: 12),
            const Text('Deactivate Venue', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Text(
          'Are you sure you want to deactivate "$vCode - $vName"? Existing timetable historical records will be preserved.',
          style: TextStyle(fontSize: 13, color: AdminColors.getTextSecondary(isDark)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              await http.delete(
                Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/academics/venues/$vId'),
                headers: {'Authorization': 'Bearer ${widget.token}'},
              );
              _fetchVenues();
              widget.onVenuesChanged?.call();
            },
            child: const Text('Deactivate Venue'),
          ),
        ],
      ),
    );
  }

  void _showVenueWeeklySchedule(Map<String, dynamic> venue) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final vCode = venue['venue_code'] ?? '';
    final vName = venue['venue_name'] ?? '';
    final typeColor = _getTypeColor(venue['venue_type'] ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminColors.getCard(isDark),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: typeColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.calendar_month_rounded, color: typeColor, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('$vCode Occupancy Matrix', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: typeColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                        child: Text('Global Matrix', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: typeColor)),
                      ),
                    ],
                  ),
                  Text(vName, style: TextStyle(fontSize: 12, color: Colors.grey.shade500), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 650,
          height: 440,
          child: FutureBuilder<http.Response>(
            future: http.get(
              Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/academics/venues/$vCode/schedule'),
              headers: {'Authorization': 'Bearer ${widget.token}'},
            ),
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError || snap.data?.statusCode != 200) {
                return const Center(child: Text('Failed to load venue schedule.'));
              }

              final data = jsonDecode(snap.data!.body);
              final List<dynamic> schedule = data['schedule'] ?? [];

              if (schedule.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), shape: BoxShape.circle),
                        child: const Icon(Icons.check_circle_outline_rounded, size: 48, color: Colors.green),
                      ),
                      const SizedBox(height: 14),
                      Text('100% Vacant Across All Timetables', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 4),
                      Text('No department has allocated periods in $vCode yet. It is ready for assignment.', style: TextStyle(color: Colors.grey.shade500, fontSize: 12), textAlign: TextAlign.center),
                    ],
                  ),
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.hub_rounded, size: 16, color: Colors.blue),
                        const SizedBox(width: 8),
                        Text(
                          'Cross-Department Utilization: ${schedule.length} Timetable Slots Booked',
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blue.shade700),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.builder(
                      itemCount: schedule.length,
                      itemBuilder: (ctx, i) {
                        final s = schedule[i];
                        final dept = s['dept'] ?? 'CSE';
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E293B) : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AdminColors.getBorder(isDark)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: typeColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Column(
                                  children: [
                                    Text(s['day_of_week'] ?? '', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: typeColor)),
                                    Text('P${s['period_number']}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: typeColor)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('${s['subject_code']} - ${s['subject_name']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                    Text('${s['dept']} Sem ${s['semester']} (${s['section']}) • Faculty: ${s['staff_name']}', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(color: typeColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                                child: Text(dept, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: typeColor)),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _getProcessedVenues() {
    var list = _venues.where((v) {
      if (_selectedType != 'ALL') {
        final vType = (v['venue_type'] ?? '').toString();
        if (!_matchesCategory(vType, _selectedType)) return false;
      }
      if (_selectedStatus != 'ALL') {
        final st = (v['status'] ?? 'AVAILABLE').toString().toUpperCase();
        if (st != _selectedStatus) return false;
      }
      return true;
    }).toList();

    list.sort((a, b) {
      if (_sortBy == 'CAPACITY') {
        return ((b['capacity'] as num?) ?? 0).compareTo((a['capacity'] as num?) ?? 0);
      } else if (_sortBy == 'WORKSTATIONS') {
        return ((b['lab_workstations'] as num?) ?? 0).compareTo((a['lab_workstations'] as num?) ?? 0);
      } else if (_sortBy == 'STATUS') {
        return (a['status'] ?? '').toString().compareTo((b['status'] ?? '').toString());
      } else {
        return (a['venue_code'] ?? '').toString().compareTo((b['venue_code'] ?? '').toString());
      }
    });

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final processedVenues = _getProcessedVenues();

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: _buildHeader(isDark),
        ),
        SliverToBoxAdapter(
          child: _buildFilterBar(isDark),
        ),
        if (_isLoading)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else if (processedVenues.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 48),
              child: _buildEmptyState(isDark),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 460,
                mainAxisExtent: 250,
                crossAxisSpacing: 18,
                mainAxisSpacing: 18,
              ),
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => _buildVenueCard(processedVenues[i], isDark),
                childCount: processedVenues.length,
              ),
            ),
          ),
        const SliverToBoxAdapter(
          child: SizedBox(height: 40),
        ),
      ],
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.meeting_room_outlined, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 14),
          Text('No Campus Facilities Found', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 4),
          Text(
            _selectedType != 'ALL'
                ? 'No facilities match the selected category filter. Try selecting "All Global Venues".'
                : 'Tap "Create Custom Venue" to register your campus rooms, labs, or blocks.',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => _openVenueDialog(),
            icon: const Icon(Icons.add_business_rounded, size: 18),
            label: const Text('Create First Venue'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: AdminColors.getCard(isDark).withValues(alpha: 0.7),
        border: Border(bottom: BorderSide(color: AdminColors.getBorder(isDark))),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 800;

          final searchField = TextField(
            decoration: InputDecoration(
              hintText: 'Search halls, laboratories, workstations, or blocks...',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onChanged: (v) {
              setState(() => _searchQuery = v);
              _fetchVenues();
            },
          );

          final blockFilter = DropdownButtonHideUnderline(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: AdminColors.getBorder(isDark)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: DropdownButton<String>(
                value: _dynamicBlocks.contains(_selectedBlock) ? _selectedBlock : 'ALL',
                items: _dynamicBlocks
                    .map((b) => DropdownMenuItem(
                          value: b,
                          child: Text(b == 'ALL' ? '🏢 All Blocks' : b, style: const TextStyle(fontSize: 12)),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _selectedBlock = v);
                    _fetchVenues();
                  }
                },
              ),
            ),
          );

          final statusFilter = DropdownButtonHideUnderline(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: AdminColors.getBorder(isDark)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: DropdownButton<String>(
                value: _selectedStatus,
                items: const [
                  DropdownMenuItem(value: 'ALL', child: Text('⚡ All Statuses', style: TextStyle(fontSize: 12))),
                  DropdownMenuItem(value: 'AVAILABLE', child: Text('🟢 Available', style: TextStyle(fontSize: 12))),
                  DropdownMenuItem(value: 'UNDER_MAINTENANCE', child: Text('🟠 Maintenance', style: TextStyle(fontSize: 12))),
                  DropdownMenuItem(value: 'RESERVED', child: Text('🔵 Reserved', style: TextStyle(fontSize: 12))),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _selectedStatus = v);
                },
              ),
            ),
          );

          final sortFilter = DropdownButtonHideUnderline(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: AdminColors.getBorder(isDark)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: DropdownButton<String>(
                value: _sortBy,
                items: const [
                  DropdownMenuItem(value: 'CODE', child: Text('Sort: Code (A-Z)', style: TextStyle(fontSize: 12))),
                  DropdownMenuItem(value: 'CAPACITY', child: Text('Sort: Capacity ↓', style: TextStyle(fontSize: 12))),
                  DropdownMenuItem(value: 'WORKSTATIONS', child: Text('Sort: Systems ↓', style: TextStyle(fontSize: 12))),
                  DropdownMenuItem(value: 'STATUS', child: Text('Sort: Status', style: TextStyle(fontSize: 12))),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _sortBy = v);
                },
              ),
            ),
          );

          final reloadBtn = IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Reload Facilities',
            onPressed: () {
              _fetchFacilityCategories();
              _fetchVenues();
            },
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isNarrow) ...[
                Row(
                  children: [
                    Expanded(child: searchField),
                    const SizedBox(width: 8),
                    reloadBtn,
                  ],
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      blockFilter,
                      const SizedBox(width: 8),
                      statusFilter,
                      const SizedBox(width: 8),
                      sortFilter,
                    ],
                  ),
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(flex: 3, child: searchField),
                    const SizedBox(width: 10),
                    blockFilter,
                    const SizedBox(width: 10),
                    statusFilter,
                    const SizedBox(width: 10),
                    sortFilter,
                    const SizedBox(width: 10),
                    reloadBtn,
                  ],
                ),
              ],
              const SizedBox(height: 12),

              // Dynamic Category Filter Chips + Manage Facilities Action
              if (_facilityCategories.isEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.domain_verification_rounded, size: 18, color: Color(0xFF8B5CF6)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'No facility categories exist in DB yet. Only admin-created facilities will appear here.',
                          style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : const Color(0xFF4C1D95)),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _openManageFacilitiesDialog,
                        icon: const Icon(Icons.add, size: 14),
                        label: const Text('Manage Facilities', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF8B5CF6),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: const Text('All Global Venues'),
                          selected: _selectedType == 'ALL',
                          selectedColor: const Color(0xFF2563EB),
                          labelStyle: TextStyle(
                            fontSize: 12,
                            color: _selectedType == 'ALL' ? Colors.white : AdminColors.getTextPrimary(isDark),
                            fontWeight: _selectedType == 'ALL' ? FontWeight.bold : FontWeight.w500,
                          ),
                          onSelected: (sel) {
                            if (sel) {
                              setState(() => _selectedType = 'ALL');
                              _fetchVenues();
                            }
                          },
                        ),
                      ),
                      ..._facilityCategories.map((cat) {
                        final cCode = (cat['category_code'] ?? '').toString();
                        final cName = (cat['category_name'] ?? cCode).toString();
                        final isSel = _matchesCategory(_selectedType, cCode);
                        final color = _parseHexColor(cat['color_hex']);
                        final icon = _getIconDataByName(cat['icon_name'] ?? 'domain_rounded');

                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            avatar: Icon(icon, size: 14, color: isSel ? Colors.white : color),
                            label: Text(cName),
                            selected: isSel,
                            selectedColor: color,
                            labelStyle: TextStyle(
                              fontSize: 12,
                              color: isSel ? Colors.white : AdminColors.getTextPrimary(isDark),
                              fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                            ),
                            onSelected: (sel) {
                              if (sel) {
                                setState(() => _selectedType = cCode);
                                _fetchVenues();
                              }
                            },
                          ),
                        );
                      }),
                      ActionChip(
                        avatar: const Icon(Icons.settings_rounded, size: 14, color: Color(0xFF8B5CF6)),
                        label: const Text('Manage Facilities', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF8B5CF6))),
                        backgroundColor: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                        side: const BorderSide(color: Color(0xFF8B5CF6), width: 0.8),
                        onPressed: _openManageFacilitiesDialog,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildVenueCard(Map<String, dynamic> v, bool isDark) {
    final vType = v['venue_type'] ?? 'LECTURE_HALL';
    final vStatus = (v['status'] ?? 'AVAILABLE').toString().toUpperCase();
    final isLab = vType == 'LABORATORY' || vType == 'WORKSHOP';
    final typeColor = _getTypeColor(vType);
    final statusColor = _getStatusColor(vStatus);
    final amenities = List<String>.from(v['equipment_amenities'] ?? []);
    final hostDept = v['dept'] ?? 'GLOBAL';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AdminColors.getCard(isDark),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AdminColors.getBorder(isDark)),
        boxShadow: [
          BoxShadow(
            color: typeColor.withValues(alpha: isDark ? 0.08 : 0.04),
            blurRadius: 16,
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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: typeColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_getTypeIcon(vType), size: 14, color: typeColor),
                    const SizedBox(width: 6),
                    Text(
                      v['venue_code'] ?? '',
                      style: TextStyle(
                        color: typeColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                tooltip: 'Change Status',
                initialValue: vStatus,
                onSelected: (newSt) => _updateVenueStatus(v, newSt),
                itemBuilder: (ctx) => [
                  const PopupMenuItem(value: 'AVAILABLE', child: Text('🟢 Available')),
                  const PopupMenuItem(value: 'UNDER_MAINTENANCE', child: Text('🟠 Under Maintenance')),
                  const PopupMenuItem(value: 'RESERVED', child: Text('🔵 Reserved')),
                  const PopupMenuItem(value: 'OFFLINE', child: Text('⚪ Offline')),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 6, height: 6, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                      const SizedBox(width: 4),
                      Text(
                        _formatStatusLabel(vStatus),
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor),
                      ),
                      const Icon(Icons.arrow_drop_down, size: 14),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.calendar_month_rounded, size: 18),
                tooltip: 'Live Timetable Schedule Matrix',
                onPressed: () => _showVenueWeeklySchedule(v),
              ),
              IconButton(
                icon: const Icon(Icons.edit_rounded, size: 18),
                tooltip: 'Edit Facility',
                onPressed: () => _openVenueDialog(initialVenue: v),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                tooltip: 'Deactivate / Delete',
                onPressed: () => _confirmDeleteVenue(v),
              ),
            ],
          ),
          const SizedBox(height: 10),

          Text(
            v['venue_name'] ?? '',
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AdminColors.getTextPrimary(isDark),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Text(
                _formatTypeTitle(vType),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: typeColor),
              ),
              const SizedBox(width: 6),
              Container(width: 3, height: 3, decoration: BoxDecoration(color: Colors.grey.shade400, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(
                '${v['block_building'] ?? 'Main'} • ${v['floor_number'] ?? 'Ground'}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ],
          ),
          const Spacer(),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AdminColors.getBorder(isDark)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Row(
                  children: [
                    Icon(Icons.people_alt_rounded, size: 14, color: Colors.grey.shade500),
                    const SizedBox(width: 6),
                    Text('${v['capacity'] ?? 0} Seats', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AdminColors.getTextPrimary(isDark))),
                  ],
                ),
                if (isLab) ...[
                  Container(width: 1, height: 14, color: AdminColors.getBorder(isDark)),
                  Row(
                    children: [
                      const Icon(Icons.computer_rounded, size: 14, color: Color(0xFF8B5CF6)),
                      const SizedBox(width: 6),
                      Text('${v['lab_workstations'] ?? 0} PCs', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF8B5CF6))),
                    ],
                  ),
                ],
                Container(width: 1, height: 14, color: AdminColors.getBorder(isDark)),
                Row(
                  children: [
                    Icon(Icons.apartment_rounded, size: 14, color: Colors.grey.shade500),
                    const SizedBox(width: 6),
                    Text(hostDept, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AdminColors.getTextPrimary(isDark))),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          if (amenities.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: amenities.map((a) => Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AdminColors.getBorder(isDark)),
                  ),
                  child: Text(a, style: TextStyle(fontSize: 10, color: AdminColors.getTextSecondary(isDark), fontWeight: FontWeight.w600)),
                )).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    final totalVenues = _venues.length;
    final totalHalls = _venues.where((v) => _matchesCategory(v['venue_type'] ?? '', 'LH')).length;
    final totalLabs = _venues.where((v) => _matchesCategory(v['venue_type'] ?? '', 'LAB')).length;
    final totalCapacity = _venues.fold<int>(0, (sum, v) => sum + ((v['capacity'] as num?)?.toInt() ?? 0));
    final totalWorkstations = _venues.fold<int>(0, (sum, v) => sum + ((v['lab_workstations'] as num?)?.toInt() ?? 0));
    final distinctBlocksCount = _dynamicBlocks.where((b) => b != 'ALL').length;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AdminColors.getCard(isDark),
        border: Border(bottom: BorderSide(color: AdminColors.getBorder(isDark))),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 800;

          final titleWidget = Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2563EB), Color(0xFF7C3AED)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(color: const Color(0xFF2563EB).withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: const Icon(Icons.domain_rounded, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Campus Facilities, Halls & Lab Infrastructure',
                          style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: AdminColors.getTextPrimary(isDark)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                          ),
                          child: const Text('Dynamic Venue & Category Engine', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Add and manage campus facilities, specialized labs, dynamic categories, capacities & equipment across all blocks',
                      style: GoogleFonts.inter(fontSize: 12, color: AdminColors.getTextSecondary(isDark)),
                    ),
                  ],
                ),
              ),
            ],
          );

          final actionsWidget = Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _openManageFacilitiesDialog,
                icon: const Icon(Icons.category_rounded, size: 16, color: Color(0xFF8B5CF6)),
                label: const Text('Manage Facilities', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF8B5CF6))),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF8B5CF6)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _openVenueDialog(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 4,
                ),
                icon: const Icon(Icons.add_business_rounded, size: 18),
                label: const Text('Create Custom Venue', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );

          final statCards = [
            _buildStatCard(
              title: 'Total Facilities',
              value: '$totalVenues',
              subtitle: '$totalHalls Halls • $totalLabs Labs',
              icon: Icons.meeting_room_rounded,
              color: const Color(0xFF2563EB),
              isDark: isDark,
            ),
            _buildStatCard(
              title: 'Seating Capacity',
              value: '$totalCapacity',
              subtitle: 'Across all lecture rooms',
              icon: Icons.people_alt_rounded,
              color: const Color(0xFF10B981),
              isDark: isDark,
            ),
            _buildStatCard(
              title: 'Workstation Units',
              value: '$totalWorkstations',
              subtitle: 'High-performance lab systems',
              icon: Icons.computer_rounded,
              color: const Color(0xFF8B5CF6),
              isDark: isDark,
            ),
            _buildStatCard(
              title: 'Campus Blocks',
              value: '$distinctBlocksCount Blocks',
              subtitle: 'Dynamically registered buildings',
              icon: Icons.location_city_rounded,
              color: const Color(0xFFF59E0B),
              isDark: isDark,
            ),
          ];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isNarrow) ...[
                titleWidget,
                const SizedBox(height: 12),
                actionsWidget,
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: titleWidget),
                    const SizedBox(width: 16),
                    actionsWidget,
                  ],
                ),
              const SizedBox(height: 16),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: statCards
                      .map((card) => Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: SizedBox(width: 220, child: card),
                          ))
                      .toList(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AdminColors.getBorder(isDark)),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
                Text(value, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AdminColors.getTextPrimary(isDark))),
                Text(subtitle, style: TextStyle(fontSize: 9, color: Colors.grey.shade500), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
