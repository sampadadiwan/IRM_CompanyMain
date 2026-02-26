# AccessRightsCache Technical Documentation

## 🏗️ Architecture Overview

The `AccessRightsCache` is a critical performance optimization component within the IRM system. It provides a serialized caching mechanism for user permissions, allowing for rapid authorization checks without expensive database joins or recursive permission lookups.

It is implemented as an `ActiveSupport::Concern` included in the `User` model (`app/packs/core/users/models/user.rb`). The cache stores a bitmask of permissions and optional metadata for specific entities (like Funds, Deals, or Documents) that a user has been granted access to.

### Roles Involved:
1.  **Company Admin**: Generally bypasses the cache as they have full access within their entity.
2.  **Employee**: Uses the cache for granular access to specific items within their company.
3.  **Investor / Investor Advisor**: Uses the cache to access data across different entities (Funds) they have invested in or advise.

---

## 🛠️ Implementation Details

### Key Storage
- **`access_rights_cache`**: A serialized `Hash` in the `users` table.
- **Structure**: `{ entity_id: { owner_type: { owner_id: "permissions, metadata" } } }`
    - `entity_id`: The ID of the entity granting the access.
    - `owner_type`: The class name of the object being accessed (e.g., `"Fund"`).
    - `owner_id`: The ID of the object.
    - `permissions`: An integer bitmask (using the `flag` gem for `create`, `read`, `update`, `destroy`).
    - `metadata`: Optional string for additional context (e.g., used for "Summary" vs "All" access).

### Core Methods (`AccessRightsCache`)
- **`get_cached_access_rights_permissions(entity_id, owner_type, owner_id)`**:
    - Performs the lookup in the hash.
    - If `entity_id` is nil, it scans across all entities in the cache (useful for Investor Advisors).
    - Sets `access_rights_cached_permissions` on the user instance for the current check.
- **`cache_access_rights(access_right, ...)`**:
    - Formats and writes an `AccessRight` record's permissions into the hash.
    - Only caches if the user is an employee, has `investor_advisor` role, or has valid `investor_access`.
- **`refresh_access_rights_cache(investor_access, add: true)`**:
    - Rebuilds parts of the cache when an investor's access is approved or revoked.
    - Handles category-based and investor-specific `AccessRight` inheritance.
- **`reset_access_rights_cache`**:
    - Completely clears and re-populates the cache based on the user's current roles and granted `AccessRight` records.

---

## 🔗 Entry Points & Usages

### 1. Authorization (Pundit Policies)
The primary consumer of the cache is `ApplicationPolicy` (`app/packs/core/base/policies/application_policy.rb`).
- **`permissioned_employee?`**: Checks the cache for the current user's entity.
- **`permissioned_investor?` / `permissioned_investor_advisor?`**: Uses the cache to verify if an external user has rights to the record (e.g., an Investor viewing a Fund).
- **`permissioned_rm?`**: Checks rights for Relationship Managers.

### 2. Data Filtering (ActiveRecord Scopes)
- **`ForInvestor` Concern**: Uses `user.get_cached_ids` to filter queries.
    - Example: `Fund.for_investor(current_user)` will use the cached IDs to perform a simple `WHERE id IN (...)` query instead of complex joins.

### 3. Lifecycle Hooks (Cache Invalidation)
The cache is automatically updated via `after_commit` hooks in several models:
- **`AccessRight`**:
    - `add_to_user_access_rights_cache`: Triggered on create/update.
    - `remove_from_user_access_rights_cache`: Triggered on destroy.
- **`InvestorAccess`**:
    - `add_to_user_access_rights_cache`: Triggered when an investor user's access is `approved`.
    - `remove_from_user_access_rights_cache`: Triggered on destruction.
- **`UpdateInvestor` (Concern)**:
    - Calls `reset_access_rights_cache` when critical investor attributes change.

---

## ⚡ Outcomes & Side Effects

### Synchronous Outcomes
- **Database Update**: Every time an `AccessRight` is changed or an `InvestorAccess` is approved, the `users.access_rights_cache` column is updated.
- **Instant Authorization**: Subsequent calls to `policy(user, record).show?` reflect the change immediately without additional DB queries.

### Asynchronous Outcomes
- **Background Jobs**: In some cases (like Folder permissions), `AccessRightsDeletedJob` may be enqueued to handle cascading cleanup, though the primary cache update is usually synchronous within the commit.

### External Side Effects
- **Search Indexing**: While the cache itself is internal to the DB, changes to `AccessRight` trigger `Chewy` index updates for the `access_right` index.

---

## 🧪 Testing Strategy
- **Unit Tests**: Check `spec/models/user_spec.rb` (or specific concern specs) for cache structure verification.
- **Policy Tests**: Many RSpec policy specs rely on `AccessRightsCache` being correctly populated.
- **Integration**: Cucumber features involving "Investor login" or "Granting permissions" exercise the full flow from `AccessRight` creation to cache lookup.

---

## ⚠️ Constraints & Edge Cases
- **Serialization Size**: Large numbers of granular permissions can lead to a large `access_rights_cache` hash.
- **Concurrency**: High-frequency updates to permissions for the same user might lead to race conditions (handled by Rails `after_commit`, but still a point of caution).
- **Manual Reset**: If the cache becomes out of sync (due to manual DB edits or failed callbacks), `user.reset_access_rights_cache` must be called to restore integrity.
- **Folder Inheritance**: Permissions for `Folder` objects are often handled differently (cascading) compared to direct entity permissions like `Fund` or `Deal`.
