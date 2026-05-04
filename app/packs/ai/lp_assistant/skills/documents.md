---
name: documents
description: Any document question an LP may ask — Statement of Account (SOA / quarterly statement), drawdown notice / capital call letter, distribution notice / payment advice, fund data room docs (LPA, PPM, side letter, subscription agreement), quarterly / annual fund reports, or general "what documents do I have / recent documents" browsing. Covers all LP-visible documents across owner types.
tables:
  - documents
  - folders
  - capital_commitments
  - capital_calls
  - capital_distributions
  - funds
---

# Documents (Unified)

Caphive stores every LP-visible document in a single polymorphic `documents` table. The `owner_type` column indicates what the document is attached to (`Fund`, `CapitalCommitment`, `CapitalCall`, `CapitalDistribution`, …). Each recognisable document type the LP asks about corresponds to a specific filter signature over this table. This skill covers all of them.

**Response always ends with the same 2-tool chain:** `run_query` → `document_url(document_id)` per row → Markdown link in the reply.

---

## Why these rules exist (read first)

Multiple LPs share funds. Each LP receives **their own** Statement of Account, distribution payment advice, and (sometimes) call notice — these documents live in the **same folder** of the **same fund** and differ only by which `CapitalCommitment` / `CapitalDistributionPayment` they're attached to. The rules below are the only thing keeping LP-A from seeing LP-B's documents in a fund both invest in:

- `cc.investor_id IN ({INVESTOR_IDS})` is **non-negotiable** for any query joining `capital_commitments`. Drop it and you leak another LP's SOA.
- `d.entity_id IN ({ENTITY_ID})` is the cross-tenant guard. Drop it and you leak across FMs.
- `cc.fund_id IN ({FUND_IDS})` is the cross-fund guard. Drop it and you leak funds the LP isn't invested in.

`DocumentUrlTool` performs the same checks again server-side as a second line of defence, but you must still write the SQL correctly — a missing filter here means we return an unaccessible `document_id` to the LLM, which the LLM may surface in error text (e.g. "I found document 7566 but cannot open it"). That leaks the **existence** of the other LP's document even when the URL itself is blocked. Don't.

---

## Universal Rules — Apply to EVERY Query

1. **Three-axis scoping is mandatory**:
   ```
   WHERE d.entity_id IN ({ENTITY_ID})
     AND cc.fund_id IN ({FUND_IDS})           -- when joining capital_commitments
     AND cc.investor_id IN ({INVESTOR_IDS})   -- when joining capital_commitments
   ```
   For `owner_type='Fund'` (data room / fund reports) the join is via `funds.id IN ({FUND_IDS})` instead.

2. **Exclude soft-deleted rows on EVERY joined table**:
   ```
   AND d.deleted_at IS NULL
   AND f.deleted_at IS NULL        -- folders
   AND cc.deleted_at IS NULL       -- capital_commitments (when joined)
   AND fund.deleted_at IS NULL     -- funds (when joined)
   ```

3. **Always** `AND d.template = false` — never return SOA Templates, CC Templates, etc.

4. **Never SELECT `d.file_data`** — it is a Shrine JSON blob, unusable by the LLM. Return `d.id AS document_id`, `d.name`, `d.created_at`, and fund name.

5. **"Latest" = max `d.created_at`** — use `ORDER BY d.created_at DESC LIMIT 1`. Do not guess from the document name.

6. **Always return `document_id`** (`SELECT d.id AS document_id`) so you can chain into `document_url`.

7. **When the LP doesn't name a fund**, do not filter on fund name — return across all their funds and include fund name in the output so the LP can tell which one each doc belongs to.

---

## Document Type Catalogue

| # | Type | `owner_type` | Extra filter signature | Typical LP question |
|---|------|--------------|------------------------|---------------------|
| 1 | **SOA / Statement of Account** | `CapitalCommitment` | `owner_tag='Generated'` AND `approved=true` AND folder name = `'Investor Statements'` | "my last SOA", "quarterly statement", "latest statement" |
| 2 | **Drawdown / Capital Call Notice** | `CapitalCall` | folder path contains `/Capital Calls/` | "drawdown notice", "capital call letter", "Q3 call notice" |
| 3 | **Distribution Notice / Payment Advice** | `CapitalDistribution` OR `CapitalDistributionPayment` | folder path contains `/Capital Distributions/` | "distribution notice", "payout advice" |
| 4 | **Fund Data Room** | `Fund` | folder is descendant of `funds.data_room_folder_id` (i.e. `f.full_path LIKE '/Funds/<fund_name>/Data Room%'`) | "the LPA", "PPM", "side letter", "subscription agreement" |
| 5 | **Fund Report / Update** | `Fund` | folder is NOT under Data Room; name often matches `%Report%` / `%Update%` / `%Newsletter%` | "Q2 fund update", "annual report" |
| 6 | **Any / Recent / Unified** | any of the above | no `owner_type` filter; union of LP-visible rows | "what documents do I have?", "recent documents" |

