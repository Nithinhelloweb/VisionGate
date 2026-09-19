"""
VisionGate / Attenda - Verified Database Cleanup Script
Target: Clear all attendance, session, telemetry, and transactional activity up to 19.09.2026.
Preserves: Master directory (Students, Staff, Face Embeddings), Configurations, Timetables.
"""

import os
import sys
import psycopg2
from psycopg2 import sql

def run_cleanup():
    db_config = {
        "host": os.environ.get("PG_HOST", "127.0.0.1"),
        "port": int(os.environ.get("PG_PORT", "5432")),
        "user": os.environ.get("PG_USER", "attenda"),
        "password": os.environ.get("PG_PASSWORD", "attenda_password"),
        "database": os.environ.get("PG_DB", "attenda"),
    }

    print("=" * 80)
    print(" VISIONGATE / ATTENDA — SYSTEM DATA CLEANUP (UP TO 19.09.2026)")
    print(f" Target Database: {db_config['database']} on {db_config['host']}:{db_config['port']}")
    print("=" * 80)

    conn = psycopg2.connect(**db_config)
    conn.autocommit = False
    cur = conn.cursor()

    # Tables to clear in strict foreign key order
    tables_to_clear = [
        # Dependent child tables first
        "student_leave_od_action_history",
        "student_leave_od_requests",
        "staff_leave_timetable_assignments",
        "staff_leave_audit_log",
        "staff_leave_requests",
        "substitute_assignments",
        "comp_off_accrual",
        # Attendance & session tables
        "student_attendance",
        "attendance",
        "daily_attendance_status",
        "morning_attendance",
        "evening_attendance",
        "class_attendance_sessions",
        "attendance_corrections",
        "student_academic_day_status",
        # Location & telemetry tables
        "user_location_logs",
        "user_latest_locations",
        # Operational biometric logs & samples
        "face_training_runs",
        "face_reregister_requests",
        "face_embedding_samples",
        # Notifications, feedback & audit trails
        "notifications_all_roles",
        "admin_notifications",
        "audit_log",
        "student_feedback_grievances",
    ]

    master_tables_to_verify = [
        ("students", 499),
        ("student_face_embeddings", 505),
        ("users", 9),
        ("other_staff", 5),
        ("departments", 9),
        ("acad_departments", 9),
        ("class_timetable", 34),
        ("subject_faculty_allocations", 11),
        ("geo_fence_coordinates_v2", 37),
        ("system_config", 9),
    ]

    try:
        print("\n[*] Phase 1: Capturing Pre-Cleanup Row Counts...")
        before_counts = {}
        total_rows_to_clear = 0
        for table in tables_to_clear:
            cur.execute(sql.SQL("SELECT count(*) FROM {}").format(sql.Identifier(table)))
            cnt = cur.fetchone()[0]
            before_counts[table] = cnt
            total_rows_to_clear += cnt
            print(f"    - {table:<36}: {cnt:>6} rows")
        print(f"\n--> Total transactional rows identified for removal: {total_rows_to_clear}")

        print("\n[*] Phase 2: Executing Safe Deletions within Database Transaction...")
        for table in tables_to_clear:
            cur.execute(sql.SQL("DELETE FROM {}").format(sql.Identifier(table)))
            deleted = cur.rowcount
            print(f"    [CLEARED] {table:<34}: deleted {deleted:>6} rows")

        # Normalize leave usage ledger to reflect cleared leave requests
        print("\n[*] Phase 3: Normalizing Leave Ledger Usage...")
        cur.execute("UPDATE casual_leave SET cl_used_current_month = 0 WHERE cl_used_current_month > 0;")
        print(f"    [RESET] Reset casual_leave used balance to 0 for {cur.rowcount} entries")
        cur.execute("UPDATE casual_leave SET current_month_cl_available = 1 WHERE reg_no = 'STAFF_0001' AND current_month = '2026-08';")
        print("    [RESET] Restored available casual leave balance for STAFF_0001")

        print("\n[*] Phase 4: Verifying Post-Cleanup State...")
        all_cleared = True
        for table in tables_to_clear:
            cur.execute(sql.SQL("SELECT count(*) FROM {}").format(sql.Identifier(table)))
            post_cnt = cur.fetchone()[0]
            if post_cnt != 0:
                print(f"    [FAIL] Table {table} still has {post_cnt} rows!")
                all_cleared = False
            else:
                print(f"    [PASS] {table:<36}: 0 rows remaining")

        if not all_cleared:
            raise RuntimeError("Post-cleanup count verification failed. Rolling back transaction.")

        print("\n[*] Phase 5: Verifying Master Directory & Config Preservation...")
        all_preserved = True
        for table, expected_cnt in master_tables_to_verify:
            cur.execute(sql.SQL("SELECT count(*) FROM {}").format(sql.Identifier(table)))
            actual_cnt = cur.fetchone()[0]
            if actual_cnt != expected_cnt:
                print(f"    [WARN] Master table {table}: expected {expected_cnt}, found {actual_cnt}!")
                all_preserved = False
            else:
                print(f"    [PRESERVED] {table:<30}: {actual_cnt:>4} rows (100% intact)")

        if not all_preserved:
            raise RuntimeError("Master data integrity check failed. Rolling back transaction.")

        # Commit transaction
        conn.commit()
        print("\n" + "=" * 80)
        print(" TRANSACTION COMMITTED SUCCESSFULLY. DATABASE CLEANUP 100% VERIFIED.")
        print(f" Total rows deleted: {total_rows_to_clear}")
        print(" All student accounts, staff logins, biometrics, and configurations remain intact.")
        print("=" * 80 + "\n")

    except Exception as e:
        conn.rollback()
        print(f"\n[ERROR] Cleanup failed: {e}")
        print("--> Transaction rolled back. Zero changes committed to database.")
        sys.exit(1)
    finally:
        cur.close()
        conn.close()

if __name__ == "__main__":
    run_cleanup()
