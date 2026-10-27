---
name: client-onboarding
allowed-tools: Bash(ruby:*)
description: "Onboard a new CapHive client end to end: configure a fresh entity, map and transform the client's own xlsx into CapHive import templates, and import it through the application's import pipeline (never by writing to the DB). Use when onboarding a client, designing or building the onboarding agent and its MCP tools, mapping a client workbook to an import template, or deciding import order, custom fields or approvals for an onboarding."
---

# Client onboarding

> **Status: DESIGN (2026-10-18).** The rules and learnings below are agreed or verified; the
> onboarding MCP tools do not exist yet. Read [design-decisions.md](design-decisions.md) before
> building anything, and record new learnings in [learnings.md](learnings.md).

## Read in this order

1. This file — the hard rules and the per-step loop.
2. [design-decisions.md](design-decisions.md) — what was decided with the user, and why.
3. [runbook.md](runbook.md) — the entity-setup checklist (draft, derived from real clients).
4. [importer-behaviour.md](importer-behaviour.md) — verified facts about the import pipeline.
5. [api-gaps.md](api-gaps.md) — what the existing APIs cannot do yet (report, never patch).
6. [learnings.md](learnings.md) — append-only log from real onboardings.
7. [report-template.md](report-template.md) — **the report every onboarding produces** (checklist → how the source
   was mapped → proof it reconciles → log). Create it at the start, update it after every step.

## Hard rules (never waive)

1. **Never write to the database directly.** No SQL writes, no `rails console`, no `rails runner`,
   no ActiveRecord. Every write is an HTTP call to the app's existing `.json` endpoints as the ops
   user (bearer token, `WithAuthentication#authenticate_user!`), so Pundit, audits, callbacks and
   jobs run exactly as in the UI.
