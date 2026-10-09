# A disabled template's auto-assignment rules block assignment — Manual QA Checklist

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
| Environment | Staging, as a company admin of an Investment Fund entity with **Workflow templates** switched on |
| Accounts | One company admin (creates templates and rules, enables and disables); one ordinary fund user in the **same** entity (sees a record's journey); one company admin in a **different** entity (for C4) |
| Seed data | On **Workflows** (top-right company menu → Workflows): two templates for the same record type. Use **Folder** for the rule tests so nothing investor-facing is touched, and the investor KYC journey for the end-to-end row. Each needs at least one step and its own auto-assignment rule — add rules from the template's page, **Auto-assignment Rules → Add Rule** |
| Background work | None needed. Assignment and launch happen as the record is saved. If a journey step bar looks stale, reload the page |
| Developer-assisted rows | X1 only — it needs a rule whose template row has been removed directly in the database, which no screen can produce |

---

## The Original Bug

| ☐ | ID | What to check | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | B1 | A retired template no longer stops new records getting the workflow you do want | 1. On **Workflows**, use **Set up journeys → Set up investor KYC journeys** so the "Investor KYC" template exists. 2. Open it and add a rule: type **Investor KYC**, no conditions, auto-launch **Yes**, priority **0**. 3. Create a second template for Investor KYC with one step, give it a rule with no conditions and priority **0**, then **Disable** that second template. 4. Create a new investor KYC. | The KYC page shows the **Investor KYC** journey step bar, and the KYC's workflow shows the "Investor KYC" template — the disabled template is simply passed over | | |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | A disabled template's rule is skipped and the next rule applies | Two Folder templates, each with a no-conditions rule at priority 0; the first-created one is **Disabled** | 1. Create a new folder. 2. Open it and look at its workflow. | The folder is on the **enabled** template, with its workflow started if that rule has auto-launch **Yes** | | |
| ☐ | H2 | Disabling is reversible and the rule comes back untouched | H1 done | 1. Open the disabled template and click **Enable**, confirm. 2. Check its **Auto-assignment Rules** list. 3. Create another folder. | The rule is still listed exactly as before — same priority, conditions and auto-launch, nothing was deleted — and the new folder is on the re-enabled template | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | With every template retired, a record still gets nothing | Both Folder templates from H1 **Disabled** | 1. Create a new folder. 2. Open it. | The folder has no workflow and no step bar. No error is shown | | |
| ☐ | E2 | A narrow retired rule falls through to the live catch-all | A disabled template with a rule "name is Target Folder" at priority **10**, and an enabled template with a no-conditions rule at priority **100** | 1. Create a folder named exactly **Target Folder**. 2. Create a folder named anything else. 3. Open both. | Both folders are on the **enabled** catch-all template — the specially named one is treated like any other | | |
| ☐ | E3 | The rule that wins decides whether the workflow starts | A disabled template whose rule has auto-launch **Yes**, and an enabled template whose matching rule has auto-launch **No** | 1. Create a new folder. 2. Open it. | The enabled template is assigned but **no** workflow has started — the page offers **Launch Workflow** rather than showing a running one | | |
| ☐ | E4 | Two rules at the same priority resolve the same way every time | Two **enabled** Folder templates, each with a no-conditions rule at priority 0 | 1. Create three folders one after another. 2. Open each. | All three are on the same template — the one whose rule was created first. No alternating between the two | | |
| ☐ | E5 | A record created while nothing could be assigned picks the workflow up when it is next saved | A folder created while the only live rule was blocked (as in B1 before the fix), now with the blocking template's rule reachable | 1. Open that folder. 2. Rename it and save. 3. Reload. | The folder now shows the live template's workflow. Records created earlier are not changed until they are saved | | |
| ☐ | E6 | The disable dialog says what will happen instead | A template with at least one rule, and another enabled template whose rule could match the same records | 1. Click **Disable** on the first template. 2. Read the confirmation message before confirming. | The message says the rules go dormant and are kept, and names the template that will take over for the records this one's rules matched (or says nothing will) | | |
| ☐ | E7 | The disabled template's page describes dormant, not dead, rules | A disabled template with rules | 1. Open it. | The note under **Auto-assignment Rules** says the rules are dormant while the template is disabled, that the next matching rule for that type applies, and that they resume unchanged when it is enabled | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message shown, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 **(dev)** | A rule pointing at a template that no longer exists does not break record creation | Ask a developer to delete a template row directly, leaving its rule behind, ahead of a live catch-all rule | 1. Create a new folder. 2. Open it. | The folder saves normally and is on the live catch-all template. No error page, no error flash | | |
| ☐ | X2 **(dev)** | A template that cannot legally be assigned fails quietly | Ask a developer to retype an enabled template to a different record type behind its rule's back, sitting behind a disabled template's rule | 1. Create a new folder. 2. Open it. | The folder saves with no workflow and no error page. The failure is only in the logs | | |

---

## Regression

| ☐ | ID | What still has to work | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | R1 | A disabled template cannot be launched by hand | 1. Open a record whose template was disabled after it was assigned. 2. Click **Launch Workflow**. | The disabled template is **not** in the picker. If it was the record's assigned template, launching is refused with a message saying the template is disabled | | |
| ☐ | R2 | Workflows already running are untouched | 1. Start a workflow on a record. 2. Disable that template. 3. Reopen the record. 4. Complete or acknowledge a step. | The step bar is unchanged and the workflow still advances, reminds and completes as before | | |
| ☐ | R3 | Journeys still work end to end for a normal fund | 1. On **Workflows**, **Set up journeys** for capital calls. 2. Create a capital call. 3. Open it. | The call shows its journey step bar and "What's needed now" panel exactly as before | | |
| ☐ | R4 | A kind with every journey template retired reports itself correctly | 1. Disable both the Full and Light capital call templates. 2. Open the **Set up journeys** menu on **Workflows**. | The menu shows the capital call kind as **disabled**, not as set up, and explains that new calls get no journey | | |
| ☐ | R5 | Enable/Disable, Status badges and the template list are unchanged | 1. Open **Workflows**. 2. Disable, then enable, a template from the list row button and again from the template page. | Each click asks for confirmation, the **Status** badge flips between Enabled and Disabled, the disabled template's name is muted, and the success message matches the direction of the change | | |
| ☐ | R6 | The user guide answers the question correctly | 1. Open the Workflow Templates user guide. 2. Read the section on enabling and disabling a template and the FAQ about a record getting no journey. 3. Ask the support chatbot "why did my new KYC get no journey?" | Both say a disabled template is skipped and the next matching rule applies, and that a record gets nothing only when no live template's rule matches. Neither says that no other rule takes over | | |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Dates on any screen the fix touched | N/A — the fix changes no date display. The template page and list show no dates | | |
| ☐ | C2 | Dates in any email the fix touched | N/A — no email content changes. Task reminder emails are unchanged | | |
| ☐ | C3 | Narrow / mobile width | The template page's disabled banner, Status tile, rules table and the longer disable confirmation message all fit with no horizontal scroll, and **Disable** stays reachable | | |
| ☐ | C4 | Tenant isolation | A company admin of another entity cannot open this entity's template by its direct URL, and their own records are assigned only from their own entity's rules | | |
| ☐ | C5 | Screens the fix touched | **Workflows** list, a template's page (banner, Status tile, rules table, Enable/Disable), the Launch Workflow dialog, and a record's journey step bar each still do everything they did before | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
