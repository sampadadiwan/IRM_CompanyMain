
---
name: capital_calls
description: Drawdown notices and the LP's share of each call — what was called, when, what the LP paid, what's still outstanding per call. Always scoped to the LP's own remittance slice; never exposes other LPs' amounts.
tables:
  - capital_calls
  - capital_remittances
  - capital_remittance_payments
  - capital_commitments
  - funds
---

# Capital Calls (LP-scoped via remittances)

A `capital_calls` row is a fund-wide drawdown event (e.g. "Call #3, 15% of commitments, due 2025-02-01"). Each LP's *share* of that call is a `capital_remittances` row, and the LP's payments against a remittance are `capital_remittance_payments` rows.

**Never query `capital_calls` alone.** Always join to `capital_remittances` and filter by `investor_id IN ({INVESTOR_IDS})` so the LP sees only their own slice.

## Table: capital_calls (fund-level — join only)

| Column | Type | Description |
|--------|------|-------------|
| id | bigint | Primary key |
| entity_id | bigint | Scope |
| fund_id | bigint | Scope |
| call_date | date | Date of the call notice |
| due_date | date | LP payment due date |
| name | varchar | Call label (e.g. "Call 3") |
| call_basis | varchar(40) | Basis of calculation |
| notes | text | Narrative / purpose of the call |
| approved | boolean | Only approved calls are sent to LPs |
| deleted_at | datetime | Soft delete |

Do NOT select `call_amount_cents`, `amount_to_be_called_cents`, or `collected_amount_cents` from `capital_calls` — those are fund-wide aggregates that include other LPs.

## Table: capital_remittances (LP's slice of a call — the main table)

| Column | Type | Description |
|--------|------|-------------|
| id | bigint | Primary key |
| entity_id | bigint | Scope |
| fund_id | bigint | Scope |
| capital_call_id | bigint | FK to `capital_calls.id` |
| capital_commitment_id | bigint | FK to `capital_commitments.id` |
| investor_id | bigint | FK to investors — **filter with `{INVESTOR_IDS}`** |
| call_amount_cents | decimal | Amount called from THIS LP on THIS call |
| collected_amount_cents | decimal | Amount THIS LP has paid against this call |
| arrear_amount_cents | decimal | Amount still outstanding (called − collected) |
| capital_fee_cents | decimal | Management fee portion of this call |
| other_fee_cents | decimal | Other fees |
| committed_amount_cents | decimal | LP's commitment snapshot at time of call |
| folio_call_amount_cents | decimal | LP-currency view |
| folio_collected_amount_cents | decimal | LP-currency view |
| folio_id | varchar(40) | Folio |
| remittance_date | date | When the remittance was generated |
| payment_date | date | When the LP actually paid (if paid) |
| status | varchar(10) | Payment status |
| percentage | decimal | LP's share of this call |
| deleted_at | datetime | Soft delete |

## Table: capital_remittance_payments (individual payment records)

| Column | Type | Description |
|--------|------|-------------|
| id | bigint | Primary key |
| entity_id | bigint | Scope |
| fund_id | bigint | Scope |
| capital_remittance_id | bigint | FK to `capital_remittances.id` |
| investor_id | bigint | FK to investors |
| amount_cents | decimal | Payment amount |
| payment_date | date | Payment date |
| reference_no | varchar(40) | Bank reference / txn id |
| folio_amount_cents | decimal | LP-currency view |
| deleted_at | datetime | Soft delete |

## CRITICAL Rules — ALWAYS Apply

1. **Always filter by entity, fund, AND investor on `capital_remittances` (alias `cr`):**
   ```
   WHERE cr.entity_id IN ({ENTITY_ID})
     AND cr.fund_id IN ({FUND_IDS})
     AND cr.investor_id IN ({INVESTOR_IDS})
   ```

2. **Only show approved calls** unless the LP explicitly asks about pending/draft:
   ```
   AND cal.approved = true
   ```

3. **Soft deletes** — filter `deleted_at IS NULL` on every joined table.

4. **Divide `*_cents` by 100** for display. Fund currency from `funds.currency`; LP currency from `cc.folio_currency` (via `capital_commitments`).

5. **Never expose fund-level aggregates** — do not select raw `capital_calls.call_amount_cents`, `capital_calls.amount_to_be_called_cents`, or `capital_calls.collected_amount_cents`. Those include every LP.

## Example Queries

### Q: "Show me all capital calls on my funds"

```sql
SELECT f.name AS fund_name,
       f.currency,
       cal.name AS call_name,
       cal.call_date,
       cal.due_date,
       cr.call_amount_cents / 100     AS my_called,
       cr.collected_amount_cents / 100 AS my_paid,
       cr.arrear_amount_cents / 100   AS my_outstanding,
       cr.status
FROM capital_remittances cr
JOIN capital_calls cal ON cal.id = cr.capital_call_id
JOIN funds f           ON f.id  = cr.fund_id
WHERE cr.entity_id IN ({ENTITY_ID})
  AND cr.fund_id IN ({FUND_IDS})
  AND cr.investor_id IN ({INVESTOR_IDS})
  AND cal.approved = true
  AND cr.deleted_at IS NULL
  AND cal.deleted_at IS NULL
  AND f.deleted_at IS NULL
ORDER BY cal.call_date DESC
LIMIT 50
```

### Q: "What do I owe right now across all calls?"

