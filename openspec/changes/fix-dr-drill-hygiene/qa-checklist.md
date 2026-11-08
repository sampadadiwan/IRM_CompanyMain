# DR drill hygiene — Manual QA Checklist

> **Audience:** The operator running the batch staging drill. Every row is **(dev)**.
> **Companion document:** [Report](report.md)

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
| Environment | staging.in → ap-south-2, the batch drill |
| Two terminals | Needed for B1 (a second drill started while the first runs) |
| Inbox | The address `ERROR_EMAIL` sends to; note the time the drill starts |

---

## The Original Bug

| ☐ | ID | What to check | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | B1 **(dev)** | A second drill is refused, not logged as failed | 1. Start the drill. 2. In a second terminal, start the same drill command | The second run stops at once: "a DR run is already in progress here (pid …)". **No** new row in `dr_drills.md`, no new run report | | |
| ☐ | B2 **(dev)** | Teardown sends no error flood | Run a drill with `TEARDOWN=true` to the end | No `CannotConnectError` mail during teardown. The log shows "stopping drill app services" before `git checkout` | | |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 **(dev)** | Free stack starts normally | No other run | Start the drill | "Pulumi lock: free" in the log, drill proceeds | | |
| ☐ | H3 **(dev)** | Any drill mail is tagged | During the drill | Check the inbox for mail from drill hosts | Subjects start `[Error][DR DRILL ap-south-2]` | | |
| ☐ | H2 | Guard logic | — | Automated suite | N/A by hand | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E2 **(dev)** | Stale lock explained | Optional: `kill -9` a drill during `pulumi up` | Start a new drill | Refused as **stale**, with the exact `pulumi cancel --stack staging-ap-south-2` command. Nothing is cancelled automatically | | |
| ☐ | E1, E3 | Automated suite | — | — | N/A by hand | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | Same as B1 | — | — | — | | |
| ☐ | X2, X3 | Guard refuses live/partial config | — | Automated suite | N/A by hand | | |

---

## Regression

| ☐ | ID | What still has to work | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | R1 **(dev)** | Deploy after boot | Drill log, phase 5 | "waiting for SSH on …" then the deploy starts; no ConnectionTimeout | | |
| ☐ | R2 **(dev)** | `main` untouched by the tag | After the drill: `git diff main -- .env.staging.in` on `main` | No `DR_DRILL_STACK` on `main` (only on the drill branch) | | |
| ☐ | R3 **(dev)** | Live staging mail unchanged | Trigger any test error on live staging, or read the next real one | Subject still `[Error] staging:(altconnects.com)` | | |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Dates on screens | N/A | | |
| ☐ | C2 | Dates in emails | Error mail bodies unchanged except the subject tag | | |
| ☐ | C3 | Narrow / mobile | N/A | | |
| ☐ | C4 | Tenant isolation | N/A: tooling | | |
| ☐ | C5 | Tools touched | Drill and real `setup_infra` still complete (batch drill) | | |
| ☐ | C6 | Looks like CapHive | N/A | | |
| ☐ | C7 | Speed | SSH wait adds seconds, not minutes, on a healthy boot | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | staging.in → ap-south-2 | | | |
