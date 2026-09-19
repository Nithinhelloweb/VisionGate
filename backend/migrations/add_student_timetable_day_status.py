import os
import sys

# Ensure parent directory is in sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import pg_adapter

def run():
    print("=== Student Timetable Day Status Migration (PostgreSQL) ===")
    cursor = pg_adapter.cursor
    conn = pg_adapter.conn

    new_cols = [
        ("period_number", "INTEGER"),
        ("is_auto_declared", "BOOLEAN DEFAULT FALSE"),
        ("day_type", "VARCHAR(30) DEFAULT 'NORMAL'"),
    ]
    for col_name, col_def in new_cols:
        try:
            cursor.execute(f"ALTER TABLE student_attendance ADD COLUMN IF NOT EXISTS {col_name} {col_def}")
            print(f"  Added column student_attendance.{col_name}")
        except Exception as e:
            print(f"  Warning {col_name}: {e}")

    cursor.execute("""
        CREATE TABLE IF NOT EXISTS student_academic_day_status (
            id SERIAL PRIMARY KEY,
            student_reg_no VARCHAR(64) NOT NULL,
            date DATE NOT NULL,
            day_type VARCHAR(30) NOT NULL DEFAULT 'NORMAL',
            reason TEXT,
            leave_request_id INTEGER,
            declared_by VARCHAR(64) DEFAULT 'SYSTEM',
            declared_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(student_reg_no, date)
        )
    """)
    print("  Table student_academic_day_status created (or already exists)")

    for idx_sql in [
        "CREATE INDEX IF NOT EXISTS idx_sads_reg_date ON student_academic_day_status (student_reg_no, date)",
        "CREATE INDEX IF NOT EXISTS idx_sads_date ON student_academic_day_status (date, day_type)",
        "CREATE INDEX IF NOT EXISTS idx_stu_att_period ON student_attendance (reg_no, date, period_number)",
    ]:
        try:
            cursor.execute(idx_sql)
            print(f"  Index created: {idx_sql.split('ON ')[1]}")
        except Exception as e:
            print(f"  Index: {e}")

    conn.commit()
    conn.close()
    print("Migration complete.")

if __name__ == "__main__":
    run()
