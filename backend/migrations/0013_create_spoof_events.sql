-- Migration 0013: Spoof events audit table
CREATE TABLE IF NOT EXISTS spoof_events (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    camera_id       TEXT        NOT NULL,
    track_id        TEXT,
    frame_ts        TEXT        NOT NULL,
    layer_failed    TEXT        NOT NULL,
    l1_score        REAL,
    l2_moire_score  REAL,
    l3_blink        INTEGER,
    l4_sigma        REAL,
    face_crop_jpeg  BLOB,
    decision        TEXT,
    layers_json     TEXT,       -- JSON of all layer pass/fail
    reg_no          TEXT,
    created_at      TEXT        DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_spoof_camera_ts  ON spoof_events(camera_id, frame_ts);
CREATE INDEX IF NOT EXISTS idx_spoof_layer       ON spoof_events(layer_failed);
CREATE INDEX IF NOT EXISTS idx_spoof_reg         ON spoof_events(reg_no);
