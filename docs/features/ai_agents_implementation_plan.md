# Tier 1 AI Agents — Implementation Plan

Five agents built on the existing Support Agent Framework. Every step that does meaningful work is gated by `enabled?("flag")` so any step can be skipped independently by setting its flag to `"false"` in `json_fields`. This matches the pattern in `KycOnboardingAgent` and `PortfolioCompanyAgent`.

**The `enabled?` helper (already in `SupportAgentService`):**
```ruby
def enabled?(field)
  %w[true 1 enabled yes].include? @support_agent.json_fields[field]&.downcase
end
```

All flags default to `"true"` — an agent with an empty `json_fields` runs all steps.

---

## Agent 1 — KYC Expiry Alert (extend `KycOnboardingAgent`)

### Changes required

1. Add one new step `check_expiry_status` after `check_field_to_document_consistency`.
2. Implement the existing `send_reminders` stub (currently only a debug log).

### Step pipeline after change

```
initialize_agent
check_field_completeness          if enabled?("validate_fields")
check_document_presence           if enabled?("validate_documents")
check_document_validity           if enabled?("validate_documents")
check_field_to_document_consistency  if enabled?("validate_documents")
check_expiry_status               if enabled?("check_expiry")        ← NEW flag
generate_progress_reports
send_reminders                    if enabled?("send_reminder")       ← IMPLEMENT stub
trigger_aml_if_complete           if enabled?("trigger_aml")
```

### `check_expiry_status` implementation

```ruby
def check_expiry_status(ctx, investor_kyc:, **)
  return true unless enabled?("check_expiry")

  expiry_date = investor_kyc.expiry_date
  if expiry_date.nil?
    ctx[:issues][:field_issues] << {
      type: :info, message: "No expiry date set", severity: :success
    }
    return true
  end

  days_remaining = (expiry_date - Date.today).to_i
  # Thresholds from json_fields, default 60/30/15
  warning_thresholds = @support_agent.json_fields["expiry_warning_days"]
                                     &.split(",")&.map(&:to_i) || [60, 30, 15]

  if investor_kyc.expired?
    ctx[:issues][:field_issues] << {
      type: :kyc_expired,
      message: "KYC expired on #{expiry_date}",
      severity: :blocking
    }
  elsif warning_thresholds.any? { |d| days_remaining <= d }
    ctx[:issues][:field_issues] << {
      type: :kyc_expiring_soon,
      message: "KYC expires in #{days_remaining} day(s) on #{expiry_date}",
      severity: :warning
    }
  else
    ctx[:issues][:field_issues] << {
      type: :info,
      message: "KYC valid until #{expiry_date} (#{days_remaining} days remaining)",
      severity: :success
    }
  end
  true
end
```

### `send_reminders` implementation

```ruby
def send_reminders(ctx, investor_kyc:, support_agent:, **)
  return true unless enabled?("send_reminder")

  expiry_issues = ctx[:issues][:field_issues].select { |i|
    %i[kyc_expired kyc_expiring_soon].include?(i[:type])
  }
  if expiry_issues.empty?
    Rails.logger.debug { "[KycOnboardingAgent] No expiry issues — skipping reminder" }
    return true
  end

  KycExpiryMailer.with(
    investor_kyc_id: investor_kyc.id,
    issues: expiry_issues,
    entity_id: support_agent.entity_id
  ).expiry_alert.deliver_later
end
```

### `json_fields` reference

| Key | Type | Default | Purpose |
|---|---|---|---|
| `validate_fields` | flag | `"true"` | Enable/disable field completeness check |
| `validate_documents` | flag | `"true"` | Enable/disable all three document steps |
| `check_expiry` | flag | `"true"` | Enable/disable expiry check step |
| `send_reminder` | flag | `"true"` | Enable/disable outbound reminder email |
| `trigger_aml` | flag | `"true"` | Enable/disable AML trigger |
| `expiry_warning_days` | value | `"60,30,15"` | Comma-separated day thresholds for warning |

### Files to modify / create

| Action | File |
|---|---|
| Modify | `app/packs/ai/support_agents/services/kyc_onboarding_agent.rb` |
| Create | `app/packs/core/investor_kycs/mailers/kyc_expiry_mailer.rb` |
| Create | `app/packs/core/investor_kycs/views/kyc_expiry_mailer/expiry_alert.html.erb` |

---

## Agent 2 — Distribution Readiness (`DistributionReadinessAgent`)

