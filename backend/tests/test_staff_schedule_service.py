"""
Comprehensive Test Suite for Staff Academic Schedule, Calendar & Reminders Hub
Validates unit service functions, database models, RFC 5545 iCalendar generation,
and FastAPI REST endpoints with authentication.
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
import httpx

import pg_adapter
from main import app
from app.services import staff_schedule_service as svc

client = httpx.Client(transport=httpx.ASGITransport(app=app), base_url="http://test")
cursor = pg_adapter.cursor


@pytest.fixture(scope="module", autouse=True)
def setup_test_schedule_environment():
    """Ensure database schema is created and seed test data for faculty schedules."""
    svc.run_staff_schedule_ddl()

    import bcrypt
    pw_hash = bcrypt.hashpw(b"staff123", bcrypt.gensalt()).decode("utf-8")

    # 1. Seed Faculty User 1 (Primary)
    cursor.execute("""
        INSERT INTO users (username, password_hash, reg_no, name, dept, role, suspended)
        VALUES ('staff_prof_a', ?, 'STAFF_PROF_A', 'Prof. Alice Johnson', 'CSE', 'staff', FALSE)
        ON CONFLICT (username) DO UPDATE SET password_hash = EXCLUDED.password_hash, suspended = FALSE
    """, (pw_hash,))

    # 2. Seed Faculty User 2 (Alternate / Substitute)
    cursor.execute("""
        INSERT INTO users (username, password_hash, reg_no, name, dept, role, suspended)
        VALUES ('staff_prof_b', ?, 'STAFF_PROF_B', 'Prof. Bob Smith', 'CSE', 'staff', FALSE)
        ON CONFLICT (username) DO UPDATE SET password_hash = EXCLUDED.password_hash, suspended = FALSE
    """, (pw_hash,))

    # 3. Seed Department Subject
    cursor.execute("""
        INSERT INTO department_subjects (dept, subject_code, subject_name, semester, subject_type, is_lab, regulation)
        VALUES ('CSE', 'CS3301', 'Data Structures & Algorithms', 3, 'Theory', FALSE, '2021')
        ON CONFLICT (dept, subject_code, regulation) DO NOTHING
    """)
    cursor.execute("""
        INSERT INTO department_subjects (dept, subject_code, subject_name, semester, subject_type, is_lab, regulation)
        VALUES ('CSE', 'CS3302', 'Data Structures Laboratory', 3, 'Lab', TRUE, '2021')
        ON CONFLICT (dept, subject_code, regulation) DO NOTHING
    """)

    # 4. Seed Subject Faculty Allocations
    cursor.execute("""
        INSERT INTO subject_faculty_allocations (dept, batch, semester, section, subject_code, subject_name, subject_type, staff_reg_no, weekly_hours)
        VALUES ('CSE', '2024-2028', 3, 'A', 'CS3301', 'Data Structures & Algorithms', 'Theory', 'STAFF_PROF_A', 4)
        ON CONFLICT (dept, batch, semester, section, subject_code, staff_reg_no) DO NOTHING
    """)

    # 5. Seed Class Timetable slots for Monday and Wednesday
    cursor.execute("""
        INSERT INTO class_timetable (dept, batch, semester, section, day_of_week, period_number, subject_code, subject_name, staff_reg_no, room_or_lab, is_lab_block, lab_batch)
        VALUES ('CSE', '2024-2028', 3, 'A', 'Monday', 1, 'CS3301', 'Data Structures & Algorithms', 'STAFF_PROF_A', 'Hall 201', FALSE, 'ALL')
        ON CONFLICT (dept, batch, semester, section, day_of_week, period_number, lab_batch) DO UPDATE SET staff_reg_no = 'STAFF_PROF_A', room_or_lab = 'Hall 201'
    """)
    cursor.execute("""
        INSERT INTO class_timetable (dept, batch, semester, section, day_of_week, period_number, subject_code, subject_name, staff_reg_no, room_or_lab, is_lab_block, lab_batch)
        VALUES ('CSE', '2024-2028', 3, 'A', 'Monday', 2, 'CS3302', 'Data Structures Laboratory', 'STAFF_PROF_A', 'Lab 302', TRUE, 'ALL')
        ON CONFLICT (dept, batch, semester, section, day_of_week, period_number, lab_batch) DO UPDATE SET staff_reg_no = 'STAFF_PROF_A', room_or_lab = 'Lab 302'
    """)
    cursor.execute("""
        INSERT INTO class_timetable (dept, batch, semester, section, day_of_week, period_number, subject_code, subject_name, staff_reg_no, room_or_lab, is_lab_block, lab_batch)
        VALUES ('CSE', '2024-2028', 3, 'A', 'Wednesday', 3, 'CS3301', 'Data Structures & Algorithms', 'STAFF_PROF_A', 'Hall 201', FALSE, 'ALL')
        ON CONFLICT (dept, batch, semester, section, day_of_week, period_number, lab_batch) DO UPDATE SET staff_reg_no = 'STAFF_PROF_A', room_or_lab = 'Hall 201'
    """)


def _get_auth_headers(username="staff_prof_a", password="staff123"):
    """Helper to generate standard Basic/Bearer auth headers."""
    token = base64.b64encode(f"{username}:{password}".encode()).decode()
    return {"Authorization": f"Bearer {token}"}


# ─────────────────────────────────────────────────────────────────────────────
# UNIT TESTS: ACADEMIC DATE & PERIOD TIMINGS
# ─────────────────────────────────────────────────────────────────────────────

def test_resolve_academic_date_standard():
    """Verify regular working day resolution."""
    # A standard Tuesday (e.g. 2026-08-25)
    test_date = date(2026, 8, 25)
    info = svc.resolve_academic_date(test_date)
    assert info["calendar_day_name"] == "Tuesday"
    assert info["mapped_day_of_week"] == "Tuesday"
    assert info["is_holiday"] is False
    assert info["day_type"] == "WORKING_DAY"


def test_resolve_academic_date_sunday_holiday():
    """Verify Sunday is automatically resolved as an institutional holiday."""
    # A Sunday (e.g. 2026-08-30)
    sunday_date = date(2026, 8, 30)
    info = svc.resolve_academic_date(sunday_date)
    assert info["calendar_day_name"] == "Sunday"
    assert info["is_holiday"] is True
    assert info["day_type"] == "HOLIDAY"
    assert "Sunday" in info["holiday_title"]


def test_resolve_academic_date_override():
    """Verify day-order mapping and holiday overrides."""
    override_date = "2026-09-05"
    cursor.execute("""
        INSERT INTO academic_calendar_date_overrides (override_date, day_type, mapped_day_of_week, day_order, title, reason, declared_by)
        VALUES (?, 'WORKING_DAY', 'Wednesday', 3, 'Teachers Day Special Working Day', 'Compensatory Working Day', 'ADMIN')
        ON CONFLICT (override_date) DO UPDATE SET mapped_day_of_week = 'Wednesday', day_order = 3
    """, (override_date,))

    info = svc.resolve_academic_date(date(2026, 9, 5))
    assert info["is_override"] is True
    assert info["mapped_day_of_week"] == "Wednesday"
    assert info["day_order"] == 3
    assert info["is_holiday"] is False


def test_get_period_timings_map():
    """Verify generation of period and break timelines."""
    timeline, timing_map = svc.get_period_timings_map("CSE")
    assert len(timeline) >= 7
    assert 1 in timing_map
    assert 2 in timing_map
    assert "start_time" in timing_map[1]
    assert "end_time" in timing_map[1]
    assert "start_24h" in timing_map[1]


# ─────────────────────────────────────────────────────────────────────────────
# UNIT TESTS: SESSIONS, SUBSTITUTION & VENUE RELOCATION
# ─────────────────────────────────────────────────────────────────────────────

def test_get_staff_sessions_for_date():
    """Verify retrieving teaching periods for Monday."""
    monday_date = date(2026, 8, 17)  # Clean Monday without venue overrides
    cursor.execute("DELETE FROM class_venue_overrides WHERE override_date = '2026-08-17'")
    cursor.execute("DELETE FROM staff_leave_timetable_assignments WHERE coverage_date = '2026-08-17'")
    date_info, sessions = svc.get_staff_sessions_for_date("STAFF_PROF_A", monday_date)

    assert date_info["calendar_day_name"] == "Monday"
    assert len(sessions) >= 2
    assert sessions[0]["subject_code"] == "CS3301"
    assert sessions[0]["period_number"] == 1
    assert sessions[0]["effective_venue"] == "Hall 201"
    assert sessions[0]["is_substituted"] is False


def test_venue_relocation_enrichment():
    """Verify that class_venue_overrides dynamically updates the effective venue."""
    target_date = "2026-08-24"
    cursor.execute("""
        INSERT INTO class_venue_overrides (
            dept, batch, semester, section, day_of_week, period_number, override_date,
            original_room_or_lab, new_venue_code, new_venue_name, relocated_by_staff_reg_no, reason
        )
        VALUES ('CSE', '2024-2028', 3, 'A', 'Monday', 1, ?, 'Hall 201', 'Auditorium-A', 'Main Auditorium', 'STAFF_PROF_A', 'Guest Lecture')
        ON CONFLICT (dept, batch, semester, section, day_of_week, period_number, override_date)
        DO UPDATE SET new_venue_code = 'Auditorium-A', reason = 'Guest Lecture'
    """, (target_date,))

    _, sessions = svc.get_staff_sessions_for_date("STAFF_PROF_A", date(2026, 8, 24))
    assert len(sessions) >= 1
    p1 = next(s for s in sessions if s["period_number"] == 1)
    assert p1["is_relocated"] is True
    assert p1["effective_venue"] == "Auditorium-A"
    assert p1["relocation_reason"] == "Guest Lecture"


def test_staff_leave_substitution_reflection():
    """Verify that approved leave substitution is reflected on both original and alternate faculty."""
    cov_date = "2026-08-24"
    
    # 1. Create dummy leave request and timetable assignment
    cursor.execute("""
        INSERT INTO staff_leave_requests (
            id, requester_reg_no, requester_name, dept, requester_role, leave_type,
            start_date, end_date, reason, alternate_reg_no, alternate_name, alternate_status,
            workflow_status, hod_status, admin_status
        )
        VALUES (99901, 'STAFF_PROF_A', 'Prof. Alice Johnson', 'CSE', 'staff', 'Casual Leave',
                ?, ?, 'Medical appointment', 'STAFF_PROF_B', 'Prof. Bob Smith', 'ACCEPTED',
                'APPROVED', 'APPROVED', 'APPROVED')
        ON CONFLICT (id) DO NOTHING
    """, (cov_date, cov_date))

    cursor.execute("""
        INSERT INTO staff_leave_timetable_assignments (
            leave_request_id, original_staff_reg, alternate_staff_reg, coverage_date,
            day_of_week, period_number, subject_code, subject_name, dept, batch, semester, section,
            room_or_lab, status
        )
        VALUES (99901, 'STAFF_PROF_A', 'STAFF_PROF_B', ?, 'Monday', 2,
                'CS3302', 'Data Structures Laboratory', 'CSE', '2024-2028', 3, 'A', 'Lab 302', 'ACTIVE')
        ON CONFLICT DO NOTHING
    """, (cov_date,))

    # Test Original Faculty (Prof A): Period 2 is marked as substituted / handed over
    _, prof_a_sessions = svc.get_staff_sessions_for_date("STAFF_PROF_A", date(2026, 8, 24))
    p2_a = next(s for s in prof_a_sessions if s["period_number"] == 2)
    assert p2_a["is_substituted"] is True
    assert "STAFF_PROF_B" in p2_a["effective_faculty_reg_no"]

    # Test Alternate Faculty (Prof B): Period 2 appears as covering for Prof A
    _, prof_b_sessions = svc.get_staff_sessions_for_date("STAFF_PROF_B", date(2026, 8, 24))
    assert len(prof_b_sessions) >= 1
    p2_b = next(s for s in prof_b_sessions if s["period_number"] == 2)
    assert p2_b["is_covering_for_other"] is True
    assert p2_b["original_faculty_reg_no"] == "STAFF_PROF_A"


# ─────────────────────────────────────────────────────────────────────────────
# UNIT TESTS: MONTH VIEW, UPCOMING SESSIONS & DAILY DIGEST
# ─────────────────────────────────────────────────────────────────────────────

def test_get_staff_calendar_month():
    """Verify monthly matrix contains correct days and aggregated session counts."""
    res = svc.get_staff_calendar_month("STAFF_PROF_A", 2026, 8)
    assert res["success"] is True
    assert res["staff_reg_no"] == "STAFF_PROF_A"
    assert res["year"] == 2026
    assert res["month"] == 8
    assert len(res["days"]) == 31
    assert res["total_working_days"] > 0
    assert res["total_holidays"] > 0
    assert res["total_sessions_month"] > 0
    assert len(res["assigned_subjects"]) >= 1


def test_get_staff_upcoming_sessions_with_filter():
    """Verify upcoming sessions list and subject code filtering."""
    res = svc.get_staff_upcoming_sessions("STAFF_PROF_A", from_date=date(2026, 8, 24), days_ahead=7)
    assert res["success"] is True
    assert res["total_upcoming"] > 0

    # Filter for CS3301 only
    filtered = svc.get_staff_upcoming_sessions(
        "STAFF_PROF_A",
        from_date=date(2026, 8, 24),
        days_ahead=7,
        subject_filter="CS3301",
    )
    for s in filtered["sessions"]:
        assert s["subject_code"] == "CS3301"


def test_get_staff_daily_digest():
    """Verify daily instruction digest output and countdown structure."""
    res = svc.get_staff_daily_digest("STAFF_PROF_A", target_date=date(2026, 8, 24))
    assert res["success"] is True
    assert "metrics" in res
    assert "total_classes" in res["metrics"]
    assert len(res["timeline"]) > 0


# ─────────────────────────────────────────────────────────────────────────────
# UNIT TESTS: iCALENDAR (.ICS) FEED GENERATION
# ─────────────────────────────────────────────────────────────────────────────

def test_generate_staff_ical_feed():
    """Verify RFC 5545 valid calendar feed generation."""
    ics_text = svc.generate_staff_ical_feed("STAFF_PROF_A", from_date=date(2026, 8, 24), days_ahead=14)
    assert "BEGIN:VCALENDAR" in ics_text
    assert "VERSION:2.0" in ics_text
    assert "PRODID:-//Attenda Educational System//Staff Academic Schedule//EN" in ics_text
    assert "BEGIN:VEVENT" in ics_text
    assert "SUMMARY:[CS3301]" in ics_text
    assert "LOCATION:" in ics_text
    assert "END:VCALENDAR" in ics_text


# ─────────────────────────────────────────────────────────────────────────────
# UNIT TESTS: LESSON NOTES & REMINDER PREFERENCES CRUD
# ─────────────────────────────────────────────────────────────────────────────

def test_session_notes_crud():
    """Verify saving and retrieving lesson plans/topics covered."""
    slot_id = 1
    sess_date = "2026-08-24"

    # Save note
    saved = svc.save_session_note(
        staff_reg_no="STAFF_PROF_A",
        timetable_slot_id=slot_id,
        session_date=sess_date,
        subject_code="CS3301",
        topic_covered="Binary Search Trees - Insertion & Deletion Algorithms",
        learning_objectives="Understand BST node balancing and algorithmic complexity",
        assignment_notes="Implement BST deletion in C++ for next lab",
    )
    assert saved["topic_covered"] == "Binary Search Trees - Insertion & Deletion Algorithms"
    assert saved["subject_code"] == "CS3301"

    # Retrieve note
    notes = svc.get_session_notes_for_slot(slot_id, "STAFF_PROF_A")
    assert len(notes) >= 1
    assert notes[0]["topic_covered"] == "Binary Search Trees - Insertion & Deletion Algorithms"


def test_reminder_preferences_crud():
    """Verify updating and reading staff session reminder preferences."""
    updated = svc.update_reminder_preferences(
        staff_reg_no="STAFF_PROF_A",
        lead_time_minutes=30,
        daily_digest_enabled=True,
        daily_digest_time="07:30",
        notify_on_substitution=True,
        notify_on_relocation=True,
    )
    assert updated["lead_time_minutes"] == 30
    assert updated["daily_digest_time"] == "07:30"

    fetched = svc.get_reminder_preferences("STAFF_PROF_A")
    assert fetched["lead_time_minutes"] == 30
    assert fetched["daily_digest_enabled"] is True


def test_dispatch_upcoming_session_reminders():
    """Verify automated background reminder execution."""
    dispatched = svc.dispatch_upcoming_session_reminders()
    assert isinstance(dispatched, int)


# ─────────────────────────────────────────────────────────────────────────────
# FASTAPI ENDPOINT INTEGRATION TESTS
# ─────────────────────────────────────────────────────────────────────────────

@pytest.mark.anyio
async def test_api_get_calendar_month():
    """Integration test for GET /api/v1/staff/schedule/calendar"""
    headers = _get_auth_headers("staff_prof_a", "staff123")
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as ac:
        resp = await ac.get("/api/v1/staff/schedule/calendar?year=2026&month=8", headers=headers)
        assert resp.status_code == 200
        data = resp.json()
        assert data["success"] is True
        assert data["staff_reg_no"] == "STAFF_PROF_A"
        assert len(data["days"]) == 31


@pytest.mark.anyio
async def test_api_get_upcoming_sessions():
    """Integration test for GET /api/v1/staff/schedule/upcoming"""
    headers = _get_auth_headers("staff_prof_a", "staff123")
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as ac:
        resp = await ac.get("/api/v1/staff/schedule/upcoming?from_date=2026-08-24&days_ahead=7", headers=headers)
        assert resp.status_code == 200
        data = resp.json()
        assert data["success"] is True
        assert "sessions" in data


@pytest.mark.anyio
async def test_api_get_daily_digest():
    """Integration test for GET /api/v1/staff/schedule/daily-digest"""
    headers = _get_auth_headers("staff_prof_a", "staff123")
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as ac:
        resp = await ac.get("/api/v1/staff/schedule/daily-digest?date=2026-08-24", headers=headers)
        assert resp.status_code == 200
        data = resp.json()
        assert data["success"] is True
        assert data["day_of_week"] == "Monday"


@pytest.mark.anyio
async def test_api_get_assigned_subjects():
    """Integration test for GET /api/v1/staff/schedule/assigned-subjects"""
    headers = _get_auth_headers("staff_prof_a", "staff123")
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as ac:
        resp = await ac.get("/api/v1/staff/schedule/assigned-subjects", headers=headers)
        assert resp.status_code == 200
        data = resp.json()
        assert isinstance(data, list)
        assert len(data) >= 1
        assert data[0]["subject_code"] == "CS3301"


@pytest.mark.anyio
async def test_api_export_ical():
    """Integration test for GET /api/v1/staff/schedule/export.ics"""
    headers = _get_auth_headers("staff_prof_a", "staff123")
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as ac:
        resp = await ac.get("/api/v1/staff/schedule/export.ics?from_date=2026-08-24&days_ahead=14", headers=headers)
        assert resp.status_code == 200
        assert "text/calendar" in resp.headers.get("content-type", "")
        assert "BEGIN:VCALENDAR" in resp.text
        assert "END:VCALENDAR" in resp.text


@pytest.mark.anyio
async def test_api_session_notes_save_and_retrieve():
    """Integration test for POST and GET session notes"""
    headers = _get_auth_headers("staff_prof_a", "staff123")
    payload = {
        "timetable_slot_id": 1,
        "session_date": "2026-08-24",
        "subject_code": "CS3301",
        "topic_covered": "Graph Traversal Algorithms (BFS and DFS)",
        "learning_objectives": "Compare BFS vs DFS time complexity",
        "assignment_notes": "Problems 4.1 to 4.5 in textbook",
    }
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as ac:
        post_resp = await ac.post("/api/v1/staff/schedule/session-notes", json=payload, headers=headers)
        assert post_resp.status_code == 200
        saved = post_resp.json()
        assert saved["topic_covered"] == "Graph Traversal Algorithms (BFS and DFS)"

        get_resp = await ac.get("/api/v1/staff/schedule/session-notes/1", headers=headers)
        assert get_resp.status_code == 200
        notes = get_resp.json()
        assert len(notes) >= 1


@pytest.mark.anyio
async def test_api_reminder_preferences():
    """Integration test for GET and PUT reminder preferences"""
    headers = _get_auth_headers("staff_prof_a", "staff123")
    payload = {
        "lead_time_minutes": 20,
        "daily_digest_enabled": True,
        "daily_digest_time": "08:15",
        "notify_on_substitution": True,
        "notify_on_relocation": True,
    }
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as ac:
        put_resp = await ac.put("/api/v1/staff/schedule/reminder-preferences", json=payload, headers=headers)
        assert put_resp.status_code == 200
        data = put_resp.json()
        assert data["lead_time_minutes"] == 20
        assert data["daily_digest_time"] == "08:15"

        get_resp = await ac.get("/api/v1/staff/schedule/reminder-preferences", headers=headers)
        assert get_resp.status_code == 200
        assert get_resp.json()["lead_time_minutes"] == 20


def test_check_staff_leave_classes_alias_resolution():
    """Verify that staff leave class checker accurately resolves username vs reg_no aliases and dates."""
    from app.services import staff_leave_service
    # Test for demoo / STAFF_0001
    res_reg = staff_leave_service.check_staff_classes("STAFF_0001", "2026-08-24", "2026-08-24")
    res_user = staff_leave_service.check_staff_classes("demoo", "2026-08-24", "2026-08-24")

    assert res_reg["success"] is True
    assert res_reg["has_classes"] is True
    assert res_reg["class_count"] >= 1

    assert res_user["success"] is True
    assert res_user["has_classes"] is True
    assert res_user["class_count"] == res_reg["class_count"]
    assert res_user["scheduled_slots"][0]["subject_code"] == "24CS602"


@pytest.mark.anyio
async def test_api_check_staff_scheduled_classes_endpoint():
    """Integration test for GET /staff/leave/check-classes with alias resolution"""
    headers = _get_auth_headers("staff_prof_a", "staff123")
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as ac:
        resp = await ac.get("/staff/leave/check-classes?start_date=2026-08-24&end_date=2026-08-24", headers=headers)
        assert resp.status_code == 200
        data = resp.json()
        assert data["success"] is True
        assert data["has_classes"] is True
        assert data["class_count"] >= 1


