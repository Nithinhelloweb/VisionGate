"""
Seed database script for VisionGate / Attenda.
Populates departments, staff members across departments, other staff, and students.
"""

import sys
import os

sys.path.insert(0, os.path.dirname(__file__))

import json
import bcrypt
import pg_adapter

cursor = pg_adapter.cursor


def hash_pw(pw):
    return bcrypt.hashpw(pw.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')


def run_seed():
    print("Starting database seeding...")

    # 1. Seed Departments
    depts = [
        'CSE',
        'ECE',
        'EEE',
        'MECH',
        'CIVIL',
        'IT',
        'AI & ML',
        'Data Science',
        'Administration',
    ]
    inserted_depts = 0
    for d in depts:
        try:
            cursor.execute('SELECT id FROM departments WHERE name = %s OR dept_name = %s', (d, d))
            if not cursor.fetchone():
                cursor.execute('INSERT INTO departments (name, dept_name) VALUES (%s, %s)', (d, d))
                inserted_depts += 1
        except Exception as e:
            print(f"Error seeding dept {d}: {e}")
    pg_adapter.conn.commit()
    print(f"Departments: {inserted_depts} inserted.")

    # 2. Seed Users (Admin, HODs, Staff)
    users = [
        ('admin', 'admin123', 'ADMIN001', 'System Administrator', 'Administration', 'admin', 'system'),
        ('demo', 'demo123', 'STAFF_0002', 'Prof. Demo User', 'CSE', 'staff', 'admin'),
        ('demoo', 'demoo123', 'STAFF_0001', 'Prof. Demoo User', 'CSE', 'staff', 'admin'),
        ('hodcse', 'hod123', 'HOD_0001', 'Dr. John Smith', 'CSE', 'hod', 'admin'),
        ('hod_cs', 'hod123', 'HOD001', 'Dr. John Smith', 'CSE', 'hod', 'admin'),
        ('hod_ec', 'hod123', 'HOD002', 'Dr. Sarah Johnson', 'ECE', 'hod', 'admin'),
        ('hod_ee', 'hod123', 'HOD003', 'Dr. James Wilson', 'EEE', 'hod', 'admin'),
        ('hod_me', 'hod123', 'HOD004', 'Dr. Maria Garcia', 'MECH', 'hod', 'admin'),
        ('hod_ce', 'hod123', 'HOD005', 'Dr. Robert Chen', 'CIVIL', 'hod', 'admin'),
        ('hod_it', 'hod123', 'HOD006', 'Dr. Priya Sharma', 'IT', 'hod', 'admin'),
        ('hod_ai', 'hod123', 'HOD007', 'Dr. Ahmed Khan', 'AI & ML', 'hod', 'admin'),
        ('hod_ds', 'hod123', 'HOD008', 'Dr. Lisa Park', 'Data Science', 'hod', 'admin'),
        ('staff001', 'staff123', 'STAFF001', 'Prof. Michael Brown', 'CSE', 'staff', 'hod_cs'),
        ('staff002', 'staff123', 'STAFF002', 'Prof. Emily Davis', 'CSE', 'staff', 'hod_cs'),
        ('staff003', 'staff123', 'STAFF003', 'Prof. Robert Wilson', 'ECE', 'staff', 'hod_ec'),
        ('staff004', 'staff123', 'STAFF004', 'Prof. Anna Lee', 'ECE', 'staff', 'hod_ec'),
        ('staff005', 'staff123', 'STAFF005', 'Prof. David Kim', 'EEE', 'staff', 'hod_ee'),
        ('staff006', 'staff123', 'STAFF006', 'Prof. Sarah Miller', 'MECH', 'staff', 'hod_me'),
        ('staff007', 'staff123', 'STAFF007', 'Prof. Tom Harris', 'CIVIL', 'staff', 'hod_ce'),
        ('staff008', 'staff123', 'STAFF008', 'Prof. Nina Patel', 'IT', 'staff', 'hod_it'),
        ('staff009', 'staff123', 'STAFF009', 'Prof. Alex Turner', 'AI & ML', 'staff', 'hod_ai'),
        ('staff010', 'staff123', 'STAFF010', 'Prof. Rachel Green', 'Data Science', 'staff', 'hod_ds'),
    ]

    inserted_users = 0
    for uname, pw, reg, name, dept, role, cb in users:
        try:
            cursor.execute('SELECT id FROM users WHERE username = ? OR LOWER(reg_no) = LOWER(?)', (uname, reg))
            if not cursor.fetchone():
                h = hash_pw(pw)
                cursor.execute(
                    'INSERT INTO users (username, password_hash, reg_no, name, dept, role, created_by) VALUES (?, ?, ?, ?, ?, ?, ?)',
                    (uname, h, reg, name, dept, role, cb)
                )
                inserted_users += 1
        except Exception as e:
            print(f"Error seeding user {uname}: {e}")
    print(f"Users: {inserted_users} inserted.")

    # 3. Seed Other Staff
    other_staff = [
        ('principal', 'principal123', 'PRINCIPAL001', 'Dr. ABC Principal', '1970-01-01', 'principal', 'Administration', 'system'),
        ('placement_staff', 'placement123', 'PLACE001', 'Mr. XYZ Placement Officer', '1985-05-15', 'placement_staff', 'Placement Staff', 'admin'),
        ('lab_tech', 'labtech123', 'LAB001', 'Mr. PQR Lab Technician', '1990-08-20', 'lab_technician', 'CSE', 'admin'),
        ('sys_admin', 'sysadmin123', 'SYS001', 'Mr. LMN System Admin', '1988-03-10', 'system_admin', 'System Admin', 'admin'),
        ('office_staff', 'office123', 'OFFICE001', 'Ms. Office Staff', '1992-07-10', 'office_staff', 'Office Staff', 'admin'),
    ]
    inserted_other = 0
    for uname, pw, reg, name, dob, role, dept, cb in other_staff:
        try:
            cursor.execute('SELECT id FROM other_staff WHERE username = ? OR LOWER(reg_no) = LOWER(?)', (uname, reg))
            if not cursor.fetchone():
                h = hash_pw(pw)
                cursor.execute(
                    'INSERT INTO other_staff (username, password_hash, reg_no, name, dob, role, dept, created_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
                    (uname, h, reg, name, dob, role, dept, cb)
                )
                inserted_other += 1
        except Exception as e:
            print(f"Error seeding other_staff {uname}: {e}")
    print(f"Other staff: {inserted_other} inserted.")

    # 4. Seed Students & Student Face Profiles
    students_data = [
        ('714024104145', 'NITHIN K V', 'CSE', 'STAFF_0002'),
        ('714024104146', 'Aravind Swamy', 'CSE', 'STAFF_0002'),
        ('714024104147', 'Bhavana R', 'CSE', 'STAFF_0001'),
        ('138', 'Naveen Kumar', 'CSE', 'STAFF_0001'),
        ('714024201001', 'Kavitha M', 'ECE', 'STAFF003'),
        ('714024201002', 'Karthik S', 'ECE', 'STAFF004'),
        ('714024301001', 'Dinesh Kumar', 'EEE', 'STAFF005'),
        ('714024401001', 'Manish V', 'MECH', 'STAFF006'),
        ('714024501001', 'Pooja R', 'CIVIL', 'STAFF007'),
        ('714024601001', 'Rahul Dravid', 'IT', 'STAFF008'),
        ('714024701001', 'Siddharth M', 'AI & ML', 'STAFF009'),
        ('714024801001', 'Tejaswini K', 'Data Science', 'STAFF010'),
    ]
    inserted_students = 0
    default_pw_hash = hash_pw('student123')
    # Ensure all columns exist on students table
    student_cols_migration = [
        "ALTER TABLE students ADD COLUMN IF NOT EXISTS roll_no VARCHAR(64)",
        "ALTER TABLE students ADD COLUMN IF NOT EXISTS email VARCHAR(160)",
        "ALTER TABLE students ADD COLUMN IF NOT EXISTS phone_number VARCHAR(20)",
        "ALTER TABLE students ADD COLUMN IF NOT EXISTS dob DATE DEFAULT '2004-01-01'",
        "ALTER TABLE students ADD COLUMN IF NOT EXISTS gender VARCHAR(10) DEFAULT 'Male'",
        "ALTER TABLE students ADD COLUMN IF NOT EXISTS blood_group VARCHAR(10)",
        "ALTER TABLE students ADD COLUMN IF NOT EXISTS degree VARCHAR(50) DEFAULT 'B.E.'",
        "ALTER TABLE students ADD COLUMN IF NOT EXISTS batch VARCHAR(20) DEFAULT '2022-2026'",
        "ALTER TABLE students ADD COLUMN IF NOT EXISTS year_of_study INT DEFAULT 1",
        "ALTER TABLE students ADD COLUMN IF NOT EXISTS semester INT DEFAULT 1",
        "ALTER TABLE students ADD COLUMN IF NOT EXISTS section VARCHAR(10) DEFAULT 'A'",
        "ALTER TABLE students ADD COLUMN IF NOT EXISTS quota VARCHAR(20) DEFAULT 'Govt'",
        "ALTER TABLE students ADD COLUMN IF NOT EXISTS mentor_staff_reg_no VARCHAR(64)",
        "ALTER TABLE students ADD COLUMN IF NOT EXISTS father_name VARCHAR(160)",
        "ALTER TABLE students ADD COLUMN IF NOT EXISTS mother_name VARCHAR(160)",
        "ALTER TABLE students ADD COLUMN IF NOT EXISTS parent_phone VARCHAR(20) DEFAULT '9876543210'",
        "ALTER TABLE students ADD COLUMN IF NOT EXISTS parent_email VARCHAR(160)",
        "ALTER TABLE students ADD COLUMN IF NOT EXISTS emergency_contact VARCHAR(20)",
        "ALTER TABLE students ADD COLUMN IF NOT EXISTS permanent_address TEXT",
        "ALTER TABLE students ADD COLUMN IF NOT EXISTS city VARCHAR(100)",
        "ALTER TABLE students ADD COLUMN IF NOT EXISTS state VARCHAR(100) DEFAULT 'Tamil Nadu'",
        "ALTER TABLE students ADD COLUMN IF NOT EXISTS pincode VARCHAR(10)",
        "ALTER TABLE students ADD COLUMN IF NOT EXISTS password_hash TEXT DEFAULT ''",
        "ALTER TABLE students ADD COLUMN IF NOT EXISTS first_time_login BOOLEAN DEFAULT TRUE",
        "ALTER TABLE students ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT TRUE",
        "ALTER TABLE students ADD COLUMN IF NOT EXISTS suspended BOOLEAN DEFAULT FALSE",
        "ALTER TABLE students ADD COLUMN IF NOT EXISTS can_reregister BOOLEAN DEFAULT FALSE",
        "ALTER TABLE students ADD COLUMN IF NOT EXISTS current_device_id VARCHAR(255)",
        "ALTER TABLE students ADD COLUMN IF NOT EXISTS registered_by VARCHAR(64) DEFAULT 'SYSTEM'",
        "ALTER TABLE students ADD COLUMN IF NOT EXISTS registered_role VARCHAR(20) DEFAULT 'admin'",
    ]
    for alt in student_cols_migration:
        try:
            cursor.execute(alt)
        except Exception:
            pass

    for reg, name, dept, reg_by in students_data:
        try:
            cursor.execute('SELECT reg_no FROM student_face_profiles WHERE LOWER(reg_no) = LOWER(?)', (reg,))
            if not cursor.fetchone():
                cursor.execute(
                    'INSERT INTO student_face_profiles (reg_no, name, dept, registered_by, embeddings) VALUES (?, ?, ?, ?, ?)',
                    (reg, name, dept, reg_by, '[]')
                )
                inserted_students += 1

            cursor.execute('SELECT reg_no FROM students WHERE LOWER(reg_no) = LOWER(?)', (reg,))
            if not cursor.fetchone():
                cursor.execute(
                    '''
                    INSERT INTO students (
                        reg_no, roll_no, name, email, phone_number, dob, gender, blood_group,
                        degree, dept, batch, year, year_of_study, semester, section, quota, mentor_staff_reg_no,
                        father_name, mother_name, parent_phone, parent_email, emergency_contact,
                        permanent_address, city, state, pincode, password_hash, first_time_login,
                        registered_by, registered_role
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ''',
                    (
                        reg, f"R_{reg[-4:]}", name, f"{reg.lower()}@college.edu", "9876543210",
                        "2004-06-15", "Male", "O+", "B.E.", dept, "2022-2026", 3, 3, 6, "A", "Govt", reg_by,
                        "Parent Name", "Mother Name", "9876543210", "parent@gmail.com", "9876543210",
                        "123 University Campus Road", "Coimbatore", "Tamil Nadu", "641001",
                        default_pw_hash, True, reg_by, "staff"
                    )
                )
        except Exception as e:
            print(f"Error seeding student {reg}: {e}")
    print(f"Students & Face Profiles: {inserted_students} inserted.")

    # 5. Seed Academic Period Configs
    depts = ['CSE', 'ECE', 'EEE', 'MECH', 'CIVIL', 'IT', 'AI & ML', 'Data Science']
    default_breaks = json.dumps([
        {"title": "Tea Break", "after_period": 2, "duration_mins": 15},
        {"title": "Lunch Break", "after_period": 4, "duration_mins": 45},
    ])
    default_days = json.dumps(["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"])

    for d in depts:
        try:
            cursor.execute("SELECT id FROM academic_period_configs WHERE LOWER(dept) = LOWER(?)", (d,))
            if not cursor.fetchone():
                cursor.execute(
                    """
                    INSERT INTO academic_period_configs (
                        dept, semester_type, start_time, total_periods, period_duration_mins,
                        working_days, breaks_json, updated_by
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (d, 'all', '08:45', 7, 50, default_days, default_breaks, 'SYSTEM')
                )
        except Exception as e:
            pass

    # 6. Seed Class Advisors
    advisors_data = [
        ('CSE', '2022-2026', 3, 6, 'A', 'STAFF_0002', 'primary', '2024-2025'),
        ('CSE', '2022-2026', 3, 6, 'A', 'STAFF_0001', 'assistant', '2024-2025'),
        ('CSE', '2022-2026', 3, 6, 'B', 'STAFF_0001', 'primary', '2024-2025'),
        ('ECE', '2022-2026', 3, 6, 'A', 'STAFF003', 'primary', '2024-2025'),
        ('IT', '2022-2026', 3, 6, 'A', 'STAFF008', 'primary', '2024-2025'),
    ]
    for dept, batch, yr, sem, sec, staff_reg, adv_type, ac_yr in advisors_data:
        try:
            cursor.execute(
                "SELECT id FROM class_advisors WHERE LOWER(dept) = LOWER(?) AND batch = ? AND semester = ? AND LOWER(section) = LOWER(?) AND advisor_type = ?",
                (dept, batch, sem, sec, adv_type)
            )
            if not cursor.fetchone():
                cursor.execute(
                    """
                    INSERT INTO class_advisors (
                        dept, batch, year_of_study, semester, section, staff_reg_no,
                        advisor_type, academic_year, assigned_by, assigned_role
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'SYSTEM', 'admin')
                    """,
                    (dept, batch, yr, sem, sec, staff_reg, adv_type, ac_yr)
                )
        except Exception:
            pass

    print("Academic period configs and class advisors seeded successfully!")
    print("Database seeding completed successfully!")


if __name__ == '__main__':
    run_seed()


