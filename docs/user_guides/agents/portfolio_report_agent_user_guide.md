# Portfolio Report Agent — User Guide

The Portfolio Report Agent is the AI engine behind **AI Portfolio Reports** — investment-grade evaluation documents generated per portfolio company from uploaded pitch materials. It does not behave like a typical Support Agent: it has no report history of its own, no Schedule tab, and no fund- or entity-level batch run. Instead, it generates or refines one report **section** at a time, on demand, from the AI Portfolio Reports area of the product.

A secondary chat assistant is also available on a report's page, letting an analyst ask questions about the company grounded in its uploaded documents and live web search.

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

This agent works on one report **section** at a time — not on a whole portfolio company, and not on the entity as a whole. For each section, it:

1. **Gets ready** — the underlying agent record is created automatically the first time it's needed, named "Portfolio Report Generator."
2. **Loads the source documents** — uses already-extracted document text if it's available, or pulls it fresh from the report's linked document folder otherwise. In normal use, the report's linked documents (pitch deck, financials, etc. — PDF, text, Word/Markdown, Excel, or PowerPoint files) are downloaded and their text extracted once, then that same extracted text is reused across every section of the report so it isn't re-processed from scratch each time.
3. **Optionally searches the web** — only when web search is turned on for that section. The company name is identified from the documents using a quick AI lookup, one or more search queries are built to fit the section (for example, a news-style search for "Recent Updates & Developments" or "Negative News," a broader search for "Key Risks" or "Competition Analysis"), and those searches run at the same time.
4. **Picks the right template** — selects a structured outline for the type of section being generated (e.g. Company Overview, Key Products & Services, Financial Snapshot, Market Size & Target, SWOT Analysis, Founders & Shareholders, Raise History/Valuations, Recent Updates & Developments, Custom Charts).
5. **Decides whether to generate or refine** — based on whether you've typed an instruction for changing existing content, or left it blank to start fresh.
6. **Generates or refines the content**:
   - **Generate** — builds the section from the template, the document content, and the web search results (if any), then sends that to your entity's configured AI model. If web search is on and the section already has document-based content, it instead generates only the new web-sourced material and adds it underneath as "Additional Insights from Web Search," rather than rewriting the whole section from scratch.
   - **Refine** — uses a separate, dedicated AI session (always a specific OpenAI model, regardless of which AI provider your entity has configured as its default) that remembers up to your last 10 rounds of edits to that section, so follow-up instructions like "make this more concise" or "add a competitor comparison" build naturally on what came before.
7. **Saves the section** — the new content is saved as either the document-only version or the web-enhanced version of that section, and the section is marked as not yet reviewed.

