# Search is empty after a DR — Manual QA Checklist

> **Audience:** The operator running the batch staging drill. Every row is **(dev)**: it needs AWS/SSH and a terminal.
> **Companion document:** [Report](report.md)

> **How to use:** tick ☐ → ☑ and write Pass or Fail. IDs match the report's Verification table.

**ID legend:** **B** = original bug · **H** = Happy · **E** = Edge · **X** = Error · **R** = Regression · **C** = Cross-cutting · **(dev)** = operator with AWS/SSH access

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
| Environment | staging.in drilled into ap-south-2 (the batch drill, shared with the other DR changes) |
| Run | `TEARDOWN=false rake "aws:dr_drill[in, ap-south-2, staging.in]"` |
| Drill app | `https://<ALB DNS from the run log>` with a `Host: dev.altconnects.com` header, or a browser `/etc/hosts` entry pointing `dev.altconnects.com` at the ALB |
| Known record | Pick a folder name and a document name that exist on staging before the drill |

---

## The Original Bug

| ☐ | ID | What to check | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | B1 **(dev)** | Search works after a DR | 1. Run the drill. 2. Log in on the drill app. 3. Search the known folder name, then the known document name | Both are found | | |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 **(dev)** | 29 indexes rebuilt, not `AccountEntryIndex` | Drill done | Read the "Rebuild the search index" phase in the run log | A table of 29 indexes, each "ok" with ES = MySQL counts. `AccountEntryIndex` listed as skipped with its reason | | |
| ☐ | H2 **(dev)** | Reindex is its own timed phase | Same | Read the run report's timeline | A "Rebuild the search index" row with its duration (note it: this is the measurement) | | |
| ☐ | H3 **(dev)** | Verify proves the indexes are full | Same | Read the verify scorecard | "Search index populated" ✅ on each app server | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E4 **(dev)** | FAQ index holds only published entries | Same | In the run log's table, find `FaqEntryIndex` | MySQL count is the *published* count, equal to ES | | |
| ☐ | E1, E2, E3, E5 | Covered by the automated suite only | — | — | N/A by hand | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X3 **(dev)** | Verify fails on an empty index | Drill boxes up | 1. On a drill app server: `bin/rails runner 'FolderIndex.delete'` (drill box only!). 2. `DR_DRILL=true LB=true bundle exec cap staging_in recovery:verify` (drill branch). 3. `bundle exec cap staging_in recovery:reindex_search` | Step 2: ❌ "search index empty" for FolderIndex. Step 3 rebuilds it | | |
| ☐ | X1, X2, X4, X5 | Covered by the automated suite only | — | — | N/A by hand | | |

---

## Regression

| ☐ | ID | What still has to work | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | R1 **(dev)** | The whole drill | B1 run | PASSED. Rebuild time = the old ~12 min plus the reindex phase | | |
| ☐ | R2 **(dev)** | The printed command after a promotion is real | Read the follow-up text in `lib/tasks/dr_fix_db.rake` | It says `bundle exec cap <stage> recovery:reindex_search`, and running it on the drill stack works | | |
| ☐ | R3 **(dev)** | Load balancer health unaffected | During the drill, read the ALB target health | Both targets healthy; `elastic_check` still answers quickly | | |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Dates on screens | N/A: no screens touched | | |
| ☐ | C2 | Dates in emails | N/A: no emails touched | | |
| ☐ | C3 | Narrow / mobile width | N/A | | |
| ☐ | C4 | Tenant isolation | Search on the drill app still shows only the logged-in entity's records (ES `entity_id` filters unchanged) | | |
| ☐ | C5 | Screens the fix touched | Search screens behave as before | | |
| ☐ | C6 | Looks like CapHive | N/A: no UI changed | | |
| ☐ | C7 | Speed | Reindex phase time recorded (H2); search on the drill app answers as fast as on staging | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | staging.in → ap-south-2 | | | |
