# KYC Doc Extractor Agent — User Guide

The KYC Doc Extractor Agent is an AI-powered document reader in the **Onboarding** category. It's the engine behind CapHive's "document-first" KYC experience: an investor uploads their identity and address documents first, the agent reads them with AI and pre-fills the matching KYC form fields, and the investor only has to review and confirm the details rather than type everything in by hand. This agent never runs on a schedule and has no manual batch button — it runs automatically at specific points in the KYC upload flow.

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

The agent has two stages:

1. **Gets ready to read the documents.** It loads the investor's KYC record and prepares a place to collect the outcome of each field it's about to try to fill in.
2. **Reads documents and fills in fields.** Based on which KYC form type the investor is using, the agent looks up the extraction rules configured for that form. Rules are grouped by document — so even if several form fields come from the same document, the agent only makes **one AI request per uploaded document**, asking it to pull out everything it needs in one go. For each configured field:
   - If the document the rule expects hasn't been uploaded yet, that field is marked **skipped** ("Document not uploaded").
   - If overwrite mode is set to "only fill blank fields" (the default) and the field already has something typed in, it's marked **skipped** ("Field already has a value") — the investor's own typed entry is never overwritten by mistake.
   - Otherwise, the document is sent to AI with a combined extraction prompt; on success, each field's value is written onto the KYC record and marked **extracted**.
   - If the AI's response can't be read, or anything else goes wrong, every field tied to that document is marked **error**.
3. All extracted values are saved together in a single save at the end. This save deliberately skips the form's normal validation rules, so a partially-filled KYC can still be saved mid-wizard without erroring out on the fields the investor hasn't reached yet.

This agent doesn't show a step-by-step progress panel like some other agents. It either runs immediately and finishes before the page reloads (when triggered from the "Extract from Documents" button), or runs in the background (when triggered from the document-first upload flow) — either way, what you see afterward is a quick summary message or simply your form fields already filled in.

## 2. Inputs

This agent has no standard configuration checklist on its Edit page the way most agents do. Instead, its settings live in a dedicated configuration panel built specifically for this agent.

| Setting | Type | Default | What it controls |
|---|---|---|---|
| Overwrite Mode | Dropdown (in the dedicated config panel) | Only fill blank fields | "Only fill blank fields" never overwrites data the investor already typed in. "Always overwrite" replaces the field's value every time extraction runs, regardless of what's already there. |
| Extraction Rules | A set of rules per KYC form type | Empty until seeded automatically | For each KYC form type (Individual / Non-Individual), an ordered list of rules. Each rule names the uploaded document to read, the instruction sent to the AI for that document, and which KYC field the result should be written into. |

Extraction Rules aren't something you type into a single text box — they're managed through an editable rule table in the agent's dedicated configuration panel, with one card per KYC form type and "Add Rule" / "Remove Rule" buttons. They're also seeded automatically the first time **Setup All Agents** is run for your entity, using your entity's actual Individual/Non-Individual KYC form types. The default starter rules are:

- Extract the tax ID number from the "Upload Tax ID" document
- Extract the full permanent address from the "Upload Address Proof" document

The default Individual KYC form type additionally gets a third starter rule that pulls the investor's full name from the "Upload Tax ID" document. This auto-seeding only happens once, the first time, and only if no rules exist yet — it will never overwrite rules you've since customized.

Other things the agent reads (not configuration, just data):

- Which KYC form type the investor is using, to decide which rule set applies.
- The investor's uploaded documents, matched to each rule by an exact (trimmed) name match against the document label the rule expects.
- The investor's existing field values, to decide whether "only fill blank fields" mode should skip a given rule.

## 3. Enabling the Agent

- **Where to toggle:** Admin → Edit Entity → Support Agents section. Requires the **Company Admin** role.
- This same toggle also gates the **document-first upload screen** itself: that screen only appears when both this agent and a separate entity setting for "doc-first wizard" are turned on, the KYC hasn't already been submitted, and no documents have been uploaded yet.
- **AI key required:** every extraction is an AI request, so an AI key must be configured at **AI → Support Agents → LLM Keys**. Gemini Flash is the recommended model here, since it handles large scanned documents well.

## 4. Accessing and Running the Agent

This agent has no Run Now button and no manual batch option on its own page — instead, it kicks in automatically at two points in the KYC document upload flow:

1. **Document-first wizard upload.** When an investor on the document-first wizard uploads their identity and address documents and clicks "Continue to Fill Form," the documents are saved and the extraction job is queued to run in the background. The investor is shown a brief "processing" screen that automatically moves them on to the (now pre-filled) form once extraction finishes.
2. **The "Extract from Documents" button.** This button, shown directly on the KYC form, runs the agent immediately against whatever documents are already uploaded and takes the investor back to the form with a summary message showing how many fields were extracted, skipped, or hit an error. This is the button referenced in the entity settings help text: *"Shows an 'Extract from Documents' button on the KYC form. Requires a KYC Doc Extractor Agent to be configured and enabled."*

Both paths always work against a single investor's KYC record — there's no entity-wide batch run for this agent. If no enabled KYC Doc Extractor Agent exists for the entity, the wizard simply skips extraction with no message, while the "Extract from Documents" button shows an alert: "Document extractor agent is not configured for this entity."

## 5. Where to Find the Output

