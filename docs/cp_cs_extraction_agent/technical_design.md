# CP/CS Extraction Agent — Technical Design

**Agent Class:** `CpCsExtractionAgent < SideLetterObligationAgent`
**Pack:** `app/packs/ai/support_agents/`
**Model:** `SideLetterObligation` (shared with SLO, `app/packs/funds/side_letters/`)

---

## Architecture Overview

The CP/CS Extraction Agent is a thin subclass of `SideLetterObligationAgent` that reuses the parent's extraction pipeline, prompt engine, dedup logic, and obligation model. It differs only in:

1. **Target resolution** — operates on `PortfolioInvestment` records (not `CapitalCommitment`)
2. **Document matching** — uses `investment_doc_tag` config field (not `side_letter_doc_label`)
3. **Sourceable link** — obligations link to `PortfolioInvestment` via `sourceable` polymorphic (not `side_letter_id`)
4. **Company-level expansion** — accepts an `Investor` target and expands to all its portfolio investments

```
CpCsExtractionAgent < SideLetterObligationAgent < SupportAgentService
                                                    ├── Trailblazer steps (DSL)
                                                    ├── broadcast_step / mark_step_*
                                                    └── finalize_report
```

---

## Data Model

### SideLetterObligation (shared model)

CP/CS obligations use the same `SideLetterObligation` model with these distinguishing fields:

| Field | CP/CS Value | SLO Value |
|-------|-------------|-----------|
| `side_letter_id` | `nil` | FK to SideLetter |
| `sourceable_type` | `"PortfolioInvestment"` | `nil` |
| `sourceable_id` | FK to PortfolioInvestment | `nil` |
| `legal_category` | `condition_precedent` or `condition_subsequent` | `side_letter_obligation` |

### Convenience Methods

```ruby
# app/packs/funds/side_letters/models/side_letter_obligation.rb

# Works for both CP/CS and SLO paths
def source_investor
  if sourceable_type == "PortfolioInvestment"
    sourceable&.portfolio_company
  else
    investor  # via side_letter → capital_commitment → investor
  end
end

def source_fund
  if sourceable_type == "PortfolioInvestment"
    sourceable&.fund
  else
    fund  # via side_letter → fund
  end
end
```

---

## Trailblazer Step Pipeline

The agent uses 5 steps inherited from `SideLetterObligationAgent`. For **single PI runs**, the parent steps are called via `super`. For **company-level (Investor) runs**, each step is overridden to loop through all portfolio investments with counter messages:

```
initialize_agent → locate_side_letter → extract_obligations → upsert_obligations → generate_progress_reports
```

### Step Override Logic

Each override checks `ctx[:investor_pi_targets]`:
- **Present** → company-level run: loop through all PIs with counter messages
- **Absent** → single PI run: `return super` to delegate to parent

### Step Details

#### 1. initialize_agent

**Single PI:** Delegates to parent. Sets `ctx[:portfolio_investment]`, `ctx[:source_mode] = :portfolio_investments`.

**Company-level (Investor target):**
- Does NOT call `super` (parent expects PI or Commitment, not Investor)
- Manually initializes `@support_agent` and `ctx[:llm]`
- Calls `targets(investor)` to resolve portfolio investments with matching documents
- Stores in `ctx[:investor_pi_targets]` and `ctx[:investor_target]`
- Step message: "Acme Corp: 5 investment(s)"

#### 2. locate_side_letter

**Single PI:** Delegates to parent. Calls `locate_investment_document(ctx)`.

**Company-level:** Loops through `ctx[:investor_pi_targets]`:
- For each PI: sets `ctx[:portfolio_investment]`, calls `locate_investment_document(ctx)`
- Accumulates results in `ctx[:pi_docs]` as `[{ pi:, doc: }]`
- Step message: "SHA Agreement — Inv1 (2/5)"

#### 3. extract_obligations

**Single PI:** Delegates to parent. Calls LLM with `extraction_prompt(:portfolio_investments)`.

**Company-level:** Loops through `ctx[:pi_docs]`:
- Skips entries with `doc: nil`
- For each doc: calls `ctx[:llm].ask(extraction_prompt(:portfolio_investments), with: [doc.file.url])`
- Applies citation guard: `rows.partition { |r| r["source_clause"].present? }`
- Accumulates in `ctx[:all_extracted]` as `[{ pi:, extracted: }]`
- Step message: "Extracted 12 — Inv1 (2/5)"

#### 4. upsert_obligations

**Single PI:** Delegates to parent. Calls `upsert_portfolio_obligations(ctx)`.

