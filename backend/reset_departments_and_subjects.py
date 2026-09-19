"""
Reset and seed single clean record per Department and Subject in Attenda database.
"""

import sys
import os
from datetime import datetime

sys.path.insert(0, os.path.dirname(__file__))
import pg_adapter

cursor = pg_adapter.cursor

def run_reset():
    print("=" * 60)
    print("Starting clean reset of Departments and Subjects...")
    print("=" * 60)

    # 1. Clear existing records in departments and subjects
    print("1. Clearing tables: department_subjects, subject_faculty_allocations, acad_subjects, acad_departments, departments...")
    cursor.execute("DELETE FROM department_subjects")
    cursor.execute("DELETE FROM subject_faculty_allocations")
    cursor.execute("DELETE FROM acad_subjects")
    cursor.execute("DELETE FROM acad_departments")
    cursor.execute("DELETE FROM departments")

    # 2. Define Departments list
    departments_list = [
        ("CSE", "Computer Science and Engineering", "Dr. John Smith", "hod_cse@college.edu", "9876543201"),
        ("ECE", "Electronics and Communication Engineering", "Dr. Sarah Johnson", "hod_ece@college.edu", "9876543202"),
        ("EEE", "Electrical and Electronics Engineering", "Dr. James Wilson", "hod_eee@college.edu", "9876543203"),
        ("MECH", "Mechanical Engineering", "Dr. Maria Garcia", "hod_mech@college.edu", "9876543204"),
        ("CIVIL", "Civil Engineering", "Dr. Robert Chen", "hod_civil@college.edu", "9876543205"),
        ("IT", "Information Technology", "Dr. Priya Sharma", "hod_it@college.edu", "9876543206"),
        ("AI & ML", "Artificial Intelligence and Machine Learning", "Dr. Ahmed Khan", "hod_aiml@college.edu", "9876543207"),
        ("Data Science", "Data Science and Analytics", "Dr. Lisa Park", "hod_ds@college.edu", "9876543208"),
        ("Administration", "Administration Department", "System Administrator", "admin@college.edu", "9876543200"),
    ]

    print("\n2. Inserting 1 record for each department...")
    dept_id_map = {}
    for code, full_name, hod, email, phone in departments_list:
        cursor.execute("INSERT INTO departments (name) VALUES (?) RETURNING id", (code,))
        res = cursor.fetchone()
        dept_db_id = res[0] if res else None

        cursor.execute(
            """
            INSERT INTO acad_departments (code, name, hod_name, hod_email, hod_phone, established_year, status)
            VALUES (?, ?, ?, ?, ?, 2008, 'active')
            RETURNING id
            """,
            (code, full_name, hod, email, phone)
        )
        acad_res = cursor.fetchone()
        acad_dept_id = acad_res[0] if acad_res else dept_db_id
        dept_id_map[code] = acad_dept_id
        print(f"  [OK] Department added: {code} (ID: {dept_db_id})")

    print("\n" + "=" * 60)
    print("Verification:")
    cursor.execute("SELECT id, name FROM departments ORDER BY id")
    print(f"Departments Count: {len(cursor.fetchall())}")
    cursor.execute("SELECT COUNT(*) FROM department_subjects")
    print(f"Department Subjects Count: {cursor.fetchone()[0]}")
    cursor.execute("SELECT COUNT(*) FROM subject_faculty_allocations")
    print(f"Subject Faculty Allocations Count: {cursor.fetchone()[0]}")
    print("=" * 60)
    print("Departments reset successfully (all subject tables remain clean and empty)!")

if __name__ == "__main__":
    run_reset()
