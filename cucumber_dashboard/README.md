# Cucumber Dashboard — Quick Start

## Setup

1. Extract the archive into your project root:

```bash
tar xzf cucumber_dashboard.tar.gz
```

This creates a `cucumber_dashboard/` folder in your project directory.

2. Make the run script executable (optional, only needed for CLI mode):

```bash
chmod +x cucumber_dashboard/run.sh
```

That's it. No gems to install, no config needed.

## Start the Dashboard

From your project root:

```bash
ruby cucumber_dashboard/dashboard_server.rb
```

Open **http://localhost:9777** in your browser.

To stop the server, press `Ctrl+C`.

## Run Tests

1. Choose worker count (2/4/6/8) from the dropdown
2. Leave **All Features** checked to run everything, or uncheck it and enter specific paths:
   ```
   features/core/access_rights.feature features/ai/kyc_validation.feature
   ```
   Paths are validated before starting — you'll see an error toast if a path doesn't exist or has no scenarios.
3. Click **Start Run**
4. Watch progress in real-time — each worker gets its own card showing current scenario, pass/fail counts, and failures

If you see a "Pending migrations" error, run:
```bash
bin/rails db:migrate
RAILS_ENV=test bin/rails db:migrate
```

## Console Output

Click the **Console Output** bar at the bottom to see the raw `parallel_cucumber` output — useful for debugging DB setup errors, missing steps, or anything not visible in the worker cards.

## Stop a Run

Click **Stop** on the dashboard. This kills all cucumber worker processes (including ones started from the terminal).

To stop from terminal: `pkill -f cucumber`

## After the Run

- Failed scenarios appear under each worker card with error details
- **Rerun files** show at the bottom of each worker card — copy the `feature:line` entries to re-run only failures:
  ```bash
  bundle exec cucumber features/core/access_rights.feature:42 features/ai/kyc_validation.feature:18
  ```
- Click **Reset** to clear results before starting a new run

## Email Alerts (Phase 2)

Email alert controls are hidden in the current UI. The backend is fully functional and will be exposed in a future release.

## Files

| File | Purpose |
|------|---------|
| `dashboard_server.rb` | HTTP server (port 9777) — start with `ruby` |
| `dashboard.html` | Frontend UI (single file, no build step) |
| `progress_formatter.rb` | Cucumber event tracker |
| `completion_mailer.rb` | Email notifications |
| `run.sh` | Alternative entry point for CLI mode |

For detailed documentation, see `docs/cucumber_dashboard/`.