**Company-level:** Loops through `ctx[:all_extracted]`:
- For each entry: sets context and calls `upsert_portfolio_obligations(ctx)`
- Dedup per PI: matches on `(sourceable, source_clause, obligation_type)`
- Sets `ctx[:extracted]` with total count for redirect logic
- Step message: "Saved 12 — Inv1 (2/5)"

#### 5. generate_progress_reports

Restores `ctx[:model]` to the Investor (from `ctx[:investor_target]`), then calls `super` which:
- Calls `SupportAgentService#generate_progress_reports` (saves report)
- Finalizes the report status to `:ready`
- Broadcasts `Turbo.visit` redirect to `support_agent_path(support_agent, tab: "obligations")`

---

## Target Resolution

```ruby
def targets(entity_id)
  # Single PI passthrough
  return [entity_id] if entity_id.is_a?(PortfolioInvestment)

  # Portfolio company → scoped to that company's investments
  if entity_id.is_a?(Investor)
    investments = portfolio_investment_targets(entity_id.entity_id, agent_record)
    return investments.where(portfolio_company_id: entity_id.id)
  end

  # Entity ID (batch) → all investments with matching documents
  portfolio_investment_targets(entity_id, agent_record)
end
```

`portfolio_investment_targets` (parent method) queries:
```sql
SELECT pi.* FROM portfolio_investments pi
WHERE pi.entity_id = ?
AND pi.id IN (
  SELECT owner_id FROM documents
  WHERE entity_id = ? AND owner_type = 'PortfolioInvestment'
  AND template IS NULL OR template = false
  AND LOWER(COALESCE(tag_list, '')) LIKE '%sha%'
)
```

---

## Dedup / Upsert Logic

Same as parent `SideLetterObligationAgent`:

```ruby
def upsert_portfolio_row(investment, row, re_extraction)
  existing = SideLetterObligation
    .where(sourceable: investment, source_clause: clause, obligation_type: type)
    .order(:id).last

  case existing&.review_status
  when nil       → create new pending row
  when "pending" → update in place (no duplicate)
  when "approved"→ create delta if content changed
  when "rejected"→ skip (counsel said no)
  end
end
```

Content change detection: checks `title`, `trigger_type`, `frequency_rrule`, `next_due_date`.

---

## Configuration

Agent config stored in `SupportAgent#json_fields`:

| Field | Required | Description |
|-------|----------|-------------|
| `investment_doc_tag` | Yes | Document tag to match (e.g. "SHA", "SSA"). Case-insensitive LIKE match against `documents.tag_list` |
| `default_reminder_days_before` | No (default: 7) | Lead time for pre-due-date reminder emails |
| `overdue_escalation_days` | No (default: 3) | Days after due date before escalation email |
| `notify_tag` | No | Employee tag for routing ownerless alerts. Falls back to company admins |

`config_issues` validates: tag is set, notify_tag matches at least one employee (or a fallback admin exists).

---

## Entry Points and Job Routing

### From portfolio company page (Investor target)

```
investors/show.html.erb
  → form POST to run_support_agents_path
  → SupportAgentsController#run
    → SupportAgentJob.perform_later(target_type: "Investor", target_id: @investor.id, with_steps: true)
      → targets = [Investor.find(target_id)]
      → CpCsExtractionAgent.call(target: investor, ...)
        → initialize_agent handles Investor expansion internally
```

### From agent show page (batch)

```
support_agents/show.html.erb → Run Agent
  → SupportAgentJob with batch_ids_type: "PortfolioInvestment"
    → CpCsExtractionAgent.process_batch(...)
      → run_batch (parent) → CpCsExtractionAgent.call per PI
```

### Scheduled (daily enforcement)

```
AgentScheduleJob → SupportAgentJob(execution_mode: :scheduled)
  → CpCsExtractionAgent.process_batch(execution_mode: :scheduled)
    → ObligationEnforcement.call(support_agent: ...)
      → scans all approved obligations, sends consolidated alerts
```

---

## Turbo Stream Broadcasting

### Step Progress UI

The `_agent_run_modal` partial renders a confirmation modal. On submit:
1. Controller creates a `SupportAgentReport` with step definitions
2. Turbo Stream response replaces `#progress_panel_new` with `_progress_panel` partial
3. The partial includes `turbo_stream_from "support_agent_report_#{report.id}"` — subscribing to the channel
4. Each `mark_step_running/success/failed` broadcasts step circle and progress bar updates
5. `finalize_report` broadcasts the completed panel state

### Auto-Redirect After Completion

```ruby
# SideLetterObligationAgent#broadcast_redirect_to_matrix
def broadcast_redirect_to_matrix(report, support_agent)
  url = support_agent_path(support_agent, tab: "obligations")
  Turbo::StreamsChannel.broadcast_append_to(
    "support_agent_report_#{report.id}",
    target: "progress_panel_#{report.id}",
    html: "<script>setTimeout(function() { Turbo.visit('#{url}') }, 2000)</script>"
  )
end
```

