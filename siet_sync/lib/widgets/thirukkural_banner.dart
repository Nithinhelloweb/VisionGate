import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../utils/wifi_check.dart';

class ThirukkuralBanner extends StatefulWidget {
  const ThirukkuralBanner({super.key});

  @override
  State<ThirukkuralBanner> createState() => _ThirukkuralBannerState();
}

class _ThirukkuralBannerState extends State<ThirukkuralBanner> {
  Map<String, dynamic>? _dailyKural;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _isLoading = AppSettings.enableThirukkural;
    _initAndLoad();
  }

  Future<void> _initAndLoad() async {
    await AppSettings.hydrateThirukkuralFlag();
    if (!AppSettings.enableThirukkural) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      return;
    }
    await AppSettings.loadSettings();
    if (mounted && AppSettings.enableThirukkural) {
      await _loadDailyKural();
    } else if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadDailyKural() async {
    try {
      final String jsonString = await rootBundle.loadString('assets/thirukkural.json');
      final List<dynamic> kurals = jsonDecode(jsonString);

      if (kurals.isNotEmpty) {
        // Calculate days since a fixed epoch to ensure all devices show the same Kural daily
        final epoch = DateTime(2024, 1, 1);
        final now = DateTime.now();
        final int daysSinceEpoch = now.difference(epoch).inDays;
        
        // Use modulo to cycle through the 1330 kurals
        final int kuralIndex = daysSinceEpoch % kurals.length;

        if (mounted) {
          setState(() {
            _dailyKural = kurals[kuralIndex];
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error loading Thirukkural: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppSettings.thirukkuralNotifier,
      builder: (context, enabled, child) {
        if (!enabled) {
          return const SizedBox.shrink();
        }

        if (_dailyKural == null && !_isLoading) {
          _loadDailyKural();
        }

        if (_isLoading) {
          return const SizedBox(
            height: 100,
            child: Center(child: CircularProgressIndicator()),
          );
        }

    if (_dailyKural == null) {
      return const SizedBox.shrink(); // Hide if error
    }

    // Ensure strict 2 lines format (4 words first line, 3 words second line ideally handled by JSON already)
    final String line1 = _dailyKural!['line1'] ?? '';
    final String line2 = _dailyKural!['line2'] ?? '';
    final String adhigaram = _dailyKural!['adhigaram'] ?? '';
    final int no = _dailyKural!['no'] ?? 0;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.shade50, Colors.deepOrange.shade50],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Icon(Icons.auto_stories, color: Colors.orange.shade700, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'தினம் ஒரு குறள் - குறள் $no',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade800,
                  ),
                  textAlign: TextAlign.left,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line1,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.left,
                ),
                Text(
                  line2,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.left,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            adhigaram,
            style: TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: Colors.grey.shade700,
            ),
            textAlign: TextAlign.left,
          ),
        ],
      ),
    );
      },
    );
  }
}
