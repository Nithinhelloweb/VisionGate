import asyncio
import json
import io
import openpyxl
from fastapi import UploadFile, Request
from starlette.datastructures import Headers
import main
import pg_adapter

class MockRequest:
    def __init__(self, headers=None):
        self.headers = Headers(headers or {})

original_verify = main.verify_admin_token
main.verify_admin_token = lambda req: {"username": "admin", "role": "admin"}

cursor = pg_adapter.cursor

async def run_tests():
    # ── DEPARTMENTS TESTS ──
    print("Testing Department JSON bulk upload...")
    cursor.execute("DELETE FROM departments WHERE name IN ('Test Dept JSON 1', 'Test Dept JSON 2', 'Test Dept Admin')")
    
    test_json = [
        {"name": "Test Dept JSON 1"},
        {"name": "Test Dept JSON 2"},
        {"name": "Test Dept JSON 1"}
    ]
    
    json_bytes = json.dumps(test_json).encode("utf-8")
    json_file = UploadFile(
        file=io.BytesIO(json_bytes),
        filename="test.json",
        headers=Headers({"content-type": "application/json"})
    )
    
    request = MockRequest()
    result = await main.admin_bulk_upload_departments(request, json_file)
    print("Dept JSON Upload Result:", result)
    assert result["success"] is True
    assert "Test Dept JSON 1" in result["inserted"]
    assert "Test Dept JSON 2" in result["inserted"]
    
    print("Testing Department Excel bulk upload...")
    cursor.execute("DELETE FROM departments WHERE name IN ('Test Dept Excel 1', 'Test Dept Excel 2')")
    
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.append(["Department Name"])
    ws.append(["Test Dept Excel 1"])
    ws.append(["Test Dept Excel 2"])
    
    excel_bytes_io = io.BytesIO()
    wb.save(excel_bytes_io)
    excel_bytes_io.seek(0)
    
    excel_file = UploadFile(
        file=excel_bytes_io,
        filename="test.xlsx",
        headers=Headers({"content-type": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"})
    )
    
    result = await main.admin_bulk_upload_departments(request, excel_file)
    print("Dept Excel Upload Result:", result)
    assert result["success"] is True
    assert "Test Dept Excel 1" in result["inserted"]
    assert "Test Dept Excel 2" in result["inserted"]

    # ── USERS TESTS ──
    cursor.execute("INSERT INTO departments (name) VALUES ('Test Dept Admin')")
    
    print("Testing Users JSON bulk upload...")
    cursor.execute("DELETE FROM users WHERE username IN ('testuser1', 'testuser2')")
    
    users_json = [
        {
            "username": "testuser1",
            "name": "Test User 1",
            "dept": "Test Dept Admin",
            "role": "staff",
            "password": "mypassword"
        },
        {
            "username": "testuser2",
            "name": "Test User 2",
            "dept": "Test Dept Admin",
            "role": "hod",
            "password": "mypassword2"
        }
    ]
    
    user_json_bytes = json.dumps(users_json).encode("utf-8")
    user_json_file = UploadFile(
        file=io.BytesIO(user_json_bytes),
        filename="users.json",
        headers=Headers({"content-type": "application/json"})
    )
    
    result = await main.admin_bulk_upload_users(request, user_json_file)
    print("Users JSON Upload Result:", result)
    assert result["success"] is True
    
    created_users = [u["username"] for u in result["data"]["created_users"]]
    assert "testuser1" in created_users
    assert "testuser2" in created_users
    
    print("Testing Users Excel bulk upload...")
    cursor.execute("DELETE FROM users WHERE username IN ('testuser3', 'testuser4')")
    
    wb_users = openpyxl.Workbook()
    ws_users = wb_users.active
    ws_users.append(["Username", "Name", "Department", "Role", "Password"])
    ws_users.append(["testuser3", "Test User 3", "Test Dept Admin", "staff", "pwd123"])
    ws_users.append(["testuser4", "Test User 4", "Test Dept Admin", "staff", "pwd456"])
    
    excel_users_bytes_io = io.BytesIO()
    wb_users.save(excel_users_bytes_io)
    excel_users_bytes_io.seek(0)
    
    user_excel_file = UploadFile(
        file=excel_users_bytes_io,
        filename="users.xlsx",
        headers=Headers({"content-type": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"})
    )
    
    result = await main.admin_bulk_upload_users(request, user_excel_file)
    print("Users Excel Upload Result:", result)
    assert result["success"] is True
    created_users = [u["username"] for u in result["data"]["created_users"]]
    assert "testuser3" in created_users
    assert "testuser4" in created_users
    
    # ── AUTO-REDIRECT TEST ──
    print("Testing auto-redirection of user JSON to department bulk upload endpoint...")
    cursor.execute("DELETE FROM users WHERE username = 'testredirect'")
    cursor.execute("DELETE FROM departments WHERE name = 'Redirected Dept'")
    
    redirect_json = [
        {
            "username": "testredirect",
            "name": "Test Redirect User",
            "dept": "Redirected Dept",
            "role": "staff",
            "password": "pwd"
        }
    ]
    
    redirect_bytes = json.dumps(redirect_json).encode("utf-8")
    redirect_file = UploadFile(
        file=io.BytesIO(redirect_bytes),
        filename="users_uploaded_to_dept.json",
        headers=Headers({"content-type": "application/json"})
    )
    
    result = await main.admin_bulk_upload_departments(request, redirect_file)
    print("Redirect Result:", result)
    assert result["success"] is True
    created_users = [u["username"] for u in result["data"]["created_users"]]
    assert "testredirect" in created_users
    
    cursor.execute("SELECT name FROM departments WHERE name = 'Redirected Dept'")
    assert cursor.fetchone() is not None
    cursor.execute("SELECT username FROM users WHERE username = 'testredirect'")
    assert cursor.fetchone() is not None

    # ── USER SKIP TEST ──
    print("Testing User Skip on duplicate username...")
    sync_json = [
        {
            "username": "testuser1",
            "name": "Synced User 1",
            "dept": "Test Dept Admin",
            "role": "staff",
            "password": "newpassword"
        }
    ]
    sync_bytes = json.dumps(sync_json).encode("utf-8")
    sync_file = UploadFile(
        file=io.BytesIO(sync_bytes),
        filename="users_sync.json",
        headers=Headers({"content-type": "application/json"})
    )
    result = await main.admin_bulk_upload_users(request, sync_file)
    print("User Sync / Skip Result:", result)
    assert result["success"] is True
    assert result["data"]["created_count"] == 0
    assert result["data"]["skipped_count"] == 1
    
    # Check that database still has the original name (it was skipped, not updated)
    cursor.execute("SELECT name FROM users WHERE username = 'testuser1'")
    assert cursor.fetchone()[0] == "Test User 1"

    # ── OTHER STAFF BULK UPLOAD TEST ──
    print("Testing Other Staff bulk upload with department auto-creation...")
    cursor.execute("DELETE FROM other_staff WHERE username IN ('testother1', 'testother2')")
    cursor.execute("DELETE FROM departments WHERE name = 'Test Other Dept'")
    
    other_json = [
        {
            "username": "testother1",
            "name": "Other Staff 1",
            "dept": "Test Other Dept",
            "role": "office_staff",
            "password": "pwd"
        },
        {
            "username": "testother2",
            "name": "Other Staff 2",
            "dept": "Test Other Dept",
            "role": "lab_technician",
            "password": "pwd"
        }
    ]
    other_bytes = json.dumps(other_json).encode("utf-8")
    other_file = UploadFile(
        file=io.BytesIO(other_bytes),
        filename="other_staff.json",
        headers=Headers({"content-type": "application/json"})
    )
    result = await main.admin_bulk_upload_other_staff(request, other_file)
    print("Other Staff Upload Result:", result)
    assert result["success"] is True
    
    # Verify that they exist in database
    cursor.execute("SELECT username FROM other_staff WHERE username = 'testother1'")
    assert cursor.fetchone() is not None
    cursor.execute("SELECT name FROM departments WHERE name = 'Test Other Dept'")
    assert cursor.fetchone() is not None

    # ── USER CASCADING DELETION CLEANUP TEST ──
    print("Testing user cascading deletion cleanup...")
    test_reg = "TEST_DEL_0001"
    
    # Pre-clean
    cursor.execute("DELETE FROM attendance WHERE reg_no = ?", (test_reg,))
    cursor.execute("DELETE FROM leave_requests WHERE user_reg_no = ?", (test_reg,))
    cursor.execute("DELETE FROM face_reregister_requests WHERE staff_reg_no = ?", (test_reg,))
    
    # Insert mock entries
    cursor.execute(
        "INSERT INTO attendance (reg_no, name, dept, timestamp) VALUES (?, 'Test Delete', 'Admin', CURRENT_TIMESTAMP)",
        (test_reg,)
    )
    cursor.execute(
        "INSERT INTO leave_requests (user_reg_no, user_name, dept, leave_type, start_date, end_date, reason) VALUES (?, 'Test Delete', 'Admin', 'casual', '2026-06-18', '2026-06-19', 'Reason')",
        (test_reg,)
    )
    cursor.execute(
        "INSERT INTO face_reregister_requests (staff_reg_no, staff_name, dept, status) VALUES (?, 'Test Delete', 'Admin', 'pending')",
        (test_reg,)
    )
    
    # Verify they were inserted
    cursor.execute("SELECT id FROM attendance WHERE reg_no = ?", (test_reg,))
    assert cursor.fetchone() is not None
    cursor.execute("SELECT id FROM leave_requests WHERE user_reg_no = ?", (test_reg,))
    assert cursor.fetchone() is not None
    cursor.execute("SELECT id FROM face_reregister_requests WHERE staff_reg_no = ?", (test_reg,))
    assert cursor.fetchone() is not None
    
    # Run the cleanup logic
    main.delete_user_data_by_reg_no(test_reg)
    
    # Verify they are deleted
    cursor.execute("SELECT id FROM attendance WHERE reg_no = ?", (test_reg,))
    assert cursor.fetchone() is None
    cursor.execute("SELECT id FROM leave_requests WHERE user_reg_no = ?", (test_reg,))
    assert cursor.fetchone() is None
    cursor.execute("SELECT id FROM face_reregister_requests WHERE staff_reg_no = ?", (test_reg,))
    assert cursor.fetchone() is None
    print("Cascading cleanup tests passed successfully!")

    print("\nAll tests passed successfully!")

if __name__ == "__main__":
    try:
        asyncio.run(run_tests())
    finally:
        # Cleanup
        cursor.execute("DELETE FROM users WHERE username IN ('testuser1', 'testuser2', 'testuser3', 'testuser4', 'testredirect')")
        cursor.execute("DELETE FROM other_staff WHERE username IN ('testother1', 'testother2')")
        cursor.execute("DELETE FROM departments WHERE name IN ('Test Dept JSON 1', 'Test Dept JSON 2', 'Test Dept Excel 1', 'Test Dept Excel 2', 'Test Dept Admin', 'Redirected Dept', 'Test Other Dept')")
        main.verify_admin_token = original_verify