**Which pattern to pick?** Match the LP's phrasing to row 1–5 first. If ambiguous ("show me my documents", "anything new?"), use pattern 6.

---

## Tables

### `documents`

| Column | Type | Description |
|--------|------|-------------|
| id | bigint | Primary key → return as `document_id` |
| entity_id | bigint | FK to entities (FM tenant). Always required for scoping. |
| folder_id | bigint | FK to folders. Join to distinguish Data Room vs Capital Calls vs Investor Statements etc. |
| owner_type | varchar | Polymorphic owner class (`Fund`, `CapitalCommitment`, `CapitalCall`, `CapitalDistribution`, `CapitalDistributionPayment`, …) |
| owner_id | bigint | Polymorphic owner id |
| name | varchar | Document name (free text, e.g. "SOA - Q4 2025", "Drawdown Notice Call-3", "LPA v2") |
| owner_tag | varchar | `'Generated'` for generator-produced docs; other values for uploads; may be NULL |
| approved | boolean | TRUE if FM has released it to LPs. Required for generated docs; non-generated uploads may have it NULL/false — see pattern-specific notes. |
| template | boolean | TRUE for blueprints — **ALWAYS filter `= false`** |
| file_data | text | Shrine JSON — **do NOT SELECT** |
| created_at | datetime | When the doc was produced — use for "latest" |
| updated_at | datetime | Last modification |
| deleted_at | datetime | Soft-delete — **ALWAYS filter `IS NULL`** |

### `folders`

| Column | Type | Description |
|--------|------|-------------|
| id | bigint | Primary key |
| entity_id | bigint | FK to entities |
| name | varchar | Last segment, e.g. `'Data Room'`, `'Investor Statements'`, `'Capital Calls'` |
| full_path | varchar | Full path, e.g. `'/Funds/Growth Fund/Data Room'` — **use this for subtree matching with LIKE** |
| owner_type | varchar | Usually matches the document's owner_type |
| owner_id | bigint | |
| deleted_at | datetime | Soft-delete |

Folders use the `ancestry` gem but `full_path` is kept in sync, so path-prefix `LIKE` is the simplest way to express "descendant of this folder".

### `capital_commitments` (joined when `owner_type='CapitalCommitment'`)

| Column | Description |
|--------|-------------|
| id | Matches `documents.owner_id` when `owner_type='CapitalCommitment'` |
| entity_id | |
| fund_id | Filter by `IN ({FUND_IDS})` |
| investor_id | **Filter by `IN ({INVESTOR_IDS})`** — ties the SOA to the LP |
| deleted_at | Soft-delete |

### `capital_calls` (joined when `owner_type='CapitalCall'`)

| Column | Description |
|--------|-------------|
| id | Matches `documents.owner_id` when `owner_type='CapitalCall'` |
| fund_id | Filter by `IN ({FUND_IDS})` |
| name | Call name/number (e.g. "Call-3") |
| deleted_at | Soft-delete |

### `capital_distributions` (joined when `owner_type='CapitalDistribution'`)

| Column | Description |
|--------|-------------|
| id | Matches `documents.owner_id` when `owner_type='CapitalDistribution'` |
| fund_id | Filter by `IN ({FUND_IDS})` |
| title | Distribution title |
| deleted_at | Soft-delete |

### `funds`

| Column | Description |
|--------|-------------|
| id | Matches `documents.owner_id` when `owner_type='Fund'` |
| name | Fund name |
| data_room_folder_id | Root folder id of this fund's Data Room subtree |
| currency | Fund currency |
| deleted_at | Soft-delete |

---

## Pattern 1 — SOA (Statement of Account)

**Filter signature** (the five markers — do not omit any):
```
AND d.owner_type = 'CapitalCommitment'
AND d.owner_tag  = 'Generated'
AND d.approved   = true
AND d.template   = false
AND f.name       = 'Investor Statements'
```

