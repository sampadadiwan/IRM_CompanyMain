# KYC Doc Extractor Agent — User Guide

The KYC Doc Extractor Agent is an AI-powered document reader in the **Onboarding** category. It's the engine behind CapHive's "document-first" KYC experience: an investor uploads their identity and address documents first, the agent reads them with AI and pre-fills the matching KYC form fields, and the investor only has to review and confirm the details rather than type everything in by hand. It is meant to run automatically from the KYC document upload flow; the agent page's **Run Now** and **Schedule** tab also exist, but they run extraction on every KYC in your entity at once.

> **Where to find it:** Company menu (house icon, top right) → [**Agents**](/support_agents) → **KYC Doc Extractor** → **Edit** to manage the extraction rules. It runs when a KYC is started document-first: Sidebar → [**Funds → KYCs**](/investor_kycs) → **New KYC**, or an investor opening a KYC with no documents, then **Continue to Fill Form →**. Needs the *KYC Doc Extractor Agent* flag (set by CapHive support), **Enable Document-First KYC Wizard** on the company profile, an LLM key, and the **Company Admin** role to configure it.

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

The agent has two stages:

1. **Gets ready to read the documents.** It loads the investor's KYC record and prepares a place to collect the outcome of each field it's about to try to fill in.
2. **Reads documents and fills in fields.** Based on which KYC form type the investor is using, the agent looks up the extraction rules configured for that form. Rules are grouped by document — so even if several form fields come from the same document, the agent only makes **one AI request per uploaded document**, asking it to pull out everything it needs in one go. For each configured field:
   - If the document the rule expects hasn't been uploaded yet, that field is marked **skipped** ("Document not uploaded").
   - If overwrite mode is set to **Blank Only** (the default) and the field already has something typed in, it's marked **skipped** ("Field already has a value") — the investor's own typed entry is never overwritten by mistake.
   - Otherwise, the document is sent to AI with a combined extraction prompt; on success, each field's value is written onto the KYC record and marked **extracted**. If the AI's reply leaves a field out, an empty value is written and still counted as extracted.
   - If the AI's response can't be read, or anything else goes wrong, every field tied to that document is marked **error**.
3. All extracted values are saved together in a single save at the end. This save deliberately skips the form's normal validation rules, so a partially-filled KYC can still be saved mid-wizard without erroring out on the fields the investor hasn't reached yet.

From the document-first wizard the agent runs in the background while the investor sees a "Reading your documents…" screen, and what they see afterward is simply their form fields already filled in. **Run Now** on the agent page runs it as a batch over every KYC in the entity, with a batch progress panel and a row in Execution History.

## 2. Inputs

This agent has no standard configuration checklist on its Edit page the way most agents do. Instead, its settings live in a dedicated configuration panel built specifically for this agent.

| Setting | Type | Default | What it controls |
|---|---|---|---|
| Overwrite Mode | Dropdown (in the dedicated config panel) | Blank Only | **Blank Only — only fill fields that are currently empty** never overwrites data the investor already typed in. **Always — overwrite existing field values** replaces the field's value every time extraction runs, regardless of what's already there — even with an empty value if the AI returned nothing for it. |
| Extraction Rules | A set of rules per KYC form type | Empty until seeded automatically | For each KYC form type (Individual / Non-Individual), an ordered list of rules. Each rule has a **Document Label** (the uploaded document to read), an **Extraction Prompt** (the instruction sent to the AI) and a **Target Field** (the KYC field the result is written into). |

Extraction Rules aren't something you type into a single text box — they're managed through an editable rule table in the agent's dedicated configuration panel, with one card per KYC form type, a **+ Add Rule** button and a red **x** to remove a row. They're also seeded automatically the first time **Setup All Agents** is run for your entity, using your entity's actual Individual/Non-Individual KYC form types. The default starter rules are:

- Extract the 10-character PAN from the "Upload Tax ID" document into the `PAN` field
- Extract the full permanent address from the "Upload Address Proof" document into the `address` field

The default Individual KYC form type additionally gets a third starter rule that pulls the investor's full name from the "Upload Tax ID" document. This auto-seeding only happens once, the first time, and only if no rules exist yet — it will never overwrite rules you've since customized.

Other things the agent reads (not configuration, just data):

- Which KYC form type the investor is using, to decide which rule set applies.
- The investor's uploaded documents, matched to each rule by an exact (trimmed) name match against the document label the rule expects.
- The investor's existing field values, to decide whether **Blank Only** mode should skip a given rule.

### Setup checklist and warnings

This agent produces no report of its own, so a broken setup used to be completely invisible — an investor's form simply stayed empty. The agent's **General** tab now shows a yellow warning banner when:

