"""
Staff Academic Schedule, Calendar & Upcoming Sessions API Routes
===============================================================
REST API endpoints for:
- Month Calendar Matrix with Holiday & Day-Order awareness
- Chronological Upcoming Sessions Feed
- Real-time Daily Instructional Digest & Class Countdowns
- RFC 5545 iCalendar (.ics) Device Calendar Export
- Lesson Notes & Topics Covered Tracking
- Staff Session Reminder Preferences
"""

from __future__ import annotations

import os
import sys
from datetime import date, datetime
from typing import Optional, List, Dict, Any

from fastapi import APIRouter, HTTPException, Query, Request, Response, Body

# Ensure backend/ is in sys.path
_backend_dir = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
)
if _backend_dir not in sys.path:
    sys.path.insert(0, _backend_dir)

from app.services import staff_schedule_service as svc
from app.api.schemas.schedule import (
    CalendarMonthSummaryResponse,
    DailyDigestResponse,
    SessionUpcomingResponse,
    SessionNoteCreateRequest,
    SessionNoteResponse,
    SessionReminderPreferenceRequest,
    SessionReminderPreferenceResponse,
    AssignedSubjectSummary,
)

router = APIRouter(prefix="/api/v1/staff/schedule", tags=["Staff Academic Schedule & Calendar"])


# ─────────────────────────────────────────────────────────────────────────────
# AUTHENTICATION HELPER
# ─────────────────────────────────────────────────────────────────────────────

def _get_current_user(request: Request) -> dict:
    """Verify authorization token and return user payload."""
    import main as _m
    user = _m.verify_any_user_token(request)
    return user


def _resolve_target_staff(request: Request, staff_reg_no: Optional[str]) -> str:
    """Resolve effective staff reg_no from query parameter or authenticated user token."""
    user = _get_current_user(request)
    user_role = str(user.get("role", "")).lower()
    caller_reg = (user.get("reg_no") or user.get("username") or "").strip()

    if staff_reg_no and staff_reg_no.strip():
        req_reg = staff_reg_no.strip()
        # Non-admin / non-hod users can only view their own schedule
        if user_role not in ("admin", "superadmin", "hod", "head of department", "principal") and req_reg.lower() != caller_reg.lower():
            raise HTTPException(status_code=403, detail="Unauthorized to view another staff's schedule.")
        return req_reg

    return caller_reg


# ─────────────────────────────────────────────────────────────────────────────
# 1. MONTH CALENDAR MATRIX
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/calendar", response_model=CalendarMonthSummaryResponse)
def get_staff_calendar(
    request: Request,
    year: Optional[int] = Query(None, ge=2020, le=2040, description="Calendar year (e.g. 2026)"),
    month: Optional[int] = Query(None, ge=1, le=12, description="Calendar month (1-12)"),
    staff_reg_no: Optional[str] = Query(None, description="Staff Reg No (defaults to caller)"),
    subject_code: Optional[str] = Query(None, description="Optional subject filter"),
):
    """
    Retrieve full monthly calendar matrix for a staff member.
    Includes day-order mappings, holiday indicators, substitution badges, and period sessions.
    """
    effective_staff_reg = _resolve_target_staff(request, staff_reg_no)
    now = datetime.now()
    eff_year = year or now.year
    eff_month = month or now.month

    data = svc.get_staff_calendar_month(
        staff_reg_no=effective_staff_reg,
        year=eff_year,
        month=eff_month,
        subject_filter=subject_code,
    )
    return data


# ─────────────────────────────────────────────────────────────────────────────
# 2. CHRONOLOGICAL UPCOMING SESSIONS
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/upcoming", response_model=SessionUpcomingResponse)
def get_upcoming_sessions(
    request: Request,
    from_date: Optional[str] = Query(None, description="Start date YYYY-MM-DD (defaults to today)"),
    days_ahead: int = Query(14, ge=1, le=60, description="Number of days to look ahead"),
    staff_reg_no: Optional[str] = Query(None, description="Staff Reg No (defaults to caller)"),
    subject_code: Optional[str] = Query(None, description="Optional subject code filter"),
):
    """
    Retrieve chronological list of upcoming teaching sessions for the staff member.
    Enriched with period timings, venue locations, substitution status, and syllabus notes.
    """
    effective_staff_reg = _resolve_target_staff(request, staff_reg_no)

    start_d = date.today()
    if from_date and from_date.strip():
        try:
            start_d = datetime.strptime(from_date.strip(), "%Y-%m-%d").date()
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid from_date format. Expected YYYY-MM-DD.")

    data = svc.get_staff_upcoming_sessions(
        staff_reg_no=effective_staff_reg,
        from_date=start_d,
        days_ahead=days_ahead,
        subject_filter=subject_code,
    )
    return data


