"""
Staff Academic Schedule, Calendar & Upcoming Sessions Service
============================================================
Provides unified resolution of faculty teaching sessions across dates:
- Academic Calendar Date Overrides & Day-Order Mappings
- Leave Substitutions & Handover Coverage Detection
- Campus Venue Relocations
- Month Matrix & Chronological Upcoming Sessions Feeds
- Live Countdown & Daily Instruction Digest
- RFC 5545 iCalendar (.ics) Feed Export
- Lesson Notes / Topics Covered Tracking
- Staff Reminder Preferences
"""

from __future__ import annotations

import json
import re
from datetime import date, datetime, timedelta, time
from typing import Any, Dict, List, Optional, Tuple

import pg_adapter

cursor = pg_adapter.cursor
conn = pg_adapter.cursor


# ─────────────────────────────────────────────────────────────────────────────
# DDL INITIALIZATION
# ─────────────────────────────────────────────────────────────────────────────

def run_staff_schedule_ddl() -> None:
    """Create all tables and indexes for staff schedule notes and reminder preferences."""
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS staff_session_notes (
            id                  SERIAL PRIMARY KEY,
            staff_reg_no        VARCHAR(64) NOT NULL,
            timetable_slot_id   INT NOT NULL,
            session_date        DATE NOT NULL,
            subject_code        VARCHAR(30) NOT NULL,
            topic_covered       TEXT NOT NULL,
            learning_objectives TEXT,
            assignment_notes    TEXT,
            created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(staff_reg_no, timetable_slot_id, session_date)
        )
    """)
    for idx in [
        "CREATE INDEX IF NOT EXISTS idx_ssn_staff_date ON staff_session_notes (staff_reg_no, session_date)",
        "CREATE INDEX IF NOT EXISTS idx_ssn_slot ON staff_session_notes (timetable_slot_id)",
        "CREATE INDEX IF NOT EXISTS idx_ssn_subject ON staff_session_notes (subject_code)",
    ]:
        try:
            cursor.execute(idx)
        except Exception:
            pass

    cursor.execute("""
        CREATE TABLE IF NOT EXISTS staff_session_reminder_preferences (
            staff_reg_no           VARCHAR(64) PRIMARY KEY,
            lead_time_minutes      INT NOT NULL DEFAULT 15,
            daily_digest_enabled   BOOLEAN NOT NULL DEFAULT TRUE,
            daily_digest_time      VARCHAR(10) NOT NULL DEFAULT '08:00',
            notify_on_substitution BOOLEAN NOT NULL DEFAULT TRUE,
            notify_on_relocation   BOOLEAN NOT NULL DEFAULT TRUE,
            updated_at             TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)


# ─────────────────────────────────────────────────────────────────────────────
# ACADEMIC CALENDAR & DATE STATUS RESOLVER
# ─────────────────────────────────────────────────────────────────────────────

def resolve_academic_date(target_date: date) -> Dict[str, Any]:
    """
    Resolves holiday, special occasion, day-order mapping, or working day status for a specific date.
    Checks academic_calendar_date_overrides first, then holiday_calendar, then standard weekends.
    """
    target_str = target_date.strftime("%Y-%m-%d")
    calendar_day_name = target_date.strftime("%A")

    # 1. Check academic_calendar_date_overrides
    cursor.execute("""
        SELECT day_type, mapped_day_of_week, day_order, title, reason, declared_by
        FROM academic_calendar_date_overrides
        WHERE override_date = ?
        LIMIT 1
    """, (target_str,))
    row = cursor.fetchone()

    if row:
        if isinstance(row, dict):
            day_type = (row.get("day_type") or "WORKING_DAY").upper()
            mapped_day = row.get("mapped_day_of_week") or calendar_day_name
            day_order = row.get("day_order")
            title = row.get("title") or f"{mapped_day} (Day Order {day_order or '—'})"
            reason = row.get("reason") or ""
        else:
            day_type = (row[0] or "WORKING_DAY").upper()
            mapped_day = row[1] or calendar_day_name
            day_order = row[2]
            title = row[3] or f"{mapped_day} (Day Order {day_order or '—'})"
            reason = row[4] or ""

        is_holiday = day_type in ("HOLIDAY", "OFF_DAY", "DECLARED_HOLIDAY", "PUBLIC_HOLIDAY", "INSTITUTIONAL_HOLIDAY")
        is_special_occasion = day_type in (
            "SPECIAL_EVENT", "SPECIAL_OCCASION", "SPORTS_DAY", "SYMPOSIUM", 
            "ANNUAL_DAY", "CULTURAL", "CULTURAL_EVENT", "FESTIVAL", "EXAM_DAY", "CELEBRATION"
        )
        attendance_required = not (is_holiday or is_special_occasion)
        return {
            "date": target_str,
            "calendar_day_name": calendar_day_name,
            "mapped_day_of_week": mapped_day,
            "day_order": day_order,
            "day_type": day_type,
            "is_holiday": is_holiday,
            "is_special_occasion": is_special_occasion,
            "holiday_title": title if is_holiday else None,
            "occasion_title": title if is_special_occasion else None,
            "title": title,
            "reason": reason,
            "attendance_required": attendance_required,
            "is_override": True,
        }

    # 2. Check holiday_calendar table
    try:
        cursor.execute("""
            SELECT holiday_name, holiday_type, is_optional
            FROM holiday_calendar
            WHERE holiday_date = ?
            LIMIT 1
        """, (target_str,))
        h_row = cursor.fetchone()
        if h_row:
            h_name = (h_row.get("holiday_name") if isinstance(h_row, dict) else h_row[0]) or "College Holiday"
            h_type = (h_row.get("holiday_type") if isinstance(h_row, dict) else h_row[1]) or "institutional"
            return {
                "date": target_str,
                "calendar_day_name": calendar_day_name,
                "mapped_day_of_week": calendar_day_name,
                "day_order": None,
                "day_type": "HOLIDAY",
                "is_holiday": True,
                "is_special_occasion": False,
                "holiday_title": h_name,
                "occasion_title": None,
                "title": h_name,
                "reason": f"Declared {h_type.replace('_', ' ').title()} Holiday",
                "attendance_required": False,
                "is_override": True,
            }
    except Exception:
        pass

    # 3. Standard weekend check (Sunday is Holiday)
    if target_date.weekday() == 6:  # Sunday
        return {
            "date": target_str,
            "calendar_day_name": calendar_day_name,
            "mapped_day_of_week": calendar_day_name,
            "day_order": None,
            "day_type": "HOLIDAY",
            "is_holiday": True,
            "is_special_occasion": False,
            "holiday_title": "Sunday Holiday",
            "occasion_title": None,
            "title": "Sunday",
            "reason": "Weekly Institutional Holiday",
            "attendance_required": False,
            "is_override": False,
        }

    return {
        "date": target_str,
        "calendar_day_name": calendar_day_name,
        "mapped_day_of_week": calendar_day_name,
        "day_order": None,
        "day_type": "WORKING_DAY",
        "is_holiday": False,
        "is_special_occasion": False,
        "holiday_title": None,
        "occasion_title": None,
        "title": calendar_day_name,
        "reason": "",
        "attendance_required": True,
        "is_override": False,
    }


