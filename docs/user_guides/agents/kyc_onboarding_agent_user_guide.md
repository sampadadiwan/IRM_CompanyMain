# KYC Onboarding Agent — User Guide

The KYC Onboarding Agent automatically reviews a completed investor KYC record and checks that it's complete, internally consistent, and not expired — before your team relies on it for capital calls, distributions, or AML clearance. It belongs to the **Onboarding** category and is used by Operations and Compliance teams as a final quality check on investor onboarding.

> **Where to find it:** Run it on one KYC from Sidebar → [**Funds → KYCs**](/investor_kycs) → open the KYC → **KYC Actions → Run Kyc Onboarding Agent**, or on every completed KYC with **Run Now** under Company menu (house icon, top right) → [**Agents**](/support_agents). Needs the *KYC Onboarding Agent* support-agent flag (set by CapHive support), the **Company Admin** role, and an LLM key for the document checks.

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

For every investor KYC record that the investor has marked complete, the agent works through a fixed checklist, notes any issues it finds along with how serious they are, saves a report — and if everything checks out, automatically kicks off AML screening.

**What happens, in order, for each KYC record:**

1. **Gets ready to check.** The agent only looks at KYC records the investor has marked as complete, and only if the agent itself is turned on for your entity. Records still in progress are skipped entirely.
2. **Checks that all required information is filled in.** Every required field — both standard fields and any custom fields your entity has marked required — must actually have a value, and that value can't be a placeholder like "N/A," "TEST," or "--". Dropdown-style fields are also checked to make sure the selected value is actually one of the allowed options.
3. **Checks that all required documents are uploaded.** Any field that calls for a document upload, plus any additional documents your entity requires, must have a matching file on the record.
4. **Checks that each uploaded document is the right document.** The agent shows the AI each uploaded file along with its expected label (e.g. "Passport") and asks whether the file actually matches. Mismatches, unreadable files, and files that can't be downloaded are all flagged.
5. **Cross-checks document contents against the form.** For fields your entity has configured to be verified against a document (for example, comparing a typed-in ID number to the ID document itself), the agent reads the relevant value out of the matching document with AI and compares it to what's typed into the form, flagging any mismatch.
6. **Checks expiry status.** The agent compares the KYC's expiry date to today and flags the record as expired (a blocker) or expiring soon (a warning), based on the warning windows you've configured.
7. **Saves the report.** All findings are saved to the KYC record's report, which is marked either "ready" or "blocked."
8. **Sends expiry reminder emails.** If **Send Reminder** is on and the KYC came up expired or expiring soon, the agent emails every active team member on the entity ("KYC Expiry Alert — <name>") — at most once per milestone (each warning threshold, plus expiry) and never twice on the same day.
9. **Kicks off AML screening.** If there are no blocking issues from the field or document checks, the agent automatically starts an AML report, using the first active team member on the entity as the requestor.

## 2. Inputs

| Field | Type | Default | What it controls |
|---|---|---|---|
| Validate Fields | Yes/No | Off (treated as disabled unless explicitly set to Yes) | Turns the "required fields filled in" check on or off. Note: by default this setting has no visible toggle on the configuration form — re-running **Setup All Agents** sets it to Yes if it was never set; otherwise your CapHive contact has to change it. |
| Validate Documents | Yes/No | Off (same as above) | Turns on both the "document matches its label" check and the "document content matches the form" check. Also has no visible toggle by default. |
| Check KYC expiry status | Yes / No | Yes | When on, checks the KYC's expiry date — adds a blocking issue if it's already expired, or a warning if it falls within any configured warning window. |
| Expiry warning thresholds (days) | Text field | 60, 30, 15 | A comma-separated list of day counts before expiry that should trigger a warning (e.g. "warn me at 60, 30, and 15 days out"). Clearing this field does **not** turn advance warnings off — a blank or non-numeric value falls back to 60/30/15 days. To stop expiry checks, set **Check KYC expiry status** to No. The warning banner on the agent's page flags a blanked-out value. |
| Send Reminder | Yes/No | Off (no visible toggle by default; off unless turned on) | Turns the expiry reminder email step on or off. |
| Trigger AML | Yes/No | Off (no visible toggle by default; off unless turned on) | Turns the automatic AML screening step on or off. |
| Required Docs | Comma-separated list (not shown on the standard form by default) | — | Extra document names required in addition to the document-upload fields already on the form — checked during the document-presence step. |

