# Data model explorer — notes for whoever changes it next

This folder builds a single interactive HTML page that shows a **prospective client** how CapHive's
data model fits their funds: the schema, custom fields, the calculation engines, the API, why
CapHive should sit upstream of a data lake, and a "will my data fit?" lookup. It was first built
for a US prospect who asked for our schema. It is sales material, so accuracy matters more than
polish: a prospect's data team will check it against the database dump they are given.

## Files

| File | Hand-written or generated | What it is |
|---|---|---|
| `template.html` | hand-written | The whole page: CSS, markup and JS, with `__DATA__` and `__GENERATED__` placeholders. All copy, examples and demos live here. |
| `extract.py` | hand-written | Parses `db/schema.rb`, model files, the MCP ontology (`app/packs/ai/mcp_server/ontology/*.yml`) and `swagger/v1/swagger.yaml` into JSON. |
| `reflect_models.rb` | hand-written | `rails runner` script: runtime reflection (associations incl. concerns, STI, monetized columns). Optional — `extract.py` falls back to static parsing. |
| `domains.py` | hand-written | Groups tables into 11 domains, tiers (core / supporting / internal), plain-English blurbs, and the US-neutral filtering (see below). |
| `build.py` | hand-written | Runs the three above and writes the outputs. |
| `caphive_data_model.html` | **generated** | Standalone page (email it, open it offline). Committed. |
| `caphive_data_dictionary.csv` | **generated** | One row per column, business tables only. Committed. |
| `../../../website_src/_holding/data-model.html` | **generated** | Parked copy in the website source. `rake website:build` reads only `website_src/pages/`, so this is never published. Committed. |
| `caphive_data_model.artifact.html` | **generated** | Body-only variant for the claude.ai Artifact. Gitignored. |

Never edit a generated file by hand; edit `template.html` / the scripts and rebuild.

## Build

```
python3 docs/gtm/data_model_explorer/build.py
```

If `bin/rails` resolves to the wrong Ruby (mise pins 4.0.6; the working gems are in rvm's 3.4.1
`default` gemset), the runner fails on the `devise-api` git gem and the build silently uses the
static parse (fewer associations). Force the right Ruby:

```
RAILS_CMD="$HOME/.rvm/bin/rvm 3.4.1 do bin/rails" python3 docs/gtm/data_model_explorer/build.py
```

Check the output line: `merged runtime reflection for ~208 tables` means reflection worked. Do not
run `bundle install` to "fix" the Ruby mismatch. In a runner script, `eager_load!` does not load
the `app/packs` models; `reflect_models.rb` constantizes each model file for that reason.

The Artifact (private, owner shares it): https://claude.ai/artifact/Ltksbre6Pcrok87sQfbdY3 —
republish `caphive_data_model.artifact.html` to the same URL after a rebuild.

## Where the content lives in `template.html`

Everything a reader sees that isn't schema data is a JS constant or markup in the template:

- `FLEX` — the six "how the model flexes" cards. Counts in them are computed from the data.
- `LANES` / `EDGES` — the core-records diagram on the overview.
- `CF_RECS`, `FTYPES` — the custom-fields demo and field-type list.
- `ENGINES` — the nine engines (reads → does → writes). `demo:` picks an inline demo
  (`demoAlloc`, `demoCost`, `demoRatios`, `demoRag`).
- `RULE_TYPES` — **copied from `FundFormula::TYPES`** (`app/packs/funds/funds/models/fund_formula.rb`).
  Re-sync it when rule types change; the hero stat counts this list.
- `CMP` — the lake-vs-CapHive comparison rows.
- `FIT` — the "will my data fit?" mappings: `[item, kind, [[table, columns/note], …]]`.
- `XP` — the side panel's content: `g:*` glossary terms, `flex0..5` card examples, `eng:*`
  worked examples for engines without a demo, `lake:fix`. Linked from `FIT_X` (fit rows),
  `COL_X`/`colHelp` (the `?` next to columns) and `ROW_X` (the "See an example" on a table).
  Any element with `data-x="<key>"` opens the panel.

## Rules that keep it trustworthy

