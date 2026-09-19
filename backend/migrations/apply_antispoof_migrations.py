"""
apply_antispoof_migrations.py — Automated runner for migrations 0012 to 0015.
PostgreSQL/SQLite dual-compatible.
"""
import os
import sys

_BACKEND = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _BACKEND not in sys.path:
    sys.path.insert(0, _BACKEND)

import pg_adapter


def apply_migrations():
    conn = pg_adapter.conn
    cursor = pg_adapter.cursor
    print("=" * 70)
    print("[MIGRATION] Applying Anti-Spoofing database schemas (0012-0015)...")
    print("=" * 70)

    # Detect if Postgres
    is_postgres = True
    try:
        cursor.execute("SELECT version();")
        v = cursor.fetchone()
        print(f"[DB] Connected to: {v[0][:40]}...")
    except Exception:
        is_postgres = False
        print("[DB] Operating in SQLite compatibility mode")

    id_serial = "SERIAL PRIMARY KEY" if is_postgres else "INTEGER PRIMARY KEY AUTOINCREMENT"
    now_fn = "NOW()" if is_postgres else "datetime('now')"
    real_type = "DOUBLE PRECISION" if is_postgres else "REAL"
    blob_type = "BYTEA" if is_postgres else "BLOB"

    # 1. Migration 0012: Alter attendance tables for liveness columns
    for tbl in ["morning_attendance", "evening_attendance"]:
        for col_name, col_type in [
            ("liveness_score", f"{real_type} DEFAULT NULL"),
            ("liveness_layers", "TEXT DEFAULT NULL"),
            ("spoof_verdict", "INTEGER DEFAULT 0"),
            ("model_version", "TEXT DEFAULT 'MiniFASNetV2+V1SE-ensemble-1.0'"),
        ]:
            try:
                cursor.execute(f"ALTER TABLE {tbl} ADD COLUMN {col_name} {col_type};")
                conn.commit()
                print(f"   [+] Added column {col_name} to {tbl}")
            except Exception:
                conn.rollback() if hasattr(conn, "rollback") else None

    # 2. Table: attendance_liveness_log
    try:
        cursor.execute(f"""
            CREATE TABLE IF NOT EXISTS attendance_liveness_log (
                id              {id_serial},
                reg_no          TEXT        NOT NULL,
                attendance_date TEXT        NOT NULL,
                slot_type       TEXT        NOT NULL,
                liveness_score  {real_type},
                l1_score_v2     {real_type},
                l1_score_se     {real_type},
                l2_moire        {real_type},
                l3_blink        INTEGER,
                l4_flow_sigma   {real_type},
                layers_passed   TEXT,
                model_version   TEXT,
                created_at      TIMESTAMPTZ DEFAULT {now_fn}
            );
        """)
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_all_liveness_reg_date ON attendance_liveness_log(reg_no, attendance_date);")
        conn.commit()
        print("[+] Created table attendance_liveness_log")
    except Exception as e:
        conn.rollback() if hasattr(conn, "rollback") else None
        print(f"[-] Table attendance_liveness_log: {e}")

    # 3. Migration 0013: spoof_events
    try:
        cursor.execute(f"""
            CREATE TABLE IF NOT EXISTS spoof_events (
                id              {id_serial},
                camera_id       TEXT        NOT NULL,
                track_id        TEXT,
                frame_ts        TIMESTAMPTZ NOT NULL,
                layer_failed    TEXT        NOT NULL,
                l1_score        {real_type},
                l2_moire_score  {real_type},
                l3_blink        INTEGER,
                l4_sigma        {real_type},
                face_crop_jpeg  {blob_type},
                decision        TEXT,
                layers_json     TEXT,
                reg_no          TEXT,
                created_at      TIMESTAMPTZ DEFAULT {now_fn}
            );
        """)
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_spoof_camera_ts ON spoof_events(camera_id, frame_ts);")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_spoof_layer ON spoof_events(layer_failed);")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_spoof_reg ON spoof_events(reg_no);")
        conn.commit()
        print("[+] Created table spoof_events")
    except Exception as e:
        conn.rollback() if hasattr(conn, "rollback") else None
        print(f"[-] Table spoof_events: {e}")

    # 4. Migration 0014: trusted_cameras
    try:
        cursor.execute(f"""
            CREATE TABLE IF NOT EXISTS trusted_cameras (
                id            {id_serial},
                camera_id     TEXT UNIQUE NOT NULL,
                device_serial TEXT        NOT NULL,
                hmac_key_enc  TEXT        NOT NULL,
                location      TEXT,
                is_active     INTEGER DEFAULT 1,
                registered_at TIMESTAMPTZ DEFAULT {now_fn}
            );
        """)
        conn.commit()
        print("[+] Created table trusted_cameras")
    except Exception as e:
        conn.rollback() if hasattr(conn, "rollback") else None
        print(f"[-] Table trusted_cameras: {e}")

    # 5. Migration 0015: spoof_rate_metrics
    try:
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS spoof_rate_metrics (
                camera_id     TEXT NOT NULL,
                hour_bucket   TIMESTAMPTZ NOT NULL,
                attempt_count INTEGER DEFAULT 0,
                PRIMARY KEY (camera_id, hour_bucket)
            );
        """)
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_spoof_metrics_hour ON spoof_rate_metrics(hour_bucket);")
        conn.commit()
        print("[+] Created table spoof_rate_metrics")
    except Exception as e:
        conn.rollback() if hasattr(conn, "rollback") else None
        print(f"[-] Table spoof_rate_metrics: {e}")

    print("=" * 70)
    print("[MIGRATION] Anti-Spoofing database schemas successfully applied.")
    print("=" * 70)


if __name__ == "__main__":
    apply_migrations()