# ─────────────────────────────────────────────────────────────────────────────
# PERIOD TIMINGS TIMELINE GENERATOR
# ─────────────────────────────────────────────────────────────────────────────

def get_period_timings_map(
    dept: str = "CSE",
    batch: Optional[str] = "all",
    semester: Optional[int] = 0,
    section: Optional[str] = "all",
) -> Tuple[List[Dict[str, Any]], Dict[int, Dict[str, Any]]]:
    """Fetch period schedule configuration for class or department and generate 12h/24h timing map."""
    target_batch = (batch or "all").strip()
    try:
        target_sem = int(semester or 0)
    except Exception:
        target_sem = 0
    target_sec = (section or "all").strip()

    cursor.execute("""
        SELECT start_time, total_periods, period_duration_mins, breaks_json,
               (
                   CASE
                       WHEN LOWER(batch) = LOWER(?) AND semester = ? AND LOWER(section) = LOWER(?) 
                            AND batch != 'all' AND semester != 0 AND LOWER(section) != 'all' THEN 40
                       WHEN LOWER(batch) = LOWER(?) AND semester = ? AND (LOWER(section) = 'all' OR section IS NULL)
                            AND batch != 'all' AND semester != 0 THEN 30
                       WHEN LOWER(batch) = LOWER(?) AND (semester = 0 OR semester IS NULL) AND (LOWER(section) = 'all' OR section IS NULL)
                            AND batch != 'all' THEN 20
                       WHEN (LOWER(batch) = 'all' OR batch IS NULL) AND (semester = 0 OR semester IS NULL) AND (LOWER(section) = 'all' OR section IS NULL) THEN 10
                       ELSE 1
                   END
               ) as match_score
        FROM academic_period_configs
        WHERE LOWER(dept) = LOWER(?)
          AND (LOWER(batch) = LOWER(?) OR LOWER(batch) = 'all' OR batch IS NULL)
          AND (semester = ? OR semester = 0 OR semester IS NULL)
          AND (LOWER(section) = LOWER(?) OR LOWER(section) = 'all' OR section IS NULL)
        ORDER BY match_score DESC, updated_at DESC NULLS LAST
        LIMIT 1
    """, (
        target_batch, target_sem, target_sec,
        target_batch, target_sem,
        target_batch,
        dept,
        target_batch,
        target_sem,
        target_sec,
    ))
    row = cursor.fetchone()
    if not row:
        cursor.execute("SELECT start_time, total_periods, period_duration_mins, breaks_json, 1 FROM academic_period_configs WHERE LOWER(dept) = LOWER(?) LIMIT 1", (dept,))
        row = cursor.fetchone()

    start_time = "08:45"
    total_periods = 7
    period_dur = 50
    default_breaks = [
        {"title": "Tea Break", "after_period": 2, "duration_mins": 15},
        {"title": "Lunch Break", "after_period": 4, "duration_mins": 45},
    ]
    breaks_list = default_breaks

    if row:
        if isinstance(row, dict):
            start_time = row.get("start_time") or start_time
            total_periods = row.get("total_periods") or total_periods
            period_dur = row.get("period_duration_mins") or period_dur
            breaks_raw = row.get("breaks_json")
        else:
            start_time = row[0] or start_time
            total_periods = row[1] or total_periods
            period_dur = row[2] or period_dur
            breaks_raw = row[3] if len(row) > 3 else None

        if isinstance(breaks_raw, str):
            try:
                breaks_list = json.loads(breaks_raw)
            except Exception:
                breaks_list = default_breaks
        elif isinstance(breaks_raw, list):
            breaks_list = breaks_raw

    # Build chronological timeline
    timeline: List[Dict[str, Any]] = []
    timing_map: Dict[int, Dict[str, Any]] = {}

    try:
        cur_h, cur_m = map(int, start_time.split(":"))
    except Exception:
        cur_h, cur_m = 8, 45

    curr_minutes = cur_h * 60 + cur_m

    for p in range(1, total_periods + 1):
        p_start_mins = curr_minutes
        p_end_mins = curr_minutes + period_dur

        s_h, s_m = divmod(p_start_mins, 60)
        e_h, e_m = divmod(p_end_mins, 60)

        s_dt = datetime.strptime(f"{s_h:02d}:{s_m:02d}", "%H:%M")
        e_dt = datetime.strptime(f"{e_h:02d}:{e_m:02d}", "%H:%M")

        s_12h = s_dt.strftime("%I:%M %p").lstrip("0")
        e_12h = e_dt.strftime("%I:%M %p").lstrip("0")
        s_24h = f"{s_h:02d}:{s_m:02d}"
        e_24h = f"{e_h:02d}:{e_m:02d}"

        p_info = {
            "type": "period",
            "period_number": p,
            "label": f"Period {p}",
            "startTime": s_12h,
            "endTime": e_12h,
            "start_time": s_12h,
            "end_time": e_12h,
            "start_24h": s_24h,
            "end_24h": e_24h,
            "start_mins": p_start_mins,
            "end_mins": p_end_mins,
            "duration_mins": period_dur,
        }
        timeline.append(p_info)
        timing_map[p] = p_info
        curr_minutes = p_end_mins

        # Check break after this period
        for brk in breaks_list:
            if brk.get("after_period") == p:
                b_dur = brk.get("duration_mins", 15)
                b_title = brk.get("title", "Break")
                b_start_mins = curr_minutes
                b_end_mins = curr_minutes + b_dur

                bs_h, bs_m = divmod(b_start_mins, 60)
                be_h, be_m = divmod(b_end_mins, 60)

                bs_dt = datetime.strptime(f"{bs_h:02d}:{bs_m:02d}", "%H:%M")
                be_dt = datetime.strptime(f"{be_h:02d}:{be_m:02d}", "%H:%M")

                timeline.append({
                    "type": "break",
                    "period_number": None,
                    "label": b_title,
                    "startTime": bs_dt.strftime("%I:%M %p").lstrip("0"),
                    "endTime": be_dt.strftime("%I:%M %p").lstrip("0"),
                    "start_24h": f"{bs_h:02d}:{bs_m:02d}",
                    "end_24h": f"{be_h:02d}:{be_m:02d}",
                    "start_mins": b_start_mins,
                    "end_mins": b_end_mins,
                    "duration_mins": b_dur,
                })
                curr_minutes = b_end_mins

    return timeline, timing_map


