# Portfolio Company Agent Scheduling Guide

## Overview

The Portfolio Company Agent is scheduled using the **Agent Scheduler Framework**, a comprehensive system that automatically runs support agents on configurable schedules (daily, weekly, monthly, etc.).

---

## How Scheduling Works

### Architecture Flow

```
1. DailyMorningJob (runs at 01:30 AM daily via whenever/cron)
   ↓
2. AgentDailySchedulerService
   ↓ (finds all enabled schedules due today)
3. Creates AgentExecutionLog (status: "queued")
   ↓
4. Schedules AgentRunnerJob.perform_at(run_time, execution_log_id)
   ↓
5. AgentRunnerJob executes at scheduled time
   ↓ (loads agent, finds targets, executes)
6. PortfolioCompanyAgent.call(support_agent_id, target, entity_id)
   ↓
7. Updates AgentExecutionLog (status: "completed"/"failed")
   ↓
8. Creates SupportAgentReport for each portfolio company
   ↓
9. Sends notifications (if configured)
```

---

## Database Schema - Where Scheduling Info is Stored

### 1. **`agent_schedules` Table**
**Location**: Primary scheduling configuration

**Key Columns**:
- `support_agent_id` - FK to support_agents table
- `entity_id` - FK to entities table (tenant isolation)
- `frequency` - enum: 'daily', 'weekly', 'monthly', 'bimonthly', 'quarterly', 'half_yearly'
- `run_on_day` - integer:
  - Weekly: 0-6 (Sunday=0, Monday=1, ..., Saturday=6)
  - Monthly: 1-31 (day of month)
- `run_at_time` - time: HH:MM when to run (e.g., "09:00")
- `timezone` - string: 'Asia/Kolkata', 'UTC', 'America/New_York', etc.
- `enabled` - boolean: schedule active/inactive
- `next_run_at` - datetime: calculated next execution time (UTC)
- `retry_count` - integer: number of retry attempts on failure
- `retry_interval_minutes` - integer: minutes between retries
- `notify_on_success` - boolean
- `notify_on_failure` - boolean
- `notify_on_partial_success` - boolean
- `failure_notification_user_ids` - jsonb: array of user IDs to notify
- `created_by_id` - FK to users table

**Validations**:
- One schedule per support_agent per entity (uniqueness constraint)
- Frequency required
- run_at_time required
- Timezone must be valid ActiveSupport timezone

### 2. **`agent_execution_logs` Table**
**Location**: Execution history tracking

**Key Columns**:
- `agent_schedule_id` - FK to agent_schedules (nullable for manual runs)
- `support_agent_id` - FK to support_agents
- `entity_id` - FK to entities
- `trigger_type` - enum: 'scheduled', 'manual'
- `status` - enum: 'queued', 'running', 'completed', 'failed', 'partial_success'
- `started_at` - datetime
- `completed_at` - datetime
- `attempt_number` - integer: retry attempt number
- `execution_summary` - jsonb: stores results/errors
  ```json
  {
    "total_targets": 10,
    "successful": 8,
    "failed": 2,
    "errors": [...]
  }
  ```

### 3. **`support_agents` Table**
**Location**: Agent configuration

**Key Columns**:
- `agent_type` - string: "PortfolioCompanyAgent" (and others)
- `name` - string: Display name
- `enabled` - boolean: Agent active/inactive
- `entity_id` - FK to entities
- `json_fields` - jsonb: Agent-specific configuration
  ```json
  {
    "due_period": "Quarter",
    "days_before_due_period_end": 15,
    "valuation_period": "Quarter",
    "days_before_valuation_period_end": 15,
    "chat_config": {
      "enabled": true,
      "model": "gemini-2.0-flash-exp"
    }
  }
  ```

### 4. **`support_agent_reports` Table**
**Location**: Agent execution results per target

**Key Columns**:
- `support_agent_id` - FK to support_agents
- `owner_type` - string: "Investor" (polymorphic)
- `owner_id` - integer: FK to investors table
- `status` - enum: 'completed', 'failed'
- `json_fields` - jsonb: Detailed compliance results
  ```json
  {
    "kpi_issues": [
      {
        "key": "kpi",
        "type": "missing",
        "message": "Last Quarter KPIs not submitted between 2025-12-31 and 2026-03-16",
        "severity": "blocking"
      }
    ],
    "document_issues": [...],
    "valuation_issues": [...]
  }
  ```

---

## How to Schedule Portfolio Company Agent

### Method 1: Via UI (Recommended)

1. **Navigate to Support Agent**:
   ```
   /support_agents/{agent_id}
   ```

2. **Click "Schedule" Tab**

