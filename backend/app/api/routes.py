"""API routes and dependencies."""
from fastapi import APIRouter

from .v1.auth import router as auth_router
from .v1.attendance import router as attendance_router
from .v1.admin import router as admin_router
from .v1.hod import router as hod_router
from .v1.staff import router as staff_router
from .v1.face import router as face_router
from .v1.location import router as location_router
from .v1.settings import router as settings_router
from .v1.leave import router as leave_router
from .v1.staff_schedule import router as staff_schedule_router

# Main API router
api_router = APIRouter()

# Include versioned routers
api_router.include_router(auth_router, tags=["Authentication"])
api_router.include_router(attendance_router, tags=["Attendance"])
api_router.include_router(admin_router, tags=["Admin"])
api_router.include_router(hod_router, tags=["HOD"])
api_router.include_router(staff_router, tags=["Staff"])
api_router.include_router(face_router, tags=["Face Recognition"])
api_router.include_router(location_router, tags=["Location Tracking"])
api_router.include_router(settings_router, tags=["Settings"])
api_router.include_router(leave_router, tags=["Leave Management"])
api_router.include_router(staff_schedule_router, tags=["Staff Academic Schedule & Calendar"])