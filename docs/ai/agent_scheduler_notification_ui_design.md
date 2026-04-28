# Agent Scheduler Notification UI Design

## Overview

This document outlines the UI design for configuring notifications in the Agent Scheduler framework. Notifications alert users about agent execution outcomes (success, failure, partial success).

---

## Notification Configuration Location

Notifications are configured as part of the **AgentSchedule** form. When a user creates or edits a schedule for an agent, they can configure notification preferences in a dedicated section.

---

## UI Wireframe

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         EDIT AGENT SCHEDULE                                  │
│                         Agent: Cash Flow Assistant                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─── SCHEDULE SETTINGS ───────────────────────────────────────────────┐    │
│  │                                                                      │    │
│  │  Frequency         [Daily          ▼]                               │    │
│  │                                                                      │    │
│  │  Run at Time       [09:00         ]                                 │    │
│  │                                                                      │    │
│  │  Timezone          [Asia/Kolkata   ▼]                               │    │
│  │                                                                      │    │
│  │  Run on Day        [Monday         ▼]  (shown for weekly/monthly)   │    │
│  │                                                                      │    │
│  └──────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│  ┌─── RETRY SETTINGS ──────────────────────────────────────────────────┐    │
│  │                                                                      │    │
│  │  Retry Count           [3    ]  attempts before marking as failed   │    │
│  │                                                                      │    │
│  │  Retry Interval        [5    ]  minutes between retries             │    │
│  │                                                                      │    │
│  └──────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│  ┌─── NOTIFICATION SETTINGS ───────────────────────────────────────────┐    │
│  │                                                                      │    │
│  │  Notify When:                                                       │    │
│  │  ┌──────────────────────────────────────────────────────────────┐   │    │
│  │  │  ☐  On Success                                                │   │    │
│  │  │      Agent completes all targets without errors               │   │    │
│  │  │                                                               │   │    │
│  │  │  ☑  On Failure                                                │   │    │
│  │  │      Agent fails after all retry attempts exhausted           │   │    │
│  │  │                                                               │   │    │
│  │  │  ☑  On Partial Success                                        │   │    │
│  │  │      Some targets succeed, some fail                          │   │    │
│  │  └──────────────────────────────────────────────────────────────┘   │    │
│  │                                                                      │    │
│  │  Notification Recipients:                                           │    │
│  │  ┌──────────────────────────────────────────────────────────────┐   │    │
│  │  │  [Select users...                                         ▼] │   │    │
│  │  │                                                               │   │    │
│  │  │  Selected:                                                    │   │    │
│  │  │  ┌─────────────────────────────────────────────────────────┐ │   │    │
│  │  │  │ ✕  John Smith (john.smith@acme.com)                     │ │   │    │
│  │  │  │ ✕  Jane Doe (jane.doe@acme.com)                         │ │   │    │
│  │  │  └─────────────────────────────────────────────────────────┘ │   │    │
│  │  └──────────────────────────────────────────────────────────────┘   │    │
│  │                                                                      │    │
│  │  Internal Notifications:                                            │    │
│  │  ┌──────────────────────────────────────────────────────────────┐   │    │
│  │  │  ☑  Send error details to Caphive support team               │   │    │
│  │  │      Technical error information will be sent internally     │   │    │
│  │  │      for debugging (not visible to client users)             │   │    │
│  │  └──────────────────────────────────────────────────────────────┘   │    │
│  │                                                                      │    │
│  └──────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│  ┌─── SCHEDULE STATUS ─────────────────────────────────────────────────┐    │
│  │                                                                      │    │
│  │  ☑  Enabled                                                         │    │
│  │                                                                      │    │
│  └──────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│                                          [ Cancel ]  [ Save Schedule ]       │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Field Specifications

### Notification Timing Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `notify_on_success` | Checkbox | `false` | Send notification when agent completes all targets successfully |
| `notify_on_failure` | Checkbox | `true` | Send notification when agent fails after all retries exhausted |
| `notify_on_partial_success` | Checkbox | `true` | Send notification when some targets succeed and some fail |

### Recipient Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `notification_user_ids` | Multi-select | `[]` | Array of User IDs to receive notifications |
| `notify_caphive_on_error` | Checkbox | `true` | Send technical error details to Caphive internal team |

---

## User Dropdown Options

The "Notification Recipients" dropdown should show users who have access to the entity. Filter options:

