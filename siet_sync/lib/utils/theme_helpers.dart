import 'package:flutter/material.dart';

/// Get the appropriate text color based on theme brightness
Color getTextColor(BuildContext context, {Color? darkColor, Color? lightColor}) {
  final brightness = Theme.of(context).brightness;
  if (brightness == Brightness.dark) {
    return darkColor ?? Colors.white;
  } else {
    return lightColor ?? Colors.black87;
  }
}

/// Get the appropriate subtitle/secondary text color based on theme brightness
Color getSubtitleColor(BuildContext context) {
  final brightness = Theme.of(context).brightness;
  return brightness == Brightness.dark ? Colors.white70 : Colors.grey[600]!;
}

/// Get the appropriate disabled/hint text color based on theme brightness
Color getHintColor(BuildContext context) {
  final brightness = Theme.of(context).brightness;
  return brightness == Brightness.dark ? Colors.white38 : Colors.grey[400]!;
}

/// Get the appropriate icon color based on theme brightness
Color getIconColor(BuildContext context) {
  final brightness = Theme.of(context).brightness;
  return brightness == Brightness.dark ? Colors.white70 : Colors.grey[600]!;
}

/// Get the appropriate card background color based on theme brightness
Color getCardColor(BuildContext context) {
  final brightness = Theme.of(context).brightness;
  return brightness == Brightness.dark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);
}
