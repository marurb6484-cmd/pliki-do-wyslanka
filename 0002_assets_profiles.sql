
CREATE TABLE IF NOT EXISTS user_profiles (
  user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  public_name TEXT NOT NULL,
  country_code TEXT NOT NULL DEFAULT '',
  selected_robot_id TEXT NOT NULL DEFAULT '',
  updated_at INTEGER NOT NULL
);

