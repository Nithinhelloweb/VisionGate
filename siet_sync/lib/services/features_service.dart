import 'dart:convert';
import '../config/college_ip_config.dart';
import 'api_client.dart';

/// Comprehensive service for interacting with all 12 enhanced system modules
class FeaturesService {
  static String get _baseUrl => CollegeIPConfig.defaultURL;

  // ─────────────────────────────────────────────────────────────────────────
  // 1. DASHBOARD & LIVE OPERATIONS
  // ─────────────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getDashboardTodaySummary(String token) async {
    try {
      final res = await apiClient.get(
        '$_baseUrl/dashboard/today-summary',
        token: token,
      );
      if (res.statusCode == 200) {
        return json.decode(res.body);
      }
    } catch (_) {}
    return {'success': false, 'summary': {}};
  }

  static Future<List<Map<String, dynamic>>> getUpcomingLeaves(String token) async {
    try {
      final res = await apiClient.get(
        '$_baseUrl/dashboard/upcoming-leaves',
        token: token,
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        return List<Map<String, dynamic>>.from(data['upcoming_approved_leaves'] ?? []);
      }
    } catch (_) {}
    return [];
  }

  static Future<List<Map<String, dynamic>>> getAnnouncements(String token) async {
    try {
      final res = await apiClient.get(
        '$_baseUrl/dashboard/announcements',
        token: token,
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        return List<Map<String, dynamic>>.from(data['announcements'] ?? []);
      }
    } catch (_) {}
    return [];
  }

  static Future<bool> postAnnouncement(
    String token, {
    required String title,
    required String message,
    String priority = 'Normal',
    String targetRole = 'All',
    String? targetDept,
    String? expiresAt,
  }) async {
    try {
      final res = await apiClient.post(
        '$_baseUrl/admin/announcements',
        token: token,
        body: json.encode({
          'title': title,
          'message': message,
          'priority': priority,
          'target_role': targetRole,
          'target_dept': ?targetDept,
          'expires_at': ?expiresAt,
        }),

      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> deleteAnnouncement(String token, int announcementId) async {
    try {
      final res = await apiClient.delete(
        '$_baseUrl/admin/announcements/$announcementId',
        token: token,
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 2. ATTENDANCE CORRECTIONS & REGULARISATION WORKFLOW
  // ─────────────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> submitAttendanceCorrection(
    String token, {
    required String requestedDate,
    required String requestedCheckIn,
    required String requestedCheckOut,
    String requestedStatus = 'Present',
    required String reason,
  }) async {
    try {
      final res = await apiClient.post(
        '$_baseUrl/attendance/correction/request',
        token: token,
        body: json.encode({
          'requested_date': requestedDate,
          'requested_check_in': requestedCheckIn,
          'requested_check_out': requestedCheckOut,
          'requested_status': requestedStatus,
          'reason': reason,
        }),
      );
      return json.decode(res.body);
    } catch (e) {
      return {'success': false, 'detail': e.toString()};
    }
  }

  static Future<List<Map<String, dynamic>>> getMyCorrections(String token) async {
    try {
      final res = await apiClient.get(
        '$_baseUrl/attendance/correction/my-requests',
        token: token,
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        return List<Map<String, dynamic>>.from(data['data'] ?? []);
      }
    } catch (_) {}
    return [];
  }

  static Future<List<Map<String, dynamic>>> getPendingCorrections(String token) async {
    try {
      final res = await apiClient.get(
        '$_baseUrl/admin/attendance/correction/pending',
        token: token,
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        return List<Map<String, dynamic>>.from(data['data'] ?? []);
      }
    } catch (_) {}
    return [];
  }

  static Future<bool> approveCorrection(String token, int correctionId, {String remarks = 'Approved'}) async {
    try {
      final res = await apiClient.post(
        '$_baseUrl/admin/attendance/correction/$correctionId/approve',
        token: token,
        body: json.encode({'remarks': remarks}),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> rejectCorrection(String token, int correctionId, {String remarks = 'Rejected'}) async {
    try {
      final res = await apiClient.post(
        '$_baseUrl/admin/attendance/correction/$correctionId/reject',
        token: token,
        body: json.encode({'remarks': remarks}),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getCorrectionHistory(
    String token, {
    String? regNo,
    String? status,
    String? fromDate,
    String? toDate,
  }) async {
    try {
      final params = <String>[];
      if (regNo != null && regNo.isNotEmpty) params.add('reg_no=$regNo');
      if (status != null && status.isNotEmpty) params.add('status=$status');
      if (fromDate != null && fromDate.isNotEmpty) params.add('from_date=$fromDate');
      if (toDate != null && toDate.isNotEmpty) params.add('to_date=$toDate');

      final url = '$_baseUrl/admin/attendance/correction/history${params.isNotEmpty ? '?${params.join('&')}' : ''}';
      final res = await apiClient.get(url, token: token);
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        return List<Map<String, dynamic>>.from(data['data'] ?? []);
      }
    } catch (_) {}
    return [];
  }

  static Future<List<Map<String, dynamic>>> getRegularisationWindows(String token) async {
    try {
      final res = await apiClient.get(
        '$_baseUrl/admin/attendance/regularisation-window',
        token: token,
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        return List<Map<String, dynamic>>.from(data['windows'] ?? []);
      }
    } catch (_) {}
    return [];
  }

  static Future<bool> saveRegularisationWindow(
    String token, {
    required String role,
    required int maxDaysBack,
    required int maxRequestsPerMonth,
  }) async {
    try {
      final res = await apiClient.post(
        '$_baseUrl/admin/attendance/regularisation-window',
        token: token,
        body: json.encode({
          'role': role,
          'max_days_back': maxDaysBack,
          'max_requests_per_month': maxRequestsPerMonth,
        }),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 3. ANALYTICS & ADVANCED REPORTING
  // ─────────────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getDailyRegisterReport(
    String token, {
    String? date,
    String? dept,
  }) async {
    try {
      final params = <String>[];
      if (date != null && date.isNotEmpty) params.add('date_str=$date');
      if (dept != null && dept.isNotEmpty) params.add('dept=$dept');

      final url = '$_baseUrl/reports/daily-register${params.isNotEmpty ? '?${params.join('&')}' : ''}';
      final res = await apiClient.get(url, token: token);
      if (res.statusCode == 200) {
        return json.decode(res.body);
      }
    } catch (_) {}
    return {'success': false, 'records': []};
  }

  static Future<Map<String, dynamic>> getMonthlySummaryReport(
    String token, {
    String? month,
    String? dept,
  }) async {
    try {
      final params = <String>[];
      if (month != null && month.isNotEmpty) params.add('month=$month');
      if (dept != null && dept.isNotEmpty) params.add('dept=$dept');

      final url = '$_baseUrl/reports/monthly-summary${params.isNotEmpty ? '?${params.join('&')}' : ''}';
      final res = await apiClient.get(url, token: token);
      if (res.statusCode == 200) {
        return json.decode(res.body);
      }
    } catch (_) {}
    return {'success': false, 'records': []};
  }

  static Future<Map<String, dynamic>> getDepartmentHeatmap(
    String token, {
    String? month,
  }) async {
    try {
      final url = '$_baseUrl/reports/department-heatmap${month != null ? '?month=$month' : ''}';
      final res = await apiClient.get(url, token: token);
      if (res.statusCode == 200) {
        return json.decode(res.body);
      }
    } catch (_) {}
    return {'success': false, 'heatmap': {}};
  }

  static Future<Map<String, dynamic>> getLeaveUtilisationReport(
    String token, {
    String? dept,
  }) async {
    try {
      final url = '$_baseUrl/reports/leave-utilisation${dept != null ? '?dept=$dept' : ''}';
      final res = await apiClient.get(url, token: token);
      if (res.statusCode == 200) {
        return json.decode(res.body);
      }
    } catch (_) {}
    return {'success': false, 'records': []};
  }

  static Future<Map<String, dynamic>> getAbsenteeismTrend(
    String token, {
    int days = 14,
    String? dept,
  }) async {
    try {
      final params = ['days=$days'];
      if (dept != null && dept.isNotEmpty) params.add('dept=$dept');

      final url = '$_baseUrl/reports/absenteeism-trend?${params.join('&')}';
      final res = await apiClient.get(url, token: token);
      if (res.statusCode == 200) {
        return json.decode(res.body);
      }
    } catch (_) {}
    return {'success': false, 'trend': []};
  }

  static Future<List<Map<String, dynamic>>> getFaceRecognitionFailures(
    String token, {
    int limit = 50,
  }) async {
    try {
      final res = await apiClient.get(
        '$_baseUrl/reports/face-recognition-failures?limit=$limit',
        token: token,
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        return List<Map<String, dynamic>>.from(data['failures'] ?? []);
      }
    } catch (_) {}
    return [];
  }

  static String getReportExportUrl(String endpoint, {required String format, Map<String, String>? params}) {
    final query = <String>['export_format=$format'];
    if (params != null) {
      params.forEach((k, v) {
        if (v.isNotEmpty) query.add('$k=$v');
      });
    }
    return '$_baseUrl$endpoint?${query.join('&')}';
  }


  // ─────────────────────────────────────────────────────────────────────────
  // 4. UNIFIED NOTIFICATION HUB & PREFERENCES
  // ─────────────────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getNotifications(String token, {bool unreadOnly = false}) async {
    try {
      final res = await apiClient.get(
        '$_baseUrl/notifications?unread_only=$unreadOnly',
        token: token,
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        return List<Map<String, dynamic>>.from(data['notifications'] ?? []);
      }
    } catch (_) {}
    return [];
  }

  static Future<bool> markNotificationRead(String token, int notificationId) async {
    try {
      final res = await apiClient.post(
        '$_baseUrl/notifications/mark-read/$notificationId',
        token: token,
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> markAllNotificationsRead(String token) async {
    try {
      final res = await apiClient.post(
        '$_baseUrl/notifications/mark-all-read',
        token: token,
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>> getNotificationPreferences(String token) async {
    try {
      final res = await apiClient.get('$_baseUrl/preferences', token: token);
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        return data['preferences'] ?? {};
      }
    } catch (_) {}
    return {};
  }

  static Future<bool> updateNotificationPreferences(
    String token, {
    required bool emailNotifications,
    required bool pushNotifications,
    required bool notifyCorrectionOutcome,
    required bool notifyAnnouncements,
  }) async {
    try {
      final res = await apiClient.post(
        '$_baseUrl/preferences',
        token: token,
        body: json.encode({
          'email_notifications': emailNotifications,
          'push_notifications': pushNotifications,
          'notify_correction_outcome': notifyCorrectionOutcome,
          'notify_announcements': notifyAnnouncements,
        }),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> broadcastNotification(
    String token, {
    required String title,
    required String message,
    String targetRole = 'All',
    String? targetDept,
    String? linkUrl,
  }) async {
    try {
      final res = await apiClient.post(
        '$_baseUrl/admin/notifications/broadcast',
        token: token,
        body: json.encode({
          'title': title,
          'message': message,
          'target_role': targetRole,
          'target_dept': ?targetDept,
          'link_url': ?linkUrl,
        }),

      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 5. SECURITY, SESSIONS & 2FA
  // ─────────────────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getActiveSessions(String token) async {
    try {
      final res = await apiClient.get(
        '$_baseUrl/admin/security/active-sessions',
        token: token,
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        return List<Map<String, dynamic>>.from(data['active_sessions'] ?? []);
      }
    } catch (_) {}
    return [];
  }

  static Future<bool> terminateSession(String token, int sessionId) async {
    try {
      final res = await apiClient.post(
        '$_baseUrl/admin/security/sessions/$sessionId/terminate',
        token: token,
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> terminateUserSessions(String token, String regNo) async {
    try {
      final res = await apiClient.post(
        '$_baseUrl/admin/security/terminate-user/$regNo',
        token: token,
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getLoginAttempts(String token, {int limit = 50}) async {
    try {
      final res = await apiClient.get(
        '$_baseUrl/admin/security/login-attempts?limit=$limit',
        token: token,
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        return List<Map<String, dynamic>>.from(data['attempts'] ?? []);
      }
    } catch (_) {}
    return [];
  }

  static Future<List<Map<String, dynamic>>> getAuditLogs(String token, {int limit = 50}) async {
    try {
      final res = await apiClient.get(
        '$_baseUrl/admin/audit-log?limit=$limit',
        token: token,
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        return List<Map<String, dynamic>>.from(data['audit_logs'] ?? []);
      }
    } catch (_) {}
    return [];
  }

  static Future<Map<String, dynamic>> setup2FA(String token) async {
    try {
      final res = await apiClient.post('$_baseUrl/2fa/setup', token: token);
      if (res.statusCode == 200) {
        return json.decode(res.body);
      }
    } catch (_) {}
    return {'success': false};
  }

  static Future<bool> verify2FA(String token, String code) async {
    try {
      final res = await apiClient.post(
        '$_baseUrl/2fa/verify',
        token: token,
        body: json.encode({'code': code}),
      );
      return res.statusCode == 200 && json.decode(res.body)['success'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> disable2FA(String token, String code) async {
    try {
      final res = await apiClient.post(
        '$_baseUrl/2fa/disable',
        token: token,
        body: json.encode({'code': code}),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 6. SYSTEM ADMINISTRATION, SMTP & MAINTENANCE
  // ─────────────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getSMTPConfig(String token) async {
    try {
      final res = await apiClient.get('$_baseUrl/admin/settings/smtp', token: token);
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        return data['smtp_config'] ?? {};
      }
    } catch (_) {}
    return {};
  }

  static Future<bool> saveSMTPConfig(String token, Map<String, dynamic> config) async {
    try {
      final res = await apiClient.post(
        '$_baseUrl/admin/settings/smtp',
        token: token,
        body: json.encode(config),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>> testSMTPEmail(String token, String recipientEmail) async {
    try {
      final res = await apiClient.post(
        '$_baseUrl/admin/settings/smtp/test',
        token: token,
        body: json.encode({'recipient_email': recipientEmail}),
      );
      return json.decode(res.body);
    } catch (e) {
      return {'success': false, 'detail': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> getMaintenanceStatus() async {
    try {
      final res = await apiClient.get('$_baseUrl/admin/settings/maintenance');
      if (res.statusCode == 200) {
        return json.decode(res.body);
      }
    } catch (_) {}
    return {'maintenance_mode': false};
  }

  static Future<bool> toggleMaintenance(String token, {required bool enabled, String message = ''}) async {
    try {
      final res = await apiClient.post(
        '$_baseUrl/admin/settings/maintenance',
        token: token,
        body: json.encode({'enabled': enabled, 'message': message}),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> getAntiSpoofingStatus() async {
    try {
      final res = await apiClient.get('$_baseUrl/admin/config/antispoofing-status');
      if (res.statusCode == 200) {
        return json.decode(res.body)['antispoofing_enabled'] ?? true;
      }
    } catch (_) {}
    return true;
  }

  static Future<bool> toggleAntiSpoofing(String token, bool enabled) async {
    try {
      final res = await apiClient.post(
        '$_baseUrl/admin/config/toggle-antispoofing',
        token: token,
        body: json.encode({'enabled': enabled}),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 7. HOLIDAY CALENDAR MANAGEMENT
  // ─────────────────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getHolidays({String? academicYear, String? month}) async {
    try {
      final params = <String>[];
      if (academicYear != null && academicYear.isNotEmpty) params.add('academic_year=$academicYear');
      if (month != null && month.isNotEmpty) params.add('month=$month');

      final url = '$_baseUrl/admin/holidays${params.isNotEmpty ? '?${params.join('&')}' : ''}';
      final res = await apiClient.get(url);
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        return List<Map<String, dynamic>>.from(data['holidays'] ?? []);
      }
    } catch (_) {}
    return [];
  }

  static Future<bool> addHoliday(
    String token, {
    required String holidayDate,
    required String holidayName,
    String holidayType = 'National',
    bool isOptional = false,
    String academicYear = '2026-2027',
  }) async {
    try {
      final res = await apiClient.post(
        '$_baseUrl/admin/holidays',
        token: token,
        body: json.encode({
          'holiday_date': holidayDate,
          'holiday_name': holidayName,
          'holiday_type': holidayType,
          'is_optional': isOptional,
          'academic_year': academicYear,
        }),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> deleteHoliday(String token, int holidayId) async {
    try {
      final res = await apiClient.delete('$_baseUrl/admin/holidays/$holidayId', token: token);
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 8. LEAVE BALANCES & COMP-OFF MANAGEMENT
  // ─────────────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getDetailedLeaveBalance(String token, String regNo) async {
    try {
      final res = await apiClient.get('$_baseUrl/leave/balance/$regNo', token: token);
      if (res.statusCode == 200) {
        return json.decode(res.body);
      }
    } catch (_) {}
    return {'success': false, 'balances': {}};
  }

  static Future<List<Map<String, dynamic>>> getTeamLeaveCalendar(
    String token, {
    String? month,
    String? dept,
  }) async {
    try {
      final params = <String>[];
      if (month != null && month.isNotEmpty) params.add('month=$month');
      if (dept != null && dept.isNotEmpty) params.add('dept=$dept');

      final url = '$_baseUrl/leave/calendar${params.isNotEmpty ? '?${params.join('&')}' : ''}';
      final res = await apiClient.get(url, token: token);
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        return List<Map<String, dynamic>>.from(data['leaves'] ?? []);
      }
    } catch (_) {}
    return [];
  }

  static Future<bool> accrueCompOff(
    String token, {
    required String regNo,
    required String dutyDate,
    required String dutyDescription,
    required double daysAccrued,
    int validityMonths = 3,
  }) async {
    try {
      final res = await apiClient.post(
        '$_baseUrl/admin/leave/comp-off/accrue',
        token: token,
        body: json.encode({
          'reg_no': regNo,
          'duty_date': dutyDate,
          'duty_description': dutyDescription,
          'days_accrued': daysAccrued,
          'validity_months': validityMonths,
        }),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 9. USER LIFECYCLE & ACTIVITY
  // ─────────────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getUserActivity(String token, int userId) async {
    try {
      final res = await apiClient.get('$_baseUrl/admin/users/$userId/activity', token: token);
      if (res.statusCode == 200) {
        return json.decode(res.body);
      }
    } catch (_) {}
    return {'success': false};
  }

  static Future<bool> bulkDeactivateUsers(String token, List<String> regNos) async {
    try {
      final res = await apiClient.post(
        '$_baseUrl/admin/users/bulk-deactivate',
        token: token,
        body: json.encode({'reg_nos': regNos}),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> transferUserDepartment(
    String token,
    int userId, {
    required String newDept,
    String? newRole,
    String reason = 'Department Transfer',
  }) async {
    try {
      final res = await apiClient.post(
        '$_baseUrl/admin/users/$userId/transfer',
        token: token,
        body: json.encode({
          'new_dept': newDept,
          'new_role': ?newRole,
          'reason': reason,
        }),

      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> forcePasswordReset(String token, int userId) async {
    try {
      final res = await apiClient.post(
        '$_baseUrl/admin/users/$userId/force-password-reset',
        token: token,
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 10. TIMETABLE & SUBSTITUTE MANAGEMENT
  // ─────────────────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getSubstituteAssignments(
    String token, {
    String? assignmentDate,
    String? dept,
  }) async {
    try {
      final params = <String>[];
      if (assignmentDate != null && assignmentDate.isNotEmpty) params.add('assignment_date=$assignmentDate');
      if (dept != null && dept.isNotEmpty) params.add('dept=$dept');

      final url = '$_baseUrl/timetable/substitute-assignments${params.isNotEmpty ? '?${params.join('&')}' : ''}';
      final res = await apiClient.get(url, token: token);
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        return List<Map<String, dynamic>>.from(data['assignments'] ?? []);
      }
    } catch (_) {}
    return [];
  }

  static Future<bool> addSubstituteAssignment(
    String token, {
    required String originalStaffRegNo,
    required String substituteStaffRegNo,
    required String assignmentDate,
    required int periodNumber,
    required String dept,
    required String batch,
    required int semester,
    required String section,
    required String subjectCode,
    required String subjectName,
    String reason = 'Faculty on Leave',
  }) async {
    try {
      final res = await apiClient.post(
        '$_baseUrl/timetable/substitute-assignments',
        token: token,
        body: json.encode({
          'original_staff_reg_no': originalStaffRegNo,
          'substitute_staff_reg_no': substituteStaffRegNo,
          'assignment_date': assignmentDate,
          'period_number': periodNumber,
          'dept': dept,
          'batch': batch,
          'semester': semester,
          'section': section,
          'subject_code': subjectCode,
          'subject_name': subjectName,
          'reason': reason,
        }),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> deleteSubstituteAssignment(String token, int assignmentId) async {
    try {
      final res = await apiClient.delete(
        '$_baseUrl/timetable/substitute-assignments/$assignmentId',
        token: token,
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 11. STUDENT PORTAL EXTENSIONS
  // ─────────────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getStudentAttendanceWarning(String token) async {
    try {
      final res = await apiClient.get(
        '$_baseUrl/student/attendance/percentage-warning',
        token: token,
      );
      if (res.statusCode == 200) {
        return json.decode(res.body);
      }
    } catch (_) {}
    return {'success': false};
  }

  static Future<List<Map<String, dynamic>>> getStudentSubjectWiseAttendance(String token) async {
    try {
      final res = await apiClient.get(
        '$_baseUrl/student/attendance/subject-wise',
        token: token,
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        return List<Map<String, dynamic>>.from(data['subject_attendance'] ?? []);
      }
    } catch (_) {}
    return [];
  }

  static Future<bool> submitStudentFeedback(
    String token, {
    required String category,
    required String subject,
    required String description,
  }) async {
    try {
      final res = await apiClient.post(
        '$_baseUrl/student/feedback',
        token: token,
        body: json.encode({
          'category': category,
          'subject': subject,
          'description': description,
        }),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getMyStudentFeedback(String token) async {
    try {
      final res = await apiClient.get(
        '$_baseUrl/student/my-feedback',
        token: token,
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        return List<Map<String, dynamic>>.from(data['feedback'] ?? []);
      }
    } catch (_) {}
    return [];
  }

  static Future<List<Map<String, dynamic>>> getAdminStudentFeedback(String token, {String? status}) async {
    try {
      final url = '$_baseUrl/admin/student-feedback${status != null ? '?status=$status' : ''}';
      final res = await apiClient.get(url, token: token);
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        return List<Map<String, dynamic>>.from(data['feedback'] ?? []);
      }
    } catch (_) {}
    return [];
  }

  static Future<bool> resolveStudentFeedback(String token, int feedbackId, {required String resolutionNotes}) async {
    try {
      final res = await apiClient.post(
        '$_baseUrl/admin/student-feedback/$feedbackId/resolve',
        token: token,
        body: json.encode({'resolution_notes': resolutionNotes}),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
