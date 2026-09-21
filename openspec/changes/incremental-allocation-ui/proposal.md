# Incremental Allocation UI

## Why

Moving a fund onto incremental since-inception allocation, and setting up its pre/post-run checks,
is currently developer work: `rake allocation:enable_incremental`, hand-written check formulas,
and an xlsx built by hand (this is how fund 342 was done). Support needs to do both from the fund
formulas page with a preview they can review, without shell access and without the logic
diverging between the rake tasks and the UI.

## What Changes

- The fund formulas page's **"Enable All" dropdown becomes "Actions"**. It keeps Enable All,
  Disable All and Filter, and adds the support-only actions below.
- **Switch to incremental allocation** (support only):
  - **Preview** runs in the background and shows the plan: each formula edit with before/after
    text and description, blockers, warnings, and tracking starting values old → new.
  - **Apply** writes exactly what was previewed. It plans again first, and refuses if the plan
    differs or the fund has an allocation run or run group in progress.
  - **Switch off** gets the same preview/apply treatment (formulas and descriptions restored from
    the audit trail).
  - **Recompute starting values** for tracking formulas replaces
    `rake allocation:reseed_carry_forward`.
- **Suggest run checks** (support only):
  - Builds pre/post-run check formulas from **rules** that read the fund's formulas, its entity's
    custom field forms and its past uploaded account entries. Every suggestion records the formulas
    and data that led to it.
  - An optional **Suggest more with AI** step proposes fund-specific checks the rules don't cover.
  - Every suggestion (rule or AI) is validated and **test-run against the fund's last successful
    allocation run** before it is shown, with its pass/warn/fail result.
  - Support ticks suggestions and either **adds them** as `FundFormula`s or **downloads them as an
    importable xlsx**. Both paths use one attribute builder shared with the existing importer.
- New table **`fund_formula_operations`** records every background operation on a fund's formulas:
  - **operations:** switch on, switch off, recompute starting values, suggest checks
  - **columns:** fund, requesting and applying user, status, plan/suggestions, result, times

  It is the history of who changed which fund and what changed. It also holds suggestion sets
  between generating them and adding them, since AI suggestions can't be regenerated identically.
- `AccountEntryAllocation::IncrementalMigration` returns a **structured result** instead of
  printing. The rake tasks in `lib/tasks/incremental_allocation.rake` become thin wrappers that
  print it. They keep their names and arguments.
- The panel shows the recommended order of steps, with a tick as each one is done: add checks →
  re-run the latest period → preview and apply → re-run the latest period, where the post-run
  check "Since Inception totals match history" confirms the switch.

## Capabilities

### New Capabilities
- `funds/incremental-allocation-migration`: support-facing preview, apply and switch-off of
  incremental since-inception allocation per fund, plus recomputing tracking starting values:
  - the fund-busy and stale-plan guards
  - the operation history
  - rake tasks as wrappers over the same service
- `funds/run-check-suggestions`: generating pre/post-run check formulas for a fund:
  - the rules and the evidence each suggestion carries
  - optional AI suggestions
  - test-running every suggestion against the last successful run
  - adding selected checks, or exporting them in the FundFormula import format

### Modified Capabilities

(none — `openspec/specs/` has no existing specs)

## Impact

- **Services:**
  - `app/packs/allocation_engine/account_entry_allocation/incremental_migration.rb` refactored to a
    result object; output formatting moves to the rake task.
  - New rule-based check suggester and AI suggester (via the existing `LlmService`).
  - Attribute builder extracted from `ImportFundFormula#save_row`.
- **Jobs:** new background job(s) for migration preview/apply and for check suggestions (dry runs
  and the full scratch copy take seconds to minutes).
- **Data:** migration adding `fund_formula_operations`. Note the local `db:migrate` schema drift
  procedure when regenerating `schema.rb`.
- **UI:** `fund_formulas/_index.html.erb` (dropdown rename), new support-only views and a
  controller for migrations and suggestions, Turbo updates while jobs run.
- **Policies:** support-only (`support?`), in line with `FundFormulaPolicy#create?`.
- **Rake:** `lib/tasks/incremental_allocation.rake` rewritten as a wrapper; behaviour and output
  unchanged.
- **Docs:** `docs/modules/allocation/incremental_allocation_history.md` and
  `docs/modules/allocation/incremental_allocation_validation.md` (production switch-on
  checklist now points at the UI); a user guide for support.
- **Tests:** Cucumber features for both capabilities (no RSpec).
- **AI cost:** only when support clicks "Suggest more with AI"; nothing runs automatically.