# ─────────────────────────────────────────────────────────────────────────────
# STAFF SESSION RESOLVER FOR A SINGLE DATE
# ─────────────────────────────────────────────────────────────────────────────

def get_staff_sessions_for_date(
    staff_reg_no: str,
    target_date: date,
    timing_map: Optional[Dict[int, Dict[str, Any]]] = None,
    subject_filter: Optional[str] = None,
) -> Tuple[Dict[str, Any], List[Dict[str, Any]]]:
    """
    Resolves the exact teaching sessions for a staff member on a specific date.
    Enriches each session with substitutions, venue relocations, live countdowns, and notes.
    """
    staff_reg_clean = staff_reg_no.strip()
    date_info = resolve_academic_date(target_date)

    if date_info["is_holiday"]:
        return date_info, []

    mapped_day = date_info["mapped_day_of_week"]
    target_date_str = target_date.strftime("%Y-%m-%d")
    today_str = datetime.now().strftime("%Y-%m-%d")
    current_time_str = datetime.now().strftime("%H:%M")
    now_dt = datetime.now()

    if timing_map is None:
        _, timing_map = get_period_timings_map()

    # Query all class_timetable slots where staff is original teacher OR substitute for this date
    cursor.execute("""
        SELECT ct.id, ct.dept, ct.batch, ct.semester, ct.section, ct.period_number,
               ct.subject_code, ct.subject_name, ct.staff_reg_no, ct.room_or_lab,
               ct.is_lab_block, ct.lab_batch,
               COALESCE(u.name, os.name, ct.staff_reg_no) as orig_staff_name,
               COALESCE(u.dept, os.dept, ct.dept) as orig_staff_dept,
               ds.subject_type
        FROM class_timetable ct
        LEFT JOIN users u ON LOWER(u.reg_no) = LOWER(ct.staff_reg_no)
        LEFT JOIN other_staff os ON LOWER(os.reg_no) = LOWER(ct.staff_reg_no)
        LEFT JOIN department_subjects ds ON (
            LOWER(ds.dept) = LOWER(ct.dept) AND LOWER(ds.subject_code) = LOWER(ct.subject_code)
        )
        WHERE LOWER(ct.day_of_week) = LOWER(?)
          AND (
            LOWER(ct.staff_reg_no) = LOWER(?)
            OR EXISTS (
                SELECT 1 FROM staff_leave_timetable_assignments slta
                WHERE LOWER(slta.dept) = LOWER(ct.dept)
                  AND slta.batch = ct.batch
                  AND slta.semester = ct.semester
                  AND LOWER(slta.section) = LOWER(ct.section)
                  AND slta.period_number = ct.period_number
                  AND slta.coverage_date = ?
                  AND LOWER(slta.alternate_staff_reg) = LOWER(?)
                  AND slta.status = 'ACTIVE'
            )
          )
        ORDER BY ct.period_number ASC
    """, (mapped_day, staff_reg_clean, target_date_str, staff_reg_clean))

    db_slots = cursor.fetchall()
    sessions: List[Dict[str, Any]] = []

    for r in db_slots:
        if isinstance(r, dict):
            slot_id = r["id"]
            s_dept = r["dept"]
            s_batch = r["batch"]
            s_sem = r["semester"]
            s_sec = r["section"]
            p_num = r["period_number"]
            sub_code = r["subject_code"]
            sub_name = r["subject_name"]
            orig_staff_reg = r["staff_reg_no"]
            orig_venue = r["room_or_lab"]
            is_lab = bool(r["is_lab_block"])
            lab_batch = r["lab_batch"]
            orig_staff_name = r["orig_staff_name"]
            orig_staff_dept = r["orig_staff_dept"]
            sub_type = r.get("subject_type") or ("Lab" if is_lab else "Theory")
        else:
            slot_id = r[0]
            s_dept = r[1]
            s_batch = r[2]
            s_sem = r[3]
            s_sec = r[4]
            p_num = r[5]
            sub_code = r[6]
            sub_name = r[7]
            orig_staff_reg = r[8]
            orig_venue = r[9]
            is_lab = bool(r[10])
            lab_batch = r[11]
            orig_staff_name = r[12]
            orig_staff_dept = r[13]
            sub_type = r[14] if (len(r) > 14 and r[14]) else ("Lab" if is_lab else "Theory")

        # Apply subject code filter if requested
        if subject_filter and subject_filter.strip():
            if sub_code.strip().upper() != subject_filter.strip().upper():
                continue

        # 1. Check if original staff is on approved leave (substituted to someone else)
        cursor.execute("""
            SELECT sa.alternate_staff_reg,
                   COALESCE(u.name, os.name, sa.alternate_staff_reg) as covering_name,
                   COALESCE(u.dept, os.dept, '') as covering_dept,
                   sa.status
            FROM staff_leave_timetable_assignments sa
            LEFT JOIN users u ON LOWER(u.reg_no) = LOWER(sa.alternate_staff_reg)
            LEFT JOIN other_staff os ON LOWER(os.reg_no) = LOWER(sa.alternate_staff_reg)
            WHERE LOWER(sa.dept) = LOWER(?) AND sa.batch = ? AND sa.semester = ?
              AND LOWER(sa.section) = LOWER(?) AND sa.period_number = ?
              AND sa.coverage_date = ? AND sa.status = 'ACTIVE'
            LIMIT 1
        """, (s_dept, s_batch, s_sem, s_sec, p_num, target_date_str))
        sub_row = cursor.fetchone()

        is_substituted = False
        is_covering_for_other = False
        effective_staff_reg = orig_staff_reg
        effective_staff_name = orig_staff_name
        effective_staff_dept = orig_staff_dept
        substitution_note = None

        if sub_row:
            cov_reg = sub_row["alternate_staff_reg"] if isinstance(sub_row, dict) else sub_row[0]
            cov_name = sub_row["covering_name"] if isinstance(sub_row, dict) else sub_row[1]
            cov_dept = sub_row["covering_dept"] if isinstance(sub_row, dict) else sub_row[2]

            if cov_reg.lower() == staff_reg_clean.lower() and orig_staff_reg.lower() != staff_reg_clean.lower():
                # Current staff is covering for another teacher on leave
                is_covering_for_other = True
                effective_staff_reg = staff_reg_clean
                effective_staff_name = cov_name
                effective_staff_dept = cov_dept
                substitution_note = f"Covering for {orig_staff_name} (on Leave)"
            elif orig_staff_reg.lower() == staff_reg_clean.lower() and cov_reg.lower() != staff_reg_clean.lower():
                # Current staff is on leave; class is covered by alternate
                is_substituted = True
                effective_staff_reg = cov_reg
                effective_staff_name = cov_name
                effective_staff_dept = cov_dept
                substitution_note = f"Handed over to {cov_name} ({cov_dept})"

        # 2. Check Venue Relocation Override
        cursor.execute("""
            SELECT new_venue_code, reason
            FROM class_venue_overrides
            WHERE LOWER(dept) = LOWER(?) AND batch = ? AND semester = ? AND LOWER(section) = LOWER(?)
              AND LOWER(day_of_week) = LOWER(?) AND period_number = ? AND override_date = ?
            LIMIT 1
        """, (s_dept, s_batch, s_sem, s_sec, mapped_day, p_num, target_date_str))
        cvo_row = cursor.fetchone()

        is_relocated = False
        effective_venue = orig_venue or "Unassigned Room"
        relocation_reason = None
        if cvo_row:
            is_relocated = True
            effective_venue = cvo_row["new_venue_code"] if isinstance(cvo_row, dict) else cvo_row[0]
            relocation_reason = cvo_row["reason"] if isinstance(cvo_row, dict) else cvo_row[1]

        # 3. Timing & Live Status
        t_info = timing_map.get(p_num, {})
        start_t_str = t_info.get("start_24h", "08:45")
        end_t_str = t_info.get("end_24h", "09:35")
        start_12h = t_info.get("startTime", "8:45 AM")
        end_12h = t_info.get("endTime", "9:35 AM")

        status = "UPCOMING"
        starts_in_minutes = None

        if target_date_str < today_str:
            status = "COMPLETED"
        elif target_date_str > today_str:
            status = "UPCOMING"
        else:
            # Target is Today
            if current_time_str >= end_t_str:
                status = "COMPLETED"
            elif start_t_str <= current_time_str < end_t_str:
                status = "LIVE"
                starts_in_minutes = 0
            else:
                status = "UPCOMING"
                try:
                    s_h, s_m = map(int, start_t_str.split(":"))
                    session_dt = datetime(now_dt.year, now_dt.month, now_dt.day, s_h, s_m)
                    diff_mins = int((session_dt - now_dt).total_seconds() / 60)
                    if diff_mins > 0:
                        starts_in_minutes = diff_mins
                except Exception:
                    pass

        # 4. Fetch Session Note (if any)
        cursor.execute("""
            SELECT id, topic_covered, learning_objectives, assignment_notes, updated_at
            FROM staff_session_notes
            WHERE LOWER(staff_reg_no) = LOWER(?) AND timetable_slot_id = ? AND session_date = ?
            LIMIT 1
        """, (staff_reg_clean, slot_id, target_date_str))
        n_row = cursor.fetchone()

        note_obj = None
        if n_row:
            if isinstance(n_row, dict):
                note_obj = {
                    "id": n_row["id"],
                    "staff_reg_no": staff_reg_clean,
                    "timetable_slot_id": slot_id,
                    "session_date": target_date_str,
                    "subject_code": sub_code,
                    "topic_covered": n_row["topic_covered"],
                    "learning_objectives": n_row.get("learning_objectives"),
                    "assignment_notes": n_row.get("assignment_notes"),
                    "updated_at": str(n_row.get("updated_at") or ""),
                }
            else:
                note_obj = {
                    "id": n_row[0],
                    "staff_reg_no": staff_reg_clean,
                    "timetable_slot_id": slot_id,
                    "session_date": target_date_str,
                    "subject_code": sub_code,
                    "topic_covered": n_row[1],
                    "learning_objectives": n_row[2],
                    "assignment_notes": n_row[3],
                    "updated_at": str(n_row[4] or ""),
                }

        sessions.append({
            "slot_id": slot_id,
            "period_number": p_num,
            "dept": s_dept,
            "batch": s_batch,
            "semester": s_sem,
            "section": s_sec,
            "subject_code": sub_code,
            "subject_name": sub_name,
            "subject_type": sub_type,
            "is_lab_block": is_lab,
            "lab_batch": lab_batch or "ALL",
            "start_time": start_12h,
            "end_time": end_12h,
            "start_24h": start_t_str,
            "end_24h": end_t_str,
            "date": target_date_str,
            "day_of_week": date_info["calendar_day_name"],
            "original_faculty_reg_no": orig_staff_reg,
            "original_faculty_name": orig_staff_name,
            "effective_faculty_reg_no": effective_staff_reg,
            "effective_faculty_name": effective_staff_name,
            "effective_faculty_dept": effective_staff_dept,
            "is_substituted": is_substituted,
            "is_covering_for_other": is_covering_for_other,
            "substitution_note": substitution_note,
            "original_venue": orig_venue or "Unassigned Room",
            "effective_venue": effective_venue,
            "is_relocated": is_relocated,
            "relocation_reason": relocation_reason,
            "status": status,
            "starts_in_minutes": starts_in_minutes,
            "note": note_obj,
        })

    return date_info, sessions


