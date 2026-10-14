---
name: portfolio
description: Fund's portfolio companies — which companies the fund invested in, when, how much, current valuation, gain/loss, and portco-level performance (MOIC/IRR). Fund-level data visible to LPs when the fund shows its portfolio; under an Allocated LP portfolio view only the holdings allocated to the LP's folio ({VISIBLE_API_IDS} / {VISIBLE_PI_IDS}).
tables:
  - portfolio_investments
  - aggregate_portfolio_investments
  - investors
  - valuations
  - funds
  - fund_ratios
---

# Portfolio Companies (fund-level, LP-visible via the *Show portfolio to LPs* feature)

The fund's portfolio — companies it has invested in. This data is **fund-level** (LPs in the same fund see the same portfolio), gated by the fund's *Show portfolio to LPs* feature (`(funds.features & 4) > 0` — bit 2 of `funds.features`). No per-LP (`investor_id`) scoping applies here.

## Data model — critical gotcha

- There is **no `portfolio_companies` table**. A "portfolio company" is an `investors` row (`category` flags it, `investor_name` is the display name).
- `portfolio_investments` (alias `pi`) is a **transaction log** — one row per buy / sell / follow-on round. A portco with three rounds has three rows. Use `DISTINCT` or `GROUP BY` when listing.
- `aggregate_portfolio_investments` (alias `api`) is the rolled-up position per (fund, portco) — use this for current holdings, quantities, cost basis, FMV.
- `portfolio_company_name` on `pi` is denormalized; always `JOIN investors i ON i.id = pi.portfolio_company_id` and read `i.investor_name` instead.

## Table: portfolio_investments (transaction log)

| Column | Type | Description |
|--------|------|-------------|
| id | bigint | Primary key |
| entity_id | bigint | Scope |
| fund_id | bigint | Scope |
| portfolio_company_id | bigint | FK to `investors.id` |
| portfolio_company_name | varchar | Denormalized — do NOT rely on; join `investors` |
| investment_date | date | Date of this buy/sell/round |
| amount_cents | decimal | Transaction amount (fund currency) |
| net_amount_cents | decimal | Net amount |
| net_quantity | decimal | Net units/shares |
| fmv_cents | decimal | Fair market value at this line |
| gain_cents | decimal | Gain on this line |
| cost_of_remaining_cents | decimal | Remaining cost basis after this tx |
| cost_of_sold_cents | decimal | Cost of sold units |
| category | varchar | Transaction category |
| investment_domicile | varchar | 'Domestic' / etc. |
| proforma | boolean | **MUST filter `= false`** — excludes what-if scenarios |
| aggregate_portfolio_investment_id | bigint | FK to aggregate |
| deleted_at | datetime | Soft delete |

## Table: aggregate_portfolio_investments (rolled-up position)

