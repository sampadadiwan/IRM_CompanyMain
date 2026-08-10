# Cucumber Dashboard — Quick Start

## Setup

1. Extract the archive into your project root:

```bash
tar xzf cucumber_dashboard.tar.gz
```

This creates a `cucumber_dashboard/` folder in your project directory.

2. Make the run script executable:

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
   features/core/login.feature features/funds/capital_call.feature
   ```
3. Click **Start Run**
4. Watch progress in real-time — each worker gets its own card showing current scenario, pass/fail counts, and failures

## Stop a Run

Click **Stop** on the dashboard. This kills all cucumber worker processes.

To stop from terminal: `pkill -f cucumber`

## After the Run

- Failed scenarios appear under each worker card with error details
- **Rerun files** show at the bottom of each worker card — copy the `feature:line` entries to re-run only failures:
  ```bash
  bundle exec cucumber features/core/login.feature:42 features/funds/capital_call.feature:18
  ```
- Click **Reset** to clear results before starting a new run

## Optional: Email Alerts

Check **Email alerts**, enter your email address, and click Start. You'll get:
- An email on each scenario failure
- A summary email when the run completes

Uses Rails ActionMailer — in dev mode, emails open in browser tabs via `letter_opener`.

## Files

| File | Purpose |
|------|---------|
| `run.sh` | Starts the dashboard server |
| `dashboard_server.rb` | HTTP server (port 9777) |
| `dashboard.html` | Frontend UI |
| `progress_formatter.rb` | Cucumber event tracker |
| `completion_mailer.rb` | Email notifications |

For detailed documentation, see `docs/cucumber_dashboard/`.