- **No extraction rules are configured at all** — the agent would run and extract nothing. Re-run **Setup All Agents** to seed the starter rules, or add rules in the configuration panel.
- **Rules are tied to a KYC form type that no longer exists** — this happens when form types were rebuilt after the rules were seeded. Those rules silently apply to nothing; re-run **Setup All Agents** or re-create the rules against the current form types.

Also double-check that each rule's document name exactly matches the upload label on the KYC form (for example "Upload Tax ID") — a near-miss name means that rule always reports "Document not uploaded."

## 3. Enabling the Agent

- **Where to toggle:** the *KYC Doc Extractor Agent* support-agent flag on your entity, set by CapHive support. Configuring the agent requires the **Company Admin** role.
- The same flag also gates the **document-first upload screen** itself: that screen only appears when both the flag and **Enable Document-First KYC Wizard** (Company menu (house icon, top right) → **Company Profile** → **Edit**, shown when KYCs are enabled) are on. It is shown on the **New KYC** form unless **Fill Form Manually** is clicked, and on an existing KYC's edit form (for example from an investor's KYC link) only while the KYC has no documents and has not been submitted or verified.
- **AI key required:** every extraction is an AI request, so an AI key must be configured at Company menu → **Agents** → [**LLM Keys**](/support_agents/llm_keys). Gemini Flash is the recommended model here, since it handles large scanned documents well.

## 4. Accessing and Running the Agent

The normal way this agent runs is automatically from the **document-first wizard**: when an investor or staff member uploads the identity and address documents and clicks **Continue to Fill Form →**, the documents are saved and the extraction job is queued to run in the background. The user is shown a "Reading your documents…" screen that automatically moves them on to the (now pre-filled) form once extraction finishes. This works against a single KYC record.

There is **no "Extract from Documents" button** on the KYC form, even though the **Enable Document-First KYC Wizard** help text on the company profile mentions one.

The agent page also has the standard **Run Now** button and **Schedule** tab. Both run extraction on **every KYC in your entity** as a batch — one AI request per uploaded document on every KYC — and are logged in Execution History. In **Always** mode this overwrites values investors have corrected, so use them with care.

If the agent record is missing or its **Enabled** box is unticked, the wizard still appears (it only needs the flag and the company-profile setting), but no extraction job is queued and the user is left on the "Reading your documents…" screen, which never moves on.

## 5. Where to Find the Output

This agent doesn't appear in a dedicated report tab the way most agents do — there's no persisted, browsable report of field-by-field results. Its results show up on the KYC itself:

- From the **document-first wizard**, there's no per-field summary beyond landing on the pre-filled form with "Fields pre-filled from your documents" — the investor simply sees their fields already populated (or not, if extraction failed or was skipped).
- From **Run Now** or a scheduled run, **Execution History** logs the batch run, but not per-field results.
- Detailed, field-by-field outcomes are only visible in **server logs**, which your CapHive technical contact can pull if you need to dig into exactly what happened with a specific document.

## 6. Understanding the Report

There's no "Ready" / "Blocked" status for this agent — it doesn't gate any other process. Each field the agent attempted ends up in one of three states:

- **Extracted** — the value was successfully read from the document and written into the field.
- **Skipped** — either the source document wasn't uploaded, or (in **Blank Only** mode) the field already had a value.
- **Error** — the AI request failed to produce a usable result; the underlying error message is captured for troubleshooting.

## 7. Where It Can Fail