### Q: "Give me my last Statement of Account"

```sql
SELECT
  d.id         AS document_id,
  d.name       AS doc_name,
  fund.name    AS fund_name,
  d.created_at AS issued_at
FROM documents d
JOIN folders f              ON f.id = d.folder_id
JOIN capital_commitments cc ON cc.id = d.owner_id
JOIN funds fund             ON fund.id = cc.fund_id
WHERE d.entity_id IN ({ENTITY_ID})
  AND cc.fund_id IN ({FUND_IDS})
  AND cc.investor_id IN ({INVESTOR_IDS})
  AND d.owner_type = 'CapitalCommitment'
  AND d.owner_tag  = 'Generated'
  AND d.approved   = true
  AND d.template   = false
  AND f.name       = 'Investor Statements'
  AND d.deleted_at IS NULL
  AND f.deleted_at IS NULL
  AND cc.deleted_at IS NULL
  AND fund.deleted_at IS NULL
ORDER BY d.created_at DESC
LIMIT 1
```

### Q: "Show me all my statements" / "List my SOAs"
Same as above, remove the `LIMIT 1`.

### Q: "Give me the last SOA for Growth Fund"
Add `AND fund.name LIKE '%Growth%'` before the `ORDER BY`.

### Q: "How many SOAs did I get from Growth Fund this year?"
Use `COUNT(*)` with `YEAR(d.created_at) = YEAR(CURDATE())` and `GROUP BY fund.id, fund.name`.

---

## Pattern 2 — Drawdown / Capital Call Notice

**Filter signature**:
```
AND d.owner_type = 'CapitalCall'
AND d.template   = false
AND f.full_path LIKE CONCAT('/Funds/', fund.name, '/Capital Calls/%')
-- Approved generated notices + user-uploaded supporting docs
AND ( (d.owner_tag = 'Generated' AND d.approved = true)
      OR d.owner_tag <> 'Generated'
      OR d.owner_tag IS NULL )
```

### Q: "Give me the latest drawdown notice"

```sql
SELECT
  d.id         AS document_id,
  d.name       AS doc_name,
  fund.name    AS fund_name,
  cap_call.name    AS call_name,
  d.created_at AS issued_at
FROM documents d
JOIN folders f          ON f.id = d.folder_id
JOIN capital_calls cap_call ON cap_call.id = d.owner_id
JOIN funds fund         ON fund.id = cap_call.fund_id
WHERE d.entity_id IN ({ENTITY_ID})
  AND cap_call.fund_id IN ({FUND_IDS})
  AND d.owner_type = 'CapitalCall'
  AND d.template   = false
  AND ( (d.owner_tag = 'Generated' AND d.approved = true)
        OR d.owner_tag <> 'Generated'
        OR d.owner_tag IS NULL )
  AND d.deleted_at    IS NULL
  AND f.deleted_at    IS NULL
  AND cap_call.deleted_at IS NULL
  AND fund.deleted_at IS NULL
ORDER BY d.created_at DESC
LIMIT 1
```

Note: the LP must have a commitment in the fund to see the call — `{FUND_IDS}` is already constrained to funds the LP is invested in, so that scoping is implicit.

---

## Pattern 3 — Distribution Notice / Payment Advice

**Filter signature**:
```
AND d.owner_type IN ('CapitalDistribution', 'CapitalDistributionPayment')
AND d.template   = false
AND ( (d.owner_tag = 'Generated' AND d.approved = true)
      OR d.owner_tag <> 'Generated'
      OR d.owner_tag IS NULL )
```

### Q: "Give me my latest distribution notice"

```sql
SELECT
  d.id         AS document_id,
  d.name       AS doc_name,
  fund.name    AS fund_name,
  d.created_at AS issued_at
FROM documents d
JOIN folders f                ON f.id = d.folder_id
JOIN capital_distributions cd ON cd.id = d.owner_id AND d.owner_type = 'CapitalDistribution'
JOIN funds fund               ON fund.id = cd.fund_id
WHERE d.entity_id IN ({ENTITY_ID})
  AND cd.fund_id IN ({FUND_IDS})
  AND d.owner_type = 'CapitalDistribution'
  AND d.template   = false
  AND ( (d.owner_tag = 'Generated' AND d.approved = true)
        OR d.owner_tag <> 'Generated'
        OR d.owner_tag IS NULL )
  AND d.deleted_at    IS NULL
  AND f.deleted_at    IS NULL
  AND cd.deleted_at   IS NULL
  AND fund.deleted_at IS NULL
ORDER BY d.created_at DESC
LIMIT 1
```

