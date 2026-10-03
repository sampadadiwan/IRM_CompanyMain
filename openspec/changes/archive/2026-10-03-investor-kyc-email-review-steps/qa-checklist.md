# Set up and preview the KYC email before it reaches the LP — Manual QA Checklist

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
| Environment | Staging, on the build that contains this change |
| Company (entity) | An Investment Fund with KYCs enabled, AML enabled, and the investor KYC journey **already set up before this release** (so the two new tasks arrive by rollout, not by fresh seeding). Required individual KYC documents: "PAN Card, Address Proof, Photo" |
| Accounts | A company admin and a non-admin fund employee in that company; an investor (LP) portal user for "Nilesh Shah"; a fund admin in a **second** company |
| Seed data | Investor "Nilesh Shah" with one approved portal user and an email you can read. KYCs: #A (new, not sent), #B (form already sent), #C (filled in by the fund — submitted with no form sent), #D (imported and verified) |
| Company KYC email | Actions → "Custom KYC Notification" on the KYC list, `for_type` KYC, email method `notify_kyc_required`, subject "Complete your KYC for Urban Fund". Create it during H2/H1, not beforehand |
| Rollout | Ask a developer to run `investor_kyc_journeys:rollout` — first as a dry run, then with `EXECUTE=1` — for this company only (`ENTITY_ID`) |
| Background work | The journey re-evaluates on each KYC page view; nothing needs to be triggered by hand. Emails: check the LP's inbox (or the mail catcher on staging) |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H8 | The dry run reports the two tasks | The company's journey template still has 9 tasks | 1. Ask a developer to run the rollout **without** EXECUTE for this company. 2. Open Settings → Workflow Templates → "Investor KYC" | Output names "Set up KYC email" and "Preview the email" as additions; the template still shows 9 tasks and nothing has changed | | |
| ☐ | H7 | The rollout adds them in the right place | H8 done | 1. Ask a developer to run the rollout **with** EXECUTE. 2. Open the "Investor KYC" template | 11 tasks: "Set up KYC email" (1), "Preview the email" (2), "Send KYC form" (3), then the previous tasks in their old order; any approver you had set on "Compliance sign-off" is still there | | |
| ☐ | H2 | A new KYC with no company email | No KYC email exists for the company; KYC #A not sent | 1. Open KYC #A | Step bar shows 11 tasks; **Set up KYC email** is current and the panel says "No KYC email is set up — CapHive's default text will be sent. Set one up, or mark reviewed to use the default"; buttons **Mark reviewed** and **Custom KYC Notification** | | |
| ☐ | H1 | The panel names the company email | H2 done | 1. Click **Custom KYC Notification**. 2. Create the email with subject "Complete your KYC for Urban Fund", enabled, and save. 3. Go back to KYC #A | Panel now reads `Your KYC email "Complete your KYC for Urban Fund" will be sent — check it and mark reviewed`, with **Mark reviewed** and **Open KYC emails** | | |
| ☐ | H3 | Both confirmations reach the send task | H1 done | 1. On KYC #A click **Mark reviewed**. 2. On "Preview the email" click **Mark reviewed** | After step 1 the current task is **Preview the email**; after step 2 the current task is **Send KYC form** with "The KYC form has not been sent — send it, or fill it in and tick complete"; tasks 1 and 2 are ticked | | |
| ☐ | H4 | The preview opens this LP's own email | KYC #A at "Preview the email" (undo H3 step 2 by editing the company email, or use a second new KYC) | 1. Click **Preview KYC Required Notification** | A new tab opens showing the KYC email with **Nilesh Shah's** name, the company name and his KYC link — not raw `{{placeholders}}` | | |
| ☐ | H5 | Fund and LP walk one KYC to verified | A fresh KYC #E for Nilesh Shah; company email exists; AML enabled | 1. Confirm "Set up KYC email" and "Preview the email". 2. Click **Send KYC Required Notification**. 3. Open the LP's email, follow the link, attach a file to every upload field the form asks for (**Upload PAN / Tax ID**, **Upload Address Proof**, and any other required document field), tick the completion box and submit. 4. Back as the fund user: mark "Validate documents" reviewed. 5. Wait for / view the AML result. 6. Mark "Review KYC" reviewed. 7. Sign off "Compliance sign-off" (as its approver). 8. Click **Verify** | The step bar advances one task per action: email tasks become "–" after step 2, "Send KYC form" ✓, "Submit KYC" ✓ and "Upload required documents" ✓ after step 3, and the journey is **complete** after step 8 | | |
| ☐ | H6 | A brand-new company seeds 11 tasks | A second Investment Fund company with no KYC journey | 1. Use the "Set up journeys" menu for investor KYC. 2. Open its "Investor KYC" template | The confirmation mentions the journey template with 11 tasks; the template has all 11, the two email tasks first | | |

