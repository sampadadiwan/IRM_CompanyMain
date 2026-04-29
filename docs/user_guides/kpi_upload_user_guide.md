# KPI Management & Workbook Upload User Guide (V9.1.86)

This guide provides a comprehensive overview of the Key Performance Indicator (KPI) reporting system in IRM. It covers everything from preparing your Excel workbooks to the automated approval workflows.

## 📑 Table of Contents
1. [Key Takeaways](#-key-takeaways)
2. [Roles & Permissions](#-roles--permissions)
3. [The Reporting Workflow](#-the-reporting-workflow)
4. [Workbook Preparation Checklist](#-workbook-preparation-checklist)
5. [Supported Date Formats](#-supported-date-formats)
6. [Automated System Actions](#-automated-system-actions)
7. [Common Pitfalls & Troubleshooting](#-common-pitfalls--troubleshooting)
8. [FAQ](#-faq)

---

## 🚀 Key Takeaways
*   **Two-Stage Process**: Data is first **Staged** (Unapproved) and then **Promoted** (Approved) by an authorized user.
*   **Approved Data Only**: Dashboards, performance tables, and growth calculations only use **Approved** data.
*   **Smart Matching**: The system skips identical values to avoid duplicates and flags changes for review.
*   **Automated Calculations**: Quarterly, YTD, and Annual totals are automatically recalculated upon approval.
*   **Direct Links**: Portfolio companies should use the link in their reminder email to upload directly to the correct period.

---

## 👥 Roles & Permissions
The KPI system ensures data integrity through role-based access:

| Role | Permissions |
| :--- | :--- |
| **Fund Admin / Approver** | Full access. Can create reports, approve staged data, trigger recomputations, and send notifications. |
| **Portfolio Company User** | Can upload workbooks for their specific company and edit their own reports via secure links. |
| **Advisor / Read-Only** | Can view approved reports and dashboards but cannot modify data or approve uploads. |

---

## 🔄 The Reporting Workflow

### 1. Notification & Request
The process typically begins when a Fund Admin sends a reminder to a Portfolio Company.
*   **Self-Reporting**: The system enables "Self-Reporting" for the specific period.
*   **Reminder Email**: The company receives an email with a direct link to the upload portal.

### 2. Staged Import (The Upload)

When a workbook is uploaded, the system performs a "Staged Import":

```
sequenceDiagram
    participant U as User
    participant J as Import Job
    participant R as Workbook Reader
    participant DB as Database

    U->>DB: Upload Workbook
    DB->>J: Enqueue Import Job
    J->>R: Scan Sheets & Extract KPIs
    loop Every Data Row
        R->>DB: Compare with Approved Data
        alt Value Changed or New
            R->>DB: Create UNAPPROVED (Staged) Record
        else Value Identical
            R->>R: Skip (No Change)
        end
    end
    J->>U: Notify: Import Completed (Pending Approval)
```

### 3. Authorized Approval

An Admin reviews the staged data. Unapproved values are highlighted in **orange** with a **"Pending"** badge in the KPI Grid View.

```
sequenceDiagram
    participant A as Approver
    participant S as Approval Service
    participant DB as Database
    participant J as Calculation Jobs

    A->>S: Approve KPI(s)
    S->>DB: Promote Staged to Approved
    S->>DB: Overwrite Old Approved Data
    S->>J: Trigger Cumulative & % Change Recalcs
    S->>A: Success Confirmation
```

---

## 📋 Workbook Preparation Checklist

### 1. Structure & Layout
*   **Header Detection**: The system scans the first 10 rows to find your date headers (e.g., "Jan 2024").
*   **Header Requirement**: A valid header row must contain at least **two** date-like values.
*   **KPI Column**: Place KPI names in the first column. The system matches these against your configured "Reported KPI Names."
*   **Data Rows**: Values should be directly beneath the header row.

### 2. KPI Naming
*   **Smart Matching**: Names are matched case-insensitively and space-insensitively (e.g., "Gross Profit" matches "gross profit").
*   **Consistency**: Ensure names match the "Reported KPI Names" in your mapping settings.

### 3. Data Integrity
*   **Numeric Only**: Ensure values are numbers. Use `na` or `n/a` for non-applicable fields.
*   **No Duplicates**: Avoid duplicate period headers (e.g., two "Jan 2024" columns) in the same sheet.
*   **Future Dates**: Values for future dates are automatically skipped for "Actual" tags.

---

## 📅 Supported Date Formats
Your column headers should use one of these recognized formats:

| Type | Examples |
| :--- | :--- |
| **Monthly** | `Jan 2024`, `January 2024`, `Sep 23` |
| **Quarterly** | `Q1 FY24`, `Q3 CY22`, `Jan-Mar 2024`, `JFM 2024` |
| **Annual** | `FY 2023-24`, `FY2024`, `CY2024`, `2024` |
| **Half-Year** | `H1 2023`, `H2 FY24` |
| **YTD** | `YTD Nov 23`, `YTD Jan-Sept 2023` |
| **Standard** | `DD-MM-YYYY`, `DD/MM/YYYY` |

---

## ⚙️ Automated System Actions
After approval, the system automatically triggers several high-impact tasks:
1.  **Growth Metrics**: Recalculates Year-on-Year (YoY) and Month-on-Month (MoM) percentage changes.
2.  **Cumulative Totals**: Recomputes **Quarterly**, **YTD**, and **Annual** sums based on monthly data.
3.  **Audit Trail**: Appends approval details (User, Timestamp) to the KPI notes.
4.  **Search Indexing**: Updates the search engine so new data is immediately findable.

---

## 🛠️ Common Pitfalls & Troubleshooting

### 1. "No Date Headers Found"
*   **Cause**: The system couldn't find at least two date-like values in the first 10 rows.
*   **Fix**: Ensure your headers use supported formats (e.g., "Jan 2024") and are not buried deep in the sheet.

### 2. "KPI Name Not Mapped"
*   **Cause**: The KPI name in Excel doesn't match any "Reported KPI Name" in the system.
*   **Fix**: Check your mapping settings or update the Excel file to use the correct name.

### 3. "Value Skipped (Identical)"
*   **Cause**: The value in Excel is exactly the same as the currently approved value.
*   **Fix**: No action needed. The system does this to save time and avoid redundant approvals.

### 4. "Future Date Skipped"
*   **Cause**: You are uploading "Actual" data for a date that hasn't occurred yet.
*   **Fix**: Use the "Budget" or "Projected" tag if you are uploading future-looking data.

---

## ❓ FAQ

**Q: I uploaded my KPIs, but the dashboard hasn't updated. Why?**
A: Your data is likely in the **Staged (Unapproved)** state. Dashboards only reflect **Approved** data. Contact your Fund Admin to review and approve the upload.

**Q: How do I see my "Pending" data?**
A: In the **KPI Grid View**, authorized users can enable **"View Including Staged"** to see unapproved values highlighted in orange.

**Q: What happens if I upload the same file twice?**
A: The system checks for identical values. If the data hasn't changed, it will skip the import for those specific KPIs to avoid redundant approvals.

**Q: Can I upload data for multiple companies in one workbook?**
A: No. Each upload is scoped to a specific Portfolio Company to ensure data security and correct mapping.

**Q: The system didn't recognize my date headers. What should I do?**
A: Ensure your dates are in one of the supported formats (see Section 5) and are located within the first 10 rows of the sheet.

---
*For technical support or custom KPI mapping, please contact your system administrator.*
