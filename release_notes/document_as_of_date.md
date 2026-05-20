# Document "As Of" Date

## What Changed

Every document in CapHive now has an optional **As Of Date** field. This is the business date a document *applies to* — for example, 31 March 2025 for a Q1 investor statement, or 15 April 2025 for a capital call notice due on that date.

The **Date column** in the document grid now shows the As Of Date when one is set. If no As Of Date is set, the upload date is shown as before. This applies in both the GP view and the LP (investor) view.

---

## Why It Matters

Previously, the document grid only showed when a file was uploaded to the system. This made it hard to answer questions like:

- "Which document is my March 2025 statement?"
- "Was the April call notice for the correct call date?"

The As Of Date separates *when the document was generated* from *what period it covers*, making document lists meaningful at a glance.

---

## How It Works

### For manually uploaded documents

An **As Of Date** field is now available in the document upload form. You can optionally set it when uploading any document. Leave it blank if the document is not tied to a specific business date.

### For system-generated documents

When CapHive generates a document automatically (call notices, distribution notices, investor statements, fund reports, portfolio reports), the As Of Date is set by the system with no manual action required:

| Document | As Of Date |
|---|---|
| Capital Call Notice | Date of the capital call (remittance date) |
| Distribution Notice | Date of the distribution payment |
| Investor Statement — commitment level | End date of the statement period |
| Investor Statement — KYC level | End date of the statement period |
| Fund Report | End date of the reporting period |
| Portfolio Report | End date of the reporting period |
| Commitment Agreement | Not set (upload date shown) |
| EOI / SPA / Secondary Sale documents | Not set (upload date shown) |

Commitment agreements and secondary-market SPAs are point-in-time execution documents rather than period-based reports, so their As Of Date is intentionally left blank.

---

## What Investors See

Investors see a simplified document list showing only the document name and its date. With the As Of Date in place, an investor's statement folder now looks like:

| Document | Date |
|---|---|
| Q1 2025 Investor Statement – Acme Capital | 31 Mar 2025 |
| Q4 2024 Investor Statement – Acme Capital | 31 Dec 2024 |
| Capital Call Notice – Call 3 | 15 Apr 2025 |

Rather than a list of upload timestamps that carry no business meaning.
