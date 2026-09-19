import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/college_ip_config.dart';

/// Leave Request Service - handles all leave request API calls
class LeaveRequestService {
  static String get API_URL => CollegeIPConfig.defaultURL;
  
  /// Maximum reason length (matching backend)
  static const int MAX_REASON_LENGTH = 1000;
  
  /// Allowed leave types
  static const List<String> LEAVE_TYPES = [
    'sick',
    'casual', 
    'earned',
    'maternity',
    'paternity',
    'unpaid',
    'other'
  ];

  /// Submit a leave request
  static Future<Map<String, dynamic>> submitLeaveRequest({
    required String token,
    required String leaveType,
    required String startDate,
    required String endDate,
    required String reason,
    bool isHalfDay = false,
    String? whichHalf,
  }) async {
    try {
      final bodyMap = <String, dynamic>{
        'leave_type': leaveType,
        'start_date': startDate,
        'end_date': endDate,
        'reason': reason,
        'is_half_day': isHalfDay,
      };
      if (isHalfDay && whichHalf != null) {
        bodyMap['which_half'] = whichHalf;
      }

      final response = await http.post(
        Uri.parse('$API_URL/leave/submit'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(bodyMap),
      );
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        return {
          'success': false,
          'message': error['detail'] ?? 'Unable to send leave request',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  /// Get all leave requests for the current user
  static Future<Map<String, dynamic>> getMyLeaveRequests(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$API_URL/leave/my-requests'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {
          'success': false,
          'requests': [],
          'message': 'Failed to fetch leave requests',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'requests': [],
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  /// Get all expired leaves list (supports optional regNo and dept filters)
  static Future<Map<String, dynamic>> getExpiredLeaves(
    String token, {
    String? regNo,
    String? dept,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (regNo != null && regNo.isNotEmpty) queryParams['reg_no'] = regNo;
      if (dept != null && dept.isNotEmpty && dept != 'All') queryParams['dept'] = dept;

      final uri = Uri.parse('$API_URL/leave/expired').replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
        },
      );
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {
          'success': false,
          'expired_leaves': [],
          'message': 'Failed to fetch expired leaves',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'expired_leaves': [],
        'message': 'Network error: ${e.toString()}',
      };
    }
  }


  /// Get details of a specific leave request
  static Future<Map<String, dynamic>> getLeaveRequestDetails(
    String token,
    int requestId,
  ) async {
    try {
      final response = await http.get(
        Uri.parse('$API_URL/leave/request/$requestId'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        return {
          'success': false,
          'message': error['detail'] ?? 'Failed to fetch leave request details',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  /// Update a pending leave request
  static Future<Map<String, dynamic>> updateLeaveRequest({
    required String token,
    required int requestId,
    String? leaveType,
    String? startDate,
    String? endDate,
    String? reason,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (leaveType != null) body['leave_type'] = leaveType;
      if (startDate != null) body['start_date'] = startDate;
      if (endDate != null) body['end_date'] = endDate;
      if (reason != null) body['reason'] = reason;
      
      final response = await http.put(
        Uri.parse('$API_URL/leave/request/$requestId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        return {
          'success': false,
          'message': error['detail'] ?? 'Failed to update leave request',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  /// Cancel a pending leave request
  static Future<Map<String, dynamic>> cancelLeaveRequest(
    String token,
    int requestId,
  ) async {
    try {
      final response = await http.delete(
        Uri.parse('$API_URL/leave/request/$requestId'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        return {
          'success': false,
          'message': error['detail'] ?? 'Failed to cancel leave request',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  // ============================================
  // ADMIN ENDPOINTS
  // ============================================

  /// Get all leave requests (admin view)
  static Future<Map<String, dynamic>> adminGetLeaveRequests({
    required String token,
    String? status,
    String? dept,
    String? search,
    String? startDate,
    String? endDate,
    String sortBy = 'submission_date',
    String sortOrder = 'desc',
    int page = 1,
    int limit = 50,
  }) async {
    try {
      final queryParams = <String, String>{
        'sort_by': sortBy,
        'sort_order': sortOrder,
        'page': page.toString(),
        'limit': limit.toString(),
      };
      
      if (status != null) queryParams['status'] = status;
      if (dept != null) queryParams['dept'] = dept;
      if (search != null) queryParams['search'] = search;
      if (startDate != null) queryParams['start_date'] = startDate;
      if (endDate != null) queryParams['end_date'] = endDate;
      
      final uri = Uri.parse('$API_URL/admin/leave/requests')
          .replace(queryParameters: queryParams);
      
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
        },
      );
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {
          'success': false,
          'requests': [],
          'message': 'Failed to fetch leave requests',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'requests': [],
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  /// Get pending leave requests (admin view)
  static Future<Map<String, dynamic>> adminGetPendingRequests(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$API_URL/admin/leave/requests/pending'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {
          'success': false,
          'requests': [],
          'message': 'Failed to fetch pending requests',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'requests': [],
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  /// Approve a leave request
  static Future<Map<String, dynamic>> adminApproveRequest({
    required String token,
    required int requestId,
    String? comment,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$API_URL/admin/leave/request/$requestId/approve'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'comment': comment ?? '',
        }),
      );
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        return {
          'success': false,
          'message': error['detail'] ?? 'Failed to approve request',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  /// Reject a leave request
  static Future<Map<String, dynamic>> adminRejectRequest({
    required String token,
    required int requestId,
    required String comment,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$API_URL/admin/leave/request/$requestId/reject'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'comment': comment,
        }),
      );
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        return {
          'success': false,
          'message': error['detail'] ?? 'Failed to reject request',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  /// Get audit log for a leave request
  static Future<Map<String, dynamic>> adminGetRequestAudit(
    String token,
    int requestId,
  ) async {
    try {
      final response = await http.get(
        Uri.parse('$API_URL/admin/leave/request/$requestId/audit'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {
          'success': false,
          'audit_log': [],
          'message': 'Failed to fetch audit log',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'audit_log': [],
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  /// Export leave requests as CSV
  static Future<Map<String, dynamic>> adminExportRequests({
    required String token,
    String? status,
    String? dept,
    String? startDate,
    String? endDate,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (status != null) queryParams['status'] = status;
      if (dept != null) queryParams['dept'] = dept;
      if (startDate != null) queryParams['start_date'] = startDate;
      if (endDate != null) queryParams['end_date'] = endDate;
      
      final uri = Uri.parse('$API_URL/admin/leave/export')
          .replace(queryParameters: queryParams);
      
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
        },
      );
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {
          'success': false,
          'message': 'Failed to export requests',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  /// Mark a leave request as read
  static Future<Map<String, dynamic>> adminMarkAsRead(
    String token,
    int requestId,
  ) async {
    try {
      final response = await http.put(
        Uri.parse('$API_URL/admin/leave/request/$requestId/mark-read'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {
          'success': false,
          'message': 'Failed to mark as read',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  // ============================================
  // NOTIFICATION ENDPOINTS
  // ============================================

  /// Get admin notifications
  static Future<Map<String, dynamic>> getAdminNotifications(
    String token, {
    bool unreadOnly = false,
  }) async {
    try {
      final uri = Uri.parse('$API_URL/admin/notifications')
          .replace(queryParameters: {'unread_only': unreadOnly.toString()});
      
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
        },
      );
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {
          'success': false,
          'notifications': [],
          'message': 'Failed to fetch notifications',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'notifications': [],
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  /// Mark notification as read
  static Future<Map<String, dynamic>> markNotificationRead(
    String token,
    int notificationId,
  ) async {
    try {
      final response = await http.put(
        Uri.parse('$API_URL/admin/notifications/$notificationId/read'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {
          'success': false,
          'message': 'Failed to mark notification as read',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  /// Mark all notifications as read
  static Future<Map<String, dynamic>> markAllNotificationsRead(String token) async {
    try {
      final response = await http.put(
        Uri.parse('$API_URL/admin/notifications/read-all'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {
          'success': false,
          'message': 'Failed to mark all notifications as read',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }
}
