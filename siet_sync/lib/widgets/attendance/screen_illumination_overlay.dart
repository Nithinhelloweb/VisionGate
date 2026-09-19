import 'package:flutter/material.dart';
import '../../services/screen_illumination_service.dart';

/// Reusable illumination wrapper for camera viewfinder cards.
/// When screen illumination is active, it wraps the viewfinder in an animated,
/// high-luminance key-light softbox frame to physically illuminate the user's
/// face in low-light environments.
class ScreenIlluminationOverlay extends StatelessWidget {
  final Widget child;
  final bool isDark;
  final VoidCallback? onToggle;

  const ScreenIlluminationOverlay({
    super.key,
    required this.child,
    required this.isDark,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ScreenIlluminationService.instance.isIlluminatingNotifier,
      builder: (context, isIlluminating, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: ScreenIlluminationService.instance.isLowLightDetectedNotifier,
          builder: (context, isLowLight, _) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.all(isIlluminating ? 12.0 : 0.0),
              decoration: BoxDecoration(
                color: isIlluminating ? const Color(0xFFFFFFFD) : Colors.transparent,
                borderRadius: BorderRadius.circular(isIlluminating ? 32 : 24),
                boxShadow: isIlluminating
                    ? [
                        BoxShadow(
                          color: const Color(0xFFFFFFFF).withValues(alpha: 0.85),
                          blurRadius: 36,
                          spreadRadius: 10,
                        ),
                        BoxShadow(
                          color: const Color(0xFFFFF9E6).withValues(alpha: 0.6),
                          blurRadius: 60,
                          spreadRadius: 20,
                        ),
                      ]
                    : null,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  child,
                  if (isIlluminating || isLowLight) ...[
                    const SizedBox(height: 10),
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: (isIlluminating || isLowLight) ? 1.0 : 0.0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: isIlluminating
                              ? const Color(0xFF1E293B)
                              : (isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9)),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isIlluminating
                                ? const Color(0xFFFBBF24)
                                : (isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1)),
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isIlluminating ? Icons.wb_sunny_rounded : Icons.light_mode_outlined,
                              color: isIlluminating ? const Color(0xFFFBBF24) : Colors.amber[700],
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isIlluminating
                                  ? (isLowLight
                                      ? "Low light detected — Screen illumination active"
                                      : "Screen illumination active")
                                  : "Low light environment detected",
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                fontStyle: FontStyle.normal,
                                color: isIlluminating ? Colors.white : (isDark ? Colors.white70 : const Color(0xFF1E293B)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Standalone button to manually toggle screen illumination in viewfinder headers
class ScreenIlluminationToggleButton extends StatelessWidget {
  final VoidCallback? onToggled;

  const ScreenIlluminationToggleButton({
    super.key,
    this.onToggled,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ScreenIlluminationService.instance.isIlluminatingNotifier,
      builder: (context, isIlluminating, _) {
        return Container(
          decoration: BoxDecoration(
            color: isIlluminating
                ? const Color(0xFFFBBF24)
                : Colors.black.withValues(alpha: 0.45),
            shape: BoxShape.circle,
            border: Border.all(
              color: isIlluminating ? Colors.white : Colors.white24,
              width: 1.5,
            ),
          ),
          child: IconButton(
            icon: Icon(
              isIlluminating ? Icons.wb_sunny_rounded : Icons.wb_sunny_outlined,
              color: isIlluminating ? const Color(0xFF1E293B) : Colors.white,
              size: 18,
            ),
            tooltip: isIlluminating ? "Disable Screen Flash" : "Enable Screen Flash",
            onPressed: () async {
              await ScreenIlluminationService.instance.toggle();
              onToggled?.call();
            },
          ),
        );
      },
    );
  }
}
