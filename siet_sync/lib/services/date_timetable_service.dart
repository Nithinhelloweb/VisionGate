import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/college_ip_config.dart';

/// Service client for date-aware timetable resolution and academic calendar overrides.
class DateTimetableService {
  static String get _base => CollegeIPConfig.defaultURL;

  static Map<String, String> _headers(String token) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  /// Fetch the exact instructional timetable for any calendar date (YYYY-MM-DD).
  /// Fuses Day Order overrides, holidays, staff leave substitutions, and venue relocations.
  static Future<Map<String, dynamic>> getTimetableForDate({
    required String token,
    String? date,
    String? dept,
    String? batch,
    int? semester,
    String? section,
    String? staffRegNo,
  }) async {
    try {
      final params = <String, String>{};
      if (date != null && date.isNotEmpty) params['date'] = date;
      if (dept != null && dept.isNotEmpty) params['dept'] = dept;
      if (batch != null && batch.isNotEmpty) params['batch'] = batch;
      if (semester != null) params['semester'] = semester.toString();
      if (section != null && section.isNotEmpty) params['section'] = section;
      if (staffRegNo != null && staffRegNo.isNotEmpty) {
        params['staff_reg_no'] = staffRegNo;
      }

      final uri = Uri.parse('$_base/api/v1/academics/timetable/by-date')
          .replace(queryParameters: params);
      final res = await http.get(uri, headers: _headers(token));
      if (res.statusCode == 200) {
        return json.decode(res.body) as Map<String, dynamic>;
      }
      return {
        'success': false,
        'message': 'Failed to load timetable: HTTP ${res.statusCode}',
        'periods': [],
      };
    } catch (e) {
      return {'success': false, 'message': e.toString(), 'periods': []};
    }
  }

  /// List calendar date overrides / Day Order mappings.
  static Future<Map<String, dynamic>> getDateOverrides({
    required String token,
    String? startDate,
    String? endDate,
    String? month,
  }) async {
    try {
      final params = <String, String>{};
      if (startDate != null && startDate.isNotEmpty) {
        params['start_date'] = startDate;
      }
      if (endDate != null && endDate.isNotEmpty) {
        params['end_date'] = endDate;
      }
      if (month != null && month.isNotEmpty) params['month'] = month;

      final uri = Uri.parse('$_base/api/v1/academics/calendar/date-overrides')
          .replace(queryParameters: params);
      final res = await http.get(uri, headers: _headers(token));
      if (res.statusCode == 200) {
        return json.decode(res.body) as Map<String, dynamic>;
      }
      return {'total': 0, 'overrides': []};
    } catch (e) {
      return {'total': 0, 'overrides': [], 'error': e.toString()};
    }
  }

  /// Create or update a date override / day schedule mapping.
  static Future<Map<String, dynamic>> saveDateOverride({
    required String token,
    required String overrideDate,
    required String dayType,
    required String mappedDayOfWeek,
    int? dayOrder,
    String? title,
    String? reason,
  }) async {
    try {
      final body = <String, dynamic>{
        'override_date': overrideDate,
        'day_type': dayType,
        'mapped_day_of_week': mappedDayOfWeek,
      };
      if (dayOrder != null) body['day_order'] = dayOrder;
      if (title != null) body['title'] = title;
      if (reason != null) body['reason'] = reason;

      final res = await http.post(
        Uri.parse('$_base/api/v1/academics/calendar/date-override'),
        headers: _headers(token),
        body: jsonEncode(body),
      );
      return json.decode(res.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Delete a date override and restore standard calendar mapping.
  static Future<Map<String, dynamic>> deleteDateOverride({
    required String token,
    required String overrideDate,
  }) async {
    try {
      final res = await http.delete(
        Uri.parse('$_base/api/v1/academics/calendar/date-override/$overrideDate'),
        headers: _headers(token),
      );
      return json.decode(res.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Bulk generate Day Order cycles (Day Order 1..6) across a date range.
  static Future<Map<String, dynamic>> bulkSetupDayOrders({
    required String token,
    required String startDate,
    required String endDate,
    int cycleDays = 6,
    bool skipSundays = true,
  }) async {
    try {
      final body = {
        'start_date': startDate,
        'end_date': endDate,
        'cycle_days': cycleDays,
        'skip_sundays': skipSundays,
      };
      final res = await http.post(
        Uri.parse('$_base/api/v1/academics/calendar/bulk-day-order-cycle'),
        headers: _headers(token),
        body: jsonEncode(body),
      );
      return json.decode(res.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }
}
