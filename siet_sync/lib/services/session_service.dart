import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Session data model containing login information
class SessionData {
  final String token;
  final Map<String, dynamic> user;
  final String role;
  final DateTime loginTime;
  final String? deviceSessionId;

  SessionData({
    required this.token,
    required this.user,
    required this.role,
    required this.loginTime,
    this.deviceSessionId,
  });

  Map<String, dynamic> toJson() => {
        'token': token,
        'user': user,
        'role': role,
        'loginTime': loginTime.toIso8601String(),
        'deviceSessionId': deviceSessionId,
      };

  factory SessionData.fromJson(Map<String, dynamic> json) => SessionData(
        token: json['token'],
        user: json['user'],
        role: json['role'],
        loginTime: DateTime.parse(json['loginTime']),
        deviceSessionId: json['deviceSessionId'],
      );
}

/// Persistent session service that maintains login until explicit logout
class SessionService {
  static const String _sessionKey = 'user_session';
  static const String _quickAccessIndexKey = 'quick_access_index';
  static final SessionService _instance = SessionService._internal();
  factory SessionService() => _instance;
  SessionService._internal();

  SharedPreferences? _prefs;

  /// Initialize shared preferences
  Future<void> _init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// Save session data - called after successful login
  Future<bool> saveSession(SessionData session) async {
    await _init();
    final jsonString = jsonEncode(session.toJson());
    return await _prefs!.setString(_sessionKey, jsonString);
  }

  /// Get stored session data - returns null if no session exists
  Future<SessionData?> getSession() async {
    await _init();
    final jsonString = _prefs!.getString(_sessionKey);
    if (jsonString == null) return null;

    try {
      final json = jsonDecode(jsonString);
      return SessionData.fromJson(json);
    } catch (e) {
      // Corrupted data - clear it
      await clearSession();
      return null;
    }
  }

  /// Clear session - called during logout
  Future<bool> clearSession() async {
    await _init();
    return await _prefs!.remove(_sessionKey);
  }

  /// Check if a valid session exists
  Future<bool> hasSession() async {
    final session = await getSession();
    return session != null;
  }

  /// Check if session exists and is valid (non-expired)
  /// Session stays valid until explicitly logged out
  Future<bool> isSessionValid() async {
    final session = await getSession();
    return session != null;
  }

  /// Get current user role from session
  Future<String?> getUserRole() async {
    final session = await getSession();
    return session?.role;
  }

  /// Get current token from session
  Future<String?> getToken() async {
    final session = await getSession();
    return session?.token;
  }

  /// Get current user data from session
  Future<Map<String, dynamic>?> getUser() async {
    final session = await getSession();
    return session?.user;
  }

  /// Save quick access widget index for persistent storage
  Future<bool> saveQuickAccessIndex(int index) async {
    await _init();
    return await _prefs!.setInt(_quickAccessIndexKey, index);
  }

  /// Get stored quick access widget index
  Future<int?> getQuickAccessIndex() async {
    await _init();
    return _prefs!.getInt(_quickAccessIndexKey);
  }

  /// Clear quick access widget index
  Future<bool> clearQuickAccessIndex() async {
    await _init();
    return await _prefs!.remove(_quickAccessIndexKey);
  }
}

// Default session service instance
final sessionService = SessionService();