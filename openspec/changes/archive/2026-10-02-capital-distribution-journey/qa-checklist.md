# Capital Distribution Journey — Manual QA Checklist

> **Audience:** Testers running the feature by hand on a deployed build. No code knowledge needed.
> **Companion documents:** [Proposal](proposal.md) · [Design](design.md)

> **How to use:** work top to bottom. Tick ☐ → ☑ and write Pass or Fail for each row. For a Fail,
> put the defect link in Notes. Row IDs match the design's worked examples (H/E/X) and UI journeys
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
| Environment | Staging (IN), then US |
| Accounts | Priya — company admin + Approver; Rahul — Approver; Ken — employee with edit rights, no Approver; an investor user of Asha Ventures |
| Second entity | Any user of a different fund company |
| Seed data | Fund "Growth Fund II" (INR) with a Distribution Template, unit type A at ₹100; investors Asha Ventures, Birla Family Trust, Chen Holdings, ₹1 Cr each, KYC verified (Chen's unverified for E5); each investor has a user subscribed to Distribution emails |
| Background work | Jobs run on their own within seconds. The 15-minute re-check can be forced by a developer (`WorkflowEvaluateJob.perform_now`) |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Rollout task | Company not set up | 1. Developer runs `bin/rails capital_distribution_journeys:rollout ENTITY_ID=<id>` 2. Then with `EXECUTE=1` | Dry run prints what it would add and changes nothing; execute adds Full and Light journeys under Workflow Templates | | |
| ☐ | H2 | New distribution gets Full | Set up | 1. Create "Q3 2026 Exit Proceeds", income 30,00,000 2. Stay on the page | Step bar appears; within seconds Create payments ✓, Generate notices ● | | |
| ☐ | H3 | Notices partly approved | 3 notices, 1 approved | Open distribution | Panel "Approve notices: 2 of 3 notices await approval", button "View notices to approve" | | |
| ☐ | H4 | Mark reviewed | All notices approved | Click Mark reviewed on Review email | Check preview becomes current | | |
| ☐ | H5 | Approve from the panel | Reviews done | As Priya click panel "Approve", confirm | Distribution approved; Mark payments completed current | | |
| ☐ | H6 | Complete payments | Approved | Panel → Mark Payments Completed, confirm | Email investors current | | |
| ☐ | H7 | Email investors | Completed | Panel → Send Payment Notifications, confirm | Investors receive the email; Redeem units current; warnings gone | | |
| ☐ | H8 | Redeem units | Emailed | Panel → Redeem Units, confirm | Every task ✓ | | |
| ☐ | H9 | Imported gets Light | Set up | Import a distribution and its payments | Step bar shows only Create payments, Mark payments completed, Redeem units | | |
| ☐ | H10 | Setup from the UI | New company, not set up | Workflow Templates → "Set up capital distribution journeys", confirm | Notice "Capital distribution journeys set up: Full and Light journeys, auto-assignment rules. New distributions will get a journey."; button now "✓ Capital distribution journeys set up", disabled | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | No template | Fund without Distribution Template | Create distribution | Generate notices and Approve notices show "–", tooltip "No distribution notice template" | | |
| ☐ | E2 | Send Notification off | Untick Send Notification | Create distribution | Notice, review and Email investors show "–" "Investors are not emailed for this distribution" | | |
| ☐ | E3 | All Skip Doc Gen | Every commitment Skip Doc Gen | Create distribution | Same tasks "–" "Every commitment is set to Skip Doc Gen" | | |
| ☐ | E4 | Upload basis | Basis Upload | 1. Create 2. Upload a file with an error | "No payments uploaded yet", then "Payment upload failed — fix and re-import" | | |
| ☐ | E5 | KYC blocks a notice | Chen KYC unverified | Generate Documents | "1 investor has unverified KYC — notices are not generated for them" | | |
| ☐ | E6 | Warnings | Asha Skip Doc Gen; Birla has no subscribed user | Open distribution; later email investors | "1 commitment has Skip Doc Gen set and will not be emailed" and "1 investor has nobody subscribed to Distribution emails"; gone after emailing | | |
| ☐ | E7 | No unit prices | No unit prices | Open | Redeem units "–" "The distribution has no unit prices" | | |
| ☐ | E8 | Recompute after CFO sign-off | Admin added "CFO sign-off" to Full; Rahul signed off | Actions → Recompute Fees | Amber "Moved back to "Generate notices" — Fees recomputed …"; CFO sign-off pending again | | |
| ☐ | E9 | Untick Completed | At Email investors | Edit a payment, untick Completed, save | Back to Mark payments completed | | |
| ☐ | E10 | Delete a payment | At Approve notices | Delete Chen's payment | Back to Create payments | | |
| ☐ | E11 | Regenerate notices | 1 of 3 approved | Generate Documents again | Approve notices current; workflow history shows "Notices regenerated" | | |
| ☐ | E12 | Unapprove a notice | At Review email | Unapprove one notice on Documents | Back to Approve notices | | |
| ☐ | E13 | Delete units | Journey complete | Delete one redeemed fund unit | Back to Redeem units | | |
| ☐ | E14 | Email edited | Review email confirmed; a second distribution already emailed | Edit the fund's Distribution notification | First: Review email and Check preview pending, "Email template changed after review"; second unchanged | | |
| ☐ | E15 | Date change | At Approve distribution | Change distribution date | Moved back to Generate notices with "Fees recomputed" | | |
| ☐ | E16 | Live: notice job | Page open at Generate notices | Generate Documents, don't reload | Bar moves on by itself | | |
| ☐ | E17 | Live: colleague | Page open at Mark payments completed | Rahul completes payments in another browser | Bar moves on by itself | | |
| ☐ | E18 | Date-range approval | Unapproved notices on 2 distributions | Documents → Approve documents by date range | Both distributions move on | | |
| ☐ | E19 | Old distribution | Distribution created before setup | Open it; approve its notices; complete payments | No step bar; everything works as before | | |
| ☐ | E20 | Re-run keeps edits | CFO step added to Full | Run the rollout again / button | No duplicate templates; CFO step still there | | |
| ☐ | E21 | Delete with journey | No redeemed units | Delete the distribution | Deleted | | |
| ☐ | E22 | Notices link | 2 unapproved notices | Actions → View Generated Notices To Approve | New window with only this distribution's 2 notices and the approval hint; original page still open | | |
| ☐ | E23 | Hint wording | — | New distribution form | Send Notification hint: "Allow emailing investors about this distribution. Emails are sent from Actions → Send Payment Notifications." | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | Non-approver | Log in as Ken | Open an unapproved distribution → Actions | No "Approve" item; developer confirms a direct request is refused | | |
| ☐ | X2 | Bulk complete unapproved | Unapproved distribution | Developer sends the Mark Payments Completed request directly | "Access Denied"; no payment completed | | |
| ☐ | X3 | Non-admin setup | Ken | Open Workflow Templates | No distribution setup button | | |
| ☐ | X4 | Generation error with no user | Import a distribution whose payment generation fails | Wait for the job | No second crash in error monitoring; error logged | | |
| ☐ | X5 | Recompute message | — | Recompute Fees | First toast names the distribution: "Recomputing fees for all payments for distribution Q3 2026 Exit Proceeds" | | |
| ☐ | X6 | Other entity | Second-entity user | Open `/capital_distributions/<id>/journey` | Access denied | | |

---

## UI Journeys

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J2.1 | Distribution page | Open a new distribution | ① Journey header, template name, "x of y done", ② step bar | | |
| ☐ | J2.2 | Distribution page | Leave open while payments generate | Bar moves without reload | | |
| ☐ | J2.3 | Distribution page | Click panel "View notices to approve" | New window with this distribution's unapproved notices | | |
| ☐ | J2.4 | Distribution page | Mark reviewed on Review email | Check preview current | | |
| ☐ | J2.5 | Distribution page | Click panel "Approve" | Actions menu opens, Approve flashes, confirmation appears | | |
| ☐ | J2.6 | Distribution page | Read warnings | Warnings shown until investors emailed | | |
| ☐ | J2.7 | Distribution page | Admin opens Workflow tab | The distribution's journey listed | | |

---

## Role Sweep

| ID | Screen / action | Company admin + Approver | Employee (update, no Approver) | Read-only employee | Investor | Other-entity user |
|---|---|---|---|---|---|---|
| R1 | See step bar | ✓ | ✓ | ✓ | ✗ | ✗ |
| R2 | Mark reviewed | ✓ | ✓ | ✗ | ✗ | ✗ |
| R3 | Approve distribution | ✓ | ✗ | ✗ | ✗ | ✗ |
| R4 | Mark Payments Completed (approved) | ✓ | ✓ | ✗ | ✗ | ✗ |
| R5 | View Generated Notices To Approve | ✓ | ✓ | ✗ | ✗ | ✗ |
| R6 | Workflow tab | ✓ | ✗ | ✗ | ✗ | ✗ |
| R7 | Setup button | ✓ | ✗ | ✗ | ✗ | ✗ |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Emails / alerts | Distribution emails unchanged; task reminders dated like `Aug 19, 2026` | | |
| ☐ | C2 | Dates on changed screens | "Moved back … on 07/10/2026 09:30" in the user's locale format | | |
| ☐ | C3 | Narrow / mobile width | Step bar wraps; panel button reachable; no horizontal scroll | | |
| ☐ | C4 | Tenant isolation | Other-entity user cannot open the journey, distribution or setup | | |
| ☐ | C5 | Regression | Capital call page journey looks and works as before (bar, panel, Approve, live update, setup button); distribution Approve / Generate / Send / Redeem / Recompute still work | | |
| ☐ | C6 | Empty states | Distribution with no journey shows no empty card | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
