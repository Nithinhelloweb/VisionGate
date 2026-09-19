-- Migration 0012: Add liveness columns to attendance logs
-- Applies to: morning_attendance, evening_attendance, daily_attendance_status

ALTER TABLE morning_attendance
    ADD COLUMN IF NOT EXISTS liveness_score      REAL DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS liveness_layers     TEXT DEFAULT NULL,   -- JSON string
    ADD COLUMN IF NOT EXISTS spoof_verdict       INTEGER DEFAULT 0,   -- 0=live,1=spoof
    ADD COLUMN IF NOT EXISTS model_version       TEXT DEFAULT 'MiniFASNetV2+V1SE-ensemble-1.0';

ALTER TABLE evening_attendance
    ADD COLUMN IF NOT EXISTS liveness_score      REAL DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS liveness_layers     TEXT DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS spoof_verdict       INTEGER DEFAULT 0,
    ADD COLUMN IF NOT EXISTS model_version       TEXT DEFAULT 'MiniFASNetV2+V1SE-ensemble-1.0';

-- General attendance log table (if exists)
CREATE TABLE IF NOT EXISTS attendance_liveness_log (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    reg_no          TEXT        NOT NULL,
    attendance_date TEXT        NOT NULL,
    slot_type       TEXT        NOT NULL,
    liveness_score  REAL,
    l1_score_v2     REAL,
    l1_score_se     REAL,
    l2_moire        REAL,
    l3_blink        INTEGER,
    l4_flow_sigma   REAL,
    layers_passed   TEXT,       -- JSON
    model_version   TEXT,
    created_at      TEXT        DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_all_liveness_reg_date ON attendance_liveness_log(reg_no, attendance_date);
