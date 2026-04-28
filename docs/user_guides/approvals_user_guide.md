# Approvals User Guide

## Overview

The Approvals system provides a structured workflow for collecting consent or decisions from investors. Fund managers create an approval request, set a due date, configure response options, and then activate it to notify investors. Investors respond via the portal or directly from an email link (no login required). The system tracks responses in real time and supports reminders, document attachments, KYC display, and post-approval processing hooks.

---

## Roles and Permissions

| Role | What they can do |
|------|-----------------|
| **Employee (Company/Fund admin)** | Create, edit, delete approvals; add access rights; add documents; activate (approve) the approval; close the approval; send reminders |
| **Approver** | Same as employee, plus the ability to activate (approve) an approval |
| **Investor** | View approvals they have been granted access to; submit and update their response before the due date |

> **Note:** The Approvals feature must be enabled for your account (`enable_approvals = true`). Contact your administrator if the menu item is not visible.

---

## Lifecycle of an Approval

```
Draft → Approved (Active) → Closed (Locked)
```

| State | Description |
|-------|-------------|
| **Draft** | Approval has been saved but not yet activated. Investors are not notified. Editable. |
| **Approved (Active)** | Activated by an Approver. Investors receive email notifications and can submit responses. Still editable until the due date or until closed. |
| **Closed (Locked)** | No further changes or responses are accepted. Post-approval processing runs (e.g. capturing committed amounts on a Fund). |

---

## Step-by-Step: Creating an Approval (Fund Manager)

The approval detail page shows a guided steps bar:

> **Setup Approval → Add Access Rights → Add Documents → Finalize Approval → Track Responses → Send Reminders**

### Step 1 — Setup Approval

Navigate to **Approvals → New Approval** and fill in the form:

| Field | Required | Description |
|-------|----------|-------------|
| **Title** | Yes | Name of the approval request (e.g. "Q1 2026 Drawdown Consent") |
| **Due Date** | Yes | Last date investors can submit a response. Defaults to 7 days from today. Responses and edits are blocked after this date. |
| **Response Status** | Yes | Comma-separated list of response options presented to investors. Default: `Approved,Pending,Rejected`. You can customise these (e.g. `Yes,No,Abstain`). |
| **Details** | No | Rich-text body of the approval request — terms, instructions, reference text, etc. |
| **Show KYCs in Approval** | No | When enabled, the investor's active KYC records (full name, PAN) are shown inside the approval email and response page. Useful for confirming identity at the point of consent. |
| **Enable response links in email** | No | Adds one-click response buttons directly in the notification email. Investors can respond without logging in. Links are cryptographically signed and expire in 7 days. |

Click **Save**. The approval is now in **Draft** state.

### Step 2 — Add Access Rights

Access rights control which investors can see and respond to this approval.

1. On the approval detail page, click the **Access Rights** tab.
2. Add individual investors, investor groups, or link the approval to an owner (e.g. a Fund) to inherit its access rights automatically.

> When an approval is linked to an **owner** (Fund, Deal, etc.), access rights are copied from the owner when the approval is created. Any new investor added to the owner after creation will automatically get an approval response generated for them.

### Step 3 — Add Documents

1. Click the **Documents** tab.
2. Upload any supporting documents (offering memoranda, term sheets, consent forms).
3. Documents attached here are automatically included as attachments in the notification email sent to investors, with optional password protection via custom notifications.

### Step 4 — Finalize Approval (Activate)

Once the approval is ready, an **Approver** role user clicks **Approve** on the approval detail page.

- A confirmation prompt appears: *"Please check that investors are added to access rights before approving. Approve and send notifications to investors?"*
- On confirmation:
  - The approval status changes to **Active** (`approved = true`).
  - Pending response records are generated for all investors with access rights.
  - Email notifications are queued and sent to each investor.

> You cannot activate an approval if you only have the standard employee role. You need the **Approver** role.

### Step 5 — Track Responses

On the **Responses** tab you can see:

- A **summary card** per response status (e.g. Approved: 12, Pending: 5, Rejected: 2, All: 19). Click any card to filter the response list.
- A **response table** showing: Investor name, Tags, Responded by (user), Status badge (colour-coded), Last updated.
- For each row: **Show**, **Edit** (if editable), and a **Quick Response** dropdown (for investors or permissioned employees).

The response counts are maintained automatically using counter-cache columns on the approval record.

### Step 6 — Send Reminders

If some investors have not yet responded before the due date:

