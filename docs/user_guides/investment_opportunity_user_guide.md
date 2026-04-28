# Investment Opportunity User Guide

## Overview

Investment Opportunities (IOs) let fund managers publish a fundraise to a selected set of investors, collect Expressions of Interest (EOIs), and manage the allocation process through to close. Each opportunity has a rich investor-facing preview page, a document/data room structure, configurable widgets for marketing content, and a tracked EOI pipeline with approval, verification, and proportional allocation.

---

## Roles and Permissions

| Role | Capabilities |
|------|-------------|
| **Employee (Fund admin)** | Create, edit, delete opportunities; manage access rights, documents, widgets, track records, notifications |
| **Approver** | All employee rights, plus approve/unapprove individual EOIs |
| **Relationship Manager (RM)** | Submit EOIs on behalf of their clients; view and manage their own submitted EOIs |
| **Investor** | View opportunities they have access to; submit and update their own EOI; access data room if granted |

> **Note:** The Investment Opportunities feature must be enabled for your account (`enable_inv_opportunities = true`). Contact your administrator if the menu is not visible.

---

## Creating an Investment Opportunity

Navigate to **Investment Opportunities → New Investment Opportunity**.

### Required Fields

| Field | Description |
|-------|-------------|
| **Company Name** | Name of the company or deal (max 100 characters). Shown on the listing card and investor preview. |
| **Fund Raise Amount** | Total amount being raised. Drives the progress bar showing % raised (based on approved EOIs). |
| **Min Ticket Size** | Minimum amount an investor can express interest for. Validated on every EOI — amounts below this are rejected. |
| **Currency** | Currency for all monetary values. Defaults to the entity's configured currency. |
| **Last Date** | Closing date for EOIs. Defaults to one month from today. |

### Optional Fields

| Field | Description |
|-------|-------------|
| **Valuation** | Company or deal valuation — shown in the key metrics strip on the preview. |
| **Logo** | Company logo (JPEG/PNG/GIF/BMP). Displayed on the listing card and the preview header. |
| **Tags** | Comma-separated tags (e.g. `SaaS, Series B, Healthcare`). Used for filtering the opportunity list. Max 120 characters total. |
| **Details** | Rich-text investment thesis, deal description, or any long-form content. Displayed prominently on the investor preview. |
| **Shareable** | When enabled, a signed link to this opportunity can be shared with anyone — they can view the preview without logging in. Useful for advisors sharing deals with prospective investors. |

Click **Save**. The opportunity is created and you are taken to the detail page.

---

## Enriching the Opportunity

The detail page has a tabbed interface: **Documents, Widgets, Track Record, Tasks, Interests, Access Rights, Notifications**.

### Documents

The **Documents** tab holds files shown in the documents section of the investor preview. Upload offering memoranda, term sheets, pitch decks, and other materials investors should see by default.

A separate **Data Room** folder also exists on the opportunity. Data room documents are only shown to investors whose EOI has `Show Data Room` enabled.

### Widgets (Sections)

**Widgets** are rich content sections that appear in the body of the investor preview. Use them to add structured marketing content such as market opportunity, team bios, product highlights, and financial projections.

Each widget has:

| Field | Description |
|-------|-------------|
| **Title** | Section heading displayed on the preview |
| **Intro Text** | Short introductory paragraph shown above the main body |
| **Details** | Main rich-text body of the section |
| **Image / Video** | Upload an image or video file for the section |
| **Image Placement** | Position of the image relative to the text: `Left`, `Right`, or `Center` |
| **Embed YouTube Videos** | Paste a YouTube embed code to include a video player |
| **URL** | Optional link associated with the widget |

Widgets are displayed in creation order. Add as many as needed to tell the full investment story.

### Track Record

**Track Record** entries appear as highlight metrics in the preview (e.g. "3x MOIC", "₹500Cr AUM", "12 Exits"). Each entry has:

| Field | Description |
|-------|-------------|
| **Name** | Label for the metric (e.g. "Realised MOIC") |
| **Prefix** | Short prefix displayed before the value (e.g. `₹`, `$`) — max 5 characters |
| **Value** | The metric value (e.g. `3.2x`, `500`) |
| **Suffix** | Short suffix after the value (e.g. `Cr`, `M`) — max 5 characters |
| **Details** | Optional explanatory note displayed below the metric |

---

## Access Rights

The **Access Rights** tab controls which investors can see this opportunity and place EOIs.

- Add individual investors or investor groups manually.
- When an investor is added, they immediately gain view access and an `InvestmentOpportunity` access right is created.
- Investors granted access will appear in notification recipient lists.

