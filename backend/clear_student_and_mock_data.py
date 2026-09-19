"""
Script to clear all student data and mock data from the database.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

os.environ["PG_HOST"] = "127.0.0.1"
os.environ["PG_USER"] = "attenda"
os.environ["PG_PASSWORD"] = "attenda_password"
os.environ["PG_DB"] = "attenda"

import pg_adapter

def clear_all_student_and_mock_data():
    cursor = pg_adapter.cursor
    
    tables_to_clear = [
        "students",
        "student_face_profiles",
        "attendance",
        "kiosk_attendance_logs",
        "kiosk_sessions",
        "staff_student_permissions",
        "face_reregister_requests",
        "multi_user_attendance_sessions",
        "multi_user_attendance_records",
        "daily_attendance_status",
        "morning_attendance",
        "evening_attendance",
        "admin_attendance",
        "fn_attendance",
        "an_attendance",
        "other_staff_attendance",
        "attendance_session_logs",
        "user_location_logs",
        "user_latest_locations",
        "user_locations",
        "leave_requests"
    ]

    print("--- Clearing Student and Mock Data ---")
    for table in tables_to_clear:
        try:
            cursor.execute(f"TRUNCATE TABLE {table} CASCADE;")
            print(f"[CLEARED] Truncated table: {table}")
        except Exception as e:
            print(f"[WARN] Failed to truncate {table}: {e}")

    # Reset face_cache.json
    cache_path = os.path.join(os.path.dirname(__file__), "face_cache.json")
    if os.path.exists(cache_path):
        try:
            with open(cache_path, "w") as f:
                f.write("{}")
            print("[CLEARED] Reset face_cache.json to empty object.")
        except Exception as e:
            print(f"[WARN] Could not reset face_cache.json: {e}")

    print("--- Database Cleanup Completed Successfully ---")

if __name__ == "__main__":
    clear_all_student_and_mock_data()
