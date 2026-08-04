# Cash Flow Assistant Agent — User Guide

The Cash Flow Assistant Agent is a rules-based (no AI involved) reporting tool that checks how up-to-date your fund data is, calculates each fund's cash position, runway, and recommended capital call, and emails a consolidated report to fund managers. It also has a secondary chat feature that lets users ask questions about the latest results in plain language.

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
9. [FAQ](#faq)

---

## 1. What This Agent Does

The agent runs at the entity level, then works through every fund listed in its setup. For each fund:

1. **Checks data freshness** — verifies the fund's cash account data and pending (not-yet-executed) investment data are recent enough. A fund whose cash data is older than its configured threshold, or has no cash data at all, is marked as "blocked" and excluded from the calculation for that run. This is a deliberate safeguard so that a runway or shortfall recommendation never gets calculated off stale numbers.
2. **Calculates the cash position**, for every fund that passed the freshness check:
   - **Cash available** — the most recent account balances tagged as "cash," added up across the fund's entity and any child entities (SPVs).
   - **Upcoming investments** — the total of any pending investments that haven't been executed yet.
   - **Estimated expenses** — a 90-day forward estimate built from account entries tagged as "expenses." The method used depends on how much history is available: 4 or more months of data uses a trend-based projection, 2–3 months uses a recency-weighted average, exactly 1 month simply repeats the most recent figure, and no historical data at all returns an estimate of zero with a "no data" flag.
   - **Buffer required** — the latest balance held in the reserve accounts.
   - **Net position** = cash available minus upcoming investments minus estimated expenses minus the required buffer.
   - **Runway (in days)** = cash available divided by the average daily outflow (investments plus expenses, spread over the 90-day window). Shown as "180+ days" in the email when there's no outflow at all to divide by.
   - **Status** — a fund is marked "shortfall" if its net position is negative, "watch" if its runway is under 90 days, and "surplus" otherwise.
   - **Recommended capital call** — for a fund in shortfall, this is the size of the gap plus the required buffer, i.e. enough to cover the shortfall and top the reserve back up.
3. **Generates reports** — saves a report for each fund, and for any fund that wasn't blocked, also saves a formatted report document into that fund's private Reports folder.
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
| Pending (not-yet-executed) investment records | Your existing deal data in CapHive |
| Each fund's entity and any child entities (SPVs) | Cash, investments, and expenses are added up across the fund's main entity and all of its child entities |

## 3. Enabling the Agent

Turned on or off using a feature toggle on the entity's Support Agents settings. An administrator enables it from **Admin → Edit Entity → Support Agents section**.

No AI provider key is required — this agent is fully rules-based (it just adds up account entries and runs the expense projection math); it never calls an AI model.

## 4. Accessing and Running the Agent

Open **AI → Support Agents → Cash Flow Assistant**. The standard "Run Now" button is available (shown once the feature is enabled for your entity, same as for any other agent) and runs the full check against every fund currently listed in its setup.

Configuration happens on the agent's **Edit** page, in the Funds & Staleness Thresholds table — add a fund row, pick the fund from the dropdown, set its two freshness thresholds (in days), and save. There's no "run for just one fund" option — a run always covers every fund currently listed there.

## 5. Scheduling

Supported through the standard **Schedule** tab on the agent's show page (this works the same way for every agent, not just this one) — set a frequency and time, turn it on, and save. Scheduled runs produce the same per-fund reports and email as a manual run.

There's also a separate daily reminder: every day, the system checks whether this agent's next scheduled run is coming up within the configured reminder lead time. If so, it emails the reminder recipients a preview of each fund's data freshness, so fund managers can fix any stale data *before* the real run happens and that fund ends up excluded.

## 6. Where to Find the Output

- **Fund Reports tab** on the agent's show page — lists the report for each fund from every run.
- **Each fund's private Reports folder** (Documents → that fund → Reports, private) — a "Cash Flow Analysis" report file is saved here for every fund that wasn't blocked. Running the agent again replaces this file rather than keeping multiple copies.
- **Consolidated email** — sent to everyone on the report recipients list. It shows an overall status banner (Action Required / Monitor / All Clear), a portfolio summary table (one row per fund: status, net position, runway, recommended action), and a detail section for each fund that was ready to calculate (cash available, upcoming investments, estimated expenses, buffer required, net position, and a cash breakdown by entity). Blocked funds show as dashes in the summary table with "Update stale data" as the suggested action.
- **Staleness reminder email** — sent separately to the reminder recipients ahead of the next scheduled run, listing each fund's freshness status and the specific reason it would be blocked (e.g. "Entity X: Cash data is 45 days old, maximum allowed is 30 days").
- **Chat assistant (secondary feature)** — when chat is enabled for this agent, a chat panel answers natural-language questions using the most recent completed report for each fund as its source of truth. It also has a built-in "what if" calculator for stress-testing scenarios (e.g. "what if we deploy more capital") and is designed to always use that calculator rather than try to work out hypothetical numbers on its own. Sample starter questions: "Which funds are running low?", "Show stale balances," "Recommend capital calls."

Nothing is ever written back to your account entries, investment records, or any other source data — this agent only reads and reports.

## 7. Understanding the Report

Each fund's report includes:

- **Status** — "ready" or "blocked" (the outcome of the freshness check).
- **Block reasons** — a plain-language list explaining exactly why a fund was blocked (e.g. stale cash data for a specific entity, stale pending-investment data for a specific entity).
- **Fund status** — "shortfall," "watch," or "surplus" (only shown for funds that were ready to calculate).
- The underlying figures: cash available, a per-entity cash breakdown with last-updated dates, upcoming investments and the list behind that total, estimated expenses and which estimation method was used, the monthly expense projections and how many data points fed them, buffer required, net position, runway in days, recommended capital call, and currency.

## 8. Where It Can Fail

- **The settings that actually drive the numbers have no on-screen panel.** Which account types count as "cash," "expenses," and "reserve buffer" must be set up before any of those figures can be anything other than zero — and there's no field for this anywhere in the product today; it has to be configured behind the scenes by CapHive. A fund manager who only fills in the Funds & Staleness Thresholds table will see every fund show zero cash available, zero estimated expenses (flagged "no data"), and zero buffer required — which can look like a perfectly healthy, fully reconciled fund rather than a sign that setup is incomplete.
- **Stale cash data quietly excludes the whole fund.** If even one of the fund's entities (including a child SPV) has no cash-tagged account data at all, or its most recent entry is older than the configured threshold, the entire fund is excluded from that run's calculation — there's no partial result. The same applies independently for stale pending-investment data.
- **Stale-but-plausible cash balances can still feed a misleading recommendation.** The freshness check only looks at how *recent* the latest data point is, not whether it's *accurate*. A fund can pass the freshness check on a balance that's recent but simply wrong, and still produce a shortfall or surplus recommendation that doesn't reflect reality.
- **A blank report recipients list skips the email.** The email step is just marked "skipped" in the run history — but the agent's page now shows a warning banner ahead of time whenever the recipient list is empty, so check there rather than the run history.
- **An empty fund list.** With no funds configured, the freshness check and the calculation both report zero funds processed, and the run completes "successfully" with nothing to show. The warning banner on the agent's page flags this state before you run.
- **The quality of the expense estimate depends entirely on how much history you have.** A fund with only one month of tagged expense data gets a flat repeat of that one figure for the entire 90-day forecast, with no sense of trend at all — while a brand-new fund with no historical expense data at all gets an estimate of exactly zero, which understates true expected spending until enough history builds up.
- **Combining a fund with its child entities assumes consistent tagging.** Cash, investment, and expense data is added up across the fund's main entity and every child entity; if account tagging is applied inconsistently between the parent and a child SPV, the combined total can double-count or miss a child's contribution with no visible warning.
- **The saved report file is replaced, not versioned.** Each new run deletes and replaces the existing "Cash Flow Analysis" file in the fund's Reports folder rather than keeping a history of past versions — only the report history list preserves the run-by-run record.

## FAQ

**Q: I ran the agent and every fund shows zero cash, zero expenses. What's wrong?**
A: Almost certainly the account-type settings for cash, expenses, and buffer haven't been set up yet. These have no on-screen field today — ask CapHive support or your administrator to confirm this configuration has been completed for your entity.

**Q: A fund I expected to see in the report is missing entirely.**
A: Check the Fund Reports tab for that fund's status — it's likely "blocked" due to stale cash or pending-investment data, which excludes it from the "ready" section of the email (it will still show in the summary table with dashes and "Update stale data").

**Q: I didn't get the consolidated email.**
A: The report recipients list is blank or hasn't been set up — there's no on-screen setting for this, so confirm with your admin or CapHive support that it's been configured.

**Q: Can I run this for just one fund?**
A: No — a run always processes every fund currently listed in the agent's configuration. To leave a fund out temporarily, remove its row from the Funds & Staleness Thresholds table on the Edit page.

**Q: How is the recommended capital call amount calculated?**
A: Only for funds in shortfall status — it's the absolute size of the shortfall plus the required buffer, i.e. enough to close the gap and restore the reserve to its target level.

**Q: What's the difference between the consolidated report email and the staleness reminder email?**
A: The consolidated report is the actual analysis, sent after a run completes. The staleness reminder is a separate, earlier heads-up sent automatically in the days before the *next scheduled run*, so stale data can be fixed proactively before that run happens and the fund ends up blocked.
