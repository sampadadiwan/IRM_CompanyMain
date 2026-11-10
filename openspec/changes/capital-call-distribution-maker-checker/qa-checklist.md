# Capital Call & Distribution Maker–Checker — Manual QA Checklist

> **Audience:** Testers running the feature by hand on a deployed build. No code knowledge needed.
> **Companion documents:** [Proposal](proposal.md) · [Design](design.md) · [Business rules](business-rules.md) · [Screen mock](mocks/approve_actions.html)

> **How to use:** work top to bottom. Tick ☐ → ☑ and write Pass or Fail for each row. For a Fail,
> put the defect link in Notes. Row IDs match [business-rules.md](business-rules.md) (H/E/X) and the UI journeys
> (J), so a failure maps straight to the automated test that should have caught it.

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
| Environment | Staging IN (staging_in) after deploy of this change |
| Accounts | Nilgiri Capital: Ravi Iyer (company admin + Approver), Meera Shah (Approver, fund edit access), Anil Rao (fund edit access, no Approver), Priya Nair (Approver, fund edit access), Tara Bose (Approver, no fund access), Deepa Kumar (Approver, deactivated), Vikram Sen (fund read-only). Solo Ventures: Sam Mehta (only user, company admin + Approver). Investor: Arun (LP of Nilgiri Growth Fund I) |
| Second entity | Kaveri Partners: Kiran Das (company admin + Approver) |
| Seed data | Exactly as [business-rules.md › Shared setup](business-rules.md#shared-setup): Nilgiri Growth Fund I with commitments ₹20 Cr / ₹18 Cr / ₹12 Cr; call "Q4 2026 Drawdown" (10%, due 15/12/2026) created by Meera; distribution "Tea Estates Exit" (income ₹3 Cr) created by Meera; Solo Fund I; open-ended fund Nilgiri Flexi Fund with a dealing date |
| Switching the setting | Ravi: Settings › Entity › Edit › Approvals › tick/untick "Require a second person to approve capital calls and distributions" › Save |
| Background work | Remittance/payment generation and imports run in the background: wait for the progress bar / flash, then refresh. Bulk approve is API-only: ask a developer to send `POST /capital_calls/bulk_actions` with `bulk_action=approve` as the named user. "No acting user" rows (E10, E45) and "legacy call" rows (E12, E13, E26) need a developer to prepare the data |
| Email | Staging mail catcher; check sender, subject, link and the date format |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Admin switches it on | Nilgiri setting off | 1. Ravi ticks the switch on the entity form and saves | Setting on; entity audit shows Ravi, false → true; "Entity was successfully updated." | | |
| ☐ | H2 | Created on the form | — | 1. Meera creates Q4 2026 Drawdown | Preparers: Meera | | |
| ☐ | H3 | Created by API | — | 1. Meera POSTs `/capital_calls.json` with a bearer token | Preparers: Meera | | |
| ☐ | H4 | Call figures edited | Q4 by Meera | 1. Anil changes 10% → 12% | Preparers: Meera, Anil | | |
| ☐ | H5 | Remittance amount edited | Q4 by Meera | 1. Anil changes ₹1.2 Cr → ₹1.25 Cr | Preparers: Meera, Anil | | |
| ☐ | H6 | Distribution payment edited | Tea Estates by Meera | 1. Anil changes ₹0.72 Cr → ₹0.75 Cr income | Preparers: Meera, Anil | | |
| ☐ | H7 | Calls imported | — | 1. Anil imports a sheet with "Q1 2027 Drawdown" | Preparers of Q1 2027: Anil | | |
| ☐ | H8 | Remittances imported | Upload-basis call "Sep 2026 Top-up" by Meera | 1. Anil imports 3 remittance rows | Preparers: Meera, Anil | | |
| ☐ | H9 | Recompute fees | Q4 with a 2% fee formula | 1. Anil clicks Recompute Fees; fees ₹10,00,000 → ₹12,00,000 | Anil is a preparer | | |
| ☐ | H10 | Fee line edited | Q4 with a call fee line | 1. Anil changes the fee line's end date | Anil is a preparer | | |
| ☐ | H11 | Distribution created | — | 1. Meera creates Tea Estates Exit | Preparers: Meera | | |
| ☐ | H12 | Checker approves | Q4 prepared by Meera | 1. Ravi clicks Approve | Approved by Ravi; "Capital call was successfully approved." | | |
| ☐ | H13 | Preparer sees the reason | Q4 prepared by Meera | 1. Meera opens Actions | Approve disabled, tooltip "You prepared this call, so another approver must approve it (maker–checker is on)."; Request approval shown | | |
| ☐ | H14 | Setting off: self-approval labelled | Solo Ventures | 1. Sam creates and approves a call | Approved by Sam; "Yes · by Sam Mehta (also prepared it)" | | |
| ☐ | H15 | Preparers listed | Q4: Meera created, Anil edited a remittance | 1. Page opened | "Prepared by: Meera Shah, Anil Rao" | | |
| ☐ | H16 | Checker approves | Tea Estates prepared by Meera | 1. Ravi clicks Approve | Approved by Ravi; Mark Payments Completed offered | | |
| ☐ | H17 | Setting off: labelled | Solo Ventures | 1. Sam creates and approves a distribution | "Yes · by Sam Mehta (also prepared it)" | | |
| ☐ | H18 | Preparer requests | Q4 by Meera | 1. Meera clicks Request approval, sees the 3-card popup, clicks Send request | Ravi and Priya get email + bell "Q4 2026 Drawdown (Nilgiri Growth Fund I) needs your approval"; "Approval requested from Ravi Iyer and Priya Nair." | | |
| ☐ | H19 | Checker follows the link | After H18 | 1. Ravi opens the email link | Q4 page; Approve enabled | | |
| ☐ | H20 | Distribution | Tea Estates by Meera | 1. Meera requests approval | "Tea Estates Exit (Nilgiri Growth Fund I) needs your approval" to Ravi and Priya | | |
| ☐ | H21 | Call figures after approval | ON; Q4 approved by Ravi | 1. Anil changes 10% → 12% | Q4 unapproved; Anil's flash "Capital call was successfully updated. Its approval was withdrawn because the figures changed — another approver must approve it again."; journey back at Approve call with "Approval withdrawn: Anil Rao changed the figures" | | |
| ☐ | H22 | Remittance after approval | ON; Q4 approved | 1. Anil changes ₹1.2 Cr → ₹1.25 Cr | Unapproved; Ravi, Priya, Meera get "Approval of Q4 2026 Drawdown was withdrawn: Anil Rao changed its figures after approval." — not Anil (he acted) or Tara (no fund access) | | |
| ☐ | H23 | Payment after approval | ON; Tea Estates approved | 1. Anil changes a payment's income | Distribution unapproved; alert sent | | |
| ☐ | H24 | Re-approval | After H22 | 1. Priya approves | Approved by Priya | | |
| ☐ | H25 | Switched off | Nilgiri ON | 1. Ravi switches off on Nov 19, 2026 | Meera, Priya, Tara get email + bell "Maker–checker for calls and distributions was turned off by Ravi Iyer on Nov 19, 2026."; Ravi, Deepa (inactive), Arun get nothing | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | Existing firm after release | Solo Ventures existed before release | 1. Migration runs | Setting off; Sam approves his own call as before | | |
| ☐ | E2 | New firm after release | — | 1. Support creates firm "Ganga Fund Advisors" | Setting off | | |
| ☐ | E3 | Form saved without touching the switch | Nilgiri ON | 1. Ravi edits the entity name only | Still on; no setting change in the audit | | |
| ☐ | E4 | Name and notes | Q4 by Meera | 1. Ravi edits name and notes | Ravi is not a preparer | | |
| ☐ | E5 | Custom field and notification switch | Q4 | 1. Ravi changes custom field "Purpose" and Send Call Notice | Ravi is not a preparer | | |
| ☐ | E6 | Payment received | Q4 | 1. Ravi records a ₹1.8 Cr payment | Ravi is not a preparer | | |
| ☐ | E7 | Remittance verified | Q4 | 1. Ravi verifies a remittance | Ravi is not a preparer | | |
| ☐ | E8 | Generation recorded once | — | 1. Meera creates Q4; 3 remittances are generated | Exactly one preparer row (Meera) | | |
| ☐ | E9 | Same person twice | Q4 | 1. Anil edits two remittances in two requests | One row for Anil | | |
| ☐ | E10 | No acting person | Q4 | 1. A job with no acting user changes a remittance amount | No row added | | |
| ☐ | E11 | Support acting as a user | — | 1. Sunil, acting as Meera, creates a call | Preparers: Sunil (the real person; Meera is not) | | |
| ☐ | E12 | Legacy call, untouched | Call created before release by Meera; no rows | 1. Page opened | Preparers: Meera (from the audit trail) | | |
| ☐ | E13 | Legacy call, edited after release | As E12 | 1. Anil changes a remittance | Preparers: Meera, Anil | | |
| ☐ | E14 | Saved with no real change | Q4 | 1. Anil saves a remittance form without changing the amount | Anil is not a preparer | | |
| ☐ | E15 | Admin-approver who edited | Ravi changed a remittance of Q4 | 1. Ravi opens Actions | Approve disabled for Ravi; Priya approves | | |
| ☐ | E16 | Approver who is not a preparer | Call created by Anil only | 1. Meera approves | Approved by Meera | | |
| ☐ | E17 | Imported call | Priya imported "Q1 2027 Drawdown" | 1. Priya opens Actions; then Ravi approves | Disabled for Priya; approved by Ravi | | |
| ☐ | E18 | Approved before switching on | Q4 self-approved by Meera while off | 1. Ravi switches ON | Q4 stays approved; Unapprove offered to Meera and Ravi | | |
| ☐ | E19 | Unapprove by a preparer | ON; Q4 approved by Ravi | 1. Meera clicks Unapprove | Unapproved, as today | | |
| ☐ | E20 | Switched off again | ON → OFF | 1. Meera approves her own call | Approved by Meera; labelled "also prepared it" | | |
| ☐ | E21 | Approver without fund access | Tara | 1. Opens Q4 | "Access Denied" (unchanged) | | |
| ☐ | E22 | Validation rule blocker | A blocker rule fires on Q4 | 1. Ravi clicks Approve | Blocked with the rule's message (unchanged) | | |
| ☐ | E23 | Unapproved notices | Q4 has generated, unapproved notices | 1. Ravi clicks Approve | "Call not approved: There are unapproved documents for the remittances of this call. Please approve them first." | | |
| ☐ | E24 | Journey panel, ON | Full journey at Approve call | 1. Page opened | "The call is not approved yet — it needs an approver who did not prepare it" | | |
| ☐ | E25 | Journey panel, OFF | Solo Ventures at Approve call | 1. Page opened | "The call is not approved yet" (unchanged) | | |
| ☐ | E26 | Legacy self-created call | E12's call; ON | 1. Meera opens Actions | Approve disabled | | |
| ☐ | E27 | Open-ended settlement | Nilgiri Flexi Fund dealing date settles | 1. Settlement call created | Created approved, no journey (unchanged) | | |
| ☐ | E28 | Preparer sees the reason | Tea Estates by Meera | 1. Meera opens Actions | Disabled; "You prepared this distribution, so another approver must approve it (maker–checker is on)." | | |
| ☐ | E29 | Payment editor | Ravi changed a payment's income | 1. Ravi opens Actions; Priya approves | Disabled for Ravi; approved by Priya | | |
| ☐ | E30 | Imported distribution | ON; imported distribution, not approved | 1. Ravi marks payments completed | Works as today (no approval needed) | | |
| ☐ | E31 | Open-ended redemption settlement | Nilgiri Flexi Fund redemptions settle | 1. Settlement distribution created | Created approved (unchanged) | | |
| ☐ | E32 | Who is told | Q4: Meera created, Anil edited | 1. Meera requests | Only Ravi and Priya — not Meera/Anil (preparers), Tara (no fund access), Deepa (inactive), Vikram (no Approver role), Arun (LP), Kiran (other firm) | | |
| ☐ | E33 | Preparer without Approver role | Q4 by Anil | 1. Anil requests | Ravi, Meera, Priya told | | |
| ☐ | E34 | No checker | Ravi and Priya lose the Approver role | 1. Meera requests | Nothing sent; "No one else can approve this call. Ask a company admin to give the Approver role to a colleague with access to this fund, or turn off maker–checker in Settings." | | |
| ☐ | E35 | Asked within the hour | Meera asked at 10:42 | 1. Meera asks again at 11:05 | Nothing sent; "Approvers were already asked at 10:42. You can ask again after 11:42." | | |
| ☐ | E36 | Asked after the hour | Meera asked at 10:42 | 1. Meera asks at 11:43 | Sent again | | |
| ☐ | E37 | Setting off | Solo Ventures | 1. Sam opens Actions; then POSTs `request_approval` | No item; "Access Denied" | | |
| ☐ | E38 | Already approved | Q4 approved by Ravi | 1. Meera opens Actions; then POSTs `request_approval` | No item; "Access Denied" | | |
| ☐ | E39 | Email content | H18 | 1. Ravi reads the email | Names call, fund, call amount ₹5,00,00,000, due date "Dec 15, 2026", preparers, a link to Q4 | | |
| ☐ | E40 | Notes after approval | ON; Q4 approved | 1. Ravi edits notes | Stays approved; nothing sent | | |
| ☐ | E41 | Payment received | ON; Q4 approved | 1. ₹1.8 Cr payment recorded | Stays approved | | |
| ☐ | E42 | Remittance verified | ON; Q4 approved | 1. Ravi verifies a remittance | Stays approved | | |
| ☐ | E43 | New commitment | ON; Q4 approved | 1. ₹10 Cr commitment added; a ₹1 Cr remittance is created in Q4 | Stays approved | | |
| ☐ | E44 | Setting off | Solo Ventures call approved | 1. Sam changes its percentage | Stays approved | | |
| ☐ | E45 | No acting person | ON; Q4 approved | 1. A job with no acting user changes a remittance amount | Stays approved; warning logged with call id | | |
| ☐ | E46 | Recompute fees changes fees | ON; Q4 approved | 1. Anil clicks Recompute Fees; fees change | Withdrawn; Anil a preparer | | |
| ☐ | E47 | Recompute fees, no change | ON; Q4 approved | 1. Recompute leaves every fee the same | Stays approved | | |
| ☐ | E48 | Remittance deleted | ON; Q4 approved | 1. Anil deletes the ₹1.2 Cr remittance | Withdrawn | | |
| ☐ | E49 | Call deleted | ON; Q4 approved | 1. Ravi deletes Q4 | Deleted; no withdrawal alert | | |
| ☐ | E50 | Open-ended settlement | ON; Nilgiri Flexi settlement call | 1. A subscription payment is added, then changed | Stays approved | | |
| ☐ | E51 | Already notified | ON; Q4 approved and notices sent | 1. Anil changes a remittance | Withdrawn; alert adds "Investors were already sent this call's notice; they are not told about the change." | | |
| ☐ | E52 | Unapproved record | ON; Q4 not approved | 1. Anil changes a remittance | No withdrawal alert; Anil a preparer | | |
| ☐ | E53 | Distribution date | ON; Tea Estates approved | 1. Anil changes the distribution date | Withdrawn | | |
| ☐ | E54 | Switched on | Nilgiri off | 1. Ravi switches on | Nothing sent | | |
| ☐ | E55 | Saved unchanged | Nilgiri ON | 1. Ravi saves the entity form | Nothing sent | | |
| ☐ | E56 | A checker is not offered it | Q4 by Meera | 1. Ravi opens Actions; then POSTs `request_approval` | No Request approval item (he can approve); "Access Denied" | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | Non-admin direct request | Nilgiri ON | 1. Meera PATCHes the entity with the switch = 0 | "Access Denied"; still on | | |
| ☐ | X2 | Other firm's admin | Nilgiri ON | 1. Kiran PATCHes Nilgiri's entity | "Access Denied"; unchanged | | |
| ☐ | X3 | Preparer forces the call URL | Q4 by Meera | 1. Meera POSTs `/capital_calls/:id/approve` | "Access Denied"; Q4 unapproved | | |
| ☐ | X4 | Preparer via API (call) | Q4 by Meera | 1. Meera POSTs `approve.json` with a bearer token | 403 `{"error":"Access Denied"}` | | |
| ☐ | X5 | Preparer forces the distribution URL | Tea Estates by Meera | 1. Meera POSTs `/capital_distributions/:id/approve` | "Access Denied"; unapproved | | |
| ☐ | X6 | Preparer via API (distribution) | Tea Estates by Meera | 1. `approve.json` with a bearer token | 403 `{"error":"Access Denied"}` | | |
| ☐ | X7 | Bulk calls with own | Q4 + Q1 2027 by Meera; "Sep 2026 Top-up" by Anil | 1. Meera bulk-approves all three via API | Top-up approved; completion email lists "You prepared Q4 2026 Drawdown — another approver must approve it" and the same for Q1 2027 | | |
| ☐ | X8 | Bulk distributions with own | Tea Estates by Meera; "Pharma Exit" by Anil | 1. Meera bulk-approves both | Pharma Exit approved; Tea Estates listed as refused with the same message | | |
| ☐ | X9 | Other firm's approver | — | 1. Kiran POSTs approve on Q4 | "Access Denied" | | |
| ☐ | X10 | Support self-approves via another user | Sunil (acting as Meera) created Q4 | 1. Sunil, acting as Ravi, POSTs approve | "Access Denied" — Sunil is a preparer | | |
| ☐ | X11 | Double approve | Ravi approved Q4 | 1. Ravi re-submits approve | "Access Denied"; approved by stays Ravi | | |
| ☐ | X12 | Mass assignment | Q4 by Meera | 1. Meera PATCHes Q4 with `approved=1`, `approved_by_user_id=<Meera>` | Fields ignored; Q4 unapproved | | |
| ☐ | X13 | Other firm requests approval | — | 1. Kiran POSTs `request_approval` on Q4 | "Access Denied"; nothing sent | | |
| ☐ | X14 | Investor requests approval | — | 1. Arun POSTs `request_approval` on Q4 | "Access Denied"; nothing sent | | |
| ☐ | X15 | Read-only employee requests approval | — | 1. Vikram POSTs `request_approval` on Q4 | "Access Denied"; nothing sent | | |
| ☐ | X16 | Unrelated validation problem on the call (design C3) | ON; Q4 approved; Q4 fails an unrelated validation (e.g. a blank due date after a data fix — developer prepares) | 1. Anil changes a remittance | Anil's change saves; Q4 shows Approved: No (withdrawn); approvers are alerted | | |

---

## UI Journeys

**Journey 1 — preparer asks, checker approves** (design › What users see)

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J1.1 | Q4 2026 Drawdown (as Meera) | Open the call | Attributes card shows "Prepared by: Meera Shah" with an ⓘ tooltip "Created, imported or changed this call's figures" | | |
| ☐ | J1.2 | Same › Actions | Hover Approve | Approve is greyed; tooltip "You prepared this call, so another approver must approve it (maker–checker is on)." | | |
| ☐ | J1.3 | Same › Actions › Request approval | Click | Popup "Request approval" with Immediate Actions bar and 3 cards: "Ravi Iyer and Priya Nair are emailed", "You can't approve it yourself", "Nothing else changes"; buttons Cancel / Send request | | |
| ☐ | J1.4 | Popup | Click Send request | Flash "Approval requested from Ravi Iyer and Priya Nair." | | |
| ☐ | J1.5 | Ravi's inbox + bell | Open the email | Subject "Q4 2026 Drawdown (Nilgiri Growth Fund I) needs your approval"; link opens the call | | |
| ☐ | J1.6 | Q4 (as Ravi) › Actions › Approve | Approve | Flash "Capital call was successfully approved."; Approved = Yes | | |

**Journey 2 — figures changed after approval**

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J2.1 | Remittance of Q4 (as Anil) › Edit | Change call amount ₹1,20,00,000 → ₹1,25,00,000, save | Flash ends "Its approval was withdrawn because the figures changed — another approver must approve it again." | | |
| ☐ | J2.2 | Q4 page | Refresh | Approved = No; journey back at "Approve call"; Prepared by includes Anil Rao | | |
| ☐ | J2.3 | Ravi's / Priya's / Meera's inbox | Open | "Approval of Q4 2026 Drawdown was withdrawn: Anil Rao changed its figures after approval." | | |

**Journey 3 — setting**

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J3.1 | Settings › Entity › Edit (as Ravi) | Scroll to Approvals | Switch with ⓘ tooltip "Whoever created, imported or changed a call's or distribution's figures cannot approve it. Changing figures after approval withdraws the approval." | | |
| ☐ | J3.2 | Same | Untick, Save | "Entity was successfully updated."; Meera, Priya, Tara receive "Maker–checker for calls and distributions was turned off by Ravi Iyer on <today as Mon dd, yyyy>." | | |

---

## Role Sweep

Setting ON, call Q4 prepared by Meera. ✓ = allowed and works, ✗ = correctly blocked, ! = wrong.

| ID | Screen / action | Ravi (admin + Approver, not preparer) | Meera (Approver, preparer) | Anil (editor, no Approver) | Priya (Approver, not preparer) | Tara (Approver, no fund access) | Vikram (read-only) | Arun (LP) | Kiran (other firm) |
|---|---|---|---|---|---|---|---|---|---|
| R1 | Open Q4 | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ | ✗ | ✗ |
| R2 | Approve Q4 (menu) | ✓ enabled | ✗ greyed with reason | ✗ not shown | ✓ enabled | ✗ | ✗ not shown | ✗ | ✗ |
| R3 | Approve Q4 (direct POST) | ✓ | ✗ Access Denied | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ |
| R4 | Request approval (menu) | ✗ not shown (can approve) | ✓ shown | ✓ shown | ✗ not shown | ✗ | ✗ | ✗ | ✗ |
| R5 | Request approval (direct POST) | ✗ Access Denied | ✓ | ✓ | ✗ Access Denied | ✗ | ✗ | ✗ | ✗ |
| R6 | Unapprove approved Q4 | ✓ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ |
| R7 | Change the maker–checker switch | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| R8 | Same rows R2–R5 on Tea Estates Exit (distribution) | as R2–R5 | as R2–R5 | as R2–R5 | as R2–R5 | ✗ | ✗ | ✗ | ✗ |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Emails / alerts sent by this feature arrive | Approval requested, Approval withdrawn, Maker–checker turned off: correct recipients (never investors, never other firms), subject and link; dates shown as `Nov 19, 2026` | | |
| ☐ | C2 | Dates on changed screens | Due date and throttle times follow the user's locale (e.g. `15/12/2026` for en) | | |
| ☐ | C3 | Narrow / mobile width | Actions menu, greyed Approve tooltip and popup usable; no horizontal scroll | | |
| ☐ | C4 | Tenant isolation | Kiran (Kaveri) cannot open, approve or request approval on Nilgiri records, even with a direct URL (X9, X13) | | |
| ☐ | C5 | Regression on modified screens | With the setting OFF, call and distribution pages, Approve, Unapprove, Send Notification, Mark Payments Completed, imports and the entity form behave exactly as before | | |
| ☐ | C6 | Empty states | A call with no preparer rows (legacy) still shows "Prepared by" with its creator | | |
| ☐ | C7 | Looks like the rest of CapHive | Actions items match the existing dropdown; popup matches KYC "Request Updates"; Approvals block matches the Weekly Task Digest block | | |
| ☐ | C8 | No full page reloads for small actions | N/A by design — Approve and Request approval reload the call page (as Approve does today) | | |
| ☐ | C9 | Explains itself | Greyed Approve has its tooltip; Prepared by and the switch have ⓘ tooltips | | |
| ☐ | C10 | Speed on a large entity | Call page with 3,000 remittances opens in under ~2 s with the setting on | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | Pass / Pass with defects / Fail | |
