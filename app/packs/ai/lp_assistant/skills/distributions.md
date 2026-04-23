---
name: distributions
description: Distribution payments received by the LP — when, how much, income vs. cost-of-capital breakdown, per-fund and per-commitment. Always scoped to the LP's own payment records; never exposes fund-wide distribution totals.
tables:
  - capital_distributions
  - capital_distribution_payments
  - capital_commitments
  - funds
---

# Distributions (LP-scoped via payments)

A `capital_distributions` row is a fund-wide distribution event (e.g. "Q4 2024 distribution, net cash of X"). Each LP's share of that distribution is a `capital_distribution_payments` row.

**Never query `capital_distributions` alone for amount data.** Always join through `capital_distribution_payments` and filter by `investor_id IN ({INVESTOR_IDS})`.

## Table: capital_distributions (fund-level — join only, for date/title/notes)

| Column | Type | Description |
|--------|------|-------------|
| id | bigint | Primary key |
| entity_id | bigint | Scope |
| fund_id | bigint | Scope |
| distribution_date | date | Date of the distribution event |
| title | varchar | Distribution label (e.g. "Q4 2024 Distribution") |
| notes | text | Narrative |
| approved | boolean | Only approved events are shown to LPs |
| completed | boolean | Whether payments have gone out |
| deleted_at | datetime | Soft delete |

Do NOT select `distribution_amount_cents`, `gross_amount_cents`, `net_amount_cents`, `carry_cents`, `fee_cents`, or `income_cents` from `capital_distributions` — those are fund-wide totals.

## Table: capital_distribution_payments (LP's slice — the main table)

| Column | Type | Description |
|--------|------|-------------|
| id | bigint | Primary key |
| entity_id | bigint | Scope |
| fund_id | bigint | Scope |
| capital_distribution_id | bigint | FK to `capital_distributions.id` |
| capital_commitment_id | bigint | FK to `capital_commitments.id` |
| investor_id | bigint | FK to investors — **filter with `{INVESTOR_IDS}`** |
| payment_date | date | When the LP was paid |
| gross_payable_cents | decimal | Gross amount payable to THIS LP |
| net_payable_cents | decimal | Net amount (after fees/carry) to THIS LP |
| income_cents | decimal | Income portion (taxable) |
| income_with_fees_cents | decimal | Income including allocated fees |
| cost_of_investment_cents | decimal | Return-of-capital portion |
| cost_of_investment_with_fees_cents | decimal | RoC including allocated fees |
| reinvestment_cents | decimal | Amount reinvested (not cash out) |
| reinvestment_with_fees_cents | decimal | Reinvestment including fees |
| folio_amount_cents | decimal | Amount in LP's folio currency |
| folio_id | varchar(40) | Folio |
| units_quantity | decimal | Units involved |
| completed | boolean | Payment completed |
| notification_sent | boolean | Notification sent to LP |
| deleted_at | datetime | Soft delete |

## CRITICAL Rules — ALWAYS Apply

1. **Always filter by entity, fund, AND investor on `capital_distribution_payments` (alias `cdp`):**
   ```
   WHERE cdp.entity_id IN ({ENTITY_ID})
     AND cdp.fund_id IN ({FUND_IDS})
     AND cdp.investor_id IN ({INVESTOR_IDS})
   ```

2. **Only show approved distributions** unless the LP explicitly asks about pending/draft:
   ```
   AND cd.approved = true
   ```

3. **Soft deletes** — filter `deleted_at IS NULL` on every joined table.

4. **Divide `*_cents` by 100** for display.

5. **Never expose fund-level aggregates** from `capital_distributions` — they include every LP. Always use `capital_distribution_payments` for amounts.

6. **Net vs. gross** — LPs typically care about `net_payable_cents` ("what hit my bank"). Use `gross_payable_cents` only when the user asks about gross.

## Example Queries

### Q: "How much have I received in distributions?"

```sql
SELECT f.name AS fund_name,
       f.currency,
       SUM(cdp.net_payable_cents) / 100   AS total_received_net,
       SUM(cdp.gross_payable_cents) / 100 AS total_received_gross
FROM capital_distribution_payments cdp
JOIN funds f ON f.id = cdp.fund_id
WHERE cdp.entity_id IN ({ENTITY_ID})
  AND cdp.fund_id IN ({FUND_IDS})
  AND cdp.investor_id IN ({INVESTOR_IDS})
  AND cdp.deleted_at IS NULL
  AND f.deleted_at IS NULL
GROUP BY f.id, f.name, f.currency
ORDER BY f.name
```

### Q: "Show me every distribution payment I've received"

