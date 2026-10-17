# LP Folio Portfolio & Company Dashboard — Manual QA Checklist

> **Audience:** Testers running the feature by hand on a deployed build. No code knowledge needed.
> **Companion documents:** [Proposal](proposal.md) · [Design](design.md) · [Business rules](business-rules.md)

> **How to use:** work top to bottom. Tick ☐ → ☑ and write Pass or Fail for each row. For a Fail,
> put the defect link in Notes. H/E/X row IDs match [business-rules.md](business-rules.md), so a
> failure maps straight to the Cucumber scenario with the same ID.

**ID legend:** **H** = Happy path · **E** = Edge case · **X** = Error case · **J** = UI journey
step (J2.3 = journey 2, step 3) · **R** = Role sweep · **C** = Cross-cutting check

---

## Contents

- [Test Setup](#test-setup)
- [Happy Path](#happy-path)
- [Edge Cases](#edge-cases)
- [Error Cases](#error-cases)
- [UI Journeys](#ui-journeys)
- [Role Sweep](#role-sweep)
- [Cross-cutting Checks](#cross-cutting-checks)
- [Sign-off](#sign-off)

---

## Test Setup

| Item | Detail |
|---|---|
| Environment | Staging build of branch `feature/lp-folio-portfolio-and-dashboards` |
| Accounts | **Meera Iyer** (Peak Capital fund operations: can edit funds, portfolio companies and dashboards). **Kiran Das** (Peak Capital employee, read-only on funds). LPs **Ravi Menon**, **Anita Rao**, **Priya Shah**, **Sunil Kapoor**. **Omar Khan** (investor user with GF1 access, no folio) |
| Second entity | **Lena Fischer**, an LP of Northstar Partners with no access to any Peak Capital fund |
| Seed data | Exactly the [shared setup in business-rules.md](business-rules.md#shared-setup): funds GF1, GF2, MFM/FFF; holdings Acme, Bluefin, Cedar, Delta, Fenix, Paywise, Echo Foods; formulas #501–#507, #601–#602, #701; folio entries per LP; company tags; the "LP" layout and the "Default" layout; Acme's "Founder Video" MP4 and KPIs. Ask a developer to load it with the seed step definitions |
| Background work | None runs in the background. Where a row says an "allocation run writes" entries, run Fund › Allocations › Run with the stated formula, or ask a developer to insert the entry |
| Today | Rows assume **14/10/2026**. Adjust dates if testing on another day (entries "dated today" must use the test day) |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Whole fund view unchanged | GF1 view *Whole fund portfolio* | 1. Ravi opens GF1 › Portfolio | Acme, Bluefin, Cedar, Delta, Fenix listed with fund cost/FMV only. No banner, no Your columns | | |
| ☐ | H2 | Allocated view narrows to the folio | GF1 view *Allocated to their folio* | 1. Ravi opens GF1 › Portfolio | Acme and Cedar only. Banner "Showing investments allocated to your folio (F-012)". Totals cost 40.00, FMV 58.00 (25 + 15, 40 + 18) | | |
| ☐ | H3 | Own share shown | GF1 view *Allocated, with their own share*, allocation formula #501, Your FMV #502 | 1. Ravi opens GF1 › Portfolio | Acme: Your cost 2.50, Your FMV 4.00. Cedar: 1.50 / 1.80. Your totals 4.00 / 5.80, multiple 1.45x (5.80 ÷ 4.00). Note: "Your cost = "Allocated Portfolio Cost", Your FMV = "Allocated Portfolio FMV", latest reporting date 30/09/2026" | | |
| ☐ | H4 | Fund team picks the view and formulas | GF1 view *Whole fund portfolio* | 1. Meera chooses *Allocated, with their own share*, picks #501 as allocation formula and #502 for Your FMV, saves | "Fund updated". Both pickers list only #501, #502, #504, #505 | | |
| ☐ | H5 | Fund team selects Allocated to their folio | GF1 view *Whole fund portfolio* | 1. Meera chooses *Allocated to their folio*, picks #501, saves | Saved. Ravi now sees H2's list | | |
| ☐ | H6 | Existing fund that showed portfolios | GF1 had "Show fund portfolios to LPs" ticked before the change | 1. Meera opens Fund › Edit | Dropdown shows *Whole fund portfolio*. Ravi's list equals H1 | | |
| ☐ | H7 | Existing fund that hid portfolios | GF2 had the checkbox unticked | 1. Meera opens GF2 › Edit | Dropdown shows *Hidden from LPs* | | |
| ☐ | H8 | Fund team sets up the LP layout | No LP layout yet | 1. Meera opens Settings › Dashboards › Portfolio Company Dashboard and clicks Set up LP layout | "LP" layout created with Data Card, Key KPIs, Valuations. Selector shows "LP (LPs, all)" | | |
| ☐ | H8a | Fund team adds an LP-safe widget | Shared setup | 1. Meera adds a KPIs widget (XL, position 5) to "LP" | Saved. Ravi's Acme page shows KPIs after Founder Video | | |
| ☐ | H9 | Fund team shows a company | Cedar switch off | 1. Meera opens Cedar › Actions › Show to LPs | Switch on, button reads Hide from LPs, "Visible to LPs" badge in header | | |
| ☐ | H10 | LP opens a shared company | GF1 *Allocated, with their own share* | 1. Ravi clicks Acme Robotics in his list | LP Company Dashboard for Acme / GF1. Holdings card: "Series B CCPS 1,00,000 ₹2,500 ₹25.00 Cr ₹40.00 Cr ₹2.50 Cr ₹4.00 Cr" (1,00,000 × 2,500 = 25.00 Cr) | | |
| ☐ | H11 | Only LP layout widgets render | Shared setup (Acme's tag Robotics matches no tag-specific layout) | 1. Ravi opens Acme | "LP" layout: Data Card and Key KPIs side by side (Medium), then Valuations, then Founder Video. No Notes, no Captable (Default layout only) | | |
| ☐ | H12 | Founder video plays | Shared setup | 1. Ravi opens Acme | Embed Document plays "Founder Video" inline with standard controls | | |
| ☐ | H13 | Preview as LP | Meera on Acme company page | 1. Meera › Preview as LP › Ravi, GF1 | Page identical to H10/H11 with banner "Preview — viewing as Ravi Menon (F-012)" | | |
| ☐ | H14 | Fund selector | GF1 and GF2 both *Allocated to their folio* | 1. Anita opens Acme, then selects Growth Fund II | Selector defaulted to Growth Fund I (cost 25.00 row). After switching: Series C CCPS row, cost 10.00, FMV 12.00. Only card and widgets reload | | |
| ☐ | H15 | Feeder LP sees master holding | MFM *Allocated to their folio* | 1. Sunil opens his portfolio | Echo Foods listed (allocated via FFF #601) | | |
| ☐ | H16 | Old holding link redirects | Ravi bookmarked `/aggregate_portfolio_investments/<Acme Series B id>` | 1. Ravi opens it | Lands on Acme's LP Company Dashboard for GF1 | | |
| ☐ | H17 | Carry-over at release | Before release, Acme's Series B holding had Show Portfolio on and Acme had no company switch | 1. Carry-over runs | Acme switch on. Ravi can open Acme (as before, with the same holdings figures) | | |
| ☐ | H18 | Hide from LPs confirms | Acme switch on | 1. Meera clicks Hide from LPs, confirms | Popup "LPs will no longer be able to open this company's page. Their portfolio list still shows the company." Switch off after confirming. Ravi sees Acme as plain text | | |
| ☐ | H19 | Assistant uses the visible set | GF1 *Allocated to their folio* | 1. Ravi asks the LP assistant "List my portfolio companies in Growth Fund I" | Answer names Acme and Cedar only | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | Warning when the formula has no folio entries | GF2's #701 has no folio entries | 1. Meera saves GF2 as *Allocated to their folio* with #701 | Saved, with warning "No folio allocations found for this fund yet. LPs will see an empty portfolio until an allocation run completes." | | |
| ☐ | E2 | Legacy upload | GF2 *Hidden from LPs* | 1. A fund upload sets "Show Portfolios" = Yes for GF2 | GF2 view becomes *Whole fund portfolio* | | |
| ☐ | E3 | Legacy upload switching off | GF1 *Allocated to their folio* | 1. A fund upload sets "Show Portfolios" = No | GF1 view becomes *Hidden from LPs*. Formula picks and the folio choice are kept for when it is shown again | | |
| ☐ | E4 | Picks kept across views | GF1 *Allocated, with their own share*, #501/#502 | 1. Meera switches to *Whole fund portfolio*, saves, then back | Pickers show #501/#502 again. Ravi sees H3's figures | | |
| ☐ | E5 | Renamed formula | GF1 own share on with #502 | 1. #502 renamed to "LP FMV" | Ravi's Your FMV is still 4.00 for Acme. Note shows the new name | | |
| ☐ | E6 | Deleted FMV formula | GF1 own share on | 1. #502 deleted | Ravi sees Acme and Cedar but no Your columns. GF1 page shows Meera "Pick a new formula for Your FMV" | | |
| ☐ | E6a | Deleted allocation formula | GF1 *Allocated* | 1. #501 deleted | Ravi sees "No investments have been allocated to your folio yet." GF1 page shows Meera "Pick a new allocation formula" | | |
| ☐ | E7 | New fund default | Shared setup | 1. Meera creates Growth Fund III | View is *Hidden from LPs* | | |
| ☐ | E8 | Pickers follow the option | GF1 form open | 1. Meera selects each option in turn | Allocation formula picker for both *Allocated* options. Your FMV picker only for *with their own share*. No page reload | | |
| ☐ | E9 | Hidden view | GF1 *Hidden from LPs* | 1. Ravi opens GF1 | No portfolio section. GF1 holdings requests return no rows | | |
| ☐ | E10 | Holding not yet allocated | GF1 *Allocated*; Delta AI has no entries | 1. Ravi opens GF1 › Portfolio | Delta not listed. Under *Whole fund* (H1) it is listed | | |
| ☐ | E11 | Proforma entries don't count | Ravi's only Delta entry is #503 (proforma) 0.30 | 1. Ravi opens portfolio | Delta not listed | | |
| ☐ | E12 | Sub-unit allocation | Ravi's only Delta entry is #501, amount 0.4 paise | 1. Ravi opens portfolio | Delta not listed | | |
| ☐ | E13 | Exactly one unit | Ravi's only Delta entry is #501, amount ₹0.01 | 1. Ravi opens portfolio | Delta listed | | |
| ☐ | E14 | Other portfolio formula doesn't count | Ravi's Delta entries: #501 0.00, #504 ₹0.05 Cr | 1. Ravi opens portfolio | Delta not listed | | |
| ☐ | E15 | Negative amount counts | Ravi's only Delta entry is #501 −0.02 | 1. Ravi opens portfolio | Delta listed | | |
| ☐ | E16 | Non-portfolio formula ignored | Ravi has a #507 Management Fee entry whose parent is Delta | 1. Ravi opens portfolio | Delta not listed | | |
| ☐ | E17 | Future-dated only | Ravi's only Delta entry is #501 0.50 dated 31/12/2026 | 1. Ravi opens portfolio | Delta not listed | | |
| ☐ | E18 | Dated today | Same as E17 but dated 14/10/2026 | 1. Ravi opens portfolio | Delta listed | | |
| ☐ | E19 | Deleted entry ignored | Ravi's only Delta entry #501 0.50 is deleted | 1. Ravi opens portfolio | Delta not listed | | |
| ☐ | E20 | Company-level formula doesn't count | Ravi has #506 Company Fees 0.10 for Fenix Mobility (company) and no #501 Fenix entries | 1. Ravi opens portfolio | Fenix not listed | | |
| ☐ | E20a | Exited holding stays visible | Ravi's #501 Delta entries: 0.40 at 30/06/2026, 0.00 at 30/09/2026 | 1. Ravi opens portfolio | Delta listed | | |
| ☐ | E21 | Aggregated-holding allocation formula | GF1 allocation formula = #505; Ravi's #505 entry for Delta's aggregated holding is 0.20 | 1. Ravi opens portfolio | Delta listed | | |
| ☐ | E22 | Company with two holdings | Shared setup | 1. Priya opens GF1 › Portfolio | Fenix listed with *Series A CCPS* only (Seed 0.00 hidden) | | |
| ☐ | E23 | Several folios combined | Shared setup | 1. Priya opens GF1 › Portfolio | Bluefin listed (F-051 allocated though F-050 excused). Banner "(F-050, F-051)" | | |
| ☐ | E24 | No folio | GF1 *Allocated* | 1. Omar opens GF1 › Portfolio | "No investments have been allocated to your folio yet." | | |
| ☐ | E25 | Re-run allocation | GF1 *Allocated*; Delta hidden for Ravi | 1. An allocation run writes Ravi #501 0.70 for Delta at 30/09/2026 | Ravi's next page load lists Delta | | |
| ☐ | E26 | Whole fund ignores excusal | GF1 *Whole fund*; Bluefin switch on | 1. Ravi opens Bluefin | Listed, and the LP Company Dashboard opens (whole-fund semantics) | | |
| ☐ | E27 | Master fund view governs master holdings | MFM *Hidden from LPs*, FFF *Allocated* | 1. Sunil opens his portfolio | Echo Foods not listed (the holding's own fund decides, as today) | | |
| ☐ | E28 | Feeder folio without master allocation | MFM *Allocated*; Sunil's #601 entries for Echo Foods are 0.00 | 1. Sunil opens portfolio | Echo Foods not listed | | |
| ☐ | E28a | Feeder fund with no allocation formula | MFM *Allocated*; FFF view *Whole fund*, no allocation formula | 1. Sunil opens portfolio | Echo Foods not listed | | |
| ☐ | E29 | Latest date used | Ravi #502 Acme: 3.60 at 30/06, 4.00 at 30/09 | 1. Ravi opens portfolio (own share) | Your FMV 4.00 | | |
| ☐ | E30 | Future-dated ignored | Also #502 Acme 4.40 at 31/12/2026 | 1. Ravi opens portfolio | Your FMV 4.00 | | |
| ☐ | E31 | Deleted latest ignored | The 30/09 #502 entry for Acme is deleted | 1. Ravi opens portfolio | Your FMV 3.60 | | |
| ☐ | E32 | Purchases summed | Ravi #501 Acme: 1.00 and 1.50 on the two purchases at 30/09 | 1. Ravi opens portfolio | Your cost 2.50 | | |
| ☐ | E33 | Purchases with different latest dates | Purchase 1 latest #501 entry 30/06 (1.00), purchase 2 latest 30/09 (1.50) | 1. Ravi opens portfolio | Your cost 2.50 (each purchase's own latest) | | |
| ☐ | E34 | Aggregated-holding FMV formula | GF1 Your FMV = #505; Ravi #505 Acme aggregated holding 4.10 | 1. Ravi opens portfolio | Your FMV 4.10 | | |
| ☐ | E35 | Several folios added | Shared setup, own share on | 1. Priya opens portfolio | Acme Your cost 1.50 (1.00 + 0.50) | | |
| ☐ | E36 | Feeder figures in feeder currency | FFF *Allocated, with their own share*, #601 / #602; MFM *Allocated* | 1. Sunil opens portfolio | Echo Foods: fund cost ₹30.00 Cr, fund FMV ₹33.00 Cr; Your cost $120,000, Your FMV $132,000 | | |
| ☐ | E37 | Re-run changes figures | Own share on | 1. Run rewrites Ravi #501 Acme to 2.60 | Next load: Your cost 2.60, totals 4.10 | | |
| ☐ | E38 | Dash for missing FMV entry | Own share on; Ravi has #501 Delta 0.70 at 30/09 but no #502 Delta entry | 1. Ravi opens portfolio | Delta Your cost 0.70, Your FMV "—" (tooltip "Not yet allocated to your folio"). Your totals: cost 4.70 (2.50 + 1.50 + 0.70), FMV 5.80 with note "Excludes 1 holding not yet allocated." | | |
| ☐ | E39 | Zero entry is a figure, not a dash | Own share on; Priya F-050 Bluefin #501 0.00, F-051 1.00 | 1. Priya opens portfolio | Bluefin Your cost 1.00 (zero added, not a dash) | | |
| ☐ | E40 | Columns absent elsewhere | GF1 *Allocated to their folio* (picks still stored) | 1. Ravi opens portfolio and Acme | No Your columns on list or holdings card | | |
| ☐ | E41 | Multiple uses LP figures | Own share on | 1. Ravi opens portfolio | Acme multiple 1.60x (4.00 ÷ 2.50), total 1.45x | | |
| ☐ | E42 | Fund-wide charts hidden | GF1 *Allocated*, Portfolio Dashboard has Portfolio Stats, FMV %, Portfolio IRR, Portfolio Investments | 1. Ravi opens GF1 › Portfolio | Only Portfolio Investments (with totals). Under *Whole fund* all four show, as today | | |
| ☐ | E43 | Aggregated and instrument lists agree | GF1 *Allocated* | 1. Ravi opens the holdings grid and the purchases grid | Both contain only Acme and Cedar rows | | |
| ☐ | E44 | Company link only when openable | GF1 *Allocated*; Cedar switch off | 1. Ravi views his list | Acme is a link. Cedar is plain text | | |
| ☐ | E45 | Double submit | Cedar switch off | 1. Show to LPs submitted twice quickly | Switch on, no error | | |
| ☐ | E46 | Switch alone grants nothing | Acme on; GF1 *Hidden from LPs* | 1. Ravi opens Acme's dashboard address | Refused ("You do not have access to this company.") | | |
| ☐ | E47 | Disabled widget | Valuations in "LP" is disabled | 1. Ravi opens Acme | No Valuations widget | | |
| ☐ | E48 | Mixed holdings carry over | Before release, Fenix *Seed* Show Portfolio on, *Series A* off | 1. Carry-over runs | Fenix switch on | | |
| ☐ | E49 | Carry-over idempotent | After H17 | 1. Carry-over runs again | No switch changes. Report: 0 changed | | |
| ☐ | E50 | Carried over in a hidden fund | GF2 *Hidden*; GF2's Acme Series C had Show Portfolio on | 1. Carry-over runs; Anita opens Acme for GF2 | Acme switch on, but GF2 page refused, as before | | |
| ☐ | E51 | Carry-over ignores deleted holdings | A deleted Bluefin holding had Show Portfolio on; no live one did | 1. Carry-over runs | Bluefin switch unchanged | | |
| ☐ | E52 | Widget form lists LP-safe types only | Shared setup | 1. Meera clicks Add widget on "LP" | Only the 8 LP-safe types offered, with help text "LP layout: only widgets that are safe to show LPs are listed." | | |
| ☐ | E52a | Set up twice | LP layout exists | 1. Set up LP layout submitted again | Nothing added. The layout opens | | |
| ☐ | E52b | Internal layouts unaffected | Shared setup | 1. Meera removes Data Card from "LP" | Default layout still has Data Card. Fund team's internal Acme dashboard unchanged | | |
| ☐ | E53 | Switched-off company address | Cedar switch off, Cedar visible to Ravi | 1. Ravi opens Cedar's dashboard address | "No company information has been shared yet." | | |
| ☐ | E54 | No usable LP layout | "LP" has no enabled widgets (also: layout deleted), no other LP layout | 1. Ravi opens Acme | Holdings card plus "No further company information has been shared." No internal widgets | | |
| ☐ | E54a | No internal controls | Shared setup | 1. Ravi opens Acme | No Reports dropdown, no layout selector, no edit/run buttons on any widget | | |
| ☐ | E55 | KPIs Actual only | Key KPIs and KPIs widgets configured with tags "Actual,Budget" | 1. Ravi opens Acme | Only Actual values (Revenue 62.0). No Budget column or series | | |
| ☐ | E56 | Only Budget KPIs | Cedar on and visible; Cedar has only Budget KPIs | 1. Ravi opens Cedar | KPI widgets show "No KPIs reported yet." | | |
| ☐ | E57 | Widget data limited to fund | Portfolio Investments and Portfolio Stats added to the LP layout | 1. Anita opens Acme for GF1 | Both show the GF1 Series B holding only (no GF2 Series C) | | |
| ☐ | E58 | Holdings card hides unallocated holdings | Fenix on; GF1 *Allocated* | 1. Priya opens Fenix | Holdings card shows *Series A CCPS* only | | |
| ☐ | E59 | Only qualifying funds in selector | GF2 *Hidden* | 1. Anita opens Acme | No selector. GF1 data only | | |
| ☐ | E60 | Missing named document | Bluefin has no "Founder Video" | 1. Priya opens Bluefin | No Embed Document widget, other widgets render | | |
| ☐ | E61 | PDF embed unchanged | Acme "Founder Video" replaced by a PDF of the same name | 1. Ravi opens Acme | PDF viewer, as before | | |
| ☐ | E62 | Latest named document | Acme has two "Founder Video" documents | 1. Ravi opens Acme | The most recently added plays | | |
| ☐ | E63 | Only the named document exposed | Shared setup | 1. Ravi views the Embed Document widget | No folder link, no other documents, no download-all | | |
| ☐ | E64 | Video on internal dashboards too | Embed Document on the fund dashboard names a video | 1. Meera opens the fund dashboard | Video plays inline (was an Office viewer frame) | | |
| ☐ | E65 | Preview for LP without access | Bluefin on | 1. Meera › Preview as LP › Ravi, GF1 on Bluefin | Preview shows "You do not have access to this company." | | |
| ☐ | E66 | Fund team holding page | Shared setup | 1. Meera opens Acme's Series B holding | No Preview, no Show/Hide Portfolio button, no "Show Portfolio" attribute row | | |
| ☐ | E67 | Legacy preview content not shown | A holding has a legacy widget | 1. Open the holding as the fund team | No Widgets or Track Record tab; the widget is not shown | | |
| ☐ | E68 | Old link to a hidden holding | GF1 *Allocated*; Bluefin hidden for Ravi | 1. Ravi opens Bluefin's old holding address | "You do not have access to this company." | | |
| ☐ | E69 | Assistant and a hidden holding | GF1 *Allocated* | 1. Ravi asks "What did the fund invest in Bluefin Health?" | Query returns no Bluefin rows; assistant says it has no such holding for him | | |
| ☐ | E70 | Assistant and a hidden fund | GF2 *Hidden*; Anita has access | 1. Anita asks about GF2 holdings | No rows returned | | |
| ☐ | E71 | Assistant under whole fund | GF1 *Whole fund* | 1. Ravi asks for his GF1 companies | Acme, Bluefin, Cedar, Delta, Fenix | | |
| ☐ | E72 | Show to LPs tooltip | Cedar company page | 1. Meera hovers Show to LPs | "LPs who hold this company will be able to open its page. They see the holdings card and the widgets of the LP layout that matches this company's tags." | | |
| ☐ | E73 | Shared with no usable LP layout | Acme on; "LP" has no enabled widgets; no other LP layout | 1. Meera opens Acme's company page | Warning notice "LPs see only the holdings card for this company. Add widgets to an LP layout" with Set up LP layout link | | |
| ☐ | E74 | Shared, but every fund hides it | Acme on; GF1 and GF2 both *Hidden* | 1. Meera opens Acme's company page | Notice "No LP can open this page yet: every fund holding this company hides its portfolio from LPs. Change it in Fund › Edit › LP portfolio view." | | |
| ☐ | E75 | Settings invite | No LP layout | 1. Meera opens the Portfolio Company Dashboard settings on the Default layout | Info notice inviting her to create an LP layout, with Set up LP layout | | |
| ☐ | E76 | LP layout explains itself | "LP, FinTech" exists; Paywise is the only shared FinTech company | 1. Meera selects "LP, FinTech", hovers it in the selector | Notice "LPs see this layout for shared companies tagged FinTech (1 today: Paywise Payments). Other companies use "LP"…". Label "(LPs, tag FinTech)", tooltip "Layouts whose name includes LP are shown to LPs. Other layouts are internal." | | |
| ☐ | E77 | Embed Document help | Shared setup | 1. Meera adds an Embed Document widget to the LP layout | Help text "Shows the company's latest document with this exact name, e.g. "Founder Video". Upload it to each company you share." | | |
| ☐ | E78 | Preview with no usable LP layout | "LP" has no enabled widgets; no other LP layout | 1. Meera › Preview as LP › Ravi on Acme | Banner adds "This LP sees only the holdings card. Add widgets to an LP layout" with Open LP layout link | | |
| ☐ | E79 | Fund view tooltip | GF1 form | 1. Meera hovers ⓘ next to LP portfolio view | "Decides which holdings LPs see. To let LPs open a company's page, also switch the company to Show to LPs and set up the LP layout." | | |
| ☐ | E80 | Holding page points to the company | Shared setup | 1. Meera opens Acme's Series B holding | Notice "Sharing with LPs has moved to the company: use Show to LPs on the company page and the LP layouts in dashboard settings." with a link to Acme | | |
| ☐ | E81 | Tag-specific layout replaces LP | "LP, FinTech" (Data Card, KPIs "Loan book") exists | 1. Priya opens Paywise | "LP, FinTech" widgets only: Data Card, KPIs "Loan book". None of "LP"'s Valuations or Founder Video | | |
| ☐ | E82 | Case and spaces ignored | Layout named "lp ,  fintech"; Paywise tagged "Fintech" | 1. Priya opens Paywise | That layout is used | | |
| ☐ | E83 | Most matching tags wins | "LP, FinTech" and "LP, FinTech, NBFC" exist | 1. Priya opens Paywise (Fintech, NBFC) | "LP, FinTech, NBFC" | | |
| ☐ | E84 | Tie goes to the first name | "LP, Fintech" and "LP, NBFC" exist (one match each) | 1. Priya opens Paywise | "LP, Fintech" (alphabetically first) | | |
| ☐ | E85 | Empty matching layout skipped | "LP, FinTech" exists with all widgets disabled | 1. Priya opens Paywise | "LP" layout | | |
| ☐ | E86 | Widget tag narrows within LP | "LP" has an extra KPIs widget tagged "NBFC" | 1. Priya opens Paywise, then Acme | Paywise shows the NBFC KPIs widget; Acme doesn't. Both show the untagged widgets | | |
| ☐ | E87 | Viewer's tags ignored | Priya's user carries tag "NBFC"; Acme isn't tagged NBFC | 1. Priya opens Acme | No NBFC-tagged widget | | |
| ☐ | E88 | New LP layout for a tag | Shared setup | 1. Meera › New LP layout for a tag › "FinTech" | "LP, FinTech" created with copies of "LP"'s 4 widgets. Editing it leaves "LP" unchanged | | |
| ☐ | E89 | Long layout name | Shared setup | 1. Meera names a layout "LP, Enterprise Infrastructure - Software" (40 characters) | Saved | | |
| ☐ | E90 | Only the exact LP tag | Layouts "LPX" and "Help" hold a Notes widget | 1. Ravi opens Acme | Neither is used. Notes never shown. Their widgets aren't validated as LP-safe | | |
| ☐ | E91 | Company page names the layout | "LP, FinTech" exists | 1. Meera opens Paywise's company page | "LPs see the "LP, FinTech" layout for this company (matched on its tag FinTech)." with Open layout link. On Acme: "…the "LP" layout (no tag-specific layout matches)" | | |
| ☐ | E92 | Company page warns about a tie | "LP, Fintech" and "LP, NBFC" exist | 1. Meera opens Paywise's company page | Warning "Two LP layouts match this company's tags ("LP, Fintech" and "LP, NBFC"). LPs see "LP, Fintech". Remove a tag or a layout to choose." | | |
| ☐ | E93 | Preview names the layout | "LP, FinTech" exists | 1. Meera › Preview as LP › Priya on Paywise | Banner "Preview — viewing as Priya Shah (F-050, F-051). Layout: "LP, FinTech" (company tag Fintech)." | | |
| ☐ | E94 | Widget tags help | Shared setup | 1. Meera edits a widget in "LP" | Tags field help "Optional. Show this widget only for companies with one of these tags. Leave empty for every company using this layout." | | |
| ☐ | E95 | Portfolio settings hidden without the module | Fund manager without the fund-portfolios module | 1. Open the fund's Features step 2. Save | No LP portfolio view or Portfolio valuations; their values unchanged after saving | | |
| ☐ | E96 | LP sharing hidden without the module | Fund manager without the fund-portfolios module | 1. Open a portfolio company page 2. Open widget settings | No LPs menu, LP notice or Set up LP layout | | |
| ☐ | E97 | KPI widgets need the KPI module | Fund manager without the KPI module; "LP" holds Key Kpis | 1. Open the company as an LP 2. Add a widget to "LP" | No Key Kpis on the LP page; no KPI widget types offered | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | Missing FMV formula | GF1 form | 1. Meera saves *Allocated, with their own share* with #501 and no Your FMV | Refused: "Choose the allocation formula that gives the LP's FMV." Nothing saved | | |
| ☐ | X2 | Missing allocation formula | GF1 form | 1. Meera saves *Allocated to their folio* with no allocation formula | Refused: "Choose the allocation formula that decides which holdings LPs see." | | |
| ☐ | X3 | Same formula twice | GF1 form | 1. Meera picks #501 as allocation formula and Your FMV | Refused: "Your cost and Your FMV must use different formulas." | | |
| ☐ | X4 | Formula of another fund | Shared setup | 1. A request sets GF1's allocation formula to FFF's #601, then its Your FMV to #601 | Each refused: "Pick one of this fund's portfolio allocation formulas." | | |
| ☐ | X5 | Proforma, company-level or non-portfolio formula | Shared setup | 1. A request sets GF1's allocation formula to #503, then #506, then #507 | Each refused with the X4 message | | |
| ☐ | X6 | Internal widget into an LP layout | Shared setup | 1. A request adds a Notes widget to "LP", then edits a Default-layout Notes widget to move it into "LP, FinTech" | Both refused: "This widget can't be added to an LP layout: it isn't safe to show LPs." | | |
| ☐ | X7 | LP changes the company switch | Shared setup | 1. Ravi submits Show to LPs for Cedar directly | Refused (not authorised). Switch unchanged | | |
| ☐ | X8 | Read-only employee changes the switch | Shared setup | 1. Kiran submits Show to LPs for Cedar | Refused. Switch unchanged | | |
| ☐ | X9 | Company outside visible set | GF1 *Allocated* | 1. Ravi opens Bluefin's dashboard address | "You do not have access to this company." No company data in the response | | |
| ☐ | X10 | Other fund manager's LP | Shared setup | 1. Lena opens Acme's dashboard address | "You do not have access to this company." | | |
| ☐ | X11 | Fund not accessible | Shared setup | 1. Ravi opens Acme's dashboard with `fund_id` = GF2 | "You do not have access to this company." | | |
| ☐ | X12 | Hidden fund page | GF1 *Hidden* | 1. Ravi opens Acme's dashboard for GF1 | "You do not have access to this company." | | |
| ☐ | X13 | Widget outside the chosen LP layout | "LP, FinTech" exists | 1. Ravi requests the widget-content address of the Default layout's Notes widget for Acme, then of an "LP, FinTech" widget for Acme (Acme uses "LP") | Both refused, no data | | |
| ☐ | X14 | Internal addresses stay closed | Shared setup | 1. Ravi requests Acme's KPI report page and its document folder directly | Refused as before this change | | |
| ☐ | X15 | LP uses preview | Shared setup | 1. Ravi requests the Preview as LP address | Refused (not authorised) | | |
| ☐ | X16 | Preview parameter bypass | Cedar off | 1. Ravi opens Cedar's holding address with `?preview=true` | "No company information has been shared yet." No holding data | | |
| ☐ | X17 | Direct request for a hidden holding | GF1 *Allocated* | 1. Ravi requests the holdings list filtered to Bluefin, and Bluefin's holding detail | List empty. Detail refused | | |
| ☐ | X18 | Assistant query without scope | Shared setup | 1. The assistant generates SQL on `aggregate_portfolio_investments` without the visible-holdings placeholder | Rejected: "missing {VISIBLE_API_IDS} placeholder — scope required." No data | | |
| ☐ | X19 | Carry-over meets deleted company | A live holding with Show Portfolio on belongs to a deleted company | 1. Carry-over runs | Skipped. Report: "1 holding skipped (company deleted)". Other companies switched on | | |
| ☐ | X20 | Portfolio switch without the module | No fund-portfolios module | 1. Post the fund form with Portfolio valuations on | Refused: "Show valuations is not available for this fund" | | |
| ☐ | X21 | LP page without the module | No fund-portfolios module; company shared | 1. Open the company page as an LP | "You do not have access to this company." | | |

---

## UI Journeys

**Journey 1: an LP opens a company** (design.md › What users see)

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J1.1 | LP › Growth Fund I › Portfolio | Log in as Ravi, open GF1, scroll to Portfolio | Banner "Showing investments allocated to your folio (F-012)". Acme (link) and Cedar (plain text). Totals row | | |
| ☐ | J1.2 | Portfolio list | Click Acme Robotics | LP Company Dashboard opens. ① Holdings card at the top, with a way back to the GF1 portfolio | | |
| ☐ | J1.3 | LP Company Dashboard | (as Anita) look at the top right | ② Fund selector listing Growth Fund I and II, Growth Fund I selected | | |
| ☐ | J1.4 | LP Company Dashboard | Wait for widgets, click each nav pill | ③ Widgets load. Each pill jumps to its widget. No Reports menu, no layout selector | | |
| ☐ | J1.5 | Founder Video widget | Press play | ④ Video plays inline with standard controls | | |

**Journey 2: the fund team shares a company**

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J2.1 | Fund › Edit › Features | As Meera, open the LP portfolio view dropdown | Four options. Choosing an *Allocated* option shows the Allocation formula picker; *with their own share* also shows Your FMV. ⓘ tooltip as in E79 | | |
| ☐ | J2.2 | Settings › Dashboards › Portfolio Company Dashboard | Open it with no LP layout | Notice inviting her to create an LP layout + **Set up LP layout** | | |
| ☐ | J2.3 | Same | Click Set up LP layout | "LP" layout with Data Card, Key KPIs, Valuations. Selector shows "LP (LPs, all)" | | |
| ☐ | J2.4 | Same | Click **New LP layout for a tag**, enter FinTech | "LP, FinTech" created as a copy. Selector label "(LPs, tag FinTech)" | | |
| ☐ | J2.5 | Acme company page | Click **Show to LPs** (hover first) | Tooltip as in E72. Button becomes Hide from LPs. "Visible to LPs" badge. Notice naming the layout in use (E91) | | |
| ☐ | J2.6 | Acme company page | Misc › **Preview as LP…**, pick Ravi and GF1 | Preview banner naming the LP and layout (E93). Same page as J1.2–J1.4 | | |
| ☐ | J2.7 | Acme company page | Click Hide from LPs | Confirm popup with the action-summary card text from H18. Switch off only after confirming | | |
| ☐ | J2.8 | A holding page (Acme Series B) | Open it | No Preview / Show Portfolio buttons. Notice pointing to the company (E80) with a working link | | |

---

## Role Sweep

✓ = allowed and works · ✗ = correctly blocked · ! = wrong

| ID | Screen / action | Meera (fund ops) | Kiran (read-only employee) | Ravi (LP with access) | Omar (investor, no folio) | Lena (other entity) |
|---|---|---|---|---|---|---|
| R1 | Fund › Edit › LP portfolio view | ✓ | ✗ | ✗ | ✗ | ✗ |
| R2 | Company › Show / Hide from LPs | ✓ | ✗ (X8) | ✗ (X7) | ✗ | ✗ |
| R3 | Dashboard settings: edit LP layouts, Set up / New LP layout | ✓ | ✗ | ✗ | ✗ | ✗ |
| R4 | Misc › Preview as LP | ✓ | ✓ if they can view the company, else ✗ | ✗ (X15) | ✗ | ✗ |
| R5 | LP Company Dashboard of Acme (GF1) | n/a (uses preview) | n/a | ✓ (H10) | ✗ empty portfolio (E24) | ✗ (X10) |
| R6 | Widget-content address of an LP layout widget | n/a | n/a | ✓ for its company only | ✗ | ✗ |
| R7 | Holding page address | ✓ internal page | ✓ internal page (read) | → redirect (H16) | ✗ | ✗ |
| R8 | LP assistant portfolio question | n/a | n/a | ✓ visible holdings only (H19) | ✓ nothing for GF1 | ✗ |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Emails / alerts | N/A: this feature sends none. Confirm no email arrives after sharing a company or changing the view | | |
| ☐ | C2 | Dates on changed screens | "As of" and reporting dates follow the user's locale format (e.g. `30/09/2026` for en, `09/30/2026` for en-US) | | |
| ☐ | C3 | Narrow / mobile width | LP portfolio list, LP Company Dashboard and the fund selector usable at phone width: no horizontal page scroll, Medium widgets stack | | |
| ☐ | C4 | Tenant isolation | Lena cannot open any Peak Capital LP page, widget address, preview or holding, even with direct URLs copied from Ravi's session | | |
| ☐ | C5 | Regression on modified screens | Fund edit form saves other features as before. Internal Portfolio Company Dashboard (Default) unchanged. Internal holding page still shows investments, income and documents. Fund dashboard Embed Documents (PDF, Excel) unchanged. LP fund page unchanged for a fund on *Whole fund* | | |
| ☐ | C6 | Empty states | Empty portfolio message (E24). No-widget LP page (E54). Settings with no LP layout (E75) | | |
| ☐ | C7 | Release carry-over | After deploy, Rhapsody and Fireside companies whose holdings had Show Portfolio on are switched on, and their LPs see the same quantity / cost / FMV figures on the new page (ask a developer for the migration output: changed / skipped counts) | | |
| ☐ | C8 | Tooltips and notices lead somewhere | Every guidance notice's link opens the place where the fix happens | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
