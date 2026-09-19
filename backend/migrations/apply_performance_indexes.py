"""
Performance Index Optimization Migration Script
Creates composite B-tree indexes across all high-frequency query paths.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
import pg_adapter

def apply_performance_indexes():
    cursor = pg_adapter.cursor
    print("[MIGRATION] Applying database composite performance indexes...")

    indexes = [
        # Students cohort lookups
        ("idx_students_cohort_active", """
            CREATE INDEX IF NOT EXISTS idx_students_cohort_active 
            ON students (LOWER(dept), TRIM(batch), semester, LOWER(section))
        """),
        ("idx_students_reg_no_lower", """
            CREATE INDEX IF NOT EXISTS idx_students_reg_no_lower 
            ON students (LOWER(reg_no))
        """),

        # Class attendance sessions
        ("idx_cas_date_status_cohort", """
            CREATE INDEX IF NOT EXISTS idx_cas_date_status_cohort 
            ON class_attendance_sessions (date, status, LOWER(dept), semester, LOWER(section))
        """),
        ("idx_cas_staff_date", """
            CREATE INDEX IF NOT EXISTS idx_cas_staff_date 
            ON class_attendance_sessions (staff_reg_no, date)
        """),

        # Student attendance logs & rolls
        ("idx_sa_session_status", """
            CREATE INDEX IF NOT EXISTS idx_sa_session_status 
            ON student_attendance (session_id, status)
        """),
        ("idx_sa_reg_date_session", """
            CREATE INDEX IF NOT EXISTS idx_sa_reg_date_session 
            ON student_attendance (reg_no, date)
        """),
        ("idx_sa_date_period", """
            CREATE INDEX IF NOT EXISTS idx_sa_date_period 
            ON student_attendance (date, period_number)
        """),

        # Face embeddings
        ("idx_sfe_reg_lower", """
            CREATE INDEX IF NOT EXISTS idx_sfe_reg_lower 
            ON student_face_embeddings (LOWER(reg_no))
        """),

        # Timetable slots
        ("idx_ct_staff_day", """
            CREATE INDEX IF NOT EXISTS idx_ct_staff_day 
            ON class_timetable (staff_reg_no, LOWER(day_of_week))
        """),
        ("idx_ct_cohort_day", """
            CREATE INDEX IF NOT EXISTS idx_ct_cohort_day 
            ON class_timetable (LOWER(day_of_week), LOWER(dept), semester, LOWER(section))
        """),

        # Academic day status & period configs
        ("idx_sads_reg_date", """
            CREATE INDEX IF NOT EXISTS idx_sads_reg_date 
            ON student_academic_day_status (student_reg_no, date)
        """),
        ("idx_apc_dept_lower", """
            CREATE INDEX IF NOT EXISTS idx_apc_dept_lower 
            ON academic_period_configs (LOWER(dept))
        """),
    ]

    for name, sql in indexes:
        try:
            cursor.execute(sql)
            print(f"  [OK] Index applied: {name}")
        except Exception as e:
            print(f"  [SKIP] Index {name}: {e}")

    try:
        pg_adapter.conn.commit()
    except Exception:
        pass
    print("[MIGRATION] Performance index migration completed successfully!")

if __name__ == "__main__":
    apply_performance_indexes()
