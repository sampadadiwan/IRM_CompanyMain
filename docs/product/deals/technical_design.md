# Deal Weekly Summary — Technical Design

## Overview

Enhance the existing `DealManagementAgent` (single-deal scope) to add weekly summary capabilities: period-based delta computation, three-way stagnation tracking, task aggregation, optional AI insight, a lightweight email, and a new "Weekly Summary" tab on the deal detail page.

Each deal gets its own agent instance — no cross-deal aggregation. Step presets are deal-specific, eliminating the "different steps per deal" problem.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                   DealManagementAgent                         │
│              (SupportAgentService subclass)                    │
│              Scope: ONE deal per agent instance                │
│                                                                │
│  EXISTING STEPS:                                              │
│  Step 1:  initialize_agent                                    │
│  Step 2:  check_deal_progress          (stagnation + overdue) │
│  Step 3:  check_document_checklist     (data room docs)       │
│  Step 4:  extract_deal_terms           (LLM, optional)        │
│  Step 5:  run_investor_pipeline        (LLM scoring, optional)│
│                                                                │
│  NEW STEPS (weekly summary):                                  │
│  Step 6:  calculate_period_deltas      (NEW)                  │
│  Step 7:  calculate_stagnation_breakdown (NEW)                │
│  Step 8:  aggregate_deal_tasks         (NEW)                  │
│  Step 9:  compute_charts_data          (NEW)                  │
│  Step 10: generate_weekly_insight      (NEW, optional LLM)    │
│                                                                │
│  EXISTING STEPS (enhanced):                                   │
│  Step 11: send_email_digest            (enhanced — new template)│
│  Step 12: generate_progress_reports    (enhanced — new fields) │
└──────────────────────┬────────────────────────────────────────┘
                       │
                       ▼
          ┌────────────────────────┐
          │  SupportAgentReport    │
          │  (owner: Deal)         │
          │  json_fields: {        │
          │    ...existing...,     │
          │    period_deltas,      │
          │    stagnation_breakdown│
          │    tasks_summary,      │
          │    charts_data,        │
          │    weekly_insight      │
          │  }                     │
          └────────────┬───────────┘
                       │
            ┌──────────┴──────────┐
            ▼                     ▼
     ┌─────────────┐    ┌─────────────────────┐
     │  Email       │    │  Weekly Summary Tab  │
     │  (lightweight│    │  on Deal detail page │
     │   HTML)      │    │                      │
     └─────────────┘    └─────────────────────┘
```

---

## Existing Steps — What They Already Do

For reference, these are the existing steps in `DealManagementAgent` that remain unchanged:

| Step | Method | What It Does | Toggle |
|---|---|---|---|
| 1 | `initialize_agent` | Validates deal is Open, loads config, initializes `ctx[:issues]` | Always |
| 2 | `check_deal_progress` | Flags stagnant investors + overdue activities | `check_progress` |
| 3 | `check_document_checklist` | Verifies required docs in data room | `check_documents` |
| 4 | `extract_deal_terms` | LLM extracts deal terms from data room docs (cached) | `extract_terms` |
| 5 | `run_investor_pipeline` | Per-investor: collect docs, summarize notes, score via LLM | `summarize_notes` / `score_investors` |

These deep-analysis features remain independently toggleable. The weekly summary steps run after them.

---

## New Steps — Detailed

### Step 6: calculate_period_deltas

Computes what changed during the reporting period for this deal.

```ruby
STEP_LABELS = {
  # ... existing labels ...
  calculate_period_deltas: "Period Deltas",
  calculate_stagnation_breakdown: "Stagnation Breakdown",
  aggregate_deal_tasks: "Tasks Summary",
  compute_charts_data: "Charts Data",
  generate_weekly_insight: "AI Insight"
}.freeze

# Add after existing steps:
step :calculate_period_deltas
step :calculate_stagnation_breakdown
step :aggregate_deal_tasks
step :compute_charts_data
step :generate_weekly_insight
# Existing steps renumbered:
step :send_email_digest
step :generate_progress_reports

def calculate_period_deltas(ctx, deal: nil, **)
  report = ctx[:support_agent_report]
  mark_step_running(report, :calculate_period_deltas) if report

  unless enabled?("weekly_summary")
    mark_step_skipped(report, :calculate_period_deltas, message: "Weekly summary disabled") if report
    return true
  end

  @report_period = [@support_agent.json_fields["report_period"].to_i, 1].max
  @period_start  = @report_period.days.ago.beginning_of_day
  @period_end    = Time.current

  ctx[:period_deltas] = {
    period_start: @period_start.iso8601,
    period_end: @period_end.iso8601,
    report_period: @report_period,
    new_investors: count_new_investors(deal),
    step_transitions: compute_step_transitions(deal),
    status_changes: compute_status_changes(deal)
  }

  total_new = ctx[:period_deltas][:new_investors][:count]
  total_transitions = ctx[:period_deltas][:step_transitions][:total]
  total_status = ctx[:period_deltas][:status_changes][:total]

  mark_step_success(report, :calculate_period_deltas,
    message: "#{total_new} new, #{total_transitions} transitions, #{total_status} status changes") if report
  true
