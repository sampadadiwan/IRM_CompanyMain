# Recurring Tasks Specification

This document outlines the design and implementation strategy for recurring tasks within the IRM system, following principles similar to Outlook calendar events.

## 1. User Interface (UI)

The UI for creating and managing recurring tasks should be intuitive and provide flexible scheduling options.

### A. Task Creation/Edit Form
- **Core Fields:** Standard task fields (Title, Description, Due Date, etc.) are always visible.
- **Advanced Options Toggle:** A button or link to "Show Advanced Options" (hidden by default).
- **Recurrence Controls (Within Advanced Options):**
    - **Recurrence Toggle:** A checkbox or switch to "Make Recurring".
    - **Recurrence Pattern Selection:**
        - **Daily:** Every [X] day(s).
    - **Weekly:** Every [X] week(s) on [Specific Days of the Week].
    - **Monthly:**
        - Day [X] of every [Y] month(s).
        - The [First/Second/Third/Fourth/Last] [Day of Week] of every [Y] month(s).
    - **Yearly:**
        - Every [Month] [Day].
        - The [First/Second/Third/Fourth/Last] [Day of Week] of [Month].
- **Range of Recurrence:**
    - **Start Date:** When the recurrence begins.
    - **End Date Options:**
        - No end date (Ongoing).
        - End after [X] occurrences.
        - End by [Specific Date].

### B. Task List/Calendar View
- **Recurring Indicator:** An icon (e.g., circular arrows) next to tasks that are part of a series.
- **Occurrence Identification:** Visually differentiate between the "Master" template and individual "Occurrences".

### C. Update/Delete Interaction
- When a user attempts to edit or delete a recurring task, a modal prompt appears:
    - **"Just this occurrence"**: Apply changes only to the selected instance.
    - **"This and following occurrences"**: Apply changes to the selected instance and all future ones in the series.
    - **"The entire series"**: Apply changes to all instances, past and future (with caution for completed tasks).

---

## 2. Database Schema

The implementation utilizes a "Master" and "Instance" relationship to balance flexibility with performance.

### A. `task_recurrence_rules` (The "Master" Template)
Stores the logic for generating instances.
- `id`: Primary Key.
- `entity_id`: For multi-tenancy.
- `task_template_payload`: JSONB field storing common task attributes (title, description, priority, assigned_to_id, etc.).
- `rrule`: String (iCal RFC 5545 format) or structured JSON storing the recurrence logic (Frequency, Interval, ByDay, ByMonthDay, etc.).
- `start_date`: DateTime.
- `end_date`: DateTime (optional).
- `max_occurrences`: Integer (optional).
- `generated_until`: DateTime (keeps track of how far into the future instances have been created).

### B. `tasks` (The "Instance" Table)
Stores individual occurrences.
- `id`: Primary Key.
- `task_recurrence_rule_id`: Foreign Key to the master rule (null for non-recurring tasks).
- `original_start_date`: DateTime (The date/time this instance was *supposed* to occur according to the rule; used to track "exceptions").
- `is_exception`: Boolean (True if this instance has been modified independently of the master rule).
- `status`: String (pending, completed, etc.).
- `...standard task fields`: title, description, due_date, etc.

---

## 3. Recurring Task Generation Job

To avoid database bloat while ensuring tasks are visible ahead of time, a background job handles proactive generation.

### A. The "Quarterly Generator" Job
- **Trigger:** Runs monthly or quarterly via Sidekiq Cron.
- **Logic:**
    1. Query all `task_recurrence_rules` where `end_date` is null or in the future.
    2. For each rule:
        - Determine the "Horizon Date" (e.g., end of the next quarter).
        - Calculate next occurrence dates between `generated_until` and "Horizon Date" using the `rrule`.
        - For each calculated date:
            - Check if an instance already exists for this `task_recurrence_rule_id` and `original_start_date`.
            - If not, create a new `tasks` record using the `task_template_payload`.
        - Update `generated_until` to the "Horizon Date".

---

## 4. Handling Changes and Exceptions

The core challenge is managing the link between the master rule and generated instances.

### A. Editing "Just This Occurrence"
- The specific `tasks` record is updated.
- `is_exception` is set to `true`.
- Any future updates to the `task_recurrence_rule`'s template will *not* overwrite this specific instance's modified fields.

### B. Editing "This and Following Occurrences"
- **Split the Series:**
    1. Update the current `task_recurrence_rule`'s `end_date` to the day before the current instance.
    2. Create a *new* `task_recurrence_rule` starting from today with the updated attributes.
    3. Update all existing future `tasks` (that aren't already exceptions) to point to the new rule or recreate them.

### C. Editing "The Entire Series"
- Update the `task_template_payload` in the `task_recurrence_rule`.
- Propagate changes to all existing `tasks` instances linked to this rule where `is_exception` is `false`.

### D. Deleting
- **Just this:** Soft delete the specific `tasks` record.
- **Series:** Soft delete the `task_recurrence_rule` and all associated `tasks` instances.

---

## 5. Current Implementation Status (as of Feb 2026)

The actual codebase implements the core architecture (Master/Instance schema and Background Generation) but has a simplified UI/Controller logic compared to the proposed specification above.

### A. Edit Implementation
- **Mechanism:** Editing a recurring task currently updates BOTH the individual `Task` instance AND the `TaskRecurrenceRule`'s template payload simultaneously.
- **Scope:** There is no modal choice for "Just this" vs "Series". All edits to core fields propagate to the master template (affecting future generated tasks) and update the current instance.
- **Detaching:** Unchecking "Make Recurring" on an existing task sets `task_recurrence_rule_id` to `nil` and marks `is_exception` as `true`, effectively isolating that task from the series.

### B. Delete Implementation
- **Scope:** Deletion is strictly "Just this occurrence". Calling `destroy` on a task only removes that specific instance.
- **Series Deletion:** Added a `destroy_series` action and "Delete Series" button on the task show page. This removes the `TaskRecurrenceRule` and all associated tasks.

### C. Notification Behavior
- **Recurring Tasks:** To avoid spamming users for automatically generated tasks, notifications are **disabled** for any task linked to a `TaskRecurrenceRule`.

### D. Key Deviations from Spec
- **No Modal Prompts:** The complex selection logic (Just this / Following / Series) is not yet implemented in the frontend or controller.
- **Simplified Exception Tracking:** `is_exception` is primarily used for detaching tasks rather than tracking field-level overrides.
