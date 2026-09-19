"""Attendance service for core business logic - marking, CL management, leave processing."""
from datetime import datetime, date, timedelta
from typing import Optional, Dict, Any, List
from decimal import Decimal
import logging
import asyncio
import numpy as np
from concurrent.futures import ThreadPoolExecutor

from app.database.repositories.attendance_repository import AttendanceRepository
from app.database.repositories.user_repository import UserRepository
from app.database.repositories.face_repository import FaceRepository
from app.database.repositories.geo_repository import GeoRepository
from app.api.schemas.attendance import AttendanceRecord, DailyStatusResponse
from app.api.schemas.leave import CLBalanceResponse
from app.config import settings

logger = logging.getLogger(__name__)

executor = ThreadPoolExecutor(max_workers=4)


class FaceNotFoundError(Exception):
    """Raised when no face is detected in the image."""
    pass


class LowConfidenceError(Exception):
    """Raised when face confidence is below threshold."""
    pass


class AttendanceService:
    def __init__(
        self,
        attendance_repo: AttendanceRepository,
        user_repo: UserRepository,
        face_repo: FaceRepository,
        geo_repo: GeoRepository,
        leave_repo: Optional[Any] = None
    ):
        self.attendance_repo = attendance_repo
        self.user_repo = user_repo
        self.face_repo = face_repo
        self.geo_repo = geo_repo
        self.leave_repo = leave_repo
        self.logger = logger

    async def mark_attendance_secure(
        self,
        reg_no: str,
        image_bytes: bytes,
        client_platform: str = None,
        client_lat: float = None,
        client_lng: float = None
    ) -> Dict[str, Any]:
        """
        Main attendance marking flow:
        1. Extract face embedding from image
        2. Verify identity against registered face (pgvector similarity search)
        3. Record attendance in DB
        4. Update daily status
        5. Log audit event
        """
        try:
            query_embedding = await self._extract_face_embedding(image_bytes)
        except FaceNotFoundError as e:
            return {"success": False, "error": str(e), "code": "NO_FACE"}
        except Exception as e:
            self.logger.error(f"Face extraction error for {reg_no}: {e}")
            return {"success": False, "error": "Failed to process image", "code": "PROCESSING_ERROR"}

        verified, confidence, reason = await self._verify_identity(reg_no, query_embedding)
        if not verified:
            return {
                "success": False,
                "error": reason,
                "code": "FACE_MISMATCH",
                "confidence": confidence
            }

        user = await self.user_repo.get_by_reg_no(reg_no)
        if not user:
            return {"success": False, "error": "User not found", "code": "USER_NOT_FOUND"}

        now = datetime.now()
        try:
            attendance_id = await self.attendance_repo.insert_attendance(
                reg_no=reg_no,
                name=user.name,
                dept=user.dept,
                timestamp=now,
                status="present"
            )
        except Exception as e:
            self.logger.error(f"DB error marking attendance: {e}")
            return {"success": False, "error": "Database error", "code": "DB_ERROR"}

        try:
            await self._sync_daily_status(reg_no, now.date())
        except Exception as e:
            self.logger.warning(f"Failed to sync daily status: {e}")

        self.logger.info(
            "attendance_marked",
            extra={"reg_no": reg_no, "confidence": confidence, "attendance_id": attendance_id}
        )

        return {
            "success": True,
            "message": "Attendance marked successfully",
            "data": {
                "attendance_id": attendance_id,
                "timestamp": now.isoformat(),
                "user": {"reg_no": reg_no, "name": user.name, "dept": user.dept},
                "confidence": confidence
            }
        }

    async def _extract_face_embedding(self, image_bytes: bytes) -> bytes:
        """Extract face embedding from image using face recognition model."""
        loop = asyncio.get_event_loop()
        
        def _extract_sync():
            import cv2
            nparr = np.frombuffer(image_bytes, np.uint8)
            img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
            if img is None:
                raise FaceNotFoundError("Could not decode image")
            
            try:
                from insightface.app import FaceAnalysis
                app = FaceAnalysis(name="buffalo_l", providers=["CPUExecutionProvider"])
                app.prepare(ctx_id=0, det_thresh=0.5)
                faces = app.get(img)
            except Exception:
                raise FaceNotFoundError("Face detection failed")
            
            if not faces:
                raise FaceNotFoundError("No face detected in image")
            
            embedding = faces[0].embedding
            return embedding.astype(np.float32).tobytes()
        
        return await loop.run_in_executor(executor, _extract_sync)

    async def _verify_identity(self, reg_no: str, query_embedding: bytes) -> tuple:
        """Verify face identity against registered user. Returns (verified, confidence, reason)."""
        matches = await self.face_repo.search_similar_faces(
            query_embedding,
            limit=5,
            threshold=settings.FACE_MIN_COSINE_SIMILARITY
        )
        
        for match_reg_no, name, dept, role, similarity in matches:
            if match_reg_no.lower() == reg_no.lower():
                if similarity >= settings.FACE_CONFIDENCE_THRESHOLD:
                    return True, similarity, "Identity verified"
                return False, similarity, f"Low confidence match ({similarity:.2f})"
        
        return False, 0.0, "Face not recognized"

    def _calculate_attendance_value(self, first_half_status: Optional[str], second_half_status: Optional[str], 
                                   status: str, leave_type: Optional[str] = None) -> Decimal:
        """Calculate attendance value based on half-day statuses and scenario types.
        
        Args:
            first_half_status: Status of first half ('Present', 'Absent', 'Leave', 'OD', 'Permission')
            second_half_status: Status of second half ('Present', 'Absent', 'Leave', 'OD', 'Permission')
            status: Overall status ('present', 'absent', 'leave', 'od', 'holiday', 'permission')
            leave_type: Type of leave/od if applicable
            
        Returns:
            Decimal attendance value (0.0, 0.5, or 1.0)
        """
        st_lower = (status or "").lower()
        lt_lower = (leave_type or "").lower()

        # Direct overall statuses
        if st_lower in ('od', 'on duty', 'on_duty', 'permission', 'holiday') or lt_lower in ('od', 'on duty', 'on_duty'):
            return Decimal("1.0")

        # Calculate based on half-day statuses if available
        if first_half_status and second_half_status:
            attendance_value = Decimal("0.0")
            fh_lower = first_half_status.lower()
            sh_lower = second_half_status.lower()

            # First half evaluation
            if fh_lower in ('present', 'od', 'on duty', 'permission'):
                attendance_value += Decimal("0.5")
            
            # Second half evaluation
            if sh_lower in ('present', 'od', 'on duty', 'permission'):
                attendance_value += Decimal("0.5")
                
            return attendance_value
        else:
            # Fallback to overall status
            if st_lower in ('present',):
                return Decimal("1.0")
            elif st_lower in ('half_day', 'half day', 'half day present (fn)', 'half day present (an)'):
                return Decimal("0.5")
            elif st_lower in ('holiday',):
                return Decimal("1.0")  # Holidays count as full credit
            # Absent, Leave (CL/ML/LOP) without present half are 0.0 attendance value
            return Decimal("0.0")

    async def _sync_daily_status(self, reg_no: str, for_date: date) -> None:
        """Sync daily attendance status for user."""
        from app.database.connection import db_pool
        from decimal import Decimal
        async with db_pool.pool.acquire() as conn:
            # Get user info
            user = await conn.fetchrow("SELECT name, dept FROM users WHERE reg_no = $1", reg_no)
            name = user['name'] if user else 'Unknown'
            dept = user['dept'] if user else 'Unknown'

            # Get half-day settings from leave_settings
            settings_rows = await conn.fetch("SELECT key, value FROM leave_settings")
            s_dict = {r['key']: r['value'] for r in settings_rows} if settings_rows else {}
            hd_enabled = str(s_dict.get("half_day_enabled", "false")).lower() == "true"

            # Check if there is an existing record to preserve approved leaves/ODs or manual adjustments
            existing = await conn.fetchrow(
                "SELECT status, leave_type, absent_reason, first_half_status, second_half_status, attendance_value FROM daily_attendance_status WHERE reg_no = $1 AND date = $2",
                reg_no, for_date
            )
            
            existing_st = (existing['status'] if existing else '') or ''
            existing_lt = (existing['leave_type'] if existing else '') or ''

            # Check if there are any scans on this date
            scans = await conn.fetch(
                "SELECT timestamp FROM attendance WHERE reg_no = $1 AND DATE(timestamp) = $2",
                reg_no, for_date
            )

            # Determine halves
            fh_present = False
            sh_present = False
            
            for scan in scans:
                scan_time = scan['timestamp'].time()
                # Use 13:00 (1 PM) as cutoff
                if scan_time.hour < 13:
                    fh_present = True
                else:
                    sh_present = True

            # If user already has an approved OD for the day, preserve it
            if existing_st in ('OD', 'On Duty') or existing_lt.lower() == 'od':
                first_half_status = existing['first_half_status'] or 'OD'
                second_half_status = existing['second_half_status'] or 'OD'
                overall_status = 'On Duty (OD)'
                attendance_value = Decimal("1.0")
            elif existing_st in ('Leave', 'On Leave') and not scans:
                first_half_status = existing['first_half_status'] or 'Leave'
                second_half_status = existing['second_half_status'] or 'Leave'
                overall_status = 'On Leave'
                attendance_value = Decimal("0.0")
            elif not hd_enabled:
                first_half_status = "Present" if scans else (existing['first_half_status'] if existing else "Absent")
                second_half_status = "Present" if scans else (existing['second_half_status'] if existing else "Absent")
                overall_status = "Present" if scans else (existing_st or "Absent")
                attendance_value = Decimal("1.0") if scans else (Decimal(str(existing['attendance_value'])) if existing and existing['attendance_value'] is not None else Decimal("0.0"))
            else:
                first_half_status = "Present" if fh_present else (existing['first_half_status'] if existing and existing['first_half_status'] in ('Leave', 'OD') else None)
                second_half_status = "Present" if sh_present else (existing['second_half_status'] if existing and existing['second_half_status'] in ('Leave', 'OD') else None)
                
                fh = first_half_status or "Absent"
                sh = second_half_status or "Absent"
                
                if fh == "Present" and sh == "Present":
                    overall_status = "Present"
                    attendance_value = Decimal("1.0")
                elif (fh in ("Present", "OD") and sh in ("Present", "OD")):
                    overall_status = "Present"
                    attendance_value = Decimal("1.0")
                elif fh == "Present" and sh != "Present":
                    overall_status = "Half Day Present (FN)"
                    attendance_value = Decimal("0.5")
                elif fh != "Present" and sh == "Present":
                    overall_status = "Half Day Present (AN)"
                    attendance_value = Decimal("0.5")
                elif fh == "Leave" and sh == "Leave":
                    overall_status = "On Leave"
                    attendance_value = Decimal("0.0")
                elif fh == "OD" and sh == "OD":
                    overall_status = "On Duty (OD)"
                    attendance_value = Decimal("1.0")
                else:
                    overall_status = "Absent"
                    attendance_value = Decimal("0.0")

            # Upsert into daily_attendance_status (using PostgreSQL ON CONFLICT syntax)
            await conn.execute(
                """
                INSERT INTO daily_attendance_status 
                (reg_no, name, dept, date, status, first_half_status, second_half_status, attendance_value, marked_by, marked_at)
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'Attendance System', NOW())
                ON CONFLICT (reg_no, date) DO UPDATE SET
                    status = EXCLUDED.status,
                    first_half_status = EXCLUDED.first_half_status,
                    second_half_status = EXCLUDED.second_half_status,
                    attendance_value = EXCLUDED.attendance_value,
                    marked_by = 'Attendance System',
                    marked_at = NOW()
                """,
                reg_no, name, dept, for_date, overall_status, first_half_status, second_half_status, attendance_value
            )

    async def get_attendance_history(self, reg_no: str, limit: int = 20) -> List[AttendanceRecord]:
        """Get recent attendance history for a user."""
        records = await self.attendance_repo.get_recent_attendance(reg_no, limit)
        return [AttendanceRecord(**r) for r in records]

    async def get_daily_status(self, reg_no: str, for_date: date = None) -> DailyStatusResponse:
        """Get daily attendance status for a user."""
        if for_date is None:
            for_date = date.today()
        
        status = await self._get_today_attendance(reg_no, for_date)
        if not status:
            status = {"status": "absent", "leave_type": None, "attendance_value": Decimal("0.0")}
        
        cl_balance = None
        if self.leave_repo:
            cl_balance = await self.leave_repo.get_cl_balance(reg_no)
        
        return DailyStatusResponse(
            date=for_date,
            status=status["status"],
            leave_type=status.get("leave_type"),
            attendance_value=status.get("attendance_value")
        )

    async def _get_today_attendance(self, reg_no: str, for_date: date) -> Optional[Dict]:
        """Get attendance status for a specific date."""
        from app.database.connection import db_pool
        async with db_pool.pool.acquire() as conn:
            row = await conn.fetchrow(
                """
                SELECT status, leave_type, attendance_value FROM daily_attendance_status
                WHERE reg_no = $1 AND date = $2
                """,
                reg_no, for_date
            )
            if row:
                return {
                    "status": row["status"], 
                    "leave_type": row["leave_type"],
                    "attendance_value": row["attendance_value"]
                }
            return None

    async def process_cl_deduction(self, reg_no: str, for_date: date) -> Dict[str, Any]:
        """Process CL deduction for a leave day."""
        if not self.leave_repo:
            return {"success": False, "error": "Leave repository not configured"}
        
        try:
            result = await self.leave_repo.deduct_cl(reg_no, for_date)
            return {"success": True, **result}
        except Exception as e:
            self.logger.error(f"CL deduction error for {reg_no}: {e}")
            return {"success": False, "error": str(e)}

    async def bulk_mark_attendance(self, records: List[Dict]) -> Dict[str, Any]:
        """Bulk mark attendance for multiple users."""
        success_count = 0
        failed = []
        
        for record in records:
            result = await self.mark_attendance_secure(
                reg_no=record["reg_no"],
                image_bytes=record["image_bytes"],
                client_platform=record.get("platform"),
                client_lat=record.get("lat"),
                client_lng=record.get("lng")
            )
            if result.get("success"):
                success_count += 1
            else:
                failed.append({"reg_no": record["reg_no"], "error": result.get("error")})
        
        return {
            "success": True,
            "total": len(records),
            "successful": success_count,
            "failed": failed
        }

    async def get_attendance_value_summary(self, reg_no: str, start_date: date, end_date: date) -> Dict[str, Any]:
        """Get attendance value summary for a user over a date range.
        
        Args:
            reg_no: Registration number
            start_date: Start date (inclusive)
            end_date: End date (inclusive)
            
        Returns:
            Dict with attendance value summary including total value, percentage, breakdown
        """
        from app.database.connection import db_pool
        async with db_pool.pool.acquire() as conn:
            # Get user info
            user = await self.user_repo.get_by_reg_no(reg_no)
            if not user:
                return {"success": False, "error": "User not found"}
            
            # Get attendance records for the period
            rows = await conn.fetch(
                """
                SELECT 
                    date,
                    status,
                    attendance_value,
                    first_half_status,
                    second_half_status,
                    leave_type
                FROM daily_attendance_status
                WHERE reg_no = $1 AND date >= $2 AND date <= $3
                ORDER BY date
                """,
                reg_no, start_date, end_date
            )
            
            total_attendance_value = Decimal("0.0")
            full_days = 0
            half_days = 0
            absent_days = 0
            leave_days = 0
            total_working_days = (end_date - start_date).days + 1
            
            for row in rows:
                value = row["attendance_value"] or Decimal("0.0")
                total_attendance_value += value
                
                if value == Decimal("1.0"):
                    full_days += 1
                elif value == Decimal("0.5"):
                    half_days += 1
                elif value == Decimal("0.0"):
                    if row["status"].lower() == "leave":
                        leave_days += 1
                    else:
                        absent_days += 1
            
            # Calculate percentage
            attendance_percentage = Decimal("0.0")
            if total_working_days > 0:
                attendance_percentage = (total_attendance_value / Decimal(str(total_working_days))) * Decimal("100")
            
            return {
                "success": True,
                "reg_no": reg_no,
                "name": user.name,
                "dept": user.dept,
                "start_date": start_date,
                "end_date": end_date,
                "total_attendance_value": float(total_attendance_value),
                "total_working_days": total_working_days,
                "attendance_percentage": float(attendance_percentage),
                "full_days": full_days,
                "half_days": half_days,
                "absent_days": absent_days,
                "leave_days": leave_days
            }

    async def get_half_day_report(self, report_date: date) -> Dict[str, Any]:
        """Generate half-day attendance report for a specific date.
        
        Args:
            report_date: Date to generate report for
            
        Returns:
            Dict with half-day breakdown statistics and details
        """
        from app.database.connection import db_pool
        async with db_pool.pool.acquire() as conn:
            # Get all users
            users = await conn.fetch(
                "SELECT reg_no, name, dept FROM users WHERE is_active = TRUE"
            )
            
            total_users = len(users)
            full_day_present = 0
            first_half_only = 0
            second_half_only = 0
            full_day_absent = 0
            on_leave = 0
            details = []
            
            for user in users:
                row = await conn.fetchrow(
                    """
                    SELECT 
                        status,
                        attendance_value,
                        first_half_status,
                        second_half_status,
                        leave_type
                    FROM daily_attendance_status
                    WHERE reg_no = $1 AND date = $2
                    """,
                    user["reg_no"], report_date
                )
                
                if row:
                    status = row["status"].lower()
                    first_half = row["first_half_status"]
                    second_half = row["second_half_status"]
                    value = row["attendance_value"] or Decimal("0.0")
                    
                    if value == Decimal("1.0"):
                        full_day_present += 1
                    elif value == Decimal("0.5"):
                        if first_half and first_half.lower() == "present":
                            first_half_only += 1
                        elif second_half and second_half.lower() == "present":
                            second_half_only += 1
                    elif value == Decimal("0.0"):
                        if status == "leave":
                            on_leave += 1
                        else:
                            full_day_absent += 1
                    
                    details.append({
                        "reg_no": user["reg_no"],
                        "name": user["name"],
                        "dept": user["dept"],
                        "status": row["status"],
                        "attendance_value": float(value),
                        "first_half_status": first_half,
                        "second_half_status": second_half,
                        "leave_type": row["leave_type"]
                    })
                else:
                    full_day_absent += 1
                    details.append({
                        "reg_no": user["reg_no"],
                        "name": user["name"],
                        "dept": user["dept"],
                        "status": "absent",
                        "attendance_value": 0.0,
                        "first_half_status": None,
                        "second_half_status": None,
                        "leave_type": None
                    })
            
            return {
                "success": True,
                "date": report_date,
                "total_users": total_users,
                "full_day_present": full_day_present,
                "first_half_only": first_half_only,
                "second_half_only": second_half_only,
                "full_day_absent": full_day_absent,
                "on_leave": on_leave,
                "details": details
            }