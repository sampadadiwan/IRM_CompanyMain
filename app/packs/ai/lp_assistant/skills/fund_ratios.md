---
name: fund_ratios
description: Fund performance metrics — NAV, IRR, TVPI, DPI, MOIC, and custom ratios. Use this skill for any question about fund returns, valuations, or performance over time.
tables:
  - fund_ratios
  - funds
---

# Fund Ratios

Fund ratios are calculated performance metrics for a fund or commitment. Each ratio has a name (e.g. "NAV", "IRR"), a numeric value, a display value, and an as-of date.

## Table: fund_ratios

| Column | Type | Description |
|--------|------|-------------|
| id | bigint | Primary key |
| fund_id | bigint | FK to `funds.id` (always required for LP scoping) |
| entity_id | bigint | FK to `entities.id` (always required for LP scoping) |
| name | varchar | Ratio name. Common: 'NAV', 'IRR', 'TVPI', 'DPI', 'MOIC', 'RVPI'. Custom names also possible |
| value | decimal(20,8) | Raw numeric value — use for math/comparisons |
| display_value | varchar(50) | Pre-formatted string for display (use this when showing to the user) |
| end_date | date | As-of date for this ratio |
| owner_type | varchar | 'Fund', 'CapitalCommitment', or 'PortfolioCompany' |
| owner_id | bigint | FK to the owner record (matches owner_type) |
| scenario | varchar | 'Default' for actuals, or a portfolio scenario name for what-if analysis |
| latest | boolean | TRUE if this is the most recent value for this ratio (use to find current values) |
| capital_commitment_id | bigint | FK — present only when ratio is per-commitment (LP-specific) |
| label | varchar(50) | Optional label/category |
| notes | text | Free-text notes |
| valuation_id | bigint | FK to a valuation record (when ratio is derived from a specific valuation) |
| portfolio_scenario_id | bigint | FK to portfolio_scenarios (for scenario analysis) |
| deleted_at | datetime | Soft delete timestamp (ALWAYS filter: deleted_at IS NULL) |
| created_at | datetime | Record creation time |
| updated_at | datetime | Last update time |

## Table: funds (joined for fund name/currency)

| Column | Type | Description |
|--------|------|-------------|
| id | bigint | Primary key |
| name | varchar | Fund name (e.g. "Growth Fund", "Venture II") |
| currency | varchar | Fund currency code (e.g. 'INR', 'USD') |
| entity_id | bigint | FK to entities.id |
| deleted_at | datetime | Soft delete timestamp |

## Common Ratio Names

Names observed across Caphive datasets. Name matching is case-sensitive — use exact casing. A given fund may have only a subset; if a query returns zero rows, report that honestly rather than assuming the ratio must exist.

| Name | Meaning | Typical owner_type | Typical Value |
|------|---------|--------------------|---------------|
| XIRR | Annualised, dollar-weighted internal rate of return | Fund | "15.2%" |
| XIRR (USD) | XIRR expressed in USD | Fund | "15.2%" |
| IRR | Internal Rate of Return | Investor, AggregatePortfolioInvestment | "15.2%" |
| IRR (USD) | IRR in USD | Investor, AggregatePortfolioInvestment | "15.2%" |
| TVPI | Total Value to Paid-In | Fund | "2.1x" |
| DPI | Distributed to Paid-In | Fund | "0.8x" |
| RVPI | Residual Value to Paid-In | Fund | "1.3x" |
| MOIC | Multiple on Invested Capital | Fund, Investor, AggregatePortfolioInvestment | "2.1x" |
| MOIC (USD) | MOIC in USD | Fund, Investor, AggregatePortfolioInvestment | "2.1x" |
| NAV | Net Asset Value per unit | Fund (may be absent in some datasets) | "1.45" |
| Portfolio Value to Cost | Portfolio value / cost ratio | Fund | "1.4x" |
| Paid In to Committed Capital | Drawdown ratio | Fund | "60%" |
| Gross Portfolio IRR | Gross IRR from portfolio companies | Fund | "18.0%" |
| Gross Portfolio IRR (USD) | Gross Portfolio IRR in USD | Fund | "18.0%" |

