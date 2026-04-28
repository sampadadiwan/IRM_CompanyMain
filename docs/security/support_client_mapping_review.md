# SupportClientMapping Review & Edge Cases

## Overview
`SupportClientMapping` is a core mechanism in IRM that allows **Support Users** to be linked to **Client Entities** for a specific duration. It manages both the administrative link and the functional "impersonation" (Switch/Revert) logic.

### Core Components
- **Model**: `SupportClientMapping` (links `User` to `Entity`)
- **Controller**: `SupportClientMappingsController` (CRUD + Switch/Revert actions)
- **Policy**: `SupportClientMappingPolicy` (Pundit-based authorization)
- **Automation**: `DailyMorningJob` (Handles expiration and cleanup)

---

## State Machine & Logic Flow

### 1. Mapping Lifecycle
- **Creation**: A Super User creates a mapping with an `end_date` and `enabled: true`.
- **Activation (`enable_support`)**: 
    - Sets `enabled: true` on the mapping.
    - Sets `:enable_support` permission on the `Entity`.
    - Sets `enable_support: true` on **all employees** of that Entity.
- **Deactivation (`disable_support`)**:
    - Sets `enabled: false` on the mapping.
    - **Conditional**: Only unsets `:enable_support` on the Entity/Employees if **no other active mappings** exist for that Entity.
- **Expiration**: `DailyMorningJob` calls `disable_expired` daily for mappings where `end_date < today`.
- **Cleanup**: `DailyMorningJob` destroys mappings that have been disabled for > 1 week.

### 2. Impersonation (Switch/Revert)
- **Switch**:
    - Caches `orig_entity_id` and `orig_roles` in the user's `json_fields`.
    - Updates user's `entity_id` to the client's `entity_id`.
    - Adds `company_admin` role; removes `support` role.
- **Revert**:
    - Restores `entity_id` and `roles` from `json_fields`.
    - Re-adds `support` role; removes `company_admin` role.

---

## Critical Edge Cases & Risks

### A. Impersonation & Expiration (High Risk)
1.  **The "Locked-In" Support User**: 
    - *Scenario*: A support user is currently "Switched" into a client entity. The mapping expires (via `DailyMorningJob`) or is manually disabled by a Super User.
    - *Result*: The `revert` method raises `Cannot revert a disabled mapping`. The support user is now stuck in the client's entity context with no UI-based way to return to their original entity.
2.  **Concurrent Mappings**:
    - *Scenario*: Two different support users are mapped to the same client entity. One mapping expires.
    - *Result*: The system correctly checks `other_active` mappings before disabling entity-wide support, but if both expire, the last one to expire triggers the global disable.
3.  **Missing `orig_entity_id`**:
    - *Scenario*: A user's `json_fields` are corrupted or cleared while switched.
    - *Result*: `revert` raises `No previous entity to revert to`.

### B. Data Integrity & Performance
4.  **`update_column` Side Effects**:
    - The model uses `update_column` and `update_columns` extensively. This **skips all ActiveRecord callbacks and validations**. If other models (like `User` or `Entity`) have `after_save` hooks for these fields, they will not fire.
5.  **Mass Employee Updates**:
    - `enable_support` iterates through `entity.employees.each` and calls `update_column` on every single one. For entities with thousands of employees, this is a performance bottleneck and should be a background job.
6.  **Race Conditions in `disable_support`**:
    - The `other_active` check (`entity.support_client_mappings.where.not(id: id).where(enabled: true).exists?`) is not atomic. In a high-concurrency environment, two mappings could be disabled simultaneously, both seeing the other as "active" during the check, resulting in support remaining enabled when it should be disabled.
7.  **Orphaned Permissions on Deletion**:
    - Deleting a `SupportClientMapping` record (via `destroy`) does not trigger `disable_support`. If the last mapping for an entity is deleted, the entity and its employees will remain in an "enabled support" state indefinitely with no active mapping to justify it.
8.  **Redundant State Updates**:
    - `enable_support` and `disable_support` do not check if the entity or users are already in the target state. They blindly perform updates, which is inefficient and can trigger unnecessary database writes (especially the `entity.save` and employee loops).

### C. Authorization & Permissions
7.  **Super User vs. Support User**:
    - Only Super Users can create/edit mappings, but Support Users can see their own mappings and perform Switch/Revert.
    - *Edge Case*: If a Support User's `support` role is removed while they are switched, they may lose the ability to see the `SupportClientMapping` index/show pages, preventing them from reverting.
8.  **Entity Support Toggle**:
    - The `switch` logic checks `entity.enable_support`. If a Super User manually unsets this permission on the Entity record (bypassing the mapping), the `switch` will fail even if the mapping is "Enabled".

---

## Test Results (Cucumber)

All identified edge cases have been implemented in `features/admin/support_client_mapping_edge_cases.feature` and are passing.

### Verified Scenarios:
- [x] **Locked-In User**: Confirmed `revert` raises "Cannot revert a disabled mapping" if mapping is disabled while switched.
- [x] **Concurrent Mappings**: Confirmed disabling one mapping doesn't break entity-wide support if another is active.
- [x] **Missing State**: Confirmed `revert` raises "No previous entity to revert to" if `orig_entity_id` is missing.
- [x] **Manual Permission Override**: Confirmed `switch` fails if entity support is manually disabled.
- [x] **Role Resilience**: Confirmed user can still revert even if their `support` role is removed while switched.
- [x] **Orphaned Permissions (Bug Found)**: Confirmed that deleting the last mapping fails to disable entity-wide support.

---

## Recommended Next Steps
1.  **Fix Deletion Bug**: Add a `before_destroy :disable_support` callback to `SupportClientMapping` to ensure permissions are revoked when the last mapping is deleted.
2.  **Force Revert Mechanism**: Implement a "Force Revert" action for Super Users to rescue "locked-in" support users.
3.  **Background Jobs**: Move the mass employee update in `enable_support` to a Sidekiq worker.
4.  **Atomic Permission Checks**: Use database locks or atomic operations when checking for `other_active` mappings to avoid race conditions.
5.  **State Verification**: Update `enable_support` and `disable_support` to only perform updates if the current state differs from the target state.
