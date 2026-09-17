# Cash Flow Assistant Agent — User Guide

The Cash Flow Assistant Agent is a rules-based reporting tool (no AI model is used to produce the report) that checks how up-to-date your fund data is, calculates each fund's cash position, runway, and recommended capital call, and emails a consolidated report to fund managers. It also has an optional, AI-powered chat feature that lets users ask questions about the latest results in plain language.

> **Where to find it:** Company menu (house icon, top right) → [**Agents**](/support_agents) → **Cash Flow Assistant** card. Configure the fund list on its **Edit** page, run it with **Run Now** on the **General** tab, and read results on the **Fund Reports** tab. Needs the *Cash Flow Assistant Agent* support-agent flag on your entity (set by your CapHive administrator) and the **Company Admin** role.

This guide covers the main reporting pipeline. The chat assistant is described briefly in [Section 6](#6-where-to-find-the-output).

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

The agent runs at the entity level, then works through every fund listed in its setup. For each fund:

1. **Checks data freshness** — verifies the fund's cash account data and pending (not-yet-executed) investment data are recent enough. A fund whose cash data is older than its configured threshold or missing, or that has a proforma investment created longer ago than its proforma threshold, is marked as "blocked" and excluded from the calculation for that run. This is a deliberate safeguard so that a runway or shortfall recommendation never gets calculated off stale numbers.
2. **Calculates the cash position**, for every fund that passed the freshness check:
   - **Cash available** — the most recent account balances tagged as "cash," added up across the fund's entity and any child entities (SPVs).
   - **Upcoming investments** — the total of the proforma (not-yet-executed) portfolio investments of the fund and its child entities.
   - **Estimated expenses** — a 90-day forward estimate built from account entries tagged as "expenses." The method used depends on how much history is available: 4 or more months of data uses a trend-based projection, 2–3 months uses a recency-weighted average, exactly 1 month simply repeats the most recent figure, and no historical data at all returns an estimate of zero with a "no data" flag.
   - **Buffer required** — the latest balance held in the reserve accounts.
   - **Net position** = cash available minus upcoming investments minus estimated expenses minus the required buffer.
   - **Runway (in days)** = cash available divided by the average daily outflow (investments plus expenses, spread over the 90-day window). Shown as "180+ days" in the email when there's no outflow at all to divide by.
   - **Status** — a fund is marked "shortfall" if its net position is negative, "watch" if its runway is under 90 days, and "surplus" otherwise.
   - **Recommended capital call** — for a fund in shortfall, this is the size of the gap plus the required buffer, i.e. enough to cover the shortfall and top the reserve back up.
3. **Generates reports** — saves (or overwrites) one report per fund, and for any fund that wasn't blocked, also saves a formatted report document into that fund's private Reports folder.
4. **Sends an email** — a single consolidated report covering all configured funds is emailed to everyone on the recipient list.

## 2. Inputs

### Configuration fields

This agent does **not** have a standard settings form like most other agents. Configuration happens in two different ways:

| Field | What it controls | Where it's set | Default |
|---|---|---|---|
| Funds & staleness thresholds | Which funds the agent processes, and how stale their data is allowed to be before that fund is excluded ("blocked"). | A dedicated table on the agent's Edit page — pick a fund per row, set its cash and pending-investment freshness thresholds, add or remove rows. | One row per existing fund, with a 30-day threshold for cash data and a 90-day threshold for pending investment data. |
| Which account types count as "cash" | Determines which account entries are added up for the cash-available figure and checked for the freshness gate. | **Not exposed in any on-screen setting today.** Has to be set up behind the scenes by CapHive on your behalf. | None set by default. |
| Which account types count as "expenses" | Determines which account entries feed the 90-day expense estimate. | Not exposed on screen today — same as above. | None set by default. |
| Which account types count as the "reserve buffer" | Determines which account entries count toward the required reserve. | Not exposed on screen today — same as above. | None set by default. |
| Report recipients | Who receives the consolidated cash flow email after each run. | Not exposed on screen today — same as above. | None set by default. |
| Reminder recipients | Who receives the staleness-reminder email (see [Scheduling](#5-scheduling)) ahead of a scheduled run. | Not exposed on screen today — same as above. | None set by default. |
| Reminder lead time | How many days before the next scheduled run the staleness reminder starts firing. | Not exposed on screen today — same as above. | 7 days. |

Because the "cash," "expenses," "reserve buffer," and "report recipients" settings have no on-screen panel anywhere in the product today, you can't get meaningful output from this agent through the standard interface alone — only the fund list and freshness thresholds are something you can configure yourself. Until CapHive sets up those other fields behind the scenes for you, every fund will show zero cash, zero expenses, and zero buffer, which can look like a clean bill of health rather than a sign that setup is incomplete.

### Setup checklist and warnings

Incomplete setup is no longer invisible: the agent's **General** tab shows a yellow warning banner whenever any of the following is true, and each item explains what will (or won't) happen until it's fixed:

- **No funds configured** — the agent would analyse nothing and still report success.
- **A configured fund no longer exists** (for example it was deleted or moved) — that row silently drops out of every run.
- **The "cash" account types are not set** — every fund would be reported blocked with a misleading "no cash data" message.
- **No report recipients** — the consolidated email would never be sent.

A clean General tab means the run will produce real numbers and the email will go out.

### Other data inputs

| Input | Source |
|---|---|
| Account entries (cash, expense, and buffer categories) | Your existing fund and entity ledger data in CapHive |
| Pending (not-yet-executed) investment records | Proforma Portfolio Investments of the fund and its child entities |
| Each fund's entity and any child entities (SPVs) | Cash, investments, and expenses are added up across the fund's main entity and all of its child entities |

## 3. Enabling the Agent

Turned on or off by the *Cash Flow Assistant Agent* support-agent flag on your entity. Only a CapHive administrator can set this flag; ask CapHive support to enable it.

No AI provider key is required for the report pipeline — it is fully rules-based (it just adds up account entries and runs the expense projection math) and never calls an AI model. Only the optional chat assistant calls the agent's AI Model and needs an LLM key.

## 4. Accessing and Running the Agent

Open the Company menu (house icon, top right) → [**Agents**](/support_agents) → **Cash Flow Assistant** card. The standard "Run Now" button is available (shown once the feature is enabled for your entity, same as for any other agent) and runs the full check against every fund currently listed in its setup.

Configuration happens on the agent's **Edit** page, in the Funds & Staleness Thresholds table — add a fund row, pick the fund from the dropdown, set its two freshness thresholds (in days), and save. There's no "run for just one fund" option — a run always covers every fund currently listed there.

## 5. Scheduling

Supported through the standard **Schedule** tab on the agent's show page (this works the same way for every agent, not just this one) — set a frequency and time, turn it on, and save. Scheduled runs produce the same per-fund reports and email as a manual run.

There's also a separate daily reminder: every day, the system checks whether this agent's next scheduled run is coming up within the configured reminder lead time. If so, it emails the reminder recipients a preview of each fund's data freshness, so fund managers can fix any stale data *before* the real run happens and that fund ends up excluded.

## 6. Where to Find the Output

- **Fund Reports tab** on the agent's show page — lists one report per fund; each run overwrites that fund's report with the latest figures.
- **Each fund's private Reports folder** (Documents → that fund → Reports, private) — a "Cash Flow Analysis" report file is saved here for every fund that wasn't blocked. Running the agent again replaces this file rather than keeping multiple copies.
- **Consolidated email** — sent to everyone on the report recipients list. It shows an overall status banner (Action Required / Monitor / All Clear), a portfolio summary table (one row per fund: status, net position, runway, recommended action), and a detail section for each fund that was ready to calculate (cash available, upcoming investments, estimated expenses, buffer required, net position, and a cash breakdown by entity). Blocked funds show as dashes in the summary table with "Update stale data" as the suggested action.
- **Staleness reminder email** — sent separately to the reminder recipients ahead of the next scheduled run, listing each fund's freshness status and the specific reason it would be blocked (e.g. "Entity X: Cash 45d old (max 30d)").
- **Chat assistant (secondary feature)** — when chat is enabled for this agent, a chat panel answers natural-language questions using the most recent completed report for each fund as its source of truth (blocked funds are left out). It calls the agent's AI Model, so it needs a saved LLM key. It also has a built-in "what if" calculator for stress-testing scenarios (e.g. "what if we deploy more capital") and is designed to always use that calculator rather than try to work out hypothetical numbers on its own. Sample starter questions: "Which funds are running low?", "Show stale balances," "Recommend capital calls."

Nothing is ever written back to your account entries, investment records, or any other source data — this agent only reads and reports.

## 7. Understanding the Report

Each fund's report includes:

- **Status** — "ready" or "blocked" (the outcome of the freshness check).
- **Block reasons** — a plain-language list explaining exactly why a fund was blocked (e.g. missing or stale cash data for a specific entity, or a specific proforma investment created longer ago than the proforma threshold).
- **Fund status** — "shortfall," "watch," or "surplus" (only shown for funds that were ready to calculate).
- The underlying figures: cash available, a per-entity cash breakdown with last-updated dates, upcoming investments and the list behind that total, estimated expenses and which estimation method was used, the monthly expense projections and how many data points fed them, buffer required, net position, runway in days, recommended capital call, and currency.

## 8. Where It Can Fail

- **The settings that actually drive the numbers have no on-screen panel.** Which account types count as "cash," "expenses," and "reserve buffer" must be set up before any of those figures can be anything other than zero — and there's no field for this anywhere in the product today; it has to be configured behind the scenes by CapHive. A fund manager who only fills in the Funds & Staleness Thresholds table will see every fund show zero cash available, zero estimated expenses (flagged "no data"), and zero buffer required — which can look like a perfectly healthy, fully reconciled fund rather than a sign that setup is incomplete.
- **Stale cash data quietly excludes the whole fund.** If even one of the fund's entities (including a child SPV) has no cash-tagged account data at all, or its most recent entry is older than the configured threshold, the entire fund is excluded from that run's calculation — there's no partial result. The same applies independently when any proforma investment of the fund was created more than **Proforma Max Days** ago (one block reason per such investment) — this is based on the investment's creation date, not on when it was last updated.
- **Stale-but-plausible cash balances can still feed a misleading recommendation.** The freshness check only looks at how *recent* the latest data point is, not whether it's *accurate*. A fund can pass the freshness check on a balance that's recent but simply wrong, and still produce a shortfall or surplus recommendation that doesn't reflect reality.
- **A blank report recipients list skips the email.** The email step is just marked "skipped" in the run history — but the agent's page now shows a warning banner ahead of time whenever the recipient list is empty, so check there rather than the run history.
- **An empty fund list.** With no funds configured, the freshness check and the calculation both report zero funds processed, and the run completes "successfully" with nothing to show. The warning banner on the agent's page flags this state before you run.
- **The quality of the expense estimate depends entirely on how much history you have.** A fund with only one month of tagged expense data gets a flat repeat of that one figure for the entire 90-day forecast, with no sense of trend at all — while a brand-new fund with no historical expense data at all gets an estimate of exactly zero, which understates true expected spending until enough history builds up.
- **Combining a fund with its child entities assumes consistent tagging.** Cash, investment, and expense data is added up across the fund's main entity and every child entity; if account tagging is applied inconsistently between the parent and a child SPV, the combined total can double-count or miss a child's contribution with no visible warning.
- **The saved report file is replaced, not versioned.** Each new run deletes and replaces the existing "Cash Flow Analysis" file in the fund's Reports folder rather than keeping a history of past versions, and the per-fund report on the Fund Reports tab is overwritten the same way — previous figures survive only in the emails already sent.

---

## 9. Frequently Asked Questions

### Navigation and getting there

**Where do I find the Cash Flow Assistant Agent in CapHive?**
Open the Company menu (house icon, top right) → [**Agents**](/support_agents) and click the **Cash Flow Assistant** card in the **Ops** group, or its **View Details** link. The agent page has **General**, **Schedule**, **Execution History** and **Fund Reports** tabs.

**The Agents item in the Company menu is greyed out with a lock. Why?**
No support agent at all is enabled for your entity, so the menu item is locked with the tooltip "AI Agents are disabled. Contact support to enable it". Ask CapHive support to enable the *Cash Flow Assistant Agent* flag for your entity.

**Who can open, configure and run this agent?**
Only users with the **Company Admin** role see the agent on the [**Agents**](/support_agents) page, and only they can **Edit**, **Run Now**, schedule or **Delete** it. A company admin grants the role from Company menu → [**User**](/users) → open the user → **Edit**.

**Where do I configure which funds the agent checks?**
On the agent page click **Edit** and scroll to **Cash Flow Assistant Configuration → Funds & Staleness Thresholds**. Each row is one fund with its **Cash Max Days** and **Proforma Max Days**; use **+ Add Fund** or the red **x** to add or remove rows, then **Save**. See [Inputs](#2-inputs).

**Where do I read the results?**
The **Fund Reports** tab on the agent page shows one row per fund with status, net position, runway and suggested action, and a **Details** button for the full breakdown. Ready funds also get a "Cash Flow Analysis" file in the fund's private **Reports** folder, and the consolidated email goes to the report recipients. See [Where to Find the Output](#6-where-to-find-the-output).

**How do I open the chat assistant for this agent?**
Tick **Enable Chat Assistant** on the agent's **Edit** page and save. A "Need help? Ask Cash Flow Assistant" bubble then appears at the bottom right of the agent page; it answers from the latest completed fund reports and needs an AI Model with a saved LLM key.

### Creating, updating and managing the agent

**How do I create the Cash Flow Assistant Agent?**
A company admin opens Company menu → **Agents**, clicks **Setup All Agents** and then **Run Setup**, which creates the **Cash Flow Assistant** with an empty configuration. Alternatively use **New Support Agent → CashFlowAssistantAgent** on the same page.

**How do I add or remove a fund, or change its freshness thresholds?**
Open **Edit**, change the rows in **Funds & Staleness Thresholds** (fund dropdown, **Cash Max Days**, **Proforma Max Days**) and click **Save**. Only funds of your own entity are listed, and a blank threshold falls back to 30 days for cash and 90 days for proforma investments.

**What happens the first time I open the Edit page?**
If no funds are configured yet, the table is pre-filled with every fund in your entity at 30 / 90 days. Clicking **Save** stores all of those rows, so remove the funds you do not want monitored before saving.

**How do I set the cash, expense and buffer account types or the email recipients?**
You cannot from the screen today: `cash_tags`, `expense_tags`, `buffer_tags`, `report_recipients`, `reminder_recipients` and `reminder_days_before_run` have no field on the Edit page. Ask CapHive support to set them; saving the Edit form later keeps them, because the form merges into the existing configuration.

**How do I run the agent now?**
Open the agent's **General** tab, click **Run Now** and confirm "Run Cash Flow Assistant now?". The run always covers every fund in the configuration; there is no single-fund run. See [Accessing and Running the Agent](#4-accessing-and-running-the-agent).

**How do I schedule it?**
On the **Schedule** tab tick **Enable scheduled runs for this agent**, pick a frequency (daily, weekly, monthly, bimonthly, quarterly or half-yearly), **Run On**, **Run At** and **Timezone**, then **Save Schedule**. An active schedule is also what triggers the staleness reminder email. See [Scheduling](#5-scheduling).

**How do I pause or delete the agent?**
To pause, untick **Enable scheduled runs for this agent** on the **Schedule** tab and save; that also stops the reminder emails. **Delete** on the General tab only succeeds for an agent that has never run, because its reports and execution logs block the delete.

**What permissions and flags does it need?**
The *Cash Flow Assistant Agent* support-agent flag on your entity (only CapHive support can set it) and the **Company Admin** role. The report pipeline needs no LLM key; only the optional chat assistant does.

### Why use the Cash Flow Assistant

**Why should I use the Cash Flow Assistant?**
It turns ledger balances, proforma investments and expense history into one cash position per fund: net position, runway in days, and the capital call needed to cover a shortfall and refill the reserve. Doing that by hand means pulling account entries for the fund and every child SPV and projecting expenses yourself.

**What does it let me do that I cannot do otherwise?**
It flags shortfall and watch funds across your whole portfolio in one email, refuses to calculate on stale cash data, and recommends a call size. The chat assistant also runs "what if" stress scenarios on the latest figures, which no standard fund screen does.

**Who typically uses it?**
Fund managers and finance or treasury teams who plan capital calls and watch fund liquidity, usually on a weekly or monthly schedule. A company admin sets it up once.

**What happens if the configuration is incomplete?**
With no funds it analyses nothing and still reports success; with no `cash_tags` every fund is blocked with "No cash data"; with no `report_recipients` the email step is skipped. The yellow banner on the **General** tab lists each of these gaps, so clear it before relying on a run.

### What happens when I…

**What happens when I click Run Now?**
A background job runs six steps (Initialize, Staleness Check, Cash Flow Calc, Generate Reports, Send Email, Save Report) with a live progress panel, and an **Execution History** row is added as a manual run with your name. You get an in-app alert when it completes or fails. No account entry, investment or other source data is changed.

**What happens to a fund whose data is stale?**
It is marked blocked with a reason per entity, such as "No cash data for Entity X" or "Entity X: Cash 45d old (max 30d)", and gets no calculation and no report file. It shows as **BLOCKED** with "Update stale data" on the **Fund Reports** tab and in the email, and it is left out of the chat assistant's data.

**What counts as stale?**
Cash is stale when the fund or any child entity has no cash-tagged fund account entry, or its latest one is older than **Cash Max Days**. Proforma is stale when any proforma portfolio investment of the fund was created more than **Proforma Max Days** ago; each such investment adds its own block reason.

**What happens when a fund passes the freshness check?**
Its cash available, upcoming proforma investments, 90-day expense estimate, buffer, net position, runway and recommended call are calculated, its report on the **Fund Reports** tab is overwritten, and a "Cash Flow Analysis" HTML file replaces the previous one in the fund's private **Reports** folder. See [Understanding the Report](#7-understanding-the-report).

**Who gets the report email, and when?**
The addresses in `report_recipients` get one consolidated email, queued at the Send Email step of every manual or scheduled run. The subject is "Cash Flow Update - Month Year", with "- Action Required" added when any fund is in shortfall; no investor is ever emailed.

**What happens when the staleness reminder fires?**
Every night at 01:30 CapHive checks each enabled Cash Flow Assistant with an active schedule; if its next run is within `reminder_days_before_run` days (default 7), the `reminder_recipients` get an email listing each fund's freshness and block reasons. Nothing is sent if there are no reminder recipients or no active schedule.

**What happens when I save the Edit page?**
The fund list and thresholds are stored and used from the next run; existing fund reports keep their old figures until then. Configuration keys set by CapHive support, such as the tags and recipients, are kept.

**Can I undo a run?**
There is nothing to undo in your data, because the agent only reads it. Each run does overwrite the per-fund report and replace the "Cash Flow Analysis" file, so the previous figures are not kept anywhere except the email already sent.

**What happens when I cancel a run?**
Clicking **Cancel** in the progress panel marks the run's report as cancelled with who and when. The background job is not stopped, so fund reports, files and the email may still be produced.

### Troubleshooting and edge cases

**Every fund shows zero cash, zero expenses and zero buffer. Is my fund healthy?**
Not necessarily. Zero usually means the cash, expense or buffer account types were never configured, or the tags do not match your account entry types. Check the yellow banner on the **General** tab and ask CapHive support to set the tags. See [Where It Can Fail](#8-where-it-can-fail).

**Every fund is blocked with "No cash data". What should I check?**
Either `cash_tags` is blank, or the fund or one of its child SPVs has no fund-level account entry with one of those entry types. One entity without cash data blocks the whole fund.

**Run Now is greyed out. Why?**
The *Cash Flow Assistant Agent* flag is not enabled for your entity and the card shows **Disabled**. Only CapHive support can enable it.

**The run completed but no email arrived. Why?**
`report_recipients` is empty, so the Send Email step was skipped; the **General** tab banner says so. Otherwise open **Execution History**, expand the run and check the Send Email step's recipient count, then the recipients' spam folders.

**Every fund was blocked. How does the run show that?**
The Staleness Check step is marked failed and the progress panel ends as blocked, although **Execution History** still lists the run as completed. If at least one fund was ready the run ends as ready, and the blocked funds show individually as **BLOCKED** on the **Fund Reports** tab.

**A fund I configured has disappeared from the reports. Why?**
The fund was deleted or moved to another entity, so its row is silently skipped. The **General** tab banner lists the missing fund ids; remove or correct the row on the **Edit** page.

**Why is the expense estimate zero or flat?**
It depends on history of expense-tagged entries: none gives zero, one month repeats that month, 2 to 3 months use a weighted average, and 4 or more months a trend projection. A new fund therefore understates expenses until history builds up.

**Why does runway say "180+ days"?**
There are no upcoming proforma investments and no estimated expenses, so there is no outflow to divide by. Status is then **Surplus** unless the net position is negative.

**Does the chat assistant use live data?**
No. It answers from the most recent completed fund reports, so re-run the agent first if balances have changed. For "what if" questions it must use its stress-scenario tool rather than compute numbers itself.

**Does the agent create the recommended capital call?**
It recommends a call size but never creates a capital call. Create the call yourself from the fund's **Calls** tab; see [Capital Calls](../capital_calls_user_guide).

## Related Guides

- [Support Agents](../support_agents_user_guide) — setup, Run Now, schedules, Execution History and the warning banner shared by every agent.
- [Capital Calls](../capital_calls_user_guide) — raising the call the agent recommends for a fund in shortfall.
- [Portfolio Investments](../portfolio_investments_user_guide) — proforma investments that feed "upcoming investments" and the proforma freshness check.
- [Document Management](../document_management_user_guide) — the fund's private Reports folder where the "Cash Flow Analysis" file is saved.
- [LLM Configuration](../llm_configuration_guide) — the AI key the optional chat assistant needs.
- [Data Quality Agent](data_quality_agent_user_guide) — catches ledger and data gaps that make cash figures unreliable.
- [Distribution Readiness Agent](distribution_readiness_agent_user_guide) — the pre-flight check before money goes out of a fund.