end
```

#### 6a. New Investors Added

```ruby
def count_new_investors(deal)
  investors = deal.deal_investors.where(created_at: @period_start..@period_end)
  {
    count: investors.count,
    investors: investors.map { |di| { id: di.id, name: di.investor_name, created_at: di.created_at.iso8601 } }
  }
end
```

#### 6b. Step Transitions

Query the `audits` table for `deal_activity_id` changes on this deal's investors.

```ruby
def compute_step_transitions(deal)
  di_ids = deal.deal_investor_ids
  return { transitions: [], details: [], total: 0 } if di_ids.empty?

  # Query audits for deal_activity_id changes
  audits = Audited::Audit.where(
    auditable_type: "DealInvestor",
    auditable_id: di_ids,
    action: "update"
  ).where(created_at: @period_start..@period_end)

  # Filter to audits that contain deal_activity_id changes
  # audited_changes is serialized YAML/JSON — filter in Ruby for reliability
  relevant_audits = audits.select { |a| a.audited_changes.key?("deal_activity_id") }

  # Build template ID → title mapping for this deal
  templates = DealActivity.where(deal_id: deal.id, deal_investor_id: nil)
                          .order(:sequence)
                          .pluck(:id, :title, :sequence)
  template_map = templates.to_h { |id, title, _seq| [id, title] }
  sequence_map = templates.to_h { |id, _title, seq| [id, seq] }

  # Apply preset filter if configured
  preset_steps = parse_preset_steps
  transitions = Hash.new(0)
  details = []

  relevant_audits.each do |audit|
    old_id, new_id = audit.audited_changes["deal_activity_id"]
    from_title = template_map[old_id] || "—"
    to_title   = template_map[new_id] || "—"
    from_seq   = sequence_map[old_id]
    to_seq     = sequence_map[new_id]

    # Apply preset filter: skip if presets configured and this transition isn't in the list
    if preset_steps.any?
      next unless preset_steps.any? { |ps| ps[:from] == from_seq && ps[:to] == to_seq }
    end

    key = "#{from_title} → #{to_title}"
    transitions[key] += 1
    details << {
      investor_id: audit.auditable_id,
      from_step: from_title,
      to_step: to_title,
      from_sequence: from_seq,
      to_sequence: to_seq,
      changed_at: audit.created_at.iso8601
    }
  end

  {
    transitions: transitions.sort_by { |_, count| -count },
    details: details,
    total: details.size
  }
end

# Parses preset_steps config: "1-2,3-4" → [{ from: 1, to: 2 }, { from: 3, to: 4 }]
def parse_preset_steps
  raw = @support_agent.json_fields["preset_steps"].to_s.strip
  return [] if raw.blank?

  raw.split(",").filter_map do |pair|
    parts = pair.strip.split("-").map(&:to_i)
    next unless parts.size == 2

    { from: parts[0], to: parts[1] }
  end
end
```

#### 6c. Status Changes

```ruby
def compute_status_changes(deal)
  di_ids = deal.deal_investor_ids
  return { by_status: {}, details: {}, total: 0 } if di_ids.empty?

  audits = Audited::Audit.where(
    auditable_type: "DealInvestor",
    auditable_id: di_ids,
    action: "update"
  ).where(created_at: @period_start..@period_end)

  relevant_audits = audits.select { |a| a.audited_changes.key?("status") }

  preset_statuses = (@support_agent.json_fields["preset_statuses"].to_s)
                    .split(",").map(&:strip).compact_blank

  changes = Hash.new { |h, k| h[k] = [] }

  relevant_audits.each do |audit|
    _old_status, new_status = audit.audited_changes["status"]

    # Apply preset filter
    next if preset_statuses.any? && !preset_statuses.include?(new_status)

    di = DealInvestor.find_by(id: audit.auditable_id)
    changes[new_status] << {
      investor_id: audit.auditable_id,
      investor_name: di&.investor_name,
      changed_at: audit.created_at.iso8601
    }
  end

  {
    by_status: changes.transform_values(&:count),
    details: changes,
    total: changes.values.sum(&:count)
  }
