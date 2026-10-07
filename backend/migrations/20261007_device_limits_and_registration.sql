-- Explicit, additive PostgreSQL migration for device-limit enforcement.
-- Review and run only against the intended database during an approved
-- maintenance window. Normal server startup does not execute this file.
BEGIN;

ALTER TABLE IF EXISTS shops
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'active',
  ADD COLUMN IF NOT EXISTS license_start_date TEXT,
  ADD COLUMN IF NOT EXISTS license_expiry_date TEXT,
  ADD COLUMN IF NOT EXISTS license_assigned BOOLEAN,
  ADD COLUMN IF NOT EXISTS device_limit INTEGER,
  ADD COLUMN IF NOT EXISTS is_lifetime BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE IF EXISTS devices
  ADD COLUMN IF NOT EXISTS device_name TEXT,
  ADD COLUMN IF NOT EXISTS device_type TEXT,
  ADD COLUMN IF NOT EXISTS ip_address TEXT,
  ADD COLUMN IF NOT EXISTS is_revoked BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS revoked_at TEXT,
  ADD COLUMN IF NOT EXISTS legacy_device_id TEXT,
  ADD COLUMN IF NOT EXISTS created_at TEXT,
  ADD COLUMN IF NOT EXISTS last_seen_at TEXT;

-- Preserve existing device rows and timestamps; fill only missing values.
UPDATE devices
SET created_at = COALESCE(created_at, last_seen_at, CURRENT_TIMESTAMP::TEXT),
    last_seen_at = COALESCE(last_seen_at, created_at, CURRENT_TIMESTAMP::TEXT),
    is_revoked = COALESCE(is_revoked, FALSE)
WHERE created_at IS NULL OR last_seen_at IS NULL OR is_revoked IS NULL;

ALTER TABLE IF EXISTS devices
  ALTER COLUMN created_at SET DEFAULT CURRENT_TIMESTAMP::TEXT,
  ALTER COLUMN created_at SET NOT NULL,
  ALTER COLUMN last_seen_at SET DEFAULT CURRENT_TIMESTAMP::TEXT,
  ALTER COLUMN last_seen_at SET NOT NULL,
  ALTER COLUMN is_revoked SET DEFAULT FALSE,
  ALTER COLUMN is_revoked SET NOT NULL;

CREATE INDEX IF NOT EXISTS devices_shop_active_idx
  ON devices (shop_id)
  WHERE is_revoked = FALSE;

-- Existing shops intentionally remain unlimited until explicitly configured.
-- Existing device IDs, including the shared "flutter-client" ID, are untouched.
COMMIT;
