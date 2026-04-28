# Agent Scheduler Framework

## Overview

The Agent Scheduler Framework provides automated, scheduled execution of AI Support Agents. It enables agents to run at configured times with support for various frequencies, automatic retries, and failure notifications.

---

## Components

### 1. Data Models

| Model | Purpose |
|-------|---------|
| **SupportAgent** | Defines an agent type and its configuration. Links to the actual agent class (e.g., TestSupportAgent, PortfolioReportAgent) |
| **AgentSchedule** | Defines WHEN an agent should run (time, frequency, timezone) and retry/notification settings |
| **AgentExecutionLog** | Tracks each individual run attempt with status, timing, results, and errors |

### 2. Services

| Service | Purpose |
|---------|---------|
| **AgentDailySchedulerService** | The "planner" - runs once daily to identify and queue all agent runs due today |
| **AgentNotificationService** | Sends success/error notifications to configured users |
| **AgentFailureNotifier** | Sends failure notifications when all retries are exhausted |

### 3. Jobs

| Job | Purpose |
|-----|---------|
| **DailyMorningJob** | Cron job (1:30 AM daily) that triggers the daily scheduler |
| **AgentRunnerJob** | The "worker" - executes a single agent run and handles results |

---

## Workflow

### Daily Scheduling Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                     DAILY SCHEDULING (1:30 AM)                      │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
                    ┌─────────────────────────┐
                    │     DailyMorningJob     │
                    │   (Sidekiq Cron Job)    │
                    └─────────────────────────┘
                                  │
                                  ▼
                    ┌─────────────────────────┐
                    │ AgentDailySchedulerService │
                    └─────────────────────────┘
                                  │
                    ┌─────────────┴─────────────┐
                    ▼                           ▼
         ┌──────────────────┐        ┌──────────────────┐
         │  Load all enabled │        │  For each schedule │
         │  AgentSchedules   │        │  due today:        │
         └──────────────────┘        └──────────────────┘
                                              │
                    ┌─────────────────────────┼─────────────────────────┐
                    ▼                         ▼                         ▼
         ┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐
         │ Check frequency:  │     │ Create execution │     │ Queue AgentRunner │
         │ Should run today? │     │ log (queued)     │     │ Job at run_at_time│
         └──────────────────┘     └──────────────────┘     └──────────────────┘
```

### Agent Execution Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                 AGENT EXECUTION (at scheduled time)                 │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
                    ┌─────────────────────────┐
                    │     AgentRunnerJob      │
                    │  (processes from queue) │
                    └─────────────────────────┘
                                  │
                                  ▼
                    ┌─────────────────────────┐
                    │  Mark execution_log     │
                    │  status = "running"     │
                    └─────────────────────────┘
                                  │
                                  ▼
                    ┌─────────────────────────┐
                    │  Get targets from agent │
                    │  agent.targets(entity)  │
                    └─────────────────────────┘
                                  │
                                  ▼
                    ┌─────────────────────────┐
                    │  For each target:       │
                    │  Execute agent.call()   │
                    └─────────────────────────┘
                                  │
                    ┌─────────────┴─────────────┐
                    ▼                           ▼
         ┌──────────────────┐        ┌──────────────────┐
         │     SUCCESS      │        │     FAILURE      │
         └──────────────────┘        └──────────────────┘
                    │                           │
                    ▼                           ▼
         ┌──────────────────┐        ┌──────────────────┐
         │ Mark as completed │        │ Mark as failed   │
         │ Send notifications│        │ Check retry count│
         └──────────────────┘        └──────────────────┘
                                              │
                              ┌───────────────┴───────────────┐
                              ▼                               ▼
                   ┌──────────────────┐            ┌──────────────────┐
                   │ Retries remaining │            │  No retries left  │
                   │ Schedule retry    │            │  Send failure     │
                   │ after interval    │            │  notification     │
                   └──────────────────┘            └──────────────────┘
```

---

## Frequency Logic

The scheduler determines if an agent should run today based on its frequency:

