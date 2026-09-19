import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../services/background_service_handler.dart';
import '../services/location_tracking_service.dart';
import 'oem_autostart_helper.dart';

/// Compact service-health status card shown on role dashboards.
///
/// States:
///  • Standby   (Blue)  — Attendance not yet marked; sync starts on check-in.
///  • Active    (Green) — Check-in marked & within tracking window duration.
///  • Completed (Slate) — Check-out marked or tracking duration window ended.
///  • Paused    (Amber) — Service interrupted during active window; tap to auto-heal.
class ServiceHealthCard extends StatefulWidget {
  const ServiceHealthCard({super.key});

  @override
  State<ServiceHealthCard> createState() => _ServiceHealthCardState();
}

class _ServiceHealthCardState extends State<ServiceHealthCard> {
  bool _running = false;
  bool _batteryExempt = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
    LocationTrackingService.instance.ensureTrackingActive().then((_) {
      if (mounted) _refresh();
    });
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final status = await BackgroundLocationService.getServiceStatus();
      await LocationTrackingService.instance.checkTrackingActive();
      if (mounted) {
        setState(() {
          _running = status.running;
          _batteryExempt = status.batteryExempt;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleTap(_StatusLevel level) async {
    if (level == _StatusLevel.warning) {
      await BackgroundLocationService.requestBatteryOptimisationExemption();
      await Future.delayed(const Duration(seconds: 1));
      await _refresh();
      if (mounted && !_batteryExempt) {
        final launched = await OemAutostartHelper.launchOemBatterySettings();
        if (!launched && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Open battery settings and disable optimisation for VisionGate.'),
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    } else if (level == _StatusLevel.error) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Restarting location sync…'),
          duration: Duration(seconds: 2),
        ),
      );
      setState(() => _loading = true);
      await LocationTrackingService.instance.ensureTrackingActive();
      await Future.delayed(const Duration(milliseconds: 800));
      await _refresh();
    } else {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const SizedBox.shrink();
    }

    final ColorScheme cs = Theme.of(context).colorScheme;

    return ValueListenableBuilder<TrackingLifecycleState>(
      valueListenable: LocationTrackingService.instance.lifecycleState,
      builder: (context, lifecycle, _) {
        final winEnd = LocationTrackingService.instance.windowEndTime.value ?? '17:30';
        
        final _StatusLevel level;
        if (_loading) {
          level = _StatusLevel.loading;
        } else if (lifecycle == TrackingLifecycleState.standbyWaitingCheckIn) {
          level = _StatusLevel.standby;
        } else if (lifecycle == TrackingLifecycleState.completedForToday) {
          level = _StatusLevel.completed;
        } else if (lifecycle == TrackingLifecycleState.activeInWindow) {
          if (!_running) {
            level = _StatusLevel.error;
          } else if (!_batteryExempt) {
            level = _StatusLevel.warning;
          } else {
            level = _StatusLevel.ok;
          }
        } else {
          level = _StatusLevel.error;
        }

        final primaryColor = _levelColor(level, cs);
        final title = _titleFor(level);
        final subtitle = _subtitleFor(level, winEnd);
        final isClickable = level == _StatusLevel.warning || level == _StatusLevel.error;

        return Semantics(
          label: '$title. $subtitle',
          button: isClickable,
          child: GestureDetector(
            onTap: () => _handleTap(level),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: primaryColor.withValues(alpha: 0.30),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  _StatusDot(color: primaryColor, pulsing: level == _StatusLevel.loading || level == _StatusLevel.ok),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            fontStyle: FontStyle.normal,
                            color: primaryColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w400,
                            color: cs.onSurface.withValues(alpha: 0.70),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isClickable)
                    Icon(Icons.chevron_right_rounded, size: 18, color: primaryColor)
                  else
                    Icon(Icons.sync_rounded, size: 16, color: primaryColor.withValues(alpha: 0.6)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Color _levelColor(_StatusLevel level, ColorScheme cs) {
    return switch (level) {
      _StatusLevel.ok => const Color(0xFF16A34A),        // green-600
      _StatusLevel.standby => const Color(0xFF2563EB),   // blue-600
      _StatusLevel.completed => const Color(0xFF64748B), // slate-500
      _StatusLevel.warning => const Color(0xFFD97706),   // amber-600
      _StatusLevel.error => const Color(0xFFDC2626),     // red-600
      _StatusLevel.loading => cs.onSurface.withValues(alpha: 0.50),
    };
  }

  String _titleFor(_StatusLevel level) {
    return switch (level) {
      _StatusLevel.ok => 'Location sync active',
      _StatusLevel.standby => 'Location sync on standby',
      _StatusLevel.completed => 'Tracking ended for today',
      _StatusLevel.warning => 'Battery optimisation active',
      _StatusLevel.error => 'Location sync paused',
      _StatusLevel.loading => 'Checking sync status…',
    };
  }

  String _subtitleFor(_StatusLevel level, String winEnd) {
    return switch (level) {
      _StatusLevel.ok => 'Tracking active until $winEnd',
      _StatusLevel.standby => 'Starts automatically after attendance check-in',
      _StatusLevel.completed => 'Completed at $winEnd',
      _StatusLevel.warning => 'Tap to exempt VisionGate for continuous sync',
      _StatusLevel.error => 'Tap to restart background sync',
      _StatusLevel.loading => 'Connecting to service…',
    };
  }
}

enum _StatusLevel { ok, standby, completed, warning, error, loading }

class _StatusDot extends StatefulWidget {
  final Color color;
  final bool pulsing;
  const _StatusDot({required this.color, required this.pulsing});

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.pulsing) {
      _ctrl.repeat(reverse: true);
    }
    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(covariant _StatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulsing != oldWidget.pulsing) {
      if (widget.pulsing) {
        _ctrl.repeat(reverse: true);
      } else {
        _ctrl.stop();
        _ctrl.value = 1.0;
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: widget.pulsing
              ? widget.color.withValues(alpha: _anim.value)
              : widget.color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: widget.pulsing ? _anim.value * 0.4 : 0.25),
              blurRadius: 4,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}
