"""
Staff Leave & OD — Alternate Staff Assignment Service
=======================================================
Handles the full lifecycle:
  1. Staff submits leave/OD request + nominates an alternate
  2. Alternate has 24 h to accept or decline
  3. On acceptance: timetable slots auto-assigned to alternate
  4. Admin + HOD notified by email (after alternate confirms)
  5. Admin/HOD approve or reject → attendance records updated

Decision log (confirmed by user):
  - Alternate scope     : cross-department allowed
  - Conflict detection  : warn + allow (alternate sees conflicts on accept screen)
  - Decline behaviour   : strict — requester must re-nominate; leave cannot proceed
  - Acceptance deadline : 24 hours (enforced by background check in _run_ddl hook)
"""

from __future__ import annotations

import os
import sys
from datetime import date, datetime, timedelta
from typing import Any, Dict, List, Optional, Tuple

# ── path resolution so this module imports pg_adapter from backend/ ──────────
_backend_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if _backend_dir not in sys.path:
    sys.path.insert(0, _backend_dir)

import pg_adapter

cursor = pg_adapter.cursor
conn = pg_adapter.cursor  # pg_adapter exposes conn as cursor (commit via cursor.connection)


# ─────────────────────────────────────────────────────────────────────────────
# DDL — called once at server startup from main.py _run_ddl()
# ─────────────────────────────────────────────────────────────────────────────

def run_staff_leave_ddl() -> None:
    """Create all tables and indexes for the staff-leave alternate-assignment feature.

    Safe to call multiple times — all statements are idempotent (IF NOT EXISTS).
    """
    # 1. Primary request record
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS staff_leave_requests (
            id                      SERIAL PRIMARY KEY,
            requester_reg_no        VARCHAR(64) NOT NULL,
            requester_name          VARCHAR(160) NOT NULL,
            dept                    VARCHAR(160) NOT NULL,
            requester_role          VARCHAR(80) NOT NULL,
            leave_type              VARCHAR(30) NOT NULL,
            start_date              DATE NOT NULL,
            end_date                DATE NOT NULL,
            is_half_day             BOOLEAN DEFAULT FALSE,
            which_half              VARCHAR(10) DEFAULT NULL,
            reason                  TEXT NOT NULL,
            document_url            TEXT,
            alternate_reg_no        VARCHAR(64),
            alternate_name          VARCHAR(160),
            alternate_dept          VARCHAR(160),
            alternate_role          VARCHAR(80),
            alternate_status        VARCHAR(20) DEFAULT 'PENDING',
            alternate_responded_at  TIMESTAMP,
            alternate_remarks       TEXT,
            alternate_deadline      TIMESTAMP,
            timetable_assigned      BOOLEAN DEFAULT FALSE,
            workflow_status         VARCHAR(30) DEFAULT 'AWAITING_ALTERNATE',
            hod_status              VARCHAR(20) DEFAULT 'PENDING',
            hod_reg_no              VARCHAR(64),
            hod_name                VARCHAR(160),
            hod_remarks             TEXT,
            hod_action_at           TIMESTAMP,
            admin_status            VARCHAR(20) DEFAULT 'PENDING',
            admin_name              VARCHAR(160),
            admin_remarks           TEXT,
            admin_action_at         TIMESTAMP,
            submission_date         TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at              TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)

    # 2. Timetable slot handover records
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS staff_leave_timetable_assignments (
            id                   SERIAL PRIMARY KEY,
            leave_request_id     INT NOT NULL REFERENCES staff_leave_requests(id) ON DELETE CASCADE,
            original_staff_reg   VARCHAR(64) NOT NULL,
            alternate_staff_reg  VARCHAR(64) NOT NULL,
            coverage_date        DATE NOT NULL,
            day_of_week          VARCHAR(20) NOT NULL,
            period_number        INT NOT NULL,
            subject_code         VARCHAR(30) NOT NULL,
            subject_name         VARCHAR(160) NOT NULL,
            dept                 VARCHAR(160) NOT NULL,
            batch                VARCHAR(20) NOT NULL,
            semester             INT NOT NULL,
            section              VARCHAR(10) NOT NULL,
            room_or_lab          VARCHAR(100),
            status               VARCHAR(20) DEFAULT 'ACTIVE',
            created_at           TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)

    # 3. Full audit trail for every status transition
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS staff_leave_audit_log (
            id               SERIAL PRIMARY KEY,
            leave_request_id INT NOT NULL REFERENCES staff_leave_requests(id) ON DELETE CASCADE,
            action           VARCHAR(40) NOT NULL,
            actor_reg_no     VARCHAR(64),
            actor_name       VARCHAR(160),
            actor_role       VARCHAR(30),
            previous_status  VARCHAR(30),
            new_status       VARCHAR(30),
            remarks          TEXT,
            created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)

    # Indexes
    for idx_sql in [
        "CREATE INDEX IF NOT EXISTS idx_slr_requester ON staff_leave_requests (requester_reg_no, submission_date DESC)",
        "CREATE INDEX IF NOT EXISTS idx_slr_alternate ON staff_leave_requests (alternate_reg_no, alternate_status)",
        "CREATE INDEX IF NOT EXISTS idx_slr_workflow ON staff_leave_requests (workflow_status, dept)",
        "CREATE INDEX IF NOT EXISTS idx_slr_deadline ON staff_leave_requests (alternate_deadline) WHERE alternate_status = 'PENDING'",
        "CREATE INDEX IF NOT EXISTS idx_slta_leave_id ON staff_leave_timetable_assignments (leave_request_id)",
        "CREATE INDEX IF NOT EXISTS idx_slta_coverage ON staff_leave_timetable_assignments (coverage_date, alternate_staff_reg)",
        "CREATE INDEX IF NOT EXISTS idx_slal_leave_id ON staff_leave_audit_log (leave_request_id, created_at ASC)",
    ]:
        try:
            cursor.execute(idx_sql)
        except Exception:
            pass

    try:
        conn.connection.commit()
    except Exception:
        pass

    print("[staff_leave_service] DDL applied successfully.")


# ─────────────────────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────────────────────

