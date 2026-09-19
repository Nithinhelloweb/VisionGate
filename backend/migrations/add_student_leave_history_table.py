import os
import sys
import json

if sys.stdout and hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
if sys.stderr and hasattr(sys.stderr, "reconfigure"):
    try:
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

# Ensure parent directory is in sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import pg_adapter

def run():
    print("=== Running Migration: add_student_leave_history_table ===")
    cursor = pg_adapter.cursor
    conn = pg_adapter.conn

    # 1. Create student_leave_od_action_history table
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS student_leave_od_action_history (
            id SERIAL PRIMARY KEY,
            request_id INTEGER NOT NULL REFERENCES student_leave_od_requests(id) ON DELETE CASCADE,
            student_reg_no VARCHAR(64) NOT NULL,
            action VARCHAR(40) NOT NULL,
            actor_role VARCHAR(30) NOT NULL,
            actor_reg_no VARCHAR(64),
            actor_name VARCHAR(160),
            previous_status VARCHAR(30),
            new_status VARCHAR(30),
            remarks TEXT,
            metadata_json TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    print("  [OK] Created table student_leave_od_action_history")

    # 2. Indexes
    for idx_sql in [
        "CREATE INDEX IF NOT EXISTS idx_sload_req_id ON student_leave_od_action_history (request_id, created_at ASC)",
        "CREATE INDEX IF NOT EXISTS idx_sload_student ON student_leave_od_action_history (student_reg_no, created_at DESC)",
        "CREATE INDEX IF NOT EXISTS idx_sload_actor ON student_leave_od_action_history (actor_reg_no, created_at DESC)",
    ]:
        try:
            cursor.execute(idx_sql)
            print(f"  [OK] Index: {idx_sql.split('ON ')[1]}")
        except Exception as e:
            print(f"  [WARN] Index notice: {e}")

    # 3. Backfill initial history for existing requests
    cursor.execute("""
        SELECT id, student_reg_no, request_type, category, start_date, end_date, session_half,
               reason, mentor_status, mentor_staff_reg_no, mentor_name, mentor_remarks, mentor_action_at,
               hod_status, hod_staff_reg_no, hod_name, hod_remarks, hod_action_at,
               admin_status, admin_remarks, admin_action_at, is_attendance_credited, created_at
        FROM student_leave_od_requests
    """)
    existing_requests = cursor.fetchall()
    backfilled = 0

    for r in existing_requests:
        rid = r[0] if isinstance(r, (list, tuple)) else r.get("id")
        stu_reg = r[1] if isinstance(r, (list, tuple)) else r.get("student_reg_no")
        req_type = r[2] if isinstance(r, (list, tuple)) else r.get("request_type")
        category = r[3] if isinstance(r, (list, tuple)) else r.get("category")
        start_d = str(r[4] if isinstance(r, (list, tuple)) else r.get("start_date"))
        end_d = str(r[5] if isinstance(r, (list, tuple)) else r.get("end_date"))
        sess_h = r[6] if isinstance(r, (list, tuple)) else r.get("session_half")
        reason = r[7] if isinstance(r, (list, tuple)) else r.get("reason")
        m_status = r[8] if isinstance(r, (list, tuple)) else r.get("mentor_status")
        m_reg = r[9] if isinstance(r, (list, tuple)) else r.get("mentor_staff_reg_no")
        m_name = r[10] if isinstance(r, (list, tuple)) else r.get("mentor_name")
        m_remarks = r[11] if isinstance(r, (list, tuple)) else r.get("mentor_remarks")
        m_time = r[12] if isinstance(r, (list, tuple)) else r.get("mentor_action_at")
        h_status = r[13] if isinstance(r, (list, tuple)) else r.get("hod_status")
        h_reg = r[14] if isinstance(r, (list, tuple)) else r.get("hod_staff_reg_no")
        h_name = r[15] if isinstance(r, (list, tuple)) else r.get("hod_name")
        h_remarks = r[16] if isinstance(r, (list, tuple)) else r.get("hod_remarks")
        h_time = r[17] if isinstance(r, (list, tuple)) else r.get("hod_action_at")
        a_status = r[18] if isinstance(r, (list, tuple)) else r.get("admin_status")
        a_remarks = r[19] if isinstance(r, (list, tuple)) else r.get("admin_remarks")
        a_time = r[20] if isinstance(r, (list, tuple)) else r.get("admin_action_at")
        att_credited = r[21] if isinstance(r, (list, tuple)) else r.get("is_attendance_credited")
        created_at = r[22] if isinstance(r, (list, tuple)) else r.get("created_at")

        cursor.execute("SELECT COUNT(*) FROM student_leave_od_action_history WHERE request_id = ?", (rid,))
        cnt = cursor.fetchone()[0]
        if cnt > 0:
            continue

        meta = json.dumps({
            "request_type": req_type,
            "category": category or "General",
            "start_date": start_d,
            "end_date": end_d,
            "session_half": sess_h or "FULL_DAY",
            "reason": reason or "",
        })

        cursor.execute("""
            INSERT INTO student_leave_od_action_history
              (request_id, student_reg_no, action, actor_role, actor_reg_no, actor_name,
               previous_status, new_status, remarks, metadata_json, created_at)
            VALUES (?, ?, 'SUBMITTED', 'STUDENT', ?, ?, NULL, 'PENDING_ADVISOR', ?, ?, COALESCE(?, CURRENT_TIMESTAMP))
        """, (rid, stu_reg, stu_reg, stu_reg, reason or "Application submitted", meta, created_at))

        if m_status and m_status != "PENDING":
            cursor.execute("""
                INSERT INTO student_leave_od_action_history
                  (request_id, student_reg_no, action, actor_role, actor_reg_no, actor_name,
                   previous_status, new_status, remarks, metadata_json, created_at)
                VALUES (?, ?, ?, 'CLASS_ADVISOR', ?, ?, 'PENDING_ADVISOR', ?, ?, ?, COALESCE(?, CURRENT_TIMESTAMP))
            """, (rid, stu_reg, "RECOMMENDED" if m_status == "RECOMMENDED" else "REJECTED_BY_MENTOR",
                  m_reg or "ADVISOR", m_name or "Class Advisor", m_status, m_remarks or "", meta, m_time))

        if h_status and h_status != "PENDING":
            act_name = "APPROVED_BY_HOD" if h_status == "APPROVED" else ("REJECTED_BY_HOD" if h_status == "REJECTED" else "REFERRED_BACK_BY_HOD")
            cursor.execute("""
                INSERT INTO student_leave_od_action_history
                  (request_id, student_reg_no, action, actor_role, actor_reg_no, actor_name,
                   previous_status, new_status, remarks, metadata_json, created_at)
                VALUES (?, ?, ?, 'HOD', ?, ?, 'PENDING_HOD', ?, ?, ?, COALESCE(?, CURRENT_TIMESTAMP))
            """, (rid, stu_reg, act_name, h_reg or "HOD", h_name or "Head of Department", h_status, h_remarks or "", meta, h_time))

        if a_status and a_status != "PENDING":
            act_name = "APPROVED_BY_ADMIN" if a_status == "APPROVED" else "REJECTED_BY_ADMIN"
            cursor.execute("""
                INSERT INTO student_leave_od_action_history
                  (request_id, student_reg_no, action, actor_role, actor_reg_no, actor_name,
                   previous_status, new_status, remarks, metadata_json, created_at)
                VALUES (?, ?, ?, 'ADMIN', 'admin', 'Central Administration', 'PENDING_ADMIN', ?, ?, ?, COALESCE(?, CURRENT_TIMESTAMP))
            """, (rid, stu_reg, act_name, a_status, a_remarks or "", meta, a_time))

        if att_credited:
            cursor.execute("""
                INSERT INTO student_leave_od_action_history
                  (request_id, student_reg_no, action, actor_role, actor_reg_no, actor_name,
                   previous_status, new_status, remarks, metadata_json, created_at)
                VALUES (?, ?, 'ATTENDANCE_CREDITED', 'SYSTEM', 'SYSTEM', 'Timetable Attendance Engine',
                        'APPROVED', 'ATTENDANCE_CREDITED', 'Timetable period attendance automatically credited', ?, CURRENT_TIMESTAMP)
            """, (rid, stu_reg, meta))

        backfilled += 1

    conn.commit()
    print(f"  [OK] Backfilled {backfilled} existing request history trails.")
    print("=== Migration completed successfully ===")

if __name__ == "__main__":
    run()