| Frequency | Run Condition |
|-----------|--------------|
| **Daily** | Every day |
| **Weekly** | When today's weekday matches `run_on_day` (0=Sunday, 6=Saturday) |
| **Monthly** | When today's date matches `run_on_day` (1-31) |
| **Bimonthly** | Every 2 months on `run_on_day` |
| **Quarterly** | Every 3 months (Jan, Apr, Jul, Oct) on `run_on_day` |
| **Half-yearly** | Every 6 months (Jan, Jul) on `run_on_day` |

**Edge Case:** If `run_on_day` exceeds the month's days (e.g., 31 in February), the agent runs on the last day of the month.

---

## Execution Status Lifecycle

```
┌─────────┐     ┌─────────┐     ┌───────────┐
│ QUEUED  │ ──▶ │ RUNNING │ ──▶ │ COMPLETED │
└─────────┘     └─────────┘     └───────────┘
                    │
                    │           ┌─────────────────┐
                    └─────────▶ │ PARTIAL_SUCCESS │
                    │           └─────────────────┘
                    │
                    └─────────▶ ┌────────┐
                               │ FAILED │
                               └────────┘
```

| Status | Description |
|--------|-------------|
| **queued** | Execution log created, waiting for scheduled time |
| **running** | Agent is currently executing |
| **completed** | All targets processed successfully |
| **partial_success** | Some targets succeeded, some failed |
| **failed** | Execution failed (error or all targets failed) |

---

## Retry Mechanism

When an agent execution fails:

1. Check if `retry_count > 0` in the schedule
2. Check if `attempt_number < retry_count + 1`
3. If retries available:
   - Create new execution log with `attempt_number + 1`
   - Schedule AgentRunnerJob after `retry_interval_minutes`
4. If no retries left:
   - Send failure notification to configured users

```
Attempt 1 fails
    │
    ▼
retry_count = 2, retry_interval = 5 min
    │
    ▼
Wait 5 minutes ──▶ Attempt 2 fails
                        │
                        ▼
                   Wait 5 minutes ──▶ Attempt 3 fails
                                           │
                                           ▼
                                      No retries left
                                           │
                                           ▼
                                    Send failure notification
```

---

## Notification System

### Success Notifications
- Sent to employees tagged with `notify_tag` (from agent's json_fields)
- Includes summary of processed targets

### Error Notifications (Partial Failures)
- Sent when some targets succeed but others fail
- Includes details of failed targets

### Failure Notifications
- Sent when all retries are exhausted
- Goes to users in `failure_notification_user_ids`
- Includes error message and execution details

---

## Timezone Handling

- All schedules store a `timezone` (e.g., "Asia/Kolkata", "America/New_York")
- `run_at_time` is interpreted in the schedule's timezone
- The scheduler converts to UTC for Sidekiq job scheduling
- This ensures agents run at the expected local time regardless of server timezone

---

## Key Design Decisions

1. **Daily Planning, Not Polling**
   - Schedules are evaluated once per day, not continuously polled
   - Reduces database load and simplifies logic

2. **Custom Retry Handling**
   - Uses application-level retries instead of Sidekiq's built-in retry
   - Allows per-schedule retry configuration

3. **Execution Logs as Audit Trail**
   - Every run attempt creates a separate log
   - Provides full history for debugging and compliance

4. **Partial Success Tracking**
   - Agents can process multiple targets
   - Individual target failures don't fail the entire run

5. **Entity-Scoped Scheduling**
   - Each schedule is tied to a specific entity
   - Supports multi-tenant deployments

---

## Testing in Local Environment

For local testing, a cron job runs every 2 minutes (instead of daily):

1. Set environment variable: `ENABLE_AGENT_SCHEDULER_TEST=true`
2. Start Sidekiq: `bundle exec sidekiq`
3. Create a schedule with `run_at_time` a few minutes in the future
4. Watch logs for execution output

---

## Future Enhancements

- Manual trigger from UI (bypass scheduling)
- Execution history dashboard
- Performance metrics and monitoring
- Concurrent execution limits
- Priority queuing for critical agents
