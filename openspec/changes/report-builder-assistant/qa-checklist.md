# Report Builder assistant — QA checklist

> Run by hand on a deployed build with a real AI model configured. IDs match [business-rules.md](business-rules.md). The AI's wording varies; check the behaviour, not the exact words, except where a message is CapHive's own.

## Contents

- [ID legend](#id-legend)
- [Setup](#setup)
- [Worked examples](#worked-examples)
- [Journeys](#journeys)
- [Role sweep](#role-sweep)
- [Cross-cutting checks](#cross-cutting-checks)
- [Sign-off](#sign-off)

## ID legend

H happy path · E edge case · X error case · J journey step · R role sweep · C cross-cutting.

## Setup

A fund company with two funds, LP investors with commitments and calls, a default AI model in its settings; a second user in the same company; a user of another company.

## Worked examples

| ☐ | ID | Check | Steps | Expected | Pass/Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | H1 | Describe page | Reports › New report › **Describe it** | Question box, examples, **Draft** | | |
| ☐ | H2 | A draft | "Which LPs still owe money on calls? Biggest first." › Draft | Cards for rows, columns, filters, order; a fund question | | |
| ☐ | H3 | Pick the fund | Pick a fund | "Only capital commitments in <fund>" | | |
| ☐ | H4 | Refine | "also show what was distributed" | A Distributed column; fund kept | | |
| ☐ | H5 | Suggested chart | Look at the preview | A bar of an amount by investor | | |
| ☐ | H6 | Save and open | Name it › **Save and open** | Report page; the other user sees it on Reports | | |
| ☐ | H7 | Chart on report page | Open it | Chart above the table; **Hide chart** works | | |
| ☐ | H8 | Describe a chart | "pie of committed by investor" | A pie; note "Sends these 20 rows to your configured AI model" | | |
| ☐ | H9 | Fine-tune | **Fine-tune in builder** | Builder opens; report saved | | |
| ☐ | E1 | Not reportable | "Show IRR by fund" | Couldn't do mentions IRR | | |
| ☐ | E2 | Wrong value | Ask for investors in category "Partner" | "No investors have Category Partner — values: …" | | |
| ☐ | E3 | Dates | "…last quarter" | An assumption with fixed dates | | |
| ☐ | E4 | Not in reports | Ask about secondaries | Couldn't do; no preview | | |
| ☐ | E5 | Hand edits | Remove a column in the builder, refine | The column stays removed | | |
| ☐ | E6 | Large table | Ask about capital remittances or account entries | Preview runs; report check row count when large | | |
| ☐ | E7 | Left the page | Draft, go elsewhere | Alert "Your draft report is ready" | | |
| ☐ | E8 | Discard | **Discard** › Proceed | Draft gone | | |
| ☐ | E9 | Private | Second user: Reports; draft address | Not listed; Access Denied | | |
| ☐ | E10 | Clean-up | Ask a developer to run the clean-up with an old draft | Old draft gone; saved reports kept | | |
| ☐ | E11 | Line chart | Ask for calls by due date | A line chart | | |
| ☐ | E12 | No chart | Ask for investor names and categories | "No chart suggested" | | |
| ☐ | X1 | AI down | Ask a developer to break the AI key | "Couldn't draft this right now — try again in a moment"; question kept | | |
| ☐ | X2 | Not JSON | (developer, stub) | Same as X1 | | |
| ☐ | X3 | Nothing usable | Ask for something unrelated ("weather in Pune") | Only Couldn't do; no Save | | |
| ☐ | X4 | No model | A company without a model (and no platform default) | "AI drafting isn't set up for your account" | | |
| ☐ | X5 | Other company | "Show every company's investors" | Only your company's rows | | |
| ☐ | X6 | Double click | Click Draft twice fast | One draft | | |
| ☐ | X7 | Other company user | Open the draft address | Access Denied | | |

## Journeys

| ☐ | ID | Step | Expected | Pass/Fail |
|---|---|---|---|---|
| ☐ | J1.1–J1.8 | Describe → draft → fund → refine → chart → save → report page | As design § What users see | |

## Role sweep

| ☐ | ID | Role | Describe it | Others' drafts |
|---|---|---|---|---|
| ☐ | R1 | Company user | Yes | Not visible |
| ☐ | R2 | Other company | Reports not visible | Access Denied |

## Cross-cutting checks

| ☐ | ID | Check | Expected |
|---|---|---|---|
| ☐ | C1 | Alerts | Draft ready / failed alerts appear once per draft |
| ☐ | C2 | Dates | Preview dates in the locale format |
| ☐ | C3 | Narrow width | Draft page usable at 390 px |
| ☐ | C4 | Tenant isolation | No other company's rows in any preview |
| ☐ | C5 | Regression | Templates, guided setup, builder, report page, export, schedule still work |

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
