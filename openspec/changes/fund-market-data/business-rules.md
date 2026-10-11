# Fund Market Data — Business Rules (Worked Examples)

> **Audience:** Product, QA, engineering.
> **Companion documents:** [Proposal](proposal.md) · [Spec](specs/) · [Design](design.md) · [QA checklist](qa-checklist.md) · [Tasks](tasks.md)

> Every business rule of this change as a worked example. Each row is one Cucumber scenario (the
> **Feature** column names the file under `features/market_data/`, or
> `features/fund/evergreen/` for `nav_market_data`), carries its ID in a comment above the scenario,
> and is a row in the QA checklist. The design's cards cite these IDs. Edge and error tables are
> exhaustive: an edge case found during apply gets a new row here **and** a scenario.
>
> Rows with Feature `exposure_limits` belong to the separate later phase 9 (exposure limits).

## Contents

- [Shared setup](#shared-setup)
- [Happy Path](#happy-path)
- [Edge Cases](#edge-cases)
- [Error Cases](#error-cases)

---

**ID legend:** **H** = Happy path · **E** = Edge case · **X** = Error (exception) case.
Spec scenario prefixes: **MDS** market-data-settings · **FX** fx-rates · **MP** market-prices ·
**DC** derivative-contracts.

## Shared setup

| Record | Name | Key data |
|---|---|---|
| Entity | Caphive Capital | INR; pivot USD; Market FX rates, Market prices, Derivatives on |
| Fund | Growth AIF II | INR; Manual only (rates, prices); derivatives off |
| Fund | Bridge Hybrid Fund | INR; rates Manual + Derived; prices Manual + Market |
| Fund | Horizon Evergreen Fund | INR, open-ended; rates Manual + Market + Derived; prices Manual + Market; derivatives on; limits 3 / 3 / 10 % / 2× |
| Rates | USD→INR | Manual 83.00 (1 Apr 2026); Market 85.00 ECB via EUR (30 Oct) |
| Rates | EUR→USD | Manual 1.07 (30 Sep); Market 1.08 ECB (30 Oct) |
| Rates | INR→GBP | Manual 0.0095 (30 Oct) |
| Rates | USD→INR, Horizon's own | Manual 84.50, owner Horizon (30 Oct) — used only when Horizon has *Use fund-specific FX rates* on (H21, E68–E72) |
| Instrument | ACMEIND | INR, NSE, Market; valuations Manual ₹1,100 (30 Sep), Market ₹1,020 (23 Oct), Market ₹1,250 (30 Oct) |
| Instrument | Nimbus Inc | USD, NASDAQ, **Manual** (no US feed in this change); Manual $120 (30 Oct); bought 1,000 @ $100 at 83.00 by Horizon and Growth AIF II |
| Instrument | Rangoli Textiles | INR, NSE `RANGOLI`, Market (used for X15) |
| Instrument | Private Co A | INR, Manual; Manual ₹500 (30 Sep); Horizon holds 10,000 |
| Instrument | Rhein AG | EUR, Manual |
| Contract | Nifty put | Horizon; long 1 lot × 75; strike 24,000; expiry 26 Nov 2026; premium ₹40,000; NSE; cash-settled |
| Contract | FX forward | Horizon; short USD 1,00,000 @ 84.00; maturity 29 Jan 2027; Bank X; hedges Nimbus Inc |
| NAV | Horizon 30 Oct | cash ₹30,00,000; other assets ₹5,00,000; mgmt fee payable ₹2,00,000; 4,00,000 units |
| Users | Priya (support), Kavya (company_admin), Meera (fund update, FundAccounting tag), Arjun (approver), Ravi (fund read only), Omar (other entity) | |

## Happy Path

| # | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| H1 | Support switches on entity features | Entity with none on | Priya ticks the three features | Saved; Kavya sees the Market Data card | MDS › Support switches on the entity features | fund_features |
| H2 | Admin sets feeds and defaults | H1 | Kavya turns on ECB, NSE, BSE, AMFI; pivot USD; defaults | Saved; card lists USD→INR, EUR→USD and next run | MDS › Admin sets feeds and defaults | fund_features |
| H3 | Fund chooses features | H1 | Meera ticks the four new switches on Horizon | Features saved; audit entry; Manual shown always | MDS › Fund chooses its market-data features; MDS › Manual is always accepted | fund_features |
| H4 | FX feed loads a rate | H2, ECB stub giving USD→INR 85.00 (via EUR) | `FxFeedJob` for 30 Oct | Market USD→INR 85.00, ECB via EUR, Reference, 30 Oct | FX › Feed loads rates | fx_feed |
| H5 | Two funds, two rates | Shared setup | FMV of Nimbus on 30 Oct | Growth AIF II at 83.00 (₹99,60,000); Horizon at 85.00 (₹1,02,00,000) | FX › Two funds value the same holding with different rates | fx_rate_sources |
| H6 | Instrument set to Market | ACMEIND Manual | Meera sets ticker/exchange, Market | Market badge | MP › Instrument set to Market | market_prices |
| H7 | Two funds, two prices | ACMEIND valuations; Bridge accepts market, Growth AIF II not | FMV 30 Oct | Bridge ₹1,250; Growth AIF II ₹1,100 | MP › Two funds price the same holding differently | market_prices |
| H8 | Price feed loads prices | NSE stub ACMEIND 1,250 | `PriceFeedJob` 30 Oct | Market ₹1,250, NSE, Close | MP › Feed loads prices | price_feed |
| H9 | Unrealised gain split | Horizon Nimbus | Recompute | Gain ₹19,00,000 = ₹17,00,000 price + ₹2,00,000 currency | FX › Unrealised split | fx_rate_sources |
| H10 | Split confirmed | NSE corporate-action stub 1:2 ACMEIND | Run, Meera confirms | StockAdjustment created; email sent once | MP › Split confirmed | price_feed |
| H11 | Listed put recorded | Horizon derivatives on | Meera records the put | Open contract, trade event, ledger −₹40,000 "Derivative Premium" | DC › Listed put recorded | derivatives_listed |
| H12 | FX forward recorded | — | Meera records the forward | Open, no premium entry | DC › FX forward recorded | derivatives_listed |
| H13 | Listed value from feed | H11, NSE F&O stub 333.33 | `PriceFeedJob` | Valuation ₹24,999.75; unrealised entry −₹15,000.25 | DC › Listed contract valued from the feed | derivatives_listed |
| H14 | Counterparty upload | H12 | Upload −1,50,000 Bank X | Valuation event; contract shown as liability | DC › Counterparty upload | derivatives_listed |
| H15 | Call exercised into shares | Long call ACMEIND 1×75, strike 1,000, premium 7,500 | Exercise | Buy 75 @ ₹1,100; contract closed | DC › Call exercised into shares | derivatives_listed |
| H16 | Forward hedges a holding | H12 hedge_of Nimbus | Open Nimbus holding | "Hedged by: FX forward, sell USD 1,00,000 @ 84.00 (−₹1,50,000)" | DC › Forward hedges a holding | derivatives_listed |
| H17 | IRS settlement | OTC phase; pay-fixed ₹10 Cr | Settlement 2,10,000 paid / 1,95,000 received | Event −₹15,000; ledger posted | DC › Interest-rate swap settlement | derivatives_otc |
| H18 | NAV with derivative lines | Shared setup, H13, H14 | Draft 30 Oct | Assets ₹25,000; liabilities ₹1,50,000; NAV ₹4,33,75,000; ₹108.44 | DC › NAV with derivative lines | nav_market_data |
| H19 | Exception accepted, then approve | H18; ACMEIND +22.5 % | Arjun accepts with note, approves | "Accepted by Arjun"; NAV approved | MP › Move above threshold; MP › Approver accepts an exception | nav_market_data |
| H20 | Rate change marks NAV | H19 | Meera adds Manual 84.80 for 30 Oct | NAV shows "Inputs changed"; not rebuilt | FX › Rate change marks the NAV; FX › Approved NAV not rebuilt; FX › Manual correction of a fed rate | nav_market_data |
| H21 | Fund-specific rate used by its own fund only | Horizon has *Use fund-specific FX rates*; own USD→INR 84.50 (30 Oct) | FMV of Nimbus on 30 Oct in Horizon, Bridge and Growth AIF II | Horizon 84.50 (own); Bridge and Growth AIF II 83.00; entity reports never use 84.50 | FX › Fund-specific rate used only by its fund | fx_rate_sources |
| H22 | Cat III preset applied | Horizon derivatives on | Meera chooses SEBI Cat III AIF | Commitment, leverage 2.0×, naked short calls not allowed | DC › Cat III preset | exposure_limits |
| H23 | Within limits | Put counts full notional 75 × 24,000 = ₹18,00,000; forward nets to 0; NAV ₹4,33,75,000; limit 2.0× | Open exposure report | 0.04× green; no exception | DC › Within limits | exposure_limits |

## Edge Cases

| # | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| E1 | No entity feature | Entity with none on | Open fund, entity settings | No market-data UI; FMV/conversions identical to before | MDS › Entity with no market-data feature | fund_features |
| E2 | Switch hidden | Entity without Market FX rates | Edit fund | No Accept market FX rates | MDS › Switch hidden when the entity feature is off | fund_features |
| E3 | New fund defaults | Entity default Manual + Market rates | Create fund | Fund accepts Market rates | MDS › New fund starts with entity defaults | fund_features |
| E4 | Values carried over | Fund with portfolios, units on, ratios off | Run migration | Flags match | MDS › Values carried over | fund_features |
| E5 | Investor access unchanged | Two funds, show portfolio on/off | Investor opens each portfolio | First shown, second refused | MDS › Investor access unchanged | fund_features |
| E6 | Fund upload columns | Upload Yes / No | Import | Ratios on, portfolio off | MDS › Fund upload keeps its columns | fund_features |
| E7 | Blank limit uses default | Entity default 3, fund blank | Read effective limit | 3 | MDS › Blank limit uses entity default | fund_features |
| E8 | Limits hidden on closed-ended | Fund without evergreen setting | Edit fund | No Limits group | MDS › Limits hidden on a closed-ended fund | fund_features |
| E9 | Changing defaults leaves existing funds | Existing funds; entity default Manual only | Kavya changes default to Manual + Market rates; then creates a fund | Existing funds unchanged; new fund accepts Market | MDS › Changing defaults leaves existing funds alone | fund_features |
| E10 | Entity flag later turned off | Horizon accepts market; support unticks Market FX rates | Convert | Manual only used; fund bit kept and restored when turned back on | MDS › Switch hidden when the entity feature is off | fund_features |
| E11 | Feed re-run idempotent | H4 | Run again for 30 Oct | One Market row; run row updated | FX › Re-run is idempotent | fx_feed |
| E12 | New pair tracked | Add GBP fund | Next run | GBP pair fetched | FX › New pair tracked | fx_feed |
| E13 | Weekend skipped | Saturday | Job runs | No fetch, no run row, no email | FX › Weekend skipped | fx_feed |
| E14 | Some pairs missing | The entity also holds an AED instrument; the ECB file has no AED | Run 30 Oct | USD→INR stored; email lists only AED→INR ("not published"); status partial | FX › Some pairs missing | fx_feed |
| E15 | Upload without Source | Upload rows | Import | Manual, provider "Upload" | FX › Upload without a Source column | fx_feed |
| E16 | Existing rates manual | Pre-change rates | Migrate | All Manual; FMV unchanged | FX › Existing rates become Manual | fx_rate_sources |
| E17 | Manual and Market same date stored | Shared setup + Manual 84.80 30 Oct | List rates | Both rows | FX › Manual and Market rate on the same date | fx_rate_sources |
| E18 | Manual wins same date | E17 | Horizon converts 30 Oct | 84.80 | FX › Manual wins on the same date | fx_rate_sources |
| E19 | Newer market beats older manual | Manual 26 Oct, Market 30 Oct | Horizon 30 Oct | Market | FX › Newer market rate beats older manual rate | fx_rate_sources |
| E20 | Manual-only ignores newer market | Shared setup | Growth AIF II 30 Oct | 83.00 (1 Apr) | FX › Manual-only fund ignores newer market rate | fx_rate_sources |
| E21 | Cross from manual legs | Bridge, Rhein AG | Convert EUR→INR 30 Oct | 88.81, Derived (via USD), as_of 1 Apr | FX › Cross rate from manual legs | fx_rate_sources |
| E22 | Reverse rate | INR→GBP 0.0095 | Fund with Derived needs GBP→INR | 105.26315789, Derived (reverse) | FX › Reverse rate | fx_rate_sources |
| E23 | Newer derived beats older direct | Horizon: Manual EUR→INR 90.00 dated 1 Jan; Market EUR→USD 1.08 and Market USD→INR 85.00 dated 30 Oct | Horizon converts EUR→INR 30 Oct | Cross 1.08 × 85.00 = 91.80 (as_of 30 Oct) beats the 1 Jan direct rate | FX › Newer derived beats older direct | fx_rate_sources |
| E24 | Leg corrected | E23 derived row unreferenced | Manual USD→INR 84.80 for 30 Oct added | Derived row deleted; next lookup 1.08 × 84.80 = 91.584 | FX › Leg corrected | fx_rate_sources |
| E25 | Derived starts no jobs | E21 | Derived row saved | No recompute, no commitment adjustment enqueued | FX › Derived rate starts no jobs | fx_rate_sources |
| E26 | Same currency | INR→INR | Convert | 1, no query | FX › Same currency | fx_rate_sources |
| E27 | Entity-level conversion | Entity default Manual only | KPI conversion | Manual only | FX › Entity-level conversion uses entity defaults | fx_rate_sources |
| E28 | Allocation run same rate | Horizon | Allocation (SQLite) conversion 30 Oct | 85.00 = live | FX › Allocation run resolves the same rate | fx_rate_sources |
| E29 | Market rate recomputes accepting funds only | Shared setup | Market rate arrives | Horizon PIs recomputed, Growth AIF II not | FX › Market rate recomputes only accepting funds | fx_rate_sources |
| E30 | Fed rate creates no adjustment | Commitment-adjustment option on, USD folio | Market rate arrives | No CommitmentAdjustment | FX › Fed rate creates no commitment adjustment | fx_rate_sources |
| E31 | Changing accepted sources | Growth AIF II USD commitment booked at 83.00 | Turn on Accept market rates | FMV recomputed at 85.00; commitment amount unchanged; audit row | FX › Changing accepted sources | fx_rate_sources |
| E32 | Split adds up after rounding | 7 sh bought $13.37 @ 83.1234, valued $14.11 @ 84.0567 | Recompute | Total ₹522.76 = price ₹435.41 + currency ₹87.35 | FX › Split adds up after rounding | fx_rate_sources |
| E33 | Realised split on sale | Horizon sells 400 Nimbus @ $125 @ 85.50 | Save sale | Realised ₹9,55,000 = ₹8,55,000 + ₹1,00,000 | FX › Realised split on a sale | fx_rate_sources |
| E34 | Existing instruments manual + ISIN copied | Instrument with `sebi_isin` | Migrate | Manual; ISIN field filled; FMV unchanged | MP › Existing instruments become Manual | market_prices |
| E35 | Switching to Market keeps history | ACMEIND manual rows | Set Market, run feed | Manual rows kept, Market added | MP › Switching to Market keeps history | market_prices |
| E36 | Existing valuations manual | Pre-change valuations | Migrate | Manual; FMV unchanged | MP › Existing valuations become Manual | market_prices |
| E37 | Upload with Price Type | Upload Mid | Import | price_type mid, source manual | MP › Valuation upload with Price Type | market_prices |
| E38 | Manual beats Market same date | Manual 1,240 + Market 1,250 on 30 Oct | Bridge FMV | 1,240 | MP › Manual beats Market on the same date | market_prices |
| E39 | Market beats Cost same date | Horizon buys ACMEIND 30 Oct @ 1,230 | FMV | 1,250 | MP › Market beats Cost on the same date | market_prices |
| E40 | Purchase never overwrites | E39 | After the buy | Market 1,250 unchanged; Cost 1,230 added | MP › Purchase on a day with a market close | market_prices |
| E41 | Manual-only fund uses Cost | Growth AIF II buys Rhein AG (manual EUR→INR 88.81 entered) | FMV | Cost price | MP › Manual-only fund uses Cost | market_prices |
| E42 | Mutual fund by ISIN | Market instrument, ISIN only; AMFI stub | Run | AMFI NAV stored | MP › Mutual fund matched by ISIN | price_feed |
| E43 | One recompute per holding | 3 instruments of one company | Run | One `PortfolioInvestmentUpdate` per (company, instrument) | MP › One recompute per holding per run | price_feed |
| E44 | Price re-run idempotent | H8 | Re-run | One Market row | MP › Re-run is idempotent | price_feed |
| E45 | Test feed | Market instruments ACMEIND and Rangoli Textiles on NSE | Test feed | "2 of 2 found" listing both; nothing stored | MP › Test feed | price_feed |
| E46 | Suggestion dismissed | Dividend suggestion | Dismiss; next run reports it again | Nothing changes; no new suggestion | MP › Suggestion dismissed | price_feed |
| E47 | Reported again | Pending split | Next run | No new suggestion, no email | MP › Reported again | price_feed |
| E48 | Short option premium | Short call premium 30,000 | Record | Ledger +₹30,000 | DC › Short option receives premium | derivatives_listed |
| E49 | Partial close-out | Long put 2 lots, premium 80,000 | Close 1 lot for 18,000 | open_lots 1; realised −₹22,000 | DC › Partial close-out | derivatives_listed |
| E50 | Expires worthless | H11 | Expiry event | Closed; realised −₹40,000 (reverses unrealised) | DC › Option expires worthless | derivatives_listed |
| E51 | Double submission | Exercise submitted twice | Same idempotency key | One event, one PI | DC › Double submission | derivatives_listed |
| E52 | Contract in foreign currency | USD contract valued $2,000; Horizon Market 85.00 | Value in fund | ₹1,70,000 | DC › Contract in a foreign currency | derivatives_listed |
| E53 | Put exercised physically | Long put ACMEIND 1×75, strike 1,300; holds 20,000 | Exercise | Sell 75 @ 1,300, FIFO attribution | DC › Put exercised physically | derivatives_listed |
| E54 | Cash-settled exercise | Index option | Exercise for 12,000 | Settlement +₹12,000; no PI | DC › Cash-settled index option | derivatives_listed |
| E55 | Hedges a share class | Contract hedge_unit_type "Class B" | Show | "Hedges: Class B" | DC › Contract hedges a share class | derivatives_listed |
| E56 | Exposure with/without delta | Option delta −0.30, 75 × 24,500; option no delta | Exposure report | counts ₹5,51,250; other "full notional" | DC › Exposure with and without delta | exposure_limits |
| E57 | Reminder once | Put expires 26 Nov | Job on 19 Nov and 20 Nov | One email on 19 Nov | DC › Reminder sent once | derivatives_listed |
| E58 | Rate at the age limit | NAV Fri 30 Oct; rate Tue 27 Oct; limit 3 | Draft | No exception | FX › Rate at the age limit | nav_market_data |
| E59 | Rate older than limit | Rate Mon 26 Oct | Draft | Rate exception listed | FX › Rate older than the limit | nav_market_data |
| E60 | Move exactly at threshold | 1,000 → 1,100 (10.00 %) | Draft | No exception | MP › Move exactly at threshold | nav_market_data |
| E61 | Stale market price | Market price older than 3 business days | Draft | Stale exception | MP › Stale market price | nav_market_data |
| E62 | Private mark age | Private Co A Manual 30 Sep | Draft | "Manual · 30 Sep (30d)"; no exception | MP › Private mark shows age | nav_market_data |
| E63 | Redraft keeps acceptance | H19 accepted (draft), unrelated fix | Redraft | Still accepted | MP › Redraft keeps unchanged acceptance | nav_market_data |
| E64 | Redraft reopens changed | Accepted; ACMEIND price corrected | Redraft | Exception open | MP › Redraft reopens changed item | nav_market_data |
| E65 | Zero contract value | Contract valued 0 | Draft | In neither line | DC › Zero value | nav_market_data |
| E66 | Valuation upload marks NAV | Draft exists | Upload forward value dated 30 Oct | "Inputs changed" | DC › Valuation upload marks the NAV | nav_market_data |
| E67 | Fund without contracts | Open-ended fund, no contracts | Draft | Both lines 0; other figures as before | DC › Fund without contracts | nav_market_data |
| E68 | Same-date fund rate beats entity manual | Horizon flag on; own 84.50 and entity Manual 84.80 both 30 Oct | Horizon converts 30 Oct | 84.50 | FX › Fund rate beats entity rate on the same date | fx_rate_sources |
| E69 | Newer entity rate beats older fund rate | Horizon own 84.50 dated 26 Oct; entity Market 85.00 dated 30 Oct | Horizon converts 30 Oct | 85.00 (latest wins) | FX › Newer entity rate beats older fund rate | fx_rate_sources |
| E70 | Flag off ignores own rates | Horizon own 84.50 exists; flag turned off | Horizon converts 30 Oct | 85.00; own rate kept, listed, unused | FX › Own rates ignored when the feature is off | fx_rate_sources |
| E71 | Cross built from the fund's own leg | Horizon flag + Derived; own USD→INR 84.50 (30 Oct); Market EUR→USD 1.08 (30 Oct); no EUR→INR | Horizon converts EUR→INR | 1.08 × 84.50 = 91.26, Derived (via USD), owner Horizon | FX › Derived rate from a fund's own leg | fx_rate_sources |
| E72 | Own rate's jobs stay in its fund | Commitment-adjustment option on; USD folios in Horizon and Growth AIF II | Horizon own Manual rate added | Adjustment and recompute only for Horizon | FX › Own rate affects only its fund | fx_rate_sources |
| E73 | Market data stays in its entity | Second entity Northwind, also on the ECB feed | Both FX feeds run 30 Oct; then Caphive's Market row is deleted | Each entity stored its own Market USD→INR 85.00 row; after the delete Northwind's row and conversions are untouched; neither lists the other's row | FX › Market rates stay in their entity | fx_feed |
| E74 | Commitment nets a hedge | Commitment; FX forward USD 1,00,000 at 85.00 linked to Nimbus (₹1,02,00,000) | Exposure report | Gross ₹85,00,000, counted ₹0 | DC › Commitment nets a hedge | exposure_limits |
| E75 | Commitment nets opposite futures | Long + short Nifty future 1 × 75 @ 24,500, same expiry | Exposure report | Gross ₹36,75,000, counted ₹0 | DC › Commitment nets opposite positions | exposure_limits |
| E76 | Preset customised | Cat III profile | Change leverage to 1.5× | "SEBI Cat III AIF (customised)" | DC › Preset customised | exposure_limits |
| E77 | Short put without delta | Short put 1 × 75 @ ₹1,000 | Exposure report | Counts ₹75,000 | DC › Short put without delta | exposure_limits |
| E78 | Naked short calls allowed | Rule switched to allowed; fund holds 0 Rangoli | Record short call 1 × 500 | Recorded | DC › Naked short calls allowed | exposure_limits |
| E79 | '40 Act preset excludes hedges | '40 Act preset; put + FX forward hedge | Exposure report | Only the put counts | DC › '40 Act preset excludes hedges | exposure_limits |
| E80 | Closed-ended fund | Non-open-ended fund with Derivatives and a 2.0× limit | Exposure report | Amounts and hard rules; % rows "Checked on open-ended funds" | DC › Closed-ended fund | exposure_limits |
| E81 | Amber near the limit | Counted ₹7,90,00,000; NAV ₹4,33,75,000; limit 2.0× | Exposure report | 1.82× amber | DC › Amber near the limit | exposure_limits |
| E82 | Exactly at the limit | Counted ₹8,67,50,000 | Exposure report | 2.00× amber, not red | DC › Exactly at the limit | exposure_limits |
| E83 | Bank counterparty over limit | Bank X owes ₹50,00,000; bank limit 10 % | Exposure report | Bank X 11.5 % red | DC › Bank counterparty over its limit | exposure_limits |
| E84 | Negative value not counterparty exposure | Fund owes Bank X ₹1,50,000 | Exposure report | Bank X 0 % | DC › Negative value is not counterparty exposure | exposure_limits |
| E85 | Non-bank counterparty over limit | Non-bank owes ₹26,00,000; limit 5 % | Exposure report | 6.0 % red | DC › Non-bank counterparty over its limit | exposure_limits |
| E86 | Single underlying over limit | ACMEIND ₹2,50,00,000 + call ₹46,875; limit 50 % | Exposure report | ACMEIND 57.7 % red | DC › Single underlying over its limit | exposure_limits |
| E87 | Breach emailed once | X32 breach | Draft twice on 30 Oct | One email | DC › Breach emailed once | exposure_limits |
| E88 | Contract that would breach | Leverage 1.95×, limit 2.0× | Meera records a future taking it to 2.10× | Confirm popup "Leverage 1.95× → 2.10× (limit 2.0×)"; recorded on confirm | DC › Contract that would breach | exposure_limits |

## Error Cases

| # | Scenario | Given | When | Then (what the user sees, who is alerted) | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| X1 | Non-support changes entity features | Kavya | Direct PATCH to admin entity | Refused; unchanged | MDS › Non-support user cannot switch entity features | fund_features |
| X2 | Price feed on with no provider | — | Kavya turns on the price feed, no provider ticked, saves | "Choose at least one provider" | MDS › Feed on with no provider | fund_features |
| X3 | Unavailable switch submitted | Entity lacks Market prices | Direct PATCH with accept_market_prices | Refused; unchanged | MDS › Direct submission of an unavailable switch | fund_features |
| X4 | Age out of range | — | Max rate age 31 | "must be between 0 and 30" | MDS › Out-of-range age | fund_features |
| X5 | Threshold out of range | — | Threshold 0 | "must be between 1 and 100" | MDS › Out-of-range threshold | fund_features |
| X6 | Provider down | ECB stub 500 ×3 | Weekday run | Run failed; FundAccounting email "FX feed: no rates loaded for Oct 29, 2026" once | FX › Provider down | fx_feed |
| X7 | Invalid provider rate | Stub returns 0 | Run | Not stored; listed missing; partial | FX › Invalid rate from provider | fx_feed |
| X8 | Duplicate manual rate | Manual exists for date | Add another Manual | Existing duplicate message | FX › Duplicate manual rate | fx_rate_sources |
| X9 | No accepted rate | Growth AIF II, no Manual EUR→INR | Book Rhein AG purchase | "No EUR→INR rate on or before 30 Oct 2026 in this fund's accepted sources (Manual). Enter a manual rate, or accept derived rates for this fund." | FX › No accepted rate | fx_rate_sources |
| X10 | Legs limited to accepted | Bridge; EUR→USD Market only (delete manual) | Convert EUR→INR | Refused with X9 message (sources Manual, Derived) | FX › Legs limited to accepted sources | fx_rate_sources |
| X11 | Invalid ISIN | — | ISIN wrong check digit | "ISIN is not valid" | MP › Invalid ISIN | market_prices |
| X12 | Market without identifiers | — | Market, no ticker/ISIN | "Market pricing needs a ticker and exchange, or an ISIN" | MP › Market without identifiers | market_prices |
| X13 | Duplicate ticker | ACMEIND exists | Another instrument ACMEIND/NSE | "Ticker already used by ACMEIND" | MP › Duplicate ticker | market_prices |
| X14 | Duplicate manual valuation | Manual exists | Add another Manual same date | Existing duplicate message | MP › Duplicate manual valuation | market_prices |
| X15 | Ticker not found | NSE stub omits RANGOLI | Run | Others stored; email names "Rangoli Textiles — ticker not found at NSE" | MP › Ticker not found | price_feed |
| X16 | Derivatives off for fund | Bridge | Open tab / direct URL | No tab; refused | DC › Fund without the feature | derivatives_listed |
| X17 | Entity derivatives off | Fund bit set, entity off | Direct URL | Refused | DC › Entity feature off | derivatives_listed |
| X18 | Other entity user | Omar | Contract URL | Refused | DC › Other entity's user | derivatives_listed |
| X19 | Option without strike | — | Save | "Strike can't be blank" | DC › Option without strike | derivatives_listed |
| X20 | OTC without counterparty | — | Save | "Counterparty can't be blank" | DC › OTC contract without counterparty | derivatives_listed |
| X21 | Event before trade date | Trade 12 Oct | Valuation 11 Oct | "must be on or after the trade date" | DC › Event before trade date | derivatives_listed |
| X22 | Event on closed contract | E50 | Add valuation | "Contract is closed" | DC › Event on a closed contract | derivatives_listed |
| X23 | Close more than open | 1 lot open | Close 2 | "Only 1 lots open" | DC › Close more lots than open | derivatives_listed |
| X24 | Put without enough shares | Holds 50 | Exercise put on 75 | "Fund holds only 50 shares of ACMEIND" | DC › Put exercised without enough shares | derivatives_listed |
| X25 | Read-only user records event | Ravi | POST event | Refused | DC › Fund without the feature | derivatives_listed |
| X26 | Swap without agreement | OTC phase | Save IRS | "Agreement can't be blank" | DC › Swap without agreement | derivatives_otc |
| X27 | Missing rate blocks NAV | No accepted USD→INR | Draft | "No USD→INR rate within 3 business days of 30 Oct 2026 (latest: none). Enter a manual rate or wait for the feed." | FX › Missing rate blocks the draft | nav_market_data |
| X28 | Missing price blocks NAV | Nimbus no price | Draft | "No price for Nimbus Inc on or before 30 Oct 2026" | MP › Missing price blocks the draft | nav_market_data |
| X29 | Missing derivative value | Open forward no valuation | Draft | "No valuation for FX forward on or before 30 Oct 2026" | DC › Missing derivative value blocks the draft | nav_market_data |
| X30 | Approve with open exception | Exception open | Direct POST approve | "Resolve or accept every exception first" | MP › Approve with an open exception | nav_market_data |
| X31 | Non-approver accepts | Meera | POST accept | Refused | MP › Non-approver cannot accept | nav_market_data |
| X32 | Exposure over limit | Exposure ₹9,00,00,000; NAV ₹4,33,75,000; limit 2× | Exposure report | 2.07× in red against 2.0×; NAV exception; Compliance + approvers emailed | DC › Exposure against NAV limit | exposure_limits |
| X33 | Upload names a fund without the feature | Bridge flag off | Rate upload row Fund = Bridge Hybrid Fund | Row refused: "Fund Bridge Hybrid Fund does not use fund-specific FX rates" | FX › Own rate for a fund without the feature | fx_rate_sources |
| X34 | Upload names another entity's fund | Omar's entity fund | Rate upload row Fund = that fund | Row refused: "Fund {name} not found" | FX › Own rate for a fund without the feature | fx_rate_sources |
| X35 | Market pricing on an uncovered exchange | Nimbus Inc on NASDAQ | Meera sets Pricing method Market | "No price feed covers NASDAQ; keep this holding Manual" | MP › Exchange not covered by a feed | market_prices |
| X36 | Hedging-only fund, no hedge link | Fund on SEBI Cat I/II preset | Record Nifty put, no hedge link | "This fund allows hedging contracts only — link the holding or class it hedges" | DC › Hedging-only fund, no hedge link | exposure_limits |
| X37 | Hedge larger than what it covers | Same fund; holding worth ₹50,00,000 | Record FX forward USD 1,00,000 (₹85,00,000) hedging it | "Hedge exceeds the value it covers (₹85,00,000 > ₹50,00,000)" | DC › Hedge larger than what it covers | exposure_limits |
| X38 | Naked short call | Naked short calls not allowed; fund holds 0 Rangoli | Record short call 1 × 500 | "Writing this call needs 500 shares of Rangoli Textiles; the fund holds 0" | DC › Naked short call | exposure_limits |
