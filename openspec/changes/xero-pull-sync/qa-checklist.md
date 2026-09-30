# Xero Pull Sync (Phase I) — Manual QA Checklist

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
| Environment | Staging (India). Repeat C-rows on US staging if the US Xero app is configured |
| Xero | Two Xero **demo companies** (free, developer.xero.com): "Alpha Growth Fund I Pty Ltd" (set base currency AUD) and "Acme Robotics Ltd" (GBP). One extra demo org in USD for X2. One tester Xero login that can see all three |
| Accounts | Asha, fund admin, Alpha Capital · Ben, fund user with KPI access, Alpha Capital · Chen, user of Acme Robotics' own entity · Ivy, investor-side user of Alpha Growth Fund I |
| Second entity | Dan, fund admin of Beta Capital, with its own fund "Beta Fund" |
| Seed data | Alpha Capital with Xero and KPIs switched on (ask a developer to turn on the Xero feature), KPI reporting frequency Monthly. Fund "Alpha Growth Fund I" (AUD). Portfolio company "Acme Robotics Ltd" with KPI mappings: "Total Income" → Revenue, "Gross Profit" → Gross Profit, "Total Bank" → Cash. An allocation run for Alpha Growth Fund I covering 01/04/2026–30/06/2026. In the fund's Xero demo org, post: Audit Fees 12,000.00 in Q3 2026, Interest Income 500.00 in Q3 2026, and Audit Fees 12,000.00 in Q2 2026 |
| Background work | Fund: **Sync now** on the Xero tab. Portco KPI pull and the nightly run: ask a developer to run the Xero nightly job. Upload reminders: ask a developer to run the periodic KPI reminder job |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Connect a fund (one org) | Signed in as Asha; fund not connected; Xero login sees only the fund org | 1. Open Alpha Growth Fund I → Xero tab 2. Click **Connect Xero** 3. Sign in to Xero and click Allow | Back on the Xero tab: "Alpha Growth Fund I Pty Ltd (AUD)", "Connected"; account mapping lists the org's accounts, all **Unmapped**; no new account entries | | |
| ☐ | H2 | Connect, picking one of several orgs | Xero login sees three orgs; fund disconnected | 1. Connect Xero 2. Allow all three orgs 3. Pick "Alpha Growth Fund I Pty Ltd" | Only that org is shown as connected | | |
| ☐ | H3 | Map an account | H1 done | 1. Unmapped filter 2. Legal Fees: type "Expense", name "Legal Fees" 3. Save 4. Post Legal Fees 1,000.00 in Q3 in Xero 5. Sync now 30/09/2026 | Row moves to Mapped; after sync a fund-level "Legal Fees" 1,000.00 entry exists for 30/09/2026 | | |
| ☐ | H4 | Nightly run pulls two quarters | Audit Fees mapped | 1. Ask a developer to run the nightly job | Entries appear for both 30/09/2026 and 30/06/2026 (latest two finished quarters on the test date) | | |
| ☐ | H5 | P&L account becomes a fund-level entry | Audit Fees mapped as Expense / "Audit Fees" | 1. Sync now 30/09/2026 2. Open Account Entries, filter the fund, 30/09/2026 | One "Audit Fees" 12,000.00, not cumulative, no folio, note mentions Xero | | |
| ☐ | H6 | Balance-sheet account is cumulative | Accrued Expenses mapped; balance 3,400.00 at 30/09/2026 | 1. Sync now 30/09/2026 | "Accrued Expenses" 3,400.00 marked cumulative | | |
| ☐ | H7 | Sign flip | Interest Income mapped with sign flip | 1. Sync now 30/09/2026 | "Interest" entry is -500.00 | | |
| ☐ | H8 | Correction updates the same entry | H5 done; no allocation run for Q3 | 1. In Xero change Audit Fees Q3 to 14,500.00 2. Sync now 30/09/2026 | Still exactly one Audit Fees entry for 30/09/2026, now 14,500.00 | | |
| ☐ | H9 | Sync now for an older period | Connected | 1. Sync now 2. Pick 31/03/2026 | "Sync queued" shown; only 31/03/2026 entries change | | |
| ☐ | H10 | Held change applied | Q2 Audit Fees entry 12,000.00 exists (synced before the Q2 run was created) | 1. Change Q2 Audit Fees in Xero to 14,500.00 2. Sync now 30/06/2026 3. Check the entry 4. On the review list click **Apply** | After sync the entry is still 12,000.00 and the review list shows "12,000.00 → 14,500.00"; after Apply the entry is 14,500.00 and the message reads "Applied. Re-run the allocation for 30/06/2026 to include it." | | |
| ☐ | H11 | Fund user connects a portco | Signed in as Ben; Acme not connected | 1. Acme Robotics → KPIs tab → Xero panel 2. **Connect Xero** 3. Allow, pick "Acme Robotics Ltd" | Panel: "Acme Robotics Ltd (GBP)", "Connected" | | |
| ☐ | H12 | Founder connects from a pending report | Acme disconnected; an August 2026 report shared with Acme's users | 1. Sign in as Chen 2. Open the pending August report 3. **Connect Xero instead of uploading** 4. Allow | Back on the report: "Xero connected. We'll fill your reports from now on."; as Ben the panel shows Connected | | |
| ☐ | H13 | Monthly KPI pull | Acme connected; test date early in a month | 1. Ask a developer to run the nightly job | The previous two months' Actual reports for Acme are filled | | |
| ☐ | H14 | KPI awaiting approval | Acme Xero shows Total Income 250,000.00 for August; no approved Revenue | 1. Run the nightly job 2. Open August report as Ben 3. Open the dashboard | Revenue 250,000.00 awaiting approval, source "Xero"; not on the dashboard | | |
| ☐ | H15 | Approve Xero KPIs | H14 done | 1. Approve the August values as usual | Revenue approved; appears on the dashboard | | |
| ☐ | H16 | No upload reminder once filled | August filled from Xero | 1. Ask a developer to run the reminder job | Acme's users get no August upload reminder | | |
| ☐ | H17 | Disconnect a fund | Fund connected, entries imported | 1. Xero tab → **Disconnect** 2. Confirm 3. Run nightly job | Tab shows "Not connected"; earlier entries unchanged; no new entries; in Xero (Settings → Connected apps) CapHive is gone | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | New Xero account appears | Connected | 1. In Xero add account 6200 Admin Fees 2. Sync now | 6200 listed Unmapped; one "items to review" notification | | |
| ☐ | E2 | Zero, unmapped, ignored not imported | Legal Fees unmapped, Bank ignored, Audit Fees mapped with 0.00 in the period | 1. Sync now for that period | No entries for any of the three | | |
| ☐ | E3 | Repeat sync changes nothing | H5 done | 1. Sync now 30/09/2026 twice | Entry count and amounts unchanged | | |
| ☐ | E4 | Removed in Xero removes the entry | Legal Fees Q3 entry exists; no Q3 run | 1. Delete the Legal Fees posting in Xero 2. Sync now 30/09/2026 | Legal Fees 30/09/2026 entry gone | | |
| ☐ | E5 | Uploaded entries untouched | Upload a fund-level "Audit Fees" 12,000.00 for 30/09/2026 via Account Entries import | 1. Sync now 30/09/2026 | Uploaded entry unchanged; the synced Audit Fees entry exists alongside | | |
| ☐ | E6 | New account in an allocated period | Legal Fees newly mapped; Xero 2,000.00 in Q2 | 1. Sync now 30/06/2026 | No new entry; review list shows "none → 2,000.00" | | |
| ☐ | E7 | Dismiss remembers the figure | Review item 12,000.00 → 14,500.00 | 1. **Dismiss** 2. Sync now 30/06/2026 3. Change Xero to 15,000.00 4. Sync now | After step 2 no item; after step 4 new item "12,000.00 → 15,000.00" | | |
| ☐ | E8 | No duplicate pending items | A pending item exists | 1. Sync now for the same period again | Still one item | | |
| ☐ | E9 | Reconnect to the same org | Status "Needs reconnecting" (see X5) | 1. **Reconnect** 2. Allow the same org | "Connected"; account mappings unchanged | | |
| ☐ | E10 | Brief outage is silent | Developer simulates one Xero failure | 1. Run the job | No notification; still "Connected" | | |
| ☐ | E11 | Unmatched label listed | Acme Xero shows "Total Cost of Sales" | 1. Run the nightly job 2. Open the Xero panel | No KPI for it; listed under "Labels with no KPI mapping" | | |
| ☐ | E12 | Missing report created | No August Actual report for Acme | 1. Run the nightly job | August report created and filled | | |
| ☐ | E13 | Same as approved creates nothing | Approved Revenue 250,000.00 | 1. Run the nightly job | No new awaiting value for Revenue | | |
| ☐ | E14 | Correction before approval | Revenue 250,000.00 awaiting approval | 1. Change Xero to 255,000.00 2. Run the nightly job | One Revenue awaiting approval, 255,000.00 | | |
| ☐ | E15 | Nothing matched keeps the reminder | Remove Acme's KPI mappings' reported names temporarily | 1. Run the nightly job 2. Run the reminder job | Report not submitted; reminder is sent | | |
| ☐ | E16 | Feature off | As Dan (Beta Capital, Xero feature off) | 1. Open Beta Fund | No Xero tab | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | Consent cancelled | Fund not connected | 1. Connect Xero 2. Click Cancel at Xero | Back on the tab: "Xero connection was cancelled." | | |
| ☐ | X2 | Currency mismatch | USD demo org | 1. Connect Xero, pick the USD org | Refused; message says "This Xero organisation reports in USD but Alpha Growth Fund I is in AUD. Connect the fund's own organisation." | | |
| ☐ | X3 | Org already used by another fund | Create "Alpha Fund II"; connect it to the fund org first | 1. Connect Alpha Growth Fund I to the same org | "This Xero organisation is already connected to Alpha Fund II." | | |
| ☐ | X4 | Reconnect to a different org | Fund connected to its org, status Needs reconnecting | 1. Reconnect, pick Acme's org | "Disconnect first. Reconnecting to a different organisation is not supported."; still linked to the original org | | |
| ☐ | X5 | Access withdrawn | Fund connected | 1. In Xero, Settings → Connected apps → disconnect CapHive 2. Run the nightly job | Status "Needs reconnecting"; Asha gets one "Xero needs reconnecting for Alpha Growth Fund I" email + in-app; **Reconnect** shown | | |
| ☐ | X6 | Long outage | Developer simulates failures for 24 h | 1. Run the job after the window | Status "Sync failing"; one notification | | |
| ☐ | X7 | Mapping missing entry type | An unmapped account | 1. Set status Mapped, leave type empty 2. Save | Not saved; entry type error shown | | |
| ☐ | X8 | Investor blocked | Signed in as Ivy | 1. Open the fund 2. Paste the Xero tab URL | No Xero tab; direct URL denied | | |
| ☐ | X9 | Other entity blocked | Signed in as Dan | 1. Paste Alpha's Xero tab URL | Denied | | |

