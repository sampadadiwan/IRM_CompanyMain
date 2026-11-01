# PR notes — Report Builder with live preview, and a reworked guided wizard (draft for the PR body)

Phase 2 of `docs/modules/reports/report_builder_usability_plan.md`. Design: `openspec/changes/report-builder-live-builder/design.md`.

## What changes

- **Builder page:** settings in tabs on the left, a preview on the right that loads by itself. Every change answers with the settings panel, the preview and the report check together (Turbo Streams) — no Build/View toggle, no Refresh Preview, no page reloads.
- **Columns:** a grouped picker (by source, then Amounts / Dates / Yes/No / Names & text; internal id and cents fields hidden; same-label fields told apart) with **Add selected**; related columns bring their related data. Each preview header has a menu: Rename, Total, Move left/right, Remove.
- **Filters:** each field gets its own input (date, Yes/No, fund, number, a value list for text with ≤ 30 values, text) and operators in words; filters save themselves after a pause and say what an incomplete row needs. No pick-list queries on the largest tables.
- **Formulas:** click columns to insert them; results for the first five rows while typing. **Pivots:** "This will create N columns: …" before Apply.
- **Undo** for removing a column or related data (10 minutes, only while nothing else changed). The remove-related-data popup lists the columns that go with it.
- **Report check** in the header: blank columns, broken formula references, money summed across currencies, filters matching nothing, oversized pivots; notes for large exports and default totals. Each item has Fix.
- **Guided wizard:** five steps — table cards with example questions, own + related columns with totals inline, fund picker and sentence filters, sort + suggested calculations (Called %, Unpaid, Uncalled, DPI), summary cards + check + suggested name. A 5-row sample beside steps 2–5. Old step links redirect. The wizard's own stylesheet is gone (app components only).

## Bugs found and fixed while building

- A **Count** of an amount column (and of a pivoted amount) was divided by 100 as if it were money: 1 commitment showed as 0.01, rounded to 0. Counts are now row counts.
- Investor KYC showed as "Investor kyc" in labels (acronym match was case-sensitive).
- Test-only: the "signed in as Omar from another entity" step kept Meera's session (Devise ignores a second sign-in), so other-entity refusals were tested as Meera; it now starts a fresh session.

## Changed from the design while building

- **E21** "No related data" can't happen — every report table has related data. It is now "Many related sources: only the table's own columns start open" (business rules, spec and QA checklist updated).
- H23 wording reads "Only capital commitments in Growth Fund II" (the related data's name), not "commitments".
- Wizard actions live in a `ReportBuilder::Wizard` concern rather than the 900-line controller.
- `confirm_controller.js` (shared) now carries the original form's `data-turbo-frame` into the popup's form. Forms without one behave exactly as before.
- report-builder-trust H25/H26 (wizard Summarize shows and saves Sum) are now covered by this change's H20/H21 scenarios; the Summarize step no longer exists.

## Deploy and rollback

- Code only — no migrations, no feature flag, no cron changes.
- `reports.template["undo"]` is a new key; the previous code ignores it. Rollback is a plain revert; optionally clear the key:
  `Report.where(report_builder: true).find_each { |r| r.update_columns(template: r.template.except("undo")) if r.template&.key?("undo") }`
- Bookmarked wizard links (`/wizard/columns`, …) redirect to the new steps; after a rollback the new step URLs (`/wizard/show`, …) would redirect to the old first step.

## Tests

`features/core/report_builder/` — all 61 worked examples (H1–H30, E1–E26, X1–X5) tagged one-to-one across `editor_{page,columns,filters,formulas,pivot,undo,health,live}.feature` and `wizard.feature`. User guide lint passes. RuboCop clean on every touched Ruby file.
