# DR Drill Report Redesign — Low-Level Design

> **Audience:** The reviewing developer. Additive to [design.md](design.md); decisions only.

> **Planning phase — no code changes.**

## Contents

- [Module interfaces](#module-interfaces)
- [Model shape](#model-shape)
- [Matching and merging rules](#matching-and-merging-rules)
- [Rendering and escaping](#rendering-and-escaping)
- [Writer changes](#writer-changes)
- [Security detail](#security-detail)
- [Project rules checklist](#project-rules-checklist)
- [Sign-off](#sign-off)

---

## Module interfaces

| Module | Signature | Returns | Raises |
|---|---|---|---|
| `Dr::ReportCatalog.check(label)` | `String` | `[entry, display_name]`; entry from `CHECKS`, or `OTHER` | never |
| `Dr::ReportCatalog.step(title)` | `String` | entry from `STEPS`, or a generic one built from the title | never |
| `Dr::ReportModel.build(**kw)` | keywords below | `Dr::ReportModel::Model` (`Data`) | `ArgumentError` on a missing keyword only |
| `Dr::ReportRender.html(model)` | `Model` | `String` (full HTML document) | template errors only |
| `Dr::ReportRender.markdown(model)` | `Model` | `String` | template errors only |

- `build` keywords: `phases:, scorecard:, evidence:, result:, stack:, region:, env_variant:, branch:, started_at:, finished:, drill:, teardown:, executed_by:`.

**Reviewer checks**
- [ ] No module reads ENV, files or globals except the writer.
- [ ] `check`/`step` never return nil.

## Model shape

| Field | Type | Example |
|---|---|---|
| `passed` | Boolean | `true` |
| `headline` | String | `"Staging recovered in ap-south-2 and verified: 12:04"` / `"Recovery stopped at step 5 · Install the app on both servers"` |
| `subline` | String | `"DR drill · staging (in) → ap-south-2 · 8 Nov 2026, 05:09–05:21 UTC · run by thimmaiah@Inspiron"` |
| `tiles` | `[[value, label]] × 4` | `["44 / 46", "Checks passed · 2 need attention · 0 failed"]` |
| `plain_words` | `[String]` | 3–4 bullets |
| `attention` | `[{status:, name:, hosts:, means:, todo:}]` | ordered: failed step, ❌, ⚠️ |
| `steps` | `[{n:, name:, does:, start:, took:, pct:, ok:}]` | `pct` = duration / total × 100, min 1 |
| `hosts` | `[String]` | `["ip-10-0-1-182", "ip-10-0-2-46"]` |
| `groups` | `[{name:, rows: [{name:, proves:, cells: {host => [status, value]}}]}]` | empty groups omitted |
| `scope`, `evidence`, `glossary` | arrays of pairs | — |

- Status symbols: `:ok`, `:warn`, `:fail`. Icon ⇄ symbol mapping in one place (`ReportModel::STATUS`).

**Reviewer checks**
- [ ] `tiles[2]` = count of ✅ over all cells / all cells. With 23 × 2 and 2 ⚠️ → `44 / 46`.
- [ ] Data-age tile = **maximum** of `([\d.]+)h old` over "Restored data freshness" details (later servers see post-restore writes: 0.4 h then 0.0 h on 2026-11-08); "—" if none.

## Matching and merging rules

| Rule | Decision |
|---|---|
| Label vs detail | Split the scorecard line on the **first** `" — "` |
| Check match | First `CHECKS` entry whose `match` regex matches the label |
| Display name | `entry[:name]`, plus the label's trailing `(…)` part when the entry sets `keep_suffix: true` (IPs, domains) |
| Row key | Display name: same name on two hosts = one row |
| Attention merge | Group by `[display_name, status]`; `hosts` = all hosts with that pair; "both servers" when it equals all hosts |
| Failed step | When `passed` is false: the last phase (the one still open, or last ended) |

**Reviewer checks**
- [ ] Group order is `GROUPS` order; rows within a group are in catalog order, with Other last.
- [ ] Drill-only labels (`Primary backup cron NOT armed (drill)`) and real ones (`Primary backup cron armed`) both have entries.

## Rendering and escaping

| Output | Escaping | Notes |
|---|---|---|
| HTML text | `ERB::Util.html_escape` on every interpolation (`<%= h(x) %>`) | No raw interpolation except the static icon `<symbol>` sprite |
| Markdown | `\|` → `\\|`; newlines → space inside table cells | Help as bullets under tables |
| CSS | Inline `<style>`; `:root` Bootstrap 5.3 values only | No `@media (prefers-color-scheme: dark)` |
| Fonts | System stack | No external URLs at all |

**Reviewer checks**
- [ ] `grep -c 'http' report.html.erb` matches only the SVG `xmlns`, if any.
- [ ] ERB `trim_mode: "-"`; templates live in `lib/tasks/dr_report/` (ignored by the autoloader).

## Writer changes

| Before | After |
|---|---|
| `write_dr_report` builds MD inline (~140 lines) and calls `write_dr_report_html` (~120 lines) + `DR_REPORT_CSS` | Builds the model once; `File.write(md, ReportRender.markdown(m))`; `File.write(html, ReportRender.html(m))` |
| — | Passes `drill:`, `teardown: ENV["TEARDOWN"] == "true"`, `executed_by:` (existing `whoami@hostname` logic) |
| `rescue StandardError` → warning | unchanged |

**Reviewer checks**
- [ ] `write_dr_report_html` and `DR_REPORT_CSS` deleted; no other caller (`grep`).
- [ ] Output file paths unchanged.

## Security detail

| New thing | Policy | Loaded via | Permitted params | Covering scenario |
|---|---|---|---|---|
| `Dr::ReportModel` / `ReportRender` | none (operator rake) | in-memory args | none | X3 (escaping) |

**Reviewer checks**
- [ ] No transcript text reaches HTML unescaped.

## Project rules checklist

| Rule (CLAUDE.md) | Applies? | How |
|---|---|---|
| Large-table hygiene | N/A | No DB access |
| Date formatting (screens: locale; emails: Mon dd, yyyy) | Applies loosely | Not an app screen or email; dates shown as `8 Nov 2026, 05:09 UTC` (strftime machine-to-human is acceptable in an ops artifact, as the current report does) |
| Tenant scoping | N/A | No tenant data |
| MCP ontology | N/A | — |
| IRM cops (`RelationBlankPresent`) | N/A | No relations |
| Inline comments | Applies | Every method body commented |

## Sign-off

| Reviewer | Date | Decision |
|---|---|---|
| | | |