- **No KYC Doc Extractor Agent enabled for the entity.** The wizard is still shown when the flag and the company-profile setting are on, but if the agent record is missing or not **Enabled**, nothing is queued and the user is left on the "Reading your documents…" screen, which never moves on. Set up the flag, the company-profile setting and an enabled agent together — these are separate switches.
- **No extraction rules configured for this KYC's form type.** If there are no rules for the investor's specific form type, the agent records a single "skipped" result — "No extraction rules configured for this form type" — and does nothing further. This looks like "the agent did nothing" rather than an error message you'd notice. If your entity added a new KYC form type after the agent was first set up, re-run **Setup All Agents** to seed rules for it (auto-seeding only happens once, when no rules exist yet).
- **Document name doesn't exactly match what the rule expects.** Matching is based on the document's name matching the rule's expected label exactly (trimmed, case-sensitive). If the uploaded document is named something close but not identical — say "PAN card" instead of the expected "Upload Tax ID" — the field is silently skipped with "Document not uploaded," even though a document clearly was uploaded, just under a different name.
- **The AI's response can't be parsed.** This is caught and recorded as an error for every field tied to that document, but the record is still saved for any other fields that succeeded — one bad document doesn't take down the whole extraction.
- **Any other AI or network problem.** Caught, recorded as an error per field, and logged. The agent moves on to the next document rather than stopping the whole run, so one problematic document doesn't block extraction from the others.
- **"Always" mode used on a record the investor has already partly filled in.** Every matching rule re-extracts and replaces the existing value — including anything the investor manually corrected after a previous extraction, and even with an empty value when the AI's reply leaves that field out. This is intentional for deliberate re-extraction, but it can quietly wipe out manual corrections if toggled on without realizing the consequence.
- **A misconfigured target field.** If a rule's target field name doesn't match a real field on the KYC record, the value is still saved, but tucked away in a spot the form doesn't display. A typo in the target field name (for example, "full_anme" instead of "full_name") won't raise an error — it'll just look like the field never got filled, because nothing on the form is reading that misspelled key.
- **No AI key configured, but the agent is turned on.** The extraction request will simply fail. This isn't treated as a special case — it's recorded in the server log as the same generic "error" outcome as any other failure, and the user just lands on an unfilled form with no indication that the actual cause is a missing AI key.
- **Running the wizard and Run Now at the same time.** Both ultimately try to fill in the same record. If someone clicks **Run Now** on the agent page while a document-first wizard extraction is still running in the background for the same KYC, both will try to save the record — whichever finishes last wins, with no conflict warning.
- **Running against a KYC with no documents uploaded at all.** Every rule resolves to "skipped" and the record is never even saved (since there's nothing new to save), so the investor proceeds to a completely blank form. This is expected — not a malfunction — for a KYC with no documents yet.

---

## 8. Frequently Asked Questions

### Navigation and getting there

**Where do I find the KYC Doc Extractor Agent in CapHive?**
Open the Company menu (house icon, top right) → [**Agents**](/support_agents) and click the **KYC Doc Extractor** card in the **Onboarding** group. Its page has **General**, **Schedule** and **Execution History** tabs.

**Where do investors and staff see the document-first wizard?**
Staff see it when creating a KYC: Sidebar → [**Funds → KYCs**](/investor_kycs) → **New KYC** → pick the type. Investors see it when they open a KYC that has no documents yet and has not been submitted. The screen asks for documents first, with **Continue to Fill Form →** and **Fill Form Manually** buttons.

**Where do I switch the document-first wizard on?**
Company menu (house icon, top right) → **Company Profile** → **Edit**, tick **Enable Document-First KYC Wizard** and save. The wizard only appears when the *KYC Doc Extractor Agent* flag is also enabled for your entity by CapHive support.

**Where do I edit the extraction rules?**
Open the agent and click **Edit**, then scroll to **KYC Document Extractor Configuration**. There is an **Overwrite Mode** dropdown and one card per KYC form type with **Document Label**, **Extraction Prompt** and **Target Field** columns. See [Inputs](#2-inputs).

**Is there an "Extract from Documents" button on the KYC form?**
No. The current KYC form has no such button, even though the company profile help text mentions one. Extraction runs from the document-first wizard; to re-run it for one KYC you would have to remove its documents and go through the wizard again.

**Who can configure it?**
Only users with the **Company Admin** role can edit the agent and its rules. Anyone who can create or fill in a KYC, including investors using their KYC link, triggers extraction through the wizard.

### Creating, updating and managing the agent

**How do I create the KYC Doc Extractor Agent?**
A company admin clicks **Setup All Agents** → **Run Setup** on Company menu → **Agents**. It creates the agent in Blank Only mode and, the first time only, seeds starter rules for your Individual and Non-Individual KYC form types.

**How do I add a new extraction rule, e.g. to pull a date of birth from a passport?**
On the agent's **Edit** page, find the card for the KYC form type and click **+ Add Rule**. Enter the exact **Document Label** of the upload, an **Extraction Prompt** such as "Extract the date of birth. Reply with just the value", and the **Target Field** name, then save.

**How do I change or remove a rule?**
Edit the row's text in the form type's card, or click the red **x** at the end of the row to remove it, then save the agent. Changes apply to the next extraction only; fields already filled stay as they are.

**What should the Document Label and Target Field contain?**
**Document Label** must match the upload's name on the KYC exactly, for example "Upload Tax ID", including capitals. **Target Field** is a KYC column such as `address`, or the name of a custom KYC field; a misspelt name saves the value where the form never shows it.

**How do I choose between Blank Only and Always?**
Pick **Overwrite Mode** on the **Edit** page. **Blank Only** (the default) never touches a field that already has a value; **Always** replaces it on every extraction, including manual corrections.

**What keys and flags does it need?**
The *KYC Doc Extractor Agent* flag (set by CapHive support), the agent's **Enabled** box ticked, **Enable Document-First KYC Wizard** on the company profile, and an LLM key under [**Agents → LLM Keys**](/support_agents/llm_keys). Every extraction is an AI request.

**Should I use Run Now or the Schedule tab for this agent?**
Usually not. Both run extraction for every KYC in your entity at once, which means one AI request per uploaded document on every KYC, and in **Always** mode they overwrite values investors have corrected.

### Why use the KYC Doc Extractor

**Why should I use the KYC Doc Extractor?**
Investors abandon long KYC forms and mistype PAN numbers and addresses. With the wizard they upload documents first and only review pre-filled fields, which is faster for them and gives cleaner KYC data for your team.

**What does it let me do that I cannot do otherwise?**
It reads scanned identity and address documents with AI and writes the values straight into the KYC fields you choose, per KYC form type. Without it every field is typed in by hand.

**Who typically uses it?**
Investor onboarding and compliance teams running LP onboarding at scale; investors experience it as the upload-first KYC screen. A company admin maintains the rules.

**What happens if I don't set it up?**
Investors fill in the KYC form manually as usual; nothing else changes. If the flag and the wizard setting are on but the agent is missing or disabled, investors can get stuck on the processing screen, so set all three together.

### What happens when I…

**What happens when an investor clicks Continue to Fill Form?**
The documents are saved on the KYC, an extraction job is queued and the investor sees a "Reading your documents…" screen. When the job finishes they land on the KYC form with "Fields pre-filled from your documents" and review before submitting. Nobody is notified and nothing is submitted or verified.

**What happens during extraction?**
For each document label in the rules, one AI request reads the uploaded file and returns every target field for it. Values are written onto the KYC and saved once at the end without form validation; missing documents and already-filled fields in Blank Only mode are skipped.

**What happens if extraction fails?**
Fields for that document are recorded as errors in the server log, other documents still extract, and the investor still lands on the form to fill the fields in by hand. No on-screen error is shown in the wizard.

**What happens when I click Fill Form Manually?**
The wizard is skipped and the normal KYC form opens with no extraction. On an existing KYC the wizard does not come back once any document has been uploaded.

**What happens when I click Run Now on the agent page?**
Extraction runs for every KYC in your entity, each logged in **Execution History**, with an in-app summary to you at the end. Values are written directly onto those KYCs; there is no undo.

**Can I undo an extraction?**
No. Extracted values are saved onto the KYC like manual edits, and the previous values are not kept by the agent; correct any wrong value on the KYC form before submitting.

### Troubleshooting and edge cases

**I uploaded documents but the form fields didn't get pre-filled. What should I check?**
Confirm the agent exists and is enabled, that an LLM key is set, and that there are rules for this KYC's form type. Then check each rule's **Document Label** matches the uploaded document's name exactly; a mismatch is skipped silently.

**Why does extraction overwrite a value I already typed in manually?**
**Overwrite Mode** is set to **Always**, which replaces every matching field on every extraction. Switch it to **Blank Only** on the agent's **Edit** page.

**The investor is stuck on "Reading your documents…". What happened?**
The job was never queued because no enabled KYC Doc Extractor agent exists, or it is still waiting in the background queue. Check the agent exists with **Enabled** ticked; the investor can reopen their KYC link, which now shows the normal form because documents are attached.

**The yellow banner says no extraction rules are configured. What do I do?**
Run **Setup All Agents** to seed the starter rules, or add rules on the **Edit** page. Until then the agent runs and extracts nothing.

**The banner says rules reference form types that no longer exist. Why?**
Your KYC form types were rebuilt after the rules were created, so the old rules apply to nothing. Recreate the rules in the cards for the current form types on the **Edit** page.

**A field shows as extracted but it is empty. Why?**
The AI returned no value for that field, and an empty value is still written and counted as extracted. Improve the **Extraction Prompt**, or check that the right document was uploaded under that label.

**A new KYC form type gets no extraction. Why?**
Starter rules are only seeded once, when the agent has no rules at all. Add rules for the new form type's card on the **Edit** page.

**Does this agent ever block KYC submission?**
No. It has no Ready or Blocked status and only pre-fills fields for review. Verification is still done by your team, optionally checked by the [KYC Onboarding Agent](kyc_onboarding_agent_user_guide).

**Where can I see field-by-field results?**
Only in the server logs, which CapHive support can check for a specific KYC. The wizard shows no per-field summary.

---

## Related Guides

- [Support Agents](../support_agents_user_guide) — setup, LLM keys, Run Now, schedules and Execution History shared by every agent.
- [Investor KYC](../investor_kyc_user_guide) — creating KYCs, uploading documents, submitting and verifying.
- [KYC Onboarding Agent](kyc_onboarding_agent_user_guide) — checks KYC completeness after the investor submits.
- [Custom Fields](../custom_fields_user_guide) — KYC custom fields that rules can use as target fields.
- [LLM Configuration](../llm_configuration_guide) — the AI provider key and model every extraction uses.
- [Entities](../entities_user_guide) — the company profile where the document-first wizard is switched on.
