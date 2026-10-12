# Spec Delta

## MODIFIED Requirements

### Requirement: Step owners and reminders
A `system` or `acknowledge` step SHALL have owners, resolved in this order: the record's override owner
when its record type defines one (e.g. a KPI report's portfolio company manager); else a named user of the
entity set on the step; else the record's default owners (the record's creator by default; a record type
MAY define several). When such a step has been current longer than its effective reminder interval, each
owner SHALL receive a reminder email with the step name, status line and a link to the record. The
reminder SHALL repeat each interval while the step stays current. In such workflows, reminders for human
steps SHALL also be timed from when the step became current, not from the instance's last update. The time
a step passed, and so the time the next step became current, SHALL be taken from the record's data where
the data records it (never earlier than the previous step passed, never later than now), falling back to
the time of detection. Human-step reminders SHALL be unchanged. Record types that define neither an
override nor several default owners SHALL behave exactly as before.

#### Scenario: Owner reminded
- **WHEN** "Approve notices" has been current for 3 days with a 2-day interval and owner "call creator"
- **THEN** the call's creator receives one reminder naming the step and "28 of 40 call notices await approval"

#### Scenario: Step completed while nobody was looking
- **WHEN** the last notice is approved Monday 10:00, nobody opens the call, and the reminder interval for the next step is 2 days
- **THEN** history records the step passed at Monday 10:00, the next step is current since Monday 10:00, no reminder is sent on Wednesday's 00:30 run (under 2 days), and its owner is reminded on Thursday's 00:30 run

#### Scenario: No interval, no reminder
- **WHEN** a step and its template have no reminder interval
- **THEN** no reminder is sent

#### Scenario: Owner left the company
- **WHEN** the owner user no longer exists or is inactive
- **THEN** no email is sent and the panel shows "Owner unavailable — update the journey template"; the owner is read from the live template step, so fixing the template fixes in-flight calls

#### Scenario: Record override wins
- **WHEN** a KPI report's portfolio company is managed by Priya and the step's named owner is Rahul
- **THEN** only Priya is reminded

#### Scenario: Several default owners
- **WHEN** a KPI report step has no override and no named owner, and the default owners are Anita and Vikram
- **THEN** Anita and Vikram each receive one reminder
