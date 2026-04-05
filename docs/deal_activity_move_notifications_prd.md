# PRD: Deal Activity Move Notifications

## 1. Overview
The goal of this feature is to enable automated email notifications when a `DealInvestor` transitions from one `DealActivity` (stage) to another within a Deal. These notifications should be configurable at the `DealActivity` (template) level, allowing admins to specify if internal employees and/or the investor themselves should receive an email when that specific stage is reached.

## 2. Problem Statement
Currently, deal transitions are silent. Internal teams must manually check the status of deals, and investors are not automatically kept in the loop when their deal progresses to a new stage (e.g., from "Term Sheet" to "Due Diligence").

## 3. User Requirements

### 3.1 Configuration
- Admins should be able to toggle notifications for each `DealActivity` template.
- Two new checkboxes should be added to the `DealActivity` form:
  - **Notify Employees**: If checked, internal admins will receive an email when a deal moves into this stage.
  - **Notify Investor**: If checked, the investor's approved users will receive an email when their deal moves into this stage.
- **Customization**: Custom notifications are managed at the **Deal** level. Users can create `CustomNotification` records for a Deal with the email method `deal_activity_move`.

### 3.2 Notification Trigger
- When a `DealInvestor`'s `deal_activity_id` is updated, the system should check the notification settings of the **new** activity.
- This trigger must handle both:
  - **Automated Transitions**: When an activity is marked "Complete" and the deal moves to the next sequential activity.
  - **Manual Updates**: When a deal is moved manually via the Kanban board or the Deal Investor edit form.
- The system will look for a `CustomNotification` owned by the `Deal`. It will prioritize a notification with a `tag` matching the new activity's title, falling back to a general `deal_activity_move` notification for that deal.

### 4.1 Data Model Changes
- **Table**: `deal_activities`
  - Add `notify_employees` (boolean, default: false)
  - Add `notify_investor` (boolean, default: false)

### 4.2 Application Logic
- **`Deal`**: Include `WithCustomNotifications` concern.
- **`DealActivity`**: Update `permit` params and ensure defaults are set.
- **`DealInvestor#create_activities`**: Ensure `notify_employees` and `notify_investor` flags are copied from the `DealActivity` template to the investor-specific instances.
- **`PerformActivityAction` Service**: After updating the `deal_activity_id` on the `DealInvestor`, trigger the notification if the new activity has flags enabled.
- **`DealActivityMoveNotifier`**: A new notifier class inheriting from `BaseNotifier`. It will look up the `CustomNotification` from the `Deal`.


### 4.3 UI Implementation
- Update the `DealActivity` form partial: `app/packs/startups/deals/views/deal_activities/_form.html.erb`.
- Update the `DealActivity` column in the Deal Investor grid if necessary, though the primary configuration is in the activity templates.

## 5. Acceptance Criteria
- [ ] New checkboxes appear in the Deal Activity template form.
- [ ] Creating/Editing a template saves the notification flags.
- [ ] New flags are correctly copied when a new `DealInvestor` is added to a deal.
- [ ] Completing an activity that leads to a "notifiable" stage triggers an email.
- [ ] Manually changing the stage of a deal to a "notifiable" stage triggers an email.
- [ ] Emails are sent to the correct recipients (Employees and/or Investor) based on the flags.
- [ ] Email content is accurate and professional.
