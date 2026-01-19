## Problem statement

“Reports” are user-saved Ransack filter definitions that, when opened, fetch and display the latest matching records.

We want to extend the existing Report feature with two new capabilities:

1. **AI Prompt (report-to-insights)**

   - Add an _AI Prompt_ field to the report form that lets a user describe what kind of insight they want from the report results (for example: “Summarize key changes since last month, highlight top 5 entities by revenue, and produce a trend chart”).
   - When a report is run, the system should fetch the latest data objects for the saved filters and package them as a machine-readable payload for an LLM (JSON).
   - The LLM is expected to return a **shareable output** typically containing:

     - A short summary (about 2–3 lines).
     - Data-driven visuals (for example charts/graphs derived from the report results).

   - Because the output format and content vary depending on the prompt, the system must handle **prompt-driven, flexible outputs** without hardcoding a single report template.

2. **Notify (scheduled generation + delivery)**

   - Add a _Notify_ configuration to the report form that allows a user to schedule automatic generation of the AI summary and email delivery to selected client recipients.
   - Scheduling must support intervals and offsets such as: “every 30 days starting 10 days from now”, and similar recurring patterns.
   - At each scheduled run, the system should:

     1. re-run the saved Ransack filters to fetch the latest dataset,
     2. generate the AI output using the current prompt,
     3. attach or link relevant data (JSON and/or Excel), and
     4. send an email to the configured recipients.

**Persistence + UI access requirement**

- Every generated AI result must be stored so it can be:

  - Viewed later in the application UI (via a stable URL per generated run).
  - Audited (what data snapshot was used, what prompt was used, when it ran, and what was sent).

## Success criteria

- Users can configure a report with an AI prompt and notification schedule.
- The system reliably generates AI summaries/graphs from the latest filtered dataset.
- Each run is saved and the latest one is viewable later from the UI via URL.
- Scheduled runs send client-ready emails at the configured cadence and start offset.
- The design supports changing prompts without requiring new code paths for each output style.

## SOLUTION

### Key decisions

- **Report has many ReportInsight** (each ReportInsight = one generated run/output)
- LLM returns:

  1. a **complete Markdown document** that can be rendered directly in the UI
  2. a **chart configuration payload** (JSON, not executable JS) that the UI uses to render charts

- **No Documents**, no stored chart images, no XLSX attachments
- Notify emails send **only a link** to the ReportInsight page

---

## 1) Domain model

### Report

```rb
# reports
ai_prompt:text                 # optional

send_notification:boolean         # default false
notification_recipients:string    # CSV
notification_ccs:string           # CSV

# Scheduling fields
notification_start_after:integer      # default 0
notification_start_unit:string        # default "days"
notification_repeat_interval:integer  # default 1
notification_repeat_unit:string       # default "days"

notify_start_at:datetime
notify_next_run_at:datetime
notify_last_run_at:datetime
```

### ReportInsight (one row = one output run)

```rb
# report_insights
report_id:bigint
entity_id:bigint

prompt_used:text              # final prompt sent to AI model
ai_response:text              # AI response (md file content) - stored as text
charts_spec:json              # chart configs (JSON) - stored as json
notes:text                    # AI generated notes

status:string                 # enum: running, success, failed
status_message:text

record_count:integer

triggered_at:datetime
trigger_type:string           # enum: manual, system
triggered_by_id:bigint        # nullable
created_at / updated_at
```

Notes:

- `ai_response` is the canonical display artifact (Markdown content).
- `charts_spec` is structured JSON only (safe), not arbitrary JS code.

---

## 2) LLM response contract (Markdown + chart specs)

### Why “JSON chart spec” instead of “JS”

If you allow raw JS from the LLM, you’re inviting XSS and arbitrary code execution. The safer pattern:

- LLM returns **JSON config** (e.g. for Chart.js, ECharts, Highcharts, etc.)
- Your frontend takes this JSON and renders charts via your trusted library

