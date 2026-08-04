# Call Notice Agent — User Guide

The Call Notice Agent checks that a capital call is actually ready before its notices go out to investors. It works on one capital call at a time, walks through a fixed checklist — KYC, document generation, document approval, and notification setup — and shows you live progress right on the capital call's page. Think of it as the capital-call counterpart to the Distribution Readiness Agent. It's built for fund operations teams preparing to send a call.

## Table of Contents

1. [What This Agent Does](#1-what-this-agent-does)
2. [Inputs](#2-inputs)
3. [Enabling the Agent](#3-enabling-the-agent)
4. [Accessing and Running the Agent](#4-accessing-and-running-the-agent)
5. [Where to Find the Output](#5-where-to-find-the-output)
6. [Understanding the Report](#6-understanding-the-report)
7. [Where It Can Fail](#7-where-it-can-fail)
8. [FAQ](#faq)

---

## 1. What This Agent Does

This agent is always run against **one specific capital call** — the one you're about to send notices for. Its checklist is fixed: every step always runs in the same order, and there's nothing to configure or skip.

**What happens when it runs, in order, with each step gating the next:**

1. **Gets started** — sets up trackers to collect findings on KYC, documents, and notifications.
2. **Checks investor KYC** — for every investor on the call, confirms their KYC record exists and has been verified. If any investor is missing KYC or isn't verified yet, **the checklist stops here** — none of the later checks run.
3. **Checks that call documents have been generated** — first confirms the fund has at least one Call Notice template uploaded; if not, the checklist stops immediately with a fund-level blocker. Otherwise, for each investor (except those whose commitment is explicitly set to skip document generation), it confirms the actual call notice documents have been generated. Missing documents stop the checklist here.
4. **Checks that call documents have been approved** — for each investor still in scope, confirms all of their generated call notice documents have been approved. Unapproved documents stop the checklist here.
5. **Checks notification setup** — confirms an active email notification is configured for this capital call. A missing or disabled notification stops the checklist here.
6. **Confirms ready to send** — a final confirmation step that only runs if every prior check passed. It doesn't change any data — it just confirms the call has cleared every gate.
7. **Saves the report** — records whether the call passed every check or got stopped partway through.

**No AI/LLM calls** — every check here is a straightforward yes/no comparison against your existing records.

---

## 2. Inputs

### Configuration fields

**None.** This agent has no settings form at all — there's nothing to toggle, reorder, or adjust. The checklist above is fixed for every entity. Setting the agent up simply makes it available; it doesn't add any configurable options.

### Other things that feed into the run

- **What it runs against**: a single capital call, specified each time you trigger a check.
- **Investors on the call**: pulled along with their KYC status and documents as needed for each step.
- **Templates**: the fund needs at least one Call Notice template document uploaded for the documents-generated check to pass.
- **Notification setup**: an active, enabled email notification configured on the capital call.
- **No AI/LLM key required.**

### Setup checklist and warnings

Although the checklist itself has no settings, the agent still depends on fund-level setup. The agent's **General** tab (under AI → Support Agents) shows a yellow warning banner listing **every fund that has no Call Notice template uploaded** — upload one under Fund → Documents before preparing a call for that fund. This matters especially for batch or scheduled runs, which do not walk through the step-by-step checks the way a run from the capital call's own page does, so a missing template would otherwise only surface at the moment you try to send.

---

## 3. Enabling the Agent

- **Where it's switched on**: Admin → Edit Entity → Support Agents section. A Company Admin checks the "Call Notice" box and saves.
- **AI key needed?** No.
- **Who can manage it**: only Company Admin users can set up or run support agents in general; the readiness panel itself is visible to anyone with access to the capital call's page.

If the agent isn't enabled for your entity, this checklist simply won't be available — check with your administrator if the panel doesn't appear or "Run Now" stays disabled.

---

## 4. Accessing and Running the Agent

Unlike the E-Sign Monitor or Data Quality agent, this one doesn't have an entity-wide "Run Now" button on its own page — it's tied to a specific capital call and runs as part of preparing that call to be sent.

1. Navigate to the **Capital Call** record you intend to send.
2. The capital call's details page automatically shows the Call Notice Agent's readiness panel at the top, displaying the most recent check for that call, if one has been run.
3. To run a fresh check, trigger it from that panel — this starts a new readiness check and shows you live progress as each step completes.
4. The panel shows six step indicators (KYC, Docs Generated, Docs Approved, Notification, Ready to Send, Save Report) updating in real time, along with a progress bar.

This agent only ever checks **one capital call at a time** — there's no way to run it against every call in a fund at once.

---

## 5. Where to Find the Output

- **Capital Call Details page** — the readiness panel itself, showing the latest check inline.
- **General tab on the agent's own page → "View Report" link** — if you go to **AI → Support Agents → Call Notice**, this shows whichever capital call was checked most recently, across the whole entity.
- **Execution History tab** — every past check across every capital call, with status and duration.

There's no email for this agent — it's purely a readiness gate shown in the app. It doesn't send anything to investors or your team on its own.

---

## 6. Understanding the Report

Each failed check records the specific investors or records affected, along with a plain-language reason for each one. These details are organized by category — KYC issues, document issues, or notification issues — so you can see exactly what needs fixing.

- **"Ready"** — every check passed; the capital call is cleared to send notices.
- **"Blocked"** — at least one check failed. The report also notes exactly which step the checklist stopped at, so you can jump straight to the blocker without reading through the whole panel.

**This is the most important thing to understand about how this agent works:** the checklist runs in a fixed order — KYC, then documents generated, then documents approved, then notification setup — and it **stops at the first failed step**. If KYC fails, the agent doesn't tell you anything yet about whether your documents or notifications are also ready; those checks simply haven't run. In the panel, steps after the first failure stay marked "pending," not "passed" or "failed." Fix the first blocker, re-run the check, and you may well discover a new blocker further down the list that you couldn't have seen before. Plan for a few rounds of fix-and-recheck rather than expecting a single pass to surface every issue at once.

---

## 7. Where It Can Fail

| Scenario | Trigger | What you'll see | What to do |
|---|---|---|---|
| Investor has no KYC record at all | An investor on the call has no linked KYC record | KYC check fails with "No KYC record linked to this commitment"; the checklist stops here. Document and notification checks never run, even if they would have passed. | Go to Investor KYCs, filter by fund, create or link the missing KYC record, then re-run the check. |
| Investor's KYC exists but isn't verified | The KYC record exists but hasn't been marked verified | KYC check fails naming the investor and noting "KYC not verified"; same stop-here behavior as above. | Mark the KYC as verified from the Investor KYCs screen, then re-run. |
| Fund has no Call Notice template uploaded | The fund has zero Call Notice template documents | The documents-generated check fails immediately at the fund level: "No call templates found for Fund '...'. Go to Fund > Documents and upload a Call Template." **This blocks every capital call in that fund**, not just the one you're checking. | Upload a Call Notice template document to the fund — this unblocks this step for every call in that fund, not just the current one. |
| An investor's commitment is set to skip document generation | The commitment has a "skip document generation" flag turned on | That investor is quietly left out of both the documents-generated and documents-approved checks — they don't pass or fail; they're simply not evaluated. | If an investor you expected to see flagged is missing from the failed list, check whether "skip document generation" was turned on for their commitment. |
| Call notice documents not yet generated | An investor has no call notice documents generated yet | The documents-generated check fails, listing each affected investor with "No call notice documents generated" and instructing you to click "Generate Docs" on the Capital Call page. The checklist stops here — approvals and notification checks never run. | Generate the call notice documents from the Capital Call page, then re-run. |
| Documents generated but not yet approved | One or more generated documents are still pending approval | The documents-approved check fails, listing each affected investor with a count of pending documents, and instructing you to approve each one. The checklist stops here — the notification check never runs. | Approve the outstanding call notice documents, then re-run. |
| No notification template configured | No active email notification is set up for this call | The notification check fails: "No email notification template configured. Go to the 'Notification' tab and create a custom notification for sending call remittance notices." | On the capital call page, go to the **Notification** tab and create/enable the notification for sending call remittance notices. |
| Capital call with zero investors linked yet | A newly created call with no investors added | The KYC, documents-generated, and documents-approved checks all pass automatically, since there's nothing to evaluate — only the notification check can still block. | A "ready" result on a call with no investors doesn't actually mean it's ready to send — confirm investors have been added before trusting that result. |
| Re-running after fixing one blocker | You fix the KYC issue and re-run, but haven't tested the later checks yet | Each re-run reuses and overwrites the same report rather than keeping every historical attempt (though Execution History does keep a log of each run). The panel will now progress further — for example into the documents-generated check — and may reveal a brand-new blocker you hadn't seen before. | Don't assume "ready" just because you fixed the first reported issue — re-run and look at the whole panel each time, since later steps can surface new blockers that weren't visible on the earlier run. |
| Mid-check error (e.g., the call's fund link is missing or broken) | Unexpected missing data somewhere in the call's setup | This isn't handled as a normal checklist failure — it can show up as a "Failed" status (rather than "Blocked") in Execution History, which signals something deeper is wrong with the call's data, not just an unmet checklist item. | If you see "Failed" rather than "Blocked" in Execution History, treat it as a data integrity issue worth investigating directly — check that the call is correctly linked to its fund and investors. |

---

## FAQ

**Q: The panel shows some steps still "pending" even though the run finished. Why?**
A: This agent's checklist stops at the very first failed step. Whichever check failed halts the process — everything after it never runs and stays marked "pending." Fix the reported blocker and re-run to see how much further the checklist gets next time.

**Q: Can I configure which checks run, or skip the notification check for calls that don't email investors?**
A: No. This agent has no settings at all — the checklist steps are fixed and always run in the same order for every capital call.

**Q: One investor's commitment has "skip document generation" enabled — will the agent still flag them for missing documents?**
A: No. Investors linked to a commitment with that flag turned on are excluded from the documents-generated and documents-approved checks entirely — they're not flagged as failing, they're simply left out of those checks.

**Q: Does fixing a blocker automatically re-run the agent?**
A: No. After fixing a KYC, document, approval, or notification issue, you need to manually trigger the check again from the capital call page — there's no automatic re-check when you save a fix.

**Q: My fund has multiple capital calls — does fixing the "no Call Template" blocker for one call fix it for all of them?**
A: Yes, conceptually — the Call Notice template check looks at the fund's documents, not anything specific to one call. Once you upload a Call Notice template to the fund, every capital call in that fund can pass this step on its next check. You'll still need to re-run the check on each individual call to refresh its report.
