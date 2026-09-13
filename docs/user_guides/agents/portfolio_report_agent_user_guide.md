# Portfolio Report Agent — User Guide

The Portfolio Report Agent is the AI engine behind **AI Portfolio Reports** — investment-grade evaluation documents generated per portfolio company from uploaded pitch materials. It does not behave like a typical Support Agent: it has no report history of its own, no useful schedule, and no fund- or entity-level batch run. Instead, it generates or refines one report **section** at a time, on demand, from the AI Portfolio Reports area of the product.

> **Where to find it:** There is no menu entry: open [**AI Portfolio Reports**](/ai_portfolio_reports) and click **New Report**, or open a portfolio company's documents folder (stakeholder page → **Misc → Documents**) and choose **Actions → Create AI Portfolio Report**. The folder menu item needs the Portfolio Company Agent enabled for your entity.

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
9. [Frequently Asked Questions](#frequently-asked-questions)

---

## 1. What This Agent Does

This agent works on one report **section** at a time — not on a whole portfolio company, and not on the entity as a whole. For each section, it:

1. **Gets ready** — uses the entity's agent record: **Setup All Agents** creates it as "Portfolio Report", and if none exists one is created automatically the first time it's needed, named "Portfolio Report Generator."
2. **Loads the source documents** — uses already-extracted document text if it's available, or pulls it fresh from the report's linked document folder otherwise. In normal use, the report's linked documents (pitch deck, financials, etc. — PDF, text, Markdown, Excel, or PowerPoint files; Word files are not read) are downloaded and their text extracted once — at most 10 documents and the first 5,000 characters of each — then that same extracted text is reused across every section of the report so it isn't re-processed from scratch each time.
3. **Optionally searches the web** — only when web search is turned on for that section. The company name is identified from the documents using a quick AI lookup, one or more search queries are built to fit the section (for example, a news-style search for "Recent Updates & Developments" or "Negative News," a broader search for "Key Risks" or "Competition Analysis"), and those searches run at the same time.
4. **Picks the right template** — selects a structured outline for the type of section being generated (e.g. Company Overview, Key Products & Services, Financial Snapshot, Market Size & Target, SWOT Analysis, Founders & Shareholders, Raise History, Valuations & Funding Trend, Recent Updates & Developments).
5. **Decides whether to generate or refine** — the first automatic pass and **Regenerate with web search** generate content; **Regenerate with AI** refines the existing content using the instruction you typed (it refuses an empty instruction).
6. **Generates or refines the content**:
   - **Generate** — builds the section from the template, the document content, and the web search results (if any), then sends that to your entity's configured AI model. If web search is on and the section already has document-based content, it instead generates only the new web-sourced material and adds it underneath as "Additional Insights from Web Search," rather than rewriting the whole section from scratch.
   - **Refine** — uses a separate, dedicated AI session (always OpenAI's gpt-4o with CapHive's platform OpenAI key, regardless of which AI provider or LLM keys your entity has configured) that remembers up to your last 10 rounds of edits to that section, so follow-up instructions like "make this more concise" or "add a competitor comparison" build naturally on what came before.
7. **Saves the section** — the new content is saved as either the document-only version or the web-enhanced version of that section, and the section is marked as not yet reviewed.

Two section types are handled differently: **Custom Charts** is skipped by the first automatic pass and hidden from the section list (add charts to any section with **Insert Chart** instead), and **Investment Fit Evaluation** is first scored by its own generator against the selected Investment Criteria Template — but when you regenerate it later, it goes through this agent like any other text section.

## 2. Inputs

This agent has **no user-configurable generation settings today**. It exists in the system mainly so it can be grouped under the "Portfolio" category — its Edit page has no generation settings form or custom settings panel; the only relevant option there is **Enable Chat Assistant**, which controls the report page's chat bubble. Everything that functions like configuration happens implicitly, through what you choose each time you generate or refine a section (whether to refine vs. generate fresh, whether web search is on, what instruction you type, and which documents the report is linked to).

| Field | Type | Default | What it controls |
|---|---|---|---|
| — | — | — | No user-configurable generation fields exist for this agent. |

### Non-config data inputs

| Input | Source |
|---|---|
| Pitch documents (PDF, text, Markdown, Excel, PowerPoint; Word files are not read) | For reports created with **New Report**, the portfolio company's **Company Evaluation Agent** sub-folder; for reports created from a folder's **Actions** menu, that folder |
| Investment Criteria Template | Selected (or created) when the report is set up; required for the Investment Fit Evaluation section — that section shows a placeholder if no template is selected |
| Web search results | Live web searches, run only when web search is turned on for a given section |
| Prior refinement history | The last 10 rounds of edit instructions and responses for that section, used only by the refine path |

## 3. Enabling the Agent

There's no feature toggle visible to end users for this agent — **Setup All Agents** creates its agent record ("Portfolio Report"), and if it doesn't exist one is created automatically the first time it's needed (when generating a report's first section), rather than requiring an administrator to turn anything on first.