3. **Fill in Schedule Form**:
   - ✅ Enable Schedule checkbox
   - **Frequency**: Daily/Weekly/Monthly/Quarterly/etc.
   - **Run On**:
     - Weekly: Select day of week (Monday, Tuesday, etc.)
     - Monthly: Select day of month (1-31)
   - **Run At**: Time in HH:MM format (e.g., "09:00")
   - **Timezone**: Select from dropdown (e.g., "Asia/Kolkata")
   - **Notifications**:
     - Check "On Success" to notify when all targets succeed
     - Check "On Failure" to notify when agent fails after retries
     - Check "On Partial Success" to notify when some targets fail
     - Select users to notify from dropdown

4. **Save Schedule**

### Method 2: Via Rails Console

```ruby
# Find the Portfolio Company Agent
agent = SupportAgent.find_by(
  agent_type: "PortfolioCompanyAgent",
  entity_id: 1  # Your entity ID
)

# Create schedule
schedule = AgentSchedule.create!(
  support_agent: agent,
  entity_id: agent.entity_id,
  frequency: 'weekly',      # or 'daily', 'monthly', 'quarterly', etc.
  run_on_day: 1,            # Monday (0=Sunday, 1=Monday, ..., 6=Saturday)
  run_at_time: '09:00',     # 9:00 AM
  timezone: 'Asia/Kolkata', # IST
  enabled: true,
  retry_count: 2,           # Retry 2 times on failure
  retry_interval_minutes: 30, # Wait 30 min between retries
  notify_on_failure: true,
  notify_on_partial_success: true,
  failure_notification_user_ids: [1, 2, 3], # User IDs to notify
  created_by: User.first
)
```

### Method 3: Via Seeds/Migration

```ruby
# In db/seeds.rb or a migration
entity = Entity.find(1)

support_agent = SupportAgent.find_or_create_by!(
  entity: entity,
  agent_type: "PortfolioCompanyAgent"
) do |agent|
  agent.name = "PortCo Compliance"
  agent.enabled = true
  agent.json_fields = {
    "due_period" => "Quarter",
    "days_before_due_period_end" => 15,
    "valuation_period" => "Quarter",
    "days_before_valuation_period_end" => 15
  }
end

AgentSchedule.find_or_create_by!(
  support_agent: support_agent,
  entity: entity
) do |schedule|
  schedule.frequency = 'weekly'
  schedule.run_on_day = 1  # Monday
  schedule.run_at_time = '09:00'
  schedule.timezone = 'Asia/Kolkata'
  schedule.enabled = true
  schedule.notify_on_failure = true
end
```

---

## Modifying Existing Schedule

### Via UI
1. Go to `/support_agents/{agent_id}?tab=schedule`
2. Modify any field in the form
3. Click "Update Schedule"

### Via Rails Console
```ruby
schedule = AgentSchedule.find_by(support_agent_id: 1, entity_id: 1)

# Change frequency
schedule.update!(frequency: 'daily')

# Change time
schedule.update!(run_at_time: '14:30')  # 2:30 PM

# Change timezone
schedule.update!(timezone: 'America/New_York')

# Disable schedule
schedule.update!(enabled: false)

# Change notification settings
schedule.update!(
  notify_on_success: true,
  failure_notification_user_ids: [4, 5, 6]
)
```

---

## Manual Execution (On-Demand)

### Via UI
1. Go to `/support_agents/{agent_id}`
2. Click "Run Agent" button
3. Optionally enable "Show Steps" for real-time progress

### Via Rails Console
```ruby
# Quick run without steps
SupportAgentJob.perform_later(support_agent_id: 1)

# Run with steps (see live progress)
SupportAgentJob.perform_later(
  support_agent_id: 1,
  with_steps: true
)

# Run for specific target
SupportAgentJob.perform_later(
  support_agent_id: 1,
  target_id: 123,        # Specific Investor ID
  target_type: "Investor"
)
```

---

## Checking Execution History

### Via UI
1. Go to `/support_agents/{agent_id}`
2. Click "Execution History" tab
3. View list of all runs with status, timing, results

### Via Rails Console
```ruby
# Get all executions for an agent
logs = AgentExecutionLog.for_agent_entity(agent_id: 1, entity_id: 1)

# Get recent failures
failed = AgentExecutionLog
  .where(support_agent_id: 1)
  .where(status: 'failed')
  .order(created_at: :desc)
  .limit(10)

# Get execution summary
log = AgentExecutionLog.last
log.execution_summary
# => {
#   "total_targets" => 10,
#   "successful" => 8,
#   "failed" => 2,
#   "errors" => [...]
# }
```

---

## Cron Configuration

The daily scheduler runs via **whenever** gem.

**File**: `config/schedule.rb`