# ─────────────────────────────────────────────────────────────────────────────
# ALLOCATED SUBJECTS FOR STAFF
# ─────────────────────────────────────────────────────────────────────────────

def get_staff_assigned_subjects(staff_reg_no: str) -> List[Dict[str, Any]]:
    """Retrieve distinct list of subjects assigned to the staff member."""
    staff_reg_clean = staff_reg_no.strip()
    cursor.execute("""
        SELECT DISTINCT sfa.dept, sfa.batch, sfa.semester, sfa.section,
                        sfa.subject_code, sfa.subject_name, sfa.subject_type,
                        sfa.weekly_hours,
                        COALESCE(ds.is_lab, FALSE) as is_lab
        FROM subject_faculty_allocations sfa
        LEFT JOIN department_subjects ds ON (
            LOWER(ds.dept) = LOWER(sfa.dept) AND LOWER(ds.subject_code) = LOWER(sfa.subject_code)
        )
        WHERE LOWER(sfa.staff_reg_no) = LOWER(?)
        UNION
        SELECT DISTINCT ct.dept, ct.batch, ct.semester, ct.section,
                        ct.subject_code, ct.subject_name,
                        CASE WHEN ct.is_lab_block THEN 'Lab' ELSE 'Theory' END as subject_type,
                        4 as weekly_hours,
                        ct.is_lab_block as is_lab
        FROM class_timetable ct
        WHERE LOWER(ct.staff_reg_no) = LOWER(?)
        ORDER BY subject_code, section
    """, (staff_reg_clean, staff_reg_clean))

    rows = cursor.fetchall()
    subjects = []
    seen = set()
    for r in rows:
        if isinstance(r, dict):
            key = (r["dept"], r["batch"], r["semester"], r["section"], r["subject_code"])
            if key not in seen:
                seen.add(key)
                subjects.append({
                    "dept": r["dept"],
                    "batch": r["batch"],
                    "semester": r["semester"],
                    "section": r["section"],
                    "subject_code": r["subject_code"],
                    "subject_name": r["subject_name"],
                    "subject_type": r["subject_type"] or "Theory",
                    "weekly_hours": int(r["weekly_hours"] or 4),
                    "is_lab": bool(r["is_lab"]),
                })
        else:
            key = (r[0], r[1], r[2], r[3], r[4])
            if key not in seen:
                seen.add(key)
                subjects.append({
                    "dept": r[0],
                    "batch": r[1],
                    "semester": r[2],
                    "section": r[3],
                    "subject_code": r[4],
                    "subject_name": r[5],
                    "subject_type": r[6] or "Theory",
                    "weekly_hours": int(r[7] or 4),
                    "is_lab": bool(r[8]),
                })
    return subjects


