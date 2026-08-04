# Distribution Readiness Agent — User Guide

The Distribution Readiness Agent is a rule-based, step-by-step agent in the **Finance** category. It checks that every prerequisite is in place — investor KYC, computed payment amounts, generated and approved notices, and bank details — before a capital distribution payment goes out. Fund operations teams run it on a capital distribution immediately before wiring funds.

## Table of Contents

1. [What This Agent Does](#1-what-this-agent-does)
2. [Inputs](#2-inputs)
3. [Enabling the Agent](#3-enabling-the-agent)
4. [Accessing and Running the Agent](#4-accessing-and-running-the-agent)
5. [Where to Find the Output](#5-where-to-find-the-output)
6. [Understanding the Report](#6-understanding-the-report)
7. [Where It Can Fail](#7-where-it-can-fail)
8. [FAQ](#8-faq)

---

## 1. What This Agent Does

The agent works through a fixed checklist against every payment on a single capital distribution. Each check can be turned on or off independently, and — importantly — if a check fails, **the agent stops right there** rather than continuing on to the remaining checks.

**Steps, in order:**

1. **Gets ready.** Sets up separate buckets to collect KYC issues, payment issues, document issues, and bank-detail issues.
2. **Checks KYC.** (Toggle: Check KYC) Every payment's linked investor must have a KYC record, and it must be marked verified. A missing or unverified KYC fails this step for that payment.
3. **Checks that the payable amount has been computed.** (Toggle: Check Net Payable) Every payment must have a net payable amount that is present and not zero.
4. **Checks that notices have been generated.** (Toggle: Check Docs Generated) The agent first confirms your fund has a Distribution Template document uploaded at all — if not, this fails the whole step for every payment on the distribution, with the message "Upload a Distribution Template under Fund > Documents." If the template exists, it then checks that each payment actually has at least one generated notice document attached.
5. **Checks that documents are approved.** (Toggle: Check Docs Approved) Every notice document on every payment must be approved; anything still pending approval fails this step.
6. **Checks bank details.** (Toggle: Check Bank Details) Every payment's investor must have a bank account number on file in their KYC record.
7. **Marks the distribution ready to pay.** This confirmation step is only reached if every enabled check above has passed.
8. **Saves the report.** Finalizes the report as either Ready or Blocked, based on whether any step failed.

Because the agent stops at the very first failing step, later steps are never run on a blocked check — their entries in the report simply stay "Pending" until you fix the blocker and run the agent again.

## 2. Inputs

| Field | Type | Default | What it controls |
|---|---|---|---|
| Check KYC | Yes / No | Yes | Verifies the investor has a completed, verified KYC record before payment release. Blocks if KYC is missing or unverified. |
| Check Net Payable | Yes / No | Yes | Verifies the distribution's net payable amount has actually been calculated. Blocks if it's missing or zero. |
| Check Docs Generated | Yes / No | Yes | Checks that distribution notice documents have been generated and attached to each payment. |
| Check Docs Approved | Yes / No | Yes | Verifies generated notices have been approved. Blocks if any notice is still pending approval. |
| Check Bank Details | Yes / No | Yes | Verifies the investor has a bank account number on file via their KYC record. Blocks if missing. |

Other things the agent reads directly (not configuration, just data):

- The distribution's payments, each with their linked investor (through the capital commitment and KYC record) and attached documents.
- The fund's documents — specifically, whether a "Distribution Template" document exists. This is a fund-level prerequisite checked once per run, not separately for each payment.

### Setup checklist and warnings

The defaults in the table above apply to agents provisioned through **Setup All Agents**. A toggle that was never given a value at all — common on agents set up before an option existed — does **not** default to Yes: the check is silently skipped. Because a skipped check looks exactly like a passed one in day-to-day use, the agent's **General** tab shows a yellow warning banner whenever setup is incomplete. For this agent the banner flags:

- **Any of the five check toggles that has never been set.** Set each one explicitly to Yes or No — an explicit No is respected and not flagged.
- **All checks turned off.** The agent would mark distributions "ready to pay" without verifying anything.
- **Any fund with no Distribution Template uploaded.** The notices-generated check will block every payment on that fund's distributions until a template exists under Fund → Documents.

Resolve everything in the banner before trusting a "Ready" result.

## 3. Enabling the Agent

- **Where to toggle:** Admin → Edit Entity → Support Agents section. Requires the **Company Admin** role.
- **AI key:** Not required. This agent is entirely rule-based — none of its checks call AI. It works with no AI key configured at all.
- If the agent is turned off for your entity, the **Run Readiness Check** button is hidden entirely from the distribution's page.

## 4. Accessing and Running the Agent

**From the agent's own page:**
1. Navigate to **AI → Support Agents** and open **Distribution Readiness**.
2. On the **General** tab, click **Run Now** to run the check against every distribution in your entity at once (batch mode — no step-by-step panel for an individual distribution this way).

**From the distribution's own page (the typical way to use it):**
1. Open the distribution's show page.
2. Click the dropdown action menu and choose **Run Readiness Check** (only visible when the agent is turned on for your entity).
3. A confirmation popup titled "Run Readiness Check" shows what the agent does, then runs it against just that distribution.
4. Because you're targeting one specific distribution, you'll see a live, step-by-step progress panel right there on the distribution's page as each check completes.

There's no way to select multiple specific distributions at once — your only batch option is the generic **Run Now** on the agent's own page, which runs against every distribution in the entity without showing a step panel.

This agent has **no Schedule tab** — it's on-demand only, by design. Run it manually before releasing each distribution's payments; there's no recurring automated check running in the background.

## 5. Where to Find the Output

- **The distribution's own page** — the live step panel shows real-time progress while the check runs, and stays visible afterward showing the final outcome of each step.
- **Agent's General tab → "View Report" link** — the most recent report for the agent overall (since this agent checks one distribution at a time, "most recent" simply reflects whichever distribution was checked last).
- **Agent's Execution History tab** — every past run across all distributions, with status, start time, and duration. Click any row to see the full report.

## 6. Understanding the Report

Each step's outcome is recorded as one of: **Success**, **Failed**, **Skipped**, or **Pending** (meaning it was never reached because an earlier step blocked the run). Each failed step includes:

- A plain-language message explaining what went wrong, often with a direct next step (e.g. "Re-run fee calculation on the distribution," "Click 'Generate Docs' on the Distribution page," "Approve each document before releasing payment," "Update KYC records before releasing payment").
- A count and list of the specific payments or investors that failed, each with a name and the reason.

**Final status:** The distribution is marked **Ready** if it reaches "Ready to Pay" with no failed steps; it's marked **Blocked** if any enabled check fails, and the report notes which step stopped the run. A blocked distribution's payments should not be released until the flagged investors or documents are corrected and the agent is run again.

## 7. Where It Can Fail

- **The agent stops at the first problem it finds.** Unlike some other agents that collect every issue before reporting back, this one stops dead at the first failed check. If KYC fails for one investor, you won't learn anything about net-payable, document, or bank-detail issues for *any* payment until that KYC issue is fixed and the agent is run again. Plan to iterate: fix the first blocker, re-run, see the next one, repeat.
- **No Distribution Template uploaded for the fund.** The notices-generated check fails for the *entire* distribution — not just one payment — if the fund has no document tagged as a Distribution Template. This is easy to miss if you've only ever generated notices by hand before. Upload a Distribution Template under **Fund → Documents** first.
- **A payment's amount is exactly zero.** The agent treats a zero net payable exactly the same as a missing one. A genuinely zero payment to an investor (say, fully offset by fees) will still be flagged as a blocker asking you to "re-run fee calculation," even when zero is actually the correct number. There's no way to mark a payment as "intentionally zero" — your only option is to turn off the Check Net Payable toggle for that run.
- **KYC exists but hasn't been marked verified.** The agent distinguishes "no KYC on file" from "KYC exists but isn't verified" in its messaging, but both block the same way. A KYC that's actually complete but simply hasn't had its "Verified" checkbox ticked will block the payment — a common source of confusion when the underlying data looks fine.
- **Bank details are only checked on the KYC record.** The bank-details check only looks at the bank account number stored on the investor's KYC record — not any separate banking module your entity might use. If bank details were entered somewhere else but never synced onto the KYC record, this check will incorrectly report them as missing.
- **The notices-generated check isn't picky about what counts as a "notice."** This step just checks whether *any* non-template document is attached to the payment — not specifically that it's a real distribution notice. That means a stray, unrelated document attached to a payment can make this check pass even with no real notice present. The flip side: a genuine notice that was mistakenly tagged as a template will be excluded and incorrectly flagged as missing.
- **The approval check doesn't notice if no documents exist yet.** This step only looks at documents that already exist and aren't templates. If the notices-generated step was turned off and no notices exist at all, the approval check trivially passes with nothing to check — "Docs Approved: Success" here doesn't mean approved documents exist, only that none of the (zero) existing ones are pending.
- **A distribution with no payments attached sails through as Ready.** Every payment-based check reports success when there's nothing to check ("All 0 payment(s) have..."). This can mask a setup mistake — like forgetting to add payments in the first place — rather than reflecting genuine readiness.
- **Running it twice on the same distribution at once.** A manual run from the distribution's page and a batch Run Now from the agent's own page can both target the same distribution at the same time. Both write to the same report, and whichever finishes last wins.
- **Turning off every check.** If you turn off all five toggles, the agent will sail through to "Ready to Pay" having validated nothing at all. The report will say Ready, but that simply reflects your configuration, not actual readiness — useful only as an emergency override, and worth double-checking before you trust it. The agent's page shows a warning banner whenever it is in this state.

## 8. FAQ

**Q: The agent blocked on KYC, but I know the investor's KYC is complete. What's wrong?**
A: Completeness and verification are two different things. Check whether the KYC record has actually been marked **Verified** — a complete-but-unverified KYC will block this check by design.

**Q: It blocked saying "no Distribution Template found," but I've generated notices before for other distributions in this fund.**
A: The check looks for a Distribution Template document on the **Fund** itself, not on the individual distribution. Confirm a template document still exists under Fund → Documents — it may have been deleted or replaced without the correct tag.

**Q: Why did it stop after the KYC step instead of showing me all the issues at once?**
A: This agent stops at the very first failing step instead of collecting every issue like some other agents do. Fix the reported blocker and run it again — it'll then surface the next blocking step, if there is one.

**Q: Can I schedule this to run automatically before every distribution?**
A: No — Distribution Readiness has no Schedule tab; it's intentionally on-demand only. Run it manually from the distribution's action menu before releasing payments.

**Q: A payment shows "Net payable not computed" but the amount is genuinely zero for that investor. How do I get past this?**
A: There's no per-payment override. You can either re-run fee calculation to confirm zero is correct (which may still leave the amount at zero and re-trigger the same block), or temporarily turn off Check Net Payable on the agent's Edit page for that run — keeping in mind that disables the check for the whole run, not just that one payment.
