# Fund Market Data — Manual QA Checklist

> **Audience:** Testers running the feature by hand on a deployed build. No code knowledge needed.
> **Companion documents:** [Proposal](proposal.md) · [Business rules](business-rules.md) · [Design](design.md)

> **How to use:** work top to bottom, one phase at a time. Tick ☐ → ☑ and write Pass or Fail for
> each row. For a Fail, put the defect link in Notes. Row IDs match the worked examples in
> [business-rules.md](business-rules.md) (H/E/X) and the UI journeys (J), so a failure maps straight
> to the automated test that should have caught it.

> **Open-ended NAV rows (phase 8) run only on a build that includes the open-ended funds work.** On a
> build from `market-data` alone, mark them N/A.

**ID legend:** **H** = Happy path · **E** = Edge case · **X** = Error case · **J** = UI journey
step (J2.3 = journey 2, step 3) · **R** = Role sweep · **C** = Cross-cutting check

---

## Contents

- [Test Setup](#test-setup)
- [Phase 1 — Entity features, fund features and settings](#phase-1--entity-features-fund-features-and-settings)
- [Phase 2 — FX rate sources per fund](#phase-2--fx-rate-sources-per-fund)
  - [Fund-specific (own) FX rates](#fund-specific-own-fx-rates)
- [Phase 3 — FX rate feed](#phase-3--fx-rate-feed)
- [Phase 4 — Instruments and prices](#phase-4--instruments-and-prices)
- [Phase 5 — Price feed and corporate actions](#phase-5--price-feed-and-corporate-actions)
- [Phase 6 — Listed derivatives and FX forwards](#phase-6--listed-derivatives-and-fx-forwards)
- [Phase 7 — OTC swaps](#phase-7--otc-swaps)
- [Phase 8 — Open-ended NAV](#phase-8--open-ended-nav)
- [Phase 9 — Derivative exposure limits (later release)](#phase-9--derivative-exposure-limits-later-release)
- [UI Journeys](#ui-journeys)
- [Role Sweep](#role-sweep)
- [Cross-cutting Checks](#cross-cutting-checks)
- [Sign-off](#sign-off)

---

## Test Setup

| Item | Detail |
|---|---|
| Environment | Staging build of `market-data` (phases 1–7); a build that also includes open-ended funds for phase 8 |
| Accounts | **Priya** — CapHive support · **Kavya** — entity admin of Caphive Capital · **Meera** — fund staff with update access to all three funds, tagged *FundAccounting* · **Arjun** — NAV approver of Horizon Evergreen Fund · **Ravi** — fund staff with read-only access · an **investor** user in Growth AIF II and Bridge Hybrid Fund |
| Second entity | **Omar** — a user of a different entity, for isolation checks |
| Seed data | Entity **Caphive Capital** (INR). Funds **Growth AIF II** (INR), **Bridge Hybrid Fund** (INR), **Horizon Evergreen Fund** (INR, open-ended for phase 8). Rates: USD→INR Manual 83.00 dated 1 Apr 2026; EUR→USD Manual 1.07 dated 30 Sep 2026; INR→GBP Manual 0.0095 dated 30 Oct 2026. Instruments: **ACMEIND** (INR) with Manual valuation ₹1,100 dated 30 Sep; **Nimbus Inc** (USD), 1,000 shares bought at $100 on a date with rate 83.00 by Horizon and by Growth AIF II; **Private Co A** (INR), Manual ₹500 dated 30 Sep, 10,000 shares held by Horizon; **Rhein AG** (EUR), Manual. Horizon 30 Oct (phase 8): cash ₹30,00,000, other assets ₹5,00,000, management fee payable ₹2,00,000, 4,00,000 units |
| Market data on staging | Live feeds are not reachable or repeatable on staging. Ask a developer to run each job **for a given date** with the test files in place (rates: USD→INR 85.00 ECB via EUR and EUR→USD 1.08 ECB for 30 Oct; prices: ACMEIND ₹1,020 for 23 Oct and ₹1,250 for 30 Oct, Nimbus $120 for 30 Oct, Nifty put settlement ₹333.33 for 30 Oct), or to simulate a provider failure where a row says so |
| Background work | **FX feed:** ask a developer to run `MarketData::FxFeedJob` for the date. **Price feed and corporate actions:** ask a developer to run `MarketData::PriceFeedJob` for the date. **Expiry reminders:** ask a developer to run `MarketData::DerivativeExpiryJob` for the date. **Test feed:** the *Test feed* button on Entity › Settings › Market Data runs straight away and stores nothing. Fair-value recomputes after a rate, price or setting change run in the background: wait a minute, then refresh |
| Mail | Check the staging mail catcher for Meera's inbox |

---

## Phase 1 — Entity features, fund features and settings

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Support switches on the entity features | Caphive Capital has none of the three on | 1. As Priya, open Admin › Entities › Caphive Capital › Edit. 2. Tick *Market FX rates*, *Market prices*, *Derivatives*. 3. Save. 4. Log in as Kavya and open Entity › Settings | The three features show as on. Kavya sees the **Market Data** card | | |
| ☐ | H2 | Admin sets feeds and defaults | H1 | 1. As Kavya, open Entity › Settings › Market Data. 2. Turn on the FX feed (ECB) and the price feed (NSE, BSE, AMFI). 3. Pivot USD; fund defaults *Manual only*, rate age 3, price age 3, threshold 10 %. 4. Save | Saved. The card lists "Pairs tracked: USD→INR, EUR→USD" and the next run time | | |
| ☐ | H3 | Fund chooses its features | H1 | 1. As Meera, open Horizon › Edit › Features. 2. Tick *Market* (FX rates), *Derived*, *Market* (prices) and *Derivatives*. 3. Save. 4. Open the fund's audit trail | Features saved, and the audit trail shows the change. *Manual (always)* is ticked for rates and prices and can't be unticked | | |
| ☐ | E1 | Entity with no market-data feature | A second test entity with none of the three features on, holding a foreign-currency holding | 1. Note a holding's fair value and a commitment's converted amount before the deploy (or compare with production). 2. Open a fund's Edit form, Entity › Settings and the fund page | No Market Data card, no market-data switches, no Derivatives or Corporate actions tab. Fair value and converted amounts are identical to before | | |
| ☐ | E2 | Switch hidden when the entity feature is off | Entity without *Market FX rates* | Open any fund's Edit › Features | No *Market* checkbox under FX rates | | |
| ☐ | E3 | New fund starts with entity defaults | Kavya sets the default to Manual + Market FX rates | 1. Create a new fund. 2. Open Edit › Features | FX rates show Manual and Market ticked | | |
| ☐ | E4 | Existing switches carried over | A fund that showed portfolio and fund units to LPs but not fund ratios before the deploy | Open its Edit › Features | *Show portfolio to LPs* and *Show fund units to LPs* ticked; *Show fund ratios to LPs* not ticked | | |
| ☐ | E5 | Investor access unchanged | Growth AIF II shows portfolio to LPs; Bridge Hybrid does not | 1. As the investor, open Growth AIF II's portfolio. 2. Open Bridge Hybrid's portfolio (direct URL too) | First is shown; second is refused, as before | | |
| ☐ | E6 | Fund upload keeps its columns | — | 1. Upload a fund with "Show Fund Ratios To Lps" = Yes and "Show Fund Portfolios To Lps" = No. 2. Open the new fund's Features | Show fund ratios to LPs on; Show portfolio to LPs off | | |
| ☐ | E7 | Blank limit uses entity default | Entity default rate age 3; Horizon is open-ended (phase 8 build) | 1. Leave *Max rate age* blank on Horizon. 2. Save and reopen | The field is blank with placeholder 3; the NAV uses 3 business days (see E58) | | |
| ☐ | E8 | Limits hidden on a closed-ended fund | — | Open Growth AIF II › Edit › Features | No *Limits* group | | |
| ☐ | E9 | Changing defaults leaves existing funds alone | Existing funds in the entity; default Manual only | 1. As Kavya, change new-fund defaults to Manual + Market FX rates. 2. Open an existing fund's Features. 3. Create a new fund and open its Features | The existing fund is unchanged; the new fund has *Accept market FX rates* ticked | | |
| ☐ | E10 | Entity feature switched off later | Horizon accepts Market FX rates | 1. As Priya, untick *Market FX rates* on the entity. 2. Check Nimbus Inc's value in Horizon. 3. Tick it on again | While off, Horizon values Nimbus at the Manual 83.00 and the Market switch is hidden. Once it's back on, the Market box is ticked again | | |
| ☐ | X1 | Non-support user cannot switch entity features | — | As Kavya, try to reach Admin › Entities › Caphive Capital › Edit (ask a developer to send the change directly) | Refused; features unchanged | | |
| ☐ | X2 | Price feed on with no provider | — | 1. As Kavya, turn on the price feed. 2. Untick every provider. 3. Save | "Choose at least one provider" | | |
| ☐ | X3 | Unavailable switch submitted directly | Entity without *Market prices* | Ask a developer to send a fund update with *Accept market prices* on | Refused; the fund's features are unchanged | | |
| ☐ | X4 | Age out of range | Open-ended fund | Enter *Max rate age* 31 and save | "must be between 0 and 30" | | |
| ☐ | X5 | Threshold out of range | Open-ended fund | Enter *Price move threshold* 0 and save | "must be between 1 and 100" | | |

## Phase 2 — FX rate sources per fund

Funds set as in the proposal: Growth AIF II *Manual only*; Bridge Hybrid *Manual + Derived* rates and *Manual + Market* prices; Horizon *Manual + Market + Derived* rates, *Manual + Market* prices, derivatives on. USD→INR Market 85.00 for 30 Oct loaded (phase 3 job, or entered by a developer as Market).

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H5 | Two funds, two rates | Setup above | Open Nimbus Inc in Growth AIF II, then in Horizon, as of 30 Oct | Growth AIF II: 1,000 × $120 × 83.00 = ₹99,60,000. Horizon: 1,000 × $120 × 85.00 = ₹1,02,00,000 | | |
| ☐ | H9 | Gain split into price and currency | H5 | Open Nimbus Inc's holding in Horizon | Gain ₹19,00,000 = price effect ₹17,00,000 + currency effect ₹2,00,000 | | |
| ☐ | E16 | Existing rates become Manual | Rates that existed before the deploy | Open Exchange Rates | Every old rate shows Source *Manual*. Fair values match pre-deploy | | |
| ☐ | E17 | Manual and Market on the same date are both kept | Add Manual USD→INR 84.80 for 30 Oct | Filter Exchange Rates to USD→INR | Both rows listed: Manual 84.80 and Market 85.00 | | |
| ☐ | E18 | Manual wins on the same date | E17 | Recheck Nimbus Inc in Horizon for 30 Oct | Valued at 84.80 | | |
| ☐ | E19 | Newer market beats older manual | Manual USD→INR dated 26 Oct; Market dated 30 Oct; no Manual 30 Oct | Value Nimbus in Horizon for 30 Oct | Uses the Market rate | | |
| ☐ | E20 | Manual-only fund ignores newer market | Setup above | Value Nimbus in Growth AIF II for 30 Oct | Uses 83.00 (1 Apr) | | |
| ☐ | E21 | Cross rate from manual legs | Bridge Hybrid buys Rhein AG; Manual EUR→USD 1.07 and USD→INR 83.00 | Save the purchase; open Exchange Rates | Uses EUR→INR 88.81, listed as *Derived (via USD)* dated 1 Apr | | |
| ☐ | E22 | Reverse rate | Only Manual INR→GBP 0.0095 | Book a GBP amount in a fund that accepts Derived | Uses 105.26315789, listed as *Derived (reverse)* | | |
| ☐ | E23 | Newer derived beats older direct | Horizon: Manual EUR→INR 90.00 dated 1 Jan; Market EUR→USD 1.08 and USD→INR 85.00 dated 30 Oct | Convert EUR→INR in Horizon for 30 Oct | Uses 1.08 × 85.00 = 91.80 (dated 30 Oct), not 90.00 | | |
| ☐ | E24 | Leg corrected | E23's derived row not used by any booked record | 1. Add Manual USD→INR 84.80 for 30 Oct. 2. Convert again | The old derived row is gone; the new one is 1.08 × 84.80 = 91.584 | | |
| ☐ | E25 | Derived rate starts no jobs | Commitment-adjustment option on | Trigger E21; ask a developer to check the job queue | No recompute and no commitment adjustment started by the derived row | | |
| ☐ | E26 | Same currency | — | Book an INR amount in an INR fund | Rate 1; no rate row needed | | |
| ☐ | E27 | Entity-level conversion uses entity defaults | Entity default *Manual only* | Open a portfolio company KPI conversion to INR | Only Manual rates are used (83.00, not 85.00) | | |
| ☐ | E28 | Allocation run uses the same rate | Horizon | Ask a developer to run an allocation that converts a 30 Oct USD amount | Same rate as the screens (85.00) | | |
| ☐ | E29 | A market rate recomputes only funds that accept it | Note Growth AIF II's and Horizon's Nimbus values | Ask a developer to load a new Market USD→INR rate | Horizon's value changes; Growth AIF II's does not | | |
| ☐ | E30 | A fed rate creates no commitment adjustment | Commitment-adjustment option on; a USD folio | Load a Market rate | No new "Exchange Rate" commitment adjustment | | |
| ☐ | E31 | Changing accepted sources | Growth AIF II USD commitment booked at 83.00 | 1. Tick *Market* FX rates on Growth AIF II. 2. Wait, refresh. 3. Open the commitment and the audit trail | Fair value now at 85.00; the commitment amount is unchanged; the audit trail shows the change | | |
| ☐ | E32 | Split adds up after rounding | A holding: 7 shares bought at $13.37 at 83.1234, valued $14.11 at 84.0567 | Open the holding | Total ₹522.76 = price ₹435.41 + currency ₹87.35 | | |
| ☐ | E33 | Realised split on a sale | Horizon sells 400 Nimbus at $125 at 85.50 | Open the sale | Realised ₹9,55,000 = price ₹8,55,000 + currency ₹1,00,000 | | |
| ☐ | X8 | Duplicate manual rate | A Manual USD→INR exists for a date | Add another Manual USD→INR for the same date | The existing duplicate-rate message; not saved | | |
| ☐ | X9 | No accepted rate | Growth AIF II; no Manual EUR→INR | Book a Rhein AG purchase dated 30 Oct | "No EUR→INR rate on or before 30 Oct 2026 in this fund's accepted sources (Manual). Enter a manual rate, or accept derived rates for this fund." | | |
| ☐ | X10 | Legs limited to accepted sources | Bridge Hybrid; delete the Manual EUR→USD so EUR→USD exists only as Market | Book a Rhein AG amount in Bridge | Refused with the X9 message naming sources (Manual, Derived) | | |

### Fund-specific (own) FX rates

A rate can optionally belong to one fund. Entity-wide is the default. The fund feature *Use
fund-specific FX rates* needs no entity feature. With it on, the rate form shows an optional
**Fund** select and the upload accepts an optional **Fund** column. A fund's own rates are Manual,
and only that fund uses them. Latest date wins; on the same date the order is fund's own > entity
manual > market > derived.

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H21 | A fund's own rate is used by that fund only | Horizon has *Use fund-specific FX rates* on. Entity rates as in setup (Manual USD→INR 83.00 dated 1 Apr; Market 85.00 dated 30 Oct) | 1. Exchange Rates › New: USD→INR 84.50 for 30 Oct, **Fund** = Horizon Evergreen Fund. 2. Value Nimbus Inc in Horizon, Bridge Hybrid and Growth AIF II for 30 Oct. 3. Open an entity-level report (e.g. a portfolio company KPI in INR) | Horizon uses 84.50. Bridge Hybrid and Growth AIF II use 83.00. The entity report doesn't use 84.50. The rate row shows the fund's name | | |
| ☐ | E68 | Same-date own rate beats entity manual | H21; also an entity Manual USD→INR 84.80 for 30 Oct | Value Nimbus in Horizon for 30 Oct | Uses the fund's own 84.50 | | |
| ☐ | E69 | Newer entity rate beats older own rate | Horizon own USD→INR 84.50 dated 26 Oct; entity Market 85.00 dated 30 Oct | Value Nimbus in Horizon for 30 Oct | Uses 85.00 (latest date wins) | | |
| ☐ | E70 | Feature off: own rate ignored | H21 | 1. Untick *Use fund-specific FX rates* on Horizon. 2. Revalue Nimbus for 30 Oct. 3. Open Exchange Rates | Uses 85.00. The own 84.50 is still listed (kept, not deleted) | | |
| ☐ | E71 | Cross rate built from the fund's own leg | Horizon (accepts Derived) has the feature on; own USD→INR 84.50 for 30 Oct; Market EUR→USD 1.08 for 30 Oct; no EUR→INR | Book a Rhein AG (EUR) amount in Horizon for 30 Oct | EUR→INR = 1.08 × 84.50 = 91.26, listed as *Derived (via USD)* with Fund = Horizon. Other funds don't use it | | |
| ☐ | E72 | An own rate adjusts and recomputes only its fund | Commitment-adjustment option on; USD folios in Horizon and Growth AIF II | Add an own Manual USD→INR rate for Horizon | Only Horizon's holdings recompute and only its USD folio gets an "Exchange Rate" commitment adjustment. Growth AIF II is unchanged | | |
| ☐ | X33 | Upload names a fund without the feature | Bridge Hybrid has *Use fund-specific FX rates* off | Upload exchange rates with **Fund** = Bridge Hybrid Fund | Row refused with "Fund Bridge Hybrid Fund does not use fund-specific FX rates" | | |
| ☐ | X34 | Upload names another entity's fund | A fund named "Omar Growth Fund" exists only in Omar's entity | Upload a rate with **Fund** = Omar Growth Fund | Row refused with "Fund Omar Growth Fund not found" | | |

## Phase 3 — FX rate feed

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H4 | Feed loads a rate | H2 | Ask a developer to run `MarketData::FxFeedJob` for 30 Oct; open Exchange Rates | USD→INR 85.00, Source *Market*, Provider *ECB via EUR*, Rate type *Reference*, dated 30 Oct | | |
| ☐ | E11 | Re-run doesn't duplicate | H4 | Run the job again for 30 Oct | Still one Market USD→INR row for 30 Oct; *Run history* shows the run updated | | |
| ☐ | E12 | New pair tracked | — | 1. Add a fund in GBP. 2. Reopen the Market Data card. 3. Run the job | GBP pair listed under Pairs tracked and fetched | | |
| ☐ | E13 | Weekend skipped | — | Run the job for Sat 31 Oct | Nothing fetched; no run in Run history; no email | | |
| ☐ | E14 | Some pairs missing | The entity holds an AED instrument (the ECB file has no AED) | Ask a developer to run the FX feed for 30 Oct | USD→INR stored; Run history shows *partial*; Meera gets one email listing only AED→INR | | |
| ☐ | E15 | Upload without a Source column | — | Upload exchange rates with the standard headers only | Rows stored as *Manual*, Provider *Upload* | | |
| ☐ | E73 | Market data stays in its entity | A second entity (Northwind), also on the ECB feed | 1. Ask a developer to run both entities' FX feeds for 30 Oct. 2. Delete Caphive's Market USD→INR row. 3. Open Exchange Rates in Northwind | Northwind still lists its own 85.00 Market row and never shows Caphive's | | |
| ☐ | X6 | Provider down | Ask a developer to make ECB via EUR fail | Run for Thu 29 Oct; run again | Run history shows *failed*. Meera receives **one** email "FX feed: no rates loaded for Oct 29, 2026" listing USD→INR; the second run sends no second email | | |
| ☐ | X7 | Invalid rate from provider | Ask a developer to make the provider return 0 for USD→INR | Run | No row stored for that pair; listed as missing; run *partial* | | |

## Phase 4 — Instruments and prices

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H6 | Instrument set to Market | ACMEIND Manual | Edit ACMEIND: ticker ACMEIND, exchange NSE, Pricing method *Market*; save | *Market* badge shown | | |
| ☐ | H7 | Two funds, two prices | ACMEIND: Manual ₹1,100 (30 Sep), Market ₹1,250 (30 Oct); both funds hold it | Value ACMEIND for 30 Oct in Bridge Hybrid and in Growth AIF II | Bridge ₹1,250; Growth AIF II ₹1,100 | | |
| ☐ | E34 | Existing instruments become Manual; ISIN copied | An instrument with the SEBI ISIN custom field filled | Open it | Pricing method *Manual*; ISIN field shows the same ISIN; fair value unchanged | | |
| ☐ | E35 | Switching to Market keeps history | ACMEIND has Manual valuations | Set Market; run the price feed | Manual rows still listed; Market rows added | | |
| ☐ | E36 | Existing valuations become Manual | Pre-deploy valuations | Open Valuations | Source *Manual*; fair values unchanged | | |
| ☐ | E37 | Upload with Price Type | — | Upload a valuation with Price Type *Mid* | Stored with Price type *Mid*, Source *Manual* | | |
| ☐ | E38 | Manual beats Market on the same date | Manual ₹1,240 and Market ₹1,250 for 30 Oct | Value ACMEIND in Bridge for 30 Oct | ₹1,240 | | |
| ☐ | E39 | Market beats Cost on the same date | Market close ₹1,250 for 30 Oct | Horizon buys ACMEIND on 30 Oct at ₹1,230; value for 30 Oct | ₹1,250 | | |
| ☐ | E40 | Purchase never overwrites | E39 | Open ACMEIND's valuations | Market ₹1,250 unchanged; a *Cost* ₹1,230 row added | | |
| ☐ | E41 | Manual-only fund uses Cost | Growth AIF II; Manual EUR→INR 88.81 entered | Buy Rhein AG; value it | Value = the purchase's Cost price | | |
| ☐ | X11 | Invalid ISIN | — | Enter an ISIN with a wrong check digit | "ISIN is not valid" | | |
| ☐ | X12 | Market without identifiers | — | Choose *Market* with no ticker, exchange or ISIN | "Market pricing needs a ticker and exchange, or an ISIN" | | |
| ☐ | X13 | Duplicate ticker | ACMEIND/NSE exists | Give another instrument ticker ACMEIND, exchange NSE | "Ticker already used by ACMEIND" | | |
| ☐ | X14 | Duplicate manual valuation | A Manual valuation exists for that date | Add another Manual for the same instrument and date | The existing duplicate message | | |
| ☐ | X35 | Market pricing on an uncovered exchange | Nimbus Inc on NASDAQ | Portfolio › Instruments › Edit Nimbus Inc; set *Pricing method* Market; Save | "No price feed covers NASDAQ; keep this holding Manual" | | |

## Phase 5 — Price feed and corporate actions

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H8 | Price feed loads prices | H6 | Ask a developer to run `MarketData::PriceFeedJob` for 30 Oct | ACMEIND ₹1,250, Source *Market*, Provider *NSE*, Price type *Close* | | |
| ☐ | H10 | Split suggested and confirmed | Test file reports a 1:2 split for ACMEIND | 1. Run the price feed. 2. Open Portfolio › Corporate actions. 3. Click *Confirm* and save the pre-filled Stock Adjustment | Meera gets one email about the suggestion. A Stock Adjustment is created: quantities doubled, prices halved | | |
| ☐ | E42 | Mutual fund matched by ISIN | A Market instrument with only an ISIN | Run the price feed | The AMFI NAV is stored as its Market price | | |
| ☐ | E43 | One recompute per holding | Three Market instruments of one portfolio company | Run the feed; ask a developer to check the jobs | One recompute per company and instrument, not one per price | | |
| ☐ | E44 | Re-run doesn't duplicate | H8 | Run again for 30 Oct | One Market row per instrument for 30 Oct | | |
| ☐ | E45 | Test feed | ACMEIND and Rangoli Textiles set to Market on NSE | Entity › Settings › Market Data › *Test feed* | The results card reads "2 of 2 found" and lists each item. Nothing is stored | | |
| ☐ | E46 | Suggestion dismissed | A suggested dividend | 1. Click *Dismiss*. 2. Run the feed again with the same dividend reported | Nothing changes; no new suggestion | | |
| ☐ | E47 | Reported again | A pending split | Run the feed again | No new suggestion; no new email | | |
| ☐ | X15 | Ticker not found | Ask a developer to leave RANGOLI out of the NSE test file | Run for 30 Oct | Other prices stored. Meera gets "Price feed: no prices loaded for Oct 30, 2026" naming "Rangoli Textiles — ticker not found at NSE" | | |

## Phase 6 — Listed derivatives and FX forwards

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H11 | Listed put recorded | Horizon has Derivatives on | Horizon › Derivatives › *New contract*: long Nifty put, 1 lot × 75, strike 24,000, expiry 26 Nov 2026, premium ₹40,000 paid, NSE, cash-settled | Open contract listed. A ledger entry "Derivative Premium" of −₹40,000 appears | | |
| ☐ | H12 | FX forward recorded | — | New contract: short USD→INR forward, USD 1,00,000 at 84.00, maturity 29 Jan 2027, counterparty Bank X | Open contract; no premium entry | | |
| ☐ | H13 | Listed contract valued from the feed | H11; test file settlement price ₹333.33 | Run the price feed for 30 Oct | Value ₹24,999.75, Source *Market · NSE*. Ledger "Derivative Unrealised Gain/Loss" −₹15,000.25 | | |
| ☐ | H14 | Counterparty upload | H12 | *Upload valuation*: −1,50,000 at 30 Oct, Bank X | Value −₹1,50,000 *(Upload · Bank X)*, shown as a liability | | |
| ☐ | H15 | Call exercised into shares | Long call ACMEIND 1 × 75, strike ₹1,000, premium ₹7,500 | *Add event › Exercise* for 1 lot | A purchase of 75 ACMEIND at ₹1,100 per share; contract *Closed* | | |
| ☐ | H16 | Forward hedges a holding | H12, *Hedges* = Nimbus Inc | Open Nimbus Inc's holding in Horizon | "Hedged by: FX forward, sell USD 1,00,000 @ 84.00 (−₹1,50,000)" | | |
| ☐ | E48 | Short option receives premium | — | Record a short call with premium ₹30,000 received | Ledger "Derivative Premium" +₹30,000 | | |
| ☐ | E49 | Partial close-out | Long put, 2 lots, premium ₹80,000 | Close out 1 lot for ₹18,000 received | 1 lot open; realised −₹22,000 posted | | |
| ☐ | E50 | Option expires worthless | H11 | *Add event › Expiry*, nothing received | Contract *Closed*; realised loss ₹40,000 | | |
| ☐ | E51 | Double submission | An open call | Click *Save* on an exercise twice quickly | One exercise event; one share purchase | | |
| ☐ | E52 | Contract in a foreign currency | A USD contract valued $2,000; Horizon accepts Market rates (85.00) | Open the contract | Value ₹1,70,000 | | |
| ☐ | E53 | Put exercised physically | Long put ACMEIND 1 × 75, strike ₹1,300; Horizon holds 20,000 | Exercise | Sale of 75 ACMEIND at ₹1,300, using the fund's cost method | | |
| ☐ | E54 | Cash-settled exercise | An index option | Exercise for ₹12,000 received | Settlement entry +₹12,000; no holding created | | |
| ☐ | E55 | Contract hedges a share class | — | Set *Hedges* to unit type "Class B"; save | Contract shows "Hedges: Class B" | | |
| ☐ | E57 | Expiry reminder sent once | The put expires 26 Nov | Ask a developer to run `MarketData::DerivativeExpiryJob` for 19 Nov, then for 20 Nov | One reminder email, on 19 Nov | | |
| ☐ | X16 | Derivatives off for the fund | Bridge Hybrid (Derivatives off) | Open the fund; try the derivatives URL directly | No Derivatives tab; direct URL refused | | |
| ☐ | X17 | Entity derivatives off | Ask a developer to leave a fund's derivatives bit set; untick the entity feature | Open the derivatives URL | Refused; tab hidden | | |
| ☐ | X18 | Other entity's user | Omar | Open a Horizon contract URL | Refused; nothing shown | | |
| ☐ | X19 | Option without strike | — | Save an option with no strike | "Strike can't be blank" | | |
| ☐ | X20 | OTC contract without counterparty | — | Save an OTC forward with no counterparty | "Counterparty can't be blank" | | |
| ☐ | X21 | Event before the trade date | Trade date 12 Oct | Add a valuation dated 11 Oct | "must be on or after the trade date" | | |
| ☐ | X22 | Event on a closed contract | E50 | Add a valuation | "Contract is closed" | | |
| ☐ | X23 | Close more lots than open | 1 lot open | Close out 2 lots | "Only 1 lots open" | | |
| ☐ | X24 | Put exercised without enough shares | Fund holds 50 ACMEIND | Exercise a physically settled put on 75 | "Fund holds only 50 shares of ACMEIND" | | |
| ☐ | X25 | Read-only user records an event | Ravi | Try *Add event* (or ask a developer to send it directly) | Refused | | |

## Phase 7 — OTC swaps

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H17 | Interest-rate swap settlement | Pay-fixed IRS on ₹10 Cr with Bank X and an agreement document | Add a settlement: ₹2,10,000 paid fixed, ₹1,95,000 received floating | Settlement event −₹15,000; ledger entry posted | | |
| ☐ | X26 | Swap without agreement | — | Save an IRS with no agreement document | "Agreement can't be blank" | | |

## Phase 8 — Open-ended NAV

*Only on a build that includes open-ended funds. Horizon is open-ended; limits 3 / 3 / 10 %.*

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H18 | NAV with derivative lines | H13, H14, rates and prices for 30 Oct loaded | Horizon › NAVs › *Draft NAV* for 30 Oct | Investments ₹4,02,00,000; Derivative assets ₹25,000; Derivative liabilities ₹1,50,000; NAV ₹4,33,75,000; NAV per unit ₹108.44 | | |
| ☐ | H19 | Exception accepted, then approve | H18; ACMEIND moved ₹1,020 → ₹1,250 | 1. Check the Exceptions panel. 2. As Arjun, *Accept* with a note. 3. *Approve* | Panel shows "ACMEIND moved +22.5% (₹1,020 → ₹1,250); threshold 10%", then "Accepted by Arjun" with time and note; NAV *Approved* | | |
| ☐ | H20 | A rate change marks the NAV | H19 | Add Manual USD→INR 84.80 for 30 Oct; reopen the NAV | NAV shows "Inputs changed"; its figures don't change. Both USD→INR rows listed | | |
| ☐ | E58 | Rate at the age limit | Latest USD→INR dated Tue 27 Oct | Draft for Fri 30 Oct | No rate exception | | |
| ☐ | E59 | Rate older than the limit | Latest USD→INR dated Mon 26 Oct | Draft for Fri 30 Oct | Rate listed as an exception to accept or fix | | |
| ☐ | E60 | Move exactly at threshold | A Market price moved ₹1,000 → ₹1,100 | Draft | No move exception | | |
| ☐ | E61 | Stale market price | A Market price older than 3 business days | Draft | Listed as stale | | |
| ☐ | E62 | Private mark shows its age | Private Co A Manual ₹500 dated 30 Sep | Draft for 30 Oct | Line shows "Manual · 30 Sep (30d)"; no exception | | |
| ☐ | E63 | Redraft keeps an unchanged acceptance | Draft with ACMEIND accepted | Fix something unrelated; redraft | ACMEIND still accepted | | |
| ☐ | E64 | Redraft reopens a changed item | Draft with ACMEIND accepted | Correct ACMEIND's price; redraft | Exception open again | | |
| ☐ | E65 | Contract valued at zero | A contract valued exactly 0 | Draft | Adds to neither derivative line | | |
| ☐ | E66 | A valuation upload marks the NAV | A draft exists | Upload a forward valuation dated 30 Oct | "Inputs changed" | | |
| ☐ | E67 | Fund without contracts | An open-ended fund with no contracts | Draft | Both derivative lines 0; other figures as before | | |
| ☐ | X27 | Missing rate blocks the draft | No accepted USD→INR at all | Draft | "No USD→INR rate within 3 business days of 30 Oct 2026 (latest: none). Enter a manual rate or wait for the feed." | | |
| ☐ | X28 | Missing price blocks the draft | Nimbus has no accepted price | Draft | "No price for Nimbus Inc on or before 30 Oct 2026" | | |
| ☐ | X29 | Missing derivative value blocks the draft | The open forward has no valuation | Draft | "No valuation for FX forward on or before 30 Oct 2026" | | |
| ☐ | X30 | Approve with an open exception | An exception is open | Check the Approve button; ask a developer to send approve directly | Button disabled; direct request refused with "Resolve or accept every exception first" | | |
| ☐ | X31 | Non-approver cannot accept | Meera (not an approver) | Try *Accept* (or a direct request) | Refused | | |

---

## Phase 9 — Derivative exposure limits (later release)

Run only on a build that includes phase 9. % of NAV rows need an open-ended fund with an approved NAV.

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H22 | Cat III preset applied | Horizon has Derivatives on | Horizon › Derivatives › Limit profile; choose *SEBI Cat III AIF*; Save | Method *Commitment*, leverage limit 2.0×, naked short calls *not allowed* | | |
| ☐ | H23 | Within limits | Put and FX forward as in setup; NAV ₹4,33,75,000 approved; limit 2.0× | Open the exposure report | Put counts ₹18,00,000, forward ₹0; total 0.04× in green; no NAV exception | | |
| ☐ | E56 | Exposure with and without delta | Option with delta −0.30, 1 × 75 over an underlying at 24,500; another option with no delta | Open *Exposure report* | First row ₹5,51,250; second shows its notional labelled "full notional" | | |
| ☐ | E74 | Commitment nets a hedge | Commitment method; forward hedges Nimbus | Open the exposure report | Forward: gross ₹85,00,000, counted ₹0 | | |
| ☐ | E75 | Commitment nets opposite futures | Long and short Nifty future, 1 × 75 @ 24,500, same expiry | Open the exposure report | Gross ₹36,75,000, counted ₹0 | | |
| ☐ | E76 | Preset customised | Cat III profile | Change leverage limit to 1.5×; Save | Profile reads "SEBI Cat III AIF (customised)" | | |
| ☐ | E77 | Short put without delta | Short put 1 × 75 @ ₹1,000, no delta | Open the exposure report | Counts ₹75,000 | | |
| ☐ | E78 | Naked short calls allowed | Allow naked short calls ticked; fund holds no Rangoli | Record a short call on Rangoli Textiles, 1 × 500 | Recorded | | |
| ☐ | E79 | '40 Act preset excludes hedges | US '40 Act preset; put + FX forward hedge | Open the exposure report | Only the put counts | | |
| ☐ | E80 | Closed-ended fund | A fund that isn't open-ended, Derivatives on, leverage limit 2.0× | Open the exposure report | Amounts shown; % rows read "Checked on open-ended funds" | | |
| ☐ | E81 | Amber near the limit | Ask a developer to set up counted exposure ₹7,90,00,000; NAV ₹4,33,75,000; limit 2.0× | Open the exposure report | 1.82× in amber | | |
| ☐ | E82 | Exactly at the limit | Counted exposure ₹8,67,50,000 | Open the exposure report | 2.00× in amber, not red | | |
| ☐ | E83 | Bank counterparty over limit | Bank X (bank) owes the fund ₹50,00,000; bank limit 10 % | Open the exposure report | Bank X 11.5 % in red | | |
| ☐ | E84 | Negative value isn't counterparty exposure | Fund owes Bank X ₹1,50,000 | Open the exposure report | Bank X 0 % | | |
| ☐ | E85 | Non-bank counterparty over limit | Non-bank owes ₹26,00,000; limit 5 % | Open the exposure report | 6.0 % in red | | |
| ☐ | E86 | Single underlying over limit | ACMEIND holdings ₹2,50,00,000 + call ₹46,875; limit 50 % | Open the exposure report | ACMEIND 57.7 % in red | | |
| ☐ | E87 | Breach emailed once | X32 set up | Draft the NAV twice on 30 Oct | Compliance and approvers get one email | | |
| ☐ | E88 | Contract that would breach | Leverage 1.95×, limit 2.0× | Record a future that takes it to 2.10× | Popup "Leverage 1.95× → 2.10× (limit 2.0×)"; recorded after *Confirm* | | |
| ☐ | X32 | Exposure over the limit (leverage) | Exposure ₹9,00,00,000; latest approved NAV ₹4,33,75,000; limit 2× | Open *Exposure report* | "2.07×" in red against 2.0× | | |
| ☐ | X36 | Hedging-only fund, no hedge link | A fund on the SEBI Cat I/II preset | Record a Nifty put with no hedge link | "This fund allows hedging contracts only — link the holding or class it hedges" | | |
| ☐ | X37 | Hedge larger than what it covers | Same fund; holding worth ₹50,00,000 | Record an FX forward on USD 1,00,000 hedging it | "Hedge exceeds the value it covers (₹85,00,000 > ₹50,00,000)" | | |
| ☐ | X38 | Naked short call | Naked short calls not allowed; fund holds no Rangoli | Record a short call on Rangoli Textiles, 1 × 500 | "Writing this call needs 500 shares of Rangoli Textiles; the fund holds 0" | | |

## UI Journeys

**J1 — Meera chooses a fund's features** (design › What users see)

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J1.1 | Horizon › Edit fund | Open it | ① *Features* section; the six existing switches ticked as before the change | | |
| ☐ | J1.2 | Features › Market data | Look at the rows | ② Only rows whose entity feature is on | | |
| ☐ | J1.3 | Features › FX rates | Try to untick *Manual* | ③ Disabled, with the tooltip "Hand-entered values are always accepted so a wrong feed value can be corrected" | | |
| ☐ | J1.4 | Features › Limits (phase 8 build) | Leave fields blank | ④ Each blank field shows the entity default as placeholder | | |
| ☐ | J1.5 | Edit fund | *Save* | Fund page with a success message; fair values recompute in the background | | |
| ☐ | J1.6 | Features › Market data, on an entity with **no** market-data entity feature | Look for *Use fund-specific FX rates*; tick it and save | It is shown (it needs no entity feature) and saves | | |
| ☐ | J1.7 | Exchange Rates › New | Open the form once J1.6 is saved | An optional **Fund** select listing the funds that use fund-specific FX rates; blank = entity-wide | | |

**J2 — Set-up** (proposal › Workflow Journey Part A)

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J2.1 | Admin › Entities › Caphive Capital › Edit | Priya ticks the three features | Three features shown as on | | |
| ☐ | J2.2 | Entity › Settings › Market Data | Kavya sets feeds, pivot, defaults | "Feeds on. Pairs tracked: USD→INR, EUR→USD. Next run: today 18:30 IST" | | |
| ☐ | J2.3 | Fund › Edit › Features (each fund) | Meera sets Growth AIF II / Bridge / Horizon as in the proposal | Horizon shows *FX rates: Manual + Market + Derived* | | |
| ☐ | J2.4 | Portfolio › Instruments › Edit | Set ACMEIND (NSE) to Market; leave Nimbus Inc (NASDAQ) Manual | *Market* badge on ACMEIND; Nimbus shows *Manual* | | |
| ☐ | J2.5 | Horizon › Derivatives › New contract | Record the put and the forward | Two open contracts; −₹40,000 premium in the ledger | | |
| ☐ | J2.6 | Entity › Settings › Market Data › Test feed | Run it | "3 of 3 found", or each one not found with the reason | | |

**J3 — Every dealing date** (Part B; phase 8 build for J3.3–J3.7)

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J3.1 | Exchange Rates / Valuations | Developer runs both feeds for 30 Oct | New rows with Source *Market* | | |
| ☐ | J3.2 | Horizon › Derivatives › FX forward › Upload valuation | Upload −1,50,000 | "Value −₹1,50,000 (Bank X, 30 Oct)" | | |
| ☐ | J3.3 | Horizon › NAVs › Draft NAV | Draft 30 Oct | Breakdown with Source/age per line and the Exceptions panel | | |
| ☐ | J3.4 | Exceptions panel | Read the count | "1 to review" | | |
| ☐ | J3.5 | Exceptions › Enter rate/price | (If something is missing) enter it | Saved as Manual; exception gone after redraft | | |
| ☐ | J3.6 | Exceptions › Accept | Arjun accepts with a note | "Accepted by Arjun" | | |
| ☐ | J3.7 | NAV › Approve | Arjun approves | *Approved*; 30 Oct orders priced at ₹108.44 | | |

**J4 — If something changes later** (Part C)

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J4.1 | Exchange Rates › New | Add Manual USD→INR 84.80 for 30 Oct | Both rows; the Manual one marked *in use* | | |
| ☐ | J4.2 | Horizon › NAVs (phase 8) | Open the 30 Oct NAV | "Inputs changed" badge; approved figures unchanged | | |
| ☐ | J4.3 | Mail | Developer runs the expiry job for 19 Nov | Expiry reminder for the put | | |
| ☐ | J4.4 | Derivatives › Put › Add event › Expiry | Record expiry | Realised loss ₹40,000; *Closed* | | |
| ☐ | J4.5 | Portfolio › Corporate actions | Developer runs the price feed with a 1:2 split for ACMEIND | "1 suggested corporate action"; email to Meera | | |
| ☐ | J4.6 | Corporate actions › Confirm | Confirm | Stock Adjustment created; quantities doubled, prices halved | | |

---

## Role Sweep

✓ = allowed and works · ✗ = correctly blocked · ! = wrong.

| ID | Screen / action | CapHive support (Priya) | Entity admin (Kavya) | Fund staff, update (Meera) | Fund staff, read (Ravi) | Investor / advisor | Other-entity user (Omar) |
|---|---|---|---|---|---|---|---|
| R1 | Edit entity features (Admin › Entities) | ✓ | ✗ (view only) | ✗ | ✗ | ✗ | ✗ |
| R2 | View Market Data settings | ✓ | ✓ | ✓ | — | ✗ | ✗ |
| R3 | Edit Market Data settings / Test feed | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ |
| R4 | Edit fund Features | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ |
| R5 | View Derivatives tab / contract / exposure report | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ |
| R6 | Record contract, add event, upload valuation | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ |
| R7 | Accept a NAV exception (phase 8) | — | — | ✗ unless approver | ✗ | ✗ | ✗ |
| R8 | Approve NAV (phase 8) | — | — | ✗ unless approver (Arjun ✓) | ✗ | ✗ | ✗ |

Expected values come from the access tables in design cards ① and ⑥ and the NAV approver rule. Try
each ✗ by direct URL as well as through the screen.

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Emails: FX feed missing, price feed missing, corporate action suggested, contract expiring, NAV exceptions open (phase 8) | Each goes only to FundAccounting-tagged users (and approvers for NAV exceptions), arrives once, has working links, and shows dates as `Oct 29, 2026` | | |
| ☐ | C2 | Dates on changed screens (Exchange Rates, Valuations, Derivatives, Run history, NAV ages) | Follow the user's locale (e.g. `30/10/2026` for en, `10/30/2026` for en-US) | | |
| ☐ | C3 | Narrow / mobile width: Market Data card, fund Features section, Derivatives list, Exposure report, Corporate actions, NAV Exceptions panel | No horizontal scroll; buttons reachable | | |
| ☐ | C4 | Tenant isolation | Omar cannot see or reach Caphive Capital's settings, runs, rates, valuations, contracts, suggestions or NAV exceptions, even by direct URL | | |
| ☐ | C5 | Regression after the fund-switch migration | Fund show pages, investor fund details, commitment cards and investor details, remittance details, fund ratios and fund units visibility for investors, portfolio visibility (incl. master-fund portfolio access), AI commentary on account entry reports — all behave as before | | |
| ☐ | C6 | Regression on Exchange Rates, Valuations and Instruments screens and uploads | Create, list, delete and upload work as before (an upload without a **Fund** column creates entity-wide rates); new columns shown; existing figures unchanged | | |
| ☐ | C7 | Empty states | Derivatives list, Corporate actions, Run history and the Exceptions panel show a sensible message when empty | | |
| ☐ | C8 | Investors see nothing new | No new email or screen for investors; published NAV per unit unchanged in format | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
