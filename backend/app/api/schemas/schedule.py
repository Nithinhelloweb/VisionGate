"""Pydantic schemas for staff academic schedule, calendar, and upcoming sessions."""
from datetime import date, datetime, time
from typing import Optional, List, Dict, Any
from pydantic import BaseModel, Field, ConfigDict


class AssignedSubjectSummary(BaseModel):
    """Summary of a subject allocated to the staff member."""
    dept: str
    batch: str
    semester: int
    section: str
    subject_code: str
    subject_name: str
    subject_type: str = "Theory"
    weekly_hours: int = 4
    is_lab: bool = False


class SessionNoteResponse(BaseModel):
    """Lesson note / topic covered for a specific session slot."""
    id: Optional[int] = None
    staff_reg_no: str
    timetable_slot_id: int
    session_date: str
    subject_code: str
    topic_covered: str
    learning_objectives: Optional[str] = None
    assignment_notes: Optional[str] = None
    created_at: Optional[str] = None
    updated_at: Optional[str] = None


class SessionNoteCreateRequest(BaseModel):
    """Payload to save topic covered / lesson plan for a session."""
    timetable_slot_id: int = Field(..., description="Class timetable slot ID")
    session_date: str = Field(..., description="Date of the session YYYY-MM-DD")
    subject_code: str = Field(..., description="Subject code e.g. CS3301")
    topic_covered: str = Field(..., min_length=1, max_length=500, description="Summary of topic taught")
    learning_objectives: Optional[str] = Field(None, max_length=500, description="Key learning objectives")
    assignment_notes: Optional[str] = Field(None, max_length=500, description="Homework or lab instructions")


class SessionDetailResponse(BaseModel):
    """Enriched session details with live dynamic status, venue, and substitution."""
    slot_id: int
    period_number: int
    dept: str
    batch: str
    semester: int
    section: str
    subject_code: str
    subject_name: str
    subject_type: str = "Theory"
    is_lab_block: bool = False
    lab_batch: Optional[str] = "ALL"
    
    # Timing
    start_time: str
    end_time: str
    start_24h: str
    end_24h: str
    date: str
    day_of_week: str
    
    # Faculty Assignment & Substitution Status
    original_faculty_reg_no: str
    original_faculty_name: str
    effective_faculty_reg_no: str
    effective_faculty_name: str
    effective_faculty_dept: Optional[str] = None
    is_substituted: bool = False
    is_covering_for_other: bool = False
    substitution_note: Optional[str] = None
    
    # Venue & Relocation Status
    original_venue: str
    effective_venue: str
    is_relocated: bool = False
    relocation_reason: Optional[str] = None
    
    # Real-time state (LIVE, UPCOMING, COMPLETED)
    status: str = "UPCOMING"
    starts_in_minutes: Optional[int] = None
    
    # Notes & syllabus tracking
    note: Optional[SessionNoteResponse] = None


class CalendarDayCellResponse(BaseModel):
    """Single calendar day cell in monthly matrix view."""
    date: str
    day_of_month: int
    day_of_week: str
    mapped_day_of_week: str
    day_order: Optional[int] = None
    day_type: str = "WORKING_DAY"  # WORKING_DAY, HOLIDAY, OFF_DAY, EXAM_DAY
    is_holiday: bool = False
    holiday_title: Optional[str] = None
    is_today: bool = False
    is_past: bool = False
    is_override: bool = False
    total_sessions: int = 0
    total_teaching_hours: float = 0.0
    has_substitution: bool = False
    sessions: List[SessionDetailResponse] = []


class CalendarMonthSummaryResponse(BaseModel):
    """Full monthly calendar payload for staff."""
    success: bool = True
    staff_reg_no: str
    staff_name: str
    year: int
    month: int
    month_name: str
    total_working_days: int
    total_holidays: int
    total_sessions_month: int
    assigned_subjects: List[AssignedSubjectSummary] = []
    days: List[CalendarDayCellResponse] = []


class DailyDigestMetrics(BaseModel):
    """Top-level metrics for today's instructional day."""
    total_classes: int = 0
    completed_classes: int = 0
    remaining_classes: int = 0
    total_teaching_hours: float = 0.0
    active_session: Optional[SessionDetailResponse] = None
    next_session: Optional[SessionDetailResponse] = None
    next_session_countdown_mins: Optional[int] = None


class DailyDigestResponse(BaseModel):
    """Real-time daily briefing response."""
    success: bool = True
    staff_reg_no: str
    staff_name: str
    date: str
    day_of_week: str
    mapped_day_of_week: str
    day_order: Optional[int] = None
    day_type: str = "WORKING_DAY"
    is_holiday: bool = False
    holiday_reason: Optional[str] = None
    metrics: DailyDigestMetrics
    timeline: List[Dict[str, Any]] = []
    sessions: List[SessionDetailResponse] = []


class SessionUpcomingResponse(BaseModel):
    """Chronological upcoming sessions response."""
    success: bool = True
    staff_reg_no: str
    total_upcoming: int
    from_date: str
    to_date: str
    assigned_subjects: List[AssignedSubjectSummary] = []
    sessions: List[SessionDetailResponse] = []


class SessionReminderPreferenceRequest(BaseModel):
    """Update payload for staff session reminder preferences."""
    lead_time_minutes: int = Field(15, ge=0, le=120, description="Minutes before class to alert")
    daily_digest_enabled: bool = Field(True, description="Enable morning briefing digest")
    daily_digest_time: str = Field("08:00", description="Time of morning digest HH:MM")
    notify_on_substitution: bool = Field(True, description="Notify when substituted or covering")
    notify_on_relocation: bool = Field(True, description="Notify when venue relocated")


class SessionReminderPreferenceResponse(BaseModel):
    """Current preference response."""
    success: bool = True
    staff_reg_no: str
    lead_time_minutes: int
    daily_digest_enabled: bool
    daily_digest_time: str
    notify_on_substitution: bool
    notify_on_relocation: bool
    updated_at: Optional[str] = None
