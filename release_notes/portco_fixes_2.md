# PR Description: portco_fixes_2

## 1. Overview
Centralized and refactored the signed ID access mechanism to allow secure, guest-access for KPI reporting without requiring a full login.

## 2. Motivation
The previous signed ID logic was tightly coupled to `KpiReport` and duplicated in controllers. This refactor makes the mechanism generic, reusable across the codebase, and improves security and maintainability.

## 3. What Changed
- **`ApplicationController`**: Added `find_by_signed_id_for_user` to dynamically resolve records and users from signed IDs.
- **`ApplicationRecord`**: Centralized signed ID generation and verification logic.
- **`KpiReportsController`**: Refactored to use the new centralized helper.
- **Pundit Policies**: Added `signed_id_access?` helper to `ApplicationPolicy` and updated `KpiReportPolicy` to authorize guest access.
- **Views**: Updated KPI report forms and mailers to support the refactored signed ID flow.
- **Tests**: Updated Cucumber features to reflect that login is no longer required when using a valid signed link.

## 4. Refactoring / Behavior Changes
- Logic for resolving guest access is now dynamic and based on model reflection.
- `current_user` is overridden to support the guest user context when accessed via a signed ID.
- Access via signed ID is now explicitly tracked on the user object using a singleton method `signed_id_access?`.

## 5. Testing
- Updated `features/startup/kpi_reminder_email.feature` to verify guest access without login.
- Manual verification of "Fill KPI Report" links from emails.

## 6. Impact
- **Maintainability**: Reduced code duplication across controllers.
- **Security**: Centralized verification logic using `ActiveSupport::MessageVerifier`.
- **UX**: Seamless experience for portfolio company users to report KPIs without password management.

## 7. Review Focus
- Dynamic instance variable setting in `ApplicationController#find_by_signed_id_for_user`.
- Authorization bypass in `KpiReportPolicy` when `signed_id_access?` is true.
- Implementation of `signed_id_access?` as a singleton method on the user object.