1. Click **Send Reminder** on the approval detail page.
2. A confirmation prompt appears: *"Send notifications to pending investors?"*
3. On confirmation, all pending approval responses are reset to `notification_sent = false` and a reminder email is re-queued for each.

> Reminders are only available when the approval is **Active** (`approved = true`) and the due date has not passed.

---

## Closing an Approval

Click **Close** on the approval detail page.

- Confirmation: *"This will close the approval and lock it so no further changes can be made."*
- The approval is **locked** — no edits, no new responses accepted.
- If the approval is linked to an owner (e.g. a Fund), the owner's `post_approval` hook runs automatically. For example, a Fund can extract approved amounts and record commitments for each investor.

---

## Investor Experience

### Viewing Approvals

Investors see only approvals for which they have been granted access rights **and** have approved investor access to the entity.

Navigate to **Approvals** from the main menu to see a list. Click an approval to open the detail view showing:

- Approval title and due date
- Description / agreement reference text
- KYC details (if enabled by the fund manager)
- The investor's current response and a form to update it

### Responding via the Portal

1. Open the approval.
2. In the response card, select a status from the dropdown (options are set by the fund manager, e.g. *Approved*, *Rejected*).
3. Click **Submit**.

The response is recorded with a timestamp and the logged-in user's name.

> **Pending** is not a valid submitted response — you must select a non-pending status. Investors cannot change a response after the approval due date has passed.

### Responding via Email (No Login Required)

When **Enable response links in email** is turned on, the notification email contains clickable response buttons (e.g. "Approved", "Rejected") for each non-Pending status.

- Clicking a link immediately records the response — no login needed.
- The link is signed and expires in **7 days**.
- After clicking, the investor sees a confirmation page ("Successfully registered response: Approved.").
- If the link is invalid or expired, an error message is shown.

---

## Email Notifications

| Trigger | Email sent to |
|---------|--------------|
| Approval activated (Approve button clicked) | All investors with pending responses |
| Reminder sent (Send Reminder button clicked) | All investors with still-pending responses |
| Investor submits a response | The investor (confirmation of their recorded status) |

### Custom Notifications

Each approval supports custom notification templates (via the **Notification** tab on the detail page). Custom templates can:

- Override the default email subject and body
- Control whether the approval link is shown
- Control whether details (e.g. KYC info) are shown inline
- Attach documents with optional password protection

If no custom notification is configured, a standard email is sent with the approval title, description, KYC section (if enabled), response links (if enabled), and a "View Approval" button.

---

## Fund / Deal Integration

Approvals can be linked to an **owner** such as a Fund or Deal. When linked:

- Each investor's response is associated with their specific **folio** (commitment record) within that Fund or Deal, rather than just the investor entity.
- The owner's access rights are automatically copied to the approval on creation.
- When the approval is **closed**, the owner's `post_approval` method is called — for example, a Fund can capture the approved amounts from each investor's response and record them as commitments.

---

## Custom Fields

Approvals and approval responses support **custom fields** configured at the entity level. These appear in the approval form and response form and can capture additional structured data (e.g. "Committed Amount", "Investment Vehicle").

---

## Admin Panel

Administrators can access approvals and approval responses via the admin panel at `/admin/approvals` and `/admin/approval_responses`. The admin dashboard provides filtering and export capabilities for oversight and audit purposes.

---

## Frequently Asked Questions

**Q: Why can't I see the "Approve" button?**  
A: The Approve button requires the **Approver** role. Contact your administrator to grant this role.

**Q: Can an investor change their response after submitting?**  
A: Yes, as long as the approval is still Active and the due date has not passed. The investor can open the approval and resubmit.

**Q: What happens if I add an investor to access rights after the approval is already Active?**  
A: A new pending response is automatically generated for the newly added investor, and they receive an email notification.

**Q: Can I reopen a closed approval?**  
A: No. Once an approval is closed (`locked = true`), it cannot be reopened. Create a new approval if you need to collect further responses.

**Q: The email response link says "Invalid link" — what went wrong?**  
A: Email response links expire after 7 days. If the investor clicked after expiry, or the email was forwarded from a different address, the link will fail. Ask the investor to log in to the portal to respond directly, or resend a reminder email.

**Q: How do I export response data?**  
A: On the Responses tab, approval responses can be exported to Excel (`.xlsx`) using the export option in the response list.

**Q: What are the default response statuses?**  
A: `Approved,Pending,Rejected`. You can customise this list when creating or editing the approval. Use a comma-separated list of any labels you need (e.g. `Yes,No,Abstain,Not Applicable`).