### Overview

New agent class mirroring `CallNoticeAgent`. Each step is individually skippable. Runs on-demand from the Capital Distributions page using the same `support_agents/progress_panel` partial.

### Step pipeline

```
initialize_agent
verify_investor_kyc               if enabled?("check_kyc")
check_net_payable_computed        if enabled?("check_net_payable")
check_distribution_notices_generated  if enabled?("check_docs_generated")
check_documents_approved          if enabled?("check_docs_approved")
verify_bank_details               if enabled?("check_bank_details")
mark_ready_to_pay
generate_progress_reports
```

### Step implementations

**`initialize_agent`**
```ruby
def initialize_agent(ctx, **)
  super
  report = ctx[:support_agent_report]
  if report
    mark_step_running(report, :initialize_agent)
    ctx[:issues] = { kyc_issues: [], payment_issues: [], document_issues: [], bank_issues: [] }
    mark_step_success(report, :initialize_agent, message: "Agent initialized")
  end
  true
end
```

**`verify_investor_kyc`**
```ruby
def verify_investor_kyc(ctx, target:, **)
  report = ctx[:support_agent_report]
  return true unless report

  unless enabled?("check_kyc")
    mark_step_skipped(report, :verify_investor_kyc, message: "Skipped via configuration")
    return true
  end

  mark_step_running(report, :verify_investor_kyc)
  # Iterate payments → linked commitment → investor_kyc
  # Identical logic to CallNoticeAgent#verify_investor_kyc
  failed_records = distribution_payments(target).filter_map do |payment|
    kyc = payment.capital_commitment&.investor_kyc
    if kyc.blank?
      { "name" => payment.investor_name, "reason" => "No KYC linked" }
    elsif !kyc.verified
      { "name" => payment.investor_name, "reason" => "KYC not verified" }
    end
  end

  if failed_records.any?
    mark_step_failed(report, :verify_investor_kyc,
      message: "#{failed_records.size} investor(s) have KYC issues",
      count: failed_records.size, failed_records: failed_records)
    finalize_report(report, status: "blocked", failed_step: 2)
    false
  else
    mark_step_success(report, :verify_investor_kyc,
      message: "All investors have verified KYC",
      count: distribution_payments(target).size)
    true
  end
end
```

**`check_net_payable_computed`**
```ruby
def check_net_payable_computed(ctx, target:, **)
  report = ctx[:support_agent_report]
  return true unless report

  unless enabled?("check_net_payable")
    mark_step_skipped(report, :check_net_payable_computed, message: "Skipped via configuration")
    return true
  end

  mark_step_running(report, :check_net_payable_computed)
  failed_records = distribution_payments(target).select { |p|
    p.net_payable_cents.nil? || p.net_payable_cents.zero?
  }.map { |p| { "name" => p.investor_name, "reason" => "Net payable not computed" } }

  if failed_records.any?
    mark_step_failed(report, :check_net_payable_computed,
      message: "#{failed_records.size} payment(s) missing net payable — re-run fee calculation",
      count: failed_records.size, failed_records: failed_records)
    finalize_report(report, status: "blocked", failed_step: 3)
    false
  else
    mark_step_success(report, :check_net_payable_computed,
      message: "All net payable amounts computed",
      count: distribution_payments(target).size)
    true
  end
end
```

**`check_distribution_notices_generated`** and **`check_documents_approved`** — same structure as their `CallNoticeAgent` counterparts, guarded by `enabled?("check_docs_generated")` and `enabled?("check_docs_approved")` respectively. Each step skips cleanly with `mark_step_skipped` when its flag is `"false"`.

**`verify_bank_details`**
```ruby
def verify_bank_details(ctx, target:, **)
  report = ctx[:support_agent_report]
  return true unless report

  unless enabled?("check_bank_details")
    mark_step_skipped(report, :verify_bank_details, message: "Skipped via configuration")
    return true
  end

  mark_step_running(report, :verify_bank_details)
  # Check each investor has bank account details (bank_account_number on InvestorKyc)
  failed_records = distribution_payments(target).filter_map do |payment|
    kyc = payment.capital_commitment&.investor_kyc
    if kyc&.bank_account_number.blank?
      { "name" => payment.investor_name, "reason" => "Bank account details missing on KYC" }
    end
  end

  if failed_records.any?
    mark_step_failed(report, :verify_bank_details,
      message: "#{failed_records.size} investor(s) missing bank details",
      count: failed_records.size, failed_records: failed_records)
    finalize_report(report, status: "blocked", failed_step: 5)
    false
  else
    mark_step_success(report, :verify_bank_details, message: "All bank details on file")
    true
  end
end
```

