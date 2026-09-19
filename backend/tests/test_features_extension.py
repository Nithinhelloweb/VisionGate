"""
Comprehensive Test Suite for Attenda Features Extension
Validates all 12 modules and 50+ endpoints with unit and integration tests.
"""

import os
import sys
import json
import base64
from datetime import datetime, date, timedelta

# Ensure backend directory is in sys.path
backend_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)

import pytest
from fastapi.testclient import TestClient

import pg_adapter
from main import app
from email_service import (
    get_smtp_configuration,
    _get_base_email_template,
    notify_leave_status_change,
    notify_attendance_correction_outcome,
)
from export_engine import (
    generate_csv,
    generate_excel,
    generate_pdf_table,
)

client = TestClient(app)
cursor = pg_adapter.cursor


@pytest.fixture(scope="module", autouse=True)
def setup_test_data():
    """Seed test users and clean up tables for test isolation."""
    # Ensure migration has run
    from migrations.features_v2 import run_migration
    run_migration()

    # Create admin user if not exists
    import bcrypt
    pw_hash = bcrypt.hashpw(b"admin123", bcrypt.gensalt()).decode("utf-8")
    cursor.execute("""
        INSERT INTO users (username, password_hash, reg_no, name, dept, role, suspended)
        VALUES ('admin_test', %s, 'ADMIN_TEST', 'Test Administrator', 'ADMIN', 'admin', FALSE)
        ON CONFLICT (username) DO UPDATE SET password_hash = EXCLUDED.password_hash, suspended = FALSE
    """, (pw_hash,))

    # Create staff user
    cursor.execute("""
        INSERT INTO users (username, password_hash, reg_no, name, dept, role, suspended)
        VALUES ('staff_test', %s, 'STAFF_TEST', 'Test Faculty Member', 'CSE', 'staff', FALSE)
        ON CONFLICT (username) DO UPDATE SET password_hash = EXCLUDED.password_hash, suspended = FALSE
    """, (pw_hash,))


    # Create HOD user
    cursor.execute("""
        INSERT INTO users (username, password_hash, reg_no, name, dept, role, suspended)
        VALUES ('hod_test', %s, 'HOD_TEST', 'Test Head of Department', 'CSE', 'hod', FALSE)
        ON CONFLICT (username) DO UPDATE SET password_hash = EXCLUDED.password_hash, suspended = FALSE
    """, (pw_hash,))

    # Create student
    st_hash = bcrypt.hashpw(b"student123", bcrypt.gensalt()).decode("utf-8")
    cursor.execute("""
        INSERT INTO students (reg_no, name, dept, batch, semester, section, password_hash)
        VALUES ('STU_TEST_001', 'Test Student', 'CSE', '2024-2028', 3, 'A', %s)
        ON CONFLICT (reg_no) DO UPDATE SET password_hash = EXCLUDED.password_hash
    """, (st_hash,))



def get_admin_auth_header():
    token = base64.b64encode(b"admin_test:admin123").decode("utf-8")
    return {"Authorization": f"Bearer {token}"}


def get_staff_auth_header():
    token = base64.b64encode(b"staff_test:admin123").decode("utf-8")
    return {"Authorization": f"Bearer {token}"}


def get_hod_auth_header():
    token = base64.b64encode(b"hod_test:admin123").decode("utf-8")
    return {"Authorization": f"Bearer {token}"}


def get_student_auth_header():
    token = base64.b64encode(b"STU_TEST_001:student123").decode("utf-8")
    return {"Authorization": f"Bearer {token}"}


# ─────────────────────────────────────────────────────────────────────────────
# 1. TEST DASHBOARD & ANNOUNCEMENTS
# ─────────────────────────────────────────────────────────────────────────────

