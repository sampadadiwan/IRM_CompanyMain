# Report Builder delivery — Business rules and worked examples

> **Companion to:** [Design](design.md) · [Proposal](proposal.md) · [Spec](specs/reports/report-builder-delivery/spec.md)
> Each row is exactly one Cucumber scenario, tagged `# <ID> — <Happy path|Edge case|Error case>: …`. Feature paths are under `features/core/report_builder/`.

**ID legend:** **H** = Happy path · **E** = Edge case · **X** = Error (exception) case.

## Contents

- [Shared setup](#shared-setup)
- [Happy path](#happy-path)
- [Edge cases](#edge-cases)
- [Error cases](#error-cases)
- [Rules in one place](#rules-in-one-place)

## Shared setup

The Phase 1 "Acme" fixture (`features/step_definitions/report_builder_trust_steps.rb`), plus extras named per row.

| Record | Name | Key data |
|---|---|---|
| Entity, users | Acme Capital; Meera (`meera@acme.test`); Ravi (`ravi@acme.test`, Acme user, added where named); Omar (Beta Partners) | As Phase 1 |
| Funds | Growth Fund II (INR), Global Fund (USD) | As Phase 1 |
| Investors | Aditi Rao (LP, Mumbai), Kiran Mehta (LP, Pune), Zeta Holdings (Co-Investor), Nova LP (LP) | City set where a row names it |
| Report "LPs" | Investor; columns Investor, Category, capital commitments' Committed (sum) and Called (sum); Category is LP; capital commitments filtered to GF2 | Phase 1 report plus the columns and Category filter named per row |
| Folder | Acme's top folder | Exports are saved there (unchanged) |

## Happy path

| # | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| H1 | Export from the report page | Meera on the report page of "LPs" | Clicks **Export XLSX** | Button reads *Preparing…* and is disabled; then **Download** (opens the new document) and **Export again**; Recent exports' first row is "LPs" by Meera | Export shows its progress | delivery_export |
| H2 | Export from the builder | Meera in the builder for "LPs" | Clicks **Export XLSX** in the header | Same states as H1 in the header | Export shows its progress | delivery_export |
| H3 | Recent exports | "LPs" has 7 exports, made one minute apart | Open the report page | 5 rows, newest first, each "LPs · Meera · <dd Mon yyyy HH:MM>" with **Download** | Recent exports | delivery_export |
| H4 | Save a schedule inside Acme | Delivery tab; switch on | Weekly, India Standard Time, `meera@acme.test, ravi@acme.test` › **Save schedule** | No popup; green "Schedule saved — weekly on Monday at 09:00 IST to 2 people"; stored recipients `meera@acme.test`, `ravi@acme.test`, time zone Asia/Kolkata | A checked schedule | delivery_schedule |
| H5 | Outsider warning, Proceed | As H4 | Recipients `meera@acme.test, lp@gmail.com` › **Save schedule** | Immediate Actions popup: "Emails 1 person outside Acme Capital" with `lp@gmail.com`; **Proceed** saves both | Recipients outside the company | delivery_schedule |
| H6 | Send test to me | Delivery tab; schedule recipients `ravi@acme.test` | **Send test to me** | Green "A test is on its way to meera@acme.test"; exactly one email, to Meera only, subject "Scheduled Report: LPs", with an `.xlsx` attachment | Send test to me | delivery_schedule |
| H7 | Last sent and next | Weekly IST schedule; last sent 2026-11-02 03:30 UTC; next 2026-11-09 03:30 UTC | Open the Delivery tab | "Last sent 02 Nov 2026 09:00 IST · Next 09 Nov 2026 09:00 IST" | Last sent and next | delivery_schedule |
| H8 | A test isn't a scheduled send | As H7 | **Send test to me** | "Last sent" still reads 02 Nov 2026 09:00 IST | Last sent and next | delivery_schedule |
| H9 | Saved filters as chips | Report "LPs" (Category is LP; commitments in GF2) | Open the report page | "This report shows only:" chips *Category is LP* and *Only capital commitments in Growth Fund II*, and a "Change in builder" link | The report's filters in words | delivery_reading |
| H10 | Narrow down | As H9; Aditi in Mumbai, Kiran in Pune | **Narrow down** › City › is › Mumbai › **Apply** | Rows: Aditi Rao only; chip *City is Mumbai*; the report's saved filters unchanged | Narrow down | delivery_reading |
| H11 | Headline totals | "LPs" with Committed and Called totals | Open the report page | Two cards, "Committed" 7,50,00,000.00 and "Called" 3,00,00,000.00, each the same text as the totals row | Headline totals | delivery_reading |
| H12 | Save as View is gone | Builder for "LPs" | Look for View settings; send `PATCH /report_builder/:id/view_settings` | No View or Sharing controls; the request is refused as an unknown page and the report is unchanged | Save as View removed | delivery_reading |

## Edge cases

| # | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| E1 | No exports yet | "LPs" never exported | Open the report page | Recent exports: "No exports yet — Export XLSX makes one." | Recent exports | delivery_export |
| E2 | Only this report's exports | Report "Funds" has an export; "LPs" has none | Open "LPs" | Recent exports is empty (E1's text) | Recent exports | delivery_export |
| E3 | Outsider warning, Cancel | As H5 | Popup › **Cancel** | Nothing saved; the report has no schedule | Recipients outside the company | delivery_schedule |
| E4 | Addresses tidied | Delivery tab | Recipients `Meera@Acme.test; ravi@acme.test` + new line + `meera@acme.test` › Save | Stored `meera@acme.test`, `ravi@acme.test` (lower-case, no duplicate) | A checked schedule | delivery_schedule |
| E5 | Turning off | A saved, enabled schedule | Switch off | Saved at once: "Schedule turned off"; schedule disabled; recipients unchanged | A checked schedule | delivery_schedule |
| E6 | An old UTC schedule | Saved daily schedule with time zone UTC | Open the Delivery tab | Time zone shows UTC; "Next … UTC"; nothing changed until saved | Time zone named | delivery_schedule |
| E7 | Never sent | New schedule, saved | Open the Delivery tab | "Not sent yet · Next <date> <time> IST" | Last sent and next | delivery_schedule |
| E8 | Remove a reader filter | As H10 | ✕ on *City is Mumbai* | Rows Aditi Rao, Kiran Mehta, Nova LP again; no reader chips | Narrow down | delivery_reading |
| E9 | Reader can't override a saved filter | Report page of "LPs" | Address with `q[category_eq]=Co-Investor` | Rows stay LPs; message "Category is already set by the report"; no reader chip | Narrow down | delivery_reading |
| E10 | Unknown field ignored | Report page | Address with `q[no_such_field_eq]=x` | Same rows as without it; no reader chip | Narrow down | delivery_reading |
| E11 | No saved filters | Investor report without filters | Open the report page | No "This report shows only" line; Narrow down still offered | The report's filters in words | delivery_reading |
| E12 | Paged report | "LPs" shown 2 rows per page | Open page 1 | Cards' figures equal the totals row "Total (this page)"; each card reads "this page" | Headline totals | delivery_reading |
| E13 | Nothing to total | Report with Investor and Category only | Open the report page | No cards | Headline totals | delivery_reading |
| E14 | A report once marked as a view | "LPs" with `is_view` true | Open the report page | Opens and runs as any report | Save as View removed | delivery_reading |

## Error cases

| # | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| X1 | Export fails | "LPs"; Acme has no folder to save to | **Export XLSX** | Button back to **Export XLSX**; red alert "Couldn't export LPs: …" | Export shows its progress | delivery_export |
| X2 | Invalid address | Delivery tab; no schedule yet | Recipients `meera@acme.test, bob@` › Save | Under the field: "bob@ isn't an email address" (what was typed stays); red message; nothing saved | A checked schedule | delivery_schedule |
| X3 | Empty list | Delivery tab, switch on | Recipients empty › Save | "Add at least one email"; nothing saved | A checked schedule | delivery_schedule |
| X4 | Outsider without confirming | No schedule | `PATCH …/schedule` with `lp@gmail.com`, no confirmation | Refused (422): "Confirm sending to people outside Acme Capital first"; nothing saved | Recipients outside the company | delivery_schedule |
| X5 | Another company | Omar (Beta Partners) | `POST …/schedule_test` and `POST …/schedule_check` on Acme's "LPs" | Refused (Access denied); no email | Send test to me | delivery_schedule |

## Rules in one place

| Rule | Value |
|---|---|
| Separators | comma, semicolon, new line, spaces |
| Valid address | `URI::MailTo::EMAIL_REGEXP` and a dot in the domain |
| In the company | a user whose `entity_id` is the report's company, email compared lower-case |
| Recent exports | documents owned by the report with tag "Generated", newest first, the first 5 the user may open |
| Cards | the first 4 columns in report order that have a total; text = the totals row's text |
| Reader filters | the report's root filter fields only; a field the report already filters on is dropped |
| Send time | 09:00 in the schedule's time zone (unchanged); new schedules default to Asia/Kolkata |
