"""Attendance routes."""
from fastapi import APIRouter, Depends, HTTPException, Query
from datetime import date, datetime, timedelta
from typing import Optional
from decimal import Decimal

from app.services.attendance_service import AttendanceService
from app.database.repositories.attendance_repository import AttendanceRepository
from app.database.repositories.user_repository import UserRepository
from app.database.repositories.face_repository import FaceRepository
from app.database.repositories.geo_repository import GeoRepository
from app.api.schemas.attendance import (
    AttendanceMarkRequest, 
    AttendanceMarkResponse, 
    AttendanceRecord,
    DailyStatusResponse,
    AttendanceValueSummary,
    HalfDayReport
)
from app.database.connection import db_pool

router = APIRouter()


# Dependency injection
async def get_attendance_service() -> AttendanceService:
    """Get attendance service instance."""
    attendance_repo = AttendanceRepository(db_pool.pool)
    user_repo = UserRepository(db_pool.pool)
    face_repo = FaceRepository()
    geo_repo = GeoRepository()
    return AttendanceService(attendance_repo, user_repo, face_repo, geo_repo)


@router.post("/mark", response_model=dict)
async def mark_attendance(
    request: AttendanceMarkRequest,
    service: AttendanceService = Depends(get_attendance_service)
):
    """Mark attendance for a user using face recognition."""
    # This would need image data in the actual implementation
    # For now, returning a placeholder response
    return {
        "success": False,
        "error": "Face recognition endpoint requires image data",
        "code": "MISSING_IMAGE"
    }


@router.get("/daily-status/{reg_no}", response_model=DailyStatusResponse)
async def get_daily_status(
    reg_no: str,
    for_date: Optional[date] = None,
    service: AttendanceService = Depends(get_attendance_service)
):
    """Get daily attendance status for a user."""
    return await service.get_daily_status(reg_no, for_date)


@router.get("/history/{reg_no}", response_model=list[AttendanceRecord])
async def get_attendance_history(
    reg_no: str,
    limit: int = Query(20, ge=1, le=100),
    service: AttendanceService = Depends(get_attendance_service)
):
    """Get recent attendance history for a user."""
    return await service.get_attendance_history(reg_no, limit)


@router.get("/value-summary/{reg_no}")
async def get_attendance_value_summary(
    reg_no: str,
    start_date: date,
    end_date: date,
    service: AttendanceService = Depends(get_attendance_service)
):
    """Get attendance value summary for a user over a date range.
    
    Returns total attendance value, percentage, and breakdown of full/half/absent days.
    """
    if start_date > end_date:
        raise HTTPException(
            status_code=400,
            detail="start_date must be before or equal to end_date"
        )
    
    return await service.get_attendance_value_summary(reg_no, start_date, end_date)


@router.get("/percentage/{reg_no}")
async def get_attendance_percentage(
    reg_no: str,
    period: str = Query(..., description="Period: 'month' (YYYY-MM) or 'custom'")
):
    """Get attendance percentage for a user.
    
    For 'month' period, use format like '2024-01'.
    For 'custom' period, provide start_date and end_date query params.
    """
    service = await get_attendance_service()
    
    if period.startswith("month:"):
        # Parse month from period string (e.g., 'month:2024-01')
        try:
            month_str = period.split(":")[1]
            year, month = map(int, month_str.split("-"))
            start_date = date(year, month, 1)
            # Get last day of month
            if month == 12:
                end_date = date(year + 1, 1, 1) - timedelta(days=1)
            else:
                end_date = date(year, month + 1, 1) - timedelta(days=1)
        except (ValueError, IndexError):
            raise HTTPException(
                status_code=400,
                detail="Invalid month format. Use month:YYYY-MM"
            )
    else:
        raise HTTPException(
            status_code=400,
            detail="Currently only 'month:YYYY-MM' period is supported"
        )
    
    result = await service.get_attendance_value_summary(reg_no, start_date, end_date)
    return {
        "reg_no": reg_no,
        "period": period,
        "attendance_percentage": result["attendance_percentage"],
        "total_attendance_value": result["total_attendance_value"],
        "total_working_days": result["total_working_days"]
    }


@router.get("/half-day-report/{report_date}", response_model=HalfDayReport)
async def get_half_day_report(
    report_date: date,
    service: AttendanceService = Depends(get_attendance_service)
):
    """Generate half-day attendance report for a specific date.
    
    Returns breakdown of users by their half-day attendance status.
    """
    return await service.get_half_day_report(report_date)