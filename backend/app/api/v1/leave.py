"""
Staff Leave & OD — API Routes
================================
All endpoints for the alternate-assignment leave workflow.

Roles covered: staff | hod | other_staff | admin

Endpoint map
────────────
POST   /staff/leave/request                      → submit leave + nominate alternate
GET    /staff/leave/requests                      → my submitted requests
GET    /staff/leave/request/{id}                  → request detail + timetable slots
DELETE /staff/leave/request/{id}                  → cancel (AWAITING_ALTERNATE only)
GET    /staff/leave/eligible-alternates           → picker list (cross-dept)
PUT    /staff/leave/request/{id}/re-nominate      → re-nominate after decline/expire
GET    /staff/leave/alternate/pending             → pending nominations where I am alternate
GET    /staff/leave/alternate/all                 → all nominations where I am alternate
GET    /staff/leave/alternate/conflicts/{id}      → show my conflicts for a leave period
POST   /staff/leave/alternate/{id}/respond        → accept or decline nomination
GET    /hod/staff-leave/requests                  → dept requests for HOD review
POST   /hod/staff-leave/request/{id}/action       → HOD approve or reject
GET    /admin/staff-leave/requests                → all requests, filterable + paginated
POST   /admin/staff-leave/request/{id}/action     → Admin final approve or reject
GET    /admin/staff-leave/timetable/{id}          → view timetable handover slots
GET    /admin/staff-leave/audit/{id}              → full audit trail for a request
"""

from __future__ import annotations

import os
import sys
from typing import Optional

from fastapi import APIRouter, HTTPException, Request

# ── ensure backend/ is on sys.path so service imports work ───────────────────
_backend_dir = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
)
if _backend_dir not in sys.path:
    sys.path.insert(0, _backend_dir)

from app.services import staff_leave_service as svc

router = APIRouter()

# ─────────────────────────────────────────────────────────────────────────────
# AUTH HELPERS  (reuse the same pattern as main.py — import at call time)
# ─────────────────────────────────────────────────────────────────────────────

def _verify_staff(request: Request) -> dict:
    """Accept staff, hod, or other_staff tokens."""
    import main as _m
    user = _m.verify_user_token(request)
    role = str(user.get("role", "")).lower()
    if role not in ("staff", "hod", "other staff", "other_staff",
                    "principal", "office_staff", "system_admin"):
        raise HTTPException(status_code=403, detail="Staff access required.")
    return user


def _verify_hod(request: Request) -> dict:
    import main as _m
    return _m.verify_hod_token(request)


def _verify_admin(request: Request) -> dict:
    import main as _m
    return _m.verify_admin_token(request)


# ─────────────────────────────────────────────────────────────────────────────
# STAFF — SUBMIT & MANAGE OWN REQUESTS
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/staff/leave/check-classes")
async def check_staff_scheduled_classes(
    request: Request,
    start_date: str,
    end_date: str,
    is_half_day: bool = False,
    which_half: Optional[str] = None,
):
    """
    Check if the authenticated staff member has scheduled classes
    in class_timetable for the given date range / half-day.
    """
    user = _verify_staff(request)
    staff_id = user.get("reg_no") or user.get("username") or ""
    try:
        result = svc.check_staff_classes(
            staff_reg_no=staff_id,
            start_date_str=start_date,
            end_date_str=end_date,
            is_half_day=is_half_day,
            which_half=which_half,
        )
        return result
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to check classes: {e}")


