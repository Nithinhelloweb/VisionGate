"""
Backfill script for attendance values.
This script recalculates attendance values for all existing records based on 
current half-day statuses and overall status.
"""
import asyncio
import asyncpg
from datetime import datetime
import sys
import os

# Add parent directory to path to import config
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.config import settings


async def backfill_attendance_values():
    """Recalculate attendance values for all existing records."""
    
    conn = await asyncpg.connect(
        host=settings.PG_HOST,
        port=settings.PG_PORT,
        database=settings.PG_DB,
        user=settings.PG_USER,
        password=settings.PG_PASSWORD
    )
    
    try:
        print("Starting backfill: Recalculate attendance values for all records")
        
        # Get total records count
        total = await conn.fetchval("""
            SELECT COUNT(*) FROM daily_attendance_status
        """)
        print(f"Total records to process: {total}")
        
        # Recalculate all attendance values
        print("Recalculating attendance values...")
        
        result = await conn.execute("""
            UPDATE daily_attendance_status
            SET attendance_value = 
                CASE 
                    -- Both halves present = 1.0
                    WHEN COALESCE(first_half_status, 'Absent') = 'Present' 
                     AND COALESCE(second_half_status, 'Absent') = 'Present' THEN 1.0
                    -- One half present = 0.5
                    WHEN COALESCE(first_half_status, 'Absent') = 'Present' 
                      OR COALESCE(second_half_status, 'Absent') = 'Present' THEN 0.5
                    -- Overall present status without half info = 1.0
                    WHEN LOWER(status) = 'present' 
                      AND first_half_status IS NULL 
                      AND second_half_status IS NULL THEN 1.0
                    -- Half day status = 0.5
                    WHEN LOWER(status) = 'half_day' THEN 0.5
                    -- Holiday = 1.0
                    WHEN LOWER(status) = 'holiday' THEN 1.0
                    -- Leave and absent = 0.0
                    ELSE 0.0
                END,
                updated_at = NOW()
        """)
        
        updated_count = result.split()[-1]
        print(f"✓ Updated {updated_count} records")
        
        # Verify the backfill with statistics
        stats = await conn.fetchrow("""
            SELECT 
                COUNT(*) FILTER (WHERE attendance_value = 1.0) as full_days,
                COUNT(*) FILTER (WHERE attendance_value = 0.5) as half_days,
                COUNT(*) FILTER (WHERE attendance_value = 0.0) as zero_days,
                COUNT(*) FILTER (WHERE attendance_value IS NULL) as null_days
            FROM daily_attendance_status
        """)
        
        print("\nBackfill Statistics:")
        print(f"  Full days (1.0): {stats['full_days']}")
        print(f"  Half days (0.5): {stats['half_days']}")
        print(f"  Zero days (0.0): {stats['zero_days']}")
        print(f"  NULL values: {stats['null_days']}")
        
        # Show breakdown by status
        status_breakdown = await conn.fetch("""
            SELECT 
                status,
                COUNT(*) as count,
                ROUND(AVG(attendance_value)::numeric, 2) as avg_value
            FROM daily_attendance_status
            GROUP BY status
            ORDER BY count DESC
        """)
        
        print("\nBreakdown by status:")
        for row in status_breakdown:
            print(f"  {row['status']}: {row['count']} records (avg value: {row['avg_value']})")
        
        # Show sample records
        sample = await conn.fetch("""
            SELECT reg_no, date, status, attendance_value, 
                   first_half_status, second_half_status
            FROM daily_attendance_status
            ORDER BY date DESC
            LIMIT 10
        """)
        
        print("\nSample records:")
        for row in sample:
            print(f"  {row['reg_no']} | {row['date']} | {row['status']} | "
                  f"value: {row['attendance_value']} | "
                  f"1st: {row['first_half_status']} | 2nd: {row['second_half_status']}")
        
        print("\n✓ Backfill completed successfully!")
        
    except Exception as e:
        print(f"✗ Backfill failed: {e}")
        raise
    finally:
        await conn.close()


if __name__ == "__main__":
    asyncio.run(backfill_attendance_values())
