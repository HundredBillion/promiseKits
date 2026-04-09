# Implementation Plan: Fix Docker Container Boot Failures

**Feature ID**: 006-fix-docker-containers
**Status**: In Progress

---

## Technical Summary

Four targeted changes required. No architectural changes, no new dependencies. All changes are configuration-level.

---

## Fix 1: Create `config/sidekiq.yml`

**File**: `config/sidekiq.yml` (new file)

Sidekiq requires a YAML config file when launched with `-C config/sidekiq.yml`. The file must define:
- `:concurrency` — number of worker threads
- `:queues` — list of queues to process

The app already has `config/sidekiq_scheduler.yml` for cron job definitions. Sidekiq-scheduler picks this up automatically when Sidekiq starts, as long as it is referenced in `sidekiq.yml`.

**Config content:**
- concurrency: 5
- queues: `default`, `mailers`
- scheduler: reference `config/sidekiq_scheduler.yml`

---

## Fix 2: Add `RAILS_MASTER_KEY` to `.env`

**File**: `.env` (create if missing), `.env.example` (update instructions)

Rails uses `config/credentials.yml.enc` (encrypted) decoded with `config/master.key` or the `RAILS_MASTER_KEY` env var. In Docker, `config/master.key` is not available inside the container (it's gitignored and not copied in), so `RAILS_MASTER_KEY` must be set as an environment variable.

**Steps:**
1. Obtain the value from `config/master.key` on the local machine
2. Add `RAILS_MASTER_KEY=<value>` to `.env`
3. Update `.env.example` to document this required variable

---

## Fix 3: Uncomment `config.eager_load` in `development.rb`

**File**: `config/environments/development.rb`

The line `# config.eager_load = false` is commented out. Rails 8 raises a warning if `eager_load` is `nil`. Simply uncomment it.

---

## Fix 4: Remove Postgres from `docker-compose.yml`

**File**: `docker-compose.yml`

The app uses SQLite (see `config/database.yml`). The Postgres `db` service is unused. Remove it and:
- Remove the `db` volume
- Remove `db` from `depends_on` in `web`, `sidekiq`, `runner`
- Remove `DATABASE_URL` env vars (SQLite uses file paths, not URLs)
- Add a named volume for SQLite `storage/` directory to persist data

---

## Acceptance Checklist

- [ ] `config/sidekiq.yml` created with correct queues
- [ ] `.env` contains valid `RAILS_MASTER_KEY`
- [ ] `development.rb` `eager_load` uncommented
- [ ] `docker-compose.yml` Postgres removed, SQLite volume added
- [ ] `docker compose up --build` runs cleanly