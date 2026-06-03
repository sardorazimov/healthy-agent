CREATE TABLE knowledge_documents (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    citation TEXT NOT NULL DEFAULT '',
    source_kind TEXT NOT NULL DEFAULT 'curated',
    created_at TEXT NOT NULL
);

CREATE TABLE knowledge_embeddings (
    document_id TEXT PRIMARY KEY REFERENCES knowledge_documents(id) ON DELETE CASCADE,
    embedding_model TEXT NOT NULL,
    dimensions INTEGER NOT NULL,
    vector_blob BLOB NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE weekly_reports (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    week_start TEXT NOT NULL,
    week_end TEXT NOT NULL,
    health_score INTEGER NOT NULL,
    summary TEXT NOT NULL,
    pdf_path TEXT NOT NULL,
    created_at TEXT NOT NULL,
    UNIQUE(user_id, week_start)
);

CREATE TABLE safety_events (
    id TEXT PRIMARY KEY,
    user_id TEXT REFERENCES users(id) ON DELETE SET NULL,
    input_text TEXT NOT NULL,
    safety_level TEXT NOT NULL,
    response_text TEXT NOT NULL,
    created_at TEXT NOT NULL
);

CREATE TABLE integration_connections (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    external_account_id TEXT,
    scopes TEXT NOT NULL DEFAULT '',
    token_ref TEXT NOT NULL DEFAULT '',
    last_sync_at TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    UNIQUE(user_id, provider)
);

CREATE TABLE integration_sync_cursors (
    connection_id TEXT PRIMARY KEY REFERENCES integration_connections(id) ON DELETE CASCADE,
    cursor_value TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
