---
name: commitments
description: LP commitments — how much the investor committed, called, paid, distributed, outstanding. Use for questions about commitment amounts, drawdown progress, uncalled capital, and folio-level positions across funds.
tables:
  - capital_commitments
  - funds
---

# Capital Commitments

Each `capital_commitments` row is a single LP's commitment to a single fund (sometimes sub-divided by folio). It is the backbone for all LP-specific capital workflows — calls, remittances, and distributions reference it via `capital_commitment_id`.

## Table: capital_commitments

| Column | Type | Description |
|--------|------|-------------|
| id | bigint | Primary key |
| entity_id | bigint | FK to entities (always required for scoping) |
| fund_id | bigint | FK to funds (always required for scoping) |
| investor_id | bigint | FK to investors (always required for LP scoping) |
| commitment_date | date | When the commitment was signed |
| committed_amount_cents | decimal | Total amount committed (fund currency, cents — divide by 100 for display) |
| call_amount_cents | decimal | Total amount called so far |
| collected_amount_cents | decimal | Total amount actually paid by the LP |
| distribution_amount_cents | decimal | Total distributions paid to the LP |
| adjustment_amount_cents | decimal | Any adjustments (defaults, transfers) |
| arrear_amount_cents | decimal | Amount called but not yet paid |
| orig_committed_amount_cents | decimal | Original commitment (before adjustments/transfers) |
| folio_currency | varchar(5) | LP's filing currency (e.g. 'USD', 'INR') |
| folio_id | varchar(40) | Folio identifier for this commitment |
| folio_committed_amount_cents | decimal | Commitment in LP's folio currency |
| folio_call_amount_cents | decimal | Called amount in folio currency |
| folio_collected_amount_cents | decimal | Collected amount in folio currency |
| percentage | decimal(20,10) | LP's % share of the fund |
| total_fund_units_quantity | decimal | Units held |
| investor_name | varchar | Denormalized for display |
| fund_close | varchar | Which close this commitment belongs to |
| onboarding_completed | boolean | Onboarding status |
| compliant | boolean | KYC/compliance status |
| notes | text | Free-text notes |
| deleted_at | datetime | Soft delete (ALWAYS filter: `deleted_at IS NULL`) |

## Table: funds (joined for fund name/currency)

| Column | Type | Description |
|--------|------|-------------|
| id | bigint | Primary key |
| name | varchar | Fund name |
| currency | varchar | Fund currency (e.g. 'USD', 'INR') |
| entity_id | bigint | FK to entities |
| deleted_at | datetime | Soft delete |

## Key Derived Values

| Concept | Formula |
|---------|---------|
| Uncalled capital | `committed_amount_cents - call_amount_cents` |
| Outstanding (unpaid) | `call_amount_cents - collected_amount_cents` (equivalent to `arrear_amount_cents`) |
| Drawdown % | `call_amount_cents / committed_amount_cents * 100` |
| Net position (cost basis) | `collected_amount_cents - distribution_amount_cents` |

Always display currency values as `amount_cents / 100` (round to 2 decimals), alongside the fund currency or folio currency.

## CRITICAL Rules — ALWAYS Apply

1. **Scope by entity, fund, and investor** — every query MUST include:
   ```
   WHERE cc.entity_id IN ({ENTITY_ID})
     AND cc.fund_id IN ({FUND_IDS})
     AND cc.investor_id IN ({INVESTOR_IDS})
   ```

2. **Always exclude soft-deleted rows:**
   ```
   AND cc.deleted_at IS NULL
   AND f.deleted_at IS NULL
   ```

3. **Display in money units, not cents** — always divide `*_cents` by 100 when reporting. Prefer fund currency (`f.currency` + `committed_amount_cents`) for cross-fund summaries, or folio (`folio_currency` + `folio_committed_amount_cents`) when the LP asks "in my currency".

4. **Aggregation** — an LP may have multiple commitments to the same fund (different folios / closes). Use `SUM(...)` when the question is "how much have I committed to Fund X?". Show individual rows only when the LP asks for the breakdown.

5. **Fund vs folio currency** — only mix currencies in the same aggregate if the user explicitly asks; otherwise group by `f.currency` or `folio_currency` in the output.

## Example Queries

### Q: "How much have I committed across all my funds?"

```sql
SELECT f.name AS fund_name,
       f.currency,
       SUM(cc.committed_amount_cents) / 100 AS committed,
       SUM(cc.call_amount_cents) / 100     AS called,
       SUM(cc.collected_amount_cents) / 100 AS collected,
       SUM(cc.distribution_amount_cents) / 100 AS distributed
FROM capital_commitments cc
JOIN funds f ON f.id = cc.fund_id
WHERE cc.entity_id IN ({ENTITY_ID})
  AND cc.fund_id IN ({FUND_IDS})
  AND cc.investor_id IN ({INVESTOR_IDS})
  AND cc.deleted_at IS NULL
  AND f.deleted_at IS NULL
GROUP BY f.id, f.name, f.currency
ORDER BY f.name
```

### Q: "What is my uncalled capital?"

