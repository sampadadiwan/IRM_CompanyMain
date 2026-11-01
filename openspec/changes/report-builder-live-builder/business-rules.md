# Report Builder with live preview, and a reworked guided wizard — Business rules and worked examples

> **Companion to:** [Design](design.md) · [Proposal](proposal.md) · [Spec](specs/)
> Each row is exactly one Cucumber scenario, tagged `# <ID> — <Happy path|Edge case|Error case>: …`. Feature paths are under `features/core/report_builder/`.

**ID legend:** **H** = Happy path · **E** = Edge case · **X** = Error (exception) case.

## Shared setup

The Phase 1 "Acme" fixture (`features/step_definitions/report_builder_trust_steps.rb`), plus extras named per row.

| Record | Name | Key data |
|---|---|---|
| Entity, users | Acme Capital; Meera (edit), Omar (Beta Partners) | As Phase 1 |
| Funds | Growth Fund II (INR), Global Fund (USD) | |
| Investors | Aditi Rao (LP), Kiran Mehta (LP), Zeta Holdings (Co-Investor), Nova LP (LP) | Nova has no commitments |
| Commitments | C1–C4 as Phase 1 | C4 is in Global Fund (USD) |
| Report "LPs" | Investor; capital commitments filtered to GF2; Stakeholder, Category | As Phase 1 |
| Extra (E8) | 31 investors with 31 different cities | Only where named |
| Extra (E17) | 21 commitments on Nova LP in GF2 with 21 different unit types | Only where named |

## Builder — Happy path

| # | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| H1 | Preview on open | Report "LPs" + Committed | Meera opens the builder | Preview shows Aditi Rao, Kiran Mehta, Zeta Holdings, Nova LP and "Total" without a click | Preview on open | editor_live |
| H2 | Change updates panel and preview | "LPs" + Committed (Sum) | Total set to Count from the builder (Turbo Stream request) | Response replaces the settings panel (Count selected) and the preview (Aditi 1) | Change updates panel and preview | editor_columns |
| H3 | Grouped column list | "LPs" | Open the builder | Columns tab has "About the investor" and "From capital commitments" with Amounts / Dates / Yes/No / Names & text groups; no field ending `_id` or `_cents` | Grouped list without internal fields | editor_columns |
| H4 | Add several | "LPs" | Add selected with Committed, Called, Commitment date | All three added in one request; Committed and Called stored `sum`, date `max` | Add several at once | editor_columns |
| H5 | Rename from the header | "LPs" + Committed | Header menu › Rename › "Total committed" | Header reads "Total committed" in the preview | Rename | editor_live |
| H6 | Move right | "LPs" (Stakeholder, Category) | Move Stakeholder right | Order: Category, Stakeholder (preview and export) | Move | editor_columns |
| H7 | Date filter | Commitment report with Folio and Commitment date | Filter Commitment date *is on or after* 01/02/2026 via the date input | Saved automatically; rows F-2, F-3, F-4 | Date filter | editor_live |
| H8 | Pick-list and fund picker | "LPs" | Open Filters tab, add a Category row and a capital commitments Fund row | Category offers LP, Co-Investor; Fund offers Global Fund, Growth Fund II | Pick-list and fund picker | editor_filters |
| H9 | Insert a column into a formula | "LPs" + Called | Formula editor › click Called | Expression contains `[capital_commitments.call_amount]` | Insert a column | editor_live |
| H10 | Formula sample results | "LPs" + Called + Committed | Validate `ROUND([capital_commitments.call_amount] / [capital_commitments.committed_amount] * 100, 2)` | ok; samples Aditi Rao 40.0, Kiran Mehta 40.0, Zeta Holdings 40.0, Nova LP blank | Sample results | editor_formulas |
| H11 | Undo a column | "LPs" + Committed (Sum) at position 3 | Remove Committed, then Undo | Committed back at position 3 with label and `sum` | Undo a column | editor_undo |
| H12 | Undo related data | "LPs" + Committed, Called, Collected + child filter | Remove capital commitments, then Undo | Join, filter and the three columns with totals restored | Undo related data | editor_undo |
| H13 | Confirmation lists columns | "LPs" + Committed, Called | Open the builder | The Remove button of capital commitments carries an Immediate Actions message naming Committed and Called | Confirmation lists columns | editor_undo |
| H14 | Health all good | "LPs" + Committed | Open the builder | Health says "All good" | All good | editor_health |
| H15 | Mixed currencies | Investor report, capital commitments **without** a fund filter, Committed (Sum) | Open the builder | Warning "Committed adds amounts in INR and USD — pick a fund or split by fund" | Mixed currencies | editor_health |
| H16 | Pivot preview | Investor report + capital commitments | Pivot preview for Unit Type × Committed | "This will create 2 columns: A, B" | Count shown | editor_pivot |
| H17 | Labels and help | "LPs" | Open the builder | Every icon-only button has an aria-label; a guide link to the Report Builder guide and a ⌘K button are present | Labels and help | editor_page |