Fires only when `ctx[:extracted].present?` — no redirect on empty extraction or failure.

---

## Obligation Lifecycle (Post-Extraction)

Identical to SLO — same services, same policies, same views:

| Action | Service | Effect |
|--------|---------|--------|
| Approve | `ObligationApprove` | Sets `approved` + `active`, calls `ObligationProjection` |
| Reject | `ObligationReject` | Sets `rejected`, never resurfaces on re-extraction |
| Fire | `ObligationFire` | Creates dated task on an armed obligation |
| Waive | `ObligationTeardown` | Removes open tasks, keeps history |
| Revert | `ObligationRevert` | Restores waived obligation to active |
| Fulfill | Manual or task completion | Records `ObligationFulfillment` audit row |

### Task Projection

```ruby
# ObligationProjection
if obligation.recurring?
  → TaskRecurrenceRule (nightly job materializes instances)
elsif obligation.next_due_date.present?
  → Single Task with due_date
else
  → Armed (no task until fired)
end
```

Task categories: CP obligations → "Condition Precedent", CS → "Condition Subsequent", SLO → "Compliance".

---

## Authorization

`SideLetterObligationPolicy` gates on `entity.support_agents.set?(:side_letter_obligation_agent)`. Both the SLO and CP/CS agent flags must be enabled for full access:

- `:cp_cs_extraction_agent` — enables the "Run CP/CS Agent" button on the investor page
- `:side_letter_obligation_agent` — enables the obligation matrix UI and show page

Both are set via `entity.support_agents.set!(:agent_symbol)`.

---

## Key Files

| File | Purpose |
|------|---------|
| `app/packs/ai/support_agents/services/cp_cs_extraction_agent.rb` | Agent class — target resolution, step overrides |
| `app/packs/ai/support_agents/services/side_letter_obligation_agent.rb` | Parent — extraction pipeline, prompts, dedup, enforcement |
| `app/packs/funds/side_letters/models/side_letter_obligation.rb` | Obligation model — `source_investor`, `source_fund`, lifecycle |
| `app/packs/funds/side_letters/services/obligation_approve.rb` | Approval gate → `ObligationProjection` |
| `app/packs/funds/side_letters/services/obligation_projection.rb` | Task creation (recurring / one-time / armed) |
| `app/packs/funds/side_letters/services/obligation_fire.rb` | Creates dated task from armed obligation |
| `app/packs/funds/side_letters/services/obligation_enforcement.rb` | Daily due-date scan and consolidated alerts |
| `app/packs/funds/side_letters/controllers/side_letter_obligations_controller.rb` | Matrix UI, show, lifecycle actions |
| `app/packs/core/investors/views/investors/show.html.erb` | Portfolio company page — "Run CP/CS Agent" button + modal |
| `app/packs/ai/support_agents/views/support_agents/_obligation_matrix_tab.html.erb` | Agent show page obligations tab |
| `app/packs/ai/support_agents/views/support_agents/show.html.erb` | Agent show page (action modals rendered outside FormCard) |

---

## Cucumber Test Coverage

`features/ai/cp_cs_extraction_agent.feature` — 10 scenarios:

| Tag | Scenario | What It Tests |
|-----|----------|---------------|
| `@extraction` | Single PI extraction | 3 cited obligations created, linked via sourceable |
| `@citation_guard` | Citation guard | Uncited obligations discarded, noted in report |
| `@no_document` | No tagged document | Graceful skip, 0 obligations |
| `@company_level` | Company-level extraction | 3 PIs × 3 obligations = 9 total |
| `@company_level @mixed` | Mixed documents | PIs without docs skipped, others extracted |
| `@idempotent` | Re-extraction | Pending updated in place, no duplicates |
| `@delta` | Delta on approved | Changed content creates new pending delta |
| `@lifecycle` | Approve + task projection | One-time CP → task with "Condition Precedent" category |
| `@lifecycle @fire` | Fire armed obligation | Event-triggered → armed → fired with deadline → task |
| `@ui` | Show page rendering | Portfolio obligation renders without nil crashes |

---

## Known Issue: Modal Flicker

The obligation matrix tab is rendered inside a `FormCard` component which wraps content in a `.card` div. The minimalist theme CSS (`minimalist_theme.scss:83`) applies `container-type: inline-size` on `.container-fluid > .card`, creating a new containing block that breaks Bootstrap's `position: fixed` modal positioning.

**Fix:** Action modals (Fire, Waive, Revert) are rendered **outside** the `FormCard` block in `show.html.erb`, so they are not affected by the CSS containment context.
