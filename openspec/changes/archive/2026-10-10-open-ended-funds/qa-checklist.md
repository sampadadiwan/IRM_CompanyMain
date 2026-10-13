# Evergreen (Open-Ended) Funds — Manual QA Checklist

> **Audience:** Testers running the feature by hand on a deployed build. No code knowledge needed.
> **Companion documents:** [Proposal](proposal.md) · [Design](design.md)

> **How to use:** work top to bottom. Tick ☐ → ☑ and write Pass or Fail for each row. For a Fail, put the defect link in Notes. Row IDs match the design's worked examples (H/E/X) and UI journeys (J), so a failure maps straight to the automated test that should have caught it.

**ID legend:** **H** = Happy path · **E** = Edge case · **X** = Error case · **J** = UI journey step (J2.3 = journey 2, step 3) · **R** = Role sweep · **C** = Cross-cutting check

---

## Contents

- [Test Setup](#test-setup)
- [Happy Path](#happy-path)
- [Edge Cases](#edge-cases)
- [Error Cases](#error-cases)
- [UI Journeys](#ui-journeys)
- [Notifications](#notifications)
- [Dealing-date documents](#dealing-date-documents)
- [Role Sweep](#role-sweep)
- [Cross-cutting Checks](#cross-cutting-checks)
- [Sign-off](#sign-off)

---

## Test Setup

| Item | Detail |
|---|---|
| Environment | Staging (IN), and separately staging (US) for C1–C2 date checks |
| Accounts | **Asha** — fund admin of Alpha Long-Short Fund (Caphive Demo). **Ravi** — user with the Approver role on Alpha. **Meera** — compliance user who approves KYCs. **P Family Trust**, **Q Capital**, **A Ltd**, **B LLP**, **C HUF**, **D Partners** — investor users with access to Alpha |
| Second entity | **Gamma Advisors** with an admin user; evergreen funds switched **off** (used in E47, R-rows and C4) |
| Entity switch | Ask support to switch on "Evergreen funds" for Caphive Demo (entity settings) before starting |
| Seed data | Follow design.md → Worked examples → Shared setup exactly: Alpha Long-Short Fund (class A, 1,00,000 units at 31 Oct 2026; folios F-012 12,000, F-031 7,000, F-044 2,000, F-050 4,000; others 75,000), Infra Co and Pharma Co holdings, Cash In Hand ₹8,00,00,000, Other Liabilities ₹30,00,000, 30 Sep NAV ₹9,980.69, and redemption orders from A, B, C. **Beta Growth Fund** — an existing closed-end fund with a call, remittances, a distribution and unit prices |
| Dates | Rows quote dates in Oct–Dec 2026. On staging, ask a developer to set the app clock (time travel) for the row, or substitute today's equivalents and keep the same day gaps (cut-off = 5 days before dealing; notice = 30 days) |
| Background work | Dealing dates are generated nightly; ask a developer to run "DealingDateGenerateJob" now. Journey steps that depend on the cut-off update every 15 minutes, or immediately when the dealing date page is reloaded. Units and documents after a payment usually appear within a minute; refresh the dealing date page |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Make a fund evergreen with defaults | A closed-end fund in Caphive Demo with unit class A | 1. Sign in as the user named in the step. 2. Asha opens Settings, clicks **Make this fund evergreen**, sets class A's initial price ₹10,000 and saves | "This fund is now evergreen". Settings show monthly subscriptions, quarterly redemptions, first business day, before dealing, 5-day cut-off, Roll, journeys off, all redemption forms, 10 days, no gate (fund level, per dealing date, pro-rata, no investor gate). The fund shows evergreen tabs | | |
| ☐ | H2 | Apply a preset | The settings form open | 1. Sign in as the user named in the step. 2. Asha picks "US evergreen / tender-offer fund" | The form shows quarterly redemptions, before dealing, 5 % fund gate per calendar quarter, pro-rata, 12-month soft lock-up 2 %; nothing saved until **Save** | | |
| ☐ | H3 | Draft a NAV from CapHive data | Alpha at 31 Oct as in shared setup, with Pharma Co's valuation present | 1. Sign in as the user named in the step. 2. Asha clicks **New NAV** for 31 Oct 2026 | A class A draft with fair value ₹95,00,00,000, cash ₹8,00,00,000, other liabilities ₹30,00,000, management fee payable ₹50,00,000 (after H4), units 1,00,000, NAV ₹102,20,00,000, NAV per unit ₹10,220.00; each line shows its source | | |
| ☐ | H4 | Override a line with reason | The H3 draft | 1. Sign in as the user named in the step. 2. Asha overrides Management fee payable to ₹50,00,000 with reason "per admin stmt" | The line shows ₹50,00,000 ✎ "per admin stmt"; NAV and NAV per unit recomputed | | |
| ☐ | H5 | Upload an administrator's NAV | No 30 Sep NAV | 1. Sign in as the user named in the step. 2. Asha uploads "A, 30 Sep 2026, 98,26,00,000, 98,450, 9,980.69" | A draft dated 30 Sep, source Uploaded, NAV per unit ₹9,980.69 | | |
| ☐ | H6 | Approve with a different approver | The H3 draft prepared by Asha | 1. Sign in as the user named in the step. 2. Ravi clicks **Approve** | Status Approved, approver and time recorded, lines read-only | | |
| ☐ | H7 | Investor subscribes through the wizard (pre-funded) | Today 20 Oct 2026; 31 Oct not yet approved, latest approved NAV per unit ₹9,980.69 (30 Sep) | 1. Sign in as the user named in the step. 2. P Family Trust enters ₹5,00,00,000, class A, reviews, acknowledges and submits | Step 1 shows "Dealt on 2 Nov 2026 · pay by 28 Oct" and indicative units ≈ 5,009.6736 "Indicative — final price is the NAV for 30 Sep 2026". The order is Pending for 2 Nov. Folio F-101 is opened. Step 3 and the email show "Pay ₹5,00,00,000 by Oct 28, 2026" with bank details and reference | | |
| ☐ | H8 | Pay-after-dealing acknowledgement | Alpha switched to pay after dealing | 1. Sign in as the user named in the step. 2. Q Capital subscribes ₹2,50,00,000 for 1 Dec 2026 | The wizard says "You'll receive payment instructions after the 1 Dec 2026 dealing date, with the exact units"; no folio opened; no instructions in the email | | |
| ☐ | H9 | Redeem a number of units with indicative value | A Ltd holds 9,064.5793 free units; approved NAV per unit ₹10,160.94; today 1 Dec 2026; B and C queued | 1. Sign in as the user named in the step. 2. A Ltd enters 2,000 units in the Redeem wizard and submits | Step 1: indicative value ≈ ₹2,03,21,880, fee none. Step 2: earliest dealing 1 Jan 2027, "you would be #3 in the queue". Order Pending | | |
| ☐ | H10 | Queue positions | Redemptions from A, B, C received 09:00, 10:00, 11:00 on one day | 1. Sign in as the user named in the step. 2. Asha opens Orders | Queue positions 1, 2, 3 | | |
| ☐ | H11 | Cancel a pending order | P's pending subscription for 1 Dec | 1. Sign in as the user named in the step. 2. P clicks **Cancel** | Status Cancelled; excluded from dealing; "Request cancelled" email sent; pre-funded subscription payment removed | | |
| ☐ | H12 | Journey on subscriptions only | Order journeys = Subscriptions | 1. Sign in as the user named in the step. 2. P subscribes and A Ltd redeems | P's order shows a step bar; A's redemption has none | | |
| ☐ | H13 | Order waiting on KYC | P's KYC pending | 1. Sign in as the user named in the step. 2. P subscribes | The order's current step is "Check investor KYC", named in What's needed now | | |
| ☐ | H14 | Redemption journey verified and accepted | Order journeys = both; A Ltd's redemption | 1. Sign in as the user named in the step. 2. Asha verifies the signatory; Ravi accepts | Journey at Ready to deal | | |
| ☐ | H15 | Investor uploads the signed form | P's order at "Collect signed subscription form" | 1. Sign in as the user named in the step. 2. P opens Requests and uploads the form | The timeline showed "Upload your signed subscription form [Upload]"; after upload the step is done | | |
| ☐ | H16 | Upcoming dealing dates before orders | Monthly dealing; no orders for 1 Jan 2027 | 1. Sign in as the user named in the step. 2. Asha opens Dealing → Dealing Dates and picks All dates in the filter | 1 Jan 2027 listed with cut-off 27 Dec 2026, step "Open for orders" | | |
| ☐ | H17 | Pre-funded step order | 2 Nov: P paid and verified, 31 Oct NAV approved, not confirmed | 1. Sign in as the user named in the step. 2. Asha opens the dealing date | Collect subscription money ✓, Approve NAV ✓, **Review and confirm dealing** current | | |
| ☐ | H18 | Preview subscription units | P ready ₹5,00,00,000; NAV per unit ₹10,220.00 | 1. Sign in as the user named in the step. 2. Asha opens pricing | P: 4,892.3679 units to allot | | |
| ☐ | H19 | FIFO over the gate | Fund NAV ₹102,20,00,000, 5 % FIFO; A, B, C requests | 1. Sign in as the user named in the step. 2. Asha opens pricing | A ₹3,00,00,000 filled; B ₹2,11,00,000 filled, ₹39,00,000 carried; C ₹0, ₹1,00,00,000 carried; gate ₹5,11,00,000 | | |
| ☐ | H20 | Pro-rata over the gate | Same, method pro-rata | 1. Sign in as the user named in the step. 2. Asha opens pricing | Each filled at 78.615 %: A ≈ ₹2,35,84,615, B ≈ ₹1,96,53,846, C ≈ ₹78,61,538 (units truncated to 4 decimals, value at ₹10,220.00), remainder carried | | |
| ☐ | H21 | Confirm creates settlements and notices | H18 + H19 preview | 1. Sign in as the user named in the step. 2. Asha confirms | "Subscription settlement — 2 Nov 2026" (P's payment, unit price ₹10,220.00) and "Redemption settlement — 2 Nov 2026" (A ₹3,00,00,000 2,935.4207 units; B ₹2,11,00,000 2,064.5793 units; both due 16 Nov) exist, linked to the dealing date. Gate notices go to B and C. No capital call or distribution notice is sent to anyone | | |
| ☐ | H22 | New subscriber, pay after dealing | Pay-after fund; Q (no folio) ₹5,00,00,000 ready | 1. Sign in as the user named in the step. 2. Asha confirms 1 Dec | Folio F-102 class A with subscribed ₹5,00,00,000 owns Q's subscription payment; payment instructions email with exact units | | |
| ☐ | H23 | Pay-after allotment on payment | H22 confirmed | 1. Sign in as the user named in the step. 2. Asha records and verifies Q's ₹5,00,00,000 on 6 Dec 2026 | Units allotted dated 6 Dec 2026; contract note sent | | |
| ☐ | H24 | Mark a redemption paid | H21 confirmed | 1. Sign in as the user named in the step. 2. Asha clicks **Mark paid** on A Ltd with date 10 Nov and reference | Row: Paid ✓, Units cancelled ✓ (exactly 2,935.4207), Advice sent ✓; F-012 holds 9,064.5793 | | |
| ☐ | H25 | Pre-funded allotment and contract note at confirmation | P paid and verified before cut-off | 1. Sign in as the user named in the step. 2. H21 confirm | F-101 holds 4,892.3679 class A units dated 2 Nov 2026. The contract note shows F-101, Class A, NAV date Oct 31, 2026, dealing date Nov 02, 2026, ₹10,220.00, 4,892.3679, ₹5,00,00,000. P's Transactions lists the allotment with the note | | |
| ☐ | H26 | Carried request heads the next queue | B carried 381.6047 units from 2 Nov; D Partners redeems on 10 Nov | 1. Sign in as the user named in the step. 2. Asha opens the 1 Dec pricing | B is ahead of D | | |
| ☐ | H27 | Monthly management-fee accrual feeds the next NAV | 31 Oct approved ₹102,20,00,000; formula seeded | 1. Sign in as the user named in the step. 2. Asha runs the fee formula for 1–30 Nov, then drafts the 30 Nov NAV | ₹12,60,000 accrued across folios by units; the 30 Nov draft's Management fee payable includes ₹12,60,000 | | |
| ☐ | H28 | Fee paid on its own schedule | Nothing payable at 30 Sep; accruals Oct ₹12,51,805, Nov ₹12,60,000, Dec ₹12,93,082; "Management Fee Paid" ₹38,04,887 on 5 Jan 2027 | 1. Sign in as the user named in the step. 2. NAVs drafted for 31 Oct, 30 Nov, 31 Dec, 31 Jan | Payable ₹12,51,805 → ₹25,11,805 → ₹38,04,887 → ₹13,12,192 (January only) | | |
| ☐ | H29 | Performance fee above the mark | Class with mark ₹10,000, no hurdle, 20 %; NAV per unit before fee ₹10,220; 1,00,000 units | 1. Sign in as the user named in the step. 2. Draft NAV | Accrued ₹44,00,000; NAV per unit after fee ₹10,176 | | |
| ☐ | H30 | Crystallisation raises the mark | H29 class; NAV dated 31 Dec 2026 (annual) | 1. Sign in as the user named in the step. 2. Ravi approves | Entries "Performance Fee Crystallised" totalling ₹44,00,000 across folios; mark becomes ₹10,176 | | |
| ☐ | H31 | Evergreen GP tabs | Alpha | 1. Sign in as the user named in the step. 2. Asha opens the fund. 3. Click Dealing, then NAV. 4. Open `?tab=evergreen-redemptions-tab` | Step 2: top row Dealing, NAV, Investors, Portfolio, Documents, Notifications, Access; no Commitments, Calls or Distributions. Step 3: Dealing shows Dealing Dates · Subscriptions (n) · Redemptions (n) with n = open orders; NAV shows NAV · Fees. Step 4: Dealing opens with Redemptions selected | | |
| ☐ | H32 | Funds list card | Alpha and Beta | 1. Sign in as the user named in the step. 2. Asha opens Funds | Alpha: Evergreen badge, NAV, NAV per unit, net flows, next dealing date; Beta unchanged | | |
| ☐ | H33 | Overview figures | 30 Nov approved ₹101,50,00,000 / ₹10,160.94; QTD allotted ₹5,00,00,000, paid ₹5,11,00,000 | 1. Sign in as the user named in the step. 2. Asha opens Overview | NAV ₹101.50 Cr, NAV/unit ₹10,160.94, net flows −₹0.11 Cr | | |
| ☐ | H34 | Redemptions list against the gate | B 381.6047 (queue #1), C 978.4736 (#2); ₹10,160.94; gate 5% | 1. Sign in as the user named in the step. 2. Asha opens the fund → Redemptions | One table, no second queue table. B Amount ≈ ₹38,77,462; C ≈ ₹99,42,211, Running total ₹1,38,19,674; both "Will be paid in full"; gate cards above the table (Gate, Requested for, Will be paid · %, Will be carried) | | |
| ☐ | H35 | Unit register totals | 12 folios, 99,892.3679 units; ₹10,160.94 | 1. Sign in as the user named in the step. 2. Asha opens Investors | Total 99,892.3679 units, ₹101.50 Cr | | |
| ☐ | H36 | Settlement record opened, no manual unit buttons | H21 confirmed | 1. Sign in as the user named in the step. 2. Asha follows Settlement records → redemption; also visits the old distribution URL | Titled "Redemption settlement — 2 Nov 2026" with "Redemption payments", links back to the dealing date; no Redeem units button; the old URL redirects here | | |
| ☐ | H37 | Investor landing card | P holds 4,892.3679 units, cost ₹5,00,00,000; ₹10,160.94 (30 Nov) | 1. Sign in as the user named in the step. 2. P logs in | Card: value ₹4,97,11,057, gain −0.6 %, 4,892.3679 × ₹10,160.94, next dealing date; no committed, called, uncalled, call % or distributed anywhere | | |
| ☐ | H38 | Investor request timeline | B part-filled on 2 Nov, 381.6047 carried, queue #1 | 1. Sign in as the user named in the step. 2. B opens Requests | Received ✓, Part-filled ✓, "Queued #1 for 1 Dec — 381.6047 units carried" | | |
| ☐ | H39 | Quarterly statement | P allotted 4,892.3679 on 2 Nov | 1. Sign in as the user named in the step. 2. Asha generates P's Oct–Dec 2026 statement from the sample template | Opening units 0, closing 4,892.3679, subscriptions 4,892.3679 units / ₹5,00,00,000 | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | Closed-end fund untouched | Beta Growth Fund (closed-end) in Caphive Demo | 1. Sign in as the user named in the step. 2. Asha opens Beta; an investor opens Beta; Beta's SOA is generated | Same tabs, header, investor pages and SOA context as before this change | | |
| ☐ | E2 | Closed-end call and distribution untouched | Beta's capital call and distribution | 1. Sign in as the user named in the step. 2. Asha opens the call; records and verifies a remittance; completes a distribution payment | Labelled "Capital call" / "Distribution"; journey unchanged; no units until **Allocate units** / **Redeem units**; units = amount ÷ price as before | | |
| ☐ | E3 | Custom redemption dates | Redemption calendar custom: 31 Mar 2027, 30 Sep 2027 | 1. Sign in as the user named in the step. 2. An investor redeems on 1 Jan 2027 | Earliest dealing date 31 Mar 2027; only those dates offered | | |
| ☐ | E4 | Class override of notice | Fund notice 30; class B override 90 | 1. Sign in as the user named in the step. 2. Class A and B investors redeem on 1 Nov | A uses 30 days, B uses 90 days | | |
| ☐ | E5 | Early-redemption fee by age | Class A soft lock-up, schedule 3 % < 12 months, 2 % 12–24 months | 1. Sign in as the user named in the step. 2. Redeem units aged 8 and 18 months | 3 % and 2 % applied respectively | | |
| ☐ | E6 | Gate change applies forward | 2 Nov confirmed at 5 % | 1. Sign in as the user named in the step. 2. Asha sets gate 10 % | 2 Nov shows 5 %; 1 Dec preview uses 10 % | | |
| ☐ | E7 | Two classes | Classes A and B; previous prices A ₹10,000 × 80,000 units, B ₹10,000 × 20,000 units; fund lines total ₹102,20,00,000 | 1. Sign in as the user named in the step. 2. Draft NAV | Shares 80 % / 20 %; class A NAV ₹81,76,00,000 and class B ₹20,44,00,000 before class fees; separate NAV per unit | | |
| ☐ | E8 | Class with no units | Class B, zero units, initial price ₹10,000 | 1. Sign in as the user named in the step. 2. Draft NAV | Class B NAV per unit ₹10,000 labelled "No units outstanding — initial price" | | |
| ☐ | E9 | Reopen an unused NAV | 30 Nov approved, no fills reference it | 1. Sign in as the user named in the step. 2. Ravi reopens | Draft again, editable, can be re-approved | | |
| ☐ | E10 | Draft becomes stale | 31 Oct draft | 1. Sign in as the user named in the step. 2. Pharma Co's 30 Oct valuation is edited | Draft shows "Inputs changed since drafted — Recalculate" | | |
| ☐ | E11 | Approved NAV inputs change | 31 Oct approved | 1. Sign in as the user named in the step. 2. A fund unit dated 15 Oct is added | Values unchanged; note "Inputs changed after approval on 2 Nov — reopen to recalculate" | | |
| ☐ | E12 | Investors never see drafts | Class A: 31 Oct draft, 30 Sep approved | 1. Sign in as the user named in the step. 2. P views Holding and NAV history | NAV per unit as of 30 Sep 2026 only | | |
| ☐ | E13 | Additional subscription minimum | A Ltd holds class A; minimum additional ₹5,00,000 | 1. Sign in as the user named in the step. 2. A Ltd subscribes ₹5,00,000 | Accepted | | |
| ☐ | E14 | Subscription after cut-off | Today 29 Oct 2026 | 1. Sign in as the user named in the step. 2. P subscribes | Dealing date 1 Dec 2026; "Received after the 28 Oct cut-off — dealt on 1 Dec 2026." | | |
| ☐ | E15 | Redemption inside notice | Quarterly last-business-day redemptions, 30 days notice; today 15 Dec 2026 | 1. Sign in as the user named in the step. 2. Investor redeems | Dealing date 31 Mar 2027 | | |
| ☐ | E16 | Soft lock-up accepted with fee | 1,200 units in a soft lock-up, 2 % | 1. Sign in as the user named in the step. 2. Investor redeems them | Accepted: "An early-redemption fee of 2% applies to 1,200 units." | | |
| ☐ | E17 | No cancel after confirmation | 2 Nov confirmed with P's order | 1. Sign in as the user named in the step. 2. P opens Requests | No Cancel action | | |
| ☐ | E18 | Back-dated admin entry | — | 1. Sign in as the user named in the step. 2. Asha enters B LLP's redemption received 1 Oct 2026 09:00 | Dealing date and queue from that time; "Entered by Asha" | | |
| ☐ | E19 | Journeys off | Order journeys Off | 1. Sign in as the user named in the step. 2. P subscribes and pays | No step bar; ready once paid | | |
| ☐ | E20 | GP rejects an order | P's order at Accept order | 1. Sign in as the user named in the step. 2. Ravi rejects "Investor not eligible" | Cancelled with reason; Request cancelled email | | |
| ☐ | E21 | Not ready at cut-off, rolled | P waiting on signed form at the 28 Oct cut-off; Roll | 1. Sign in as the user named in the step. 2. Asha confirms 2 Nov | P not priced; dealing date becomes 1 Dec 2026 | | |
| ☐ | E22 | Rolled redemption keeps queue place | Journeys both; redemption received 1 Oct not ready; another received 20 Oct ready | 1. Sign in as the user named in the step. 2. Confirm, then next dealing date | The 1 Oct redemption is ahead | | |
| ☐ | E23 | Subscriptions only | 1 Dec has subscriptions, no redemptions | 1. Sign in as the user named in the step. 2. Asha confirms | Only the subscription settlement is created; Pay redemptions and Cancel units steps are not applicable | | |
| ☐ | E24 | Unpaid pre-funded subscription rolled | Q ₹2,50,00,000, nothing received by 28 Oct; Roll | 1. Sign in as the user named in the step. 2. Asha opens and confirms 2 Nov | Listed "Not paid by cut-off — will roll to 1 Dec 2026"; not priced; after confirm dealing date 1 Dec and its payment row is in the 1 Dec settlement | | |
| ☐ | E25 | Not-ready order cancelled | unready_handling Cancel; order waiting on KYC at the cut-off | 1. Sign in as the user named in the step. 2. Asha confirms | Listed "Not ready — waiting on: Check investor KYC"; cancelled at confirm; email sent | | |
| ☐ | E26 | Nothing to deal | No ready orders for 1 Jan 2027 | 1. Sign in as the user named in the step. 2. Asha opens the dealing date | "Nothing to deal on 1 Jan 2027"; Confirm unavailable | | |
| ☐ | E27 | Under the gate | Requests total ₹4,00,00,000, gate ₹5,11,00,000 | 1. Sign in as the user named in the step. 2. Pricing | All filled in full | | |
| ☐ | E28 | Quarterly gate across monthly dealing dates | 5 % of ₹100,00,00,000 per quarter; ₹3,00,00,000 paid 1 Oct; ₹4,00,00,000 requested 2 Nov | 1. Sign in as the user named in the step. 2. Pricing | ₹2,00,00,000 filled, ₹2,00,00,000 carried | | |
| ☐ | E29 | Investor-level gate | 25 % of holding per quarter; investor holds 4,000 and requests all units | 1. Sign in as the user named in the step. 2. Pricing | At most 1,000 filled before the fund gate; rest carried | | |
| ☐ | E30 | Class-level gate | 5 % class level; class A NAV ₹80,00,00,000, class B ₹20,00,00,000 | 1. Sign in as the user named in the step. 2. Pricing | A gated at ₹4,00,00,000, B at ₹1,00,00,000, independently | | |
| ☐ | E31 | Existing folio top-up | F-012 subscribed ₹3,00,00,000 | 1. Sign in as the user named in the step. 2. A Ltd's ₹1,00,00,000 subscription is accepted (pre-funded) and dealt | F-012 subscribed amount ₹4,00,00,000 | | |
| ☐ | E32 | Early-redemption fee deducted and shown on the advice | 1,200 units at ₹10,220.00, 2 % fee | 1. Sign in as the user named in the step. 2. Confirm, then mark paid on 10 Nov | Net payment ₹1,20,18,720; units cancelled 1,200; advice shows gross ₹1,22,64,000, fee ₹2,45,280, net ₹1,20,18,720, Nov 10, 2026 | | |
| ☐ | E33 | Undo before anything settles | Pay-after 1 Dec confirmed; no money recorded, no redemption paid | 1. Sign in as the user named in the step. 2. Asha clicks **Undo dealing** | Settlement records removed; top-ups reversed; orders Pending; status open | | |
| ☐ | E34 | All-units resolved at confirmation | Investor asked for all units holding 1,000; allotted 200 more before confirm | 1. Sign in as the user named in the step. 2. Confirm | 1,200 units requested (before the gate) | | |
| ☐ | E35 | Management fee accrual missing | Class A 1.5 %; latest accrual dated 31 Oct | 1. Sign in as the user named in the step. 2. Draft the 30 Nov NAV | "Management fee accrued only to 31 Oct 2026 — run the fee formula to 30 Nov 2026 before approving" on draft and approval screens; Approve still enabled | | |
| ☐ | E36 | Class without management fee | Class B 0 % | 1. Sign in as the user named in the step. 2. Draft NAV | No accrual warning for class B | | |
| ☐ | E37 | Quarterly NAV accrual | NAVs quarterly; approved ₹102,20,00,000 | 1. Sign in as the user named in the step. 2. Fee formula for 1 Oct–31 Dec | ₹38,64,000 | | |
| ☐ | E38 | Below the mark | Alpha mark ₹10,400; NAV per unit ₹10,160.94 (and a class at ₹9,900 vs ₹10,000) | 1. Sign in as the user named in the step. 2. Draft NAV; open Fees | Accrued performance fee ₹0; Fees shows "₹239.06 below" | | |
| ☐ | E39 | Hard hurdle | Mark ₹10,000; hard 8 %; 91 days; 20 %; ₹10,220; 1,00,000 units | 1. Sign in as the user named in the step. 2. Draft NAV | Hurdle-adjusted mark ₹10,199.45; fee ₹4,10,958.90 | | |
| ☐ | E40 | Soft hurdle | Same, soft | 1. Sign in as the user named in the step. 2. Draft NAV | Fee ₹44,00,000 | | |
| ☐ | E41 | Soft hurdle not beaten | Soft 8 %; NAV per unit ₹10,150 vs ₹10,199.45 | 1. Sign in as the user named in the step. 2. Draft NAV | Fee ₹0 | | |
| ☐ | E42 | Performance-fee model None | Class B model None | 1. Sign in as the user named in the step. 2. Draft NAV | No performance-fee lines or mark for B | | |
| ☐ | E43 | No crystallisation off-schedule | Annual crystallisation; 30 Nov NAV with an accrued fee | 1. Sign in as the user named in the step. 2. Ravi approves | Nothing crystallised; mark unchanged | | |
| ☐ | E44 | Reopen reverses crystallisation | H30 approved, no fills reference it | 1. Sign in as the user named in the step. 2. Ravi reopens | Crystallisation entries deleted; mark back to ₹10,000 | | |
| ☐ | E45 | Newer draft noted on Overview | 31 Dec draft; 30 Nov approved | 1. Sign in as the user named in the step. 2. Asha opens Overview | Shows 30 Nov figures and "Draft 31 Dec awaiting approval" | | |
| ☐ | E219 | Dealing tab counts open orders only | A Ltd subscription dealt; Q subscription pending | 1. Sign in as Asha. 2. Open the fund → Dealing | "Subscriptions (1)", "Redemptions (0)" | | |
| ☐ | E220 | Link to an inner tab | Alpha | 1. Sign in as Asha. 2. Open the fund page with `?tab=evergreen-redemptions-tab` | Dealing active, Redemptions shown inside it | | |
| ☐ | E221 | Dealing date reads as a preview | A Ltd redeems 12,000 units for 2 Nov; 5% FIFO gate | 1. Sign in as Asha. 2. Open the 2 Nov dealing date → Redemptions (before confirming) | Blue "Preview — nothing is … until you click Confirm dealing" line naming the NAV; the row says "Will be part-filled", 5,000.0000 units will be paid; same columns as the fund's Redemptions list | | |
| ☐ | E222 | Dealing list hides empty dates | Calendar generated; no orders | 1. Sign in as Asha. 2. Fund → Dealing → Dealing Dates. 3. Filter → All dates | Step 2: only the next date still taking orders (and dates with orders / being settled). Step 3: every generated date | | |
| ☐ | E223 | Confirmed date keeps the preview's tabs | A ₹3 Cr, B ₹2.5 Cr, C ₹1 Cr; 5% FIFO gate | 1. Sign in as Asha. 2. Confirm 2 Nov | Green "Confirmed … final" line; same Subscriptions / Redemptions tabs and columns in past tense; A Paid in full, B Part-filled, C Carried; Settlement column with actions; no "Settlement tracker" tab | | |
| ☐ | E224 | Resend is a button that asks first | A Ltd's redemption paid, advice emailed | 1. Sign in as Asha. 2. Open the 2 Nov dealing date → Redemptions. 3. Click Resend | Step 2: status as badges, Resend / View as outline buttons in Actions. Step 3: Immediate Actions popup (email again; nothing else changes); Proceed → "Sent again" | | |
| ☐ | E225 | Order page shows its dealing | As E224 | 1. Sign in as Asha. 2. Open A Ltd's redemption order | "Units cancelled … at ₹… on 02/11/2026" next to Requested; Dealing card with the 2 Nov row (NAV / unit, amount, units, badges) and Resend; an undealt order says "Not dealt yet — will be priced on …" | | |
| ☐ | E226 | LP order page has no fund-user links | P's subscription dealt | 1. Sign in as P. 2. Open the order from Requests | Investor, folio, date as plain text; no Dealing card. (As Asha the same fields are links.) | | |
| ☐ | E216 | Gate part-fills the last request that fits | B 4,935.4207 u (#1), C 978.4736 u (#2); FIFO gate ₹5,07,50,017.83 | 1. Sign in as Asha. 2. Fund → Redemptions | B "Will be paid in full"; C "Will be part-filled", Will be carried 919.2760 units | | |
| ☐ | E217 | Order book opens on open orders | A Ltd subscription dealt; Q subscription pending | 1. Sign in as Asha. 2. Fund → Subscriptions. 3. Filter → Dealt | Step 2: Q only. Step 3: A Ltd only, newest first, no gate columns | | |
| ☐ | E218 | Amount and units columns | B redeems ₹1,00,00,000 as an amount; NAV ₹10,160.94 | 1. Sign in as Asha. 2. Fund → Redemptions; hover the ≈ figure | Amount ₹1,00,00,000.00; Units ≈ 984.1609; tooltip names the NAV and its date | | |
| ☐ | E46 | Unpaid subscription highlighted | Today 24 Nov; Q unpaid for 1 Dec (cut-off 26 Nov) | 1. Sign in as the user named in the step. 2. Asha opens Orders | Q highlighted "Awaiting money" | | |
| ☐ | E47 | Entity without the switch | Gamma Advisors (evergreen funds switched off) | 1. Sign in as the user named in the step. 2. Its admin opens a fund's Settings; requests an evergreen route directly | No "Make this fund evergreen" option; route refused by policy | | |
| ☐ | E48 | Holding with lock-up | P's 4,892.3679 units allotted 2 Nov 2026; 12-month hard lock-up | 1. Sign in as the user named in the step. 2. P opens Holding | "Locked: 4,892.3679 units until 2 Nov 2027 (hard lock-up)", "Free to redeem: 0 units"; Redeem disabled "All your units are locked until 2 Nov 2027" | | |
| ☐ | E49 | No approved NAV yet | New evergreen fund, no approved NAV | 1. Sign in as the user named in the step. 2. Investor opens Holding | Units and cost; "NAV not yet published" | | |
| ☐ | E50 | Redeem hidden without units | Investor with access, no units | 1. Sign in as the user named in the step. 2. Opens the fund | Subscribe shown; Redeem not shown | | |
| ☐ | E51 | No contract-note template: email at allotment | Alpha has no document tagged "Contract Note Template" | 1. Sign in as Asha. 2. Confirm the 2 Nov dealing date with P paid | P's users get the contract-note email at once; its body shows F-101, Class A, NAV date Oct 31, 2026, dealing date Nov 02, 2026, ₹10,220.00, 4,892.3679 units and ₹5,00,00,000; no attachment; nothing new in F-101's documents | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | No unit class | Fund without unit classes | 1. Sign in as the user named in the step. 2. Asha opens Settings | No option to make it evergreen; "Add a unit class first" with link | | |
| ☐ | X2 | Gate out of range | Settings form | 1. Sign in as the user named in the step. 2. Save with gate 120 % | Not saved; "must be between 0 and 100" on the gate field | | |
| ☐ | X3 | No redemption form | Settings form | 1. Sign in as the user named in the step. 2. Clear Units, Amount, All units; save | Not saved; "Allow at least one way to redeem" | | |
| ☐ | X4 | Switch back after dealing | Alpha with a confirmed dealing date | 1. Sign in as the user named in the step. 2. Asha tries to make it closed-end | Unavailable: "Dealing dates exist — cannot switch back" | | |
| ☐ | X5 | Missing valuation | Pharma Co has no valuation on or before 31 Oct | 1. Sign in as the user named in the step. 2. **New NAV** for 31 Oct | No draft; "No valuation for Pharma Co on or before 31 Oct 2026 — add one or upload the NAV" | | |
| ☐ | X6 | Override without reason | A draft | 1. Sign in as the user named in the step. 2. Override a line, reason blank | Not saved; reason field error | | |
| ☐ | X7 | Inconsistent upload row | — | 1. Sign in as the user named in the step. 2. Upload "A, 30 Sep 2026, 98,26,00,000, 98,450, 9,980.40" | Row rejected "NAV per unit does not equal NAV ÷ units outstanding" | | |
| ☐ | X8 | Preparer approves | Asha's draft | 1. Sign in as the user named in the step. 2. Asha views it; Asha posts approve directly | No Approve action, tooltip "Needs a different approver"; the direct request is refused by the system | | |
| ☐ | X9 | Reopen a used NAV | 31 Oct NAV used by the confirmed 2 Nov dealing date | 1. Sign in as the user named in the step. 2. Ravi views it | Reopen disabled: "Used by dealing date 2 Nov 2026 — cannot reopen" | | |
| ☐ | X10 | Below minimum initial | Minimum initial ₹25,00,000; new investor | 1. Sign in as the user named in the step. 2. Subscribe ₹10,00,000 | Rejected: "Minimum subscription is ₹25,00,000" | | |
| ☐ | X11 | Foreign-currency folio | USD folio in an INR fund | 1. Sign in as the user named in the step. 2. Place an order | Rejected: "Evergreen orders must be in the fund currency (INR)" | | |
| ☐ | X12 | More units than free | Holds 4,892.3679, 2,000 queued | 1. Sign in as the user named in the step. 2. Redeem 3,000 | Rejected: "You hold 4,892.37 units; 2,000 are already queued for redemption." | | |
| ☐ | X13 | Form not allowed | Fund allows units and all units only | 1. Sign in as the user named in the step. 2. Upload a row with an amount | Row rejected: "This fund accepts redemptions in units or all units only" | | |
| ☐ | X14 | Hard lock-up | 1,200 units locked until 15 Mar 2027 | 1. Sign in as the user named in the step. 2. Redeem them | Rejected: "1,200 of these units are locked until 15 Mar 2027." | | |
| ☐ | X15 | Below minimum holding | Minimum holding ₹50,00,000 | 1. Sign in as the user named in the step. 2. Partial redemption leaving ₹40,00,000 | Rejected: "This would leave ₹40,00,000, below the ₹50,00,000 minimum holding. Redeem all units instead." | | |
| ☐ | X16 | Upload with one bad row | Two rows, second over-redeems | 1. Sign in as the user named in the step. 2. Upload | First created; second row's result explains the failure | | |
| ☐ | X17 | NAV not approved | Class A ready orders; 31 Oct NAV draft | 1. Sign in as the user named in the step. 2. Asha opens the 2 Nov dealing date | Confirm disabled: "Approve the NAV for Class A dated 31 Oct 2026 first" | | |
| ☐ | X18 | Undo after allotment | H21 confirmed, P allotted | 1. Sign in as the user named in the step. 2. Asha views the dealing date | Undo disabled: "Units allotted or payments recorded — reverse them first" | | |
| ☐ | X19 | Another investor's order | P logged in | 1. Sign in as the user named in the step. 2. P opens B LLP's order URL | Access denied | | |
| ☐ | X20 | Pricing changed between preview and confirm | Preview open; P cancels in another session | 1. Sign in as the user named in the step. 2. Asha clicks Confirm | Confirm aborted: "Pricing changed — review again"; nothing written | | |

---

## UI Journeys

**Journey 1 — run a dealing date (fund admin).** Design: [What users see](design.md#what-users-see).

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J1.1 | Alpha → Overview | Click **Open** on the next dealing date | The dealing date page with a step bar matching the fund's payment timing (pre-funded: Collect subscription money, Approve NAV, Review and confirm dealing, Allot units, Pay redemptions, Cancel units, Generate documents, Approve and send documents, Close dealing date; the two document steps read "n/a — no template" when Alpha has no template) | | |
| ☐ | J1.2 | Dealing date | Read the panel under the step bar | One sentence under "What's needed now" naming the current step's task | | |
| ☐ | J1.3 | Dealing date — Subscriptions | Review the list | Paid orders priced at the approved NAV with units; unpaid ones listed under "Not paid by cut-off — will roll to <next date>" (or "— will be cancelled"); not-ready ones under "Not ready — waiting on: <step>" | | |
| ☐ | J1.4 | Dealing date — Redemptions | Review the list | Queue order, requested, filled and carried amounts; the line "Gate 5% of NAV = 5,11,00,000 · FIFO · filled 78.6%" | | |
| ☐ | J1.5 | Dealing date | Click **Confirm dealing** | A popup with three cards: "Allot 4,892.3679 units to 1 investor", "Pay 2 redemptions — ₹5.11 Cr", "Carry ₹1.39 Cr to 1 Dec 2026 and send 2 gate notices"; confirming shows the settlement tracker | | |
| ☐ | J1.6 | Settlement tracker | **Record payment** / **Mark paid** / **Resend** on rows; then **Close dealing date** | Each row moves through its statuses (Awaiting money → Money received → Units allotted → Contract note sent; Awaiting payment → Paid → Units cancelled → Advice sent; with a template, Generated → Approved sit before Sent — see Journey 7); Close is enabled only when every earlier step is done and every contract note and advice has been sent | | |

**Journey 2 — investor subscribes.** Proposal screen LP-3.

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J2.1 | Investor landing page | Click **Subscribe** on the Alpha card | Wizard step ① Amount: class picker, "Minimum ₹25,00,000", dealing date and "pay by" date, indicative units and "Indicative — final price is the NAV for <date>" | | |
| ☐ | J2.2 | Wizard ② Review | Click **Next**, tick the offering-documents acknowledgement | A summary of class, amount and dealing date; Submit disabled until the box is ticked | | |
| ☐ | J2.3 | Wizard ③ Done | Click **Submit** | Pre-funded: "✓ Subscription request received", amount, pay-by date, bank details, reference, "We've emailed you these instructions." Pay-after: "You'll receive payment instructions after the <date> dealing date, with the exact units" | | |
| ☐ | J2.4 | Fund page → Requests | Open Requests | The new subscription with its timeline and a **Cancel** link | | |

**Journey 3 — investor redeems.** Proposal screen LP-4.

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J3.1 | Fund page → Holding | Click **Redeem** | Wizard ① What: only the forms the fund allows; held, free and queued units; indicative value; early-redemption fee | | |
| ☐ | J3.2 | Wizard ② When | Enter units, click **Next** | Earliest dealing date, the gate, and "you would be #N in the queue" | | |
| ☐ | J3.3 | Wizard ③ Done | Submit | Confirmation with units and dealing date; email received | | |

**Journey 4 — draft and approve a NAV.** Proposal screen GP-5.

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J4.1 | Alpha → NAV | Click **New NAV**, pick 31 Oct 2026 | A draft per class with every line and its source, NAV, units and NAV per unit | | |
| ☐ | J4.2 | NAV draft | Click **Edit lines**, override a line with a reason | Line updates in place, ✎ with the reason; NAV per unit recalculates without a page reload | | |
| ☐ | J4.3 | NAV draft (as Asha) | Look for Approve | Approve hidden; tooltip "Needs a different approver" | | |
| ☐ | J4.4 | NAV draft (as Ravi) | Click **Approve** | Status Approved; lines read-only | | |

**Journey 5 — make a fund evergreen.** Proposal screen GP-8.

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J5.1 | Fund → Settings | Click **Make this fund evergreen** | The form with sections Dealing calendar, Subscriptions, Redemptions, Classes, Order journeys, NAV sources, Documents, each with a one-line hint | | |
| ☐ | J5.2 | Settings form | Open **Typical setups**, pick a preset | Fields fill; nothing saved | | |
| ☐ | J5.3 | Settings form | Save | "This fund is now evergreen"; the fund now shows the evergreen tabs | | |

**Journey 6 — order journey (subscription).** Proposal US-14.

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J6.1 | Orders → an order (Asha) | Open a subscription with journeys on | A step bar: Check investor KYC, Collect signed subscription form, Accept order, Collect subscription money, Ready to deal, Allot units and send contract note | | |
| ☐ | J6.2 | Investor → Requests | Open the order | "Upload your signed subscription form [Upload]"; uploading completes the step | | |
| ☐ | J6.3 | Order (Ravi) | Click **Accept**; on another order click **Reject** with a reason | Accept moves the step on; Reject cancels the order and the investor gets "Request cancelled" | | |

---

## Notifications

Design: [card ⑩](design.md#⑩-notifications) and [Notifications](design.md#notifications). **Extra setup:** on the user form tick "FundOps" and "FundAccounting" for Asha and "Compliance" for Meera; set **Karan** as "Managed by" for P Family Trust and D Partners (leave Q Capital and A Ltd empty); give B LLP a **Vikram Advisors** advisor user; create **R Trust** (KYC approved) and **Gamma Income Fund** (evergreen, with Evergreen custom notifications for payment reminder, contract note and gate notice). Daily checks: ask a developer to run "EvergreenNotificationsJob" for the row's date. Team alerts arrive both by email and in the bell (in-app).

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H40 | Payment reminder | Q's ₹2,50,00,000 pre-funded subscription for 2 Nov unpaid | Run the daily check for 26 Oct 2026 | Q Capital's users get "Payment reminder": ₹2,50,00,000, "Pay by Oct 28, 2026", bank details, reference | | |
| ☐ | H41 | Action needed (Roll) | R Trust's subscription at "Collect signed subscription form"; Roll | Run the daily check for 26 Oct 2026 | Email names "Upload your signed subscription form" and says the request moves to the Dec 01, 2026 dealing date if not done by Oct 28, 2026 | | |
| ☐ | H42 | Payment received | P's subscription | Asha records and verifies ₹5,00,00,000 on 23 Oct | P's users get "Payment received" for ₹5,00,00,000 (2 Nov 2026 dealing date) | | |
| ☐ | H43 | Units unlocked | Switch "Units unlocked" on; P allotted 2 Nov 2026, 12-month lock-up | Run the daily check for 2 Nov 2027 | P's users get "Units unlocked": 4,892.3679 units in F-101 free to redeem | | |
| ☐ | H44 | NAV update | Switch "NAV update" on | Ravi approves the 30 Nov NAV (₹10,160.94) | One email for F-101: ₹10,160.94 as of Nov 30, 2026, holding ₹4,97,11,057 | | |
| ☐ | H45 | New order → relationship manager | — | P subscribes in the portal | Karan gets "New subscription: P Family Trust ₹5,00,00,000 for 2 Nov 2026" (email + bell); Asha does not | | |
| ☐ | H46 | NAV awaiting approval | Asha also has the approver role | Asha drafts the 31 Oct NAV | Ravi is told; Asha is not | | |
| ☐ | H47 | NAV approved | H46 | Ravi approves | Asha gets "NAV approved: Class A, Oct 31, 2026, ₹10,220.00" exactly once | | |
| ☐ | H48 | Cut-off summary | Shared setup for 2 Nov | Run the daily check for 29 Oct | Asha gets one summary: 2 subscriptions ₹7,50,00,000; 1 unpaid (Q, will roll to 1 Dec 2026); 0 not ready; 3 redemptions ₹6,50,00,000 | | |
| ☐ | H49 | Ready to confirm | Cut-off passed | Ravi approves the 31 Oct NAV on 2 Nov | Asha and Ravi get "2 Nov 2026 is ready to confirm" with a working link | | |
| ☐ | H50 | Gate applied | H19 pricing | Asha confirms 2 Nov | Meera and Asha get "Gate applied on 2 Nov 2026: ₹5,11,00,000 paid, ₹1,39,00,000 carried to 1 Dec 2026" | | |
| ☐ | H51 | Large redemption | Class A NAV ₹102,20,00,000 | D Partners redeems ₹2,50,00,000 | Meera and Karan get "Large redemption: D Partners ₹2,50,00,000 (2.45 % of Class A NAV)" | | |
| ☐ | H52 | Redemption overdue | 2 Nov confirmed; A Ltd not paid by 16 Nov | Run the daily check for 17 Nov | Asha gets "Settlement overdue on 2 Nov 2026" listing A Ltd ₹3,00,00,000, due Nov 16, 2026 | | |
| ☐ | H53 | Fee accrual behind | Fee accrued only to 31 Oct | Asha drafts the 30 Nov NAV | Asha gets "Management fee accrued only to Oct 31, 2026 — run the fee formula to Nov 30, 2026 before approving" | | |
| ☐ | H54 | Notifications step | — | Open Settings → Notifications step; hover each (i); set reminder days 3; save; run the daily check for 25 Oct | Each switch shows its tooltip and recipients at the default; Q's reminder arrives on 25 Oct | | |
| ☐ | H55 | Copy from fund | Alpha has no custom notifications | Notifications tab → **Copy from fund…** → Gamma Income Fund | "3 copied, 0 skipped"; the three templates match Gamma's subject, body, attachments and show-details | | |
| ☐ | H56 | Custom wording used | Alpha payment-reminder template with subject "Reminder: fund your {{fund_name}} subscription" | Run the daily check for 26 Oct | Q's email subject reads "Reminder: fund your Alpha Long-Short Fund subscription" | | |
| ☐ | E52 | Advisor and the order | Vikram Advisors user on B LLP | Acknowledge B LLP's redemption with the advisor not allowed to see it; then allow it and repeat | First time only the B LLP users get it; second time the advisor does too | | |
| ☐ | E53 | No relationship manager | Q has no "Managed by" | Q subscribes in the portal | Asha (Fund ops) gets the new-order alert | | |
| ☐ | E54 | Switched off | Switch "Payment reminder" off | Run the daily check for 26 Oct | Q gets no reminder | | |
| ☐ | E55 | Default off | Never saved a NAV update choice | Ravi approves a NAV | No NAV update emails to investors | | |
| ☐ | E56 | Run twice | H40 done | Run the daily check for 26 Oct again | No second reminder | | |
| ☐ | E57 | Copy skips existing | Alpha already customises the contract note | Copy from Gamma Income Fund | "2 copied, 1 skipped"; Alpha's contract note unchanged | | |
| ☐ | E58 | Preparer is the only approver | Remove Ravi's approver role | Asha drafts a NAV | Nobody gets "NAV awaiting approval" | | |
| ☐ | E59 | Tagged but no fund access | Remove Meera's access to Alpha | Confirm a gated dealing date | Meera gets nothing; Asha does | | |
| ☐ | E60 | Below threshold | — | C HUF redeems ₹1,00,00,000 (0.98 %) | No large-redemption alert | | |
| ☐ | E61 | Pay-after overdue | Pay after dealing, 7 days; 1 Dec confirmed; Q unpaid | Run the daily check for 9 Dec | Asha gets "Settlement overdue on 1 Dec 2026" listing Q ₹5,00,00,000, pay by Dec 08, 2026 | | |
| ☐ | E62 | Action needed (Cancel) | As H41 with unready handling Cancel | Run the daily check for 26 Oct | Email says the request will be cancelled if not done by Oct 28, 2026 | | |
| ☐ | E63 | No reminder when paid | P paid and verified | Run the daily check for 26 Oct | P gets no reminder | | |
| ☐ | E64 | Closed-end untouched | Beta Growth Fund | Verify a Beta remittance; run the daily check | No evergreen notification for Beta | | |
| ☐ | E65 | Default for a missing key; no repeat | Settings saved earlier with only "Payment reminder" off | Verify P's payment; then edit its reference and save | One "Payment received"; none after the edit | | |
| ☐ | X21 | Reminder days 0 | Notifications step | Enter 0, save | Not saved; "must be between 1 and 30" | | |
| ☐ | X22 | Threshold 0 % / 120 % | Notifications step | Enter 0, save; then 120, save | Not saved; "must be greater than 0 and at most 100" | | |
| ☐ | X23 | Nothing to copy | No other evergreen fund with templates | Click **Copy from fund…** | "No other evergreen fund has custom notifications to copy" | | |
| ☐ | X24 | Copy / switch without rights | Investor user; Gamma Advisors user | Try the copy and settings URLs directly | Access denied; nothing changes | | |
| ☐ | X25 | One fund's check fails | Developer forces an error for Gamma Income Fund | Run the daily check for 26 Oct | Alpha's reminders still go; developers get the job error mail | | |

## Dealing-date documents

Design: [card ⑨ → Dealing-date documents](design.md#⑨-screens-documents-journeys). **Extra setup:** for rows that say "both templates", upload two Word files to Alpha's Documents and tag them "Contract Note Template" (*Alpha Contract Note*) and "Redemption Advice Template" (*Alpha Redemption Advice*); remove them again for rows that say "no templates". **Generate documents** runs in the background: wait for the "documents generated" alert (or refresh the dealing date after a minute).

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H57 | Generate documents from templates | Both templates; 2 Nov confirmed with P allotted; A Ltd and B LLP marked paid | 1. Sign in as Asha. 2. Open the 2 Nov dealing date; note the step bar. 3. **Actions → Generate documents**. 4. Wait for the alert, refresh | Before: ✓ Allot units ✓ Pay redemptions ✓ Cancel units, **Generate documents** current. Flash "Generating 3 documents — you'll be notified when they are ready". Alert "3 documents generated for 02/11/2026 — approve and send them on the dealing date". Rows show Generated for F-101, F-012, F-031; no investor email arrived; **Approve and send documents** current | | |
| ☐ | H58 | Approvers are told | H57 | Check Ravi's and Asha's bell and inbox | One "Documents awaiting approval" alert each for 2 Nov 2026: "1 contract note and 2 redemption advices to approve", with a working link | | |
| ☐ | H59 | Approve and send | H57 | 1. Sign in as Ravi. 2. **Actions → Approve & send**. 3. Read the popup, confirm | Popup card: "Approve 1 contract note and 2 redemption advices, and email them to investors". Flash "3 documents approved and sent". P, A Ltd and B LLP each get their email with the PDF attached (dates like `Nov 02, 2026`). Rows show Sent; **Close dealing date** is current and enabled | | |
| ☐ | H60 | Folio template wins | Both templates; F-101 has its own *Alpha Contract Note* with a different letterhead; 1 Dec has P and A Ltd subscriptions allotted | 1. Asha clicks **Generate documents** on 1 Dec. 2. **View** both contract notes | P's uses F-101's letterhead; A Ltd's uses the fund's | | |
| ☐ | H61 | No templates | No templates | 1. Confirm 2 Nov. 2. Mark A Ltd and B LLP paid. 3. Open **Actions** | Contract note email to P at confirm, advices to A and B as each is paid, no attachments. Step bar: "Generate documents — n/a, no template", "Approve and send documents — n/a, no template". No Generate or Approve & send in Actions. Close current after B is paid | | |
| ☐ | H62 | Regenerate | H57 | 1. Edit *Alpha Redemption Advice* (fix a heading), re-upload. 2. Click **Regenerate** on B LLP's row. 3. **View** it | "Document regenerated"; the new PDF has the corrected heading; still unapproved; other rows unchanged | | |
| ☐ | E66 | Only a contract-note template | Only *Alpha Contract Note* | 1. Confirm 2 Nov (P allotted). 2. Mark A Ltd paid. 3. Generate documents. 4. Ravi: Approve & send | A's advice email arrives at step 2 with no PDF; P gets nothing until step 4. Popup: "Approve 1 contract note, and email it to investors"; P then gets the PDF | | |
| ☐ | E67 | Re-run picks up only new settlements | Pay after dealing; both templates; 1 Dec with P and Q; P paid 3 Dec, documents generated, approved and sent on 4 Dec | 1. Record and verify Q's money (6 Dec). 2. Look at the step bar. 3. Generate documents. 4. Ravi: Approve & send | Step 2: **Generate documents** current again. Only Q's contract note is generated; popup "Approve 1 contract note, and email it to investors"; P receives nothing more | | |
| ☐ | E68 | No advice email at payment | *Alpha Redemption Advice* uploaded | Mark A Ltd paid | Units cancelled (2,935.4207); no email to A; row "Paid ✓ Units cancelled ✓ · Advice to generate" | | |
| ☐ | E69 | Investors can't see unapproved documents | H57 | 1. Sign in as P; open Documents and Transactions. 2. After H59, look again | Step 1: no contract note. Step 2: it is listed and linked from the allotment | | |
| ☐ | E70 | Alert switched off | Settings → Notifications: "Documents awaiting approval" off | Repeat H57 | Approvers get no alert; Asha still gets her own "3 documents generated…" alert | | |
| ☐ | X26 | Approve & send needs the approver role | H57; remove Asha's approver role | 1. Asha opens **Actions**. 2. Ask a developer to post the approve URL as Asha | No Approve & send item; the direct request is refused; nothing approved or sent | | |
| ☐ | X27 | Approved documents are locked | H59 | 1. Look at P's row. 2. Ask a developer to post the regenerate URL | No Regenerate link; refused with "Approved documents can't be regenerated" | | |
| ☐ | X28 | Close waits for documents | H57 (not yet approved) | Look at **Close dealing date** | Disabled: "Send every contract note and redemption advice first" | | |
| ☐ | X29 | Nothing to generate | H59 | Click **Generate documents** | "Nothing to generate — every settled order already has its document or email"; no alert | | |
| ☐ | X30 | One document fails | Both templates; ask a developer to give F-031 a broken folio-level *Alpha Redemption Advice* | Repeat H57 | P's and A's documents generated; alert "2 documents generated for 02/11/2026 … 1 failed: B LLP: …"; B's row "Not generated — Regenerate"; Generate documents stays current | | |

**Journey 7 — generate, approve and send a dealing date's documents** (design card ⑨)

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J7.1 | Dealing date (both templates, units moved) | Look at the step bar | *Generate documents* current (or *Approve and send documents*); both "n/a — no template" on a fund without templates | | |
| ☐ | J7.2 | Dealing date | Open **Actions** | **Generate documents** for fund admins; **Approve & send** for approvers, only while documents await approval | | |
| ☐ | J7.3 | Tracker row | Click **View**; then **Regenerate** | The PDF opens; Regenerate replaces it while unapproved | | |
| ☐ | J7.4 | Dealing date (Ravi) | Click **Approve & send** | A popup with action-summary cards: the counts to approve and email, and that approved documents can't be regenerated | | |
| ☐ | J7.5 | Popup | Confirm | "N documents approved and sent"; rows show Sent; *Close dealing date* current | | |

---

## Role Sweep

✓ = allowed and works · ✗ = correctly blocked (no button, or access denied on a direct URL) · ! = wrong

| ID | Screen / action | Fund admin (Asha) | Approver (Ravi) | Investor of the fund (P) | Investor of another fund | Other-entity user (Gamma) |
|---|---|---|---|---|---|---|
| R1 | Make a fund evergreen / edit settings | ✓ | ✓ if also fund admin | ✗ | ✗ | ✗ |
| R2 | Draft, override, recalculate, upload NAV | ✓ | ✓ | ✗ | ✗ | ✗ |
| R3 | Approve / reopen NAV | ✗ (own draft) | ✓ | ✗ | ✗ | ✗ |
| R4 | See approved NAV history | ✓ | ✓ | ✓ (own classes) | ✗ | ✗ |
| R5 | See draft NAVs | ✓ | ✓ | ✗ | ✗ | ✗ |
| R6 | Place subscription / redemption | ✓ (for any investor) | ✓ if fund admin | ✓ (own only) | ✗ | ✗ |
| R7 | Cancel a pending order | ✓ | ✓ if fund admin | ✓ (own only) | ✗ | ✗ |
| R8 | Accept / reject order; verify signatory | ✗ (verify ✓) | ✓ | ✗ | ✗ | ✗ |
| R9 | Open order book / unit register | ✓ | ✓ | ✗ | ✗ | ✗ |
| R10 | Open a dealing date; confirm, undo, close | ✓ | ✓ if fund admin | ✗ | ✗ | ✗ |
| R11 | Record payment / verify / mark paid / resend | ✓ | ✓ if fund admin | ✗ | ✗ | ✗ |
| R12 | Open an evergreen settlement record | ✓ | ✓ | ✗ | ✗ | ✗ |
| R13 | Holding, Transactions, Requests, Documents (investor pages) | ✓ (folio page) | ✓ | ✓ (own only) | ✗ | ✗ |
| R14 | Another investor's order URL | ✓ | ✓ | ✗ | ✗ | ✗ |
| R15 | Change notification switches (Notifications step) | ✓ | ✓ if also fund admin | ✗ | ✗ | ✗ |
| R16 | Copy notifications from another fund | ✓ | ✓ if also fund admin | ✗ | ✗ | ✗ |
| R17 | Generate documents; View; Regenerate (unapproved) on a dealing date | ✓ | ✓ if also fund admin | ✗ | ✗ | ✗ |
| R18 | Approve & send documents | ✗ (✓ only with the approver role) | ✓ | ✗ | ✗ | ✗ |
| R19 | See a generated contract note / advice in investor Documents | ✓ | ✓ | ✓ own, approved only | ✗ | ✗ |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | All seven evergreen emails arrive (subscription acknowledgement, payment instructions, contract note, redemption acknowledgement, gate notice, redemption advice, request cancelled) | Correct recipients (the investor's users who get fund notices), subjects and links; dates shown as `Nov 02, 2026`, also when the user's locale is ja or en-US. Contract note and advice: figures in the body without a template; PDF attached after Approve & send with one | | |
| ☐ | C2 | Dates on evergreen screens | Follow the user's locale (`02/11/2026` for en, `11/02/2026` for en-US, `2026/11/02` for ja) | | |
| ☐ | C3 | Narrow / mobile width (375 px): Overview, dealing date tracker, order book, investor Holding, both wizards | No horizontal page scroll; buttons reachable; wide tables scroll inside their container | | |
| ☐ | C4 | Tenant isolation | A Gamma Advisors user cannot see or reach Alpha's NAVs, orders, dealing dates, settlement pages, documents or uploads, even with direct URLs | | |
| ☐ | C5 | Regression on modified screens (Beta Growth Fund, closed-end) | Fund page tabs and header; funds list card; investor landing card and fund page; capital call page, remittance verify and **Allocate units**; distribution page, payment complete and **Redeem units**; commitment page; SOA generation — all exactly as before | | |
| ☐ | C6 | Empty states | Dealing list with no dates ("No dealing dates yet"), order book with no orders, NAV list with none, investor Requests with none — each shows a sensible message | | |
| ☐ | C7 | Labels | No evergreen screen, email, document or export shows "capital call", "distribution", "committed", "called" or "uncalled" | | |
| ☐ | C8 | Entity switch off | Switching "Evergreen funds" off for Caphive Demo hides all evergreen screens; Alpha then shows closed-end screens; switching back on restores them with data intact | | |
| ☐ | C9 | Notification emails and alerts | Every new email and team alert shows dates as `Nov 02, 2026` under en, en-US and ja; no email or alert goes to a user who cannot see the fund or order | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
