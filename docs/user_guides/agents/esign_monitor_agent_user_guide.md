# E-Sign Monitor — User Guide

The E-Sign Monitor keeps watch over every document that has been sent out for e-signature within your entity. Each time it runs, it flags signature requests that have been sitting unsigned too long, and documents that expired, were cancelled, voided, or failed — then emails a status report to your team. It checks the whole entity in one pass (not one document or fund at a time), so it's well suited to Company Admins and ops teams who want a daily pulse on the e-sign pipeline.

> **Where to find it:** Company menu (house icon, top right) → [**Agents**](/support_agents) → **E-Sign Monitor** card. Run it with **Run Now** on the **General** tab or let its daily schedule run it; change its settings with **Edit**. Needs the *E-Sign Monitor Agent* support-agent flag on your entity (set by CapHive support) and the **Company Admin** role.

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

The agent looks at the entity as a whole — not one document or fund — and only considers documents that were deliberately routed through the e-sign workflow. Anything that was never sent for e-signature is left out entirely.

**What happens when it runs, in order:**

1. **Gets started** — sets up a fresh tracker to collect findings for this run.
2. **Finds documents waiting on a signature** — looks for any document still sitting in "requested" status for longer than your configured reminder window, where at least one signer has an email on file.
3. **Flags expired or failed documents** — if this check is switched on, finds documents that have expired, been cancelled, voided, or failed. If switched off, this step is skipped and simply notes that it was skipped.
4. **Notifies your team** — puts together the details for every pending document (who still needs to sign), then sends a single combined email covering both pending and expired/voided/failed documents.
5. **Saves the report** — stores the results of the run. A **Run Now** run always finishes in a "ready" state. A scheduled run has no step report, so its saved report is marked blocked whenever an expired, voided or failed document was flagged (the Execution History row still shows the run as completed).

**Important:** this agent only observes and reports — it never resends, re-triggers, or otherwise touches a document. The email it sends says explicitly: "No action was taken on any document — this is a notification only." If a document needs to be resent for signature, an ops user has to do that manually from the document's page.

---

## 2. Inputs

### Configuration fields (Edit page)

| Field | Type | Default | What it controls |
|---|---|---|---|
| Send e-sign reminders | Select (Yes/No) | Yes | **This toggle currently has no effect.** It appears in the settings form, but nothing in the agent's behavior actually checks it — turning it on or off doesn't change which documents get flagged or whether the email goes out. Treat it as decorative for now. |
| Flag expired/voided documents | Select (Yes/No) | Yes | When set to Yes, the agent checks for expired, cancelled, voided, or failed documents and lists them as blocking issues in the report. When set to No, that check is skipped and the report simply notes it didn't run. |
| Reminder after (days) | Number | 3 | How many days a document can sit in "requested" status before the agent flags it as pending. The clock is measured from the last time the document record was updated. A field that is present but blank counts as 0 days, which flags every requested document. |

### Other things that feed into the run

- **Which documents get checked**: only documents belonging to this entity that were actually sent for e-signature — anything not sent through e-sign is ignored.
- **Who gets the email**: the agent looks for a list of employees tagged for e-sign notifications. There's currently no settings-page field to set that tag, so in practice it's usually empty — when it is, the agent falls back to sending the report to the entity's primary email instead. The tag is matched as a substring of each employee's tags, so a short tag such as "ops" also matches employees tagged "devops".
- **No AI/LLM setup needed.** This agent works entirely off straightforward rule checks — it doesn't call out to any AI model.

### Setup checklist and warnings

The agent's **General** tab shows a yellow warning banner whenever the run's email could go nowhere. For this agent it flags:

- **A notification tag that matches no employees** — if a tag has been configured behind the scenes but no employee carries it, the report email will never be sent.
- **No tag and no entity contact email** — with neither in place there is no possible recipient at all.
- **The "Flag expired/voided documents" toggle never set** — an unset toggle counts as off, so expired and failed documents would be silently ignored. Set it explicitly to Yes or No.

Note that a run with no valid recipients still finishes and saves its report as "ready" — the banner is the only up-front signal that nobody will be emailed.

---

## 3. Enabling the Agent