The feature does require an AI provider key: section generation uses your entity's default AI model. The refine path (**Regenerate with AI**) always uses OpenAI's gpt-4o with CapHive's platform OpenAI key, not the keys under **Agents → LLM Keys**, so adding your own OpenAI key doesn't affect it.

No Support Agent feature toggle gates the AI Portfolio Reports pages. The **Create AI Portfolio Report** item on a portfolio company folder's **Actions** menu is the exception: it needs the Portfolio Company Agent flag.

## 4. Accessing and Running the Agent

The **Portfolio Report** card on the Agents page has a **Run Now** button, but it has no report section to work on, so it produces nothing useful — this agent is used entirely from the **AI Portfolio Reports** feature:

1. Open [**AI Portfolio Reports**](/ai_portfolio_reports) (there is no menu entry) and click **New Report**, or use a portfolio company folder's **Actions → Create AI Portfolio Report**. On the New Report form, select the portfolio company and optionally pick or create an Investment Criteria Template.
2. Once created, the report is linked to the company's document folder, and every section except Custom Charts is generated once automatically, in sequence, with a short pause between sections.
3. Open the report's **show page** to review the generated sections, one at a time, in a section-by-section editor.
4. To refine a section: type an instruction describing the change and click **Regenerate with AI** (an empty instruction is refused with "Please enter a prompt…"). To generate fresh web-sourced content, tick **Regenerate with web search**. The new content appears directly on the page once it's ready.
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

Supported sections span company narrative (Company Overview, Key Products & Services, Founders & Shareholders, Recent Updates & Developments), financials (Financial Snapshot, Custom Charts — hidden from the section list), market context (Market Size & Target, SWOT Analysis, Competition Analysis), funding history (Raise History, Valuations & Funding Trend), risk (Key Risks, Operational Red Flags, Negative News), diligence (AML/KYB Check), deal terms (Investment Ask), and a template-driven Investment Fit Evaluation score.

## 8. Where It Can Fail

- **Missing or incomplete source documents.** If the report's folder has no documents, or only documents in unsupported formats (including Word files), every text-based section is generated purely from the AI's general knowledge with no real grounding in the company's actual materials — there's no warning shown to the user when this happens; the section simply generates with weaker or more generic content than expected.
- **Web search depends on a quick AI lookup succeeding first.** Identifying the company name for web search is itself a small AI step; if that comes back blank and there's no company name on file to fall back on, web search context is silently skipped for that section with no visible error.
- **Refine always uses OpenAI's gpt-4o with CapHive's platform key, regardless of your entity's AI settings.** The first draft uses your entity's configured model and LLM keys, but **Regenerate with AI** ignores them — so it can fail even when generation works, and adding your own OpenAI key doesn't fix it. Contact CapHive support if refinement fails.
- **Investment Fit Evaluation quietly does nothing without a template.** If no Investment Criteria Template was selected for the report, that section simply shows a "Not Configured" placeholder rather than failing the report — easy to miss, since the rest of the report generates normally around it.
- **The initial batch generation skips any section that already has content.** If that first automatic pass is retriggered (for example, after a partial failure), sections that already generated successfully are left untouched, and only the still-blank sections are processed. This is usually what you want, but it also means a section with bad or incomplete content from a failed first attempt won't be retried automatically — it has to be manually regenerated from the report's page (with an instruction, or via **Regenerate with web search**).
- **Web-enhanced content is only appended, never used to double-check the original.** When web search adds new material to a section that already has document-based content, the web-sourced content is simply added on at the end — if the original document-based content was wrong or out of date, the web addition doesn't catch or correct it.
- **Failures during the initial batch generation are logged, but not shown to the user.** If a section fails to generate during that first automatic pass, the failure is recorded behind the scenes and the system moves on to the next section — but there's no in-product indicator afterward showing which sections (if any) failed. You'd need to notice a section is still blank and manually regenerate it yourself.
- **There's no on/off toggle for this feature visible to users**, even though one exists conceptually for consistency with other agents — disabling it would have no actual effect, since nothing in the report-generation flow checks it before running.