# ─────────────────────────────────────────────────────────────────────────────
# MONTH VIEW GENERATOR
# ─────────────────────────────────────────────────────────────────────────────

def get_staff_calendar_month(
    staff_reg_no: str,
    year: int,
    month: int,
    subject_filter: Optional[str] = None,
) -> Dict[str, Any]:
    """Generates the full month calendar matrix with day statuses and session breakdowns."""
    staff_reg_clean = staff_reg_no.strip()

    # Get Staff Name
    cursor.execute("SELECT name FROM users WHERE LOWER(reg_no) = LOWER(?) UNION SELECT name FROM other_staff WHERE LOWER(reg_no) = LOWER(?) LIMIT 1", (staff_reg_clean, staff_reg_clean))
    user_row = cursor.fetchone()
    staff_name = (user_row["name"] if isinstance(user_row, dict) else user_row[0]) if user_row else "Faculty"

    # Pre-fetch timings map
    _, timing_map = get_period_timings_map()

    # Calculate month bounds
    first_day = date(year, month, 1)
    if month == 12:
        next_month_first = date(year + 1, 1, 1)
    else:
        next_month_first = date(year, month + 1, 1)
    num_days = (next_month_first - first_day).days

    today = date.today()
    days_response: List[Dict[str, Any]] = []
    total_working = 0
    total_holidays = 0
    total_sessions_month = 0

    for d in range(1, num_days + 1):
        cur_date = date(year, month, d)
        date_info, sessions = get_staff_sessions_for_date(
            staff_reg_no=staff_reg_clean,
            target_date=cur_date,
            timing_map=timing_map,
            subject_filter=subject_filter,
        )

        is_hol = date_info["is_holiday"]
        if is_hol:
            total_holidays += 1
        else:
            total_working += 1

        sess_count = len(sessions)
        total_sessions_month += sess_count
        hours = round(sum(s.get("period_duration_mins", 50) for s in sessions) / 60.0, 1) if sess_count > 0 else (sess_count * 50 / 60.0)

        has_sub = any(s.get("is_substituted") or s.get("is_covering_for_other") for s in sessions)

        days_response.append({
            "date": cur_date.strftime("%Y-%m-%d"),
            "day_of_month": d,
            "day_of_week": date_info["calendar_day_name"],
            "mapped_day_of_week": date_info["mapped_day_of_week"],
            "day_order": date_info.get("day_order"),
            "day_type": date_info["day_type"],
            "is_holiday": is_hol,
            "holiday_title": date_info.get("holiday_title"),
            "is_today": cur_date == today,
            "is_past": cur_date < today,
            "is_override": date_info["is_override"],
            "total_sessions": sess_count,
            "total_teaching_hours": round(hours, 2),
            "has_substitution": has_sub,
            "sessions": sessions,
        })

    assigned_subs = get_staff_assigned_subjects(staff_reg_clean)

    return {
        "success": True,
        "staff_reg_no": staff_reg_clean,
        "staff_name": staff_name,
        "year": year,
        "month": month,
        "month_name": first_day.strftime("%B"),
        "total_working_days": total_working,
        "total_holidays": total_holidays,
        "total_sessions_month": total_sessions_month,
        "assigned_subjects": assigned_subs,
        "days": days_response,
    }


