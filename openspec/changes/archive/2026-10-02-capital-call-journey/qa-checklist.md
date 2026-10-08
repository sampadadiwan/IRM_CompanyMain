# Capital Call Journey — Manual QA Checklist

> **Audience:** Testers running the feature by hand on a deployed build. No code knowledge needed.
> **Companion documents:** [Proposal](proposal.md) · [Design](design.md)

> **How to use:** work top to bottom. Tick ☐ → ☑ and write Pass or Fail for each row. For a Fail,
> put the defect link in Notes. Row IDs match the design's worked examples (H/E/X) and UI journeys
> (J), so a failure maps straight to the automated test that should have caught it.

**ID legend:** **H** = Happy path · **E** = Edge case · **X** = Error case · **J** = UI journey
step (J2.3 = journey 2, step 3) · **R** = Role sweep · **C** = Cross-cutting check

**Words used below:** the **step bar** is the row of tasks at the top of a capital call page. Each task
has a mark: ✓ done · ● we are here (waiting on this, not done yet) · ○ later · ↺ back here (was done,
must be done again) · n/a (doesn't apply). The **panel** is the "What's needed now" box under it.

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
| Environment | Staging (IN). Repeat the C rows on US staging |
| Accounts | **Admin** (company admin, Alpha Capital) · **Priya** (employee with edit rights on calls and the *approver* role) · **Arjun** (employee, approver; the CFO) · **Vik** (employee, view-only on calls) · **Investor** (an investor login on Alpha Fund I) |
| Second entity | **Beta Partners** with its own admin and one call, for isolation checks |
| Seed data | Alpha Capital → Alpha Fund I (INR) with a call notice template and a CapitalCall custom notification; 40 commitments, all KYC verified, one with Skip Doc Gen = Yes, two whose investors have no Capital Call subscriber; unit prices available |
| Rollout | Ask a developer to run the journey rollout for Alpha Capital (dry run first, then for real) before H1 |
| Journey changes | For rows that need the CFO step, Admin adds a human step "CFO sign-off" (approver Arjun, reminder every 1 day) to the Full journey at position 7, before Approve call |
| Background work | Remittance and notice generation run in the background; wait about a minute. The **15-minute check** and the **daily reminder** run on their own; to avoid waiting, ask a developer to run them now ("run the journey tick" / "run the reminder job") |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Rollout seeds the journeys | Alpha Capital not rolled out | 1. Developer runs the rollout dry run 2. then for real 3. Admin opens Settings → Workflow Templates | Dry run lists 2 templates, 2 rules and the flag and changes nothing. Afterwards **Capital Call — Full: Notify Investors** (11 tasks) and **Capital Call — Light: Record Only** (4 tasks) appear, plus two auto-assign rules | | |
| ☐ | H2 | New call starts the Full journey | H1 done | 1. Priya creates "Q3 Drawdown" at 10% 2. lands on the call page 3. waits a minute, reloads | Step 1: **● Create remittances**. After reload: ✓ Create remittances, ✓ Add call notice template, **● Generate notices** | | |
| ☐ | H3 | Panel while notices are partly approved | H2; notices generated; 12 of 40 approved | 1. Open the call | Panel: "28 of 40 call notices await approval" with **View notices to approve →** opening the call's generated notices | | |
| ☐ | H4 | Mark reviewed | all notices approved | 1. Click **Mark reviewed** on Review email 2. again on Check preview | Both ✓; history shows Priya and the time; current task moves on | | |
| ☐ | H5 | Approve and send are picked up | tasks before Approve call done | 1. Arjun approves 2. Priya clicks Send Notification 3. wait for the next 15-minute check (or reload) | Approve call ✓, Send notices ✓ (39 sent; the Skip Doc Gen investor excluded), **● Collect payments** | | |
| ☐ | H6 | Last payment completes collection | H5 | 1. Record the last payment 2. open the call | ✓ Collect payments, **● Verify remittances** | | |
| ☐ | H7 | Journey completes | all verified | 1. Allocate Units 2. wait for the next check or reload | Panel: "Journey complete" with the date; every task ✓ or n/a | | |
| ☐ | H8 | Sign-off after earlier tasks | CFO step added; tasks 1–6 done | 1. Arjun approves the CFO sign-off from his email | CFO ✓; current moves straight on to Approve call | | |
| ☐ | H9 | Owner reminder | Approve notices current for over 2 days | 1. Developer runs the reminder job | Priya gets "Approve notices — 28 of 40 call notices await approval" with a link to the call | | |
| ☐ | H10 | Calls after rollout get a journey | H1 | 1. Create any new call | It shows a step bar | | |
| ☐ | H11 | Dry run writes nothing | an un-rolled-out entity | 1. Developer runs the dry run | Lists templates, rules and flag per entity; no templates appear in Settings | | |
| ☐ | H12 | Advisory only on Approve | notices approved; Review email current | 1. Arjun clicks Approve | Dialog shows its usual message with **no** journey list; **Approve** proceeds and approves | | |
| ☐ | H14 | User guide updated | — | 1. Open the Capital Calls user guide | A Journey section describes all 11 Full and 4 Light tasks with a diagram each; FAQs present | | |
| ☐ | H15 | Late detection still timed right | Review email interval 2 days | 1. Approve the last notice Mon 10:00 and close the call 2. check history after the next 15-minute check 3. check email Wed and Thu mornings | History says Approve notices passed **Mon 10:00**. No reminder Wed morning; Priya reminded Thu morning | | |
| ☐ | H16 | Approver told without anyone viewing | CFO step placed right after Approve notices | 1. Approve the last notice on the Documents screen and log off 2. wait 15 minutes | Arjun receives "your sign-off is needed" within 15 minutes | | |
| ☐ | H17 | Approval workflows untouched | a KYC approval workflow is running | 1. Wait for a 15-minute check | The KYC workflow page and history are unchanged | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | Existing workflows behave as before | an existing KYC Review workflow | 1. Run it through approve and reject as usual | Same behaviour as before the release; no step bar | | |
| ☐ | E2 | Existing button disabling | KYC Review lists "Approve" as gated, still running | 1. Open the KYC record | Approve is disabled as today | | |
| ☐ | E3 | Imported call on Full | Admin points both rules at Full | 1. Import a call | Notice, email and Approve call tasks show greyed **n/a**; hover reads "Notices are not sent for imported calls" | | |
| ☐ | E4 | No unit prices | call without unit prices, all verified | 1. Open the call | Allocate units n/a "No unit prices set on this call"; journey complete | | |
| ☐ | E5 | Missing template | fund has no call notice template | 1. Create a call, wait, open it | **● Add call notice template**: "The fund has no call notice template" + link | | |
| ☐ | E6 | Readiness warnings before sending | 2 investors with no subscriber | 1. Open the call before sending 2. again after sending | Before: "2 investors have nobody subscribed to Capital Call emails". After: gone | | |
| ☐ | E7 | Unapprove and regenerate notices | all notices approved, both reviews done | 1. Unapprove the notices on the Documents screen 2. Generate Documents | After 1: ↺ Approve notices, and both review confirmations are reset (they were given before the change). After 2: still ● Approve notices with new notices | | |
| ☐ | E8 | Figures edit resets CFO sign-off | CFO signed off | 1. Change percentage to 12% | ↺ Create remittances; banner "Moved back to "Create remittances" — call figures changed by Priya S on …"; Arjun gets "your sign-off was reset" | | |
| ☐ | E9 | Keep sign-off option | CFO step has "Keep sign-off when moved back" ticked | 1. Change figures, recompute, unapprove notices, regenerate, re-approve | CFO ✓ again without Arjun voting again | | |
| ☐ | E10 | Undo and redo quickly | CFO signed off; notices approved | 1. Unapprove one notice 2. re-approve it within a minute; don't open the call | History shows the move back at the unapprove; Arjun's sign-off reset | | |
| ☐ | E10b | Unapprove call keeps earlier sign-off | CFO signed off; call approved | 1. Click Unapprove | ↺ Approve call; CFO still ✓; banner "Moved back to Approve call — unapproved by Priya S on …" | | |
| ☐ | E10c | Check during a long recompute | big call; CFO signed off | 1. Click Recompute Call 2. reload the page while it runs 3. wait for it to finish | CFO sign-off is reset after the recompute finishes even though the page view saw the move back first | | |
| ☐ | E11 | Move back without an undo | Collect payments ✓ | 1. Ask a developer to delete a payment from the console 2. open the call | ↺ Collect payments in history with no person; no sign-off reset | | |
| ☐ | E12 | Email edit invalidates reviews | both reviews ✓, not sent | 1. Edit the fund's CapitalCall email | Both reviews back to not done: "Email template changed after review" | | |
| ☐ | E13 | Figures edit then recompute | notices approved | 1. Change percentage 2. Recompute Call | After 1: "Remittances were calculated before the call figures changed — recompute". After 2: "Notices were generated before the remittances changed — unapprove them on the Documents screen, then click Generate Documents" | | |
| ☐ | E14 | Re-running rollout | Admin added the CFO step | 1. Developer re-runs rollout | No duplicate templates; CFO step still there | | |
| ☐ | E15 | Existing call untouched | a call created before rollout, mid-way | 1. Run rollout 2. open that call | No step bar; page as before | | |
| ☐ | E16 | No reminder without interval | template and step have no interval | 1. Leave a step stuck for 3 days; run the reminder job | No reminder email | | |
| ☐ | E17 | Edit a call without a journey | pre-rollout call | 1. Change its percentage | Saves normally; no error | | |
| ☐ | E18 | Unverify reopens a finished journey | journey complete | 1. Unverify one remittance | Journey active again; ↺ Verify remittances | | |
| ☐ | E19 | Large call is fast | call with 5,000 investors | 1. Open it | Page loads normally (developer confirms no full remittance load) | | |
| ☐ | E20 | Unverified KYC | 2 investors' KYC unverified | 1. Generate Documents | ● Generate notices: "2 investors have unverified KYC — notices are not generated for them" | | |
| ☐ | E21 | Uploaded call | Upload-basis call | 1. Import a 25-investor file 2. open the call while it runs 3. after it finishes | During: "Remittance upload in progress". After: ✓ Create remittances | | |
| ☐ | E22 | Light journey | a call on Light | 1. Create, pay, verify, allocate | Only the 4 Light tasks show; journey completes | | |
| ☐ | E23 | Call set not to notify | Full; "send call notice" off | 1. Open the call | Template … Check preview and Send notices n/a "This call is set to not notify investors" | | |
| ☐ | E24 | Email edit after sending | call A sent, call B not, same fund | 1. Edit the fund's CapitalCall email | Call B asks for review again; call A unchanged | | |
| ☐ | E25 | Imported calls get Light | seeded entity | 1. Import a call | It shows the Light journey | | |
| ☐ | E26 | Rejected sign-off | CFO step current | 1. Arjun rejects with "Fee looks wrong" | Task stays current "Rejected by Arjun M: Fee looks wrong"; Arjun can vote again | | |
| ☐ | E27 | Skip Doc Gen warning | 1 commitment with Skip Doc Gen | 1. Open the call before sending | "1 commitment has Skip Doc Gen set and will not be emailed" | | |
| ☐ | E28 | Sending picked up | — | 1. Click Send Notification; don't reload 2. wait 15 minutes, open the call | ✓ Send notices; ● Collect payments | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | System task needs a check | Admin editing a Full task | 1. Set kind System, leave Check empty, Save | Error "Check must be a Capital Call check" | | |
| ☐ | X2 | Only Capital Call checks offered | Admin editing a Full task | 1. Open the Check list | Only Capital Call checks listed | | |
| ☐ | X3 | View-only user can't confirm | Vik logged in; Review email current | 1. Open the call | No **Mark reviewed** button | | |
| ☐ | X4 | Owner left the company | owner user deactivated | 1. Open the call 2. run the reminder job | Panel "Owner unavailable — update the journey template"; no email | | |
| ☐ | X5 | Entity not rolled out | Beta Partners | 1. Create a call | No step bar; page as today | | |
| ☐ | X6 | A check fails | ask a developer to force a check error | 1. Open the call | "Could not check this step — support has been notified"; developer confirms the alert | | |

---

## UI Journeys

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J1.1 | Settings → Workflow Templates | open after rollout | ① both journeys with task descriptions | | |
| ☐ | J1.2 | Auto-assign rules | change the default rule to Light | ② new calls get Light | | |
| ☐ | J1.3 | Full journey → add task | add "CFO sign-off", kind Human, approver Arjun, position 7 | ③ saved; new calls show the CFO task | | |
| ☐ | J1.4 | Edit a System task | open it | ④ Check / Skip lists; ⑤ owner + reminder; ⑥ unlocks | | |
| ☐ | J2.1 | Capital call page | create a call | ① step bar starts at ● Create remittances | | |
| ☐ | J2.2 | Capital call page | generate notices | ③ "0 of 39 …" then ✓; ● Approve notices | | |
| ☐ | J2.3 | Panel | click ④ **View notices to approve →** | A new window opens on the call's notices still awaiting approval; the call page stays open | | |
| ☐ | J2.4 | Capital call page | approve notices, return | ✓ Approve notices; ④ becomes **Mark reviewed** | | |
| ☐ | J2.5 | Approve dialog | approve the call | usual confirmation, no journey list (the panel shows it) | | |
| ☐ | J2.6 | Capital call page | follow payments to the end | ③ "Collected 62%" …; "Journey complete" | | |
| ☐ | J3.1 | Capital call page | Unapprove | banner "↺ Moved back to Approve call — unapproved by …" | | |
| ☐ | J3.2 | Arjun's inbox | after a figures edit | "Your sign-off was reset" with reason and link | | |
| ☐ | J3.3 | Workflow instance page | open history | moved back and sign-off reset entries with who and why | | |
| ☐ | J4.1 | Priya's inbox | a task stalls past its interval | reminder email naming the task, status line, link; panel "current for N days" | | |

---

## Role Sweep

✓ = allowed and works · ✗ = correctly blocked · ! = wrong

| ID | Screen / action | Admin | Priya (edit + approver) | Arjun (approver) | Vik (view only) | Investor | Beta Partners user |
|---|---|---|---|---|---|---|---|
| R1 | See step bar and panel | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ |
| R2 | Mark reviewed | ✓ | ✓ | ✓ if edit rights | ✗ | ✗ | ✗ |
| R3 | Vote on CFO sign-off | — | — | ✓ | ✗ | ✗ | ✗ |
| R4 | Edit journey templates and tasks | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ |
| R5 | Open the call's workflow history page | ✓ | ✓ | ✓ | as today | ✗ | ✗ |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Owner reminder, sign-off reset and "sign-off needed" emails | Right recipient, subject and link; dates shown like `Oct 07, 2026` | | |
| ☐ | C2 | Dates on the panel, banner and history | Locale format (e.g. `07/10/2026` for en) | | |
| ☐ | C3 | Narrow / mobile width | Step bar wraps; no horizontal scroll; Mark reviewed reachable | | |
| ☐ | C4 | Tenant isolation | Beta Partners user cannot open Alpha's journey, history or Mark reviewed, even with a direct URL | | |
| ☐ | C5 | Regression on modified screens | Call page actions, Approve/Unapprove, Send Notification, Recompute, Generate Documents, Verify, bulk actions, Documents approve/unapprove, custom notifications and workflow screens work as before | | |
| ☐ | C6 | Empty states | A brand-new call with nothing done shows a sensible first task, not an empty bar | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