This agent doesn't produce a step-by-step progress panel and doesn't appear in a dedicated report tab the way most agents do — there's no persisted, browsable report for it. Its results are returned directly to whichever screen triggered it:

- From the **"Extract from Documents" button**, you get an immediate summary message: *"Extracted N field(s) from your documents. X skipped (already filled or document not uploaded). Y error(s) — check server logs."*
- From the **document-first wizard**, there's no summary shown at all beyond landing on the pre-filled form — the investor simply sees their fields already populated (or not, if extraction failed or was skipped).
- Detailed, field-by-field outcomes are only visible in **server logs**, which your CapHive technical contact can pull if you need to dig into exactly what happened with a specific document.

## 6. Understanding the Report

There's no "Ready" / "Blocked" status for this agent — it doesn't gate any other process. Each field the agent attempted ends up in one of three states:

- **Extracted** — the value was successfully read from the document and written into the field.
- **Skipped** — either the source document wasn't uploaded, or (in "only fill blank fields" mode) the field already had a value.
- **Error** — the AI request failed to produce a usable result; the underlying error message is captured for troubleshooting.

## 7. Where It Can Fail

- **No KYC Doc Extractor Agent enabled for the entity.** Both entry points check for an enabled agent before doing anything. If none is found, the document-first wizard silently skips extraction (nothing is queued, no message shown), while the "Extract from Documents" button shows an explicit alert. If you've set this up before and it's still not working, double-check the agent is enabled both as a record and via the entity-level toggle — these are two separate switches.
- **No extraction rules configured for this KYC's form type.** If there are no rules for the investor's specific form type, the agent records a single "skipped" result — "No extraction rules configured for this form type" — and does nothing further. This looks like "the agent did nothing" rather than an error message you'd notice. If your entity added a new KYC form type after the agent was first set up, re-run **Setup All Agents** to seed rules for it (auto-seeding only happens once, when no rules exist yet).
- **Document name doesn't exactly match what the rule expects.** Matching is based on the document's name matching the rule's expected label exactly (trimmed, case-sensitive). If the uploaded document is named something close but not identical — say "PAN card" instead of the expected "Upload Tax ID" — the field is silently skipped with "Document not uploaded," even though a document clearly was uploaded, just under a different name.
- **The AI's response can't be parsed.** This is caught and recorded as an error for every field tied to that document, but the record is still saved for any other fields that succeeded — one bad document doesn't take down the whole extraction.
- **Any other AI or network problem.** Caught, recorded as an error per field, and logged. The agent moves on to the next document rather than stopping the whole run, so one problematic document doesn't block extraction from the others.
- **"Always overwrite" mode used on a record the investor has already partly filled in.** Every matching rule re-extracts and replaces the existing value — including anything the investor manually corrected after a previous extraction. This is intentional for deliberate re-extraction, but it can quietly wipe out manual corrections if toggled on without realizing the consequence.
- **A misconfigured target field.** If a rule's target field name doesn't match a real field on the KYC record, the value is still saved, but tucked away in a spot the form doesn't display. A typo in the target field name (for example, "full_anme" instead of "full_name") won't raise an error — it'll just look like the field never got filled, because nothing on the form is reading that misspelled key.
- **No AI key configured, but the agent is turned on.** The extraction request will simply fail. This isn't treated as a special case — it shows up as the same generic "error" outcome as any other failure, so the investor or staff member sees "N error(s) — check server logs" with no indication that the actual cause is a missing AI key.
- **Running the wizard and the manual button at the same time.** Both ultimately try to fill in the same record. If someone clicks "Extract from Documents" while a document-first wizard extraction is still running in the background for the same investor, both will try to save the record — whichever finishes last wins, with no conflict warning.
- **Running against a KYC with no documents uploaded at all.** Every rule resolves to "skipped" and the record is never even saved (since there's nothing new to save), so the investor proceeds to a completely blank form. This is expected — not a malfunction — for a KYC with no documents yet.

## 8. FAQ

**Q: I uploaded documents but the form fields didn't get pre-filled. What should I check?**
A: First confirm a KYC Doc Extractor Agent is enabled for the entity and that it has extraction rules configured for this investor's KYC form type. Then double-check that the uploaded document's name exactly matches what the rule expects — a mismatch causes a silent skip, not a visible error.

**Q: Why does extraction overwrite a value I already typed in manually?**
A: Check the agent's Overwrite Mode setting. "Only fill blank fields" (the default) never overwrites fields that already have a value; "Always overwrite" replaces every matching field on every extraction run, including values you entered by hand.

**Q: How do I add a new extraction rule, e.g. to pull a date of birth from a passport?**
A: Open the KYC Doc Extractor Agent's Edit page and find the rule table for the relevant form type (Individual or Non-Individual KYC). Click "Add Rule," fill in the document label, the extraction instruction, and the target field, then save.

**Q: The extraction result says "N error(s)" with no further detail in the UI. Where do I look?**
A: Ask your CapHive technical contact to check the server logs — they capture the underlying AI response or error message that the on-screen summary doesn't show.

**Q: Does this agent ever block KYC submission or show up in Execution History?**
A: No. It has no "Ready"/"Blocked" status and doesn't appear in an Execution History tab — it only pre-fills fields for the investor to review. KYC submission and verification are still handled separately by the standard KYC workflow, and optionally double-checked afterward by the KYC Onboarding Agent.
