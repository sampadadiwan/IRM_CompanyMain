# Call Notice Agent — User Guide

The Call Notice Agent checks that a capital call is actually ready before its notices go out to investors. It works on one capital call at a time and walks through a fixed checklist — KYC, document generation, document approval, and notification setup. Think of it as the capital-call counterpart to the Distribution Readiness Agent. It's built for fund operations teams preparing to send a call.

> **Where to find it:** Company menu (house icon, top right) → [**Agents**](/support_agents) → **Call Notice** card. Run the check from the capital call itself: Sidebar → [**Funds → Funds**](/funds) → open the fund → **Calls** tab → open the call → **Actions → Run Call Notice Check** → **Run Agent**. Needs the *Call Notice Agent* support-agent flag on your entity (set by your CapHive administrator); the menu item is shown to users with the Capital Calls *update* permission, but running the check and managing the agent need the **Company Admin** role.

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

Although the checklist itself has no settings, the agent still depends on fund-level setup. The agent's **General** tab (Company menu (house icon, top right) → **Agents** → **Call Notice**) shows a yellow warning banner listing **every fund that has no Call Notice template uploaded** — upload one under Fund → Documents before preparing a call for that fund. This matters especially for batch or scheduled runs, which do not walk through the step-by-step checks the way a run from the capital call's own page does, so a missing template would otherwise only surface at the moment you try to send.

---

## 3. Enabling the Agent

- **Where it's switched on**: a CapHive administrator sets the *Call Notice Agent* support-agent flag on your entity; a Company Admin then runs **Setup All Agents** to create the agent.
- **AI key needed?** No.
- **Who can manage it**: only Company Admin users can set up, configure or run support agents — including running this check from a capital call. Users with the Capital Calls *update* permission see the **Run Call Notice Check** menu item, but get a not-authorised error without the Company Admin role.

If the flag isn't enabled for your entity, **Run Call Notice Check** shows a lock icon with the tooltip "Call Notice Agent is disabled. Contact support to enable it", and **Run Now** on the agent page stays disabled.

---

## 4. Accessing and Running the Agent

The agent page has the standard **Run Now** button, but a batch run like that does not actually evaluate any checks (see the FAQ) — this agent is tied to a specific capital call and runs as part of preparing that call to be sent.

1. Navigate to the **Capital Call** record you intend to send.
2. Open **Actions → Run Call Notice Check**.
3. A confirmation modal describes the checklist; click **Run Agent**. The check is queued in the background for that one call.
4. While it runs, a live step panel (KYC, Docs Generated, Docs Approved, Notification, Ready to Send, Save Report) is streamed to the page. It lands inside the call's **Reconciliation** tab, so it is only visible when that tab exists (the Remittance Reconciliation Agent is enabled) and you open it; the call page does not keep a readiness panel once you reload.

This agent only ever checks **one capital call at a time** — there's no working way to run it against every call in a fund at once.

---

## 5. Where to Find the Output