1a. **Verify through the API too — as in production.** No database queries (not even read-only), no `rails runner`,
   no reading app logs or stored files. Counts, row errors, sandbox, totals and units are read from API responses
   only; if the API cannot show something, record a gap and pause that step. (The first Orios trial verified with
   read-only DB queries — that hid how blind the agent is in production; don't repeat it.)
2. **Do not change the app's APIs.** Another workstream owns them. If an endpoint is missing or
   wrong, add it to [api-gaps.md](api-gaps.md) and stop that step; do not work around it.
3. **Fresh entities only.** Ops creates the bare entity in the UI and hands over its id. Refuse an
   entity that already has live users or data.
4. **Sandbox first, sandbox always.** The first write sets `entity_setting.sandbox = true` with
   `sandbox_emails` = the ops user's address. Re-check before every write; if sandbox is off, stop.
   Turning sandbox off (go-live) is a human action in the UI, never a tool.
5. **Investor access goes last** — after every other import is done and reconciled — and always
   needs explicit approval (not waivable). Investor advisors go in the same final step.
6. **Reads run freely; writes need approval**, unless ops has waived a type for this client
   (e.g. "all KYCs", "all remittances"), recorded in `onboarding/<client>/approvals.yml`.
   Undo (delete an upload's data) is never waivable.
7. **Claude transforms by writing a script, not by retyping values**, then reconciles source vs
   output mechanically (row counts, money totals, every source row and column accounted for).
8. **Client questions are mandatory.** Create `<client>_client_questions.md` in the workspace from
   [client-questions-template.md](client-questions-template.md) right after profiling the source, before the first
   import, and update it after every step that makes an assumption. **Every assumption has a question id** — the same
   id goes on the assumption in the mapping yml (`q:`), and the tools refuse a `q:` that is not in the file. Go-live
   cannot be ticked while a question marked "(needed before go-live)" is unanswered.
9. **The must-have gate.** Every fund needs answers M1–M13 (questions file, section M): fund terms (M1–M5), folios
   and commitments (M6), drawdowns and payments (M7–M9, M11), distributions (M10–M11), investor contacts and KYC
   (M12–M13), and with a portfolio in scope (`mappings/portfolio.yml`) holdings (M15), KPI → MIS lines and reporting
   convention (M16–M17). `tools/gate.rb` blocks each step until its M items are answered — the builders and `api.rb` call it.
   **Check-data override:** `mode: check_data` in `onboarding.yml`, with `check_data_approved_by` and
   `check_data_approved_on`, lets fund / commitments / drawdowns / distributions / portfolio / kpis run on assumptions so the data can be
   imported and checked. It never unlocks investor access or go-live, which also need **M14 — a fund-ops reviewer's
   sign-off** (set only by the reviewer). **Go-live also needs a passing fund
   reconciliation** (`tools/fund/fund_recon.rb` → `out/fund_recon.json` with `passed: true`), and with a portfolio a passing
   portfolio reconciliation (`tools/portfolio/portfolio_recon.rb` → `out/portfolio_recon.json`).
10. **Ops reviews every upload file by hand before it goes in** (ops, 2026-10-20). Build the upload files from the raw data,
   dump them with `tools/review.rb dump` into `<workspace>/review/` (copies + `REVIEW.md`: rows, columns, money totals, dates,
   SHA-256 per file) and **stop**. Ops approves **in the session** (ops, 2026-10-27: "approval should be from here"):
   show `ruby <tools>/review.rb summary` (one line per waiting file: rows, money totals, then a **summary code**) and ask
   ops with a question prompt — **Approve all** / **Not yet** / other (e.g. "all except 07"). Only on ops' answer, run
   `review.rb approve --all --summary <that code>` (or `approve <file>` for the ones ops named) `--by <ops name> --via
   "Claude Code session — answered '<ops' exact answer>'"`. The code pins the exact files and hashes ops was shown:
   anything rebuilt or added in between is refused, and needs a new summary and a new question. **Never approve a file on your own** — not without asking, not from an earlier answer
   for different files, not because a step is blocked; a rebuilt file (new hash) needs a new question.
   `Api#call` refuses every `/import_uploads` post (from any tool or workspace script) and every JSON post in `onboard.rb`
   checks its source file, so a file whose current hash is not approved never goes in and a rebuild needs a fresh review. Only on ops' explicit word
   for one client: `review: {waived_by, waived_on, reason}` in `onboarding.yml` (files are still dumped; writes print ⚠).
11. **Every onboarding ends with its report, written up with the recon** (ops, 2026-10-27: "Always write the report up with
   the recon"). After the last recon, write `report.md` in [report-template.md](report-template.md)'s shape — Part 2 tells
   the recon's story with worked examples, Appendix B is `out/fund_recon.md` (and `out/portfolio_recon.md`), the Log comes
   from `out/onboard_run.log` (every `next --run` appends to it). Put each recon's marker line in the report, exactly as
   `onboard.rb status` prints it under **Run report** (e.g. `<!-- recon: fund_recon.json <generated_at> · 11497/11497 -->`).
   The "Run report" step stays open until the report is newer than every recon and carries their markers, so a recon re-run
   reopens it. Investor access and go-live come after it — never hand over an onboarding without its report.

## Tools

**First, on every machine and every onboarding: `ruby <tools>/doctor.rb --workspace <workspace>`** — read-only; checks Ruby,
the gems (`roo`, `caxlsx`), the workspace files, the token and the entity, with a fix for each ✖. Fix every ✖ before anything
else. Setup per OS (Windows included) is in [tools/README.md](tools/README.md#machine-setup-windows-linux-macos).

**Paths work on every OS** (BU users run this on Windows): `<tools>` is this skill's `tools/` folder — use the skill's base
directory you were given, never a path from another machine; quote paths (client file names have spaces). **A script you
write in a client workspace's `scripts/` loads the tools with `require "api"` (not `require_relative` with an absolute path)
and runs as `ruby -I "<tools>" scripts/<name>.rb`.**

**Sounds:** every `next --run` ends with a sound on ops' machine — a chime when the step is done, a doorbell when it
needs ops (files to review, the report, investor access), a low alert when it fails or stalls (`tools/sounds/`). `ONBOARDING_SOUND=0` turns
them off; `doctor.rb` shows the player it found.

**Then `tools/onboard.rb status`** — it reads where the onboarding stands and runs the next step (`next --run`),
one at a time, in the order below, stopping at the first failure and never running investor access. It covers the fund
(steps 1–19) and, with `mappings/portfolio.yml`, the portfolio and KPIs (steps 20–31), then the run report (step 32); `--portfolio` follows only the
portfolio track, so a fund waiting on client answers does not hold the portfolio back.
Reusable, client-neutral tools live in [tools/](tools/README.md): `api.rb` (API client + CLI), `merge_mis.rb`, `kpi_dry_run.rb`,
`check_dryrun_cells.rb`, `kpi_upload.rb`, `kpi_recon.rb`, `compare_xlsx.rb`, and for the fund side `fund/read_drawdowns.rb` +
`fund/build_fund_uploads.rb` (driven by the workspace's `mappings/drawdowns.yml`; refuses assumptions without a client question),
`fund/fund_recon.rb` (source vs app, tests ①–⑦ incl. distributions and units; go-live needs it to pass), `fund/apply_units.rb`
(allocate / price / redeem units after import; dry run by default), for the portfolio `portfolio/build_portfolio_uploads.rb`,
`portfolio/build_kpi_mappings.rb` (label check against the MIS; stops on a KPI line with no MIS row) and
`portfolio/portfolio_recon.rb`, and `gate.rb` (the must-have gate). They read settings from the client workspace (`onboarding.yml`,
`state/token`), never from this repo. Transforms that read one client's sheet layout stay in that client's workspace `scripts/`.

## How to report each step to ops (always)

Ops asked for this on Inflexor (2026-10-19): every step is announced, then confirmed, and steps are visibly separated.

1. **Before**: say what you are going to do — the call(s), the records it touches, what "done" will look like.
2. **After**: confirm what was done — HTTP status, ids, counts, and what you read back to prove it.
3. **Separate steps** with a section marker or a small graphic so each step stands out, e.g.

```
━━━━━━━━━━━━━━━━━━━━ STEP 2 / 4 · Upload merged workbook ━━━━━━━━━━━━━━━━━━━━
▶ Plan:  POST /kpi_reports.json (Month 31-Aug-2026) with Butterfly_MIS_Aug26_merged.xlsx as "KPIs"
✔ Done:  HTTP 201, report 2863; reader made 31 period reports, 626 KPIs (read back via /kpis.json)
```

Use the same icons the tools print (`tools/ui.rb`): 📋 plan, ✅ / 🎉 confirmed, 🛑 failure (with what happens next),
💡 what to do, 🐢 stalled. When the tools print plain symbols (▶ ✔ ✖ — see `doctor.rb`'s display line), use those.

4. **Long steps (imports, verify, units): keep ops posted.** Run `onboard.rb next --run` in the background and pass on
   its ⏳ lines in one short line at about each quarter, on any 🐢 / ⚠️ line, and at the end — e.g.
   "⏳ Payments 50% · 2,050 / 4,109 rows · 0 failed · ~8 min left". Never start the same step again while it runs; if the
   watch stops (closed laptop, a stall), running the step again watches the same upload — `api.rb upload` never sends a
   file twice while its first upload is still importing. A job that died still shows "running" for a day; resending
   (`api.rb upload … --resend <id>`) is ops' call after they check the rows it already imported — never Claude's.

## Import order

```
entity settings + sandbox ─▶ fund (POST /funds.json) ─▶ unit settings
  ─▶ investors ─▶ KYCs (+ KYC docs) ─▶ commitment form type ─▶ commitments
  ─▶ calls ─▶ remittances ─▶ remittance payments ─▶ approve calls ─▶ (wait for recount) ─▶ bulk verify
  ─▶ allocate units ─▶ distributions ─▶ distribution payments ─▶ approve ─▶ unit prices ─▶ redeem units
  ─▶ account entries, documents ─▶ reconcile everything (rows, totals, units per folio)
  ─▶ portfolio companies (+ logos) ─▶ portfolio investments ─▶ valuations
  ─▶ KPI mappings ─▶ per MIS: dry run ─▶ check ok cells vs source ─▶ upload ─▶ tie stored KPIs ─▶ approve ─▶ check computed
  ─▶ INVESTOR ACCESS + advisors (last, always approved)
```

**KPIs (proven on Inflexor, 2026-10-19):** every value goes through `KpiWorkbookReader` via the API (`validate_upload` dry run, then
a KPI report with the MIS as its "KPIs" document) — never a scripted `Kpi` import. A dry run that says ok is not proof: check every
ok cell against the source before loading, and tie the stored KPIs again before approving. Details in [learnings.md](learnings.md).

Proven on the Orios trial (details and evidence in [learnings.md](learnings.md)):

- **Fund:** create with `POST /funds.json` — the Fund *import* fails every row until P3 ships.
- **Commitments:** create a `CapitalCommitment` form type with a tag (`POST /form_types.json`) and put the tag in
  "Form Tag"; a fresh entity has none.
- **Calls:** always include an "Exchange Rates" sheet (header only for one currency) until P8 ships; per-investor
  drawdown dates → sequence calls ("Drawdown 1st…"), Call Basis "Upload", remittances with actual amounts.
- **After payments:** approve each call, **wait until the payment import's recount has finished**, then bulk-verify
  (verifying during the recount loses or double-counts totals — P6).
- **Distributions:** one payment per folio per distribution — split a second line into its own distribution
  (Orios: "Redemption 5th - STCG"); correct the header so it equals its payments; approve each.
- **Units:** imports create none. Allocate on calls, set `unit_prices` on redemption distributions, redeem; check every
  folio's balance units against the client's figures.

## The loop for every import type

```
map columns ─▶ leftover columns? ─▶ propose typed custom fields ─▶ approve ─▶ create (FormCustomField import)
  ─▶ transform script ─▶ check against template ─▶ review.rb dump ─▶ OPS REVIEWS + APPROVES THE FILE ─▶ import (ImportUpload)
  ─▶ reconcile
  ─▶ errors? stop, show each failed row with a suggested fix; ops chooses fix+re-import or undo
```

- Every client column ends in exactly one of: **template column**, **custom field**, **dropped on
  purpose**. The mapping file (`onboarding/<client>/mappings/<type>.yml`) records which and why.
- Create typed custom fields *before* the import — see importer-behaviour.md for why the
  importer's own auto-creation is not good enough.
- Keep each import one type, one upload, so per-upload undo stays precise.
- **Write real Excel date cells, never date text** (text is parsed in a locale; `05/04/2021` became 4 May).
- **Emit every template column, even optional ones**, until P8 ships.
- **"Completed" is not success** — check counts and per-row errors on every upload (P1).

## Client workspace

```
onboarding/<client>/
  <client>_client_questions.md   MANDATORY — every assumption as a question for the client (client-questions-template.md)
  report.md        THE run report, in report-template.md's shape: checklist (any session resumes from it),
                   mapping (Part 1), reconciliation proof (Part 2), log. Ops may name another path.
  approvals.yml    waivers ops granted, per import type
  source/*.xlsx    client files, never edited
  mappings/*.yml   approved column/value maps (reusable for the next client on the same system)
  scripts/*        transform scripts Claude wrote
  out/*.xlsx       generated upload files
  out/recon_report.md  output of scripts/recon_report.rb, pasted into the report's Appendix B
  review/          copies of every upload file + REVIEW.md for ops' manual check; approved.yml = file hashes ops approved
```
