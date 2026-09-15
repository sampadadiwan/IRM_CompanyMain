# Cap Table Import — UI Sign-off & Backend Contract

**Purpose:**
Provide a one-page sign-off for the UI changes in the horizontal cap table view and the backend JSON contract that `GenerateHorizontalCapTable` must return so uploaded funding-round labels like "March 2026" and "June 2026" render correctly.

**File (view):**
- [app/packs/startups/investments/views/investments/_horizontal_captable.html.erb](app/packs/startups/investments/views/investments/_horizontal_captable.html.erb)

**High-level decisions to sign off**
- **Funding rounds format:** Backend returns `funding_rounds` as an ordered array of strings (e.g., "March 2026", "June 2026"). Backend SHOULD return rounds already sorted chronologically by default. If the importer must preserve upload order, the backend will include `preserve_round_order: true` in the response.
- **Round keys consistency:** `table_data` and `round_data` MUST use the exact strings in `funding_rounds` as keys.
- **Latest round selection:** The view uses `latest_round = funding_rounds.last`. The backend must supply `funding_rounds` in the desired order (chronological or upload order depending on above decision).
- **Quantity column visibility:** The view toggles columns via request params `show_quantity_actual` and `show_quantity_diluted`. Backend may provide defaults via metadata but the view will respect params.

**JSON contract: expected `h_data` structure (example)**

```json
{
  "funding_rounds": ["March 2026", "June 2026"],
  "categories": ["Self", "Founders", "Employees", "Others"],
  "investors_by_category": {
    "Founders": [ { "investor_name": "Alice" }, { "investor_name": "Bob" } ],
    "Employees": [ { "investor_name": "Employee Pool" } ]
  },
  "table_data": {
    "Founders": {
      "Alice": {
        "March 2026": { "quantity": 1000, "fully_diluted": 1100, "fully_diluted_percentage": "10.0%" },
        "June 2026":  { "quantity": 900,  "fully_diluted": 1000, "fully_diluted_percentage": "9.1%" }
      },
      "Bob": {
        "March 2026": { "quantity": 2000, "fully_diluted": 2200, "fully_diluted_percentage": "20.0%" },
        "June 2026":  { "quantity": 1800, "fully_diluted": 2000, "fully_diluted_percentage": "18.2%" }
      }
    }
  },
  "round_data": {
    "June 2026": { "total_equity": 10000, "total_fully_diluted": 11000 }
  }
}
```

**Key fields and types (for backend devs)**
- **funding_rounds**: Array[String] — ordered labels to display as column headers.
- **categories**: Array[String] — top-level category list (e.g., "Self", "Founders").
- **investors_by_category**: Object[String => Array[{ investor_name: String }]] — investor list per category used to render rows in the same order as the array.
- **table_data**: Object[category => Object[investor_name => Object[round => { quantity: Number, fully_diluted: Number, fully_diluted_percentage: String }]]]
- **round_data**: Object[round => { total_equity: Number, total_fully_diluted: Number }]
- **Optional metadata**: `preserve_round_order` (Boolean) — when true, the UI should present rounds in upload order instead of chronological sort. Backend can include additional flags if needed.

**Behavioral expectations**
- The view will call `h_data.dig(:table_data, category, investor.investor_name, round)` for each combination. If a key is missing the UI will render `"-"` or `0` as currently coded. Backend must avoid key mismatches.
- Percentages: backend may return pre-formatted strings like "9.1%". If returning numeric values instead, update must be agreed (view currently calls `.to_f` on percentage strings in some summaries). Preferred: return formatted percentage strings for per-cell `fully_diluted_percentage` and numeric totals for `round_data`.
- Date parsing / sorting: backend should parse month-year labels reliably. Acceptable label formats: `March 2026`, `Mar 2026`, `2026-03`. If backend cannot parse, it should set `preserve_round_order: true` to avoid unintended reordering.
- Latest round: UI uses the last element of `funding_rounds` as `latest_round`; backend must ensure that is the intended latest round.
- Column visibility: `show_quantity_actual` and `show_quantity_diluted` are request params the UI respects. Backend defaults are advisory only.

**Acceptance tests (sign-off checklist)**
- [ ] Upload/return `funding_rounds` = ["March 2026", "June 2026"] and UI shows two columns labeled exactly as provided.
- [ ] Backend returns `table_data` keys matching `funding_rounds` and values render correctly for each investor.
- [ ] If backend returns `preserve_round_order: true`, UI preserves order; otherwise backend returns chronologically-sorted `funding_rounds`.
- [ ] Footer totals use `round_data[latest_round][:total_equity]` and `:total_fully_diluted` and match aggregated row sums within a small rounding tolerance.
- [ ] UI shows fallback '-' for missing per-cell data and no exceptions are raised server-side.
- [ ] Performance: view renders responsively for up to X rounds (decide X during sign-off; recommend 24 months by default).

**Edge cases & notes for Tech Lead**
- If the upload creates many monthly rounds, decide whether to cap visible columns or enable horizontal scrolling/paging.
- If source formats vary (docx), require ETL to normalize to `funding_rounds` + `table_data` before returning `h_data`.
- If the product wants full audit/versioning this doc does not mandate schema changes; the UI contract above can be implemented without new tables but risks making rollback/diffing harder. Consider implementing a small `cap_table_imports` metadata record even if rows are stored in-place.

**Next steps after sign-off**
1. Backend implements `GenerateHorizontalCapTable` contract and returns `h_data` per this doc.
2. Backend dev runs the acceptance tests above against a staging view and confirms.
3. Frontend/devops: confirm UI param `preserve_round_order` behaviour and document allowed round label formats.


---
Generated for handoff to backend & engineering; attach this file to the business requirement doc for approvals.
