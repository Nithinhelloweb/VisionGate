import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/platform_utils.dart';

class LocationPermissionEnforcer extends StatefulWidget {
  final Widget child;

  const LocationPermissionEnforcer({
    super.key,
    required this.child,
  });

  @override
  State<LocationPermissionEnforcer> createState() => _LocationPermissionEnforcerState();
}

class _LocationPermissionEnforcerState extends State<LocationPermissionEnforcer> with WidgetsBindingObserver {
  bool _isChecking = true;
  bool _gpsEnabled = false;
  bool _alwaysPermissionGranted = false;
  bool _notificationPermissionGranted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions(showLoading: false);
    }
  }

  Future<void> _checkPermissions({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() => _isChecking = true);
    }
    try {
      final gpsEnabled = await Geolocator.isLocationServiceEnabled();
      final permission = await Geolocator.checkPermission();
      
      // On Android 13+, check notification permission
      bool notificationGranted = true;
      if (await Permission.notification.status.isDenied) {
        notificationGranted = false;
      } else {
        notificationGranted = await Permission.notification.isGranted;
      }

      final alwaysGranted = permission == LocationPermission.always;

      if (mounted) {
        setState(() {
          _gpsEnabled = gpsEnabled;
          _alwaysPermissionGranted = alwaysGranted;
          _notificationPermissionGranted = notificationGranted;
          _isChecking = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isChecking = false);
      }
    }
  }

  Future<void> _requestAlwaysPermission() async {
    // 1. Request standard permission (while in use) if not already granted
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    // 2. Request always permission if currently in use
    if (permission == LocationPermission.whileInUse) {
      await Permission.locationAlways.request();
    }

    // 3. Request notification permission for background service notification
    if (await Permission.notification.status.isDenied || 
        await Permission.notification.status.isPermanentlyDenied) {
      await Permission.notification.request();
    }

    await _checkPermissions();
  }

  @override
  Widget build(BuildContext context) {
    // Only enforce mobile-specific background permissions on Android/iOS
    if (!AppPlatform.isMobile) {
      return widget.child;
    }

    if (_isChecking) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            color: Color(0xFF6366F1),
          ),
        ),
      );
    }

    final hasAllPermissions = _gpsEnabled && _alwaysPermissionGranted && _notificationPermissionGranted;

    if (hasAllPermissions) {
      return widget.child;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = const Color(0xFF6366F1);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Beautiful warning illustration/icon
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.location_off_rounded,
                      size: 72,
                      color: primaryColor,
                    ),
                  ),
                  const SizedBox(height: 32),
                  
                  // Title
                  Text(
                    'Always-On Location Required',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  
                  // Description
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Text(
                      'To prevent moving outside the attendance boundary, VisionGate requires Always-On Location access. This runs verified tracking even when the app is closed or in the background.',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white70 : Colors.grey[600],
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 32),
                  
                  // Status card checklist
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        _buildStatusRow(
                          title: 'Location Service (GPS)',
                          isGranted: _gpsEnabled,
                          isDark: isDark,
                        ),
                        const Divider(height: 24),
                        _buildStatusRow(
                          title: 'Location Permission: Allow All Time',
                          isGranted: _alwaysPermissionGranted,
                          isDark: isDark,
                        ),
                        const Divider(height: 24),
                        _buildStatusRow(
                          title: 'Notifications (For Background Sync)',
                          isGranted: _notificationPermissionGranted,
                          isDark: isDark,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                  
                  // Action buttons
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _requestAlwaysPermission,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Grant Permissions',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => openAppSettings(),
                    child: Text(
                      'Open Device Settings Manually',
                      style: TextStyle(
                        color: primaryColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusRow({
    required String title,
    required bool isGranted,
    required bool isDark,
  }) {
    return Row(
      children: [
        Icon(
          isGranted ? Icons.check_circle_rounded : Icons.cancel_rounded,
          color: isGranted ? const Color(0xFF10B981) : const Color(0xFFEF4444),
          size: 24,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white70 : Colors.grey[800],
            ),
          ),
        ),
      ],
    );
  }
}