To see who will receive a notification before sending, use **Notifications → View Who Gets Notified** (available as a link in each notification confirmation prompt).

---

## Preview

Click **Preview** on the detail page to see the opportunity exactly as investors see it:

- **Header** — company name, logo, close date
- **Key Metrics strip** — Fund Raise Amount, Approved EOI Amount, Valuation, Min Ticket Size
- **Details** — investment thesis (from the Details field)
- **Widgets** — all content sections in order
- **Track Record** — highlight metric cards
- **Documents panel** (right column) — all documents in the opportunity's folder
- **"Ready to Invest?" CTA** — links directly to the EOI form
- **Your Interest** (investors only) — shows the investor's own EOI card
- **Data Room** (visible to investors with data room access; always visible to fund managers)

### Shareable Link

When **Shareable** is enabled, a signed URL is generated that allows anyone with the link to view the preview without logging in. This is intended for advisors and relationship managers sharing opportunities externally. The link is cryptographically signed and scoped to the specific opportunity.

---

## Notifications

Fund managers can send notifications from the **Notifications** dropdown on the detail page.

### Built-in Notifications

| Notification | When to use |
|-------------|-------------|
| **Send Investment Opportunity Open: To LPs** | Announce that the opportunity is now open and investors can place EOIs |
| **Send Investment Opportunity Allocated: To LPs** | Announce that allocations have been finalised |

Both notifications are sent to all investors who have access rights to the opportunity.

Before confirming, a link to **View Who Gets Notified** is shown in the confirmation dialog — click it to verify the recipient list before sending.

### Custom Notifications

Any custom notification template configured at the entity level for `InvestmentOpportunity` appears as an additional menu item. Custom notifications support custom subject lines, body copy, and document attachments.

---

## Expression of Interest (EOI) Workflow

### How Investors Submit an EOI

1. Investor opens the opportunity (via notification email, direct link, or the portal listing).
2. Clicks **Express Interest** on the preview page.
3. Fills in the EOI form:

| Field | Description |
|-------|-------------|
| **Investor** | Pre-selected to the logged-in investor (investors cannot change this) |
| **Amount** | Investment amount. Must be ≥ Min Ticket Size and ≤ Fund Raise Amount |
| **Investor KYC** | Optionally link an existing KYC record to the EOI |
| **Details** | Free-text notes or questions for the fund manager |

4. Clicks **Save**. The EOI is created in an unapproved state and access rights to the opportunity are automatically granted.

> If the amount is edited after submission, the EOI is automatically reset to unapproved and must be re-approved by an Approver.

### How RMs Submit EOIs for Clients

Relationship managers can submit EOIs on behalf of their clients. In addition to the standard fields, RMs see:

| Field | Description |
|-------|-------------|
| **Investor Name** | Name identifying the investor or investor group |
| **Investor Email** | Email for the investor or investor group |
| **Investor KYC** | Select a KYC record; required before the EOI can be approved |

When an RM-submitted EOI is **approved**, the system automatically:
1. Looks up or creates a new Investor record using the `investor_name` and `investor_email`.
2. Re-points the linked KYC record to that new investor.

When the same EOI is **unapproved**, the KYC is re-pointed back to the RM.

### Approving and Unapproving EOIs

Users with the **Approver** role can approve or unapprove EOIs from the **Interests** tab or the Finalize Allocation view.

- Clicking **Approve** marks the EOI as `approved = true`.
- The EOI amount is added to the opportunity's **Approved EOI Amount** counter and the progress bar updates.
- Clicking **UnApprove** reverses this.

> An EOI for an RM-submitted interest cannot be approved unless a KYC record has been attached to it.

### Data Room Access

From the Interests tab, fund managers can toggle **Show Data Room** on or off for each individual EOI via the Actions dropdown. When enabled, the investor can see the data room section on the preview page.

### EOI Status Summary

The Interests tab shows five filter cards:

| Card | What it shows |
|------|--------------|
| **Total** | All EOIs for this opportunity |
| **Approved** | EOIs where `approved = true` |
| **Verified** | EOIs where `verified = true` (manually marked by the fund manager) |
| **Unapproved** | EOIs not yet approved |
| **Unverified** | EOIs not yet verified |

Click any card to filter the EOI table to that subset.

---

## Allocation Process

### Step 1 — Lock EOIs

Once the opportunity closes (or earlier if desired), lock new EOIs to prevent further submissions.

