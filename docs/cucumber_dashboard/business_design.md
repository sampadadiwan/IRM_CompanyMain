# Cucumber Dashboard — User Guide

## What Is It?

The Cucumber Dashboard is a real-time web UI for monitoring parallel Cucumber test runs. Instead of watching a terminal scroll with opaque output, you get a live dashboard at `http://localhost:9777` showing exactly what each worker is doing, which scenarios passed or failed, and how far along the overall run is.

## Why Do We Need It?

Running `parallel_cucumber` with multiple workers produces interleaved, hard-to-read terminal output. There is no visibility into:

- How many workers are actually running
- Which features each worker is processing
- How many scenarios have passed, failed, or are still running
- Which specific scenarios failed and why
- Overall progress toward completion
- What's happening in the background (raw console output)

The dashboard solves all of these problems with a single browser tab.

## How to Start

### Option 1: Dashboard Only (Recommended)

Start the server from your project root:

```bash
ruby cucumber_dashboard/dashboard_server.rb
```

Open `http://localhost:9777`. You'll see:
- A config bar at the top to set worker count, feature selection, email/browser alerts
- A **Start Run** button to kick off tests
- A **Stop** button (appears during runs) to kill all workers
- A **Reset** button to clear results and start fresh
- A **Console Output** panel at the bottom for raw background output

To stop the server, press `Ctrl+C`.

### Option 2: Dashboard + Immediate Run

Start the server and immediately begin a test run:

```bash
cd cucumber_dashboard
./run.sh features/ -n 4
```

This counts scenarios, starts the dashboard server, and launches `parallel_cucumber` all at once.

## Dashboard Layout

### Config Bar

| Control | What It Does |
|---------|-------------|
| **Workers** dropdown | Choose how many parallel workers (2, 4, 6, or 8) |
| **All Features** checkbox | When checked, runs all features. Uncheck to specify individual paths |
| **Feature paths** text input | Space-separated `.feature` file paths (visible when "All Features" is unchecked) |
| **Start Run** button | Begin the parallel test run |
| **Stop** button | Kill all running cucumber workers immediately |
| **Reset** button | Clear all progress data and return to initial state |

> **Phase 2 (planned):** Email alerts and browser notification controls are built into the backend but hidden from the UI. They will be enabled in a future release.

### Running Specific Features

1. Uncheck **All Features**
2. In the text input, type space-separated paths:
   ```
   features/core/access_rights.feature features/ai/support_agents/call_notice_agent.feature
   ```
3. Click **Start Run**

You can specify individual `.feature` files or entire directories (e.g. `features/core/`).

**Validation:** The dashboard validates all paths before starting. If a path doesn't exist, you'll see a red error toast (e.g. "Path not found: features/core/login.feature"). If the selected paths contain no scenarios, you'll see "No scenarios found in the selected paths". The run won't start until the paths are valid.

### Summary Strip

Five stats shown in real-time:

- **Progress** — completed / total (with percentage)
- **Passed** — green count of passing scenarios
- **Failed** — red count of failing scenarios
- **Running** — orange count of currently executing scenarios
- **Skipped** — grey count of skipped/pending scenarios

A progress bar below the stats shows passed (green) and failed (red) proportions visually.

### Worker Cards

Each worker gets its own card showing:

- **Worker ID** (W1, W2, etc.) and **PID**
- **Status** — IDLE, RUNNING, or DONE
- **Current feature** and **current scenario** being executed
- **Pass/Fail/Skip counts** for that worker
- **Features completed** count

#### Failed Scenarios

When a worker encounters failures, the card expands to show:

- **FAILED section** — each failed scenario with:
  - Feature file path and line number
  - Scenario name
  - Error message (truncated)

#### Rerun File

Below the failures, a **Rerun File** section appears showing:

- The file path (`/tmp/cucumber_progress/worker_N_failures.txt`)
- A scrollable box with the file contents — `feature:line` entries you can copy