```sql
SELECT f.name AS fund_name,
       f.currency,
       SUM(cr.arrear_amount_cents) / 100 AS total_outstanding
FROM capital_remittances cr
JOIN funds f ON f.id = cr.fund_id
WHERE cr.entity_id IN ({ENTITY_ID})
  AND cr.fund_id IN ({FUND_IDS})
  AND cr.investor_id IN ({INVESTOR_IDS})
  AND cr.arrear_amount_cents > 0
  AND cr.deleted_at IS NULL
  AND f.deleted_at IS NULL
GROUP BY f.id, f.name, f.currency
ORDER BY total_outstanding DESC
```

### Q: "Show me the details of the most recent call on Growth Fund"

```sql
SELECT f.name AS fund_name,
       cal.name AS call_name,
       cal.call_date,
       cal.due_date,
       cal.notes,
       cr.call_amount_cents / 100      AS my_called,
       cr.capital_fee_cents / 100      AS fee,
       cr.other_fee_cents / 100        AS other_fee,
       cr.collected_amount_cents / 100 AS my_paid,
       cr.arrear_amount_cents / 100    AS my_outstanding,
       cr.payment_date,
       cr.status
FROM capital_remittances cr
JOIN capital_calls cal ON cal.id = cr.capital_call_id
JOIN funds f           ON f.id  = cr.fund_id
WHERE cr.entity_id IN ({ENTITY_ID})
  AND cr.fund_id IN ({FUND_IDS})
  AND cr.investor_id IN ({INVESTOR_IDS})
  AND f.name LIKE '%Growth%'
  AND cal.approved = true
  AND cr.deleted_at IS NULL
  AND cal.deleted_at IS NULL
  AND f.deleted_at IS NULL
ORDER BY cal.call_date DESC
LIMIT 1
```

### Q: "What's my payment history — every payment I've made?"

```sql
SELECT f.name AS fund_name,
       f.currency,
       cal.name AS call_name,
       crp.payment_date,
       crp.amount_cents / 100 AS amount,
       crp.reference_no
FROM capital_remittance_payments crp
JOIN capital_remittances cr ON cr.id = crp.capital_remittance_id
JOIN capital_calls cal      ON cal.id = cr.capital_call_id
JOIN funds f                ON f.id  = crp.fund_id
WHERE crp.entity_id IN ({ENTITY_ID})
  AND crp.fund_id IN ({FUND_IDS})
  AND crp.investor_id IN ({INVESTOR_IDS})
  AND crp.deleted_at IS NULL
  AND cr.deleted_at IS NULL
  AND cal.deleted_at IS NULL
ORDER BY crp.payment_date DESC
LIMIT 50
```

### Q: "Which calls are still unpaid / upcoming?"

```sql
SELECT f.name AS fund_name,
       f.currency,
       cal.name AS call_name,
       cal.due_date,
       cr.arrear_amount_cents / 100 AS outstanding,
       cr.status
FROM capital_remittances cr
JOIN capital_calls cal ON cal.id = cr.capital_call_id
JOIN funds f           ON f.id  = cr.fund_id
WHERE cr.entity_id IN ({ENTITY_ID})
  AND cr.fund_id IN ({FUND_IDS})
  AND cr.investor_id IN ({INVESTOR_IDS})
  AND cr.arrear_amount_cents > 0
  AND cal.approved = true
  AND cr.deleted_at IS NULL
  AND cal.deleted_at IS NULL
  AND f.deleted_at IS NULL
ORDER BY cal.due_date ASC
```

### Q: "Total fees I've been charged through calls"

```sql
SELECT f.name AS fund_name,
       f.currency,
       SUM(cr.capital_fee_cents) / 100 AS management_fees,
       SUM(cr.other_fee_cents) / 100   AS other_fees
FROM capital_remittances cr
JOIN capital_calls cal ON cal.id = cr.capital_call_id
JOIN funds f           ON f.id  = cr.fund_id
WHERE cr.entity_id IN ({ENTITY_ID})
  AND cr.fund_id IN ({FUND_IDS})
  AND cr.investor_id IN ({INVESTOR_IDS})
  AND cal.approved = true
  AND cr.deleted_at IS NULL
  AND cal.deleted_at IS NULL
  AND f.deleted_at IS NULL
GROUP BY f.id, f.name, f.currency
ORDER BY f.name
```

## Anti-patterns to Avoid

| Bad | Why | Fix |
|-----|-----|-----|
| `SELECT ... FROM capital_calls WHERE ...` without joining `capital_remittances` | Exposes fund-wide totals (other LPs' amounts) | Always start FROM `capital_remittances cr` and join to `capital_calls` |
| Omitting `cr.investor_id IN ({INVESTOR_IDS})` | Tool rejects when `{INVESTOR_IDS}` is used, AND semantically would leak other LPs | Always include it |
| Selecting `cal.call_amount_cents` | That's the fund's total for the call, not the LP's share | Select `cr.call_amount_cents` |
| Forgetting `cal.approved = true` | Shows draft/unapproved calls LPs shouldn't see | Always filter |
| Showing `_cents` values directly | User expects money, not minor units | Divide by 100 |

## When to Use Other Skills

- **Total committed / uncalled / overall drawdown %** → `commitments` skill
- **Distributions received (money back to LP)** → `distributions` skill
- **Performance metrics (TVPI, DPI, IRR)** → `fund_ratios` skill
