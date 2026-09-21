# Support Agent UI - Design Specification

**Generic Real-time Progress Panel for All Trailblazer-based Support Agents**

Version 1.0 | January 2026

---

## Contents

1. [Overview & Goals](#1-overview--goals)
2. [Design Decisions](#2-design-decisions)
3. [Technical Architecture](#3-technical-architecture)
4. [Data Flow](#4-data-flow)
5. [Step States & Timing](#5-step-states--timing)
6. [Data Structure](#6-data-structure)
7. [UI Mockups](#7-ui-mockups)
8. [API Endpoints](#8-api-endpoints)
9. [Permissions](#9-permissions)
10. [Files to Create/Modify](#10-files-to-createmodify)
11. [Implementation Order](#11-implementation-order)

---

## 1. Overview & Goals

### What is this?

A **generic, reusable UI component** that displays real-time progress for any Trailblazer-based support agent. The component dynamically fetches step definitions from the agent class at runtime and broadcasts progress updates via Turbo Streams.

### Goals

- Single UI component works for ALL support agents
- Steps are introspected from Trailblazer at runtime (no duplication)
- Real-time updates via Turbo Streams (existing infrastructure)
- Click-to-expand step details
- Support for concurrent agent runs
- Backward compatible with existing agents

### Agents Covered

| Agent | Page Location | Target Model |
| :--- | :--- | :--- |
| KycOnboardingAgent | `/investor_kycs/:id` | InvestorKyc |
| PortfolioCompanyAgent | `/investors/:id` | Investor |
| CallNoticeAgent | `/capital_calls/:id` | CapitalCall |
| FundStatsAgent | `/entities/:id/fund_stats` | Entity |
| PortfolioReportAgent | `/ai_report_sections/:id` | AiReportSection |

---

## 2. Design Decisions

> **Decision 1: Step Introspection**
> **Approach:** Fetch steps from Trailblazer at runtime using `Trailblazer::Activity::Introspect.Nodes()`
> **Rationale:** Single source of truth, no duplication, works with existing agents automatically

> **Decision 2: Skipped Steps**
> **Approach:** Show skipped steps as gray with "Skipped" label
> **Rationale:** Provides visibility into what was checked vs what was bypassed

> **Decision 3: Step Timing**
> **Approach:** Show duration per step (e.g., "1.2s")
> **Rationale:** Helps identify slow steps, useful for debugging and optimization

> **Decision 4: History**
> **Approach:** No history view (show only latest run)
> **Rationale:** Simplifies UI, can be added later if needed

> **Decision 5: Cancellation**
> **Approach:** Manual "Cancel" button during running state
> **Rationale:** User control for long-running jobs or stuck processes

> **Decision 6: Permissions**
> **Approach:** Role-based access control for run/cancel actions
> **Rationale:** Prevents unauthorized execution, maintains audit trail

> **Decision 7: Real-time Updates**
> **Approach:** Turbo Streams (existing infrastructure)
> **Rationale:** Already configured, consistent with UserAlert pattern

> **Decision 8: Step Details**
> **Approach:** Click-to-expand inline (not modal)
> **Rationale:** Quick access without context switch

---

## 3. Technical Architecture

### Component Overview

| Component | Location | Responsibility |
| :--- | :--- | :--- |
| `SupportAgentService.step_definitions` | Base class | Returns steps from Trailblazer at runtime |
| `SupportAgentService#broadcast_step` | Base class | Broadcasts step progress via Turbo |
| `SupportAgentReport` | Model | Stores steps array in json_fields |
| `_progress_panel.html.erb` | Partial | Generic UI for any agent |
| `support_agent_progress_controller.js` | Stimulus | Handles click interactions |

### Step Introspection Code

```ruby
# In SupportAgentService base class
def self.step_definitions
  nodes = Trailblazer::Activity::Introspect.Nodes(self)
  steps = nodes.values
    .map { |attrs| attrs.id }
    .reject { |id| id.to_s.start_with?("Start.", "End.") }

  steps.map.with_index(1) do |step_id, index|
    {
      step: index,
      id: step_id,
      label: step_label(step_id),
      short_label: short_label(step_id)
    }
  end
end

# Default: humanize the step name
def self.step_label(step_id)
  step_id.to_s.humanize
end

def self.short_label(step_id)
  step_id.to_s.humanize.truncate(12, omission: '')
end
```

### Optional Label Override (per agent)

```ruby
# In CallNoticeAgent (optional customization)
STEP_LABELS = {
  verify_investor_kyc: "KYC Pre-Check",
  check_documents_generated: "Documents Generated",
  check_documents_approved: "Documents Approved",
  check_notification_configured: "Notification Configured",
  mark_ready_to_send: "Ready to Send"
}.freeze

def self.step_label(step_id)
  STEP_LABELS[step_id] || super
end
```

---

## 4. Data Flow

```text
+---------------------------------------------------------------------+
|                           USER CLICKS                                |
|                        "Run Agent" Button                            |
+---------------------------------------------------------------------+
                                   |
                                   v
+---------------------------------------------------------------------+
|                         CONTROLLER                                   |
|  POST /support_agents/:id/run                                        |
|  -> Creates SupportAgentReport (status: running)                     |
|  -> Enqueues SupportAgentJob                                         |
|  -> Returns report_id                                                |
+---------------------------------------------------------------------+
                                   |
                                   v
+---------------------------------------------------------------------+
|                      BACKGROUND JOB                                  |
|  SupportAgentJob                                                     |
|  -> For each step:                                                   |
|     -> Check if cancelled                                            |
|     -> Broadcast { step: N, status: 'running' }                      |
|     -> Execute step logic                                            |
|     -> Broadcast { step: N, status: 'success'|'failed', ... }        |
|  -> Broadcast final status                                           |
+---------------------------------------------------------------------+
                                   |
                                   v
+---------------------------------------------------------------------+
|                      TURBO BROADCAST                                 |
|  Stream: "support_agent_report_#{report.id}"                         |
|  Actions: replace step_circle, progress_bar, status_badge            |
+---------------------------------------------------------------------+
                                   |
                                   v
+---------------------------------------------------------------------+
|                      BROWSER (Auto-updated)                          |
|  Turbo Stream receives broadcast                                     |
|  -> Replaces DOM elements automatically                              |
|  -> No custom JS needed for updates                                  |
+---------------------------------------------------------------------+
```

### Broadcast Pattern

```ruby
# In SupportAgentService
def broadcast_step(report, step_id, status:, message: nil, count: nil, failed_records: nil)
  step_data = report.json_fields["steps"].find { |s| s["id"] == step_id.to_s }
  return unless step_data

  step_data["status"] = status.to_s
  step_data["message"] = message if message
  step_data["count"] = count if count
  step_data["failed_records"] = failed_records if failed_records

  if status.to_s.in?(%w[success failed skipped])
    step_data["completed_at"] = Time.current.iso8601
    step_data["duration_ms"] = calculate_duration(step_data)
  end

  report.save!

  Turbo::StreamsChannel.broadcast_replace_to(
    "support_agent_report_#{report.id}",
    target: "step_#{step_data['step']}",
    partial: "support_agents/step_circle",
    locals: { step: step_data }
  )
end
```

---

## 5. Step States & Timing

### Step States

| State | Circle | Color | Label Example |
| :--- | :---: | :--- | :--- |
| `pending` | ○ | Gray | Waiting... |
| `running` | ↻ | Blue | Checking... |
| `success` | ✓ | Green | 12/12 verified |
| `failed` | ✗ | Red | 3 failed |
| `skipped` | — | Gray | Skipped |

---

## 6. Data Structure

### SupportAgentReport.json_fields

```json
{
  "steps": [
    {
      "step": 1,
      "id": "verify_investor_kyc",
      "label": "KYC Pre-Check",
      "status": "success",
      "message": "All 12 investors verified",
      "count": { "passed": 12, "total": 12 },
      "started_at": "2026-01-14T10:00:01.000Z",
      "completed_at": "2026-01-14T10:00:03.500Z",
      "duration_ms": 2500
    },
    {
      "step": 2,
      "id": "check_documents_generated",
      "label": "Documents Generated",
      "status": "skipped",
      "message": "Document validation disabled",
      "skipped_reason": "validate_documents = false"
    },
    {
      "step": 3,
      "id": "check_documents_approved",
      "label": "Documents Approved",
      "status": "failed",
      "message": "3 documents pending approval",
      "count": { "passed": 9, "total": 12 },
      "failed_records": [
        { "id": 101, "name": "Investor A", "reason": "Pending", "link": "/documents/101" },
        { "id": 102, "name": "Investor B", "reason": "Pending", "link": "/documents/102" },
        { "id": 103, "name": "Investor C", "reason": "Pending", "link": "/documents/103" }
      ],
      "started_at": "2026-01-14T10:00:03.500Z",
      "completed_at": "2026-01-14T10:00:04.200Z",
      "duration_ms": 700
    },
    {
      "step": 4,
      "id": "check_notification_configured",
      "label": "Notification Configured",
      "status": "pending"
    },
    {
      "step": 5,
      "id": "mark_ready_to_send",
      "label": "Ready to Send",
      "status": "pending"
    }
  ],
  "final_status": "blocked",
  "failed_step": 3,
  "triggered_by": "manual",
  "triggered_by_user_id": 123,
  "run_at": "2026-01-14T10:00:00Z",
  "completed_at": "2026-01-14T10:00:04.200Z",
  "total_duration_ms": 4200,
  "cancelled_at": null,
  "cancelled_by_user_id": null
}
```

### Model Helper Methods

```ruby
# In SupportAgentReport
def steps
  json_fields["steps"] || []
end

def current_step
  steps.find { |s| s["status"] == "running" }
end

def failed_step
  steps.find { |s| s["status"] == "failed" }
end

def progress_percentage
  return 0 if steps.empty?
  completed = steps.count { |s| s["status"].in?(%w[success failed skipped]) }
  (completed.to_f / steps.size * 100).round
end

def total_duration
  json_fields["total_duration_ms"]&.then { |ms| "#{(ms / 1000.0).round(1)}s" }
end

def running?
  json_fields["final_status"] == "running"
end

def ready?
  json_fields["final_status"] == "ready"
end

def blocked?
  json_fields["final_status"] == "blocked"
end

def cancelled?
  json_fields["cancelled_at"].present?
end
```

---

## 7. UI Mockups

### Initial State (Never Run)

```text
+---------------------------------------------------------------------+
|  KYC Onboarding Check                                               |
|  Validates investor KYC completeness                                |
|                                                         [Run Agent] |
+---------------------------------------------------------------------+
```

### Running State

```text
+---------------------------------------------------------------------+
|  KYC Onboarding Check                              [Running]        |
|  Validates investor KYC completeness                    [Cancel]    |
+---------------------------------------------------------------------+
|  2 of 5 steps completed                                             |
|  [========------------] 40%                                         |
|                                                                     |
|    (ok)       (ok)       (~~)       ( )        ( )                  |
|   Fields     Docs      Validity   Consist.    Report                |
|   1.2s       0.8s      Running    Pending     Pending               |
+---------------------------------------------------------------------+
```

### Completed - All Passed

```text
+---------------------------------------------------------------------+
|  KYC Onboarding Check                              [Ready]          |
|  Validates investor KYC completeness               [Run Again]      |
+---------------------------------------------------------------------+
|  5 of 5 steps completed - Run at 10:30 AM - Total: 4.8s             |
|  [====================] 100%                                        |
|                                                                     |
|    (ok)       (ok)       (ok)       (ok)       (ok)                 |
|   Fields     Docs      Validity   Consist.    Report                |
|   1.2s       0.8s       2.1s       0.5s        0.2s                 |
+---------------------------------------------------------------------+
```

### Completed - With Failure (Collapsed)

```text
+---------------------------------------------------------------------+
|  KYC Onboarding Check                              [Blocked]        |
|  Validates investor KYC completeness               [Run Again]      |
+---------------------------------------------------------------------+
|  3 of 5 steps completed - Run at 10:30 AM                           |
|  [==============------] 60%                                         |
|                                                                     |
|    (ok)       (--)       (ok)       (X)        ( )                  |
|   Fields     Docs      Validity   Consist.    Report                |
|   1.2s      Skipped     2.1s       0.5s       Pending               |
+---------------------------------------------------------------------+
```

---

## 8. API Endpoints

### POST /support_agents/:id/run

Triggers the support agent for a specific target.

#### Request

```http
POST /support_agents/42/run
Content-Type: application/json

{
  "target_type": "CapitalCall",
  "target_id": 123
}
```

#### Response (Success - 202 Accepted)

```json
{
  "status": "started",
  "report_id": 456,
  "stream": "support_agent_report_456",
  "steps": [
    { "step": 1, "id": "verify_investor_kyc", "label": "KYC Pre-Check", "status": "pending" },
    { "step": 2, "id": "check_documents_generated", "label": "Documents Generated", "status": "pending" },
    ...
  ]
}
```

---

## 9. Permissions

### Permission Matrix

| Role | Can Run | Can Cancel |
| :--- | :--- | :--- |
| Admin | All agents | All agents |
| Ops Manager | All agents | Own runs only |
| Ops User | Assigned agents | Own runs only |
| Viewer | None | None |

---

## 10. Files to Create/Modify

### New Files

| File | Purpose |
| :--- | :--- |
| `app/views/support_agents/_progress_panel.html.erb` | Main UI container partial |
| `app/views/support_agents/_step_circle.html.erb` | Individual step circle partial |
| `app/views/support_agents/_step_details.html.erb` | Expanded step details partial |
| `app/views/support_agents/_progress_bar.html.erb` | Progress bar partial |
| `app/views/support_agents/_status_badge.html.erb` | Status badge partial |
| `app/javascript/controllers/support_agent_progress_controller.js` | Stimulus controller for click interactions |

---

## 11. Implementation Order

1. **Backend Base**
   - Modify `SupportAgentService` with `step_definitions` class method
   - Add `broadcast_step` helper method
   - Add `cancelled?` check method
   - Add `initialize_report_with_steps` method

2. **Model Helpers**
   - Update `SupportAgentReport` with new json structure helpers
   - Add `steps`, `progress_percentage`, `duration` methods
   - Add status enum for `:running`, `:cancelled`

3. **Routes + Controller**
   - Add `run`, `cancel`, `status` endpoints
   - Add permission checks

4. **Partials**
   - Create `_progress_panel.html.erb`
   - Create `_step_circle.html.erb`
   - Create `_step_details.html.erb`
   - Create `_progress_bar.html.erb`
   - Create `_status_badge.html.erb`

5. **Stimulus Controller**
   - Create `support_agent_progress_controller.js`
   - Handle click-to-expand
   - Handle run/cancel button actions

6. **Pilot Agent**
   - Migrate `KycOnboardingAgent` as first implementation
   - Add broadcast calls to each step
   - Embed partial in investor_kyc show page
   - Test end-to-end

7. **Migrate Remaining Agents**
   - PortfolioCompanyAgent
   - CallNoticeAgent (new)
   - FundStatsAgent
   - PortfolioReportAgent

---

Support Agent UI Design Specification | Generated January 2026
