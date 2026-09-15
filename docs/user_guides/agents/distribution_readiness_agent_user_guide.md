# Distribution Readiness Agent — User Guide

The Distribution Readiness Agent is a rule-based, step-by-step agent in the **Finance** category. It checks that every prerequisite is in place — investor KYC, computed payment amounts, generated and approved notices, and bank details — before a capital distribution payment goes out. Fund operations teams run it on a capital distribution immediately before wiring funds.

> **Where to find it:** Run the check from the distribution: Sidebar → [**Funds → Funds**](/funds) → open the fund → **Distributions** tab → open the distribution → **Actions → Run Readiness Check**. Manage its toggles under Company menu (house icon, top right) → [**Agents**](/support_agents) → **Distribution Readiness** → **Edit**. Needs the *Distribution Readiness Agent* support-agent flag (set by CapHive support) and the **Company Admin** role.

## Table of Contents

1. [What This Agent Does](#1-what-this-agent-does)
2. [Inputs](#2-inputs)
3. [Enabling the Agent](#3-enabling-the-agent)
4. [Accessing and Running the Agent](#4-accessing-and-running-the-agent)
5. [Where to Find the Output](#5-where-to-find-the-output)
6. [Understanding the Report](#6-understanding-the-report)
7. [Where It Can Fail](#7-where-it-can-fail)
8. [Frequently Asked Questions](#8-frequently-asked-questions)

---

## 1. What This Agent Does

The agent works through a fixed checklist against every payment on a single capital distribution. Each check can be turned on or off independently, and — importantly — if a check fails, **the agent stops right there** rather than continuing on to the remaining checks.

**Steps, in order:**

1. **Gets ready.** Sets up separate buckets to collect KYC issues, payment issues, document issues, and bank-detail issues.
2. **Checks KYC.** (Toggle: Check investor KYC) Every payment's linked investor must have a KYC record, and it must be marked verified. A missing or unverified KYC fails this step for that payment.
3. **Checks that the payable amount has been computed.** (Toggle: Check net payable computed) Every payment must have a net payable amount that is present and not zero.
4. **Checks that notices have been generated.** (Toggle: Check notices generated) The agent first confirms your fund has a Distribution Template document uploaded at all — if not, this fails the whole step for every payment on the distribution, with the message "No Distribution Template found for Fund '…'. Upload a Distribution Template under Fund > Documents." If the template exists, it then checks that each payment actually has at least one generated notice document attached.
5. **Checks that documents are approved.** (Toggle: Check notices approved) Every notice document on every payment must be approved; anything still pending approval fails this step.
6. **Checks bank details.** (Toggle: Check bank details on file) Every payment's investor must have a bank account number on file in their KYC record.
7. **Marks the distribution ready to pay.** This confirmation step is only reached if every enabled check above has passed.
8. **Saves the report.** Finalizes the report as either Ready or Blocked, based on whether any step failed.

Because the agent stops at the very first failing step, later steps are never run on a blocked check — their entries in the report simply stay "Pending" until you fix the blocker and run the agent again.

## 2. Inputs

| Field | Type | Default | What it controls |
|---|---|---|---|
| Check investor KYC | Yes / No | Yes | Verifies the investor has a completed, verified KYC record before payment release. Blocks if KYC is missing or unverified. |
| Check net payable computed | Yes / No | Yes | Verifies the distribution's net payable amount has actually been calculated. Blocks if it's missing or zero. |
| Check notices generated | Yes / No | Yes | Checks that distribution notice documents have been generated and attached to each payment. |
| Check notices approved | Yes / No | Yes | Verifies generated notices have been approved. Blocks if any notice is still pending approval. |
| Check bank details on file | Yes / No | Yes | Verifies the investor has a bank account number on file via their KYC record. Blocks if missing. |

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

- **Where to toggle:** the *Distribution Readiness Agent* support-agent flag on your entity, set by CapHive support. Running the check and editing the agent both require the **Company Admin** role.
- **AI key:** Not required. This agent is entirely rule-based — none of its checks call AI. It works with no AI key configured at all.
- If the agent is turned off for your entity, **Run Readiness Check** stays in the distribution's **Actions** menu but is greyed out with a lock and the tooltip "Distribution Readiness Agent is disabled. Contact support to enable it".

## 4. Accessing and Running the Agent

**From the distribution's own page (the way to use it):**
1. Open the distribution's show page.
2. Open the **Actions** menu and choose **Run Readiness Check** (greyed out with a lock when the agent is turned off for your entity).
3. A confirmation popup titled "Run Readiness Check" shows what the agent does; click **Run Readiness Check** to run it against just that distribution.
4. Because you're targeting one specific distribution, you'll see a live, step-by-step progress panel right there on the distribution's page as each check completes.

**From the agent's own page:** Company menu (house icon, top right) → [**Agents**](/support_agents) → **Distribution Readiness** → **General** tab → **Run Now**. This goes through every distribution in your entity as a batch, but a batch run has no step report, so every check returns immediately — nothing is verified and no result is saved. Only an entity with exactly one distribution gets a real check this way.

The agent page also has the standard **Schedule** tab, but scheduled runs work like the batch **Run Now** above and verify nothing. Run the check manually from the distribution before releasing each distribution's payments; there's no useful recurring automated check.

## 5. Where to Find the Output

- **The distribution's own page** — the live step panel shows real-time progress while the check runs, and stays visible afterward showing the final outcome of each step.
- **Agent's Execution History tab** — every past run across all distributions, with status, start time, and duration. Expanding a row shows a short summary, not the full step report.

Each distribution has a single report that is reused and overwritten on every run, so only the latest result is kept.

## 6. Understanding the Report

Each step's outcome is recorded as one of: **Success**, **Failed**, **Skipped**, or **Pending** (meaning it was never reached because an earlier step blocked the run). Each failed step includes:

- A plain-language message explaining what went wrong, often with a direct next step (e.g. "Re-run fee calculation on the distribution," "Click 'Generate Docs' on the Distribution page," "Approve each document before releasing payment," "Update KYC records before releasing payment"). On the distribution's **Actions** menu, "re-run fee calculation" is **Recompute Fees** and "Generate Docs" is **Generate Documents**.
- A count and list of the specific payments or investors that failed, each with a name and the reason.

**Final status:** The distribution is marked **Ready** if it reaches "Ready to Pay" with no failed steps; it's marked **Blocked** if any enabled check fails, and the report notes which step stopped the run. A blocked distribution's payments should not be released until the flagged investors or documents are corrected and the agent is run again.

## 7. Where It Can Fail

- **The agent stops at the first problem it finds.** Unlike some other agents that collect every issue before reporting back, this one stops dead at the first failed check. If KYC fails for one investor, you won't learn anything about net-payable, document, or bank-detail issues for *any* payment until that KYC issue is fixed and the agent is run again. Plan to iterate: fix the first blocker, re-run, see the next one, repeat.
- **No Distribution Template uploaded for the fund.** The notices-generated check fails for the *entire* distribution — not just one payment — if the fund has no document tagged as a Distribution Template. This is easy to miss if you've only ever generated notices by hand before. Upload a Distribution Template under **Fund → Documents** first.
- **A payment's amount is exactly zero.** The agent treats a zero net payable exactly the same as a missing one. A genuinely zero payment to an investor (say, fully offset by fees) will still be flagged as a blocker asking you to "re-run fee calculation" (**Actions → Recompute Fees**), even when zero is actually the correct number. There's no way to mark a payment as "intentionally zero" — your only option is to turn off **Check net payable computed**, which applies to every run until you set it back.
- **KYC exists but hasn't been marked verified.** The agent distinguishes "no KYC on file" from "KYC exists but isn't verified" in its messaging, but both block the same way. A KYC that's actually complete but simply hasn't had its "Verified" checkbox ticked will block the payment — a common source of confusion when the underlying data looks fine.
- **Bank details are only checked on the KYC record.** The bank-details check only looks at the bank account number stored on the investor's KYC record — not any separate banking module your entity might use. If bank details were entered somewhere else but never synced onto the KYC record, this check will incorrectly report them as missing.
- **The notices-generated check isn't picky about what counts as a "notice."** This step just checks whether *any* non-template document is attached to the payment — not specifically that it's a real distribution notice. That means a stray, unrelated document attached to a payment can make this check pass even with no real notice present. The flip side: a genuine notice that was mistakenly tagged as a template will be excluded and incorrectly flagged as missing.
- **The approval check doesn't notice if no documents exist yet.** This step only looks at documents that already exist and aren't templates. If the notices-generated step was turned off and no notices exist at all, the approval check trivially passes with nothing to check — "Docs Approved: Success" here doesn't mean approved documents exist, only that none of the (zero) existing ones are pending.
- **A distribution with no payments attached sails through as Ready.** Every payment-based check reports success when there's nothing to check ("All 0 payment(s) have..."). This can mask a setup mistake — like forgetting to add payments in the first place — rather than reflecting genuine readiness.
- **Run Now and scheduled runs on the agent page check nothing.** They run as a batch without a step report, so every check returns immediately and no result is saved — an apparently successful batch run does not mean any distribution is ready. Always run the check from the distribution's **Actions** menu.
- **Turning off every check.** If you turn off all five toggles, the agent will sail through to "Ready to Pay" having validated nothing at all. The report will say Ready, but that simply reflects your configuration, not actual readiness — useful only as an emergency override, and worth double-checking before you trust it. The agent's page shows a warning banner whenever it is in this state.

---

## 8. Frequently Asked Questions

### Navigation and getting there

**Where do I find the Distribution Readiness Agent in CapHive?**
Open the Company menu (house icon, top right) → [**Agents**](/support_agents) and click the **Distribution Readiness** card in the **Finance** group. Its page has **General**, **Schedule** and **Execution History** tabs.

**How do I run the readiness check on a distribution?**
Sidebar → [**Funds → Funds**](/funds) → open the fund → **Distributions** tab → open the distribution → **Actions → Run Readiness Check**. The modal describes the checks; click **Run Readiness Check** and the step panel appears below the page. See [Accessing and Running the Agent](#4-accessing-and-running-the-agent).

**Why is Run Readiness Check greyed out with a lock?**
The *Distribution Readiness Agent* flag is not enabled for your entity; the tooltip says "Distribution Readiness Agent is disabled. Contact support to enable it". Only CapHive support can enable it.

**Where do I change which checks run?**
Open the agent and click **Edit**. Set **Check investor KYC**, **Check net payable computed**, **Check notices generated**, **Check notices approved** and **Check bank details on file** to Yes or No and save. See [Inputs](#2-inputs).

**Where do I see the result?**
On the distribution page, the step panel shows each step as it runs and names the failing investors when you click a failed step. The agent's **Execution History** tab keeps a row per run with trigger, status and duration.

**Who can run it?**
Anyone who is not an investor sees the **Actions** menu item, but running the check needs the **Company Admin** role. Editing the agent's toggles also needs Company Admin.

### Creating, updating and managing the agent

**How do I create the Distribution Readiness Agent?**
A company admin opens Company menu → **Agents** → **Setup All Agents** → **Run Setup**. It creates the agent with all five checks set to Yes and no schedule.

**How do I turn a check off?**
Set its field to No on the **Edit** page and save. The step then shows **Skipped** on every later run; a field that was never set also counts as No and is flagged in the yellow banner on the **General** tab.

**What must be in place before I run it?**
The fund needs a document tagged *Distribution Template* under its **Documents** tab, and each payment needs a verified KYC with a bank account number, a computed net payable, and generated and approved notices. The **General** tab banner lists funds that have no Distribution Template.

**Can I schedule it or use Run Now on the agent page?**
You can, but it does not help: scheduled runs and **Run Now** go through every distribution as a batch without a step report, so no check is actually performed and nothing is saved. Always run it from the distribution's **Actions** menu.

**Can I delete the agent?**
**Delete** on the General tab only succeeds for an agent that has never run. To stop using it, simply stop running the check.

### Why use the Distribution Readiness Agent

**Why should I run this before paying a distribution?**
Money sent to an investor with unverified KYC, no bank account, a zero payable or an unapproved notice is hard to recall. The check tests every payment on the distribution against all five gates in seconds, instead of opening each investor, KYC and document by hand.

**What does it let me do that I cannot do otherwise?**
It gives a single Ready or Blocked answer for the whole distribution with a named list of the investors and reasons behind any blocker. The underlying facts live on the KYC, payment and document screens, but nothing else cross-checks them for every payment at once.

**Who typically uses it?**
Fund operations and finance teams, immediately before **Mark Payments Completed** or wiring funds, and again after fixing each blocker. It needs no AI key.

**What happens if I skip it?**
Nothing in CapHive stops you paying a distribution, so a missing KYC, bank detail or approval surfaces only after money has moved or an investor complains.

### What happens when I…

**What happens when I click Run Readiness Check?**
CapHive resets that distribution's report, adds a Manual row with your name to **Execution History** and queues a background job. The job runs the checks in order and streams each result into the step panel; you get an in-app alert when it finishes. No payment, KYC or document is changed and no investor is emailed.

**What happens when a check fails?**
The step is marked **Failed** with the affected investors and reasons, the report is finalised as **Blocked** at that step, and every later step stays **Pending** because it never ran. Fix the blocker and run the check again. See [Where It Can Fail](#7-where-it-can-fail).

**What happens when every check passes?**
The **Ready to Pay** step succeeds and the report is marked **Ready**. That is a confirmation only: the agent does not approve the distribution, mark payments completed or send payment notifications.

**Who is notified?**
Only the user who ran it, by an in-app alert. Investors and colleagues are not contacted, and there is no report email.

**Can I cancel or undo a run?**
While it is running, click **Cancel** in the step panel; the report is marked cancelled with who and when. There is nothing to undo afterwards because the check changes no data, and the next run simply overwrites the distribution's report.

### Troubleshooting and edge cases

**The agent blocked on KYC, but I know the investor's KYC is complete. What's wrong?**
Completeness and verification are two different things. Check whether the KYC record has actually been marked **Verified**, and that the payment's commitment is linked to that KYC; either gap blocks the check by design.

**It blocked saying "no Distribution Template found," but I've generated notices before for other distributions in this fund.**
The check looks for a template document tagged *Distribution Template* on the **Fund** itself, not on the distribution. Confirm one still exists under the fund's **Documents** tab; it may have been deleted or re-tagged.

**Why did it stop after the KYC step instead of showing me all the issues at once?**
This agent stops at the first failing step. Fix the reported blocker and run it again; it will then surface the next blocking step, if there is one.

**Can I schedule this to run automatically before every distribution?**
Not usefully. The **Schedule** tab exists, but scheduled runs have no step report, so the checks do not run. Run it from the distribution's **Actions** menu before releasing payments.

**A payment shows "Net payable not computed" but the amount is genuinely zero for that investor. How do I get past this?**
There is no per-payment override; a zero net payable always blocks. Run **Actions → Recompute Fees** to confirm the figure, or temporarily set **Check net payable computed** to No on the agent's **Edit** page, which disables the check for every run until you set it back.

**The notices step says documents are missing. How do I fix it?**
Use **Actions → Generate Documents** on the distribution, then run the check again. Any non-template document attached to a payment satisfies this step, so make sure the attached documents really are the notices.

**Docs Approved passed but there are no notices. How?**
If **Check notices generated** is off, the approval step only checks documents that exist, so zero documents pass. Keep both checks on together.

**A distribution with no payments came back Ready. Is it?**
No. With zero payments every payment check passes trivially. Add the payments first, then run the check again.

**I clicked Run Readiness Check and got a not-authorised error. Why?**
Running a support agent requires the **Company Admin** role. Ask a company admin to run it or to grant you the role.

**How does this agent relate to the Call Notice Agent?**
They are twins: the [Call Notice Agent](call_notice_agent_user_guide) gates a capital call before notices go out, this agent gates a distribution before payments are released. Both are rule-based and only report.

---

## Related Guides

- [Support Agents](../support_agents_user_guide) — setup, Execution History, the warning banner and report statuses shared by every agent.
- [Capital Distributions](../capital_distributions_user_guide) — creating the distribution, recomputing fees, generating documents and marking payments completed.
- [Investor KYC](../investor_kyc_user_guide) — verifying KYC and recording the bank account number the agent checks.
- [Document Management](../document_management_user_guide) — uploading the fund's Distribution Template and approving notices.
- [Call Notice Agent](call_notice_agent_user_guide) — the equivalent pre-flight checklist for capital calls.
- [RTA Reconciliation Agent](rta_reconciliation_agent_user_guide) — another finance agent run from fund records.