## Builder — Edge cases

| # | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| E1 | Nothing ticked | "LPs" | Open the builder | Add selected is disabled | Nothing ticked | editor_columns |
| E2 | Already added and refused | "LPs" | Add selected with Category (already there), Committed and `capital_commitments.no_such` | Committed added; Category skipped; error names `no_such` | Already added and refused columns | editor_columns |
| E3 | Same label told apart | Aggregate Portfolio Investment | Column list | "Net bought amount" twice, each with its field hint | Same label told apart | editor_columns |
| E4 | Blank rename | "LPs" + Committed renamed "Total committed" | Rename to blank | Label back to "Committed" | Blank rename | editor_columns |
| E5 | No total on one-per-row | Commitment report with `fund.name` | Open the builder | The fund name header menu has no Total | No total on one-per-row columns | editor_columns |
| E6 | Ends | "LPs" | Open the builder | First column's Move left and last column's Move right are disabled | Ends | editor_columns |
| E7 | Large table field | Investor report + capital remittances | Filters tab, remittances Status row | Text box, no pick-list (no distinct query) | Large table field | editor_filters |
| E8 | Many values | 31 investors with different cities | Filters tab, City row | Text box | Many values | editor_filters |
| E9 | Missing value | Builder, Filters tab | Add Category row, pick *is*, leave value empty | Row says "needs a value"; nothing saved | Missing value | editor_live |
| E10 | Unreadable date | Commitment report | Type "31/31/2026" in a date filter | "Enter a date like 19/08/2026"; nothing saved | Unreadable date | editor_live |
| E11 | Invalid formula | "LPs" + Called | Validate `[capital_commitments.call_amount] /` | Not ok; error shown; no samples | Invalid expression | editor_formulas |
| E12 | Undo too late | E11-like removal | Undo 11 minutes later | Refused: "Too late to undo — removals can be undone for 10 minutes" | Too late | editor_undo |
| E13 | Undo after another change | Removed Committed | Change sort, then Undo | Refused: "Too late to undo — the report has changed since" | Changed since | editor_undo |
| E14 | Blank column warning | Template with join `capital_commitments.no_such` and its column | Open the builder | Warning "no_such name will be blank — its related data no longer exists" | Blank column | editor_health |
| E15 | Broken formula reference | Formula uses `[capital_commitments.collected_amount]`, column removed | Open the builder | Warning names the formula and the missing column | Broken formula reference | editor_health |
| E16 | Filter matches nothing | Root filter `category_eq` = "Partner" | Open the builder | Warning "No rows match Category is Partner" | Filter matches nothing | editor_health |
| E17 | Large pivot | 21 unit types on GF2 | Pivot on Unit Type | Health warning "pivot creates 22 columns"; pivot preview says "consider fewer categories" | Large pivot | editor_health |
| E18 | Large export and default totals | Export threshold stubbed to 3; legacy related column with no stored total | Open the builder | Info "Export will have 4 rows"; info "Committed uses the default total Sum" | Large export and default totals | editor_health |
| E19 | Preview error contained | Report whose engine raises | Request the preview | Error card in the preview frame; status 200 | Preview error contained | editor_page |
| E20 | Empty report | Report with no columns | Open the builder | Preview says "Tick columns on the left, then Add selected" | Empty report | editor_page |

## Builder — Error cases

| # | Scenario | Given | When | Then (what the user sees, who is alerted) | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| X1 | Undo by another entity | Meera removed a column | Omar requests the undo | Refused; nothing restored | Another entity | editor_undo |
| X2 | Pivot preview unknown field | Investor report + capital commitments | Pivot preview with value `no_such` | 422 "no_such isn't a field of capital commitments" | Unknown field | editor_pivot |
| X3 | Move with an invalid direction | "LPs" | Move request with direction `up` | 422; order unchanged | Ends | editor_columns |

## Wizard — Happy path

| # | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| H18 | Cards with examples | Meera | Open the wizard | A card per reportable table with icon and example question | Cards with examples | wizard |
| H19 | No name yet | Meera | Choose Investors | Untitled Investor report; step "show" opens | No name yet | wizard |
| H20 | Own and related together | Wizard Investor report | Add selected: investor_name, capital_commitments.committed_amount, capital_commitments.call_amount | Join added; 3 columns; both amounts `sum`; the step shows "Sum" | Own and related columns together | wizard |
| H21 | Change a total inline | H20 | Set Called to Count on step 2 | Stored `count` | Change a total inline | wizard |
| H22 | Sample beside the step | H20 | Open step 3 | Page has the 5-row sample frame | Sample beside the step | wizard |
| H23 | Fund on related data | H20 | Pick Growth Fund II | capital commitments child filter fund_id = GF2; summary "Only capital commitments in Growth Fund II" | Fund on related data | wizard |
| H24 | Sentence filters | H20 | Add Category is LP | Step shows "Only include investors where Category is LP" | Sentence filters | wizard |
| H25 | Suggestions offered | H20 + Collected | Open step 4 | Called %, Unpaid, Uncalled suggested | Suggestions offered | wizard |
| H26 | Add a suggestion | H25 | Add Called % | Formula "Called %" saved; suggestion shows Added | Add a suggestion | wizard |
| H27 | Summary and suggested name | H23 | Open step 5 | Cards present; name box "Investors — Committed, Called — Growth Fund II" | Summary and suggested name | wizard |
| H28 | Card opens its step | H27 | Follow the Only include card | Step 3 | Card opens its step | wizard |
| H29 | Save and open | H27 | Save and open with the suggested name | Report renamed; redirected to its report page | Save and open | wizard |
| H30 | Fine-tune | H27 | Fine-tune in builder | Builder opens | Fine-tune | wizard |

## Wizard — Edge cases

| # | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| E21 | Many related sources | Exchange Rate wizard report (documents, leg 1, leg 2) | Step 2 | Only "About the exchange rate" starts open; the related sources are listed closed below it | Many related sources | wizard |
| E22 | All funds | H23 | Pick All funds | Fund filter removed | All funds | wizard |
| E23 | No fund | Exchange Rate wizard report | Step 3 | No fund picker | No fund | wizard |
| E24 | Nothing to suggest | Wizard Investor report with Stakeholder only | Step 4 | "No suggestions for these columns" | Nothing to suggest | wizard |
| E25 | Blank name | H27 | Save and open with a blank name | Suggested name used | Blank name | wizard |
| E26 | Old links | Wizard report | Open old steps columns, joins, aggregates, filters, sort, review | Redirected to show, show, show, fund_filters, order, check | Old link | wizard |

## Wizard — Error cases

| # | Scenario | Given | When | Then (what the user sees, who is alerted) | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| X4 | Unknown table | Meera | Create a wizard report for "NotAModel" | Back to step 1 with "Choose one of the listed tables"; no report created | Unknown table | wizard |
| X5 | Another entity | Wizard report of Acme | Omar opens its step 2 | Refused | Another entity | wizard |

## Wizard restored

**2026-11-01 — the five-step guided setup (WZ1–WZ8; worked examples H18–H30, E21–E26, X4, X5 above) was reverted.** In hands-on use it was harder to use than the original wizard: two cramped columns, a full-page reload on every change, and less guidance. The original wizard (Columns → Related Data → Summarize → Filters → Sort → Review, with its help boxes, icons and styling) is back, unchanged apart from four fixes. The builder rows of this change (H1–H17, E1–E20, X1–X3) stand. The five-step rows above are kept for history only; their scenarios were removed with it.

| # | Scenario | Given | When | Then | Feature |
|---|---|---|---|---|---|
| R1 | Every table has an example question | The first page | Look at the table list | Every table has an example question (the original had 7 of 18) | wizard |
| R2 | One name everywhere | A wizard report | Open a step | "Guided setup" and "Open in builder"; never "Guided Report Wizard" or "Advanced Builder" | wizard |
| R3 | The Summarize total is the saved total | Investor report with capital commitments | Add Committed on Summarize | The picker shows Sum, and Sum is stored (it was shown but never stored, so the column was blank — W1) | wizard |
| R4 | Open My Report opens the report page | A wizard report | Review | "Open My Report" links to the report page, not the builder (W11) | wizard |
