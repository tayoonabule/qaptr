CREATE TABLE captures (
    capture_id TEXT PRIMARY KEY NOT NULL,
    captured_at_ms INTEGER NOT NULL,
    vault_record_id TEXT NOT NULL UNIQUE,
    context_summary TEXT
);

CREATE TABLE observations (
    observation_id TEXT PRIMARY KEY NOT NULL,
    capture_id TEXT REFERENCES captures(capture_id) ON DELETE SET NULL,
    session_id TEXT NOT NULL,
    title TEXT NOT NULL,
    summary TEXT NOT NULL,
    confidence REAL NOT NULL CHECK (confidence >= 0.0 AND confidence <= 1.0),
    created_at_ms INTEGER NOT NULL
);

CREATE TABLE workflows (
    workflow_id TEXT PRIMARY KEY NOT NULL,
    session_id TEXT NOT NULL,
    title TEXT NOT NULL,
    goal TEXT NOT NULL,
    context TEXT NOT NULL,
    tools TEXT NOT NULL,
    sequence TEXT NOT NULL,
    decisions TEXT NOT NULL,
    variations TEXT NOT NULL,
    evidence_confidence REAL NOT NULL CHECK (
        evidence_confidence >= 0.0 AND evidence_confidence <= 1.0
    ),
    created_at_ms INTEGER NOT NULL
);
