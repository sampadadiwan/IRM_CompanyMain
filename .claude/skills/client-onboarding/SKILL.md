---
name: client-onboarding
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

## Import order

```
entity settings + sandbox ─▶ fund (POST /funds.json) ─▶ unit settings
  ─▶ investors ─▶ KYCs (+ KYC docs) ─▶ commitment form type ─▶ commitments
  ─▶ calls ─▶ remittances ─▶ remittance payments ─▶ approve calls ─▶ (wait for recount) ─▶ bulk verify
  ─▶ allocate units ─▶ distributions ─▶ distribution payments ─▶ approve ─▶ unit prices ─▶ redeem units
  ─▶ account entries, documents ─▶ reconcile everything (rows, totals, units per folio)
  ─▶ INVESTOR ACCESS + advisors (last, always approved)
```

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
  ─▶ transform script ─▶ check against template ─▶ approve ─▶ import (ImportUpload) ─▶ reconcile
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
  report.md        THE run report, in report-template.md's shape: checklist (any session resumes from it),
                   mapping (Part 1), reconciliation proof (Part 2), log. Ops may name another path.
  approvals.yml    waivers ops granted, per import type
  source/*.xlsx    client files, never edited
  mappings/*.yml   approved column/value maps (reusable for the next client on the same system)
  scripts/*        transform scripts Claude wrote
  out/*.xlsx       generated upload files
  out/recon_report.md  output of scripts/recon_report.rb, pasted into the report's Appendix B
```
