# Allocation Run Templates User Guide

Allocation run templates let you define a close once and run it for any period with one action. A template remembers one fund and the options you always run it with. A group puts templates in run order, so the master fund always finishes before its feeders.

> For what an allocation run itself does, see the **[Capital Commitments User Guide](capital_commitments_user_guide)**. Locking and unlocking runs works exactly as before.

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
11. [Frequently asked questions](#frequently-asked-questions)

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

1. Open the fund and choose **Allocate Account Entries** from the fund's actions.
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

After you start a run you land on its progress page, which refreshes itself every few seconds. It shows a progress bar and, for each template, whether it is pending, running, finished or skipped, how long it took, and links to the account entries it produced and to the fund's allocation screen.

You can leave the page. When the group finishes you receive an in-app alert and an email listing the result of every template.

Locking each allocation run stays a manual step on the fund's allocation screen, exactly as today.

---

## When a template fails

A template counts as successful only when its allocation run finishes with status **Success**. Anything else — an error, or a run left at *Pending* — stops the group. Templates after it are not run and are marked **Skipped**.

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

## Frequently asked questions

**Can I give different periods to different templates in one run?**
No. One start and end date is entered per run and applied to every template.

**Can two groups run at the same time?**
No. One group runs at a time per entity, so two closes can never write entries on the same fund in an undefined order.

**Does the group lock the runs when it succeeds?**
No. Locking is the review point and stays a manual click per run on the fund's allocation screen.

**What happens if the server restarts during a run?**
The run continues from the template that was running; templates that already finished are not run again.

**Why is Delete greyed out on a template?**
It is part of a group. Edit the group and untick the template, or delete the group, then delete the template. Run history is kept either way.
