# Feature Specification: Fix Docker Container Boot Failures

**Feature ID**: 006-fix-docker-containers
**Status**: In Progress
**Created**: 2026-02-22
**Last Updated**: 2026-02-22

---

## Overview

The Docker Compose stack fails to start cleanly due to three issues discovered during `docker compose up --build`:

1. **Missing `config/sidekiq.yml`** — The `sidekiq` container crashes immediately because Sidekiq cannot find its config file.
2. **Missing `RAILS_MASTER_KEY` in `.env`** — The `runner` container crashes during `db:migrate` because Rails cannot decrypt `config/credentials.yml.enc` without the master key. The error is: `ArgumentError: key must be 16 bytes`.
3. **`config.eager_load` is `nil` in `development.rb`** — The `config.eager_load = false` line is commented out, which triggers a Rails boot warning. This warning appears across all containers.

Additionally, the `docker-compose.yml` includes a Postgres service, but the application uses **SQLite** (as configured in `config/database.yml` and `config/database.yml`). The Postgres service is unused and misleading.

---

## User Stories

### US-1: Sidekiq Container Starts Successfully
**As a** developer
**I want** the Sidekiq container to boot without errors
**So that** background jobs and scheduled tasks can run

**Acceptance Criteria:**
- `config/sidekiq.yml` exists with at least a `default` queue and concurrency setting
- Sidekiq-scheduler references `config/sidekiq_scheduler.yml` for cron jobs
- `promisekits_sidekiq` container starts and stays running without crash-looping

---

### US-2: Runner Container Completes Migrations
**As a** developer
**I want** the runner container to successfully run `db:migrate`
**So that** the database schema is up to date on boot

**Acceptance Criteria:**
- `RAILS_MASTER_KEY` is present in `.env` and correctly set
- `.env.example` documents all required secrets clearly
- Runner container exits with code 0 after completing migrations

---

### US-3: No `eager_load` Nil Warning on Boot
**As a** developer
**I want** the Rails boot process to be clean and warning-free
**So that** logs are clear and actionable

**Acceptance Criteria:**
- `config/environments/development.rb` has `config.eager_load = false` uncommented
- No `config.eager_load is set to nil` warning appears in container logs

---

### US-4: Docker Compose Uses Correct Database (SQLite)
**As a** developer
**I want** `docker-compose.yml` to reflect the app's actual database setup
**So that** the stack matches the application's architecture

**Acceptance Criteria:**
- Postgres service removed from `docker-compose.yml`
- `DATABASE_URL` env var removed (app uses SQLite with file paths)
- `db` service dependency removed from `web`, `sidekiq`, and `runner`
- SQLite storage volume mounted correctly

---

## Edge Cases

- **`RAILS_MASTER_KEY` wrong length**: The key must be exactly 32 hex characters (16 bytes). If it's shorter, the `ArgumentError: key must be 16 bytes` error occurs.
- **`config/master.key` missing**: If `config/master.key` doesn't exist locally, the user must obtain it from a secure source (team secrets manager, etc.).
- **Sidekiq queue mismatch**: If jobs are enqueued on a queue not listed in `sidekiq.yml`, they will never be processed.

---

## Success Criteria

- [ ] `docker compose up --build` completes without container crash-loops
- [ ] `promisekits_sidekiq` container runs and stays up
- [ ] `promisekits_runner` container exits with code 0
- [ ] `promisekits_web` container boots without warnings
- [ ] No `eager_load is nil` warning in logs
- [ ] No Postgres service in docker-compose (app uses SQLite)