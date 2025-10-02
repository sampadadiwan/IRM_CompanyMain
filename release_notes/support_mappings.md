# PR: Support Client Mappings

## User Note
App users with support role can now:
- Create and manage **support client mappings** that determine which entities they can impersonate.
- **Login as end-users** within a client entity if allowed by mapping settings (`enable_user_login` and optional `user_emails` whitelist).
- **Switch and revert** between their own support entity and client entities securely, with roles updated automatically.
- Find new menu entries under **Profile → Support** for quick access.

## Overview
Introduced support client mappings feature with switch/revert capabilities and enhanced login restrictions.

## Motivation
This change was needed to enable support users to securely impersonate client accounts in a controlled manner, improving support and troubleshooting efficiency while tightening access control via email whitelists.

## What Changed
- **Views**
  - Updated `admin/users/show.html.erb` to integrate `SupportClientMapping.allow_login_as`.
  - Extended modernize company and profile menus to link to support client mappings and support agents.
  - Added UI for `enable_user_login` and `user_emails` in `_form.html.erb` and `show.html.erb`.
  - Adjusted conditional visibility of edit/delete actions based on Pundit policies.
- **Controllers**
  - Added `switch` and `revert` actions in `SupportClientMappingsController`.
- **Models**
  - Expanded `SupportClientMapping` with:
    - Lifecycle methods for `switch` (enable, impersonate as client) and `revert` (return to original state).
    - `status` handler (Switched/Reverted).
    - `allow_login_as` enforcement against allowed user emails.
- **Policies**
  - Enhanced `SupportClientMappingPolicy` to support `switch?`, `revert?` and scoped access for non-super users.
- **Routes**
  - Added `PATCH` member routes for `switch` and `revert`.
- **Locales**
  - New translation entries for `settings` and `settings_with_caphive`.

## Refactoring / Behavior Changes
- Core impersonation logic moved into `SupportClientMapping` model methods (`switch`, `revert`) with persisted state in `json_fields`.
- Fine-grained authorization: only support users or super users can switch/revert mappings.
- Frontend conditionals adapted to `policy` checks instead of blanket access.

## Testing
- Manual UI verification:
  - Support users restricted to visible mappings.
  - Switch to client entity as company admin, then revert back successfully.
- Negative testing:
  - Prevented switch on disabled mappings.
  - Prevented revert without previous entity context.
- Verified `allow_login_as` blocks unauthorized email impersonations.

## Impact
- Security: Strengthened support login checks and auditability.
- UX: Support agents have dedicated menu entries for mappings and agent portals.
- Compatibility: Non-invasive to existing entities/users, default behavior unchanged.
- No breaking migrations or API changes.

## Review Focus
- **Model logic**: Correct persist/restore of entity_id and roles in `switch`/`revert`.
- **Policy edge cases**: Ensure no unauthorized support logins.
- **UI conditions**: Visibility of mapping controls aligned with permissions.