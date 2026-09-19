"""
Attenda Features Extension Router
=================================
Provides all 50+ missing essential features across 12 tabs:
1.  Dashboard Summary & Announcements
2.  Attendance Corrections Dispute Workflow & Regularisation Window
3.  Comprehensive Attendance & Leave Reports & Analytics Tab
4.  Standardized Attendance & Report Exports (Excel, PDF, CSV)
5.  Unified Notification System for all roles + Preferences + Broadcast
6.  Active Session Management, Login Logs & 2FA Security
7.  Extended Settings (SMTP, Maintenance Mode, Session TTL, Backup/Restore, Anti-Spoofing)
8.  Institutional Holiday Calendar Management
9.  Leave Balances, Calendar & Comp-Off / Carry-Forward Engine
10. User Activity Timeline, Transfers & Forced Password Reset
11. Timetable Substitute Faculty Assignment & Weekly Matrix
12. Student Attendance Warning Engine & Grievance Feedback Portal
"""

import os
import sys
import json
import base64
import smtplib
from datetime import datetime, date, timedelta
from typing import Optional, List, Dict, Any, Union

from fastapi import APIRouter, Request, Response, HTTPException, Query, Body, Depends
from fastapi.responses import StreamingResponse, JSONResponse
from pydantic import BaseModel

import pg_adapter
from email_service import (
    get_smtp_configuration,
    send_email,
    notify_leave_status_change,
    notify_attendance_correction_outcome,
    notify_daily_pending_digest,
)
from export_engine import (
    generate_csv,
    generate_excel,
    generate_pdf_table,
)

# Optional PyOTP for 2FA
try:
    import pyotp
    PYOTP_AVAILABLE = True
except ImportError:
    PYOTP_AVAILABLE = False

feature_router = APIRouter(tags=["Extended Features"])
cursor = pg_adapter.cursor
conn = pg_adapter.cursor


# ─────────────────────────────────────────────────────────────────────────────
# AUDIT LOGGING HELPER
# ─────────────────────────────────────────────────────────────────────────────