## Frequently Asked Questions

### Navigation and getting there

**Where do I find AI Portfolio Reports in CapHive?**
There is no sidebar or menu entry: open [**AI Portfolio Reports**](/ai_portfolio_reports) from this link, which lists every report with **Open**, **Edit** and **Delete** buttons and a **New Report** button at the top. The alternative route is from a portfolio company's documents folder (see the next question). See [Accessing and Running the Agent](#4-accessing-and-running-the-agent).

**How do I start a report from a portfolio company's documents?**
Open the portfolio company's stakeholder page ([**Stakeholders → View Stakeholders**](/investors) → open the record), click **Misc → Documents**, then open the folder's **Actions** dropdown and choose **Create AI Portfolio Report (N docs)**. The item only appears on folders owned by a stakeholder of category *Portfolio Company*, and reads "Upload documents first to generate AI Report" when the folder is empty.

**The Create AI Portfolio Report item is greyed out with a lock. Why?**
The folder menu checks the **Portfolio Company Agent** flag (`portfolio_company_agent`), not a Portfolio Report flag; when it is off the item is locked with the tooltip "Portfolio Company Agent is disabled. Contact support to enable it". Ask CapHive support to enable that agent, or create the report from the [New Report form](/ai_portfolio_reports/new) instead.

**Is there a Portfolio Report card on the Agents page?**
Yes. **Setup All Agents** on Company menu (house icon, top right) → [**Agents**](/support_agents) creates a **Portfolio Report** card in the Portfolio category. The card is not where reports are produced: it has no settings, and its **Run Now** has no report section to work on, so always use the AI Portfolio Reports pages.

**Where do I open a report that is still a draft?**
On [**AI Portfolio Reports**](/ai_portfolio_reports), **Open** is disabled for draft reports, so click **Edit**; it takes you to the report's section editor. **Open** becomes available, and **Edit** disabled, once the report is finalised with **Save Report**.

**Where is the chat assistant for a report?**
On the report's section editor page, as a chat bubble in the corner. It only appears when the Portfolio Report agent record exists for your entity and **Enable Chat Assistant** is ticked on that agent's **Edit** page (Company menu (house icon, top right) → **Agents** → **Portfolio Report** → **Edit**).

### Creating, updating and managing reports