```sql
SELECT f.name AS fund_name,
       f.currency,
       SUM(cc.committed_amount_cents - cc.call_amount_cents) / 100 AS uncalled
FROM capital_commitments cc
JOIN funds f ON f.id = cc.fund_id
WHERE cc.entity_id IN ({ENTITY_ID})
  AND cc.fund_id IN ({FUND_IDS})
  AND cc.investor_id IN ({INVESTOR_IDS})
  AND cc.deleted_at IS NULL
  AND f.deleted_at IS NULL
GROUP BY f.id, f.name, f.currency
ORDER BY f.name
```

### Q: "Show my drawdown percentage for each fund"

```sql
SELECT f.name AS fund_name,
       f.currency,
       SUM(cc.committed_amount_cents) / 100 AS committed,
       SUM(cc.call_amount_cents) / 100     AS called,
       ROUND(SUM(cc.call_amount_cents) / NULLIF(SUM(cc.committed_amount_cents), 0) * 100, 2) AS drawdown_pct
FROM capital_commitments cc
JOIN funds f ON f.id = cc.fund_id
WHERE cc.entity_id IN ({ENTITY_ID})
  AND cc.fund_id IN ({FUND_IDS})
  AND cc.investor_id IN ({INVESTOR_IDS})
  AND cc.deleted_at IS NULL
  AND f.deleted_at IS NULL
GROUP BY f.id, f.name, f.currency
ORDER BY drawdown_pct DESC
```

### Q: "What do I owe right now (arrears)?"

```sql
SELECT f.name AS fund_name,
       f.currency,
       cc.folio_id,
       cc.arrear_amount_cents / 100 AS outstanding
FROM capital_commitments cc
JOIN funds f ON f.id = cc.fund_id
WHERE cc.entity_id IN ({ENTITY_ID})
  AND cc.fund_id IN ({FUND_IDS})
  AND cc.investor_id IN ({INVESTOR_IDS})
  AND cc.arrear_amount_cents > 0
  AND cc.deleted_at IS NULL
  AND f.deleted_at IS NULL
ORDER BY cc.arrear_amount_cents DESC
```

### Q: "Show my commitments in my own currency (folio)"

```sql
SELECT f.name AS fund_name,
       cc.folio_currency,
       cc.folio_id,
       cc.folio_committed_amount_cents / 100 AS committed_folio,
       cc.folio_call_amount_cents / 100     AS called_folio,
       cc.folio_collected_amount_cents / 100 AS collected_folio,
       cc.commitment_date
FROM capital_commitments cc
JOIN funds f ON f.id = cc.fund_id
WHERE cc.entity_id IN ({ENTITY_ID})
  AND cc.fund_id IN ({FUND_IDS})
  AND cc.investor_id IN ({INVESTOR_IDS})
  AND cc.deleted_at IS NULL
  AND f.deleted_at IS NULL
ORDER BY f.name, cc.commitment_date
```

### Q: "When did I sign up for each fund, and for how much?"

```sql
SELECT f.name AS fund_name,
       f.currency,
       cc.commitment_date,
       cc.committed_amount_cents / 100 AS committed,
       cc.fund_close,
       cc.percentage AS share_pct
FROM capital_commitments cc
JOIN funds f ON f.id = cc.fund_id
WHERE cc.entity_id IN ({ENTITY_ID})
  AND cc.fund_id IN ({FUND_IDS})
  AND cc.investor_id IN ({INVESTOR_IDS})
  AND cc.deleted_at IS NULL
  AND f.deleted_at IS NULL
ORDER BY cc.commitment_date DESC
```

### Q: "My net cash position per fund (money in vs. money out)"

```sql
SELECT f.name AS fund_name,
       f.currency,
       SUM(cc.collected_amount_cents) / 100       AS paid_in,
       SUM(cc.distribution_amount_cents) / 100    AS received,
       (SUM(cc.collected_amount_cents) - SUM(cc.distribution_amount_cents)) / 100 AS net_outlay
FROM capital_commitments cc
JOIN funds f ON f.id = cc.fund_id
WHERE cc.entity_id IN ({ENTITY_ID})
  AND cc.fund_id IN ({FUND_IDS})
  AND cc.investor_id IN ({INVESTOR_IDS})
  AND cc.deleted_at IS NULL
  AND f.deleted_at IS NULL
GROUP BY f.id, f.name, f.currency
ORDER BY f.name
```

## Anti-patterns to Avoid

| Bad | Why | Fix |
|-----|-----|-----|
| Returning raw `*_cents` values | User sees "5000000000" instead of "5,000,000.00" | Always divide by 100 |
| Mixing fund currency across rows | Summing USD + INR is meaningless | Group by `f.currency` or filter to one fund |
| Omitting `investor_id IN ({INVESTOR_IDS})` | Tool will reject the query — investor scope required | Include the placeholder |
| Using `committed_amount_cents` when user asks "in my currency" | Fund currency ≠ folio currency | Use `folio_committed_amount_cents` + `folio_currency` |
| Treating each row as a separate commitment | One LP may have several folios per fund | `SUM()` and `GROUP BY fund_id` for totals |
| Forgetting `deleted_at IS NULL` on both `cc` and `f` | Returns soft-deleted rows | Filter both tables |

## When to Use Other Skills

- **Per-call / drawdown notice details, arrears per call, payment dates** → `capital_calls` skill
- **Distribution history, how much received when** → `distributions` skill
- **Performance metrics (TVPI, DPI, IRR)** → `fund_ratios` skill
- **Portfolio companies the fund invested in** → `portfolio` skill
