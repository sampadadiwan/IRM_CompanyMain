# Product Requirements Document: Access Rights Module

## 1. Overview

The Access Rights module is a core component responsible for managing and enforcing granular access permissions for various entities within the system. It allows for the assignment of specific rights (e.g., create, read, update, destroy) to individual investors or users for different types of entities such as funds, secondary sales, or documents. This module supports both manual granting via the User Interface and bulk import functionalities. A critical aspect of its design is the caching mechanism, which optimizes performance by storing user access rights in the `User` model via the `AccessRightsCache` concern, ensuring quick retrieval and efficient permission checks.

## 2. Objectives

*   **Ensure Data Security and Confidentiality:** Implement robust mechanisms to control who can access and modify sensitive entity data based on their assigned roles and permissions.
*   **Provide Granular Access Control:** Allow for precise definition of access rights at the entity level, enabling different levels of visibility and interaction for various user types (e.g., company admin, employee, investor advisor).
*   **Optimize Performance for Access Checks:** Utilize caching strategies to minimize database queries and improve the responsiveness of the application when performing access rights validations.
*   **Support Flexible Access Granting:** Facilitate both manual and automated (import-based) methods for assigning and revoking access rights.
*   **Maintain Data Consistency:** Ensure that access rights, once granted or revoked, are consistently reflected across the system and in the cached user permissions.

## 3. Features and Functionality

### 3.1 Access Rights Assignment

*   **UI-Based Assignment:**
    *   Ability for authorized users (e.g., system administrators, company admins) to grant specific access rights to individual users or investors for a given entity (e.g., a specific Fund, Secondary Sale, Document).
    *   Support for selecting permission types (create, read, update, destroy) via a bitmask or similar mechanism.
    *   Option to specify metadata associated with the access right.
*   **Bulk Import:**
    *   Functionality to import access rights from a structured file (e.g., CSV, Excel) for multiple users/investors and entities.
    *   Validation of imported data to ensure correctness and prevent invalid assignments.
    *   Error reporting for failed imports.

### 3.2 Access Rights Enforcement

*   **Permission Checks:**
    *   System-wide enforcement of access rights before allowing users to perform actions (create, read, update, destroy) on entities.
    *   Integration with application policies (e.g., `ApplicationPolicy`) to leverage cached permissions for quick decisions.
*   **Role-Based Access Logic:**
    *   **Company Admin:** Full access to everything within their entity, no specific access rights or investor access required.
    *   **Employee:** Access to specific entities only if explicitly granted access rights. No investor access required.
    *   **Fund Investor Advisor:** Access to specific entities if granted access rights by the fund, and requires investor access from the fund.
    *   **Investor Investor Advisor:** Access to specific entities if granted access rights by the investor, and requires investor access from the fund.

### 3.3 Access Rights Caching (`AccessRightsCache` Concern)

*   **Cache Structure:**
    *   `access_rights_cache` (hash serialized in `User` model): Stores permissions in the format `{entity_id: {owner_type: {owner_id: permissions}}}`.
    *   `access_rights_cached_permissions` (flag in `User` model): Temporary cache for bitmask permissions (create, read, update, destroy) used in policy checks.
*   **Cache Management:**
    *   `cache_access_rights`: Adds or updates access rights in the cache when an `AccessRight` object is created or modified.
    *   `remove_access_rights_cache`: Removes access rights from the cache when an `AccessRight` object is deleted.
    *   `refresh_access_rights_cache`: Resets and rebuilds the cache for a user, typically triggered when `InvestorAccess` is approved, unapproved, or deleted. This method handles both employee and investor advisor access rights, including investor-specific and category-specific access rights.
    *   `reset_access_rights_cache`: Cleans up and resets all access rights for a user based on their cached role (company_admin, employee, investor, investor_advisor).
