# A DR drill stack can contact real users — Manual QA Checklist

> **Audience:** The operator running the next staging drill. Every row is **(dev)**.
> **Companion document:** [Report](report.md)

**ID legend:** **B** = original bug · **H** = Happy · **E** = Edge · **X** = Error · **R** = Regression · **C** = Cross-cutting

## Contents

- [Test Setup](#test-setup) · [The Original Bug](#the-original-bug) · [Happy Path](#happy-path) · [Edge Cases](#edge-cases) · [Error Cases](#error-cases) · [Regression](#regression) · [Cross-cutting Checks](#cross-cutting-checks) · [Sign-off](#sign-off)

## Test Setup

| Item | Detail |
|---|---|
| Run | `TEARDOWN=false rake "aws:dr_drill[in, ap-south-2, staging.in]"`, then tear down by hand |
| Inbox | The staging test users' inboxes and the ops inbox; note the drill's start time |

## The Original Bug

| ☐ | ID | What to check | Steps | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | B1 **(dev)** | No user hears from the drill | Leave the drill stack up for 1 h (across a `:00` and a `:30`) | No email, WhatsApp, SMS or push from the drill copy reaches any user | | |

## Happy Path

| ☐ | ID | What to check | Steps | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | H1 **(dev)** | Suppression proven at the end | Read the verify scorecard | "Drill cannot contact users" ✅ with "N suppressed" | | |
| ☐ | H5 **(dev)** | No timed jobs | On a drill app server: `crontab -l`; in the drill's Rails console `Sidekiq::Cron::Job.all.size` | No whenever lines; 0 cron jobs | | |
| ☐ | H2–H4 | Automated suite | — | N/A by hand | | |

## Edge Cases

| ☐ | ID | What to check | Steps | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | E1 **(dev)** | Live staging still sends | After the drill, trigger one staging email | It arrives as usual | | |
| ☐ | E3 | Deploy and backups unaffected | Drill passes; restore and S3 work | ✅ | | |

## Error Cases

| ☐ | ID | What to check | Steps | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | X1, X2 | Automated suite | — | N/A by hand | | |

## Regression

| ☐ | ID | What still has to work | Steps | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | R1 **(dev)** | Whole drill | — | PASSED, all other checks unchanged | | |
| ☐ | R2 **(dev)** | Background search rebuild still runs on the drill | Read "Search index populated" | queued / running / finished (the chewy queue isn't a timed job) | | |

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Emails / alerts | None from a drill stack; normal elsewhere (E1) | | |
| ☐ | C2–C6 | Screens, dates, mobile, tenant, look | N/A: no screens changed | | |

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | staging.in → ap-south-2 | | | |