def write_audit_log(
    action_type: str,
    actor_reg_no: Optional[str] = None,
    actor_name: Optional[str] = None,
    actor_role: Optional[str] = None,
    entity_type: Optional[str] = None,
    entity_id: Optional[str] = None,
    details: Optional[str] = None,
    ip_address: Optional[str] = None,
    success: bool = True,
):
    """Persist an audit event into the PostgreSQL database."""
    try:
        cursor.execute(
            """
            INSERT INTO audit_log
            (actor_reg_no, actor_name, actor_role, action_type, entity_type, entity_id, details, ip_address, success)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
            (
                actor_reg_no or "system",
                actor_name or "System",
                actor_role or "system",
                action_type,
                entity_type,
                str(entity_id) if entity_id else None,
                details,
                ip_address or "N/A",
                success,
            ),
        )
    except Exception as e:
        print(f"[AUDIT_LOG_ERROR] Could not write audit log: {e}")


# ─────────────────────────────────────────────────────────────────────────────
# AUTHENTICATION & ACCESS CONTROL HELPERS
# ─────────────────────────────────────────────────────────────────────────────

def get_client_ip(request: Request) -> str:
    """Extract client IP respecting X-Forwarded-For if available."""
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return request.client.host if request.client else "127.0.0.1"


def get_current_user_context(request: Request) -> Dict[str, Any]:
    """
    Authenticate caller from Bearer token across all user tables
    (users, other_staff, students).
    """
    auth_header = request.headers.get("Authorization")
    if not auth_header or not auth_header.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Authentication token required")

    token = auth_header.replace("Bearer ", "").strip()
    try:
        decoded = base64.b64decode(token).decode("utf-8")
        parts = decoded.split(":")
        if len(parts) < 2:
            raise HTTPException(status_code=401, detail="Invalid token format")
        username, password = parts[0], parts[1]
    except Exception:
        raise HTTPException(status_code=401, detail="Could not decode authentication credentials")

    # 1. Check regular users (admin, hod, staff, principal, dean, etc.)
    cursor.execute(
        "SELECT id, username, password_hash, reg_no, name, dept, role, suspended FROM users WHERE username = ? OR LOWER(reg_no) = LOWER(?)",
        (username, username),
    )
    u_row = cursor.fetchone()
    if u_row:
        import bcrypt
        pw_hash = u_row[2]
        is_valid = False
        try:
            if bcrypt.checkpw(password.encode("utf-8"), pw_hash.encode("utf-8") if isinstance(pw_hash, str) else pw_hash):
                is_valid = True
        except Exception:
            if pw_hash == password:
                is_valid = True

        if is_valid:
            if u_row[7]:
                raise HTTPException(status_code=403, detail="Account is suspended. Contact administration.")
            return {
                "id": u_row[0],
                "username": u_row[1],
                "reg_no": u_row[3],
                "name": u_row[4],
                "dept": u_row[5],
                "role": (u_row[6] or "staff").lower(),
                "table": "users",
            }

    # 2. Check other_staff
    cursor.execute(
        "SELECT id, username, password_hash, reg_no, name, dept, role, suspended FROM other_staff WHERE username = ? OR LOWER(reg_no) = LOWER(?)",
        (username, username),
    )
    os_row = cursor.fetchone()
    if os_row:
        import bcrypt
        pw_hash = os_row[2]
        is_valid = False
        try:
            if bcrypt.checkpw(password.encode("utf-8"), pw_hash.encode("utf-8") if isinstance(pw_hash, str) else pw_hash):
                is_valid = True
        except Exception:
            if pw_hash == password:
                is_valid = True

        if is_valid:
            if os_row[7]:
                raise HTTPException(status_code=403, detail="Account is suspended. Contact administration.")
            return {
                "id": os_row[0],
                "username": os_row[1],
                "reg_no": os_row[3],
                "name": os_row[4],
                "dept": os_row[5],
                "role": (os_row[6] or "other_staff").lower(),
                "table": "other_staff",
            }

    # 3. Check students
    cursor.execute(
        "SELECT id, reg_no, name, dept, batch, semester, section, password_hash FROM students WHERE LOWER(reg_no) = LOWER(?)",
        (username,),
    )
    st_row = cursor.fetchone()
    if st_row:
        import bcrypt
        pw_hash = st_row[7]
        is_valid = False
        try:
            if pw_hash and bcrypt.checkpw(password.encode("utf-8"), pw_hash.encode("utf-8") if isinstance(pw_hash, str) else pw_hash):
                is_valid = True
        except Exception:
            if pw_hash == password:
                is_valid = True

        if is_valid:
            return {
                "id": st_row[0],
                "username": st_row[1],
                "reg_no": st_row[1],
                "name": st_row[2],
                "dept": st_row[3],
                "batch": st_row[4],
                "semester": st_row[5],
                "section": st_row[6],
                "role": "student",
                "table": "students",
            }


    raise HTTPException(status_code=401, detail="Invalid username or password")


def require_admin(request: Request) -> Dict[str, Any]:
    """Require Admin or SuperAdmin role."""
    user = get_current_user_context(request)
    if user.get("role") not in ["admin", "superadmin", "principal", "director", "vice_chancellor"]:
        raise HTTPException(status_code=403, detail="Administrative privileges required")
    return user


def require_hod_or_admin(request: Request) -> Dict[str, Any]:
    """Require HOD, Dean, Principal or Admin role."""
    user = get_current_user_context(request)
    if user.get("role") not in ["admin", "superadmin", "hod", "head of department", "dean", "principal", "director"]:
        raise HTTPException(status_code=403, detail="HOD or Administrative privileges required")
    return user


# ─────────────────────────────────────────────────────────────────────────────
# 1. DASHBOARD SUMMARY & ANNOUNCEMENTS
# ─────────────────────────────────────────────────────────────────────────────

@feature_router.get("/dashboard/today-summary")
async def get_dashboard_today_summary(request: Request):
    """
    Returns today's real-time attendance counts (Present, Absent, Half Day, On Leave)
    scoped appropriately by user role (Institution-wide for Admin, Dept for HOD, Personal for Staff/Student).
    """
    user = get_current_user_context(request)
    role = user.get("role", "staff")
    dept = user.get("dept", "")
    reg_no = user.get("reg_no", "")
    today_str = datetime.now().strftime("%Y-%m-%d")

    summary: Dict[str, Any] = {
        "date": today_str,
        "role": role,
        "user_status": "Absent",
        "check_in": None,
        "check_out": None,
        "metrics": {
            "total_members": 0,
            "present_count": 0,
            "absent_count": 0,
            "leave_count": 0,
            "half_day_count": 0,
            "attendance_percentage": 0.0,
        },
    }

    # Fetch personal attendance for today
    cursor.execute(
        """
        SELECT status, in_time, out_time
        FROM daily_attendance_status
        WHERE reg_no = ? AND date = ?
    """,
        (reg_no, today_str),
    )
    my_status = cursor.fetchone()
    if my_status:
        summary["user_status"] = my_status[0] or "Present"
        summary["check_in"] = my_status[1]
        summary["check_out"] = my_status[2]


    # Department / Institution aggregation
    if role in ["admin", "superadmin", "principal", "director"]:
        cursor.execute("SELECT COUNT(*) FROM users WHERE suspended = FALSE")
        tot = cursor.fetchone()[0] or 0
        cursor.execute(
            """
            SELECT status, COUNT(*)
            FROM daily_attendance_status
            WHERE date = ?
            GROUP BY status
        """,
            (today_str,),
        )
        counts = dict(cursor.fetchall())
        p_count = counts.get("Present", 0)
        hd_count = counts.get("Half Day", 0)
        l_count = counts.get("On Leave", 0)
        a_count = max(0, tot - (p_count + hd_count + l_count))

        summary["metrics"] = {
            "total_members": tot,
            "present_count": p_count,
            "absent_count": a_count,
            "leave_count": l_count,
            "half_day_count": hd_count,
            "attendance_percentage": round((p_count + (hd_count * 0.5)) / max(tot, 1) * 100, 1),
        }
    elif role in ["hod", "head of department", "dean"]:
        cursor.execute("SELECT COUNT(*) FROM users WHERE LOWER(dept) = LOWER(?) AND suspended = FALSE", (dept,))
        tot = cursor.fetchone()[0] or 0
        cursor.execute(
            """
            SELECT d.status, COUNT(*)
            FROM daily_attendance_status d
            JOIN users u ON LOWER(d.reg_no) = LOWER(u.reg_no)
            WHERE d.date = ? AND LOWER(u.dept) = LOWER(?)
            GROUP BY d.status
        """,
            (today_str, dept),
        )
        counts = dict(cursor.fetchall())
        p_count = counts.get("Present", 0)
        hd_count = counts.get("Half Day", 0)
        l_count = counts.get("On Leave", 0)
        a_count = max(0, tot - (p_count + hd_count + l_count))

        summary["metrics"] = {
            "total_members": tot,
            "present_count": p_count,
            "absent_count": a_count,
            "leave_count": l_count,
            "half_day_count": hd_count,
            "attendance_percentage": round((p_count + (hd_count * 0.5)) / max(tot, 1) * 100, 1),
        }

    return {"success": True, "data": summary}


@feature_router.get("/dashboard/upcoming-leaves")
async def get_dashboard_upcoming_leaves(request: Request):
    """Returns approved upcoming leaves for the user and upcoming public holidays."""
    user = get_current_user_context(request)
    reg_no = user.get("reg_no", "")
    today_str = datetime.now().strftime("%Y-%m-%d")

    # Upcoming approved personal leaves
    cursor.execute(
        """
        SELECT id, leave_type, start_date, end_date, reason, status
        FROM leave_requests
        WHERE LOWER(user_reg_no) = LOWER(?) AND start_date >= ? AND LOWER(status) = 'approved'
        ORDER BY start_date ASC
        LIMIT 5
    """,
        (reg_no, today_str),
    )

    leaves = [
        {
            "id": r[0],
            "leave_type": r[1],
            "start_date": str(r[2]),
            "end_date": str(r[3]),
            "reason": r[4],
            "status": r[5],
        }
        for r in cursor.fetchall()
    ]

    # Upcoming holidays
    cursor.execute(
        """
        SELECT id, holiday_date, holiday_name, holiday_type
        FROM holiday_calendar
        WHERE holiday_date >= ?
        ORDER BY holiday_date ASC
        LIMIT 5
    """,
        (today_str,),
    )
    holidays = [
        {
            "id": r[0],
            "holiday_date": str(r[1]),
            "holiday_name": r[2],
            "holiday_type": r[3],
        }
        for r in cursor.fetchall()
    ]

    return {"success": True, "data": {"upcoming_leaves": leaves, "upcoming_holidays": holidays}}


@feature_router.get("/dashboard/announcements")
async def get_dashboard_announcements(request: Request):
    """Retrieve active announcements applicable to the caller's role/department."""
    user = get_current_user_context(request)
    role = user.get("role", "")
    dept = user.get("dept", "")
    now_str = datetime.now().isoformat()

    cursor.execute(
        """
        SELECT id, title, content, target_audience, target_dept, priority, created_by, created_at
        FROM system_announcements
        WHERE (expires_at IS NULL OR expires_at >= ?)
          AND (target_audience = 'All' OR LOWER(target_audience) = LOWER(?) OR target_audience = 'Staff')
          AND (target_dept IS NULL OR target_dept = '' OR LOWER(target_dept) = LOWER(?))
        ORDER BY created_at DESC
        LIMIT 10
    """,
        (now_str, role, dept),
    )
    announcements = [
        {
            "id": r[0],
            "title": r[1],
            "content": r[2],
            "target_audience": r[3],
            "target_dept": r[4],
            "priority": r[5],
            "created_by": r[6],
            "created_at": str(r[7]),
        }
        for r in cursor.fetchall()
    ]

    return {"success": True, "data": announcements}


@feature_router.post("/admin/announcements")
async def create_system_announcement(request: Request, body: Dict[str, Any] = Body(...)):
    """Create a new institutional announcement — Admin and HOD."""
    user = require_hod_or_admin(request)
    title = body.get("title", "").strip()
    content = body.get("content", "").strip()
    target_audience = body.get("target_audience", "All").strip()
    target_dept = body.get("target_dept", "").strip() if user.get("role") in ["admin", "superadmin"] else user.get("dept", "")
    priority = body.get("priority", "Normal").strip()
    expires_at = body.get("expires_at")

    if not title or not content:
        raise HTTPException(status_code=400, detail="Title and content are required")

    cursor.execute(
        """
        INSERT INTO system_announcements
        (title, content, target_audience, target_dept, priority, expires_at, created_by)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    """,
        (title, content, target_audience, target_dept, priority, expires_at, user.get("name", "admin")),
    )

    write_audit_log(
        action_type="CREATE_ANNOUNCEMENT",
        actor_reg_no=user.get("reg_no"),
        actor_name=user.get("name"),
        actor_role=user.get("role"),
        entity_type="announcement",
        details=f"Created announcement: {title} (Target: {target_audience} {target_dept})",
        ip_address=get_client_ip(request),
    )

    return {"success": True, "message": "Announcement published successfully"}


@feature_router.delete("/admin/announcements/{announcement_id}")
async def delete_system_announcement(announcement_id: int, request: Request):
    """Delete an announcement — Admin only."""
    user = require_admin(request)
    cursor.execute("DELETE FROM system_announcements WHERE id = ?", (announcement_id,))
    write_audit_log(
        action_type="DELETE_ANNOUNCEMENT",
        actor_reg_no=user.get("reg_no"),
        actor_name=user.get("name"),
        actor_role=user.get("role"),
        entity_type="announcement",
        entity_id=str(announcement_id),
        details=f"Deleted announcement ID {announcement_id}",
        ip_address=get_client_ip(request),
    )
    return {"success": True, "message": "Announcement deleted"}


# ─────────────────────────────────────────────────────────────────────────────
# 2. ATTENDANCE CORRECTION & REGULARISATION WORKFLOW
# ─────────────────────────────────────────────────────────────────────────────

@feature_router.get("/admin/attendance/regularisation-window")
async def get_regularisation_window(request: Request):
    """Get the active attendance regularisation dispute window (days)."""
    cursor.execute("SELECT max_correction_days, updated_at, updated_by FROM attendance_regularisation_window WHERE id = 1")
    row = cursor.fetchone()
    return {
        "success": True,
        "data": {
            "max_correction_days": row[0] if row else 7,
            "updated_at": str(row[1]) if row else None,
            "updated_by": row[2] if row else "system",
        },
    }


@feature_router.post("/admin/attendance/regularisation-window")
async def update_regularisation_window(request: Request, body: Dict[str, Any] = Body(...)):
    """Update regularisation window in days — Admin only."""
    user = require_admin(request)
    days = int(body.get("max_correction_days", 7))
    if days < 1 or days > 90:
        raise HTTPException(status_code=400, detail="Regularisation window must be between 1 and 90 days")

    cursor.execute(
        """
        UPDATE attendance_regularisation_window
        SET max_correction_days = ?, updated_at = CURRENT_TIMESTAMP, updated_by = ?
        WHERE id = 1
    """,
        (days, user.get("name", "admin")),
    )

    write_audit_log(
        action_type="UPDATE_REGULARISATION_WINDOW",
        actor_reg_no=user.get("reg_no"),
        actor_name=user.get("name"),
        actor_role=user.get("role"),
        entity_type="settings",
        details=f"Updated regularisation window to {days} days",
        ip_address=get_client_ip(request),
    )

    return {"success": True, "message": f"Regularisation window updated to {days} days", "max_correction_days": days}


@feature_router.post("/attendance/correction/request")
async def submit_attendance_correction(request: Request, body: Dict[str, Any] = Body(...)):
    """
    Staff or Student raises an attendance correction dispute.
    Validates against the regularisation window.
    """
    user = get_current_user_context(request)
    reg_no = user.get("reg_no", "")
    requested_date_str = body.get("requested_date", "").strip()
    reason = body.get("reason", "").strip()
    requested_check_in = body.get("requested_check_in", "09:00")
    requested_check_out = body.get("requested_check_out", "17:00")
    requested_status = body.get("requested_status", "Present")

    if not requested_date_str or not reason:
        raise HTTPException(status_code=400, detail="Requested date and reason are required")

    try:
        req_date = datetime.strptime(requested_date_str, "%Y-%m-%d").date()
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid date format (expected YYYY-MM-DD)")

    today = datetime.now().date()
    if req_date > today:
        raise HTTPException(status_code=400, detail="Cannot request correction for a future date")

    # Check regularisation window limit
    cursor.execute("SELECT max_correction_days FROM attendance_regularisation_window WHERE id = 1")
    w_row = cursor.fetchone()
    max_days = w_row[0] if w_row else 7
    earliest_allowed = today - timedelta(days=max_days)

    if req_date < earliest_allowed:
        raise HTTPException(
            status_code=400,
            detail=f"Dispute exceeds the {max_days}-day regularisation policy window (earliest allowed: {earliest_allowed})",
        )

    # Check for existing pending request on same date
    cursor.execute(
        "SELECT id FROM attendance_corrections WHERE reg_no = ? AND requested_date = ? AND status = 'Pending'",
        (reg_no, requested_date_str),
    )
    if cursor.fetchone():
        raise HTTPException(status_code=400, detail="A pending correction request already exists for this date")

    cursor.execute(
        """
        INSERT INTO attendance_corrections
        (reg_no, user_name, role, dept, requested_date, requested_check_in, requested_check_out, requested_status, reason, status)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'Pending')
    """,
        (
            reg_no,
            user.get("name", "Staff Member"),
            user.get("role", "staff"),
            user.get("dept", ""),
            requested_date_str,
            requested_check_in,
            requested_check_out,
            requested_status,
            reason,
        ),
    )

    # Trigger in-app notification to department HOD & Admin
    cursor.execute(
        """
        INSERT INTO notifications_all_roles
        (target_role, target_dept, title, message, type, created_by)
        VALUES ('hod', ?, ?, ?, 'attendance_correction', ?)
    """,
        (
            user.get("dept", ""),
            f"Attendance Dispute: {user.get('name')}",
            f"{user.get('name')} ({reg_no}) submitted a correction request for {requested_date_str}.",
            reg_no,
        ),
    )

    return {"success": True, "message": "Attendance correction request submitted for administrative review"}


@feature_router.get("/attendance/correction/my-requests")
async def get_my_attendance_corrections(request: Request):
    """Retrieve personal attendance correction dispute requests."""
    user = get_current_user_context(request)
    reg_no = user.get("reg_no", "")

    cursor.execute(
        """
        SELECT id, requested_date, requested_check_in, requested_check_out, requested_status,
               reason, status, reviewer_name, review_remarks, reviewed_at, created_at
        FROM attendance_corrections
        WHERE reg_no = ?
        ORDER BY created_at DESC
    """,
        (reg_no,),
    )

    rows = cursor.fetchall()
    results = [
        {
            "id": r[0],
            "requested_date": str(r[1]),
            "requested_check_in": r[2],
            "requested_check_out": r[3],
            "requested_status": r[4],
            "reason": r[5],
            "status": r[6],
            "reviewer_name": r[7],
            "review_remarks": r[8],
            "reviewed_at": str(r[9]) if r[9] else None,
            "created_at": str(r[10]),
        }
        for r in rows
    ]

    return {"success": True, "data": results}


@feature_router.get("/admin/attendance/correction/pending")
async def get_pending_attendance_corrections(request: Request):
    """Retrieve pending correction disputes — Admin & HOD."""
    user = require_hod_or_admin(request)
    role = user.get("role", "")
    dept = user.get("dept", "")

    if role in ["admin", "superadmin", "principal", "director"]:
        cursor.execute(
            """
            SELECT id, reg_no, user_name, role, dept, requested_date, requested_check_in,
                   requested_check_out, requested_status, reason, created_at
            FROM attendance_corrections
            WHERE status = 'Pending'
            ORDER BY created_at ASC
        """
        )
    else:
        cursor.execute(
            """
            SELECT id, reg_no, user_name, role, dept, requested_date, requested_check_in,
                   requested_check_out, requested_status, reason, created_at
            FROM attendance_corrections
            WHERE status = 'Pending' AND LOWER(dept) = LOWER(?)
            ORDER BY created_at ASC
        """,
            (dept,),
        )

    rows = cursor.fetchall()
    results = [
        {
            "id": r[0],
            "reg_no": r[1],
            "user_name": r[2],
            "role": r[3],
            "dept": r[4],
            "requested_date": str(r[5]),
            "requested_check_in": r[6],
            "requested_check_out": r[7],
            "requested_status": r[8],
            "reason": r[9],
            "created_at": str(r[10]),
        }
        for r in rows
    ]

    return {"success": True, "data": results}


@feature_router.get("/admin/attendance/correction/history")
async def get_attendance_corrections_history(request: Request, limit: int = 100):
    """Retrieve processed correction dispute records — Admin & HOD."""
    user = require_hod_or_admin(request)
    role = user.get("role", "")
    dept = user.get("dept", "")

    if role in ["admin", "superadmin", "principal", "director"]:
        cursor.execute(
            """
            SELECT id, reg_no, user_name, role, dept, requested_date, requested_status,
                   status, reviewer_name, review_remarks, reviewed_at, created_at
            FROM attendance_corrections
            WHERE status != 'Pending'
            ORDER BY reviewed_at DESC
            LIMIT ?
        """,
            (limit,),
        )
    else:
        cursor.execute(
            """
            SELECT id, reg_no, user_name, role, dept, requested_date, requested_status,
                   status, reviewer_name, review_remarks, reviewed_at, created_at
            FROM attendance_corrections
            WHERE status != 'Pending' AND LOWER(dept) = LOWER(?)
            ORDER BY reviewed_at DESC
            LIMIT ?
        """,
            (dept, limit),
        )

    rows = cursor.fetchall()
    results = [
        {
            "id": r[0],
            "reg_no": r[1],
            "user_name": r[2],
            "role": r[3],
            "dept": r[4],
            "requested_date": str(r[5]),
            "requested_status": r[6],
            "status": r[7],
            "reviewer_name": r[8],
            "review_remarks": r[9],
            "reviewed_at": str(r[10]) if r[10] else None,
            "created_at": str(r[11]),
        }
        for r in rows
    ]

    return {"success": True, "data": results}


@feature_router.post("/admin/attendance/correction/{correction_id}/approve")
async def approve_attendance_correction(correction_id: int, request: Request, body: Dict[str, Any] = Body(...)):
    """
    Approve an attendance correction request.
    Applies the correction to daily_attendance_status / attendance tables, logs audit event,
    and dispatches email / in-app notification.
    """
    user = require_hod_or_admin(request)
    remarks = body.get("remarks", "Approved by administrator").strip()

    cursor.execute("SELECT reg_no, user_name, dept, requested_date, requested_check_in, requested_check_out, requested_status, role FROM attendance_corrections WHERE id = ?", (correction_id,))
    req = cursor.fetchone()
    if not req:
        raise HTTPException(status_code=404, detail="Correction request not found")

    reg_no, user_name, dept, req_date_str, check_in, check_out, req_status, u_role = (
        req[0], req[1], req[2], str(req[3]), req[4], req[5], req[6] or "Present", req[7]
    )

    # 1. Update daily_attendance_status table
    cursor.execute(
        """
        INSERT INTO daily_attendance_status (reg_no, name, dept, date, status, in_time, out_time, is_manual_override, override_by, override_reason)
        VALUES (?, ?, ?, ?, ?, ?, ?, TRUE, ?, ?)
        ON CONFLICT (reg_no, date) DO UPDATE SET
            status = EXCLUDED.status,
            name = COALESCE(EXCLUDED.name, daily_attendance_status.name),
            dept = COALESCE(EXCLUDED.dept, daily_attendance_status.dept),
            in_time = EXCLUDED.in_time,
            out_time = EXCLUDED.out_time,
            is_manual_override = TRUE,
            override_by = EXCLUDED.override_by,
            override_reason = EXCLUDED.override_reason
    """,
        (reg_no, user_name or reg_no, dept or "General", req_date_str, req_status, check_in, check_out, user.get("name"), remarks),
    )



    # 2. Mark correction record as Approved
    cursor.execute(
        """
        UPDATE attendance_corrections
        SET status = 'Approved', reviewer_reg_no = ?, reviewer_name = ?, review_remarks = ?, reviewed_at = CURRENT_TIMESTAMP
        WHERE id = ?
    """,
        (user.get("reg_no"), user.get("name"), remarks, correction_id),
    )

    # 3. Create In-App Notification
    cursor.execute(
        """
        INSERT INTO notifications_all_roles (recipient_reg_no, title, message, type, created_by)
        VALUES (?, ?, ?, 'attendance_correction_approved', ?)
    """,
        (
            reg_no,
            "Attendance Correction Approved",
            f"Your attendance dispute for {req_date_str} was approved ({req_status}). Notes: {remarks}",
            user.get("name"),
        ),
    )

    # 4. Attempt Email Dispatch
    cursor.execute("SELECT username FROM users WHERE LOWER(reg_no) = LOWER(?)", (reg_no,))
    email_row = cursor.fetchone()
    if email_row and "@" in (email_row[0] or ""):
        notify_attendance_correction_outcome(
            recipient_email=email_row[0],
            staff_name=user_name,
            requested_date=req_date_str,
            requested_status=req_status,
            outcome_status="Approved",
            remarks=remarks,
        )

    # 5. Audit Log
    write_audit_log(
        action_type="APPROVE_ATTENDANCE_CORRECTION",
        actor_reg_no=user.get("reg_no"),
        actor_name=user.get("name"),
        actor_role=user.get("role"),
        entity_type="attendance_correction",
        entity_id=str(correction_id),
        details=f"Approved correction for {user_name} ({reg_no}) on {req_date_str} to {req_status}",
        ip_address=get_client_ip(request),
    )

    return {"success": True, "message": f"Attendance correction approved and applied for {req_date_str}"}


@feature_router.post("/admin/attendance/correction/{correction_id}/reject")
async def reject_attendance_correction(correction_id: int, request: Request, body: Dict[str, Any] = Body(...)):
    """Reject an attendance correction dispute with required reason."""
    user = require_hod_or_admin(request)
    remarks = body.get("remarks", "").strip()
    if not remarks:
        raise HTTPException(status_code=400, detail="Rejection reason is required")

    cursor.execute("SELECT reg_no, user_name, requested_date, requested_status FROM attendance_corrections WHERE id = ?", (correction_id,))
    req = cursor.fetchone()
    if not req:
        raise HTTPException(status_code=404, detail="Correction request not found")

    reg_no, user_name, req_date_str, req_status = req[0], req[1], str(req[2]), req[3]

    cursor.execute(
        """
        UPDATE attendance_corrections
        SET status = 'Rejected', reviewer_reg_no = ?, reviewer_name = ?, review_remarks = ?, reviewed_at = CURRENT_TIMESTAMP
        WHERE id = ?
    """,
        (user.get("reg_no"), user.get("name"), remarks, correction_id),
    )

    # In-app notification
    cursor.execute(
        """
        INSERT INTO notifications_all_roles (recipient_reg_no, title, message, type, created_by)
        VALUES (?, ?, ?, 'attendance_correction_rejected', ?)
    """,
        (
            reg_no,
            "Attendance Correction Declined",
            f"Your attendance dispute for {req_date_str} was declined. Reason: {remarks}",
            user.get("name"),
        ),
    )

    # Email
    cursor.execute("SELECT username FROM users WHERE LOWER(reg_no) = LOWER(?)", (reg_no,))
    email_row = cursor.fetchone()
    if email_row and "@" in (email_row[0] or ""):
        notify_attendance_correction_outcome(
            recipient_email=email_row[0],
            staff_name=user_name,
            requested_date=req_date_str,
            requested_status=req_status,
            outcome_status="Rejected",
            remarks=remarks,
        )

    write_audit_log(
        action_type="REJECT_ATTENDANCE_CORRECTION",
        actor_reg_no=user.get("reg_no"),
        actor_name=user.get("name"),
        actor_role=user.get("role"),
        entity_type="attendance_correction",
        entity_id=str(correction_id),
        details=f"Rejected correction for {user_name} ({reg_no}) on {req_date_str}. Reason: {remarks}",
        ip_address=get_client_ip(request),
    )

    return {"success": True, "message": "Attendance correction declined"}


# ─────────────────────────────────────────────────────────────────────────────
# 3. COMPREHENSIVE REPORTS & ANALYTICS TAB
# ─────────────────────────────────────────────────────────────────────────────

@feature_router.get("/reports/daily-register")
async def get_daily_register_report(
    request: Request,
    date_str: Optional[str] = None,
    dept: Optional[str] = None,
    export_format: Optional[str] = None,
):
    """
    Institutional Daily Attendance Register.
    Returns tabular data or triggers formatted download (excel, pdf, csv).
    """
    user = require_hod_or_admin(request)
    target_date = date_str or datetime.now().strftime("%Y-%m-%d")
    target_dept = dept or (user.get("dept") if user.get("role") in ["hod", "head of department"] else "")

    query = """
        SELECT u.reg_no, u.name, u.dept, u.role,
               COALESCE(d.status, 'Absent') AS attendance_status,
               d.in_time, d.out_time, d.is_manual_override
        FROM users u
        LEFT JOIN daily_attendance_status d ON (LOWER(u.reg_no) = LOWER(d.reg_no) AND d.date = ?)
        WHERE u.suspended = FALSE
    """

    params: List[Any] = [target_date]

    if target_dept:
        query += " AND LOWER(u.dept) = LOWER(?)"
        params.append(target_dept)

    query += " ORDER BY u.dept, u.name ASC"

    cursor.execute(query, tuple(params))
    rows = cursor.fetchall()

    headers = ["Reg No", "Staff Name", "Department", "Role", "Status", "Check In", "Check Out", "Manual Override"]
    data_rows = []
    for r in rows:
        data_rows.append([
            r[0],
            r[1],
            r[2],
            r[3],
            r[4],
            r[5] or "—",
            r[6] or "—",
            "Yes" if r[7] else "No",
        ])

    if export_format == "excel":
        excel_bytes = generate_excel(
            title=f"Daily Attendance Register — {target_date}",
            sheet_name="Daily Register",
            headers=headers,
            rows=data_rows,
            subtitle=f"Department: {target_dept or 'All Departments'}",
        )
        return Response(
            content=excel_bytes,
            media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            headers={"Content-Disposition": f"attachment; filename=daily_register_{target_date}.xlsx"},
        )
    elif export_format == "pdf":
        pdf_bytes = generate_pdf_table(
            title=f"Daily Attendance Register — {target_date}",
            headers=headers,
            rows=data_rows,
            subtitle=f"Department: {target_dept or 'All Departments'}",
            landscape_mode=True,
        )
        return Response(
            content=pdf_bytes,
            media_type="application/pdf",
            headers={"Content-Disposition": f"attachment; filename=daily_register_{target_date}.pdf"},
        )
    elif export_format == "csv":
        csv_str = generate_csv(headers, data_rows)
        return Response(
            content=csv_str,
            media_type="text/csv",
            headers={"Content-Disposition": f"attachment; filename=daily_register_{target_date}.csv"},
        )

    # Default JSON Response
    return {
        "success": True,
        "date": target_date,
        "dept": target_dept or "All",
        "total_records": len(data_rows),
        "headers": headers,
        "records": [
            {
                "reg_no": r[0],
                "name": r[1],
                "dept": r[2],
                "role": r[3],
                "status": r[4],
                "check_in": r[5],
                "check_out": r[6],
                "is_manual": r[7],
            }
            for r in data_rows
        ],
    }


@feature_router.get("/reports/monthly-summary")
async def get_monthly_attendance_summary(
    request: Request,
    year_month: Optional[str] = None,
    dept: Optional[str] = None,
    export_format: Optional[str] = None,
):
    """
    Monthly staff attendance summary: Total Days, Present, Half Day, Leaves, Absent, Percentage.
    """
    user = require_hod_or_admin(request)
    target_ym = year_month or datetime.now().strftime("%Y-%m")
    target_dept = dept or (user.get("dept") if user.get("role") in ["hod", "head of department"] else "")

    start_date = f"{target_ym}-01"
    # Calculate end of month
    y, m = int(target_ym.split("-")[0]), int(target_ym.split("-")[1])
    if m == 12:
        end_date = f"{y}-12-31"
    else:
        next_month = date(y, m + 1, 1)
        end_date = (next_month - timedelta(days=1)).strftime("%Y-%m-%d")

    query = """
        SELECT u.reg_no, u.name, u.dept,
               COUNT(CASE WHEN d.status = 'Present' THEN 1 END) as present_days,
               COUNT(CASE WHEN d.status = 'Half Day' THEN 1 END) as half_days,
               COUNT(CASE WHEN d.status = 'On Leave' THEN 1 END) as leave_days,
               COUNT(CASE WHEN d.status = 'Absent' THEN 1 END) as absent_days
        FROM users u
        LEFT JOIN daily_attendance_status d ON (LOWER(u.reg_no) = LOWER(d.reg_no) AND d.date >= ? AND d.date <= ?)
        WHERE u.suspended = FALSE
    """
    params: List[Any] = [start_date, end_date]

    if target_dept:
        query += " AND LOWER(u.dept) = LOWER(?)"
        params.append(target_dept)

    query += " GROUP BY u.reg_no, u.name, u.dept ORDER BY u.dept, u.name ASC"

    cursor.execute(query, tuple(params))
    rows = cursor.fetchall()

    headers = ["Reg No", "Staff Name", "Department", "Present Days", "Half Days", "Leave Days", "Absent Days", "Effective Attendance %"]
    data_rows = []
    dict_records = []
    for r in rows:
        p, hd, lv, ab = r[3] or 0, r[4] or 0, r[5] or 0, r[6] or 0
        total_active = p + hd + lv + ab
        eff_pct = round((p + (hd * 0.5)) / max(total_active, 1) * 100, 1) if total_active > 0 else 0.0
        data_rows.append([r[0], r[1], r[2], p, hd, lv, ab, f"{eff_pct}%"])
        dict_records.append({
            "reg_no": r[0],
            "name": r[1],
            "dept": r[2],
            "present_days": p,
            "half_days": hd,
            "leave_days": lv,
            "absent_days": ab,
            "working_days": total_active,
            "attendance_pct": eff_pct,
        })

    if export_format == "excel":
        excel_bytes = generate_excel(
            title=f"Monthly Attendance Summary — {target_ym}",
            sheet_name="Monthly Summary",
            headers=headers,
            rows=data_rows,
            subtitle=f"Department: {target_dept or 'All Departments'}",
        )
        return Response(
            content=excel_bytes,
            media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            headers={"Content-Disposition": f"attachment; filename=monthly_summary_{target_ym}.xlsx"},
        )
    elif export_format == "pdf":
        pdf_bytes = generate_pdf_table(
            title=f"Monthly Attendance Summary — {target_ym}",
            headers=headers,
            rows=data_rows,
            subtitle=f"Department: {target_dept or 'All Departments'}",
            landscape_mode=True,
        )
        return Response(
            content=pdf_bytes,
            media_type="application/pdf",
            headers={"Content-Disposition": f"attachment; filename=monthly_summary_{target_ym}.pdf"},
        )

    return {"success": True, "year_month": target_ym, "dept": target_dept or "All", "headers": headers, "records": dict_records, "raw_rows": data_rows}


@feature_router.get("/reports/department-heatmap")
async def get_department_attendance_heatmap(
    request: Request,
    from_date: Optional[str] = None,
    to_date: Optional[str] = None,
    dept: Optional[str] = None,
):
    """
    Returns a matrix of Date × Staff attendance status for graphical heatmap rendering.
    """
    user = require_hod_or_admin(request)
    today = datetime.now().date()
    start_str = from_date or (today - timedelta(days=14)).strftime("%Y-%m-%d")
    end_str = to_date or today.strftime("%Y-%m-%d")
    target_dept = dept or (user.get("dept") if user.get("role") in ["hod", "head of department"] else "")

    query = """
        SELECT d.date, u.name, u.reg_no, u.dept, d.status
        FROM daily_attendance_status d
        JOIN users u ON LOWER(d.reg_no) = LOWER(u.reg_no)
        WHERE d.date >= ? AND d.date <= ?
    """
    params: List[Any] = [start_str, end_str]
    if target_dept:
        query += " AND LOWER(u.dept) = LOWER(?)"
        params.append(target_dept)
    query += " ORDER BY d.date ASC, u.name ASC"

    cursor.execute(query, tuple(params))
    rows = cursor.fetchall()

    matrix = []
    grid: Dict[str, Dict[str, float]] = {}
    dept_totals: Dict[str, Dict[str, int]] = {}

    for r in rows:
        d_str = str(r[0])
        name = r[1]
        reg_no = r[2]
        dept_name = r[3] or "General"
        status = r[4]

        matrix.append({
            "date": d_str,
            "name": name,
            "reg_no": reg_no,
            "dept": dept_name,
            "status": status,
        })

        # Calculate daily department percentage
        day_num = d_str.split("-")[-1].lstrip("0") or "1"
        if dept_name not in dept_totals:
            dept_totals[dept_name] = {}
        if day_num not in dept_totals[dept_name]:
            dept_totals[dept_name][day_num] = {"present": 0, "total": 0}

        dept_totals[dept_name][day_num]["total"] += 1
        if status == "Present":
            dept_totals[dept_name][day_num]["present"] += 1
        elif status == "Half Day":
            dept_totals[dept_name][day_num]["present"] += 0.5

    for d_name, days in dept_totals.items():
        grid[d_name] = {}
        for d_key, counts in days.items():
            tot = counts["total"]
            pres = counts["present"]
            grid[d_name][d_key] = round((pres / max(tot, 1)) * 100, 1)

    return {
        "success": True,
        "from_date": start_str,
        "to_date": end_str,
        "dept": target_dept or "All",
        "days_in_month": 31,
        "grid": grid,
        "data": matrix,
    }


@feature_router.get("/reports/leave-utilisation")
async def get_leave_utilisation_report(request: Request, dept: Optional[str] = None, export_format: Optional[str] = None):
    """
    Leave quota utilization report: Casual Leave, Earned Leave, CCL, and Comp-Off consumption.
    """
    user = require_hod_or_admin(request)
    target_dept = dept or (user.get("dept") if user.get("role") in ["hod", "head of department"] else "")

    query = """
        SELECT u.reg_no, u.name, u.dept,
               COUNT(CASE WHEN LOWER(l.leave_type) = 'cl' AND LOWER(l.status) = 'approved' THEN 1 END) as cl_used,
               COUNT(CASE WHEN LOWER(l.leave_type) = 'el' AND LOWER(l.status) = 'approved' THEN 1 END) as el_used,
               COUNT(CASE WHEN LOWER(l.leave_type) = 'ccl' AND LOWER(l.status) = 'approved' THEN 1 END) as ccl_used
        FROM users u
        LEFT JOIN leave_requests l ON (LOWER(u.reg_no) = LOWER(l.user_reg_no))

        WHERE u.suspended = FALSE
    """
    params: List[Any] = []
    if target_dept:
        query += " AND LOWER(u.dept) = LOWER(?)"
        params.append(target_dept)
    query += " GROUP BY u.reg_no, u.name, u.dept ORDER BY u.dept, u.name ASC"

    cursor.execute(query, tuple(params))
    rows = cursor.fetchall()

    headers = ["Reg No", "Staff Name", "Department", "CL Balance", "CL Used", "EL Balance", "EL Used", "CCL Balance", "CCL Used"]
    data_rows = []
    dict_records = []
    for r in rows:
        reg_no, name, dept_val = r[0], r[1], r[2]
        cl_used, el_used, ccl_used = r[3] or 0, r[4] or 0, r[5] or 0
        cl_bal = max(0, 12 - cl_used)
        el_bal = max(0, 15 - el_used)
        ccl_bal = max(0, 5 - ccl_used)
        data_rows.append([reg_no, name, dept_val, cl_bal, cl_used, el_bal, el_used, ccl_bal, ccl_used])
        dict_records.append({
            "reg_no": reg_no,
            "name": name,
            "dept": dept_val,
            "cl_used": cl_used,
            "cl_balance": cl_bal,
            "el_used": el_used,
            "el_balance": el_bal,
            "ccl_used": ccl_used,
            "ccl_balance": ccl_bal,
        })

    if export_format == "excel":
        excel_bytes = generate_excel(
            title="Institutional Leave Utilization & Balance Report",
            sheet_name="Leave Utilization",
            headers=headers,
            rows=data_rows,
            subtitle=f"Department: {target_dept or 'All Departments'}",
        )
        return Response(
            content=excel_bytes,
            media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            headers={"Content-Disposition": "attachment; filename=leave_utilisation_report.xlsx"},
        )

    return {"success": True, "headers": headers, "records": dict_records, "raw_rows": data_rows}


@feature_router.get("/reports/absenteeism-trend")
async def get_absenteeism_trend_report(request: Request, days: int = 30):
    """Week-over-week and day-over-day institutional absenteeism percentages."""
    require_hod_or_admin(request)
    today = datetime.now().date()
    start_date = today - timedelta(days=days)

    cursor.execute(
        """
        SELECT date,
               COUNT(CASE WHEN status = 'Present' THEN 1 END) as present_count,
               COUNT(CASE WHEN status = 'Half Day' THEN 1 END) as half_day_count,
               COUNT(CASE WHEN status = 'On Leave' THEN 1 END) as leave_count,
               COUNT(CASE WHEN status = 'Absent' THEN 1 END) as absent_count,
               COUNT(*) as total_logged
        FROM daily_attendance_status
        WHERE date >= ? AND date <= ?
        GROUP BY date
        ORDER BY date ASC
    """,
        (start_date.strftime("%Y-%m-%d"), today.strftime("%Y-%m-%d")),
    )
    rows = cursor.fetchall()
    trends = []
    for r in rows:
        tot = r[5] or 1
        ab_pct = round((r[4] / tot) * 100, 1)
        trends.append({
            "date": str(r[0]),
            "present": r[1],
            "half_day": r[2],
            "leave": r[3],
            "absent": r[4],
            "absenteeism_rate": f"{ab_pct}%",
        })

    return {"success": True, "days_analyzed": days, "data": trends}


@feature_router.get("/reports/face-recognition-failures")
async def get_face_recognition_failures_report(request: Request, limit: int = 100):
    """Audit log report of face verification failures, photo spoof rejections, and lockouts."""
    require_admin(request)
    cursor.execute(
        """
        SELECT timestamp, actor_reg_no, actor_name, action_type, details, ip_address
        FROM audit_log
        WHERE success = FALSE OR action_type IN ('LOCKOUT', 'FAILED_ATTEMPT', 'FACE_VERIFY_FAIL', 'SPOOF_DETECTED')
        ORDER BY timestamp DESC
        LIMIT ?
    """,
        (limit,),
    )
    rows = cursor.fetchall()
    records = [
        {
            "timestamp": str(r[0]),
            "reg_no": r[1],
            "name": r[2],
            "event_type": r[3],
            "details": r[4],
            "ip": r[5],
        }
        for r in rows
    ]
    return {"success": True, "total_failures": len(records), "records": records}


# ─────────────────────────────────────────────────────────────────────────────
# 4. UNIFIED NOTIFICATIONS SYSTEM (ALL ROLES)
# ─────────────────────────────────────────────────────────────────────────────

@feature_router.get("/notifications")
async def get_user_notifications(request: Request, unread_only: bool = False, limit: int = 50):
    """Retrieve notifications for the authenticated user across personal, role, and dept channels."""
    user = get_current_user_context(request)
    reg_no = user.get("reg_no", "")
    role = user.get("role", "")
    dept = user.get("dept", "")

    query = """
        SELECT id, title, message, type, is_read, metadata, created_at, created_by
        FROM notifications_all_roles
        WHERE (LOWER(recipient_reg_no) = LOWER(?)
           OR (target_role IS NOT NULL AND LOWER(target_role) = LOWER(?))
           OR (target_dept IS NOT NULL AND LOWER(target_dept) = LOWER(?)))
    """
    params: List[Any] = [reg_no, role, dept]

    if unread_only:
        query += " AND is_read = FALSE"

    query += " ORDER BY created_at DESC LIMIT ?"
    params.append(limit)

    cursor.execute(query, tuple(params))
    rows = cursor.fetchall()

    cursor.execute(
        """
        SELECT COUNT(*)
        FROM notifications_all_roles
        WHERE (LOWER(recipient_reg_no) = LOWER(?)
           OR (target_role IS NOT NULL AND LOWER(target_role) = LOWER(?))
           OR (target_dept IS NOT NULL AND LOWER(target_dept) = LOWER(?)))
          AND is_read = FALSE
    """,
        (reg_no, role, dept),
    )
    unread_count = cursor.fetchone()[0] or 0

    items = [
        {
            "id": r[0],
            "title": r[1],
            "message": r[2],
            "type": r[3],
            "is_read": bool(r[4]),
            "metadata": json.loads(r[5]) if r[5] else None,
            "created_at": str(r[6]),
            "created_by": r[7],
        }
        for r in rows
    ]

    return {"success": True, "unread_count": unread_count, "notifications": items}


@feature_router.post("/notifications/mark-read/{notification_id}")
async def mark_notification_as_read(notification_id: int, request: Request):
    """Mark a notification as read."""
    get_current_user_context(request)
    cursor.execute("UPDATE notifications_all_roles SET is_read = TRUE WHERE id = ?", (notification_id,))
    return {"success": True, "message": "Notification marked as read"}


@feature_router.post("/notifications/mark-all-read")
async def mark_all_notifications_as_read(request: Request):
    """Mark all notifications as read for current user."""
    user = get_current_user_context(request)
    reg_no = user.get("reg_no", "")
    cursor.execute(
        "UPDATE notifications_all_roles SET is_read = TRUE WHERE LOWER(recipient_reg_no) = LOWER(?)",
        (reg_no,),
    )
    return {"success": True, "message": "All notifications marked as read"}


@feature_router.get("/notifications/preferences")
async def get_notification_preferences(request: Request):
    """Get personal notification preferences."""
    user = get_current_user_context(request)
    reg_no = user.get("reg_no", "")

    cursor.execute(
        "SELECT email_enabled, push_enabled, leave_alerts, attendance_alerts, announcement_alerts FROM notification_preferences WHERE LOWER(reg_no) = LOWER(?)",
        (reg_no,),
    )
    row = cursor.fetchone()
    if not row:
        return {
            "success": True,
            "preferences": {
                "email_enabled": True,
                "push_enabled": True,
                "leave_alerts": True,
                "attendance_alerts": True,
                "announcement_alerts": True,
            },
        }

    return {
        "success": True,
        "preferences": {
            "email_enabled": bool(row[0]),
            "push_enabled": bool(row[1]),
            "leave_alerts": bool(row[2]),
            "attendance_alerts": bool(row[3]),
            "announcement_alerts": bool(row[4]),
        },
    }


@feature_router.post("/notifications/preferences")
async def update_notification_preferences(request: Request, body: Dict[str, Any] = Body(...)):
    """Save personal notification preferences."""
    user = get_current_user_context(request)
    reg_no = user.get("reg_no", "")

    email_en = bool(body.get("email_enabled", True))
    push_en = bool(body.get("push_enabled", True))
    leave_al = bool(body.get("leave_alerts", True))
    att_al = bool(body.get("attendance_alerts", True))
    ann_al = bool(body.get("announcement_alerts", True))

    cursor.execute(
        """
        INSERT INTO notification_preferences (reg_no, email_enabled, push_enabled, leave_alerts, attendance_alerts, announcement_alerts, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
        ON CONFLICT (reg_no) DO UPDATE SET
            email_enabled = EXCLUDED.email_enabled,
            push_enabled = EXCLUDED.push_enabled,
            leave_alerts = EXCLUDED.leave_alerts,
            attendance_alerts = EXCLUDED.attendance_alerts,
            announcement_alerts = EXCLUDED.announcement_alerts,
            updated_at = CURRENT_TIMESTAMP
    """,
        (reg_no, email_en, push_en, leave_al, att_al, ann_al),
    )

    return {"success": True, "message": "Notification preferences updated successfully"}


@feature_router.post("/admin/notifications/broadcast")
async def broadcast_notification(request: Request, body: Dict[str, Any] = Body(...)):
    """Send an institutional broadcast notification — Admin & HOD."""
    user = require_hod_or_admin(request)
    title = body.get("title", "").strip()
    message = body.get("message", "").strip()
    target_role = body.get("target_role")
    target_dept = body.get("target_dept") or (user.get("dept") if user.get("role") in ["hod", "head of department"] else None)
    notif_type = body.get("type", "announcement")

    if not title or not message:
        raise HTTPException(status_code=400, detail="Title and message are required")

    cursor.execute(
        """
        INSERT INTO notifications_all_roles (target_role, target_dept, title, message, type, created_by)
        VALUES (?, ?, ?, ?, ?, ?)
    """,
        (target_role, target_dept, title, message, notif_type, user.get("name", "admin")),
    )

    write_audit_log(
        action_type="BROADCAST_NOTIFICATION",
        actor_reg_no=user.get("reg_no"),
        actor_name=user.get("name"),
        actor_role=user.get("role"),
        entity_type="notification",
        details=f"Broadcasted: {title} to Role: {target_role or 'All'} Dept: {target_dept or 'All'}",
        ip_address=get_client_ip(request),
    )

    return {"success": True, "message": "Notification broadcasted successfully"}


# ─────────────────────────────────────────────────────────────────────────────
# 5. ACTIVE SESSIONS & SECURITY MANAGEMENT
# ─────────────────────────────────────────────────────────────────────────────

@feature_router.get("/admin/security/active-sessions")
async def get_active_sessions(request: Request, limit: int = 100):
    """Retrieve all active user login sessions across the platform — Admin only."""
    require_admin(request)
    cursor.execute(
        """
        SELECT session_id, reg_no, username, role, ip_address, user_agent, created_at, last_activity, is_active
        FROM active_sessions
        WHERE is_active = TRUE
        ORDER BY last_activity DESC
        LIMIT ?
    """,
        (limit,),
    )
    rows = cursor.fetchall()
    sessions = [
        {
            "session_id": r[0],
            "reg_no": r[1],
            "username": r[2],
            "role": r[3],
            "ip_address": r[4],
            "user_agent": r[5],
            "created_at": str(r[6]),
            "last_activity": str(r[7]),
            "is_active": bool(r[8]),
        }
        for r in rows
    ]
    return {"success": True, "total_active_sessions": len(sessions), "sessions": sessions}


@feature_router.delete("/admin/security/sessions/{session_id}")
async def revoke_active_session(session_id: str, request: Request):
    """Revoke a single active login session — Admin only."""
    user = require_admin(request)
    cursor.execute("UPDATE active_sessions SET is_active = FALSE WHERE session_id = ?", (session_id,))
    write_audit_log(
        action_type="REVOKE_SESSION",
        actor_reg_no=user.get("reg_no"),
        actor_name=user.get("name"),
        actor_role=user.get("role"),
        entity_type="session",
        entity_id=session_id,
        details=f"Revoked session {session_id}",
        ip_address=get_client_ip(request),
    )
    return {"success": True, "message": "Session revoked successfully"}


@feature_router.post("/admin/security/sessions/terminate-user/{reg_no}")
async def terminate_all_user_sessions(reg_no: str, request: Request):
    """Terminate all active sessions for a user — Admin only."""
    user = require_admin(request)
    cursor.execute("UPDATE active_sessions SET is_active = FALSE WHERE LOWER(reg_no) = LOWER(?)", (reg_no,))
    write_audit_log(
        action_type="TERMINATE_USER_SESSIONS",
        actor_reg_no=user.get("reg_no"),
        actor_name=user.get("name"),
        actor_role=user.get("role"),
        entity_type="user",
        entity_id=reg_no,
        details=f"Terminated all active sessions for user {reg_no}",
        ip_address=get_client_ip(request),
    )
    return {"success": True, "message": f"All sessions terminated for user {reg_no}"}


@feature_router.get("/admin/security/login-attempts")
async def get_login_attempts_log(request: Request, limit: int = 100):
    """Retrieve security login attempts log — Admin only."""
    require_admin(request)
    cursor.execute(
        """
        SELECT id, username, ip_address, success, reason, attempted_at
        FROM login_attempts_log
        ORDER BY attempted_at DESC
        LIMIT ?
    """,
        (limit,),
    )
    rows = cursor.fetchall()
    attempts = [
        {
            "id": r[0],
            "username": r[1],
            "ip_address": r[2],
            "success": bool(r[3]),
            "reason": r[4],
            "attempted_at": str(r[5]),
        }
        for r in rows
    ]
    return {"success": True, "total_attempts": len(attempts), "attempts": attempts}


@feature_router.post("/admin/security/2fa/setup")
async def setup_totp_2fa(request: Request):
    """Generate a TOTP secret and QR code URI for 2FA enrollment."""
    user = get_current_user_context(request)
    reg_no = user.get("reg_no", "")

    if not PYOTP_AVAILABLE:
        raise HTTPException(status_code=500, detail="PyOTP library is not installed on the server")

    secret = pyotp.random_base32()
    totp = pyotp.TOTP(secret)
    provisioning_uri = totp.provisioning_uri(name=user.get("username", reg_no), issuer_name="Attenda")

    cursor.execute(
        """
        INSERT INTO totp_secrets (reg_no, secret_key, is_enabled, backup_codes)
        VALUES (?, ?, FALSE, '')
        ON CONFLICT (reg_no) DO UPDATE SET secret_key = EXCLUDED.secret_key, is_enabled = FALSE
    """,
        (reg_no, secret),
    )

    return {
        "success": True,
        "secret": secret,
        "otpauth_url": provisioning_uri,
        "message": "Scan the OTP Auth URL into Google Authenticator or Microsoft Authenticator, then verify with /admin/security/2fa/verify",
    }


@feature_router.post("/admin/security/2fa/verify")
async def verify_and_enable_2fa(request: Request, body: Dict[str, Any] = Body(...)):
    """Verify a 6-digit TOTP code and activate 2FA for the account."""
    user = get_current_user_context(request)
    reg_no = user.get("reg_no", "")
    code = str(body.get("code", "")).strip()

    if not code:
        raise HTTPException(status_code=400, detail="6-digit authentication code required")

    cursor.execute("SELECT secret_key FROM totp_secrets WHERE LOWER(reg_no) = LOWER(?)", (reg_no,))
    row = cursor.fetchone()
    if not row or not row[0]:
        raise HTTPException(status_code=400, detail="No 2FA setup in progress. Initiate setup first.")

    secret = row[0]
    totp = pyotp.TOTP(secret)
    if not totp.verify(code):
        raise HTTPException(status_code=400, detail="Invalid verification code")

    cursor.execute("UPDATE totp_secrets SET is_enabled = TRUE, enabled_at = CURRENT_TIMESTAMP WHERE LOWER(reg_no) = LOWER(?)", (reg_no,))
    write_audit_log(
        action_type="ENABLE_2FA",
        actor_reg_no=reg_no,
        actor_name=user.get("name"),
        actor_role=user.get("role"),
        entity_type="security",
        details=f"Enabled Two-Factor Authentication for {reg_no}",
        ip_address=get_client_ip(request),
    )

    return {"success": True, "message": "Two-Factor Authentication successfully enabled"}


# ─────────────────────────────────────────────────────────────────────────────
# 6. EXTENDED SETTINGS (SMTP, MAINTENANCE, SESSION TTL, BACKUP)
# ─────────────────────────────────────────────────────────────────────────────

@feature_router.get("/admin/settings/smtp")
async def get_smtp_settings(request: Request):
    """Retrieve SMTP settings with password masked — Admin only."""
    require_admin(request)
    config = get_smtp_configuration()
    if config.get("password"):
        config["password"] = "••••••••••••"
    return {"success": True, "smtp_config": config}


@feature_router.post("/admin/settings/smtp")
async def update_smtp_settings(request: Request, body: Dict[str, Any] = Body(...)):
    """Update SMTP settings and optionally perform a live test dispatch — Admin only."""
    user = require_admin(request)
    host = str(body.get("host", "")).strip()
    port = int(body.get("port", 587))
    username = str(body.get("username", "")).strip()
    password = str(body.get("password", "")).strip()
    sender_email = str(body.get("sender_email", "")).strip()
    sender_name = str(body.get("sender_name", "Attenda Notification")).strip()
    use_tls = bool(body.get("use_tls", True))
    is_active = bool(body.get("is_active", True))
    test_recipient = str(body.get("test_recipient", "")).strip()

    # If password is mask placeholder, retain existing
    if password == "••••••••••••":
        cursor.execute("SELECT password FROM smtp_config WHERE id = 1")
        old_pw = cursor.fetchone()
        password = old_pw[0] if old_pw else ""

    cursor.execute(
        """
        UPDATE smtp_config
        SET host = ?, port = ?, username = ?, password = ?, sender_email = ?,
            sender_name = ?, use_tls = ?, is_active = ?, updated_at = CURRENT_TIMESTAMP, updated_by = ?
        WHERE id = 1
    """,
        (host, port, username, password, sender_email, sender_name, use_tls, is_active, user.get("name")),
    )

    test_result = None
    if test_recipient and is_active:
        test_result = send_email(
            to_email=test_recipient,
            subject="Attenda SMTP Configuration Test",
            body_html="<p>This is a verified test email from the <strong>Attenda Institutional System</strong>. Your SMTP gateway is operating properly.</p>",
            preheader="SMTP verification test",
        )

    write_audit_log(
        action_type="UPDATE_SMTP_SETTINGS",
        actor_reg_no=user.get("reg_no"),
        actor_name=user.get("name"),
        actor_role=user.get("role"),
        entity_type="settings",
        details=f"Updated SMTP Host: {host}:{port} (Active: {is_active})",
        ip_address=get_client_ip(request),
    )

    return {
        "success": True,
        "message": "SMTP settings saved successfully",
        "test_email_dispatched": test_result if test_recipient else "No test recipient specified",
    }


@feature_router.get("/admin/settings/maintenance")
async def get_maintenance_mode_status():
    """Check whether maintenance mode is active."""
    cursor.execute("SELECT value FROM system_config WHERE key = 'maintenance_mode'")
    row = cursor.fetchone()
    cursor.execute("SELECT value FROM system_config WHERE key = 'maintenance_message'")
    msg_row = cursor.fetchone()

    is_active = (row[0].lower() == "true") if row else False
    msg = msg_row[0] if msg_row else "System is currently undergoing routine maintenance. Please check back shortly."

    return {"success": True, "maintenance_mode": is_active, "message": msg}


@feature_router.post("/admin/settings/maintenance")
async def toggle_maintenance_mode(request: Request, body: Dict[str, Any] = Body(...)):
    """Toggle maintenance mode — Admin only."""
    user = require_admin(request)
    enabled = bool(body.get("enabled", False))
    msg = str(body.get("message", "System is undergoing maintenance")).strip()

    # Save to system_config
    cursor.execute(
        """
        INSERT INTO system_config (key, value, updated_at)
        VALUES ('maintenance_mode', ?, CURRENT_TIMESTAMP)
        ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = CURRENT_TIMESTAMP
    """,
        (str(enabled).lower(),),
    )
    cursor.execute(
        """
        INSERT INTO system_config (key, value, updated_at)
        VALUES ('maintenance_message', ?, CURRENT_TIMESTAMP)
        ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = CURRENT_TIMESTAMP
    """,
        (msg,),
    )

    write_audit_log(
        action_type="TOGGLE_MAINTENANCE_MODE",
        actor_reg_no=user.get("reg_no"),
        actor_name=user.get("name"),
        actor_role=user.get("role"),
        entity_type="settings",
        details=f"Maintenance mode {'ENABLED' if enabled else 'DISABLED'}: {msg}",
        ip_address=get_client_ip(request),
    )

    return {"success": True, "maintenance_mode": enabled, "message": msg}


@feature_router.get("/admin/config/antispoofing-status")
async def get_antispoofing_config():
    """Retrieve the real-time anti-spoofing toggle state."""
    cursor.execute("SELECT value FROM system_config WHERE key = 'antispoofing_enabled'")
    row = cursor.fetchone()
    is_enabled = (row[0].lower() == "true") if row else False
    return {"success": True, "antispoofing_enabled": is_enabled}


@feature_router.post("/admin/config/antispoofing-status")
async def update_antispoofing_config(request: Request, body: Dict[str, Any] = Body(...)):
    """Toggle anti-spoofing facial texture & liveness verification — Admin only."""
    user = require_admin(request)
    enabled = bool(body.get("antispoofing_enabled", True))

    cursor.execute(
        """
        INSERT INTO system_config (key, value, updated_at)
        VALUES ('antispoofing_enabled', ?, CURRENT_TIMESTAMP)
        ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = CURRENT_TIMESTAMP
    """,
        (str(enabled).lower(),),
    )

    write_audit_log(
        action_type="UPDATE_ANTISPOOFING_CONFIG",
        actor_reg_no=user.get("reg_no"),
        actor_name=user.get("name"),
        actor_role=user.get("role"),
        entity_type="settings",
        details=f"Anti-spoofing enforcement {'ENABLED' if enabled else 'DISABLED'}",
        ip_address=get_client_ip(request),
    )

    return {"success": True, "antispoofing_enabled": enabled, "message": f"Anti-spoofing verification {'enabled' if enabled else 'disabled'}"}


@feature_router.get("/admin/settings/export")
async def export_all_system_settings(request: Request):
    """Export complete institutional settings backup as a JSON file — Admin only."""
    require_admin(request)
    cursor.execute("SELECT key, value FROM system_config")
    configs = dict(cursor.fetchall())
    cursor.execute("SELECT max_correction_days FROM attendance_regularisation_window WHERE id = 1")
    reg_w = cursor.fetchone()
    cursor.execute("SELECT max_el_carry_forward, max_cl_carry_forward, encashment_allowed FROM leave_carry_forward_rules WHERE id = 1")
    cf = cursor.fetchone()

    backup = {
        "export_timestamp": datetime.now().isoformat(),
        "system_config": configs,
        "regularisation_window_days": reg_w[0] if reg_w else 7,
        "leave_rules": {
            "max_el_carry_forward": cf[0] if cf else 15,
            "max_cl_carry_forward": cf[1] if cf else 0,
            "encashment_allowed": cf[2] if cf else False,
        },
    }

    backup_json = json.dumps(backup, indent=2)
    return Response(
        content=backup_json,
        media_type="application/json",
        headers={"Content-Disposition": f"attachment; filename=attenda_settings_backup_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"},
    )


# ─────────────────────────────────────────────────────────────────────────────
# 7. HOLIDAY CALENDAR MANAGEMENT
# ─────────────────────────────────────────────────────────────────────────────

@feature_router.get("/admin/holidays")
async def get_all_holidays(academic_year: Optional[str] = None):
    """Retrieve all declared institutional holidays."""
    query = "SELECT id, holiday_date, holiday_name, holiday_type, is_optional, academic_year FROM holiday_calendar"
    params = []
    if academic_year:
        query += " WHERE academic_year = ?"
        params.append(academic_year)
    query += " ORDER BY holiday_date ASC"

    cursor.execute(query, tuple(params))
    rows = cursor.fetchall()
    holidays = [
        {
            "id": r[0],
            "holiday_date": str(r[1]),
            "holiday_name": r[2],
            "holiday_type": r[3],
            "is_optional": bool(r[4]),
            "academic_year": r[5],
        }
        for r in rows
    ]
    return {"success": True, "total_holidays": len(holidays), "holidays": holidays}


@feature_router.post("/admin/holidays")
async def add_holiday(request: Request, body: Dict[str, Any] = Body(...)):
    """Add a declared institutional holiday — Admin only."""
    user = require_admin(request)
    holiday_date = str(body.get("holiday_date", "")).strip()
    holiday_name = str(body.get("holiday_name", "")).strip()
    holiday_type = str(body.get("holiday_type", "General")).strip()
    is_optional = bool(body.get("is_optional", False))
    academic_year = str(body.get("academic_year", "")).strip()

    if not holiday_date or not holiday_name:
        raise HTTPException(status_code=400, detail="Holiday date and name are required")

    cursor.execute(
        """
        INSERT INTO holiday_calendar (holiday_date, holiday_name, holiday_type, is_optional, academic_year, created_by)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT (holiday_date) DO UPDATE SET
            holiday_name = EXCLUDED.holiday_name,
            holiday_type = EXCLUDED.holiday_type,
            is_optional = EXCLUDED.is_optional,
            academic_year = EXCLUDED.academic_year
    """,
        (holiday_date, holiday_name, holiday_type, is_optional, academic_year, user.get("name")),
    )

    write_audit_log(
        action_type="ADD_HOLIDAY",
        actor_reg_no=user.get("reg_no"),
        actor_name=user.get("name"),
        actor_role=user.get("role"),
        entity_type="holiday",
        details=f"Added holiday: {holiday_name} on {holiday_date}",
        ip_address=get_client_ip(request),
    )

    return {"success": True, "message": f"Holiday '{holiday_name}' registered for {holiday_date}"}


@feature_router.delete("/admin/holidays/{holiday_id}")
async def delete_holiday(holiday_id: int, request: Request):
    """Delete a holiday — Admin only."""
    user = require_admin(request)
    cursor.execute("DELETE FROM holiday_calendar WHERE id = ?", (holiday_id,))
    write_audit_log(
        action_type="DELETE_HOLIDAY",
        actor_reg_no=user.get("reg_no"),
        actor_name=user.get("name"),
        actor_role=user.get("role"),
        entity_type="holiday",
        entity_id=str(holiday_id),
        details=f"Deleted holiday ID {holiday_id}",
        ip_address=get_client_ip(request),
    )
    return {"success": True, "message": "Holiday deleted successfully"}


# ─────────────────────────────────────────────────────────────────────────────
# 8. LEAVE BALANCES, CALENDAR & COMP-OFF ENGINE
# ─────────────────────────────────────────────────────────────────────────────

@feature_router.get("/leave/balance/{reg_no}")
async def get_detailed_leave_balance(reg_no: str, request: Request):
    """Retrieve detailed breakdown of CL, EL, CCL, and Comp-Off balances."""
    user = get_current_user_context(request)
    # Check authorization (own record, or HOD/Admin)
    if user.get("role") not in ["admin", "superadmin", "hod", "head of department"] and user.get("reg_no").lower() != reg_no.lower():
        raise HTTPException(status_code=403, detail="Unauthorized to view other staff balances")

    # Calculate used leaves
    cursor.execute(
        """
        SELECT leave_type, COUNT(*)
        FROM leave_requests
        WHERE LOWER(user_reg_no) = LOWER(?) AND LOWER(status) = 'approved'
        GROUP BY leave_type
    """,
        (reg_no,),
    )

    used_map = dict(cursor.fetchall())
    cl_used = used_map.get("cl", used_map.get("CL", 0))
    el_used = used_map.get("el", used_map.get("EL", 0))
    ccl_used = used_map.get("ccl", used_map.get("CCL", 0))

    cl_bal = max(0, 12 - cl_used)
    el_bal = max(0, 15 - el_used)
    ccl_bal = max(0, 5 - ccl_used)

    # Comp-Off Available
    cursor.execute(
        """
        SELECT COALESCE(SUM(days_earned), 0)
        FROM comp_off_accrual
        WHERE LOWER(reg_no) = LOWER(?) AND status = 'Available' AND (expiry_date IS NULL OR expiry_date >= CURRENT_DATE)
    """,
        (reg_no,),
    )
    co_bal = cursor.fetchone()[0] or 0.0

    return {
        "success": True,
        "reg_no": reg_no,
        "balances": {
            "casual_leave": cl_bal,
            "earned_leave": el_bal,
            "compensatory_casual_leave": ccl_bal,
            "comp_off_days": float(co_bal),
        },
    }



@feature_router.get("/leave/calendar")
async def get_team_leave_calendar(request: Request, month: Optional[str] = None, dept: Optional[str] = None):
    """Institutional leave calendar showing all approved staff leaves across a month."""
    user = require_hod_or_admin(request)
    target_month = month or datetime.now().strftime("%Y-%m")
    target_dept = dept or (user.get("dept") if user.get("role") in ["hod", "head of department"] else "")

    start_date = f"{target_month}-01"
    y, m = int(target_month.split("-")[0]), int(target_month.split("-")[1])
    next_month = date(y + 1, 1, 1) if m == 12 else date(y, m + 1, 1)
    end_date = (next_month - timedelta(days=1)).strftime("%Y-%m-%d")

    query = """
        SELECT l.id, l.user_reg_no, u.name, u.dept, l.leave_type, l.start_date, l.end_date, l.reason, l.status
        FROM leave_requests l
        JOIN users u ON LOWER(l.user_reg_no) = LOWER(u.reg_no)
        WHERE LOWER(l.status) = 'approved'
          AND ((l.start_date >= ? AND l.start_date <= ?) OR (l.end_date >= ? AND l.end_date <= ?))
    """

    params: List[Any] = [start_date, end_date, start_date, end_date]
    if target_dept:
        query += " AND LOWER(u.dept) = LOWER(?)"
        params.append(target_dept)
    query += " ORDER BY l.start_date ASC"

    cursor.execute(query, tuple(params))
    rows = cursor.fetchall()
    calendar_entries = [
        {
            "id": r[0],
            "reg_no": r[1],
            "name": r[2],
            "dept": r[3],
            "leave_type": r[4],
            "start_date": str(r[5]),
            "end_date": str(r[6]),
            "reason": r[7],
        }
        for r in rows
    ]

    return {"success": True, "month": target_month, "dept": target_dept or "All", "entries": calendar_entries}


@feature_router.post("/admin/leave/comp-off/accrue")
async def accrue_comp_off(request: Request, body: Dict[str, Any] = Body(...)):
    """Grant compensatory off for weekend or holiday duty — Admin & HOD."""
    user = require_hod_or_admin(request)
    reg_no = str(body.get("reg_no", "")).strip()
    duty_date = str(body.get("duty_date", "")).strip()
    duty_type = str(body.get("duty_type", "Holiday Duty")).strip()
    days_earned = float(body.get("days_earned", 1.0))
    reason = str(body.get("reason", "")).strip()
    validity_days = int(body.get("validity_days", 90))

    if not reg_no or not duty_date:
        raise HTTPException(status_code=400, detail="Staff Reg No and Duty Date required")

    cursor.execute("SELECT name FROM users WHERE LOWER(reg_no) = LOWER(?)", (reg_no,))
    u_row = cursor.fetchone()
    staff_name = u_row[0] if u_row else reg_no

    exp_date = (datetime.strptime(duty_date, "%Y-%m-%d").date() + timedelta(days=validity_days)).strftime("%Y-%m-%d")

    cursor.execute(
        """
        INSERT INTO comp_off_accrual (reg_no, staff_name, duty_date, duty_type, days_earned, reason, expiry_date, status, approved_by)
        VALUES (?, ?, ?, ?, ?, ?, ?, 'Available', ?)
    """,
        (reg_no, staff_name, duty_date, duty_type, days_earned, reason, exp_date, user.get("name")),
    )

    write_audit_log(
        action_type="ACCRUE_COMP_OFF",
        actor_reg_no=user.get("reg_no"),
        actor_name=user.get("name"),
        actor_role=user.get("role"),
        entity_type="comp_off",
        details=f"Accrued {days_earned} comp-off days for {staff_name} ({reg_no}) for {duty_type} on {duty_date}",
        ip_address=get_client_ip(request),
    )

    return {"success": True, "message": f"Comp-off credit of {days_earned} day(s) accrued for {staff_name}"}


# ─────────────────────────────────────────────────────────────────────────────
# 9. USER ACTIVITY TIMELINE & MANAGEMENT EXTENSIONS
# ─────────────────────────────────────────────────────────────────────────────

@feature_router.get("/admin/users/{user_id}/activity")
async def get_user_activity_timeline(user_id: int, request: Request):
    """Retrieve full activity history for a staff member (attendance, leaves, audits) — Admin only."""
    require_admin(request)
    cursor.execute("SELECT reg_no, name, dept, role FROM users WHERE id = ?", (user_id,))
    user_row = cursor.fetchone()
    if not user_row:
        raise HTTPException(status_code=404, detail="User not found")

    reg_no = user_row[0]

    # Attendance logs
    cursor.execute(
        """
        SELECT date, status, in_time, out_time
        FROM daily_attendance_status
        WHERE LOWER(reg_no) = LOWER(?)
        ORDER BY date DESC
        LIMIT 20
    """,
        (reg_no,),
    )
    att_rows = [
        {"date": str(r[0]), "status": r[1], "check_in": r[2], "check_out": r[3]}
        for r in cursor.fetchall()
    ]

    # Leave history
    cursor.execute(
        """
        SELECT leave_type, start_date, end_date, status, reason
        FROM leave_requests
        WHERE LOWER(user_reg_no) = LOWER(?)
        ORDER BY start_date DESC
        LIMIT 10
    """,
        (reg_no,),
    )

    leave_rows = [
        {"type": r[0], "start_date": str(r[1]), "end_date": str(r[2]), "status": r[3], "reason": r[4]}
        for r in cursor.fetchall()
    ]

    # Audit events
    cursor.execute(
        """
        SELECT timestamp, action_type, details, ip_address
        FROM audit_log
        WHERE LOWER(actor_reg_no) = LOWER(?)
        ORDER BY timestamp DESC
        LIMIT 15
    """,
        (reg_no,),
    )
    audit_rows = [
        {"timestamp": str(r[0]), "action": r[1], "details": r[2], "ip": r[3]}
        for r in cursor.fetchall()
    ]

    return {
        "success": True,
        "user": {"reg_no": user_row[0], "name": user_row[1], "dept": user_row[2], "role": user_row[3]},
        "recent_attendance": att_rows,
        "recent_leaves": leave_rows,
        "recent_audit_events": audit_rows,
    }


@feature_router.post("/admin/users/bulk-deactivate")
async def bulk_deactivate_users(request: Request, body: Dict[str, Any] = Body(...)):
    """Bulk deactivate multiple staff accounts without deleting historical data — Admin only."""
    admin_user = require_admin(request)
    reg_nos = body.get("reg_nos", [])
    if not isinstance(reg_nos, list) or not reg_nos:
        raise HTTPException(status_code=400, detail="List of registration numbers is required")

    deactivated = 0
    for r in reg_nos:
        cursor.execute("UPDATE users SET suspended = TRUE WHERE LOWER(reg_no) = LOWER(?)", (r,))
        cursor.execute("UPDATE active_sessions SET is_active = FALSE WHERE LOWER(reg_no) = LOWER(?)", (r,))
        deactivated += 1

    write_audit_log(
        action_type="BULK_DEACTIVATE_USERS",
        actor_reg_no=admin_user.get("reg_no"),
        actor_name=admin_user.get("name"),
        actor_role=admin_user.get("role"),
        entity_type="users",
        details=f"Bulk deactivated {deactivated} user accounts: {', '.join(reg_nos[:10])}",
        ip_address=get_client_ip(request),
    )

    return {"success": True, "deactivated_count": deactivated, "message": f"{deactivated} user account(s) deactivated"}


@feature_router.post("/admin/users/{user_id}/transfer")
async def transfer_user_department(user_id: int, request: Request, body: Dict[str, Any] = Body(...)):
    """Transfer staff to a new department or role with an audit trail — Admin only."""
    admin_user = require_admin(request)
    new_dept = str(body.get("new_dept", "")).strip()
    new_role = str(body.get("new_role", "")).strip()
    remarks = str(body.get("remarks", "")).strip()

    if not new_dept:
        raise HTTPException(status_code=400, detail="New department is required")

    cursor.execute("SELECT reg_no, name, dept, role FROM users WHERE id = ?", (user_id,))
    u_row = cursor.fetchone()
    if not u_row:
        raise HTTPException(status_code=404, detail="User not found")

    reg_no, name, old_dept, old_role = u_row[0], u_row[1], u_row[2], u_row[3]
    eff_role = new_role if new_role else old_role

    cursor.execute("UPDATE users SET dept = ?, role = ? WHERE id = ?", (new_dept, eff_role, user_id))

    cursor.execute(
        """
        INSERT INTO user_transfers_log (user_id, reg_no, old_dept, new_dept, old_role, new_role, remarks, transferred_by)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    """,
        (user_id, reg_no, old_dept, new_dept, old_role, eff_role, remarks, admin_user.get("name")),
    )

    write_audit_log(
        action_type="TRANSFER_USER",
        actor_reg_no=admin_user.get("reg_no"),
        actor_name=admin_user.get("name"),
        actor_role=admin_user.get("role"),
        entity_type="user",
        entity_id=str(user_id),
        details=f"Transferred {name} ({reg_no}) from {old_dept} ({old_role}) to {new_dept} ({eff_role})",
        ip_address=get_client_ip(request),
    )

    return {"success": True, "message": f"{name} successfully transferred to {new_dept}"}


@feature_router.post("/admin/users/{user_id}/force-password-reset")
async def force_password_reset(user_id: int, request: Request):
    """Set flag mandating password reset on the user's next login — Admin only."""
    admin_user = require_admin(request)
    cursor.execute("SELECT reg_no, name FROM users WHERE id = ?", (user_id,))
    u_row = cursor.fetchone()
    if not u_row:
        raise HTTPException(status_code=404, detail="User not found")

    reg_no, name = u_row[0], u_row[1]
    cursor.execute(
        """
        INSERT INTO user_security_flags (reg_no, force_password_reset, updated_at)
        VALUES (?, TRUE, CURRENT_TIMESTAMP)
        ON CONFLICT (reg_no) DO UPDATE SET force_password_reset = TRUE, updated_at = CURRENT_TIMESTAMP
    """,
        (reg_no,),
    )

    write_audit_log(
        action_type="FORCE_PASSWORD_RESET",
        actor_reg_no=admin_user.get("reg_no"),
        actor_name=admin_user.get("name"),
        actor_role=admin_user.get("role"),
        entity_type="user",
        entity_id=str(user_id),
        details=f"Mandated password change on next login for {name} ({reg_no})",
        ip_address=get_client_ip(request),
    )

    return {"success": True, "message": f"Forced password reset configured for {name}"}


# ─────────────────────────────────────────────────────────────────────────────
# 10. TIMETABLE SUBSTITUTE FACULTY ASSIGNMENT & WEEKLY MATRIX
# ─────────────────────────────────────────────────────────────────────────────

@feature_router.get("/timetable/substitute-assignments")
async def get_substitute_assignments(request: Request, assignment_date: Optional[str] = None, dept: Optional[str] = None):
    """Retrieve substitute teacher assignments for a given date / department."""
    user = require_hod_or_admin(request)
    target_date = assignment_date or datetime.now().strftime("%Y-%m-%d")
    target_dept = dept or (user.get("dept") if user.get("role") in ["hod", "head of department"] else "")

    query = """
        SELECT id, original_staff_reg_no, original_staff_name, substitute_staff_reg_no,
               substitute_staff_name, dept, batch, semester, section, subject_code,
               subject_name, assignment_date, period_number, status, reason, assigned_by
        FROM substitute_assignments
        WHERE assignment_date = ?
    """
    params: List[Any] = [target_date]
    if target_dept:
        query += " AND LOWER(dept) = LOWER(?)"
        params.append(target_dept)

    cursor.execute(query, tuple(params))
    rows = cursor.fetchall()
    assignments = [
        {
            "id": r[0],
            "original_staff_reg_no": r[1],
            "original_staff_name": r[2],
            "substitute_staff_reg_no": r[3],
            "substitute_staff_name": r[4],
            "dept": r[5],
            "batch": r[6],
            "semester": r[7],
            "section": r[8],
            "subject_code": r[9],
            "subject_name": r[10],
            "assignment_date": str(r[11]),
            "period_number": r[12],
            "status": r[13],
            "reason": r[14],
            "assigned_by": r[15],
        }
        for r in rows
    ]
    return {"success": True, "date": target_date, "assignments": assignments}


@feature_router.post("/timetable/substitute-assignments")
async def assign_substitute_faculty(request: Request, body: Dict[str, Any] = Body(...)):
    """Assign substitute teacher for an absent faculty's class period — HOD and Admin."""
    user = require_hod_or_admin(request)
    orig_reg = str(body.get("original_staff_reg_no", "")).strip()
    sub_reg = str(body.get("substitute_staff_reg_no", "")).strip()
    assignment_date = str(body.get("assignment_date", "")).strip()
    period_number = int(body.get("period_number", 1))
    dept = str(body.get("dept", user.get("dept", ""))).strip()
    batch = str(body.get("batch", "")).strip()
    semester = int(body.get("semester", 1))
    section = str(body.get("section", "A")).strip()
    subject_code = str(body.get("subject_code", "")).strip()
    subject_name = str(body.get("subject_name", "")).strip()
    reason = str(body.get("reason", "Faculty on approved leave")).strip()

    if not orig_reg or not sub_reg or not assignment_date:
        raise HTTPException(status_code=400, detail="Original staff, substitute staff, and assignment date are required")

    cursor.execute("SELECT name FROM users WHERE LOWER(reg_no) = LOWER(?)", (orig_reg,))
    o_row = cursor.fetchone()
    orig_name = o_row[0] if o_row else orig_reg

    cursor.execute("SELECT name FROM users WHERE LOWER(reg_no) = LOWER(?)", (sub_reg,))
    s_row = cursor.fetchone()
    sub_name = s_row[0] if s_row else sub_reg

    cursor.execute(
        """
        INSERT INTO substitute_assignments
        (original_staff_reg_no, original_staff_name, substitute_staff_reg_no, substitute_staff_name,
         dept, batch, semester, section, subject_code, subject_name, assignment_date, period_number, reason, assigned_by)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """,
        (
            orig_reg,
            orig_name,
            sub_reg,
            sub_name,
            dept,
            batch,
            semester,
            section,
            subject_code,
            subject_name,
            assignment_date,
            period_number,
            reason,
            user.get("name"),
        ),
    )

    # Notify substitute faculty
    cursor.execute(
        """
        INSERT INTO notifications_all_roles (recipient_reg_no, title, message, type, created_by)
        VALUES (?, ?, ?, 'substitute_duty', ?)
    """,
        (
            sub_reg,
            "Substitute Duty Assigned",
            f"You have been assigned as substitute faculty for {orig_name} on {assignment_date} (Period {period_number}, {dept} Sec {section}).",
            user.get("name"),
        ),
    )

    write_audit_log(
        action_type="ASSIGN_SUBSTITUTE_FACULTY",
        actor_reg_no=user.get("reg_no"),
        actor_name=user.get("name"),
        actor_role=user.get("role"),
        entity_type="timetable",
        details=f"Assigned {sub_name} as substitute for {orig_name} on {assignment_date} Period {period_number}",
        ip_address=get_client_ip(request),
    )

    return {"success": True, "message": f"{sub_name} successfully assigned as substitute for Period {period_number}"}


@feature_router.delete("/timetable/substitute-assignments/{assignment_id}")
async def remove_substitute_assignment(assignment_id: int, request: Request):
    """Remove a substitute assignment — HOD and Admin."""
    user = require_hod_or_admin(request)
    cursor.execute("DELETE FROM substitute_assignments WHERE id = ?", (assignment_id,))
    return {"success": True, "message": "Substitute assignment cancelled"}


@feature_router.get("/timetable/weekly/{dept}/{batch}/{semester}/{section}")
async def get_weekly_timetable_matrix(dept: str, batch: str, semester: int, section: str, request: Request):
    """Retrieve full weekly structured timetable grid for class/section."""
    get_current_user_context(request)
    cursor.execute(
        """
        SELECT day_of_week, period_number, subject_code, subject_name, staff_reg_no, room_or_lab, is_lab_block, lab_batch
        FROM class_timetable
        WHERE LOWER(dept) = LOWER(?) AND batch = ? AND semester = ? AND LOWER(section) = LOWER(?)
        ORDER BY day_of_week, period_number ASC
    """,
        (dept, batch, semester, section),
    )
    rows = cursor.fetchall()
    days_order = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    grid: Dict[str, List[Any]] = {d: [] for d in days_order}

    for r in rows:
        d = r[0]
        if d in grid:
            grid[d].append({
                "period_number": r[1],
                "subject_code": r[2],
                "subject_name": r[3],
                "staff_reg_no": r[4],
                "room": r[5],
                "is_lab": bool(r[6]),
                "lab_batch": r[7],
            })

    return {"success": True, "dept": dept, "batch": batch, "semester": semester, "section": section, "timetable": grid}


# ─────────────────────────────────────────────────────────────────────────────
# 11. STUDENT PORTAL ATTENDANCE WARNING & GRIEVANCE FEEDBACK
# ─────────────────────────────────────────────────────────────────────────────

@feature_router.get("/student/attendance/percentage-warning")
async def get_student_attendance_warning(request: Request):
    """
    Computes attendance percentage for the logged in student against institutional 75% requirement.
    Calculates exact number of consecutive classes required to restore eligibility if < 75%.
    """
    user = get_current_user_context(request)
    reg_no = user.get("reg_no", "")

    cursor.execute(
        """
        SELECT COUNT(CASE WHEN status IN ('Present', 'Half Day') THEN 1 END) as attended,
               COUNT(*) as total_days
        FROM daily_attendance_status
        WHERE LOWER(reg_no) = LOWER(?)
    """,
        (reg_no,),
    )
    row = cursor.fetchone()
    attended = row[0] or 0
    total = row[1] or 0

    percentage = round((attended / max(total, 1)) * 100, 1) if total > 0 else 100.0
    is_at_risk = percentage < 75.0

    # Number of consecutive classes needed to reach 75%: (attended + x) / (total + x) >= 0.75 => x >= (0.75 * total - attended) / 0.25
    classes_needed = 0
    if is_at_risk:
        classes_needed = max(0, int((0.75 * total - attended) / 0.25) + 1)

    return {
        "success": True,
        "reg_no": reg_no,
        "attended_classes": attended,
        "total_conducted": total,
        "attendance_percentage": f"{percentage}%",
        "is_at_risk": is_at_risk,
        "threshold": "75.0%",
        "consecutive_classes_needed_for_75_pct": classes_needed,
        "alert_message": f"Your attendance is {percentage}%. You need to attend {classes_needed} more consecutive classes to reach the mandatory 75% threshold." if is_at_risk else "Your attendance is satisfactory.",
    }


@feature_router.get("/student/attendance/subject-wise")
async def get_student_subject_wise_attendance(request: Request):
    """Retrieve detailed subject-by-subject attendance percentage breakdown for a student."""
    user = get_current_user_context(request)
    reg_no = user.get("reg_no", "")
    dept = user.get("dept", "")
    batch = user.get("batch", "")
    sem = user.get("semester", 1)
    sec = user.get("section", "A")

    # Fetch allocated subjects for student's class
    cursor.execute(
        """
        SELECT subject_code, subject_name
        FROM subject_faculty_allocations
        WHERE LOWER(dept) = LOWER(?) AND batch = ? AND semester = ? AND LOWER(section) = LOWER(?)
    """,
        (dept, batch, sem, sec),
    )
    subjects = cursor.fetchall()
    if not subjects:
        # Fallback to department subjects
        cursor.execute("SELECT subject_code, subject_name FROM department_subjects WHERE LOWER(dept) = LOWER(?) AND semester = ?", (dept, sem))
        subjects = cursor.fetchall()

    results = []
    for sub in subjects:
        s_code, s_name = sub[0], sub[1]
        # In this architecture, student attendance is tracked via daily/period logs
        cursor.execute(
            """
            SELECT COUNT(CASE WHEN status = 'Present' THEN 1 END), COUNT(*)
            FROM student_attendance
            WHERE LOWER(student_reg_no) = LOWER(?) AND LOWER(subject_code) = LOWER(?)
        """,
            (reg_no, s_code),
        )
        s_row = cursor.fetchone()
        att = s_row[0] if s_row else 0
        tot = s_row[1] if s_row else 0

        # If zero period rows yet, mock aggregate based on overall daily status
        if tot == 0:
            cursor.execute("SELECT COUNT(CASE WHEN status IN ('Present','Half Day') THEN 1 END), COUNT(*) FROM daily_attendance_status WHERE LOWER(reg_no) = LOWER(?)", (reg_no,))
            d_row = cursor.fetchone()
            att = d_row[0] or 0
            tot = d_row[1] or 0

        pct = round((att / max(tot, 1)) * 100, 1) if tot > 0 else 100.0
        results.append({
            "subject_code": s_code,
            "subject_name": s_name,
            "attended": att,
            "total_conducted": tot,
            "percentage": f"{pct}%",
            "is_eligible": pct >= 75.0,
        })

    return {"success": True, "reg_no": reg_no, "subject_attendance": results}


@feature_router.post("/student/feedback")
async def submit_student_feedback(request: Request, body: Dict[str, Any] = Body(...)):
    """Submit a confidential grievance or academic feedback."""
    user = get_current_user_context(request)
    reg_no = user.get("reg_no", "")
    category = str(body.get("category", "General")).strip()
    subject = str(body.get("subject", "")).strip()
    description = str(body.get("description", "")).strip()

    if not subject or not description:
        raise HTTPException(status_code=400, detail="Subject and description are required")

    cursor.execute(
        """
        INSERT INTO student_feedback_grievances (student_reg_no, student_name, dept, category, subject, description, status)
        VALUES (?, ?, ?, ?, ?, ?, 'Open')
    """,
        (reg_no, user.get("name", "Student"), user.get("dept", ""), category, subject, description),
    )

    return {"success": True, "message": "Feedback submitted successfully. Your submission will be reviewed by administration."}


@feature_router.get("/student/feedback/my-list")
async def get_student_feedback_list(request: Request):
    """Retrieve feedback history for the authenticated student."""
    user = get_current_user_context(request)
    reg_no = user.get("reg_no", "")

    cursor.execute(
        """
        SELECT id, category, subject, description, status, admin_remarks, resolved_at, created_at
        FROM student_feedback_grievances
        WHERE LOWER(student_reg_no) = LOWER(?)
        ORDER BY created_at DESC
    """,
        (reg_no,),
    )
    rows = cursor.fetchall()
    items = [
        {
            "id": r[0],
            "category": r[1],
            "subject": r[2],
            "description": r[3],
            "status": r[4],
            "admin_remarks": r[5],
            "resolved_at": str(r[6]) if r[6] else None,
            "created_at": str(r[7]),
        }
        for r in rows
    ]
    return {"success": True, "feedback_history": items}


@feature_router.get("/admin/student-feedback")
async def get_admin_student_feedback(request: Request, status: Optional[str] = None):
    """Admin and HOD feedback review inbox."""
    user = require_hod_or_admin(request)
    dept = user.get("dept", "") if user.get("role") in ["hod", "head of department"] else None

    query = "SELECT id, student_reg_no, student_name, dept, category, subject, description, status, admin_remarks, created_at FROM student_feedback_grievances WHERE 1=1"
    params = []
    if status:
        query += " AND status = ?"
        params.append(status)
    if dept:
        query += " AND LOWER(dept) = LOWER(?)"
        params.append(dept)
    query += " ORDER BY created_at DESC"

    cursor.execute(query, tuple(params))
    rows = cursor.fetchall()
    items = [
        {
            "id": r[0],
            "student_reg_no": r[1],
            "student_name": r[2],
            "dept": r[3],
            "category": r[4],
            "subject": r[5],
            "description": r[6],
            "status": r[7],
            "admin_remarks": r[8],
            "created_at": str(r[9]),
        }
        for r in rows
    ]
    return {"success": True, "total_feedback": len(items), "feedback": items}


@feature_router.post("/admin/student-feedback/{feedback_id}/resolve")
async def resolve_student_feedback(feedback_id: int, request: Request, body: Dict[str, Any] = Body(...)):
    """Resolve student grievance with administrative remarks — Admin and HOD."""
    user = require_hod_or_admin(request)
    remarks = str(body.get("remarks", "Reviewed and resolved")).strip()

    cursor.execute(
        """
        UPDATE student_feedback_grievances
        SET status = 'Resolved', admin_remarks = ?, resolved_at = CURRENT_TIMESTAMP
        WHERE id = ?
    """,
        (remarks, feedback_id),
    )

    write_audit_log(
        action_type="RESOLVE_STUDENT_FEEDBACK",
        actor_reg_no=user.get("reg_no"),
        actor_name=user.get("name"),
        actor_role=user.get("role"),
        entity_type="student_feedback",
        entity_id=str(feedback_id),
        details=f"Resolved feedback ID {feedback_id}: {remarks}",
        ip_address=get_client_ip(request),
    )

    return {"success": True, "message": "Grievance marked as resolved"}