| Column | Type | Description |
|--------|------|-------------|
| id | bigint | Primary key |
| entity_id | bigint | Scope |
| fund_id | bigint | Scope |
| portfolio_company_id | bigint | FK to `investors.id` |
| bought_amount_cents | decimal | Total invested |
| bought_quantity | decimal | Total units bought |
| sold_amount_cents | decimal | Total exits |
| sold_quantity | decimal | Total units sold |
| cost_of_remaining_cents | decimal | Cost basis of current holdings |
| fmv_cents | decimal | Current fair market value |
| gain_cents | decimal | Unrealized gain |
| avg_cost_cents | decimal | Average cost per unit |
| quantity | decimal | Current units held |
| portfolio_income_cents | decimal | Income received |
| investment_type | varchar | e.g. 'Equity', 'Debt' |
| show_portfolio | boolean | Retired — no longer used (sharing is the company's `investors.show_to_lps`) |
| snapshot | boolean | True for historical snapshots |
| snapshot_date | date | Snapshot date (NULL for current) |
| deleted_at | datetime | Soft delete |

For current holdings, filter `api.snapshot = false` (or omit snapshot rows).

## Table: investors (portco display info)

| Column | Type | Description |
|--------|------|-------------|
| id | bigint | Primary key |
| entity_id | bigint | Scope |
| investor_name | varchar | Portco display name |
| category | varchar(100) | Investor category (portcos have specific values) |
| sector | varchar | Sector/industry |
| city | varchar(50) | Location |
| deleted_at | datetime | Soft delete |

## Table: valuations (valuation history per portco)

| Column | Type | Description |
|--------|------|-------------|
| id | bigint | Primary key |
| entity_id | bigint | Scope |
| owner_type | varchar | Filter `= 'PortfolioCompany'` for portco valuations |
| owner_id | bigint | FK — matches `investors.id` for portcos |
| valuation_date | date | As-of date |
| valuation_cents | decimal | Valuation amount |
| per_share_value_cents | decimal(20,8) | Per-share value |
| net_valuation_cents | decimal | Net valuation |
| synthetic | boolean | True for derived valuations |
| deleted_at | datetime | Soft delete |

## CRITICAL Rules — ALWAYS Apply

1. **Scope by entity and fund** (no investor filter):
   ```
   WHERE pi.entity_id IN ({ENTITY_ID})
     AND pi.fund_id IN ({FUND_IDS})
     AND pi.id IN ({VISIBLE_PI_IDS})
   ```
   Note: `{INVESTOR_IDS}` is NOT used in this skill — portfolio is fund-level.

2. **LP visibility gate** — always require:
   ```
   AND (f.features & 4) > 0
   ```
   Funds without that feature bit hide the portfolio from LPs; the query must respect this.

3. **Visible holdings** — always (queries without them are rejected):
   ```
   AND api.id IN ({VISIBLE_API_IDS})   -- on aggregate_portfolio_investments
   AND pi.id  IN ({VISIBLE_PI_IDS})    -- on portfolio_investments
   ```
   They hold only the holdings this LP may see: the whole fund, or — when the fund narrows its portfolio to each
   LP's folio — just the holdings allocated to this LP. Never answer about a holding outside them.

4. **Proforma filter** — always on `portfolio_investments`:
   ```
   AND pi.proforma = false
   ```

5. **Soft deletes** — `deleted_at IS NULL` on every joined table (`pi`, `api`, `f`, `i`, `v`, `fr`).

6. **Use DISTINCT or GROUP BY when listing portcos** — `pi` is a transaction log; without DISTINCT the same portco appears once per round.

7. **Join `investors` for the display name** — don't trust `pi.portfolio_company_name` (denormalized and may be stale).

8. **Divide `*_cents` by 100** for display. Currency from `f.currency`.

## Example Queries

### Q: "What companies has my fund invested in?" (list portcos)

```sql
SELECT DISTINCT
       i.id            AS portco_id,
       i.investor_name AS company,
       f.name          AS fund_name,
       i.sector
FROM portfolio_investments pi
JOIN funds     f ON f.id = pi.fund_id
JOIN investors i ON i.id = pi.portfolio_company_id
WHERE pi.entity_id IN ({ENTITY_ID})
  AND pi.fund_id IN ({FUND_IDS})
  AND pi.id IN ({VISIBLE_PI_IDS})
  AND (f.features & 4) > 0
  AND pi.proforma = false
  AND pi.deleted_at IS NULL
  AND f.deleted_at IS NULL
  AND i.deleted_at IS NULL
ORDER BY f.name, i.investor_name
```

### Q: "Current holdings — cost basis and FMV for each portco"

```sql
SELECT f.name          AS fund_name,
       f.currency,
       i.investor_name AS company,
       api.bought_amount_cents / 100        AS total_invested,
       api.cost_of_remaining_cents / 100    AS cost_basis,
       api.fmv_cents / 100                  AS current_value,
       api.gain_cents / 100                 AS unrealized_gain,
       api.quantity                         AS units_held
FROM aggregate_portfolio_investments api
JOIN funds     f ON f.id = api.fund_id
JOIN investors i ON i.id = api.portfolio_company_id
WHERE api.entity_id IN ({ENTITY_ID})
  AND api.fund_id IN ({FUND_IDS})
  AND api.id IN ({VISIBLE_API_IDS})
  AND (f.features & 4) > 0
  AND api.snapshot = false
  AND api.deleted_at IS NULL
  AND f.deleted_at IS NULL
  AND i.deleted_at IS NULL
ORDER BY api.fmv_cents DESC
```

### Q: "When did the fund invest in Acme Corp? Show me every round."

```sql
SELECT f.name          AS fund_name,
       i.investor_name AS company,
       pi.investment_date,
       pi.amount_cents / 100   AS round_amount,
       pi.net_quantity,
       pi.category
FROM portfolio_investments pi
JOIN funds     f ON f.id = pi.fund_id
JOIN investors i ON i.id = pi.portfolio_company_id
WHERE pi.entity_id IN ({ENTITY_ID})
  AND pi.fund_id IN ({FUND_IDS})
  AND pi.id IN ({VISIBLE_PI_IDS})
  AND i.investor_name LIKE '%Acme%'
  AND (f.features & 4) > 0
  AND pi.proforma = false
  AND pi.deleted_at IS NULL
  AND f.deleted_at IS NULL
  AND i.deleted_at IS NULL
ORDER BY pi.investment_date
```

### Q: "MOIC per portfolio company in Growth Fund" (cross-skill join with fund_ratios)

```sql
SELECT i.investor_name  AS company,
       fr.display_value AS moic,
       fr.end_date
FROM fund_ratios fr
JOIN investors i              ON i.id = fr.owner_id
JOIN portfolio_investments pi ON pi.portfolio_company_id = i.id
JOIN funds f                  ON f.id = pi.fund_id
WHERE fr.entity_id IN ({ENTITY_ID})
  AND fr.fund_id IN ({FUND_IDS})
  AND fr.owner_type = 'PortfolioCompany'
  AND fr.name = 'MOIC'
  AND fr.latest = true
  AND fr.scenario = 'Default'
  AND f.name LIKE '%Growth%'
  AND (f.features & 4) > 0
  AND pi.id IN ({VISIBLE_PI_IDS})
  AND pi.proforma = false
  AND fr.deleted_at IS NULL
  AND pi.deleted_at IS NULL
  AND f.deleted_at IS NULL
  AND i.deleted_at IS NULL
GROUP BY i.id, i.investor_name, fr.display_value, fr.end_date
ORDER BY i.investor_name
```

### Q: "Latest valuation for each portco"

```sql
SELECT i.investor_name              AS company,
       f.name                       AS fund_name,
       v.valuation_date,
       v.valuation_cents / 100      AS valuation,
       v.per_share_value_cents / 100 AS per_share
FROM valuations v
JOIN investors i              ON i.id = v.owner_id
JOIN portfolio_investments pi ON pi.portfolio_company_id = i.id
JOIN funds f                  ON f.id = pi.fund_id
WHERE v.entity_id IN ({ENTITY_ID})
  AND pi.fund_id IN ({FUND_IDS})
  AND pi.id IN ({VISIBLE_PI_IDS})
  AND v.owner_type = 'PortfolioCompany'
  AND (f.features & 4) > 0
  AND pi.proforma = false
  AND v.deleted_at IS NULL
  AND pi.deleted_at IS NULL
  AND f.deleted_at IS NULL
  AND i.deleted_at IS NULL
  AND v.valuation_date = (
    SELECT MAX(v2.valuation_date)
    FROM valuations v2
    WHERE v2.owner_type = 'PortfolioCompany'
      AND v2.owner_id = v.owner_id
      AND v2.entity_id IN ({ENTITY_ID})
      AND v2.deleted_at IS NULL
  )
GROUP BY i.id, i.investor_name, f.name, v.valuation_date, v.valuation_cents, v.per_share_value_cents
ORDER BY i.investor_name
```

### Q: "Sector breakdown of the portfolio (by cost basis)"

```sql
SELECT i.sector,
       f.currency,
       COUNT(DISTINCT i.id)                  AS company_count,
       SUM(api.cost_of_remaining_cents) / 100 AS total_cost_basis,
       SUM(api.fmv_cents) / 100              AS total_fmv
FROM aggregate_portfolio_investments api
JOIN funds     f ON f.id = api.fund_id
JOIN investors i ON i.id = api.portfolio_company_id
WHERE api.entity_id IN ({ENTITY_ID})
  AND api.fund_id IN ({FUND_IDS})
  AND api.id IN ({VISIBLE_API_IDS})
  AND (f.features & 4) > 0
  AND api.snapshot = false
  AND api.deleted_at IS NULL
  AND f.deleted_at IS NULL
  AND i.deleted_at IS NULL
GROUP BY i.sector, f.currency
ORDER BY total_fmv DESC
```

### Q: "Top 5 portcos by current value"

```sql
SELECT i.investor_name AS company,
       f.name          AS fund_name,
       f.currency,
       api.fmv_cents / 100 AS current_value,
       api.gain_cents / 100 AS unrealized_gain
FROM aggregate_portfolio_investments api
JOIN funds     f ON f.id = api.fund_id
JOIN investors i ON i.id = api.portfolio_company_id
WHERE api.entity_id IN ({ENTITY_ID})
  AND api.fund_id IN ({FUND_IDS})
  AND api.id IN ({VISIBLE_API_IDS})
  AND (f.features & 4) > 0
  AND api.snapshot = false
  AND api.deleted_at IS NULL
  AND f.deleted_at IS NULL
  AND i.deleted_at IS NULL
ORDER BY api.fmv_cents DESC
LIMIT 5
```

## Anti-patterns to Avoid

| Bad | Why | Fix |
|-----|-----|-----|
| `SELECT * FROM portfolio_companies` | That table doesn't exist | Portcos are `investors` rows; join `investors` on `pi.portfolio_company_id` |
| Listing portcos without `DISTINCT` | `pi` is a tx log — one portco appears once per round | Use `SELECT DISTINCT` or `GROUP BY portfolio_company_id` |
| Forgetting `(f.features & 4) > 0` | LPs shouldn't see portfolios of funds where the FM hid them | Always include the filter |
| Forgetting `pi.proforma = false` | Returns what-if / scenario rows alongside actuals | Always filter |
| Using `pi.portfolio_company_name` for display | Denormalized and may be stale | Read `i.investor_name` from the joined `investors` |
| Summing amounts across `pi` rows for current holdings | PI is a tx log including buys & sells — double-counts | Use `aggregate_portfolio_investments` for current position |
| Reporting `*_cents` raw | User expects money, not minor units | Divide by 100 |
| Filtering fund_ratios by `owner_type = 'Fund'` for portco metrics | Those are fund-level rows | For portco metrics use `owner_type = 'PortfolioCompany'` |

## When to Use Other Skills

- **Fund-level returns (TVPI, DPI, IRR of the fund)** → `fund_ratios` skill with `owner_type = 'Fund'`
- **How much the LP committed / paid / received** → `commitments`, `capital_calls`, `distributions`
- **Portco-level performance (MOIC / IRR per portco)** → this skill's cross-skill example above, or `fund_ratios` with `owner_type = 'PortfolioCompany'`
