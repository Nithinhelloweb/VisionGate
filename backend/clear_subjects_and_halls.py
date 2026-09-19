"""
Script to clear all subjects, halls, subject allocations, and timetable records from the database.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

import pg_adapter

def clear_subjects_and_halls():
    cursor = pg_adapter.cursor
    
    tables_to_clear = [
        # Timetable & venue overrides (dependent on subjects/venues)
        "class_venue_overrides",
        "acad_timetable_slots",
        "class_timetable",
        # Faculty allocations (dependent on subjects)
        "acad_faculty_allocation",
        "subject_faculty_allocations",
        # Venues / Halls / Classrooms
        "acad_classrooms",
        "campus_venues",
        # Subjects
        "acad_subjects",
        "department_subjects",
    ]

    print("=" * 60)
    print("Starting clearance of Subjects and Halls...")
    print("=" * 60)

    # Report before counts
    print("\n[INFO] Checking record counts before cleanup:")
    for table in tables_to_clear:
        try:
            cursor.execute(f"SELECT COUNT(*) FROM {table}")
            cnt = cursor.fetchone()[0]
            print(f"  - {table}: {cnt} rows")
        except Exception as e:
            print(f"  - {table}: error reading count ({e})")

    print("\n[ACTION] Truncating tables...")
    for table in tables_to_clear:
        try:
            cursor.execute(f"TRUNCATE TABLE {table} CASCADE;")
            print(f"  [CLEARED] Truncated {table}")
        except Exception as e:
            print(f"  [ERROR] Failed to truncate {table}: {e}")

    # Report after counts
    print("\n[VERIFICATION] Checking record counts after cleanup:")
    all_zero = True
    for table in tables_to_clear:
        try:
            cursor.execute(f"SELECT COUNT(*) FROM {table}")
            cnt = cursor.fetchone()[0]
            print(f"  - {table}: {cnt} rows")
            if cnt != 0:
                all_zero = False
        except Exception as e:
            print(f"  - {table}: error verifying ({e})")
            all_zero = False

    print("\n" + "=" * 60)
    if all_zero:
        print("[SUCCESS] All subjects and halls successfully cleared from database!")
    else:
        print("[WARNING] Some tables may still contain records. Please review above logs.")
    print("=" * 60)

if __name__ == "__main__":
    clear_subjects_and_halls()
