# Template Fix Agent — User Guide

## What it does

Word templates that generate your legal documents — commitment agreements, KYC
forms, notices — sometimes have problems that only show up once a document is
generated: clause numbers that duplicate or skip, a section that leaves a large
blank gap partway down a page, or a section that always appears even though it
should only apply to certain investors.

> **Where to find it:** Open the template document's page (for example from Sidebar → [**Documents**](/documents) or the owning record's **Documents** tab) and click **Fix Me**; the result appears on the same page. Needs the **company_admin** role, edit rights on the template and an LLM key under [**Agents → LLM Keys**](/support_agents/llm_keys).

The Template Fix Agent lets you describe a problem like this in plain English on
the template itself. It reads through the template, works out what's causing the
problem, fixes it, and hands you back a new draft to review — the original
template is never changed. Nothing is replaced automatically; you decide whether
the draft is right and, if so, upload it in place of the old template yourself.

## Who can use it

The **Fix Me** button appears only on a document marked as a template, and only for
company administrators who also have edit rights on that document, since it makes
structural edits to the templates that generate your firm's legal documents.

## Setting it up

Nothing to configure ahead of time — the assistant is created automatically the
first time someone clicks **Fix Me**. The one prerequisite is that your firm has
at least one AI provider key entered; if none is configured, the Fix Me dialog
will say so and won't let you submit. See the **LLM Configuration Guide** to add
a provider key and pick a default model.

## Day-to-day flow

1. **Open the template** you're having trouble with, from its Documents page.
2. **Click Fix Me.** A dialog opens with a text box and a model picker.
3. **Describe the problem** in your own words — for example, "the clause
   numbers after section 5.2 don't make sense" or "there's a big blank gap on
   the page after clause 5.2.9." The **Model** list is preselected with the
   agent's own model; pick a different one if you want.
4. **Submit.** The fix runs in the background — this can take anywhere from
   under a minute to several minutes for a large document. You'll get a
   notification when it's done.
5. **Review the result** on the template's page: a summary of what was changed
   and why, a list of the individual changes, and a **download link** for the
   fixed draft. Anything the assistant noticed but chose not to touch (for
   example, wording it thought a human should decide on) is called out
   separately.
6. **Replace the template yourself**, once you're satisfied the draft is
   correct, the same way you'd upload any new version.

## What it's good at

- Clause or section numbers that duplicate, skip, or restart partway through
  a document.
- A section that leaves unexpected blank space or pushes content awkwardly
  onto the next page when the document is generated.
- A section that shows up for every investor when it should only apply to
  one type (for example, individual vs. entity investors) — a common
  side-effect of templates that were assembled by combining two versions of
  a section without properly separating them.

## Good to know

- **The original template is never modified.** Every successful run produces a
  brand new, separately named draft document (a run blocked by the content check
  saves no draft) — nothing is overwritten, and nothing goes live until you
  replace the template yourself.
- **It won't delete your legal wording.** If it thinks a passage should be
  removed rather than reorganised, it says so in the summary instead of
  removing it — that decision is left to you.
- **Always review the draft before using it.** Treat it the way you'd treat
  a first pass from a paralegal: check the specific area you asked about,
  and skim the rest before replacing your live template.
- **Larger, more complex templates take longer** and may occasionally run
  out of time before finishing. If the summary says it ran out of time or
  didn't fully confirm its own fix, review the listed changes carefully
  before trusting the draft, or try again with a more specific description
  of the problem.
- A progress panel on the template's page shows each step of the run live.
  Only the latest run's result card is kept — each run replaces the previous
  summary — although earlier "(AI Fix - draft)" documents stay until you delete them.

---

## Frequently Asked Questions

### Navigation and getting there

**Where do I find the Template Fix Agent?**
On the template document itself. Open the document page, for example from Sidebar → [**Documents**](/documents) or the **Documents** tab of the fund, deal or other record that owns the template, and click **Fix Me** in the document's action buttons. There is no separate screen for it. See [Day-to-day flow](#day-to-day-flow).