# ─────────────────────────────────────────────────────────────────────────────
# CHRONOLOGICAL UPCOMING SESSIONS
# ─────────────────────────────────────────────────────────────────────────────

def get_staff_upcoming_sessions(
    staff_reg_no: str,
    from_date: Optional[date] = None,
    days_ahead: int = 14,
    subject_filter: Optional[str] = None,
) -> Dict[str, Any]:
    """Retrieves chronological list of upcoming sessions for the next N days."""
    staff_reg_clean = staff_reg_no.strip()
    start_dt = from_date or date.today()
    max_days = min(max(days_ahead, 1), 60)
    end_dt = start_dt + timedelta(days=max_days)

    _, timing_map = get_period_timings_map()

    all_upcoming: List[Dict[str, Any]] = []
    today = date.today()

    for i in range(max_days):
        cur_dt = start_dt + timedelta(days=i)
        date_info, sessions = get_staff_sessions_for_date(
            staff_reg_no=staff_reg_clean,
            target_date=cur_dt,
            timing_map=timing_map,
            subject_filter=subject_filter,
        )

        for s in sessions:
            # Include if today and upcoming/live, or future date
            if cur_dt > today or (cur_dt == today and s["status"] in ("UPCOMING", "LIVE")):
                all_upcoming.append(s)

    assigned_subs = get_staff_assigned_subjects(staff_reg_clean)

    return {
        "success": True,
        "staff_reg_no": staff_reg_clean,
        "total_upcoming": len(all_upcoming),
        "from_date": start_dt.strftime("%Y-%m-%d"),
        "to_date": end_dt.strftime("%Y-%m-%d"),
        "assigned_subjects": assigned_subs,
        "sessions": all_upcoming,
    }


# ─────────────────────────────────────────────────────────────────────────────
# REAL-TIME DAILY INSTRUCTION DIGEST
# ─────────────────────────────────────────────────────────────────────────────

def get_staff_daily_digest(staff_reg_no: str, target_date: Optional[date] = None) -> Dict[str, Any]:
    """Computes today's instruction digest, active class, and countdown metrics."""
    staff_reg_clean = staff_reg_no.strip()
    target_dt = target_date or date.today()

    # Get Staff Name
    cursor.execute("SELECT name FROM users WHERE LOWER(reg_no) = LOWER(?) UNION SELECT name FROM other_staff WHERE LOWER(reg_no) = LOWER(?) LIMIT 1", (staff_reg_clean, staff_reg_clean))
    user_row = cursor.fetchone()
    staff_name = (user_row["name"] if isinstance(user_row, dict) else user_row[0]) if user_row else "Faculty"

    timeline, timing_map = get_period_timings_map()
    date_info, sessions = get_staff_sessions_for_date(
        staff_reg_no=staff_reg_clean,
        target_date=target_dt,
        timing_map=timing_map,
    )

    total_classes = len(sessions)
    completed = [s for s in sessions if s["status"] == "COMPLETED"]
    active = next((s for s in sessions if s["status"] == "LIVE"), None)
    upcoming = [s for s in sessions if s["status"] == "UPCOMING"]
    next_session = upcoming[0] if upcoming else None

    countdown = next_session.get("starts_in_minutes") if next_session else None
    teaching_hours = round(total_classes * 50 / 60.0, 2)

    return {
        "success": True,
        "staff_reg_no": staff_reg_clean,
        "staff_name": staff_name,
        "date": target_dt.strftime("%Y-%m-%d"),
        "day_of_week": date_info["calendar_day_name"],
        "mapped_day_of_week": date_info["mapped_day_of_week"],
        "day_order": date_info.get("day_order"),
        "day_type": date_info["day_type"],
        "is_holiday": date_info["is_holiday"],
        "holiday_reason": date_info.get("holiday_title") or date_info.get("reason"),
        "metrics": {
            "total_classes": total_classes,
            "completed_classes": len(completed),
            "remaining_classes": len(upcoming) + (1 if active else 0),
            "total_teaching_hours": teaching_hours,
            "active_session": active,
            "next_session": next_session,
            "next_session_countdown_mins": countdown,
        },
        "timeline": timeline,
        "sessions": sessions,
    }


# ─────────────────────────────────────────────────────────────────────────────
# RFC 5545 iCALENDAR (.ICS) FEED EXPORT
# ─────────────────────────────────────────────────────────────────────────────

