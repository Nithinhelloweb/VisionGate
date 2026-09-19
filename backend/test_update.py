import pg_adapter

cursor = pg_adapter.cursor
reg_no = 'HOD_0001'
name = 'demoo'
dept = 'CSE'

try:
    cursor.execute("SELECT balance FROM earned_leave WHERE reg_no = ?", (reg_no,))
    bal_row = cursor.fetchone()
    print("bal_row fetched:", bal_row)
    if not bal_row:
        print("Not bal_row - inserting")
        cursor.execute("""
            INSERT INTO earned_leave (reg_no, user_name, dept, role, balance)
            VALUES (?, ?, ?, ?, 1.0)
        """, (reg_no, name, dept, "hod", 1.0))
    else:
        new_balance = float(bal_row[0]) + 1.0
        print("Bal_row exists - updating to:", new_balance)
        cursor.execute("""
            UPDATE earned_leave 
            SET balance = ?, updated_at = CURRENT_TIMESTAMP
            WHERE reg_no = ?
        """, (new_balance, reg_no))
    
    # Check again
    cursor.execute("SELECT balance FROM earned_leave WHERE reg_no = ?", (reg_no,))
    print("Post-update fetched balance:", cursor.fetchone())
except Exception as e:
    print("Error occurred:", e)