Two section types skip this process entirely and are handled by their own dedicated generators instead: **Custom Charts** (built directly from spreadsheet data in the report's documents) and **Investment Fit Evaluation** (scored against a selected Investment Criteria Template).

## 2. Inputs

This agent has **no user-configurable settings today**. Like the Cash Flow Assistant, it exists in the system mainly so it can be grouped under the "Portfolio" category — there's no Edit-page settings form, and unlike the Cash Flow Assistant there isn't even a dedicated custom settings panel. Everything that functions like configuration happens implicitly, through what you choose each time you generate or refine a section (whether to refine vs. generate fresh, whether web search is on, what instruction you type, and which documents the report is linked to).

| Field | Type | Default | What it controls |
|---|---|---|---|
| — | — | — | No user-configurable fields exist for this agent. |

### Non-config data inputs

| Input | Source |
|---|---|
| Pitch documents (PDF, text, Word/Markdown, Excel, PowerPoint, CSV) | The report's linked document folder, created from a portfolio company's "Company Evaluation" folder when the report is first created |
| Investment Criteria Template | Selected (or created) when the report is set up; required for the Investment Fit Evaluation section — that section shows a placeholder if no template is selected |
| Web search results | Live web searches, run only when web search is turned on for a given section |
| Prior refinement history | The last 10 rounds of edit instructions and responses for that section, used only by the refine path |

## 3. Enabling the Agent

There's no feature toggle visible to end users for this agent — the underlying agent record is created and activated automatically the first time it's needed (when generating a report's first section), rather than requiring an administrator to turn anything on first.

The feature does require an AI provider key: section generation uses your entity's default AI model, and the refine path additionally requires an OpenAI credential to be configured, regardless of which provider your entity has set as its default, since refinement is always handled by a specific OpenAI model.

Access to creating and editing AI Portfolio Reports is controlled by the normal permissions for that feature, not by a Support Agent feature toggle — so there's no on/off switch for this feature beyond your existing report permissions; it's simply available whenever an AI Portfolio Report is created.

## 4. Accessing and Running the Agent

There's no "Run Now" button, run history tab, or any other generic Support Agent screen for this agent — it's used entirely from the **AI Portfolio Reports** feature:

1. Navigate to **AI → Portfolio Reports → New**. Select the portfolio company, and optionally pick or create an Investment Criteria Template.
2. Once created, the report is linked to that company's evaluation document folder, and every section is generated once automatically, in sequence, with a short pause between sections.
3. Open the report's **show page** to review the generated sections, one at a time, in a section-by-section editor.
4. To regenerate or refine a section: type an optional instruction (leave it blank to regenerate from scratch, or describe a change to refine the existing content) and toggle web search on or off, then submit. The new content appears directly on the page once it's ready.
5. Mark a section **reviewed** to include it in the final assembled report; sections that haven't been reviewed are left out.

There's no batch or entity-wide mode — every action targets exactly one section of one report.

## 5. Scheduling

Not supported, and not really applicable to how this feature works — there's no standing pipeline to schedule, and no on/off toggle for the feature as a whole. Generation happens once automatically when the report is created, and again on demand whenever you choose to regenerate or refine a section from the report's page.

## 6. Where to Find the Output

- **The report's own show page** — each section's generated content is shown directly in the section editor, with a toggle between the document-only version and the web-enhanced version (if one was generated).
- **Collated Report** — assembled fresh from only the sections marked "reviewed," in their set order — this is the polished, presentable version of the report.
- **Export** — PDF and Word export options are available for sharing the collated report outside the platform.
- Nothing is saved to a Support Agent report history, and nothing is emailed automatically by this agent.
- **Chat assistant (secondary feature)** — a chat panel on the report's show page is grounded in that same pitch document content plus a live web search tool. Sample starter questions shown for this feature include things like "Top 5 portfolio companies by valuation" and "Which companies missed KPIs?" — but these read like cross-portfolio, dashboard-style questions, while the chat assistant's actual knowledge is limited to the one report's own documents. Questions that span multiple companies aren't answerable with the information the chat assistant actually has access to.

## 7. Understanding the Report

A finished AI Portfolio Report is a sequence of sections, each with: a section type, the document-grounded content, the web-enhanced content (if generated, otherwise blank), which version is currently being shown, whether it's marked reviewed (and therefore included in the collated output), the last 10 rounds of refinement history, and any charts embedded in that section.

Supported sections span company narrative (Company Overview, Key Products & Services, Founders & Shareholders), financials (Financial Snapshot, Custom Charts), market context (Market Size & Target, SWOT Analysis, Competitive Landscape), funding history (Raise History/Valuations), risk (Market Risks, Operational Risks, Adverse Media), diligence (AML/KYB Screening), deal terms (Investment Terms), and a template-driven Investment Fit Evaluation score.

## 8. Where It Can Fail

- **Missing or incomplete source documents.** If the report's folder has no documents, or only documents in unsupported formats, every text-based section is generated purely from the AI's general knowledge with no real grounding in the company's actual materials — there's no warning shown to the user when this happens; the section simply generates with weaker or more generic content than expected.
- **Web search depends on a quick AI lookup succeeding first.** Identifying the company name for web search is itself a small AI step; if that comes back blank and there's no company name on file to fall back on, web search context is silently skipped for that section with no visible error.
- **Refine always uses a specific OpenAI model, regardless of your entity's AI settings.** If your entity has only configured a Gemini or Anthropic key (and no OpenAI credential), the "Generate" button will work fine, but "Refine" will fail — because refinement is hardcoded to use OpenAI directly rather than your entity's configured default model.
- **Investment Fit Evaluation quietly does nothing without a template.** If no Investment Criteria Template was selected for the report, that section simply shows a "Not Configured" placeholder rather than failing the report — easy to miss, since the rest of the report generates normally around it.
- **The initial batch generation skips any section that already has content.** If that first automatic pass is retriggered (for example, after a partial failure), sections that already generated successfully are left untouched, and only the still-blank sections are processed. This is usually what you want, but it also means a section with bad or incomplete content from a failed first attempt won't be retried automatically — it has to be manually regenerated from the report's page.
- **Web-enhanced content is only appended, never used to double-check the original.** When web search adds new material to a section that already has document-based content, the web-sourced content is simply added on at the end — if the original document-based content was wrong or out of date, the web addition doesn't catch or correct it.
- **Failures during the initial batch generation are logged, but not shown to the user.** If a section fails to generate during that first automatic pass, the failure is recorded behind the scenes and the system moves on to the next section — but there's no in-product indicator afterward showing which sections (if any) failed. You'd need to notice a section is still blank and manually regenerate it yourself.
- **There's no on/off toggle for this feature visible to users**, even though one exists conceptually for consistency with other agents — disabling it would have no actual effect, since nothing in the report-generation flow checks it before running.

## FAQ

**Q: Where's the "Run Now" button for the Portfolio Report Agent?**
A: There isn't one. This agent only runs in the context of an AI Portfolio Report — create a report from **AI → Portfolio Reports → New** for a specific portfolio company, and its sections generate automatically. Use the report's own page afterward to regenerate individual sections.

**Q: Can I schedule this agent to run periodically for all portfolio companies?**
A: No. There's no schedule, no entity-wide batch mode, and no separate report history — it's a per-report, per-section, on-demand generator only.

**Q: I asked the chat assistant about KPIs across my whole portfolio and it didn't have an answer.**
A: The chat assistant only has access to the single report's uploaded documents, not your entire portfolio. The sample questions shown for this feature include cross-portfolio phrasing, but the assistant itself only ever has one report's pitch documents to draw on — questions spanning multiple companies are outside what it can actually answer.

**Q: Refine isn't working even though Generate works fine.**
A: Refine always uses a specific OpenAI model, regardless of what AI provider your entity has configured as default. Confirm an OpenAI credential is set up for your entity — this is required for Refine even if your entity's default model is Gemini or Anthropic.

**Q: A section looks like it was never generated.**
A: Check whether the initial automatic generation pass hit an error for that section — failures during that first pass are logged behind the scenes but not shown in the product, and the system won't automatically retry a section that already has content, even if that content is blank or a placeholder left over from a failed attempt. Manually regenerate that section from the report's page.

**Q: Why does my Investment Fit Evaluation section just say "Not Configured"?**
A: No Investment Criteria Template was selected when the report was created (or none exists yet). Edit the report to select or create a template, then regenerate that section.
