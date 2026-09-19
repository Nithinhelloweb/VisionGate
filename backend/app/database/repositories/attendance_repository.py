"""Attendance repository for attendance-related database operations."""
import logging
from typing import Optional, Dict, Any, List
import asyncpg
from datetime import datetime, date
from decimal import Decimal
from ..connection import db_pool
from .base_repository import BaseRepository
from ..models import Attendance, OtherStaffAttendance, DailyAttendanceStatus, UserLatestLocation, UserLocationLog

logger = logging.getLogger(__name__)


class AttendanceRepository(BaseRepository):
    """Repository for attendance-related database operations."""

    async def mark_attendance(
        self,
        reg_no: str,
        name: str,
        dept: str,
        timestamp: datetime
    ) -> int:
        """Mark attendance for a regular user/staff.
        
        Args:
            reg_no: Registration number
            name: Full name
            dept: Department
            timestamp: Timestamp of attendance
            
        Returns:
            ID of the created attendance record
        """
        row = await self.fetchrow(
            """
            INSERT INTO attendance (reg_no, name, dept, timestamp, status)
            VALUES ($1, $2, $3, $4, 'IN')
            RETURNING id
            """,
            reg_no, name, dept, timestamp
        )
        logger.info(f"Marked attendance for {reg_no} at {timestamp}")
        return row["id"]
    
    async def mark_other_staff_attendance(
        self,
        reg_no: str,
        name: str,
        dept: str,
        role: str,
        timestamp: datetime
    ) -> int:
        """Mark attendance for other staff.
        
        Args:
            reg_no: Registration number (contact_no)
            name: Full name
            dept: Department
            role: Staff role
            timestamp: Timestamp of attendance
            
        Returns:
            ID of the created attendance record
        """
        # First ensure other_staff exists
        staff = await self._get_or_create_other_staff(reg_no, name, dept, role)
        
        row = await self.fetchrow(
            """
            INSERT INTO other_staff_attendance (staff_id, timestamp, status)
            VALUES ($1, $2, 'IN')
            RETURNING id
            """,
            staff["id"], timestamp
        )
        logger.info(f"Marked other staff attendance for {reg_no} at {timestamp}")
        return row["id"]
    
    async def _get_or_create_other_staff(self, reg_no: str, name: str, dept: str, role: str) -> Dict[str, Any]:
        """Get or create an other_staff record.
        
        Args:
            reg_no: Contact number (used as reg_no)
            name: Full name
            dept: Department
            role: Staff role
            
        Returns:
            Dict with other_staff fields
        """
        row = await self.fetchrow(
            "SELECT * FROM other_staff WHERE contact_no = $1",
            reg_no
        )
        if row:
            return dict(row)
        
        row = await self.fetchrow(
            """
            INSERT INTO other_staff (name, dept, contact_no, role, is_active)
            VALUES ($1, $2, $3, $4, TRUE)
            RETURNING id, name, dept, contact_no, role
            """,
            name, dept, reg_no, role
        )
        return dict(row)
    
    async def get_today_attendance(self, reg_no: str) -> Optional[dict]:
        """Get today's attendance status for a user.
        
        Args:
            reg_no: Registration number
            
        Returns:
            Dict with daily attendance status or None
        """
        row = await self.fetchrow(
            """
            SELECT * FROM daily_attendance_status
            WHERE reg_no = $1 AND date = CURRENT_DATE
            """,
            reg_no
        )
        return dict(row) if row else None
    
    async def get_recent_attendance(self, reg_no: str, limit: int = 10) -> List[dict]:
        """Get recent attendance records for a user.
        
        Args:
            reg_no: Registration number
            limit: Maximum number of records to return
            
        Returns:
            List of attendance record dicts
        """
        rows = await self.fetch(
            """
            SELECT * FROM attendance
            WHERE reg_no = $1
            ORDER BY timestamp DESC
            LIMIT $2
            """,
            reg_no, limit
        )
        return [dict(row) for row in rows]
    
    async def get_staff_attendance_range(
        self,
        reg_no: str,
        start_date: date,
        end_date: date
    ) -> List[dict]:
        """Get attendance records for a user within a date range.
        
        Args:
            reg_no: Registration number
            start_date: Start date (inclusive)
            end_date: End date (inclusive)
            
        Returns:
            List of attendance record dicts
        """
        rows = await self.fetch(
            """
            SELECT * FROM attendance
            WHERE reg_no = $1 AND timestamp::date >= $2 AND timestamp::date <= $3
            ORDER BY timestamp
            """,
            reg_no, start_date, end_date
        )
        return [dict(row) for row in rows]
    
    async def sync_daily_status_for_month(self, reg_no: str, month: str) -> None:
        """Sync daily attendance status for a given month (YYYY-MM format).
        
        Updates daily_attendance_status table based on attendance table,
        summarizing IN/OUT times into daily status.
        
        Args:
            reg_no: Registration number
            month: Month in YYYY-MM format
        """
        await self.execute(
            """
            WITH month_days AS (
                SELECT generate_series(
                    date_trunc('month', $2::date),
                    (date_trunc('month', $2::date) + INTERVAL '1 month - 1 day')::date,
                    '1 day'::interval
                )::date AS day
            ),
            daily_summary AS (
                SELECT
                    d.day AS date,
                    MIN(a.timestamp) FILTER (WHERE a.status = 'IN') AS in_time,
                    MAX(a.timestamp) FILTER (WHERE a.status = 'OUT') AS out_time,
                    CASE
                        WHEN COUNT(*) FILTER (WHERE a.status IN ('IN', 'OUT')) > 0 THEN 'PRESENT'
                        ELSE 'ABSENT'
                    END AS status
                FROM month_days d
                LEFT JOIN attendance a ON d.day = a.timestamp::date AND a.reg_no = $1
                GROUP BY d.day
            )
            INSERT INTO daily_attendance_status (reg_no, date, status, in_time, out_time, updated_at)
            SELECT $1, date, status, in_time::time, out_time::time, NOW()
            FROM daily_summary
            ON CONFLICT (reg_no, date)
            DO UPDATE SET
                status = EXCLUDED.status,
                in_time = EXCLUDED.in_time,
                out_time = EXCLUDED.out_time,
                updated_at = NOW()
            """,
            reg_no, month
        )
        logger.info(f"Synced daily status for {reg_no} for month {month}")
    
    async def get_department_attendance(self, dept: str, date: date) -> List[dict]:
        """Get attendance records for a department on a specific date.
        
        Args:
            dept: Department name
            date: Date
            
        Returns:
            List of attendance record dicts
        """
        rows = await self.fetch(
            """
            SELECT a.* FROM attendance a
            JOIN users u ON a.reg_no = u.reg_no
            WHERE u.dept = $1 AND a.timestamp::date = $2
            ORDER BY a.timestamp
            """,
            dept, date
        )
        return [dict(row) for row in rows]
    
    async def get_attendance_stats(
        self,
        dept: str | None,
        start_date: date,
        end_date: date
    ) -> Dict[str, Any]:
        """Get attendance statistics for a department or all departments.
        
        Args:
            dept: Department name (None for all departments)
            start_date: Start date
            end_date: End date
            
        Returns:
            Dict with stats (total_records, unique_users, present_count, absent_count)
        """
        if dept is not None:
            rows = await self.fetch(
                """
                SELECT
                    COUNT(*) AS total_records,
                    COUNT(DISTINCT a.reg_no) AS unique_users,
                    COUNT(*) FILTER (WHERE a.status = 'IN') AS present_count,
                    COUNT(*) FILTER (WHERE a.status = 'OUT') AS absent_count
                FROM attendance a
                JOIN users u ON a.reg_no = u.reg_no
                WHERE u.dept = $1 AND a.timestamp::date >= $2 AND a.timestamp::date <= $3
                """,
                dept, start_date, end_date
            )
        else:
            rows = await self.fetch(
                """
                SELECT
                    COUNT(*) AS total_records,
                    COUNT(DISTINCT reg_no) AS unique_users,
                    COUNT(*) FILTER (WHERE status = 'IN') AS present_count,
                    COUNT(*) FILTER (WHERE status = 'OUT') AS absent_count
                FROM attendance
                WHERE timestamp::date >= $1 AND timestamp::date <= $2
                """,
                start_date, end_date
            )
        
        row = rows[0] if rows else {}
        return {
            "total_records": int(row.get("total_records", 0)),
            "unique_users": int(row.get("unique_users", 0)),
            "present_count": int(row.get("present_count", 0)),
            "absent_count": int(row.get("absent_count", 0))
        }
    
    async def bulk_mark_attendance(self, records: List[Dict[str, Any]]) -> List[int]:
        """Bulk mark attendance records.
        
        Args:
            records: List of dicts with reg_no, name, dept, timestamp
            
        Returns:
            List of inserted record IDs
        """
        ids = []
        async with self.pool.acquire() as conn:
            async with conn.transaction():
                for record in records:
                    row = await conn.fetchrow(
                        """
                        INSERT INTO attendance (reg_no, name, dept, timestamp, status)
                        VALUES ($1, $2, $3, $4, 'IN')
                        RETURNING id
                        """,
                        record["reg_no"], record["name"],
                        record["dept"], record["timestamp"]
                    )
                    ids.append(row["id"])
        return ids

    async def update_attendance_value(
        self,
        reg_no: str,
        for_date: date,
        attendance_value: Decimal
    ) -> bool:
        """Update attendance value for a specific user and date.
        
        Args:
            reg_no: Registration number
            for_date: Date to update
            attendance_value: New attendance value (0.0, 0.5, or 1.0)
            
        Returns:
            True if update successful, False otherwise
        """
        result = await self.execute(
            """
            UPDATE daily_attendance_status
            SET attendance_value = $3, updated_at = NOW()
            WHERE reg_no = $1 AND date = $2
            """,
            reg_no, for_date, attendance_value
        )
        return result is not None

    async def get_attendance_value_sum(
        self,
        reg_no: str,
        start_date: date,
        end_date: date
    ) -> Decimal:
        """Get sum of attendance values for a user over a date range.
        
        Args:
            reg_no: Registration number
            start_date: Start date (inclusive)
            end_date: End date (inclusive)
            
        Returns:
            Sum of attendance values as Decimal
        """
        row = await self.fetchrow(
            """
            SELECT COALESCE(SUM(attendance_value), 0) as total_value
            FROM daily_attendance_status
            WHERE reg_no = $1 AND date >= $2 AND date <= $3
            """,
            reg_no, start_date, end_date
        )
        return row["total_value"] if row else Decimal("0.0")

    async def recalculate_attendance_values(self, reg_no: str, for_date: date) -> bool:
        """Recalculate attendance value based on half-day statuses.
        
        Args:
            reg_no: Registration number
            for_date: Date to recalculate
            
        Returns:
            True if recalculation successful, False otherwise
        """
        row = await self.fetchrow(
            """
            UPDATE daily_attendance_status
            SET attendance_value = 
                CASE 
                    WHEN COALESCE(first_half_status, 'Absent') = 'Present' 
                     AND COALESCE(second_half_status, 'Absent') = 'Present' THEN 1.0
                    WHEN COALESCE(first_half_status, 'Absent') = 'Present' 
                      OR COALESCE(second_half_status, 'Absent') = 'Present' THEN 0.5
                    WHEN status = 'Holiday' THEN 1.0
                    ELSE 0.0
                END,
                updated_at = NOW()
            WHERE reg_no = $1 AND date = $2
            RETURNING attendance_value
            """,
            reg_no, for_date
        )
        return row is not None