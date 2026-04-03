# Feature Specification: Tasks for Deal Steps (Multi-Task CSV)

## 1. Overview
Automate the creation of multiple tasks for a `DealInvestor` by parsing a CSV-formatted list stored directly within `DealActivity` templates.

## 2. Technical Architecture

### 2.1 Data Model Adjustments
*   **DealActivity Enhancement**:
    *   Add `tasks_csv` (Text) to the `deal_activities` table.
    *   This field stores a list of tasks. Each task is separated by a newline or comma.

### 2.2 Logic & Workflow
*   **Trigger Point**: `PerformActivityAction` (step transition).
*   **Multi-Task Generation Logic**:
    1.  Upon transition, the system reads the `tasks_csv` from the new `DealActivity`.
    2.  It splits the string into an array of task titles using `,` and `\n` as delimiters.
    3.  For each unique title in the array:
        *   Checks if a task with that title already exists for the `DealInvestor`.
        *   If not, creates a new `Task` record.
        *   **Owner**: The `DealInvestor`.
        *   **Assigned To**: The `current_user` who performed the step transition.
*   **Template Sync**:
    *   Update `DealInvestor#create_activities` to copy the `tasks_csv` content from the deal template to the investor-specific activity records.

## 3. UI/UX Enhancements

### 3.1 Activity Management
*   Update the `DealActivity` edit form to include a `Tasks (one per line or comma-separated)` text area.

### 3.2 Visibility
*   **Deal Details View**: Add a "Tasks" tab showing all open and completed tasks for the deal's investors.
*   **Global Dashboard**: Filterable view for `owner_type: 'DealInvestor'` in the main Tasks dashboard.

## 4. Implementation Steps
1.  **Migration**: Add `tasks_csv` to `deal_activities`.
2.  **Job Implementation**: Create `GenerateDealStepTasksJob` with multi-task parsing logic.
3.  **Service Hook**: Enqueue the job in `PerformActivityAction`.
4.  **View Updates**: Modify Deal and Activity forms/tabs.
