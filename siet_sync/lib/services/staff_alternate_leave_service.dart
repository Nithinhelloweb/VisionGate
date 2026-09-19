import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/college_ip_config.dart';

/// Service layer for the staff leave alternate-assignment workflow.
/// Covers all 3 roles: staff (requester), alternate, and HOD/admin.
class StaffAlternateLeaveService {
  static String get _base => CollegeIPConfig.defaultURL;

  static Map<String, String> _headers(String token) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  static Map<String, dynamic> _errorResult(dynamic e) =>
      {'success': false, 'message': 'Network error: $e'};

  // ─────────────────────────────────────────────────────────────────────────
  // STAFF — SUBMIT & MANAGE OWN REQUESTS
  // ─────────────────────────────────────────────────────────────────────────

  /// Fetch all staff eligible to be nominated as alternate (cross-dept).
  static Future<Map<String, dynamic>> getEligibleAlternates(
      String token) async {
    try {
      final res = await http.get(
        Uri.parse('$_base/staff/leave/eligible-alternates'),
        headers: _headers(token),
      );
      return json.decode(res.body) as Map<String, dynamic>;
    } catch (e) {
      return _errorResult(e);
    }
  }

  /// Check if the logged-in staff member has scheduled classes for a date range
  static Future<Map<String, dynamic>> checkScheduledClasses({
    required String token,
    required String startDate,
    required String endDate,
    bool isHalfDay = false,
    String? whichHalf,
  }) async {
    try {
      final params = <String, String>{
        'start_date': startDate,
        'end_date': endDate,
        'is_half_day': isHalfDay.toString(),
      };
      if (whichHalf != null && whichHalf.isNotEmpty) {
        params['which_half'] = whichHalf;
      }
      final uri = Uri.parse('$_base/staff/leave/check-classes')
          .replace(queryParameters: params);
      final res = await http.get(uri, headers: _headers(token));
      return json.decode(res.body) as Map<String, dynamic>;
    } catch (e) {
      return _errorResult(e);
    }
  }

  /// Submit a new staff leave/OD request.
  /// If classes are scheduled on the dates, alternate fields are required.
  static Future<Map<String, dynamic>> submitLeaveRequest({
    required String token,
    required String leaveType,
    required String startDate,
    required String endDate,
    required String reason,
    String? alternateRegNo,
    String? alternateName,
    String? alternateDept,
    String? alternateRole,
    bool isHalfDay = false,
    String? whichHalf,
    String? documentUrl,
  }) async {
    try {
      final body = <String, dynamic>{
        'leave_type': leaveType,
        'start_date': startDate,
        'end_date': endDate,
        'reason': reason,
        'is_half_day': isHalfDay,
      };
      if (alternateRegNo != null && alternateRegNo.isNotEmpty) {
        body['alternate_reg_no'] = alternateRegNo;
        body['alternate_name'] = alternateName;
        body['alternate_dept'] = alternateDept;
        body['alternate_role'] = alternateRole;
      }
      if (isHalfDay && whichHalf != null) body['which_half'] = whichHalf;
      if (documentUrl != null) body['document_url'] = documentUrl;

      final res = await http.post(
        Uri.parse('$_base/staff/leave/request'),
        headers: _headers(token),
        body: jsonEncode(body),
      );
      return json.decode(res.body) as Map<String, dynamic>;
    } catch (e) {
      return _errorResult(e);
    }
  }

  /// Fetch all leave requests submitted by me.
  static Future<Map<String, dynamic>> getMyRequests(String token) async {
    try {
      final res = await http.get(
        Uri.parse('$_base/staff/leave/requests'),
        headers: _headers(token),
      );
      return json.decode(res.body) as Map<String, dynamic>;
    } catch (e) {
      return _errorResult(e);
    }
  }

  /// Full detail for a single request (includes timetable + audit).
  static Future<Map<String, dynamic>> getRequestDetail(
      String token, int requestId) async {
    try {
      final res = await http.get(
        Uri.parse('$_base/staff/leave/request/$requestId'),
        headers: _headers(token),
      );
      return json.decode(res.body) as Map<String, dynamic>;
    } catch (e) {
      return _errorResult(e);
    }
  }

  /// Cancel a leave request (AWAITING_ALTERNATE only).
  static Future<Map<String, dynamic>> cancelRequest(
      String token, int requestId) async {
    try {
      final res = await http.delete(
        Uri.parse('$_base/staff/leave/request/$requestId'),
        headers: _headers(token),
      );
      return json.decode(res.body) as Map<String, dynamic>;
    } catch (e) {
      return _errorResult(e);
    }
  }

