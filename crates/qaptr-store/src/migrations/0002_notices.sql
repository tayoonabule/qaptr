CREATE TABLE notices (
    notice_id TEXT PRIMARY KEY NOT NULL,
    created_at_ms INTEGER NOT NULL,
    excluded_count INTEGER NOT NULL CHECK (excluded_count > 0),
    reason TEXT NOT NULL CHECK (reason IN ('application_excluded', 'window_excluded'))
);
