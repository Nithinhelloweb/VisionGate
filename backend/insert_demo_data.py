"""
Insert demo credentials into PostgreSQL.
Run from the backend directory with the virtual environment activated.
"""

import sys
import os

sys.path.insert(0, os.path.dirname(__file__))

os.environ["PG_HOST"] = "127.0.0.1"
os.environ["PG_USER"] = "attenda"
os.environ["PG_PASSWORD"] = "attenda_password"
os.environ["PG_DB"] = "attenda"

import bcrypt as bcrypt_lib
import pg_adapter

cursor = pg_adapter.cursor


def hash_password(password):
    return bcrypt_lib.hashpw(password.encode("utf-8"), bcrypt_lib.gensalt()).decode(
        "utf-8"
    )


# ---- USERS (admin, hod, staff) ----
demo_users = [
    # Admin
    (
        "admin",
        "admin123",
        "ADMIN001",
        "System Administrator",
        "Administration",
        "admin",
        "system",
    ),
    # HODs
    (
        "hod_cs",
        "hod123",
        "HOD001",
        "Dr. John Smith",
        "Computer Science",
        "hod",
        "admin",
    ),
    ("hod_ec", "hod123", "HOD002", "Dr. Sarah Johnson", "Electronics", "hod", "admin"),
    ("hod_ee", "hod123", "HOD003", "Dr. James Wilson", "Electrical", "hod", "admin"),
    ("hod_me", "hod123", "HOD004", "Dr. Maria Garcia", "Mechanical", "hod", "admin"),
    ("hod_ce", "hod123", "HOD005", "Dr. Robert Chen", "Civil", "hod", "admin"),
    (
        "hod_it",
        "hod123",
        "HOD006",
        "Dr. Priya Sharma",
        "Information Technology",
        "hod",
        "admin",
    ),
    ("hod_ai", "hod123", "HOD007", "Dr. Ahmed Khan", "AI & ML", "hod", "admin"),
    ("hod_ds", "hod123", "HOD008", "Dr. Lisa Park", "Data Science", "hod", "admin"),
    # Staff
    (
        "staff001",
        "staff123",
        "STAFF001",
        "Prof. Michael Brown",
        "Computer Science",
        "staff",
        "hod_cs",
    ),
    (
        "staff002",
        "staff123",
        "STAFF002",
        "Prof. Emily Davis",
        "Computer Science",
        "staff",
        "hod_cs",
    ),
    (
        "staff003",
        "staff123",
        "STAFF003",
        "Prof. Robert Wilson",
        "Electronics",
        "staff",
        "hod_ec",
    ),
    (
        "staff004",
        "staff123",
        "STAFF004",
        "Prof. Anna Lee",
        "Electronics",
        "staff",
        "hod_ec",
    ),
    (
        "staff005",
        "staff123",
        "STAFF005",
        "Prof. David Kim",
        "Electrical",
        "staff",
        "hod_ee",
    ),
    (
        "staff006",
        "staff123",
        "STAFF006",
        "Prof. Sarah Miller",
        "Mechanical",
        "staff",
        "hod_me",
    ),
    (
        "staff007",
        "staff123",
        "STAFF007",
        "Prof. Tom Harris",
        "Civil",
        "staff",
        "hod_ce",
    ),
    (
        "staff008",
        "staff123",
        "STAFF008",
        "Prof. Nina Patel",
        "Information Technology",
        "staff",
        "hod_it",
    ),
    (
        "staff009",
        "staff123",
        "STAFF009",
        "Prof. Alex Turner",
        "AI & ML",
        "staff",
        "hod_ai",
    ),
    (
        "staff010",
        "staff123",
        "STAFF010",
        "Prof. Rachel Green",
        "Data Science",
        "staff",
        "hod_ds",
    ),
]

inserted_users = 0
for username, password, reg_no, name, dept, role, created_by in demo_users:
    cursor.execute("SELECT id FROM users WHERE username = %s", (username,))
    if cursor.fetchone():
        print(f"  SKIP: {username} (already exists)")
        continue
    pw_hash = hash_password(password)
    cursor.execute(
        "INSERT INTO users (username, password_hash, reg_no, name, dept, role, created_by) VALUES (%s, %s, %s, %s, %s, %s, %s)",
        (username, pw_hash, reg_no, name, dept, role, created_by),
    )
    inserted_users += 1
    print(f"  INSERTED: {username} ({role}) - {name}")

print(f"\nUsers: {inserted_users} inserted")

# ---- OTHER STAFF ----
demo_other_staff = [
    (
        "principal",
        "principal123",
        "PRINCIPAL001",
        "Dr. ABC Principal",
        "1970-01-01",
        "principal",
        "Administration",
        "system",
    ),
    (
        "placement_staff",
        "placement123",
        "PLACE001",
        "Mr. XYZ Placement Officer",
        "1985-05-15",
        "placement_staff",
        "Placement Staff",
        "admin",
    ),
    (
        "lab_tech",
        "labtech123",
        "LAB001",
        "Mr. PQR Lab Technician",
        "1990-08-20",
        "lab_technician",
        "Lab Technician",
        "admin",
    ),
    (
        "sys_admin",
        "sysadmin123",
        "SYS001",
        "Mr. LMN System Admin",
        "1988-03-10",
        "system_admin",
        "System Admin",
        "admin",
    ),
    (
        "office_staff",
        "office123",
        "OFFICE001",
        "Ms. Office Staff",
        "1992-07-10",
        "office_staff",
        "Office Staff",
        "admin",
    ),
]

inserted_staff = 0
for username, password, reg_no, name, dob, role, dept, created_by in demo_other_staff:
    cursor.execute("SELECT id FROM other_staff WHERE username = %s", (username,))
    if cursor.fetchone():
        print(f"  SKIP: {username} (already exists)")
        continue
    pw_hash = hash_password(password)
    cursor.execute(
        "INSERT INTO other_staff (username, password_hash, reg_no, name, dob, role, dept, created_by) VALUES (%s, %s, %s, %s, %s, %s, %s, %s)",
        (username, pw_hash, reg_no, name, dob, role, dept, created_by),
    )
    inserted_staff += 1
    print(f"  INSERTED: {username} ({role}) - {name}")

print(f"\nOther Staff: {inserted_staff} inserted")

# ---- DEPARTMENTS ----
departments = [
    "Computer Science",
    "Electronics",
    "Electrical",
    "Mechanical",
    "Civil",
    "Information Technology",
    "AI & ML",
    "Data Science",
]

inserted_depts = 0
for dept in departments:
    cursor.execute("SELECT id FROM departments WHERE name = %s", (dept,))
    if cursor.fetchone():
        continue
    cursor.execute("INSERT INTO departments (name) VALUES (%s)", (dept,))
    inserted_depts += 1

print(f"\nDepartments: {inserted_depts} inserted")

print("\n" + "=" * 60)
print("Demo credentials inserted successfully!")
print("=" * 60)
