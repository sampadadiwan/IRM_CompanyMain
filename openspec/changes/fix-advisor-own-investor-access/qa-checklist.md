# Investor advisor loses access to their own investor record — Manual QA Checklist

> **Audience:** Testers running the fix by hand on a deployed build. No code knowledge needed.
> **Companion document:** [Report](report.md)

> **How to use:** work top to bottom. Tick ☐ → ☑ and write Pass or Fail for each row. For a Fail,
> put the defect link in Notes. Row IDs match the report's Verification table (H/E/X), so a
> failure maps straight to the automated scenario that should have caught it.

**ID legend:** **B** = the original bug, reproduced · **H** = Happy path · **E** = Edge case ·
**X** = Error case · **R** = Regression (from Blast Radius) · **C** = Cross-cutting check ·
**(dev)** = needs a developer or a config change

---

## Contents

- [Test Setup](#test-setup)
- [The Original Bug](#the-original-bug)
- [Happy Path](#happy-path)
- [Edge Cases](#edge-cases)
- [Error Cases](#error-cases)
- [Regression](#regression)
- [Cross-cutting Checks](#cross-cutting-checks)
- [Sign-off](#sign-off)

---

## Test Setup

| Item | Detail |
|---|---|
| Environment | Staging |
| Accounts | **Fund admin** at a fund company with fund *F*. **Advisor A**: a user whose own company is an *Investor* company, set up as an investor advisor for a client. **Plain contact P**: a second contact on A's own investor. **Advisor A2**: a user in an *Investor Advisor* firm. |
| Seed data | **(dev)** On *F*: investor **Own** (A's own company) with contacts A and P, approved and email enabled, plus fund access granted to Own. Investor **Client** with fund access and A set up as its advisor. A second client **Client2** with no access to *F*. A fund *G* where only Client has access. A capital call on *F* with a pending remittance for Own and for Client, approved. |
| Background work | Notices and reminders send from the capital call's **Remittances** tab (**Reminder** button). Emails arrive within a minute. |
| Developer-assisted rows | Seed data, X5 (reads the application log) |

---

## The Original Bug

| ☐ | ID | What to check | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | B1 | An advisor at home gets the reminder for their own investment | 1. A signs in and stays in their own company (no switch). 2. Fund admin opens the capital call → Remittances → **Reminder**. 3. Check A's bell and inbox. | A gets the in-app notification and the reminder email, as P does | | |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Reminder reaches A and P | A at home | Fund admin presses **Reminder** | A and P are both notified | | |
| ☐ | H2 | Call notice reaches A and P | A at home; a new call on *F* | Fund admin approves the call and sends notices | A and P are both notified | | |
| ☐ | H3 | A can open their own fund and remittance | A at home | A opens *F*, then Own's remittance | Both pages open | | |
| ☐ | H4 | A still acts for the client when switched | A switched into Client | Fund admin sends the reminder; A opens Client's remittance | A is notified and the page opens | | |
| ☐ | H5 | **Fund Advisor** at home gets their own reminder | **(dev)** A's only advisor grant is on the fund company (Company menu → Advisors, roles employee) | Fund admin presses **Reminder**; A opens *F* | A and P notified; *F* opens | | |
| ☐ | H6 | Switched **Fund Advisor** works as staff | A has the fund-company grant and personal access to *F* | A switches into the fund company; opens *F* and Client's remittance | Both open | | |
| ☐ | H7 | Family-office advisor with home roles starting with investor | **(dev)** A's home is an Investor Advisor firm with home roles `investor,investor_advisor` | Fund admin presses **Reminder** | A notified | | |
| ☐ | H8 | Access Denied offers the switch | A at home | A opens Client's remittance from its notice | Red alert: "Access Denied: You can view this as an advisor for Client. Switch your persona to Client to view it." with a **Switch to Client** button; pressing it opens the remittance and shows "You have now been switched to the advisor role for Client." | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | Switched into a client with no access to *F* | A switched into Client2 | Fund admin presses **Reminder** | A still gets Own's reminder | | |
| ☐ | E2 | Switched into a client with access to *F* | A switched into Client | Fund admin presses **Reminder** | A gets Own's reminder | | |
| ☐ | E3 | Client's records hidden at home | A at home | A pastes the URL of Client's remittance | Access denied (A still receives Client's notices, by design) | | |
| ☐ | E4 | Client-only fund hidden at home | A at home | A pastes the URL of fund *G* | Access denied; A is not on *G*'s notices | | |
| ☐ | E5 | Topic tags still respected | A's own contact row tagged only `KYC` | Fund admin presses **Reminder** | A is not notified, P is | | |
| ☐ | E6 | No duplicate when A also has a personal grant | **(dev)** grant A personal access to *F* in Own | Fund admin presses **Reminder** | A gets exactly one notification | | |
| ☐ | E7 | Advisory-firm user gains nothing at home | A2 at home in the advisory firm | A2 pastes *F*'s URL | Access denied | | |
| ☐ | E8 | Recipient preview matches who is sent to | A at home | Fund admin opens the call's notification preview / recipient counts | A is counted as a recipient | | |
| ☐ | E9 | Switching back gives the same recipients | A switched into Client | A presses **Revert**; fund admin presses **Reminder** both before and after | Same recipients both times | | |
| ☐ | E10 | Switched **Fund Advisor** still gets their own reminder | A switched into the fund company | Fund admin presses **Reminder** | A and P notified | | |
| ☐ | E11 | **Fund Advisor** staff rights don't come home | A has the fund-company grant; A at home | A pastes Client's remittance URL | Access denied | | |
| ☐ | E12 | Advisor whose grants were all deleted | **(dev)** delete all of A's advisor grants | Fund admin presses **Reminder**; A opens *F* | A notified; *F* opens | | |
| ☐ | E13 | Fund Advisor opt-out respected | **(dev)** A has a fund-company grant; A's own contact row has email off | Press **Reminder** | A sees the bell notification but gets **no email**; P gets the email | | |
| ☐ | E14 | Deal notice at home | A deal shared with Own | Send the deal notice | A and P notified | | |
| ☐ | E15 | Own KYC without commitment | A KYC for Own with no commitment yet | A opens it; fund admin sends the KYC form | Opens; A gets the KYC form | | |
| ☐ | E16 | Advisor without the advisor role at home | **(dev)** A's stored home roles set to `investor`, A reverted | A pastes *G*'s URL; opens *F* | *G* denied; *F* opens | | |
| ☐ | E17 | Wrong client | A switched into Client2 | A opens Client's remittance | Alert names Client2 (where A is) and Client (where to switch) | | |
| ☐ | E18 | Fund Advisor switch offered | A has the fund-company grant; Rao's remittance | A opens it | Alert names the fund company with a **Switch to …** button | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message shown, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | No fund access for Own | Remove Own's access on *F* | Press **Reminder**; A opens *F* | Neither A nor P notified; A denied | | |
| ☐ | X2 | A's contact row unapproved | Unapprove A on Own | Press **Reminder** | A not notified | | |
| ☐ | X3 | A's contact row deleted | Delete A's contact row on Own | Press **Reminder** | A not notified | | |
| ☐ | X4 | Own records not reachable through the client session | A switched into Client2 | A pastes Own's remittance URL | Access denied (with the "switch back" hint) | | |
| ☐ | X5 | Dropped contact is logged | **(dev)** as X1 | Press **Reminder**; developer reads the log | A log line names A's contact row and fund *F* | | |
| ☐ | X6 | Legacy advisor switched in | **(dev)** advisor with no recorded home, switched into a client whose investor has fund access | A opens *F* | Access denied | | |
| ☐ | X7 | Shared fund, no personal grant | A is a contact of Rao (on *F*) without personal access | Press **Reminder** | A gets Own's reminder, **not** Rao's | | |
| ☐ | X8 | Switched into Client, Rao's notice | as X7, A switched into Client | Press **Reminder** | A gets Client's, not Rao's | | |
| ☐ | X9 | No switch helps | A at home | A pastes *G*'s URL | Plain "Access Denied", no button | | |
| ☐ | X10 | Off-site return path | **(dev)** post the switch with `return_to=//evil.example.com` | — | Stays on CapHive | | |
| ☐ | X11 | Name with markup | **(dev)** rename Client to `Client <b>Bold</b> & Co` | A opens Client's remittance | Name shown literally, not bold | | |

---

## Regression

| ☐ | ID | What still has to work | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | R1 | Ordinary investors (no advisor role) | Plain investor opens their fund, commitment and remittance; receives a reminder | Unchanged | | |
| ☐ | R2 | Advisor switched into a client | A switched into Client: fund, commitment, remittance, documents | Unchanged | | |
| ☐ | R3 | Advisor document / KYC notifications | Send a KYC document to Own while A is switched away | A receives it (as before) | | |
| ☐ | R4 | "Switch back to view" hint | A, switched away, opens a link from an Own notification | Hint shown as before | | |
| ☐ | R5 | Fund lists | A at home and switched: Funds list | Same funds as before the fix, plus none from clients at home | | |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Dates on any screen the fix touched | N/A: no screen rendering changed | | |
| ☐ | C2 | Dates in the reminder email A now receives | `Aug 19, 2026` style, whatever the locale | | |
| ☐ | C3 | Narrow / mobile width | N/A: no layout changed | | |
| ☐ | C4 | Tenant isolation | A at home cannot reach Client's or *G*'s records by direct URL (E3, E4) | | |
| ☐ | C5 | Screens the fix touched | Fund, remittance and notification preview pages behave as before for every other user | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
