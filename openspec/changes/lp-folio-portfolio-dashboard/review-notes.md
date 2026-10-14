# Review notes — LP Folio Portfolio & Company Dashboard

Assumptions made while you were away, and how to review the feature by hand. Nothing here is committed.

## How to set up the demo

```
bin/rails lp_portfolio:seed_demo            # dry run: prints the plan
bin/rails lp_portfolio:seed_demo EXECUTE=1  # builds it and prints every review URL (re-run safely: it reuses what exists)
```

- Logic: `lib/tasks/support/lp_portfolio_demo.rb`. Development / staging only (refuses production).
- It creates its own fund manager, **LP Portfolio Demo Capital**, so its entity-wide LP layouts never touch a
  real fund manager. Fund: **Growth Fund I (LP demo)**, INR, view *Allocated, with their own share*.
- Logins (password `password`): fund team `meera@lp-portfolio-demo.example.com`; LPs
  `ravi@lp-portfolio-demo.example.com` (folio F-012, excused from Bluefin) and
  `priya@lp-portfolio-demo.example.com` (folios F-050 and F-051).
- Data follows business-rules.md#shared-setup: Acme (two purchases), Bluefin, Cedar (**not shared**), Paywise
  (tagged Fintech, NBFC → "LP, FinTech" layout), Fenix (Seed + Series A). Acme has a founder video, Actual KPIs
  and one Budget quarter (₹70 Cr revenue, which LPs must never see).

## Assumptions to review

| # | Assumption | Why | Alternative not taken | What you'll see / where |
|---|---|---|---|---|
| 1 | The demo creates its **own fund manager**, "LP Portfolio Demo Capital" | LP layouts apply to *every* portfolio company of a fund manager, and the demo switches companies to Show to LPs. Seeding into an existing fund manager would change what its LPs see everywhere | An `ENTITY_ID=` option to seed into an existing fund manager | You log in as the demo users (Meera, Ravi, Priya), not your usual account. `lp_portfolio_demo.rb` |
| 2 | Every demo login's password is **`password`** | Same as the existing ops demo task | A random password printed at the end | `lp_portfolio_demo.rb` |
| 3 | The demo's allocation formulas are created **disabled** | An allocation run would otherwise overwrite the hand-made folio entries the demo relies on | Enabled formulas with real formula code | Formulas show as disabled on the fund. `lp_portfolio_demo.rb#formula` |
| 4 | On an LP company page, the **Portfolio Investments widget lists only that company** | It used to show, inside the Paywise card, Priya's banner "(F-050, F-051)", totals of ₹59 Cr / ₹79 Cr and "Your totals ₹3.20 Cr". Those cover all four of her companies, so they read as Paywise's figures | Company-level totals inside the widget. The holdings card at the top already shows the company's own figures | Banner, totals and own-share note appear only on the fund's full holdings list. `aggregate_portfolio_investments/_index.html.erb` |
| 5 | LP widget content is **built with the page**, with no separate URL per widget | The internal widgets load from fund-team URLs (e.g. `/kpi_reports?…`) that show Budget figures and are closed to LPs. Building the LP versions server-side (Actual-only KPIs, the selected fund's valuations and stats) leaves no widget URL an LP could call | The design's new LP URL per widget, each re-checking access | Same page for the LP. A few small queries run up front instead of lazily (Portfolio Investments still lazy-loads through the filtered holdings list). X13 and design card ⑦ updated. `DashboardWidgetsHelper#lp_widget_partial` |
| 6 | "Which holdings can this LP see" is **worked out once per request** and reused | One page asks it many times (access check, each row, totals, company links). The app's `Current` must hold only the logged-in user, per its own header | Store it on `Current` (breaks its rule), or recompute each time (several times the queries) | No visible change; code structure only. New per-request store `LpPortfolioVisibilityCache`, cleared after every request |
| 7 | "Set up LP layout" gives its **Data Card default fields** (Category, Sector, City) | A Data Card with no fields renders empty, so a new LP layout looked broken | Leave it empty for the fund team to configure | The starter Data Card shows the three fields. `DashboardWidget::LP_STARTER_METADATA` |
| 8 | **Your Cost / FMV / Multiple sit right after the fund's FMV** column | Appended at the end, they were off-screen behind the grid's horizontal scroll | Keep them at the end of the grid | LP holdings grid. `LpOwnShareSummary.insert_columns` |
| 9 | The preview banner names the LP **in full** ("Ravi Menon") | It is the investor record's name; first names are wrong for companies or trusts that invest | First name only | Preview banner. `lp_company_dashboards/show` |
| 10 | E2/E3 test **"upload creates" and "legacy switch off/on"**, not "upload updates" | The fund upload only creates funds; it never updates one | Add update support to fund uploads | business-rules.md E2, E3 |
| 11 | The four migrations **ran on the local dev DB** (127.0.0.1:3306) | Needed for the demo to work in the browser | Leave the dev DB alone and review via screenshots only | `schema.rb` / `schema_test.rb` restored afterwards. The carry-over switched on 6 companies in dev |
| 12 | `portfolio_report.feature` now checks the **"moved to the company" notice** | It tested the retired holding preview page; its five preview-only steps were removed | Keep the preview page | `features/fund/portfolio_report.feature` |
| 13 | The holding page's **Widgets and Track Record tabs are removed** (not read-only) | Only demo accounts ever used them, and they are no longer shown to LPs | Keep them read-only with a note | The holding page has Investments, Income, Documents tabs only; records stay in the database |

## Found and fixed during the hands-on review

- The Portfolio Investments widget on an LP company page showed the LP's whole-fund banner, totals (₹59 Cr) and
  own-share note inside one company's card. Now those appear only on the full list (assumption 4).
- A syntax slip in that fix (`fund: if …`) broke the holdings list; caught by the review and fixed.
- Demo companies had no sector or city, so the Data Card showed empty rows; the demo now fills them.
- The fund form's Features moved onto its own wizard step (after Other details), with iOS toggles, an icon, tooltip and help text per switch, and no inner blue header bar. Step 2 keeps a Save button, so a closed-ended fund can still be saved there.
- The company page's LP actions are one **LPs menu**: its label shows the state (Visible to LPs / Not shared with
  LPs), and it holds Show or Hide from LPs plus Preview as LP… (moved out of Misc). View Notes and Add Note are
  one **Notes** menu.
- **Module gates.** Without the fund-portfolios module, the Features step hides LP portfolio view and Portfolio
  valuations (stored values kept, as for market data), and the LPs menu, LP notices, LP layout setup and the LP page
  are gone. Without the KPI module, KPI widgets are not offered in LP layouts and are skipped on LP pages, so a layout
  set up before the module was removed stops showing them (E95–E97, X20, X21).
