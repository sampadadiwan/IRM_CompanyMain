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
4. **Estimated closing date** — optionally accepts a closing date from a modal date picker, injected into the LLM prompt for concrete `next_due_date` calculation

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

The agent uses 5 steps inherited from `SideLetterObligationAgent`. For **single PI runs**, the parent steps are called via `super`:

```
initialize_agent → locate_side_letter → extract_obligations → upsert_obligations → generate_progress_reports
```

### Step Details

#### 1. initialize_agent

Delegates to parent. Sets `ctx[:portfolio_investment]`, `ctx[:source_mode] = :portfolio_investments`.

#### 2. locate_side_letter

Delegates to parent. Calls `locate_investment_document(ctx)`.

#### 3. extract_obligations

Delegates to parent. Calls LLM with `extraction_prompt(:portfolio_investments)`.

#### 4. upsert_obligations

Delegates to parent. Calls `upsert_portfolio_obligations(ctx)`.

#### 5. generate_progress_reports

Calls `super` which:
- Calls `SupportAgentService#generate_progress_reports` (saves report)
- Finalizes the report status to `:ready`
- Broadcasts `Turbo.visit` redirect to `support_agent_path(support_agent, tab: "obligations")`

---

## Target Resolution

```ruby
def targets(entity_id)
  # Single PI passthrough
  return [entity_id] if entity_id.is_a?(PortfolioInvestment)

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

## Estimated Closing Date Flow

An optional estimated closing date can be provided via a modal date picker on the entry point pages. The date flows through the full stack to the LLM prompt:

```
Modal (date picker) → params[:estimated_closing_date]
  → SupportAgentsController#run → SupportAgentJob.perform_later(estimated_closing_date: ...)
    → SupportAgentJob#perform(estimated_closing_date: nil)
      → agent.call(estimated_closing_date: ctx[:estimated_closing_date])
        → extraction_prompt(estimated_closing_date: ...) / portfolio_extraction_prompt(estimated_closing_date: ...)
```

### Files Involved

| File | Role |
|------|------|
| `app/packs/ai/support_agents/views/support_agents/_agent_run_modal.html.erb` | Optional `show_closing_date` local renders date picker |
| `app/packs/ai/support_agents/controllers/support_agents_controller.rb` | Forwards `estimated_closing_date` param |
| `app/packs/ai/support_agents/jobs/support_agent_job.rb` | Accepts and passes through `estimated_closing_date` |
| `app/packs/ai/support_agents/services/side_letter_obligation_agent.rb` | `extraction_prompt` and `portfolio_extraction_prompt` accept `estimated_closing_date:` keyword |
| `app/packs/ai/support_agents/services/cp_cs_extraction_agent.rb` | Passes `ctx[:estimated_closing_date]` to prompt methods |

### Prompt Injection

The closing date is conditionally injected into the LLM extraction prompt:

```ruby
if estimated_closing_date.present?
  "The estimated Closing date is #{estimated_closing_date}. Use this date to calculate concrete next_due_date values..."
else
  "Set next_due_date only where a concrete YYYY-MM-DD can be calculated from dates in the document..."
end
```

When present, the LLM uses the closing date as an anchor to calculate concrete `next_due_date` values (e.g., "within 30 days of Closing" becomes a real date). When absent, the LLM only sets `next_due_date` where a concrete date is explicitly stated in the document.

---

## Context-Aware Obligation Matrix

The obligation matrix supports three contexts via `@obligation_context = params[:context]`:

### Pre-filtering

| Context | Filter |
|---------|--------|
| `cp_cs` | `where(legal_category: [:condition_precedent, :condition_subsequent])` |
| `side_letter` | `where(legal_category: :side_letter_obligation)` |
| `nil` | No pre-filter (all obligations) |

### UI Behavior

| Aspect | `cp_cs` | `side_letter` | `nil` |
|--------|---------|---------------|-------|
| **Title** | CP/CS Obligation Matrix | Side Letter Obligation Matrix | LP Obligation Matrix |
| **Legal category column** | Visible (to distinguish CP vs CS) | Hidden | Visible |
| **Filter dropdown** | Excludes SLO from legal category options | — | All options |

### Context Preservation

Context is preserved across filter submissions and navigation via:
- Hidden field `<input type="hidden" name="context" value="<%= @obligation_context %>">` in filter forms
- `context` param appended to breadcrumb links

### Files Involved

- `app/packs/funds/side_letters/controllers/side_letter_obligations_controller.rb` — reads `params[:context]`, applies pre-filter
- `app/packs/funds/side_letters/views/side_letter_obligations/index.html.erb` — title and layout
- `app/packs/funds/side_letters/views/side_letter_obligations/_matrix.html.erb` — column visibility, filter options
- `app/packs/ai/support_agents/views/support_agents/_obligation_matrix_tab.html.erb` — embedded matrix tab

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
| `investment_doc_tag` | Yes | Comma-separated document tags to match (e.g. "SHA" or "SHA,SSA"). Each tag is matched case-insensitively via LIKE against `documents.tag_list`. All matching documents per PI are extracted. |
| `default_reminder_days_before` | No (default: 7) | Lead time for pre-due-date reminder emails |
| `overdue_escalation_days` | No (default: 3) | Days after due date before escalation email |
| `notify_tag` | No | Employee tag for routing ownerless alerts. Falls back to company admins |

`config_issues` validates: tag is set, notify_tag matches at least one employee (or a fallback admin exists).

---

## Entry Points and Job Routing

### From portfolio investment show page (per-PI run)

```
portfolio_investments/show.html.erb
  → Actions dropdown → "Run CP/CS Agent"
  → _agent_run_modal.html.erb (with optional estimated_closing_date date picker)
  → form POST to run_support_agents_path
  → SupportAgentsController#run
    → SupportAgentJob.perform_later(
        target_type: "PortfolioInvestment", target_id: @pi.id,
        estimated_closing_date: params[:estimated_closing_date],
        with_steps: true
      )
      → CpCsExtractionAgent.call(target: portfolio_investment, ...)
