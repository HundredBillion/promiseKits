# Implementation Tasks: Fix Docker Container Boot Failures

**Feature ID**: 006-fix-docker-containers

---

## Task Execution Instructions

Execute tasks in order. Each task has a clear file target, action, and validation step.

---

## Phase 1: Configuration Files

### Task 1.1: Create `config/sidekiq.yml`
**File**: `config/sidekiq.yml`
**Action**: Create new file

Content:
```yaml
# Sidekiq configuration
# Queues are processed in priority order (top = highest priority)
:concurrency: 5

:queues:
  - default
  - mailers

# Sidekiq-scheduler: load cron job definitions
:scheduler:
  :schedule: config/sidekiq_scheduler.yml
```

**Validation**: File exists at `config/sidekiq.yml`. Sidekiq container no longer logs "No such file config/sidekiq.yml".

---

### Task 1.2: Uncomment `eager_load` in `development.rb`
**File**: `config/environments/development.rb`
**Action**: Uncomment line `# config.eager_load = false` → `config.eager_load = false`

**Validation**: No `config.eager_load is set to nil` warning in container logs.

---

## Phase 2: Docker Compose Cleanup

### Task 2.1: Remove Postgres from `docker-compose.yml` and add SQLite volume
**File**: `docker-compose.yml`
**Action**:
- Remove the `db` service (Postgres)
- Remove `db_data` volume
- Remove `DATABASE_URL` environment variables from all services
- Remove `db` from `depends_on` in `web`, `sidekiq`, `runner`
- Add `sqlite_data:/rails/storage` volume to `web` and `runner` services
- Add `sqlite_data` to the `volumes` section

**Validation**: `docker-compose.yml` has no postgres references. `docker compose config` shows no db service.

---

## Phase 3: Secrets

### Task 3.1: Document `RAILS_MASTER_KEY` in `.env.example`
**File**: `.env.example`
**Action**: Ensure `RAILS_MASTER_KEY=` is documented as a required variable with instructions.

### Task 3.2: Add `RAILS_MASTER_KEY` to `.env`
**File**: `.env` (create if not exists — DO NOT commit)
**Action**: 
1. Read the value from `config/master.key` on the local machine
2. Add `RAILS_MASTER_KEY=<value from config/master.key>` to `.env`

**Note**: This task requires the user to manually copy the value from `config/master.key` since it is gitignored and cannot be automated safely.

---

## Phase 4: Validation

### Task 4.1: Rebuild and run the stack
```bash
docker compose down -v
docker compose up --build
```

**Expected outcome:**
- `promisekits_sidekiq`: starts and stays running
- `promisekits_runner`: exits with code 0 after migrations
- `promisekits_web`: boots without `eager_load` warnings
- No crash-loop restarts

### Task 4.2: Verify Sidekiq is processing
Check Sidekiq logs for successful startup:
```
promisekits_sidekiq | Sidekiq 8.x.x connecting to Redis...
promisekits_sidekiq | Sidekiq is ready, push it...
```

### Task 4.3: Verify web is reachable
Open http://localhost:3000 and confirm the app loads.

---

## Summary

| Task | File | Type | Priority |
|------|------|------|----------|
| 1.1 | `config/sidekiq.yml` | Create | Critical |
| 1.2 | `config/environments/development.rb` | Edit | Medium |
| 2.1 | `docker-compose.yml` | Edit | High |
| 3.1 | `.env.example` | Edit | Medium |
| 3.2 | `.env` | Manual (user action) | Critical |
| 4.1-4.3 | — | Validation | Required |