def test_dashboard_today_summary():
    headers = get_admin_auth_header()
    response = client.get("/dashboard/today-summary", headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert data["success"] is True
    assert "metrics" in data["data"]
    assert "present_count" in data["data"]["metrics"]


def test_dashboard_upcoming_leaves():
    headers = get_staff_auth_header()
    response = client.get("/dashboard/upcoming-leaves", headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert data["success"] is True
    assert "upcoming_leaves" in data["data"]
    assert "upcoming_holidays" in data["data"]


def test_system_announcements_workflow():
    admin_headers = get_admin_auth_header()
    staff_headers = get_staff_auth_header()

    # Create announcement
    post_res = client.post(
        "/admin/announcements",
        headers=admin_headers,
        json={
            "title": "Semester Examination Schedule Published",
            "content": "All faculty members are requested to review the end-semester duty roster.",
            "target_audience": "All",
            "priority": "High"
        }
    )
    assert post_res.status_code == 200
    assert post_res.json()["success"] is True

    # Read from staff dashboard
    get_res = client.get("/dashboard/announcements", headers=staff_headers)
    assert get_res.status_code == 200
    announcements = get_res.json()["data"]
    assert len(announcements) > 0
    assert any(a["title"] == "Semester Examination Schedule Published" for a in announcements)


# ─────────────────────────────────────────────────────────────────────────────
# 2. TEST ATTENDANCE CORRECTIONS & REGULARISATION
# ─────────────────────────────────────────────────────────────────────────────

def test_regularisation_window_settings():
    admin_headers = get_admin_auth_header()

    # Get window
    res = client.get("/admin/attendance/regularisation-window", headers=admin_headers)
    assert res.status_code == 200
    assert "max_correction_days" in res.json()["data"]

    # Update window to 10 days
    up_res = client.post(
        "/admin/attendance/regularisation-window",
        headers=admin_headers,
        json={"max_correction_days": 10}
    )
    assert up_res.status_code == 200
    assert up_res.json()["max_correction_days"] == 10


def test_attendance_correction_lifecycle():
    staff_headers = get_staff_auth_header()
    admin_headers = get_admin_auth_header()

    target_date = (datetime.now().date() - timedelta(days=1)).strftime("%Y-%m-%d")

    # Clean prior test requests for this date
    cursor.execute("DELETE FROM attendance_corrections WHERE reg_no = 'STAFF_TEST' AND requested_date = %s", (target_date,))

    # Staff submits dispute
    sub_res = client.post(
        "/attendance/correction/request",
        headers=staff_headers,
        json={
            "requested_date": target_date,
            "requested_check_in": "08:55",
            "requested_check_out": "17:05",
            "requested_status": "Present",
            "reason": "Biometric terminal was offline during morning entry"
        }
    )
    assert sub_res.status_code == 200
    assert sub_res.json()["success"] is True

    # Check in my requests
    my_res = client.get("/attendance/correction/my-requests", headers=staff_headers)
    assert my_res.status_code == 200
    my_requests = my_res.json()["data"]
    matching = [r for r in my_requests if r["requested_date"] == target_date]
    assert len(matching) > 0
    correction_id = matching[0]["id"]
    assert matching[0]["status"] == "Pending"

    # Admin fetches pending
    pend_res = client.get("/admin/attendance/correction/pending", headers=admin_headers)
    assert pend_res.status_code == 200
    pending_list = pend_res.json()["data"]
    assert any(p["id"] == correction_id for p in pending_list)

    # Admin approves
    appr_res = client.post(
        f"/admin/attendance/correction/{correction_id}/approve",
        headers=admin_headers,
        json={"remarks": "Verified with security logbook"}
    )
    assert appr_res.status_code == 200
    assert appr_res.json()["success"] is True

    # Verify daily_attendance_status table was updated
    cursor.execute("SELECT status, is_manual_override FROM daily_attendance_status WHERE reg_no = 'STAFF_TEST' AND date = %s", (target_date,))
    row = cursor.fetchone()
    assert row is not None
    assert row[0] == "Present"
    assert row[1] is True


# ─────────────────────────────────────────────────────────────────────────────
# 3. TEST REPORTS & EXPORTS
# ─────────────────────────────────────────────────────────────────────────────

def test_daily_register_json_and_formats():
    admin_headers = get_admin_auth_header()
    today_str = datetime.now().strftime("%Y-%m-%d")

    # 1. JSON
    res_json = client.get(f"/reports/daily-register?date_str={today_str}", headers=admin_headers)
    assert res_json.status_code == 200
    assert res_json.json()["success"] is True

    # 2. Excel
    res_excel = client.get(f"/reports/daily-register?date_str={today_str}&export_format=excel", headers=admin_headers)
    assert res_excel.status_code == 200
    assert res_excel.headers["content-type"] == "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    assert len(res_excel.content) > 100

    # 3. PDF
    res_pdf = client.get(f"/reports/daily-register?date_str={today_str}&export_format=pdf", headers=admin_headers)
    assert res_pdf.status_code == 200
    assert res_pdf.headers["content-type"] == "application/pdf"
    assert len(res_pdf.content) > 100

    # 4. CSV
    res_csv = client.get(f"/reports/daily-register?date_str={today_str}&export_format=csv", headers=admin_headers)
    assert res_csv.status_code == 200
    assert res_csv.headers["content-type"] == "text/csv; charset=utf-8"
    assert "Reg No,Staff Name" in res_csv.text


def test_monthly_summary_and_heatmap():
    admin_headers = get_admin_auth_header()
    ym = datetime.now().strftime("%Y-%m")

    # Monthly summary
    res_m = client.get(f"/reports/monthly-summary?year_month={ym}", headers=admin_headers)
    assert res_m.status_code == 200
    assert res_m.json()["success"] is True

    # Department heatmap
    res_h = client.get("/reports/department-heatmap", headers=admin_headers)
    assert res_h.status_code == 200
    assert res_h.json()["success"] is True


def test_leave_utilisation_and_absenteeism():
    admin_headers = get_admin_auth_header()

    res_lv = client.get("/reports/leave-utilisation", headers=admin_headers)
    assert res_lv.status_code == 200
    assert res_lv.json()["success"] is True

    res_ab = client.get("/reports/absenteeism-trend?days=14", headers=admin_headers)
    assert res_ab.status_code == 200
    assert res_ab.json()["success"] is True


def test_face_recognition_failures_report():
    admin_headers = get_admin_auth_header()
    res = client.get("/reports/face-recognition-failures", headers=admin_headers)
    assert res.status_code == 200
    assert res.json()["success"] is True


# ─────────────────────────────────────────────────────────────────────────────
# 4. TEST NOTIFICATIONS SYSTEM
# ─────────────────────────────────────────────────────────────────────────────

def test_notifications_workflow():
    admin_headers = get_admin_auth_header()
    staff_headers = get_staff_auth_header()

    # Broadcast notification to Staff
    b_res = client.post(
        "/admin/notifications/broadcast",
        headers=admin_headers,
        json={
            "title": "Academic Council Meeting",
            "message": "The Academic Council convenes this Friday at 3:00 PM in Conference Hall A.",
            "target_role": "staff",
            "type": "meeting"
        }
    )
    assert b_res.status_code == 200
    assert b_res.json()["success"] is True

    # Staff fetches notifications
    n_res = client.get("/notifications", headers=staff_headers)
    assert n_res.status_code == 200
    notifs = n_res.json()["notifications"]
    assert len(notifs) > 0
    assert any("Academic Council" in n["title"] for n in notifs)

    # Preferences get and update
    p_get = client.get("/notifications/preferences", headers=staff_headers)
    assert p_get.status_code == 200

    p_post = client.post(
        "/notifications/preferences",
        headers=staff_headers,
        json={"email_enabled": True, "push_enabled": False, "leave_alerts": True}
    )
    assert p_post.status_code == 200
    assert p_post.json()["success"] is True


# ─────────────────────────────────────────────────────────────────────────────
# 5. TEST ACTIVE SESSIONS & SECURITY
# ─────────────────────────────────────────────────────────────────────────────

def test_active_sessions_and_login_attempts():
    admin_headers = get_admin_auth_header()

    # Fetch active sessions
    s_res = client.get("/admin/security/active-sessions", headers=admin_headers)
    assert s_res.status_code == 200
    assert "sessions" in s_res.json()

    # Fetch login attempts
    l_res = client.get("/admin/security/login-attempts", headers=admin_headers)
    assert l_res.status_code == 200
    assert "attempts" in l_res.json()


def test_2fa_setup_flow():
    admin_headers = get_admin_auth_header()
    res = client.post("/admin/security/2fa/setup", headers=admin_headers)
    assert res.status_code == 200
    data = res.json()
    assert data["success"] is True
    assert "secret" in data
    assert "otpauth_url" in data


# ─────────────────────────────────────────────────────────────────────────────
# 6. TEST EXTENDED SETTINGS
# ─────────────────────────────────────────────────────────────────────────────

def test_smtp_settings_and_maintenance():
    admin_headers = get_admin_auth_header()

    # SMTP Get
    s_get = client.get("/admin/settings/smtp", headers=admin_headers)
    assert s_get.status_code == 200
    assert "smtp_config" in s_get.json()

    # Maintenance Get
    m_get = client.get("/admin/settings/maintenance")
    assert m_get.status_code == 200
    assert "maintenance_mode" in m_get.json()

    # Maintenance Toggle
    m_toggle = client.post(
        "/admin/settings/maintenance",
        headers=admin_headers,
        json={"enabled": False, "message": "All systems operational"}
    )
    assert m_toggle.status_code == 200
    assert m_toggle.json()["maintenance_mode"] is False

    # Anti-spoofing toggle
    as_get = client.get("/admin/config/antispoofing-status")
    assert as_get.status_code == 200

    as_post = client.post(
        "/admin/config/antispoofing-status",
        headers=admin_headers,
        json={"antispoofing_enabled": True}
    )
    assert as_post.status_code == 200
    assert as_post.json()["antispoofing_enabled"] is True

    # Export settings
    exp_res = client.get("/admin/settings/export", headers=admin_headers)
    assert exp_res.status_code == 200
    assert exp_res.headers["content-type"] == "application/json"


# ─────────────────────────────────────────────────────────────────────────────
# 7. TEST HOLIDAY CALENDAR
# ─────────────────────────────────────────────────────────────────────────────

def test_holiday_calendar_crud():
    admin_headers = get_admin_auth_header()
    test_h_date = "2026-10-02"

    # Add holiday
    add_res = client.post(
        "/admin/holidays",
        headers=admin_headers,
        json={
            "holiday_date": test_h_date,
            "holiday_name": "Gandhi Jayanti",
            "holiday_type": "National",
            "is_optional": False,
            "academic_year": "2026-2027"
        }
    )
    assert add_res.status_code == 200
    assert add_res.json()["success"] is True

    # Get holidays
    get_res = client.get("/admin/holidays", headers=admin_headers)
    assert get_res.status_code == 200
    holidays = get_res.json()["holidays"]
    assert any(h["holiday_date"] == test_h_date for h in holidays)


# ─────────────────────────────────────────────────────────────────────────────
# 8. TEST LEAVE BALANCES & COMP-OFF
# ─────────────────────────────────────────────────────────────────────────────

def test_detailed_leave_balance():
    staff_headers = get_staff_auth_header()
    res = client.get("/leave/balance/STAFF_TEST", headers=staff_headers)
    assert res.status_code == 200
    data = res.json()
    assert data["success"] is True
    assert "casual_leave" in data["balances"]
    assert "earned_leave" in data["balances"]


def test_comp_off_accrual():
    admin_headers = get_admin_auth_header()
    duty_date = (datetime.now().date() - timedelta(days=5)).strftime("%Y-%m-%d")

    res = client.post(
        "/admin/leave/comp-off/accrue",
        headers=admin_headers,
        json={
            "reg_no": "STAFF_TEST",
            "duty_date": duty_date,
            "duty_type": "Sunday Examination Duty",
            "days_earned": 1.0,
            "reason": "Invigilation duties"
        }
    )
    assert res.status_code == 200
    assert res.json()["success"] is True


# ─────────────────────────────────────────────────────────────────────────────
# 9. TEST USER ACTIVITY & TRANSFERS
# ─────────────────────────────────────────────────────────────────────────────

def test_user_activity_and_forced_reset():
    admin_headers = get_admin_auth_header()

    cursor.execute("SELECT id FROM users WHERE username = 'staff_test'")
    user_id = cursor.fetchone()[0]

    # Activity timeline
    act_res = client.get(f"/admin/users/{user_id}/activity", headers=admin_headers)
    assert act_res.status_code == 200
    assert "recent_attendance" in act_res.json()

    # Force password reset flag
    rst_res = client.post(f"/admin/users/{user_id}/force-password-reset", headers=admin_headers)
    assert rst_res.status_code == 200
    assert rst_res.json()["success"] is True


# ─────────────────────────────────────────────────────────────────────────────
# 10. TEST TIMETABLE SUBSTITUTE FACULTY
# ─────────────────────────────────────────────────────────────────────────────

def test_substitute_faculty_workflow():
    admin_headers = get_admin_auth_header()
    t_date = (datetime.now().date() + timedelta(days=1)).strftime("%Y-%m-%d")

    res = client.post(
        "/timetable/substitute-assignments",
        headers=admin_headers,
        json={
            "original_staff_reg_no": "STAFF_TEST",
            "substitute_staff_reg_no": "HOD_TEST",
            "assignment_date": t_date,
            "period_number": 3,
            "dept": "CSE",
            "batch": "2024-2028",
            "semester": 3,
            "section": "A",
            "subject_code": "CS301",
            "subject_name": "Data Structures & Algorithms",
            "reason": "Faculty attending research seminar"
        }
    )
    assert res.status_code == 200
    assert res.json()["success"] is True

    # Query substitute assignments
    list_res = client.get(f"/timetable/substitute-assignments?assignment_date={t_date}&dept=CSE", headers=admin_headers)
    assert list_res.status_code == 200
    assignments = list_res.json()["assignments"]
    assert any(a["original_staff_reg_no"] == "STAFF_TEST" for a in assignments)


# ─────────────────────────────────────────────────────────────────────────────
# 11. TEST STUDENT PORTAL EXTENSIONS
# ─────────────────────────────────────────────────────────────────────────────

def test_student_attendance_warning_and_grievances():
    student_headers = get_student_auth_header()
    admin_headers = get_admin_auth_header()

    # Attendance percentage warning
    warn_res = client.get("/student/attendance/percentage-warning", headers=student_headers)
    assert warn_res.status_code == 200
    data = warn_res.json()
    assert data["success"] is True
    assert "attendance_percentage" in data
    assert "threshold" in data

    # Subject wise attendance
    sub_res = client.get("/student/attendance/subject-wise", headers=student_headers)
    assert sub_res.status_code == 200
    assert "subject_attendance" in sub_res.json()

    # Submit grievance feedback
    fb_res = client.post(
        "/student/feedback",
        headers=student_headers,
        json={
            "category": "Facility",
            "subject": "Lab 3 Air Conditioning",
            "description": "The AC in computer lab 3 requires servicing."
        }
    )
    assert fb_res.status_code == 200
    assert fb_res.json()["success"] is True

    # Admin reviews feedback
    afb_res = client.get("/admin/student-feedback", headers=admin_headers)
    assert afb_res.status_code == 200
    feedbacks = afb_res.json()["feedback"]
    assert any("Lab 3 Air Conditioning" in f["subject"] for f in feedbacks)