end
```

### Step 7: calculate_stagnation_breakdown

Three-way stagnation breakdown comparing current state vs previous report.

```ruby
def calculate_stagnation_breakdown(ctx, deal: nil, **)
  report = ctx[:support_agent_report]
  mark_step_running(report, :calculate_stagnation_breakdown) if report

  unless enabled?("weekly_summary")
    mark_step_skipped(report, :calculate_stagnation_breakdown, message: "Disabled") if report
    return true
  end

  investors = active_deal_investors(deal).includes(:deal_activities)
  stagnant_days = [@support_agent.json_fields["stagnant_days"].to_i, 1].max

  # Current stagnant: both investor AND all activities are stale
  current_stagnant_ids = investors.select do |di|
    investor_stale = di.updated_at < stagnant_days.days.ago
    activities_stale = di.deal_activities.none? { |a| a.updated_at >= stagnant_days.days.ago }
    investor_stale && activities_stale
  end.map(&:id).to_set

  # Previous stagnant: from last completed report's json_fields
  previous_report = SupportAgentReport
                    .where(owner: deal, support_agent: @support_agent)
                    .where(status: :completed)
                    .where.not(id: report&.id)
                    .order(created_at: :desc)
                    .first

  previous_stagnant_ids = (
    previous_report&.json_fields&.dig("stagnation_breakdown", "current_stagnant_ids") || []
  ).map(&:to_i).to_set

  # Three-way breakdown
  still_stagnant = current_stagnant_ids & previous_stagnant_ids
  newly_stagnant = current_stagnant_ids - previous_stagnant_ids
  now_active     = previous_stagnant_ids - current_stagnant_ids

  # Resolve names for display
  all_relevant_ids = (still_stagnant + newly_stagnant + now_active).to_a
  name_map = DealInvestor.where(id: all_relevant_ids).pluck(:id, :investor_name).to_h

  # Compute last_activity date per investor (max of investor updated_at and latest deal_activity updated_at)
  last_activity_map = investors.each_with_object({}) do |di, map|
    latest_activity = di.deal_activities.map(&:updated_at).max
    map[di.id] = [di.updated_at, latest_activity].compact.max.iso8601
  end

  ctx[:stagnation_breakdown] = {
    total: current_stagnant_ids.size,
    still_stagnant: still_stagnant.map { |id| { id: id, name: name_map[id], last_activity: last_activity_map[id] } },
    newly_stagnant: newly_stagnant.map { |id| { id: id, name: name_map[id], last_activity: last_activity_map[id] } },
    now_active: now_active.map { |id| { id: id, name: name_map[id] } },
    still_stagnant_count: still_stagnant.size,
    newly_stagnant_count: newly_stagnant.size,
    now_active_count: now_active.size,
    current_stagnant_ids: current_stagnant_ids.to_a,
    stagnant_days: stagnant_days
  }

  mark_step_success(report, :calculate_stagnation_breakdown,
    message: "#{newly_stagnant.size} new, #{still_stagnant.size} still, #{now_active.size} recovered") if report
  true
end
```

### Step 8: aggregate_deal_tasks

Aggregates tasks for this deal and its investors.

```ruby
def aggregate_deal_tasks(ctx, deal: nil, **)
  report = ctx[:support_agent_report]
  mark_step_running(report, :aggregate_deal_tasks) if report

  unless enabled?("weekly_summary")
    mark_step_skipped(report, :aggregate_deal_tasks, message: "Disabled") if report
    return true
  end

  di_ids = deal.deal_investor_ids

  # Tasks owned by this deal OR its deal investors
  all_tasks = Task.where(
    "(owner_type = 'Deal' AND owner_id = ?) OR
     (owner_type = 'DealInvestor' AND owner_id IN (?))",
    deal.id, di_ids
  ).includes(:assigned_to, :rich_text_details).to_a

  # Fixed 7-day lookahead — period_end is Time.current (today), so the old
  # upcoming filter only caught tasks due exactly today. Now: upcoming = today..+7d,
  # pending = no due date or due beyond 7 days.
  upcoming_horizon = Time.zone.today + 7.days
  overdue   = all_tasks.select { |t| !t.completed && t.due_date.present? && t.due_date < Date.today }
  upcoming  = all_tasks.select { |t| !t.completed && t.due_date.present? && t.due_date >= Date.today && t.due_date <= upcoming_horizon }
  pending   = all_tasks.select { |t| !t.completed && (t.due_date.blank? || t.due_date > upcoming_horizon) }
  completed = all_tasks.select { |t| t.completed && t.updated_at >= @period_start }

  max_tasks = [@support_agent.json_fields["max_tasks_in_email"].to_i, 5].max
  highlighted_overdue = overdue.min_by(&:due_date)
  pending_due_soon = upcoming.sort_by(&:due_date).first(max_tasks)

  ctx[:tasks_summary] = {
    overdue_count: overdue.size,
    upcoming_count: upcoming.size,
    pending_count: pending.size,
    completed_count: completed.size,
    highlighted_overdue: format_deal_task(highlighted_overdue),
    overdue_tasks: overdue.sort_by(&:due_date).first(max_tasks).map { |t| format_deal_task(t) },
    pending_due_soon: pending_due_soon.map { |t| format_deal_task(t) },
    pending_tasks: pending.sort_by { |t| t.due_date || Date.new(9999) }.first(max_tasks).map { |t| format_deal_task(t) },
    completed_tasks: completed.sort_by(&:updated_at).reverse.first(max_tasks).map { |t| format_deal_task(t) },
    all_overdue_ids: overdue.map(&:id),
    all_upcoming_ids: upcoming.map(&:id),
    all_pending_ids: pending.map(&:id),
    all_completed_ids: completed.map(&:id)
  }

  mark_step_success(report, :aggregate_deal_tasks,
    message: "#{overdue.size} overdue, #{upcoming.size} upcoming, #{pending.size} pending, #{completed.size} completed") if report
  true