On the detail page, open the **Allocation** dropdown and click **Lock EOIs**. A confirmation prompt explains what this does. Toggle again at any time to unlock.

### Step 2 — Run Automatic Allocation

Click **Allocate** from the Allocation dropdown. A background job runs asynchronously:

1. Resets all EOI `allocation_amount` and `allocation_percentage` to zero.
2. For each **approved** EOI, calculates a proportional allocation:
   - `allocation_amount = eoi_amount × (100 / max(percentage_raised, 100))`
   - If the raise is over-subscribed (>100%), every investor receives a pro-rata haircut.
3. Saves the updated amounts.

The page shows "Allocation in progress, check back in a few minutes." Refresh after a short wait.

### Step 3 — Review and Adjust in Finalize Allocation

Click **View Allocations** from the Allocation dropdown to open the **Finalize Allocation** screen.

This shows a full table of all EOIs with inline editing. For each EOI you can set:

| Field | Description |
|-------|-------------|
| **Approved** | Check/uncheck to approve or revoke the EOI's approval |
| **Verified** | Check/uncheck to mark the EOI as verified |
| **Allocation Amount** | Override the auto-calculated allocation amount |
| **Comments** | Internal notes for this EOI |

Filter the view to **Verified**, **Un-Verified**, or **All** using the buttons at the top. Use the search box to find a specific investor by name.

Click **Save** on any row to save changes inline without leaving the page.

### Step 4 — Lock Allocations

Once allocations are finalised, click **Lock Allocations** from the Allocation dropdown. This prevents further edits to allocation amounts.

### Step 5 — Notify Investors

Send the **"Investment Opportunity Allocated: To LPs"** notification to inform investors of their final allocation.

---

## EOI Detail Page

Each EOI has its own detail page accessible via **Show** in the Interests tab. It includes:

- **Investor details** — name, email, submission date, expression amount, approval status, last updated
- **Documents tab** — files the investor or RM has attached to their EOI (e.g. signed subscription forms)
- **Tasks tab** — any tasks assigned in the context of this EOI

---

## Key Metrics on the Opportunity Detail Page

The top of the detail page shows four summary cards:

| Metric | What it represents |
|--------|--------------------|
| **Fund Raise Amount** | Target raise as configured on the opportunity |
| **Approved EOI Amount** | Sum of amounts from all approved EOIs (auto-maintained via counter cache) |
| **Valuation** | Deal valuation if configured |
| **Min Ticket Size** | Minimum per-investor investment amount |

A progress bar on the Fund Raise Amount in the summary table shows the percentage of the raise covered by approved EOIs.

---

## Frequently Asked Questions

**Q: An investor can't see the opportunity in their portal — what's wrong?**  
A: Check that the investor has been added to the opportunity's **Access Rights**. Also verify that the investor has approved portal access (`InvestorAccess` approved for their entity).

**Q: Can I edit an opportunity after investors have submitted EOIs?**  
A: Yes. Core fields (company name, amounts, dates, details) remain editable. Note that changing the fund raise amount or min ticket size may invalidate existing EOIs that were previously within range.

**Q: Why does the "Approve" option not appear for an RM-submitted EOI?**  
A: RM EOIs require a linked KYC record before they can be approved. Open the EOI, select an Investor KYC, save, then approve.

**Q: What happens if I unapprove an EOI after running allocation?**  
A: The EOI amount is removed from the `eoi_amount_cents` counter on the opportunity. Re-run **Allocate** to recalculate allocation amounts for all remaining approved EOIs.

**Q: Can an investor edit their EOI after submission?**  
A: Yes, as long as the EOI is not yet approved and EOIs are not locked. Once an EOI is approved, it cannot be edited (the policy check blocks updates on approved records).

**Q: What is the "Verified" flag for?**  
A: Verification is a manual flag for the fund manager's internal process — typically used to confirm that KYC, subscription documents, and fund transfer have been completed. It has no automatic effect on allocation calculations.

**Q: Can I share the opportunity with someone who doesn't have a portal account?**  
A: Yes. Enable **Shareable** on the opportunity. The system generates a signed link that can be given to advisors or prospective investors. They can view the full preview page without logging in. They cannot submit an EOI from that link — they would need to log in for that.

**Q: How is proportional allocation calculated when the raise is oversubscribed?**  
A: Each approved EOI receives `EOI_amount × (100 / percentage_raised)`. For example, if ₹150 Cr in EOIs were approved against a ₹100 Cr target (150% subscribed), each investor receives 66.67% of their stated EOI amount as their allocation.