```sql
SELECT f.name AS fund_name,
       f.currency,
       cd.title,
       cdp.payment_date,
       cdp.gross_payable_cents / 100 AS gross,
       cdp.net_payable_cents / 100   AS net,
       cdp.income_cents / 100        AS income,
       cdp.cost_of_investment_cents / 100 AS return_of_capital
FROM capital_distribution_payments cdp
JOIN capital_distributions cd ON cd.id = cdp.capital_distribution_id
JOIN funds f                  ON f.id  = cdp.fund_id
WHERE cdp.entity_id IN ({ENTITY_ID})
  AND cdp.fund_id IN ({FUND_IDS})
  AND cdp.investor_id IN ({INVESTOR_IDS})
  AND cd.approved = true
  AND cdp.deleted_at IS NULL
  AND cd.deleted_at IS NULL
  AND f.deleted_at IS NULL
ORDER BY cdp.payment_date DESC
LIMIT 50
```

### Q: "Break down my distributions into income vs. return of capital"

```sql
SELECT f.name AS fund_name,
       f.currency,
       SUM(cdp.income_cents) / 100             AS income,
       SUM(cdp.cost_of_investment_cents) / 100 AS return_of_capital,
       SUM(cdp.reinvestment_cents) / 100       AS reinvested,
       SUM(cdp.net_payable_cents) / 100        AS net_total
FROM capital_distribution_payments cdp
JOIN funds f ON f.id = cdp.fund_id
WHERE cdp.entity_id IN ({ENTITY_ID})
  AND cdp.fund_id IN ({FUND_IDS})
  AND cdp.investor_id IN ({INVESTOR_IDS})
  AND cdp.deleted_at IS NULL
  AND f.deleted_at IS NULL
GROUP BY f.id, f.name, f.currency
ORDER BY f.name
```

### Q: "Distribution history for Growth Fund"

```sql
SELECT cd.title,
       cdp.payment_date,
       cdp.gross_payable_cents / 100 AS gross,
       cdp.net_payable_cents / 100   AS net,
       cdp.units_quantity,
       cdp.completed
FROM capital_distribution_payments cdp
JOIN capital_distributions cd ON cd.id = cdp.capital_distribution_id
JOIN funds f                  ON f.id  = cdp.fund_id
WHERE cdp.entity_id IN ({ENTITY_ID})
  AND cdp.fund_id IN ({FUND_IDS})
  AND cdp.investor_id IN ({INVESTOR_IDS})
  AND f.name LIKE '%Growth%'
  AND cd.approved = true
  AND cdp.deleted_at IS NULL
  AND cd.deleted_at IS NULL
  AND f.deleted_at IS NULL
ORDER BY cdp.payment_date DESC
LIMIT 20
```

### Q: "Distribution trend over time (for charting)"

```sql
SELECT f.name AS fund_name,
       cdp.payment_date,
       cdp.net_payable_cents / 100 AS net_amount
FROM capital_distribution_payments cdp
JOIN capital_distributions cd ON cd.id = cdp.capital_distribution_id
JOIN funds f                  ON f.id  = cdp.fund_id
WHERE cdp.entity_id IN ({ENTITY_ID})
  AND cdp.fund_id IN ({FUND_IDS})
  AND cdp.investor_id IN ({INVESTOR_IDS})
  AND cd.approved = true
  AND cdp.deleted_at IS NULL
  AND cd.deleted_at IS NULL
  AND f.deleted_at IS NULL
ORDER BY cdp.payment_date
```

Render as a bar or line chart per `chart_rendering_prompt`.

### Q: "Pending distributions (announced but not yet paid to me)"

```sql
SELECT f.name AS fund_name,
       cd.title,
       cd.distribution_date,
       cdp.net_payable_cents / 100 AS expected_net
FROM capital_distribution_payments cdp
JOIN capital_distributions cd ON cd.id = cdp.capital_distribution_id
JOIN funds f                  ON f.id  = cdp.fund_id
WHERE cdp.entity_id IN ({ENTITY_ID})
  AND cdp.fund_id IN ({FUND_IDS})
  AND cdp.investor_id IN ({INVESTOR_IDS})
  AND cd.approved = true
  AND cdp.completed = false
  AND cdp.deleted_at IS NULL
  AND cd.deleted_at IS NULL
  AND f.deleted_at IS NULL
ORDER BY cd.distribution_date DESC
```

## Anti-patterns to Avoid

| Bad | Why | Fix |
|-----|-----|-----|
| `SELECT cd.net_amount_cents FROM capital_distributions cd` | That's the fund-wide net — includes all LPs | Start FROM `capital_distribution_payments cdp` instead |
| Omitting `cdp.investor_id IN ({INVESTOR_IDS})` | Leaks other LPs' payments | Always include it |
| Forgetting `cd.approved = true` | Shows draft distributions not yet visible to LPs | Always filter |
| Using `gross_payable_cents` when the user says "how much did I receive" | LPs usually mean net (after fees/carry) | Default to `net_payable_cents`, mention gross separately if relevant |
| Showing `_cents` values raw | User expects money units | Divide by 100 |

## When to Use Other Skills

- **Committed vs. called amounts, uncalled capital** → `commitments` skill
- **Capital calls (money the LP has to put IN)** → `capital_calls` skill
- **TVPI / DPI / IRR performance metrics** → `fund_ratios` skill
