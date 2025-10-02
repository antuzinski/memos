/*
  # Create Memos Application Schema

  1. Tables Created
    - `migration_history` - Tracks database migrations
    - `system_setting` - Stores system-wide settings
    - `user` - User accounts with authentication
    - `user_setting` - User-specific settings
    - `memo` - User memos/notes
    - `memo_organizer` - User memo organization (pins, etc.)
    - `memo_relation` - Relations between memos
    - `resource` - Attachments and resources
    - `activity` - Activity log
    - `idp` - Identity providers for SSO
    - `inbox` - User inbox messages
    - `reaction` - Reactions to content

  2. Security
    - Enable RLS on all tables
    - Add policies for authenticated user access
*/

-- migration_history
CREATE TABLE IF NOT EXISTS migration_history (
  version TEXT NOT NULL PRIMARY KEY,
  created_ts BIGINT NOT NULL DEFAULT extract(epoch from now())
);

ALTER TABLE migration_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admin can manage migration history"
  ON migration_history FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

-- system_setting
CREATE TABLE IF NOT EXISTS system_setting (
  name TEXT NOT NULL PRIMARY KEY,
  value TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT ''
);

ALTER TABLE system_setting ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read system settings"
  ON system_setting FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Admin can manage system settings"
  ON system_setting FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

-- user
CREATE TABLE IF NOT EXISTS "user" (
  id SERIAL PRIMARY KEY,
  created_ts BIGINT NOT NULL DEFAULT extract(epoch from now()),
  updated_ts BIGINT NOT NULL DEFAULT extract(epoch from now()),
  row_status TEXT NOT NULL CHECK (row_status IN ('NORMAL', 'ARCHIVED')) DEFAULT 'NORMAL',
  username TEXT NOT NULL UNIQUE,
  role TEXT NOT NULL CHECK (role IN ('HOST', 'ADMIN', 'USER')) DEFAULT 'USER',
  email TEXT NOT NULL DEFAULT '',
  nickname TEXT NOT NULL DEFAULT '',
  password_hash TEXT NOT NULL,
  avatar_url TEXT NOT NULL DEFAULT '',
  description TEXT NOT NULL DEFAULT ''
);

CREATE INDEX IF NOT EXISTS idx_user_username ON "user" (username);

ALTER TABLE "user" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read all users"
  ON "user" FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Users can update own profile"
  ON "user" FOR UPDATE
  TO authenticated
  USING (id = (current_setting('app.user_id', true))::integer)
  WITH CHECK (id = (current_setting('app.user_id', true))::integer);

-- user_setting
CREATE TABLE IF NOT EXISTS user_setting (
  user_id INTEGER NOT NULL REFERENCES "user"(id) ON DELETE CASCADE,
  key TEXT NOT NULL,
  value TEXT NOT NULL,
  PRIMARY KEY (user_id, key)
);

ALTER TABLE user_setting ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own settings"
  ON user_setting FOR ALL
  TO authenticated
  USING (user_id = (current_setting('app.user_id', true))::integer)
  WITH CHECK (user_id = (current_setting('app.user_id', true))::integer);

-- memo
CREATE TABLE IF NOT EXISTS memo (
  id SERIAL PRIMARY KEY,
  uid TEXT NOT NULL UNIQUE,
  creator_id INTEGER NOT NULL REFERENCES "user"(id) ON DELETE CASCADE,
  created_ts BIGINT NOT NULL DEFAULT extract(epoch from now()),
  updated_ts BIGINT NOT NULL DEFAULT extract(epoch from now()),
  row_status TEXT NOT NULL CHECK (row_status IN ('NORMAL', 'ARCHIVED')) DEFAULT 'NORMAL',
  content TEXT NOT NULL DEFAULT '',
  visibility TEXT NOT NULL CHECK (visibility IN ('PUBLIC', 'PROTECTED', 'PRIVATE')) DEFAULT 'PRIVATE',
  pinned INTEGER NOT NULL CHECK (pinned IN (0, 1)) DEFAULT 0,
  payload TEXT NOT NULL DEFAULT '{}'
);

CREATE INDEX IF NOT EXISTS idx_memo_creator_id ON memo (creator_id);

ALTER TABLE memo ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own memos"
  ON memo FOR SELECT
  TO authenticated
  USING (creator_id = (current_setting('app.user_id', true))::integer OR visibility = 'PUBLIC');

CREATE POLICY "Users can create own memos"
  ON memo FOR INSERT
  TO authenticated
  WITH CHECK (creator_id = (current_setting('app.user_id', true))::integer);

CREATE POLICY "Users can update own memos"
  ON memo FOR UPDATE
  TO authenticated
  USING (creator_id = (current_setting('app.user_id', true))::integer)
  WITH CHECK (creator_id = (current_setting('app.user_id', true))::integer);

CREATE POLICY "Users can delete own memos"
  ON memo FOR DELETE
  TO authenticated
  USING (creator_id = (current_setting('app.user_id', true))::integer);

-- memo_organizer
CREATE TABLE IF NOT EXISTS memo_organizer (
  memo_id INTEGER NOT NULL REFERENCES memo(id) ON DELETE CASCADE,
  user_id INTEGER NOT NULL REFERENCES "user"(id) ON DELETE CASCADE,
  pinned INTEGER NOT NULL CHECK (pinned IN (0, 1)) DEFAULT 0,
  PRIMARY KEY (memo_id, user_id)
);

ALTER TABLE memo_organizer ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own memo organization"
  ON memo_organizer FOR ALL
  TO authenticated
  USING (user_id = (current_setting('app.user_id', true))::integer)
  WITH CHECK (user_id = (current_setting('app.user_id', true))::integer);

