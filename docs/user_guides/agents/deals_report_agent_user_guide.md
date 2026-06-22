# Deals Report Agent — User Guide

The Deals Report Agent looks across a fund's open deals and produces a fundraising status report for each one — committed vs. target amounts, fill rate, activity-step distribution, top investors, and staleness — then emails a consolidated summary to whoever you've configured to receive it.

## Table of Contents

1. [What This Agent Does](#1-what-this-agent-does)
2. [Inputs](#2-inputs)
3. [Enabling the Agent](#3-enabling-the-agent)
4. [Accessing and Running the Agent](#4-accessing-and-running-the-agent)
5. [Scheduling](#5-scheduling)
6. [Where to Find the Output](#6-where-to-find-the-output)
7. [Understanding the Report](#7-understanding-the-report)
8. [Where It Can Fail](#8-where-it-can-fail)
9. [FAQ](#faq)

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
| Schedule (frequency/day/time/timezone/enabled) | Form controls | weekly, 10:00, UTC, enabled | Sets up the agent's recurring schedule directly from this same page. |

**Important — this is the single most important thing to know about this agent.** Saving this panel always sets the deal scope to **just the current deal you're viewing**. There's no control on this panel to build a list of several deals, or to clear the scope back to "all open deals." By default — before this panel has ever been saved — the agent covers every open deal in your fund. But the moment anyone opens a deal's Agent Settings tab and saves it (even just to update the recipient list), the report quietly narrows down to that one deal only, with no warning that this happened. If you need the report to go back to covering all open deals, or to cover a specific custom set of deals, that currently requires admin or engineering help working directly with the underlying record — there's no in-app way to do either of those today.

The actual settings stored behind the scenes are:

- The deal scope — comma-separated deal IDs, or blank for "all open deals."
- The recipient list — comma-separated email addresses.
- The staleness threshold — a day count (falls back to 30 if not set at all).
- The five section toggles — each defaulting to on.

Other things the agent looks at (not settings you configure): each open deal's investors (active, pending, or declined), each investor's committed amount, the deal's target amount, the pipeline template steps used to build the step distribution, and the most recent activity update tied to any investor (used to determine staleness).

## 3. Enabling the Agent

1. An administrator turns on the **Deals Report Agent** toggle for your organization from **Admin → Edit Entity → Support Agents**.
2. No AI provider key is required — this agent never calls the AI.
3. The Deal page's "Agent Settings" tab is available to any user with permission to edit that deal — it's **not** gated by the organization-wide toggle the way the agent's own Run Now button is. The organization toggle still controls whether the agent shows as enabled under **AI → Support Agents** and whether its own Run Now button there is active.

## 4. Accessing and Running the Agent

**From the Deal page (the supported path today):**
1. Open any deal → **Agent Settings** tab.
2. Set recipients, the staleness threshold, the content toggles, and the schedule.
3. Click **Run Now** to open the confirmation prompt, or just let the schedule handle it.

Because this agent always runs at the organization level and works through deals internally, triggering it from any single deal's page still produces a report covering whichever deals are currently in scope — which, per the note above, may have already been narrowed down to just that one deal the last time someone saved that panel.

**From AI → Support Agents:** open the Deals Report Agent card and click **Run Now** from the General tab.

**What you'll see while it runs:** this agent always runs in the background without a live, step-by-step progress panel, because it's working through multiple deals internally rather than one target with visible steps. You'll see a "queued" notice rather than a step tracker.

## 5. Scheduling

Unlike the Deal Management Agent and Presentation Analyst, this agent does **not** come with a pre-built schedule out of the box. The only place a schedule actually gets created is the Deal page's **Agent Settings** tab — saving that form is what creates (or updates) the schedule, defaulting to weekly at 10:00 UTC, and saving the form is also what turns it on. If nobody has ever opened that tab and saved it, this agent has no schedule at all and will only run when someone clicks Run Now.

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
| Target / committed / pending / declined / remaining amounts | Fundraising amounts in dollars. |
| Fill rate | Committed amount divided by target amount, as a percentage rounded to one decimal place. Shows 0.0% if there's no target set. |
| Total / active / pending / declined investor counts | Investor counts broken out by status. |
| Stale, no-activity days, last activity date | Whether the deal has exceeded the no-activity threshold, the actual day count, and the timestamp of the most recent linked activity. The day count is blank if there's never been any activity at all. |
| Step distribution | How many investors sit at each pipeline step, in order. Empty if the deal has no pipeline template steps defined. |
| Top investors | Up to 10 active investors sorted by committed amount, each with name, status, tier, amount, and current pipeline step. |

## 8. Where It Can Fail

- **Deals you've listed that no longer exist or aren't open are silently dropped, not flagged as errors.** If a deal in your configured list has been deleted, belongs to a different fund, or is no longer open, it just disappears from the results with no warning. If that leaves zero deals to report on, the agent records that as "no open deals found" rather than a failure, and the rest of the run still proceeds — meaning you'd get zero deal reports and likely a near-empty email.
- **The Deal page panel silently narrows the report scope to one deal every time it's saved.** This is the most likely real-world surprise: someone opens the Agent Settings tab on Deal A just to tweak the recipient list, saves it, and without realizing it, scopes the entire fund-wide report down to Deal A only. Anyone relying on "all open deals" coverage should know this and avoid saving that panel unless they actually intend to narrow the scope — or have it reset back to "all deals" afterward by an admin.
- **There's no UI for choosing a specific handful of deals.** The agent technically supports a custom multi-deal list, but the only panel that touches this setting is the single-deal Agent Settings tab, which always writes exactly one deal id. Setting up a genuine custom subset has to be done directly on the underlying record by someone with admin/engineering access.
- **No schedule comes pre-built for this agent.** Unlike the other two agents in this set, don't assume a disabled schedule is already waiting for you to switch on. Check the Deal page's Agent Settings tab — if it's never been saved, there is no schedule at all yet.
- **Leaving the recipient list blank silences the email** — reports still get generated and saved per deal, but nobody is notified.
- **No AI dependency, but document-save failures are handled gracefully per deal.** If saving the HTML report into a deal's Reports folder hits an error, it's caught and logged, and the run moves on to the next deal — that deal's report still saves even if its HTML document doesn't.
- **Staleness is based purely on activity-step updates** — not notes, not document uploads, not other interactions. A deal where documents are actively being uploaded but no activity steps have changed can still get flagged as stale.

## FAQ

**Q: I want this report to cover all our open deals, but it only seems to include one. Why?**
A: Most likely someone saved the Agent Settings tab from a single deal's page, which always resets the scope to just that deal. An admin can reset the scope back to "all open deals," and it's worth avoiding re-saving that per-deal panel unless you actually intend to narrow the scope.

**Q: Where do I configure which deals are included, beyond "all" or "this one deal"?**
A: There's currently no in-app field for a custom multi-deal list. The agent can support it, but the only panel that touches this setting is the single-deal Agent Settings tab, which always writes exactly one deal. A genuine custom subset requires direct admin/engineering help.

**Q: The agent ran but I didn't get an email.**
A: Check the recipient list on the Deal page's Agent Settings tab — if it's blank, no email goes out, even though the per-deal reports were still generated and saved.

**Q: Does this agent need an AI provider key?**
A: No. All the numbers (fill rate, staleness, step distribution, top investors) are calculated directly from your deal, investor, and activity data — no AI involved.

**Q: I enabled the organization-wide toggle but nothing runs automatically. What's missing?**
A: Unlike the Deal Management Agent and Presentation Analyst, this agent ships with no schedule already set up. You need to open a deal's Agent Settings tab, configure the schedule fields, and save — that's what actually creates the schedule in the first place.
