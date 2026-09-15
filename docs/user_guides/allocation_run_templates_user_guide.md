# Allocation Run Templates User Guide

Allocation run templates let you define a close once and run it for any period with one action. A template remembers one fund and the options you always run it with. A group puts templates in run order, so the master fund always finishes before its feeders.

> **Where to find it:** Sidebar → [**Funds → Allocation Run Templates**](/allocation_run_templates); create with **New Template** or **New Group**, or with **Save as template** on a past run in the fund's **Actions → Account Entries → Allocate Account Entries** screen. Needs the Funds module; creating, editing and running need update rights on every fund involved (or company admin).

> An allocation run evaluates a fund's allocation formulas for a period and creates account entries (plus fund ratios and investor statements when those options are on); you start one by hand from the fund's **Actions → Account Entries → Allocate Account Entries** screen. Locking and unlocking runs works exactly as before.

---

## Table of Contents

1. [Why use templates](#why-use-templates)
2. [Saving a template from a past run](#saving-a-template-from-a-past-run)
3. [Creating a template from scratch](#creating-a-template-from-scratch)
4. [Creating a group and setting the run order](#creating-a-group-and-setting-the-run-order)
5. [Running a group](#running-a-group)
6. [The pre-flight check](#the-pre-flight-check)
7. [Following progress](#following-progress)
8. [When a template fails](#when-a-template-fails)
9. [Run history](#run-history)
10. [Who can do what](#who-can-do-what)
11. [Frequently Asked Questions](#frequently-asked-questions)
12. [Related Guides](#related-guides)

---

## Why use templates

Every quarter the same funds are run with the same options, in the same order, and the only thing that changes is the period. Without templates each run has to be typed in again, and the order lives in someone's head. Templates and groups put that knowledge in the system:

- **No re-typing.** The fund, formula scope, formula tags, statement and ratio options are saved once.
- **No wrong order.** Templates in a group run strictly one after another, in the order you set.
- **No half-done close.** Every template is checked before anything starts. If one would be refused, nothing runs and you are shown why.
- **Fail early.** If a template fails mid-way, the group stops and the remaining templates are reported as skipped.
- **A record.** Every run of a group is kept, with a link to the allocation run each template produced.

---

## Saving a template from a past run

This is the easiest way, because the settings have already been worked out by running them.

1. Open the fund and choose **Actions → Account Entries → Allocate Account Entries**.
2. In **Previous Runs**, find the run whose settings you want to keep and click **Save as template**.
3. The popup lists exactly what will be copied and reminds you that the period is *not* saved.
4. Give the template a name that says which fund and which close it is for, such as *Master Fund — quarterly*, and click **Save template**.

Nothing runs when you save. The template appears under **Funds → Allocation Run Templates**.

---

## Creating a template from scratch

1. Go to **Funds → Allocation Run Templates** and click **New Template**.
2. Choose the fund. The form has the same options as the allocation screen, each with a short explanation:
   - **Run allocation formulas**, with the formula scope (Accounting, Reporting or both) and optional formula tags.
   - **Generate fund ratios**, **Explain formulas** and **Sample run** (a few folios only — a group run warns if this is on).
   - **Generate investor statements**, with *Statement for* and the *Statement document* to use.
3. Click **Save template**.

A template must at least run formulas or generate statements. The statement document is remembered by reference: if it is later deleted, runs of the template are blocked until you pick another.

---

## Creating a group and setting the run order

1. On **Allocation Run Templates**, click **New Group**.
2. Name the close, for example *Quarterly close* or *Annual close*.
3. Tick the templates that belong to it and give each a **position**. Lower numbers run first — put the **master fund before its feeders**.
4. Click **Save group**.

A fund may appear in more than one group with different templates (quarterly tags in one, annual tags in another), and a template may belong to more than one group. A template that is in a group cannot be deleted until it is removed from the group.

---

## Running a group

1. On **Allocation Run Templates**, click **Run** on the group's card (or on the group's page).
2. The popup explains what will happen, then asks for the **start date** and **end date**. The same period is applied to every template.
3. If the group has been run before, **Resume from the failed template** is ticked by default. Leave it on to skip the templates that already succeeded for exactly this period; untick it to run everything again.
4. Click **Check templates**. Nothing runs yet — you go to the pre-flight page first.

Only one group can run at a time for your entity. While a group is running, the **Run** buttons are disabled and a manual allocation on a fund the group still has to reach is refused.

---

## The pre-flight check

The pre-flight page checks every template for the requested period and shows one row per template, in run order, with a result:

| Result | Meaning |
|--------|---------|
| **Ready** | All checks passed. |
| **Warnings** | Will run, but read the message first — usually a gap in the dates or a sample run. |
| **Blocked** | Would be refused. Nothing in the group runs while any template is blocked. |
| **Already done** | Succeeded in the previous run for this period and will be skipped. |

What is checked:

- You have the right to run allocations on the fund.
- No locked allocation run already covers the period on that fund.
- No blocking validation rule fires for the fund and period; warnings are shown too.
- The statement document still exists, if the template generates statements.
- Every formula tag on the template still exists in the entity settings.
- The period starts the day after the last locked run on the fund (a gap is a warning, not a blocker).

If everything passes, click **Start run**. If something is blocked, fix it (the message says what and links to the fund's allocation screen), then click **Check again**.

---

## Following progress

After you start a run you land on its progress page, which refreshes itself every few seconds. It shows a progress bar and, for each template, its status (pending, running, success, failed, skipped, or **Reused** for a template kept from an earlier successful run of this period — the pre-flight calls these *Already done*), how long it took, and links to the account entries it produced and to the fund's allocation screen.

You can leave the page. When the group finishes you receive an in-app alert and an email listing the result of every template.

Locking each allocation run stays a manual step on the fund's allocation screen, exactly as today.

---

## When a template fails

A template that runs formulas counts as successful only when its allocation run finishes with status **Success**; a statements-only template succeeds when its run finishes with a blank or **Success** status (no recorded error). Anything else — an error, or a formula run left at *Pending* — stops the group. Templates after it are not run and are marked **Skipped**.

To recover:

1. Open the progress page and read the failure message on the failed template.
2. Fix the cause on the fund (a formula, a missing valuation, a document…).
3. Click **Run** on the group again with the same period. With **Resume from the failed template** ticked, the templates that already succeeded are shown as *Already done* and only the failed one and those after it run.

Each run creates a new allocation run record on the fund; earlier ones stay in the fund's history.

---

## Run history

- **Allocation Run Templates → Run History** lists every time any group was run, newest first, with its period, status, progress and who started it.
- A group's page has its own **Run history** tab.
- A template's page has a **Runs** tab showing every group run it took part in.

History is kept even after a group or template is deleted.

---

## Who can do what

- **Company admins** can define, change and run any template or group in the entity.
- **Other employees** can define and change a template when they may run allocations on its fund, and can run a group only when they may run allocations on **every** fund in it. The pre-flight checks this fund by fund before anything starts.
- Investors never see these screens.

---

## Frequently Asked Questions

### Navigation and getting there

**Where do I find Allocation Run Templates in CapHive?**
Sidebar → [**Funds → Allocation Run Templates**](/allocation_run_templates). The page has three tabs: **Groups** (the default), **Templates** and **Run History**, and the buttons **Run History**, **New Template** and **New Group** at the top right.

**How do I open the fund's allocation screen, where Save as template lives?**
Sidebar → [**Funds → Funds**](/funds), open the fund, then **Actions → Account Entries → Allocate Account Entries**. The **Previous Runs** list on that screen has the **Save as template** icon on each run. See [Saving a template from a past run](#saving-a-template-from-a-past-run).

**Where do I see every group run that has ever happened?**
Click **Run History** at the top of Allocation Run Templates, or open [**Run History**](/allocation_group_runs) directly; it lists every group run newest first with period, status, progress and who started it. A group's page has its own **Run history** tab, and a template's page has a **Runs** tab. See [Run history](#run-history).

**Where is the progress page of a run I started?**
Starting a run takes you straight to its page (tabs **Progress** and **Details**). While a group is running a **View progress** button also appears at the top of Allocation Run Templates and on the group's page, and the finish alert links back to it. See [Following progress](#following-progress).

**I can't see Allocation Run Templates in the sidebar. Why?**
The **Funds** sidebar block and this page need the Funds module (`enable_funds`) and a non-investor role; investor logins never see it. If you see the page but cannot open or run a template or group, you lack update rights on one of its funds. See [Who can do what](#who-can-do-what).

### Creating, updating and managing templates and groups

**How do I create an allocation run template?**
Either open a fund's **Allocate Account Entries** screen and click **Save as template** on a past run (settings are copied, the period is not), or go to **Funds → Allocation Run Templates** and click [**New Template**](/allocation_run_templates/new). Choose the fund and options, then **Save template**. See [Creating a template from scratch](#creating-a-template-from-scratch).

**What must a template contain to be saved?**
A unique name (per entity, up to 100 characters), a fund of your entity, and at least one of **Run allocation formulas** or **Generate investor statements**. If it generates statements, *Statement for* is required and the statement document must be an SOA or investor statement template on that same fund.

**How do I edit a template?**
On the **Templates** tab open the row's action menu and choose **Edit**, change the options and save. You need update rights on the template's fund, or be a company admin.

**How do I delete a template?**
On the **Templates** tab choose **Delete** from the row's action menu and confirm. If the template is in a group the item shows **Delete (in a group)** and is disabled: edit the group and untick it, or delete the group, first.

**How do I create a group and set the run order?**
Click [**New Group**](/allocation_run_template_groups/new), name the close, tick the templates and give each a **position** (whole number above zero; lower runs first), then **Save group**. Put the master fund before its feeders. See [Creating a group and setting the run order](#creating-a-group-and-setting-the-run-order).

**How do I change a group's order or templates?**
On the group's card open the settings menu and choose **Edit order and templates**, or click **Edit** on the group's page. Change positions, tick or untick templates and save; a group must keep at least one template.

**How do I delete a group?**
Group card settings menu → **Delete**, or **Delete** on the group's page, then confirm. The templates in it and its run history are kept.

**How do I run a group for a period?**
Click **Run** on the group's card, enter the **start date** and **end date** (it defaults to the last full quarter), leave **Resume from the failed template** as needed, click **Check templates**, review the pre-flight page, then click **Start run**. See [Running a group](#running-a-group).

**Can I run a single template without a group?**
No. A template only runs inside a group, so create a one-template group for it, or run the fund manually from its **Allocate Account Entries** screen.

**What permission do I need, and how do I get it?**
Company admins can do everything. Other employees need update rights on the fund (granted on the fund's **Access** tab by a company admin) to create, edit, delete or open a template, and update rights on **every** fund in a group to open, edit, delete or run that group.

### Why use allocation run templates

**Why should I use allocation run templates?**
A quarterly or annual close repeats the same funds, options and order every period. Templates save the fund, formula scope, tags, ratio and statement options once, and a group runs them in a fixed order with one action, so nothing is retyped and the order no longer lives in someone's head. See [Why use templates](#why-use-templates).

**What does a group run give me that running funds one by one does not?**
Every template is checked before anything starts, so a close never half-runs because of a locked period or a missing document. Templates run strictly in order, a failure stops the rest, you can resume from the failed template, and every run is recorded with a link to each fund's allocation run.

**What goes wrong if I keep running closes by hand?**
A feeder can be run before its master fund and pick up stale numbers, a formula tag or statement option can be forgotten, and there is no single record of what was run for the period. Nothing stops two people allocating the same fund at once either, which a group run prevents.

**Who typically uses allocation run templates?**
Fund accountants and operations staff who run the periodic close across several related funds, especially master-feeder structures. Company admins usually define the groups; employees with update rights on all the funds run them.

### What happens when I …

**What happens when I save a template?**
Only the template record is created; nothing runs and no account entries change. It appears on the **Templates** tab and can be added to groups. The statement document is stored by reference, so deleting that document later blocks runs until you pick another.

**What happens when I click Check templates?**
Nothing runs and nothing is recorded. The pre-flight page checks each template for the period (permission, locked runs, validation rules, statement document, formula tags, date gap) and marks it **Ready**, **Warnings**, **Blocked** or **Already done**. See [The pre-flight check](#the-pre-flight-check).

**What happens when I click Start run?**
The checks run again, a group run is recorded with one item per template (status *pending*, or *reused* for templates already done), and a background job starts. No other group can start for your entity until it finishes, and manual allocation runs on funds it has still to reach are refused.

**What happens to account entries when each template runs?**
A new allocation run is created on the fund for the period. If the template runs formulas, previously generated entries for those formulas in the period are hard-deleted and regenerated; then fund ratios and investor statements are generated if the template says so. Earlier allocation runs stay in the fund's **Previous Runs** list.

**Who is notified when a group run finishes?**
Only the user who started it: an in-app alert with the counts by status and a **View progress** link, and an email titled "Allocation run group … finished successfully" or "… stopped after a failure" (sent to the entity's sandbox addresses when sandbox mode is on). Investors are not notified; statements generated are not emailed by the run.

**What happens when a template fails?**
Its item is marked failed with the reason, every later template is marked **Skipped** and not run, and the group run ends as failed. Templates that already succeeded keep their entries. See [When a template fails](#when-a-template-fails).

**What happens when I run the group again with Resume ticked?**
The latest finished run of the group for exactly the same start and end date is found, and templates that succeeded there are marked **Already done** and reuse that allocation run. Only the failed template and those after it run. If every template already succeeded, the pre-flight tells you to untick Resume.

**What happens when I delete a template or a group?**
Deleting a template removes only its definition; past group run items keep their name and allocation run. Deleting a group removes the group and its template list, but not the templates or its run history. Neither touches any account entries, and neither can be undone.

**What happens if I edit a template while its group is running?**
The job reads the template when that template's turn comes, so edits saved before then are used for this run. If the template is deleted before its turn, its item fails with "The allocation run template was deleted before it could run."

**Can I undo a group run?**
There is no undo button, and allocation runs cannot be deleted from the screen. Correct the cause and run the group again for the same period (untick Resume to re-run every fund): each formula-running template deletes and regenerates its generated entries for the period.

### Troubleshooting and edge cases

**Can I give different periods to different templates in one run?**
No. One start and end date is entered per run and applied to every template.

**Can two groups run at the same time?**
No. One group runs at a time per entity, so two closes can never write entries on the same fund in an undefined order. The **Run** button is disabled with a tooltip while another group is running.

**Does the group lock the runs when it succeeds?**
No. Locking is the review point and stays a manual **Lock** click per run on the fund's **Allocate Account Entries** screen, which needs update rights on the fund.

**What happens if the server restarts during a run?**
If the background worker hands the job back on shutdown, the run continues: finished templates are skipped and the template that was running is run again with a fresh allocation run. If the worker is killed outright the group can stay at *running* and block new group runs until support marks it failed.

**Why is Delete greyed out on a template?**
It is part of a group. Edit the group and untick the template, or delete the group, then delete the template. Run history is kept either way.

**Why is a template Blocked by a locked allocation run?**
A locked run on that fund overlaps the period, and templates that run formulas cannot overwrite locked periods. Unlock the run on the fund's **Allocate Account Entries** screen if the period really needs re-running, then click **Check again**.

**Why does the pre-flight say a formula tag no longer exists?**
A tag saved on the template was removed from the entity's formula tag list, so fewer formulas would run than intended. Edit the template to remove or replace the tag, or add the tag back in the entity settings.

**Why did a manual allocation on my fund get refused with "An allocation run group is currently running on this fund"?**
A group run in progress still has a pending or running item for that fund. Wait until the group finishes (watch its progress page); once the fund's template is done, manual runs work again.

**Why does my template show a sample warning?**
**Sample run** is ticked, so only a few folios are computed. It is a warning, not a blocker; edit the template and untick it for a real close.

**A template generates only statements. When does it count as successful?**
When its allocation run finishes without a recorded error. A template that runs formulas succeeds only when its allocation run reaches status **Success**; a run left at *Pending* counts as a failure.

## Related Guides

- [Capital Commitments](capital_commitments_user_guide) — the folios every allocation run computes entries for.
- [Fund Ratios](fund_ratios_user_guide) — what the Generate fund ratios option produces.
- [Fund Ratio Run Templates](fund_ratio_run_templates_user_guide) — the equivalent templates for cross-fund and cross-company ratio runs.
- [Formula Dependencies](formula_dependencies_user_guide) — checking the allocation formulas a template runs.
- [Validation Rule Engine](validation_rule_engine_user_guide) — the rules the pre-flight check evaluates for each fund and period.
- [Account Entries Period Report](account_entries_period_report_user_guide) — reviewing the entries a close produced.