---

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | A KYC already sent is left alone | KYC #B (form sent, not submitted) | 1. Open KYC #B | Both email tasks show "–" with "The KYC form has already been sent"; the current task is "Submit KYC" | | |
| ☐ | E2 | A fund-filled KYC | KYC #C (submitted, no form ever sent) | 1. Open KYC #C | Both email tasks and "Send KYC form" show "–" with "Filled in by the fund"; the current task is a later one | | |
| ☐ | E3 | An imported, verified KYC | KYC #D | 1. Open KYC #D | Both email tasks show "–" with "Verified without this step" and the journey is complete | | |
| ☐ | E11 | A KYC waiting to be sent moves back to the gate | A KYC that was current at "Send KYC form" before the rollout | 1. After H7, open that KYC | It is now current at **Set up KYC email** | | |
| ☐ | E4 | Editing the email withdraws both confirmations | KYC #A with both email tasks ticked and its form not sent | 1. Edit the company KYC email (change the subject) and save. 2. Open KYC #A | Current task is **Set up KYC email** with the message "Email template changed after review"; both ticks are gone | | |
| ☐ | E5 | Editing the email after sending changes nothing | KYC #B (form sent) | 1. Edit the company KYC email and save. 2. Open KYC #B | KYC #B's journey is exactly as it was in E1 | | |
| ☐ | E6 | Creating the first company email withdraws confirmations | A KYC with both email tasks ticked while **no** company email existed, form not sent | 1. Create the company KYC email. 2. Open that KYC | Back at **Set up KYC email**, now naming the new email by subject | | |
| ☐ | E7 | Editing a different KYC email does nothing | A company KYC **reminder** email exists; KYC #A has both tasks ticked, form not sent | 1. Edit the reminder email and save. 2. Open KYC #A | KYC #A still shows both email tasks ticked and the same current task | | |
| ☐ | E8 | Sending is never blocked | A fresh KYC with neither email task confirmed | 1. Click **Send KYC Required Notification** from the Actions menu | The form is sent (success message, the LP gets the email) and both email tasks become "–" with "The KYC form has already been sent" | | |
| ☐ | E9 | Running the rollout twice is harmless | H7 done | 1. Ask a developer to run the rollout with EXECUTE again. 2. Open the template | Output reports nothing to add for this company; the template still has exactly 11 tasks, with no duplicates | | |
| ☐ | E10 | A template without "Send KYC form" | A company whose "Investor KYC" template has had "Send KYC form" removed (ask an admin to remove it on a test company) | 1. Run the rollout with EXECUTE. 2. Open the template | Neither email task is added | | |
| ☐ | E12 | Admin edits survive | On the test company: an approver set on "Compliance sign-off" and "Run AML screening" removed | 1. Run the rollout with EXECUTE. 2. Open the template | The two email tasks are added; the approver is still set and "Run AML screening" is still absent | | |
| ☐ | E13 | A company with its own KYC rule | A company with its own KYC auto-assignment rule and no seeded template | 1. Run the "Set up journeys" menu for investor KYC | The template is created with 11 tasks, no extra rule is added, and the confirmation says so | | |
| ☐ | E14 | A disabled company email reads as "none" | The company KYC email exists but is **not enabled** | 1. Open a fresh KYC | The panel shows the "No KYC email is set up — CapHive's default text will be sent…" message and **Custom KYC Notification** | | |

