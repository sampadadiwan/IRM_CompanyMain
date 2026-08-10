# Cucumber Dashboard — Technical Design

## Architecture Overview

The dashboard is a self-contained tool (no gem dependencies beyond Rails) with four components:

```
                  ┌─────────────────────────┐
                  │    Browser (dashboard)   │
                  │    http://localhost:9777  │
                  └────────┬────────────────┘
                           │ HTTP polling (500ms)
                           │
                  ┌────────▼────────────────┐
                  │    WEBrick Server        │
                  │    dashboard_server.rb   │
                  │    Port 9777             │
                  └────────┬────────────────┘
                           │ reads JSONL files
                           │
              ┌────────────▼──────────────────┐
              │   /tmp/cucumber_progress/      │
              │   worker_1.jsonl               │
              │   worker_2.jsonl               │
              │   worker_1_failures.txt        │
              │   worker_2_failures.txt        │
              │   total_scenarios              │
              │   run_config.json              │
              └────────────▲──────────────────┘
                           │ writes events
                           │
          ┌────────────────┴──────────────────┐
          │  Cucumber Workers (parallel_cucumber)  │
          │  Each runs ProgressFormatter            │
          │  Identified by TEST_ENV_NUMBER          │
          └────────────────────────────────────┘
```

**Data flow:** Cucumber workers write JSONL events to per-worker files. The WEBrick server reads these files on each poll request. The browser polls the server every 500ms and renders worker state in real-time.

There is no WebSocket or SSE — WEBrick's chunked response handling doesn't flush reliably. Cursor-based polling (tracking byte offset per file) is simple and works.

## File Structure

```
cucumber_dashboard/
├── run.sh                 # Entry point — starts server, optionally runs tests
├── dashboard_server.rb    # WEBrick HTTP server with all API endpoints
├── dashboard.html         # Single-file frontend (HTML + CSS + JS, no build step)
├── progress_formatter.rb  # Cucumber formatter — hooks into test lifecycle events
└── completion_mailer.rb   # ActionMailer for email notifications
```

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
features/core/login.feature:42 # Scenario: User can log in
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
  "workers": 4,
  "feature_path": "features/",
  "send_email": false,
  "email_to": ""
}
```

**Process:**
1. Reject if a run is already in progress
2. Clean `/tmp/cucumber_progress/`
3. Count total scenarios (grep for `^Scenario` lines)
4. Write `total_scenarios` and `run_config.json`
5. Normalize comma-separated paths to space-separated
6. Spawn `parallel_cucumber` with `Process.spawn(cmd, pgroup: true)`
7. Detach process and return PID + total count

**Spawned command:**

```bash
cd <PROJECT_DIR> && RUBYOPT='-W0' bundle exec parallel_cucumber <features> -n <workers> \
  -o "--require features --require <DASHBOARD_DIR> \
      --format CucumberDashboard::ProgressFormatter --out /dev/null" \
  > /tmp/cucumber_full_output.txt 2>&1
```

Key flags:
- `RUBYOPT='-W0'` — suppress Ruby warnings
- `--require features` — load step definitions (must come first, otherwise `--require <DASHBOARD_DIR>` overrides Cucumber's autoload)
- `--format ... --out /dev/null` — our formatter writes to JSONL files, not STDOUT. `--out /dev/null` avoids the "all but one formatter must use --out" error
- `pgroup: true` — creates a process group so Stop can kill the entire tree

#### `POST /stop` — Stop All Workers

Aggressively kills everything:
1. If tracked PID exists: send `TERM` to process group, wait 0.5s, send `KILL`
2. Run `pkill -f 'parallel_cucumber'` to catch parent
3. Run `pkill -f 'cucumber.*features'` to catch worker children

This works regardless of whether the run was started from the dashboard or CLI.

#### `GET /rerun_file?worker=<id>` — Read Worker Failure File

Returns the content of `/tmp/cucumber_progress/worker_N_failures.txt` as JSON:

```json
{
  "path": "/tmp/cucumber_progress/worker_1_failures.txt",
  "content": "features/core/login.feature:42 # Scenario: ...\n..."
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
  totalScenarios: null,  // from server
  finished: 0,           // workers done count
  workerCount: 0,
  timerInterval: null,
  runStatus: 'idle',     // idle | running | finished | stopped
  notifyEnabled: true,
  allDoneFired: false
}
```

#### Polling Loop

```
poll() → fetch /poll?cursor=... → process events → setTimeout(poll, delay)
                                                     ↑
                                        500ms if running, 5000ms if idle
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

#### Notifications

**Browser:** Uses the Notification API. Permission requested on page load. Fires on:
- Each scenario failure (tagged by worker+line to avoid duplicates)
- Run completion

**Email:** POST to `/send_email` endpoint. Fires on:
- Each scenario failure (immediate, from `onScenarioEnd`)
- Run completion (from `onAllDone`, includes full failure summary)

### 4. Completion Mailer (`completion_mailer.rb`)

**Class:** `CucumberDashboard::CompletionMailer < ActionMailer::Base`

Two mail methods:

#### `run_complete(to, summary)`

Subject: `Cucumber Run Complete — {status} ({total} scenarios, {duration})`

HTML email with:
- Summary table: Passed / Failed / Skipped / Duration
- Failed scenarios table (if any): location, scenario name, worker, error

#### `scenario_failed(to, failure)`

Subject: `FAILED — {scenario} ({location})`

HTML email with:
- Scenario name, file:line, worker ID
- Error message

Both methods render inline ERB templates (no external template files).

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
3. Server counts scenarios, writes total_scenarios file
   ↓
4. Server spawns: parallel_cucumber features/ -n 4 -o "... --format ProgressFormatter ..."
   ↓
5. parallel_cucumber spawns 4 worker processes
   ↓
6. Each worker loads ProgressFormatter, writes worker_start to worker_N.jsonl
   ↓
7. Browser polls GET /poll every 500ms
   ↓
8. Server reads new bytes from each worker_N.jsonl since last cursor position
   ↓
9. Server returns new events + updated cursor
   ↓
10. Browser processes events, updates worker cards, summary stats, progress bar
   ↓
11. On failure: browser sends POST /send_email (if enabled), shows notification
   ↓
12. On all workers done: browser shows finished banner, sends completion email
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

## Error Handling

| Layer | Strategy |
|-------|----------|
| Formatter | All file writes wrapped in `rescue StandardError` — never crashes the test run |
| Server | WEBrick catches exceptions per-request. `count_scenarios` and `read_total_scenarios` rescue to safe defaults (0 / nil) |
| Stop | Tries TERM → KILL → pkill. Each step rescues `Errno::ESRCH` in case the process is already gone |
| Frontend | Poll errors trigger exponential backoff. Fetch failures show toast. Connection dot indicates server reachability |
| Email | Spawned in a detached process — failures are logged to STDOUT but never block the server or dashboard |

## Configuration Constants

| Constant | Value | Location |
|----------|-------|----------|
| `PORT` | 9777 | `dashboard_server.rb` |
| `PROGRESS_DIR` | `/tmp/cucumber_progress` | `dashboard_server.rb`, `progress_formatter.rb` |
| Poll interval (running) | 500ms | `dashboard.html` |
| Poll interval (idle) | 5000ms | `dashboard.html` |
| Max workers | 16 | `dashboard_server.rb` (clamp) |
| Error truncation | 300 chars | `progress_formatter.rb` |
| Rerun file scroll height | 120px | `dashboard.html` |
| Failure list scroll height | 150px | `dashboard.html` |
