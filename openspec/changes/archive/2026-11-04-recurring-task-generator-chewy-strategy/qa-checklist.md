# RecurringTaskGeneratorJob Chewy strategy — Manual QA Checklist

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
| Environment | Staging or production, after the fix is deployed and the background workers are restarted **(dev)** |
| Accounts | One entity user who can see the Tasks list |
| Seed data | An entity with at least one recurring task rule (for example a weekly or quarterly compliance task) |
| Background work | Ask a developer to run the recurring task job by hand **(dev)** |
| Developer-assisted rows | B1, H1, E1, X1 (run the job, check the error inbox); R1 (console reindex) |

---

## The Original Bug

| ☐ | ID | What to check | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | B1 **(dev)** | The job no longer fails with the "Index update strategy is undefined" error | 1. Ask a developer to run the recurring task job. 2. Watch the support error inbox for ~5 minutes. | The job finishes. No new "Chewy::UndefinedUpdateStrategy" email arrives. | | |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 **(dev)** | New recurring tasks show up in the Tasks list and in search | A recurring rule with occurrences not yet created | 1. A developer runs the job. 2. Open the Tasks list. 3. Search for the recurring task's title. | The new tasks are listed with the right due dates and appear in search results. | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 **(dev)** | Running the job again after a partial run does not duplicate tasks | Some tasks for the rule already exist | 1. Note the number of tasks for the rule. 2. A developer runs the job again. 3. Count again. | The count only grows by the missing occurrences. No duplicates. | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message shown, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 **(dev)** | The job works when started from the background workers, not from a screen | The job is started by the scheduler or a developer, not by a user click | 1. Let the scheduled run happen, or ask a developer to enqueue it. | The job completes. No error email is sent. | | |

---

## Regression

| ☐ | ID | What still has to work | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | R1 **(dev)** | Tasks created during the failed runs on 2026-10-01 are searchable | 1. A developer reindexes those tasks from the console. 2. Search for one of them in the Tasks list. | The task appears in search. | | |
| ☐ | R2 | Side-letter obligation tasks still appear | 1. Open a side letter with obligations. 2. Open its tasks. | Obligation tasks are listed as before. | | |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Dates on the Tasks list | Locale format (e.g. `19/08/2026` for en) | | |
| ☐ | C2 | Dates in any email | N/A: no email is changed by this fix | | |
| ☐ | C3 | Narrow / mobile width | N/A: no screen is changed by this fix | | |
| ☐ | C4 | Tenant isolation | A user in a different entity cannot see these tasks, even with a direct URL | | |
| ☐ | C5 | Tasks list | Still does everything it did before | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | <!-- Pass / Pass with defects / Fail --> | |
