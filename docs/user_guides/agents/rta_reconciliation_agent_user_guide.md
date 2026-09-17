# RTA Reconciliation Agent — User Guide

The RTA Reconciliation Agent reconciles an uploaded RTA (Registrar and Transfer Agent) unit statement PDF — e.g. from CAMS or KFintech — against your fund's own unit records in CapHive. It checks for mismatches at the scheme (ISIN) level and at the individual folio level, flags folios in the statement that have no matching record in CapHive, and flags unit classes that CapHive holds but the statement never mentions.

> **Where to find it:** Sidebar → [**Funds → Funds**](/funds) → open the fund → **Actions → Misc → Run RTA Reconciliation** to upload the RTA statement PDF; results are on Company menu (house icon, top right) → [**Agents**](/support_agents) → **RTA Reconciliation** → **Reconciliation History**. Needs update permission on the fund, the `rta_reconciliation_agent` entity flag and an LLM key.

## Table of Contents

1. [What This Agent Does](#1-what-this-agent-does)
2. [Inputs](#2-inputs)
3. [Enabling the Agent](#3-enabling-the-agent)
4. [Accessing and Running the Agent](#4-accessing-and-running-the-agent)
5. [Scheduling](#5-scheduling)
6. [Where to Find the Output](#6-where-to-find-the-output)
7. [Understanding the Report](#7-understanding-the-report)
8. [Where It Can Fail](#8-where-it-can-fail)
9. [Frequently Asked Questions](#frequently-asked-questions)

---

## 1. What This Agent Does

The agent works on one Fund per run. When you upload a statement PDF, it:

1. **Checks fund readiness** — before even looking at the statement, it checks whether every unit type your fund actually holds (with a real, non-zero balance) has an ISIN set up against it. A unit type with real commitments but no ISIN configured can never be reconciled, no matter how good the statement is — this check exists to surface that gap up front, rather than let it hide inside a "clean" reconciliation.
2. **Reads the statement** — extracts the text from the PDF and uses AI to pull out one entry per scheme (each ISIN block): scheme name, ISIN, NAV, summary totals (opening/subscribed/redeemed/closing units), and a folio-by-folio breakdown (folio number, investor name, holding type, opening/closing units, pending requests).
3. **Reconciles each scheme found in the statement**:
   - **Summary check** — compares the RTA's total closing units for that scheme against the total units CapHive has on record for that unit type.
   - **Folio-level check** — compares each folio's closing units on the statement against the matching investor record in CapHive (matched by folio number and unit type).
   - **Movement check** — compares the subscriptions/redemptions the RTA reports for the period against CapHive's own unit activity over the same dates. This only runs once a previous reconciliation exists for the fund, since it needs that prior run to know where the period started.
   - **Opening balance continuity** — checks that this period's opening balance, as reported by the RTA, matches the closing balance the RTA reported last time for the same folio. This catches discrepancies that a closing-balance-only check could miss.
   - **Investor name check** — flags a folio where the folio number matches a CapHive record but the investor name on the statement differs from what's on file (ignoring case and extra spacing).
   - **Reverse check** — looks for investor holdings in CapHive with a real balance and a folio number that never shows up anywhere in the statement at all.
4. **Checks coverage fund-wide** — compares every ISIN your fund holds (that's properly configured with a non-zero balance) against which ISINs this particular statement actually covered. This is the only check that can catch a scheme the AMC forgot to send entirely, since the per-scheme checks above only ever look at ISINs the PDF actually mentions.
5. **Flags pending requests** — folios where the statement shows an in-flight subscription or redemption request are flagged as warnings, not as mismatches.
6. **Sends the report** — optionally emails the reconciliation summary.

## 2. Inputs

### Configuration fields (Edit page)

| Field | Type | Default | What it controls |
|---|---|---|---|
| Tolerance (units) | Number | `0.01` | The maximum difference in units (in absolute terms) per folio or summary that's still treated as a match. This accommodates the minor rounding you typically see in RTA PDFs. |
| Tolerance (%) | Number | `0` | The maximum percentage difference that's still treated as a match. A folio is only flagged as a mismatch if it fails **both** checks — see [Where It Can Fail](#8-where-it-can-fail) for exactly how this combines. Leave at 0 to rely on the unit tolerance alone (the default). |
| Flag pending requests | Select (Yes/No) | `Yes` | When set to Yes, folios where the statement shows a pending transaction (worded as "Pending TXN", "Outstanding Requests", etc.) are flagged as warnings — not as mismatches. |
| Email report after run | Select (Yes/No) | `Yes` | When set to Yes, the reconciliation summary is emailed to the address in "Notify email" after each run. |
| Notify email | Text | (blank) | The recipient for the reconciliation report email. Required when "Email report after run" is set to Yes. |
| Statement date override | Date | (blank) | Overrides the statement period-end date that was pulled from the PDF. Use this when the RTA's date format is unusual and the automatic extraction gets it wrong. It is a single agent-wide setting: it applies to every fund's run until you clear it. |

### Setup checklist and warnings

The agent's **General** tab shows a yellow warning banner whenever setup would undermine a run. For this agent it flags:

- **Both tolerance fields empty.** With neither set, tolerance is zero — every minor rounding difference in the RTA PDF is reported as a mismatch, drowning real breaks in noise.
- **"Email report after run" set to Yes with a blank Notify email** — the report would never be emailed.
- **Any unit type whose ISIN is not configured.** A unit type with no ISIN on its fund unit settings cannot be matched to any scheme in the statement, so its folios are invisible to every check. The banner names each affected unit type and fund.
- **Either Yes/No toggle that has never been given a value** — an unset toggle counts as off, which silently skips that behaviour.

### Other data inputs

| Input | Source | Notes |
|---|---|---|
| RTA Statement PDF | Uploaded each time you run the agent, through the dedicated upload window — not through the agent's normal configuration page. | The only file input. There's no recurring or pre-attached statement; every run needs its own fresh upload. |
| Your fund's unit configuration | Existing CapHive data | Provides the ISIN that each unit type is matched against. |
| Your fund's investor holding records | Existing CapHive data | The unit count and folio number on file for each investor and unit type are the CapHive side of every comparison. |
| Your fund's unit activity ledger | Existing CapHive data | Used only for the movement check (subscriptions/redemptions over the period since the prior run). |
| The previous reconciliation report, if one exists | Stored automatically from prior runs | Anchors the movement check and the opening-balance continuity check. The very first run for a fund has neither available, so those two checks are skipped that time. |

## 3. Enabling the Agent

This agent is turned on or off by the `rta_reconciliation_agent` support-agent flag on your entity, which only CapHive support can set.

The agent uses AI to read the statement, so your entity needs at least one AI provider key configured (under Company menu (house icon, top right) → **Agents** → [**LLM Keys**](/support_agents/llm_keys)). There's also a per-agent **AI Model** setting on this agent's Edit page that, if filled in, overrides your entity's default model for this agent only.

The **Run RTA Reconciliation** menu item that starts a run is shown only to users who have update permission on the specific fund; when the flag above is off it is greyed out with a lock.

Note for administrators: this agent isn't assigned to one of the usual groupings (Ops/Finance/Portfolio/Onboarding), so on the agent index page it shows up under **Uncategorized**.

## 4. Accessing and Running the Agent

Running it always requires uploading a PDF, so it has its own dedicated upload window instead of the standard agent run screen. The agent page's General tab does show the standard **Run Now** button, but it has no PDF to read: it runs over every fund and each one fails with "No RTA statement PDF uploaded", so don't use it.

1. Navigate to the **Fund's show page**.
2. If the feature is enabled for your entity and you have update rights on the fund, choose **Actions → Misc → Run RTA Reconciliation**.
3. The upload window asks for an **RTA Statement PDF** (PDF files only) — this is the only required field; there's no separate notes or context field.
4. Click **Run Reconciliation**.

Behind the scenes, the uploaded PDF is saved as a document on the fund (named "RTA Statement (PDF)") before the reconciliation actually starts running. That order matters in your favor: the PDF stays safely on file even if the reading step later fails or has to be retried.

The upload window always runs against the one fund you triggered it from — there's no working "run for every fund at once" option. Once you click Run, a live step-by-step progress panel appears, showing: Initialize → Fund Readiness → Parse Statement → Reconcile → Coverage Check → Pending Requests → Send Report → Save Report.

## 5. Scheduling

Not supported in practice. There's no default schedule, and although the agent page has the standard **Schedule** tab, a scheduled run has no PDF to read, just like **Run Now** — reconciliation is inherently tied to a one-off statement upload, so you run it on demand each time a new statement arrives from your RTA.

## 6. Where to Find the Output

- **Reconciliation History tab** on the agent's own show page (Company menu (house icon, top right) → [**Agents**](/support_agents) → **RTA Reconciliation**) — lists every run across all of your funds, with a health score, scheme count, and folio-mismatch count per run. Expanding a row shows the full coverage breakdown (fund-wide → ISIN-configured → covered by this statement), per-scheme detail, folio-level mismatches, pending requests, folios missing from the statement, opening-balance continuity issues, and investor name mismatches.
- **Email** — if "Email report after run" is set to Yes and "Notify email" is filled in, an HTML summary is sent to that address after each run. The email shows, per scheme: a banner with the mismatch count and an all-matched/health score indicator; a summary table (RTA units vs. CapHive units vs. difference vs. match/mismatch); a folio mismatch table when any exist; pending-request callouts; and a callout listing CapHive folios that are missing from the statement entirely.
- **Report history** — a new report is saved on every run (older runs are never overwritten), tied to the fund, and marked as Failed when any serious issue was found and Completed otherwise. Nothing is ever written back to your investor holding or unit activity records — this agent only compares and reports, it never changes your CapHive data.

## 7. Understanding the Report

Each report includes:

- **Health score** — the percentage of checks that passed cleanly. Only clean passes and serious mismatches count toward this score; warning-level issues (pending requests, folios missing from the statement, name mismatches, continuity issues) are excluded, so a run with no real mismatches scores 100% even if it has advisory warnings attached.
- **Scheme results** — one entry per ISIN found in the statement: whether the summary matched, the per-folio match/mismatch/unmatched status with RTA vs. CapHive units and the difference, folios on file that are missing from the statement, folios with pending requests, and the movement comparison (or blank if there's no prior run to anchor the period against).
- **Scheme coverage** — every ISIN your fund holds, and whether this statement covered it at all.
- **Unit readiness** — every unit type with a real balance, and whether it even has an ISIN configured (the fund-wide readiness check, independent of any statement).
- **Fund-wide rollup** — a summary across three layers, each a subset of the one before it: every unit type the fund holds, regardless of setup; the subset of those with an ISIN configured; and the subset of those that this specific statement actually covered. A gap between the first two layers points to a setup problem on your side; a gap between the last two points to an incomplete statement from the AMC.

## 8. Where It Can Fail

- **A folio only needs to pass one of the two tolerance checks, not both.** A folio or summary is treated as a match if it's close enough on *either* an absolute basis (the Tolerance in units) *or* a percentage basis (the Tolerance %) — it doesn't need to clear both bars. With the default setup (percentage tolerance at 0), only the absolute tolerance is actually active. If you turn on a percentage tolerance, this means a small fund with a sizeable percentage swing could still pass if the absolute unit gap is tiny, and a large fund with a tiny percentage swing could still pass even with a fairly large absolute gap. If matching feels too loose, tighten whichever of the two tolerances is letting too much through.
- **No PDF uploaded, or the PDF can't be read.** If no file was actually attached, or the file is empty, the run stops immediately with "No RTA statement PDF uploaded." If the PDF has no readable text at all (for example, it's a scanned image with no text layer), the run stops with "Could not read text from the uploaded PDF" — there's no fallback that can read text out of an image-only scan.
- **Non-standard statement dates.** RTAs format dates inconsistently from one to the next. The agent does its best to interpret whatever date it found; if that fails, it falls back to storing the raw text, which then doesn't sort or compare reliably for the movement check. Use the **Statement date override** field to force the correct date when the automatic extraction gets it wrong — and clear it afterwards, because it applies to every fund's run until removed.
- **The statement couldn't be understood, or came back malformed.** Both show up as a serious issue on the run ("no scheme data found" or "response wasn't valid"). A timeout or rate-limit hiccup from the AI provider is also caught and shown as a run issue rather than crashing the page.
- **Very long statements can get cut off.** Statement text is capped at 30,000 characters before being processed. Very large or multi-fund statements may have their tail end cut off, which can silently drop schemes or folios that appear later in the document.
- **Orphan ISINs.** If the PDF contains an ISIN that doesn't match any unit configuration on the fund, that whole scheme is skipped and shown as a warning rather than reconciled — its folios and units are reported as "orphan," but they're never actually checked against CapHive.
- **Unconfigured unit types.** A unit type with real, non-zero holdings but no ISIN set up at all is invisible to the per-scheme checks (it never even shows up in the statement comparison). The fund readiness check at the start of the run is the only thing that surfaces this — as a serious issue, regardless of what's in the statement you upload.
- **Folios in the statement that don't exist in CapHive ("unmatched").** These show up as mismatches that need attention. Common causes: a typo in the folio number on the AMC's statement, a folio that predates your CapHive records, or a unit-type mix-up (the same folio number reused across two different unit classes can resolve to the wrong investor record if the unit type doesn't line up).
- **Pending-transaction false positives or negatives.** The agent recognizes the common ways an RTA phrases "nothing pending" (None, Nil, NA, N/A, Not Applicable, a dash, or blank). A statement that phrases it differently (e.g. "Settled", "Processed") could be misread as an actual pending request, or the reverse, if the extraction normalizes it inconsistently.
- **Movement and continuity checks need a prior run to compare against.** The very first reconciliation for a fund has nothing to anchor against, so both checks are quietly skipped (not flagged as a problem) — don't expect this detail until the second run onward for a given fund.
- **A blank Notify email with "Email report after run" set to Yes.** The email step is simply skipped, with no error and no warning raised on that run — so a blank recipient field looks identical to everything working fine.
- **Running the agent twice in quick succession on the same fund.** Each run creates a new report rather than locking the fund while it works, so two uploads back-to-back for the same fund could overlap. Whichever run finishes and is marked "latest" is what the next run will anchor against, so overlapping runs can produce confusing movement/continuity results.
- **Investor name mismatches don't block the run.** They're shown only as warnings, even though they could point to a stale folio reassignment or two different investors sharing a folio number by coincidence.

## Frequently Asked Questions

### Navigation and getting there

**Where do I run the RTA Reconciliation Agent?**
From the fund: Sidebar → [**Funds → Funds**](/funds), open the fund, then **Actions → Misc → Run RTA Reconciliation**. This opens the **Run RTA Reconciliation** window where you upload the statement PDF. See [Accessing and Running the Agent](#4-accessing-and-running-the-agent).

**Where do I see past reconciliations?**
Company menu (house icon, top right) → [**Agents**](/support_agents) → **RTA Reconciliation** card → **Reconciliation History** tab. It lists every run across your funds with fund, statement date, AMC, health score, scheme count and run time, and each row expands to the full breakdown. See [Where to Find the Output](#6-where-to-find-the-output).

**Where do I change the agent's settings?**
Open the **RTA Reconciliation** card on the [**Agents**](/support_agents) page and click **Edit** on the **General** tab. Only a Company Admin can edit. The card sits under **Uncategorized** on the Agents page because the agent has no category.

**Run RTA Reconciliation is greyed out with a lock. Why?**
The `rta_reconciliation_agent` entity flag is off, so the item shows the tooltip "RTA Reconciliation Agent is disabled. Contact support to enable it". Only CapHive support can enable the flag.

**I can't see Run RTA Reconciliation in the Misc menu at all. Why?**
The item, locked or not, is only shown to users with update permission on the fund. Ask a fund admin for an access right on the fund with update permission.

**Where do I set the ISIN for a unit type?**
On the fund page choose **Actions → Fund Unit Settings**, edit the unit type and fill in **ISIN**. Every unit type with holdings needs one, or the readiness check blocks the run and its folios are never compared.

### Running and managing reconciliations

**How do I run a reconciliation?**
On the fund page choose **Actions → Misc → Run RTA Reconciliation**, pick the file under **RTA Statement PDF** (PDF only) and click **Run Reconciliation**. A progress panel then shows Initialize, Fund Readiness, Parse Statement, Reconcile, Coverage Check, Pending Requests, Send Report and Save Report.

**How do I set up the agent the first time?**
Ask CapHive support to enable the `rta_reconciliation_agent` flag, make sure an LLM key exists under [**Agents → LLM Keys**](/support_agents/llm_keys), click **Setup All Agents → Run Setup** on the [**Agents**](/support_agents) page, then set **Notify email** and check the tolerances on the agent's **Edit** page. See [Enabling the Agent](#3-enabling-the-agent).

**How do I change the matching tolerance?**
On the agent's **Edit** page set **Tolerance (units)** (default 0.01) and, if wanted, **Tolerance (%)** (default 0), then save. A difference within either tolerance counts as a match, and the settings apply to every fund's next run.

**How do I get the reconciliation emailed?**
Set **Email report after run** to Yes and enter a recipient in **Notify email** on the agent's **Edit** page. The HTML report then goes to that address after every run; with a blank address the email is skipped without warning.

**How do I correct the statement date?**
Enter the right date in **Statement date override** on the agent's **Edit** page and re-run. The override is agent-wide: it applies to every fund's run until you clear it, so blank it again afterwards.

**Can I delete a reconciliation report?**
No. Reports cannot be deleted from the UI, and every run adds a new one. The uploaded PDF is saved on the fund as a document named "RTA Statement (PDF)" and can be managed like any other fund document.

**Can I schedule the agent or run it for all funds?**
No schedule is created, because each run needs a freshly uploaded statement, and the upload window works on one fund at a time. **Run Now** on the agent's **General** tab has no PDF to read, so every fund it touches is reported as "No RTA statement PDF uploaded"; always start runs from the fund page. See [Scheduling](#5-scheduling).

### Why use RTA reconciliation

**Why should I use the RTA Reconciliation Agent?**
The RTA (CAMS, KFintech) is the official register of units, and any difference from CapHive's unit records means a statement, an allotment or an investor record is wrong. Checking a multi-scheme PDF folio by folio by hand is slow and error-prone; the agent does it in one run and lists only the breaks.

**What does it let me do that I could not do otherwise?**
It checks every scheme's totals and every folio's closing units within a tolerance, spots folios the RTA has that CapHive does not (and the reverse), detects schemes the statement left out, flags pending requests and investor-name differences, and from the second run checks movements and opening-balance continuity.

**Who typically uses it?**
Fund operations and compliance teams who receive periodic RTA statements for a unitised fund, typically monthly or after each allotment, and controllers who sign off that the unit register agrees with CapHive.

**What happens if I don't reconcile with the RTA?**
Nothing in CapHive changes, but unit differences go unnoticed until an investor statement, audit or redemption exposes them. Unit types without an ISIN also stay hidden, because only this agent's readiness check reports them.

### What happens when I...

**What happens when I click Run Reconciliation?**
The PDF is saved on the fund as "RTA Statement (PDF)", a background job reads it with AI and runs every check, and a new report is saved and marked latest for that fund. You get an in-app alert when it finishes, the report appears on **Reconciliation History**, and the email goes to **Notify email** if enabled.

**Does the agent change my unit or investor records?**
No. It only reads fund unit settings, holdings and unit activity and writes its own report; units, folios, investor names and commitments are never changed, and no investor is contacted. Fix breaks yourself, then re-run.

**What happens to earlier reports when I re-run?**
They are kept. The new report becomes the latest one for that fund, and the next run uses it as the starting point for the movement and opening-balance continuity checks.

**What happens if a unit type has holdings but no ISIN?**
The readiness check records a blocking issue naming the unit type, folio count and units, so the report is marked Failed even if the statement itself matches. Add the ISIN under **Fund Unit Settings** and re-run.

**What happens if the statement contains an ISIN the fund does not have?**
That scheme is skipped as an orphan and shown as a warning; its folios and units are listed but never compared with CapHive. Add or correct the ISIN on the matching unit type and re-run.

**What does a Failed report mean?**
At least one blocking issue was found: no or unreadable PDF, no scheme data extracted, a unit type without an ISIN, or similar. Warnings such as pending requests, name mismatches or missing folios do not fail a run on their own.

### Troubleshooting and edge cases

**I uploaded the PDF but the run says "No RTA statement PDF uploaded." What happened?**
The file did not reach the run or was empty. Check that it is a valid, non-empty PDF and upload again from the fund page; runs started with **Run Now** on the Agents page always show this message.

**The run says "Could not read text from the uploaded PDF". Why?**
The PDF has no text layer, typically a scanned image. There is no OCR fallback, so ask the RTA for a text-based (downloaded, not scanned) statement.

**A folio shows as a mismatch even though the numbers look close to me. Why?**
A difference only counts as a match when it is within **Tolerance (units)** or, if set, **Tolerance (%)**; a mismatch means both were exceeded. If the default 0.01 units is too tight for your RTA's rounding, raise it on the **Edit** page.

**The statement date on the report looks wrong / doesn't match the PDF.**
RTAs format dates inconsistently and the extraction can misread them. Set **Statement date override** on the **Edit** page, re-run, and clear it afterwards because it applies to every fund.

**A scheme in my PDF was skipped entirely with a "not found" warning.**
The statement's ISIN does not match any unit type configured for this fund. Add or correct the ISIN under **Actions → Fund Unit Settings**, then re-run.

**Why didn't I get an email after the run?**
Either **Email report after run** is No or **Notify email** is blank; both must be set on the agent's **Edit** page. A sending error is recorded as a warning on the report.

**The movement/continuity sections are missing from my report.**
They need a previous reconciliation for the same fund to anchor the period, so they appear from the fund's second run onward.

**Schemes near the end of a long statement are missing. Why?**
Statement text is cut at 30,000 characters before the AI reads it, so the tail of a very long or multi-fund PDF can be dropped. Ask the RTA for one statement per fund, or split the PDF and run each part.

**I ran two statements back-to-back and the continuity results look odd.**
Runs are not locked per fund, so two overlapping runs can both anchor on the same earlier report. Wait for one run to finish before starting the next.

## Related Guides

- [Fund Units](../fund_units_user_guide) — the unit holdings and activity the statement is compared against.
- [Support Agents](../support_agents_user_guide) — the Agents page, setup, LLM keys and run panels.
- [LLM Configuration](../llm_configuration_guide) — the provider key used to read the statement PDF.
- [Fund Unit Transfers](../fund_unit_transfers_user_guide) — transfers that change folio balances between statements.
- [Capital Commitments](../capital_commitments_user_guide) — folio numbers and investor records matched by the agent.
- [Remittance Reconciliation Agent](remittance_reconciliation_agent_user_guide) — reconciling bank statements against a capital call.
