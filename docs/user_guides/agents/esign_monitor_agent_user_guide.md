# E-Sign Monitor — User Guide

The E-Sign Monitor keeps watch over every document that has been sent out for e-signature within your entity. Each time it runs, it flags signature requests that have been sitting unsigned too long, and documents that expired, were cancelled, voided, or failed — then emails a status report to your team. It checks the whole entity in one pass (not one document or fund at a time), so it's well suited to Company Admins and ops teams who want a daily pulse on the e-sign pipeline.

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

The agent looks at the entity as a whole — not one document or fund — and only considers documents that were deliberately routed through the e-sign workflow. Anything that was never sent for e-signature is left out entirely.

**What happens when it runs, in order:**

1. **Gets started** — sets up a fresh tracker to collect findings for this run.
2. **Finds documents waiting on a signature** — looks for any document still sitting in "requested" status for longer than your configured reminder window, where at least one signer has an email on file.
3. **Flags expired or failed documents** — if this check is switched on, finds documents that have expired, been cancelled, voided, or failed. If switched off, this step is skipped and simply notes that it was skipped.
4. **Notifies your team** — puts together the details for every pending document (who still needs to sign), then sends a single combined email covering both pending and expired/voided/failed documents.
5. **Saves the report** — stores the results of the run so you can review them later. This agent always finishes in a "ready" state — it doesn't have a "blocked" outcome.

**Important:** this agent only observes and reports — it never resends, re-triggers, or otherwise touches a document. The email it sends says explicitly: "No action was taken on any document — this is a notification only." If a document needs to be resent for signature, an ops user has to do that manually from the document's page.

---

## 2. Inputs

### Configuration fields (Edit page)

| Field | Type | Default | What it controls |
|---|---|---|---|
| Send e-sign reminders | Select (Yes/No) | Yes | **This toggle currently has no effect.** It appears in the settings form, but nothing in the agent's behavior actually checks it — turning it on or off doesn't change which documents get flagged or whether the email goes out. Treat it as decorative for now. |
| Flag expired/voided documents | Select (Yes/No) | Yes | When set to Yes, the agent checks for expired, cancelled, voided, or failed documents and lists them as blocking issues in the report. When set to No, that check is skipped and the report simply notes it didn't run. |
| Reminder after (days) | Number | 3 | How many days a document can sit in "requested" status before the agent flags it as pending. The clock is measured from the last time the document record was updated. |

### Other things that feed into the run

- **Which documents get checked**: only documents belonging to this entity that were actually sent for e-signature — anything not sent through e-sign is ignored.
- **Who gets the email**: the agent looks for a list of employees tagged for e-sign notifications. There's currently no settings-page field to set that tag, so in practice it's usually empty — when it is, the agent falls back to sending the report to the entity's main contact email instead.
- **No AI/LLM setup needed.** This agent works entirely off straightforward rule checks — it doesn't call out to any AI model.

---

## 3. Enabling the Agent

- **Where it's switched on**: Admin → Edit Entity → Support Agents section. A Company Admin checks the "E-Sign Monitor" box and saves.
- **AI key needed?** No — this agent never calls an AI model.
- **Who can manage it**: only Company Admin users can set up, configure, or run this agent.

If the agent isn't enabled for your entity, the **Run Now** button on its page is disabled, with a tooltip telling you to contact your administrator.

---

## 4. Accessing and Running the Agent

1. Navigate to **AI → Support Agents**.
2. If this is the first time anyone has set up agents for your entity, click **Setup All Agents** once — this provisions the E-Sign Monitor along with its default settings and daily schedule.
3. Click the **E-Sign Monitor** card to open its page.
4. On the **General** tab, click **Run Now**.

