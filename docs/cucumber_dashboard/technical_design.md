# Cucumber Dashboard — Technical Design

## Architecture Overview

The dashboard is a self-contained tool (no gem dependencies beyond Rails) with four components:

```
                  ┌─────────────────────────┐
                  │    Browser (dashboard)   │
                  │    http://localhost:9777  │
                  └────────┬────────────────┘
                           │ HTTP polling (500ms events, 1s console)
                           │
                  ┌────────▼────────────────┐
                  │    WEBrick Server        │
                  │    dashboard_server.rb   │
                  │    Port 9777             │
                  └────────┬────────────────┘
                           │ reads JSONL + console output files
                           │
              ┌────────────▼──────────────────┐
              │   /tmp/cucumber_progress/      │
              │   worker_1.jsonl               │
              │   worker_2.jsonl               │
              │   worker_1_failures.txt        │
              │   worker_2_failures.txt        │
              │   total_scenarios              │
              │   run_config.json              │
              ├───────────────────────────────┤
              │   /tmp/cucumber_full_output.txt │
              └────────────▲──────────────────┘
                           │ writes events + stdout/stderr
                           │
          ┌────────────────┴──────────────────┐
          │  Cucumber Workers (parallel_cucumber)  │
          │  Each runs ProgressFormatter            │
          │  Identified by TEST_ENV_NUMBER          │
          └────────────────────────────────────┘
```

**Data flow:** Cucumber workers write JSONL events to per-worker files and console output to a shared log. The WEBrick server reads these files on each poll request. The browser polls the server every 500ms (events) and 1s (console) and renders worker state in real-time.

There is no WebSocket or SSE — WEBrick's chunked response handling doesn't flush reliably. Cursor-based polling (tracking byte offset per file) is simple and works.

## File Structure

```
cucumber_dashboard/
├── run.sh                 # Entry point — starts server, optionally runs tests
├── dashboard_server.rb    # WEBrick HTTP server with all API endpoints
├── dashboard.html         # Single-file frontend (HTML + CSS + JS, no build step)
├── progress_formatter.rb  # Cucumber formatter — hooks into test lifecycle events
├── completion_mailer.rb   # ActionMailer for email notifications (Phase 2)
└── README.md              # Quick start guide for teammates
```

> **Important:** Do NOT add `.rb` files to this directory unless they are intended to be loaded by Cucumber. The `--require cucumber_dashboard/` flag causes Cucumber to auto-load every `.rb` file in this directory as a support file.

## Component Details

### 1. Progress Formatter (`progress_formatter.rb`)

**Module:** `CucumberDashboard::ProgressFormatter`

A custom Cucumber formatter that hooks into Cucumber's event system. Each parallel worker loads this formatter and writes structured events to its own JSONL file.

**Worker identification:** Uses `ENV['TEST_ENV_NUMBER']` set by `parallel_tests` gem. Falls back to `'1'` if empty.

**Cucumber event hooks:**

| Hook | Triggers | Event Written |
|------|----------|---------------|
| Constructor | Formatter loaded | `worker_start` |
| `on_test_case_started` | Scenario begins | `feature_start` (on feature change) + `scenario_start` |
| `on_test_case_finished` | Scenario ends | `scenario_end` + `feature_end` (on feature change) |
| `on_test_run_finished` | All scenarios done | `feature_end` (final) + `worker_end` |

**Event schema (JSONL):**

Every event has these common fields:

```json
{
  "type": "scenario_end",
  "worker": 2,
  "timestamp": "2026-08-07T13:22:45.123+0530"
}
```

Event-specific fields:

| Event | Key Fields |
|-------|-----------|
| `worker_start` | `pid`, `started_at` |
| `feature_start` | `feature` (path), `feature_name`, `feature_index` |
| `scenario_start` | `feature`, `scenario`, `line`, `scenario_number` |
| `scenario_end` | `feature`, `scenario`, `line`, `status`, `duration_s`, `error`, `counts` (cumulative), `total_scenarios` |
| `feature_end` | `feature`, `duration_s` |
| `worker_end` | `pid`, `finished_at`, `total_scenarios`, `counts`, `features_run` |

**Status mapping:**