def generate_staff_ical_feed(
    staff_reg_no: str,
    from_date: Optional[date] = None,
    days_ahead: int = 90,
) -> str:
    """
    Generates standard RFC 5545 iCalendar (.ics) string for importing into
    Google Calendar, Apple Calendar, or Microsoft Outlook.
    """
    staff_reg_clean = staff_reg_no.strip()
    start_dt = from_date or date.today()
    max_days = min(max(days_ahead, 7), 180)

    # Get Staff Name
    cursor.execute("SELECT name FROM users WHERE LOWER(reg_no) = LOWER(?) UNION SELECT name FROM other_staff WHERE LOWER(reg_no) = LOWER(?) LIMIT 1", (staff_reg_clean, staff_reg_clean))
    user_row = cursor.fetchone()
    staff_name = (user_row["name"] if isinstance(user_row, dict) else user_row[0]) if user_row else staff_reg_clean

    _, timing_map = get_period_timings_map()

    lines = [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//Attenda Educational System//Staff Academic Schedule//EN",
        "CALSCALE:GREGORIAN",
        "METHOD:PUBLISH",
        f"X-WR-CALNAME:Teaching Schedule - {staff_name}",
        "X-WR-TIMEZONE:Asia/Kolkata",
    ]

    from datetime import timezone
    now_utc = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")

    for i in range(max_days):
        cur_dt = start_dt + timedelta(days=i)
        date_info, sessions = get_staff_sessions_for_date(
            staff_reg_no=staff_reg_clean,
            target_date=cur_dt,
            timing_map=timing_map,
        )

        for s in sessions:
            # Skip classes where current staff is on leave and substituted
            if s.get("is_substituted"):
                continue

            slot_id = s["slot_id"]
            p_num = s["period_number"]
            s_date_str = cur_dt.strftime("%Y%m%d")
            
            s_start_raw = s["start_24h"].replace(":", "") + "00"
            s_end_raw = s["end_24h"].replace(":", "") + "00"

            dtstart = f"{s_date_str}T{s_start_raw}"
            dtend = f"{s_date_str}T{s_end_raw}"
            uid = f"attenda-{staff_reg_clean}-{cur_dt.strftime('%Y%m%d')}-P{p_num}-{slot_id}@attenda.institution"

            sub_code = s["subject_code"]
            sub_name = s["subject_name"]
            sec = s["section"]
            batch = s["batch"]
            sem = s["semester"]
            venue = s["effective_venue"]

            summary = f"[{sub_code}] {sub_name} (Sec {sec})"
            desc_lines = [
                f"Subject: {sub_name} ({sub_code})",
                f"Class: {s['dept']} Batch {batch} Sem {sem} Sec {sec}",
                f"Period: {p_num} ({s['start_time']} - {s['end_time']})",
                f"Venue: {venue}",
            ]
            if s.get("is_covering_for_other"):
                desc_lines.append(f"Note: {s.get('substitution_note', 'Substitute Coverage')}")
            if s.get("is_relocated"):
                desc_lines.append(f"Relocation: {s.get('relocation_reason', 'Venue changed')}")

            description = "\\n".join(desc_lines)

            lines.extend([
                "BEGIN:VEVENT",
                f"UID:{uid}",
                f"DTSTAMP:{now_utc}",
                f"DTSTART;TZID=Asia/Kolkata:{dtstart}",
                f"DTEND;TZID=Asia/Kolkata:{dtend}",
                f"SUMMARY:{summary}",
                f"LOCATION:{venue}",
                f"DESCRIPTION:{description}",
                "STATUS:CONFIRMED",
                "CATEGORIES:Teaching,Academic,Class",
                "END:VEVENT",
            ])

    lines.append("END:VCALENDAR")
    return "\r\n".join(lines)


# ─────────────────────────────────────────────────────────────────────────────
# LESSON NOTES / TOPICS COVERED CRUD
# ─────────────────────────────────────────────────────────────────────────────

def save_session_note(
    staff_reg_no: str,
    timetable_slot_id: int,
    session_date: str,
    subject_code: str,
    topic_covered: str,
    learning_objectives: Optional[str] = None,
    assignment_notes: Optional[str] = None,
) -> Dict[str, Any]:
    """Upsert lesson plan / topics taught for a specific class session."""
    staff_reg_clean = staff_reg_no.strip()
    cursor.execute("""
        INSERT INTO staff_session_notes (
            staff_reg_no, timetable_slot_id, session_date, subject_code,
            topic_covered, learning_objectives, assignment_notes, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
        ON CONFLICT (staff_reg_no, timetable_slot_id, session_date) DO UPDATE SET
            subject_code = EXCLUDED.subject_code,
            topic_covered = EXCLUDED.topic_covered,
            learning_objectives = EXCLUDED.learning_objectives,
            assignment_notes = EXCLUDED.assignment_notes,
            updated_at = CURRENT_TIMESTAMP
        RETURNING id, staff_reg_no, timetable_slot_id, session_date, subject_code, topic_covered, learning_objectives, assignment_notes, updated_at
    """, (
        staff_reg_clean,
        timetable_slot_id,
        session_date,
        subject_code.strip(),
        topic_covered.strip(),
        (learning_objectives or "").strip() or None,
        (assignment_notes or "").strip() or None,
    ))
    row = cursor.fetchone()

    if row:
        if isinstance(row, dict):
            return {
                "id": row["id"],
                "staff_reg_no": row["staff_reg_no"],
                "timetable_slot_id": row["timetable_slot_id"],
                "session_date": str(row["session_date"]),
                "subject_code": row["subject_code"],
                "topic_covered": row["topic_covered"],
                "learning_objectives": row.get("learning_objectives"),
                "assignment_notes": row.get("assignment_notes"),
                "updated_at": str(row.get("updated_at") or ""),
            }
        else:
            return {
                "id": row[0],
                "staff_reg_no": row[1],
                "timetable_slot_id": row[2],
                "session_date": str(row[3]),
                "subject_code": row[4],
                "topic_covered": row[5],
                "learning_objectives": row[6],
                "assignment_notes": row[7],
                "updated_at": str(row[8] or ""),
            }
    return {"success": True, "message": "Session note saved."}


def get_session_notes_for_slot(timetable_slot_id: int, staff_reg_no: Optional[str] = None) -> List[Dict[str, Any]]:
    """Retrieve historical session notes for a timetable slot."""
    where = ["timetable_slot_id = ?"]
    params = [timetable_slot_id]
    if staff_reg_no:
        where.append("LOWER(staff_reg_no) = LOWER(?)")
        params.append(staff_reg_no.strip())

    cursor.execute(f"""
        SELECT id, staff_reg_no, timetable_slot_id, session_date, subject_code,
               topic_covered, learning_objectives, assignment_notes, created_at, updated_at
        FROM staff_session_notes
        WHERE {' AND '.join(where)}
        ORDER BY session_date DESC
    """, tuple(params))
    rows = cursor.fetchall()

    notes = []
    for r in rows:
        if isinstance(r, dict):
            notes.append({
                "id": r["id"],
                "staff_reg_no": r["staff_reg_no"],
                "timetable_slot_id": r["timetable_slot_id"],
                "session_date": str(r["session_date"]),
                "subject_code": r["subject_code"],
                "topic_covered": r["topic_covered"],
                "learning_objectives": r.get("learning_objectives"),
                "assignment_notes": r.get("assignment_notes"),
                "created_at": str(r.get("created_at") or ""),
                "updated_at": str(r.get("updated_at") or ""),
            })
        else:
            notes.append({
                "id": r[0],
                "staff_reg_no": r[1],
                "timetable_slot_id": r[2],
                "session_date": str(r[3]),
                "subject_code": r[4],
                "topic_covered": r[5],
                "learning_objectives": r[6],
                "assignment_notes": r[7],
                "created_at": str(r[8] or ""),
                "updated_at": str(r[9] or ""),
            })
    return notes