If the user asks for "IRR" and you find `XIRR` at Fund level, use `XIRR` and clarify in the response (e.g. "Your fund's IRR — measured as XIRR — is ..."). If they ask for NAV and no NAV rows exist, say so explicitly.

## CRITICAL Rules — ALWAYS Apply

1. **Scope by entity_id and fund_id** — every query MUST include:
   ```
   WHERE fr.entity_id IN ({ENTITY_ID})
     AND fr.fund_id IN ({FUND_IDS})
   ```
   These values come from the CONTEXT section of your system prompt.

2. **Always exclude soft-deleted rows:**
   ```
   AND fr.deleted_at IS NULL
   AND f.deleted_at IS NULL
   ```

3. **Default scenario** — for normal LP questions, filter by:
   ```
   AND fr.scenario = 'Default'
   ```
   Only use other scenarios if the user explicitly asks for what-if analysis.

4. **owner_type matters:**
   - `owner_type = 'Fund'` → fund-level ratios (fund's overall XIRR, TVPI, DPI, RVPI, MOIC, etc.)
   - `owner_type = 'Investor'` → LP-specific ratios across this investor's positions (IRR, MOIC over time)
   - `owner_type = 'CapitalCommitment'` → ratios tied to a specific capital commitment
   - `owner_type = 'AggregatePortfolioInvestment'` → ratios on the aggregate portfolio (IRR, MOIC at portfolio level)
   - `owner_type = 'PortfolioCompany'` → ratios on individual portfolio companies
   - **Fallback strategy:** for LP questions about "my returns" or general fund performance, try `'Fund'` first. If no rows match, try `'Investor'`. Only try other owner_types if the user explicitly asks about portfolio companies or aggregate portfolio.

5. **Latest values** — use `latest = true` to get current values:
   ```
   AND fr.latest = true
   ```
   For trend/history queries, omit this and order by end_date.

6. **Display value** — use `display_value` (pre-formatted string) when showing values to the user. Use `value` (decimal) only for sorting, math, or chart data.

## Example Queries

### Q: "What is my NAV for Growth Fund?"

```sql
SELECT f.name AS fund_name, fr.display_value, fr.end_date
FROM fund_ratios fr
JOIN funds f ON f.id = fr.fund_id
WHERE fr.entity_id IN ({ENTITY_ID})
  AND fr.fund_id IN ({FUND_IDS})
  AND f.name LIKE '%Growth%'
  AND fr.name = 'NAV'
  AND fr.owner_type = 'Fund'
  AND fr.scenario = 'Default'
  AND fr.latest = true
  AND fr.deleted_at IS NULL
  AND f.deleted_at IS NULL
LIMIT 5
```

### Q: "What is the current NAV across all my funds?"

```sql
SELECT f.name AS fund_name, fr.display_value, fr.end_date
FROM fund_ratios fr
JOIN funds f ON f.id = fr.fund_id
WHERE fr.entity_id IN ({ENTITY_ID})
  AND fr.fund_id IN ({FUND_IDS})
  AND fr.name = 'NAV'
  AND fr.owner_type = 'Fund'
  AND fr.scenario = 'Default'
  AND fr.latest = true
  AND fr.deleted_at IS NULL
  AND f.deleted_at IS NULL
ORDER BY f.name
```

### Q: "Show IRR for Growth Fund for the last 8 quarters"

```sql
SELECT f.name AS fund_name, fr.value, fr.display_value, fr.end_date
FROM fund_ratios fr
JOIN funds f ON f.id = fr.fund_id
WHERE fr.entity_id IN ({ENTITY_ID})
  AND fr.fund_id IN ({FUND_IDS})
  AND f.name LIKE '%Growth%'
  AND fr.name = 'IRR'
  AND fr.owner_type = 'Fund'
  AND fr.scenario = 'Default'
  AND fr.deleted_at IS NULL
ORDER BY fr.end_date DESC
LIMIT 8
```

After getting this data, render as a bar chart per `chart_rendering_prompt` instructions.

### Q: "Show me TVPI and DPI for all my funds (latest)"

```sql
SELECT f.name AS fund_name, fr.name AS ratio, fr.display_value, fr.end_date
FROM fund_ratios fr
JOIN funds f ON f.id = fr.fund_id
WHERE fr.entity_id IN ({ENTITY_ID})
  AND fr.fund_id IN ({FUND_IDS})
  AND fr.name IN ('TVPI', 'DPI')
  AND fr.owner_type = 'Fund'
  AND fr.scenario = 'Default'
  AND fr.latest = true
  AND fr.deleted_at IS NULL
  AND f.deleted_at IS NULL
ORDER BY f.name, fr.name
```

### Q: "Compare all performance metrics for Venture Fund II"

```sql
SELECT fr.name AS ratio, fr.display_value, fr.end_date
FROM fund_ratios fr
JOIN funds f ON f.id = fr.fund_id
WHERE fr.entity_id IN ({ENTITY_ID})
  AND fr.fund_id IN ({FUND_IDS})
  AND f.name LIKE '%Venture%II%'
  AND fr.owner_type = 'Fund'
  AND fr.scenario = 'Default'
  AND fr.latest = true
  AND fr.deleted_at IS NULL
  AND f.deleted_at IS NULL
ORDER BY fr.name
```

### Q: "What are my commitment-specific ratios?" (LP-specific)

```sql
SELECT f.name AS fund_name, fr.name AS ratio, fr.display_value, fr.end_date
FROM fund_ratios fr
JOIN funds f ON f.id = fr.fund_id
WHERE fr.entity_id IN ({ENTITY_ID})
  AND fr.fund_id IN ({FUND_IDS})
  AND fr.owner_type = 'CapitalCommitment'
  AND fr.scenario = 'Default'
  AND fr.latest = true
  AND fr.deleted_at IS NULL
  AND f.deleted_at IS NULL
ORDER BY f.name, fr.name
```

### Q: "What is my personal IRR across my investments?" (Investor-level)

```sql
SELECT f.name AS fund_name, fr.name AS ratio, fr.display_value, fr.end_date
FROM fund_ratios fr
JOIN funds f ON f.id = fr.fund_id
WHERE fr.entity_id IN ({ENTITY_ID})
  AND fr.fund_id IN ({FUND_IDS})
  AND fr.name IN ('IRR', 'MOIC')
  AND fr.owner_type = 'Investor'
  AND fr.scenario = 'Default'
  AND fr.latest = true
  AND fr.deleted_at IS NULL
  AND f.deleted_at IS NULL
ORDER BY f.name, fr.name
```

### Q: "NAV trend across all my funds (last 12 months)"

```sql
SELECT f.name AS fund_name, fr.value, fr.display_value, fr.end_date
FROM fund_ratios fr
JOIN funds f ON f.id = fr.fund_id
WHERE fr.entity_id IN ({ENTITY_ID})
  AND fr.fund_id IN ({FUND_IDS})
  AND fr.name = 'NAV'
  AND fr.owner_type = 'Fund'
  AND fr.scenario = 'Default'
  AND fr.end_date >= DATE_SUB(CURDATE(), INTERVAL 12 MONTH)
  AND fr.deleted_at IS NULL
  AND f.deleted_at IS NULL
ORDER BY f.name, fr.end_date
```

Render as a line chart with one series per fund.

## Anti-patterns to Avoid

| Bad | Why | Fix |
|-----|-----|-----|
| `SELECT * FROM fund_ratios` | No scoping → exposes other LPs' data | Always include `entity_id` and `fund_id IN (...)` |
| `WHERE name = 'nav'` | Case-sensitive mismatch | Use `WHERE name = 'NAV'` (uppercase) |
| Forgetting `deleted_at IS NULL` | Returns deleted records | Always filter `deleted_at IS NULL` |
| Showing `value` to user | Raw decimal, no formatting | Use `display_value` for user output |
| Querying without `scenario = 'Default'` | Mixes actuals and scenarios | Filter by `scenario = 'Default'` for normal questions |
| Using `latest = true` for trend queries | Returns only one row | Omit `latest` and order by `end_date` for trends |

## When to Use Other Skills

If the user asks about:
- **How much they committed / called / collected / distributed** → use `commitments` skill
- **Specific drawdown notice or capital call details** → use `capital_calls` skill
- **Distribution payments** → use `distributions` skill
- **Portfolio companies the fund invested in** → use `portfolio` skill