def _working_dates(start: date, end: date) -> List[Tuple[date, str]]:
    """Return list of (date, day_of_week) for active instructional/working days in range [start, end]."""
    from app.services import staff_schedule_service as sched_svc
    days = []
    current = start
    while current <= end:
        d_info = sched_svc.resolve_academic_date(current)
        if not d_info.get("is_holiday"):
            day_name = d_info.get("day_order_day_name") or d_info.get("calendar_day_name") or current.strftime("%A")
            days.append((current, day_name))
        current += timedelta(days=1)
    return days


def _audit(leave_request_id: int, action: str, actor_reg_no: str,
           actor_name: str, actor_role: str,
           previous_status: Optional[str], new_status: Optional[str],
           remarks: Optional[str] = None) -> None:
    """Insert one row into staff_leave_audit_log."""
    cursor.execute(
        """
        INSERT INTO staff_leave_audit_log
            (leave_request_id, action, actor_reg_no, actor_name, actor_role,
             previous_status, new_status, remarks)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
        """,
        (leave_request_id, action, actor_reg_no, actor_name, actor_role,
         previous_status, new_status, remarks),
    )


def _notify(notification_type: str, title: str, message: str,
            related_id: int, created_for: str) -> None:
    """Insert a row into admin_notifications for in-app badge."""
    try:
        cursor.execute(
            """
            INSERT INTO admin_notifications
                (notification_type, title, message, related_id, created_for)
            VALUES (%s, %s, %s, %s, %s)
            """,
            (notification_type, title, message, related_id, created_for),
        )
    except Exception as exc:
        print(f"[staff_leave_service] Notification insert failed: {exc}")


def _fetch_hod_email(dept: str) -> Optional[str]:
    """Return the first active HOD's email for a department."""
    try:
        cursor.execute(
            "SELECT email FROM users WHERE role = 'hod' AND dept = %s AND is_suspended IS NOT TRUE LIMIT 1",
            (dept,),
        )
        row = cursor.fetchone()
        return row[0] if row else None
    except Exception:
        return None


def _fetch_admin_email() -> Optional[str]:
    """Return the first admin's email."""
    try:
        cursor.execute(
            "SELECT email FROM users WHERE role = 'admin' LIMIT 1"
        )
        row = cursor.fetchone()
        return row[0] if row else None
    except Exception:
        return None


def _fetch_user_email(reg_no: str) -> Optional[str]:
    """Return the email for a user (users table first, then other_staff)."""
    try:
        cursor.execute("SELECT email FROM users WHERE reg_no = %s", (reg_no,))
        row = cursor.fetchone()
        if row:
            return row[0]
        cursor.execute("SELECT email FROM other_staff WHERE reg_no = %s", (reg_no,))
        row = cursor.fetchone()
        return row[0] if row else None
    except Exception:
        return None


# ─────────────────────────────────────────────────────────────────────────────
# PUBLIC API
# ─────────────────────────────────────────────────────────────────────────────

def get_eligible_alternates(requester_reg_no: str) -> List[Dict[str, Any]]:
    """
    Return all staff/HOD/other_staff who can be nominated as alternate.
    Cross-department allowed; the requester themselves are excluded.
    """
    results: List[Dict[str, Any]] = []

    # From users table (staff, hod)
    cursor.execute(
        """
        SELECT reg_no, name, dept, role, COALESCE(email, '') as email
        FROM users
        WHERE reg_no != %s
          AND is_suspended IS NOT TRUE
          AND role IN ('staff', 'hod')
        ORDER BY dept, name
        """,
        (requester_reg_no,),
    )
    for row in cursor.fetchall():
        results.append({
            "reg_no": row[0], "name": row[1],
            "dept": row[2], "role": row[3], "email": row[4],
        })

    # From other_staff table
    cursor.execute(
        """
        SELECT reg_no, name, dept, role, COALESCE(email, '') as email
        FROM other_staff
        WHERE reg_no != %s
          AND is_suspended IS NOT TRUE
        ORDER BY dept, name
        """,
        (requester_reg_no,),
    )
    for row in cursor.fetchall():
        results.append({
            "reg_no": row[0], "name": row[1],
            "dept": row[2], "role": row[3], "email": row[4],
        })

    return results


def resolve_all_staff_reg_variants(staff_input: str) -> List[str]:
    """
    Resolve all possible identifiers for a staff member (reg_no, username, name),
    returning normalized strings.
    """
    if not staff_input:
        return []
    clean = str(staff_input).strip()
    variants = {clean, clean.lower(), clean.upper()}
    try:
        # Check users table
        cursor.execute(
            """
            SELECT reg_no, username, name FROM users 
            WHERE LOWER(TRIM(reg_no)) = LOWER(TRIM(%s)) 
               OR LOWER(TRIM(username)) = LOWER(TRIM(%s)) 
               OR LOWER(TRIM(name)) = LOWER(TRIM(%s))
            """,
            (clean, clean, clean),
        )
        for row in cursor.fetchall():
            for val in row:
                if val:
                    s = str(val).strip()
                    variants.add(s)
                    variants.add(s.lower())
                    variants.add(s.upper())

        # Check other_staff table
        cursor.execute(
            """
            SELECT reg_no, username, name FROM other_staff 
            WHERE LOWER(TRIM(reg_no)) = LOWER(TRIM(%s)) 
               OR LOWER(TRIM(username)) = LOWER(TRIM(%s)) 
               OR LOWER(TRIM(name)) = LOWER(TRIM(%s))
            """,
            (clean, clean, clean),
        )
        for row in cursor.fetchall():
            for val in row:
                if val:
                    s = str(val).strip()
                    variants.add(s)
                    variants.add(s.lower())
                    variants.add(s.upper())
    except Exception as e:
        print(f"[staff_leave_service] resolve_all_staff_reg_variants error: {e}")
    return list(variants)