- **Where it's switched on**: the *E-Sign Monitor Agent* support-agent flag on your entity, which only CapHive support can set.
- **AI key needed?** No — this agent never calls an AI model.
- **Who can manage it**: only Company Admin users can set up, configure, or run this agent.

If the agent isn't enabled for your entity, the **Run Now** button on its page is disabled, with a tooltip telling you to contact support.

---

## 4. Accessing and Running the Agent

1. Open the Company menu (house icon, top right) → [**Agents**](/support_agents).
2. If this is the first time anyone has set up agents for your entity, click **Setup All Agents** once — this provisions the E-Sign Monitor along with its default settings and daily schedule.
3. Click the **E-Sign Monitor** card to open its page.
4. On the **General** tab, click **Run Now**.

Unlike some agents (for example, the KYC Onboarding Agent, which you can trigger from an individual investor's record), there's no per-document trigger for this one — the only thing you can run it against is the entity as a whole. After you click **Run Now**, the check runs in the background and a live step-by-step progress panel (Initialize, Find Pending, Flag Expired, Notify Team, Save Report) streams on the **General** tab.

---

## 5. Scheduling

The agent comes with a default daily schedule, set up automatically by **Setup All Agents**: it runs once a day at **08:00 Asia/Kolkata** time. You can change the frequency, time, or who gets notified on failure, partial success, or full success from the agent's **Schedule** tab — just toggle it on, set the frequency and run time, and choose your notification preferences. Scheduled runs produce exactly the same kind of report as a manual run.

---

## 6. Where to Find the Output

- **Execution History tab** — every past run, with its status and how long it took; expanding a row shows a one-line summary such as "2 docs reported to team · 1 expired — action needed". There is no full report view in the app — the email carries the details.
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

When you click **Run Now**, the report finishes in a "ready" state even when blocking issues are found. Scheduled runs are the exception: their saved report is marked blocked when a blocking issue was flagged. Either way, the blocking label is there to draw your team's attention; it doesn't stop or gate any other workflow.

---

## 8. Where It Can Fail

| Scenario | Trigger | What you'll see | What to do |
|---|---|---|---|
| Turning off "Send e-sign reminders" expecting reminders to stop | Toggled to No (or Yes) | No change at all — pending-document detection and the email still run exactly the same either way, because this setting isn't actually wired up yet. | Don't rely on this toggle. If you want to stop the report from going out, disable the agent's schedule, or turn the agent off for the entity, instead. |
| No pending or expired documents found | Entity has no documents sent for e-sign, or everything is current/signed | The pending and expired checks both come back clean; the notify step is skipped with the message "Nothing to report — notification skipped." No email goes out. | Expected behavior on a clean pipeline. Check Execution History to confirm the run completed successfully rather than assuming something broke. |
| No one configured to receive the email | The notification tag is empty (it usually is, since there's no UI field for it yet) and the entity's primary email is also blank | The notify step is skipped with "No email recipients configured — set notify_tag in agent settings." The report still saves, but nobody is told. | Ask CapHive support to set your entity's primary email (it is read-only on the company profile) or a notification tag. There's currently no settings-page way to set either yourself. |
| A document's signers have no email on file | Every signer listed on a document is missing an email address | That document is left out of every check entirely — it never shows up in the report, even if it's genuinely stuck waiting on a signature. | If a document you expect to see flagged is missing from the report, check whether its listed signers actually have email addresses on file. |
| Reminder-window edge case | A document was last updated exactly on the reminder-day boundary | The check only flags documents older than the threshold, not exactly at it — so a document updated exactly N days ago won't be caught until the next day's run. | If you need same-day flagging, lower the "Reminder after (days)" setting by one. |
| Expired documents are always reported as "cannot be automatically resent" | Expired/voided check is on and a document has expired, been cancelled, voided, or failed | These are always shown as blocking issues with an instruction to handle them manually — there's no automatic resend, by design. | Re-initiate the signature request manually from the document's page. |
| No documents have ever been sent for e-sign in this entity | New entity, or one that doesn't use the e-sign workflow | Both checks come back empty every time, and the notify step is always skipped — the agent essentially does nothing each day. | Expected. There's nothing to disable; the agent simply has nothing to report until your entity starts sending documents for e-signature. |
| Schedule timezone confusion | Schedule is set to 08:00 Asia/Kolkata, but you expected it in your own local time | The run fires at 08:00 in whatever timezone is configured on the Schedule tab — not your browser's local timezone. | Check the timezone shown on the **Schedule** tab before assuming the run time is wrong. |
| Running it manually right after a scheduled run | Two runs happen close together and find the same stuck documents | There's no deduplication — each run starts fresh and re-sends the same pending/expired list if the underlying documents haven't changed. Running it twice in a day can send two nearly identical emails to the same people. | If you want to avoid duplicate emails, avoid manually clicking Run Now on a day the schedule has already fired, or adjust the schedule instead. |

---

## 9. Frequently Asked Questions

### Navigation and getting there

**Where do I find the E-Sign Monitor in CapHive?**
Open the Company menu (house icon, top right) → [**Agents**](/support_agents) and click the **E-Sign Monitor** card in the **Ops** group. Its page has **General**, **Schedule** and **Execution History** tabs.

**Is there an E-Sign Monitor button on a document?**
No. The agent only runs for your whole entity, from **Run Now** on its **General** tab or from its daily schedule. To act on a single document, open it from [**Documents**](/documents).

**Where do I change its settings?**
Click **Edit** on the agent page. The fields are **Send e-sign reminders**, **Flag expired/voided documents** and **Reminder after (days)**. See [Inputs](#2-inputs).

**Where do I see what it found?**
In the "[E-Sign Alert]" email to the recipients, which lists pending and expired documents. In the app, **Execution History** shows a one-line summary per run such as "2 docs reported to team · 1 expired — action needed", and **Run Now** shows the step panel while it runs.

**Who can see and use this agent?**
Only users with the **Company Admin** role see it on the [**Agents**](/support_agents) page and can edit, run, schedule or delete it. Another company admin grants the role from Company menu → [**User**](/users) → open the user → **Edit**.

### Creating, updating and managing the agent

**How do I create the E-Sign Monitor?**
On Company menu → **Agents**, click **Setup All Agents** → **Run Setup**. It creates the agent with both toggles set to Yes, a 3-day reminder window and a daily 08:00 Asia/Kolkata schedule that is already enabled.

**How do I run it now?**
Open the agent's **General** tab, click **Run Now** and confirm. The five steps stream in a progress panel on the page. See [Accessing and Running the Agent](#4-accessing-and-running-the-agent).

**How do I change how long a document can wait before it is flagged?**
Set **Reminder after (days)** on the **Edit** page and save. A document is flagged once it has sat in requested status, unchanged, for more than that many days; never leave the field blank, which counts as 0 days.

**How do I stop it reporting expired or voided documents?**
Set **Flag expired/voided documents** to No and save. Pending signatures are still reported; there is no toggle that turns the pending check off.

**How do I change who receives the report?**
There is no field for it on the Edit page. By default the email goes to your entity's primary email; to send it to a team instead, ask CapHive support to set a notification tag, then add that tag to each employee under Company menu → **User** → open the user → **Edit** → **Tags**.

**How do I change or pause the schedule?**
On the **Schedule** tab, change **Frequency**, **Run At** or **Timezone** and click **Save Schedule**, or untick **Enable scheduled runs for this agent** to pause the daily email. See [Scheduling](#5-scheduling).

**Can I delete the agent?**
**Delete** on the General tab only works for an agent that has never run; after the first run its reports and logs block it. Pause the schedule instead.

**What permissions and flags are needed?**
The *E-Sign Monitor Agent* flag on your entity, set by CapHive support, and the **Company Admin** role. No LLM key is needed.

### Why use the E-Sign Monitor

**Why should I use the E-Sign Monitor?**
Signature requests stall quietly: an LP never opens the email, a request expires, a provider call fails. The monitor finds every stuck or dead request across the entity each morning and tells your team who still has to sign, before a closing or capital call slips.

**What does it let me do that I cannot do otherwise?**
It checks every document sent for e-signature at once and names the outstanding signers per document. Without it you would open each document's e-sign status one by one.

**Who typically uses it?**
Fund operations, investor relations and compliance teams chasing subscription agreements, side letters and other signed documents. A Company Admin sets it up once.

**What happens if I don't use it?**
Nobody is warned about expired, cancelled, voided or failed requests, so they are discovered only when a signed document is needed. The e-sign workflow itself is unaffected.

### What happens when I…

**What happens when I click Run Now?**
A background job checks documents sent for e-sign, saves a report on your entity and adds a Manual row with your name to **Execution History**. If anything is pending or expired, one email is queued to the recipients. No document is resent, cancelled or changed, and signers are not contacted.

**What happens during the daily scheduled run?**
The same checks run at the **Run At** time and are logged as Scheduled. The team members in **Schedule → Notification Recipients** are told about failed or partially successful runs; the e-sign report itself goes to the report recipients.

**Who gets the report email, and when?**
The employees carrying the configured notification tag, or the entity's primary email if no tag is set, as soon as the run finishes. The subject reads, for example, "[E-Sign Alert] 3 pending + 1 expired — Entity"; no email is sent when there is nothing to report.

**What happens to a document flagged as expired, cancelled, voided or failed?**
It is listed as a blocking issue with "re-initiate manually from the document page" (or "check provider logs" for failures). Nothing happens to the document itself; someone has to send it for signature again.

**Does the agent send reminders to signers?**
No. Despite its name, **Send e-sign reminders** has no effect, and the agent never emails signers or resends a document. Only your internal recipients are emailed.

**Can I undo a run?**
There is nothing to undo, because the agent changes no document. An email already sent cannot be recalled.

### Troubleshooting and edge cases

**I turned off "Send e-sign reminders" but the report still shows pending documents. Is that a bug?**
No. That setting is not connected to the agent's behaviour yet and changes nothing. Only **Reminder after (days)** controls pending detection, and there is no way to switch that check off.

**Does this agent ever actually resend a document for signature?**
No. It only observes and notifies, and every email says "No action was taken on any document". Resending has to be done manually from the document's page.

**The agent ran but no email arrived. Why?**
Either there was nothing pending or expired, so no email was needed, or there was no recipient: no employee carries the notification tag, or no tag is set and the entity has no primary email. Expand the run in **Execution History** and check the yellow banner on the **General** tab.

**A document has been stuck for over a week but never shows up in the report. Why?**
Check that its signers have email addresses; documents where every signer lacks an email are left out. Also check it was sent through e-sign and is still in requested status, and that nobody edited it recently, since the clock restarts on any update.

**Can I change who receives the report?**
Not from the Edit page. The fallback is your entity's primary email, which is read-only on the company profile, so ask CapHive support to change it or to set a notification tag that you then add to employees.

**The yellow banner says no employee carries the tag. What do I do?**
Add the tag named in the banner to at least one employee with an email, under Company menu → **User** → open the user → **Edit** → **Tags**, and save. The banner clears the next time you open the agent.

**Does it check documents in every fund and deal?**
Yes. It scans every document in your entity that was sent for e-signature, whatever it is attached to, and reports them in one email. You cannot limit it to one fund.

**Why did the team get two identical emails today?**
Each run reports the same stuck documents again. Clicking **Run Now** on a day the schedule already ran sends a second copy.

**A document updated exactly N days ago was not flagged. Why?**
Only documents older than the threshold are flagged, so it will appear in the next day's run. Lower **Reminder after (days)** by one if you need it sooner.

**Run Now is greyed out. Why?**
The *E-Sign Monitor Agent* flag is not enabled for your entity and the card shows **Disabled**. Only CapHive support can enable it.

---

## Related Guides

- [Support Agents](../support_agents_user_guide) — setup, Run Now, schedules, Execution History and the warning banner shared by every agent.
- [E-Signing](../esigning_user_guide) — sending documents for signature, statuses and re-initiating a request.
- [Document Management](../document_management_user_guide) — finding the documents the report names.
- [User Role Management](../user_role_management_user_guide) — employee tags and the Company Admin role.
- [Data Quality Agent](data_quality_agent_user_guide) — another deterministic nightly monitor.
- [KYC Onboarding Agent](kyc_onboarding_agent_user_guide) — chases incomplete KYC, often alongside unsigned onboarding documents.
