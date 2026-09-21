# Allocation Run Checks (Pre-run and Post-run)

**Status:** Built (2026-09-13): rule types, engine steps, report findings, and helpers P1–P7 and
Q1–Q3. The cash reconciliation check (post-run example 4) is waiting on a worked example; see
[Open items](#open-items). Code: `app/packs/allocation_engine/account_entry_allocation/`
(`run_checks.rb`, `check_context.rb`, `check_helpers.rb`, `check_failed.rb`, `check_warning.rb`),
`RunFormulas#run_pre_checks` / `#run_post_checks` / `#persist_check_results`,
`AllocationRunReportBuild#check_run_checks`, `AllocationRunReadiness`. Tests:
`features/fund/allocation_run_checks.feature`.

## Problem

An allocation run has no built-in way to confirm what it assumes before it starts ("every uploaded
expense sits under a known expense head", "FX rates are loaded"). It also can't confirm afterwards
that its results are sound ("everything uploaded at fund level was allocated to the folios"). Today
a broken assumption shows up as a wrong NAV, usually after statements have gone out.

The [Allocation Run Checker](allocation_run_checker_requirements.md) covers generic checks that apply to every
fund. This feature is for checks **configured per fund**, set up in the same formula list as that
fund's allocation formulas.

## What we are building

1. Two new `FundFormula` rule types: **`PreRunCheck`** and **`PostRunCheck`**. A check formula
   creates no account entries. It passes, warns or fails.
2. A library of **check helpers**, so a check is normally a single line of settings rather than
   hand-written queries:

```ruby
# PreRunCheck "Non Deal Expense heads"
allowed_entry_names("Non Deal Expense", ["Management Fees", "Fund Administrative Costs", "Audit Fees", ...])

# PostRunCheck "Uploaded entries tie to folios"
fund_entries_tie_to_folios
```

Plain Ruby still works for a one-off check (`check!(condition, "message")`, `raise`, or returning
`false`).

## Decisions

| # | Decision |
|---|----------|
| D1 | Checks are **fund-level**: each one is evaluated once per run, not once per folio. |
| D2 | A check **fails** if it raises or returns `false`. It **warns** if it raises `CheckWarning` or a helper called with `severity: :warning` finds something. Raising `SkipRule` marks it **skipped**. Any other return value (including `nil`) is a **pass**. |
| D3 | Pre-run checks run **before anything is deleted or loaded**, against the primary database. |
| D4 | Every check of a kind runs, even after one fails, so all problems are collected. **If any pre-run check fails, the run stops.** Warnings never stop a run. |
| D5 | **If any post-run check fails, the run stops**: no fund ratios, no investor statements (SOA), and a group run does not continue to its next template. |
| D6 | On a post-run failure, the account entries the run already wrote **stay in the ledger**. The next run for the period deletes them as usual. |
| D7 | Check results are stored on the run's **`AllocationRunReport`**. That row is reused if it exists and created if it doesn't. Rebuilding the report **never erases** them. |
| D8 | **Each check is its own finding** on the report's existing "Did the run happen correctly?" tab, with its own table of offending rows. |
| D9 | Results are stored and the report is **built automatically when any check failed or warned**. A run whose checks all passed stores nothing. |
| D10 | "Uploaded" means **`generated: false` with `reporting_date` in the run's period**, both fund-level and folio-level. Portfolio investment checks look at **investments dated in the period**. |
| D11 | Entry names and entry types are matched **exactly**: same case, same spelling. |
| D12 | Deal entries must be mapped to a **Portfolio Investment**. A portfolio company as parent does not count. |
| D13 | FX rates and valuations must exist **within N days before the end date**. N is a parameter of the check. |
| D14 | Amount comparisons use an **absolute tolerance of 1.00 in the fund's currency** by default, overridable per check with `tolerance:`. |
| D15 | FX rate and valuation checks **reuse the existing validation rule logic** in `AllocationRunRuleContextProvider`. The logic is extracted, not copied, and the existing entity-level rules stay as they are. |

### Why a tolerance of 1.00 (D14)

A fund-level amount is split across every folio, and each folio's share is rounded. With N folios
the shares can drift from the total by up to about N × 0.005, so a fund with 2,000 folios can be
off by up to 10.00 through rounding alone. The report checker's 0.005 epsilon would fail a healthy
run. 1.00 is immaterial at fund level and still catches a genuinely unallocated entry. A fund with
a very large folio count or a low-denomination currency can pass a larger `tolerance:`.

## The checks

These are the checks the business has asked for, and how each is set up.

### Pre-run

| # | Check | Formula | Default result |
|---|-------|---------|----------------|
| P1 | Every uploaded "Non Deal Expense" entry has a known expense head | `allowed_entry_names("Non Deal Expense", [...23 names...])` | Fail |
| P2 | Every uploaded "Non Deal Income" entry has a known income head | `allowed_entry_names("Non Deal Income", ["Income from Temporary Investments", "Miscelleneous Income"])` | Fail |
| P3 | Every uploaded entry has the UDR and expense-head custom fields | `required_custom_fields(:account_entries, ["Fund Level UDR Code", "Domestic UDR Code", "Offshore UDR Code", "Exchange Rate", "Expense Head"])` | Fail |
| P4 | Every portfolio investment dated in the period has the UDR custom fields | `required_custom_fields(:portfolio_investments, ["Fund Level UDR Code", "Domestic UDR Code", "Offshore UDR Code", "Exchange Rate"])` | Fail |
| P5 | Every uploaded deal entry is mapped to a portfolio investment | `entries_mapped_to_portfolio_investment(["Deal Expense", "Deal Expense Capitalized", "Deal income"])` | Fail |
| P6 | FX rates are loaded up to the end date | `fx_rates_present(within_days: 5)` | Fail |
| P7 | Portfolio valuations are up to date | `valuations_present(within_days: 30, severity: :warning)` | Warn |

### Post-run

| # | Check | Formula | Default result |
|---|-------|---------|----------------|
| Q1 | Every entry uploaded at fund level was allocated | `fund_entries_allocated` | Fail |
| Q2 | Uploaded fund-level totals equal what was allocated to the folios | `fund_entries_tie_to_folios(tolerance: 1.0)` | Fail |
| Q3 | Portfolio investment amounts equal what was allocated to the folios | `portfolio_allocations_tie("Investment Amount" => :amount_cents, "Cost Of Sold" => :cost_of_sold_cents)` | Fail |
| Q4 | Cash reconciles: opening + inflows − outflows = closing | `cash_reconciles(...)`, **pending definition** | Fail |

Every name in these lists is the business's and is matched exactly (D11), including
"Miscelleneous Income" and "Deal income". If the uploads use a different spelling, the check fails
until one side is corrected.

## Check helpers

Helpers live in one module (`AllocationChecks::Helpers`) that is available only inside check
formulas.

**Rules every helper follows:**

- **SQL only.** Helpers aggregate in SQL and never load `account_entries` rows, and they never read
  the wide `json_fields`, `notes` or `explanation` columns in bulk (see CLAUDE.md, "Large-table
  query hygiene"). `required_custom_fields` is the one helper that must read `json_fields`. It
  plucks only `id` plus that column, in batches, over the period's uploaded entries.
- **Rows, not a sentence.** A helper that finds problems raises `CheckFailed` (or `CheckWarning`
  when called with `severity: :warning`). The error carries a one-line summary, a table of
  offending rows (at most `AllocationRunReport::MAX_ROWS_PER_FINDING`, plus a count of the rest),
  and a filter per row that links to the account entries screen, like the report's existing
  findings.
- **Messages are built in Ruby,** not in the formula text, so the eval blocklist never sees them
  (see [FAQ](#faq)).
- **Every helper accepts `severity: :fail | :warning`**, with `:fail` as the default.
- **One helper per check formula.** A formula that calls two helpers stops at the first one that
  finds a problem.

### `allowed_entry_names(entry_type, names)`

Uploaded entries (D10) for this fund with `entry_type == entry_type` whose `name` is not in `names`.
**Rows:** Entry name, Entries, Total amount.

The name comparison happens in Ruby, over `distinct.pluck(:name)`, which is a handful of values.
MySQL's default collation is case-insensitive, so a SQL `NOT IN` would quietly accept "audit fees"
for "Audit Fees" and break D11. The same applies to entry type matching in every helper: select by
entry type in SQL, then re-check the exact value in Ruby.

### `required_custom_fields(target, labels, fund_level_only: false, entry_types: nil)`

- **`:account_entries`:** every uploaded entry (D10), of any entry type, fund-level and folio-level.
- **`:portfolio_investments`:** the fund's portfolio investments with `investment_date` in the
  period, proforma included.

Each label is resolved to its `json_fields` key through the entity's form type for that model
(`FormCustomField` matched on label, ignoring case), which is how imports resolve it. If no custom
field has that label, the fallback is `FormCustomField.to_name(label)`, e.g. "Fund Level UDR Code"
→ `fund_level_udr_code`. A key that is missing or has a blank value counts as missing.

**Rows:** Record (entry name and date, or investment), Folio (for entries), Missing fields.

**Narrowing the check (account entries only).** Two options limit which uploads are checked:

- **`fund_level_only: true`:** only fund-level uploads. These are the entries the allocation formulas
  read custom fields from. For example, fund 319's allocation formulas read
  `fund_account_entry.json_fields['fund_level_udr_code']` to pick each folio's share, and a missing
  code crashed run 3303. Folio-level uploads, such as per-folio "Taxes Paid"/"TDS" or folio-level
  Fund Administrative Costs, are never allocated, so they don't need the codes.
- **`entry_types: [...]`:** only uploads of these entry types, matched exactly.

On fund 319's August 2026 data, the check without options fails 46 of 101 uploads, and every one of
the 46 is a folio-level upload. With `fund_level_only: true` it checks the 55 fund-level uploads, and
all of them pass.

### `entries_mapped_to_portfolio_investment(entry_types)`

Uploaded entries (D10) whose `entry_type` is in `entry_types`, and where any of these is true:

- `parent_type` is not `PortfolioInvestment`
- `parent_id` is blank
- the parent investment does not belong to this fund

**Rows:** Entry name, Entry type, Reporting date, Amount, Current mapping.

### `fx_rates_present(within_days: 5)` or `fx_rates_present(within_months: 3)`

The same currency pairs and window as the `allocation_run_fx_rates_exist` rule:

- each instrument's currency → fund currency
- each feeder fund's currency → fund currency
- fund currency → tracking currency

**Rows:** From, To, Needed by.

### `valuations_present(within_days: 30)` or `valuations_present(within_months: 3)`

Both FX rates and valuations take the window either in days or in calendar months (3 months before
31 Aug is 31 May).

The same logic as the `allocation_run_valuation_exists` rule: every portfolio company in which the
fund holds a position at the end date needs a valuation dated within the window.
**Rows:** Portfolio company, Latest valuation date.

### How post-run checks recognise an allocation

The obvious test ("the folio entry's parent is the uploaded entry") does not work. `AllocateEntry`
builds each folio entry as a **copy** of the fund-level entry (`fund_account_entry.dup`), so the
copy inherits that entry's own `parent_id`/`parent_type`, and `CreateAccountEntry` only sets the
parent when there is none. A deal expense already mapped to a portfolio investment therefore
allocates into folio entries whose parent is that investment, not the uploaded entry. Grouped
allocation adds a second problem: it links every folio entry to only the first entry of a
same-name group.

So Q1 and Q2 match the way the engine picks entries up:

- An `AllocateAccountEntry*-Name` formula (including the legacy `AllocateAccountEntry`) takes every
  fund-level entry in the period **named** after it. An `-EntryType` formula takes every one of its
  **entry type**.
- Every folio entry it writes carries that formula's `fund_formula_id` and the fund-level entry's
  name.
- A formula "ran" when it wrote at least one non-cumulative folio entry in this run. That is read
  from the entries, so whether the formula is enabled or in scope today doesn't matter.

### `fund_entries_allocated(except: [])`

Uploaded **fund-level** entries (D10, `capital_commitment_id` blank), grouped by exact name and
entry type. A group counts as allocated when a formula that ran selects it by name or by entry type.
Names in `except:` are left out, for entries a fund never allocates on purpose.

**Rows:** Entry name, Entry type, Entries, Total amount.

### `fund_entries_tie_to_folios(tolerance: 1.0, except: [])`

For each entry allocation formula that ran, and for each name it picked up:

- **Fund level:** the sum of fund-level entries in the period matching the formula's selector that
  **this run did not write**. Both uploaded and generated entries count, because the formula
  allocated whatever was there. This run's own entries, such as its fund-level rollups, are
  excluded.
- **Allocated:** the sum of this run's non-cumulative folio entries from that formula with **that
  exact name**. The "Quarterly …", "YTD …" and "Since Inception …" entries added by
  `generate_ytd_qtly` carry prefixed names, so they never count.

A difference above the tolerance is a failure. A name nothing allocated is left to
`fund_entries_allocated`, so one problem isn't reported twice.

**Rows:** Formula, Entry name, Fund level, Allocated to folios, Difference.

**Limit:** the comparison is per formula, so an entry allocated in full by **two** formulas passes
both comparisons.

### `portfolio_allocations_tie(mapping, tolerance: 1.0)`

`mapping` pairs an `AllocatePortfolioInvestment*` formula name with the `PortfolioInvestment`
amount column that formula allocates. Only `*_cents` amount columns are accepted; anything else is
an error.

For each pair, every portfolio investment's column value is compared with the sum of entries that
meet all of these:

- written by this run from that formula
- `parent_type: "PortfolioInvestment"` and `parent_id` = that investment
- `capital_commitment_id` present

The set of investments comes from the **same scope the engine used for that formula**:

- master fund or own fund
- proforma or not
- `between_start_and_end_dates` and `where` settings in the formula's `meta_data`

That scope is taken out of `AllocatePortfolioInvestments` into a method both call, so the check
can't compare against investments the formula was never meant to allocate. Entries are found by
`allocation_run_id`, not by date, because `meta_data` can set `reporting_date` to the investment
date.

The mapping may be written with or without braces. Without braces Ruby passes
`"Name" => :column` as keyword arguments, so the helper accepts both forms. A name that doesn't
match exactly one of the fund's portfolio allocation formulas fails the check, rather than silently
comparing nothing.

**Rows:** Formula, Portfolio investment, Amount, Investment, Allocated to folios, Difference.

**Limit:** this assumes an investment's amount columns are in the same currency as the entries
allocated from it (the fund's). It has not been verified for instruments held in another currency.

### `folio_shares_total(field_key, tolerance: 0.01)`

Allocation formulas that split by a code do three things:
- read a code such as "UDR - 2" from the fund-level entry or portfolio investment they allocate,
  from the json field `field_key`
- turn the code into a folio field name ("udr_2")
- multiply by that folio's percentage

A code that no folio has a field for, or whose percentages don't add up to 100, allocates part of
the amount to nobody, with no error. This check catches it before the run deletes anything.

- **Codes:** from this period's fund-level uploads, and every portfolio investment held by the end
  date (proforma included).
- **Folios:** the commitments an allocation run for the end date includes
  (`commitment_date <= end_date`).
- **Passes** when each code's percentages total 100 within `tolerance` (percentage points).

**Rows:** Code, Folio field, Folios with a value, Total %.

### `unit_settings_present(keys)`

Every unit type in use by the fund's commitments has a unit setting with a value for each key.
Unit types are matched to settings ignoring case, as `fund_unit_setting` does in MySQL. A key can be
a unit setting column (such as `carry`) or a json field (such as `catch_up`). A waterfall formula
that reads `fund_unit_setting.json_fields['catch_up']` for a unit type with no setting stops the
run part-way with `undefined method 'json_fields' for nil`; fund 342's run 1854 did exactly that.

**Rows:** Unit type, Folios, Missing ("no unit setting" or the missing keys).

### `since_inception_matches_history(names, tolerance: 1.0)`

Compares each folio's stored `Since Inception <name>` entry on the end date with the sum of all its
non-cumulative `<name>` entries up to that date. Names are matched exactly.

- **Why it exists:** under incremental allocation a run stores a total and the next run carries it
  forward instead of summing history, so a wrong carried total shows up here. On a production copy
  it replaces the snapshot diff used in development.
- **Where it runs:** normally as a post-run check. As a pre-run check it tests the previous run's
  totals.
- **Folios left out:** a folio with no stored entry for a name (for example one skipped by the
  formula) is not compared.

**Rows:** Entry, Folio, Stored, Full history, Difference.

### Helper catalogue

`CheckHelpers::HELPER_CATALOGUE` lists every helper with its signature, where it can run and what
it checks. The AI check suggester (fund formulas page, Actions > Suggest run checks) sends that list
as the only vocabulary it may use. When adding a helper, add it to the catalogue and to this section.

### `cash_reconciles(...)`: pending definition

The equation is opening cash + portfolio sales − exit costs − other costs − portfolio buys −
non-deal expenses − deal expenses + drawdowns − distributions = closing cash. To build it we need
to know where the opening and closing balances come from, what each term maps to (entry types,
portfolio investment buys and sells, remittances collected or called, distribution payments), the
sign conventions, and the dates each term uses. See [Open items](#open-items).

## How it works

### Rule types and formula form

- Add `PreRunCheck` and `PostRunCheck` to `FundFormula::TYPES`.
- For these types:
  - `entry_type` is not required: relax the presence validation.
  - `generate_ytd_qtly` and `roll_up` are rejected.
  - `formula_kosher?` and `formula_syntax_valid?` apply as they do today.
- They use `sequence`, `enabled`, `rule_for` and `tag_list` like any other formula, so a run's
  `rule_for`/tag filter picks up the matching checks.
- The formula form hides the entry type for these types and shows an explanation row listing the
  helpers.
- The standard checks above can be saved as template formulas (`is_template`) and copied into each
  fund, then adjusted per fund.

### Excluded from everything that expects entries

Check formulas are filtered out of:

- `RunFormulas#get_formulas`
- `RunFormulas#configure_commitment_cache_dependencies`
- `RunFormulas#delete_existing_primary_entries`
- `FundFormulaDependencyGraph`

### Evaluation

- A check is evaluated inside a small context object that exposes `@fund`, `@start_date`,
  `@end_date`, `@allocation_run`, `check!` and the helpers. It does not run inside an allocation
  operation's binding, so commitment-level variables and other formulas' outputs are not available.
- The source is guarded with `ApplicationRecord.safe_eval!`, like every formula.
- It does **not** go through `AllocationBaseOperation#safe_eval`'s rescue. That rescue rewrites
  every exception into "Error in eval …", which would bury the check's own message.
- **Messages:**
  - `CheckFailed`/`CheckWarning` keep the summary and rows as the helper built them.
  - Another `RuntimeError` keeps its message.
  - Anything else is stored as `"#{e.class}: #{e.message}"`, so a typo reads as a broken check.
  - A `false` return is stored as "Check returned false".
  - Summaries are truncated to 500 characters.

### Where the checks run in `RunFormulas`

```
setup_start_time
run_pre_checks            <- new: fails the operation if any pre-run check failed
delete_existing_entries
load_sqlite_db
get_commitments
run_formulas
run_post_checks           <- new: fails the operation if any post-run check failed
persist_check_results     <- new: success AND failure track (like cleanup_sqlite)
generate_fund_ratios
generate_soa
cleanup_sqlite            (success and failure track)
display_generated_links
```

- **Nothing to check:** neither check step does anything when `run_allocations` is false (a
  statements-only run) or when no enabled check is in scope.
- **Where results go:** both steps put their results in `ctx[:check_results]`; neither writes the
  report.
- **Post-run checks read the primary database:** `run_post_checks` runs after the final migration
  to the primary database and after parent relinking, outside the scratch SQLite block.
- **`persist_check_results` runs on both tracks.** It sits on both tracks so it runs however the run
  ends: pre-run failure, formula error, post-run failure or success. It writes to the report only
  when a check failed or warned (D9). Writing at the end also means a run that merely warned
  doesn't queue the report build while its own entries are still being written.

### When a check fails

1. **Status.** `allocation_run.status` becomes `Pre-run checks failed (N): <name>: <summary>; …` or
   `Post-run checks failed (N): …`, truncated to 2000 characters.
2. **Report.** `persist_check_results` stores the results and queues the report build.
3. **Notification.** The user gets a `:danger` notification that links to the report.
4. **Everything else stops.**
   - `Engine#call` keeps the status, because it only fills in a blank one.
   - `AllocationGroupRunJob` stops the group, because the status isn't `Success`.
   - Neither needs changes.

Warnings leave the status alone: a run that only warned finishes as `Success`, and its
notification says "finished with N check warnings" with a link to the report.

### Storing results on `AllocationRunReport`

`persist_check_results` calls `AllocationRunReport.find_or_initialize_by(allocation_run:)`, merges
`run_checks` into its `json_fields`, sets `status: "Pending"`, and queues `AllocationRunReportJob`:

```json
{
  "run_checks": [
    { "kind": "pre", "formula_id": 12, "sequence": 1, "name": "Non Deal Expense heads",
      "result": "fail", "summary": "2 entry names are not recognised expense heads",
      "columns": ["Entry name", "Entries", "Total amount"],
      "rows": [["Audit fee", 3, "1,200.00"], ["Bank charge", 1, "15.00"]],
      "filters": [[...], [...]], "truncated": 0, "duration_ms": 40 }
  ]
}
```

- Every check that ran is stored (pass, warn, fail and skipped), in sequence order, pre-run checks
  first.
- `user_id` is the run's user. A run without a user falls back to an entity admin, the way
  `allocation_run_checker.rake#admin_for` does.
- **Reuse requires three changes.** Today three places wipe `json_fields` on every rebuild, which
  would erase results that can't be recomputed (they describe the data at the moment the run
  happened):

| Where | Today | Change |
|-------|-------|--------|
| `AllocationRunReportsController#create` | `json_fields: {}` | keep `run_checks`, clear the rest |
| `lib/tasks/allocation_run_checker.rake` | `json_fields: {}` | same |
| `AllocationRunReportBuild#persist` | replaces `json_fields` | merge `findings` and `duration_ms` into it |

### Report findings

A new step, `check_run_checks`, runs after `check_period_continuity` (1.4), so findings read in code
order. For each kind that has stored results it adds one finding per check:

- **Codes:** `1.5.<n>` for pre-run checks and `1.6.<n>` for post-run checks, where n is the
  position in sequence order.
- **Group:** `Finding` derives the group from the code's leading "1", so these land on the existing
  "Did the run happen correctly?" tab. No new tab and no view changes.
- **Contents:** the title is the formula name, the summary is the check's summary, and
  columns/rows/filters/truncated come straight from the stored result.
- **Severity:** pass → `pass`, warn → `warn`, fail → `fail`, skipped → `skipped`. The report's
  overall Pass/Warn/Fail therefore already takes check results into account.

A kind with nothing stored gets a single summary finding (`1.5` or `1.6`). The engine stores results
whenever a check fails or warns, and a failure stops the run, so the run's status is enough to
conclude something:

| Situation | Finding |
|-----------|---------|
| No enabled check of that kind, created before the run and matching the run's `rule_for`/tags | **skipped**: "no pre-run checks in scope" |
| Statements-only run, or run still `Pending`/blank | **skipped** |
| Pre-run kind, and the run got past its pre-run checks (any other status) | **pass**: "so none of them failed" |
| Post-run kind, run status `Success` | **pass** |
| Post-run kind, run stopped before its post-run checks | **skipped** |

No "recorded from" date is needed. Only check formulas created before the run count, so a run older
than this feature correctly finds no checks in scope.

- **Pre-run checks failed:** the run produced nothing, so `setup` sets `ctx[:ledger_complete] =
  false`. Checks 1.2, 1.3 and section 2 then sit it out with "the run stopped before computing
  anything", instead of listing every formula as silent.
- **Post-run checks failed:** the ledger is complete (D6), so every other check runs.

## Tests (Cucumber)

`features/fund/allocation_run_checks.feature` (steps in
`features/step_definitions/allocation_run_checks_steps.rb`; it reuses the allocation run checker's
steps and cleanup hook):

- **Formulas:** checks need no entry type; `generate_ytd_qtly`/`roll_up` are rejected; entry
  formulas still need an entry type; checks are excluded from the dependency graph and from
  `RunFormulas#get_formulas`.
- **Outcomes:** pass, `nil`, `false`, a raised message, `check!`, `CheckWarning`, `SkipRule`, and a
  `NoMethodError` shown with its class name. Every check still runs after one fails.
- **Pre-run helpers:** `allowed_entry_names` is exact (a lowercase variant is flagged, a differently
  cased entry type is ignored) and skips generated and out-of-period entries, and it can warn;
  `required_custom_fields`; `entries_mapped_to_portfolio_investment` (a portfolio company parent or
  no parent fails); `fx_rates_present` fails and then passes once the rate is loaded;
  `valuations_present` warns.
- **Post-run helpers:** `fund_entries_allocated` (with `except:`); `fund_entries_tie_to_folios`
  passes within tolerance while ignoring the run's rollup and the Quarterly children, and fails an
  under-allocated entry; `portfolio_allocations_tie` passes a full allocation, fails a short one,
  and fails an unknown formula name. Post-run helpers refuse to run without an allocation run.
- **Report:** stored results become `1.5.n` findings, skip the ledger checks after a pre-run
  failure, and survive a re-check. Unstored checks show as pass; a fund with no checks shows them as
  skipped.
- **End to end (real engine):**
  - A failed pre-run check leaves the previous run's entries untouched, sets the status and builds
    the report.
  - A failed post-run check fails the run, keeps its allocated entries and reports the unallocated
    and under-allocated names.
  - A run whose checks only warned finishes as Success and still gets a report.
  - A run whose checks all pass gets no report.

**Not covered:** an allocation run group stopping at a failed check. `AllocationGroupRunJob` was not
changed; it already stops on any status other than Success.

## Known limits

- **A formula that raises** during `run_formulas` escapes the whole operation (as it did before
  this feature), so no failure-track step runs. Warnings from that run's pre-run checks aren't
  stored; the run's status still names the formula error.
- **Exact matching cuts both ways.** An entry typed "non deal expense" (lowercase) isn't looked at
  by a check for "Non Deal Expense" at all.
- **Report links:** rows about portfolio investments, FX rates and valuations have no drill-down
  link, because the report's links only open the account entries screen.

## Out of scope

- Folio-level checks (evaluated once per commitment by the engine).
- Rolling back entries when a post-run check fails (D6).
- Storing results when every check passes.
- Allowing a formula to mention a word on the eval blocklist (see FAQ).
- Changing the existing entity-level validation rules for FX rates and valuations.

## Open items

- **Q4 cash reconciliation:** waiting on a worked example from a real fund: balance sources, what
  each term maps to, signs, dates.
- **Existing bug, not part of this change:** `RunFormulas#relink_account_entry_parents` joins on
  `parent.entry_type = 'AccountEntry'`. That column holds values like "Expense", so it almost
  certainly should be `parent.parent_type`, and the relink probably never matches.

## FAQ

**What is the difference between a check and a normal fund formula?**
A normal formula computes an amount and writes an account entry. A check writes nothing. It looks
at the fund's data and passes, warns or fails. Checks sit in the same formula list, with the same
sequence, enabled flag, rule-for and tags, so the people who maintain a fund's formulas maintain
its checks too.

**How is this different from the Allocation Run Checker's report?**
The checker's findings (1.1–2.3) are the same for every fund and are worked out from the ledger
whenever someone presses Check. Pre-run and post-run checks are configured per fund, run during the
allocation, and can stop it. Their results are shown in the same report, as findings 1.5.n and
1.6.n on the "Did the run happen correctly?" tab, so a reviewer has one place to look.

**How is this different from the validation rules for FX rates and valuations?**
Those rules apply to a whole entity and are checked when someone submits an allocation: a blocker
stops the submission and a warning asks for confirmation. `fx_rates_present` and
`valuations_present` use the same logic, but they're set per fund, run as part of the run itself
(including runs started by an allocation run group), and their results land in the report. With
both enabled, a missing rate shows up at submission and again in the run. The rules are unchanged.

**Why do I write `allowed_entry_names(...)` instead of the query itself?**
The helpers get the hard parts right once: grouped allocation, the Quarterly/YTD child entries, the
rounding tolerance, links to the offending entries, and not loading millions of account entries
into memory. A hand-written version of the "uploaded totals tie to folios" check is about 25 lines
and easy to get subtly wrong, and copied into every fund it would drift. Plain Ruby is still
available for anything the helpers don't cover.

**How do I make a hand-written check fail or warn?**
Raise with a message that says what is wrong (`raise "3 commitments have no unit type"`), use
`check!(condition, "message")`, or make the formula's last expression evaluate to `false`. To warn
without stopping the run, raise `CheckWarning`. Returning `nil` is a pass, so a formula ending in
something like `puts` doesn't fail by accident.

**What happens when a pre-run check fails?**
Every pre-run check still runs, so you see every problem at once rather than one per attempt. Then
the run stops before anything is deleted, so the previous run's entries for the period are exactly
as they were. The run's status lists the failed checks, you get a notification linking to the
report, and the report shows each failed check with the entries or investments behind it.

**Why do pre-run checks run before the old entries are deleted?**
Deleting the period's entries is the first thing a run does. If checks ran after it, a failed check
would stop a run that had already wiped the period. It is also why the helpers only look at
**uploaded** entries: the previous run's generated entries are still in the ledger at that moment
and would otherwise be checked too.

**What counts as an "uploaded" entry?**
An entry the engine didn't generate (`generated` is false), dated inside the run's period, at fund
level or folio level. Entries from earlier periods aren't checked: they were checked when their own
period ran. Portfolio investment checks look only at investments dated inside the period.

**What happens when a post-run check fails?**
The run stops. Every post-run check still runs first, so all failures are listed. The run is marked
failed, fund ratios and investor statements are not generated, and in a group run the next template
doesn't start. That matters most for a master fund feeding feeder funds, since a feeder would
otherwise allocate from numbers a check has just flagged. The report is built automatically.

**Why are the entries kept when a post-run check fails?**
You need them to understand the failure: the report's arithmetic checks run over them, and each
failed check's rows link straight to them. They don't linger: the next run for the same period
deletes them first. The run is marked failed, so it shouldn't be locked.

**What happens when a check only warns?**
The run carries on and finishes as `Success`. When it ends, the check results are stored and the
report is built, so its badge reads Warn rather than "Not checked", and the notification says how
many checks warned. The portfolio valuations check warns by default, because a stale valuation
doesn't make the allocation wrong, only out of date.

**Why does "Miscelleneous Income" have to be spelled that way?**
Names and entry types are matched exactly, because that is how the allocation formulas themselves
match them: an entry named "Miscellaneous Income" wouldn't be picked up by a formula looking for
"Miscelleneous Income". If the check listed a different spelling from the formulas, it would pass
entries the allocation then skips. Fix the spelling in the uploads or in both the formulas and the
check.

**Why does a deal entry mapped to the portfolio company fail the check?**
Deal entries are shown in the investor statement against a specific portfolio investment. An entry
mapped only to the company can't be placed against an investment, so the check requires the
investment itself.

**The folios received my uploaded entry, so why does the allocation check say it wasn't allocated?**
The check decides "allocated" the way the engine does. An `AllocateAccountEntry…-Name` formula
allocates entries whose name equals the formula's name exactly, and an `…-EntryType` formula
allocates entries whose entry type equals it. If the folios got the amount through some other kind
of formula (for example a `GenerateAccountEntry` formula that reads the uploaded entry), no
allocation formula picked the entry up, and the check says so. Either allocate it with an
`AllocateAccountEntry` formula, or list the name in `except:` if it is meant to reach the folios
another way. The check doesn't follow the folio entries' parent link: a folio entry is a copy of
the uploaded entry and keeps that entry's own parent, so a deal expense mapped to a portfolio
investment would never point back at the uploaded entry.

**Why does the "uploaded totals tie to folios" check allow a difference of 1.00?**
Each folio's share of a fund-level amount is rounded, so with thousands of folios the shares can
legitimately differ from the total by a few units in total. 1.00 is immaterial at fund level but
still catches a real problem, such as an entry allocated to only some folios. A fund with an
unusually large number of folios can pass a larger `tolerance:`.

**Can a check see the values other formulas computed, like `@setup_fees`?**
No. A check can see `@fund`, `@start_date`, `@end_date` and `@allocation_run`. Formula outputs are
held per folio during the run, and a check runs once for the whole fund. A post-run check reads what
the run wrote to the ledger, which is also what investors will see.

**Why was my check formula refused with "unsafe expression"?**
Every formula's text is screened for words that could modify data or run code. The screen is
deliberately blunt: `select`, `update`, `create`, `delete`, `save`, `insert`, `drop` and `alter` are
refused **anywhere** in the text, including inside a word or a quoted string, so `created_at`,
`deleted_at` or a message like "valuations not updated" is refused. The helpers build their messages
and queries in Ruby, outside the screened text, which is one reason to prefer them. A custom field
label or entry name that contains one of those words can't be written in a formula today.

**Do checks run on a sample run or a statements-only run?**
A sample run (three folios) runs them, so the post-run tie-out checks will usually fail on a sample
run: only three folios received allocations. A statements-only run (with allocations off) runs no
checks, because it computes nothing.

**Why doesn't a run whose checks all passed get a report?**
Building the report runs heavy aggregate queries over account entries, so it only starts
automatically when there is something to look at. If you check a successful run later, findings
1.5 and 1.6 show as passed: a run can only finish with status Success if no check failed. The
individual checks aren't listed, because nothing was stored for them.

**If I re-check a run, do I lose the check results?**
No. Pressing Check again (or running the checker rake task) rebuilds the other findings from the
ledger as it is now, but keeps the stored check results. Those can't be recomputed, because they
describe the data at the moment the run happened.

**I fixed the data. How do I clear the failure?**
Run the allocation again for the same period. That creates a new allocation run and, if its checks
fail or warn, a new report. The failed run and its report stay in the history.

**A check fails with `NoMethodError` or `NameError`. Is that a real failure?**
It means the check itself is broken (a typo, or a method that doesn't exist on that object), not
that the data is wrong. It still stops the run, because a check that can't run proves nothing. The
report puts the error class in front of the message so you can tell the two apart.

**Can I use the same checks across all our funds?**
Yes. Save them as template formulas and copy them into each fund, then adjust the lists or
tolerances where a fund differs. Each fund keeps its own copy, which is what "mapping at fund level"
allows: one fund can have an extra expense head without affecting the others.