end

def format_deal_task(task)
  return nil unless task

  company_name = if task.owner_type == "DealInvestor"
                   task.owner&.investor_name
                 end

  {
    id: task.id,
    title: String(ActionController::Base.helpers.strip_tags(task.read_attribute(:details))).truncate(80),
    company_name: company_name,
    responsible: task.assigned_to&.name,
    due_date: task.due_date&.iso8601,
    completed: task.completed,
    status: task.completed ? "Completed" : (task.due_date && task.due_date < Date.today ? "Overdue" : "Pending")
  }
end
```

### Step 9: compute_charts_data

Pre-computes chart data from the deal's current state and stores it in the report for the dashboard.

```ruby
def compute_charts_data(ctx, deal: nil, **)
  report = ctx[:support_agent_report]
  mark_step_running(report, :compute_charts_data) if report

  unless enabled?("weekly_summary")
    mark_step_skipped(report, :compute_charts_data, message: "Disabled") if report
    return true
  end

  preset_charts = (@support_agent.json_fields["preset_charts"].to_s)
                  .split(",").map(&:strip).compact_blank
  # Default: all charts
  preset_charts = %w[funnel source lead] if preset_charts.empty?

  investors = deal.deal_investors.includes(:deal_activity, :deal_activities)

  charts = {}

  # Deal Funnel — investor count per template step
  if preset_charts.include?("funnel")
    templates = DealActivity.where(deal_id: deal.id, deal_investor_id: nil).order(:sequence)
    charts[:funnel] = templates.map do |tmpl|
      count = investors.count { |di| di.deal_activity_id == tmpl.id }
      { step_title: tmpl.title, investor_count: count, sequence: tmpl.sequence }
    end
  end

  # Mix by Source — amounts grouped by source
  if preset_charts.include?("source")
    source_groups = investors.group_by(&:source)
    charts[:source_mix] = source_groups.map do |source, dis|
      { label: source.presence || "Unknown", value: dis.sum(&:total_amount_cents).to_i }
    end.sort_by { |d| -d[:value] }
  end

  # Mix by Lead — amounts grouped by deal_lead
  if preset_charts.include?("lead")
    lead_groups = investors.group_by(&:deal_lead)
    charts[:lead_mix] = lead_groups.map do |lead, dis|
      { label: lead.presence || "Unknown", value: dis.sum(&:total_amount_cents).to_i }
    end.sort_by { |d| -d[:value] }
  end

  ctx[:charts_data] = charts

  mark_step_success(report, :compute_charts_data,
    message: "#{charts.keys.join(', ')} computed") if report
  true
