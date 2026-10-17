# Users form refuses an advisor on their own firm's LP record — Manual QA Checklist

> **Audience:** Testers running the fix by hand on a deployed build. No code knowledge needed.
> **Companion document:** [Report](report.md)

> **How to use:** work top to bottom. Tick ☐ → ☑ and write Pass or Fail for each row. Row IDs
> match the report's Verification table.

**ID legend:** **B** = the original bug · **H** = Happy path · **E** = Edge case · **X** = Error case ·
**R** = Regression · **C** = Cross-cutting · **(dev)** = needs a developer

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
| Accounts | **GP admin** of fund company *Artha* with fund *F*. **Advisor A**: holds the Investor Advisor role, and their own firm *Home* is an LP of *F*. **Advisor B**: from a different advisory firm. |
| Seed data | **(dev)** *Home* added as a stakeholder of Artha with access to *F*; a second stakeholder *Client* with access to *F*; a fund-company advisor whose company *Feeder* is also an LP |
| Developer-assisted rows | E3, E4 |

---

## The Original Bug

| ☐ | ID | What to check | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | B1 | An advisor can be added to their own firm's LP record | 1. GP opens stakeholder *Home* → **Users** → **New**. 2. Enter A's email, name, tick Approved. 3. **Save** | "Investor access was successfully created."; A is listed on the Users tab | | |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Row saved from the form | — | as B1 | saved; Users tab shows A with type **Advisor** | | |
| ☐ | H2 | A gets *Home*'s call notices | H1 done | GP sends a capital call reminder on *F* | A receives *Home*'s reminder | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | A is switched into a client at the time | A switched into a client persona | as B1 | saved | | |
| ☐ | E2 | Fund-company home | Feeder's advisor; *Feeder* is an LP | add them on *Feeder*'s Users tab | saved | | |
| ☐ | E3 | Legacy advisor without a recorded home | **(dev)** advisor with no advisor home | add them on their entity's LP record | saved | | |
| ☐ | E4 | Deleting the row removes their personal fund access | **(dev)** A has personal access to *F* in *Home* | GP deletes A from *Home*'s Users tab | A can no longer open *F* | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message shown) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | Client's stakeholder | — | add A on *Client*'s Users tab | refused: "belongs to a user with the Investor Advisor role and cannot be added as investor access from this page" | | |
| ☐ | X2 | Advisor from another firm | — | add B on *Home*'s Users tab | same refusal | | |
| ☐ | X3 | Plain user of another company | — | add a user of another company on *Home* | refused: "cannot be given access. Belongs to …" | | |

---

## Regression

| ☐ | ID | What still has to work | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | R1 | Add Investor Advisor from a commitment | Commitment → Actions → Add Investor Advisor | advisor created with fund access, as before | | |
| ☐ | R2 | CSV import of contacts | Import a contacts sheet including an advisor | imported, as before | | |
| ☐ | R3 | Adding ordinary contacts | Users → New for a plain user of *Home* | saved, as before | | |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Dates on screens touched | N/A — no dates changed | | |
| ☐ | C2 | Dates in the "access granted" email | `Aug 19, 2026` style | | |
| ☐ | C3 | Narrow / mobile width | N/A — no layout changed | | |
| ☐ | C4 | Tenant isolation | A still can't be attached to another company's stakeholder from the form (X1, X2) | | |
| ☐ | C5 | Users tab | lists, labels and edit work as before | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