---

## UI Journeys

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J1.1 | Fund → Xero tab | Click Connect Xero ① | Xero sign-in and consent | | |
| ☐ | J1.2 | Xero consent | Allow (pick org if several) | Tab: org name, currency, Connected ② | | |
| ☐ | J1.3 | Fund → Xero tab | Change Periods ③ to Monthly | Saved in place, no page reload | | |
| ☐ | J1.4 | Account mapping ④ | Map one account, ignore another | Rows move to Mapped / Ignored; Unmapped count drops | | |
| ☐ | J1.5 | Fund → Xero tab | Sync now ③, pick a period | "Sync queued", then entries appear under Account Entries | | |
| ☐ | J2.1 | Notification → Xero tab | Open the "items to review" notification link | Review list ① with the row ② | | |
| ☐ | J2.2 | Review row | Apply ③ | Row disappears; "Applied. Re-run the allocation for 30/06/2026 to include it." | | |
| ☐ | J2.3 | Review row | Dismiss ③ (on another item) | Row disappears | | |
| ☐ | J3.1 | Portco → KPIs → Xero panel | Send connect link ① | "Link sent to Acme Robotics users"; Chen receives the email | | |
| ☐ | J3.2 | Founder's pending report | Chen clicks ③ and allows | "Xero connected. We'll fill your reports from now on." | | |
| ☐ | J3.3 | Xero panel | After nightly job, open as Ben | Connected, last pull date ②, unmatched labels ④ | | |
| ☐ | J3.4 | August KPI report | Open as Ben | Values awaiting approval with source "Xero"; approve works | | |
| ☐ | J4.1 | Email / in-app | Receive "Xero needs reconnecting…" | Link opens the Xero tab | | |
| ☐ | J4.2 | Fund → Xero tab | Look at the status area | "Needs reconnecting", **Reconnect** shown instead of Sync now | | |
| ☐ | J4.3 | Fund → Xero tab | Reconnect to the same org | "Connected"; mappings intact; a sync queued | | |