(For payment-level advices use `owner_type = 'CapitalDistributionPayment'` and join `capital_distribution_payments` → `capital_distributions` → `funds`.)

---

## Pattern 4 — Fund Data Room

Data Room is the fund-level document library (LPA, PPM, side letters, subscription agreements, fund reports filed here by FM). Each fund has one Data Room folder: `funds.data_room_folder_id`. Sub-folders may exist beneath it.

**Filter signature**:
```
AND d.owner_type = 'Fund'
AND d.template   = false
AND f.full_path LIKE CONCAT('/Funds/', fund.name, '/Data Room%')
AND ( (d.owner_tag = 'Generated' AND d.approved = true)
      OR d.owner_tag <> 'Generated'
      OR d.owner_tag IS NULL )
```

### Q: "Show me the LPA for Growth Fund"

```sql
SELECT
  d.id         AS document_id,
  d.name       AS doc_name,
  fund.name    AS fund_name,
  d.created_at AS issued_at
FROM documents d
JOIN folders f ON f.id = d.folder_id
JOIN funds fund ON fund.id = d.owner_id AND d.owner_type = 'Fund'
WHERE d.entity_id IN ({ENTITY_ID})
  AND fund.id IN ({FUND_IDS})
  AND fund.name LIKE '%Growth%'
  AND d.owner_type = 'Fund'
  AND d.template   = false
  AND f.full_path LIKE CONCAT('/Funds/', fund.name, '/Data Room%')
  AND d.name LIKE '%LPA%'
  AND ( (d.owner_tag = 'Generated' AND d.approved = true)
        OR d.owner_tag <> 'Generated'
        OR d.owner_tag IS NULL )
  AND d.deleted_at    IS NULL
  AND f.deleted_at    IS NULL
  AND fund.deleted_at IS NULL
ORDER BY d.created_at DESC
LIMIT 5
```

### Q: "List all data room documents for Growth Fund"
Drop the `AND d.name LIKE '%LPA%'` filter; keep the rest.

---

## Pattern 5 — Fund Report / Update (fund-level, outside Data Room)

Some FMs store quarterly reports / newsletters outside the Data Room subtree. Same `owner_type='Fund'` but folder path is not under `/Data Room`.

**Filter signature**:
```
AND d.owner_type = 'Fund'
AND d.template   = false
AND f.full_path NOT LIKE CONCAT('/Funds/', fund.name, '/Data Room%')
AND (d.name LIKE '%Report%' OR d.name LIKE '%Update%' OR d.name LIKE '%Newsletter%' OR f.name LIKE '%Report%')
```

If unsure whether a doc is a "report" or a "data room" item, run Pattern 4 and Pattern 5 as a `UNION ALL` and let the LP see both.

---

## Pattern 6 — Recent / Unified ("what docs do I have?")

Mirrors the dashboard's Recent Documents card — union across owner types. Use when the LP asks without naming a type.

```sql
SELECT
  d.id         AS document_id,
  d.name       AS doc_name,
  d.owner_type AS doc_type,
  fund.name    AS fund_name,
  d.created_at AS issued_at
FROM documents d
JOIN folders f ON f.id = d.folder_id
LEFT JOIN capital_commitments cc
       ON cc.id = d.owner_id AND d.owner_type = 'CapitalCommitment'
LEFT JOIN capital_calls cap_call
       ON cap_call.id = d.owner_id AND d.owner_type = 'CapitalCall'
LEFT JOIN capital_distributions cd
       ON cd.id = d.owner_id AND d.owner_type = 'CapitalDistribution'
LEFT JOIN funds fund
       ON fund.id = COALESCE(cc.fund_id, cap_call.fund_id, cd.fund_id,
                             CASE WHEN d.owner_type = 'Fund' THEN d.owner_id END)
WHERE d.entity_id IN ({ENTITY_ID})
  AND d.template = false
  AND fund.id IN ({FUND_IDS})
  AND (
        -- SOA-style: per-commitment, only this LP's
        (d.owner_type = 'CapitalCommitment'
          AND cc.investor_id IN ({INVESTOR_IDS})
          AND d.owner_tag = 'Generated' AND d.approved = true)
        -- Call / Distribution / Fund docs: LP-visible because the fund is in {FUND_IDS}
     OR (d.owner_type IN ('CapitalCall','CapitalDistribution','Fund')
          AND ( (d.owner_tag = 'Generated' AND d.approved = true)
                OR d.owner_tag <> 'Generated'
                OR d.owner_tag IS NULL ))
      )
  AND d.deleted_at    IS NULL
  AND f.deleted_at    IS NULL
  AND fund.deleted_at IS NULL
ORDER BY d.created_at DESC
LIMIT 10
```