**Current Setup**: No explicit agent scheduler entry (runs via DailyMorningJob)

**How DailyMorningJob is Scheduled**:
Check for sidekiq-cron or whenever configuration:

```bash
# View whenever generated crontab
bundle exec whenever

# Update crontab
bundle exec whenever --update-crontab
```

**DailyMorningJob triggers**:
- Location: `app/packs/core/base/jobs/daily_morning_job.rb`
- Line 47: `AgentDailySchedulerService.new.call`
- Runs at: 01:30 AM (configured in sidekiq-cron or whenever)

---

## Key Service Classes

### 1. **AgentDailySchedulerService**
**Path**: `app/packs/ai/support_agents/services/agent_scheduler/agent_daily_scheduler_service.rb`

**Purpose**: Runs daily to schedule agents for the day

**Logic**:
- Finds all `AgentSchedule.enabled`
- Checks `should_run_today?` based on frequency
- Creates `AgentExecutionLog`
- Enqueues `AgentRunnerJob.perform_at(run_time, log_id)`

### 2. **AgentRunnerJob**
**Path**: `app/packs/ai/support_agents/jobs/agent_scheduler/agent_runner_job.rb`

**Purpose**: Executes the agent against all targets

**Logic**:
1. Marks log as "running"
2. Calls `agent.targets(entity_id)` to get all portfolio companies
3. Loops through each target:
   ```ruby
   agent.call(
     support_agent_id: id,
     target: investor,
     entity_id: entity_id
   )
   ```
4. Handles success/failure
5. Sends notifications if configured

### 3. **PortfolioCompanyAgent**
**Path**: `app/packs/ai/support_agents/services/portfolio_company_agent.rb`

**Purpose**: Compliance checks for portfolio companies

**Targets**:
```ruby
def targets(entity_id)
  Investor.where(
    entity_id: entity_id,
    category: "Portfolio Company"
  ).includes(:kpi_reports, :valuations)
end
```

**Steps**:
1. `check_kpi_submission` - Validates last quarter KPIs
2. `check_document_presence` - Checks for required documents
3. `check_valuations` - Validates recent valuations
4. `generate_progress_reports` - Creates SupportAgentReport

---

## Testing Scheduler

### Test Job (Dev/Staging Only)
```ruby
# In Rails console or Sidekiq
AgentSchedulerTestJob.perform_now

# Or enable via ENV
ENABLE_AGENT_SCHEDULER_TEST=true bundle exec sidekiq
```

### Manual Trigger for Today
```ruby
# Force run scheduler service
AgentDailySchedulerService.new.call
# => Returns count of scheduled runs

# Check what got scheduled
AgentExecutionLog.where(
  trigger_type: 'scheduled',
  status: 'queued'
).order(created_at: :desc)
```

---

## Notifications

When configured, notifications are sent via:

**File**: Look for `AgentFailureNotifier` or similar service

**Triggered By**: `AgentRunnerJob` after execution completes

**Channels**: Check notification system (email, in-app, etc.)

---

## Best Practices

1. **Always Set Timezone**: Use `Asia/Kolkata` for IST, not `UTC+5:30`
2. **Test Before Enabling**: Run manual execution first
3. **Monitor Execution Logs**: Check history tab regularly
4. **Set Appropriate Retry**: 2-3 retries with 30-60 min intervals
5. **Configure Notifications**: At minimum, enable `notify_on_failure`
6. **Avoid Overlapping Schedules**: Don't schedule too frequently if agent takes long to run

---

## Troubleshooting

### Schedule Not Running
1. Check `schedule.enabled == true`
2. Verify `schedule.next_run_at` is in the future
3. Check Sidekiq is running: `bundle exec sidekiq`
4. Verify DailyMorningJob is scheduled in cron

### Agent Failing
1. Check `AgentExecutionLog.last.execution_summary`
2. Review `SupportAgentReport` records for error details
3. Check agent configuration in `support_agent.json_fields`
4. Verify targets exist: `agent.agent.new.targets(entity_id).count`

### No Notifications
1. Verify `notify_on_failure` or similar is `true`
2. Check `failure_notification_user_ids` has user IDs
3. Verify users exist and have valid emails
4. Check notification delivery system (ActionMailer, Noticed, etc.)

---

## Summary

- **Scheduling Storage**: `agent_schedules` table
- **Execution History**: `agent_execution_logs` table
- **Results Storage**: `support_agent_reports` table
- **Daily Trigger**: `DailyMorningJob` → `AgentDailySchedulerService`
- **Execution**: `AgentRunnerJob` → `PortfolioCompanyAgent`
- **UI**: `/support_agents/{id}?tab=schedule`
- **Console**: `AgentSchedule.create!(...)`