- **Capital Call page** — the live step panel while the run streams (see [Accessing and Running the Agent](#4-accessing-and-running-the-agent)); it is not kept after you reload the page.
- **Execution History tab** on the agent's page — every past check across every capital call, with trigger, status, duration and processed/failed counts. It records that the call was processed, not whether the result was Ready or Blocked.
- **In-app toast** — when the run finishes, you get a notification that the call was processed, or naming the error.

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
| Mid-check error (e.g., the call's fund link is missing or broken) | Unexpected missing data somewhere in the call's setup | This isn't handled as a normal checklist failure — you get an error toast, and Execution History counts the call as failed (with the error in the expanded row) rather than processed. That signals something deeper is wrong with the call's data, not just an unmet checklist item. | Treat it as a data integrity issue worth investigating directly — check that the call is correctly linked to its fund and investors. |

---

## FAQ

**Where do I find the Call Notice Agent in CapHive?**
Click the house icon at the top right (tooltip "Company menu") to open the Company menu, then [**Agents**](/support_agents). The agent is the **Call Notice** card in the **Ops** group; click **View Details** to open its page with **General**, **Schedule** and **Execution History** tabs.

**How do I run the check for a specific capital call?**
Sidebar → [**Funds → Funds**](/funds) → open the fund → **Calls** tab → open the call → **Actions → Run Call Notice Check**. A confirmation modal describes the checklist; click **Run Agent**. The check is queued in the background for that one call. See [Accessing and Running the Agent](#4-accessing-and-running-the-agent).

**How do I enable the agent for my entity?**
Two steps. First a CapHive administrator ticks **Call Notice Agent** in the entity's Support Agents flags in the Admin panel (this is not something a Company Admin can do from the app). Then a Company Admin opens Company menu → **Agents** and clicks **Setup All Agents → Run Setup**, which creates the **Call Notice** card. Until the flag is set, the card shows **Disabled**, **Run Now** is greyed out and the capital call's **Run Call Notice Check** item shows a lock icon.

**Why is the Agents item in my Company menu greyed out with a lock?**
No support-agent flag at all is enabled for your entity, so the Agents page is hidden. The tooltip says "AI Agents are disabled. Contact support to enable it" — ask your CapHive administrator to enable the *Call Notice Agent* flag (and any others you need). See [Enabling the Agent](#3-enabling-the-agent).

**Who can run the check?**
Any employee whose role has the Capital Calls *update* permission sees **Actions → Run Call Notice Check**, but running the check, from the call or from **Agents**, needs the **Company Admin** role; others get a not-authorised error. Creating, editing, deleting or scheduling the agent also needs Company Admin.

**How do I create, edit or delete the agent?**
**Setup All Agents** on the Agents page creates it for you (or use **New Support Agent → CallNoticeAgent** on that page). **Edit** on the card or the General tab lets you change only the name, category and AI Model (the model is never used — the agent makes no LLM calls); there are no checklist settings. **Delete** on the General tab only succeeds for an agent that has never run, because its reports and execution logs block the delete. Re-running **Setup All Agents** recreates a deleted agent.

**Can I configure which checks run, or skip the notification check for calls that don't email investors?**
No. This agent has no settings at all — the checklist steps are fixed and always run in the same order for every capital call. See [Inputs](#2-inputs).

**Does "Run Now" on the agent's page or a schedule check my capital calls?**
Not usefully. **Run Now** and the **Schedule** tab run the agent against every capital call in the entity as a batch, and the checks only execute when a step-tracked report exists, which batch and scheduled runs do not create. Such runs appear in **Execution History** as "processed" but do not evaluate KYC, documents or notifications. Always run it from the capital call's **Actions** menu.

**Where do I see the result of a check?**
While a run is in progress the step panel is streamed live into the call's **Reconciliation** tab (only present when the Remittance Reconciliation Agent is enabled); clicking a step circle shows the affected investors and reason. Afterwards, Company menu → **Agents → Call Notice → Execution History** shows only trigger, status, duration and processed/failed counts. See [Where to Find the Output](#5-where-to-find-the-output).

**Why should I run this before sending call notices?**
**Send Notification** on a capital call is not blocked by the agent, so without a check you can email investors whose KYC is unverified, attach nothing because notices were never generated or approved, or find the send fails for lack of a notification template. One click checks every remittance on the call against all four gates in seconds instead of opening each investor, document and tab by hand.

**What does the agent let me do that I cannot do otherwise?**
It gives you a single ready/blocked answer per capital call with a named list of blockers (investor, folio and reason) across KYC, generated documents, approvals and the notification template. The same information exists on the KYCs page, the Documents page and the call's **Notification** tab, but only the agent cross-checks all of it for every investor on the call at once.

**Who typically uses it, and what happens if I skip it?**
Fund operations teams preparing a capital call, right before **Actions → Send Notification**. If you skip it nothing stops you from sending, but any missing KYC, unapproved notice or missing template surfaces only as investor complaints or a failed send afterwards. See [What This Agent Does](#1-what-this-agent-does).

**What happens when I click Run Agent in the modal?**
CapHive creates (or overwrites) one report for that capital call, writes an **Execution History** row marked Manual with your name, and queues a background job. The job runs the seven steps in order, saving each result to the report. Nothing on the call, its remittances, KYCs or documents is changed, and no investor or colleague is emailed. When it finishes you get an in-app toast saying the call was processed or naming the error.

**What happens when a check fails?**
The failed step records the affected investors and reasons, the report is finalised as **Blocked** with the step number it stopped at, and every later step stays "pending" because it never ran. Execution History still counts the call as processed. Fix the blocker (verify KYC, **Generate Docs**, approve the notices under **View Generated Documents**, or add the notification on the call's **Notification** tab) and run it again. See [Where It Can Fail](#7-where-it-can-fail).

**What happens when every check passes?**
The report is finalised as **Ready** (status Completed). That is a confirmation only: the agent does not send notices, approve anything or change the call. You still send the notices yourself with **Actions → Send Notification** on the capital call.

**Can I cancel a running check, and can I undo a run?**
While it is running, the progress panel shows a **Cancel** button; cancelling marks the report as cancelled with who cancelled and when, and it stays in Execution History. There is nothing to undo after a run because it changes no data; each new run on the same call simply overwrites that call's report (Execution History keeps a log row per run).

**Who gets notified when the check runs?**
For a manual run from the capital call, only you: an in-app toast on completion (or naming the error). Investors are never contacted. For a scheduled run, the users chosen under **Schedule → Notification Recipients** are emailed on success, failure or partial success according to the ticked boxes.

**The panel shows some steps still "pending" even though the run finished. Why?**
This agent's checklist stops at the very first failed step. Whichever check failed halts the process — everything after it never runs and stays marked "pending." Fix the reported blocker and re-run to see how much further the checklist gets next time. See [Understanding the Report](#6-understanding-the-report).

**One investor's commitment has "skip document generation" enabled — will the agent still flag them for missing documents?**
No. Investors linked to a commitment with that flag turned on are excluded from the documents-generated and documents-approved checks entirely — they're not flagged as failing, they're simply left out of those checks. They are still included in the KYC check.

**Does fixing a blocker automatically re-run the agent?**
No. After fixing a KYC, document, approval, or notification issue, you need to manually trigger the check again from the capital call page (**Actions → Run Call Notice Check**) — there's no automatic re-check when you save a fix.

**My fund has multiple capital calls — does fixing the "no Call Template" blocker for one call fix it for all of them?**
Yes, conceptually — the Call Notice template check looks at the fund's documents (a template document tagged *Call Template*), not anything specific to one call. Once you upload one to the fund, every capital call in that fund can pass this step on its next check. You'll still need to re-run the check on each individual call to refresh its report.

**What does the yellow banner on the agent's General tab mean?**
It lists every fund in your entity that has no *Call Template* document uploaded. Any capital call in such a fund will be blocked at the Docs Generated step, so upload a Call Template under the fund's **Documents** tab before preparing calls for that fund. The banner disappears once each fund has one.

**Execution History shows a failed count for my call. Is that the same as Blocked?**
No. **Blocked** means a checklist gate failed and the call still counts as processed. A failed count, with an error in the expanded row, means the run itself crashed, usually because the call's data is broken, for example a call not linked to a fund. Treat that as a data problem, not a checklist item.

**A "Ready" result came back for a call with no investors. Is it really ready?**
No. With zero remittances the KYC, documents-generated and documents-approved steps pass trivially because there is nothing to evaluate; only the notification check can still block. Add the investors (remittances) to the call first, then run the check again before trusting a Ready result.

**How does this agent relate to the Distribution Readiness Agent?**
They are twins for the two sides of the ledger: this agent gates a capital call before its notices go out, the Distribution Readiness Agent gates a capital distribution before payments are released. Both are deterministic, use no AI model and only report — neither changes your data. See [Distribution Readiness Agent](distribution_readiness_agent_user_guide).

## Related Guides

- [Support Agents](../support_agents_user_guide) — the shared framework: setup, LLM keys, schedules, Execution History and report statuses.
- [Capital Calls](../capital_calls_user_guide) — creating a call, generating and approving notices, and sending the notification the agent checks for.
- [Investor KYC](../investor_kyc_user_guide) — how a KYC record is created and marked verified, the first gate in the checklist.
- [Document Management](../document_management_user_guide) — uploading the fund's Call Template and approving generated notices.
- [Fund Commitment Notifications](../fund_commitment_notifications_user_guide) — the custom notification templates the Notification step looks for.
- [Distribution Readiness Agent](distribution_readiness_agent_user_guide) — the equivalent pre-flight checklist for capital distributions.
