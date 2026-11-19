CrunpBot Racer — Cloudflare multiplayer, accounts, saves and profiles

This Worker uses Cloudflare D1 and Durable Objects. Cloudflare R2 asset storage is disabled.

Preserved multiplayer

GET /health, POST /api/rooms, GET /api/rooms and GET /ws remain in place. Room discovery is backed by RoomDirectory; rooms support up to six players. Lobby robot and OVR values are client metadata, not anti-cheat guarantees.

Existing Durable Object classes, bindings and migration tags are retained.

Accounts and saves

POST /api/auth/register — {email,password,display_name}; password 10–128 characters.

POST /api/auth/login — {email,password}.

POST /api/auth/google — {id_token}; requires Worker variable GOOGLE_CLIENT_ID and a native Android sign-in plugin. Google Login is not enabled in the current game release.

POST /api/auth/logout — revokes the bearer session.

GET /api/save and PUT /api/save — revisioned progress sync; a stale revision returns HTTP 409 and the cloud copy.

Passwords use salted PBKDF2-SHA256 (210,000 iterations). Session tokens are random and only SHA-256 hashes are stored in D1. Previous cloud save revisions are retained in save_history before replacement. The game requires explicit player choice before applying a cloud save.

Profiles

GET /api/profile

PUT /api/profile — update public_name, country_code, and selected_robot_id.

Cloud assets disabled

R2 is not configured or used by this Worker.

GET /api/assets

POST /api/assets

GET /api/assets/<uuid>

DELETE /api/assets/<uuid>

These endpoints return HTTP 410 with CLOUD_ASSETS_DISABLED.

Cloud skins and track uploads/downloads are not available in this configuration. Local game content remains separate.

Cloudflare setup

The existing D1 database is:

Name: crunpbot-racer-db

ID: ae95f769-978e-489a-9b83-deeddde0dcb7

Do not create an R2 bucket or add an R2 binding.

D1 migrations

The repository contains these migration files:

migrations/0001_accounts_saves.sql

migrations/0002_assets_profiles.sql

The second migration creates user_profiles only.

Both migrations have already been applied to the existing D1 database. Do not execute them again.

Do not delete, recreate, or reset the existing D1 database.

Worker deployment

Before deploying:

Confirm wrangler.jsonc contains the correct D1 database name and ID listed above.

Confirm there is no r2_buckets binding.

Confirm the existing D1 migrations are already applied. Do not run them again.

Preserve the existing Durable Object classes, bindings and migration tags: 

RaceRoom

RoomDirectory

Deploy the complete Worker from the repository.

Verify /health reports: 

cloud_accounts: true

cloud_profiles: true

cloud_assets: false

Do not deploy if the configuration or existing database bindings are incorrect.

Cost and abuse precautions

This configuration does not use R2. It uses D1 and Durable Objects.

Free plan quotas and application-level limits are not a complete guarantee against abuse, service disruption or unexpected charges.

Rate limiting for registration, login, save writes and room creation must be implemented before public launch. The existing per-socket message limit in room.ts is not a substitute for global API rate limiting.

Do not switch to a paid Cloudflare plan if strict avoidance of charges is required.

About

Robot Racing multiplayer server.


