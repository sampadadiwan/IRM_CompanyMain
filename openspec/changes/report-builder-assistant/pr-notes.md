# PR notes — Report Builder assistant (draft for the PR body)

Phase 4 (last) of `docs/modules/reports/report_builder_usability_plan.md`. Design: `openspec/changes/report-builder-assistant/design.md`.

## What changes

- **New report › Describe it:** a question becomes a private draft report, drafted in the background by the company's AI model (`LlmService.ruby_llm_chat`). The model is asked in two steps:
  1. **REPORT TABLE**, from the company's report tables
  2. **REPORT SPEC**, with only that table's columns and related data, and two starter templates as examples
- **Every part of the answer is pruned** with the Phase 3 `ReportSpecValidator` (`ReportSpecPruner`). Failures go to **Couldn't do**: unknown columns, tables not in the account, filters on the company, and values that match nothing.
- **Draft page:**
  - guided setup's cards
  - the AI's questions (the fund is picked from the DB, with no AI call), assumptions and Couldn't do
  - Refine, which sends `spec_from(report)` so hand edits are kept
  - the 20-row preview with the report check
  - Save and open / Fine-tune / Discard
- **Charts:** a suggested chart by rules (bar / line / stacked; no AI call), **No chart**, or **Describe a chart** (`ChartAgentService` with the 20 preview rows, stated in the UI). The report page shows the chart above the table with **Hide chart**.
- **Private drafts:**
  - a Report with `category: "AI draft"`
  - `ReportPolicy` scope and `show?`/`update?` limit drafts to their maker
  - a Draft badge
  - `ReportDraftCleanupJob`, daily, deletes drafts unchanged for 7 days
- `ReportSpecApplier.apply!` gains `replace:` (rewrites a draft's columns, keeping `draft`/`ai`/`chart`).

## Existing code touched

- `ReportPolicy` (draft privacy) — flagged in the design.
- `config/initializers/sidekiq.rb` — one daily cron.

## Data sent to the AI

Table and column names, the question, refinements and the current spec. No rows, except for **Describe a chart**, which the UI states.

## Deploy and rollback

- No migrations.
- Needs a default AI model per entity, or `DEFAULT_MODEL`. Without one, the page says "AI drafting isn't set up for your account".
- Rollback: revert. Unsaved drafts stay as reports with category "AI draft"; delete them with `Report.where(category: "AI draft").destroy_all` if wanted.

## Tests

`assistant`, `assistant_chart`: 28 worked examples (H1–H9, E1–E12, X1–X7). The AI is stubbed at `LlmService.ruby_llm_chat` with a fake chat that records prompts.