end
```

### Step 10: generate_weekly_insight (optional LLM)

One LLM call to generate an actionable one-liner.

```ruby
def generate_weekly_insight(ctx, deal: nil, **)
  report = ctx[:support_agent_report]
  mark_step_running(report, :generate_weekly_insight) if report

  unless enabled?("weekly_summary") && enabled?("enable_ai_insight")
    mark_step_skipped(report, :generate_weekly_insight, message: "Disabled") if report
    return true
  end

  deltas = ctx[:period_deltas] || {}
  stagnation = ctx[:stagnation_breakdown] || {}
  tasks = ctx[:tasks_summary] || {}
  charts = ctx[:charts_data] || {}

  summary_data = {
    deal_name: deal.name,
    new_investors: deltas.dig(:new_investors, :count) || 0,
    total_transitions: deltas.dig(:step_transitions, :total) || 0,
    top_transitions: deltas.dig(:step_transitions, :transitions)&.first(3),
    total_stagnant: stagnation[:total] || 0,
    newly_stagnant: stagnation[:newly_stagnant_count] || 0,
    overdue_tasks: tasks[:overdue_count] || 0,
    funnel: charts[:funnel]
  }

  prompt = <<~PROMPT
    You are a deal pipeline analyst for a fund management firm.
    Based on this week's data for the deal "#{deal.name}", write ONE actionable
    sentence (max 30 words) recommending what the team should focus on next week.
    Be specific — mention step names, investor counts, or stagnation trends.
    No generic advice.

    Data: #{summary_data.to_json}
  PROMPT

  response = ctx[:llm].ask(prompt)
  ctx[:weekly_insight] = extract_text_content(response).strip

  mark_step_success(report, :generate_weekly_insight,
    message: ctx[:weekly_insight].truncate(80)) if report
  true
rescue StandardError => e
  Rails.logger.error { "[DealManagementAgent] Weekly insight failed: #{e.message}" }
  ctx[:weekly_insight] = nil
  mark_step_failed(report, :generate_weekly_insight, message: e.message) if report
  true # soft-fail
end
```

---

## Enhanced Existing Steps

### send_email_digest (enhanced)

Add a new mailer action `weekly_summary` alongside the existing `pipeline_digest`.

```ruby
def send_email_digest(ctx, deal: nil, **)
  # ... existing pipeline_digest logic stays unchanged ...

  # NEW: send weekly summary email if weekly_summary is enabled
  # NOTE: JSON round-trip to convert SafeBuffer → String and symbol → string keys
  # (Sidekiq 8 strict args rejects ActiveSupport::SafeBuffer)
  if enabled?("weekly_summary") && notify_email.present?
    weekly_params = JSON.parse({
      support_agent_id: @support_agent.id,
      deal_id: deal.id,
      notify_email: notify_email,
      period_deltas: ctx[:period_deltas],
      stagnation_breakdown: ctx[:stagnation_breakdown],
      tasks_summary: ctx[:tasks_summary],
      weekly_insight: ctx[:weekly_insight]
    }.to_json)
    DealManagementDigestMailer.with(weekly_params).weekly_summary.deliver_later
  end

  true
end
```

### generate_progress_reports (enhanced)

Merge new fields into the report's json_fields.

```ruby
def generate_progress_reports(ctx, support_agent:, deal: nil, **)
  # ... existing logic ...

  # Merge weekly summary data into report
  if enabled?("weekly_summary")
    report.json_fields = (report.json_fields || {}).merge(
      "period_deltas"         => ctx[:period_deltas],
      "stagnation_breakdown"  => ctx[:stagnation_breakdown],
      "tasks_summary"         => ctx[:tasks_summary],
      "charts_data"           => ctx[:charts_data],
      "weekly_insight"        => ctx[:weekly_insight]
    )
  end

  # ... existing save logic ...