**`mark_ready_to_pay`** — always runs if reached; no flag needed. Confirms all steps passed.

### `targets`

```ruby
def targets(entity_id)
  CapitalDistribution.joins(:fund).where(funds: { entity_id: entity_id })
end
```

### Helper

```ruby
def distribution_payments(distribution)
  @distribution_payments ||= distribution.capital_distribution_payments
                                          .includes(capital_commitment: :investor_kyc)
end
```

### `STEP_LABELS`

```ruby
STEP_LABELS = {
  initialize_agent:                     "Initialize",
  verify_investor_kyc:                  "KYC Check",
  check_net_payable_computed:           "Net Payable",
  check_distribution_notices_generated: "Notices Generated",
  check_documents_approved:             "Docs Approved",
  verify_bank_details:                  "Bank Details",
  mark_ready_to_pay:                    "Ready to Pay",
  generate_progress_reports:            "Save Report"
}.freeze
```

### `json_fields` reference

| Key | Type | Default | Purpose |
|---|---|---|---|
| `check_kyc` | flag | `"true"` | Enable/disable KYC verification step |
| `check_net_payable` | flag | `"true"` | Enable/disable net payable check |
| `check_docs_generated` | flag | `"true"` | Enable/disable notice generation check |
| `check_docs_approved` | flag | `"true"` | Enable/disable document approval check |
| `check_bank_details` | flag | `"true"` | Enable/disable bank details check |

### Files to create / modify

| Action | File |
|---|---|
| Create | `app/packs/ai/support_agents/services/distribution_readiness_agent.rb` |
| Modify | `app/packs/ai/support_agents/models/support_agent.rb` — add `DistributionReadinessAgent` to `AGENT_TYPES` |
| Modify | Capital Distributions show view — embed `support_agents/progress_panel` partial |

---

## Agent 3 — KPI Collection Campaign (extend `PortfolioCompanyAgent`)

### Changes required

Add one new step `send_kpi_reminder` after `check_kpi_submission`. The step fires only when KPIs are missing and only on configured day-offsets from the period start, avoiding daily spam.

### Step pipeline after change

```
initialize_agent
check_kpi_submission              (existing)
send_kpi_reminder                 if enabled?("send_kpi_reminder")   ← NEW flag
check_document_presence           if enabled?("validate_documents")
check_valuations                  (existing)
generate_progress_reports
```

### `send_kpi_reminder` implementation

```ruby
def send_kpi_reminder(ctx, portfolio_company:, support_agent:, **)
  return true unless enabled?("send_kpi_reminder")

  kpi_missing = ctx[:issues][:kpi_issues].any? { |i| i[:severity] == :blocking }
  unless kpi_missing
    ctx[:issues][:kpi_issues] << {
      type: :info, message: "KPIs submitted — no reminder needed", severity: :success
    }
    return true
  end

  # Only fire on configured milestone days from period start
  due_period    = support_agent.json_fields["due_period"] || "Quarter"
  reminder_days = support_agent.json_fields["reminder_days"]
                               &.split(",")&.map(&:to_i) || [7, 14, 21]
  period_start  = Date.beginning_of_period(due_period)
  days_elapsed  = (Date.today - period_start).to_i

  unless reminder_days.include?(days_elapsed)
    ctx[:issues][:kpi_issues] << {
      type: :info,
      message: "Reminder not due today (day #{days_elapsed} of period; fires on days #{reminder_days.join(', ')})",
      severity: :success
    }
    return true
  end

  # Avoid double-sending — check last reminder timestamp stored on previous report
  last_report = SupportAgentReport
    .where(owner: portfolio_company, support_agent: support_agent)
    .order(created_at: :desc).first
  last_sent = last_report&.json_fields&.dig("last_kpi_reminder_sent_at")
  if last_sent && Date.parse(last_sent) >= Date.today
    ctx[:issues][:kpi_issues] << {
      type: :info, message: "Reminder already sent today", severity: :success
    }
    return true
  end

  EntityMailer.with(
    entity_id: portfolio_company.entity_id,
    requesting_entity_id: support_agent.entity_id
  ).kpi_reminder.deliver_later

  ctx[:last_kpi_reminder_sent_at] = Date.today.iso8601
  ctx[:issues][:kpi_issues] << {
    type: :info, message: "KPI reminder sent (day #{days_elapsed})", severity: :success
  }
  true
end
```

