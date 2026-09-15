# Data Quality Agent — User Guide

The Data Quality Agent runs nightly integrity checks across every fund's financial data — looking for commitments that have collected more than was committed, valuations that have gone stale, and FX rates that haven't been refreshed — then emails a health score and a fix-it list to the people you've configured to receive it. It checks every fund in your entity in one pass, and is built for Company Admins and fund operations teams who want an early warning before bad data reaches LPs or shows up in reporting.

> **Where to find it:** Company menu (house icon, top right) → [**Agents**](/support_agents) → **Data Quality** card. Run it with **Run Now** on the **General** tab, or let its nightly schedule run it; change checks and recipients with **Edit**. Needs the *Data Quality Agent* support-agent flag on your entity (set by CapHive support) and the **Company Admin** role.

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

The agent always checks every fund that belongs to your entity. You run it from the entity level (there's no per-fund trigger), and it automatically expands that into a check across all of your funds in a single run — but the results are still broken out per fund, so each fund gets its own email and its own score.

**What happens when it runs, in order:**

1. **Gets started** — sets up trackers to collect both the overall results and each fund's individual results.
2. **Checks for commitment overflows** — for each fund, looks for any commitment whose collected amount is greater than its committed amount.
3. **Checks for stale valuations** — for each fund, looks at every portfolio company and flags any that don't have a valuation dated within your configured freshness window.
4. **Checks for stale FX rates** — looks at the entity's exchange rates (these are shared across all funds, not specific to one) and flags any whose latest record hasn't been updated (by record update time, not rate date) within your configured window. Because FX rates aren't tracked per fund, the same result shows up on every fund's report.
5. **Calculates a health score** — this always runs, with no on/off switch; it's a simple calculation based on the results of the checks above.
6. **Sends the report** — if this option is turned on and recipients are configured, sends one quality report email per fund. With no recipients the step is skipped.
7. **Saves the report** — stores the results of the run. This agent always finishes in a "ready" state.

**No AI/LLM setup needed.** Every check here is a straightforward comparison against your data — nothing requires an AI model to run.

---

## 2. Inputs

### Configuration fields (Edit page)

| Field | Type | Default | What it controls |
|---|---|---|---|
| Check commitment overflows | Select (Yes/No) | Yes | When set to Yes, the agent checks for commitments that have collected more than their committed amount. When set to No, this check is skipped and left out of the health score entirely. |
| Check missing/stale valuations | Select (Yes/No) | Yes | When set to Yes, the agent checks portfolio company valuations against your freshness window. When set to No, this check is skipped and left out of the health score. |
| Check stale FX rates | Select (Yes/No) | Yes | When set to Yes, the agent checks exchange rates against your freshness window. When set to No, this check is skipped and left out of the health score. |
| Email quality report after each run | Select (Yes/No) | Yes | When set to Yes, sends one email per fund with that fund's results. When set to No, no email goes out, but the checks still run and each run is logged in Execution History. |
| Stale valuation threshold (days) | Number | 90 | Portfolio companies are flagged if their most recent valuation is older than this many days. |
| Stale FX rate threshold (days) | Number | 30 | Exchange rates are flagged if they haven't been updated within this many days. |
| Report recipient email(s) | Text | blank | Comma-separated addresses that receive the email report. If you leave this blank, no report email is sent to anyone. |

### Setup checklist and warnings

An unset Yes/No toggle counts as **off**, not on — if a toggle was never given a value (common on agents set up before the option existed), that check is silently skipped. The agent's **General** tab shows a yellow warning banner whenever setup needs attention. For this agent it flags:

- **Any of the four toggles that has never been set.** Set each explicitly to Yes or No — an explicit No is respected and not flagged.
- **All three data checks turned off.** The agent would report a perfect 100% health score having checked nothing at all.
- **A threshold field that is present but blank.** A blank value is treated as 0 days — every valuation or FX rate would be flagged stale. Enter a number of days or remove the value.

### Other things that feed into the run

- **Which funds get checked**: every fund belonging to the entity — there's currently no way to exclude a specific fund from these checks.
- **Commitments**: each fund's full list of capital commitments is checked for overflows.
- **Portfolio companies**: identified through each fund's portfolio investments, then checked against their recorded valuations.
- **FX rates**: the entity's shared exchange rate records — these apply identically across all funds, since they aren't fund-specific.
- **No AI/LLM key required.**

---

## 3. Enabling the Agent

- **Where it's switched on**: the *Data Quality Agent* support-agent flag on your entity, which only CapHive support can set.
- **The agent's own Enabled box**: if **Enabled** is unticked on the agent's **Edit** page, a run stops right after the Initialize step and no check runs.
- **AI key needed?** No.
- **Who can manage it**: only Company Admin users can set up, configure, or run this agent.

If the agent isn't enabled for your entity, the **Run Now** button on its page is disabled, with a tooltip pointing you to your administrator.

---

## 4. Accessing and Running the Agent

1. Open the Company menu (house icon, top right) → [**Agents**](/support_agents).
2. Run **Setup All Agents** once if this is the first time agents have been provisioned for your entity — this creates the agent's default settings and daily schedule.
3. Click the **Data Quality** card to open its page.
4. On the **General** tab, click **Run Now**.

There's no per-fund trigger button — you always run this against the entity as a whole, and it automatically fans out to check every fund. After clicking **Run Now**, the check runs in the background with a live progress panel: a batch panel counting through the funds when your entity has several, or the step-by-step panel when it has only one.

---

## 5. Scheduling

The agent comes with a default daily schedule, set up automatically by **Setup All Agents**: it runs once a day at **01:00 Asia/Kolkata** — deliberately scheduled for off-hours, after most of the day's data entry is done. You can adjust the frequency, time, or notification preferences from the agent's **Schedule** tab. Scheduled runs produce the same kind of reports and emails as a manual run.

---

## 6. Where to Find the Output

- **Execution History tab** — every past run, with its status, how long it took, the number of funds processed or failed, and links to those funds. The fix-it lists and health scores are not shown in the app; the email is the only place they appear.
- **Email** — one per fund, with a subject line like "Data Quality Report — <Fund Name> (<health score>%)". Each email includes:
  - The fund's health score as a percentage.
  - A pass/fail/skipped breakdown for each of the three checks, scoped to that fund.
  - The detailed fix-it lists for that fund (commitment issues, valuation issues, FX issues), each naming the affected record and explaining why it was flagged.
  - Recipients: whoever is set in "Report recipient email(s)"; if that's blank, no email is sent. If your entity is in sandbox mode, the email goes to the entity's sandbox addresses instead.

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
| Recipient field left blank with email sending turned on | "Report recipient email(s)" is empty and "Email quality report after each run" is Yes | No report email goes to anyone — the Send Report step is skipped with "No recipients configured", and there is no fallback to employees. The findings are not visible anywhere else in the app. | Enter the recipient addresses on the **Edit** page. |
| Commitment check can be slow on funds with many LPs | A fund has a very large number of commitments | The check pulls in all of that fund's commitment records to evaluate them, rather than filtering at the database level — this isn't a correctness issue, but it can make the run noticeably slower on funds with thousands of LPs. | No action needed; just be aware that a run may take longer on your largest funds. |
| Stale valuation threshold edge case | A valuation is dated exactly at the cutoff (e.g., exactly 90 days old) | The freshness window includes the cutoff date itself, so a valuation dated exactly on the boundary still counts as current, not stale. | If you want stricter staleness checking, lower the threshold by one day. |
| Stale FX check applies the same result to every fund | Multi-currency entity with several funds sharing one set of exchange rates | The same stale-FX findings and pass/fail outcome show up identically on every fund's report — a rate that really only affects one fund's currency mix will still appear on all of them. | This is expected, since FX rates aren't tracked per fund. Don't assume a fund-specific cause if you see the same FX result repeated across several funds' reports. |
| Fund has no portfolio companies linked | A fund with no portfolio investments recorded | There's nothing for the valuation check to evaluate, so it passes by default — not because the data is good, but because there was nothing to check. | If a fund shows "All valuations current" but doesn't actually have any portfolio companies linked yet, double-check that its portfolio investments are set up correctly rather than taking the pass at face value. |
| Running the agent more than once in a day | Manual Run Now triggered shortly after the scheduled 01:00 run | There's no deduplication — each run starts fresh and, if email sending is on, sends a brand-new report email per fund every time. Running it twice in one day means recipients get two emails. | Avoid manually re-running on a day the schedule already fired, unless you've just fixed something and want an updated score — otherwise expect duplicate emails. |
| Schedule timezone confusion | Schedule set to 01:00 Asia/Kolkata | The run fires at 01:00 in whatever timezone is configured — which could be midday or evening for an admin viewing from elsewhere. | Check the timezone shown on the **Schedule** tab — it's independent of your own local timezone. |

---

## 9. Frequently Asked Questions

### Navigation and getting there

**Where do I find the Data Quality Agent in CapHive?**
Open the Company menu (house icon, top right) → [**Agents**](/support_agents) and click the **Data Quality** card in the **Ops** group. Its page has **General**, **Schedule** and **Execution History** tabs.

**The Agents item in the Company menu is greyed out with a lock. Why?**
No support agent is enabled for your entity, so the item is locked with the tooltip "AI Agents are disabled. Contact support to enable it". Ask CapHive support to enable the *Data Quality Agent* flag.

**Is there a Data Quality button on the fund page?**
No. This agent has no in-context launch button; you run it only from its own page with **Run Now**, or let the schedule run it. Each run always covers every fund in your entity.

**Where do I change the checks, thresholds and recipients?**
Open the agent and click **Edit**. The fields are **Check commitment overflows**, **Check missing/stale valuations**, **Check stale FX rates**, **Email quality report after each run**, the two threshold fields and **Report recipient email(s)**. See [Inputs](#2-inputs).

**Where do I see the results of a run?**
In the per-fund email "Data Quality Report — Fund Name (score%)" sent to the recipients, which holds the health score and fix-it lists. In the app, the **Execution History** tab shows each run's status, duration, funds processed and links to those funds, but not the fix-it lists.

**Who can see and use this agent?**
Only users with the **Company Admin** role see it on the [Support Agents](/support_agents) page and can edit, run, schedule or delete it. Another company admin grants the role from Company menu → [**User**](/users) → open the user → **Edit**.

### Creating, updating and managing the agent

**How do I create the Data Quality Agent?**
On Company menu → **Agents**, click **Setup All Agents** and **Run Setup**. It creates the agent with every toggle set to Yes, thresholds of 90 and 30 days, a blank recipient field and a daily 01:00 Asia/Kolkata schedule.

**How do I choose who receives the report?**
Enter comma-separated addresses in **Report recipient email(s)** on the **Edit** page and save. The field starts blank, and while it is blank no report email is sent to anyone.

**How do I turn a check on or off?**
Set its Yes/No field on the **Edit** page and save. A check set to No is skipped and left out of the health score; a field never set counts as No and is flagged in the yellow banner on the **General** tab.

**How do I change the staleness thresholds?**
Edit **Stale valuation threshold (days)** (default 90) or **Stale FX rate threshold (days)** (default 30) and save. Never leave a threshold present but empty: blank means 0 days and flags everything as stale.

**How do I run it now?**
Open the agent's **General** tab, click **Run Now** and confirm. With several funds a batch progress panel counts through them; with a single fund the step panel shows each check. See [Accessing and Running the Agent](#4-accessing-and-running-the-agent).

**How do I change or pause the nightly schedule?**
Use the **Schedule** tab: change **Frequency**, **Run At** or **Timezone** and **Save Schedule**, or untick **Enable scheduled runs for this agent** to pause. Manual **Run Now** still works while the schedule is off. See [Scheduling](#5-scheduling).

**How do I stop the emails without stopping the checks?**
Set **Email quality report after each run** to No, or clear **Report recipient email(s)**. The checks still run and Execution History still logs each run.

**Can I delete the agent?**
**Delete** on the General tab only works for an agent that has never run; once it has reports or execution logs the delete is blocked. Pause the schedule instead.

**What permissions and flags are needed?**
The *Data Quality Agent* flag on your entity (set by CapHive support) and the **Company Admin** role. No LLM key or AI model is used.

### Why use the Data Quality Agent

**Why should I use the Data Quality Agent?**
It catches three silent data problems before they reach LP statements, NAV or reporting: commitments that collected more than was committed, portfolio companies without a recent valuation, and exchange rates nobody has refreshed. Checking them by hand means opening every commitment, company and rate.

**What does it let me do that I cannot do otherwise?**
It gives each fund a single health score and a named fix-it list, every night, without anyone remembering to look. No standard CapHive screen cross-checks all funds for these conditions at once.

**Who typically uses it?**
Fund operations and finance teams who own ledger and valuation data, and Company Admins who want an early warning before quarter-end reporting. The recipients are usually the people who can fix the flagged records.

**What happens if I don't set it up or leave recipients blank?**
Without the agent nobody is warned, so an over-collected commitment or a stale FX rate surfaces only when an LP or auditor spots it. With the agent but no recipients, runs still execute nightly but no one receives the findings.

### What happens when I…

**What happens when I click Run Now?**
A background job checks each fund separately, saves a report per fund, and adds one **Execution History** row marked Manual with your name. If emailing is on and recipients are set, each fund's email is sent immediately. You get an in-app summary alert when the run finishes; no data is changed.

**What happens during the nightly scheduled run?**
The same checks run for every fund at the **Run At** time, logged in **Execution History** as Scheduled. Your team is emailed about the run itself only if they are in **Notification Recipients** on the **Schedule** tab (failure and partial success by default), separately from the quality report email.

**What happens when a check finds a problem?**
The check is marked failed for that fund, lowering its health score, and the fund's email lists each flagged commitment, company or currency pair with a reason such as "No valuation in the last 90 days". Nothing is corrected automatically, and the run still finishes as ready.

**How is the health score calculated?**
It is the percentage of switched-on checks that passed for that fund, rounded: two of three passing gives 67%. Skipped checks are ignored, and with all checks off the score is 100%. See [Understanding the Report](#7-understanding-the-report).

**What happens when I save the Edit page?**
The new toggles, thresholds and recipients apply from the next run, manual or scheduled. Emails already sent are not changed, and the yellow banner re-checks the setup when you reopen the **General** tab.

**Who is emailed, and what if my entity is in sandbox mode?**
Each fund's report goes to the addresses in **Report recipient email(s)**; investors are never emailed. If sandbox is on for your entity, the email goes to the entity's sandbox addresses instead.

**Can I undo a run?**
There is nothing to undo, because the agent only reads data. Emails already sent cannot be recalled, and each new run overwrites that fund's saved report.

**What happens when I untick Enabled on the Edit page?**
Runs stop right after the Initialize step: no check runs and no email is sent. Tick **Enabled** again and save to resume.

### Troubleshooting and edge cases

**My fund shows 100% health score but I know there's a problem. Why?**
Check whether all three checks are set to No, or were never set. With no active checks the score is 100% automatically, which does not mean the data was verified; the **General** tab banner warns about this.

**I left "Report recipient email(s)" blank. Who gets the report?**
No one. The Send Report step is skipped with "No recipients configured"; there is no fallback to employees. Enter the addresses on the **Edit** page.

**The agent ran but no email arrived for one of my funds.**
Check that **Email quality report after each run** is Yes and **Report recipient email(s)** is filled in, and whether sandbox mode redirected the email. Then check **Execution History** to confirm that fund was processed.

**A portfolio company's valuation is from yesterday but it's still flagged as stale. Is that a bug?**
Check that the valuation is recorded against the portfolio company with a **valuation date** inside **Stale valuation threshold (days)**; the check reads the valuation date, not when the record was entered. Also make sure the threshold field is not blank, which means 0 days.

**Every valuation and FX rate is flagged as stale. Why?**
A threshold field is present but empty, which counts as 0 days. Enter a number of days on the **Edit** page; the yellow banner names the blank field.

**An LP is flagged for overflow but has not been called beyond the commitment. Why?**
The check compares the commitment's collected amount with its committed amount, not the called amount. Look for duplicate or misallocated remittance payments on that commitment. See [Capital Commitments](../capital_commitments_user_guide).

**Why do all my funds show the same FX result?**
Exchange rates are entity-wide, so the same stale pairs appear on every fund's email. A rate counts as stale when its latest record has not been updated within the threshold; refresh it under Company menu → [**Exchange Rates**](/exchange_rates).

**A fund with no portfolio companies passes the valuation check. Is that right?**
Yes. There is nothing to evaluate, so the check passes by default. Confirm the fund's portfolio investments are recorded before trusting the pass.

**Does this agent ever block anything, like other agents do?**
No. It always finishes as ready whatever the health score, and it never stops a call, distribution or report. The score and fix-it list only inform you.

**Why did recipients get two emails today?**
Each run sends a fresh email per fund, so a manual **Run Now** on the same day as the scheduled run doubles up. Avoid re-running unless you have fixed something and want an updated score.

**Run Now is greyed out. Why?**
The *Data Quality Agent* flag is not enabled for your entity, and the card shows **Disabled**. Only CapHive support can enable it.

---

## Related Guides

- [Support Agents](../support_agents_user_guide) — setup, Run Now, schedules, Execution History and the warning banner shared by every agent.
- [Capital Commitments](../capital_commitments_user_guide) — the committed and collected amounts behind the overflow check.
- [Valuations](../valuations_user_guide) — recording the portfolio company valuations the stale-valuation check looks for.
- [Portfolio Investments](../portfolio_investments_user_guide) — how a fund's portfolio companies are linked, which decides what gets checked.
- [Tracking Currency](../tracking_currency_guide) — multi-currency funds and exchange rates.
- [Cash Flow Assistant Agent](cash_flow_assistant_agent_user_guide) — fund liquidity checks that rely on the same ledger data.
- [E-Sign Monitor Agent](esign_monitor_agent_user_guide) — another deterministic nightly monitor.
