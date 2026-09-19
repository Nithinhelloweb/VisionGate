import 'package:flutter/material.dart';

class Breakpoints {
  static const double mobile = 600;
  static const double tablet = 900;
  static const double desktop = 1280;
  static const double largeDesktop = 1600;

  static bool isMobile(double width) => width < mobile;
  static bool isTablet(double width) => width >= mobile && width < desktop;
  static bool isDesktop(double width) => width >= desktop;
  static bool isLargeDesktop(double width) => width >= largeDesktop;

  static int gridCrossAxisCount(double width) {
    if (width < mobile) return 2;
    if (width < tablet) return 3;
    if (width < desktop) return 3;
    if (width < largeDesktop) return 4;
    return 5;
  }

  static double contentMaxWidth(double width) {
    if (width < desktop) return double.infinity;
    if (width < largeDesktop) return 1200;
    return 1400;
  }

  static double pagePadding(double width) {
    if (width < mobile) return 12;
    if (width < desktop) return 20;
    return 32;
  }

  static double gridSpacing(double width) {
    if (width < mobile) return 12;
    if (width < desktop) return 16;
    return 20;
  }
}

class ResponsiveBuilder extends StatelessWidget {
  final Widget Function(BuildContext context, BoxConstraints constraints)
  builder;
  const ResponsiveBuilder({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: builder);
  }
}

class AdaptiveScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavDestination> destinations;
  final Widget? drawer;
  final Color? accentColor;
  final String title;
  final List<Widget>? appBarActions;
  final VoidCallback? onLogout;
  final Widget? floatingActionButton;

  const AdaptiveScaffold({
    super.key,
    this.appBar,
    required this.body,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    this.drawer,
    this.accentColor,
    required this.title,
    this.appBarActions,
    this.onLogout,
    this.floatingActionButton,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    // Treat wider tablets and desktops as rail layouts for better responsiveness.
    final useRail = width >= 900;
    // Always show extended rail (full labels) when using rail.
    final shouldExtend = useRail;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = accentColor ?? Theme.of(context).primaryColor;

    if (useRail) {
      return Scaffold(
        body: Row(
          children: [
            _DesktopRail(
              selectedIndex: selectedIndex,
              onDestinationSelected: onDestinationSelected,
              destinations: destinations,
              extended: shouldExtend,
              accentColor: accent,
              isDark: isDark,
              onLogout: onLogout,
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(child: body),
          ],
        ),
        floatingActionButton: floatingActionButton,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        backgroundColor: isDark
            ? const Color(0xFF000000)
            : const Color(0xFFF2F2F7),
        elevation: 0,
        foregroundColor: isDark ? Colors.white : Colors.black,
        leading: Builder(
          builder: (context) => Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: IconButton(
              icon: Icon(
                Icons.menu,
                color: isDark ? Colors.white : Colors.black,
              ),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
        ),
        actions:
            appBarActions ??
            [
              if (onLogout != null)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: IconButton(
                    icon: Icon(
                      Icons.logout,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                    onPressed: onLogout,
                  ),
                ),
            ],
      ),
      drawer: drawer,
      body: body,
      floatingActionButton: floatingActionButton,
    );
  }
}

class NavDestination {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final String? sectionHeader;

  const NavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.sectionHeader,
  });
}

class _DesktopRail extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavDestination> destinations;
  final bool extended;
  final Color accentColor;
  final bool isDark;
  final VoidCallback? onLogout;

  const _DesktopRail({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    required this.extended,
    required this.accentColor,
    required this.isDark,
    this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isDark ? const Color(0xFF0F172A) : Colors.white;
    final borderColor = isDark ? Colors.white10 : Colors.grey.shade200;

    return Container(
      width: extended ? 240.0 : 72.0,
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          right: BorderSide(color: borderColor, width: 1.0),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // App Header Branding
            if (extended)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [accentColor, accentColor.withValues(alpha: 0.8)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.school_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'VisionGate',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          Text(
                            'Institutional Portal',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: isDark ? Colors.white54 : Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.school_rounded, color: accentColor, size: 20),
                ),
              ),

            Divider(color: borderColor, height: 1),

            // Scrollable Navigation List with Section Sub-Headings
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.symmetric(
                  horizontal: extended ? 10 : 6,
                  vertical: 8,
                ),
                itemCount: destinations.length,
                itemBuilder: (context, index) {
                  final item = destinations[index];
                  final isSelected = selectedIndex == index;

                  // Check if this item has a section header
                  Widget? headerWidget;
                  if (item.sectionHeader != null) {
                    if (extended) {
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
                            color: isDark ? Colors.white38 : Colors.grey.shade500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    } else {
                      headerWidget = Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Divider(
                          color: isDark ? Colors.white12 : Colors.grey.shade200,
                          thickness: 1,
                          indent: 8,
                          endIndent: 8,
                        ),
                      );
                    }
                  }

                  final itemTile = extended
                      ? Container(
                          margin: const EdgeInsets.symmetric(vertical: 2),
                          child: Material(
                            color: isSelected
                                ? accentColor.withValues(alpha: isDark ? 0.2 : 0.1)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            child: InkWell(
                              onTap: () => onDestinationSelected(index),
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
                                          ? accentColor
                                          : (isDark ? Colors.white60 : Colors.grey.shade600),
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
                                              ? accentColor
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
                                  ? accentColor.withValues(alpha: isDark ? 0.25 : 0.12)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              child: InkWell(
                                onTap: () => onDestinationSelected(index),
                                borderRadius: BorderRadius.circular(10),
                                child: SizedBox(
                                  width: 48,
                                  height: 42,
                                  child: Icon(
                                    isSelected ? item.selectedIcon : item.icon,
                                    color: isSelected
                                        ? accentColor
                                        : (isDark ? Colors.white60 : Colors.grey.shade500),
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

            // Logout Action
            if (onLogout != null) ...[
              Divider(color: borderColor, height: 1),
              Padding(
                padding: EdgeInsets.all(extended ? 10 : 8),
                child: extended
                    ? Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: onLogout,
                          borderRadius: BorderRadius.circular(10),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.logout_rounded,
                                  color: Color(0xFFEF4444),
                                  size: 18,
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  'Sign Out',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFEF4444),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : Tooltip(
                        message: 'Sign Out',
                        child: IconButton(
                          icon: const Icon(
                            Icons.logout_rounded,
                            color: Color(0xFFEF4444),
                            size: 20,
                          ),
                          onPressed: onLogout,
                        ),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ResponsiveContent extends StatelessWidget {
  final Widget child;
  final double? maxWidth;
  final EdgeInsetsGeometry? padding;

  const ResponsiveContent({
    super.key,
    required this.child,
    this.maxWidth,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final maxW = maxWidth ?? Breakpoints.contentMaxWidth(width);
    final pad = padding ?? EdgeInsets.all(Breakpoints.pagePadding(width));

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: Padding(padding: pad, child: child),
      ),
    );
  }
}

class ResponsiveGrid extends StatelessWidget {
  final List<Widget> children;
  final double? childAspectRatio;
  final double? maxCrossAxisExtent;

  const ResponsiveGrid({
    super.key,
    required this.children,
    this.childAspectRatio,
    this.maxCrossAxisExtent,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final crossAxisCount = Breakpoints.gridCrossAxisCount(width);
    final spacing = Breakpoints.gridSpacing(width);

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: crossAxisCount,
      crossAxisSpacing: spacing,
      mainAxisSpacing: spacing,
      childAspectRatio:
          childAspectRatio ?? (Breakpoints.isMobile(width) ? 1.15 : 1.1),
      children: children,
    );
  }
}