*   **Cache Retrieval:**
    *   `get_cached_access_rights_permissions`: Retrieves cached permissions for a specific entity, owner type, and owner ID.
    *   `get_cached_ids`: Retrieves cached owner IDs for a given entity and owner type, or all IDs for an owner type across all entities.

## 4. User Stories and Use Cases

### 4.1 Administrator/Company Admin

*   **User Story:** As a Company Admin, I want to grant a new employee read-only access to specific fund documents so they can review them without making changes.
    *   **Use Case:** The Company Admin navigates to the employee's profile, selects the "Access Rights" section, chooses the relevant fund documents, and assigns "read" permission.
*   **User Story:** As a Company Admin, I want to import a list of 50 new investors and automatically assign them read access to all public reports.
    *   **Use Case:** The Company Admin prepares a CSV file with investor IDs and report IDs, uses the bulk import feature, and verifies the successful assignment of access rights.

### 4.2 Employee

*   **User Story:** As an Employee, I want to view only the deals that I have been granted access to, so I don't see irrelevant or restricted information.
    *   **Use Case:** The Employee logs in, navigates to the "Deals" section, and the system automatically filters the list to show only deals for which they have "read" access.
*   **User Story:** As an Employee, I want to upload a document to a specific fund, but only if I have "create" permissions for that fund's documents.
    *   **Use Case:** The Employee attempts to upload a document. The system checks their cached permissions for the fund's documents. If "create" permission is present, the upload proceeds; otherwise, an error message is displayed.

### 4.3 Investor Advisor (Fund-based)

*   **User Story:** As a Fund Investor Advisor, I want to see all documents and reports related to the funds I advise, provided the fund has granted me investor access.
    *   **Use Case:** The Investor Advisor logs in. The system checks their `InvestorAccess` status for the relevant funds and their `AccessRight` grants from those funds. Only accessible documents and reports are displayed.

### 4.4 Investor Advisor (Investor-based)

*   **User Story:** As an Investor Investor Advisor, I want to view the portfolio details of a specific investor I manage, provided I have been granted access by that investor and the fund.
    *   **Use Case:** The Investor Investor Advisor navigates to the investor's portfolio. The system verifies both the investor-specific access rights and the overarching fund investor access before displaying the data.

## 5. Technical Requirements

*   **Database Schema:**
    *   `AccessRight` model: Must include fields for `user_id`, `entity_id`, `owner_type`, `owner_id`, `permissions` (integer bitmask), and `metadata`.
    *   `User` model: Must include a `text` column for `access_rights_cache` (serialized hash) and an integer column for `access_rights_cached_permissions` (flag).
    *   `InvestorAccess` model: Must include `user_id`, `entity_id`, `investor_id`, `investor_entity_id`, and `status` (e.g., `approved`).
*   **Caching Mechanism:**
    *   The `AccessRightsCache` concern in `app/packs/core/users/models/concerns/access_rights_cache.rb` must be included in the `User` model.
    *   The `access_rights_cache` attribute must be serialized as a `Hash`.
    *   The `access_rights_cached_permissions` attribute must be a flag with `create`, `read`, `update`, `destroy` permissions.
*   **Performance:**
    *   Access rights checks should primarily rely on the `access_rights_cache` to minimize database load.
    *   Cache invalidation and refresh mechanisms must be efficient to ensure data freshness without performance degradation.
*   **Security:**
    *   All access rights assignments and checks must be secure against unauthorized modifications and bypasses.
    *   Input validation for all access rights operations (UI and import) is critical.
*   **Integrations:**
    *   Seamless integration with existing `ApplicationPolicy` for authorization.
    *   Compatibility with various entity types (e.g., `Fund`, `SecondarySale`, `Document`) that can act as `owner_type`.
*   **Error Handling:**
    *   Clear error messages for users attempting unauthorized actions or during import failures.
    *   Robust logging for access rights related events and errors.
*   **Scalability:**
    *   The caching mechanism should be designed to handle a large number of users, entities, and access rights without significant performance degradation.