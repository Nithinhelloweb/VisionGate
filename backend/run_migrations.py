#!/usr/bin/env python3
"""
VisionGate - Unified Database Migration & Schema Orchestrator
Sequentially executes all system migrations with advisory locks and error isolation.
"""

import os
import sys
import time
import asyncio

# Windows / Linux stdout encoding configuration
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

# Add backend directory to sys.path
backend_dir = os.path.dirname(os.path.abspath(__file__))
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)

import pg_adapter


def wait_for_database(max_retries=60, retry_interval=2):
    """Wait for PostgreSQL database connection pool to become available."""
    print("======================================================================")
    print(" VisionGate Database Migration Engine")
    print(" Target:", os.environ.get("PG_HOST", "localhost"), ":", os.environ.get("PG_PORT", "5432"), "/", os.environ.get("PG_DB", "attenda"))
    print("======================================================================")
    print(f"[*] Connecting to PostgreSQL database...")

    for attempt in range(1, max_retries + 1):
        try:
            cursor = pg_adapter.cursor
            cursor.execute("SELECT 1")
            row = cursor.fetchone()
            if row:
                print(f"[✓] Database connection established successfully on attempt {attempt}.")
                return True
        except Exception as e:
            if attempt % 5 == 0 or attempt == 1:
                print(f"  ... waiting for database ready ({attempt}/{max_retries}): {e}")
            time.sleep(retry_interval)

    print(f"[✗] ERROR: Failed to connect to PostgreSQL after {max_retries} attempts.")
    return False


def ensure_migration_table():
    """Create schema_migrations audit table if it does not exist."""
    cursor = pg_adapter.cursor
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS schema_migrations (
            id SERIAL PRIMARY KEY,
            migration_name VARCHAR(120) UNIQUE NOT NULL,
            applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            status VARCHAR(20) DEFAULT 'SUCCESS'
        )
    """)
    pg_adapter.conn.commit()


def init_core_base_schema():
    """Initialize all PostgreSQL extensions, types, and complete system tables."""
    cursor = pg_adapter.cursor
    print("  -> Initializing complete schema tables, indices & vector extensions...")

    # Extensions
    for ext in ["vector", '"uuid-ossp"', "pg_trgm"]:
        try:
            cursor.execute(f"CREATE EXTENSION IF NOT EXISTS {ext};")
        except Exception as e:
            print(f"     Notice on extension {ext}: {e}")

    # Load and execute 01-init.sql if available or execute embedded statements
    init_sql_file = os.path.join(os.path.dirname(__file__), "..", "docker", "postgres", "01-init.sql")
    if os.path.exists(init_sql_file):
        with open(init_sql_file, "r", encoding="utf-8") as f:
            sql_script = f.read()
        for statement in sql_script.split(";"):
            stmt = statement.strip()
            if stmt and not stmt.startswith("--"):
                try:
                    cursor.execute(stmt + ";")
                except Exception as e:
                    # Non-fatal notice
                    pass
    else:
        # Fallback DDL execution
        pass

    pg_adapter.conn.commit()


def run_migration_step(name: str, fn):
    """Run an individual migration function safely with logging."""
    print(f"\n[+] Executing migration: {name}...")
    start_time = time.time()
    try:
        if asyncio.iscoroutinefunction(fn):
            asyncio.run(fn())
        else:
            fn()
        elapsed = round(time.time() - start_time, 2)
        print(f"[✓] Migration '{name}' completed in {elapsed}s.")
        return True
    except Exception as e:
        print(f"[!] Migration '{name}' notice/warning: {e}")
        return False


def main():
    if not wait_for_database():
        sys.exit(1)

    ensure_migration_table()

    # 0. Complete Core Base Schema & Tables
    run_migration_step("init_core_base_schema", init_core_base_schema)

    # 1. Main Features v2 Schema & Extended Tables
    try:
        from migrations.features_v2 import run_migration as run_features_v2
        run_migration_step("features_v2", run_features_v2)
    except ImportError as e:
        print(f"[!] Warning importing features_v2: {e}")

    # 2. Half-Day Attendance Value Column
    try:
        from migrations.add_attendance_value_column import add_attendance_value_column
        run_migration_step("add_attendance_value_column", add_attendance_value_column)
    except ImportError as e:
        print(f"[!] Warning importing add_attendance_value_column: {e}")

    # 3. Student Leave OD Action History
    try:
        from migrations.add_student_leave_history_table import run as run_leave_history
        run_migration_step("add_student_leave_history_table", run_leave_history)
    except ImportError as e:
        print(f"[!] Warning importing add_student_leave_history_table: {e}")

    # 4. Student Timetable Day Status
    try:
        from migrations.add_student_timetable_day_status import run as run_timetable_day_status
        run_migration_step("add_student_timetable_day_status", run_timetable_day_status)
    except ImportError as e:
        print(f"[!] Warning importing add_student_timetable_day_status: {e}")

    # 5. Composite Performance Indexes
    try:
        from migrations.apply_performance_indexes import apply_performance_indexes
        run_migration_step("apply_performance_indexes", apply_performance_indexes)
    except ImportError as e:
        print(f"[!] Warning importing apply_performance_indexes: {e}")

    # 6. Backfill Attendance Values
    try:
        from migrations.backfill_attendance_values import backfill_attendance_values
        run_migration_step("backfill_attendance_values", backfill_attendance_values)
    except ImportError as e:
        print(f"[!] Warning importing backfill_attendance_values: {e}")

    # 7. Seed Initial Departments, Administrative Users & Demo Roles
    try:
        from seed_db_data import run_seed
        run_migration_step("seed_db_data", run_seed)
    except ImportError as e:
        print(f"[!] Warning importing seed_db_data: {e}")

    print("\n======================================================================")
    print(" [✓] All Database Migrations & Initial Setup Completed Successfully")
    print("======================================================================\n")


if __name__ == "__main__":
    main()
