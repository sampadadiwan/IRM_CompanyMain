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

The dashboard solves all of these problems with a single browser tab.

## How to Start

### Option 1: Dashboard Only (Recommended)

Start the server, then configure and run tests from the browser:

```bash
cd cucumber_dashboard
./run.sh
```

Open `http://localhost:9777`. You'll see:
- A config bar at the top to set worker count, feature selection, email/browser alerts
- A **Start Run** button to kick off tests
- A **Stop** button (appears during runs) to kill all workers
- A **Reset** button to clear results and start fresh

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
| **Email alerts** checkbox | Enable email notifications on failures and run completion |
| **Browser alerts** checkbox | Enable desktop notifications (requires browser permission) |
| **Start Run** button | Begin the parallel test run |
| **Stop** button | Kill all running cucumber workers immediately |
| **Reset** button | Clear all progress data and return to initial state |

### Running Specific Features

1. Uncheck **All Features**
2. In the text input, type space-separated paths:
   ```
   features/core/login.feature features/funds/capital_call.feature features/ai/support_agents/
   ```
3. Click **Start Run**

You can specify individual `.feature` files or entire directories.

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
- A scrollable box with the file contents — `feature:line` entries

You can use these entries to re-run only failed scenarios:

```bash
bundle exec cucumber features/core/login.feature:42 features/funds/capital_call.feature:18
```

#### Feature Timeline

At the bottom of each card, a scrollable timeline shows completed features with:

- Pass/fail indicator (checkmark or X)
- Feature name
- Duration

### Finished Banner

When all workers complete, a banner appears:

- **Green** — "All N scenarios passed (MM:SS)"
- **Red** — "Run complete — N scenarios failed, M passed (MM:SS)"

### Elapsed Timer

Top-right corner shows a live clock counting up from when the first worker started.

## Notifications

### Browser Notifications

When enabled (checked by default), you get desktop notifications for:

- **Each scenario failure** — shows worker ID, scenario name, and file location
- **Run completion** — shows pass/fail summary and duration

Your browser will ask for notification permission on first visit.

### Email Notifications

When enabled:

- **Each failure** — sends an email immediately when a scenario fails, with the scenario name, location, worker, and error
- **Run completion** — sends a summary email with pass/fail/skip counts, duration, and a table of all failed scenarios

Emails use Rails ActionMailer. In development, `letter_opener` opens them in browser tabs automatically.

## Stopping a Run

Click the **Stop** button during a run. This:

1. Sends TERM then KILL to the process group
2. Runs `pkill` to catch any stray cucumber workers
3. Returns the dashboard to idle state

The Stop button appears whenever workers are detected as running, regardless of whether the run was started from the dashboard UI or the command line.

## Keyboard Shortcuts

None currently — all interaction is mouse/touch based.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Dashboard doesn't load | Check that the server is running (`./run.sh`). Look for port 9777 conflicts. |
| Workers show but no progress | Verify features exist at the specified paths. Check `/tmp/cucumber_full_output.txt` for errors. |
| Stop doesn't kill workers | Run `pkill -f cucumber` manually in terminal. |
| Email not arriving | Check that `letter_opener` is configured in development. Verify email address is entered. |
| Connection dot is red | Server may have crashed. Restart with `./run.sh`. |
| All scenarios "undefined" | Step definitions aren't being loaded. Check that `--require features` is in the command. |

## File Locations

| File | Purpose |
|------|---------|
| `/tmp/cucumber_progress/worker_N.jsonl` | Per-worker event log (JSON Lines) |
| `/tmp/cucumber_progress/worker_N_failures.txt` | Per-worker failed scenarios for rerun |
| `/tmp/cucumber_progress/total_scenarios` | Total scenario count |
| `/tmp/cucumber_progress/run_config.json` | Run configuration snapshot |
| `/tmp/cucumber_full_output.txt` | Full console output from the run |
