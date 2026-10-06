# Skip Redundant Cleanup in Allocation Data Load — Manual QA Checklist

> **Audience:** Testers running the feature by hand on a deployed build. No code knowledge needed.
> **Companion documents:** [Proposal](proposal.md) · [Design](design.md)

> **How to use:** work top to bottom. Tick ☐ → ☑ and write Pass or Fail for each row. For a Fail,
> put the defect link in Notes. Row IDs match the design's worked examples (H/E/X), so a failure maps
> straight to the automated test that should have caught it.

**ID legend:** **H** = Happy path · **E** = Edge case · **X** = Error case · **J** = UI journey
step · **R** = Role sweep · **C** = Cross-cutting check

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
| Environment | Staging, or production only with a developer watching the logs |
| Accounts | A fund admin who can run allocations for a fund |
| Second entity | Not needed (no data or screen changes) |
| Seed data | A fund with capital commitments and account entries. For the real check, a **large** fund (hundreds of thousands of account entries, e.g. over 1 million) |
| Background work | Allocation runs as a background job. Start it from the fund's allocation screen. A developer should be available to look at the job service log and its service status |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | A normal allocation moves from data loading to the formulas | Seed fund above | 1. Start an allocation for a period. 2. Watch the progress messages | "Loading data for fund …", then "Loaded N account entries and M commitments for fund …", then formula progress and "Done running N formulas …" | | |
| ☐ | H2 | Allocation results are the same as before | A period already allocated with the previous build, if available | 1. Run the allocation again. 2. Compare the generated entries (View Account Entries, View Expenses, View Portfolio Allocation links in the final message) | Same entries and totals as before | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | Re-running the allocation into the same run (the run's "Re-run" action) | Fund allocated once already | 1. Note the fund's account entry count and total. 2. Re-run the same allocation run. 3. Compare | Same entry count and total, status Success. No entries are duplicated | | |
| ☐ | E3 | Re-run after a formula was disabled | As E1 | 1. Note the count and total. 2. Disable one formula of the fund (try the last, then the first). 3. Re-run the same run. 4. Compare | Same entry count and total as before the re-run, status Success. Duplicated entries or a changed total is a **fail** | | |
| ☐ | E2 | A fund with no capital commitments | Fund with zero commitments | 1. Start an allocation | Warning "No capital commitments were loaded for fund …" shown, as before | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | Data load failure is reported as before | Ask a developer to make the load fail (e.g. in staging) | 1. Start an allocation | "Failed to load data for fund … (exit_code=…) — see the allocation run status for details" | | |

---

## UI Journeys

N/A — no screen changes.

---

## Role Sweep

N/A — no new or changed screen or action, and no permission changes.

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Emails / alerts sent by this feature | N/A, none changed | | |
| ☐ | C2 | Dates on changed screens | N/A, none changed | | |
| ☐ | C3 | Narrow / mobile width | N/A, no screen changes | | |
| ☐ | C4 | Tenant isolation | N/A, no data access changes | | |
| ☐ | C5 | Regression on the allocation screens | The allocation screen, run status and final message links behave as before | | |
| ☐ | C6 | **The reason for this change:** the job service survives a large-fund allocation | During and after the load, a developer confirms the job service was **not** restarted (no "Failed with result 'watchdog'" in the service log; the service's start time is unchanged), and the log shows a "loaded N account_entries …" line for the run | | |
| ☐ | C8 | The health-monitor limit is now 10 minutes | A developer runs `systemctl show sidekiq_IRM_production -p WatchdogUSec` on the server and sees `10min` | | |
| ☐ | C7 | Other jobs unaffected | Reports, imports or notifications queued during the allocation still finish | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
