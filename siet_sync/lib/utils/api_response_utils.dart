import 'dart:convert';

class ApiResponseUtils {
  static Map<String, dynamic>? tryParseJson(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static String sanitize(dynamic error) {
    if (error == null) return 'An unexpected error occurred. Please try again.';
    
    final errStr = error.toString().trim();
    final lower = errStr.toLowerCase();

    // Connection/socket/refused/network errors
    if (lower.contains('socketexception') || 
        lower.contains('connection refused') || 
        lower.contains('failed host lookup') || 
        lower.contains('clientexception') ||
        lower.contains('xmlhttprequest error') ||
        lower.contains('connection failed') ||
        lower.contains('network_error') ||
        lower.contains('http status')) {
      return 'Unable to connect to the server. Please check your internet connection and verify that the API server is online.';
    }

    // JSON/format errors
    if (lower.contains('formatexception') || lower.contains('unexpected character')) {
      return 'Received an invalid response format from the server. Please try again.';
    }

    // Timeout
    if (lower.contains('timeout') || lower.contains('time out')) {
      return 'The request timed out. Please check your network stability and try again.';
    }

    // Database or specific internal terms we want to hide
    if (lower.contains('operator does not exist') || 
        lower.contains('pg_adapter') || 
        lower.contains('psycopg2') || 
        lower.contains('sqlite') || 
        lower.contains('traceback') ||
        lower.contains('stacktrace') ||
        lower.contains('line ') ||
        (lower.contains('error code:') && !lower.contains('1033'))) {
      return 'A database schema or query error occurred. Please contact the system administrator.';
    }

    // If it starts with standard Exception prefixes, strip them
    String cleaned = errStr;
    if (lower.startsWith('exception:') || lower.startsWith('error:')) {
      cleaned = errStr.replaceAll(RegExp(r'^(Exception:|Error:)\s*', caseSensitive: false), '').trim();
    }
    if (cleaned.startsWith('Connection error:')) {
      cleaned = cleaned.replaceAll(RegExp(r'^Connection error:\s*', caseSensitive: false), '').trim();
    }

    // If the message is still very long or looks like stack/system log, fallback to a clean message
    if (cleaned.length > 120 || cleaned.contains('\n') || cleaned.contains('    at ') || cleaned.contains(r'$_')) {
      return 'The request could not be processed due to a server error. Please try again or contact support.';
    }

    return cleaned.isNotEmpty ? cleaned : 'An unexpected error occurred.';
  }

  static String nonJsonErrorMessage(int statusCode, String rawBody) {
    final trimmed = rawBody.trim();
    if (trimmed.isEmpty) {
      return 'Server returned an empty response (HTTP $statusCode).';
    }

    final lower = trimmed.toLowerCase();
    if (lower.contains('error code: 1033') || lower.contains('error 1033')) {
      return 'The server tunnel or connection domain is currently unavailable. Please verify the backend service status.';
    }

    if (trimmed.startsWith('<!DOCTYPE html') || trimmed.startsWith('<html')) {
      return 'A server configuration or database error occurred (HTTP $statusCode). Please contact the system administrator.';
    }

    return sanitize(trimmed);
  }
}