def get_timetable_for_staff_and_dates(
    staff_reg_no: str, start: date, end: date
) -> List[Dict[str, Any]]:
    """
    Fetch all class_timetable slots for a staff member across the instructional
    working days in [start, end]. Resolves Day-Order mappings, holidays,
    and all staff aliases (reg_no, username, name).
    """
    variants = resolve_all_staff_reg_variants(staff_reg_no)
    if not variants:
        variants = [staff_reg_no]

    clean_variants_lower = list({v.strip().lower() for v in variants if v and v.strip()})
    if not clean_variants_lower:
        return []

    # Import staff_schedule_service to leverage complete academic calendar resolution
    from app.services import staff_schedule_service as sched_svc

    slots: List[Dict[str, Any]] = []
    curr = start
    while curr <= end:
        # Resolve date status (day-order, holiday overrides, sunday)
        d_info = sched_svc.resolve_academic_date(curr)
        if d_info.get("is_holiday") is True:
            curr += timedelta(days=1)
            continue

        mapped_day = d_info.get("day_order_day_name") or d_info.get("calendar_day_name") or curr.strftime("%A")
        date_str = curr.strftime("%Y-%m-%d")

        # Query timetable for this mapped day order matching any staff variant
        placeholders = ", ".join(["%s"] * len(clean_variants_lower))
        cursor.execute(
            f"""
            SELECT id, dept, batch, semester, section, day_of_week, period_number,
                   subject_code, subject_name, staff_reg_no, room_or_lab
            FROM class_timetable
            WHERE LOWER(TRIM(staff_reg_no)) IN ({placeholders})
              AND LOWER(TRIM(day_of_week)) = LOWER(TRIM(%s))
            ORDER BY period_number ASC
            """,
            clean_variants_lower + [mapped_day],
        )
        rows = cursor.fetchall()
        for row in rows:
            slots.append({
                "timetable_id": row[0],
                "dept": row[1],
                "batch": row[2],
                "semester": row[3],
                "section": row[4],
                "day_of_week": mapped_day,
                "period_number": row[6],
                "subject_code": row[7],
                "subject_name": row[8],
                "staff_reg_no": row[9],
                "room_or_lab": row[10],
                "coverage_date": date_str,
            })
        curr += timedelta(days=1)

    return slots


def check_alternate_conflicts(
    alternate_reg_no: str, slots: List[Dict[str, Any]]
) -> List[Dict[str, Any]]:
    """
    For each slot the leave-requester holds, check if the alternate already
    has a different class on the same date+period.
    Returns list of conflicting slots (warn + allow decision — returned to UI).
    """
    if not slots:
        return []

    alt_variants = resolve_all_staff_reg_variants(alternate_reg_no)
    clean_alt_lower = list({v.strip().lower() for v in alt_variants if v and v.strip()})
    if not clean_alt_lower:
        return []

    conflicts: List[Dict[str, Any]] = []
    placeholders = ", ".join(["%s"] * len(clean_alt_lower))

    for slot in slots:
        cdate = slot["coverage_date"]
        day = slot["day_of_week"]
        period = slot["period_number"]

        cursor.execute(
            f"""
            SELECT subject_name, dept, batch, section
            FROM class_timetable
            WHERE LOWER(TRIM(staff_reg_no)) IN ({placeholders})
              AND LOWER(TRIM(day_of_week)) = LOWER(TRIM(%s))
              AND period_number = %s
            LIMIT 1
            """,
            clean_alt_lower + [day, period],
        )
        conflict_row = cursor.fetchone()
        if conflict_row:
            conflicts.append({
                "coverage_date": cdate,
                "day_of_week": day,
                "period_number": period,
                "leave_subject": slot["subject_name"],
                "conflict_subject": conflict_row[0],
                "conflict_dept": conflict_row[1],
                "conflict_batch": conflict_row[2],
                "conflict_section": conflict_row[3],
            })
    return conflicts


def check_staff_classes(
    staff_reg_no: str,
    start_date_str: str,
    end_date_str: str,
    is_half_day: bool = False,
    which_half: Optional[str] = None,
) -> Dict[str, Any]:
    """
    Check if the staff member has scheduled classes in class_timetable
    during the working days in [start_date, end_date].
    Filters by FN (periods 1-4) or AN (periods 5-8) if is_half_day is True.
    """
    try:
        s_date = date.fromisoformat(start_date_str)
        e_date = date.fromisoformat(end_date_str)
    except Exception as e:
        raise ValueError(f"Invalid date format: {e}")

    slots = get_timetable_for_staff_and_dates(staff_reg_no, s_date, e_date)

    if is_half_day and which_half:
        w_half = which_half.upper()
        if w_half in ("FN", "FIRST"):
            slots = [s for s in slots if int(s.get("period_number", 0)) <= 4]
        elif w_half in ("AN", "SECOND"):
            slots = [s for s in slots if int(s.get("period_number", 0)) > 4]

    return {
        "success": True,
        "has_classes": len(slots) > 0,
        "class_count": len(slots),
        "scheduled_slots": slots,
    }


