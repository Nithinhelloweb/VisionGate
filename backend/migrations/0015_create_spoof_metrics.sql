-- Migration 0015: Spoof attempt rate tracking (per camera, per hour)
CREATE TABLE IF NOT EXISTS spoof_rate_metrics (
    camera_id     TEXT NOT NULL,
    hour_bucket   TEXT NOT NULL,
    attempt_count INTEGER DEFAULT 0,
    PRIMARY KEY (camera_id, hour_bucket)
);
CREATE INDEX IF NOT EXISTS idx_spoof_metrics_hour ON spoof_rate_metrics(hour_bucket);
