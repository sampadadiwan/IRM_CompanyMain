# RTA Reconciliation Agent — User Guide

The RTA Reconciliation Agent reconciles an uploaded RTA (Registrar and Transfer Agent) unit statement PDF — e.g. from CAMS or KFintech — against your fund's own unit records in CapHive. It checks for mismatches at the scheme (ISIN) level and at the individual folio level, flags folios in the statement that have no matching record in CapHive, and flags unit classes that CapHive holds but the statement never mentions.

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
| Statement date override | Date | (blank) | Overrides the statement period-end date that was pulled from the PDF. Use this when the RTA's date format is unusual and the automatic extraction gets it wrong. |

### Other data inputs

| Input | Source | Notes |
|---|---|---|
| RTA Statement PDF | Uploaded each time you run the agent, through the dedicated upload window — not through the agent's normal configuration page. | The only file input. There's no recurring or pre-attached statement; every run needs its own fresh upload. |
| Your fund's unit configuration | Existing CapHive data | Provides the ISIN that each unit type is matched against. |
| Your fund's investor holding records | Existing CapHive data | The unit count and folio number on file for each investor and unit type are the CapHive side of every comparison. |
| Your fund's unit activity ledger | Existing CapHive data | Used only for the movement check (subscriptions/redemptions over the period since the prior run). |
| The previous reconciliation report, if one exists | Stored automatically from prior runs | Anchors the movement check and the opening-balance continuity check. The very first run for a fund has neither available, so those two checks are skipped that time. |

## 3. Enabling the Agent

This agent is turned on or off using a feature toggle on the entity's Support Agents settings. An administrator enables it from **Admin → Edit Entity → Support Agents section**.

The agent uses AI to read the statement, so your entity needs at least one AI provider key configured (under **AI → Support Agents → LLM Keys**). There's also a per-agent **AI Model** setting on this agent's Edit page that, if filled in, overrides your entity's default model for this agent only.

The upload button that starts a run only appears once the feature toggle above is enabled, and only for users who have edit/update permission on the specific fund.

Note for administrators: this agent isn't assigned to one of the usual groupings (Ops/Finance/Portfolio/Onboarding), so on the agent index page it shows up under **Uncategorized**.

## 4. Accessing and Running the Agent

There's no generic "Run Now" button for this agent — running it always requires uploading a PDF, so it has its own dedicated upload window instead of the standard agent run screen.

1. Navigate to the **Fund's show page**.
2. If the feature is enabled for your entity and you have edit rights on the fund, a **Run RTA Reconciliation** button is available in the fund's action area.
3. The upload window asks for an **RTA Statement PDF** (PDF files only) — this is the only required field; there's no separate notes or context field.
4. Click **Run Reconciliation**.

Behind the scenes, the uploaded PDF is saved as a document on the fund (named "RTA Statement (PDF)") before the reconciliation actually starts running. That order matters in your favor: the PDF stays safely on file even if the reading step later fails or has to be retried.

The agent always runs against the one fund you triggered it from — there's no "run for every fund at once" option. Once you click Run, a live step-by-step progress panel appears, showing: Initialize → Fund Readiness → Parse Statement → Reconcile → Coverage Check → Pending Requests → Send Report → Save Report.

## 5. Scheduling

Not supported. There's no default schedule and no recurring-run option for this agent — reconciliation is inherently tied to a one-off statement upload, so you run it on demand each time a new statement arrives from your RTA.

## 6. Where to Find the Output

- **Reconciliation History tab** on the agent's own show page (**AI → Support Agents → RTA Reconciliation**) — lists every run across all of your funds, with a health score, scheme count, and folio-mismatch count per run. Expanding a row shows the full coverage breakdown (fund-wide → ISIN-configured → covered by this statement), per-scheme detail, folio-level mismatches, pending requests, folios missing from the statement, opening-balance continuity issues, and investor name mismatches.
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
- **Non-standard statement dates.** RTAs format dates inconsistently from one to the next. The agent does its best to interpret whatever date it found; if that fails, it falls back to storing the raw text, which then doesn't sort or compare reliably for the movement check. Use the **Statement date override** field to force the correct date when the automatic extraction gets it wrong.
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

## FAQ

**Q: I uploaded the PDF but the run says "No RTA statement PDF uploaded." What happened?**
A: This means the file didn't save properly before the run started, or the file you uploaded was empty. Double-check the file is a valid, non-empty PDF and try the upload again.

**Q: A folio shows as a mismatch even though the numbers look close to me. Why?**
A: Check both tolerance fields. The agent only treats a difference as a match if it's within the unit tolerance OR (if you've set one) the percentage tolerance — only when both are exceeded does it count as a mismatch. If the default unit tolerance of 0.01 is too tight for your RTA's typical rounding, raise it on the Edit page.

**Q: The statement date on the report looks wrong / doesn't match the PDF.**
A: RTAs use inconsistent date formats, and the automatic extraction can misread them. Set the **Statement date override** field on the Edit page to force the correct date for future runs against this fund.

**Q: A scheme in my PDF was skipped entirely with a "not found" warning.**
A: The ISIN in the statement doesn't match anything configured for this fund. Add or correct the ISIN under the fund's Unit Settings, then re-run.

**Q: Why didn't I get an email after the run?**
A: Either "Email report after run" is set to No, or the "Notify email" field is blank. Both need to be set together — check the agent's Edit page.

**Q: The movement/continuity sections are missing from my report.**
A: These require a prior reconciliation run for the same fund to anchor the comparison period. They'll start appearing from your fund's second reconciliation run onward.