end
```

---

## Configuration Keys

### New json_fields on SupportAgent

| Key | Type | Purpose | Default |
|---|---|---|---|
| `weekly_summary` | String | "Yes"/"No" — master toggle for weekly summary features | "No" |
| `report_period` | Integer | Days to look back for period deltas | 7 |
| `preset_steps` | String (CSV) | Step transition pairs to show: "1-2,3-4". Blank = all non-zero | All |
| `preset_statuses` | String (CSV) | Statuses to track: "Declined,Active". Blank = all | All |
| `preset_charts` | String (CSV) | Charts to show: "funnel,source,lead". Blank = all | All |
| `enable_ai_insight` | String | "Yes"/"No" — generate LLM one-liner | "No" |
| `max_tasks_in_email` | Integer | Max task rows in email | 5 |

### Existing keys (unchanged)

| Key | Purpose |
|---|---|
| `check_progress` | Toggle stagnation + overdue checks |
| `check_documents` | Toggle document checklist |
| `required_docs` | Comma-separated required doc names |
| `extract_terms` | Toggle LLM term extraction |
| `summarize_notes` | Toggle investor note summarization |
| `score_investors` | Toggle investor LLM scoring |
| `notify_email` | Email for digest + weekly summary |
| `stagnant_days` | Days threshold for stagnation (reused by weekly summary) |
| `note_period` | Period for note collection (Month/Quarter) |

---

## SupportAgentReport.json_fields Structure

The report already stores existing agent data. Weekly summary adds these keys:

```json
{
  "...existing keys (progress_issues, document_issues, extracted_terms, etc.)...",

  "period_deltas": {
    "period_start": "2025-05-19T00:00:00Z",
    "period_end": "2025-05-26T00:00:00Z",
    "report_period": 7,
    "new_investors": {
      "count": 3,
      "investors": [
        { "id": 101, "name": "Sequoia Capital", "created_at": "2025-05-20T10:00:00Z" },
        { "id": 102, "name": "Tiger Global", "created_at": "2025-05-22T14:30:00Z" }
      ]
    },
    "step_transitions": {
      "transitions": [
        ["Outreach → First Call", 5],
        ["DD → Term Sheet", 2]
      ],
      "details": [
        {
          "investor_id": 101,
          "from_step": "Outreach",
          "to_step": "First Call",
          "from_sequence": 1,
          "to_sequence": 2,
          "changed_at": "2025-05-21T09:00:00Z"
        }
      ],
      "total": 7
    },
    "status_changes": {
      "by_status": { "Declined": 2, "Active": 1 },
      "details": {
        "Declined": [
          { "investor_id": 201, "investor_name": "KKR", "changed_at": "2025-05-23T11:00:00Z" }
        ]
      },
      "total": 3
    }
  },

  "stagnation_breakdown": {
    "total": 5,
    "still_stagnant": [{ "id": 201, "name": "Investor A", "last_activity": "2025-04-10T00:00:00Z" }],
    "newly_stagnant": [{ "id": 203, "name": "Investor B", "last_activity": "2025-05-05T00:00:00Z" }],
    "now_active": [{ "id": 206, "name": "Investor C" }],
    "still_stagnant_count": 2,
    "newly_stagnant_count": 3,
    "now_active_count": 2,
    "current_stagnant_ids": [201, 202, 203, 204, 205],
    "stagnant_days": 14
  },

  "tasks_summary": {
    "overdue_count": 1,
    "upcoming_count": 3,
    "pending_count": 2,
    "completed_count": 7,
    "highlighted_overdue": {
      "id": 501,
      "title": "Financial Model Review",
      "company_name": "Quantum Health",
      "responsible": "the responsible team member",
      "due_date": "2025-05-22",
      "status": "Overdue"
    },
    "overdue_tasks": [
      {
        "id": 501,
        "title": "Financial Model Review",
        "company_name": "Quantum Health",
        "responsible": "the responsible team member",
        "due_date": "2025-05-22",
        "status": "Overdue"
      }
    ],
    "pending_due_soon": [
      {
        "id": 502,
        "title": "Market Analysis",
        "company_name": "Astra Robotics",
        "responsible": "the responsible team member",
        "due_date": "2025-05-27",
        "status": "Pending"
      }
    ],
    "pending_tasks": [
      {
        "id": 504,
        "title": "Board Presentation Prep",
        "company_name": "Quantum Health",
        "responsible": "the responsible team member",
        "due_date": "2025-06-15",
        "status": "Pending"
      }
    ],
    "completed_tasks": [
      {
        "id": 503,
        "title": "NDA Review",
        "company_name": "Verde Logistics",
        "responsible": "the responsible team member",
        "due_date": "2025-05-20",
        "status": "Completed"
      }
    ],
    "all_overdue_ids": [501],
    "all_upcoming_ids": [502],
    "all_pending_ids": [504],
    "all_completed_ids": [503]
  },

  "charts_data": {
    "funnel": [
      { "step_title": "Lead In", "investor_count": 28, "sequence": 1 },
      { "step_title": "Prelim Eval", "investor_count": 21, "sequence": 2 }
    ],
    "source_mix": [
      { "label": "Referrals", "value": 30000000 },
      { "label": "Outbound", "value": 25000000 }
    ],
    "lead_mix": [
      { "label": "the responsible team member", "value": 28000000 },
      { "label": "the responsible team member", "value": 24000000 }
    ]
  },

  "weekly_insight": "Focus on converting 4 investors stuck in Diligence to IC — stagnation increased 20% this week."
}
```

---

## Dashboard View

### Route

```ruby
# config/routes/startup.rb
resources :deals do
  member do
    get :weekly_summary
  end
  # ... existing routes ...
end
```

This gives us `/deals/:id/weekly_summary` — scoped to a specific deal.

### Controller Action

```ruby
# DealsController
def weekly_summary
  @deal = Deal.find(params[:id])
  authorize @deal, :show?

  @support_agent = SupportAgent.find_by(
    entity_id: @deal.entity_id,
    agent_type: "DealManagementAgent"
  )

  @report = @support_agent&.support_agent_reports
                           &.where(owner: @deal)
                           &.where(status: :completed)
                           &.order(created_at: :desc)
                           &.first

  @data = @report&.json_fields || {}

  # Historical reports for the sidebar/dropdown
  @past_reports = @support_agent&.support_agent_reports
                                &.where(owner: @deal)
                                &.where(status: :completed)
                                &.order(created_at: :desc)
                                &.limit(12)