  /// Re-nominate a new alternate after decline/expire (strict mode).
  static Future<Map<String, dynamic>> reNominateAlternate({
    required String token,
    required int requestId,
    required String alternateRegNo,
    required String alternateName,
    required String alternateDept,
    required String alternateRole,
  }) async {
    try {
      final res = await http.put(
        Uri.parse('$_base/staff/leave/request/$requestId/re-nominate'),
        headers: _headers(token),
        body: jsonEncode({
          'alternate_reg_no': alternateRegNo,
          'alternate_name': alternateName,
          'alternate_dept': alternateDept,
          'alternate_role': alternateRole,
        }),
      );
      return json.decode(res.body) as Map<String, dynamic>;
    } catch (e) {
      return _errorResult(e);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ALTERNATE — VIEW & RESPOND
  // ─────────────────────────────────────────────────────────────────────────

  /// Nominations where I am the alternate and haven't responded.
  static Future<Map<String, dynamic>> getPendingNominations(
      String token) async {
    try {
      final res = await http.get(
        Uri.parse('$_base/staff/leave/alternate/pending'),
        headers: _headers(token),
      );
      return json.decode(res.body) as Map<String, dynamic>;
    } catch (e) {
      return _errorResult(e);
    }
  }

  /// All nominations (any status) where I am the alternate.
  static Future<Map<String, dynamic>> getAllMyNominations(String token) async {
    try {
      final res = await http.get(
        Uri.parse('$_base/staff/leave/alternate/all'),
        headers: _headers(token),
      );
      return json.decode(res.body) as Map<String, dynamic>;
    } catch (e) {
      return _errorResult(e);
    }
  }

  /// My timetable conflicts for a specific leave period.
  static Future<Map<String, dynamic>> getConflictsForRequest(
      String token, int requestId) async {
    try {
      final res = await http.get(
        Uri.parse('$_base/staff/leave/alternate/conflicts/$requestId'),
        headers: _headers(token),
      );
      return json.decode(res.body) as Map<String, dynamic>;
    } catch (e) {
      return _errorResult(e);
    }
  }

  /// Accept or decline a nomination.
  static Future<Map<String, dynamic>> respondToNomination({
    required String token,
    required int requestId,
    required bool accepted,
    String? remarks,
  }) async {
    try {
      final body = <String, dynamic>{
        'accepted': accepted,
      };
      if (remarks != null && remarks.isNotEmpty) {
        body['remarks'] = remarks;
      }
      final res = await http.post(
        Uri.parse('$_base/staff/leave/alternate/$requestId/respond'),
        headers: _headers(token),
        body: jsonEncode(body),
      );
      return json.decode(res.body) as Map<String, dynamic>;
    } catch (e) {
      return _errorResult(e);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HOD — DEPARTMENT REVIEW
  // ─────────────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> hodGetRequests(
    String token, {
    String? workflowStatus,
  }) async {
    try {
      final params = <String, String>{};
      if (workflowStatus != null) params['workflow_status'] = workflowStatus;
      final uri = Uri.parse('$_base/hod/staff-leave/requests')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final res = await http.get(uri, headers: _headers(token));
      return json.decode(res.body) as Map<String, dynamic>;
    } catch (e) {
      return _errorResult(e);
    }
  }

  static Future<Map<String, dynamic>> hodAction({
    required String token,
    required int requestId,
    required bool approved,
    String? remarks,
  }) async {
    try {
      final body = <String, dynamic>{
        'approved': approved,
      };
      if (remarks != null && remarks.isNotEmpty) {
        body['remarks'] = remarks;
      }
      final res = await http.post(
        Uri.parse('$_base/hod/staff-leave/request/$requestId/action'),
        headers: _headers(token),
        body: jsonEncode(body),
      );
      return json.decode(res.body) as Map<String, dynamic>;
    } catch (e) {
      return _errorResult(e);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ADMIN — FULL ACCESS
  // ─────────────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> adminGetRequests(
    String token, {
    String? workflowStatus,
    String? dept,
    String? leaveType,
    int page = 1,
    int limit = 50,
  }) async {
    try {
      final params = <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
      };
      if (workflowStatus != null) params['workflow_status'] = workflowStatus;
      if (dept != null) params['dept'] = dept;
      if (leaveType != null) params['leave_type'] = leaveType;
      final uri = Uri.parse('$_base/admin/staff-leave/requests')
          .replace(queryParameters: params);
      final res = await http.get(uri, headers: _headers(token));
      return json.decode(res.body) as Map<String, dynamic>;
    } catch (e) {
      return _errorResult(e);
    }
  }

  static Future<Map<String, dynamic>> adminAction({
    required String token,
    required int requestId,
    required bool approved,
    String? remarks,
  }) async {
    try {
      final body = <String, dynamic>{
        'approved': approved,
      };
      if (remarks != null && remarks.isNotEmpty) {
        body['remarks'] = remarks;
      }
      final res = await http.post(
        Uri.parse('$_base/admin/staff-leave/request/$requestId/action'),
        headers: _headers(token),
        body: jsonEncode(body),
      );
      return json.decode(res.body) as Map<String, dynamic>;
    } catch (e) {
      return _errorResult(e);
    }
  }

  static Future<Map<String, dynamic>> adminGetDetail(
      String token, int requestId) async {
    try {
      final res = await http.get(
        Uri.parse('$_base/admin/staff-leave/request/$requestId'),
        headers: _headers(token),
      );
      return json.decode(res.body) as Map<String, dynamic>;
    } catch (e) {
      return _errorResult(e);
    }
  }
}