**I don't see the Fix Me button. Why?**
**Fix Me** only appears when the document is marked as a template, you have edit rights on it, and you have the **company_admin** role. Ordinary uploaded documents and generated documents never show it. See [Who can use it](#who-can-use-it).

**Where do I see the result of a run?**
On the same template's page, in the **Fix Me result** card under the progress panel: a summary, **Changes made**, a **Content check** (paragraph count, word count, word-for-word match) and a **Download fixed draft** button. The notification you receive links back to it with **View result**.

**Where is the fixed draft saved?**
As a new document named "<template name> (AI Fix - draft)" in the same folder and on the same owner as the original template, so it appears alongside it in that record's documents list.

**Does the agent have a card on the Agents page?**
A **Template Fix Agent** record is created automatically the first time anyone clicks **Fix Me**, so it can then appear on Company menu (house icon, top right) → [**Agents**](/support_agents). Runs are still started only from a template's **Fix Me** button.

### Running and managing fixes

**How do I run a fix?**
Click **Fix Me**, describe the problem under **What's wrong?** (for example "clause numbers after 5.2 restart at 1"), optionally change the **Model**, and click **Run Fix Me**. A progress panel on the page shows the run while it works in the background.

**What do I need before I can use it?**
The **company_admin** role and at least one AI provider key for your entity under Company menu (house icon, top right) → **Agents** → [**LLM Keys**](/support_agents/llm_keys). With no key, the dialog shows "No LLM provider is configured for this entity" and **Run Fix Me** is disabled.

**How do I pick which AI model is used?**
The **Model** list in the Fix Me dialog shows the models of every provider that has a key, preselected with the agent's own model (`gemini-3.7-flash` when the agent is first created, or your entity's default). Pick a different one for a single run if needed.

**How do I put the fixed draft into use?**
Download it with **Download fixed draft**, review it, then open the original template, click **Edit** and upload the fixed file in place of the old one, and save. Until you do, the original template keeps generating documents exactly as before.

**How do I get rid of a draft I don't want?**
Delete the "(AI Fix - draft)" document from the owner's documents list like any other document. The original template is unaffected.

**Can I re-run Fix Me on the same template?**
Yes. Each run creates a new draft document, and the **Fix Me result** card then shows the newest run; the previous run's summary is replaced, though its draft document stays until you delete it.

**What file types can it fix?**
Word `.docx` templates, because it edits the document's underlying Word structure. Convert other formats to `.docx` before uploading the template.

### Why use the Template Fix Agent

**Why should I use the Template Fix Agent?**
Structural faults in Word templates, such as broken clause numbering, stray page gaps or sections that show for the wrong investor type, only appear after documents are generated and are tedious to trace in the Word XML. The agent diagnoses and repairs them from a plain-English description, so you do not need a Word expert for each fix.

**What does it let me do that I could not do otherwise?**
Get a repaired draft plus a written explanation of what caused the problem and each change made, with an automatic check that not a single word of the legal text changed. See [What it's good at](#what-its-good-at).

**Who typically uses it?**
Company admins and operations or legal staff who maintain the templates for commitment agreements, KYC forms, notices and other generated documents.

**What happens if I ignore template problems?**
Every document generated from the template repeats the fault, for example wrong clause numbers in every investor's agreement, until someone fixes the template by hand.

### What happens when I...

**What happens when I click Run Fix Me?**
A background job makes a private working copy of the template, lets the AI inspect and repair its structure, renders a preview, and checks that paragraphs, word count and every word are unchanged. If all is well a new "(AI Fix - draft)" template document is created; you get an in-app notification when it finishes or fails. No one else is notified and no investor sees anything.

**Is the original template changed?**
No. The original file and its settings are never modified; the draft is a separate document. It is not tagged for automatic document generation, so it is not used by generation runs.

**What happens if the AI changed any wording?**
The run is stopped at the content check: no draft is saved, the result is marked blocked, and the **Fix Me result** card shows "Could not produce a valid draft" with the difference found. Legal wording can therefore never be altered or deleted by the agent.

**What happens if the run takes too long?**
Each run has a time limit (10 minutes by default). If it runs out, the agent saves whatever state it reached, says so in the summary and marks the result blocked; review those changes carefully or re-run with a narrower description.

### Troubleshooting and edge cases

**Run Fix Me is greyed out. What should I do?**
No AI provider key is configured for your entity. Add one under [**Agents → LLM Keys**](/support_agents/llm_keys) and reopen the dialog. See [Setting it up](#setting-it-up).

**Fix Me says "Please describe the issue before running Fix Me."**
The **What's wrong?** box was empty. Describe the specific problem and where it occurs, then run it again.

**The draft didn't fix my problem.**
Re-run with a more specific description naming the clause, heading or page and what you expected, and try a different **Model**. Check the **Changes made** list to see what the previous run touched.

**Content check shows FAIL. Can I still use the draft?**
When the content check fails no draft is saved, so there is nothing to use; the original template is unchanged. Re-run, or fix that part of the template by hand.

**Can it rewrite or improve clause wording?**
No. It only fixes structure such as numbering, indentation, spacing, pagination and conditional sections, and it reports wording it thinks needs a human decision in the summary instead of changing it.

## Related Guides

- [Document Management](../document_management_user_guide) — uploading, editing and replacing template documents.
- [Support Agents](../support_agents_user_guide) — the Agents page, LLM keys and progress panels.
- [LLM Configuration](../llm_configuration_guide) — adding the provider key Fix Me needs.
- [Capital Commitments](../capital_commitments_user_guide) — commitment agreements generated from templates.
- [Investor KYC](../investor_kyc_user_guide) — KYC forms generated from templates.