end
```

### View Structure

```
app/packs/startups/deals/views/deals/weekly_summary.html.erb
│
├── Header: "[Deal Name] — Weekly Summary"
│   ├── Week range: "Week of 19-25 May 2025"
│   ├── Generated on date
│   └── Historical report selector (dropdown of past weeks)
│
├── Executive Summary card
│   └── Natural language paragraph + key aggregate counts
│
├── Section 1: Deals Summary (three panels side by side)
│   ├── Panel A: Overall Progress
│   │   ├── New investors added: [count] (expandable → list of names)
│   │   ├── Step transitions (expandable → detail per investor)
│   │   └── Each row: "Outreach → First Call: 5  >"
│   │
│   ├── Panel B: Stagnant / Stuck ([total])
│   │   ├── Stagnant now active: [count] (expandable)
│   │   ├── Still stagnant: [count] (expandable)
│   │   └── Newly stagnant: [count] (expandable)
│   │
│   └── Panel C: Status Changes (Preset)
│       ├── Moved to Active: [count] (expandable)
│       └── Declined: [count] (expandable)
│
├── Section 2: Pending Tasks Summary
│   ├── Count cards: Overdue | Upcoming | Completed
│   ├── Highlighted overdue task card
│   └── "Pending Tasks Due Soon" table
│
├── Section 3: Pipeline Overview (charts)
│   ├── Deal Funnel bar chart
│   ├── Mix by Source donut chart
│   └── Mix by Lead donut chart
│
└── AI Insight card (if enabled)
```

### Tab Integration

Add "Weekly Summary" as a new tab on the deal detail page:

```erb
<!-- In deal list_view.html.erb or equivalent tab navigation -->
<li class="nav-item">
  <%= link_to "Weekly Summary", weekly_summary_deal_path(@deal),
      class: "nav-link #{'active' if action_name == 'weekly_summary'}" %>
</li>
```

---

## Email Template

### New Mailer Action

```ruby
# DealManagementDigestMailer
# NOTE: params arrive as string keys after JSON round-trip (Sidekiq serialization).
# Dual access (symbol || string) ensures compatibility with both direct and queued calls.
def weekly_summary
  @support_agent  = SupportAgent.find(params[:support_agent_id] || params["support_agent_id"])
  @deal           = Deal.find(params[:deal_id] || params["deal_id"])
  @notify_email   = params[:notify_email] || params["notify_email"]
  @period_deltas  = params[:period_deltas] || params["period_deltas"] || {}
  @stagnation     = params[:stagnation_breakdown] || params["stagnation_breakdown"] || {}
  @tasks_summary  = params[:tasks_summary] || params["tasks_summary"] || {}
  @weekly_insight = params[:weekly_insight] || params["weekly_insight"]

  subject = "#{@deal.name} — Weekly Summary"

  mail(to: @notify_email, subject: subject)