Other things the agent looks at directly on the record (not configuration, just data it reads):

- The KYC record's own field values, including any custom fields, for the completeness check.
- The KYC's required configuration fields — including any field your entity has flagged for document cross-checking, which drives the "compare to document" step.
- The documents uploaded to the KYC record, matched by name to the required field labels and to the extra required-document list above.
- The investor and entity linked to the record — the entity is needed to find an active team member to act as the AML requestor.
- The record's expiry date and expired/not-expired status.

> Note: Out of the box, only **Check KYC expiry status** and **Expiry warning thresholds (days)** show up as visible toggles on the agent's configuration form. Validate Fields, Validate Documents, Send Reminder, Trigger AML, and Required Docs are real settings the agent reads, but they don't have a visible form control by default. Because the agent treats anything other than an explicit "on" as "off," any of these left unset will silently behave as disabled.

### Setup checklist and warnings

Silent skips are now surfaced up front: the agent's **General** tab shows a yellow warning banner listing every one of the five toggles that has never been given a value, plus a blanked-out **Expiry warning thresholds (days)** field. An explicit "No" is respected as your choice and is not flagged.

Two things fix most banner items:

- **Re-run Setup All Agents.** It now fills in **Validate Fields** and **Validate Documents** as Yes automatically on existing agents that never had them — these are the agent's core checks and were the most common silent gap.
- **Send Reminder and Trigger AML are deliberate opt-ins.** Setup never turns these on for you, because they send email and start AML screening. If you want them, set them to Yes explicitly; until you decide, the banner keeps reminding you they're off.

## 3. Enabling the Agent

- **Where to toggle:** the *KYC Onboarding Agent* support-agent flag on your entity, set by CapHive support. **Setup All Agents** does not create this agent — CapHive provisions it; Setup only adds the expiry fields and fills in unset defaults on an agent that already exists. Running and configuring it require the **Company Admin** role.
- **AI key required for two of the steps:** The "document matches its label" check and the "document content matches the form" check both call out to AI, so an AI key must be configured at Company menu (house icon, top right) → **Agents** → [**LLM Keys**](/support_agents/llm_keys). The rest of the checks are simple rule-based checks and don't need one — but if those two AI-dependent steps run without a key configured, they will fail (see [Where It Can Fail](#8-where-it-can-fail)).
- If the agent is turned off for your entity, the **Run Now** / **Run Kyc Onboarding Agent** button appears greyed out wherever it shows up; on the KYC page the tooltip reads "KYC Onboarding Agent is disabled. Contact support to enable it".

## 4. Accessing and Running the Agent