def create_staff_leave_request(
    requester: Dict[str, Any],
    leave_type: str,
    start_date: str,
    end_date: str,
    reason: str,
    alternate_reg_no: Optional[str] = None,
    alternate_name: Optional[str] = None,
    alternate_dept: Optional[str] = None,
    alternate_role: Optional[str] = None,
    is_half_day: bool = False,
    which_half: Optional[str] = None,
    document_url: Optional[str] = None,
) -> Dict[str, Any]:
    """
    Insert a new staff_leave_request.
    - If staff has classes and alternate is provided: status = AWAITING_ALTERNATE (24h deadline).
    - If staff has NO classes (or no alternate required/provided): status = AWAITING_HOD_ADMIN directly.
    """
    if len(reason.strip()) < 10:
        raise ValueError("Reason must be at least 10 characters.")

    class_info = check_staff_classes(requester["reg_no"], start_date, end_date, is_half_day, which_half)
    has_classes = class_info["has_classes"]

    if has_classes and not (alternate_reg_no and alternate_reg_no.strip()):
        raise ValueError(f"Alternate staff nomination is required because you have {class_info['class_count']} scheduled class period(s) during this leave.")

    has_alternate = bool(alternate_reg_no and alternate_reg_no.strip())

    if has_alternate:
        workflow_status = "AWAITING_ALTERNATE"
        alternate_status = "PENDING"
        deadline = datetime.utcnow() + timedelta(hours=24)
    else:
        workflow_status = "AWAITING_HOD_ADMIN"
        alternate_status = "NOT_REQUIRED"
        deadline = None

    cursor.execute(
        """
        INSERT INTO staff_leave_requests (
            requester_reg_no, requester_name, dept, requester_role,
            leave_type, start_date, end_date, is_half_day, which_half,
            reason, document_url,
            alternate_reg_no, alternate_name, alternate_dept, alternate_role,
            alternate_status, alternate_deadline, workflow_status
        ) VALUES (
            %s, %s, %s, %s,
            %s, %s, %s, %s, %s,
            %s, %s,
            %s, %s, %s, %s,
            %s, %s, %s
        )
        RETURNING id
        """,
        (
            requester["reg_no"], requester["name"], requester["dept"], requester["role"],
            leave_type, start_date, end_date, is_half_day,
            which_half if is_half_day else None,
            reason, document_url,
            alternate_reg_no, alternate_name, alternate_dept, alternate_role,
            alternate_status, deadline, workflow_status,
        ),
    )
    row = cursor.fetchone()
    request_id: int = row[0]

    _audit(request_id, "SUBMITTED", requester["reg_no"], requester["name"],
           requester["role"], None, workflow_status,
           "Direct submission (no class coverage needed)" if not has_alternate else None)

    if has_alternate and alternate_reg_no:
        # In-app notification to alternate
        _notify(
            "staff_leave_alternate_request",
            f"Coverage request from {requester['name']}",
            (
                f"{requester['name']} ({requester['dept']}) has nominated you as alternate "
                f"for {leave_type} leave from {start_date} to {end_date}. "
                f"Please respond within 24 hours."
            ),
            request_id,
            alternate_reg_no,
        )

        try:
            conn.connection.commit()
        except Exception:
            pass

        # Email the alternate (fire-and-forget; import here to avoid circular dep)
        try:
            from email_service import notify_alternate_nomination
            alt_email = _fetch_user_email(alternate_reg_no)
            if alt_email:
                notify_alternate_nomination(
                    email=alt_email,
                    alternate_name=alternate_name or "",
                    requester_name=requester["name"],
                    requester_dept=requester["dept"],
                    leave_type=leave_type,
                    start_date=str(start_date),
                    end_date=str(end_date),
                    request_id=request_id,
                )
        except Exception as exc:
            print(f"[staff_leave_service] Alternate email failed (non-fatal): {exc}")
    else:
        # Direct submission: Notify HOD and Admin immediately
        _notify(
            "staff_leave_pending_approval",
            f"New leave request from {requester['name']}",
            f"{requester['name']} ({requester['dept']}) submitted {leave_type} leave from {start_date} to {end_date} (No timetable classes scheduled).",
            request_id,
            "hod",
        )
        _notify(
            "staff_leave_pending_approval",
            f"New leave request from {requester['name']}",
            f"{requester['name']} ({requester['dept']}) submitted {leave_type} leave from {start_date} to {end_date}.",
            request_id,
            "admin",
        )

        try:
            conn.connection.commit()
        except Exception:
            pass

        try:
            from email_service import notify_alternate_accepted
            hod_email = _fetch_hod_email(requester["dept"])
            admin_email = _fetch_admin_email()
            for rec in filter(None, [hod_email, admin_email]):
                notify_alternate_accepted(
                    recipient_email=rec,
                    requester_name=requester["name"],
                    requester_dept=requester["dept"],
                    alternate_name="None (No teaching periods scheduled)",
                    leave_type=leave_type,
                    start_date=str(start_date),
                    end_date=str(end_date),
                    request_id=request_id,
                )
        except Exception as exc:
            print(f"[staff_leave_service] Direct notification email failed (non-fatal): {exc}")

    return get_request_by_id(request_id)


