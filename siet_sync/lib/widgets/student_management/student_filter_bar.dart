import 'package:flutter/material.dart';

class StudentFilterBar extends StatelessWidget {
  final bool isAdmin;
  final bool isHod;
  final bool isStaff;
  final String selectedDept;
  final String selectedBatch;
  final int? selectedSemester;
  final String selectedSemesterType; // 'ALL', 'ODD', 'EVEN'
  final String selectedSection;
  final String selectedFaceStatus; // 'ALL', 'ENROLLED', 'MISSING'
  final String selectedAccountStatus; // 'ALL', 'ACTIVE', 'SUSPENDED'
  final bool myClassOnly;
  final String searchQuery;
  final List<String>? availableBatches;
  final ValueChanged<String>? onDeptChanged;
  final ValueChanged<String>? onBatchChanged;
  final ValueChanged<int?>? onSemesterChanged;
  final ValueChanged<String>? onSemesterTypeChanged;
  final ValueChanged<String>? onSectionChanged;
  final ValueChanged<String>? onFaceStatusChanged;
  final ValueChanged<String>? onAccountStatusChanged;
  final ValueChanged<bool>? onMyClassOnlyChanged;
  final ValueChanged<String>? onSearchChanged;
  final VoidCallback onClearFilters;

  const StudentFilterBar({
    super.key,
    required this.isAdmin,
    required this.isHod,
    required this.isStaff,
    required this.selectedDept,
    required this.selectedBatch,
    required this.selectedSemester,
    this.selectedSemesterType = 'ALL',
    required this.selectedSection,
    this.selectedFaceStatus = 'ALL',
    this.selectedAccountStatus = 'ALL',
    required this.myClassOnly,
    required this.searchQuery,
    this.availableBatches,
    this.onDeptChanged,
    this.onBatchChanged,
    this.onSemesterChanged,
    this.onSemesterTypeChanged,
    this.onSectionChanged,
    this.onFaceStatusChanged,
    this.onAccountStatusChanged,
    this.onMyClassOnlyChanged,
    this.onSearchChanged,
    required this.onClearFilters,
  });

  static const List<String> departments = [
    'ALL',
    'CSE',
    'IT',
    'AI & DS',
    'AI & ML',
    'CYBER',
    'ECE',
    'EEE',
    'MECH',
    'CIVIL',
    'BIOTECH',
    'BME',
    'AGRI',
  ];