# ─────────────────────────────────────────────────────────────────────────────
# 3. REAL-TIME DAILY INSTRUCTION DIGEST
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/daily-digest", response_model=DailyDigestResponse)
def get_daily_instruction_digest(
    request: Request,
    date_str: Optional[str] = Query(None, alias="date", description="Target date YYYY-MM-DD (defaults to today)"),
    staff_reg_no: Optional[str] = Query(None, description="Staff Reg No (defaults to caller)"),
):
    """
    Retrieve today's instructional briefing with active session, next class countdown, and period timeline.
    """
    effective_staff_reg = _resolve_target_staff(request, staff_reg_no)

    target_d = date.today()
    if date_str and date_str.strip():
        try:
            target_d = datetime.strptime(date_str.strip(), "%Y-%m-%d").date()
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid date format. Expected YYYY-MM-DD.")

    data = svc.get_staff_daily_digest(
        staff_reg_no=effective_staff_reg,
        target_date=target_d,
    )
    return data


# ─────────────────────────────────────────────────────────────────────────────
# 4. ASSIGNED SUBJECTS LIST
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/assigned-subjects", response_model=List[AssignedSubjectSummary])
def get_assigned_subjects(
    request: Request,
    staff_reg_no: Optional[str] = Query(None, description="Staff Reg No (defaults to caller)"),
):
    """
    Retrieve list of distinct academic subjects allocated to the staff member.
    """
    effective_staff_reg = _resolve_target_staff(request, staff_reg_no)
    subs = svc.get_staff_assigned_subjects(effective_staff_reg)
    return subs


# ─────────────────────────────────────────────────────────────────────────────
# 5. RFC 5545 iCALENDAR (.ICS) DEVICE CALENDAR EXPORT
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/export.ics")
def export_icalendar_feed(
    request: Request,
    staff_reg_no: Optional[str] = Query(None, description="Staff Reg No (defaults to caller)"),
    from_date: Optional[str] = Query(None, description="Start date YYYY-MM-DD"),
    days_ahead: int = Query(90, ge=7, le=180, description="Days range to export"),
):
    """
    Generate and stream an RFC 5545 compliant .ics calendar file for Apple Calendar, Google Calendar, and Outlook.
    """
    effective_staff_reg = _resolve_target_staff(request, staff_reg_no)

    start_d = date.today()
    if from_date and from_date.strip():
        try:
            start_d = datetime.strptime(from_date.strip(), "%Y-%m-%d").date()
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid from_date format. Expected YYYY-MM-DD.")

    ics_content = svc.generate_staff_ical_feed(
        staff_reg_no=effective_staff_reg,
        from_date=start_d,
        days_ahead=days_ahead,
    )

    filename = f"schedule_{effective_staff_reg}_{start_d.strftime('%Y%m%d')}.ics"
    return Response(
        content=ics_content,
        media_type="text/calendar; charset=utf-8",
        headers={
            "Content-Disposition": f'attachment; filename="{filename}"',
            "Cache-Control": "no-cache, no-store, must-revalidate",
        },
    )


# ─────────────────────────────────────────────────────────────────────────────
# 6. LESSON NOTES / TOPICS COVERED
# ─────────────────────────────────────────────────────────────────────────────

@router.post("/session-notes", response_model=SessionNoteResponse)
def save_session_notes(
    request: Request,
    body: SessionNoteCreateRequest = Body(...),
):
    """
    Save syllabus lesson plan, topic covered, or homework for a specific session date.
    """
    user = _get_current_user(request)
    staff_reg = (user.get("reg_no") or user.get("username") or "").strip()

    res = svc.save_session_note(
        staff_reg_no=staff_reg,
        timetable_slot_id=body.timetable_slot_id,
        session_date=body.session_date,
        subject_code=body.subject_code,
        topic_covered=body.topic_covered,
        learning_objectives=body.learning_objectives,
        assignment_notes=body.assignment_notes,
    )
    return res


@router.get("/session-notes/{slot_id}", response_model=List[SessionNoteResponse])
def get_session_notes(
    slot_id: int,
    request: Request,
    staff_reg_no: Optional[str] = Query(None, description="Staff Reg No"),
):
    """
    Retrieve historical session notes recorded for a timetable slot.
    """
    effective_staff_reg = _resolve_target_staff(request, staff_reg_no)
    notes = svc.get_session_notes_for_slot(slot_id, effective_staff_reg)
    return notes


# ─────────────────────────────────────────────────────────────────────────────
# 7. REMINDER PREFERENCES
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/reminder-preferences", response_model=SessionReminderPreferenceResponse)
def get_reminder_preferences(
    request: Request,
    staff_reg_no: Optional[str] = Query(None, description="Staff Reg No"),
):
    """
    Retrieve personal session reminder and daily briefing preferences.
    """
    effective_staff_reg = _resolve_target_staff(request, staff_reg_no)
    prefs = svc.get_reminder_preferences(effective_staff_reg)
    return prefs


@router.put("/reminder-preferences", response_model=SessionReminderPreferenceResponse)
def update_reminder_preferences(
    request: Request,
    body: SessionReminderPreferenceRequest = Body(...),
):
    """
    Update personal session reminder timing and daily digest switches.
    """
    user = _get_current_user(request)
    staff_reg = (user.get("reg_no") or user.get("username") or "").strip()

    updated = svc.update_reminder_preferences(
        staff_reg_no=staff_reg,
        lead_time_minutes=body.lead_time_minutes,
        daily_digest_enabled=body.daily_digest_enabled,
        daily_digest_time=body.daily_digest_time,
        notify_on_substitution=body.notify_on_substitution,
        notify_on_relocation=body.notify_on_relocation,
    )
    return updated
