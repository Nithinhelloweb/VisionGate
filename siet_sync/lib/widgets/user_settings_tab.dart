import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/college_ip_config.dart';
import '../services/theme_service.dart';
import 'three_option_toggle.dart';

String get API_URL => CollegeIPConfig.defaultURL;

class UserSettingsTab extends StatefulWidget {
  final String title;
  final String token;
  final Color accentColor;

  const UserSettingsTab({
    super.key,
    required this.title,
    required this.token,
    this.accentColor = const Color(0xFF007AFF),
  });

  @override
  State<UserSettingsTab> createState() => _UserSettingsTabState();
}

class _UserSettingsTabState extends State<UserSettingsTab> {
  bool _isChangingPassword = false;
  bool _isThemeExpanded = false;

  void _showChangePasswordDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        String current = '';
        String newPass = '';
        String confirm = '';
        String? errorText;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Change Password'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Current Password',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => current = v,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'New Password',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => newPass = v,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Confirm New Password',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => confirm = v,
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        errorText!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: _isChangingPassword
                      ? null
                      : () async {
                          if (current.isEmpty ||
                              newPass.isEmpty ||
                              confirm.isEmpty) {
                            setDialogState(() {
                              errorText = 'All fields are required.';
                            });
                            return;
                          }
                          if (newPass.length < 6) {
                            setDialogState(() {
                              errorText = 'New password must be at least 6 characters.';
                            });
                            return;
                          }
                          if (newPass != confirm) {
                            setDialogState(() {
                              errorText = 'New passwords do not match.';
                            });
                            return;
                          }
                          if (current == newPass) {
                            setDialogState(() {
                              errorText = 'New password must be different.';
                            });
                            return;
                          }

                          setDialogState(() {
                            _isChangingPassword = true;
                            errorText = null;
                          });
                          try {
                            final response = await http.post(
                              Uri.parse('$API_URL/user/change_password'),
                              headers: {
                                'Authorization': 'Bearer ${widget.token}',
                                'Content-Type': 'application/json',
                              },
                              body: jsonEncode({
                                'current_password': current,
                                'new_password': newPass,
                                'confirm_password': confirm,
                              }),
                            );

                            if (response.statusCode == 200) {
                              if (dialogContext.mounted) {
                                Navigator.pop(dialogContext);
                              }
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Password changed. Please login again.',
                                    ),
                                  ),
                                );
                              }
                            } else {
                              String message = 'Failed to change password.';
                              try {
                                final data = jsonDecode(response.body);
                                message = data['detail'] ?? message;
                              } catch (_) {}
                              setDialogState(() {
                                errorText = message;
                              });
                            }
                          } catch (e) {
                            setDialogState(() {
                              errorText = 'Error: $e';
                            });
                          } finally {
                            setDialogState(() {
                              _isChangingPassword = false;
                            });
                          }
                        },
                  child: const Text('Update'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeService,
      builder: (context, _) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final accent = widget.accentColor;
        final screenWidth = MediaQuery.sizeOf(context).width;
        final isCompact = screenWidth < 360;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.3 : 0.08,
                      ),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.settings, color: accent, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                          ),
                          Text(
                            'Customize your app experience',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: isDark
                                      ? Colors.white60
                                      : Colors.grey[600],
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Icon(Icons.security, color: accent, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Security',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.3 : 0.08,
                      ),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.lock, color: accent),
                  ),
                  title: Text(
                    'Change Password',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  subtitle: Text(
                    'Update your account password',
                    style: TextStyle(
                      color: isDark ? Colors.white60 : Colors.grey[600],
                    ),
                  ),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: isDark ? Colors.white60 : Colors.grey[400],
                  ),
                  onTap: _showChangePasswordDialog,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Icon(Icons.palette, color: accent, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Appearance',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.3 : 0.08,
                      ),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      themeService.isSystemMode
                          ? Icons.settings_suggest
                          : (isDark ? Icons.dark_mode : Icons.light_mode),
                      color: accent,
                    ),
                  ),
                  title: Text(
                    'Theme',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  subtitle: Text(
                    themeService.isSystemMode
                        ? 'Following system theme'
                        : (isDark ? 'Dark theme' : 'Light theme'),
                    style: TextStyle(
                      color: isDark ? Colors.white60 : Colors.grey[600],
                    ),
                  ),
                  trailing: AnimatedRotation(
                    turns: _isThemeExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      color: isDark ? Colors.white60 : Colors.grey[400],
                    ),
                  ),
                  onTap: () {
                    setState(() {
                      _isThemeExpanded = !_isThemeExpanded;
                    });
                  },
                ),
              ),
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: _buildInlineThemeSelector(isDark, isCompact),
                crossFadeState: _isThemeExpanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 200),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInlineThemeSelector(bool isDark, bool isCompact) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ThreeOptionToggle<ThemeMode>(
            options: const [
              ThreeToggleOption(
                value: ThemeMode.light,
                label: 'Light',
                icon: Icons.light_mode,
              ),
              ThreeToggleOption(
                value: ThemeMode.dark,
                label: 'Dark',
                icon: Icons.dark_mode,
              ),
              ThreeToggleOption(
                value: ThemeMode.system,
                label: 'System',
                icon: Icons.settings_suggest,
              ),
            ],
            selectedValue: themeService.themeMode,
            onChanged: themeService.setThemeMode,
            isDark: isDark,
            showLabels: !isCompact,
          ),
        ],
      ),
    );
  }
}
