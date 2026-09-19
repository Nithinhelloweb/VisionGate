"""
Migration script to add attendance_value column to daily_attendance_status table.
This enables half-day attendance tracking with 0.5 values.
"""
import asyncio
import asyncpg
from datetime import datetime
import sys
import os

# Add parent directory to path to import config
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.config import settings


async def add_attendance_value_column():
    """Add attendance_value column to daily_attendance_status table."""
    
    conn = await asyncpg.connect(
        host=settings.PG_HOST,
        port=settings.PG_PORT,
        database=settings.PG_DB,
        user=settings.PG_USER,
        password=settings.PG_PASSWORD
    )
    
    try:
        print("Starting migration: Add attendance_value column")
        
        # Check if column already exists
        check_column = await conn.fetchval("""
            SELECT column_name 
            FROM information_schema.columns 
            WHERE table_name = 'daily_attendance_status' 
            AND column_name = 'attendance_value'
        """)
        
        if check_column:
            print("Column attendance_value already exists. Skipping column addition.")
        else:
            # Add the attendance_value column
            await conn.execute("""
                ALTER TABLE daily_attendance_status 
                ADD COLUMN attendance_value DECIMAL(3,2) DEFAULT NULL
            """)
            print("Added attendance_value column to daily_attendance_status table")
        
        # Backfill existing records with attendance values
        print("Backfilling existing records with attendance values...")
        
        backfill_result = await conn.execute("""
            UPDATE daily_attendance_status
            SET attendance_value = 
                CASE 
                    WHEN COALESCE(first_half_status, 'Absent') = 'Present' 
                     AND COALESCE(second_half_status, 'Absent') = 'Present' THEN 1.0
                    WHEN COALESCE(first_half_status, 'Absent') = 'Present' 
                      OR COALESCE(second_half_status, 'Absent') = 'Present' THEN 0.5
                    WHEN LOWER(status) = 'present' THEN 1.0
                    WHEN LOWER(status) = 'half_day' THEN 0.5
                    WHEN LOWER(status) = 'holiday' THEN 1.0
                    ELSE 0.0
                END
            WHERE attendance_value IS NULL
        """)
        
        print(f"Backfilled {backfill_result.split()[-1]} records with attendance values")
        
        # Verify the migration
        count = await conn.fetchval("""
            SELECT COUNT(*) FROM daily_attendance_status 
            WHERE attendance_value IS NOT NULL
        """)
        
        total = await conn.fetchval("""
            SELECT COUNT(*) FROM daily_attendance_status
        """)
        
        print(f"Migration complete: {count}/{total} records have attendance_value set")
        
        # Show sample of updated values
        sample = await conn.fetch("""
            SELECT reg_no, date, status, attendance_value, 
                   first_half_status, second_half_status
            FROM daily_attendance_status
            LIMIT 5
        """)
        
        print("\nSample updated records:")
        for row in sample:
            print(f"  {row['reg_no']} | {row['date']} | {row['status']} | "
                  f"value: {row['attendance_value']} | "
                  f"1st: {row['first_half_status']} | 2nd: {row['second_half_status']}")
        
        print("\nMigration completed successfully!")
        
    except Exception as e:
        print(f"Migration failed: {e}")
        raise
    finally:
        await conn.close()


if __name__ == "__main__":
    asyncio.run(add_attendance_value_column())
