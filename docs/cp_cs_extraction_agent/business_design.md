# CP/CS Extraction Agent — Business Design

**Status:** Delivered (P1)
**Agent Type:** `CpCsExtractionAgent`
**Parent Feature:** LP Obligation Matrix (see `docs/features/us_gtm/side_letter_obligations.md`)

---

## What This Is

When a fund makes a portfolio investment, the transaction documents (SHA — Shareholders' Agreement, SSA — Share Subscription Agreement, SPA — Share Purchase Agreement) contain legally binding obligations: conditions that must be met before or after closing, ongoing reporting requirements, board approval mandates, regulatory filings, and post-closing deliverables. These are collectively called **Conditions Precedent (CP)** and **Conditions Subsequent (CS)**.

Today, these obligations live in PDF documents reviewed during the deal closing and are then largely forgotten — until a compliance deadline is missed or a regulatory filing is overdue. The CP/CS Extraction Agent solves this by automatically extracting these obligations from investment agreement documents, structuring them for counsel review, and — once approved — projecting them into the task system with due-date alerts.

The CP/CS agent shares the same obligation model, review gate, task projection, and enforcement engine as the Side Letter Obligation Agent (SLO). The difference is the **source**: SLO extracts from side letters attached to capital commitments (LP-facing), while CP/CS extracts from investment agreements attached to portfolio investments (portfolio company-facing).

---

## Who Uses It

| Persona | When | What They Need |
|---------|------|----------------|
| **Deal Team / Legal** | After a deal closing | Know every CP and CS from the investment agreement; track that all pre-closing conditions were met |
| **Compliance / Operations** | Ongoing | Track post-closing deliverables (CS): regulatory filings, board approvals, reporting to co-investors |
| **Fund Manager** | Portfolio review | See which portfolio companies have outstanding conditions; ensure no obligation is missed |
| **Counsel** | Review and approval | Review AI-extracted obligations against the source document before anything goes live |

---

## Use Cases

### UC-1: Board Approval Before Disbursement (Condition Precedent)
A SHA requires the portfolio company's board to pass a resolution approving the investment before the first tranche is disbursed. The CP/CS agent extracts this as a one-time CP with a due date. Counsel reviews and approves it. A task appears on the task board with the deadline. 7 days before the due date, the assigned owner receives a reminder email. Once the board resolution is obtained, the task is marked completed, and the obligation records a fulfillment entry with the date and evidence.

### UC-2: Regulatory Filing After Closing (Condition Subsequent)
An investment agreement requires the portfolio company to file with SEBI within 30 days of closing. The agent extracts this as a one-time CS with a specific due date. After counsel approval, a task is created. The daily enforcement run sends alerts as the deadline approaches, and escalates overdue items to the configured team.

### UC-3: Quarterly Compliance Certificate (Recurring CS)
The SHA requires quarterly compliance certificates delivered within 30 days of each quarter-end. The agent extracts this as a recurring obligation with an RRULE. After approval, a `TaskRecurrenceRule` is created, and the nightly job materializes individual task instances for each quarter. Each can be completed independently and records its own fulfillment.

### UC-4: Regulatory Clearance Notice (Event-Triggered CP)
The agreement requires the investor to be notified within 10 business days of obtaining regulatory clearance. Since the trigger is an event (not a date), the obligation sits **armed** in the matrix — visible, but with no task or deadline. When the event occurs, a user **fires** the obligation with a specific due date, creating a dated task. The obligation stays armed and can be re-fired if the event recurs.

### UC-5: Company-Level Extraction
A fund manager navigates to a portfolio company page (e.g. "Acme Corp") and clicks "Run CP/CS Agent" from the Misc dropdown. The agent finds all portfolio investments under Acme Corp that have tagged documents (e.g. documents tagged "SHA"), extracts obligations from each, and shows step-by-step progress on the investor page. After completion, the page auto-redirects to the CP/CS agent's obligation matrix tab where all extracted obligations appear, grouped by investment.

### UC-6: Re-Extraction After Amendment
An investment agreement is amended, and the updated document is uploaded with the same tag. The agent re-runs and compares the new extraction to existing obligations:
- **Pending** obligations are updated in place (no duplicates)
- **Approved** obligations that changed create a new **delta** obligation for counsel to review beside the original
- **Rejected** obligations are not resurfaced (counsel already said no)

---

## How It Works (User Journey)

### Setup (one-time, per entity)
1. Admin enables the CP/CS Extraction Agent in the Support Agents configuration
2. Admin sets the **investment_doc_tag** (e.g. "SHA" or "SHA,SSA" for multiple document types) — this tells the agent which documents to extract from. When multiple tags are set, the agent extracts from all matching documents on each investment.
3. Admin optionally sets the **notify_tag** to route alerts to specific team members

### Extraction Run
1. User navigates to a portfolio company page → Misc → "Run CP/CS Agent"
2. A confirmation modal explains what the agent will do
3. On confirm, a step-by-step progress UI appears:
   - **Initialize** — resolves portfolio investments under the company
   - **Locate Document** — finds tagged documents on each investment (counter: "SHA — Inv1 (1/3)")
   - **Extract Obligations** — LLM reads each document (counter: "Extracted 5 — Inv1 (1/3)")
   - **Save For Review** — stores obligations as pending (counter: "Saved 5 — Inv1 (1/3)")
   - **Generate Report** — finalizes the run report
4. After completion, the page auto-redirects to the obligation matrix tab

### Review Gate
- All extracted obligations start as **pending review** — they never create tasks or send alerts until counsel approves
- Counsel can:
  - **Approve** — makes the obligation active; tasks and alerts go live
  - **Reject** — permanently discards it; re-extraction will not resurface the same clause
  - **Edit** — correct misclassifications (CP vs CS vs SLO), adjust trigger type, owner, due dates

### Task Projection (after approval)
| Obligation Shape | What Happens |
|-----------------|--------------|
| **One-time / dated** (e.g. "file within 30 days") | Single task created with due date |
| **Recurring** (e.g. "quarterly certificate") | `TaskRecurrenceRule` created; nightly job materializes instances |
| **Event-triggered** (e.g. "on regulatory clearance") | Stays armed — no task until manually fired with a deadline |

### Enforcement (daily, automated)
The daily scheduled run scans all approved obligations:
- **Upcoming** (within reminder window) → email reminder to owner
- **Due today** → email alert
- **Overdue** → escalation email to the configured team tag
- One consolidated email per owner per day (not one per obligation)

---

## Obligation Matrix

All CP/CS obligations appear in the entity-wide **Obligation Matrix** alongside SLO obligations. The matrix supports:
- **Fund filter** — narrows to obligations from investments in a specific fund
- **Stakeholder filter** — narrows to obligations from a specific portfolio company
- **Status filter** — pending review, approved, active, fulfilled, waived
- **Inline edit** — counsel can edit obligation details directly in the matrix row
- **Inline approve/reject** — one-click review from the matrix
- **Fire** — for armed obligations, set a due date and create a task
- **Waive** — end an obligation, removing open tasks but preserving history

### Obligation Detail Page
Clicking an obligation opens a detail page with:
- Key attributes: investor, fund, type, source clause, trigger, next due, owner, reminder lead, recurrence, extraction confidence
- The obligation text as written in the agreement
- Action buttons (approve, reject, fire, waive, revert) based on current state
- **Tasks tab** — all tasks projected from this obligation
- **Fulfillment History tab** — audit trail of completed tasks and manual fulfillments
- **Alerts Sent tab** — log of all reminder and overdue emails sent

---

## Entry Points

| Where | Action | What Happens |
|-------|--------|--------------|
| Portfolio company page → Misc dropdown | "Run CP/CS Agent" | Extracts from all that company's investments |
| CP/CS agent show page | "Run Agent" batch | Extracts from all entity-wide portfolio investments |
| CP/CS agent show page → single PI | Adhoc single run | Extracts from one specific investment |
| Scheduled (daily cron) | Enforcement run | Scans all approved obligations and sends due-date alerts |

---

## Key Design Decisions

1. **Shared obligation model** — CP/CS obligations use the same `SideLetterObligation` model as SLO. The `legal_category` field distinguishes CP vs CS vs SLO. The `sourceable` polymorphic links to `PortfolioInvestment` (CP/CS) instead of `side_letter_id` (SLO).

2. **Mandatory review gate** — Nothing goes live without counsel approval. This is non-negotiable: AI extraction has useful but imperfect accuracy, and false positives creating spurious tasks and alerts would erode trust.

3. **Citation guard** — Obligations without a source clause citation are automatically discarded. This filters out hallucinated or vague extractions that can't be verified against the document.

4. **Idempotent extraction** — Re-running the agent against the same documents does not duplicate obligations. Pending obligations are updated in place; approved obligations generate a delta for review if content changed.

5. **Company-level runs** — Running from a portfolio company page processes all its investments in one go, with step counters showing progress across investments. The step UI stays on the investor page (not redirected to each PI).

---

## What's Deferred

| Item | Reason |
|------|--------|
| **Expandable obligation rows** in the matrix showing inline tasks | Final product enhancement; not needed for demo |
| **Agent-calculated due dates** from estimated closing date | Requires closing date integration; not for demo |
| **Automatic event detection** (fire armed obligations programmatically) | Complex; manual Fire is sufficient for now |
| **MFN cross-comparison dashboard** | Same as SLO; deferred |
