-- Migration 0014: Trusted camera registry (Layer 5 HMAC)
CREATE TABLE IF NOT EXISTS trusted_cameras (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    camera_id     TEXT UNIQUE NOT NULL,
    device_serial TEXT        NOT NULL,
    hmac_key_enc  TEXT        NOT NULL,   -- AES-256 encrypted with SECRET_KEY
    location      TEXT,
    is_active     INTEGER DEFAULT 1,
    registered_at TEXT DEFAULT (datetime('now'))
);