**How do I create a report from the New Report form?**
On [**AI Portfolio Reports**](/ai_portfolio_reports) click **New Report**, pick the **Portfolio Company** (or use **+ Create new portfolio company**), check the **Report Date**, optionally use **Add Documents** to upload pitch files, choose an Investment Fit criteria template (existing, new or none) and click **Create Report**. See [Accessing and Running the Agent](#4-accessing-and-running-the-agent).

**Where do the documents for a report come from?**
Reports created with **New Report** read the portfolio company's **Company Evaluation Agent** sub-folder, which CapHive creates under the company's document folder; **Add Documents** on the form uploads straight into it. Reports created from a folder's **Actions** menu read that folder instead.

**How do I change a section's content with AI?**
Open the report, pick the section in the left **SECTIONS** list, type an instruction in the box under the editor (for example "Make it more concise") and click **Regenerate with AI** or press Enter. The button requires an instruction; an empty box shows "Please enter a prompt describing how you want to refine the content".

**How do I add web search results to a section?**
Tick **Regenerate with web search** at the top of the section and confirm "This will generate the section with latest web information". The checkbox only appears on web-eligible sections (such as Company Overview, SWOT Analysis, Competition Analysis, Key Risks and Negative News); untick it to switch back to the document-only version.

**How do I edit a section by hand?**
Click into the section text, which is directly editable, and type your changes, then click **Save Section**. Your edits are saved to whichever version is on screen (document-only or web search) and the section is marked reviewed.

**How do I add a chart to a section?**
Click **Insert Chart**, describe the chart under "Describe the chart you want:", click **Generate Chart** to see a preview, then click **Insert Chart** in the dialog. Charts are built from the figures in the report's documents, so documents without numbers give the AI nothing to chart.

**How do I choose which sections go into the final report?**
Only reviewed sections are included. A section becomes reviewed when you click **Save Section**, and you can include or exclude any section with the tick toggle next to its name in the **SECTIONS** list; the header counter shows how many are reviewed.

**How do I produce, save and export the final report?**
Click **Generate Final Report** on the report page to open the collated view, adjust the text if needed and click **Save Report**. Then use **Export → Download PDF** or **Download Word** on the same page.

**How do I delete a report?**
On [**AI Portfolio Reports**](/ai_portfolio_reports) click **Delete** on the report's row and confirm. **Delete** is available whatever the report's status.

**What permissions do I need?**
The folder route needs permission to view the portfolio company's folder, and **Create AI Portfolio Report** there also needs the Portfolio Company Agent flag on your entity. If you cannot reach the report pages, ask your company admin.

### Why use AI Portfolio Reports

**Why should I use the Portfolio Report Agent?**
Writing an investment memo from a pitch deck and financials takes an analyst hours per company. The agent drafts every standard section (overview, products, financials, market, founders, funding, SWOT, competition, risks, AML/KYB, investment ask) from the uploaded documents in one pass, so the analyst's time goes into checking and refining rather than first drafts.

**What does it let me do that I could not do otherwise?**
It grounds each section in the company's own documents, optionally adds dated web research such as recent news and negative press, scores the company against your own Investment Fit criteria template, and lets you refine a section conversationally before assembling an exportable PDF or Word report.

**Who typically uses it?**
Investment and deal teams evaluating a prospective or existing portfolio company, and analysts preparing investment committee or monitoring memos. The report is internal: nothing is shared with the portfolio company or with investors.

**What happens if I don't select an Investment Criteria Template?**
The report is still created, but the **Investment Fit Evaluation** section shows "Investment Fit Evaluation Not Configured" and is marked skipped. A template can only be chosen on the **New Report** form, so reports created from a folder never get one.

### What happens when I...

**What happens when I click Create Report or Create AI Portfolio Report?**
The report is saved as **Draft** with all standard sections, you are taken to its section editor with the notice "Report created! AI is generating content for all sections (this may take a minute)...", and a background job drafts each empty section from the documents. No one is notified and nothing is emailed; refresh the page to see sections fill in.

**What happens when I click Regenerate with AI?**
The instruction and the current section text are sent to the AI, which rewrites the section while remembering your last 10 refinement rounds for that section. The new text replaces that version of the section and the section is marked not reviewed, so you must save or tick it again to keep it in the final report.

**What happens when I tick Regenerate with web search?**
If the section already has a web version it is simply loaded. Otherwise web searches run for the company and the result is saved as a separate web version; when a document-only version exists, only new web material is generated. The document-only version is kept, so unticking brings it back.

**What happens when I click Save Section?**
The text in the editor is saved to the version on screen and the section is marked reviewed, which counts it in the header counter and includes it in **Generate Final Report**. Nothing else changes and no one is notified.

**What happens when I click Save Report on the final report?**
The collated HTML is stored on the report and its status becomes **Finalized**. On [**AI Portfolio Reports**](/ai_portfolio_reports) the report's **Open** button is enabled and **Edit** is disabled; to change a section, click **Open** and then **Back to Sections**.

**What happens when I export the report?**
PDF and Word exports use the saved final report if you have clicked **Save Report**, otherwise the reviewed sections, and download to your browser. The file is not saved to CapHive's documents and no one is notified.

**What happens when I delete a report?**
The report and all its sections, including refinement history and saved final text, are permanently removed; there is no undo. The uploaded documents stay in the company's folder, so you can create a new report from them.

**Does the agent change anything outside the report?**
No. It only writes to the report's sections (and chart records for inserted charts); it does not change the portfolio company, its KPIs or valuations, and it sends no emails, notifications or tasks. Creating a report with **New Report** does create the **Company Evaluation Agent** folder if it did not exist.

### Troubleshooting and edge cases

**Where's the "Run Now" button for the Portfolio Report Agent?**
There isn't a useful one. The agent only works on a report section, so create a report from [**AI Portfolio Reports**](/ai_portfolio_reports) (**New Report**) or from a portfolio company folder's **Actions** menu, and its sections generate automatically; use the report's page afterwards to refine individual sections.

**Can I schedule this agent to run periodically for all portfolio companies?**
No. There is no schedule, no entity-wide batch mode and no execution history for it; it is a per-report, per-section, on-demand generator only. See [Scheduling](#5-scheduling).

**Regenerate with AI fails even though the first draft worked.**
The first draft uses your entity's configured AI model, but **Regenerate with AI** always uses OpenAI's gpt-4o with CapHive's platform OpenAI key, not the keys under **Agents → LLM Keys**. If it fails, contact CapHive support; adding your own OpenAI key does not change this path.

**A section looks like it was never generated.**
Failures during the first automatic pass are logged but not shown on screen, and a later pass skips any section that already has content. Open the section and use **Regenerate with AI** (with an instruction) or **Regenerate with web search** to fill it. See [Where It Can Fail](#8-where-it-can-fail).

**Why does my Investment Fit Evaluation section just say "Not Configured"?**
No Investment Criteria Template was selected on the **New Report** form, or the report was created from a folder, which never sets one. The section editor has no template picker, so create a new report from **New Report** and choose a template there.

**The report ignores my Word document. Why?**
Text is extracted from PDF, TXT, Markdown, Excel and PowerPoint (.pptx) files only; `.docx` files are downloaded but not read. Only the first 10 readable documents are used, and only the first 5,000 characters of each, so put the key material early in a PDF.

**I don't see a Custom Charts section in the list. Where is it?**
Custom Charts is hidden from the **SECTIONS** list and not generated in the first pass. Add charts to any section with **Insert Chart** instead.

**I asked the chat assistant about KPIs across my whole portfolio and it didn't have an answer.**
The chat assistant only has the single report's pitch documents plus a web search tool, not your portfolio data. The sample questions shown for it are cross-portfolio, but questions spanning multiple companies are outside what it can answer.

**Can I reopen a finalised report for edits?**
Yes. Click **Open** on the report's row, then **Back to Sections**; change and save sections, then click **Generate Final Report** and **Save Report** again. **Generate Final Report** always rebuilds from the currently reviewed sections, so manual edits made only on the collated page are replaced unless you save them again.

## Related Guides

- [AI Features](../ai_features_user_guide) — the AI Portfolio Reports screens, templates and exports in more detail.
- [Support Agents](../support_agents_user_guide) — the Agents page, LLM keys and the chat assistant setting.
- [LLM Configuration](../llm_configuration_guide) — the provider keys used for first drafts and chat.
- [Document Management](../document_management_user_guide) — uploading pitch files to a portfolio company's folder.
- [Portfolio Company Agent](portfolio_company_agent_user_guide) — the agent whose flag unlocks the folder menu item.
- [Presentation Analyst Agent](presentation_analyst_agent_user_guide) — AI analysis of a single uploaded presentation.