def alternate_respond(
    request_id: int,
    alternate_reg_no: str,
    accepted: bool,
    remarks: Optional[str] = None,
) -> Dict[str, Any]:
    """
    Alternate accepts or declines the nomination.

    - Accept  → timetable slots assigned; workflow moves to AWAITING_HOD_ADMIN;
                HOD + Admin notified by in-app notification + email.
    - Decline → alternate_status = DECLINED; workflow stays AWAITING_ALTERNATE;
                requester must re-nominate (strict mode).
    """
    cursor.execute(
        """
        SELECT id, requester_reg_no, requester_name, dept, requester_role,
               leave_type, start_date, end_date, alternate_reg_no, alternate_name,
               alternate_status, workflow_status, alternate_deadline
        FROM staff_leave_requests
        WHERE id = %s
        """,
        (request_id,),
    )
    row = cursor.fetchone()
    if not row:
        raise ValueError("Leave request not found.")

    (rid, req_reg, req_name, dept, req_role,
     leave_type, start_date, end_date,
     alt_reg, alt_name, alt_status, wf_status, deadline) = row

    if alt_reg != alternate_reg_no:
        raise PermissionError("You are not the nominated alternate for this request.")

    if alt_status != "PENDING":
        raise ValueError(f"This nomination has already been responded to ({alt_status}).")

    if wf_status != "AWAITING_ALTERNATE":
        raise ValueError("This request is no longer awaiting alternate confirmation.")

    # 24 h deadline check
    if deadline and datetime.utcnow() > deadline:
        # Auto-expire — reset so requester can re-nominate
        cursor.execute(
            """
            UPDATE staff_leave_requests
            SET alternate_status = 'EXPIRED', updated_at = CURRENT_TIMESTAMP
            WHERE id = %s
            """,
            (request_id,),
        )
        _audit(request_id, "ALTERNATE_EXPIRED", alt_reg, alt_name or "",
               "alternate", "PENDING", "EXPIRED", "24-hour deadline elapsed")
        try:
            conn.connection.commit()
        except Exception:
            pass
        raise ValueError("The 24-hour acceptance window has expired. The requester must re-nominate an alternate.")

    now = datetime.utcnow()
    start = date.fromisoformat(str(start_date))
    end = date.fromisoformat(str(end_date))

    if accepted:
        new_alt_status = "ACCEPTED"
        new_wf_status = "AWAITING_HOD_ADMIN"

        # Assign timetable slots
        slots = get_timetable_for_staff_and_dates(req_reg, start, end)
        for slot in slots:
            cursor.execute(
                """
                INSERT INTO staff_leave_timetable_assignments (
                    leave_request_id, original_staff_reg, alternate_staff_reg,
                    coverage_date, day_of_week, period_number,
                    subject_code, subject_name, dept, batch, semester, section,
                    room_or_lab, status
                ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, 'ACTIVE')
                ON CONFLICT DO NOTHING
                """,
                (
                    request_id, req_reg, alternate_reg_no,
                    slot["coverage_date"], slot["day_of_week"], slot["period_number"],
                    slot["subject_code"], slot["subject_name"],
                    slot["dept"], slot["batch"], slot["semester"], slot["section"],
                    slot.get("room_or_lab"),
                ),
            )

        cursor.execute(
            """
            UPDATE staff_leave_requests
            SET alternate_status = %s,
                alternate_responded_at = %s,
                alternate_remarks = %s,
                timetable_assigned = TRUE,
                workflow_status = %s,
                updated_at = CURRENT_TIMESTAMP
            WHERE id = %s
            """,
            (new_alt_status, now, remarks, new_wf_status, request_id),
        )

        _audit(request_id, "ALTERNATE_ACCEPTED", alternate_reg_no, alt_name or "",
               "alternate", "PENDING", "ACCEPTED", remarks)

        # Notify HOD (in-app)
        _notify(
            "staff_leave_pending_approval",
            f"Leave request from {req_name} — alternate confirmed",
            (
                f"{req_name} ({dept}) has filed a {leave_type} leave from {start_date} to {end_date}. "
                f"Alternate {alt_name} has confirmed coverage. Awaiting your approval."
            ),
            request_id,
            "hod",
        )

        # Notify Admin (in-app)
        _notify(
            "staff_leave_pending_approval",
            f"Staff Leave — alternate confirmed [{req_name}]",
            (
                f"{req_name} ({dept}) — {leave_type} from {start_date} to {end_date}. "
                f"Coverage by {alt_name} confirmed. Awaiting admin review."
            ),
            request_id,
            "admin",
        )

        # Email HOD + Admin
        try:
            from email_service import notify_alternate_accepted
            hod_email = _fetch_hod_email(dept)
            admin_email = _fetch_admin_email()
            notify_alternate_accepted(
                hod_email=hod_email,
                admin_email=admin_email,
                requester_name=req_name,
                requester_dept=dept,
                alternate_name=alt_name or "",
                leave_type=leave_type,
                start_date=str(start_date),
                end_date=str(end_date),
                request_id=request_id,
            )
        except Exception as exc:
            print(f"[staff_leave_service] HOD/Admin email failed (non-fatal): {exc}")

    else:
        # Declined — strict: requester must re-nominate
        new_alt_status = "DECLINED"
        new_wf_status = "AWAITING_ALTERNATE"  # stays in same stage

        cursor.execute(
            """
            UPDATE staff_leave_requests
            SET alternate_status = %s,
                alternate_responded_at = %s,
                alternate_remarks = %s,
                workflow_status = %s,
                updated_at = CURRENT_TIMESTAMP
            WHERE id = %s
            """,
            (new_alt_status, now, remarks, new_wf_status, request_id),
        )

        _audit(request_id, "ALTERNATE_DECLINED", alternate_reg_no, alt_name or "",
               "alternate", "PENDING", "DECLINED", remarks)

        # Notify requester that alternate declined
        _notify(
            "staff_leave_alternate_declined",
            "Your alternate has declined the coverage request",
            (
                f"{alt_name} has declined your leave coverage request for "
                f"{leave_type} ({start_date} to {end_date}). "
                f"Please nominate a different alternate."
            ),
            request_id,
            req_reg,
        )

    try:
        conn.connection.commit()
    except Exception:
        pass

    return get_request_by_id(request_id)


def re_nominate_alternate(
    request_id: int,
    requester_reg_no: str,
    new_alternate_reg_no: str,
    new_alternate_name: str,
    new_alternate_dept: str,
    new_alternate_role: str,
) -> Dict[str, Any]:
    """
    Requester nominates a new alternate after previous alternate declined/expired.
    Only allowed when workflow_status = 'AWAITING_ALTERNATE'.
    """
    cursor.execute(
        "SELECT requester_reg_no, workflow_status, leave_type, start_date, end_date, requester_name, dept FROM staff_leave_requests WHERE id = %s",
        (request_id,),
    )
    row = cursor.fetchone()
    if not row:
        raise ValueError("Leave request not found.")

    req_reg, wf_status, leave_type, start_date, end_date, req_name, dept = row

    if req_reg != requester_reg_no:
        raise PermissionError("Only the requester can re-nominate an alternate.")

    if wf_status != "AWAITING_ALTERNATE":
        raise ValueError("Cannot re-nominate: request is not in AWAITING_ALTERNATE state.")

    deadline = datetime.utcnow() + timedelta(hours=24)

    cursor.execute(
        """
        UPDATE staff_leave_requests
        SET alternate_reg_no       = %s,
            alternate_name         = %s,
            alternate_dept         = %s,
            alternate_role         = %s,
            alternate_status       = 'PENDING',
            alternate_responded_at = NULL,
            alternate_remarks      = NULL,
            alternate_deadline     = %s,
            timetable_assigned     = FALSE,
            updated_at             = CURRENT_TIMESTAMP
        WHERE id = %s
        """,
        (new_alternate_reg_no, new_alternate_name, new_alternate_dept,
         new_alternate_role, deadline, request_id),
    )

    _audit(request_id, "ALTERNATE_RE_NOMINATED", requester_reg_no, req_name or "",
           "requester", None, "AWAITING_ALTERNATE",
           f"New alternate: {new_alternate_name}")

    _notify(
        "staff_leave_alternate_request",
        f"Coverage request from {req_name}",
        (
            f"{req_name} ({dept}) has nominated you as alternate for "
            f"{leave_type} leave from {start_date} to {end_date}. "
            f"Please respond within 24 hours."
        ),
        request_id,
        new_alternate_reg_no,
    )

    try:
        conn.connection.commit()
    except Exception:
        pass

    # Email new alternate
    try:
        from email_service import notify_alternate_nomination
        alt_email = _fetch_user_email(new_alternate_reg_no)
        if alt_email:
            notify_alternate_nomination(
                email=alt_email,
                alternate_name=new_alternate_name,
                requester_name=req_name or "",
                requester_dept=dept or "",
                leave_type=leave_type,
                start_date=str(start_date),
                end_date=str(end_date),
                request_id=request_id,
            )
    except Exception as exc:
        print(f"[staff_leave_service] Re-nominate email failed (non-fatal): {exc}")

    return get_request_by_id(request_id)