---

## Role Sweep

| ID | Screen / action | Asha (fund admin) | Ben (fund user, KPI access) | Chen (portco user) | Ivy (investor) | Dan (other entity) |
|---|---|---|---|---|---|---|
| R1 | See fund Xero tab | ✓ | ✗ (unless can update fund) | ✗ | ✗ | ✗ |
| R2 | Connect / disconnect fund | ✓ | ✗ | ✗ | ✗ | ✗ |
| R3 | Map accounts, Sync now | ✓ | ✗ | ✗ | ✗ | ✗ |
| R4 | Apply / dismiss review items | ✓ | ✗ | ✗ | ✗ | ✗ |
| R5 | See portco Xero panel | ✓ (if KPI access) | ✓ | ✗ | ✗ | ✗ |
| R6 | Connect portco / send link | ✓ (if KPI access) | ✓ | ✗ | ✗ | ✗ |
| R7 | "Connect Xero instead of uploading" on pending report | — | — | ✓ | ✗ | ✗ |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Emails: needs reconnecting, sync failing, items to review, connect link | Right recipients; links open the right tab/report; any dates shown as e.g. `Sep 30, 2026` | | |
| ☐ | C2 | Dates on the Xero tab, review list and panel | Locale format (e.g. `30/09/2026` for en) | | |
| ☐ | C3 | Narrow / mobile width | Xero tab, mapping table and review list don't scroll the page sideways; buttons reachable | | |
| ☐ | C4 | Tenant isolation | Dan cannot open Alpha's Xero tab, mapping, review items or portco panel by direct URL | | |
| ☐ | C5 | Regression: KPI workbook upload and approval | Upload a workbook for another portco; values stage and approve as before | | |
| ☐ | C6 | Regression: fund page tabs and Account Entries list | Other tabs work; entries list, filters and export unchanged | | |
| ☐ | C7 | Regression: reminders for non-connected portcos | Still sent as before | | |
| ☐ | C8 | Empty states | Not-connected tab; empty review list ("No changes awaiting review"); no unmatched labels | | |
| ☐ | C9 | Allocation run after sync | Run the Q3 allocation: synced fund-level entries are allocated to folios like uploaded ones | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