So the “JS config” in practice should be “JSON config used by JS”.

### Contract shape

The model must return a strict JSON envelope:

```json
{
  "md_body": "string (a complete Markdown document)",
  "charts": [
    {
      "id": "string",
      "library": "chartjs",
      "config": {
        "type": "...",
        "data": {...},
        "options": {...}
      }
    }
  ],
  "summary": "string (a complete Markdown document)",
  "notes": "string (optional)"
}
```

How Markdown references charts:

- Use tokens like `{{chart:<id>}}`
- UI replaces each token with a chart component that loads `charts` entry with matching `id`.

This gives you:

- Markdown is clean and readable
- Charts are decoupled and renderable
- Parsing stays deterministic

---

## 3) Execution flow

### A) Manual run (Generate button)

1. User clicks "Generate AI Report".
2. `GenerateReportInsightJob` is enqueued with `report_id`, `user_id`, and `triggered_by_id`.
3. Job performs:
   - Creates `ReportInsight` in `running` status.
   - Calls `ReportInsightRunner.call?` (Trailblazer operation).
   - `ReportInsightRunner`:
     - Fetches report data using Ransack.
     - Saves data as temporary JSON file.
     - Builds prompt with JSON schema instructions.
     - Calls LLM (RubyLLM).
     - Parses response (JSON).
     - Updates `ReportInsight` with `ai_response`, `charts_spec`, `status`, etc.
   - Updates `report.notify_last_run_at` and calculates `notify_next_run_at`.
   - Sends success/failure notification via `UserAlert`.
   - Sends email via `ReportInsightMailer` if successful.

### B) Scheduled run

A periodic scheduler checks due reports:

- `send_notification = true AND notify_next_run_at <= now`

For each:

1. Enqueue `GenerateReportInsightJob(report_id, trigger_type: "system")`.
2. Job executes same flow as manual run, but without `user_id` (so no UI alerts).
3. `ReportInsightMailer` sends email to `notification_recipients` and optionally `notification_ccs`.

---

## 4) Rendering on UI

### Markdown rendering

- Render `md_body` using a Markdown renderer (server-side or client-side).
- **Sanitize HTML** if you allow embedded HTML in markdown. Safer: disable raw HTML.

### Chart rendering

- During render, scan the markdown for `{{chart:key}}`
- Replace with a chart component that:

  - finds `charts_spec[key]`
  - validates it (library/type allowed, size bounds, dataset length bounds)
  - renders via your chosen chart library

This allows charts to “live” inside the markdown narrative.

---

## 5) Services/classes

### `GenerateReportInsightJob`

Responsibilities:

- Entry point for both manual and scheduled runs.
- Creates `ReportInsight` record.
- Calls `ReportInsightRunner`.
- Updates Report scheduling fields (`notify_last_run_at`, `notify_next_run_at`).
- Handles notifications (UserAlert, Email).

### `ReportInsightRunner` (Trailblazer Operation)

Responsibilities:

- `initialize_llm`: Sets up RubyLLM chat client.
- `get_report_data`: Fetches data using Ransack.
- `save_data_as_json`: Writes data to temp file (limits to 500 records).
- `build_prompt`: Constructs prompt with schema instructions.
- `get_llm_response`: Calls LLM with prompt and file attachment.
- `process_response`: Parses JSON response and validates charts.
- `update_report_insight`: Saves results to `ReportInsight` record.

---

## 6) URLs

- `/reports/:report_id/report_insights` (index)
- `/reports/:report_id/report_insights/:id` (show)

Show page:

- markdown rendered
- charts rendered inline
- metadata: sent_at, triggered_by, trigger_type, record_count, status

---

## 7) What we store (and don’t)

Stored:

- `ai_response` (the markdown artifact)
- `charts_spec` (JSON config)
- `notes`
- `prompt_used`
- `record_count`, status, error, timestamps

Not stored:

- `response_raw` (full LLM response)
- dataset snapshot (JSON)
- images
- documents/attachments

---
