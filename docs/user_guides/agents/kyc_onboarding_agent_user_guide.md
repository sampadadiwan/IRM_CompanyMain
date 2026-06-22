# KYC Onboarding Agent — User Guide

The KYC Onboarding Agent automatically reviews a completed investor KYC record and checks that it's complete, internally consistent, and not expired — before your team relies on it for capital calls, distributions, or AML clearance. It belongs to the **Onboarding** category and is used by Operations and Compliance teams as a final quality check on investor onboarding.

## Table of Contents

1. [What This Agent Does](#1-what-this-agent-does)
2. [Inputs](#2-inputs)
3. [Enabling the Agent](#3-enabling-the-agent)
4. [Accessing and Running the Agent](#4-accessing-and-running-the-agent)
5. [Scheduling](#5-scheduling)
6. [Where to Find the Output](#6-where-to-find-the-output)
7. [Understanding the Report](#7-understanding-the-report)
8. [Where It Can Fail](#8-where-it-can-fail)
9. [FAQ](#9-faq)

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
8. **Sends expiry reminder emails.** If anything came up expired or expiring soon, the agent emails every active team member on the entity.
9. **Kicks off AML screening.** If there are no blocking issues from the field or document checks, the agent automatically starts an AML report, using the first active team member on the entity as the requestor.

## 2. Inputs

| Field | Type | Default | What it controls |
|---|---|---|---|
| Validate Fields | Yes/No | Off (treated as disabled unless explicitly set to Yes) | Turns the "required fields filled in" check on or off. Note: by default this setting has no visible toggle on the configuration form — it must be turned on by your CapHive contact or it stays off. |
| Validate Documents | Yes/No | Off (same as above) | Turns on both the "document matches its label" check and the "document content matches the form" check. Also has no visible toggle by default. |
| Check Expiry | Yes / No | Yes | When on, checks the KYC's expiry date — adds a blocking issue if it's already expired, or a warning if it falls within any configured warning window. |
| Expiry Warning Days | Text field | 60, 30, 15 | A comma-separated list of day counts before expiry that should trigger a warning (e.g. "warn me at 60, 30, and 15 days out"). If you leave this blank, the agent quietly falls back to the default 60/30/15 windows rather than turning warnings off. |
| Send Reminder | Yes/No | Off (no visible toggle by default; off unless turned on) | Turns the expiry reminder email step on or off. |
| Trigger AML | Yes/No | Off (no visible toggle by default; off unless turned on) | Turns the automatic AML screening step on or off. |
| Required Docs | Comma-separated list (not shown on the standard form by default) | — | Extra document names required in addition to the document-upload fields already on the form — checked during the document-presence step. |

Other things the agent looks at directly on the record (not configuration, just data it reads):

- The KYC record's own field values, including any custom fields, for the completeness check.
- The KYC's required configuration fields — including any field your entity has flagged for document cross-checking, which drives the "compare to document" step.
- The documents uploaded to the KYC record, matched by name to the required field labels and to the extra required-document list above.
- The investor and entity linked to the record — the entity is needed to find an active team member to act as the AML requestor.
- The record's expiry date and expired/not-expired status.

> Note: Out of the box, only **Check Expiry** and **Expiry Warning Days** show up as visible toggles on the agent's configuration form. Validate Fields, Validate Documents, Send Reminder, Trigger AML, and Required Docs are real settings the agent reads, but they don't have a visible form control by default — they need to be set up behind the scenes (ask your CapHive contact, or they can be set during initial setup) to take effect. Because the agent treats anything other than an explicit "on" as "off," any of these left unset will silently behave as disabled.

## 3. Enabling the Agent

- **Where to toggle:** Admin → Edit Entity → Support Agents section. Requires the **Company Admin** role.
- **AI key required for two of the steps:** The "document matches its label" check and the "document content matches the form" check both call out to AI, so an AI key must be configured at **AI → Support Agents → LLM Keys**. The rest of the checks are simple rule-based checks and don't need one — but if those two AI-dependent steps run without a key configured, they will fail (see [Where It Can Fail](#8-where-it-can-fail)).
- If the agent is turned off for your entity, the **Run Now** / **Run Kyc Onboarding Agent** button appears greyed out wherever it shows up.

## 4. Accessing and Running the Agent

**From the agent's own page:**
1. Navigate to **AI → Support Agents** and open **KYC Onboarding Agent**.
2. On the **General** tab, click **Run Now**. This runs the agent against every completed KYC record in your entity in one batch (you won't see a step-by-step panel for an individual record this way).

**From a single investor's KYC record (the more common path):**
1. Open the investor's KYC record page.
2. Click the dropdown action menu and choose **Run Kyc Onboarding Agent**. This option is only clickable when the agent is turned on for your entity; otherwise it's greyed out with a lock icon and a tooltip explaining why.
3. A confirmation popup shows what the agent checks, then runs it against just that one record.
4. The check runs in the background and the record's report status shows as "Pending" while it works. Because you're running it against one specific record, you'll see a live step-by-step progress panel as each check completes.

Either way, you don't have to wait on the page — results appear once the check finishes running in the background.

## 5. Scheduling

The agent is designed to support both scheduled runs and automatic triggers, but out of the box no recurring schedule is pre-configured for it. To set one up:

1. Open the agent's page and click the **Schedule** tab.
2. Set the **Frequency** (daily/weekly/monthly), **Run At Time**, and timezone.
3. Turn on **Enabled**, and choose who should be notified on success, failure, or partial success.
4. Save.

One important gap: even though the agent's own description mentions it can run automatically when a new KYC is submitted, a document is uploaded, or a field is updated, none of those automatic triggers are actually wired up yet. The only ways it runs today are the manual **Run Now** / **Run Kyc Onboarding Agent** buttons and whatever schedule you set up yourself. If you need pre-filled fields right after a document upload, that's a job for the **KYC Doc Extractor Agent** instead — use a daily schedule (or manual runs) here for the full onboarding review.

## 6. Where to Find the Output

- **The KYC record's own page** — a row of summary cards (Missing Fields, Missing Docs, Invalid Docs, Mismatched, AML Report) shows the latest results right on the record.
- **Agent's General tab → "View Report" link** — the most recent report for the agent overall.
- **Agent's Execution History tab** — every past run, scheduled or manual.
- **Email** — an expiry alert is sent to every active team member on the entity any time a run turns up an expired or soon-to-expire KYC, no matter how the run was triggered.

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
- **Some settings have no visible toggle and may be silently off.** Validate Fields, Validate Documents, Send Reminder, and Trigger AML all default to "off" unless explicitly turned on behind the scenes, and none of them show up on the standard configuration form out of the box. A newly set-up agent can silently skip the completeness check, document checks, reminder emails, or AML — with no issues showing up at all, so the report looks unexpectedly clean. If checks seem to be getting skipped, confirm with your CapHive contact that these settings are actually turned on.
- **KYC not yet marked complete by the investor.** The agent only looks at records the investor has marked complete. Records still in progress are simply left out of a batch run — that's expected behavior, not a bug, even though it can look like "nothing happened."
- **Leaving the expiry warning window blank doesn't turn warnings off.** If you clear out the Expiry Warning Days field expecting to disable advance warnings, the agent instead falls back to its default 60/30/15-day windows. The only way to fully disable expiry checking is to set Check Expiry itself to "No."
- **Document names have to match closely.** The "required document uploaded" check matches document names exactly, including case. The "document content matches form" check is a little more forgiving (case-insensitive), but still requires a close name match. A document uploaded under a slightly different label than expected will be reported as missing even though a similar file is right there on the record.
- **Running the same record from two places at once.** A manual run and a scheduled run both update the same report for that record, and only one "latest" version is kept. If you trigger a manual run while a scheduled run is still in progress, their updates can interleave — whichever finishes last wins.
- **Re-running an already-resolved record doesn't reconcile outside changes.** A re-run replaces the issue list from scratch, so previously-resolved issues are correctly cleared — but if something was changed outside the KYC record itself (for example, AML was triggered manually), the agent has no way to know about that and won't reflect it.

## 9. FAQ

**Q: I ran the agent and the report shows zero issues, but I expected some checks to run. What happened?**
A: Check with your CapHive contact whether Validate Fields and Validate Documents are actually turned on for this agent. These two settings have no visible toggle by default, so on a freshly set-up agent they may be off — which means the completeness and document checks are silently skipped rather than run.

**Q: The report says "Ready" but no AML report was generated. Why?**
A: Look at the AML section of the report. If it says no active team member was found, add or activate an employee for the entity — AML needs someone to act as requestor. If Trigger AML is turned off, that step is skipped regardless of how everything else looks.

**Q: A document I uploaded is being flagged as missing even though I can see it on the record.**
A: The document-presence check matches the required document's expected label to the uploaded document's name exactly, including case. Double-check that the uploaded document's name matches the expected label or the configured required-document name exactly, down to spacing and capitalization.

**Q: Will this agent run automatically when an investor uploads a new document?**
A: Not currently — even though the agent's description mentions automatic triggers, there's no automatic trigger wired up for document uploads today. Set up a daily or weekly schedule on the agent's Schedule tab, or trigger it manually from the KYC record.

**Q: Why didn't the expiry reminder email get sent even though the KYC shows "expiring soon"?**
A: Confirm Send Reminder is actually turned on for this agent — it has no visible toggle by default, so it may simply be off. Also confirm the entity has active team members; the reminder goes to active employees, and if there are none, there's effectively no one to send it to.