```ruby
Cucumber::Core::Test::Result::Passed    → :passed
Cucumber::Core::Test::Result::Failed    → :failed
Cucumber::Core::Test::Result::Skipped   → :skipped
Cucumber::Core::Test::Result::Pending   → :pending
Cucumber::Core::Test::Result::Undefined → :pending
```

**Failure tracking:** On each failed scenario, the formatter appends to `worker_N_failures.txt`:

```
features/core/access_rights.feature:42 # Scenario: User can see fund models
  StandardError: expected 200, got 500
```

**Safety:** All writes are wrapped in `rescue StandardError` — the formatter never crashes the test run.

### 2. Dashboard Server (`dashboard_server.rb`)

**Class:** `DashboardServer`

A WEBrick HTTP server on port 9777 with the following endpoints:

#### `GET /` — Serve Dashboard HTML

Returns `dashboard.html` as `text/html`.

#### `GET /poll?cursor=<cursor>` — Polling Endpoint

The core data channel. The cursor is a string encoding byte offsets per worker file:

```
worker_1.jsonl:4523,worker_2.jsonl:8901
```

**Algorithm:**
1. For each `worker_*.jsonl` file in `/tmp/cucumber_progress/`:
   - Parse cursor to get last-read byte offset for this file
   - If file has grown since last offset, seek to offset and read new lines
   - Parse each line as JSON and append to events array
   - Record new byte offset
2. Read `total_scenarios` file if present
3. Check if the spawned process has exited (`Process.waitpid2` with `WNOHANG`)
4. Return `{ events, cursor, total_scenarios, run_status, run_pid }`

**Poll interval:** Browser polls every 500ms during runs, 5000ms when idle/finished.

#### `POST /run` — Start a Test Run

**Request body:**

```json
{
  "workers": 3,
  "feature_path": "features/",
  "skip_ai": true,
  "send_email": false,
  "email_to": ""
}
```

**Process:**
1. Reject if a run is already in progress
2. **Check for pending migrations** — runs `db:migrate:status` and rejects if any migrations are `down`
3. **Expand paths with AI exclusion** — if `skip_ai` is true and path is `features/`, lists all subdirectories under `features/` except `ai/` and joins them as comma-separated paths
4. **Validate all paths exist** — returns error with missing paths if any are invalid
5. Clean `/tmp/cucumber_progress/`
6. Count total scenarios (grep for `^Scenario` lines)
7. **Reject if 0 scenarios found** — returns error instead of starting an empty run
8. Write `total_scenarios` and `run_config.json`
9. Clear previous console output
10. Normalize comma-separated paths to space-separated
11. Spawn `parallel_cucumber` with `Process.spawn(env, cmd, pgroup: true)` where `env` sets `RAILS_ENV=test`
12. Detach process and return PID + total count

**Validation errors:**
- `"Pending migrations found!"` — dev DB has unapplied migrations
- `"Database preparation in progress, please wait"` — a DB prep step is already running
- `"Path not found: features/core/nonexistent.feature"` — file/directory doesn't exist
- `"No scenarios found in the selected paths"` — paths exist but contain no Scenario lines

**Spawned command:**

```bash
RAILS_ENV=test RUBYOPT='-W0' \
  cd <PROJECT_DIR> && bundle exec parallel_cucumber <features> -n <workers> \
  -o "--require features --require <DASHBOARD_DIR> \
      --format CucumberDashboard::ProgressFormatter --out /dev/null" \
  > /tmp/cucumber_full_output.txt 2>&1
```