You can use these entries to re-run only failed scenarios:

```bash
bundle exec cucumber features/core/access_rights.feature:42 features/ai/kyc_validation.feature:18
```

#### Feature Timeline

At the bottom of each card, a scrollable timeline shows completed features with:

- Pass/fail indicator (checkmark or X)
- Feature name
- Duration

### Console Output Panel

A collapsible panel fixed at the bottom of the dashboard shows the raw `parallel_cucumber` output — the same content as `/tmp/cucumber_full_output.txt`. Click the **Console Output** bar to expand/collapse.

- Auto-scrolls to the latest output during a run
- Green dot indicator when output is actively streaming
- **Clear** button next to the label to manually clear console content
- Automatically cleared when a new run starts
- Polls every 1 second during runs, 3 seconds when idle
- Useful for debugging errors that don't surface in the worker cards (e.g. DB setup failures, missing step definitions)
- Cleared on Reset

### Finished Banner

When all workers complete, a banner appears:

- **Green** — "All N scenarios passed (MM:SS)"
- **Red** — "Run complete — N scenarios failed, M passed (MM:SS)"

### Elapsed Timer

Top-right corner shows a live clock counting up from when the first worker started.

## Notifications

> **Note:** Email and browser alert controls are hidden in the current UI. They will be enabled in Phase 2. The backend endpoints are fully functional.

### Browser Notifications (Phase 2)

Desktop notifications for:

- **Each scenario failure** — shows worker ID, scenario name, and file location
- **Run completion** — shows pass/fail summary and duration

### Email Notifications (Phase 2)

- **Each failure** — sends an email immediately when a scenario fails, with the scenario name, location, worker, and error
- **Run completion** — sends a summary email with pass/fail/skip counts, duration, and a table of all failed scenarios

Emails use Rails ActionMailer with real SMTP delivery. SMTP credentials are configured per-run in the UI.

## Stopping a Run

Click the **Stop** button during a run. This:

1. Sends TERM then KILL to the tracked process group
2. Runs `pkill` to catch any stray `parallel_cucumber` and cucumber worker processes
3. Returns the dashboard to idle state

The Stop button appears whenever workers are detected as running, regardless of whether the run was started from the dashboard UI or the command line. To stop from terminal directly: `pkill -f cucumber`.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Dashboard doesn't load | Check that the server is running (`ruby cucumber_dashboard/dashboard_server.rb`). Look for port 9777 conflicts. |
| "Pending migrations" error | Run `bin/rails db:migrate` then `RAILS_ENV=test bin/rails db:migrate` to sync both dev and test DBs. |
| "Test DB not ready" error | Run `RAILS_ENV=test bin/rails db:migrate` to prepare the test SQLite DB. |
| "Path not found" error | The feature file or directory you entered doesn't exist. Check the path spelling. |
| "No scenarios found" error | The path exists but contains no `Scenario` lines. Verify the feature file has scenarios. |
| Workers show but no progress | Open the Console Output panel to see raw errors. Check `/tmp/cucumber_full_output.txt`. |
| Stop doesn't kill workers | Run `pkill -f cucumber` manually in terminal. |
| Connection dot is red | Server may have crashed. Restart with `ruby cucumber_dashboard/dashboard_server.rb`. |
| All scenarios "undefined" | Step definitions aren't being loaded. Check that `--require features` is in the command. |
| Scenario count wrong after reset | Click Reset before starting a new run with different features. |

## File Locations

| File | Purpose |
|------|---------|
| `/tmp/cucumber_progress/worker_N.jsonl` | Per-worker event log (JSON Lines) |
| `/tmp/cucumber_progress/worker_N_failures.txt` | Per-worker failed scenarios for rerun |
| `/tmp/cucumber_progress/total_scenarios` | Total scenario count |
| `/tmp/cucumber_progress/run_config.json` | Run configuration snapshot |
| `/tmp/cucumber_full_output.txt` | Full console output from the run |
