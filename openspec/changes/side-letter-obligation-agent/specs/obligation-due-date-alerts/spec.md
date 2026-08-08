# obligation-due-date-alerts

## ADDED Requirements

### Requirement: Daily enforcement run
The `SideLetterObligationAgent` SHALL support a scheduled enforcement mode, run daily via `AgentSchedule`, that scans approved obligations' projected tasks and classifies them as upcoming (due within the obligation's `reminder_days_before` days), due today, or overdue.

#### Scenario: Scheduled run classifies items
- **WHEN** the enforcement run executes for an entity with tasks due in 3 days, today, and 5 days ago
- **THEN** each is picked up in its respective category, honoring per-obligation `reminder_days_before`

#### Scenario: Suppressed pre-due alerts
- **WHEN** an obligation has `reminder_days_before = 0`
- **THEN** no upcoming alert is sent for it, while due-today and overdue alerts still fire

### Requirement: Consolidated owner notifications
The enforcement run SHALL send at most one consolidated notification per owner per run, listing all their upcoming, due, and overdue obligation tasks, delivered through the Noticed stack. When an obligation has no `owner_user_id`, the notification SHALL fall back to the agent's `notify_tag` recipient group.

#### Scenario: Owner with multiple items gets one email
- **WHEN** an owner has two upcoming and one overdue obligation task
- **THEN** they receive a single notification listing all three items

#### Scenario: Ownerless obligation alerts the notify group
- **WHEN** a due obligation has only an owner team and no owner user
- **THEN** the alert goes to the users resolved from the agent's `notify_tag`

### Requirement: Overdue escalation
Overdue obligation tasks SHALL be re-alerted on the configured `overdue_escalation_days` cadence, with escalations additionally sent to the agent's `notify_tag` recipient group.

#### Scenario: Escalation cadence respected
- **WHEN** a task is 1 day overdue with a 3-day escalation cadence and an overdue alert was sent yesterday
- **THEN** no new overdue alert is sent until the cadence elapses

### Requirement: Alert logging and idempotency
Every sent alert SHALL be logged as an `ObligationReminder` (kind: upcoming, due, or overdue; recipient; timestamp), and the log SHALL serve as the idempotency guard: at most one `upcoming` and one `due` alert per obligation per due date, and `overdue` alerts only after the escalation interval since the last one.

#### Scenario: Rerun does not duplicate alerts
- **WHEN** the enforcement run executes twice on the same day
- **THEN** no duplicate notifications are sent and no duplicate reminder log rows are created

### Requirement: Enforcement report
Each enforcement run SHALL produce a `SupportAgentReport` summarizing counts of upcoming, due, overdue, alerted, and escalated items, and record its execution through the standard `AgentExecutionLog`.

#### Scenario: Run summary visible in execution history
- **WHEN** an enforcement run completes
- **THEN** the agent's execution history shows the run with its summary counts
