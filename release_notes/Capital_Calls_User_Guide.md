# Capital Calls Setup & Management Guide

CapHive provides a comprehensive solution for managing Capital Calls and Drawdowns, automating the computation of call amounts, generation of notices, investor notifications, and payment tracking.

## 1. Top-Level Summary & Stats
At the top of the Call screen, key financial aggregates are displayed:
*   **Called**: Total amount requested across all remittances.
*   **Collected**: Total amount received and recorded.
*   **To Be Called**: Any remaining amount yet to be allocated (if applicable).
*   **Due**: The current outstanding balance (Called - Collected).
*   **Due Date**: A large indicator of the deadline for this call.

---

## 2. Creating & Configuring a New Call
When creating or editing a call, the following parameters define how CapHive computes the **Remittances** (investor-wise dues):

### Call Basis (Computation Logic)
*   **Percentage of Commitment**: (Default) Calls a fixed percentage (e.g., 10%) of the committed capital for each investor.
    *   *Note*: You must specify the percentage applicable for each close (e.g., 5% for First Close, 10% for Final Close).
*   **Investable Capital Percentage**: Uses any custom basis set up for your fund (e.g., Unfunded Capital %).
    *   *Requirement*: Ensure applicable percentages have been computed in allocations or uploaded prior to the call.
    *   *Total Amount*: You will need to enter the total call amount to be allocated among investors.
*   **Upload**: Manually provide the amounts to be called from each investor via an Excel upload.

### Dates & Tracking
*   **Call Date**: The official date of issuance.
*   **Due Date**: Used for flagging status (Due/Overdue) and computation of IRRs.

### Notification Options (Checkbox Toggles)
*   **Send Call Notice**: Triggers an email when the call is **Approved**.
*   **Send Payment Notification**: Triggers an email when the remittance is **Verified**.
*   *Default*: Both are turned on by default but can be unselected if you prefer the platform not to send automated emails.

---

## 3. Primary Call Actions & Permissions
Directly below the call summary are the primary controls. Visibility depends on user roles and status.

### Call Management
*   **Edit**: Modify call details. Requires Employee `update` permission.
*   **Delete**: Remove the call and its remittances. Requires Employee `destroy` permission.
*   **Actions (Dropdown)**:
    *   **Generate Documents**: Creates personalized drawdown notices based on the uploaded template, remittance details, and investor personal details (unit type, address, etc.).
        *   *Technical Action*: Starts `CapitalRemittanceDocJob`.
    *   **View Generated Documents**: Review the generated PDFs. Review can be done individually or in bulk.
        *   *Approval Requirement*: Notices must be approved (individually or in bulk) prior to call approval.
    *   **Approve**: Marks the call as ready and triggers the issuance process.
        *   *Conditions*: Blocked if there are unapproved generated documents.
        *   *Notification*: Triggers the email notification to all investors (if enabled). Approved notices are attached to the email.
        *   *Preview*: Use "View Who Gets Notified" during approval to verify recipients.
        *   *Permissions*: Requires Employee `update` permission AND `approver` role.
    *   **Allocate Units**: Starts `FundUnitsJob` to compute units for each commitment.
        *   *Conditions*: Only available after the call is **Approved** and **Unit Prices** are defined.
    *   **Recompute Call**: Refresh all remittance amounts if you've updated fund data or fee structures.

---

## 4. Remittances Workspace
The **Remittances** tab is the primary area for managing individual dues.

*   **Review**: Review dues on-screen or download as Excel.
*   **Exclude Investors**: Delete an individual remittance to exclude that investor from the call.
*   **Capital Call Reminder**: Sends follow-up emails specifically to investors with "Pending" or "Overdue" status.
*   **Upload / Download (Dropdown)**:
    *   **Download**: Exports the full list including fee breakdowns.
    *   **Upload Remittances**: Bulk import custom call amounts.
    *   **Upload Payments**: Bulk record payment receipts mapping to **Folio Numbers** (the unique identifier).
*   **Verification**:
    *   **Verify Action**: Once a payment is added, it must be **Verified** by a user with an Approver role.
    *   *Bulk Action*: Multiple remittances can be verified at once via the "Unverified Remittances" report.
    *   *Result*: Triggers the payment confirmation email.

---

## 5. Typical Workflow Summary
1.  **Setup**: Create call, set Basis (e.g., 10% of Commitment) and Dates.
2.  **Review**: Verify the generated Remittances in the tab. Exclude any investors if necessary.
3.  **Docs**: Click **Actions > Generate Documents**.
4.  **Review Docs**: Navigate to **View Generated Documents**, review, and **Approve** the PDFs.
5.  **Issue**: Click **Actions > Approve** to send emails with attachments.
6.  **Payments**: Add payments (UI or Bulk Upload).
7.  **Confirm**: Verify payments to trigger confirmation emails.
8.  **Remind**: Use **Capital Call Reminder** for outstanding balances.

---

## 6. Execution & Notification Summary
| Action | Notification Triggered? | Content | Recipient |
| :--- | :--- | :--- | :--- |
| **Approve Call** | **Yes** (if flag set) | Drawdown Notice (PDF) + Custom Message | All Investors in Call |
| **Send Reminder**| **Yes** | Reminder Message | Pending/Overdue Investors |
| **Verify Payment**| **Yes** (if flag set) | Payment Confirmation | Specific Investor |

*Note: For any additional standard attachments, attach them to the **Custom Notification** tab. For investor-specific attachments, upload them directly to the respective remittance.*