def hod_action(
    request_id: int,
    hod: Dict[str, Any],
    approved: bool,
    remarks: Optional[str] = None,
) -> Dict[str, Any]:
    """HOD approves or rejects a leave request."""
    cursor.execute(
        """
        SELECT requester_reg_no, requester_name, dept, leave_type,
               start_date, end_date, workflow_status, hod_status
        FROM staff_leave_requests WHERE id = %s
        """,
        (request_id,),
    )
    row = cursor.fetchone()
    if not row:
        raise ValueError("Leave request not found.")

    req_reg, req_name, dept, leave_type, start_date, end_date, wf_status, hod_status = row

    if wf_status != "AWAITING_HOD_ADMIN":
        raise ValueError("This request is not yet ready for HOD review.")

    if hod_status != "PENDING":
        raise ValueError(f"HOD has already acted on this request ({hod_status}).")

    new_hod_status = "APPROVED" if approved else "REJECTED"
    now = datetime.utcnow()

    cursor.execute(
        """
        UPDATE staff_leave_requests
        SET hod_status    = %s,
            hod_reg_no    = %s,
            hod_name      = %s,
            hod_remarks   = %s,
            hod_action_at = %s,
            updated_at    = CURRENT_TIMESTAMP
        WHERE id = %s
        """,
        (new_hod_status, hod["reg_no"], hod["name"], remarks, now, request_id),
    )

    _audit(request_id, f"HOD_{new_hod_status}", hod["reg_no"], hod["name"],
           "hod", "PENDING", new_hod_status, remarks)

    if not approved:
        # Reject cascades — revoke timetable slots immediately
        _revoke_timetable_slots(request_id)
        cursor.execute(
            "UPDATE staff_leave_requests SET workflow_status = 'REJECTED', updated_at = CURRENT_TIMESTAMP WHERE id = %s",
            (request_id,),
        )
        _notify(
            "staff_leave_rejected",
            "Your leave request was rejected by HOD",
            f"Your {leave_type} leave ({start_date} to {end_date}) was rejected by HOD. Remarks: {remarks or 'None'}.",
            request_id, req_reg,
        )
        _send_requester_outcome_email(req_reg, req_name or "", leave_type, "Rejected", str(start_date), str(end_date), remarks)
    else:
        # Notify admin to complete approval
        _notify(
            "staff_leave_pending_approval",
            f"HOD-approved leave — needs Admin sign-off [{req_name}]",
            f"{req_name} ({dept}) — {leave_type} leave HOD-approved. Awaiting admin action.",
            request_id, "admin",
        )

    try:
        conn.connection.commit()
    except Exception:
        pass

    return get_request_by_id(request_id)


def admin_action(
    request_id: int,
    admin_name: str,
    approved: bool,
    remarks: Optional[str] = None,
) -> Dict[str, Any]:
    """Admin gives final approval or rejection."""
    cursor.execute(
        """
        SELECT requester_reg_no, requester_name, dept, leave_type,
               start_date, end_date, is_half_day, which_half,
               workflow_status, admin_status
        FROM staff_leave_requests WHERE id = %s
        """,
        (request_id,),
    )
    row = cursor.fetchone()
    if not row:
        raise ValueError("Leave request not found.")

    (req_reg, req_name, dept, leave_type, start_date, end_date,
     is_half_day, which_half, wf_status, admin_status_val) = row

    if wf_status not in ("AWAITING_HOD_ADMIN", "AWAITING_ALTERNATE"):
        raise ValueError("This request cannot be actioned by admin at this stage.")

    if admin_status_val != "PENDING":
        raise ValueError(f"Admin has already acted on this request ({admin_status_val}).")

    new_admin_status = "APPROVED" if approved else "REJECTED"
    new_wf_status = "APPROVED" if approved else "REJECTED"
    now = datetime.utcnow()

    cursor.execute(
        """
        UPDATE staff_leave_requests
        SET admin_status    = %s,
            admin_name      = %s,
            admin_remarks   = %s,
            admin_action_at = %s,
            workflow_status = %s,
            updated_at      = CURRENT_TIMESTAMP
        WHERE id = %s
        """,
        (new_admin_status, admin_name, remarks, now, new_wf_status, request_id),
    )

    _audit(request_id, f"ADMIN_{new_admin_status}", admin_name, admin_name,
           "admin", "PENDING", new_admin_status, remarks)

    if approved:
        # Mark attendance in daily_attendance_status for the leave period
        _credit_leave_attendance(req_reg, req_name or "", dept, leave_type,
                                 date.fromisoformat(str(start_date)),
                                 date.fromisoformat(str(end_date)),
                                 is_half_day, which_half, request_id)
        outcome_label = "Approved"
    else:
        _revoke_timetable_slots(request_id)
        outcome_label = "Rejected"

    _notify(
        f"staff_leave_{new_admin_status.lower()}",
        f"Your leave request was {outcome_label}",
        f"Your {leave_type} leave ({start_date} to {end_date}) was {outcome_label.lower()} by Admin. {remarks or ''}",
        request_id, req_reg,
    )

    _send_requester_outcome_email(req_reg, req_name or "", leave_type, outcome_label,
                                  str(start_date), str(end_date), remarks)

    try:
        conn.connection.commit()
    except Exception:
        pass

    return get_request_by_id(request_id)


def expire_overdue_alternate_requests() -> int:
    """
    Background task: auto-expire PENDING alternate nominations past the 24 h deadline.
    Returns the number of requests expired.
    """
    now = datetime.utcnow()
    cursor.execute(
        """
        UPDATE staff_leave_requests
        SET alternate_status = 'EXPIRED',
            updated_at = CURRENT_TIMESTAMP
        WHERE alternate_status = 'PENDING'
          AND alternate_deadline < %s
        RETURNING id, requester_reg_no, requester_name, alternate_name, leave_type, start_date, end_date
        """,
        (now,),
    )
    rows = cursor.fetchall() or []

    for row in rows:
        req_id, req_reg, req_name, alt_name, ltype, sd, ed = row
        _audit(req_id, "ALTERNATE_EXPIRED", "SYSTEM", "SYSTEM", "system",
               "PENDING", "EXPIRED", "24-hour acceptance window elapsed")
        _notify(
            "staff_leave_alternate_expired",
            "Alternate nomination expired — re-nominate required",
            (
                f"Your nominated alternate ({alt_name}) did not respond within 24 hours "
                f"for your {ltype} leave ({sd} to {ed}). Please nominate a new alternate."
            ),
            req_id, req_reg,
        )

    try:
        conn.connection.commit()
    except Exception:
        pass

    return len(rows)


