# Investor Relations (IR) Data Models

## 1. Investor (LP Profile)
**Table Name:** `investors`
**Purpose:** The central repository for an LP's profile, tracking the overall relationship, communication history, and access analytics.

**Key IR Fields:**
- `investor_name` (string): Legal/display name of the LP.
- `category` (string): Segment (e.g., "UHNW", "Institutional", "Family Office").
- `tag_list` (string): Arbitrary labels for grouping (e.g., "Tier 1", "Real Estate Focused").
- `last_interaction_date` (date): Automatically updated when a `Note` is saved.
- `investor_access_count` (integer): Engagement metric showing how often they log in.
- `primary_email` (string): Main contact for distribution and notifications.

**Key IR Relationships:**
- **Has Many Notes (`notes`):** Log of meetings, calls, and internal remarks.
- **Has Many Tasks (`tasks`):** To-do items for the IR team or the LP.
- **Has Many Capital Commitments (`capital_commitments`):** Financial exposure across various funds.
- **Has Many Investor Accesses (`investor_accesses`):** Links to individual `User` accounts (LPs, their assistants, or advisors).

---

## 2. Note (Interaction Log)
**Table Name:** `notes`
**Purpose:** Captures qualitative data from interactions. Crucial for maintaining institutional memory and ensuring personal follow-ups.

**Key Fields:**
- `details` (rich text): The body of the note (meetings, calls, etc.).
- `tags` (string): categorization (e.g., "Quarterly Review", "Complaint", "Prospecting").
- `created_at` (datetime): Used to update the investor's `last_interaction_date`.

**Key IR Workflow:**
- **Reminders:** Notes can have an associated `Reminder` to prompt a follow-up action at a specific date.
- **Multi-tenancy:** Notes belong to a specific `entity` (the GP) and are linked to a specific `investor` (the LP).

---

## 3. Task (Action Items)
**Table Name:** `tasks`
**Purpose:** Manages specific deliverables, requests, or internal workflow steps.

**Key Fields:**
- `details` (rich text): Description of the task.
- `due_date` (date): The deadline for the task.
- `completed` (boolean): Completion status.
- `category` (string): Grouping (e.g., "IR", "Finance", "Compliance").
- `assigned_to_id` (integer): The team member responsible for the task.
- `owner` (polymorphic): Tasks can be attached directly to an `Investor`, `Fund`, or `Deal`.

**Key IR Workflow:**
- **Notifications:** Assigned users receive notifications upon creation or update.
- **LPs as Users:** If an LP logs a task (e.g., "Request for Statement"), the IR team sees it in their dashboard.

---

## 4. Capital Commitment (Financial Context)
**Table Name:** `capital_commitments`
**Purpose:** Provides the quantitative context for the relationship. IR teams use this to understand an LP's importance and financial standing.

**Key Fields:**
- `folio_id` (string): Unique identifier for the LP's holding in a specific fund.
- `committed_amount_cents` (decimal): Total capital the LP has agreed to provide.
- `call_amount_cents` (decimal): Amount that has been requested from the LP.
- `collected_amount_cents` (decimal): Actual capital paid in by the LP.
- `distribution_amount_cents` (decimal): Total capital returned to the LP.
- `percentage` (decimal): The LP's ownership share in the fund.

**Relationships:**
- **Belongs to Fund (`fund_id`):** The specific fund vehicle.
- **Belongs to InvestorKyc (`investor_kyc_id`):** Links the commitment to the verified legal entity.

---

## 5. Sample IR Agent Queries for LP Satisfaction

### Retrieve & Monitor Queries
1. Which "Tier 1" investors haven't had an interaction (Note) in the last 90 days?
2. List all incomplete tasks assigned to the IR team that are past their due date.
3. Show the latest note and current capital commitment summary for [Investor Name].
4. Find all tasks created by [Investor Name] (LP) that are still "incomplete".
5. Which LPs have the highest `investor_access_count` this month?

### Analysis & Sentiment Queries
6. Summarize the notes for [Investor Name] from the last three months to identify recurring concerns.
7. What is the total committed capital across all funds for LPs tagged as "Family Office"?
8. Identify LPs who have multiple incomplete tasks and no recent notes (High churn/dissatisfaction risk).
9. Compare the `call_amount` vs `collected_amount` for [Investor Name] to check for payment delays.

### Action & Follow-up Queries
10. Create a follow-up task for [Assigned User] based on the reminder in the latest note for [Investor Name].
11. Generate a summary of all "IR" category tasks completed in the last 30 days.
12. Notify the IR head if [Investor Name] logs a new task with "Urgent" in the details.
13. Draft a check-in email for LPs who have had no interaction since their last `capital_call`.