@router.post("/staff/leave/request")
async def submit_staff_leave_request(request: Request):
    """
    Submit a new leave or OD request.
    If classes exist on the requested dates, alternate staff is required.
    If no classes exist, alternate nomination is optional/bypassed.
    """
    user = _verify_staff(request)
    try:
        data = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid JSON body.")

    required = ["leave_type", "start_date", "end_date", "reason"]
    missing = [f for f in required if not data.get(f)]
    if missing:
        raise HTTPException(
            status_code=400,
            detail=f"Missing required fields: {', '.join(missing)}",
        )

    is_half_day = bool(data.get("is_half_day", False))
    which_half = (data.get("which_half") or "").strip().upper()
    if is_half_day and which_half not in ("FN", "AN"):
        raise HTTPException(
            status_code=400,
            detail="which_half must be 'FN' or 'AN' when is_half_day is true.",
        )
    if is_half_day and data["start_date"] != data["end_date"]:
        raise HTTPException(
            status_code=400,
            detail="Half-day leave can only span a single day (start_date must equal end_date).",
        )

    alt_reg = data.get("alternate_reg_no")
    if alt_reg and alt_reg.strip() == user["reg_no"]:
        raise HTTPException(status_code=400, detail="You cannot nominate yourself as alternate.")

    try:
        result = svc.create_staff_leave_request(
            requester=user,
            leave_type=data["leave_type"].lower().strip(),
            start_date=data["start_date"],
            end_date=data["end_date"],
            reason=data["reason"].strip(),
            alternate_reg_no=data.get("alternate_reg_no"),
            alternate_name=data.get("alternate_name"),
            alternate_dept=data.get("alternate_dept"),
            alternate_role=data.get("alternate_role"),
            is_half_day=is_half_day,
            which_half=which_half if is_half_day else None,
            document_url=data.get("document_url"),
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except Exception as exc:
        print(f"[leave.py] create_staff_leave_request error: {exc}")
        raise HTTPException(status_code=500, detail="Failed to submit leave request.")

    return {"success": True, "message": "Leave request submitted. Alternate has 24 hours to confirm.", "request": result}


@router.get("/staff/leave/requests")
async def get_my_staff_leave_requests(request: Request):
    """Return all leave requests submitted by the authenticated user."""
    user = _verify_staff(request)
    try:
        requests = svc.get_requests_for_requester(user["reg_no"])
        return {"success": True, "requests": requests, "total": len(requests)}
    except Exception as exc:
        print(f"[leave.py] get_my_staff_leave_requests error: {exc}")
        raise HTTPException(status_code=500, detail="Failed to fetch leave requests.")


@router.get("/staff/leave/request/{request_id}")
async def get_staff_leave_request_detail(request: Request, request_id: int):
    """
    Full detail for a single leave request.
    Accessible by: the requester, the alternate, HOD of the dept, or admin.
    Includes timetable assignment slots and audit log.
    """
    user = _verify_staff(request)
    try:
        req = svc.get_request_by_id(request_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="Leave request not found.")

    role = str(user.get("role", "")).lower()
    is_requester = req["requester_reg_no"] == user["reg_no"]
    is_alternate = req["alternate_reg_no"] == user["reg_no"]
    is_hod_of_dept = (role == "hod" and req["dept"] == user["dept"])
    is_admin = role in ("admin", "system_admin")

    if not (is_requester or is_alternate or is_hod_of_dept or is_admin):
        raise HTTPException(status_code=403, detail="Access denied.")

    timetable = svc.get_timetable_assignments(request_id)
    audit = svc.get_audit_log(request_id)

    return {"success": True, "request": req, "timetable_slots": timetable, "audit_log": audit}


@router.delete("/staff/leave/request/{request_id}")
async def cancel_staff_leave_request(request: Request, request_id: int):
    """Cancel a leave request. Only possible when status is AWAITING_ALTERNATE."""
    user = _verify_staff(request)
    try:
        req = svc.get_request_by_id(request_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="Leave request not found.")

    if req["requester_reg_no"] != user["reg_no"]:
        raise HTTPException(status_code=403, detail="Only the requester can cancel this request.")

    if req["workflow_status"] not in ("AWAITING_ALTERNATE",):
        raise HTTPException(
            status_code=400,
            detail=f"Cannot cancel a request in '{req['workflow_status']}' state.",
        )

    import pg_adapter
    cursor = pg_adapter.cursor
    cursor.execute(
        "UPDATE staff_leave_requests SET workflow_status = 'CANCELLED', updated_at = CURRENT_TIMESTAMP WHERE id = %s",
        (request_id,),
    )
    from app.services.staff_leave_service import _audit
    _audit(request_id, "CANCELLED", user["reg_no"], user["name"], user["role"],
           req["workflow_status"], "CANCELLED", "Cancelled by requester")
    try:
        cursor.connection.commit()
    except Exception:
        pass

    return {"success": True, "message": "Leave request cancelled."}


@router.get("/staff/leave/eligible-alternates")
async def get_eligible_alternates(request: Request):
    """
    Return all staff/HOD/other_staff who can be nominated as alternate.
    Cross-department. The current user is excluded.
    """
    user = _verify_staff(request)
    try:
        alternates = svc.get_eligible_alternates(user["reg_no"])
        return {"success": True, "alternates": alternates, "total": len(alternates)}
    except Exception as exc:
        print(f"[leave.py] get_eligible_alternates error: {exc}")
        raise HTTPException(status_code=500, detail="Failed to fetch eligible alternates.")


@router.put("/staff/leave/request/{request_id}/re-nominate")
async def re_nominate_alternate(request: Request, request_id: int):
    """
    Re-nominate a new alternate after the previous declined or their deadline expired.
    Requester only. Strict mode: required to proceed.

    Body (JSON):
        alternate_reg_no : str
        alternate_name   : str
        alternate_dept   : str
        alternate_role   : str
    """
    user = _verify_staff(request)
    try:
        data = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid JSON body.")

    required = ["alternate_reg_no", "alternate_name", "alternate_dept", "alternate_role"]
    missing = [f for f in required if not data.get(f)]
    if missing:
        raise HTTPException(status_code=400, detail=f"Missing fields: {', '.join(missing)}")

    if data["alternate_reg_no"] == user["reg_no"]:
        raise HTTPException(status_code=400, detail="You cannot nominate yourself as alternate.")

    try:
        result = svc.re_nominate_alternate(
            request_id=request_id,
            requester_reg_no=user["reg_no"],
            new_alternate_reg_no=data["alternate_reg_no"],
            new_alternate_name=data["alternate_name"],
            new_alternate_dept=data["alternate_dept"],
            new_alternate_role=data["alternate_role"],
        )
    except PermissionError as exc:
        raise HTTPException(status_code=403, detail=str(exc))
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except Exception as exc:
        print(f"[leave.py] re_nominate_alternate error: {exc}")
        raise HTTPException(status_code=500, detail="Failed to re-nominate alternate.")

    return {"success": True, "message": "New alternate nominated. They have 24 hours to respond.", "request": result}


# ─────────────────────────────────────────────────────────────────────────────
# ALTERNATE STAFF — VIEW & RESPOND TO NOMINATIONS
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/staff/leave/alternate/pending")
async def get_my_pending_alternate_nominations(request: Request):
    """
    Return all leave requests where the current user is the nominated alternate
    and has not yet responded (status = PENDING).
    """
    user = _verify_staff(request)
    try:
        pending = svc.get_pending_alternate_requests(user["reg_no"])
        return {"success": True, "pending_nominations": pending, "total": len(pending)}
    except Exception as exc:
        print(f"[leave.py] get_my_pending_alternate_nominations error: {exc}")
        raise HTTPException(status_code=500, detail="Failed to fetch pending nominations.")


@router.get("/staff/leave/alternate/all")
async def get_all_my_alternate_nominations(request: Request):
    """Return all leave requests (any status) where the current user is the alternate."""
    user = _verify_staff(request)
    try:
        all_nominations = svc.get_all_alternate_requests_for_me(user["reg_no"])
        return {"success": True, "nominations": all_nominations, "total": len(all_nominations)}
    except Exception as exc:
        print(f"[leave.py] get_all_my_alternate_nominations error: {exc}")
        raise HTTPException(status_code=500, detail="Failed to fetch nominations.")


@router.get("/staff/leave/alternate/conflicts/{request_id}")
async def get_alternate_conflicts_for_request(request: Request, request_id: int):
    """
    Show which of the alternate's own timetable slots clash with the leave period.
    Called by the alternate before they accept, so they can make an informed decision.
    Warn + allow: conflicts are informational only.
    """
    user = _verify_staff(request)
    try:
        req = svc.get_request_by_id(request_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="Leave request not found.")

    if req["alternate_reg_no"] != user["reg_no"]:
        raise HTTPException(status_code=403, detail="You are not the nominated alternate for this request.")

    from datetime import date as _date
    start = _date.fromisoformat(req["start_date"])
    end = _date.fromisoformat(req["end_date"])

    # Slots the requester holds (what alternate will need to cover)
    requester_slots = svc.get_timetable_for_staff_and_dates(req["requester_reg_no"], start, end)
    # Conflicts with alternate's own schedule
    conflicts = svc.check_alternate_conflicts(user["reg_no"], requester_slots)

    return {
        "success": True,
        "slots_to_cover": len(requester_slots),
        "conflict_count": len(conflicts),
        "conflicts": conflicts,
        "requester_slots": requester_slots,
    }


@router.post("/staff/leave/alternate/{request_id}/respond")
async def alternate_respond_to_nomination(request: Request, request_id: int):
    """
    Accept or decline an alternate nomination.

    Body (JSON):
        accepted : bool
        remarks  : str (optional — required if declining; explain why)
    """
    user = _verify_staff(request)
    try:
        data = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid JSON body.")

    accepted = data.get("accepted")
    if accepted is None:
        raise HTTPException(status_code=400, detail="'accepted' field (true/false) is required.")

    accepted = bool(accepted)
    remarks = (data.get("remarks") or "").strip() or None

    if not accepted and not remarks:
        raise HTTPException(
            status_code=400,
            detail="A reason (remarks) is required when declining a nomination.",
        )

    try:
        result = svc.alternate_respond(
            request_id=request_id,
            alternate_reg_no=user["reg_no"],
            accepted=accepted,
            remarks=remarks,
        )
    except PermissionError as exc:
        raise HTTPException(status_code=403, detail=str(exc))
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except Exception as exc:
        print(f"[leave.py] alternate_respond error: {exc}")
        raise HTTPException(status_code=500, detail="Failed to record your response.")

    msg = (
        "You have accepted the coverage request. Admin and HOD have been notified."
        if accepted
        else "You have declined. The requester has been notified and must nominate a new alternate."
    )
    return {"success": True, "message": msg, "request": result}


# ─────────────────────────────────────────────────────────────────────────────
# HOD — DEPARTMENT-LEVEL REVIEW
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/hod/staff-leave/requests")
async def hod_get_staff_leave_requests(
    request: Request,
    workflow_status: Optional[str] = None,
):
    """
    HOD: view leave requests from their department.
    Filter by workflow_status (e.g. AWAITING_HOD_ADMIN) or leave blank for all.
    """
    hod = _verify_hod(request)
    try:
        requests = svc.get_requests_for_hod(hod["dept"], workflow_status)
        return {"success": True, "requests": requests, "total": len(requests)}
    except Exception as exc:
        print(f"[leave.py] hod_get_staff_leave_requests error: {exc}")
        raise HTTPException(status_code=500, detail="Failed to fetch leave requests.")


@router.post("/hod/staff-leave/request/{request_id}/action")
async def hod_action_on_leave_request(request: Request, request_id: int):
    """
    HOD approves or rejects a leave request.

    Body (JSON):
        approved : bool
        remarks  : str (optional — required if rejecting)
    """
    hod = _verify_hod(request)
    try:
        data = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid JSON body.")

    approved = data.get("approved")
    if approved is None:
        raise HTTPException(status_code=400, detail="'approved' field is required.")

    approved = bool(approved)
    remarks = (data.get("remarks") or "").strip() or None

    if not approved and not remarks:
        raise HTTPException(
            status_code=400,
            detail="Remarks are required when rejecting a leave request.",
        )

    # Ensure HOD is acting on a request from their own department
    try:
        req = svc.get_request_by_id(request_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="Leave request not found.")

    if req["dept"] != hod["dept"]:
        raise HTTPException(
            status_code=403,
            detail="You can only act on leave requests from your department.",
        )

    try:
        result = svc.hod_action(
            request_id=request_id,
            hod=hod,
            approved=approved,
            remarks=remarks,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except Exception as exc:
        print(f"[leave.py] hod_action error: {exc}")
        raise HTTPException(status_code=500, detail="Failed to process HOD action.")

    msg = "Leave request approved by HOD. Admin has been notified." if approved else "Leave request rejected by HOD."
    return {"success": True, "message": msg, "request": result}


@router.get("/hod/staff-leave/request/{request_id}")
async def hod_get_leave_request_detail(request: Request, request_id: int):
    """HOD: full detail of a leave request in their department."""
    hod = _verify_hod(request)
    try:
        req = svc.get_request_by_id(request_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="Leave request not found.")

    if req["dept"] != hod["dept"]:
        raise HTTPException(status_code=403, detail="Access denied.")

    timetable = svc.get_timetable_assignments(request_id)
    audit = svc.get_audit_log(request_id)
    return {"success": True, "request": req, "timetable_slots": timetable, "audit_log": audit}


# ─────────────────────────────────────────────────────────────────────────────
# ADMIN — FULL VISIBILITY + FINAL APPROVAL
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/admin/staff-leave/requests")
async def admin_get_all_staff_leave_requests(
    request: Request,
    workflow_status: Optional[str] = None,
    dept: Optional[str] = None,
    leave_type: Optional[str] = None,
    page: int = 1,
    limit: int = 50,
):
    """
    Admin: paginated, filterable list of all staff leave requests.
    Query params: workflow_status, dept, leave_type, page, limit.
    """
    _verify_admin(request)
    try:
        result = svc.get_all_requests_admin(
            workflow_status=workflow_status,
            dept=dept,
            leave_type=leave_type,
            page=max(1, page),
            limit=min(max(1, limit), 200),
        )
        return {"success": True, **result}
    except Exception as exc:
        print(f"[leave.py] admin_get_all_staff_leave_requests error: {exc}")
        raise HTTPException(status_code=500, detail="Failed to fetch leave requests.")


@router.post("/admin/staff-leave/request/{request_id}/action")
async def admin_action_on_leave_request(request: Request, request_id: int):
    """
    Admin gives final approval or rejection.

    Body (JSON):
        approved : bool
        remarks  : str (optional)
    """
    admin = _verify_admin(request)
    try:
        data = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid JSON body.")

    approved = data.get("approved")
    if approved is None:
        raise HTTPException(status_code=400, detail="'approved' field is required.")

    approved = bool(approved)
    remarks = (data.get("remarks") or "").strip() or None

    if not approved and not remarks:
        raise HTTPException(
            status_code=400,
            detail="Remarks are required when rejecting a leave request.",
        )

    admin_name = admin.get("name") or admin.get("username", "Admin")

    try:
        result = svc.admin_action(
            request_id=request_id,
            admin_name=admin_name,
            approved=approved,
            remarks=remarks,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except Exception as exc:
        print(f"[leave.py] admin_action error: {exc}")
        raise HTTPException(status_code=500, detail="Failed to process admin action.")

    msg = "Leave approved. Attendance records updated." if approved else "Leave rejected."
    return {"success": True, "message": msg, "request": result}


@router.get("/admin/staff-leave/request/{request_id}")
async def admin_get_leave_request_detail(request: Request, request_id: int):
    """Admin: full detail — request + timetable slots + audit log."""
    _verify_admin(request)
    try:
        req = svc.get_request_by_id(request_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="Leave request not found.")

    timetable = svc.get_timetable_assignments(request_id)
    audit = svc.get_audit_log(request_id)
    return {"success": True, "request": req, "timetable_slots": timetable, "audit_log": audit}


@router.get("/admin/staff-leave/timetable/{request_id}")
async def admin_get_timetable_assignments(request: Request, request_id: int):
    """Admin/HOD: view only the timetable handover slots for a request."""
    _verify_admin(request)
    try:
        slots = svc.get_timetable_assignments(request_id)
        return {"success": True, "timetable_slots": slots, "total": len(slots)}
    except Exception as exc:
        print(f"[leave.py] admin_get_timetable_assignments error: {exc}")
        raise HTTPException(status_code=500, detail="Failed to fetch timetable assignments.")


@router.get("/admin/staff-leave/audit/{request_id}")
async def admin_get_audit_log(request: Request, request_id: int):
    """Admin: full lifecycle audit trail for a leave request."""
    _verify_admin(request)
    try:
        log = svc.get_audit_log(request_id)
        return {"success": True, "audit_log": log, "total": len(log)}
    except Exception as exc:
        print(f"[leave.py] admin_get_audit_log error: {exc}")
        raise HTTPException(status_code=500, detail="Failed to fetch audit log.")