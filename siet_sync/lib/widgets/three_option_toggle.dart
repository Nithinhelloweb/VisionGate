import 'package:flutter/material.dart';

class ThreeToggleOption<T> {
  final T value;
  final String label;
  final IconData icon;

  const ThreeToggleOption({
    required this.value,
    required this.label,
    required this.icon,
  });
}

class ThreeOptionToggle<T> extends StatelessWidget {
  final List<ThreeToggleOption<T>> options;
  final T selectedValue;
  final ValueChanged<T> onChanged;
  final bool isDark;
  final bool showLabels;

  const ThreeOptionToggle({
    super.key,
    required this.options,
    required this.selectedValue,
    required this.onChanged,
    required this.isDark,
    this.showLabels = true,
  }) : assert(options.length == 3, 'ThreeOptionToggle requires exactly 3 options');

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: options.map((option) {
          final isSelected = option.value == selectedValue;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(option.value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                padding: EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: showLabels ? 8 : 4,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    Icon(
                      option.icon,
                      size: showLabels ? 18 : 20,
                      color: isSelected
                          ? Colors.black
                          : (isDark ? Colors.white60 : Colors.grey[600]),
                    ),
                    if (showLabels) ...[
                      const SizedBox(width: 6),
                      Text(
                        option.label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.normal,
                          color: isSelected
                              ? Colors.black
                              : (isDark ? Colors.white60 : Colors.grey[600]),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
