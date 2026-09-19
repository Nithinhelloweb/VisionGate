import 'package:flutter/material.dart';

// Data class for drawer items
class DrawerItem {
  final int index;
  final IconData icon;
  final String title;

  const DrawerItem({
    required this.index,
    required this.icon,
    required this.title,
  });
}

// Quick Access Stat Card - Redirect to tab when clicked (no embedded widget)
class QuickAccessStatCard extends StatefulWidget {
  final List<DrawerItem> availableItems;
  final int? selectedIndex;
  final Function(int) onItemSelected;
  final VoidCallback onRemove;
  final Function(int)? onWidgetTap; // Callback when card is clicked after selection
  final Color accentColor;

  const QuickAccessStatCard({
    super.key,
    required this.availableItems,
    this.selectedIndex,
    required this.onItemSelected,
    required this.onRemove,
    this.onWidgetTap,
    this.accentColor = Colors.blue,
  });

  @override
  State<QuickAccessStatCard> createState() => _QuickAccessStatCardState();
}

class _QuickAccessStatCardState extends State<QuickAccessStatCard> {
  void _showSelectionDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Add Quick Access Widget',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: widget.availableItems.length,
                  itemBuilder: (context, index) {
                    final item = widget.availableItems[index];
                    return ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: widget.accentColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(item.icon, color: widget.accentColor),
                      ),
                      title: Text(item.title),
                      trailing: widget.selectedIndex == item.index
                          ? Icon(Icons.check_circle, color: widget.accentColor)
                          : null,
                      onTap: () {
                        widget.onItemSelected(item.index);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 400;

    // Find the selected item
    final selectedItem = widget.selectedIndex != null
        ? widget.availableItems.firstWhere(
            (item) => item.index == widget.selectedIndex,
            orElse: () => widget.availableItems.first,
          )
        : null;

    final isSelected = widget.selectedIndex != null;

    return GestureDetector(
      onTap: () {
        if (isSelected && widget.onWidgetTap != null) {
          // When selected and onWidgetTap is provided, trigger the callback
          widget.onWidgetTap!(widget.selectedIndex!);
        } else if (!isSelected) {
          // When not selected, show the selection dialog
          _showSelectionDialog();
        }
      },
      child: Container(
        height: 120, // Reduced height since we don't embed widget anymore
        decoration: BoxDecoration(
          color: isDark 
              ? Colors.grey[900] 
              : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: widget.accentColor.withValues(alpha: 0.3),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: widget.accentColor.withValues(alpha: 0.1),
              blurRadius: 15,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: isSelected
              ? Column(
                  children: [
                    // Header with icon, title and remove button
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: widget.accentColor.withValues(alpha: 0.1),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: widget.accentColor.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              selectedItem?.icon ?? Icons.widgets,
                              size: 20,
                              color: widget.accentColor,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  selectedItem?.title ?? 'Widget',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.white : Color(0xFF1A1A2E),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Tap to open',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey[500],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Remove button
                          GestureDetector(
                            onTap: widget.onRemove,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.close,
                                size: 16,
                                color: Colors.red,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Bottom area with redirect hint
                    Expanded(
                      child: Container(
                        color: isDark ? Colors.grey[850] : Colors.grey[50],
                        child: Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.arrow_forward_ios,
                                size: 12,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Tap to navigate',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[500],
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.arrow_forward_ios,
                                size: 12,
                                color: Colors.grey[400],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : Stack(
                  children: [
                    // Show + button when nothing selected
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: widget.accentColor.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.add_rounded,
                                  size: isSmallScreen ? 20 : 22,
                                  color: widget.accentColor,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Add Widget',
                                style: TextStyle(
                                  fontSize: isSmallScreen ? 11 : 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Tap to add quick access',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey[500],
                                ),
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
    );
  }
}