```

### From documents page (per-document run)

```
documents/_index.html.erb / _document.html.erb
  → Per-document "Run CP/CS Agent" button
  → _agent_run_modal.html.erb (with optional estimated_closing_date date picker)
  → form POST to run_support_agents_path
  → SupportAgentsController#run
    → SupportAgentJob.perform_later(
        target_type: "PortfolioInvestment", target_id: @pi.id,
        estimated_closing_date: params[:estimated_closing_date],
        with_steps: true
      )
      → CpCsExtractionAgent.call(target: portfolio_investment, ...)
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

> **Removed:** The "Run CP/CS Agent" button was removed from `investors/show.html.erb` (portfolio company page). All runs are now per-portfolio-investment or per-document.

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

## Obligation Title Links

In `_side_letter_obligation.html.erb`, all obligation titles link to `side_letter_obligation_path(obligation)` — the show page with Tasks/Fulfillment/Alerts tabs. This applies to both SLO and portfolio-sourced obligations (previously portfolio obligations linked to inline edit).

---

## jQuery DataTables Sorting

The obligation matrix table uses client-side sorting via jQuery DataTables:

- `jqDataTable` CSS class on the `<table>` element
- `data-controller="datatable"` Stimulus controller on the parent `<div>`
- `data-sort` timestamp attributes on Next Due column cells for correct chronological ordering
- Empty-state colspan row removed from table markup (causes DataTables "unknown parameter" error when DataTables attempts to parse it as a data row)

---

## Legal Category Filter Fix

`legal_category_options` helper returns integer enum values instead of string keys:

```ruby
def legal_category_options
  SideLetterObligation.legal_categories.map { |k, v| [k.humanize, v] }
end
```

This fixes an issue where MySQL silently cast non-numeric string keys to `0` in integer column comparisons, causing the filter to always match `condition_precedent` (enum value 0) regardless of the selected option.

---

## Edit Form Changes

`_form.html.erb` conditionally adjusts fields based on the `is_cp_cs` flag:

- **MFN checkbox:** Hidden when `is_cp_cs` is true (MFN clause is a side-letter-only concept)
- **Legal category dropdown:** Filtered to CP/CS values only (excludes `side_letter_obligation`, enum value 2) when `is_cp_cs` is true

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

- `:cp_cs_extraction_agent` — enables the "Run CP/CS Agent" button on the portfolio investment and documents pages
- `:side_letter_obligation_agent` — enables the obligation matrix UI and show page

Both are set via `entity.support_agents.set!(:agent_symbol)`.

---

## Key Files

| File | Purpose |
|------|---------|
| `app/packs/ai/support_agents/services/cp_cs_extraction_agent.rb` | Agent class — target resolution, step overrides |
| `app/packs/ai/support_agents/services/side_letter_obligation_agent.rb` | Parent — extraction pipeline, prompts, dedup, enforcement; `estimated_closing_date` prompt injection |
| `app/packs/funds/side_letters/models/side_letter_obligation.rb` | Obligation model — `source_investor`, `source_fund`, lifecycle |
| `app/packs/funds/side_letters/services/obligation_approve.rb` | Approval gate → `ObligationProjection` |
| `app/packs/funds/side_letters/services/obligation_projection.rb` | Task creation (recurring / one-time / armed) |
| `app/packs/funds/side_letters/services/obligation_fire.rb` | Creates dated task from armed obligation |
| `app/packs/funds/side_letters/services/obligation_enforcement.rb` | Daily due-date scan and consolidated alerts |
| `app/packs/funds/side_letters/controllers/side_letter_obligations_controller.rb` | Matrix UI (context-aware filtering), show, lifecycle actions |
| `app/packs/funds/side_letters/views/side_letter_obligations/_side_letter_obligation.html.erb` | Obligation row partial — title links to show page |
| `app/packs/funds/portfolios/views/portfolio_investments/show.html.erb` | Portfolio investment page — "Run CP/CS Agent" button with estimated closing date modal |
| `app/packs/core/documents/views/documents/_index.html.erb` | Documents page — "Run CP/CS Agent" button |
| `app/packs/core/documents/views/documents/_document.html.erb` | Per-document "Run CP/CS Agent" button |
| `app/packs/ai/support_agents/views/support_agents/_agent_run_modal.html.erb` | Agent run modal — optional `show_closing_date` date picker |
| `app/packs/ai/support_agents/views/support_agents/_obligation_matrix_tab.html.erb` | Agent show page obligations tab |
| `app/packs/ai/support_agents/views/support_agents/show.html.erb` | Agent show page (action modals rendered outside FormCard) |
| `app/packs/ai/support_agents/controllers/support_agents_controller.rb` | Forwards `estimated_closing_date` param to job |
| `app/packs/ai/support_agents/jobs/support_agent_job.rb` | Accepts and passes through `estimated_closing_date` |
| ~~`app/packs/core/investors/views/investors/show.html.erb`~~ | CP/CS Agent button **removed** (per-PI runs only now) |

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
