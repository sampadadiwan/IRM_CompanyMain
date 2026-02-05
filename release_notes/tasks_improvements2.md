# PR Note: Recurring Tasks and Category Filtering Improvements

## Overview
This PR introduces a robust recurring task generation system and enhances task organization through category-based filtering and dashboard statistics.

## Motivation
Previously, tasks in the IRM system were one-off entities. Users needed a way to automate repetitive tasks (e.g., quarterly reporting, monthly follow-ups). Additionally, as task volume increases, better organization via categories and high-level dashboard metrics became necessary for efficient task management.

## What Changed
- **Recurring Tasks Core:**
    - Created `TaskRecurrenceRule` model to store recurrence patterns (using RRule format).
    - Added `GenerateRecurringTasksJob` to automatically instantiate tasks based on active rules.
    - Updated `TasksController` to handle creating and updating recurrence rules alongside task creation.
- **Frontend Enhancements:**
    - New Stimulus controller `task_recurrence_controller.js` for dynamic UI transitions between simple and recurring task forms.
    - Updated Task forms to include recurrence options (pattern, interval, end date).
    - Enhanced Sidebar with quick links to filtered task categories.
- **Dashboard & Filtering:**
    - Added category-based filtering to the Tasks index.
    - Implemented task statistics cards on the dashboard to show counts by category.
- **Bug Fixes:**
    - Fixed a parameter passing issue in `DocumentDownloadJob`.

## Refactoring / Behavior Changes
- Tasks now support an `original_start_date` to track their intended occurrence in a series, separate from their `due_date`.
- The task creation flow now optionally creates a `TaskRecurrenceRule` which serves as a template for future task instances.

## Testing
- **Cucumber Integration Tests:**
    - `features/core/recurring_task_generation.feature`: Covers rule creation, task generation via background jobs, and handling of existing tasks to prevent duplicates.
    - `features/core/task_category_filtering.feature`: Verifies category filtering on the index page and dashboard stat cards.
- **Manual Testing:** Verified the UI toggle for recurring options and the correct generation of weekly/monthly tasks in a development environment.

## Impact
- **Automation:** Reduces manual effort for repetitive investor relationship management activities.
- **Performance:** Task generation is handled asynchronously via Sidekiq jobs to ensure UI responsiveness.
- **User Experience:** Provides a clearer overview of task distribution across different categories.

## Review Focus
- **Recurrence Logic:** Inspect `app/packs/core/tasks/jobs/generate_recurring_tasks_job.rb` for how it handles time horizons and duplicate prevention.
- **Controller Logic:** Review `TasksController#create` and `#update` for the integration of recurrence rule persistence.
- **UI State:** Check the Stimulus controller for clean handling of the "Advanced Options" toggle.