-- memo_relation
CREATE TABLE IF NOT EXISTS memo_relation (
  memo_id INTEGER NOT NULL REFERENCES memo(id) ON DELETE CASCADE,
  related_memo_id INTEGER NOT NULL REFERENCES memo(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  PRIMARY KEY (memo_id, related_memo_id, type)
);

ALTER TABLE memo_relation ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage memo relations"
  ON memo_relation FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

-- resource
CREATE TABLE IF NOT EXISTS resource (
  id SERIAL PRIMARY KEY,
  uid TEXT NOT NULL UNIQUE,
  creator_id INTEGER NOT NULL REFERENCES "user"(id) ON DELETE CASCADE,
  created_ts BIGINT NOT NULL DEFAULT extract(epoch from now()),
  updated_ts BIGINT NOT NULL DEFAULT extract(epoch from now()),
  filename TEXT NOT NULL DEFAULT '',
  blob BYTEA DEFAULT NULL,
  type TEXT NOT NULL DEFAULT '',
  size INTEGER NOT NULL DEFAULT 0,
  memo_id INTEGER REFERENCES memo(id) ON DELETE CASCADE,
  storage_type TEXT NOT NULL DEFAULT '',
  reference TEXT NOT NULL DEFAULT '',
  payload TEXT NOT NULL DEFAULT '{}'
);

CREATE INDEX IF NOT EXISTS idx_resource_creator_id ON resource (creator_id);
CREATE INDEX IF NOT EXISTS idx_resource_memo_id ON resource (memo_id);

ALTER TABLE resource ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own resources"
  ON resource FOR SELECT
  TO authenticated
  USING (creator_id = (current_setting('app.user_id', true))::integer);

CREATE POLICY "Users can create own resources"
  ON resource FOR INSERT
  TO authenticated
  WITH CHECK (creator_id = (current_setting('app.user_id', true))::integer);

CREATE POLICY "Users can update own resources"
  ON resource FOR UPDATE
  TO authenticated
  USING (creator_id = (current_setting('app.user_id', true))::integer)
  WITH CHECK (creator_id = (current_setting('app.user_id', true))::integer);

CREATE POLICY "Users can delete own resources"
  ON resource FOR DELETE
  TO authenticated
  USING (creator_id = (current_setting('app.user_id', true))::integer);

-- activity
CREATE TABLE IF NOT EXISTS activity (
  id SERIAL PRIMARY KEY,
  creator_id INTEGER NOT NULL REFERENCES "user"(id) ON DELETE CASCADE,
  created_ts BIGINT NOT NULL DEFAULT extract(epoch from now()),
  type TEXT NOT NULL DEFAULT '',
  level TEXT NOT NULL CHECK (level IN ('INFO', 'WARN', 'ERROR')) DEFAULT 'INFO',
  payload TEXT NOT NULL DEFAULT '{}'
);

ALTER TABLE activity ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own activities"
  ON activity FOR ALL
  TO authenticated
  USING (creator_id = (current_setting('app.user_id', true))::integer)
  WITH CHECK (creator_id = (current_setting('app.user_id', true))::integer);

-- idp
CREATE TABLE IF NOT EXISTS idp (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  type TEXT NOT NULL,
  identifier_filter TEXT NOT NULL DEFAULT '',
  config TEXT NOT NULL DEFAULT '{}'
);

ALTER TABLE idp ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read identity providers"
  ON idp FOR SELECT
  TO authenticated
  USING (true);

-- inbox
CREATE TABLE IF NOT EXISTS inbox (
  id SERIAL PRIMARY KEY,
  created_ts BIGINT NOT NULL DEFAULT extract(epoch from now()),
  sender_id INTEGER NOT NULL REFERENCES "user"(id) ON DELETE CASCADE,
  receiver_id INTEGER NOT NULL REFERENCES "user"(id) ON DELETE CASCADE,
  status TEXT NOT NULL,
  message TEXT NOT NULL DEFAULT '{}'
);

ALTER TABLE inbox ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own inbox"
  ON inbox FOR SELECT
  TO authenticated
  USING (receiver_id = (current_setting('app.user_id', true))::integer OR sender_id = (current_setting('app.user_id', true))::integer);

CREATE POLICY "Users can send messages"
  ON inbox FOR INSERT
  TO authenticated
  WITH CHECK (sender_id = (current_setting('app.user_id', true))::integer);

CREATE POLICY "Users can update own inbox"
  ON inbox FOR UPDATE
  TO authenticated
  USING (receiver_id = (current_setting('app.user_id', true))::integer)
  WITH CHECK (receiver_id = (current_setting('app.user_id', true))::integer);

-- reaction
CREATE TABLE IF NOT EXISTS reaction (
  id SERIAL PRIMARY KEY,
  created_ts BIGINT NOT NULL DEFAULT extract(epoch from now()),
  creator_id INTEGER NOT NULL REFERENCES "user"(id) ON DELETE CASCADE,
  content_id TEXT NOT NULL,
  reaction_type TEXT NOT NULL,
  UNIQUE(creator_id, content_id, reaction_type)
);

ALTER TABLE reaction ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read all reactions"
  ON reaction FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Users can create own reactions"
  ON reaction FOR INSERT
  TO authenticated
  WITH CHECK (creator_id = (current_setting('app.user_id', true))::integer);

CREATE POLICY "Users can delete own reactions"
  ON reaction FOR DELETE
  TO authenticated
  USING (creator_id = (current_setting('app.user_id', true))::integer);
