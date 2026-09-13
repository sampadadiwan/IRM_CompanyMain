# Deals Report Agent — User Guide

The Deals Report Agent looks across a fund's open deals and produces a fundraising status report for each one — committed vs. target amounts, fill rate, activity-step distribution, top investors, and staleness — then emails a consolidated summary to whoever you've configured to receive it.

> **Where to find it:** Company menu (house icon, top right) → [**Agents**](/support_agents) → **Deals Report** card, with **Run Now** on its **General** tab and results on **Deal Reports**. Recipients, report sections and a schedule are set on any deal: Sidebar → [**Deals**](/deals) → open the deal → **Agent Settings** tab → **Save Settings**. Needs the *Deals Report Agent* support-agent flag (set by CapHive support); running it needs the **Company Admin** role.

## Table of Contents

1. [What This Agent Does](#1-what-this-agent-does)
2. [Inputs](#2-inputs)
3. [Enabling the Agent](#3-enabling-the-agent)
4. [Accessing and Running the Agent](#4-accessing-and-running-the-agent)
5. [Scheduling](#5-scheduling)
6. [Where to Find the Output](#6-where-to-find-the-output)
7. [Understanding the Report](#7-understanding-the-report)
8. [Where It Can Fail](#8-where-it-can-fail)
9. [Frequently Asked Questions](#9-frequently-asked-questions)

---

## 1. What This Agent Does

Unlike the Deal Management Agent, this one runs against your whole organization rather than a single deal, and works through these steps:

1. **Gets started** — loads its settings: who should receive the report, the staleness threshold, an optional list limiting it to specific deals, and five on/off switches controlling which sections appear in the email (greeting, activity updates, tasks due, tasks overdue, and stale items — all on by default).
2. **Loads the deals** — pulls in every open deal for your organization, narrowed down to a specific list of deals if one has been set.
3. **Calculates summaries** — for each deal, works out target vs. committed/pending/declined amounts, fill rate, an overall health classification (on track / needs attention / complete / closed), how many days since the last investor activity, how investors are distributed across pipeline steps, and the top 10 investors by committed amount.
4. **Generates reports** — saves each deal's summary as a report attached to that deal, and also creates an HTML document called "Deal Fundraising Report" in a private Reports folder inside that deal's documents (replacing any earlier version rather than piling up duplicates).
5. **Sends the email** — sends one consolidated summary to the configured recipients, if any are set.
6. **Wraps up** — finalizes the run's status.

Unlike the Deal Management Agent, this one is **not AI-powered** — it's pure number-crunching over your deal, investor, and activity data. No AI provider key is needed for it to work.

## 2. Inputs

This agent doesn't have its own configuration screen the way the other agents do — there's no field-by-field settings page on its Edit screen.

In practice, you configure it through a **dedicated panel on the Deal page itself**, not the agent's own edit page:

- Open a deal → **Agent Settings** tab.

| Field (set from the Deal page) | Type | Default | What it controls |
|---|---|---|---|
| Email addresses | Text (comma-separated) | blank | Who receives the summary email. |
| No-activity threshold (days) | Number | 14 from this panel | How many days without investor activity before a deal gets flagged as stale. |
| Greeting & Fill Rate Summary | Checkbox | on | Includes the greeting/fill-rate paragraph in the email. |
| Activity Updates | Checkbox | on | Includes the "updates to existing items" section. |
| Tasks Due | Checkbox | on | Includes upcoming due-date tasks. |
| Tasks Overdue | Checkbox | on | Includes overdue tasks. |
| No-Activity Items | Checkbox | on | Includes the staleness section. |
| Schedule (frequency/day/time/timezone/enabled) | Form controls | weekly, 10:00, UTC, enabled | Sets up the agent's recurring schedule directly from this same page (Daily, Weekly or Monthly only). **Enabled** is pre-ticked when no schedule exists yet, so the first **Save Settings** turns the schedule on. |

**Important — this is the single most important thing to know about this agent.** Saving this panel always sets the deal scope to **just the current deal you're viewing**. There's no control on this panel to build a list of several deals, or to clear the scope back to "all open deals." By default — before this panel has ever been saved — the agent covers every open deal in your entity. But the moment anyone opens a deal's Agent Settings tab and saves it (even just to update the recipient list), the report quietly narrows down to that one deal only, with no warning that this happened. If you need the report to go back to covering all open deals, or to cover a specific custom set of deals, that currently requires admin or engineering help working directly with the underlying record — there's no in-app way to do either of those today.

The actual settings stored behind the scenes are:

- The deal scope — comma-separated deal IDs, or blank for "all open deals."
- The recipient list — comma-separated email addresses.
- The staleness threshold — a day count (falls back to 30 if not set at all).
- The five section toggles — each defaulting to on.

Other things the agent looks at (not settings you configure): each open deal's investors (active, pending, or declined), each investor's committed amount, the deal's target amount, the pipeline template steps used to build the step distribution, and the most recent activity update tied to any investor (used to determine staleness).

### Setup checklist and warnings

The agent's **General** tab (Company menu (house icon, top right) → **Agents**) shows a yellow warning banner when setup would silence or distort the report:

- **No email recipients configured** — the summary email, this agent's main output, will never be sent. The run still completes and looks successful in the history.
- **The staleness threshold set but left blank** — a blank value is treated as 0 days, which flags every deal as stale. Enter a day count or remove the value.
- **A section toggle stored with an unexpected value.** The five section checkboxes are strict about how their on/off state is stored — if one holds anything other than a plain on/off value (which can happen when settings are edited outside the Deal page panel), that section silently drops out of the email. The banner names the affected section; re-saving the Agent Settings panel on the Deal page fixes it.

## 3. Enabling the Agent

1. CapHive support turns on the *Deals Report Agent* support-agent flag for your entity.
2. No AI provider key is required — this agent never calls the AI.
3. The Deal page's **Agent Settings** tab is gated by the same flag: without it the tab is shown locked with the tooltip "Deals Report Agent is disabled. Contact support to enable it". With the flag on, any user with permission to edit the deal can **Save Settings**, but the tab's **Run Now** (like the agent page's) needs the **Company Admin** role.
4. The agent record must exist first — a company admin runs **Setup All Agents** on Company menu (house icon, top right) → **Agents**. Until then the panel shows no **Run Now** button and **Save Settings** fails with "Could not save agent settings: Name can't be blank".

## 4. Accessing and Running the Agent

**From the Deal page (the supported path today):**
1. Open any deal → **Agent Settings** tab.
2. Set recipients, the staleness threshold, the content toggles, and the schedule.
3. Click **Run Now** and then **Run Agent** in the modal (needs the **Company Admin** role), or just let the schedule handle it.

Because this agent always runs at the organization level and works through deals internally, triggering it from any single deal's page still produces a report covering whichever deals are currently in scope — which, per the note above, may have already been narrowed down to just that one deal the last time someone saved that panel.

**From Company menu (house icon, top right) → Agents:** open the Deals Report Agent card and click **Run Now** from the General tab.

**What you'll see while it runs:** **Run Now** on the agent's General tab runs your entity as a single target and shows the live step-by-step progress panel. **Run Now** from a deal's Agent Settings tab runs in the background without a progress panel — you'll see a "queued" notice rather than a step tracker.

## 5. Scheduling

Unlike the Deal Management Agent and Presentation Analyst, this agent does **not** come with a pre-built schedule out of the box. A schedule can be created in two places: the Deal page's **Agent Settings** tab — saving that form creates (or updates) the schedule, defaulting to weekly at 10:00 UTC with **Enabled** pre-ticked, so the first save turns it on — or the agent's own **Schedule** tab, which also offers bimonthly, quarterly and half-yearly frequencies. If nobody has done either, this agent has no schedule at all and will only run when someone clicks Run Now.

## 6. Where to Find the Output

- **Per-deal report**: one report per deal, **replaced** each run rather than kept as history — only the latest result per deal is available.
- **HTML document**: a "Deal Fundraising Report" document saved into a private Reports folder under each deal's documents, replacing any earlier copy.
- **Deal Reports tab**: on the agent's own page (this tab name is shared with the Deal Management Agent's deal-level reports — they're told apart by which agent produced them).
- **Email**: sent to the configured recipients, if any. The subject line includes "- Action Required" if any deal needs attention. No recipients configured means no email goes out — the run still completes and reports still save.

## 7. Understanding the Report

Each deal's report includes:

| Field | Meaning |
|---|---|
| Deal status | "Closed," "Complete" (fill rate at or above 100%), "On track" (fill rate at or above 60%), or "Needs attention" (below 60%). |
| Target / committed / pending / declined / remaining amounts | Fundraising amounts in the deal's own currency. |
| Fill rate | Committed amount divided by target amount, as a percentage rounded to one decimal place. Shows 0.0% if there's no target set. |
| Total / active / pending / declined investor counts | Investor counts broken out by status. |
| Stale, no-activity days, last activity date | Whether the deal has exceeded the no-activity threshold, the actual day count, and the timestamp of the most recent linked activity. The day count is blank if there's never been any activity at all. |
| Step distribution | How many investors sit at each pipeline step, in order. Empty if the deal has no pipeline template steps defined. |
| Top investors | Up to 10 active investors sorted by committed amount, each with name, status, tier, amount, and current pipeline step. |

## 8. Where It Can Fail

- **Deals you've listed that no longer exist or aren't open are silently dropped, not flagged as errors.** If a deal in your configured list has been deleted, belongs to a different fund, or is no longer open, it just disappears from the results with no warning. If that leaves zero deals to report on, the agent records that as "no open deals found" rather than a failure, and the rest of the run still proceeds — meaning you'd get zero deal reports and likely a near-empty email.
- **The Deal page panel silently narrows the report scope to one deal every time it's saved.** This is the most likely real-world surprise: someone opens the Agent Settings tab on Deal A just to tweak the recipient list, saves it, and without realizing it, scopes the entire fund-wide report down to Deal A only. Anyone relying on "all open deals" coverage should know this and avoid saving that panel unless they actually intend to narrow the scope — or have it reset back to "all deals" afterward by an admin.
- **There's no UI for choosing a specific handful of deals.** The agent technically supports a custom multi-deal list, but the only panel that touches this setting is the single-deal Agent Settings tab, which always writes exactly one deal id. Setting up a genuine custom subset has to be done directly on the underlying record by someone with admin/engineering access.
- **No schedule comes pre-built for this agent.** Unlike the other two agents in this set, don't assume a disabled schedule is already waiting for you to switch on. Check the Deal page's Agent Settings tab and the agent's own **Schedule** tab — if neither has been saved, there is no schedule at all yet.
- **Leaving the recipient list blank silences the email** — reports still get generated and saved per deal, but nobody is notified.
- **No AI dependency, but document-save failures are handled gracefully per deal.** If saving the HTML report into a deal's Reports folder hits an error, it's caught and logged, and the run moves on to the next deal — that deal's report still saves even if its HTML document doesn't.
- **Staleness is based purely on activity-step updates** — not notes, not document uploads, not other interactions. A deal where documents are actively being uploaded but no activity steps have changed can still get flagged as stale.

---

## 9. Frequently Asked Questions

### Navigation and getting there

**Where do I find the Deals Report Agent in CapHive?**
Open the Company menu (house icon, top right) → [**Agents**](/support_agents) and click the **Deals Report** card in the **Deal** group. Its page has **General**, **Schedule**, **Execution History** and **Deal Reports** tabs.

**Where do I configure recipients and report content?**
Sidebar → [**Deals**](/deals), open any deal and click the **Agent Settings** tab. The panel has **Report Recipients**, **Schedule** and **Report Content** sections with **Save Settings** and **Run Now** buttons. See [Inputs](#2-inputs).

**Why is the Agent Settings tab greyed out with a lock?**
The *Deals Report Agent* flag is not enabled for your entity; the tooltip says "Deals Report Agent is disabled. Contact support to enable it". Only CapHive support can enable it.

**Where do I read the results?**
On the agent page, the **Deal Reports** tab lists each deal with status, fill rate and amounts. Each deal also gets a "Deal Fundraising Report" file in its private **Reports** folder, and the recipients get the "Deal Fundraising Update" email. See [Where to Find the Output](#6-where-to-find-the-output).

**Who can open and use this agent?**
Anyone who can edit a deal can save its **Agent Settings** panel. Running the agent, from either the deal panel or the agent page, and editing, scheduling or deleting it on the [Support Agents](/support_agents) page need the **Company Admin** role.

### Creating, updating and managing the agent

**How do I create the Deals Report Agent?**
A company admin runs **Setup All Agents → Run Setup** on Company menu → **Agents**; it creates the agent with an empty configuration and no schedule. Do this first: the deal's **Agent Settings** panel cannot create the agent and fails with "Could not save agent settings" until it exists.

**How do I set who receives the report?**
On a deal's **Agent Settings** tab, enter comma-separated addresses under **Report Recipients** and click **Save Settings**. Remember that saving also narrows the scope to that deal, as described below.

**How do I choose which sections appear in the email?**
Tick or untick **Greeting & Fill Rate Summary**, **Activity Updates**, **Tasks Due**, **Tasks Overdue** and **No-Activity Items** under **Report Content**, set the no-activity days, and click **Save Settings**.

**How do I schedule the report?**
Either set **Enabled**, **Frequency** (Daily, Weekly or Monthly), **Day of Week**, **Time** and **Timezone** in the deal panel's **Schedule** section and click **Save Settings**, or use the agent page's **Schedule** tab, which also offers bimonthly, quarterly and half-yearly. Setup creates no schedule. See [Scheduling](#5-scheduling).

**How do I run the report now?**
Click **Run Now** on the agent's **General** tab (live step panel), or **Run Now** on a deal's **Agent Settings** tab and then **Run Agent** in the modal (queued in the background). Both cover every deal in the current scope, not only the deal you are on.

**How do I get the report back to all open deals?**
There is no field for it: every **Save Settings** writes that one deal as the scope. Ask CapHive support to clear the agent's `deal_ids` setting, then avoid saving the deal panel again. See [Where It Can Fail](#8-where-it-can-fail).

**How do I pause or delete the agent?**
Untick **Enabled** in the deal panel's **Schedule** section and save, or untick **Enable scheduled runs for this agent** on the agent's **Schedule** tab. **Delete** on the General tab only works for an agent that has never run.

### Why use the Deals Report Agent

**Why should I use the Deals Report Agent?**
It gives your fundraising team one email with every open deal's committed versus target amount, fill rate, investors by pipeline step, top investors and deals gone quiet. Building that by hand means exporting each deal's investors and adding them up.

**What does it let me do that I cannot do otherwise?**
It rolls every open deal into one portfolio-level status on a schedule, flags deals below 60% fill rate as needing attention, and files a dated HTML report inside each deal's documents. The deal screens only show one deal at a time.

**Who typically uses it?**
Fundraising, investor relations and deal teams, and the partners who want a weekly or monthly pipeline snapshot. No AI key or model is needed.

**How is it different from the Deal Management Agent?**
This agent is pure arithmetic over all open deals and sends one consolidated email. The [Deal Management Agent](deal_management_agent_user_guide) goes deep on one deal with AI term extraction, investor scoring and stagnation checks.

### What happens when I…

**What happens when I click Save Settings on a deal?**
The recipients, no-activity days and section toggles are saved on the agent, the scope is set to that deal only, and the schedule is created or updated from the Schedule fields. On a first save **Enabled** is already ticked, so the schedule starts running. Nothing is sent until the next run.

**What happens when the agent runs?**
It loads open deals in scope, calculates each deal's amounts, fill rate, status, step distribution and top 10 investors, and overwrites that deal's report. It replaces the "Deal Fundraising Report" file in the deal's private **Reports** folder and queues the email. Execution History gets a row; no deal data changes.

**Who is emailed, and when?**
The **Report Recipients** get one "Deal Fundraising Update - Month Year" email when each run finishes, with "- Action Required" added if any deal needs attention. Investors are never emailed; a blank recipient list sends nothing.

**What happens to earlier reports and files?**
Each run overwrites the deal's report on the **Deal Reports** tab and deletes the previous "Deal Fundraising Report" file before saving the new one. Keep the emails if you need history.

**Can I undo a run?**
There is nothing to undo in your deal data, because the agent only reads it. The replaced report file and the sent email cannot be restored or recalled.

**What happens when a deal is closed or deleted?**
Only deals with status Open are loaded, so a closed or deleted deal silently drops out of the next run. If no deals remain, the Load Deals step records "No open deals found" and the email lists nothing.

### Troubleshooting and edge cases

**I want this report to cover all our open deals, but it only seems to include one. Why?**
Someone saved the **Agent Settings** tab on a single deal, which always sets the scope to just that deal. Ask CapHive support to reset the scope to all open deals, and avoid re-saving that panel unless you intend to narrow it.

**Where do I configure which deals are included, beyond "all" or "this one deal"?**
There is no in-app field for a custom list of deals. The agent supports one, but only CapHive support can set it; the deal panel always writes exactly one deal.

**The agent ran but I didn't get an email.**
Check **Report Recipients** on a deal's **Agent Settings** tab; if it is blank no email goes out, although reports are still saved. The yellow banner on the agent's **General** tab also flags a blank recipient list.

**Does this agent need an AI provider key?**
No. Fill rate, staleness, step distribution and top investors are calculated directly from your deal, investor and activity data.

**I enabled the organization-wide toggle but nothing runs automatically. What's missing?**
This agent ships with no schedule. Create one on a deal's **Agent Settings** tab or on the agent page's **Schedule** tab, and make sure it is enabled.

**I clicked Run Now on the deal panel and got a not-authorised error. Why?**
Running any support agent needs the **Company Admin** role, even though saving the panel only needs deal edit permission. Ask a company admin to run it.

**There is no Run Now button on the Agent Settings tab, or Save Settings fails. Why?**
The agent has not been created for your entity yet. A company admin must run **Setup All Agents** on Company menu → **Agents**; then reload the deal and save the panel again.

**Every deal is flagged as having no activity. Why?**
The no-activity days value is blank, which counts as 0 days, or no investor deal step has been updated within the threshold. Only deal-step updates count; notes and document uploads do not.

**A section disappeared from the email. Why?**
Its checkbox is unticked, or the setting holds a value other than exactly "true" after being edited outside the deal panel. The **General** tab banner names the section; re-save the deal panel to fix it.

**Why is the fill rate 0% or the deal marked Needs Attention?**
Fill rate is the Active investors' amount divided by the deal amount; with no deal amount it shows 0.0%. Below 60% the deal is Needs Attention, 60% or more On Track, and 100% or more Complete.

---

## Related Guides

- [Support Agents](../support_agents_user_guide) — setup, Run Now, schedules, Execution History and the warning banner shared by every agent.
- [Deals Management](../deals_management_user_guide) — deals, deal investors, statuses and deal steps the report is built from.
- [Deal Management Agent](deal_management_agent_user_guide) — AI-driven, single-deal monitoring and investor scoring.
- [Document Management](../document_management_user_guide) — the deal's private Reports folder where the HTML report is saved.
- [Tasks](../tasks_user_guide) — the deal tasks behind the Tasks Due and Tasks Overdue sections.