---

## Response Formatting — 2-Tool Chain (applies to every pattern)

After `run_query` returns rows, **for each `document_id`** call the `document_url` tool to get a short-lived signed URL, then embed it in a Markdown link.

**Tool chain:**
1. `run_query(sql)` → rows including `document_id`
2. For each `document_id` → `document_url(document_id: N)` → signed URL string
3. Reply in Markdown using `[<doc_name>](<url>)`

**Example — single doc:**

> Your most recent Statement of Account is **[SOA - Q4 2025](https://s3.amazonaws.com/...)** for **Growth Fund**, issued **15 Jan 2026**. Click the link to open the PDF.

**Example — multiple docs (mixed types):**

- NEVER render document links as a Markdown table. Always use a bulleted list — one document per `- [name](url) — meta` line. Tables break inline link parsing for long presigned S3 URLs (the link renders as raw `[text](url)` text instead of a clickable anchor). This applies even if the LP asks for a "table" or "better visualization" — explain in prose, list with bullets.


> Your recent documents:
> - [SOA - Q4 2025](<url_1>) — Statement · Growth Fund · 15 Jan 2026
> - [Drawdown Notice Call-3](<url_2>) — Capital Call · Growth Fund · 10 Jan 2026
> - [Q4 2025 Fund Update](<url_3>) — Fund Report · Growth Fund · 05 Jan 2026

**Rules:**
- Always call `document_url` for every `document_id`. Never fabricate URLs, never use `/documents/<id>` paths, never reference `file_data`.
- Use `d.name` as the link text.
- If `document_url` errors ("Document not found", "no file attached"), surface that — don't hide it.
- If `run_query` returns zero rows, say so honestly: "I couldn't find any <type> for you in the system yet."
- Signed URLs expire (~1 hour). On a repeat ask, regenerate by running the chain again.

---

## Anti-patterns to Avoid

| Bad | Why | Fix |
|-----|-----|-----|
| Omitting `{INVESTOR_IDS}` on Pattern 1 (SOA) | Returns other LPs' SOAs in shared funds | Always filter `cc.investor_id IN ({INVESTOR_IDS})` |
| Filtering only by `name LIKE '%SOA%'` | Misses SOAs named "Quarterly Statement …"; catches unrelated docs | Use the five-marker signature, not the name |
| `template = true` | Returns blueprints, not real docs | Always `template = false` |
| Omitting `approved = true` on generated docs | May show FM drafts | Always include the approved-if-generated clause |
| SELECTing `file_data` | Opaque Shrine JSON | SELECT only `id`, `name`, `created_at`, `fund_name`, `owner_type` |
| Sorting by `d.name` to find "latest" | Names are free-text, not chronological | `ORDER BY d.created_at DESC` |
| Case-mismatching folder name (`'investor statements'`) | Zero rows | Use exact `'Investor Statements'`, `'Data Room'`, `'Capital Calls'`, `'Capital Distributions'` |
| Confusing `funds.data_room_folder_id` (LP-visible library) with `funds.document_folder_id` (FM-internal root) | Returns wrong folder subtree | Use the Data Room path (`…/Data Room%`) for Pattern 4 |
| Forgetting `deleted_at IS NULL` on joined tables | Returns rows whose parent was soft-deleted | Add `deleted_at IS NULL` to every joined table |

---

## When to Use Other Skills

- Performance metrics shown **inside** an SOA (NAV, IRR, TVPI, DPI, MOIC) → `fund_ratios` skill
- Capital call **amounts / due dates / status** (not the notice PDF) → `capital_calls` skill
- Distribution **amounts / payment dates** (not the notice PDF) → `distributions` skill
- Commitment-level numbers (committed, called, paid) → `commitments` skill
- Portfolio company data → `portfolio` skill
- Anything not about retrieving a document → pick the appropriate data skill
