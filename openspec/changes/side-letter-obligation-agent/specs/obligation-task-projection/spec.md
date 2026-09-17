# obligation-task-projection

## ADDED Requirements

### Requirement: Projection on approval only
The system SHALL create task projections exclusively when an obligation transitions to `review_status = approved`: calendar-driven obligations (`trigger_type = calendar_event` with a `frequency_rrule`) create a `TaskRecurrenceRule` whose id is stored on the obligation; one-time obligations (`trigger_type = one_time`) create a single `Task` with `due_date = next_due_date`; event-triggered and ongoing obligations create no task.

#### Scenario: Recurring obligation projects a recurrence rule
- **WHEN** a quarterly reporting obligation with an RRULE is approved
- **THEN** a `TaskRecurrenceRule` is created from that RRULE and the existing generator materializes its future task occurrences

#### Scenario: One-time obligation projects a single task
- **WHEN** a one-time obligation with a due date is approved
- **THEN** exactly one task with that due date is created

#### Scenario: Event-triggered obligation stays armed
- **WHEN** a key-person notice obligation is approved
- **THEN** no task is created and the obligation shows as armed in the matrix

### Requirement: Projected task attributes
Projected tasks SHALL be owned polymorphically by the `SideLetterObligation`, assigned to the obligation's `owner_user_id` when present, and categorized "Compliance".

#### Scenario: Task links back to its obligation
- **WHEN** a projected task is viewed
- **THEN** its owner is the obligation and the obligation's commitment and investor are reachable from it

### Requirement: Manual firing of armed obligations
The system SHALL allow an authorized user to fire an armed (event-triggered) obligation, supplying a due date, which creates a dated task projected from that obligation.

#### Scenario: Firing a key-person notice
- **WHEN** a user fires an armed key-person obligation with a due date 5 business days out
- **THEN** a task with that due date, owned by the obligation and assigned to its owner, is created

### Requirement: Teardown on reject or waive
When an approved obligation is rejected, waived, or expired, the system SHALL remove its recurrence rule and destroy its incomplete projected tasks, leaving completed tasks and fulfillment history intact.

#### Scenario: Waiving a recurring obligation
- **WHEN** an approved recurring obligation is waived
- **THEN** its `TaskRecurrenceRule` and incomplete future tasks are removed while past completed tasks remain

### Requirement: Fulfillment on task completion
Completing a task owned by a `SideLetterObligation` SHALL create an `ObligationFulfillment` linked to that task and, for one-time obligations, set the obligation `status` to `fulfilled`.

#### Scenario: Completing a projected task records fulfillment
- **WHEN** the assignee marks a projected task done
- **THEN** an `ObligationFulfillment` exists recording the user and completion date, linked to the task and obligation

#### Scenario: Recurring obligation stays active after one fulfillment
- **WHEN** one occurrence task of a recurring obligation is completed
- **THEN** a fulfillment is recorded and the obligation remains `active`
