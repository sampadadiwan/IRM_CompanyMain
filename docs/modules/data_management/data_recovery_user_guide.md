# User Guide: Data Recovery & Soft-Delete Management

The Investor Relationship Management (CapHive) system includes a robust data recovery feature that allows administrators to view and restore accidentally deleted records. This feature leverages "soft-deletion," meaning records are not immediately removed from the database but are instead marked as deleted.

---

## 1. Viewing Deleted Records

You can view a list of all deleted records for a specific resource (e.g., Investors, Documents, Entities) by navigating to the `show_deleted` URL for that resource.

### How to access:
Simply append `/show_deleted` to the standard index URL of any supported resource.

| Resource | URL for Deleted Records |
| :--- | :--- |
| **Investors** | `/investors/show_deleted` |
| **Documents** | `/documents/show_deleted` |
| **Entities** | `/entities/show_deleted` |
| **Investor KYCs** | `/investor_kycs/show_deleted` |
| **Funds** | `/funds/show_deleted` |

### Features of the Deleted View:
*   **Searchable:** Use the standard search filters to find specific deleted items.
*   **Paginated:** Easily navigate through large volumes of deleted data.
*   **Audit Trail:** View exactly when each record was deleted.

---

## 2. Restoring Deleted Records

Restoring a record brings it back to its active state, along with its associated data.

### Steps to Restore:
1.  Navigate to the `show_deleted` view for the relevant resource (as described above).
2.  Locate the record you wish to recover.
3.  Click the **Restore** button.
4.  A confirmation popup will appear asking if you are sure. Click **OK** to proceed.

### What happens during restoration:
*   **Recursive Recovery:** The system performs a recursive restore. For example, if you restore a `Fund`, its associated `Capital Calls` or `Commitments` that were deleted with it will also be restored.
*   **Special Handling for Documents:** If a Document belongs to a folder that is also deleted, the system will offer a **Restore Folder & All Docs** option. This ensures that the document's organizational structure is maintained upon recovery.
*   **Redirect to Show:** Once the restoration is complete, you will be automatically redirected to the record's primary **Show** page.
*   **Notification:** A success message will appear at the top of the screen confirming the restoration.

---

## 3. Authorization & Security

The ability to view and restore deleted records is governed by the same permissions as deleting records:

*   **View Access:** If you have permission to view the resource index, you can view the deleted index.
*   **Restore Access:** Only users with `destroy` (delete) permissions for a specific record are authorized to restore it.
*   **Entity Scoping:** Users can only see and restore deleted records belonging to their own entity (multi-tenancy is strictly enforced).

---

## 4. Supported Resources

The following resources support soft-deletion and the generic recovery feature:

*   **Core Management:** Investors, Entities, Documents, Investor KYCs, Quick Links, Folders.
*   **Financials:** Funds, Capital Calls, Capital Commitments, Capital Distributions, Capital Remittances, Portfolio Investments.
*   **Secondary Sales:** Secondary Sales, Offers, Interests, Allocations.
*   **Startup Tracking:** Deals, KPIs, KPI Reports, Deal Activities.
*   **Tasks & Misc:** Kanban Cards, Kanban Columns, Reminders, Nudges.

---

*Note: Records that have been "Permanently Deleted" by a system administrator cannot be recovered using this feature.*