# ─────────────────────────────────────────────────────────────────────────────
# REMINDER PREFERENCES CRUD
# ─────────────────────────────────────────────────────────────────────────────

def get_reminder_preferences(staff_reg_no: str) -> Dict[str, Any]:
    """Retrieve reminder preferences for a staff member."""
    staff_reg_clean = staff_reg_no.strip()
    cursor.execute("""
        SELECT lead_time_minutes, daily_digest_enabled, daily_digest_time,
               notify_on_substitution, notify_on_relocation, updated_at
        FROM staff_session_reminder_preferences
        WHERE LOWER(staff_reg_no) = LOWER(?)
        LIMIT 1
    """, (staff_reg_clean,))
    row = cursor.fetchone()

    if row:
        if isinstance(row, dict):
            return {
                "success": True,
                "staff_reg_no": staff_reg_clean,
                "lead_time_minutes": row["lead_time_minutes"],
                "daily_digest_enabled": bool(row["daily_digest_enabled"]),
                "daily_digest_time": row["daily_digest_time"],
                "notify_on_substitution": bool(row["notify_on_substitution"]),
                "notify_on_relocation": bool(row["notify_on_relocation"]),
                "updated_at": str(row.get("updated_at") or ""),
            }
        else:
            return {
                "success": True,
                "staff_reg_no": staff_reg_clean,
                "lead_time_minutes": row[0],
                "daily_digest_enabled": bool(row[1]),
                "daily_digest_time": row[2],
                "notify_on_substitution": bool(row[3]),
                "notify_on_relocation": bool(row[4]),
                "updated_at": str(row[5] or ""),
            }

    # Defaults
    return {
        "success": True,
        "staff_reg_no": staff_reg_clean,
        "lead_time_minutes": 15,
        "daily_digest_enabled": True,
        "daily_digest_time": "08:00",
        "notify_on_substitution": True,
        "notify_on_relocation": True,
        "updated_at": None,
    }


def update_reminder_preferences(
    staff_reg_no: str,
    lead_time_minutes: int = 15,
    daily_digest_enabled: bool = True,
    daily_digest_time: str = "08:00",
    notify_on_substitution: bool = True,
    notify_on_relocation: bool = True,
) -> Dict[str, Any]:
    """Save updated reminder preferences for a staff member."""
    staff_reg_clean = staff_reg_no.strip()
    cursor.execute("""
        INSERT INTO staff_session_reminder_preferences (
            staff_reg_no, lead_time_minutes, daily_digest_enabled, daily_digest_time,
            notify_on_substitution, notify_on_relocation, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
        ON CONFLICT (staff_reg_no) DO UPDATE SET
            lead_time_minutes = EXCLUDED.lead_time_minutes,
            daily_digest_enabled = EXCLUDED.daily_digest_enabled,
            daily_digest_time = EXCLUDED.daily_digest_time,
            notify_on_substitution = EXCLUDED.notify_on_substitution,
            notify_on_relocation = EXCLUDED.notify_on_relocation,
            updated_at = CURRENT_TIMESTAMP
    """, (
        staff_reg_clean,
        lead_time_minutes,
        daily_digest_enabled,
        daily_digest_time,
        notify_on_substitution,
        notify_on_relocation,
    ))

    return get_reminder_preferences(staff_reg_clean)


# ─────────────────────────────────────────────────────────────────────────────
# BACKGROUND REMINDER DISPATCH ENGINE
# ─────────────────────────────────────────────────────────────────────────────

def dispatch_upcoming_session_reminders() -> int:
    """
    Evaluates today's upcoming sessions across all staff and generates heads-up
    notifications for sessions starting within each staff's configured lead time.
    Prevents duplicate notifications for the same session.
    """
    today_dt = date.today()
    today_str = today_dt.strftime("%Y-%m-%d")
    now_dt = datetime.now()
    dispatched_count = 0

    # 1. Fetch all distinct active staff with classes today
    cursor.execute("""
        SELECT DISTINCT ct.staff_reg_no
        FROM class_timetable ct
        WHERE LOWER(ct.day_of_week) = LOWER(?)
    """, (today_dt.strftime("%A"),))
    rows = cursor.fetchall()
    staff_regs = [r[0] if not isinstance(r, dict) else r["staff_reg_no"] for r in rows if r]

    for reg in staff_regs:
        if not reg:
            continue
        try:
            prefs = get_reminder_preferences(reg)
            lead_mins = prefs.get("lead_time_minutes", 15)
            _, sessions = get_staff_sessions_for_date(reg, today_dt)

            for s in sessions:
                # Only upcoming sessions that have not started
                if s["status"] != "UPCOMING":
                    continue
                starts_in = s.get("starts_in_minutes")
                if starts_in is not None and 0 <= starts_in <= lead_mins:
                    # Unique notification check for this slot today
                    notif_title = f"Class Starting in {starts_in}m: {s['subject_code']}"
                    notif_msg = f"{s['subject_name']} (Sec {s['section']}) begins at {s['start_time']} in {s['effective_venue']}."
                    if s.get("is_covering_for_other"):
                        notif_msg += f" (Substitute coverage for {s['original_faculty_name']})"

                    # Prevent duplicate for today
                    cursor.execute("""
                        SELECT id FROM notifications_all_roles
                        WHERE LOWER(recipient_reg_no) = LOWER(?)
                          AND title = ?
                          AND created_at >= ?
                        LIMIT 1
                    """, (reg, notif_title, f"{today_str} 00:00:00"))
                    existing = cursor.fetchone()

                    if not existing:
                        cursor.execute("""
                            INSERT INTO notifications_all_roles (
                                recipient_reg_no, title, message, type, is_read, created_by, created_at
                            )
                            VALUES (?, ?, ?, 'SESSION_REMINDER', FALSE, 'SYSTEM', CURRENT_TIMESTAMP)
                        """, (reg, notif_title, notif_msg))
                        dispatched_count += 1
        except Exception as err:
            print(f"[staff_schedule_service] Error dispatching reminder for {reg}: {err}")

    return dispatched_count

