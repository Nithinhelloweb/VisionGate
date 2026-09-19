-- ==============================================================================
-- VisionGate / Attenda — Authoritative Production Schema v3.0
-- Generated from live database: 2026-09-02
-- PostgreSQL 16 | 82 Tables | Fully idempotent (safe to re-run on any existing DB)
-- ==============================================================================

CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pg_trgm;

SET timezone = 'Asia/Kolkata';

-- ==============================================================================
-- 1. SYSTEM CONFIGURATION
-- ==============================================================================
CREATE TABLE IF NOT EXISTS system_config (
    key        VARCHAR(255) PRIMARY KEY,
    value      TEXT NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ==============================================================================
-- 2. SCHEMA MIGRATIONS TRACKER
-- ==============================================================================
CREATE TABLE IF NOT EXISTS schema_migrations (
    id             SERIAL PRIMARY KEY,
    migration_name VARCHAR(120) NOT NULL UNIQUE,
    applied_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status         VARCHAR(20) DEFAULT 'SUCCESS'
);

-- ==============================================================================
-- 3. DEPARTMENTS
-- ==============================================================================
CREATE TABLE IF NOT EXISTS departments (
    id         SERIAL PRIMARY KEY,
    dept_name  VARCHAR(160) NOT NULL UNIQUE,
    dept_code  VARCHAR(50),
    is_active  BOOLEAN DEFAULT TRUE,
    name       VARCHAR(160),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
ALTER TABLE departments ADD COLUMN IF NOT EXISTS name       VARCHAR(160);
ALTER TABLE departments ADD COLUMN IF NOT EXISTS dept_code  VARCHAR(50);
ALTER TABLE departments ADD COLUMN IF NOT EXISTS is_active  BOOLEAN DEFAULT TRUE;
ALTER TABLE departments ADD COLUMN IF NOT EXISTS created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP;
UPDATE departments SET name = dept_name WHERE name IS NULL AND dept_name IS NOT NULL;
UPDATE departments SET dept_name = name WHERE dept_name IS NULL AND name IS NOT NULL;

-- ==============================================================================
-- 4. CORE USERS (Staff)
-- ==============================================================================
CREATE TABLE IF NOT EXISTS users (
    id                     SERIAL PRIMARY KEY,
    username               VARCHAR(120) UNIQUE NOT NULL,
    password_hash          VARCHAR(255),
    reg_no                 VARCHAR(64) UNIQUE,
    name                   VARCHAR(160) NOT NULL,
    dept                   VARCHAR(160),
    role                   VARCHAR(80) DEFAULT 'staff',
    created_by             VARCHAR(120),
    created_at             TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    suspended              BOOLEAN DEFAULT FALSE,
    is_active              BOOLEAN DEFAULT TRUE,
    kiosk_enabled          BOOLEAN DEFAULT TRUE,
    profile_photo          TEXT,
    current_device_id      VARCHAR(255),
    email                  VARCHAR(160) DEFAULT '',
    phone                  VARCHAR(20) DEFAULT '',
    phone_number           VARCHAR(20) DEFAULT '',
    embedding              vector(512),
    out_permission_enabled BOOLEAN DEFAULT FALSE,
    out_permission_expiry  TIMESTAMP,
    photo                  TEXT,
    fcm_token              TEXT,
    designation            VARCHAR(160),
    joining_date           DATE,
    can_reregister         INTEGER DEFAULT 0,
    is_suspended           BOOLEAN DEFAULT FALSE,
    class_div              VARCHAR(20) DEFAULT '',
    district               VARCHAR(100),
    state                  VARCHAR(100)
);
ALTER TABLE users ADD COLUMN IF NOT EXISTS embedding              vector(512);
ALTER TABLE users ADD COLUMN IF NOT EXISTS kiosk_enabled          BOOLEAN DEFAULT TRUE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS current_device_id      VARCHAR(255);
ALTER TABLE users ADD COLUMN IF NOT EXISTS email                  VARCHAR(160) DEFAULT '';
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone                  VARCHAR(20) DEFAULT '';
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone_number           VARCHAR(20) DEFAULT '';
ALTER TABLE users ADD COLUMN IF NOT EXISTS out_permission_enabled BOOLEAN DEFAULT FALSE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS out_permission_expiry  TIMESTAMP;
ALTER TABLE users ADD COLUMN IF NOT EXISTS photo                  TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS fcm_token              TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS designation            VARCHAR(160);
ALTER TABLE users ADD COLUMN IF NOT EXISTS joining_date           DATE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS can_reregister         INTEGER DEFAULT 0;
ALTER TABLE users ADD COLUMN IF NOT EXISTS is_suspended           BOOLEAN DEFAULT FALSE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS class_div              VARCHAR(20) DEFAULT '';
ALTER TABLE users ADD COLUMN IF NOT EXISTS district               VARCHAR(100);
ALTER TABLE users ADD COLUMN IF NOT EXISTS state                  VARCHAR(100);

CREATE INDEX IF NOT EXISTS idx_users_username     ON users (username);
CREATE INDEX IF NOT EXISTS idx_users_reg_no       ON users (reg_no);
CREATE INDEX IF NOT EXISTS idx_users_dept         ON users (dept);
CREATE INDEX IF NOT EXISTS idx_users_role         ON users (role);
CREATE INDEX IF NOT EXISTS idx_users_dept_role    ON users (dept, role);
CREATE INDEX IF NOT EXISTS idx_users_reg_no_lower ON users (lower(reg_no));

-- ==============================================================================
-- 5. OTHER STAFF
-- ==============================================================================
CREATE TABLE IF NOT EXISTS other_staff (
    id                     SERIAL PRIMARY KEY,
    username               VARCHAR(120) NOT NULL UNIQUE,
    password_hash          TEXT NOT NULL,
    reg_no                 VARCHAR(64) NOT NULL UNIQUE,
    name                   VARCHAR(160) NOT NULL,
    dob                    DATE,
    role                   VARCHAR(80) NOT NULL,
    dept                   VARCHAR(160) NOT NULL,
    embedding              BYTEA,
    can_reregister         INTEGER DEFAULT 0,
    current_device_id      VARCHAR(255),
    suspended              BOOLEAN DEFAULT FALSE,
    created_at             TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by             VARCHAR(120),
    email                  VARCHAR(160) DEFAULT '',
    phone                  VARCHAR(20) DEFAULT '',
    phone_number           VARCHAR(20) DEFAULT '',
    is_active              BOOLEAN DEFAULT TRUE,
    out_permission_enabled BOOLEAN DEFAULT FALSE,
    out_permission_expiry  TIMESTAMP,
    photo                  TEXT,
    fcm_token              TEXT,
    designation            VARCHAR(160),
    joining_date           DATE,
    district               VARCHAR(100),
    state                  VARCHAR(100)
);
ALTER TABLE other_staff ADD COLUMN IF NOT EXISTS current_device_id      VARCHAR(255);
ALTER TABLE other_staff ADD COLUMN IF NOT EXISTS email                  VARCHAR(160) DEFAULT '';
ALTER TABLE other_staff ADD COLUMN IF NOT EXISTS phone                  VARCHAR(20) DEFAULT '';
ALTER TABLE other_staff ADD COLUMN IF NOT EXISTS phone_number           VARCHAR(20) DEFAULT '';
ALTER TABLE other_staff ADD COLUMN IF NOT EXISTS is_active              BOOLEAN DEFAULT TRUE;
ALTER TABLE other_staff ADD COLUMN IF NOT EXISTS out_permission_enabled BOOLEAN DEFAULT FALSE;
ALTER TABLE other_staff ADD COLUMN IF NOT EXISTS out_permission_expiry  TIMESTAMP;
ALTER TABLE other_staff ADD COLUMN IF NOT EXISTS photo                  TEXT;
ALTER TABLE other_staff ADD COLUMN IF NOT EXISTS fcm_token              TEXT;
ALTER TABLE other_staff ADD COLUMN IF NOT EXISTS designation            VARCHAR(160);
ALTER TABLE other_staff ADD COLUMN IF NOT EXISTS joining_date           DATE;
ALTER TABLE other_staff ADD COLUMN IF NOT EXISTS district               VARCHAR(100);
ALTER TABLE other_staff ADD COLUMN IF NOT EXISTS state                  VARCHAR(100);

CREATE INDEX IF NOT EXISTS idx_other_staff_reg_no_lower ON other_staff (lower(reg_no));
CREATE INDEX IF NOT EXISTS idx_other_staff_reg_no       ON other_staff (reg_no);
CREATE INDEX IF NOT EXISTS idx_other_staff_dept         ON other_staff (dept);
CREATE INDEX IF NOT EXISTS idx_other_staff_role         ON other_staff (role);
CREATE INDEX IF NOT EXISTS idx_other_staff_dept_role    ON other_staff (dept, role);
CREATE INDEX IF NOT EXISTS idx_other_staff_username     ON other_staff (username);

-- ==============================================================================
-- 6. STUDENTS
-- ==============================================================================
CREATE TABLE IF NOT EXISTS students (
    id                  SERIAL PRIMARY KEY,
    reg_no              VARCHAR(64) NOT NULL UNIQUE,
    name                VARCHAR(160) NOT NULL,
    dept                VARCHAR(160) NOT NULL,
    year                INTEGER,
    section             VARCHAR(16) NOT NULL,
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    roll_no             VARCHAR(64),
    email               VARCHAR(160),
    phone_number        VARCHAR(20),
    dob                 DATE DEFAULT '2004-01-01',
    gender              VARCHAR(10) DEFAULT 'Male',
    blood_group         VARCHAR(10),
    degree              VARCHAR(50) DEFAULT 'B.E.',
    batch               VARCHAR(20) DEFAULT '2022-2026',
    year_of_study       INTEGER DEFAULT 1,
    semester            INTEGER DEFAULT 1,
    quota               VARCHAR(20) DEFAULT 'Govt',
    mentor_staff_reg_no VARCHAR(64),
    father_name         VARCHAR(160),
    mother_name         VARCHAR(160),
    parent_phone        VARCHAR(20) DEFAULT '9876543210',
    parent_email        VARCHAR(160),
    emergency_contact   VARCHAR(20),
    permanent_address   TEXT,
    city                VARCHAR(100),
    state               VARCHAR(100) DEFAULT 'Tamil Nadu',
    pincode             VARCHAR(10),
    password_hash       TEXT DEFAULT '',
    first_time_login    BOOLEAN DEFAULT TRUE,
    suspended           BOOLEAN DEFAULT FALSE,
    can_reregister      BOOLEAN DEFAULT FALSE,
    current_device_id   VARCHAR(255),
    registered_by       VARCHAR(64) DEFAULT 'SYSTEM',
    registered_role     VARCHAR(20) DEFAULT 'admin',
    class_div           VARCHAR(50),
    district            VARCHAR(100)
);
ALTER TABLE students ADD COLUMN IF NOT EXISTS roll_no             VARCHAR(64);
ALTER TABLE students ADD COLUMN IF NOT EXISTS email               VARCHAR(160);
ALTER TABLE students ADD COLUMN IF NOT EXISTS phone_number        VARCHAR(20);
ALTER TABLE students ADD COLUMN IF NOT EXISTS dob                 DATE DEFAULT '2004-01-01';
ALTER TABLE students ADD COLUMN IF NOT EXISTS gender              VARCHAR(10) DEFAULT 'Male';
ALTER TABLE students ADD COLUMN IF NOT EXISTS blood_group         VARCHAR(10);
ALTER TABLE students ADD COLUMN IF NOT EXISTS degree              VARCHAR(50) DEFAULT 'B.E.';
ALTER TABLE students ADD COLUMN IF NOT EXISTS batch               VARCHAR(20) DEFAULT '2022-2026';
ALTER TABLE students ADD COLUMN IF NOT EXISTS year_of_study       INTEGER DEFAULT 1;
ALTER TABLE students ADD COLUMN IF NOT EXISTS semester            INTEGER DEFAULT 1;
ALTER TABLE students ADD COLUMN IF NOT EXISTS quota               VARCHAR(20) DEFAULT 'Govt';
ALTER TABLE students ADD COLUMN IF NOT EXISTS mentor_staff_reg_no VARCHAR(64);
ALTER TABLE students ADD COLUMN IF NOT EXISTS father_name         VARCHAR(160);
ALTER TABLE students ADD COLUMN IF NOT EXISTS mother_name         VARCHAR(160);
ALTER TABLE students ADD COLUMN IF NOT EXISTS parent_phone        VARCHAR(20) DEFAULT '9876543210';
ALTER TABLE students ADD COLUMN IF NOT EXISTS parent_email        VARCHAR(160);
ALTER TABLE students ADD COLUMN IF NOT EXISTS emergency_contact   VARCHAR(20);
ALTER TABLE students ADD COLUMN IF NOT EXISTS permanent_address   TEXT;
ALTER TABLE students ADD COLUMN IF NOT EXISTS city                VARCHAR(100);
ALTER TABLE students ADD COLUMN IF NOT EXISTS state               VARCHAR(100) DEFAULT 'Tamil Nadu';
ALTER TABLE students ADD COLUMN IF NOT EXISTS pincode             VARCHAR(10);
ALTER TABLE students ADD COLUMN IF NOT EXISTS password_hash       TEXT DEFAULT '';
ALTER TABLE students ADD COLUMN IF NOT EXISTS first_time_login    BOOLEAN DEFAULT TRUE;
ALTER TABLE students ADD COLUMN IF NOT EXISTS suspended           BOOLEAN DEFAULT FALSE;
ALTER TABLE students ADD COLUMN IF NOT EXISTS can_reregister      BOOLEAN DEFAULT FALSE;
ALTER TABLE students ADD COLUMN IF NOT EXISTS current_device_id   VARCHAR(255);
ALTER TABLE students ADD COLUMN IF NOT EXISTS registered_by       VARCHAR(64) DEFAULT 'SYSTEM';
ALTER TABLE students ADD COLUMN IF NOT EXISTS registered_role     VARCHAR(20) DEFAULT 'admin';
ALTER TABLE students ADD COLUMN IF NOT EXISTS class_div           VARCHAR(50);
ALTER TABLE students ADD COLUMN IF NOT EXISTS district            VARCHAR(100);

CREATE INDEX IF NOT EXISTS idx_students_reg_no        ON students (reg_no);
CREATE INDEX IF NOT EXISTS idx_students_reg_no_lower  ON students (lower(reg_no));
CREATE INDEX IF NOT EXISTS idx_students_dept_sec      ON students (dept, semester, section);
CREATE INDEX IF NOT EXISTS idx_students_batch         ON students (batch, dept);
CREATE INDEX IF NOT EXISTS idx_students_mentor        ON students (mentor_staff_reg_no);
CREATE INDEX IF NOT EXISTS idx_students_cohort_active ON students (lower(dept), trim(batch), semester, lower(section));

-- ==============================================================================
-- 7. ACTIVE SESSIONS
-- ==============================================================================
CREATE TABLE IF NOT EXISTS active_sessions (
    session_id    VARCHAR(150) PRIMARY KEY,
    reg_no        VARCHAR(100) NOT NULL,
    username      VARCHAR(100),
    role          VARCHAR(50),
    ip_address    VARCHAR(100),
    user_agent    TEXT,
    device_info   TEXT,
    created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_activity TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_active     BOOLEAN DEFAULT TRUE
);
CREATE INDEX IF NOT EXISTS idx_sessions_reg_no ON active_sessions (reg_no);
CREATE INDEX IF NOT EXISTS idx_sessions_active ON active_sessions (is_active);

-- ==============================================================================
-- 8. FACE PROFILES & EMBEDDINGS (Staff)
-- ==============================================================================
CREATE TABLE IF NOT EXISTS face_profiles (
    id         SERIAL PRIMARY KEY,
    user_id    INTEGER REFERENCES users(id) ON DELETE CASCADE,
    reg_no     VARCHAR(64) UNIQUE,
    name       VARCHAR(160),
    dept       VARCHAR(160),
    embedding  vector(512),
    embeddings JSONB,
    image_path TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_face_profiles_reg_no ON face_profiles (reg_no);

CREATE TABLE IF NOT EXISTS face_embedding_samples (
    id           SERIAL PRIMARY KEY,
    reg_no       VARCHAR(64) NOT NULL,
    sample_type  VARCHAR(50) DEFAULT 'kiosk',
    source_table VARCHAR(64) DEFAULT 'users',
    embedding    vector(512),
    created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    confidence   DOUBLE PRECISION
);
ALTER TABLE face_embedding_samples ADD COLUMN IF NOT EXISTS source_table VARCHAR(64) DEFAULT 'users';
ALTER TABLE face_embedding_samples ADD COLUMN IF NOT EXISTS confidence   DOUBLE PRECISION;
CREATE INDEX IF NOT EXISTS idx_face_embedding_samples_reg_no         ON face_embedding_samples (reg_no);
CREATE INDEX IF NOT EXISTS idx_face_embedding_samples_reg_no_created ON face_embedding_samples (reg_no, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_face_embedding_samples_source         ON face_embedding_samples (source_table);

CREATE TABLE IF NOT EXISTS face_training_runs (
    id               SERIAL PRIMARY KEY,
    status           VARCHAR(32) DEFAULT 'running',
    notes            TEXT,
    started_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at     TIMESTAMP,
    profiles_updated INTEGER DEFAULT 0,
    updated_profiles INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS face_reregister_requests (
    id               SERIAL PRIMARY KEY,
    staff_reg_no     VARCHAR(64) NOT NULL,
    staff_name       VARCHAR(160),
    dept             VARCHAR(160),
    request_date     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status           VARCHAR(50) DEFAULT 'pending',
    hod_approved     BOOLEAN DEFAULT FALSE,
    admin_approved   BOOLEAN DEFAULT FALSE,
    rejection_reason TEXT,
    approved_by      VARCHAR(120),
    approved_at      TIMESTAMP,
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    notes            TEXT,
    reason           TEXT
);
ALTER TABLE face_reregister_requests ADD COLUMN IF NOT EXISTS notes  TEXT;
ALTER TABLE face_reregister_requests ADD COLUMN IF NOT EXISTS reason TEXT;

-- ==============================================================================
-- 9. STUDENT FACE MODULE
-- ==============================================================================
CREATE TABLE IF NOT EXISTS student_face_profiles (
    reg_no        VARCHAR(64) PRIMARY KEY,
    name          VARCHAR(160) NOT NULL,
    dept          VARCHAR(160) NOT NULL,
    embeddings    JSONB NOT NULL,
    registered_by VARCHAR(64),
    created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS student_face_embeddings (
    id               SERIAL PRIMARY KEY,
    reg_no           VARCHAR(64),
    embedding        vector(512),
    is_active        BOOLEAN DEFAULT TRUE,
    quality_score    DOUBLE PRECISION,
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    student_reg_no   VARCHAR(64),
    pose_angle       VARCHAR(32),
    embedding_vector BYTEA,
    liveness_score   REAL DEFAULT 1.0
);
ALTER TABLE student_face_embeddings ADD COLUMN IF NOT EXISTS student_reg_no   VARCHAR(64);
ALTER TABLE student_face_embeddings ADD COLUMN IF NOT EXISTS pose_angle       VARCHAR(32);
ALTER TABLE student_face_embeddings ADD COLUMN IF NOT EXISTS embedding_vector BYTEA;
ALTER TABLE student_face_embeddings ADD COLUMN IF NOT EXISTS liveness_score   REAL DEFAULT 1.0;
ALTER TABLE student_face_embeddings ALTER COLUMN reg_no DROP NOT NULL;
-- Add FK only if students table exists and column is set
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'student_face_embeddings_reg_no_fkey'
  ) THEN
    ALTER TABLE student_face_embeddings
      ADD CONSTRAINT student_face_embeddings_reg_no_fkey
      FOREIGN KEY (reg_no) REFERENCES students(reg_no) ON DELETE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_sfe_reg_lower   ON student_face_embeddings (lower(reg_no));
CREATE INDEX IF NOT EXISTS idx_sfe_student_reg ON student_face_embeddings (student_reg_no);

CREATE TABLE IF NOT EXISTS student_face_prototypes (
    id              SERIAL PRIMARY KEY,
    reg_no          VARCHAR(64) UNIQUE,
    prototype       vector(512),
    sample_count    INTEGER DEFAULT 1,
    updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    average_quality REAL DEFAULT 0.85,
    student_reg_no  VARCHAR(64),
    centroid_vector BYTEA,
    total_samples   INTEGER DEFAULT 0
);
ALTER TABLE student_face_prototypes ADD COLUMN IF NOT EXISTS student_reg_no  VARCHAR(64);
ALTER TABLE student_face_prototypes ADD COLUMN IF NOT EXISTS centroid_vector BYTEA;
ALTER TABLE student_face_prototypes ADD COLUMN IF NOT EXISTS total_samples   INTEGER DEFAULT 0;
ALTER TABLE student_face_prototypes ADD COLUMN IF NOT EXISTS average_quality REAL DEFAULT 0.85;
ALTER TABLE student_face_prototypes ALTER COLUMN reg_no DROP NOT NULL;
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'student_face_prototypes_reg_no_fkey'
  ) THEN
    ALTER TABLE student_face_prototypes
      ADD CONSTRAINT student_face_prototypes_reg_no_fkey
      FOREIGN KEY (reg_no) REFERENCES students(reg_no) ON DELETE CASCADE;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS idx_student_face_prototypes_stu_reg ON student_face_prototypes (student_reg_no);

CREATE TABLE IF NOT EXISTS student_face_requests (
    id                  SERIAL PRIMARY KEY,
    reg_no              VARCHAR(64),
    name                VARCHAR(160),
    dept                VARCHAR(160),
    year                INTEGER,
    section             VARCHAR(16),
    photo_url           TEXT,
    status              VARCHAR(32) DEFAULT 'pending',
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    mentor_staff_reg_no VARCHAR(64),
    student_reg_no      VARCHAR(64),
    student_name        VARCHAR(160),
    request_type        VARCHAR(50) DEFAULT 'REGISTRATION',
    sample_count        INTEGER DEFAULT 0,
    quality_score       REAL DEFAULT 0.0,
    student_notes       TEXT,
    advisor_feedback    TEXT,
    hod_feedback        TEXT,
    admin_feedback      TEXT,
    review_status       VARCHAR(30) DEFAULT 'PENDING',
    reviewed_by         VARCHAR(64),
    reviewed_at         TIMESTAMP,
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    embeddings          TEXT
);
ALTER TABLE student_face_requests ADD COLUMN IF NOT EXISTS mentor_staff_reg_no VARCHAR(64);
ALTER TABLE student_face_requests ADD COLUMN IF NOT EXISTS student_reg_no      VARCHAR(64);
ALTER TABLE student_face_requests ADD COLUMN IF NOT EXISTS student_name        VARCHAR(160);
ALTER TABLE student_face_requests ADD COLUMN IF NOT EXISTS request_type        VARCHAR(50) DEFAULT 'REGISTRATION';
ALTER TABLE student_face_requests ADD COLUMN IF NOT EXISTS sample_count        INTEGER DEFAULT 0;
ALTER TABLE student_face_requests ADD COLUMN IF NOT EXISTS quality_score       REAL DEFAULT 0.0;
ALTER TABLE student_face_requests ADD COLUMN IF NOT EXISTS student_notes       TEXT;
ALTER TABLE student_face_requests ADD COLUMN IF NOT EXISTS advisor_feedback    TEXT;
ALTER TABLE student_face_requests ADD COLUMN IF NOT EXISTS hod_feedback        TEXT;
ALTER TABLE student_face_requests ADD COLUMN IF NOT EXISTS admin_feedback      TEXT;
ALTER TABLE student_face_requests ADD COLUMN IF NOT EXISTS review_status       VARCHAR(30) DEFAULT 'PENDING';
ALTER TABLE student_face_requests ADD COLUMN IF NOT EXISTS reviewed_by         VARCHAR(64);
ALTER TABLE student_face_requests ADD COLUMN IF NOT EXISTS reviewed_at         TIMESTAMP;
ALTER TABLE student_face_requests ADD COLUMN IF NOT EXISTS updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE student_face_requests ADD COLUMN IF NOT EXISTS embeddings          TEXT;
ALTER TABLE student_face_requests ALTER COLUMN reg_no    DROP NOT NULL;
ALTER TABLE student_face_requests ALTER COLUMN name      DROP NOT NULL;
ALTER TABLE student_face_requests ALTER COLUMN dept      DROP NOT NULL;
ALTER TABLE student_face_requests ALTER COLUMN photo_url DROP NOT NULL;

CREATE INDEX IF NOT EXISTS idx_stu_face_req_stu    ON student_face_requests (student_reg_no, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_stu_face_req_mentor ON student_face_requests (mentor_staff_reg_no, status);

-- ==============================================================================
-- 10. KIOSK
-- ==============================================================================
CREATE TABLE IF NOT EXISTS kiosk_sessions (
    session_uuid UUID PRIMARY KEY,
    staff_reg_no VARCHAR(64) NOT NULL,
    started_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    ended_at     TIMESTAMP,
    total_scans  INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS kiosk_attendance_logs (
    id               SERIAL PRIMARY KEY,
    session_uuid     UUID REFERENCES kiosk_sessions(session_uuid),
    reg_no           VARCHAR(64),
    name             VARCHAR(160),
    dept             VARCHAR(160),
    scanned_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    similarity_score DOUBLE PRECISION,
    status           VARCHAR(32) DEFAULT 'Present',
    student_reg_no   VARCHAR(64),
    matched_score    NUMERIC
);
ALTER TABLE kiosk_attendance_logs ADD COLUMN IF NOT EXISTS student_reg_no VARCHAR(64);
ALTER TABLE kiosk_attendance_logs ADD COLUMN IF NOT EXISTS matched_score   NUMERIC;
ALTER TABLE kiosk_attendance_logs ALTER COLUMN reg_no DROP NOT NULL;
ALTER TABLE kiosk_attendance_logs ALTER COLUMN name   DROP NOT NULL;
ALTER TABLE kiosk_attendance_logs ALTER COLUMN dept   DROP NOT NULL;

-- ==============================================================================
-- 11. STAFF ATTENDANCE
-- ==============================================================================
CREATE TABLE IF NOT EXISTS attendance (
    id                 SERIAL PRIMARY KEY,
    reg_no             VARCHAR(64) NOT NULL,
    name               VARCHAR(160),
    dept               VARCHAR(160),
    role               VARCHAR(80) DEFAULT 'staff',
    timestamp          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    date               DATE DEFAULT CURRENT_DATE,
    time               VARCHAR(50),
    status             VARCHAR(50) DEFAULT 'check_in',
    device_id          VARCHAR(120),
    location           VARCHAR(255),
    sub_status         VARCHAR(50) DEFAULT '',
    document_proof_url TEXT,
    attendance_value   DOUBLE PRECISION DEFAULT 1.0,
    class_div          VARCHAR(20) DEFAULT ''
);
ALTER TABLE attendance ADD COLUMN IF NOT EXISTS sub_status         VARCHAR(50) DEFAULT '';
ALTER TABLE attendance ADD COLUMN IF NOT EXISTS document_proof_url TEXT;
ALTER TABLE attendance ADD COLUMN IF NOT EXISTS attendance_value   DOUBLE PRECISION DEFAULT 1.0;
ALTER TABLE attendance ADD COLUMN IF NOT EXISTS class_div          VARCHAR(20) DEFAULT '';

CREATE INDEX IF NOT EXISTS idx_attendance_reg_no           ON attendance (reg_no);
CREATE INDEX IF NOT EXISTS idx_attendance_dept             ON attendance (dept);
CREATE INDEX IF NOT EXISTS idx_attendance_timestamp        ON attendance (timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_attendance_reg_no_timestamp ON attendance (reg_no, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_attendance_dept_timestamp   ON attendance (dept, timestamp DESC);

CREATE TABLE IF NOT EXISTS attendance_logs (
    id               SERIAL PRIMARY KEY,
    user_id          INTEGER,
    reg_no           VARCHAR(64),
    name             VARCHAR(160),
    dept             VARCHAR(160),
    role             VARCHAR(80) DEFAULT 'staff',
    timestamp        TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    date             DATE DEFAULT CURRENT_DATE,
    time             VARCHAR(50),
    type             VARCHAR(50) DEFAULT 'checkin',
    status           VARCHAR(50) DEFAULT 'Present',
    attendance_value NUMERIC DEFAULT 1.0,
    latitude         NUMERIC,
    longitude        NUMERIC,
    accuracy_meters  NUMERIC,
    ip_address       VARCHAR(80),
    device_id        VARCHAR(120),
    session_id       VARCHAR(120),
    source           VARCHAR(50) DEFAULT 'app',
    is_mocked        BOOLEAN DEFAULT FALSE
);
CREATE INDEX IF NOT EXISTS idx_att_logs_reg_no ON attendance_logs (reg_no);
CREATE INDEX IF NOT EXISTS idx_att_logs_dept   ON attendance_logs (dept);
CREATE INDEX IF NOT EXISTS idx_att_logs_date   ON attendance_logs (date);

CREATE TABLE IF NOT EXISTS attendance_corrections (
    id                  SERIAL PRIMARY KEY,
    reg_no              VARCHAR(100) NOT NULL,
    user_name           VARCHAR(150),
    role                VARCHAR(50),
    dept                VARCHAR(100),
    requested_date      DATE NOT NULL,
    requested_check_in  VARCHAR(50),
    requested_check_out VARCHAR(50),
    requested_status    VARCHAR(50) DEFAULT 'Present',
    reason              TEXT NOT NULL,
    status              VARCHAR(50) DEFAULT 'Pending',
    reviewer_reg_no     VARCHAR(100),
    reviewer_name       VARCHAR(150),
    review_remarks      TEXT,
    reviewed_at         TIMESTAMP,
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_att_corr_reg_no ON attendance_corrections (reg_no);
CREATE INDEX IF NOT EXISTS idx_att_corr_dept   ON attendance_corrections (dept);
CREATE INDEX IF NOT EXISTS idx_att_corr_status ON attendance_corrections (status);

CREATE TABLE IF NOT EXISTS attendance_duration_settings (
    id                  SERIAL PRIMARY KEY,
    role                VARCHAR(80) DEFAULT 'staff',
    min_duration_hours  NUMERIC DEFAULT 8.0,
    half_day_min_hours  NUMERIC DEFAULT 4.0,
    slot_half           VARCHAR(20) DEFAULT 'full_day',
    grace_period_mins   INTEGER DEFAULT 15,
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    slot_type           VARCHAR(20) DEFAULT 'check_in',
    is_enabled          BOOLEAN DEFAULT TRUE,
    first_half_end      VARCHAR(10) DEFAULT '13:00',
    second_half_end     VARCHAR(10) DEFAULT '17:30',
    slot_number         INTEGER DEFAULT 1,
    start_time          VARCHAR(20) DEFAULT '08:45',
    duration_minutes    INTEGER DEFAULT 50,
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
ALTER TABLE attendance_duration_settings ADD COLUMN IF NOT EXISTS slot_type        VARCHAR(20) DEFAULT 'check_in';
ALTER TABLE attendance_duration_settings ADD COLUMN IF NOT EXISTS is_enabled       BOOLEAN DEFAULT TRUE;
ALTER TABLE attendance_duration_settings ADD COLUMN IF NOT EXISTS first_half_end   VARCHAR(10) DEFAULT '13:00';
ALTER TABLE attendance_duration_settings ADD COLUMN IF NOT EXISTS second_half_end  VARCHAR(10) DEFAULT '17:30';
ALTER TABLE attendance_duration_settings ADD COLUMN IF NOT EXISTS slot_number      INTEGER DEFAULT 1;
ALTER TABLE attendance_duration_settings ADD COLUMN IF NOT EXISTS start_time       VARCHAR(20) DEFAULT '08:45';
ALTER TABLE attendance_duration_settings ADD COLUMN IF NOT EXISTS duration_minutes INTEGER DEFAULT 50;
ALTER TABLE attendance_duration_settings ADD COLUMN IF NOT EXISTS created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP;

CREATE TABLE IF NOT EXISTS attendance_regularisation_window (
    id                  INTEGER PRIMARY KEY DEFAULT 1,
    max_correction_days INTEGER DEFAULT 7,
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_by          VARCHAR(100)
);
INSERT INTO attendance_regularisation_window (id, max_correction_days) VALUES (1, 7)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS daily_attendance_status (
    id                   SERIAL PRIMARY KEY,
    reg_no               VARCHAR(64) NOT NULL,
    date                 DATE NOT NULL,
    in_time              TIME,
    out_time             TIME,
    status               VARCHAR(50) DEFAULT 'Present',
    sub_status           VARCHAR(50) DEFAULT '',
    first_half_status    VARCHAR(50) DEFAULT 'Pending',
    second_half_status   VARCHAR(50) DEFAULT 'Pending',
    first_half_in_time   VARCHAR(50),
    first_half_out_time  VARCHAR(50),
    second_half_in_time  VARCHAR(50),
    second_half_out_time VARCHAR(50),
    leave_type           VARCHAR(100),
    absent_reason        TEXT,
    document_proof_url   TEXT,
    attendance_value     DOUBLE PRECISION DEFAULT 1.0,
    is_regularised       BOOLEAN DEFAULT FALSE,
    marked_by            VARCHAR(100) DEFAULT 'System',
    dept                 VARCHAR(160),
    created_at           TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at           TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_manual_override   BOOLEAN DEFAULT FALSE,
    override_by          VARCHAR(100),
    override_reason      TEXT,
    name                 VARCHAR(160),
    role                 VARCHAR(50),
    marked_at            TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    leave_request_id     INTEGER,
    class_div            VARCHAR(20) DEFAULT '',
    UNIQUE (reg_no, date)
);
ALTER TABLE daily_attendance_status ADD COLUMN IF NOT EXISTS dept              VARCHAR(160);
ALTER TABLE daily_attendance_status ADD COLUMN IF NOT EXISTS created_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE daily_attendance_status ADD COLUMN IF NOT EXISTS updated_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE daily_attendance_status ADD COLUMN IF NOT EXISTS is_manual_override BOOLEAN DEFAULT FALSE;
ALTER TABLE daily_attendance_status ADD COLUMN IF NOT EXISTS override_by       VARCHAR(100);
ALTER TABLE daily_attendance_status ADD COLUMN IF NOT EXISTS override_reason   TEXT;
ALTER TABLE daily_attendance_status ADD COLUMN IF NOT EXISTS name              VARCHAR(160);
ALTER TABLE daily_attendance_status ADD COLUMN IF NOT EXISTS role              VARCHAR(50);
ALTER TABLE daily_attendance_status ADD COLUMN IF NOT EXISTS marked_at         TIMESTAMP DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE daily_attendance_status ADD COLUMN IF NOT EXISTS leave_request_id  INTEGER;
ALTER TABLE daily_attendance_status ADD COLUMN IF NOT EXISTS class_div         VARCHAR(20) DEFAULT '';

CREATE INDEX IF NOT EXISTS idx_daily_attendance_status_reg_no      ON daily_attendance_status (reg_no);
CREATE INDEX IF NOT EXISTS idx_daily_attendance_status_date        ON daily_attendance_status (date DESC);
CREATE INDEX IF NOT EXISTS idx_daily_attendance_status_dept_date   ON daily_attendance_status (dept, date DESC);
CREATE INDEX IF NOT EXISTS idx_daily_attendance_status_reg_no_date ON daily_attendance_status (reg_no, date DESC);

CREATE TABLE IF NOT EXISTS morning_attendance (
    id               SERIAL PRIMARY KEY,
    reg_no           VARCHAR(64) NOT NULL,
    name             VARCHAR(160) NOT NULL,
    dept             VARCHAR(160) NOT NULL,
    date             DATE NOT NULL,
    in_time          TIME,
    status           VARCHAR(20) DEFAULT 'Present',
    attendance_value NUMERIC DEFAULT 0.5,
    marked_by        VARCHAR(120),
    marked_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (reg_no, date)
);
CREATE INDEX IF NOT EXISTS idx_morning_attendance_reg_no ON morning_attendance (reg_no);
CREATE INDEX IF NOT EXISTS idx_morning_attendance_date   ON morning_attendance (date DESC);

CREATE TABLE IF NOT EXISTS evening_attendance (
    id               SERIAL PRIMARY KEY,
    reg_no           VARCHAR(64) NOT NULL,
    name             VARCHAR(160) NOT NULL,
    dept             VARCHAR(160) NOT NULL,
    date             DATE NOT NULL,
    in_time          TIME,
    status           VARCHAR(20) DEFAULT 'Present',
    attendance_value NUMERIC DEFAULT 0.5,
    marked_by        VARCHAR(120),
    marked_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (reg_no, date)
);
CREATE INDEX IF NOT EXISTS idx_evening_attendance_reg_no ON evening_attendance (reg_no);
CREATE INDEX IF NOT EXISTS idx_evening_attendance_date   ON evening_attendance (date DESC);

CREATE TABLE IF NOT EXISTS other_staff_attendance (
    id                 SERIAL PRIMARY KEY,
    reg_no             VARCHAR(64) NOT NULL,
    name               VARCHAR(160) NOT NULL,
    dept               VARCHAR(160) NOT NULL,
    role               VARCHAR(80) NOT NULL,
    timestamp          TIMESTAMP NOT NULL,
    status             VARCHAR(20) DEFAULT 'check_in',
    device_id          VARCHAR(120),
    location           VARCHAR(255),
    sub_status         VARCHAR(50) DEFAULT '',
    document_proof_url TEXT,
    attendance_value   DOUBLE PRECISION DEFAULT 1.0
);
CREATE INDEX IF NOT EXISTS idx_other_staff_attendance_reg_no           ON other_staff_attendance (reg_no);
CREATE INDEX IF NOT EXISTS idx_other_staff_attendance_timestamp        ON other_staff_attendance (timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_other_staff_attendance_reg_no_timestamp ON other_staff_attendance (reg_no, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_other_staff_attendance_dept_timestamp   ON other_staff_attendance (dept, timestamp DESC);

-- ==============================================================================
-- 12. STUDENT ATTENDANCE
-- ==============================================================================
CREATE TABLE IF NOT EXISTS student_attendance (
    id               SERIAL PRIMARY KEY,
    reg_no           VARCHAR(64),
    session_id       VARCHAR(64),
    date             DATE NOT NULL,
    time             TIME,
    status           VARCHAR(32) DEFAULT 'Present',
    confidence       DOUBLE PRECISION,
    marked_by        VARCHAR(64),
    marked_via       VARCHAR(32) DEFAULT 'kiosk',
    device_id        VARCHAR(120),
    period_number    INTEGER,
    is_auto_declared BOOLEAN DEFAULT FALSE,
    day_type         VARCHAR(20) DEFAULT 'REGULAR',
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    student_reg_no   VARCHAR(64),
    session          VARCHAR(64),
    subject_code     VARCHAR(50),
    subject_name     VARCHAR(160),
    faculty_reg_no   VARCHAR(64),
    marked_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    checkout_time    TIMESTAMP,
    confidence_score DOUBLE PRECISION
);
ALTER TABLE student_attendance ADD COLUMN IF NOT EXISTS student_reg_no   VARCHAR(64);
ALTER TABLE student_attendance ADD COLUMN IF NOT EXISTS session          VARCHAR(64);
ALTER TABLE student_attendance ADD COLUMN IF NOT EXISTS subject_code     VARCHAR(50);
ALTER TABLE student_attendance ADD COLUMN IF NOT EXISTS subject_name     VARCHAR(160);
ALTER TABLE student_attendance ADD COLUMN IF NOT EXISTS faculty_reg_no   VARCHAR(64);
ALTER TABLE student_attendance ADD COLUMN IF NOT EXISTS marked_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE student_attendance ADD COLUMN IF NOT EXISTS checkout_time    TIMESTAMP;
ALTER TABLE student_attendance ADD COLUMN IF NOT EXISTS confidence_score DOUBLE PRECISION;
ALTER TABLE student_attendance ALTER COLUMN reg_no DROP NOT NULL;
-- Re-add FK safely
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'student_attendance_reg_no_fkey'
  ) THEN
    ALTER TABLE student_attendance
      ADD CONSTRAINT student_attendance_reg_no_fkey
      FOREIGN KEY (reg_no) REFERENCES students(reg_no) ON DELETE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_sa_reg_date_session ON student_attendance (reg_no, date);
CREATE INDEX IF NOT EXISTS idx_sa_session_status   ON student_attendance (session_id, status);
CREATE INDEX IF NOT EXISTS idx_sa_date_period      ON student_attendance (date, period_number);
CREATE INDEX IF NOT EXISTS idx_stu_att_reg_date    ON student_attendance (student_reg_no, date DESC);
CREATE INDEX IF NOT EXISTS idx_stu_att_date_reg    ON student_attendance (date DESC, student_reg_no);
CREATE INDEX IF NOT EXISTS idx_stu_att_period      ON student_attendance (reg_no, date, period_number);

CREATE TABLE IF NOT EXISTS student_academic_day_status (
    id              SERIAL PRIMARY KEY,
    student_reg_no  VARCHAR(64) NOT NULL,
    date            DATE NOT NULL,
    day_type        VARCHAR(30) NOT NULL DEFAULT 'NORMAL',
    reason          TEXT,
    leave_request_id INTEGER,
    declared_by     VARCHAR(64) DEFAULT 'SYSTEM',
    declared_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (student_reg_no, date)
);
CREATE INDEX IF NOT EXISTS idx_sads_reg_date ON student_academic_day_status (student_reg_no, date);
CREATE INDEX IF NOT EXISTS idx_sads_date     ON student_academic_day_status (date, day_type);

-- ==============================================================================
-- 13. CLASS ATTENDANCE SESSIONS
-- ==============================================================================
CREATE TABLE IF NOT EXISTS class_attendance_sessions (
    id                   VARCHAR(64) PRIMARY KEY
                         DEFAULT ('cas_' || floor(random() * 10000000)::text),
    staff_reg_no         VARCHAR(64),
    dept                 VARCHAR(160),
    year                 INTEGER,
    section              VARCHAR(16),
    subject              VARCHAR(160),
    date                 DATE NOT NULL,
    period_number        INTEGER,
    start_time           TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    end_time             TIMESTAMP,
    status               VARCHAR(32) DEFAULT 'active',
    created_at           TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    session_id           VARCHAR(64),
    period_numbers       VARCHAR(50),
    scheduled_end_time   TIME,
    subject_name         VARCHAR(160),
    subject_code         VARCHAR(64),
    batch                VARCHAR(50),
    semester             INTEGER,
    scheduled_start_time VARCHAR(20),
    checkin_opened_at    TIMESTAMP,
    checkout_opened_at   TIMESTAMP,
    checkin_closed_at    TIMESTAMP,
    checkout_closed_at   TIMESTAMP
);
ALTER TABLE class_attendance_sessions ADD COLUMN IF NOT EXISTS session_id           VARCHAR(64);
ALTER TABLE class_attendance_sessions ADD COLUMN IF NOT EXISTS period_numbers       VARCHAR(50);
ALTER TABLE class_attendance_sessions ADD COLUMN IF NOT EXISTS scheduled_end_time   TIME;
ALTER TABLE class_attendance_sessions ADD COLUMN IF NOT EXISTS subject_name         VARCHAR(160);
ALTER TABLE class_attendance_sessions ADD COLUMN IF NOT EXISTS subject_code         VARCHAR(64);
ALTER TABLE class_attendance_sessions ADD COLUMN IF NOT EXISTS batch               VARCHAR(50);
ALTER TABLE class_attendance_sessions ADD COLUMN IF NOT EXISTS semester            INTEGER;
ALTER TABLE class_attendance_sessions ADD COLUMN IF NOT EXISTS scheduled_start_time VARCHAR(20);
ALTER TABLE class_attendance_sessions ADD COLUMN IF NOT EXISTS checkin_opened_at   TIMESTAMP;
ALTER TABLE class_attendance_sessions ADD COLUMN IF NOT EXISTS checkout_opened_at  TIMESTAMP;
ALTER TABLE class_attendance_sessions ADD COLUMN IF NOT EXISTS checkin_closed_at   TIMESTAMP;
ALTER TABLE class_attendance_sessions ADD COLUMN IF NOT EXISTS checkout_closed_at  TIMESTAMP;

CREATE INDEX IF NOT EXISTS idx_cas_staff_date         ON class_attendance_sessions (staff_reg_no, date);
CREATE INDEX IF NOT EXISTS idx_cas_date_dept          ON class_attendance_sessions (date, dept);
CREATE INDEX IF NOT EXISTS idx_cas_status             ON class_attendance_sessions (status, date);
CREATE INDEX IF NOT EXISTS idx_cas_date_status_cohort ON class_attendance_sessions (date, status, lower(dept), semester, lower(section));

CREATE TABLE IF NOT EXISTS class_attendance_session_students (
    id             SERIAL PRIMARY KEY,
    session_id     INTEGER,
    student_reg_no VARCHAR(64) NOT NULL,
    student_name   VARCHAR(160),
    status         VARCHAR(50) DEFAULT 'present',
    checkin_time   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    checkout_time  TIMESTAMP,
    marked_by      VARCHAR(64),
    created_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS class_session_staff_prefs (
    id           SERIAL PRIMARY KEY,
    staff_reg_no VARCHAR(64) NOT NULL,
    session_id   VARCHAR(64),
    pref_key     VARCHAR(64),
    pref_value   TEXT,
    updated_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ==============================================================================
-- 14. TIMETABLE
-- ==============================================================================
CREATE TABLE IF NOT EXISTS class_timetable (
    id            SERIAL PRIMARY KEY,
    dept          VARCHAR(160) NOT NULL,
    year          INTEGER NOT NULL,
    section       VARCHAR(16) NOT NULL,
    day_of_week   VARCHAR(20) NOT NULL,
    period_number INTEGER NOT NULL,
    subject       VARCHAR(160) NOT NULL,
    staff_reg_no  VARCHAR(64) NOT NULL,
    created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    batch         VARCHAR(20) DEFAULT '2022-2026',
    semester      INTEGER DEFAULT 1,
    subject_code  VARCHAR(64),
    subject_name  VARCHAR(160),
    room_or_lab   VARCHAR(100),
    is_lab_block  BOOLEAN DEFAULT FALSE,
    lab_batch     VARCHAR(20) DEFAULT 'ALL',
    created_by    VARCHAR(64) DEFAULT 'SYSTEM',
    updated_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
ALTER TABLE class_timetable ADD COLUMN IF NOT EXISTS batch        VARCHAR(20) DEFAULT '2022-2026';
ALTER TABLE class_timetable ADD COLUMN IF NOT EXISTS semester     INTEGER DEFAULT 1;
ALTER TABLE class_timetable ADD COLUMN IF NOT EXISTS subject_code VARCHAR(64);
ALTER TABLE class_timetable ADD COLUMN IF NOT EXISTS subject_name VARCHAR(160);
ALTER TABLE class_timetable ADD COLUMN IF NOT EXISTS room_or_lab  VARCHAR(100);
ALTER TABLE class_timetable ADD COLUMN IF NOT EXISTS is_lab_block BOOLEAN DEFAULT FALSE;
ALTER TABLE class_timetable ADD COLUMN IF NOT EXISTS lab_batch    VARCHAR(20) DEFAULT 'ALL';
ALTER TABLE class_timetable ADD COLUMN IF NOT EXISTS created_by   VARCHAR(64) DEFAULT 'SYSTEM';
ALTER TABLE class_timetable ADD COLUMN IF NOT EXISTS updated_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP;

CREATE INDEX IF NOT EXISTS idx_ct_cohort_day ON class_timetable (lower(day_of_week), lower(dept), semester, lower(section));
CREATE INDEX IF NOT EXISTS idx_ct_staff_day  ON class_timetable (staff_reg_no, lower(day_of_week));

-- ==============================================================================
-- 15. SUBJECT FACULTY ALLOCATIONS (Critical for timetable feature)
-- ==============================================================================
CREATE TABLE IF NOT EXISTS subject_faculty_allocations (
    id           SERIAL PRIMARY KEY,
    dept         VARCHAR(160) NOT NULL,
    batch        VARCHAR(50) NOT NULL,
    semester     INTEGER NOT NULL,
    section      VARCHAR(20) NOT NULL,
    subject_code VARCHAR(50) NOT NULL,
    subject_name VARCHAR(255) NOT NULL,
    subject_type VARCHAR(50) DEFAULT 'Theory',
    staff_reg_no VARCHAR(64) NOT NULL,
    staff_name   VARCHAR(160),
    weekly_hours INTEGER DEFAULT 4,
    created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
ALTER TABLE subject_faculty_allocations ADD COLUMN IF NOT EXISTS subject_type VARCHAR(50) DEFAULT 'Theory';
ALTER TABLE subject_faculty_allocations ADD COLUMN IF NOT EXISTS staff_name   VARCHAR(160);
ALTER TABLE subject_faculty_allocations ADD COLUMN IF NOT EXISTS weekly_hours INTEGER DEFAULT 4;
ALTER TABLE subject_faculty_allocations ADD COLUMN IF NOT EXISTS updated_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP;

CREATE INDEX IF NOT EXISTS idx_sfa_dept_sem ON subject_faculty_allocations (dept, batch, semester, section);

-- ==============================================================================
-- 16. CLASS ADVISORS
-- ==============================================================================
CREATE TABLE IF NOT EXISTS class_advisors (
    id            SERIAL PRIMARY KEY,
    dept          VARCHAR(160) NOT NULL,
    year          INTEGER NOT NULL,
    section       VARCHAR(16) NOT NULL,
    staff_reg_no  VARCHAR(64) NOT NULL,
    created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    batch         VARCHAR(50),
    semester      INTEGER,
    advisor_type  VARCHAR(50) DEFAULT 'primary',
    is_active     BOOLEAN DEFAULT TRUE,
    year_of_study INTEGER DEFAULT 1,
    academic_year VARCHAR(50),
    assigned_by   VARCHAR(120),
    advisor_name  VARCHAR(160),
    effective_from DATE,
    effective_to   DATE,
    assigned_role  VARCHAR(50) DEFAULT 'admin',
    UNIQUE (dept, year, section)
);
ALTER TABLE class_advisors ADD COLUMN IF NOT EXISTS batch         VARCHAR(50);
ALTER TABLE class_advisors ADD COLUMN IF NOT EXISTS semester      INTEGER;
ALTER TABLE class_advisors ADD COLUMN IF NOT EXISTS advisor_type  VARCHAR(50) DEFAULT 'primary';
ALTER TABLE class_advisors ADD COLUMN IF NOT EXISTS is_active     BOOLEAN DEFAULT TRUE;
ALTER TABLE class_advisors ADD COLUMN IF NOT EXISTS year_of_study INTEGER DEFAULT 1;
ALTER TABLE class_advisors ADD COLUMN IF NOT EXISTS academic_year VARCHAR(50);
ALTER TABLE class_advisors ADD COLUMN IF NOT EXISTS assigned_by   VARCHAR(120);
ALTER TABLE class_advisors ADD COLUMN IF NOT EXISTS advisor_name  VARCHAR(160);
ALTER TABLE class_advisors ADD COLUMN IF NOT EXISTS effective_from DATE;
ALTER TABLE class_advisors ADD COLUMN IF NOT EXISTS effective_to  DATE;
ALTER TABLE class_advisors ADD COLUMN IF NOT EXISTS assigned_role VARCHAR(50) DEFAULT 'admin';

CREATE INDEX IF NOT EXISTS idx_class_adv_staff    ON class_advisors (staff_reg_no);
CREATE INDEX IF NOT EXISTS idx_class_adv_dept_sem ON class_advisors (dept, batch, semester, section);

-- ==============================================================================
-- 17. DEPARTMENT SUBJECTS
-- ==============================================================================
CREATE TABLE IF NOT EXISTS department_subjects (
    id           SERIAL PRIMARY KEY,
    dept         VARCHAR(160) NOT NULL,
    year         INTEGER NOT NULL,
    subject_code VARCHAR(64) NOT NULL,
    subject_name VARCHAR(160) NOT NULL,
    created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    short_name   VARCHAR(50),
    semester     INTEGER DEFAULT 1,
    subject_type VARCHAR(50) DEFAULT 'Theory',
    credits      INTEGER DEFAULT 3,
    weekly_hours INTEGER DEFAULT 4,
    regulation   VARCHAR(50) DEFAULT 'R2021',
    is_lab       BOOLEAN DEFAULT FALSE,
    lab_details  TEXT,
    is_active    BOOLEAN DEFAULT TRUE,
    created_by   VARCHAR(64),
    updated_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (dept, year, subject_code)
);
ALTER TABLE department_subjects ADD COLUMN IF NOT EXISTS short_name   VARCHAR(50);
ALTER TABLE department_subjects ADD COLUMN IF NOT EXISTS semester     INTEGER DEFAULT 1;
ALTER TABLE department_subjects ADD COLUMN IF NOT EXISTS subject_type VARCHAR(50) DEFAULT 'Theory';
ALTER TABLE department_subjects ADD COLUMN IF NOT EXISTS credits      INTEGER DEFAULT 3;
ALTER TABLE department_subjects ADD COLUMN IF NOT EXISTS weekly_hours INTEGER DEFAULT 4;
ALTER TABLE department_subjects ADD COLUMN IF NOT EXISTS regulation   VARCHAR(50) DEFAULT 'R2021';
ALTER TABLE department_subjects ADD COLUMN IF NOT EXISTS is_lab       BOOLEAN DEFAULT FALSE;
ALTER TABLE department_subjects ADD COLUMN IF NOT EXISTS lab_details  TEXT;
ALTER TABLE department_subjects ADD COLUMN IF NOT EXISTS is_active    BOOLEAN DEFAULT TRUE;
ALTER TABLE department_subjects ADD COLUMN IF NOT EXISTS created_by   VARCHAR(64);
ALTER TABLE department_subjects ADD COLUMN IF NOT EXISTS updated_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP;

CREATE INDEX IF NOT EXISTS idx_dept_subj_code ON department_subjects (dept, subject_code);
CREATE INDEX IF NOT EXISTS idx_dept_subj_sem  ON department_subjects (dept, semester);

-- ==============================================================================
-- 18. SUBSTITUTE ASSIGNMENTS
-- ==============================================================================
CREATE TABLE IF NOT EXISTS substitute_assignments (
    id                      SERIAL PRIMARY KEY,
    original_staff_reg_no   VARCHAR(100) NOT NULL,
    original_staff_name     VARCHAR(150),
    substitute_staff_reg_no VARCHAR(100) NOT NULL,
    substitute_staff_name   VARCHAR(150),
    dept                    VARCHAR(100),
    batch                   VARCHAR(50),
    semester                INTEGER,
    section                 VARCHAR(50),
    subject_code            VARCHAR(100),
    subject_name            VARCHAR(255),
    assignment_date         DATE NOT NULL,
    period_number           INTEGER NOT NULL,
    status                  VARCHAR(50) DEFAULT 'Assigned',
    reason                  TEXT,
    assigned_by             VARCHAR(100),
    created_at              TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_sub_orig_staff   ON substitute_assignments (original_staff_reg_no, assignment_date);
CREATE INDEX IF NOT EXISTS idx_sub_target_staff ON substitute_assignments (substitute_staff_reg_no, assignment_date);

-- ==============================================================================
-- 19. CLASS VENUE OVERRIDES
-- ==============================================================================
CREATE TABLE IF NOT EXISTS class_venue_overrides (
    id                        SERIAL PRIMARY KEY,
    timetable_slot_id         INTEGER,
    dept                      VARCHAR(160) NOT NULL,
    batch                     VARCHAR(20) NOT NULL,
    semester                  INTEGER NOT NULL,
    section                   VARCHAR(10) NOT NULL,
    day_of_week               VARCHAR(20) NOT NULL,
    period_number             INTEGER NOT NULL,
    override_date             DATE,
    original_room_or_lab      VARCHAR(100),
    new_venue_code            VARCHAR(50) NOT NULL,
    new_venue_name            VARCHAR(160),
    relocated_by_staff_reg_no VARCHAR(64) NOT NULL,
    reason                    TEXT,
    created_at                TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_cvo_date_period ON class_venue_overrides (override_date, day_of_week, period_number);

-- ==============================================================================
-- 20. CAMPUS VENUES & FACILITY CATEGORIES
-- ==============================================================================
CREATE TABLE IF NOT EXISTS campus_facility_categories (
    id            SERIAL PRIMARY KEY,
    category_code VARCHAR(64) NOT NULL UNIQUE,
    category_name VARCHAR(120) NOT NULL,
    icon_name     VARCHAR(64) DEFAULT 'domain_rounded',
    color_hex     VARCHAR(20) DEFAULT '#4F46E5',
    description   TEXT,
    is_system     BOOLEAN DEFAULT FALSE,
    is_active     BOOLEAN DEFAULT TRUE,
    created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_fac_cat_code ON campus_facility_categories (category_code);

CREATE TABLE IF NOT EXISTS campus_venues (
    id                     SERIAL PRIMARY KEY,
    venue_code             VARCHAR(64) NOT NULL UNIQUE,
    venue_name             VARCHAR(160) NOT NULL,
    capacity               INTEGER DEFAULT 60,
    created_at             TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    venue_type             VARCHAR(50) DEFAULT 'LECTURE_HALL',
    dept                   VARCHAR(160) DEFAULT 'GENERAL',
    block_building         VARCHAR(100),
    floor_number           VARCHAR(20),
    lab_workstations       INTEGER DEFAULT 0,
    equipment_amenities    TEXT,
    in_charge_staff_reg_no VARCHAR(64),
    in_charge_staff_name   VARCHAR(160),
    status                 VARCHAR(50) DEFAULT 'AVAILABLE',
    is_active              BOOLEAN DEFAULT TRUE
);
ALTER TABLE campus_venues ADD COLUMN IF NOT EXISTS venue_type            VARCHAR(50) DEFAULT 'LECTURE_HALL';
ALTER TABLE campus_venues ADD COLUMN IF NOT EXISTS dept                  VARCHAR(160) DEFAULT 'GENERAL';
ALTER TABLE campus_venues ADD COLUMN IF NOT EXISTS block_building        VARCHAR(100);
ALTER TABLE campus_venues ADD COLUMN IF NOT EXISTS floor_number         VARCHAR(20);
ALTER TABLE campus_venues ADD COLUMN IF NOT EXISTS lab_workstations     INTEGER DEFAULT 0;
ALTER TABLE campus_venues ADD COLUMN IF NOT EXISTS equipment_amenities  TEXT;
ALTER TABLE campus_venues ADD COLUMN IF NOT EXISTS in_charge_staff_reg_no VARCHAR(64);
ALTER TABLE campus_venues ADD COLUMN IF NOT EXISTS in_charge_staff_name VARCHAR(160);
ALTER TABLE campus_venues ADD COLUMN IF NOT EXISTS status               VARCHAR(50) DEFAULT 'AVAILABLE';
ALTER TABLE campus_venues ADD COLUMN IF NOT EXISTS is_active            BOOLEAN DEFAULT TRUE;

CREATE INDEX IF NOT EXISTS idx_venues_code ON campus_venues (venue_code);
CREATE INDEX IF NOT EXISTS idx_venues_dept ON campus_venues (dept);
CREATE INDEX IF NOT EXISTS idx_venues_type ON campus_venues (venue_type, dept);

-- ==============================================================================
-- 21. LEAVE MANAGEMENT
-- ==============================================================================
CREATE TABLE IF NOT EXISTS leave_settings (
    key        VARCHAR(100) PRIMARY KEY,
    value      TEXT,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_by VARCHAR(120)
);
ALTER TABLE leave_settings ADD COLUMN IF NOT EXISTS updated_by VARCHAR(120);

CREATE TABLE IF NOT EXISTS leave_carry_forward_rules (
    id                   INTEGER PRIMARY KEY DEFAULT 1,
    max_el_carry_forward INTEGER DEFAULT 15,
    max_cl_carry_forward INTEGER DEFAULT 0,
    encashment_allowed   BOOLEAN DEFAULT FALSE,
    max_encashment_days  INTEGER DEFAULT 10,
    updated_at           TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_by           VARCHAR(100)
);
INSERT INTO leave_carry_forward_rules (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS casual_leave (
    id                         SERIAL PRIMARY KEY,
    reg_no                     VARCHAR(64) NOT NULL UNIQUE,
    name                       VARCHAR(160),
    dept                       VARCHAR(160),
    current_month_cl_available NUMERIC DEFAULT 1.0,
    accumulated_cl             NUMERIC DEFAULT 0.0,
    last_updated               TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    current_month              VARCHAR(20),
    cl_used_current_month      NUMERIC DEFAULT 0,
    total_cl_available         NUMERIC DEFAULT 1,
    role                       VARCHAR(50),
    user_type                  VARCHAR(50),
    user_name                  VARCHAR(160)
);
ALTER TABLE casual_leave ADD COLUMN IF NOT EXISTS role      VARCHAR(50);
ALTER TABLE casual_leave ADD COLUMN IF NOT EXISTS user_type VARCHAR(50);
ALTER TABLE casual_leave ADD COLUMN IF NOT EXISTS user_name VARCHAR(160);
CREATE INDEX IF NOT EXISTS idx_casual_leave_reg_no        ON casual_leave (reg_no);
CREATE INDEX IF NOT EXISTS idx_casual_leave_current_month ON casual_leave (current_month);
CREATE INDEX IF NOT EXISTS idx_casual_leave_reg_no_month  ON casual_leave (reg_no, current_month);

CREATE TABLE IF NOT EXISTS earned_leave (
    id        SERIAL PRIMARY KEY,
    reg_no    VARCHAR(64) NOT NULL UNIQUE,
    balance   NUMERIC DEFAULT 0.0,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    user_name VARCHAR(160),
    dept      VARCHAR(160),
    role      VARCHAR(50)
);
ALTER TABLE earned_leave ADD COLUMN IF NOT EXISTS user_name VARCHAR(160);
ALTER TABLE earned_leave ADD COLUMN IF NOT EXISTS dept      VARCHAR(160);
ALTER TABLE earned_leave ADD COLUMN IF NOT EXISTS role      VARCHAR(50);
CREATE INDEX IF NOT EXISTS idx_earned_leave_dept ON earned_leave (dept);

CREATE TABLE IF NOT EXISTS expired_leaves (
    id             SERIAL PRIMARY KEY,
    reg_no         VARCHAR(64) NOT NULL,
    user_name      VARCHAR(160) NOT NULL,
    dept           VARCHAR(160) NOT NULL,
    role           VARCHAR(80) DEFAULT 'staff',
    leave_type     VARCHAR(50) NOT NULL,
    expired_amount NUMERIC NOT NULL,
    expiry_date    DATE NOT NULL,
    reason         VARCHAR(255) DEFAULT 'System automated expiry',
    created_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_expired_leaves_reg_no      ON expired_leaves (reg_no);
CREATE INDEX IF NOT EXISTS idx_expired_leaves_dept        ON expired_leaves (dept);
CREATE INDEX IF NOT EXISTS idx_expired_leaves_expiry_date ON expired_leaves (expiry_date DESC);

CREATE TABLE IF NOT EXISTS leave_requests (
    id               SERIAL PRIMARY KEY,
    reg_no           VARCHAR(64) NOT NULL,
    name             VARCHAR(160),
    dept             VARCHAR(160),
    leave_type       VARCHAR(50) NOT NULL,
    from_date        DATE NOT NULL,
    to_date          DATE NOT NULL,
    days             NUMERIC DEFAULT 1.0,
    reason           TEXT,
    status           VARCHAR(50) DEFAULT 'pending',
    applied_on       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    approved_by      VARCHAR(120),
    approved_on      TIMESTAMP,
    rejection_reason TEXT,
    is_half_day      BOOLEAN DEFAULT FALSE,
    which_half       VARCHAR(20),
    document_path    TEXT,
    start_date       DATE,
    end_date         DATE,
    user_reg_no      VARCHAR(64),
    user_name        VARCHAR(160),
    is_read_by_admin BOOLEAN DEFAULT FALSE,
    submission_date  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    processed_by     VARCHAR(64),
    processed_date   TIMESTAMP,
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    staff_reg_no     VARCHAR(64),
    staff_name       VARCHAR(160),
    admin_comment    TEXT
);
ALTER TABLE leave_requests ADD COLUMN IF NOT EXISTS user_reg_no      VARCHAR(64);
ALTER TABLE leave_requests ADD COLUMN IF NOT EXISTS user_name        VARCHAR(160);
ALTER TABLE leave_requests ADD COLUMN IF NOT EXISTS is_read_by_admin BOOLEAN DEFAULT FALSE;
ALTER TABLE leave_requests ADD COLUMN IF NOT EXISTS submission_date  TIMESTAMP DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE leave_requests ADD COLUMN IF NOT EXISTS processed_by     VARCHAR(64);
ALTER TABLE leave_requests ADD COLUMN IF NOT EXISTS processed_date   TIMESTAMP;
ALTER TABLE leave_requests ADD COLUMN IF NOT EXISTS created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE leave_requests ADD COLUMN IF NOT EXISTS staff_reg_no     VARCHAR(64);
ALTER TABLE leave_requests ADD COLUMN IF NOT EXISTS staff_name       VARCHAR(160);
ALTER TABLE leave_requests ADD COLUMN IF NOT EXISTS admin_comment    TEXT;

CREATE INDEX IF NOT EXISTS idx_leave_req_reg_no ON leave_requests (reg_no);
CREATE INDEX IF NOT EXISTS idx_leave_req_dates  ON leave_requests (from_date, to_date);

CREATE TABLE IF NOT EXISTS leave_request_audit_log (
    id               SERIAL PRIMARY KEY,
    leave_request_id INTEGER NOT NULL,
    action           VARCHAR(100) NOT NULL,
    performed_by     VARCHAR(64) NOT NULL,
    performed_by_name VARCHAR(160),
    comments         TEXT,
    timestamp        TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS staff_leave_requests (
    id                     SERIAL PRIMARY KEY,
    requester_reg_no       VARCHAR(64) NOT NULL,
    requester_name         VARCHAR(160) NOT NULL,
    dept                   VARCHAR(160) NOT NULL,
    requester_role         VARCHAR(80) NOT NULL,
    leave_type             VARCHAR(30) NOT NULL,
    start_date             DATE NOT NULL,
    end_date               DATE NOT NULL,
    is_half_day            BOOLEAN DEFAULT FALSE,
    which_half             VARCHAR(10),
    reason                 TEXT NOT NULL,
    document_url           TEXT,
    alternate_reg_no       VARCHAR(64),
    alternate_name         VARCHAR(160),
    alternate_dept         VARCHAR(160),
    alternate_role         VARCHAR(80),
    alternate_status       VARCHAR(20) DEFAULT 'PENDING',
    alternate_responded_at TIMESTAMP,
    alternate_remarks      TEXT,
    alternate_deadline     TIMESTAMP,
    timetable_assigned     BOOLEAN DEFAULT FALSE,
    workflow_status        VARCHAR(30) DEFAULT 'AWAITING_ALTERNATE',
    hod_status             VARCHAR(20) DEFAULT 'PENDING',
    hod_reg_no             VARCHAR(64),
    hod_name               VARCHAR(160),
    hod_remarks            TEXT,
    hod_action_at          TIMESTAMP,
    admin_status           VARCHAR(20) DEFAULT 'PENDING',
    admin_name             VARCHAR(160),
    admin_remarks          TEXT,
    admin_action_at        TIMESTAMP,
    submission_date        TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at             TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_slr_requester ON staff_leave_requests (requester_reg_no, submission_date DESC);
CREATE INDEX IF NOT EXISTS idx_slr_alternate ON staff_leave_requests (alternate_reg_no, alternate_status);
CREATE INDEX IF NOT EXISTS idx_slr_workflow  ON staff_leave_requests (workflow_status, dept);
CREATE INDEX IF NOT EXISTS idx_slr_deadline  ON staff_leave_requests (alternate_deadline) WHERE alternate_status = 'PENDING';

CREATE TABLE IF NOT EXISTS staff_leave_audit_log (
    id               SERIAL PRIMARY KEY,
    leave_request_id INTEGER NOT NULL REFERENCES staff_leave_requests(id),
    action           VARCHAR(40) NOT NULL,
    actor_reg_no     VARCHAR(64),
    actor_name       VARCHAR(160),
    actor_role       VARCHAR(30),
    previous_status  VARCHAR(30),
    new_status       VARCHAR(30),
    remarks          TEXT,
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_slal_leave_id ON staff_leave_audit_log (leave_request_id, created_at);

CREATE TABLE IF NOT EXISTS staff_leave_timetable_assignments (
    id                   SERIAL PRIMARY KEY,
    leave_request_id     INTEGER,
    period_number        INTEGER,
    alternate_staff_reg  VARCHAR(64),
    alternate_staff_name VARCHAR(160),
    subject_code         VARCHAR(50),
    status               VARCHAR(50) DEFAULT 'pending',
    created_at           TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    dept                 VARCHAR(160),
    semester             INTEGER,
    coverage_date        DATE,
    original_staff_reg   VARCHAR(64),
    day_of_week          VARCHAR(20),
    subject_name         VARCHAR(160),
    batch                VARCHAR(20),
    section              VARCHAR(10),
    room_or_lab          VARCHAR(100)
);
ALTER TABLE staff_leave_timetable_assignments ADD COLUMN IF NOT EXISTS dept             VARCHAR(160);
ALTER TABLE staff_leave_timetable_assignments ADD COLUMN IF NOT EXISTS semester         INTEGER;
ALTER TABLE staff_leave_timetable_assignments ADD COLUMN IF NOT EXISTS coverage_date    DATE;
ALTER TABLE staff_leave_timetable_assignments ADD COLUMN IF NOT EXISTS original_staff_reg VARCHAR(64);
ALTER TABLE staff_leave_timetable_assignments ADD COLUMN IF NOT EXISTS day_of_week      VARCHAR(20);
ALTER TABLE staff_leave_timetable_assignments ADD COLUMN IF NOT EXISTS subject_name     VARCHAR(160);
ALTER TABLE staff_leave_timetable_assignments ADD COLUMN IF NOT EXISTS batch            VARCHAR(20);
ALTER TABLE staff_leave_timetable_assignments ADD COLUMN IF NOT EXISTS section          VARCHAR(10);
ALTER TABLE staff_leave_timetable_assignments ADD COLUMN IF NOT EXISTS room_or_lab      VARCHAR(100);

CREATE INDEX IF NOT EXISTS idx_slta_leave_id ON staff_leave_timetable_assignments (leave_request_id);
CREATE INDEX IF NOT EXISTS idx_slta_coverage ON staff_leave_timetable_assignments (coverage_date, alternate_staff_reg);

-- ==============================================================================
-- 22. STUDENT LEAVE / OD
-- ==============================================================================
CREATE TABLE IF NOT EXISTS student_leave_od_requests (
    id                     SERIAL PRIMARY KEY,
    reg_no                 VARCHAR(64) NOT NULL,
    name                   VARCHAR(160),
    dept                   VARCHAR(160),
    year                   INTEGER,
    section                VARCHAR(16),
    request_type           VARCHAR(32) NOT NULL,
    from_date              DATE NOT NULL,
    to_date                DATE NOT NULL,
    reason                 TEXT,
    document_url           TEXT,
    status                 VARCHAR(32) DEFAULT 'pending',
    created_at             TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    student_reg_no         VARCHAR(64),
    category               VARCHAR(64),
    start_date             DATE,
    end_date               DATE,
    session_half           VARCHAR(32) DEFAULT 'FULL_DAY',
    mentor_status          VARCHAR(32) DEFAULT 'PENDING',
    mentor_staff_reg_no    VARCHAR(64),
    mentor_name            VARCHAR(160),
    mentor_remarks         TEXT,
    mentor_action_at       TIMESTAMP,
    hod_status             VARCHAR(32) DEFAULT 'PENDING',
    hod_staff_reg_no       VARCHAR(64),
    hod_name               VARCHAR(160),
    hod_remarks            TEXT,
    hod_action_at          TIMESTAMP,
    admin_status           VARCHAR(32) DEFAULT 'PENDING',
    admin_remarks          TEXT,
    admin_action_at        TIMESTAMP,
    is_attendance_credited BOOLEAN DEFAULT FALSE,
    document_proof_url     TEXT
);
ALTER TABLE student_leave_od_requests ADD COLUMN IF NOT EXISTS student_reg_no         VARCHAR(64);
ALTER TABLE student_leave_od_requests ADD COLUMN IF NOT EXISTS category               VARCHAR(64);
ALTER TABLE student_leave_od_requests ADD COLUMN IF NOT EXISTS start_date             DATE;
ALTER TABLE student_leave_od_requests ADD COLUMN IF NOT EXISTS end_date               DATE;
ALTER TABLE student_leave_od_requests ADD COLUMN IF NOT EXISTS session_half           VARCHAR(32) DEFAULT 'FULL_DAY';
ALTER TABLE student_leave_od_requests ADD COLUMN IF NOT EXISTS mentor_status          VARCHAR(32) DEFAULT 'PENDING';
ALTER TABLE student_leave_od_requests ADD COLUMN IF NOT EXISTS mentor_staff_reg_no    VARCHAR(64);
ALTER TABLE student_leave_od_requests ADD COLUMN IF NOT EXISTS mentor_name            VARCHAR(160);
ALTER TABLE student_leave_od_requests ADD COLUMN IF NOT EXISTS mentor_remarks         TEXT;
ALTER TABLE student_leave_od_requests ADD COLUMN IF NOT EXISTS mentor_action_at       TIMESTAMP;
ALTER TABLE student_leave_od_requests ADD COLUMN IF NOT EXISTS hod_status             VARCHAR(32) DEFAULT 'PENDING';
ALTER TABLE student_leave_od_requests ADD COLUMN IF NOT EXISTS hod_staff_reg_no       VARCHAR(64);
ALTER TABLE student_leave_od_requests ADD COLUMN IF NOT EXISTS hod_name               VARCHAR(160);
ALTER TABLE student_leave_od_requests ADD COLUMN IF NOT EXISTS hod_remarks            TEXT;
ALTER TABLE student_leave_od_requests ADD COLUMN IF NOT EXISTS hod_action_at          TIMESTAMP;
ALTER TABLE student_leave_od_requests ADD COLUMN IF NOT EXISTS admin_status           VARCHAR(32) DEFAULT 'PENDING';
ALTER TABLE student_leave_od_requests ADD COLUMN IF NOT EXISTS admin_remarks          TEXT;
ALTER TABLE student_leave_od_requests ADD COLUMN IF NOT EXISTS admin_action_at        TIMESTAMP;
ALTER TABLE student_leave_od_requests ADD COLUMN IF NOT EXISTS is_attendance_credited BOOLEAN DEFAULT FALSE;
ALTER TABLE student_leave_od_requests ADD COLUMN IF NOT EXISTS document_proof_url     TEXT;
CREATE INDEX IF NOT EXISTS idx_stu_leave_reg ON student_leave_od_requests (student_reg_no, created_at DESC);

CREATE TABLE IF NOT EXISTS student_leave_od_action_history (
    id               SERIAL PRIMARY KEY,
    request_id       INTEGER NOT NULL REFERENCES student_leave_od_requests(id),
    action           VARCHAR(32) NOT NULL,
    action_by        VARCHAR(64) NOT NULL,
    action_by_role   VARCHAR(32) NOT NULL,
    notes            TEXT,
    action_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    student_reg_no   VARCHAR(64),
    actor_role       VARCHAR(30),
    actor_reg_no     VARCHAR(64),
    actor_name       VARCHAR(160),
    previous_status  VARCHAR(30),
    new_status       VARCHAR(30),
    remarks          TEXT,
    metadata_json    TEXT,
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
ALTER TABLE student_leave_od_action_history ADD COLUMN IF NOT EXISTS student_reg_no  VARCHAR(64);
ALTER TABLE student_leave_od_action_history ADD COLUMN IF NOT EXISTS actor_role      VARCHAR(30);
ALTER TABLE student_leave_od_action_history ADD COLUMN IF NOT EXISTS actor_reg_no    VARCHAR(64);
ALTER TABLE student_leave_od_action_history ADD COLUMN IF NOT EXISTS actor_name      VARCHAR(160);
ALTER TABLE student_leave_od_action_history ADD COLUMN IF NOT EXISTS previous_status VARCHAR(30);
ALTER TABLE student_leave_od_action_history ADD COLUMN IF NOT EXISTS new_status      VARCHAR(30);
ALTER TABLE student_leave_od_action_history ADD COLUMN IF NOT EXISTS remarks         TEXT;
ALTER TABLE student_leave_od_action_history ADD COLUMN IF NOT EXISTS metadata_json   TEXT;
ALTER TABLE student_leave_od_action_history ADD COLUMN IF NOT EXISTS created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP;

CREATE INDEX IF NOT EXISTS idx_sload_req_id  ON student_leave_od_action_history (request_id, created_at);
CREATE INDEX IF NOT EXISTS idx_sload_student ON student_leave_od_action_history (student_reg_no, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_sload_actor   ON student_leave_od_action_history (actor_reg_no, created_at DESC);

-- ==============================================================================
-- 23. CCL
-- ==============================================================================
CREATE TABLE IF NOT EXISTS ccl_settings (
    key   VARCHAR(50) PRIMARY KEY,
    value VARCHAR(255)
);
CREATE TABLE IF NOT EXISTS ccl_accrual_rules (
    id             SERIAL PRIMARY KEY,
    event_type     VARCHAR(100) NOT NULL,
    min_hours      INTEGER DEFAULT 4,
    ccl_days_earned NUMERIC DEFAULT 1.0,
    validity_days  INTEGER DEFAULT 90,
    description    TEXT,
    is_active      BOOLEAN DEFAULT TRUE,
    created_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS ccl_custom_dates (
    id             SERIAL PRIMARY KEY,
    ccl_date       DATE NOT NULL UNIQUE,
    early_enabled  BOOLEAN DEFAULT FALSE,
    early_start    VARCHAR(5) DEFAULT '07:00',
    early_end      VARCHAR(5) DEFAULT '08:00',
    early_duration INTEGER DEFAULT 60,
    late_enabled   BOOLEAN DEFAULT FALSE,
    late_start     VARCHAR(5) DEFAULT '17:00',
    late_end       VARCHAR(5) DEFAULT '18:00',
    late_duration  INTEGER DEFAULT 60
);
CREATE TABLE IF NOT EXISTS ccl_earned_history (
    id            SERIAL PRIMARY KEY,
    reg_no        VARCHAR(64) NOT NULL,
    name          VARCHAR(160) NOT NULL,
    dept          VARCHAR(160) NOT NULL,
    date          DATE NOT NULL,
    time          TIME NOT NULL,
    slot_type     VARCHAR(30) NOT NULL,
    earned_points NUMERIC DEFAULT 1.0,
    created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_ccl_earned_history_reg_no ON ccl_earned_history (reg_no);
CREATE INDEX IF NOT EXISTS idx_ccl_earned_history_date   ON ccl_earned_history (date DESC);

CREATE TABLE IF NOT EXISTS comp_off_accrual (
    id          SERIAL PRIMARY KEY,
    reg_no      VARCHAR(100) NOT NULL,
    staff_name  VARCHAR(150),
    duty_date   DATE NOT NULL,
    duty_type   VARCHAR(100),
    days_earned NUMERIC DEFAULT 1.0,
    reason      TEXT,
    expiry_date DATE,
    status      VARCHAR(50) DEFAULT 'Available',
    approved_by VARCHAR(100),
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_comp_off_reg ON comp_off_accrual (reg_no, status);

-- ==============================================================================
-- 24. PERMISSION REQUESTS
-- ==============================================================================
CREATE TABLE IF NOT EXISTS permission_requests (
    id          SERIAL PRIMARY KEY,
    reg_no      VARCHAR(64) NOT NULL,
    name        VARCHAR(160),
    dept        VARCHAR(160),
    date        DATE NOT NULL,
    from_time   VARCHAR(20),
    to_time     VARCHAR(20),
    hours       NUMERIC DEFAULT 1.0,
    reason      TEXT,
    status      VARCHAR(50) DEFAULT 'pending',
    applied_on  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    approved_by VARCHAR(120),
    approved_on TIMESTAMP
);

-- ==============================================================================
-- 25. HOLIDAY & ACADEMIC CALENDAR
-- ==============================================================================
CREATE TABLE IF NOT EXISTS holiday_calendar (
    id            SERIAL PRIMARY KEY,
    holiday_date  DATE NOT NULL UNIQUE,
    holiday_name  VARCHAR(255) NOT NULL,
    holiday_type  VARCHAR(50) DEFAULT 'General',
    is_optional   BOOLEAN DEFAULT FALSE,
    academic_year VARCHAR(50),
    created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by    VARCHAR(100)
);
CREATE INDEX IF NOT EXISTS idx_holiday_date ON holiday_calendar (holiday_date);

CREATE TABLE IF NOT EXISTS academic_calendar_date_overrides (
    id                 SERIAL PRIMARY KEY,
    override_date      DATE NOT NULL UNIQUE,
    day_type           VARCHAR(30) NOT NULL DEFAULT 'WORKING_DAY',
    mapped_day_of_week VARCHAR(20) NOT NULL,
    day_order          INTEGER,
    title              VARCHAR(160),
    reason             TEXT,
    declared_by        VARCHAR(64) NOT NULL DEFAULT 'ADMIN',
    created_at         TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at         TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_acdo_date ON academic_calendar_date_overrides (override_date);

CREATE TABLE IF NOT EXISTS academic_period_configs (
    id                  SERIAL PRIMARY KEY,
    dept                VARCHAR(160) NOT NULL,
    year                INTEGER,
    period_number       INTEGER,
    start_time          TIME,
    end_time            TIME,
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    semester_type       VARCHAR(20) DEFAULT 'all',
    total_periods       INTEGER DEFAULT 7,
    period_duration_mins INTEGER DEFAULT 50,
    working_days        JSONB,
    breaks_json         JSONB,
    updated_by          VARCHAR(120)
);
ALTER TABLE academic_period_configs ADD COLUMN IF NOT EXISTS batch                VARCHAR(50) DEFAULT 'all';
ALTER TABLE academic_period_configs ADD COLUMN IF NOT EXISTS semester             INTEGER DEFAULT 0;
ALTER TABLE academic_period_configs ADD COLUMN IF NOT EXISTS section              VARCHAR(20) DEFAULT 'all';
ALTER TABLE academic_period_configs ADD COLUMN IF NOT EXISTS semester_type        VARCHAR(20) DEFAULT 'all';
ALTER TABLE academic_period_configs ADD COLUMN IF NOT EXISTS total_periods        INTEGER DEFAULT 7;
ALTER TABLE academic_period_configs ADD COLUMN IF NOT EXISTS period_duration_mins INTEGER DEFAULT 50;
ALTER TABLE academic_period_configs ADD COLUMN IF NOT EXISTS working_days         JSONB;
ALTER TABLE academic_period_configs ADD COLUMN IF NOT EXISTS breaks_json          JSONB;
ALTER TABLE academic_period_configs ADD COLUMN IF NOT EXISTS updated_by           VARCHAR(120);
CREATE INDEX IF NOT EXISTS idx_apc_dept_lower ON academic_period_configs (lower(dept));
CREATE INDEX IF NOT EXISTS idx_apc_class_lookup ON academic_period_configs (lower(dept), lower(batch), semester, lower(section));

-- ==============================================================================
-- 26. NOTIFICATIONS & ANNOUNCEMENTS
-- ==============================================================================
CREATE TABLE IF NOT EXISTS notifications_all_roles (
    id               SERIAL PRIMARY KEY,
    recipient_reg_no VARCHAR(100),
    target_role      VARCHAR(50),
    target_dept      VARCHAR(100),
    title            VARCHAR(255) NOT NULL,
    message          TEXT NOT NULL,
    type             VARCHAR(50) DEFAULT 'info',
    is_read          BOOLEAN DEFAULT FALSE,
    metadata         TEXT,
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by       VARCHAR(100)
);
ALTER TABLE notifications_all_roles ADD COLUMN IF NOT EXISTS created_by VARCHAR(100);
CREATE INDEX IF NOT EXISTS idx_notif_recipient ON notifications_all_roles (recipient_reg_no);
CREATE INDEX IF NOT EXISTS idx_notif_role_dept ON notifications_all_roles (target_role, target_dept);
CREATE INDEX IF NOT EXISTS idx_notif_is_read   ON notifications_all_roles (is_read);

CREATE TABLE IF NOT EXISTS admin_notifications (
    id                SERIAL PRIMARY KEY,
    notification_type VARCHAR(100),
    title             VARCHAR(255),
    message           TEXT,
    related_id        VARCHAR(100),
    created_for       VARCHAR(100),
    is_read           INTEGER DEFAULT 0,
    created_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS system_announcements (
    id              SERIAL PRIMARY KEY,
    title           VARCHAR(255) NOT NULL,
    content         TEXT NOT NULL,
    target_audience VARCHAR(50) DEFAULT 'All',
    target_dept     VARCHAR(100),
    priority        VARCHAR(50) DEFAULT 'Normal',
    expires_at      TIMESTAMP,
    created_by      VARCHAR(100),
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS notification_preferences (
    reg_no              VARCHAR(100) PRIMARY KEY,
    email_enabled       BOOLEAN DEFAULT TRUE,
    push_enabled        BOOLEAN DEFAULT TRUE,
    leave_alerts        BOOLEAN DEFAULT TRUE,
    attendance_alerts   BOOLEAN DEFAULT TRUE,
    announcement_alerts BOOLEAN DEFAULT TRUE,
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ==============================================================================
-- 27. GEOFENCE & LOCATION
-- ==============================================================================
CREATE TABLE IF NOT EXISTS geo_fence_coordinates_v2 (
    id             SERIAL PRIMARY KEY,
    polygon_name   VARCHAR(120) DEFAULT 'Main Campus',
    latitude       NUMERIC NOT NULL,
    longitude      NUMERIC NOT NULL,
    sequence_order INTEGER DEFAULT 0,
    is_active      BOOLEAN DEFAULT TRUE,
    created_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    polygon_type   VARCHAR(50) DEFAULT 'outer',
    polygon_group  INTEGER DEFAULT 1,
    point_order    INTEGER DEFAULT 0
);
ALTER TABLE geo_fence_coordinates_v2 ADD COLUMN IF NOT EXISTS polygon_type  VARCHAR(50) DEFAULT 'outer';
ALTER TABLE geo_fence_coordinates_v2 ADD COLUMN IF NOT EXISTS polygon_group INTEGER DEFAULT 1;
ALTER TABLE geo_fence_coordinates_v2 ADD COLUMN IF NOT EXISTS point_order   INTEGER DEFAULT 0;

CREATE TABLE IF NOT EXISTS user_location_logs (
    id                 SERIAL PRIMARY KEY,
    reg_no             VARCHAR(64) NOT NULL,
    username           VARCHAR(120),
    name               VARCHAR(160),
    dept               VARCHAR(160),
    role               VARCHAR(80),
    latitude           NUMERIC NOT NULL,
    longitude          NUMERIC NOT NULL,
    accuracy_meters    NUMERIC,
    speed_mps          NUMERIC,
    heading_deg        NUMERIC,
    altitude_m         NUMERIC,
    source             VARCHAR(50) DEFAULT 'gps',
    app_state          VARCHAR(20) DEFAULT 'foreground',
    is_mocked          BOOLEAN DEFAULT FALSE,
    device_id          VARCHAR(120),
    captured_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    server_received_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    boundary_warning   BOOLEAN DEFAULT FALSE,
    warning_message    VARCHAR(255)
);
CREATE INDEX IF NOT EXISTS idx_user_location_logs_reg_no          ON user_location_logs (reg_no);
CREATE INDEX IF NOT EXISTS idx_user_location_logs_captured_at     ON user_location_logs (captured_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_location_logs_reg_no_captured ON user_location_logs (reg_no, captured_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_location_logs_reg_time        ON user_location_logs (reg_no, captured_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_location_logs_server_time     ON user_location_logs (server_received_at DESC);

CREATE TABLE IF NOT EXISTS user_latest_locations (
    reg_no                VARCHAR(64) PRIMARY KEY,
    username              VARCHAR(120),
    name                  VARCHAR(160),
    dept                  VARCHAR(160),
    role                  VARCHAR(80),
    latitude              NUMERIC NOT NULL,
    longitude             NUMERIC NOT NULL,
    accuracy_meters       NUMERIC,
    speed_mps             NUMERIC,
    heading_deg           NUMERIC,
    altitude_m            NUMERIC,
    source                VARCHAR(50) DEFAULT 'gps',
    app_state             VARCHAR(20) DEFAULT 'foreground',
    is_mocked             BOOLEAN DEFAULT FALSE,
    device_id             VARCHAR(120),
    captured_at           TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_seen_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    force_update_requested BOOLEAN DEFAULT FALSE,
    boundary_warning      BOOLEAN DEFAULT FALSE,
    warning_message       VARCHAR(255),
    first_left_boundary_at TIMESTAMP
);
ALTER TABLE user_latest_locations ADD COLUMN IF NOT EXISTS force_update_requested  BOOLEAN DEFAULT FALSE;
ALTER TABLE user_latest_locations ADD COLUMN IF NOT EXISTS boundary_warning        BOOLEAN DEFAULT FALSE;
ALTER TABLE user_latest_locations ADD COLUMN IF NOT EXISTS warning_message         VARCHAR(255);
ALTER TABLE user_latest_locations ADD COLUMN IF NOT EXISTS first_left_boundary_at  TIMESTAMP;
CREATE INDEX IF NOT EXISTS idx_user_latest_locations_reg_no    ON user_latest_locations (reg_no);
CREATE INDEX IF NOT EXISTS idx_user_latest_locations_dept      ON user_latest_locations (dept);
CREATE INDEX IF NOT EXISTS idx_user_latest_locations_last_seen ON user_latest_locations (last_seen_at DESC);

CREATE TABLE IF NOT EXISTS student_location_logs (
    id              SERIAL PRIMARY KEY,
    student_reg_no  VARCHAR(64) NOT NULL,
    latitude        NUMERIC NOT NULL,
    longitude       NUMERIC NOT NULL,
    accuracy_meters NUMERIC,
    speed_mps       NUMERIC,
    captured_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ==============================================================================
-- 28. VPN & WIFI
-- ==============================================================================
CREATE TABLE IF NOT EXISTS vpn_networks (
    id          SERIAL PRIMARY KEY,
    cidr        VARCHAR(100) NOT NULL UNIQUE,
    description VARCHAR(255),
    is_blocked  BOOLEAN DEFAULT TRUE
);
CREATE TABLE IF NOT EXISTS wifi_whitelist (
    id        SERIAL PRIMARY KEY,
    ssid      VARCHAR(120) NOT NULL,
    bssid     VARCHAR(120),
    is_active BOOLEAN DEFAULT TRUE
);

-- ==============================================================================
-- 29. SECURITY & AUTH
-- ==============================================================================
CREATE TABLE IF NOT EXISTS login_logs (
    id         SERIAL PRIMARY KEY,
    username   VARCHAR(100),
    ip_address VARCHAR(100),
    user_agent TEXT,
    status     VARCHAR(50),
    timestamp  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS login_attempts_log (
    id           SERIAL PRIMARY KEY,
    username     VARCHAR(100),
    ip_address   VARCHAR(100),
    success      BOOLEAN DEFAULT FALSE,
    reason       TEXT,
    attempted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_login_attempts_user ON login_attempts_log (username);
CREATE INDEX IF NOT EXISTS idx_login_attempts_ip   ON login_attempts_log (ip_address);

CREATE TABLE IF NOT EXISTS totp_secrets (
    reg_no       VARCHAR(100) PRIMARY KEY,
    secret_key   VARCHAR(100) NOT NULL,
    is_enabled   BOOLEAN DEFAULT FALSE,
    enabled_at   TIMESTAMP,
    backup_codes TEXT
);
CREATE TABLE IF NOT EXISTS user_security_flags (
    reg_no               VARCHAR(100) PRIMARY KEY,
    force_password_reset BOOLEAN DEFAULT FALSE,
    two_factor_required  BOOLEAN DEFAULT FALSE,
    last_password_change TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    account_locked_until TIMESTAMP,
    updated_at           TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ==============================================================================
-- 30. AUDIT & TRANSFERS
-- ==============================================================================
CREATE TABLE IF NOT EXISTS audit_log (
    id           SERIAL PRIMARY KEY,
    timestamp    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    actor_reg_no VARCHAR(100),
    actor_name   VARCHAR(150),
    actor_role   VARCHAR(50),
    action_type  VARCHAR(100) NOT NULL,
    entity_type  VARCHAR(100),
    entity_id    VARCHAR(100),
    details      TEXT,
    ip_address   VARCHAR(100),
    success      BOOLEAN DEFAULT TRUE
);
CREATE INDEX IF NOT EXISTS idx_audit_log_actor     ON audit_log (actor_reg_no);
CREATE INDEX IF NOT EXISTS idx_audit_log_action    ON audit_log (action_type);
CREATE INDEX IF NOT EXISTS idx_audit_log_timestamp ON audit_log (timestamp DESC);

CREATE TABLE IF NOT EXISTS user_transfers_log (
    id            SERIAL PRIMARY KEY,
    user_id       INTEGER,
    reg_no        VARCHAR(100) NOT NULL,
    old_dept      VARCHAR(100),
    new_dept      VARCHAR(100),
    old_role      VARCHAR(50),
    new_role      VARCHAR(50),
    transfer_date DATE DEFAULT CURRENT_DATE,
    remarks       TEXT,
    transferred_by VARCHAR(100),
    created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ==============================================================================
-- 31. SMTP
-- ==============================================================================
CREATE TABLE IF NOT EXISTS smtp_config (
    id           INTEGER PRIMARY KEY DEFAULT 1,
    host         VARCHAR(255) DEFAULT '',
    port         INTEGER DEFAULT 587,
    username     VARCHAR(255) DEFAULT '',
    password     VARCHAR(255) DEFAULT '',
    sender_email VARCHAR(255) DEFAULT '',
    sender_name  VARCHAR(255) DEFAULT 'Attenda Notification',
    use_tls      BOOLEAN DEFAULT TRUE,
    is_active    BOOLEAN DEFAULT FALSE,
    updated_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_by   VARCHAR(100)
);
INSERT INTO smtp_config (id) VALUES (1) ON CONFLICT (id) DO NOTHING;
ALTER TABLE smtp_config ADD COLUMN IF NOT EXISTS updated_by VARCHAR(100);

-- ==============================================================================
-- 32. STAFF STUDENT PERMISSIONS
-- ==============================================================================
CREATE TABLE IF NOT EXISTS staff_student_permissions (
    id             SERIAL PRIMARY KEY,
    staff_reg_no   VARCHAR(64) NOT NULL,
    student_reg_no VARCHAR(64) NOT NULL,
    granted_by     VARCHAR(64) NOT NULL,
    granted_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (staff_reg_no, student_reg_no)
);

-- ==============================================================================
-- 33. STAFF SESSION NOTES & PREFERENCES
-- ==============================================================================
CREATE TABLE IF NOT EXISTS staff_session_notes (
    id                  SERIAL PRIMARY KEY,
    staff_reg_no        VARCHAR(64) NOT NULL,
    timetable_slot_id   INTEGER NOT NULL,
    session_date        DATE NOT NULL,
    subject_code        VARCHAR(30) NOT NULL,
    topic_covered       TEXT NOT NULL,
    learning_objectives TEXT,
    assignment_notes    TEXT,
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (staff_reg_no, timetable_slot_id, session_date)
);
CREATE INDEX IF NOT EXISTS idx_ssn_staff_date ON staff_session_notes (staff_reg_no, session_date);
CREATE INDEX IF NOT EXISTS idx_ssn_slot       ON staff_session_notes (timetable_slot_id);
CREATE INDEX IF NOT EXISTS idx_ssn_subject    ON staff_session_notes (subject_code);

CREATE TABLE IF NOT EXISTS staff_session_reminder_preferences (
    staff_reg_no           VARCHAR(64) PRIMARY KEY,
    lead_time_minutes      INTEGER NOT NULL DEFAULT 15,
    daily_digest_enabled   BOOLEAN NOT NULL DEFAULT TRUE,
    daily_digest_time      VARCHAR(10) NOT NULL DEFAULT '08:00',
    notify_on_substitution BOOLEAN NOT NULL DEFAULT TRUE,
    notify_on_relocation   BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at             TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ==============================================================================
-- 34. STUDENT FEEDBACK & GRIEVANCES
-- ==============================================================================
CREATE TABLE IF NOT EXISTS student_feedback_grievances (
    id             SERIAL PRIMARY KEY,
    student_reg_no VARCHAR(100) NOT NULL,
    student_name   VARCHAR(150),
    dept           VARCHAR(100),
    category       VARCHAR(100),
    subject        VARCHAR(255) NOT NULL,
    description    TEXT NOT NULL,
    status         VARCHAR(50) DEFAULT 'Open',
    admin_remarks  TEXT,
    resolved_at    TIMESTAMP,
    created_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_feedback_reg ON student_feedback_grievances (student_reg_no);

CREATE TABLE IF NOT EXISTS student_course_feedback (
    id             SERIAL PRIMARY KEY,
    student_reg_no VARCHAR(64) NOT NULL,
    subject_code   VARCHAR(64) NOT NULL,
    staff_reg_no   VARCHAR(64),
    rating         INTEGER DEFAULT 5,
    feedback_text  TEXT,
    created_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ==============================================================================
-- 35. MATERIALIZED VIEW — ATTENDANCE SUMMARY
-- ==============================================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_matviews WHERE matviewname = 'mv_attendance_summary'
  ) THEN
    EXECUTE $mv$
      CREATE MATERIALIZED VIEW mv_attendance_summary AS
      SELECT
          a.reg_no,
          a.dept,
          a.date::date AS attendance_date,
          COUNT(*) AS total_records,
          SUM(CASE WHEN a.status IN ('check_in','Present','present') THEN 1 ELSE 0 END) AS present_count,
          SUM(a.attendance_value) AS total_value
      FROM attendance a
      GROUP BY a.reg_no, a.dept, a.date::date
    $mv$;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_mv_attendance_summary_date_dept
    ON mv_attendance_summary (attendance_date DESC, dept);

-- ==============================================================================
-- 36. SEED DATA
-- ==============================================================================
INSERT INTO leave_settings (key, value) VALUES
    ('el_accrual_rate',      '1.25'),
    ('el_max_balance',       '300'),
    ('cl_per_month',         '1'),
    ('cl_max_accumulation',  '12'),
    ('permission_max_hours', '2'),
    ('min_leave_notice_days','1')
ON CONFLICT (key) DO NOTHING;

INSERT INTO system_config (key, value) VALUES
    ('attendance_mode',      'geofence'),
    ('geofence_radius_m',    '200'),
    ('kiosk_mode_enabled',   'true'),
    ('academic_year',        '2024-2025'),
    ('face_liveness_check',  'false'),
    ('max_login_attempts',   '5'),
    ('session_timeout_mins', '480')
ON CONFLICT (key) DO NOTHING;

INSERT INTO ccl_settings (key, value) VALUES
    ('ccl_enabled',       'true'),
    ('ccl_validity_days', '90'),
    ('early_slot_start',  '07:00'),
    ('early_slot_end',    '08:00'),
    ('late_slot_start',   '17:00'),
    ('late_slot_end',     '18:00')
ON CONFLICT (key) DO NOTHING;

-- ==============================================================================
-- END OF SCHEMA v3.0
-- ==============================================================================