# ─────────────────────────────────────────────────────────────────────────────
# READ QUERIES
# ─────────────────────────────────────────────────────────────────────────────

def _row_to_dict(row) -> Dict[str, Any]:
    keys = [
        "id", "requester_reg_no", "requester_name", "dept", "requester_role",
        "leave_type", "start_date", "end_date", "is_half_day", "which_half",
        "reason", "document_url",
        "alternate_reg_no", "alternate_name", "alternate_dept", "alternate_role",
        "alternate_status", "alternate_responded_at", "alternate_remarks",
        "alternate_deadline", "timetable_assigned", "workflow_status",
        "hod_status", "hod_reg_no", "hod_name", "hod_remarks", "hod_action_at",
        "admin_status", "admin_name", "admin_remarks", "admin_action_at",
        "submission_date", "updated_at",
    ]
    d: Dict[str, Any] = {}
    for i, k in enumerate(keys):
        v = row[i] if i < len(row) else None
        d[k] = str(v) if isinstance(v, (date, datetime)) else v
    return d


_SELECT_ALL = """
    SELECT id, requester_reg_no, requester_name, dept, requester_role,
           leave_type, start_date, end_date, is_half_day, which_half,
           reason, document_url,
           alternate_reg_no, alternate_name, alternate_dept, alternate_role,
           alternate_status, alternate_responded_at, alternate_remarks,
           alternate_deadline, timetable_assigned, workflow_status,
           hod_status, hod_reg_no, hod_name, hod_remarks, hod_action_at,
           admin_status, admin_name, admin_remarks, admin_action_at,
           submission_date, updated_at
    FROM staff_leave_requests
"""


def get_request_by_id(request_id: int) -> Dict[str, Any]:
    cursor.execute(_SELECT_ALL + " WHERE id = %s", (request_id,))
    row = cursor.fetchone()
    if not row:
        raise ValueError("Leave request not found.")
    return _row_to_dict(row)


def get_requests_for_requester(requester_reg_no: str) -> List[Dict[str, Any]]:
    cursor.execute(
        _SELECT_ALL + " WHERE requester_reg_no = %s ORDER BY submission_date DESC",
        (requester_reg_no,),
    )
    return [_row_to_dict(r) for r in cursor.fetchall()]


def get_pending_alternate_requests(alternate_reg_no: str) -> List[Dict[str, Any]]:
    """All requests where I am nominated alternate and haven't responded yet."""
    cursor.execute(
        _SELECT_ALL + " WHERE alternate_reg_no = %s AND alternate_status = 'PENDING' ORDER BY alternate_deadline ASC",
        (alternate_reg_no,),
    )
    return [_row_to_dict(r) for r in cursor.fetchall()]


def get_all_alternate_requests_for_me(alternate_reg_no: str) -> List[Dict[str, Any]]:
    """All requests (any status) where I was/am the alternate."""
    cursor.execute(
        _SELECT_ALL + " WHERE alternate_reg_no = %s ORDER BY submission_date DESC",
        (alternate_reg_no,),
    )
    return [_row_to_dict(r) for r in cursor.fetchall()]


def get_requests_for_hod(hod_dept: str,
                          workflow_status: Optional[str] = None) -> List[Dict[str, Any]]:
    """HOD sees requests from their department awaiting action."""
    sql = _SELECT_ALL + " WHERE dept = %s"
    params: List[Any] = [hod_dept]
    if workflow_status:
        sql += " AND workflow_status = %s"
        params.append(workflow_status)
    sql += " ORDER BY submission_date DESC"
    cursor.execute(sql, params)
    return [_row_to_dict(r) for r in cursor.fetchall()]


def get_all_requests_admin(
    workflow_status: Optional[str] = None,
    dept: Optional[str] = None,
    leave_type: Optional[str] = None,
    page: int = 1,
    limit: int = 50,
) -> Dict[str, Any]:
    """Admin: paginated, filterable list of all staff leave requests."""
    where_clauses = ["1=1"]
    params: List[Any] = []

    if workflow_status:
        where_clauses.append("workflow_status = %s")
        params.append(workflow_status)
    if dept:
        where_clauses.append("dept = %s")
        params.append(dept)
    if leave_type:
        where_clauses.append("leave_type = %s")
        params.append(leave_type)

    where = " AND ".join(where_clauses)

    cursor.execute(f"SELECT COUNT(*) FROM staff_leave_requests WHERE {where}", params)
    total = cursor.fetchone()[0]

    offset = (page - 1) * limit
    cursor.execute(
        f"{_SELECT_ALL} WHERE {where} ORDER BY submission_date DESC LIMIT %s OFFSET %s",
        params + [limit, offset],
    )
    rows = [_row_to_dict(r) for r in cursor.fetchall()]

    return {"total": total, "page": page, "limit": limit, "requests": rows}


def get_timetable_assignments(request_id: int) -> List[Dict[str, Any]]:
    cursor.execute(
        """
        SELECT id, leave_request_id, original_staff_reg, alternate_staff_reg,
               coverage_date, day_of_week, period_number, subject_code, subject_name,
               dept, batch, semester, section, room_or_lab, status, created_at
        FROM staff_leave_timetable_assignments
        WHERE leave_request_id = %s
        ORDER BY coverage_date, period_number
        """,
        (request_id,),
    )
    cols = ["id", "leave_request_id", "original_staff_reg", "alternate_staff_reg",
            "coverage_date", "day_of_week", "period_number", "subject_code", "subject_name",
            "dept", "batch", "semester", "section", "room_or_lab", "status", "created_at"]
    return [dict(zip(cols, r)) for r in cursor.fetchall()]


def get_audit_log(request_id: int) -> List[Dict[str, Any]]:
    cursor.execute(
        """
        SELECT id, action, actor_reg_no, actor_name, actor_role,
               previous_status, new_status, remarks, created_at
        FROM staff_leave_audit_log
        WHERE leave_request_id = %s
        ORDER BY created_at ASC
        """,
        (request_id,),
    )
    cols = ["id", "action", "actor_reg_no", "actor_name", "actor_role",
            "previous_status", "new_status", "remarks", "created_at"]
    return [dict(zip(cols, r)) for r in cursor.fetchall()]


