"""
Attenda Features v2 Schema Migration
Creates all new tables required for the extended feature set:
- audit_log
- attendance_corrections
- attendance_regularisation_window
- notifications_all_roles
- notification_preferences
- active_sessions
- login_attempts_log
- totp_secrets
- smtp_config
- holiday_calendar
- comp_off_accrual
- leave_carry_forward_rules
- ccl_accrual_rules
- substitute_assignments
- student_feedback_grievances
- system_announcements
- user_transfers_log
- user_security_flags (for forced password reset, etc.)
"""

import os
import sys

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
os.environ.setdefault("PYTHONIOENCODING", "utf-8")

# Ensure backend directory is in sys.path
backend_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)

import pg_adapter


def run_migration():
    cursor = pg_adapter.cursor
    print("Running Features v2 Database Migrations...")

    # Ensure daily_attendance_status columns exist
    cursor.execute("ALTER TABLE daily_attendance_status ADD COLUMN IF NOT EXISTS in_time VARCHAR(50)")
    cursor.execute("ALTER TABLE daily_attendance_status ADD COLUMN IF NOT EXISTS out_time VARCHAR(50)")
    cursor.execute("ALTER TABLE daily_attendance_status ADD COLUMN IF NOT EXISTS is_manual_override BOOLEAN DEFAULT FALSE")
    cursor.execute("ALTER TABLE daily_attendance_status ADD COLUMN IF NOT EXISTS override_by VARCHAR(100)")
    cursor.execute("ALTER TABLE daily_attendance_status ADD COLUMN IF NOT EXISTS override_reason TEXT")

    # 1. Audit Log
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS audit_log (
            id SERIAL PRIMARY KEY,
            timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            actor_reg_no VARCHAR(100),
            actor_name VARCHAR(150),
            actor_role VARCHAR(50),
            action_type VARCHAR(100) NOT NULL,
            entity_type VARCHAR(100),
            entity_id VARCHAR(100),
            details TEXT,
            ip_address VARCHAR(100),
            success BOOLEAN DEFAULT TRUE
        )
    """)
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_audit_log_timestamp ON audit_log (timestamp DESC)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_audit_log_actor ON audit_log (actor_reg_no)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_audit_log_action ON audit_log (action_type)")

    # 2. Attendance Corrections
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS attendance_corrections (
            id SERIAL PRIMARY KEY,
            reg_no VARCHAR(100) NOT NULL,
            user_name VARCHAR(150),
            role VARCHAR(50),
            dept VARCHAR(100),
            requested_date DATE NOT NULL,
            requested_check_in VARCHAR(50),
            requested_check_out VARCHAR(50),
            requested_status VARCHAR(50) DEFAULT 'Present',
            reason TEXT NOT NULL,
            status VARCHAR(50) DEFAULT 'Pending',
            reviewer_reg_no VARCHAR(100),
            reviewer_name VARCHAR(150),
            review_remarks TEXT,
            reviewed_at TIMESTAMP,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_att_corr_reg_no ON attendance_corrections (reg_no)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_att_corr_status ON attendance_corrections (status)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_att_corr_dept ON attendance_corrections (dept)")

    # 3. Regularisation Window Settings
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS attendance_regularisation_window (
            id INT PRIMARY KEY DEFAULT 1,
            max_correction_days INT DEFAULT 7,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_by VARCHAR(100)
        )
    """)
    cursor.execute("""
        INSERT INTO attendance_regularisation_window (id, max_correction_days, updated_by)
        VALUES (1, 7, 'system')
        ON CONFLICT (id) DO NOTHING
    """)

    # 4. Notifications (All Roles)
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS notifications_all_roles (
            id SERIAL PRIMARY KEY,
            recipient_reg_no VARCHAR(100),
            target_role VARCHAR(50),
            target_dept VARCHAR(100),
            title VARCHAR(255) NOT NULL,
            message TEXT NOT NULL,
            type VARCHAR(50) DEFAULT 'info',
            is_read BOOLEAN DEFAULT FALSE,
            metadata TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            created_by VARCHAR(100)
        )
    """)
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_notif_recipient ON notifications_all_roles (recipient_reg_no)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_notif_role_dept ON notifications_all_roles (target_role, target_dept)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_notif_is_read ON notifications_all_roles (is_read)")

    # 5. Notification Preferences
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS notification_preferences (
            reg_no VARCHAR(100) PRIMARY KEY,
            email_enabled BOOLEAN DEFAULT TRUE,
            push_enabled BOOLEAN DEFAULT TRUE,
            leave_alerts BOOLEAN DEFAULT TRUE,
            attendance_alerts BOOLEAN DEFAULT TRUE,
            announcement_alerts BOOLEAN DEFAULT TRUE,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)

    # 6. Active Sessions
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS active_sessions (
            session_id VARCHAR(150) PRIMARY KEY,
            reg_no VARCHAR(100) NOT NULL,
            username VARCHAR(100),
            role VARCHAR(50),
            ip_address VARCHAR(100),
            user_agent TEXT,
            device_info TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            last_activity TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            is_active BOOLEAN DEFAULT TRUE
        )
    """)
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_sessions_reg_no ON active_sessions (reg_no)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_sessions_active ON active_sessions (is_active)")

    # 7. Login Attempts Log
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS login_attempts_log (
            id SERIAL PRIMARY KEY,
            username VARCHAR(100),
            ip_address VARCHAR(100),
            success BOOLEAN DEFAULT FALSE,
            reason TEXT,
            attempted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_login_attempts_ip ON login_attempts_log (ip_address)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_login_attempts_user ON login_attempts_log (username)")

    # 8. TOTP Secrets
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS totp_secrets (
            reg_no VARCHAR(100) PRIMARY KEY,
            secret_key VARCHAR(100) NOT NULL,
            is_enabled BOOLEAN DEFAULT FALSE,
            enabled_at TIMESTAMP,
            backup_codes TEXT
        )
    """)

    # 9. SMTP Config
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS smtp_config (
            id INT PRIMARY KEY DEFAULT 1,
            host VARCHAR(255) DEFAULT '',
            port INT DEFAULT 587,
            username VARCHAR(255) DEFAULT '',
            password VARCHAR(255) DEFAULT '',
            sender_email VARCHAR(255) DEFAULT '',
            sender_name VARCHAR(255) DEFAULT 'Attenda Notification',
            use_tls BOOLEAN DEFAULT TRUE,
            is_active BOOLEAN DEFAULT FALSE,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_by VARCHAR(100)
        )
    """)
    cursor.execute("""
        INSERT INTO smtp_config (id, host, port, username, password, sender_email, sender_name, use_tls, is_active, updated_by)
        VALUES (1, '', 587, '', '', '', 'Attenda Notification', TRUE, FALSE, 'system')
        ON CONFLICT (id) DO NOTHING
    """)

    # 10. Holiday Calendar
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS holiday_calendar (
            id SERIAL PRIMARY KEY,
            holiday_date DATE UNIQUE NOT NULL,
            holiday_name VARCHAR(255) NOT NULL,
            holiday_type VARCHAR(50) DEFAULT 'General',
            is_optional BOOLEAN DEFAULT FALSE,
            academic_year VARCHAR(50),
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            created_by VARCHAR(100)
        )
    """)
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_holiday_date ON holiday_calendar (holiday_date)")

    # 11. Comp-off Accrual
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS comp_off_accrual (
            id SERIAL PRIMARY KEY,
            reg_no VARCHAR(100) NOT NULL,
            staff_name VARCHAR(150),
            duty_date DATE NOT NULL,
            duty_type VARCHAR(100),
            days_earned NUMERIC(4,2) DEFAULT 1.0,
            reason TEXT,
            expiry_date DATE,
            status VARCHAR(50) DEFAULT 'Available',
            approved_by VARCHAR(100),
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_comp_off_reg ON comp_off_accrual (reg_no, status)")

    # 12. Leave Carry Forward Rules
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS leave_carry_forward_rules (
            id INT PRIMARY KEY DEFAULT 1,
            max_el_carry_forward INT DEFAULT 15,
            max_cl_carry_forward INT DEFAULT 0,
            encashment_allowed BOOLEAN DEFAULT FALSE,
            max_encashment_days INT DEFAULT 10,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_by VARCHAR(100)
        )
    """)
    cursor.execute("""
        INSERT INTO leave_carry_forward_rules (id, max_el_carry_forward, max_cl_carry_forward, encashment_allowed, max_encashment_days, updated_by)
        VALUES (1, 15, 0, FALSE, 10, 'system')
        ON CONFLICT (id) DO NOTHING
    """)

    # 13. CCL Accrual Rules
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS ccl_accrual_rules (
            id SERIAL PRIMARY KEY,
            event_type VARCHAR(100) NOT NULL,
            min_hours INT DEFAULT 4,
            ccl_days_earned NUMERIC(4,2) DEFAULT 1.0,
            validity_days INT DEFAULT 90,
            description TEXT,
            is_active BOOLEAN DEFAULT TRUE,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)

    # 14. Substitute Assignments
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS substitute_assignments (
            id SERIAL PRIMARY KEY,
            original_staff_reg_no VARCHAR(100) NOT NULL,
            original_staff_name VARCHAR(150),
            substitute_staff_reg_no VARCHAR(100) NOT NULL,
            substitute_staff_name VARCHAR(150),
            dept VARCHAR(100),
            batch VARCHAR(50),
            semester INT,
            section VARCHAR(50),
            subject_code VARCHAR(100),
            subject_name VARCHAR(255),
            assignment_date DATE NOT NULL,
            period_number INT NOT NULL,
            status VARCHAR(50) DEFAULT 'Assigned',
            reason TEXT,
            assigned_by VARCHAR(100),
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_sub_orig_staff ON substitute_assignments (original_staff_reg_no, assignment_date)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_sub_target_staff ON substitute_assignments (substitute_staff_reg_no, assignment_date)")

    # 15. Student Feedback & Grievances
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS student_feedback_grievances (
            id SERIAL PRIMARY KEY,
            student_reg_no VARCHAR(100) NOT NULL,
            student_name VARCHAR(150),
            dept VARCHAR(100),
            category VARCHAR(100),
            subject VARCHAR(255) NOT NULL,
            description TEXT NOT NULL,
            status VARCHAR(50) DEFAULT 'Open',
            admin_remarks TEXT,
            resolved_at TIMESTAMP,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_feedback_reg ON student_feedback_grievances (student_reg_no)")

    # 16. System Announcements
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS system_announcements (
            id SERIAL PRIMARY KEY,
            title VARCHAR(255) NOT NULL,
            content TEXT NOT NULL,
            target_audience VARCHAR(50) DEFAULT 'All',
            target_dept VARCHAR(100),
            priority VARCHAR(50) DEFAULT 'Normal',
            expires_at TIMESTAMP,
            created_by VARCHAR(100),
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)

    # 17. User Transfers Log
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS user_transfers_log (
            id SERIAL PRIMARY KEY,
            user_id INT,
            reg_no VARCHAR(100) NOT NULL,
            old_dept VARCHAR(100),
            new_dept VARCHAR(100),
            old_role VARCHAR(50),
            new_role VARCHAR(50),
            transfer_date DATE DEFAULT CURRENT_DATE,
            remarks TEXT,
            transferred_by VARCHAR(100),
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)

    # 18. User Security Flags (for force password reset flag, etc.)
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS user_security_flags (
            reg_no VARCHAR(100) PRIMARY KEY,
            force_password_reset BOOLEAN DEFAULT FALSE,
            two_factor_required BOOLEAN DEFAULT FALSE,
            last_password_change TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            account_locked_until TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)

    print("[SUCCESS] Features v2 Database Migrations completed successfully!")


if __name__ == "__main__":
    run_migration()
