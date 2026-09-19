"""Leave repository for leave management operations."""
import logging
from typing import Optional, Dict, Any, List
import asyncpg
from datetime import date
from ..connection import db_pool
from .base_repository import BaseRepository
from ..models import CasualLeave, LeaveRequest, LeaveRequestAuditLog

logger = logging.getLogger(__name__)


class LeaveRepository(BaseRepository):
    """Repository for leave management operations."""

    async def get_cl_balance(self, reg_no: str, month: str) -> Dict[str, Any]:
        """Get casual leave balance for a user in a given month.
        
        Args:
            reg_no: Registration number
            month: Month in YYYY-MM format
            
        Returns:
            Dict with cl_balance fields:
                - current_month_cl_available
                - accumulated_cl
                - cl_used_current_month
        """
        # Count CL used in current month
        used_row = await self.fetchrow(
            """
            SELECT COUNT(*) AS cl_used
            FROM casual_leave
            WHERE reg_no = $1
            AND to_char(leave_date, 'YYYY-MM') = $2
            AND approved = TRUE
            """,
            reg_no, month
        )
        cl_used = int(used_row["cl_used"]) if used_row else 0
        
        # Get accumulated CL (sum from cl_ledger or similar logic)
        # For now, assume a base of 2 days per month, counting from user creation
        user_row = await self.fetchrow(
            "SELECT created_at FROM users WHERE reg_no = $1",
            reg_no
        )
        
        accumulated_cl = 2.0  # default monthly allowance
        
        if user_row:
            # Could compute months since creation/last reset
            # Simplification: return base value
            pass
        
        available = accumulated_cl - cl_used
        
        return {
            "reg_no": reg_no,
            "month": month,
            "current_month_cl_available": max(0.0, float(available)),
            "accumulated_cl": float(accumulated_cl),
            "cl_used_current_month": float(cl_used)
        }
    
    async def initialize_cl_for_user(
        self,
        reg_no: str,
        user_name: str,
        dept: str,
        role: str,
        month: str
    ) -> None:
        """Initialize CL for a new user for a given month.
        
        Args:
            reg_no: Registration number
            user_name: Full name
            dept: Department
            role: Role
            month: Month in YYYY-MM format
        """
        # Check if already initialized
        exists = await self.fetchval(
            """
            SELECT EXISTS(
                SELECT 1 FROM cl_ledger
                WHERE reg_no = $1 AND month = $2
            )
            """,
            reg_no, month
        )
        
        if not exists:
            await self.execute(
                """
                INSERT INTO cl_ledger (reg_no, user_name, dept, role, month, cl_allocated, cl_used, cl_balance)
                VALUES ($1, $2, $3, $4, $5, $6, 0, $6)
                """,
                reg_no, user_name, dept, role, month, 2.0  # 2 days allocated
            )
            logger.info(f"Initialized CL for {reg_no} for month {month}")
    
    async def reset_monthly_cl(self, target_month: str) -> int:
        """Reset monthly CL for all users (typically run at month start).
        
        Archives old ledger entries and initializes new month with fresh allocation.
        
        Args:
            target_month: Month in YYYY-MM format to reset for
            
        Returns:
            Number of users processed
        """
        async with self.pool.acquire() as conn:
            async with conn.transaction():
                # Get all active users
                rows = await conn.fetch(
                    "SELECT reg_no, name, dept, role FROM users WHERE is_active = TRUE"
                )
                
                count = 0
                for row in rows:
                    reg_no = row["reg_no"]
                    
                    # Check if already initialized for this month
                    exists = await conn.fetchval(
                        "SELECT EXISTS(SELECT 1 FROM cl_ledger WHERE reg_no = $1 AND month = $2)",
                        reg_no, target_month
                    )
                    
                    if not exists:
                        await conn.execute(
                            """
                            INSERT INTO cl_ledger (reg_no, user_name, dept, role, month, cl_allocated, cl_used, cl_balance)
                            VALUES ($1, $2, $3, $4, $5, $6, 0, $6)
                            """,
                            reg_no, row["name"], row["dept"], row["role"], target_month, 2.0
                        )
                        count += 1
        
        logger.info(f"Reset monthly CL for {count} users for month {target_month}")
        return count
    
    async def use_cl(self, reg_no: str, month: str) -> bool:
        """Decrement available CL for a user.
        
        Args:
            reg_no: Registration number
            month: Month in YYYY-MM format
            
        Returns:
            True if CL was available and decremented, False otherwise
        """
        result = await self.execute(
            """
            UPDATE cl_ledger
            SET cl_used = cl_used + 1, cl_balance = cl_balance - 1
            WHERE reg_no = $1 AND month = $2 AND cl_balance > 0
            """,
            reg_no, month
        )
        
        updated = result and "UPDATE 1" in result
        if updated:
            logger.info(f"CL used by {reg_no} for month {month}")
        else:
            logger.warning(f"No CL available for {reg_no} for month {month}")
        
        return updated
    
    async def get_all_cl_statuses(self, month: str) -> List[Dict[str, Any]]:
        """Get CL status for all users for a given month.
        
        Args:
            month: Month in YYYY-MM format
            
        Returns:
            List of CL status dicts
        """
        rows = await self.fetch(
            """
            SELECT reg_no, user_name, dept, role, cl_allocated, cl_used, cl_balance
            FROM cl_ledger
            WHERE month = $1
            ORDER BY dept, user_name
            """,
            month
        )
        return [dict(row) for row in rows]
    
    async def create_leave_request(self, request_data: Dict[str, Any]) -> int:
        """Create a new leave request.
        
        Args:
            request_data: Dict containing:
                - reg_no: Registration number
                - leave_type: Type of leave ('CASUAL', 'SICK', 'EARNED', etc.)
                - start_date: Start date
                - end_date: End date
                - reason: Reason for leave
                - status: Initial status ('PENDING' by default)
                
        Returns:
            ID of the created leave request
        """
        row = await self.fetchrow(
            """
            INSERT INTO leave_requests
            (reg_no, leave_type, start_date, end_date, reason, status)
            VALUES ($1, $2, $3, $4, $5, COALESCE($6, 'PENDING'))
            RETURNING id
            """,
            request_data.get("reg_no"),
            request_data.get("leave_type"),
            request_data.get("start_date"),
            request_data.get("end_date"),
            request_data.get("reason"),
            request_data.get("status", "PENDING")
        )
        request_id = row["id"]
        logger.info(f"Created leave request {request_id} for {request_data.get('reg_no')}")
        return request_id
    
    async def get_leave_requests_by_user(self, reg_no: str) -> List[Dict[str, Any]]:
        """Get all leave requests for a specific user.
        
        Args:
            reg_no: Registration number
            
        Returns:
            List of leave request dicts
        """
        rows = await self.fetch(
            """
            SELECT * FROM leave_requests
            WHERE reg_no = $1
            ORDER BY created_at DESC
            """,
            reg_no
        )
        return [dict(row) for row in rows]
    
    async def get_leave_requests_by_status(self, status: str) -> List[Dict[str, Any]]:
        """Get all leave requests with a specific status.
        
        Args:
            status: Status to filter by ('PENDING', 'APPROVED', 'REJECTED')
            
        Returns:
            List of leave request dicts
        """
        rows = await self.fetch(
            "SELECT * FROM leave_requests WHERE status = $1 ORDER BY created_at DESC",
            status
        )
        return [dict(row) for row in rows]
    
    async def update_leave_request_status(
        self,
        request_id: int,
        status: str,
        processed_by: str,
        admin_comment: str | None
    ) -> bool:
        """Update the status of a leave request.
        
        Args:
            request_id: Leave request ID
            status: New status ('APPROVED', 'REJECTED', etc.)
            processed_by: User who processed the request
            admin_comment: Optional admin comment
            
        Returns:
            True if updated successfully, False otherwise
        """
        async with self.pool.acquire() as conn:
            async with conn.transaction():
                # Update leave request
                result = await conn.execute(
                    """
                    UPDATE leave_requests
                    SET status = $1, approved_by = $2, admin_comment = $3, updated_at = NOW()
                    WHERE id = $4
                    """,
                    status, processed_by, admin_comment, request_id
                )
                
                if not result or result == "UPDATE 0":
                    return False
                
                # Get the leave request details
                row = await conn.fetchrow(
                    "SELECT reg_no, leave_type, start_date, end_date FROM leave_requests WHERE id = $1",
                    request_id
                )
                
                if not row:
                    return False
                
                reg_no = row["reg_no"]
                
                # If approved and it's casual leave, deduct from CL balance
                if status == "APPROVED" and row["leave_type"] == "CASUAL":
                    start_date = row["start_date"]
                    if isinstance(start_date, date):
                        month = start_date.strftime("%Y-%m")
                    else:
                        month = str(start_date)[:7]
                    
                    await conn.execute(
                        """
                        UPDATE cl_ledger
                        SET cl_used = cl_used + 1, cl_balance = cl_balance - 1
                        WHERE reg_no = $1 AND month = $2 AND cl_balance > 0
                        """,
                        reg_no, month
                    )
                
                # Log the action
                await conn.execute(
                    """
                    INSERT INTO leave_request_audit_log
                    (leave_request_id, action, performed_by, remarks)
                    VALUES ($1, $2, $3, $4)
                    """,
                    request_id, status.upper(), processed_by, admin_comment or ""
                )
        
        logger.info(f"Leave request {request_id} updated to {status} by {processed_by}")
        return True
    
    async def get_pending_leave_count(self) -> int:
        """Get the count of pending leave requests.
        
        Returns:
            Number of pending leave requests
        """
        count = await self.fetchval(
            "SELECT COUNT(*) FROM leave_requests WHERE status = 'PENDING'"
        )
        return int(count) if count else 0
    
    async def get_casual_leave_history(self, reg_no: str) -> List[Dict[str, Any]]:
        """Get casual leave history for a user.
        
        Args:
            reg_no: Registration number
            
        Returns:
            List of casual leave records
        """
        rows = await self.fetch(
            """
            SELECT * FROM casual_leave
            WHERE reg_no = $1
            ORDER BY leave_date DESC
            """,
            reg_no
        )
        return [dict(row) for row in rows]
    
    async def bulk_create_leave_requests(self, requests: List[Dict[str, Any]]) -> List[int]:
        """Bulk create leave requests.
        
        Args:
            requests: List of leave request dicts
            
        Returns:
            List of created request IDs
        """
        ids = []
        async with self.pool.acquire() as conn:
            async with conn.transaction():
                for req in requests:
                    row = await conn.fetchrow(
                        """
                        INSERT INTO leave_requests
                        (reg_no, leave_type, start_date, end_date, reason, status)
                        VALUES ($1, $2, $3, $4, $5, COALESCE($6, 'PENDING'))
                        RETURNING id
                        """,
                        req.get("reg_no"), req.get("leave_type"),
                        req.get("start_date"), req.get("end_date"),
                        req.get("reason"), req.get("status", "PENDING")
                    )
                    ids.append(row["id"])
        return ids