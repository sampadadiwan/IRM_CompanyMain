# DR Drill Report Redesign — Manual QA Checklist

> **Audience:** Whoever runs the batch staging drill and reads its report. No code knowledge needed.
> **Companion document:** [Design](design.md)

**ID legend:** **H** = Happy · **E** = Edge · **X** = Error · **J** = Journey step · **R** = Regression · **C** = Cross-cutting

---

## Contents

- [Test Setup](#test-setup)
- [Journey](#journey)
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
| Report | `docs/operations/dr/runs/<run>.html` and `.md` from the batch staging drill |
| Reference | The approved mock `tmp/dr_report_mock/drill_report.html` |
| Dark mode | Set the computer to dark mode for C3 |
| Role sweep | N/A: a file, not an app screen. Anyone with the repository can open it |

---

## Journey

| ☐ | ID | What to check | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J1.1 | Answer first | Open the `.html` | Title, Passed/Failed badge, 4 tiles at the top | | |
| ☐ | J1.2 | Plain words | Read "In plain words" | 3–4 non-technical sentences; says "drill" and "live site was not touched" | | |
| ☐ | J1.3 | Needs attention | Read the section | Each item has "What it means" and "What to do"; or "Nothing needs attention" | | |
| ☐ | J1.4 | Steps | Open "What this does" on any step | Plain explanation, including what to check if it fails | | |
| ☐ | J1.5 | Checks | Open "What it proves" on any check | Plain explanation | | |

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Tiles add up | Drill report | Count ✅ cells in the checks table | Equals the tile's first number; second = rows × servers | | |
| ☐ | H2 | Checks shown once | Same | Look at the checks table | One row per check, one column per server, under App servers / Requests / Data / Database servers / Backups | | |
| ☐ | H3 | 9 steps | Same | Look at the steps | 9 rows incl. "Rebuild the search index"; bars proportional to time | | |
| ☐ | H4 | Light and offline | Disconnect the network | Open the `.html` | Fully styled, light, icons visible | | |
| ☐ | H5 | Markdown matches | Open the `.md` on GitHub | Compare headings | Same sections, same order as the HTML | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E3 | Variable names | Same | Find the primary MySQL row | "Primary MySQL (10.0.x.x)" with that run's IP | | |
| ☐ | E1, E2, E4, E5, E6 | Automated suite only | — | — | N/A by hand | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | A failed run's report | Any failed drill report (or ask a developer to render one from a failed transcript) | Open it | "Failed" badge; headline "Recovery stopped at step N · …"; first attention item is that step; checks say "not reached" | | |
| ☐ | X2, X3, X4 | Automated suite only | — | — | N/A by hand | | |

---

## Regression

| ☐ | ID | What still has to work | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | R1 | Drill log row | After the drill | `dr_drills.md` has its row as before | | |
| ☐ | R2 | Evidence present | Read "Proof you can check yourself" | Pulumi update, instance ids, commit, bucket, each with a command | | |
| ☐ | R3 | Transcript link | Glossary / evidence | Names `docs/operations/dr/runs/<run>.log` | | |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Emails / alerts | N/A: the report sends nothing | | |
| ☐ | C2 | Dates | Shown as e.g. "8 Nov 2026, 05:09 UTC"; no ISO strings in the headline | | |
| ☐ | C3 | Dark-mode computer | Report still light | | |
| ☐ | C4 | Narrow / phone width | Tiles wrap 2×2; no sideways scroll | | |
| ☐ | C5 | Tenant isolation | N/A: no customer data in the report | | |
| ☐ | C6 | Side by side with the mock | Same sections, order, colours, icons | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | staging.in → ap-south-2 | | | |