---

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | Saving the email never fails because of the journey | Several KYCs in the company, some sent, some not | 1. Edit the company KYC email and save | The save succeeds and redirects with "Custom notification was successfully updated." — no error page, whatever the journeys do afterwards | | |
| ☐ | X2 | Only unsent KYCs are reopened | At least 3 KYCs with journeys: two unsent with both tasks ticked, one already sent | 1. Edit the company KYC email and save. 2. Open all three | The two unsent ones are back at "Set up KYC email"; the sent one is untouched | | |
| ☐ | X3 | The LP sees no journey | KYC #E at an email task, LP link available | 1. Open the KYC as the LP, through their emailed link | No step bar, no "What's needed now" panel, no **Mark reviewed** button anywhere | | |

---

## UI Journeys

Journey J1 — the everyday gate on the KYC page (design Part 2 → [What users see](design.md#what-users-see)).

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J1.1 | KYC page, new KYC | Open it | ① Step bar with 11 tasks, "Set up KYC email" marked current; ② panel heading "1 of 11 · Set up KYC email" | | |
| ☐ | J1.2 | KYC page, task 1 | Click the second button (**Open KYC emails** or **Custom KYC Notification**) | The KYC emails list filtered to KYC notifications, or the new-notification form with the KYC type pre-filled | | |
| ☐ | J1.3 | KYC page, task 1 | Click **Mark reviewed** | Task 1 ticked, panel moves to "2 of 11 · Preview the email" without a full page reload | | |
| ☐ | J1.4 | KYC page, task 2 | Click **Preview KYC Required Notification** | The preview opens in a **new tab**; the KYC page stays where it was | | |
| ☐ | J1.5 | KYC page, task 2 | Click **Mark reviewed** | Task 2 ticked, panel moves to "3 of 11 · Send KYC form" with its existing **Send KYC Required Notification** button | | |
| ☐ | J1.6 | KYC page, after an email edit | Reopen the KYC | Panel back at task 1 with "Email template changed after review"; the days-here chip restarts | | |

---

## Role Sweep

| ID | Screen / action | Company admin | Fund employee (can edit KYCs) | Fund employee (read-only) | Investor (LP) | Other-company admin |
|---|---|---|---|---|---|---|
| R1 | See the two tasks in the step bar on a KYC | | | | | |
| R2 | Click **Mark reviewed** on "Set up KYC email" | | | | | |
| R3 | Click **Open KYC emails** / **Custom KYC Notification** | | | | | |
| R4 | Click **Preview KYC Required Notification** | | | | | |
| R5 | Open another company's KYC by URL | | | | | |

Expected: ✓ for the company admin on R1–R4; ✓ for an editing employee on R1–R4 (R3 subject to their
notification access); R2 correctly absent (✗) for a read-only employee; ✗ everywhere for the LP and
the other-company admin, with R5 refused as it is today.

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | The KYC email the LP receives | Same subject and body as the preview showed; the link works; dates shown as `Aug 19, 2026` | | |
| ☐ | C2 | Dates on changed screens | The panel's "n days here" chip and any confirmation timestamps follow the user's locale format | | |
| ☐ | C3 | Narrow / mobile width | The 11-task step bar wraps onto more rows (6 / 4 / 3 / 2 pills per row as the window narrows) with no dangling connector line and no horizontal page scroll; both panel buttons stay reachable | | |
| ☐ | C4 | Tenant isolation | A second company's admin editing **their** KYC email does not move any journey in this company | | |
| ☐ | C5 | Regression: capital call journey | A capital call still shows "Review email" and "Check preview" with only **Mark reviewed** (no second button) and behaves as before | | |
| ☐ | C6 | Regression: capital distribution journey | Unchanged, as C5 | | |
| ☐ | C7 | Regression: KYC page Actions menu | Send, reminder, previews, request updates, verify all behave as before | | |
| ☐ | C8 | Regression: custom notifications screens | Creating, editing and deleting any notification still works and redirects with its usual message | | |
| ☐ | C9 | Real-time updates | With the KYC page open, a colleague confirming a task or sending the form updates the step bar without a reload | | |
| ☐ | C10 | User guide | `docs/user_guides/investor_kyc_user_guide.md` lists all 11 tasks and answers "why did my review reset?" | | |

---

## Sign-off

| Field | Value |
|---|---|
| Tester | |
| Build / commit | |
| Environment | |
| Date | |
| Result | pass / pass with defects / fail |
| Open defects | |