In `generate_progress_reports`, merge `last_kpi_reminder_sent_at` from ctx into `report.json_fields` when present.

### `json_fields` reference

All existing keys plus:

| Key | Type | Default | Purpose |
|---|---|---|---|
| `send_kpi_reminder` | flag | `"true"` | Enable/disable outbound KPI reminder step |
| `reminder_days` | value | `"7,14,21"` | Day offsets from period start when reminders fire |
| `due_period` | value | `"Quarter"` | Reporting period (already used by `check_kpi_submission`) |
| `days_before_due_period_end` | value | `"15"` | Already used by `check_kpi_submission` |
| `validate_documents` | flag | `"true"` | Already used by `check_document_presence` |

### Files to modify

| Action | File |
|---|---|
| Modify | `app/packs/ai/support_agents/services/portfolio_company_agent.rb` |

---

## Agent 4 — Data Quality Agent (`DataQualityAgent`)

### Overview

New agent targeting `Fund`. Each check is independently skippable. Runs nightly, produces one `SupportAgentReport` per fund, and emails a fix-it list.

### Step pipeline

```
initialize_agent
check_commitment_overflows        if enabled?("check_commitment_overflows")
check_missing_valuations          if enabled?("check_missing_valuations")
check_stale_fx_rates              if enabled?("check_stale_fx_rates")
compute_health_score
send_quality_report               if enabled?("send_report")
generate_progress_reports
```

### Step implementations

**`initialize_agent`**
```ruby
def initialize_agent(ctx, target:, **)
  super
  ctx[:fund] = target
  ctx[:issues] = { commitment_issues: [], valuation_issues: [], fx_issues: [] }
  ctx[:check_results] = []
  @support_agent.enabled?
end
```

**`check_commitment_overflows`**
```ruby
def check_commitment_overflows(ctx, fund:, **)
  unless enabled?("check_commitment_overflows")
    ctx[:check_results] << { name: "Commitment Overflows", status: :skipped }
    return true
  end

  overflows = fund.capital_commitments.select { |c|
    c.called_amount_cents.to_i > c.committed_amount_cents.to_i
  }

  if overflows.any?
    failed = overflows.map { |c|
      { "name" => c.investor_name,
        "reason" => "Called #{c.called_amount} > Committed #{c.committed_amount}" }
    }
    ctx[:issues][:commitment_issues] += failed
    ctx[:check_results] << { name: "Commitment Overflows", status: :fail, count: overflows.size }
  else
    ctx[:check_results] << { name: "Commitment Overflows", status: :pass }
  end
  true
end
```

**`check_missing_valuations`**
```ruby
def check_missing_valuations(ctx, fund:, **)
  unless enabled?("check_missing_valuations")
    ctx[:check_results] << { name: "Missing Valuations", status: :skipped }
    return true
  end

  stale_days = @support_agent.json_fields["stale_valuation_days"]&.to_i || 90
  stale = fund.portfolio_companies.select { |pc|
    pc.valuations.where('valuation_date >= ?', stale_days.days.ago).empty?
  }

  if stale.any?
    ctx[:issues][:valuation_issues] += stale.map { |pc|
      { "name" => pc.name, "reason" => "No valuation in the last #{stale_days} days" }
    }
    ctx[:check_results] << { name: "Missing Valuations", status: :fail, count: stale.size }
  else
    ctx[:check_results] << { name: "Missing Valuations", status: :pass }
  end
  true
end
```

**`check_stale_fx_rates`**
```ruby
def check_stale_fx_rates(ctx, fund:, **)
  unless enabled?("check_stale_fx_rates")
    ctx[:check_results] << { name: "Stale FX Rates", status: :skipped }
    return true
  end

  stale_days = @support_agent.json_fields["stale_fx_days"]&.to_i || 30
  # Query the exchange rate model for this fund's active currency pairs
  # Exact model name TBD — adjust to match actual ExchangeRate / FxRate class
  stale_pairs = ExchangeRate
    .where(entity_id: fund.entity_id)
    .where('updated_at < ?', stale_days.days.ago)

  if stale_pairs.any?
    ctx[:issues][:fx_issues] += stale_pairs.map { |r|
      { "name" => "#{r.from_currency}/#{r.to_currency}",
        "reason" => "Last updated #{r.updated_at.to_date}" }
    }
    ctx[:check_results] << { name: "Stale FX Rates", status: :fail, count: stale_pairs.size }
  else
    ctx[:check_results] << { name: "Stale FX Rates", status: :pass }
  end
  true
end
```

