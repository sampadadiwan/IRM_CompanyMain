# PR notes — Report Builder starting points (draft for the PR body)

Phase 3 of `docs/modules/reports/report_builder_usability_plan.md`. Design: `openspec/changes/report-builder-starting-points/design.md`.

## What changes

- **One New report menu** on the Reports page — From a template, Guided setup — replacing "New Custom Report" and "Builder Report". The standard reports list is unchanged.
- **Ten starter templates** (`config/report_builder_templates.yml`) on a new template page, grouped by area, each with the question it answers. **Use this** asks for a name and, where needed, a fund; **Create** makes a new report and opens it in the builder.
- **Fund on create:** money templates require one fund (no All funds); KYC is optional; fund-level and KPI templates ask for none. The fund goes on the rows when they have one, else on each related data that does — the same rule as guided setup (`ReportBuilderFundTarget`, now shared).
- **Duplicate** on the report card menu and the report page: "Copy of …" (unique), same set-up, no schedule, no pending Undo.
- **One spec applier + validator** (`ReportSpecApplier`, `ReportSpecValidator`) behind templates and Duplicate, reusable by the Phase 4 assistant. The validator asks the column catalog and column types — no second allow-list.
- **Template check** (`templates_check.feature`): every template validates, creates and runs on the Acme fixture; a broken column fails naming the template and the column.
- **Report check:** on reports of funds, mixed currencies become a note about the totals row instead of a "pick a fund" warning.
- **Naming:** "Guided setup" everywhere; "Guided Wizard", "Advanced builder", "Custom report", "New Report Builder" gone.

**BREAKING:** the builder's **Templates** button, its gallery and the `POST /report_builder/:id/apply_template` route are removed — a template can no longer replace an existing report. Trust H23/E26 scenarios removed with it; the trust spec's "Applying a template asks first" is a REMOVED delta here.

## Found while building

- The old "Builder Report" button checked `policy(Report.new).create?` with no entity, which is always false — so it never showed (the user guide said "no button"). The New report menu checks with the user's entity.
- Ransack drops a `false` filter value as blank, so a YAML `verified_eq: false` would silently not filter. Template filters use strings (`"false"`, `"true"`).
- Plan Appendix A, checked against the live catalog: "# Payments" (chase list) and "Last activity" (MOIC) dropped — no column to count / the same column can't be both min and max; the KPI matrix has no Excel grouping ("For" is display-only).
- Test-only: two Phase 1 steps ("filtered to", "saved sorted by") wrote back a stale template and wiped changes made over HTTP; they now reload first.

## Deploy and rollback

- Code and a YAML file only — no migrations, no flags, no jobs.
- Rollback: revert. Reports made from templates or by Duplicate are ordinary reports and keep working.

## Tests

`features/core/report_builder/` — all 26 worked examples of this change (H1–H12, E1–E9, X1–X5) tagged one-to-one in `starting_points`, `templates`, `templates_check` and `duplicate`. User guide lint passes. RuboCop clean on touched code (one pre-existing offense in `report_builder_model_discovery.rb` line 101 left as is).
