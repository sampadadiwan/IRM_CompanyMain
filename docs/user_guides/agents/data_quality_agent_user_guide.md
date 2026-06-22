# Data Quality Agent — User Guide

The Data Quality Agent runs nightly integrity checks across every fund's financial data — looking for commitments that have collected more than was committed, valuations that have gone stale, and FX rates that haven't been refreshed — then emails a health score and a fix-it list to the people you've configured to receive it. It checks every fund in your entity in one pass, and is built for Company Admins and fund operations teams who want an early warning before bad data reaches LPs or shows up in reporting.

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

The agent always checks every fund that belongs to your entity. You run it from the entity level (there's no per-fund trigger), and it automatically expands that into a check across all of your funds in a single run — but the results are still broken out per fund, so each fund gets its own email and its own score.

**What happens when it runs, in order:**

1. **Gets started** — sets up trackers to collect both the overall results and each fund's individual results.
2. **Checks for commitment overflows** — for each fund, looks for any LP that's been called for more money than they actually committed.
3. **Checks for stale valuations** — for each fund, looks at every portfolio company and flags any that don't have a valuation dated within your configured freshness window.
4. **Checks for stale FX rates** — looks at the entity's exchange rates (these are shared across all funds, not specific to one) and flags any that haven't been refreshed within your configured window. Because FX rates aren't tracked per fund, the same result shows up on every fund's report.
5. **Calculates a health score** — this always runs, with no on/off switch; it's a simple calculation based on the results of the checks above.
6. **Sends the report** — if this option is turned on, sends one quality report email per fund.
7. **Saves the report** — stores the results of the run. This agent always finishes in a "ready" state.

**No AI/LLM setup needed.** Every check here is a straightforward comparison against your data — nothing requires an AI model to run.

---

## 2. Inputs

### Configuration fields (Edit page)

| Field | Type | Default | What it controls |
|---|---|---|---|
| Check commitment overflows | Select (Yes/No) | Yes | When set to Yes, the agent checks for LPs called beyond their committed amount. When set to No, this check is skipped and left out of the health score entirely. |
| Check missing/stale valuations | Select (Yes/No) | Yes | When set to Yes, the agent checks portfolio company valuations against your freshness window. When set to No, this check is skipped and left out of the health score. |
| Check stale FX rates | Select (Yes/No) | Yes | When set to Yes, the agent checks exchange rates against your freshness window. When set to No, this check is skipped and left out of the health score. |
| Email quality report after each run | Select (Yes/No) | Yes | When set to Yes, sends one email per fund with that fund's results. When set to No, no email goes out, but the report is still saved and viewable in the app. |
| Stale valuation threshold (days) | Number | 90 | Portfolio companies are flagged if their most recent valuation is older than this many days. |
| Stale FX rate threshold (days) | Number | 30 | Exchange rates are flagged if they haven't been updated within this many days. |
| Report recipient email(s) | Text | blank | Who receives the email report. If you leave this blank, the report goes to every active employee in your entity instead. |

### Other things that feed into the run

- **Which funds get checked**: every fund belonging to the entity — there's currently no way to exclude a specific fund from these checks.
- **Commitments**: each fund's full list of capital commitments is checked for overflows.
- **Portfolio companies**: identified through each fund's portfolio investments, then checked against their recorded valuations.
- **FX rates**: the entity's shared exchange rate records — these apply identically across all funds, since they aren't fund-specific.
- **No AI/LLM key required.**

---

## 3. Enabling the Agent

- **Where it's switched on**: Admin → Edit Entity → Support Agents section. A Company Admin checks the "Data Quality" box and saves.
- **AI key needed?** No.
- **Who can manage it**: only Company Admin users can set up, configure, or run this agent.

If the agent isn't enabled for your entity, the **Run Now** button on its page is disabled, with a tooltip pointing you to your administrator.

---

## 4. Accessing and Running the Agent

1. Navigate to **AI → Support Agents**.
2. Run **Setup All Agents** once if this is the first time agents have been provisioned for your entity — this creates the agent's default settings and daily schedule.
3. Click the **Data Quality** card to open its page.
4. On the **General** tab, click **Run Now**.

There's no per-fund trigger button — you always run this against the entity as a whole, and it automatically fans out to check every fund. After clicking **Run Now**, the check runs in the background; there's no live, step-by-step progress view for this agent — the result appears once the run finishes.

---

## 5. Scheduling

The agent comes with a default daily schedule, set up automatically by **Setup All Agents**: it runs once a day at **01:00 Asia/Kolkata** — deliberately scheduled for off-hours, after most of the day's data entry is done. You can adjust the frequency, time, or notification preferences from the agent's **Schedule** tab. Scheduled runs produce the same kind of reports and emails as a manual run.

---

## 6. Where to Find the Output

- **General tab → "View Report" link** — the most recent run's combined results across all funds.
- **Execution History tab** — every past run, with its status and how long it took.
- **Email** — one per fund, with a subject line like "Data Quality Report — <Fund Name> (<health score>%)". Each email includes:
  - The fund's health score as a percentage.
  - A pass/fail/skipped breakdown for each of the three checks, scoped to that fund.
  - The detailed fix-it lists for that fund (commitment issues, valuation issues, FX issues), each naming the affected record and explaining why it was flagged.
  - Recipients: whoever is set in "Report recipient email(s)", or — if that's blank — every active employee in the entity.

---

## 7. Understanding the Report

**The health score** is the percentage of your *active* (i.e., switched-on) checks that came back clean. There are at most three checks — commitment overflows, missing valuations, and stale FX rates — and each can be turned on or off independently.

**This has one important quirk worth knowing about:** if you turn off all three checks, the score will show **100%** — not because your data is clean, but because nothing was actually checked. A fund with every check disabled looks "perfectly healthy" on paper, when in reality it simply wasn't verified at all. Don't read a 100% score as "all clear" unless you can confirm at least one check is switched on. This score is calculated twice — once as an overall figure across all funds, and again separately for each fund's individual email — so in a multi-fund entity, different funds can show different scores even though something like FX staleness is identical across all of them (since FX rates are shared, not fund-specific).

Each check comes back as one of three outcomes:
- **Pass** — no issues found for that check.
- **Fail** — one or more issues found; the relevant fix-it list is populated with the affected records and the reason each was flagged.
- **Skipped** — the check's toggle is set to No; it's left out of the health score entirely, neither helping nor hurting it.

This agent doesn't have a "blocked" outcome — it always finishes as "ready," even with a 0% health score. The score itself is the signal you should be watching, not the report's overall status.

---

## 8. Where It Can Fail

| Scenario | Trigger | What you'll see | What to do |
|---|---|---|---|
| All three checks turned off | "Check commitment overflows," "Check missing/stale valuations," and "Check stale FX rates" all set to No | Every fund shows a **100%** health score, even though nothing was actually checked. | Don't disable all three checks if you want a meaningful score. Re-enable at least one — and remember that a 100% score only means something if you know which checks were actually running. |
| No funds in the entity yet | New entity, or one with no funds set up | Nothing to check; every step reports zero issues, a 100% score, and no emails go out. | Expected — there's nothing to flag yet. Confirm in Execution History that the run completed rather than assuming it's broken. |
| Recipient field left blank with email sending turned on | "Report recipient email(s)" is empty and "Email quality report after each run" is Yes | The report goes out to **every active employee** in the entity, including people who may not want operational emails, such as read-only viewers. | Fill in the recipient field explicitly if you don't want a blast to your entire active employee list. |
| Commitment check can be slow on funds with many LPs | A fund has a very large number of commitments | The check pulls in all of that fund's commitment records to evaluate them, rather than filtering at the database level — this isn't a correctness issue, but it can make the run noticeably slower on funds with thousands of LPs. | No action needed; just be aware that a run may take longer on your largest funds. |
| Stale valuation threshold edge case | A valuation is dated exactly at the cutoff (e.g., exactly 90 days old) | The freshness window includes the cutoff date itself, so a valuation dated exactly on the boundary still counts as current, not stale. | If you want stricter staleness checking, lower the threshold by one day. |
| Stale FX check applies the same result to every fund | Multi-currency entity with several funds sharing one set of exchange rates | The same stale-FX findings and pass/fail outcome show up identically on every fund's report — a rate that really only affects one fund's currency mix will still appear on all of them. | This is expected, since FX rates aren't tracked per fund. Don't assume a fund-specific cause if you see the same FX result repeated across several funds' reports. |
| Fund has no portfolio companies linked | A fund with no portfolio investments recorded | There's nothing for the valuation check to evaluate, so it passes by default — not because the data is good, but because there was nothing to check. | If a fund shows "All valuations current" but doesn't actually have any portfolio companies linked yet, double-check that its portfolio investments are set up correctly rather than taking the pass at face value. |
| Running the agent more than once in a day | Manual Run Now triggered shortly after the scheduled 01:00 run | There's no deduplication — each run starts fresh and, if email sending is on, sends a brand-new report email per fund every time. Running it twice in one day means recipients get two emails. | Avoid manually re-running on a day the schedule already fired, unless you've just fixed something and want an updated score — otherwise expect duplicate emails. |
| Schedule timezone confusion | Schedule set to 01:00 Asia/Kolkata | The run fires at 01:00 in whatever timezone is configured — which could be midday or evening for an admin viewing from elsewhere. | Check the timezone shown on the **Schedule** tab — it's independent of your own local timezone. |

---

## FAQ

**Q: My fund shows 100% health score but I know there's a problem. Why?**
A: Check whether all three checks are turned off in the settings — a fund with every check disabled scores 100% automatically, since there's nothing active to fail. It doesn't mean the underlying data was actually verified as clean.

**Q: I left "Report recipient email(s)" blank. Who gets the report?**
A: Every active employee in the entity. If you only want specific people to see it, fill in that field explicitly.

**Q: The agent ran but no email arrived for one of my funds.**
A: First check that "Email quality report after each run" is set to Yes. If it is, and your entity has zero active employees and a blank recipient field, there's simply no one configured to receive it.

**Q: A portfolio company's valuation is from yesterday but it's still flagged as stale. Is that a bug?**
A: No — check the configured "Stale valuation threshold (days)." The valuation has to be within that window to count as current, not just recent in absolute terms.

**Q: Does this agent ever block anything, like other agents do?**
A: No. It always finishes as "ready," regardless of the health score. The score and fix-it list are there to inform you — nothing about this agent prevents an action from proceeding based on what it finds.