  static const List<String> batches = [
    'ALL',
    '2021-2025',
    '2022-2026',
    '2023-2027',
    '2024-2028',
    '2025-2029',
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isMobile = screenWidth < 650;
    const primaryBlue = Color(0xFF2563EB);

    final searchHint = isMobile
        ? (isStaff ? 'Search advisees or Reg No...' : 'Search students or Reg No...')
        : (isStaff ? 'Search advisees by student name, Reg No, or Roll No...' : 'Search by student name, Reg No, or Roll No...');

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 16,
        vertical: isMobile ? 10 : 14,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(isMobile ? 14 : 18),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search Input Field
          TextField(
            onChanged: onSearchChanged,
            style: TextStyle(fontSize: isMobile ? 13 : 14),
            decoration: InputDecoration(
              hintText: searchHint,
              hintStyle: TextStyle(
                fontSize: isMobile ? 12 : 13,
                color: isDark ? Colors.white38 : Colors.grey.shade500,
              ),
              prefixIcon: Icon(Icons.search_rounded, size: isMobile ? 18 : 20),
              suffixIcon: searchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear, size: isMobile ? 16 : 18),
                      onPressed: () => onSearchChanged?.call(''),
                    )
                  : null,
              contentPadding: EdgeInsets.symmetric(vertical: 0, horizontal: isMobile ? 10 : 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: isDark ? Colors.white24 : Colors.grey.shade300,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: isDark ? Colors.white12 : Colors.grey.shade200,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: primaryBlue, width: 1.5),
              ),
              filled: true,
              fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
            ),
          ),

          // -------------------------------------------------------------
          // SEMESTER SELECTION CHIPS (Admin and HOD only - Not for Staff Advised View)
          // -------------------------------------------------------------
          if (!isStaff) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.view_timeline_outlined, size: 16, color: primaryBlue),
                const SizedBox(width: 6),
                Text(
                  'Semester Scope:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white70 : Colors.grey.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // All Semesters Pill
                  _buildSemesterChip(
                    label: 'All Semesters',
                    isSelected: selectedSemester == null && selectedSemesterType == 'ALL',
                    isDark: isDark,
                    onTap: () {
                      onSemesterChanged?.call(null);
                      onSemesterTypeChanged?.call('ALL');
                    },
                  ),
                  const SizedBox(width: 6),

                  // Odd Semesters Pill (1, 3, 5, 7)
                  _buildSemesterChip(
                    label: 'Odd Semesters (1, 3, 5, 7)',
                    isSelected: selectedSemester == null && selectedSemesterType == 'ODD',
                    isDark: isDark,
                    activeColor: const Color(0xFF10B981),
                    onTap: () {
                      onSemesterChanged?.call(null);
                      onSemesterTypeChanged?.call('ODD');
                    },
                  ),
                  const SizedBox(width: 6),

                  // Even Semesters Pill (2, 4, 6, 8)
                  _buildSemesterChip(
                    label: 'Even Semesters (2, 4, 6, 8)',
                    isSelected: selectedSemester == null && selectedSemesterType == 'EVEN',
                    isDark: isDark,
                    activeColor: const Color(0xFF8B5CF6),
                    onTap: () {
                      onSemesterChanged?.call(null);
                      onSemesterTypeChanged?.call('EVEN');
                    },
                  ),
                  const SizedBox(width: 6),

                  // Divider
                  Container(
                    height: 20,
                    width: 1,
                    color: isDark ? Colors.white24 : Colors.grey.shade300,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                  const SizedBox(width: 6),

                  // Individual Semester Chips: Sem 1 through Sem 8
                  ...List.generate(8, (i) {
                    final semNum = i + 1;
                    final isOdd = semNum % 2 != 0;
                    final isSelected = selectedSemester == semNum;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _buildSemesterChip(
                        label: 'Sem $semNum',
                        isSelected: isSelected,
                        isDark: isDark,
                        activeColor: isOdd ? const Color(0xFF10B981) : const Color(0xFF8B5CF6),
                        onTap: () {
                          if (isSelected) {
                            onSemesterChanged?.call(null);
                            onSemesterTypeChanged?.call('ALL');
                          } else {
                            onSemesterChanged?.call(semNum);
                            onSemesterTypeChanged?.call(isOdd ? 'ODD' : 'EVEN');
                          }
                        },
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),

          // -------------------------------------------------------------
          // DETAILED FILTERS ROW (Dept, Batch, Section, Face ID, Status, Reset)
          // -------------------------------------------------------------
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Department Filter (Selectable for Admin, Locked badge for HOD)
                if (isAdmin) ...[
                  _buildDropdown<String>(
                    label: 'Dept',
                    value: selectedDept,
                    items: departments,
                    onChanged: (v) => onDeptChanged?.call(v ?? 'ALL'),
                    isDark: isDark,
                  ),
                  const SizedBox(width: 8),
                ] else if (isHod) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: primaryBlue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: primaryBlue.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.domain_rounded, size: 14, color: primaryBlue),
                        const SizedBox(width: 4),
                        Text(
                          'Dept: $selectedDept',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: primaryBlue,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                ],

                // Batch Filter (Admin and HOD only - Staff advised class is set via banner)
                if (!isStaff) ...[
                  _buildDropdown<String>(
                    label: 'Batch',
                    value: selectedBatch,
                    items: (availableBatches != null && availableBatches!.isNotEmpty)
                        ? ['ALL', ...availableBatches!.where((b) => b != 'ALL')]
                        : batches,
                    onChanged: (v) => onBatchChanged?.call(v ?? 'ALL'),
                    isDark: isDark,
                  ),
                  const SizedBox(width: 8),
                ],

                // Section Filter (Admin and HOD only)
                if (!isStaff) ...[
                  _buildDropdown<String>(
                    label: 'Section',
                    value: selectedSection,
                    items: ['ALL', 'A', 'B', 'C', 'D'],
                    onChanged: (v) => onSectionChanged?.call(v ?? 'ALL'),
                    isDark: isDark,
                  ),
                  const SizedBox(width: 8),
                ],

                // Biometrics Status Filter
                _buildDropdown<String>(
                  label: 'Face Biometrics',
                  value: selectedFaceStatus,
                  items: const ['ALL', 'ENROLLED', 'MISSING'],
                  displayMap: const {
                    'ALL': 'Face: All',
                    'ENROLLED': 'Face Enrolled',
                    'MISSING': 'Missing Face ID',
                  },
                  onChanged: (v) => onFaceStatusChanged?.call(v ?? 'ALL'),
                  isDark: isDark,
                ),
                const SizedBox(width: 8),

                // Account Status Filter
                _buildDropdown<String>(
                  label: 'Status',
                  value: selectedAccountStatus,
                  items: const ['ALL', 'ACTIVE', 'SUSPENDED'],
                  displayMap: const {
                    'ALL': 'Status: All',
                    'ACTIVE': 'Active Only',
                    'SUSPENDED': 'Suspended',
                  },
                  onChanged: (v) => onAccountStatusChanged?.call(v ?? 'ALL'),
                  isDark: isDark,
                ),
                const SizedBox(width: 8),

                // Reset Filters Button
                TextButton.icon(
                  onPressed: onClearFilters,
                  icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
                  label: const Text('Reset All', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSemesterChip({
    required String label,
    required bool isSelected,
    required bool isDark,
    Color activeColor = const Color(0xFF2563EB),
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? activeColor
                : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9)),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? activeColor
                  : (isDark ? Colors.white12 : Colors.grey.shade300),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected
                  ? Colors.white
                  : (isDark ? Colors.white70 : Colors.black87),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDropdown<T>({
    required String label,
    required T value,
    required List<T> items,
    Map<T, String>? displayMap,
    required ValueChanged<T?> onChanged,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.grey.shade300,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: items.contains(value) ? value : items.first,
          isDense: true,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black87,
          ),
          items: items
              .map((item) => DropdownMenuItem<T>(
                    value: item,
                    child: Text(displayMap?[item] ?? '$item'),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