Key flags:
- `RAILS_ENV=test` — ensures workers connect to SQLite test DBs, not MySQL dev DB (passed via `Process.spawn` env hash)
- `RUBYOPT='-W0'` — suppress Ruby warnings
- `--require features` — load step definitions (must come first, otherwise `--require <DASHBOARD_DIR>` overrides Cucumber's autoload)
- `--format ... --out /dev/null` — our formatter writes to JSONL files, not STDOUT. `--out /dev/null` avoids the "all but one formatter must use --out" error
- `pgroup: true` — creates a process group so Stop can kill the entire tree
- `> /tmp/cucumber_full_output.txt 2>&1` — captures all stdout/stderr for the console panel

#### `POST /stop` — Stop All Workers

Aggressively kills everything regardless of how the run was started:
1. If tracked PID exists: send `TERM` to process group, wait 0.5s, send `KILL`
2. Run `pkill -f 'parallel_cucumber'` to catch parent
3. Run `pkill -f 'cucumber.*features'` to catch worker children

No precondition checks — always attempts the kill and returns success.

#### `GET /console?offset=<byte_offset>` — Console Output Stream

Returns new content from `/tmp/cucumber_full_output.txt` since the given byte offset:

```json
{
  "content": "...new output lines...",
  "offset": 84523
}
```

The browser tracks its offset and only receives new data on each poll. Poll interval: 1s during runs, 3s when idle.

#### `GET /rerun_file?worker=<id>` — Read Worker Failure File

Returns the content of `/tmp/cucumber_progress/worker_N_failures.txt` as JSON:

```json
{
  "path": "/tmp/cucumber_progress/worker_1_failures.txt",
  "content": "features/core/access_rights.feature:42 # Scenario: ...\n..."
}
```

#### `POST /reset` — Clear All State

Deletes `/tmp/cucumber_progress/`, recreates the directory, resets server state to idle.

#### `POST /send_email` — Send Email Notification

Handles two types:
- `type: 'failure'` — sends per-scenario failure email
- `type: 'completion'` (default) — sends run summary email

Spawns a separate Ruby process that loads the Rails environment and calls the mailer. This avoids loading Rails into the WEBrick server process.

### 3. Dashboard Frontend (`dashboard.html`)

A single HTML file with embedded CSS and JavaScript. No build step, no external dependencies.

#### Theming

CSS custom properties on `:root` with three layers:
1. Default (dark theme)
2. `@media (prefers-color-scheme: light)` — OS preference
3. `:root[data-theme="dark"]` / `:root[data-theme="light"]` — manual toggle override

#### State Management

A plain JavaScript object tracks all dashboard state:

```javascript
state = {
  workers: {},           // keyed by worker ID
  workerFailures: {},    // keyed by worker ID, arrays of failure objects
  startTime: null,
  totalCompleted: 0,
  totalPassed: 0,
  totalFailed: 0,
  totalSkipped: 0,
  totalScenarios: null,  // from /run response; poll only sets if null
  finished: 0,           // workers done count
  workerCount: 0,
  timerInterval: null,
  runStatus: 'idle',     // idle | running | finished | stopped
  notifyEnabled: true,
  allDoneFired: false
}
```

**Note:** `totalScenarios` is set from the `/run` response and only falls back to the poll's `total_scenarios` if not already set. This prevents stale counts from a previous run overwriting the current run's count. `resetState()` clears `totalScenarios` to `null`.

#### Polling Loop

Two independent polling loops:

```
Event poll:   poll() → fetch /poll?cursor=...   → process events   → setTimeout (500ms / 5000ms)
Console poll: pollConsole() → fetch /console?offset=... → append text → setTimeout (1000ms / 3000ms)
```

Error handling: exponential backoff on fetch failures (2s, 4s, 8s, max 10s). Connection indicator dot goes red.

#### Event Processing

Each polled event is routed by `type` to a handler:

| Event | Handler | What It Does |
|-------|---------|-------------|
| `worker_start` | `onWorkerStart` | Creates worker state, shows worker grid, starts timer, shows Stop button |
| `feature_start` | `onFeatureStart` | Updates worker's current feature display |
| `scenario_start` | `onScenarioStart` | Updates worker's current scenario |
| `scenario_end` | `onScenarioEnd` | Updates counts (delta-based), records failures, triggers notifications/emails |
| `feature_end` | `onFeatureEnd` | Adds to feature timeline |
| `worker_end` | `onWorkerEnd` | Marks worker done, triggers `onAllDone` when all workers finish |

**Count tracking:** The formatter sends cumulative counts per worker. The dashboard computes deltas:

```javascript
state.totalPassed += (w.passed - oldPassed);
```

This prevents double-counting if events are replayed.

#### Rendering

`renderWorker(id)` rebuilds the entire worker card innerHTML on each update. This is simple and fast enough for 2-8 worker cards. Each card contains:

1. Header: badge, PID, status
2. Current feature/scenario
3. Pass/fail/skip counts with colored dots
4. Failed scenarios list (if any)
5. Rerun file section (if failures exist) — fetches content from `/rerun_file`
6. Feature timeline (completed features with durations)

#### Console Panel

A fixed-position panel at the bottom of the page:
- Toggle open/closed by clicking the bar
- Polls `/console?offset=N` independently from the event poll
- Appends new content and auto-scrolls to bottom
- Green dot when output is actively streaming
- **Clear** button to manually reset console content and offset
- Auto-cleared when a new run starts (offset and content reset)
- Cleared on Reset (offset reset to 0, content cleared)

#### Notifications

**Browser:** Uses the Notification API. Permission requested on page load. Fires on:
- Each scenario failure (tagged by worker+line to avoid duplicates)
- Run completion

**Email (Phase 2):** POST to `/send_email` endpoint. Backend is functional but UI controls are hidden. When enabled:
- Each scenario failure (immediate, from `onScenarioEnd`)
- Run completion (from `onAllDone`, includes full failure summary)

### 4. Completion Mailer (`completion_mailer.rb`) — Phase 2

**Class:** `CucumberDashboard::CompletionMailer < ActionMailer::Base`

> **Note:** The mailer is fully functional but the UI controls to enable email alerts are hidden. They will be exposed in Phase 2.

Three mail methods:

#### `run_complete(to, summary)`

Subject: `Cucumber Run Complete — {status} ({total} scenarios, {duration})`

HTML email with:
- Summary table: Passed / Failed / Skipped / Duration
- Failed scenarios table (if any): location, scenario name, worker, error

#### `run_started(to, config)`

Subject: `Cucumber Run Started — {workers} workers, {total} scenarios`

HTML email with run configuration details (workers, feature paths, start time).

#### `scenario_failed(to, failure)`

Subject: `FAILED — {scenario} ({location})`

HTML email with:
- Scenario name, file:line, worker ID
- Error message

All methods render inline ERB templates (no external template files). Uses real SMTP delivery (credentials passed via environment variables per invocation).

### 5. Shell Script (`run.sh`)

Two modes:

**Server-only** (`./run.sh`):
- Starts `dashboard_server.rb` in foreground
- Tests are started from the dashboard UI

**Direct run** (`./run.sh features/ -n 4`):
- Counts scenarios via `grep -r -c "Scenario"`
- Writes count to `/tmp/cucumber_progress/total_scenarios`
- Starts dashboard server in background
- Runs `parallel_cucumber` with formatter flags
- Waits for run to complete, keeps server alive for inspection

## Data Flow Diagram

```
1. User clicks "Start Run" in browser
   ↓
2. POST /run { workers: 4, feature_path: "features/" }
   ↓
3. Server checks for pending migrations (rejects if any are down)
   ↓
4. Server validates paths exist and contain scenarios
   ↓
5. Server counts scenarios, writes total_scenarios file, clears console output
   ↓
6. Server spawns with RAILS_ENV=test: parallel_cucumber features/ -n 4 -o "... --format ProgressFormatter ..."
   ↓
7. parallel_cucumber spawns 4 worker processes (all inherit RAILS_ENV=test)
   ↓
8. Each worker loads ProgressFormatter, writes worker_start to worker_N.jsonl
   ↓
9. Browser polls GET /poll every 500ms + GET /console every 1s
   ↓
10. Server reads new bytes from each worker_N.jsonl and cucumber_full_output.txt
   ↓
11. Server returns new events + updated cursor / new console content + offset
   ↓
12. Browser processes events, updates worker cards, summary stats, progress bar, console
   ↓
13. On failure: browser shows notification (email alerts planned for Phase 2)
   ↓
14. On all workers done: browser shows finished banner
```

## Key Design Decisions

### Why JSONL files instead of a database or socket?

- Each worker process is independent — no shared memory or IPC needed
- File appends are atomic at the OS level for small writes
- The server doesn't need to be running when workers write — it reads at its own pace
- No additional dependencies (no Redis, no SQLite)
- Files persist after the run for debugging

### Why cursor-based polling instead of SSE/WebSocket?

WEBrick's `chunked` response body doesn't flush to the browser reliably. SSE was attempted first but the browser never received events until the connection closed. Cursor-based polling with byte offsets is simple, reliable, and has low overhead (reading a few KB of new data every 500ms).

### Why spawn a separate process for emails?

The mailer needs the full Rails environment loaded (`config/environment`). Loading Rails into the WEBrick server would add 10+ seconds to startup and consume significant memory. Spawning a short-lived Ruby process that loads Rails just-in-time keeps the dashboard server lightweight.

### Why process groups for stopping?

`parallel_cucumber` spawns child processes which may outlive the parent if only the parent is killed. `Process.spawn(cmd, pgroup: true)` creates a process group, and `Process.kill('-TERM', pid)` sends the signal to the entire group. The additional `pkill` commands catch edge cases where workers were spawned outside the tracked process group (e.g., CLI-started runs).

### Why `--require features` in the command?

When `--require <dashboard_dir>` is specified, Cucumber stops auto-loading step definitions from `features/step_definitions/`. The explicit `--require features` before our require restores the default autoload behavior. Without this, all scenarios show as "undefined" (0 passed, 0 failed, N undefined).

### Why pass RAILS_ENV=test via Process.spawn?

Without `RAILS_ENV=test`, Cucumber workers boot in development mode and connect to the MySQL dev database instead of the SQLite test databases at `/dev/shm/test_*.sqlite3`. The env is passed via `Process.spawn`'s env hash so it is inherited by all child processes spawned by `parallel_cucumber`.

### Why check for pending migrations before starting?

If the dev DB has pending migrations, the test run will fail with cryptic errors (missing tables, column mismatches). Checking `db:migrate:status` upfront gives a clear error message telling the user to run `bin/rails db:migrate` first, before any workers are spawned.

### Why validate paths before starting?

Without validation, `parallel_cucumber` would spawn workers that immediately error out on missing files. The dashboard would show "Workers starting up..." forever with 0 scenarios. Validating upfront gives immediate feedback via a toast error, preventing wasted time and confusion.

## Error Handling

| Layer | Strategy |
|-------|----------|
| Formatter | All file writes wrapped in `rescue StandardError` — never crashes the test run |
| Server `/run` | Checks pending migrations, validates paths exist and contain scenarios before spawning workers. Returns structured error JSON on failure |
| Server general | WEBrick catches exceptions per-request. `count_scenarios` and `read_total_scenarios` rescue to safe defaults (0 / nil) |
| Stop | Tries TERM → KILL → pkill. Each step rescues `Errno::ESRCH` in case the process is already gone. No precondition — always attempts kill |
| Frontend | Poll errors trigger exponential backoff. Fetch failures show toast. Connection dot indicates server reachability |
| Email | Spawned in a detached process — failures are logged to STDOUT but never block the server or dashboard |

## Configuration Constants

| Constant | Value | Location |
|----------|-------|----------|
| `PORT` | 9777 | `dashboard_server.rb` |
| `PROGRESS_DIR` | `/tmp/cucumber_progress` | `dashboard_server.rb`, `progress_formatter.rb` |
| Default workers | 3 | `dashboard.html` |
| Default skip AI | true | `dashboard.html` |
| Event poll interval (running) | 500ms | `dashboard.html` |
| Event poll interval (idle) | 5000ms | `dashboard.html` |
| Console poll interval (running) | 1000ms | `dashboard.html` |
| Console poll interval (idle) | 3000ms | `dashboard.html` |
| Max workers | 16 | `dashboard_server.rb` (clamp) |
| Error truncation | 300 chars | `progress_formatter.rb` |
| Console panel height | 280px | `dashboard.html` |
| Rerun file scroll height | 120px | `dashboard.html` |
| Failure list scroll height | 150px | `dashboard.html` |

## API Summary

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/` | GET | Serve dashboard HTML |
| `/poll` | GET | Cursor-based event stream |
| `/console` | GET | Cursor-based console output stream |
| `/run` | POST | Start a test run (with validation) |
| `/stop` | POST | Kill all cucumber processes |
| `/reset` | POST | Clear progress data and state |
| `/rerun_file` | GET | Read per-worker failure file |
| `/send_email` | POST | Send completion or failure email |
