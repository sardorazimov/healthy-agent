CREATE TABLE users (
    id TEXT PRIMARY KEY,
    display_name TEXT NOT NULL,
    birth_year INTEGER,
    sex TEXT NOT NULL DEFAULT 'unspecified',
    height_cm REAL,
    weight_kg REAL,
    locale TEXT NOT NULL DEFAULT 'en-US',
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE user_profiles (
    user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    medical_context TEXT NOT NULL DEFAULT '',
    dietary_preferences TEXT NOT NULL DEFAULT '',
    fitness_level TEXT NOT NULL DEFAULT 'unknown',
    sleep_chronotype TEXT NOT NULL DEFAULT 'unknown',
    privacy_consent_version TEXT NOT NULL DEFAULT 'v1',
    updated_at TEXT NOT NULL
);

CREATE TABLE health_timeline_events (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    event_type TEXT NOT NULL,
    occurred_at TEXT NOT NULL,
    title TEXT NOT NULL,
    body TEXT NOT NULL DEFAULT '',
    value REAL,
    unit TEXT,
    source TEXT NOT NULL DEFAULT 'manual',
    metadata_json TEXT NOT NULL DEFAULT '{}'
);

CREATE INDEX idx_health_timeline_user_time
    ON health_timeline_events(user_id, occurred_at DESC);

CREATE TABLE goals (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    metric TEXT NOT NULL,
    target_value REAL NOT NULL,
    current_value REAL NOT NULL DEFAULT 0,
    unit TEXT NOT NULL DEFAULT '',
    due_at TEXT,
    status TEXT NOT NULL DEFAULT 'active',
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE INDEX idx_goals_user_status
    ON goals(user_id, status);

CREATE TABLE long_term_memories (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    memory_text TEXT NOT NULL,
    tags TEXT NOT NULL DEFAULT '',
    observed_at TEXT NOT NULL,
    importance REAL NOT NULL DEFAULT 0.5,
    source_event_id TEXT REFERENCES health_timeline_events(id) ON DELETE SET NULL
);

CREATE INDEX idx_memories_user_importance
    ON long_term_memories(user_id, importance DESC, observed_at DESC);

CREATE TABLE reminders (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    instructions TEXT NOT NULL DEFAULT '',
    due_at TEXT NOT NULL,
    repeat_minutes INTEGER NOT NULL DEFAULT 0,
    delivered_at TEXT,
    channel TEXT NOT NULL DEFAULT 'local'
);

CREATE INDEX idx_reminders_due
    ON reminders(user_id, due_at, delivered_at);
