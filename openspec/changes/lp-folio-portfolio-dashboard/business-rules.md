# LP Folio Portfolio & Company Dashboard — Business Rules

> **Audience:** QA, support, engineering. **Companion documents:** [Proposal](proposal.md) ·
> [Design](design.md) · [Specs](specs/)
>
> Every row is one Cucumber scenario, and every scenario carries a comment naming its ID, e.g.
> `# E12 — Edge case: a sub-unit allocation does not make a holding visible`. Code comments name the
> IDs of the paths they implement. **ID legend:** **H** = happy path · **E** = edge case · **X** =
> error (exception) case.

## Contents

- [Shared setup](#shared-setup)
- [Feature files](#feature-files)
- [Happy path](#happy-path)
- [Edge cases](#edge-cases)
  - [Fund setting (①)](#fund-setting-)
  - [Visible set (③)](#visible-set-)
  - [Own share (③)](#own-share-)
  - [LP portfolio screens (④)](#lp-portfolio-screens-)
  - [Company sharing and carry-over (⑤)](#company-sharing-and-carry-over-)
  - [LP Company Dashboard (⑥)](#lp-company-dashboard-)
  - [LP assistant and data paths (⑦)](#lp-assistant-and-data-paths-)
  - [Guidance: tooltips and info notices](#guidance-tooltips-and-info-notices---)
  - [LP layouts chosen by tags](#lp-layouts-chosen-by-tags--)
  - [Fund manager modules](#fund-manager-modules---)
- [Error cases](#error-cases)
- [Spec coverage check](#spec-coverage-check)

---

## Shared setup

Today is **14/10/2026**. Amounts are in ₹ Cr unless stated. "Entry" means a folio allocation entry
(`account_entries` row with a capital commitment and a parent).

| Record | Name | Key data |
|---|---|---|
| Fund manager | Peak Capital | Entity of every fund below |
| Fund | Growth Fund I (GF1) | INR. Holdings below. LP portfolio view varies by row (default in a row: *Allocated to their folio* with allocation formula **#501**; own-share rows also pick Your FMV **#502**) |
| Fund | Growth Fund II (GF2) | INR. Holds Acme Robotics *Series C CCPS*: cost 10.00, FMV 12.00. Formula #701 Allocated Cost (instrument level) |
| Fund | Master Fund M (MFM) | INR. Holds Echo Foods *Equity*: cost 30.00, FMV 33.00. View *Allocated to their folio* |
| Fund | Feeder Fund F (FFF) | USD, master = MFM. Own folios only. Allocation formula **#601** |
| Holding (GF1) | Acme Robotics *Series B CCPS* | 1,00,000 units, avg cost ₹2,500, cost 25.00, FMV 40.00. Two purchases: 40,000 units (10.00) and 60,000 units (15.00) |
| Holding (GF1) | Bluefin Health *Series A CCPS* | cost 20.00, FMV 22.00. Ravi's F-012 is excused |
| Holding (GF1) | Cedar Logistics *Series A CCPS* | cost 15.00, FMV 18.00 |
| Holding (GF1) | Delta AI *Seed CCPS* | Recorded 05/10/2026. No entries yet (rows add their own) |
| Holdings (GF1) | Fenix Mobility *Seed CCPS* (5.00) and *Series A CCPS* (8.00) | Ravi has no allocation to either |
| Formula (GF1) | #501 Allocated Portfolio Cost | Instrument-level allocation (`AllocatePortfolioInvestment`) |
| Formula (GF1) | #502 Allocated Portfolio FMV | Instrument-level allocation |
| Formula (GF1) | #503 Allocated Portfolio Cost Proforma | `AllocatePortfolioInvestment-Proforma` |
| Formula (GF1) | #504 Apportioned Deal Expense | Instrument-level allocation |
| Formula (GF1) | #505 Portfolio FMV by API | Aggregated-holding allocation (`AllocateAggregatePortfolios`) |
| Formula (GF1) | #506 Company Fees | Company-level folio allocation (`AllocateForPortfolioCompany-Folio`) |
| Formula (GF1) | #507 Management Fee | Not a portfolio formula (`AllocateAccountEntry-Name`) |
| Formula (FFF) | #601 Master PI Cost, #602 Master PI FMV | `AllocateMasterFundPortfolioInvestment` |
| LP | Ravi Menon | Folio **F-012** in GF1 (10%). Entries at 30/09/2026: Acme cost 2.50 (1.00 + 1.50 across the two purchases), FMV 4.00 (30/06/2026: 3.60); Cedar cost 1.50, FMV 1.80; Bluefin 0.00 on every formula |
| LP | Anita Rao | **F-031** in GF1 (allocated to Acme: cost 1.25, FMV 2.00) and **G-007** in GF2 (allocated to Acme Series C: cost 0.50, FMV 0.60) |
| LP | Priya Shah | Two folios in GF1. **F-050**: excused from Bluefin (0.00), Acme cost 1.00. **F-051**: Bluefin cost 1.00, Acme cost 0.50, Fenix *Series A* cost 0.40 (Seed 0.00) |
| LP | Sunil Kapoor | **FF-01** in FFF. #601 entry for Echo Foods: $120,000; #602: $132,000 |
| User | Omar Khan | Investor user with access to GF1, no folio in it |
| LP | Lena Fischer | LP of another fund manager (Northstar Partners). No access to any Peak Capital fund |
| User | Meera Iyer | Peak Capital fund operations: update permission on funds and portfolio companies, investor read |
| User | Kiran Das | Peak Capital employee: read-only on funds, no update on portfolio companies |
| Company switch | Show to LPs | On for Acme, Bluefin, Echo Foods. Off for Cedar, Delta, Fenix |
| Dashboard layouts | Portfolio Company Dashboard (Peak Capital) | **"LP"** layout: Data Card (Medium), Key KPIs (Medium), Valuations (XL), Embed Document "Founder Video" (XL), all enabled, untagged. **Default** layout (internal): Notes, Captable, Data Card, KPIs. Rows add "LP, FinTech" etc. where needed |
| Company tags | Portfolio companies | Acme Robotics: "Robotics". Bluefin Health: "HealthTech". Cedar Logistics: none. **Paywise Payments** (GF1 holding *Series A CCPS*, cost 6.00, FMV 9.00; switch on; Priya's F-051 allocated 0.30, Ravi 0.00): "Fintech, NBFC" |
| Documents | Acme Robotics | "Founder Video" (MP4). Acme KPIs: Actual and Budget for Q2 FY27 (Actual Revenue 62.0) |

## Feature files

| Short name | Path |
|---|---|
| view_setting | `features/funds/lp_portfolio/lp_portfolio_view_setting.feature` |
| visibility | `features/funds/lp_portfolio/lp_folio_visibility.feature` |
| own_share | `features/funds/lp_portfolio/lp_own_share.feature` |
| sharing | `features/funds/lp_portfolio/lp_company_sharing.feature` |
| company_dashboard | `features/funds/lp_portfolio/lp_company_dashboard.feature` |
| assistant | `features/ai/lp_assistant/lp_assistant_portfolio_scope.feature` |

Spec abbreviations: **V** = [lp-folio-portfolio-visibility](specs/funds/lp-folio-portfolio-visibility/spec.md),
**O** = [lp-portfolio-own-share](specs/funds/lp-portfolio-own-share/spec.md),
**C** = [lp-portfolio-company-dashboard](specs/funds/lp-portfolio-company-dashboard/spec.md).

---

## Happy path

| # | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| H1 | Whole fund view unchanged | GF1 view *Whole fund portfolio* | Ravi opens GF1 › Portfolio | Acme, Bluefin, Cedar, Delta, Fenix listed with fund cost/FMV only. No banner, no Your columns | V: Whole fund view lists every holding | visibility |
| H2 | Allocated view narrows to the folio | GF1 view *Allocated to their folio* | Ravi opens GF1 › Portfolio | Acme and Cedar only. Banner "Showing investments allocated to your folio (F-012)". Totals cost 40.00, FMV 58.00 (25 + 15, 40 + 18) | V: Excused folio does not see the holding; V: Totals add only visible holdings | visibility |
| H3 | Own share shown | GF1 view *Allocated, with their own share*, allocation formula #501, Your FMV #502 | Ravi opens GF1 › Portfolio | Acme: Your cost 2.50, Your FMV 4.00. Cedar: 1.50 / 1.80. Your totals 4.00 / 5.80, multiple 1.45x (5.80 ÷ 4.00). Note: "Your cost = "Allocated Portfolio Cost", Your FMV = "Allocated Portfolio FMV", latest reporting date 30/09/2026" | O: LP sees own cost and FMV | own_share |
| H4 | Fund team picks the view and formulas | GF1 view *Whole fund portfolio* | Meera chooses *Allocated, with their own share*, picks #501 as allocation formula and #502 for Your FMV, saves | "Fund updated". Both pickers list only #501, #502, #504, #505 | O: Fund team picks the FMV formula | view_setting |
| H5 | Fund team selects Allocated to their folio | GF1 view *Whole fund portfolio* | Meera chooses *Allocated to their folio*, picks #501, saves | Saved. Ravi now sees H2's list | V: Fund team selects Allocated to their folio | view_setting |
| H6 | Existing fund that showed portfolios | GF1 had "Show fund portfolios to LPs" ticked before the change | Meera opens Fund › Edit | Dropdown shows *Whole fund portfolio*. Ravi's list equals H1 | V: Existing fund that showed portfolios opens as Whole fund | view_setting |
| H7 | Existing fund that hid portfolios | GF2 had the checkbox unticked | Meera opens GF2 › Edit | Dropdown shows *Hidden from LPs* | V: Existing fund that hid portfolios opens as Hidden | view_setting |
| H8 | Fund team sets up the LP layout | No LP layout yet | Meera opens Settings › Dashboards › Portfolio Company Dashboard and clicks Set up LP layout | "LP" layout created with Data Card, Key KPIs, Valuations. Selector shows "LP (LPs, all)" | C: Fund team sets up the LP layout | sharing |
| H8a | Fund team adds an LP-safe widget | Shared setup | Meera adds a KPIs widget (XL, position 5) to "LP" | Saved. Ravi's Acme page shows KPIs after Founder Video | C: Fund team adds an LP-safe widget to the LP layout | sharing |
| H9 | Fund team shows a company | Cedar switch off | Meera opens Cedar › Actions › Show to LPs | Switch on, button reads Hide from LPs, "Visible to LPs" badge in header | C: Fund team shows a company to LPs | sharing |
| H10 | LP opens a shared company | GF1 *Allocated, with their own share* | Ravi clicks Acme Robotics in his list | LP Company Dashboard for Acme / GF1. Holdings card: "Series B CCPS 1,00,000 ₹2,500 ₹25.00 Cr ₹40.00 Cr ₹2.50 Cr ₹4.00 Cr" (1,00,000 × 2,500 = 25.00 Cr) | C: LP opens a shared company; C: Holdings card lists the LP's visible holdings for the selected fund; O: Own share appears on company holdings card | company_dashboard |
| H11 | Only LP layout widgets render | Shared setup (Acme's tag Robotics matches no tag-specific layout) | Ravi opens Acme | "LP" layout: Data Card and Key KPIs side by side (Medium), then Valuations, then Founder Video. No Notes, no Captable (Default layout only) | C: Only LP layout widgets render; C: Untagged company uses LP | company_dashboard |
| H12 | Founder video plays | Shared setup | Ravi opens Acme | Embed Document plays "Founder Video" inline with standard controls | C: Founder video plays | company_dashboard |
| H13 | Preview as LP | Meera on Acme company page | Meera › Preview as LP › Ravi, GF1 | Page identical to H10/H11 with banner "Preview — viewing as Ravi Menon (F-012)" | C: Fund team previews as an LP | company_dashboard |
| H14 | Fund selector | GF1 and GF2 both *Allocated to their folio* | Anita opens Acme, then selects Growth Fund II | Selector defaulted to Growth Fund I (cost 25.00 row). After switching: Series C CCPS row, cost 10.00, FMV 12.00. Only card and widgets reload | C: LP holding a company in two funds picks the fund | company_dashboard |
| H15 | Feeder LP sees master holding | MFM *Allocated to their folio* | Sunil opens his portfolio | Echo Foods listed (allocated via FFF #601) | V: Feeder folio sees allocated master holdings | visibility |
| H16 | Old holding link redirects | Ravi bookmarked `/aggregate_portfolio_investments/<Acme Series B id>` | Ravi opens it | Lands on Acme's LP Company Dashboard for GF1 | C: Old holding link redirects | company_dashboard |
| H17 | Carry-over at release | Before release, Acme's Series B holding had Show Portfolio on and Acme had no company switch | Carry-over runs | Acme switch on. Ravi can open Acme (as before, with the same holdings figures) | C: Company switched on from holding flag | company_dashboard |
| H18 | Hide from LPs confirms | Acme switch on | Meera clicks Hide from LPs, confirms | Popup "LPs will no longer be able to open this company's page. Their portfolio list still shows the company." Switch off after confirming. Ravi sees Acme as plain text | C: Hide from LPs asks for confirmation | sharing |
| H19 | Assistant uses the visible set | GF1 *Allocated to their folio* | Ravi asks the LP assistant "List my portfolio companies in Growth Fund I" | Answer names Acme and Cedar only | V: Assistant answers only from visible holdings | assistant |

---

## Edge cases

### Fund setting (①)

| # | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| E1 | Warning when the formula has no folio entries | GF2's #701 has no folio entries | Meera saves GF2 as *Allocated to their folio* with #701 | Saved, with warning "No folio allocations found for this fund yet. LPs will see an empty portfolio until an allocation run completes." | V: Warning when no folio allocations exist | view_setting |
| E2 | Upload creates a Whole fund fund | — | A fund upload row has "Show Fund Portfolios To Lps" = Yes | The new fund's view is *Whole fund portfolio*. A row with No creates a *Hidden from LPs* fund | V: Legacy upload sets Whole fund | view_setting |
| E3 | Legacy switch off and on restores the view | GF1 *Allocated to their folio* with #501 | A JSON client sets `show_portfolios` false, then true | After false: view *Hidden from LPs*, folio bit and #501 kept. After true: *Allocated to their folio* again | V: Legacy upload sets Whole fund | view_setting |
| E4 | Picks kept across views | GF1 *Allocated, with their own share*, #501/#502 | Meera switches to *Whole fund portfolio*, saves, then back | Pickers show #501/#502 again. Ravi sees H3's figures | O: Picks kept when switching views | view_setting |
| E5 | Renamed formula | GF1 own share on with #502 | #502 renamed to "LP FMV" | Ravi's Your FMV is still 4.00 for Acme. Note shows the new name | O: Renamed formula keeps working | own_share |
| E6 | Deleted FMV formula | GF1 own share on | #502 deleted | Ravi sees Acme and Cedar but no Your columns. GF1 page shows Meera "Pick a new formula for Your FMV" | O: Deleted formula hides own share | own_share |
| E6a | Deleted allocation formula | GF1 *Allocated* | #501 deleted | Ravi sees "No investments have been allocated to your folio yet." GF1 page shows Meera "Pick a new allocation formula" | O: Deleted formula hides own share | own_share |
| E7 | New fund default | — | Meera creates Growth Fund III | View is *Hidden from LPs* | V: Existing fund that hid portfolios opens as Hidden | view_setting |
| E8 | Pickers follow the option | GF1 form open | Meera selects each option in turn | Allocation formula picker for both *Allocated* options. Your FMV picker only for *with their own share*. No page reload | O: Fund team picks the FMV formula | view_setting |

### Visible set (③)

| # | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| E9 | Hidden view | GF1 *Hidden from LPs* | Ravi opens GF1 | No portfolio section. GF1 holdings requests return no rows | V: Hidden view hides portfolio | visibility |
| E10 | Holding not yet allocated | GF1 *Allocated*; Delta AI has no entries | Ravi opens GF1 › Portfolio | Delta not listed. Under *Whole fund* (H1) it is listed | V: Holding not yet allocated is hidden | visibility |
| E11 | Proforma entries don't count | Ravi's only Delta entry is #503 (proforma) 0.30 | Ravi opens portfolio | Delta not listed | V: Other formulas do not count | visibility |
| E12 | Sub-unit allocation | Ravi's only Delta entry is #501, amount 0.4 paise | Ravi opens portfolio | Delta not listed | V: Sub-unit allocations are ignored | visibility |
| E13 | Exactly one unit | Ravi's only Delta entry is #501, amount ₹0.01 | Ravi opens portfolio | Delta listed | V: Sub-unit allocations are ignored | visibility |
| E14 | Other portfolio formula doesn't count | Ravi's Delta entries: #501 0.00, #504 ₹0.05 Cr | Ravi opens portfolio | Delta not listed | V: Other formulas do not count | visibility |
| E15 | Negative amount counts | Ravi's only Delta entry is #501 −0.02 | Ravi opens portfolio | Delta listed | V: Negative amounts count | visibility |
| E16 | Non-portfolio formula ignored | Ravi has a #507 Management Fee entry whose parent is Delta | Ravi opens portfolio | Delta not listed | V: Other formulas do not count | visibility |
| E17 | Future-dated only | Ravi's only Delta entry is #501 0.50 dated 31/12/2026 | Ravi opens portfolio | Delta not listed | V: Future-dated allocations are ignored for visibility | visibility |
| E18 | Dated today | Same as E17 but dated 14/10/2026 | Ravi opens portfolio | Delta listed | V: Future-dated allocations are ignored for visibility | visibility |
| E19 | Deleted entry ignored | Ravi's only Delta entry #501 0.50 is deleted | Ravi opens portfolio | Delta not listed | V: Holding not yet allocated is hidden | visibility |
| E20 | Company-level formula doesn't count | Ravi has #506 Company Fees 0.10 for Fenix Mobility (company) and no #501 Fenix entries | Ravi opens portfolio | Fenix not listed | V: Other formulas do not count | visibility |
| E20a | Exited holding stays visible | Ravi's #501 Delta entries: 0.40 at 30/06/2026, 0.00 at 30/09/2026 | Ravi opens portfolio | Delta listed | V: Exited holding stays visible | visibility |
| E21 | Aggregated-holding allocation formula | GF1 allocation formula = #505; Ravi's #505 entry for Delta's aggregated holding is 0.20 | Ravi opens portfolio | Delta listed | V: Aggregated-holding allocation formula reveals the holding | visibility |
| E22 | Company with two holdings | Shared setup | Priya opens GF1 › Portfolio | Fenix listed with *Series A CCPS* only (Seed 0.00 hidden) | V: Company with several holdings shows only allocated ones | visibility |
| E23 | Several folios combined | Shared setup | Priya opens GF1 › Portfolio | Bluefin listed (F-051 allocated though F-050 excused). Banner "(F-050, F-051)" | V: Several folios are combined | visibility |
| E24 | No folio | GF1 *Allocated* | Omar opens GF1 › Portfolio | "No investments have been allocated to your folio yet." | V: LP with no folio sees an empty portfolio | visibility |
| E25 | Re-run allocation | GF1 *Allocated*; Delta hidden for Ravi | An allocation run writes Ravi #501 0.70 for Delta at 30/09/2026 | Ravi's next page load lists Delta | V: Re-run allocation updates visibility | visibility |
| E26 | Whole fund ignores excusal | GF1 *Whole fund*; Bluefin switch on | Ravi opens Bluefin | Listed, and the LP Company Dashboard opens (whole-fund semantics) | V: Whole fund view lists every holding | visibility |
| E27 | Master fund view governs master holdings | MFM *Hidden from LPs*, FFF *Allocated* | Sunil opens his portfolio | Echo Foods not listed (the holding's own fund decides, as today) | V: Hidden view hides portfolio | visibility |
| E28 | Feeder folio without master allocation | MFM *Allocated*; Sunil's #601 entries for Echo Foods are 0.00 | Sunil opens portfolio | Echo Foods not listed | V: Feeder folio sees allocated master holdings | visibility |
| E28a | Feeder fund with no allocation formula | MFM *Allocated*; FFF view *Whole fund*, no allocation formula | Sunil opens portfolio | Echo Foods not listed | V: Feeder fund without an allocation formula shows no master holdings | visibility |

### Own share (③)

| # | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| E29 | Latest date used | Ravi #502 Acme: 3.60 at 30/06, 4.00 at 30/09 | Ravi opens portfolio (own share) | Your FMV 4.00 | O: Latest reporting date on or before today is used | own_share |
| E30 | Future-dated ignored | Also #502 Acme 4.40 at 31/12/2026 | Ravi opens portfolio | Your FMV 4.00 | O: Future-dated entries are ignored | own_share |
| E31 | Deleted latest ignored | The 30/09 #502 entry for Acme is deleted | Ravi opens portfolio | Your FMV 3.60 | O: Deleted entries are ignored | own_share |
| E32 | Purchases summed | Ravi #501 Acme: 1.00 and 1.50 on the two purchases at 30/09 | Ravi opens portfolio | Your cost 2.50 | O: Instrument-level entries are summed to the holding | own_share |
| E33 | Purchases with different latest dates | Purchase 1 latest #501 entry 30/06 (1.00), purchase 2 latest 30/09 (1.50) | Ravi opens portfolio | Your cost 2.50 (each purchase's own latest) | O: Instrument-level entries are summed to the holding | own_share |
| E34 | Aggregated-holding FMV formula | GF1 Your FMV = #505; Ravi #505 Acme aggregated holding 4.10 | Ravi opens portfolio | Your FMV 4.10 | O: Aggregated-holding entries map directly | own_share |
| E35 | Several folios added | Shared setup, own share on | Priya opens portfolio | Acme Your cost 1.50 (1.00 + 0.50) | O: Several folios are added together | own_share |
| E36 | Feeder figures in feeder currency | FFF *Allocated, with their own share*, #601 / #602; MFM *Allocated* | Sunil opens portfolio | Echo Foods: fund cost ₹30.00 Cr, fund FMV ₹33.00 Cr; Your cost $120,000, Your FMV $132,000 | O: Feeder folio uses the feeder fund's formulas | own_share |
| E37 | Re-run changes figures | Own share on | Run rewrites Ravi #501 Acme to 2.60 | Next load: Your cost 2.60, totals 4.10 | O: Re-run allocation shows new figures | own_share |
| E38 | Dash for missing FMV entry | Own share on; Ravi has #501 Delta 0.70 at 30/09 but no #502 Delta entry | Ravi opens portfolio | Delta Your cost 0.70, Your FMV "—" (tooltip "Not yet allocated to your folio"). Your totals: cost 4.70 (2.50 + 1.50 + 0.70), FMV 5.80 with note "Excludes 1 holding not yet allocated." | O: Holding without an FMV entry shows a dash and is excluded from totals | own_share |
| E39 | Zero entry is a figure, not a dash | Own share on; Priya F-050 Bluefin #501 0.00, F-051 1.00 | Priya opens portfolio | Bluefin Your cost 1.00 (zero added, not a dash) | O: Several folios are added together | own_share |
| E40 | Columns absent elsewhere | GF1 *Allocated to their folio* (picks still stored) | Ravi opens portfolio and Acme | No Your columns on list or holdings card | O: Own share columns absent in other views | own_share |
| E41 | Multiple uses LP figures | Own share on | Ravi opens portfolio | Acme multiple 1.60x (4.00 ÷ 2.50), total 1.45x | O: LP sees own cost and FMV | own_share |

### LP portfolio screens (④)

| # | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| E42 | Fund-wide charts hidden | GF1 *Allocated*, Portfolio Dashboard has Portfolio Stats, FMV %, Portfolio IRR, Portfolio Investments | Ravi opens GF1 › Portfolio | Only Portfolio Investments (with totals). Under *Whole fund* all four show, as today | V: Fund-wide charts are hidden under allocated views | visibility |
| E43 | Aggregated and instrument lists agree | GF1 *Allocated* | Ravi opens the holdings grid and the purchases grid | Both contain only Acme and Cedar rows | V: Totals add only visible holdings | visibility |
| E44 | Company link only when openable | GF1 *Allocated*; Cedar switch off | Ravi views his list | Acme is a link. Cedar is plain text | C: Company switched off | company_dashboard |

### Company sharing and carry-over (⑤)

| # | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| E45 | Double submit | Cedar switch off | Show to LPs submitted twice quickly | Switch on, no error | C: Repeated clicks are idempotent | sharing |
| E46 | Switch alone grants nothing | Acme on; GF1 *Hidden from LPs* | Ravi opens Acme's dashboard address | Refused ("You do not have access to this company.") | C: Switch alone grants nothing | company_dashboard |
| E47 | Disabled widget | Valuations in "LP" is disabled | Ravi opens Acme | No Valuations widget | C: Disabled widget is never shown | company_dashboard |
| E48 | Mixed holdings carry over | Before release, Fenix *Seed* Show Portfolio on, *Series A* off | Carry-over runs | Fenix switch on | C: Mixed holdings carry over as on | sharing |
| E49 | Carry-over idempotent | After H17 | Carry-over runs again | No switch changes. Report: 0 changed | C: Carry-over is idempotent | sharing |
| E50 | Carried over in a hidden fund | GF2 *Hidden*; GF2's Acme Series C had Show Portfolio on | Carry-over runs; Anita opens Acme for GF2 | Acme switch on, but GF2 page refused, as before | C: Carried-over company in a hidden fund stays invisible | company_dashboard |
| E51 | Carry-over ignores deleted holdings | A deleted Bluefin holding had Show Portfolio on; no live one did | Carry-over runs | Bluefin switch unchanged | C: Company switched on from holding flag | sharing |
| E52 | Widget form lists LP-safe types only | Shared setup | Meera clicks Add widget on "LP" | Only the 8 LP-safe types offered, with help text "LP layout: only widgets that are safe to show LPs are listed." | C: Widget form lists only LP-safe types for the LP layout | sharing |
| E52a | Set up twice | LP layout exists | Set up LP layout submitted again | Nothing added. The layout opens | C: Set up twice creates nothing new | sharing |
| E52b | Internal layouts unaffected | Shared setup | Meera removes Data Card from "LP" | Default layout still has Data Card. Fund team's internal Acme dashboard unchanged | C: Internal layouts are unaffected | sharing |

### LP Company Dashboard (⑥)

| # | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| E53 | Switched-off company address | Cedar switch off, Cedar visible to Ravi | Ravi opens Cedar's dashboard address | "No company information has been shared yet." | C: Company switched off | company_dashboard |
| E54 | No usable LP layout | "LP" has no enabled widgets (also: layout deleted), no other LP layout | Ravi opens Acme | Holdings card plus "No further company information has been shared." No internal widgets | C: No usable LP layout shows holdings card only; C: No LP layout at all | company_dashboard |
| E54a | No internal controls | Shared setup | Ravi opens Acme | No Reports dropdown, no layout selector, no edit/run buttons on any widget | C: No internal controls for LPs | company_dashboard |
| E55 | KPIs Actual only | Key KPIs and KPIs widgets configured with tags "Actual,Budget" | Ravi opens Acme | Only Actual values (Revenue 62.0). No Budget column or series | C: KPIs are Actual only | company_dashboard |
| E56 | Only Budget KPIs | Cedar on and visible; Cedar has only Budget KPIs | Ravi opens Cedar | KPI widgets show "No KPIs reported yet." | C: KPI widget with only Budget KPIs | company_dashboard |
| E57 | Widget data limited to fund | Portfolio Investments and Portfolio Stats added to the LP layout | Anita opens Acme for GF1 | Both show the GF1 Series B holding only (no GF2 Series C) | C: Widget data limited to the selected fund | company_dashboard |
| E58 | Holdings card hides unallocated holdings | Fenix on; GF1 *Allocated* | Priya opens Fenix | Holdings card shows *Series A CCPS* only | C: Holdings card lists the LP's visible holdings for the selected fund | company_dashboard |
| E59 | Only qualifying funds in selector | GF2 *Hidden* | Anita opens Acme | No selector. GF1 data only | C: Only qualifying funds are offered | company_dashboard |
| E60 | Missing named document | Bluefin has no "Founder Video" | Priya opens Bluefin | No Embed Document widget, other widgets render | C: Missing named document hides the widget | company_dashboard |
| E61 | PDF embed unchanged | Acme "Founder Video" replaced by a PDF of the same name | Ravi opens Acme | PDF viewer, as before | C: PDF embed unchanged | company_dashboard |
| E62 | Latest named document | Acme has two "Founder Video" documents | Ravi opens Acme | The most recently added plays | C: Latest named document is used | company_dashboard |
| E63 | Only the named document exposed | Shared setup | Ravi views the Embed Document widget | No folder link, no other documents, no download-all | C: Only the named document is exposed | company_dashboard |
| E64 | Video on internal dashboards too | Embed Document on the fund dashboard names a video | Meera opens the fund dashboard | Video plays inline (was an Office viewer frame) | C: Founder video plays | company_dashboard |
| E65 | Preview for LP without access | Bluefin on | Meera › Preview as LP › Ravi, GF1 on Bluefin | Preview shows "You do not have access to this company." | C: Preview for an LP without access shows the refusal | company_dashboard |
| E66 | Fund team holding page | Shared setup | Meera opens Acme's Series B holding | No Preview, no Show/Hide Portfolio button, no "Show Portfolio" attribute row | C: Fund team holding page without retired buttons | company_dashboard |
| E67 | Legacy preview content not shown | A holding has a legacy widget "Company Overview" | Meera opens it | No Widgets or Track Record tab; the widget is not shown (its record stays stored) | C: Holding preview content becomes read-only | company_dashboard |
| E68 | Old link to a hidden holding | GF1 *Allocated*; Bluefin hidden for Ravi | Ravi opens Bluefin's old holding address | "You do not have access to this company." | C: Old holding link redirects | company_dashboard |

### LP assistant and data paths (⑦)

| # | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| E69 | Assistant and a hidden holding | GF1 *Allocated* | Ravi asks "What did the fund invest in Bluefin Health?" | Query returns no Bluefin rows; assistant says it has no such holding for him | V: Assistant answers only from visible holdings | assistant |
| E70 | Assistant and a hidden fund | GF2 *Hidden*; Anita has access | Anita asks about GF2 holdings | No rows returned | V: Assistant answers only from visible holdings | assistant |
| E71 | Assistant under whole fund | GF1 *Whole fund* | Ravi asks for his GF1 companies | Acme, Bluefin, Cedar, Delta, Fenix | V: Assistant answers only from visible holdings | assistant |

### Guidance: tooltips and info notices (⑤ ⑥ ①)

| # | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| E72 | Show to LPs tooltip | Cedar company page | Meera hovers Show to LPs | "LPs who hold this company will be able to open its page. They see the holdings card and the widgets of the LP layout that matches this company's tags." | C: Show to LPs tooltip explains what LPs see | sharing |
| E73 | Shared with no usable LP layout | Acme on; "LP" has no enabled widgets; no other LP layout | Meera opens Acme's company page | Warning notice "LPs see only the holdings card for this company. Add widgets to an LP layout" with Set up LP layout link | C: Company shared with no usable LP layout | sharing |
| E74 | Shared, but every fund hides it | Acme on; GF1 and GF2 both *Hidden* | Meera opens Acme's company page | Notice "No LP can open this page yet: every fund holding this company hides its portfolio from LPs. Change it in Fund › Edit › LP portfolio view." | C: Company shared but every holding fund hides its portfolio | sharing |
| E75 | Settings invite | No LP layout | Meera opens the Portfolio Company Dashboard settings on the Default layout | Info notice inviting her to create an LP layout, with Set up LP layout | C: Dashboard settings invite setting up the LP layout | sharing |
| E76 | LP layout explains itself | "LP, FinTech" exists; Paywise is the only shared FinTech company | Meera selects "LP, FinTech", hovers it in the selector | Notice "LPs see this layout for shared companies tagged FinTech (1 today: Paywise Payments). Other companies use "LP"…". Label "(LPs, tag FinTech)", tooltip "Layouts whose name includes LP are shown to LPs. Other layouts are internal." | C: LP layout explains itself | sharing |
| E77 | Embed Document help | Shared setup | Meera adds an Embed Document widget to the LP layout | Help text "Shows the company's latest document with this exact name, e.g. "Founder Video". Upload it to each company you share." | C: Embed Document help on the LP layout | sharing |
| E78 | Preview with no usable LP layout | "LP" has no enabled widgets; no other LP layout | Meera › Preview as LP › Ravi on Acme | Banner adds "This LP sees only the holdings card. Add widgets to an LP layout" with Open LP layout link | C: Preview with no usable LP layout | company_dashboard |
| E79 | Fund view tooltip | GF1 form | Meera hovers ⓘ next to LP portfolio view | "Decides which holdings LPs see. To let LPs open a company's page, also switch the company to Show to LPs and set up the LP layout." | C: Fund LP portfolio view tooltip | view_setting |
| E80 | Holding page points to the company | Shared setup | Meera opens Acme's Series B holding | Notice "Sharing with LPs has moved to the company: use Show to LPs on the company page and the LP layouts in dashboard settings." with a link to Acme | C: Holding page points to the new place | company_dashboard |

### LP layouts chosen by tags (⑤ ⑥)

| # | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| E81 | Tag-specific layout replaces LP | "LP, FinTech" (Data Card, KPIs "Loan book") exists | Priya opens Paywise | "LP, FinTech" widgets only: Data Card, KPIs "Loan book". None of "LP"'s Valuations or Founder Video | C: Tag-specific layout replaces LP | company_dashboard |
| E82 | Case and spaces ignored | Layout named "lp ,  fintech"; Paywise tagged "Fintech" | Priya opens Paywise | That layout is used | C: Tag-specific layout replaces LP | company_dashboard |
| E83 | Most matching tags wins | "LP, FinTech" and "LP, FinTech, NBFC" exist | Priya opens Paywise (Fintech, NBFC) | "LP, FinTech, NBFC" | C: Most matching tags wins | company_dashboard |
| E84 | Tie goes to the first name | "LP, Fintech" and "LP, NBFC" exist (one match each) | Priya opens Paywise | "LP, Fintech" (alphabetically first) | C: Tie goes to the first name | company_dashboard |
| E85 | Empty matching layout skipped | "LP, FinTech" exists with all widgets disabled | Priya opens Paywise | "LP" layout | C: Empty matching layout is skipped | company_dashboard |
| E86 | Widget tag narrows within LP | "LP" has an extra KPIs widget tagged "NBFC" | Priya opens Paywise, then Acme | Paywise shows the NBFC KPIs widget; Acme doesn't. Both show the untagged widgets | C: Widget tag narrows a widget within the layout | company_dashboard |
| E87 | Viewer's tags ignored | Priya's user carries tag "NBFC"; Acme isn't tagged NBFC | Priya opens Acme | No NBFC-tagged widget | C: Viewer's own tags are ignored | company_dashboard |
| E88 | New LP layout for a tag | Shared setup | Meera › New LP layout for a tag › "FinTech" | "LP, FinTech" created with copies of "LP"'s 4 widgets. Editing it leaves "LP" unchanged | C: New LP layout for a tag copies LP | sharing |
| E89 | Long layout name | — | Meera names a layout "LP, Enterprise Infrastructure - Software" (40 characters) | Saved | C: Long layout names are accepted | sharing |
| E90 | Only the exact LP tag | Layouts "LPX" and "Help" hold a Notes widget | Ravi opens Acme | Neither is used. Notes never shown. Their widgets aren't validated as LP-safe | C: Only the exact LP tag marks an LP layout | company_dashboard |
| E91 | Company page names the layout | "LP, FinTech" exists | Meera opens Paywise's company page | "LPs see the "LP, FinTech" layout for this company (matched on its tag FinTech)." with Open layout link. On Acme: "…the "LP" layout (no tag-specific layout matches)" | C: Company page names the layout LPs see | sharing |
| E92 | Company page warns about a tie | "LP, Fintech" and "LP, NBFC" exist | Meera opens Paywise's company page | Warning "Two LP layouts match this company's tags ("LP, Fintech" and "LP, NBFC"). LPs see "LP, Fintech". Remove a tag or a layout to choose." | C: Company page warns about a tie | sharing |
| E93 | Preview names the layout | "LP, FinTech" exists | Meera › Preview as LP › Priya on Paywise | Banner "Preview — viewing as Priya Shah (F-050, F-051). Layout: "LP, FinTech" (company tag Fintech)." | C: Preview names the layout | company_dashboard |
| E94 | Widget tags help | Shared setup | Meera edits a widget in "LP" | Tags field help "Optional. Show this widget only for companies with one of these tags. Leave empty for every company using this layout." | C: Widget tags field explained | sharing |
### Fund manager modules (① ⑤ ⑥)

| # | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| E95 | Portfolio settings hidden without the module | GF1 *Whole fund*, Portfolio valuations on; the fund manager has no fund-portfolios module | Meera opens the Features step and saves | No LP portfolio view or Portfolio valuations on the form. After saving, the view is still *Whole fund* and valuations still on | V: Portfolio settings need the fund-portfolios module | view_setting |
| E96 | LP sharing hidden without the module | No fund-portfolios module | Meera opens Acme's company page, then widget settings | No LPs menu, LP notice or Preview as LP; no "Set up LP layout" | C: LP sharing needs the fund-portfolios module | sharing |
| E97 | KPI widgets need the KPI module | "LP" holds Key Kpis; the fund manager has no KPI module | Ravi opens Acme; Meera sets up a new LP layout and adds a widget | Ravi sees Data Card, Valuations, Embed Document, no Key Kpis. The starter layout is Data Card, Valuations. The widget form offers no KPI widgets; a request to add Kpis is refused with the X6 message | C: KPI widgets need the KPI module | company_dashboard, sharing |

---

## Error cases

| # | Scenario | Given | When | Then (what the user sees, who is alerted) | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| X1 | Missing FMV formula | GF1 form | Meera saves *Allocated, with their own share* with #501 and no Your FMV | Refused: "Choose the allocation formula that gives the LP's FMV." Nothing saved | O: Missing FMV formula is refused | view_setting |
| X2 | Missing allocation formula | GF1 form | Meera saves *Allocated to their folio* with no allocation formula | Refused: "Choose the allocation formula that decides which holdings LPs see." | V: Missing allocation formula is refused | view_setting |
| X3 | Same formula twice | GF1 form | Meera picks #501 as allocation formula and Your FMV | Refused: "Your cost and Your FMV must use different formulas." | O: Same formula for both is refused | view_setting |
| X4 | Formula of another fund | — | A request sets GF1's allocation formula to FFF's #601, then its Your FMV to #601 | Each refused: "Pick one of this fund's portfolio allocation formulas." | V: Allocation formula outside the fund's holding allocation formulas is refused; O: FMV formula outside the fund's holding allocation formulas is refused | view_setting |
| X5 | Proforma, company-level or non-portfolio formula | — | A request sets GF1's allocation formula to #503, then #506, then #507 | Each refused with the X4 message | V: Allocation formula outside the fund's holding allocation formulas is refused | view_setting |
| X6 | Internal widget into an LP layout | — | A request adds a Notes widget to "LP", then edits a Default-layout Notes widget to move it into "LP, FinTech" | Both refused: "This widget can't be added to an LP layout: it isn't safe to show LPs." | C: Internal widgets cannot be added to the LP layout | sharing |
| X7 | LP changes the company switch | — | Ravi submits Show to LPs for Cedar directly | Refused (not authorised). Switch unchanged | C: Only permitted fund team can change the switch | sharing |
| X8 | Read-only employee changes the switch | — | Kiran submits Show to LPs for Cedar | Refused. Switch unchanged | C: Only permitted fund team can change the switch | sharing |
| X9 | Company outside visible set | GF1 *Allocated* | Ravi opens Bluefin's dashboard address | "You do not have access to this company." No company data in the response | C: Company outside the visible set is refused | company_dashboard |
| X10 | Other fund manager's LP | — | Lena opens Acme's dashboard address | "You do not have access to this company." | C: LP of another fund manager is refused | company_dashboard |
| X11 | Fund not accessible | — | Ravi opens Acme's dashboard with `fund_id` = GF2 | "You do not have access to this company." | C: Fund the LP cannot access is refused | company_dashboard |
| X12 | Hidden fund page | GF1 *Hidden* | Ravi opens Acme's dashboard for GF1 | "You do not have access to this company." | C: Hidden fund view refuses the page | company_dashboard |
| X13 | Widget outside the chosen LP layout | "LP, FinTech" has a Notes-free layout; Default has Notes | Ravi opens Acme (uses "LP"), then requests Acme's internal dashboard address | Acme's page shows only "LP" widgets (no "LP, FinTech" or Default widgets). The internal dashboard is refused ("Access Denied") | C: Widget request outside the LP layout is refused | company_dashboard |
| X14 | Internal addresses stay closed | — | Ravi requests Acme's internal company dashboard address | Refused ("Access Denied"), as before this change. The internal KPI and document screens keep their existing policies | C: Internal data addresses stay closed to LPs | company_dashboard |
| X15 | LP uses preview | — | Ravi requests the Preview as LP address | Refused (not authorised) | C: LP cannot use preview | company_dashboard |
| X16 | Preview parameter bypass | Cedar off | Ravi opens Cedar's holding address with `?preview=true` | "No company information has been shared yet." No holding data | C: Preview parameter no longer bypasses | company_dashboard |
| X17 | Direct request for a hidden holding | GF1 *Allocated* | Ravi requests the holdings list filtered to Bluefin, and Bluefin's holding detail | List empty. Detail refused | V: Direct request for a hidden holding returns nothing | visibility |
| X18 | Assistant query without scope | — | The assistant generates SQL on `aggregate_portfolio_investments` without the visible-holdings placeholder | Rejected: "missing {VISIBLE_API_IDS} placeholder — scope required." No data | V: Portfolio query without visibility scope is rejected | assistant |
| X19 | Carry-over meets deleted company | A live holding with Show Portfolio on belongs to a deleted company | Carry-over runs | Skipped. Report: "1 holding skipped (company deleted)". Other companies switched on | C: Holding of a deleted company is skipped | sharing |
| X20 | Portfolio switch without the module | No fund-portfolios module | A request saves GF1's features with Portfolio valuations and the view *Hidden* | Refused: "Show valuations is not available for this fund". The view stays *Whole fund* | V: Portfolio settings need the fund-portfolios module | view_setting |
| X21 | LP page without the module | No fund-portfolios module; Acme shared | Ravi opens Acme's company page | "You do not have access to this company." | C: LP sharing needs the fund-portfolios module | company_dashboard |

---

## Spec coverage check

Every spec scenario appears in at least one row above:

- **V (29 scenarios):** Whole fund: H1, E26. Existing funds: H6, H7, E7. Selects Allocated: H5. Warning: E1. Legacy upload: E2, E3. Hidden: E9, E27. Missing allocation formula: X2. Formula outside: X4, X5. Excused: H2. Not yet allocated: E10, E19. Other formulas: E11, E14, E16, E20. Sub-unit: E12, E13. Negative: E15. Exited: E20a. Future-dated: E17, E18. Aggregated: E21. Several holdings: E22. Several folios: E23. No folio: E24. Feeder: H15, E28. Feeder without formula: E28a. Totals: H2, E43. Direct request: X17. Fund-wide charts: E42. Re-run: E25. Assistant: H19, E69–E71. No scope: X18. Portfolio settings need the module: E95, X20.
- **O (19 scenarios):** Picks FMV: H4, E8. Missing FMV: X1. Same formula: X3. FMV outside: X4. Picks kept: E4. Renamed: E5. Deleted: E6, E6a. LP sees own: H3, E41. Latest: E29. Future: E30. Deleted entries: E31. Summed: E32, E33. Aggregated: E34. Several folios: E35, E39. Feeder: E36. Re-run: E37. Dash: E38. Absent elsewhere: E40. Holdings card: H10.
- **C (72 scenarios):** H8–H14, H8a, H16–H18, E44–E68, E52a, E52b, E54a, E72–E94, E96, E97, X6–X16, X19, X21.