end
```

### Email Template Structure

```
weekly_summary.html.erb (lightweight HTML)
│
├── Header: CapHive logo + "[Deal Name] — Weekly Summary" + week range
│
├── Executive Summary (1-2 sentences, template-generated from data)
│
├── "View Full Dashboard →" CTA button
│   └── Links to /deals/:id/weekly_summary
│
├── Key Counts (inline colored cards):
│   ├── 🟢 New Investors: [count]
│   ├── 🔵 Step Advances: [count]
│   ├── 🟡 Stagnant: [count]
│   ├── 🔴 Status Changes: [count]
│   └── All counts link to dashboard
│
├── Tasks Quick View:
│   ├── Overdue: [count] | Upcoming: [count] | Completed: [count]
│   ├── Highlighted overdue task (title, responsible, due date)
│   └── "View all tasks →"
│
├── AI Insight (if enabled): colored highlight box with one-liner
│
└── Footer: "Manage preferences | Unsubscribe"
```

---

## File Changes Required

### Modified Files

| File | Changes |
|---|---|
| `app/packs/ai/support_agents/services/deal_management_agent.rb` | Add 5 new steps (6-10), enhance steps 11-12, add helper methods, add new config keys to STEP_LABELS |
| `app/packs/ai/support_agents/mailers/deal_management_digest_mailer.rb` | Add `weekly_summary` mailer action |
| `app/packs/startups/deals/controllers/deals_controller.rb` | Add `weekly_summary` action |
| `app/packs/startups/deals/policies/deal_policy.rb` | Add `weekly_summary?` permission |
| `config/routes/startup.rb` | Add `weekly_summary` member route under deals |
| Deal detail tab navigation view | Add "Weekly Summary" tab link |

### New Files

| File | Purpose |
|---|---|
| `app/packs/startups/deals/views/deals/weekly_summary.html.erb` | Dashboard main view |
| `app/packs/startups/deals/views/deals/_weekly_summary_header.html.erb` | Header + report selector partial |
| `app/packs/startups/deals/views/deals/_weekly_summary_progress.html.erb` | Overall progress panel |
| `app/packs/startups/deals/views/deals/_weekly_summary_stagnation.html.erb` | Stagnation breakdown panel |
| `app/packs/startups/deals/views/deals/_weekly_summary_status.html.erb` | Status changes panel |
| `app/packs/startups/deals/views/deals/_weekly_summary_tasks.html.erb` | Tasks summary section |
| `app/packs/startups/deals/views/deals/_weekly_summary_charts.html.erb` | Charts section |
| `app/packs/ai/support_agents/views/deal_management_digest_mailer/weekly_summary.html.erb` | Email template |

### No Migration Required

All data stored in existing JSONB columns (`SupportAgentReport.json_fields`, `SupportAgent.json_fields`).

---

## Audit Trail Query Considerations

### Performance

Queries filter by:
- `auditable_type = 'DealInvestor'` (indexed)
- `auditable_id IN (deal.deal_investor_ids)` — scoped to one deal's investors (typically < 200)
- `created_at` range (7-day window)
- Change detection done in Ruby (not SQL LIKE), since `audited_changes` format varies

Since we're scoped to one deal (not entity-wide), the query set is small.

### Bulk Update Gap

`bulk_update_status` uses `update_all` — may bypass audit creation. Status changes from bulk operations may not appear in the weekly report.

**Recommendation (separate PR):** Fix bulk update to create audit records, or at minimum log status changes to a lightweight tracking table.

---

## Open Questions

1. **Preset steps UX** — Should the agent settings form show a dropdown of the deal's actual step names (better UX), or a text field for sequence pairs like "1-2,3-4"? Dropdown recommended.

2. **AI Insight** — P0 or P1? It requires LLM to be configured on the agent (which DealManagementAgent already supports for scoring/extraction).

3. **Historical reports** — How many past weeks to show? Current design: last 12.

4. **Consolidated email** — If a fund manager has 3 deals with agents, they get 3 emails. Should we offer a consolidated digest as a future enhancement?

5. **Stagnation threshold** — Reuses existing `stagnant_days` config. Is the current default (agent minimum of 1 day) appropriate, or should weekly summary default to 14?

6. **Email frequency** — Weekly only, or support daily/monthly as well? Current design: tied to AgentSchedule (already supports any cron frequency).

---

## Implementation Notes

### Task Title Extraction — ActionText Gotcha

The `Task` model uses `has_rich_text :details`, which creates an ActionText proxy that reads from `action_text_rich_texts` table. However, the actual task content is stored in a raw `details` string column on the `tasks` table (HTML). Calling `task.details` returns the ActionText proxy (empty if no ActionText record exists). To read the actual content:

```ruby
String(ActionController::Base.helpers.strip_tags(task.read_attribute(:details))).truncate(80)
```

Also requires `.includes(:rich_text_details)` to avoid N+1 on the ActionText lookup.

### SafeBuffer / Sidekiq 8 Strict Args

`strip_tags()` returns `ActiveSupport::SafeBuffer`, not `String`. Sidekiq 8 strict args rejects SafeBuffer values in job arguments. Wrapping with `String(...)` fixes individual values, but the entire params hash passed to the mailer must also be clean. Solution: JSON round-trip the full mailer params before `deliver_later`:

```ruby
weekly_params = JSON.parse({ ...hash... }.to_json)
DealManagementDigestMailer.with(weekly_params).weekly_summary.deliver_later
```

### String Keys After JSON Round-Trip

`JSON.parse(hash.to_json)` converts all symbol keys to string keys. The mailer must handle both:

```ruby
params[:support_agent_id] || params["support_agent_id"]
```

### Collapsible Task Tables in Dashboard

The dashboard shows overdue/upcoming/pending/completed task count cards. Each card's "View details" link toggles a collapsible table inline (via Bootstrap `data-bs-toggle="collapse"`) rather than redirecting to the deal page. All tables start collapsed. Upcoming = due within 7 days; Pending = no due date or due beyond 7 days.