# ─────────────────────────────────────────────────────────────────────────────
# INTERNAL HELPERS
# ─────────────────────────────────────────────────────────────────────────────

def _revoke_timetable_slots(request_id: int) -> None:
    cursor.execute(
        "UPDATE staff_leave_timetable_assignments SET status = 'REVOKED' WHERE leave_request_id = %s",
        (request_id,),
    )


def _credit_leave_attendance(
    reg_no: str, name: str, dept: str,
    leave_type: str,
    start: date, end: date,
    is_half_day: bool, which_half: Optional[str],
    leave_request_id: int,
) -> None:
    """
    Insert/update daily_attendance_status rows to mark approved OD / Leave days accurately.
    """
    lt_lower = (leave_type or "").lower().strip()
    is_od = "od" in lt_lower or "duty" in lt_lower

    if is_od:
        overall_status = "On Duty (OD)" if not is_half_day else (f"Half Day OD ({which_half or 'FN'})")
        fh_status = "OD" if (not is_half_day or which_half == "FN") else "Absent"
        sh_status = "OD" if (not is_half_day or which_half == "AN") else "Absent"
        att_value = 0.5 if is_half_day else 1.0
    else:
        overall_status = "On Leave" if not is_half_day else (f"Half Day Leave ({which_half or 'FN'})")
        fh_status = "Leave" if (not is_half_day or which_half == "FN") else "Absent"
        sh_status = "Leave" if (not is_half_day or which_half == "AN") else "Absent"
        att_value = 0.0

    working = _working_dates(start, end)
    for cdate, _ in working:
        date_str = str(cdate)
        # Check existing
        cursor.execute(
            "SELECT id, first_half_status, second_half_status FROM daily_attendance_status WHERE reg_no = %s AND date = %s",
            (reg_no, date_str),
        )
        existing = cursor.fetchone()
        if existing:
            # Preserve half-day present scans if this leave is for only one half
            ex_fh = existing[1] if len(existing) > 1 else None
            ex_sh = existing[2] if len(existing) > 2 else None
            
            final_fh = fh_status
            final_sh = sh_status
            if is_half_day:
                if which_half == "FN":
                    final_sh = ex_sh or "Pending"
                elif which_half == "AN":
                    final_fh = ex_fh or "Pending"
            
            # Recalculate attendance value
            calc_val = att_value
            if is_half_day:
                if is_od:
                    calc_val = 0.5 + (0.5 if (final_fh == "Present" or final_sh == "Present") else 0.0)
                else:
                    calc_val = 0.5 if (final_fh == "Present" or final_sh == "Present") else 0.0

            cursor.execute(
                """
                UPDATE daily_attendance_status
                SET status = %s, leave_type = %s, leave_request_id = %s,
                    first_half_status = %s, second_half_status = %s,
                    attendance_value = %s, updated_at = CURRENT_TIMESTAMP
                WHERE reg_no = %s AND date = %s
                """,
                (overall_status, leave_type, leave_request_id, final_fh, final_sh, calc_val, reg_no, date_str),
            )
        else:
            cursor.execute(
                """
                INSERT INTO daily_attendance_status
                    (reg_no, name, dept, date, status, leave_type, leave_request_id, first_half_status, second_half_status, attendance_value, marked_by, marked_at)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, 'Leave Management System', CURRENT_TIMESTAMP)
                """,
                (reg_no, name, dept, date_str, overall_status, leave_type, leave_request_id, fh_status, sh_status, att_value),
            )

    # Balance deduction for casual and earned leave
    try:
        _deduct_leave_balances(reg_no, leave_type, start, end, is_half_day)
    except Exception as exc:
        print(f"[staff_leave_service] Balance deduction warning: {exc}")


def _deduct_leave_balances(
    reg_no: str, leave_type: str, start: date, end: date, is_half_day: bool
) -> None:
    """Deduct approved leave days from casual_leave or earned_leave tables."""
    ltype = (leave_type or "").lower().strip()
    working = _working_dates(start, end)
    day_count = len(working) * (0.5 if is_half_day else 1.0)
    if day_count <= 0:
        return

    current_month = start.strftime("%Y-%m")

    if ltype in ("casual", "cl", "casual leave"):
        cursor.execute(
            """
            SELECT current_month_cl_available, accumulated_cl, cl_used_current_month
            FROM casual_leave
            WHERE reg_no = %s AND current_month = %s
            """,
            (reg_no, current_month),
        )
        row = cursor.fetchone()
        if row:
            cl_avail, accum, used = float(row[0] or 0), float(row[1] or 0), float(row[2] or 0)
            rem = day_count
            new_accum = accum
            new_avail = cl_avail
            if new_accum >= rem:
                new_accum -= rem
                rem = 0
            else:
                rem -= new_accum
                new_accum = 0
                if new_avail >= rem:
                    new_avail -= rem
                    rem = 0
                else:
                    new_avail = 0
            new_used = used + day_count
            cursor.execute(
                """
                UPDATE casual_leave
                SET current_month_cl_available = %s, accumulated_cl = %s,
                    cl_used_current_month = %s, last_updated = CURRENT_TIMESTAMP
                WHERE reg_no = %s AND current_month = %s
                """,
                (new_avail, new_accum, new_used, reg_no, current_month),
            )
    elif ltype in ("earned", "el", "earned leave", "ccl"):
        cursor.execute(
            "SELECT balance FROM earned_leave WHERE reg_no = %s", (reg_no,)
        )
        row = cursor.fetchone()
        if row:
            curr_el = float(row[0] or 0)
            new_el = max(0.0, curr_el - day_count)
            cursor.execute(
                "UPDATE earned_leave SET balance = %s, last_updated = CURRENT_TIMESTAMP WHERE reg_no = %s",
                (new_el, reg_no),
            )


def _send_requester_outcome_email(
    req_reg: str, req_name: str, leave_type: str,
    outcome: str, start_date: str, end_date: str,
    remarks: Optional[str],
) -> None:
    try:
        from email_service import notify_requester_final_outcome
        email = _fetch_user_email(req_reg)
        if email:
            notify_requester_final_outcome(
                requester_email=email,
                name=req_name,
                leave_type=leave_type,
                status=outcome,
                start_date=start_date,
                end_date=end_date,
                remarks=remarks,
            )
    except Exception as exc:
        print(f"[staff_leave_service] Requester outcome email failed (non-fatal): {exc}")