1. **Verify every claim against the code before writing it.** Most copy came from
   `docs/user_guides/*` and was then checked in the models/services. Things that turned out
   wrong on first draft, as a warning:
   - The allocation engine **hard-deletes** the entries it replaces — the audit trail does not
     keep old ledger figures. Say "the formula edit is audited; `allocation_runs` shows each re-run".
   - `kpis.rag_status` is lowercase (`red`/`amber`/`green`); `kpi_reports.status` has no
     `approved` (values: shell_created, link_sent, draft_saved, submitted, reviewed).
   - API JSON returns money in **major units** (`committed_amount: 25000000.0`) and custom fields
     under the key **`custom_fields`**, not `json_fields`.
   - A portfolio company is an `investors` row with `category` "Portfolio Company"; one record
     cannot be both an LP and a company.
2. **Examples are illustrative but column names and stored values are real.** Every panel ends
   with "Illustrative values. Column names are exact." Keep it that way. Check arithmetic — one
   running example is used everywhere (Meridian Growth Fund II, USD, tracking currency GBP; LP
   Halcyon Pension Trust, folio F-0142, folio currency EUR; commitments 25m / 10m / 5m of a
   120m fund; classes A 2.0% and B 1.5%). Changing one number usually means changing several panels.
3. **US-neutral by request.** The audience is a US client: no SEBI, PAN, Aadhaar, IFSC, CRISIL,
   INR, demat, Digio, CKYC/KRA, HUF, lakh/crore, Indian cities. This is enforced in `domains.py`:
   - `REGION_TABLES` / `REGION_COLUMNS` — India-only tables and columns are omitted.
   - `ALIAS` — `PAN` is shown as `tax_id`, `ifsc_code` as `bank_routing_code`. The page footer
     states the real names so the explorer still matches a database dump. Keep that footnote.
   - `REGION_DEFAULTS`, `EXAMPLES` and the INR→USD rewrite — neutralise column defaults and the
     Swagger example values (the spec was recorded from an India demo; `swagger.yaml` itself is
     left untouched).
   After any change, grep the outputs:
   `grep -i -E '\b(sebi|aadhaa?r|crisil|gstin|inr|india|demat|digio|ckyc|huf|cheque|lakh|crore)\b|₹' caphive_data_model.html caphive_data_dictionary.csv`
   should print nothing (the footer's one `PAN` mention is intentional). A new schema column with
   an India-specific name needs adding to `REGION_COLUMNS` or `ALIAS`.
4. **Not for the public website.** The parked copy stays in `website_src/_holding/`, never
   `website_src/pages/`.

## Design decisions (and why)

- **Annual-report look, light-only.** Navy masthead and a ledger-ruled navy hero band, white
  ruled body, split section headers under a heavy rule, ruled grids instead of floating cards,
  square tags, underlined tab bars, sentence-case labels. The owner asked for white, business-like
  and "not like generated HTML", so avoid: serif display headings, mono uppercase eyebrows,
  rounded pill chips, translucent blur headers, bright accents, and orange in particular (the
  CapHive brand orange was tried and removed).
- **Colour:** navy `--band` + corporate blue `--accent`/`--accent-ink` on white, lighter
  `--band-accent` on navy. Red/amber/green are reserved for status (RAG, HTTP verbs).
  Domain colours (`--d-*`) only mark which domain a table belongs to.
- **Type:** Libre Franklin (headings), Source Sans 3 (body), IBM Plex Mono (table/column names,
  code, numbers). Chosen to read as US financial/corporate.
- **Width:** content up to 1760px; side panel `clamp(560px, 46vw, 880px)`, full-screen on phones.
  Content-heavy detail goes in the side panel, not inline, to keep pages uncrowded.

## Checking a change

1. `python3 -m py_compile docs/gtm/data_model_explorer/*.py` and
   `bundle exec rubocop docs/gtm/data_model_explorer/reflect_models.rb` (under rvm 3.4.1).
2. Rebuild, then render headless (there is no Node here; Chrome is installed):
   `google-chrome --headless=new --no-sandbox --virtual-time-budget=4000 --window-size=1600,1400 --screenshot=out.png "file://…/caphive_data_model.html#schema"`.
   Check desktop and ~420px wide. To screenshot the side panel, render a scratch copy with a
   `setTimeout(()=>document.querySelector('[data-x="flex2"]').click(),400)` appended — never
   leave that in the template.
3. Known layout traps: a scroll pane that is `display:grid` shrinks its children (the schema
   detail pane uses flex + `flex-shrink:0` for this reason); a grid of six cards needs fixed
   column counts (`#flex`) or wide screens leave a ragged last row; in zsh, `for v in "a b c"`
   with `set -- $v` does not split words.
4. Run the India-terms grep above.
