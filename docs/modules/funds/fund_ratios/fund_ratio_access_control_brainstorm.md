# FundRatio Access Control — Brainstorm

**Status:** Open question — no decision made yet.

## Background

Employees in IRM are currently restricted to specific funds and portfolio companies via `AccessRight` records. When a user views a single fund's `FundRatio` rows, the fund's access right gates that access cleanly.

`FundRatioRun` changes the picture: a cross-run ratio (e.g. portfolio XIRR across Fund A + Fund B + 12 portfolio companies) is a **single aggregated number**. It cannot be meaningfully split — you either see the run or you don't. The question is: what grants or denies visibility to the run as a whole?

---

## The Core Tension

| Existing model | Cross-run model |
|---|---|
| Employee has access to Fund A → sees Fund A's ratios | Employee has access to Fund A → should they see a run that covers Fund A *and* Fund B? |
| One fund, one access right, clean gate | Multiple constituent funds/companies, single aggregate output |

---

## Options

### Option 1 — Anchor fund gates access *(current de facto)*

The run already has an `anchor_fund` (the fund the user navigated from when triggering the job). Gate visibility on whether the employee has access to `anchor_fund`.

- **Pro:** Zero new logic; consistent with existing `permissioned_employee?` pattern.
- **Con:** `anchor_fund` is a navigation accident, not a meaningful representation of scope. Two identical runs triggered from different starting funds would have different visibility for the same employee.

---

### Option 2 — Any constituent fund = access

If the employee has access to *any* fund in `fund_ids`, they can see the run.

- **Pro:** Inclusive; employees see runs relevant to at least some of their funds.
- **Con:** The employee reads an aggregate built partly from data (other funds/companies) they are not supposed to see. Could be a regulatory or confidentiality concern.

---

### Option 3 — All constituent funds = access

Employee must have access to *all* funds and portfolio companies in the run.

- **Pro:** No data leakage.
- **Con:** Nearly unusable in practice. Cross-portfolio runs spanning 30 companies would be invisible to almost all employees except `company_admin`.

---

### Option 4 — Cross-runs are company_admin only

Regular employees only see single-fund `FundRatio` rows (via `fund_id`). Cross-fund and cross-portfolio runs are treated as admin-level analytics.

- **Pro:** Clean separation of concerns; zero ambiguity.
- **Con:** Excludes fund managers who own multiple funds but are not `company_admin`. May be too blunt for larger organisations with senior analysts.

---

### Option 5 — Row-level filtering (cross-portfolio) + run-level gate (cross-fund)

For **cross-portfolio** runs, each `FundRatio` row has an `owner` (a portfolio company). Filter to only rows where the employee has access to that company. The aggregate "portfolio IRR" row (which spans all companies) is shown if the employee can see *any* company in the run.

For **cross-fund** runs, the entire run is one aggregate — gate on anchor fund or a primary-fund heuristic.

- **Pro:** Most precise for cross-portfolio; employees see their slice.
- **Con:** Significant complexity. Aggregate rows (e.g. blended IRR across all 30 companies) become philosophically tricky — showing a "partial" aggregate built from only the companies the employee can see may be worse than showing nothing, because it silently misrepresents the number.

---

### Option 6 — Explicit access grant per run

When a run is triggered, auto-grant access to all employees who have access to at least one constituent fund or portfolio company. The run gets its own `AccessRight` records.

- **Pro:** Fine-grained and auditable.
- **Con:** Schema and job overhead. Runs are created automatically; managing access rights at job time is fragile, especially for bulk triggers.

---

### Option 7 — New permission flag (`enable_cross_fund_ratios`)

Add a boolean permission flag (similar to `enable_funds`). Employees with the flag see all entity-scoped runs. Others see nothing beyond their single-fund ratios.

- **Pro:** Simple, operator-controlled, easy to retrofit later with per-fund granularity.
- **Con:** Binary — no per-fund or per-company granularity. An employee with two funds either sees all cross-runs or none.

---

## Key Questions That Shape the Decision

1. **How sensitive are cross-run numbers?**
   If seeing a blended IRR across funds an employee doesn't manage is genuinely problematic (regulatory, LP confidentiality), Options 3 or 4 are the safe floor. If it is just an analytics convenience, Options 2 or 7 are sufficient.

2. **Who typically triggers cross-runs?**
   If only `company_admin` users ever trigger them, Option 4 is the natural outcome anyway. If senior fund managers (non-admin employees) trigger them for their own portfolios, they will expect to see what they ran.

3. **Should restricted employees see the FundRatioRun index at all?**
   Currently the index shows all entity-scoped runs — no access-right filtering. Should a restricted employee see run records they cannot read the details of?

4. **Cross-portfolio vs cross-fund — different rules?**
   These two run types may warrant different access models. Cross-portfolio runs are about portfolio companies (which have their own per-company access rights). Cross-fund runs are about fund-level aggregates. Splitting the logic by `run_type` is worth considering.

---

## Instinct / Recommendation (not decided)

**Option 7** (a simple `enable_cross_fund_ratios` flag) combined with the existing entity scope is the most pragmatic starting point:

- Keeps the model simple and consistent with other `enable_*` flags.
- Easy to tighten later — a per-fund or per-company layer can be bolted on once the access pattern is better understood from real usage.
- Avoids the philosophically broken "partial aggregate" problem that arises when filtering individual ratio rows from a run that produces a single blended number.

A possible refinement: treat cross-runs like a report — visible to anyone who can see any of the constituent funds, but clearly labelled with its full scope so employees understand they are viewing an entity-wide aggregate.

---

## Related Code

| File | Role |
|---|---|
| `app/packs/funds/funds/policies/fund_ratio_run_policy.rb` | Current policy — entity scope only, no access-right filtering |
| `app/packs/funds/funds/policies/fund_ratio_policy.rb` | Single-fund ratio policy — uses `permissioned_employee?` |
| `app/packs/core/base/policies/application_policy.rb` | `permissioned_employee?`, `belongs_to_entity?` |
| `app/packs/funds/funds/models/fund_ratio_run.rb` | `fund_ids`, `portfolio_company_ids`, `sectors`, `portfolio_companies_tags` |
| `app/packs/funds/funds/services/fund_ratio_multi_fund_calcs.rb` | Company resolution logic (tags ∩ sectors when both set) |