Unlike some agents (for example, the KYC Onboarding Agent, which you can trigger from an individual investor's record), there's no per-document trigger for this one — the only thing you can run it against is the entity as a whole. After you click **Run Now**, the check runs in the background; you won't see a live, step-by-step progress view for this particular agent — the result simply appears once the run finishes and the report is saved.

---

## 5. Scheduling

The agent comes with a default daily schedule, set up automatically by **Setup All Agents**: it runs once a day at **08:00 Asia/Kolkata** time. You can change the frequency, time, or who gets notified on failure, partial success, or full success from the agent's **Schedule** tab — just toggle it on, set the frequency and run time, and choose your notification preferences. Scheduled runs produce exactly the same kind of report as a manual run.

---

## 6. Where to Find the Output

- **General tab → "View Report" link** — shows the most recent run.
- **Execution History tab** — every past run, with its status and how long it took; click any row to see the full report.
- **Email** — sent to the recipients described above. The email includes:
  - A summary banner whose tone reflects severity — red if any documents expired, yellow if only pending signatures were found, green/"All Clear" if neither.
  - A **Pending Signatures** table listing each stuck document, how long it's been waiting, and who still needs to sign.
  - An **Expired / Voided** table listing each flagged document and its status, noting these "cannot be automatically resent" and must be re-initiated manually from the document's page.
  - A closing note confirming that no action was taken automatically.
  - A subject line that's built on the fly, for example: `[E-Sign Alert] 3 pending + 1 expired — Acme Fund`.

---

## 7. Understanding the Report

Every finding from the run is recorded in the report with one of three severities:

- **Info / "all clear"** — no documents pending, no expired/voided/failed documents found, or a check was deliberately skipped. Nothing for you to act on.
- **Warning** — a document is pending past your reminder threshold, or a document was included in the notification email along with its list of outstanding signers.
- **Blocking** — a document has expired, been cancelled, voided, or failed. This is the only severity that represents a real problem requiring an ops user to step in and manually re-initiate the signature request.

Even when blocking issues are found, the report itself always finishes in a "ready" state — this agent doesn't have a "blocked" outcome the way some others do. The blocking label is there to draw your team's attention; it doesn't stop or gate any other workflow.

---

## 8. Where It Can Fail

| Scenario | Trigger | What you'll see | What to do |
|---|---|---|---|
| Turning off "Send e-sign reminders" expecting reminders to stop | Toggled to No (or Yes) | No change at all — pending-document detection and the email still run exactly the same either way, because this setting isn't actually wired up yet. | Don't rely on this toggle. If you want to stop the report from going out, disable the agent's schedule, or turn the agent off for the entity, instead. |
| No pending or expired documents found | Entity has no documents sent for e-sign, or everything is current/signed | The pending and expired checks both come back clean; the notify step is skipped with the message "Nothing to report — notification skipped." No email goes out. | Expected behavior on a clean pipeline. Check Execution History to confirm the run completed successfully rather than assuming something broke. |
| No one configured to receive the email | The notification tag is empty (it usually is, since there's no UI field for it yet) and the entity's main contact email is also blank | The notify step is skipped with "No email recipients configured — set notify_tag in agent settings." The report still saves, but nobody is told. | Make sure your entity has a main contact email set (Admin → Edit Entity). There's currently no settings-page way to set the notification tag directly — that would require a manual backend change. |
| A document's signers have no email on file | Every signer listed on a document is missing an email address | That document is left out of every check entirely — it never shows up in the report, even if it's genuinely stuck waiting on a signature. | If a document you expect to see flagged is missing from the report, check whether its listed signers actually have email addresses on file. |
| Reminder-window edge case | A document was last updated exactly on the reminder-day boundary | The check only flags documents older than the threshold, not exactly at it — so a document updated exactly N days ago won't be caught until the next day's run. | If you need same-day flagging, lower the "Reminder after (days)" setting by one. |
| Expired documents are always reported as "cannot be automatically resent" | Expired/voided check is on and a document has expired, been cancelled, voided, or failed | These are always shown as blocking issues with an instruction to handle them manually — there's no automatic resend, by design. | Re-initiate the signature request manually from the document's page. |
| No documents have ever been sent for e-sign in this entity | New entity, or one that doesn't use the e-sign workflow | Both checks come back empty every time, and the notify step is always skipped — the agent essentially does nothing each day. | Expected. There's nothing to disable; the agent simply has nothing to report until your entity starts sending documents for e-signature. |
| Schedule timezone confusion | Schedule is set to 08:00 Asia/Kolkata, but you expected it in your own local time | The run fires at 08:00 in whatever timezone is configured on the Schedule tab — not your browser's local timezone. | Check the timezone shown on the **Schedule** tab before assuming the run time is wrong. |
| Running it manually right after a scheduled run | Two runs happen close together and find the same stuck documents | There's no deduplication — each run starts fresh and re-sends the same pending/expired list if the underlying documents haven't changed. Running it twice in a day can send two nearly identical emails to the same people. | If you want to avoid duplicate emails, avoid manually clicking Run Now on a day the schedule has already fired, or adjust the schedule instead. |

---

## FAQ

**Q: I turned off "Send e-sign reminders" but the report still shows pending documents. Is that a bug?**
A: No — that setting isn't connected to the agent's behavior yet. It has no effect on what gets detected or emailed. The only thing controlling pending detection is "Reminder after (days)"; there's currently no way to fully suppress that check.

**Q: Does this agent ever actually resend a document for signature?**
A: No. It only observes and notifies — it never modifies a document. Every email it sends says so explicitly. Resending has to be done manually from the document's page.

**Q: The agent ran but no email arrived. Why?**
A: Either there was nothing to report (no pending or expired documents — expected, no email needed), or there was no one configured to receive it (no notification tag set and no entity contact email). Check the Execution History detail for the exact reason.

**Q: A document has been stuck for over a week but never shows up in the report. Why?**
A: Check that the document's signers actually have email addresses on file — documents where every signer is missing an email are left out of every check this agent runs.

**Q: Can I change who receives the report?**
A: There isn't a settings-page field for this yet — the agent falls back to the entity's main contact email. Setting up a tag-based recipient list would require a direct backend configuration change.