1. **All Entity Employees** - Users with employee role for this entity
2. **Entity Admins** - Users with admin privileges
3. **Individual Selection** - Pick specific users from the list

### Dropdown Display Format

```
┌─────────────────────────────────────────────────────────┐
│  Search users...                                        │
├─────────────────────────────────────────────────────────┤
│  ☐  John Smith          john.smith@acme.com     Admin   │
│  ☐  Jane Doe            jane.doe@acme.com       Admin   │
│  ☐  Bob Wilson          bob.wilson@acme.com     Employee│
│  ☐  Alice Brown         alice.brown@acme.com    Employee│
└─────────────────────────────────────────────────────────┘
```

---

## Notification Content by Outcome

### What Recipients Receive

| Outcome | Client Email Content | Client In-App | Caphive Internal |
|---------|---------------------|---------------|------------------|
| **Success** | Agent name, completion time, summary (X targets processed) | Brief success message | None |
| **Partial Success** | Agent name, summary (X succeeded, Y failed), generic error note | Warning message | Full error details per target |
| **Failure** | Agent name, sanitized error message, "team has been notified" | Error message | Full error + stacktrace + context |
| **Internal Error** | None (never exposed to client) | None | Critical alert with full technical details |

### Example Email Content

**Success Email:**
```
Subject: [Agent Success] Cash Flow Assistant completed

The scheduled agent "Cash Flow Assistant" has completed successfully.

Summary:
- Targets processed: 15
- Completed at: 2024-01-15 09:05:00 IST

Entity: Acme Investments
Schedule: Daily at 09:00
```

**Failure Email (Client):**
```
Subject: [Agent Failed] Cash Flow Assistant requires attention

The scheduled agent "Cash Flow Assistant" has failed to complete.

We encountered an issue while processing. Our technical team has been
notified and is investigating.

Failed at: 2024-01-15 09:05:00 IST
Attempts: 3 of 3

Entity: Acme Investments

If you have questions, please contact support.
```

**Failure Email (Caphive Internal):**
```
Subject: [AGENT ERROR] Cash Flow Assistant - Acme Investments

Agent Execution Failed
======================
Agent: Cash Flow Assistant
Entity: Acme Investments (ID: 123)
Schedule ID: 456
Execution Log ID: 789

Error Details:
--------------
Message: Connection timeout to OpenAI API
Attempts: 3 of 3

Stacktrace:
-----------
/app/services/cash_flow_agent.rb:45:in `call_openai`
/app/services/cash_flow_agent.rb:23:in `process_target`
...

Context:
--------
- Trigger: Scheduled
- Started at: 2024-01-15 09:00:00
- Failed at: 2024-01-15 09:05:00
- Targets attempted: 15
- Targets failed: 15
```

---

## Database Schema Changes

### Migration

```ruby
class AddNotificationFieldsToAgentSchedules < ActiveRecord::Migration[7.0]
  def change
    # Notification timing toggles
    add_column :agent_schedules, :notify_on_success, :boolean, default: false, null: false
    add_column :agent_schedules, :notify_on_partial_success, :boolean, default: true, null: false

    # Rename existing field for clarity (optional)
    # rename_column :agent_schedules, :failure_notification_user_ids, :notification_user_ids

    # Internal notification toggle
    add_column :agent_schedules, :notify_caphive_on_error, :boolean, default: true, null: false
  end
end
```

### Updated AgentSchedule Model

```ruby
class AgentSchedule < ApplicationRecord
  # Existing fields...

  # Notification settings
  attribute :notify_on_success, :boolean, default: false
  attribute :notify_on_failure, :boolean, default: true  # Already exists
  attribute :notify_on_partial_success, :boolean, default: true
  attribute :failure_notification_user_ids, default: -> { [] }  # Already exists
  attribute :notify_caphive_on_error, :boolean, default: true

  # Helper method
  def notification_users
    User.where(id: failure_notification_user_ids)
  end
end
```

---

## UI Behavior Rules

### Conditional Display

1. **Show "Run on Day"** only when frequency is weekly, monthly, bimonthly, quarterly, or half_yearly
2. **Disable "Notification Recipients"** if all three notify checkboxes are unchecked
3. **Show warning** if notifications are enabled but no recipients selected

### Validation Rules

1. If any `notify_on_*` is checked, at least one recipient should be selected (warning, not blocking)
2. `notification_user_ids` must contain valid user IDs belonging to the entity