**From the agent's own page:**
1. Open the Company menu (house icon, top right) → [**Agents**](/support_agents) and open the KYC Onboarding agent card.
2. On the **General** tab, click **Run Now**. This runs the agent against every completed KYC record in your entity in one batch (you won't see a step-by-step panel for an individual record this way).

**From a single investor's KYC record (the more common path):**
1. Open the investor's KYC record page.
2. Open **KYC Actions** and choose **Run Kyc Onboarding Agent**. This option is only clickable when the agent is turned on for your entity; otherwise it's greyed out with a lock icon and a tooltip explaining why. Running it needs the **Company Admin** role.
3. A confirmation popup shows what the agent checks; click **Run Kyc Onboarding Agent** to run it against just that one record.
4. You'll see "Support agent job has been queued." The check runs in the background with no step-by-step progress panel; reload the KYC page to see the result. If the investor hasn't marked the KYC completed, the run processes nothing.

Either way, you don't have to wait on the page — results appear once the check finishes running in the background.

## 5. Scheduling

The agent is designed to support both scheduled runs and automatic triggers, but out of the box no recurring schedule is pre-configured for it. To set one up:

1. Open the agent's page and click the **Schedule** tab.
2. Set the **Frequency** (daily, weekly, monthly, bimonthly, quarterly or half-yearly), **Run On**, **Run At** and **Timezone**.
3. Tick **Enable scheduled runs for this agent**, and choose who should be notified on success, failure, or partial success.
4. Click **Save Schedule**.

One important gap: even though the agent's own description mentions it can run automatically when a new KYC is submitted, a document is uploaded, or a field is updated, none of those automatic triggers are actually wired up yet. The only ways it runs today are the manual **Run Now** / **Run Kyc Onboarding Agent** buttons and whatever schedule you set up yourself. If you need pre-filled fields right after a document upload, that's a job for the **KYC Doc Extractor Agent** instead — use a daily schedule (or manual runs) here for the full onboarding review.

## 6. Where to Find the Output

- **The KYC record's own page** — once a report exists, a row of summary cards (Missing Fields, Missing Docs, Invalid Docs, Mismatched, AML Report) shows the latest results right on the record.
- **The KYCs list** — **Onboarding Agent: Completed** and **Onboarding Agent: Failed** filters find KYCs by their latest agent result.
- **Agent's Execution History tab** — every past run, scheduled or manual.
- **Email** — with **Send Reminder** on, a "KYC Expiry Alert — <name>" email goes to every active team member on the entity (or the entity's sandbox addresses when sandbox mode is on) when a run finds an expired or soon-to-expire KYC — once per milestone (each warning threshold, plus expiry), never twice on the same day, no matter how the run was triggered.

## 7. Understanding the Report

The report groups its findings into three sections:

- **Field issues** — completeness and expiry findings. These include invalid or placeholder field values (blocking), an expired KYC (blocking), a KYC expiring soon (warning), and informational notes when everything checks out (e.g. "All required attributes are valid").
- **Document issues** — findings about presence, validity, and content matching. These include a missing required document (blocking), a document that doesn't match its expected label (blocking), a document the AI couldn't parse (warning), a document that couldn't be accessed (warning), a field that doesn't match its source document (blocking), and informational notes when everything checks out.
- **AML report** — a short log of what happened with AML screening: either confirmation that it was triggered, or a reason it was skipped (KYC incomplete / has blocking issues, or no active team member was found to act as requestor).

**Final status:** The record is marked **Blocked** if any field or document issue is blocking; otherwise it's marked **Ready**. Blocked means AML screening did **not** run this time — someone needs to resolve the blocking issue(s) and re-run the check before AML can proceed.

## 8. Where It Can Fail

- **No active team member on the entity.** AML screening needs someone to act as the requestor, and the agent looks for the first active team member on your entity. If there isn't one, AML is skipped with a "no active employee found" note — even though every other check passed and the record shows "Ready." Check your entity's team/employee list if AML never seems to trigger.
- **No AI key configured, but the agent is turned on.** The "document matches its label" and "compare field to document" steps both need an AI key. If none is configured, expect the AI call itself to fail outright rather than produce a tidy, per-document warning — this kind of configuration error isn't caught gracefully like a parsing error would be, so it can stop the whole run for that record rather than just flagging one document.
- **The AI returns something it can't read as a result.** This is caught and recorded as a warning on that specific document — it doesn't stop the run, but it also doesn't confirm the document one way or the other. Worth a manual look.
- **A document file can't be opened or downloaded.** Recorded as a warning, and that document's validity check is simply skipped — it isn't retried automatically.
- **Some settings have no visible toggle and may be silently off.** Validate Fields, Validate Documents, Send Reminder, and Trigger AML all default to "off" unless explicitly turned on behind the scenes, and none of them show up on the standard configuration form out of the box. A newly set-up agent can silently skip the completeness check, document checks, reminder emails, or AML — with no issues showing up at all, so the report looks unexpectedly clean. Re-running **Setup All Agents** sets Validate Fields and Validate Documents to Yes if they were never set; for anything else, confirm with your CapHive contact that these settings are actually turned on.
- **KYC not yet marked complete by the investor.** The agent only looks at records the investor has marked complete. Records still in progress are simply left out of a batch run, and a run started from that KYC's own page processes nothing — that's expected behavior, not a bug, even though it can look like "nothing happened."
- **Leaving the expiry warning window blank doesn't turn warnings off.** If you clear out the **Expiry warning thresholds (days)** field expecting to disable advance warnings, the agent instead falls back to its default 60/30/15-day windows. The only way to fully disable expiry checking is to set **Check KYC expiry status** itself to "No."
- **Document names have to match closely.** The "required document uploaded" check matches document names exactly, including case. The "document content matches form" check is a little more forgiving (case-insensitive), but still requires a close name match. A document uploaded under a slightly different label than expected will be reported as missing even though a similar file is right there on the record.
- **Running the same record from two places at once.** A manual run and a scheduled run both update the same report for that record, and only one "latest" version is kept. If you trigger a manual run while a scheduled run is still in progress, their updates can interleave — whichever finishes last wins.
- **Re-running an already-resolved record doesn't reconcile outside changes.** A re-run replaces the issue list from scratch, so previously-resolved issues are correctly cleared — but if something was changed outside the KYC record itself (for example, AML was triggered manually), the agent has no way to know about that and won't reflect it.

---

## 9. Frequently Asked Questions

### Navigation and getting there

**Where do I find the KYC Onboarding Agent in CapHive?**
Open the Company menu (house icon, top right) → [**Agents**](/support_agents) and open the KYC Onboarding agent card in the **Onboarding** group. Its page has **General**, **Schedule** and **Execution History** tabs.

**How do I run it on one KYC?**
Sidebar → [**Funds → KYCs**](/investor_kycs) → open the KYC → **KYC Actions → Run Kyc Onboarding Agent**, then click **Run Kyc Onboarding Agent** in the modal. The check runs in the background; reload the KYC page for the result. See [Accessing and Running the Agent](#4-accessing-and-running-the-agent).

**Where do I see the result for a KYC?**
On the KYC page, a row of cards shows **Missing Fields**, **Missing Docs**, **Invalid Docs**, **Mismatched** and **AML Report** once the agent has produced a report. On the KYCs list, the **New KYC** menu has **Onboarding Agent: Completed** and **Onboarding Agent: Failed** filters.

**Why is Run Kyc Onboarding Agent greyed out with a lock?**
The *KYC Onboarding Agent* flag is not enabled for your entity; the tooltip says "KYC Onboarding Agent is disabled. Contact support to enable it". Only CapHive support can enable it.

**Where do I change its settings?**
Open the agent and click **Edit**. **Check KYC expiry status** and **Expiry warning thresholds (days)** are always there; other toggles appear only if your entity's agent form has them. See [Inputs](#2-inputs).

**Who can run and configure it?**
Running it, from the KYC page or the agent page, and editing, scheduling or deleting it all need the **Company Admin** role. Another company admin grants the role from Company menu → [**User**](/users).

### Creating, updating and managing the agent

**How do I get the KYC Onboarding Agent for my entity?**
It is provisioned by CapHive support. **Setup All Agents** does not create it; on an existing agent it adds the expiry fields and fills in Check Expiry, Expiry Warning Days, Validate Fields and Validate Documents where they were never set.

**How do I turn on the field and document checks?**
Run **Setup All Agents** on Company menu → **Agents**, which sets **Validate Fields** and **Validate Documents** to Yes if they were never set. If a value was explicitly set to No and has no field on the Edit page, ask CapHive support to change it.

**How do I turn on expiry reminder emails or automatic AML?**
Set **Send Reminder** and **Trigger AML** to Yes on the **Edit** page if your agent form shows them, otherwise ask CapHive support. Setup never turns these on because they send email and start AML screening.

**How do I change the expiry warning windows?**
Enter comma-separated days in **Expiry warning thresholds (days)**, for example "90,30", and save. A blank or non-numeric value falls back to 60, 30 and 15 days; set **Check KYC expiry status** to No to stop expiry checks.

**How do I run it for all completed KYCs?**
Click **Run Now** on the agent's **General** tab. It checks every KYC marked completed by the investor, as a batch, with one summary alert at the end.

**How do I schedule it?**
On the **Schedule** tab tick **Enable scheduled runs for this agent**, pick a frequency (daily, weekly, monthly, bimonthly, quarterly or half-yearly), **Run On**, **Run At** and **Timezone**, then **Save Schedule**. No schedule exists by default. See [Scheduling](#5-scheduling).

**How do I pause or delete the agent?**
Untick the schedule to stop automatic runs. **Delete** on the General tab only works for an agent that has never run; after that its reports block the delete.

**What keys does it need?**
An LLM key under [**Agents → LLM Keys**](/support_agents/llm_keys) for the document checks, which ask the AI whether each file matches its label and read values to compare with the form. Field completeness and expiry checks need no key.

### Why use the KYC Onboarding Agent

**Why should I use the KYC Onboarding Agent?**
A KYC marked complete by an investor can still have placeholder values like "N/A", the wrong file under "Passport", a PAN that does not match the document, or an expiry date that has passed. The agent catches these before your team relies on the KYC for a capital call, distribution or AML clearance.

**What does it let me do that I cannot do otherwise?**
It reads every uploaded document with AI and cross-checks it against the form, across all completed KYCs, then starts AML screening automatically for the clean ones. Doing this by hand means opening each document for each investor.

**Who typically uses it?**
Onboarding, operations and compliance teams reviewing investor KYCs, often on a daily or weekly schedule during a fundraise.

**What happens if I don't use it?**
KYC review stays manual, expired KYCs are noticed only when someone looks, and AML reports are generated only when a user clicks **Generate AML Report**. Other agents, such as the Call Notice and Distribution Readiness agents, still block on unverified KYCs.

### What happens when I…

**What happens when I run it on a KYC?**
If the investor has marked the KYC completed, the agent runs its checks and overwrites that KYC's report with field and document issues, marked blocked if anything is blocking. The KYC data itself is not changed and its verified status is untouched. An **Execution History** row is added and you get an in-app alert.

**What happens when the KYC is not marked completed?**
Nothing is checked. The agent only processes KYCs the investor has marked completed, so an in-progress KYC is left out of both single and batch runs.

**What happens when the KYC is expired or about to expire?**
An expired KYC is a blocking issue and one inside a warning window is a warning. With **Send Reminder** on, all active employees get a "KYC Expiry Alert" email once per milestone (each window and expiry), not on every run; investors are not emailed.

**What happens with AML when all checks pass?**
With **Trigger AML** on and no blocking field or document issue, an AML report is generated in the background using your entity's first active employee as requestor, and the **AML Report** card shows "Triggered". With blocking issues, AML is skipped with a note.

**Can I undo a run?**
The agent's report is simply replaced on the next run. An expiry email already sent cannot be recalled, and an AML report it started stays on the KYC under **View AML Reports**.

### Troubleshooting and edge cases

**I ran the agent and the report shows zero issues, but I expected some checks to run. What happened?**
**Validate Fields** or **Validate Documents** is probably unset or No, so those checks were skipped silently. The yellow banner on the **General** tab lists unset toggles; run **Setup All Agents** or ask CapHive support to set them.

**The report says "Ready" but no AML report was generated. Why?**
Look at the **AML Report** card. **Trigger AML** may be off, or no active employee exists to act as requestor; add or activate an employee for the entity.

**A document I uploaded is being flagged as missing even though I can see it on the record.**
The presence check matches the required document's label to the uploaded document's name exactly, including case and spacing. Rename the document or the required label so they match.

**Will this agent run automatically when an investor uploads a new document?**
No. Despite the description, no upload or submission trigger is wired up. Use a schedule on the **Schedule** tab or run it from **KYC Actions**.

**Why didn't the expiry reminder email get sent even though the KYC shows "expiring soon"?**
**Send Reminder** may be off, a reminder for the same milestone may already have gone out, or the entity has no active employees. Check the KYC's expiry date against your warning windows and the agent's toggles.

**Nothing happened after I clicked Run Kyc Onboarding Agent. Why?**
The KYC is probably not marked completed by the investor, so the run had nothing to check. Confirm the KYC's completed status, then run it again.

**The run failed with an error instead of a report. Why?**
A common cause is a missing LLM key: the AI call for the document checks raises an error that stops the run for that KYC, and you get an error alert. Add a key under **Agents → LLM Keys** and run the agent again.

**A document is flagged "Could not ascertain" or "not accessible". What should I do?**
"Could not ascertain" means the AI reply could not be read, and "Document file not accessible" means the file could not be downloaded; both are warnings, not blockers. Open the file and check it manually, then re-run the agent.

**Does the agent verify the KYC for me?**
No. It never ticks **Verified**; a person still reviews and verifies the KYC. Use the agent's report to decide.

---

## Related Guides

- [Support Agents](../support_agents_user_guide) — setup, LLM keys, schedules, Execution History and the warning banner shared by every agent.
- [Investor KYC](../investor_kyc_user_guide) — KYC forms, documents, verification and AML reports.
- [KYC Doc Extractor Agent](kyc_doc_extractor_agent_user_guide) — pre-fills KYC fields from uploaded documents before the investor submits.
- [Custom Fields](../custom_fields_user_guide) — marking KYC fields required, which the completeness check enforces.
- [Call Notice Agent](call_notice_agent_user_guide) — blocks a capital call on missing or unverified KYC.
- [Distribution Readiness Agent](distribution_readiness_agent_user_guide) — blocks a distribution on unverified KYC or missing bank details.
- [LLM Configuration](../llm_configuration_guide) — the AI key the document checks need.
