# Report Builder assistant — Business rules and worked examples

> **Companion to:** [Design](design.md) · [Proposal](proposal.md) · [Spec](specs/reports/report-builder-assistant/spec.md)
> Each row is exactly one Cucumber scenario, tagged `# <ID> — <Happy path|Edge case|Error case>: …`. Feature paths are under `features/core/report_builder/`. The AI is always stubbed at `LlmService.ruby_llm_chat`; each row names the answer it gives.

**ID legend:** **H** = Happy path · **E** = Edge case · **X** = Error (exception) case.

## Contents

- [Shared setup](#shared-setup)
- [Happy path](#happy-path)
- [Edge cases](#edge-cases)
- [Error cases](#error-cases)
- [Rules in one place](#rules-in-one-place)

## Shared setup

The Phase 1 "Acme" fixture (`report_builder_trust_steps.rb`), with Acme's default AI model set, plus:

| Name | What the stubbed AI answers |
|---|---|
| **LP owing draft** | Step 1 `{"root_model":"Investor"}`. Step 2: columns Investor, Category, capital commitments' Committed, Called, Collected (sum), formula Unpaid = Called − Collected; Category is LP; sort Unpaid desc; question `pick_fund` "Which fund?"; assumption "owe money = Called − Collected"; name "LPs owing on calls" |
| **Distributed refinement** | The current draft it was sent, plus the column `capital_commitments.distribution_amount` "Distributed" (sum) |

## Happy path

| # | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| H1 | Describe page | Meera on Reports | New report › **Describe it** | "Describe your report" box; examples are the template questions; **Draft** | Ask in words | assistant |
| H2 | A draft | Describe page | "Which LPs still owe money on calls? Biggest first." › Draft (LP owing draft) | Draft page: cards *One row per investor*; columns Investor, Category, Committed, Called, Collected; *Only include investors where Category is LP*; *Sorted by Unpaid (largest first)*; *Calculates Unpaid*; question **Which fund?** listing Global Fund, Growth Fund II; assumption shown | Check the draft | assistant |
| H3 | Pick the fund | H2 | Which fund? › Growth Fund II | Card *Only capital commitments in Growth Fund II*; no AI call made | Answer the fund question | assistant |
| H4 | Refine | H3 | Refine "also show what was distributed" (Distributed refinement) | The AI got the current draft and the instruction; column Distributed added; GF2 limit kept | Refine in words | assistant |
| H5 | Suggested chart | H3 | Open the preview | Chart *Bar — Committed by Investor* (horizontal bar of the first amount by the first text column, top 15) | Suggested chart | assistant_chart |
| H6 | Save and open | H3 | Name "LPs owing — GF2" › **Save and open** | Lands on the report page; not a draft; description is the question; Ravi sees it on Reports | Save | assistant |
| H7 | Chart on the report page | H6 with the suggested chart kept | Open the report page | A chart above the table with **Hide chart** | Charts on the report page | assistant_chart |
| H8 | Describe a chart | H3 | Describe a chart "pie of committed by investor" | The chart AI gets the 20 preview rows; the chart is saved for the report; the page says "sends these 20 rows to your configured AI model" | Describe a chart | assistant_chart |
| H9 | Fine-tune in builder | H3 | **Fine-tune in builder** | Saved (not a draft); the builder opens | Save | assistant |

## Edge cases

| # | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| E1 | Something not reportable | "Show IRR by fund" — AI: Fund rows, Name; cannot "IRR isn't a reportable column" (suggest DPI) | Draft | Under **Assistant's notes** (collapsed): "IRR isn't a reportable column — try DPI"; the rest is drafted. **Couldn't do** lists only what CapHive's checks removed (real-model check, 2026-11-01: the model's own remarks were long and sometimes contradicted its draft) | Couldn't do | assistant |
| E2 | A value that matches nothing | AI: investors where Category is "Partner" | Draft | Filter left out; Couldn't do: "No investors have Category Partner — values: Co-Investor, LP" (on the four largest tables, a text value is checked with one EXISTS and no list is given) | Couldn't do | assistant |
| E3 | Fixed dates | AI: assumption "last quarter = 1 Jul – 30 Sep 2026", date filters | Draft | The assumption is listed; filters on those dates | Check the draft | assistant |
| E4 | Data not in reports | AI step 1: `SecondarySale` | Draft | Couldn't do: "secondary sales aren't available in reports for your account"; nothing to preview | Couldn't do | assistant |
| E5 | Hand edits kept | H3; Meera removed Category in the builder | Refine "also show what was distributed" | The draft sent to the AI has no Category column | Refine in words | assistant |
| E6 | A very large table | AI: capital remittances (one of the largest tables), Folio, Call amount; export threshold 2 rows | Preview | The preview runs; the report check says "Export will have 4 rows — it may take a while" | Suggested chart | assistant_chart |
| E7 | Left the page | Drafting | The draft finishes | Alert "Your draft report is ready" with a link to the draft | Ask in words | assistant |
| E8 | Discard | H3 | **Discard** | The draft is deleted; back on Describe | Save | assistant |
| E9 | Private drafts | Meera's draft | Ravi opens Reports, then the draft's address | Not listed for Ravi; Access denied | Private drafts | assistant |
| E10 | Clean-up | A draft untouched for 8 days, one for 2 days, a saved report from 30 days ago | The clean-up runs | Only the 8-day draft is deleted | Private drafts | assistant |
| E11 | Date and amount | AI: capital calls, Due date, Call amount | Preview | Suggested chart *Line — Call amount over Due date* | Suggested chart | assistant_chart |
| E12 | Nothing to chart | AI: investors, Name, Category | Preview | "No chart suggested"; Describe a chart still offered | Suggested chart | assistant_chart |

## Error cases

| # | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| X1 | AI times out | The AI raises twice | Draft | "Couldn't draft this right now — try again in a moment"; the question stays; asked twice | AI failures | assistant |
| X2 | Not JSON twice | The AI answers prose twice | Draft | Same as X1 | AI failures | assistant |
| X3 | Nothing usable | AI: every column unknown | Draft | Only Couldn't do; no preview; no Save | Couldn't do | assistant |
| X4 | No AI model | Acme without a default model and no platform default | Open Describe it | "AI drafting isn't set up for your account" + **Start from a template**; no Draft button | Ask in words | assistant |
| X5 | Another company's data | AI adds a filter `entity_id_eq` = Beta's id | Draft and preview | The filter is left out (Couldn't do names it); preview rows are Acme's | Couldn't do | assistant |
| X6 | Double click | Drafting already | Draft again | One AI conversation, not two | Ask in words | assistant |
| X7 | Another company | Omar (Beta Partners) | Opens or refines Acme's draft | Access denied | Private drafts | assistant |

## Rules in one place

| Rule | Value |
|---|---|
| Draft mark | `reports.category` = "AI draft" and `template.draft` = true |
| Draft name | "Draft — <first 40 characters of the question>" |
| Clean-up | Daily; drafts with `updated_at` older than 7 days |
| AI steps | 1: pick the table from the company's report tables. 2: the spec with that table's columns and related data |
| Retries | One more try after an error or a non-JSON answer |
| Busy | A draft whose state is "drafting" and less than 2 minutes old doesn't start another |
| Chart rules | text + amount → horizontal bar (top 15); date + amount → line; pivot → stacked bar; else none |
