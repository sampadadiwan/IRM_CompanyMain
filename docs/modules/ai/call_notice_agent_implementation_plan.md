# Call Notice Support Agent - Implementation Plan

---

## Contents

1. [Overview & Purpose](#1-overview--purpose)
2. [Design Summary](#2-design-summary)
3. [Agent Steps Definition](#3-agent-steps-definition)
4. [UI Design](#4-ui-design)
5. [Technical Architecture](#5-technical-architecture)
6. [Data Models](#6-data-models)
7. [Implementation Plan](#7-implementation-plan)
8. [Files to Create/Modify](#8-files-to-createmodify)
9. [API Contracts](#9-api-contracts)
10. [Testing Plan](#10-testing-plan)

---

## 1. Overview & Purpose

### What is the Call Notice Support Agent?

A **deterministic, step-based support worker** that guides ops users through the capital call workflow. It validates that all prerequisites are met before sending call notices to investors.

### Problem it Solves

- Prevents missed steps in the call notice workflow
- Surfaces blockers early with actionable guidance
- Reduces operational errors and support tickets
- Provides clear visibility into call readiness status

### Agent Type

> **Support Agent** (not AI Assistant)
> - Fixed steps, no free-form reasoning
> - Deterministic execution
> - Run on demand (manual) or on schedule (background job)
> - Stateless - runs all validations every time

### Scope

| In Scope | Out of Scope |
| :--- | :--- |
| - KYC verification checks | - Actual email sending (separate action) |
| - Document generation validation | - Remittance generation (auto on call creation) |
| - Document approval validation | - Document content validation (paid feature - future) |
| - Notification configuration check | |
| - Readiness confirmation | |

---

## 2. Design Summary

### Agent Behavior

- **Stateless validation pipeline** - runs all 5 steps on every invocation
- **Stops at first blocker** - returns actionable message
- **No resume logic** - always validates from step 1 (previous steps could become invalid)
- **Audit trail** - persists each run for history/analytics

### Workflow Overview

```text
1. KYC Verified -> 2. Docs Generated -> 3. Docs Approved -> 4. Notification Configured -> 5. Ready to Send
```

### Key Design Decisions

| Decision | Rationale |
| :--- | :--- |
| Stateless (no resume) | Previous steps can become invalid (e.g., KYC revoked). Must re-validate all steps every run. |
| Use existing SupportAgentReport | Existing model supports status tracking and json_fields for storing step details. |
| ActionCable for live updates | Steps may take time; users need real-time feedback without page refresh. |
| 5 steps (not 7) | Remittances auto-generated; email sending is separate action outside agent scope. |

---

## 3. Agent Steps Definition

| # | Step Name | Validation Logic | Failure Message |
| :--- | :--- | :--- | :--- |
| 1 | **KYC Pre-Check** | All investors linked to the call have `investor_kyc.verified = true` and KYC not expired | "X investors need KYC verification: [list with links]" |
| 2 | **Documents Generated** | Call notice documents exist for all capital remittances | "X investors missing call notice documents: [list]" |
| 3 | **Documents Approved** | All call notice documents have `approved = true` | "X documents pending approval: [list with links]" |
| 4 | **Notification Configured** | CustomNotification exists for the CapitalCall with `enabled = true` | "Email notification not configured for this call" |
| 5 | **Ready to Send** | All previous steps passed | N/A (only fails if previous step failed) |

### Step Success Messages

| Step | Success Message |
| :--- | :--- |
| 1. KYC Pre-Check | "All X investors have verified KYC" |
| 2. Documents Generated | "Call notice documents generated for all X investors" |
| 3. Documents Approved | "All X call notice documents approved" |
| 4. Notification Configured | "Email notification configured and enabled" |
| 5. Ready to Send | "Call is ready to send" |

### Trailblazer Operation Structure

```ruby
class CallNoticeAgent < SupportAgentService
  step :initialize_agent
  step :verify_investor_kyc
  step :check_documents_generated
  step :check_documents_approved
  step :check_notification_configured
  step :mark_ready_to_send
  step :generate_progress_reports

  # Each step:
  # 1. Runs validation
  # 2. Broadcasts progress via ActionCable
  # 3. Records result in ctx[:steps]
  # 4. Returns true/false (false halts pipeline)
end
```

---

## 4. UI Design

### Placement

The Call Notice Agent UI is embedded on the **Capital Call Remittances page** (`/capital_calls/:id`), above the remittances table.

### UI States

- **Initial State:** Button "▶ Run Call Agent"
- **Running State:** Shows progress bar and steps with "Running" status.
- **Completed (Ready):** Shows all steps as successful.
- **Failed (Blocked):** Shows where the pipeline stopped with failure details.

---

## 5. Technical Architecture

### System Flow

```text
┌─────────────────────────────────────────────────────────────────────┐
│                         USER INTERFACE                               │
│  [Run Call Agent Button] → Stimulus Controller                      │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         API ENDPOINT                                 │
│  POST /capital_calls/:id/run_agent                                  │
│  → Creates background job                                           │
│  → Returns job_id for tracking                                      │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                       BACKGROUND JOB                                 │
│  CallNoticeAgentJob                                                 │
│  → Runs CallNoticeAgent operation                                   │
│  → Broadcasts progress via ActionCable                              │
└─────────────────────────────────────────────────────────────────────┘
```

### Technology Stack

| Layer | Technology | Notes |
| :--- | :--- | :--- |
| Backend Framework | Rails 8.1 | Existing stack |
| Operation Pattern | Trailblazer | Existing pattern - extend SupportAgentService |
| Background Jobs | Sidekiq | Already configured |
| Real-time Updates | ActionCable (Redis) | Already configured |
| Frontend | Hotwire (Turbo + Stimulus) | Existing stack - no React/Vue |
| Persistence | SupportAgentReport model | Existing model - reuse for audit trail |

---

## 6. Data Models

### Existing Models Used

| Model | Location | Key Fields/Associations |
| :--- | :--- | :--- |
| `CapitalCall` | `app/packs/funds/capital_calls/models/` | `has_many :capital_remittances`, `has_many :committed_investors` |
| `CapitalRemittance` | `app/packs/funds/capital_remittances/models/` | `belongs_to :capital_call`, `belongs_to :investor`, `has_many :documents` |
| `InvestorKyc` | `app/packs/core/investor_kycs/models/` | `verified` (boolean), `expiry_date` |
| `Document` | `app/packs/core/documents/models/` | `approved` (boolean), polymorphic owner |
| `CustomNotification` | `app/packs/core/notifications/models/` | `enabled` (boolean), polymorphic owner |
| `SupportAgentReport` | `app/packs/ai/support_agents/models/` | polymorphic owner, `json_fields` (JSONB) |

---

## 7. Implementation Plan

### Phase 1: Backend - Agent Operation
- [ ] Create `CallNoticeAgent` class extending `SupportAgentService`
- [ ] Implement validation steps (KYC, Docs Gen, Docs Approved, etc.)
- [ ] Add `CallNoticeAgent` to `SupportAgent::AGENT_TYPES`

### Phase 2: Backend - Job & Channel
- [ ] Create `CallNoticeAgentJob` background job
- [ ] Create `CallNoticeAgentChannel` ActionCable channel
- [ ] Add API endpoints for running agent and checking status

### Phase 3: Frontend - Stimulus Controller
- [ ] Create `call_notice_agent_controller.js`
- [ ] Implement live updates and click-to-expand behavior

### Phase 4: Frontend - View Partial
- [ ] Create `_call_notice_agent.html.erb` partial
- [ ] Embed partial in capital call show page

---

## 8. Files to Create/Modify

### New Files
- `app/packs/ai/support_agents/services/call_notice_agent.rb`
- `app/packs/funds/capital_calls/jobs/call_notice_agent_job.rb`
- `app/channels/call_notice_agent_channel.rb`
- `app/javascript/controllers/call_notice_agent_controller.js`
- `app/views/capital_calls/_call_notice_agent.html.erb`
- `spec/services/call_notice_agent_spec.rb`

### Files to Modify
- `app/packs/ai/support_agents/models/support_agent.rb`
- `config/routes.rb`
- `app/packs/funds/capital_calls/controllers/capital_calls_controller.rb`
- `app/views/capital_calls/show.html.erb`

---

## 9. API Contracts

### POST /capital_calls/:id/run_agent
Triggers the Call Notice Agent. Returns `202 Accepted` with `job_id`.

### GET /capital_calls/:id/agent_status
Returns the latest `SupportAgentReport` for the call.

---

## 10. Testing Plan

### Unit Tests
- Verify each step passes/fails based on mock data.
- Test edge cases like calls with no investors.

### System Tests
- Verify UI updates in real-time when the agent runs.
- Test interaction with the progress panel (expand/collapse).

---

Call Notice Support Agent Implementation Plan Generated January 2026