### Default Values for New Schedules

| Field | Default |
|-------|---------|
| `notify_on_success` | `false` |
| `notify_on_failure` | `true` |
| `notify_on_partial_success` | `true` |
| `notification_user_ids` | `[current_user.id]` (creator) |
| `notify_caphive_on_error` | `true` |

---

## User Flow

### Creating a New Schedule with Notifications

```
1. User navigates to Agent → Schedule tab
                │
                ▼
2. User clicks "Create Schedule" or "Edit"
                │
                ▼
3. User fills schedule timing (frequency, time, timezone)
                │
                ▼
4. User configures retry settings
                │
                ▼
5. User expands/views "Notification Settings" section
                │
                ▼
6. User checks desired notification triggers:
   • ☐ On Success
   • ☑ On Failure
   • ☑ On Partial Success
                │
                ▼
7. User selects notification recipients from dropdown
   (filtered to entity users)
                │
                ▼
8. User optionally unchecks "Send to Caphive" if desired
                │
                ▼
9. User clicks "Save Schedule"
                │
                ▼
10. System validates and saves schedule
                │
                ▼
11. Notifications will be sent based on configuration
    when the agent runs
```

---

## Component Structure (Vue/React)

```
AgentScheduleForm
├── ScheduleSettingsSection
│   ├── FrequencySelect
│   ├── TimeInput
│   ├── TimezoneSelect
│   └── RunOnDaySelect (conditional)
│
├── RetrySettingsSection
│   ├── RetryCountInput
│   └── RetryIntervalInput
│
├── NotificationSettingsSection      ← NEW
│   ├── NotificationTriggersGroup
│   │   ├── Checkbox (notify_on_success)
│   │   ├── Checkbox (notify_on_failure)
│   │   └── Checkbox (notify_on_partial_success)
│   │
│   ├── NotificationRecipientsSelect
│   │   └── MultiSelect (users)
│   │
│   └── InternalNotificationToggle
│       └── Checkbox (notify_caphive_on_error)
│
└── FormActions
    ├── CancelButton
    └── SaveButton
```

---

## API Payload

### Create/Update AgentSchedule Request

```json
{
  "agent_schedule": {
    "support_agent_id": 1,
    "entity_id": 123,
    "frequency": "daily",
    "run_at_time": "09:00",
    "timezone": "Asia/Kolkata",
    "run_on_day": null,
    "retry_count": 3,
    "retry_interval_minutes": 5,
    "enabled": true,

    "notify_on_success": false,
    "notify_on_failure": true,
    "notify_on_partial_success": true,
    "failure_notification_user_ids": [1, 2, 3],
    "notify_caphive_on_error": true
  }
}
```

### Response

```json
{
  "id": 456,
  "support_agent_id": 1,
  "entity_id": 123,
  "frequency": "daily",
  "run_at_time": "09:00",
  "timezone": "Asia/Kolkata",
  "next_run_at": "2024-01-16T09:00:00+05:30",
  "enabled": true,

  "notify_on_success": false,
  "notify_on_failure": true,
  "notify_on_partial_success": true,
  "failure_notification_user_ids": [1, 2, 3],
  "notify_caphive_on_error": true,

  "notification_users": [
    { "id": 1, "name": "John Smith", "email": "john.smith@acme.com" },
    { "id": 2, "name": "Jane Doe", "email": "jane.doe@acme.com" },
    { "id": 3, "name": "Bob Wilson", "email": "bob.wilson@acme.com" }
  ]
}
```

---

## Future Enhancements (Out of Scope)

1. **Per-outcome recipient configuration** - Different users for success vs failure
2. **Channel selection** - Choose email, in-app, or WhatsApp per user
3. **Notification templates** - Customizable email templates per agent
4. **Digest notifications** - Combine multiple agent results into single email
5. **Escalation rules** - Auto-escalate to different users after repeated failures

---

## Implementation Checklist

- [ ] Add database migration for new fields
- [ ] Update AgentSchedule model with new attributes
- [ ] Update AgentSchedule serializer to include new fields
- [ ] Update AgentSchedule controller strong params
- [ ] Create NotificationSettingsSection component
- [ ] Add user multi-select dropdown with entity user filtering
- [ ] Update form validation
- [ ] Write tests for new notification configuration
- [ ] Update API documentation
