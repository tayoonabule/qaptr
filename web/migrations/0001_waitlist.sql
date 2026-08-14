-- Migration 0001: waitlist storage and rate-limit bucket.
--
-- The waitlist table intentionally has exactly three columns per R-W1 /
-- KTD12: email, a created timestamp, and a coarse source tag. No IP
-- address, user agent, or free-text field is stored here.
--
-- The rate_limit_bucket table is a separate, non-PII sliding-window
-- counter. It stores a *hashed* client key (never a raw IP) and a rolling
-- count/window, purely to throttle abusive POST volume. It is not part of
-- the waitlist's durable signup history and is pruned continuously.

CREATE TABLE IF NOT EXISTS waitlist (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  email TEXT NOT NULL UNIQUE,
  created_at TEXT NOT NULL,
  source TEXT NOT NULL DEFAULT 'unknown'
);

CREATE INDEX IF NOT EXISTS idx_waitlist_created_at ON waitlist (created_at);

CREATE TABLE IF NOT EXISTS rate_limit_bucket (
  client_key TEXT PRIMARY KEY,
  window_start TEXT NOT NULL,
  request_count INTEGER NOT NULL DEFAULT 0
);