**`compute_health_score`** — always runs, not skippable (it's just arithmetic on ctx).
```ruby
def compute_health_score(ctx, **)
  results = ctx[:check_results].reject { |r| r[:status] == :skipped }
  passing = results.count { |r| r[:status] == :pass }
  ctx[:health_score] = results.any? ? (passing.to_f / results.size * 100).round : 100
  true
end
```

**`send_quality_report`**
```ruby
def send_quality_report(ctx, fund:, support_agent:, **)
  return true unless enabled?("send_report")

  DataQualityMailer.with(
    fund_id: fund.id,
    entity_id: support_agent.entity_id,
    health_score: ctx[:health_score],
    check_results: ctx[:check_results],
    issues: ctx[:issues]
  ).quality_report.deliver_later
  true
end
```

### `targets`

```ruby
def targets(entity_id)
  Fund.where(entity_id: entity_id)
      .includes(:capital_commitments, :portfolio_companies, :portfolio_investments)
end
```

### `json_fields` reference

| Key | Type | Default | Purpose |
|---|---|---|---|
| `check_commitment_overflows` | flag | `"true"` | Enable/disable commitment overflow check |
| `check_missing_valuations` | flag | `"true"` | Enable/disable stale valuation check |
| `check_stale_fx_rates` | flag | `"true"` | Enable/disable stale FX rate check |
| `send_report` | flag | `"true"` | Enable/disable email report |
| `stale_valuation_days` | value | `"90"` | Days before a missing valuation is flagged |
| `stale_fx_days` | value | `"30"` | Days before an FX rate is flagged as stale |

### Files to create / modify

| Action | File |
|---|---|
| Create | `app/packs/ai/support_agents/services/data_quality_agent.rb` |
| Create | `app/packs/core/base/mailers/data_quality_mailer.rb` |
| Create | `app/packs/core/base/mailers/views/data_quality_mailer/quality_report.html.erb` |
| Modify | `app/packs/ai/support_agents/models/support_agent.rb` — add `DataQualityAgent` to `AGENT_TYPES` |

---

## Agent 5 — E-Signing Monitor (`EsignMonitorAgent`)

### Overview

New agent. Runs at the entity level (one run per entity, iterating all its documents internally). Finds stuck e-sign requests, fires resends, and flags expired/voided documents for manual ops action.

### Step pipeline

```
initialize_agent
find_pending_esigns               (always — populates ctx for subsequent steps)
send_esign_reminders              if enabled?("send_reminders")
flag_expired_esigns               if enabled?("flag_expired")
generate_progress_reports
```

### Step implementations

**`initialize_agent`**
```ruby
def initialize_agent(ctx, target:, **)
  super
  ctx[:entity] = target
  ctx[:issues] = { esign_issues: [] }
  @support_agent.enabled?
end
```

**`find_pending_esigns`** — always runs; no flag (it only queries, takes no action).
```ruby
def find_pending_esigns(ctx, target:, **)
  reminder_after_days = @support_agent.json_fields["reminder_after_days"]&.to_i || 3

  ctx[:pending_docs] = Document
    .where(entity_id: target.id)
    .esign_status_requested
    .where('updated_at < ?', reminder_after_days.days.ago)
    .includes(:e_signatures)

  ctx[:issues][:esign_issues] << {
    type: :info,
    message: "#{ctx[:pending_docs].size} document(s) pending e-sign for > #{reminder_after_days} days",
    severity: ctx[:pending_docs].any? ? :warning : :success
  }
  true
end
```

**`send_esign_reminders`**
```ruby
def send_esign_reminders(ctx, **)
  unless enabled?("send_reminders")
    ctx[:issues][:esign_issues] << {
      type: :info, message: "Reminders skipped via configuration", severity: :success
    }
    return true
  end

  ctx[:pending_docs].each do |doc|
    if doc.resend_for_esign?
      EsignReminderJob.perform_later(doc.id)
      ctx[:issues][:esign_issues] << {
        type: :reminded, name: doc.name, message: "Reminder queued", severity: :success
      }
    else
      ctx[:issues][:esign_issues] << {
        type: :skipped,
        name: doc.name,
        message: "Not eligible for resend — check approval or e-signature configuration",
        severity: :warning
      }
    end
  end
  true
end
```

**`flag_expired_esigns`**
```ruby
def flag_expired_esigns(ctx, target:, **)
  unless enabled?("flag_expired")
    ctx[:issues][:esign_issues] << {
      type: :info, message: "Expired document check skipped via configuration", severity: :success
    }
    return true
  end

  expired_docs = Document
    .where(entity_id: target.id)
    .where(esign_status: %w[expired cancelled voided])

  expired_docs.each do |doc|
    ctx[:issues][:esign_issues] << {
      type: :expired,
      name: doc.name,
      message: "E-sign #{doc.esign_status} — resend or void manually",
      severity: :blocking
    }
  end

  if expired_docs.empty?
    ctx[:issues][:esign_issues] << {
      type: :info, message: "No expired or voided e-sign documents", severity: :success
    }
  end
  true
end
```

### `targets`

```ruby
def targets(entity_id)
  Entity.where(id: entity_id)
end
```

### `json_fields` reference

| Key | Type | Default | Purpose |
|---|---|---|---|
| `send_reminders` | flag | `"true"` | Enable/disable e-sign resend step |
| `flag_expired` | flag | `"true"` | Enable/disable expired document flagging |
| `reminder_after_days` | value | `"3"` | Days in "requested" state before resend is triggered |

### Files to create / modify

| Action | File |
|---|---|
| Create | `app/packs/ai/support_agents/services/esign_monitor_agent.rb` |
| Modify | `app/packs/ai/support_agents/models/support_agent.rb` — add `EsignMonitorAgent` to `AGENT_TYPES` |

---

## Shared notes

### `AGENT_TYPES` final state

```ruby
AGENT_TYPES = %w[
  KycOnboardingAgent
  PortfolioCompanyAgent
  FundStatsAgent
  PortfolioReportAgent
  CallNoticeAgent
  CashFlowAssistantAgent
  DistributionReadinessAgent
  DataQualityAgent
  EsignMonitorAgent
].freeze
```

### Skipping convention

Every step that takes action (sends email, blocks pipeline, makes external call) follows this pattern:

```ruby
def some_step(ctx, **)
  unless enabled?("flag_name")
    mark_step_skipped(report, :some_step, message: "Skipped via configuration")
    return true   # return true so the pipeline continues to the next step
  end
  # ... actual logic
end
```

Steps that only read/query and populate ctx (e.g. `find_pending_esigns`, `compute_health_score`) do not need a flag — they are cheap and have no side effects.

### `json_fields` editing

`json_fields` is edited as raw JSON in the SupportAgent admin UI (the controller parses it from a string in `support_agent_params`). When creating a new agent, provide a documented JSON example in its `DESCRIPTION` constant or agent card so ops know which keys to set:

```ruby
DESCRIPTION = "Monitors e-signing pipeline. Config keys: send_reminders (true/false), " \
              "flag_expired (true/false), reminder_after_days (integer, default 3).".freeze
```

### Suggested schedules (`AgentSchedule`)

| Agent | Frequency | Time |
|---|---|---|
| `KycOnboardingAgent` | Daily | 07:00 |
| `PortfolioCompanyAgent` | Weekly (Mon) | 08:00 |
| `DistributionReadinessAgent` | On-demand only | — |
| `DataQualityAgent` | Daily | 01:00 |
| `EsignMonitorAgent` | Daily | 08:00 |

### Build order

1. `KycOnboardingAgent` extension — least risk, base pipeline already tested
2. `PortfolioCompanyAgent` extension — same reasoning
3. `DistributionReadinessAgent` — scaffold from `CallNoticeAgent`, no new patterns
4. `EsignMonitorAgent` — new class, simple document queries
5. `DataQualityAgent` — new class, most SQL validation work; do last so FX model name is confirmed

### Issue hash keys per agent

| Agent | `ctx[:issues]` keys |
|---|---|
| `KycOnboardingAgent` | `field_issues`, `document_issues`, `aml_report` |
| `PortfolioCompanyAgent` | `kpi_issues`, `document_issues`, `valuation_issues` |
| `DistributionReadinessAgent` | `kyc_issues`, `payment_issues`, `document_issues`, `bank_issues` |
| `DataQualityAgent` | `commitment_issues`, `valuation_issues`, `fx_issues` |
| `EsignMonitorAgent` | `esign_issues` |
