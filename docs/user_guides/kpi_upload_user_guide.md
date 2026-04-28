# KPI Management & Workbook Upload User Guide

To ensure your KPI data is processed accurately and without errors, please follow these guidelines for managing reports and preparing your Excel workbooks for upload.

## 👥 Roles & Permissions
The KPI management system is role-based to ensure data integrity:

| Role | Permissions |
| :--- | :--- |
| **Fund Admin** | Full access to create, edit, approve, and delete all KPI reports. Can trigger recomputations and send notifications to companies. |
| **Portfolio Company (User)** | Can view and edit their own reports (typically via a secure signed link). Can upload workbooks for their specific company. |
| **Advisor / Read-Only** | Can view approved KPI reports and performance dashboards but cannot modify data or trigger recomputations. |

## 🖥️ Screen Reference

### 1. KPI Reports Index (`/kpi_reports`)
The main dashboard for managing and tracking all KPI submissions.
*   **Data Displayed**: A list of reports showing the Portfolio Company, Period (Month/Quarter/YTD), As Of date, Tags (Actual/Budget), and Status.
*   **Key Buttons & Actions**:
    *   **New KPI Report**: Create a manual entry or start a new workbook upload shell.
    *   **Filter/Search**: Filter reports by Tag (e.g., only "Actual"), Period, or specific Portfolio Companies.
    *   **Send Notifications**: Opens a modal to send email/WhatsApp reminders to one or many Portfolio Companies to upload their data.
    *   **Grid View**: Switches to a compact view highlighting data coverage across companies.

### 2. KPI Report Detail View (`/kpi_reports/:id`)
A deep dive into a specific submission for a company and period.
*   **Data Displayed**: Detailed table of all KPIs (Revenue, EBITDA, etc.), including their values, notes, and calculated percentage changes (MoM, YoY).
*   **Key Buttons & Actions**:
    *   **Edit**: Modify individual KPI values or notes manually.
    *   **Recompute % Change**: Manually trigger a recalculation of the growth metrics for this report.
    *   **Recompute Cumulative**: Force the system to recalculate Quarterly and YTD sums for the company (useful after data corrections).
    *   **Analyze**: Triggers an AI-driven analysis to identify trends or anomalies in the data.
    *   **Upload Document**: Attach the source Excel/PDF file to the report for audit trails.

### 3. Performance Table (`/kpi_reports/show_performance`)
A high-level comparison view across periods.
*   **Data Displayed**: A comparative table showing KPI performance for a specific company over multiple months or quarters.
*   **Key Buttons & Actions**:
    *   **Download XLSX**: Export the performance table to Excel for offline reporting.

---

## 📋 KPI Upload Checklist

### 1. Workbook Structure & Layout
*   **Header Identification:** The system scans the first row of each sheet to find the header. Ensure your date headers (e.g., "Jan 2024", "Q1 FY24") are within these top 10 rows.
*   **Header Row Requirement:** A valid header row must contain at least **two** date-like values to be recognized.
*   **KPI Name Column:** Place your KPI names in one of the first column. The system automatically detects which column contains the KPI names by matching them against your configured target KPIs.
*   **Data Rows:** KPI values should be placed in the rows directly beneath the identified header row.

### 2. KPI Naming
*   **Matching:** KPI names are matched using a case-insensitive and space-insensitive method (e.g., "Gross Profit" will match "gross profit" or "GrossProfit").
*   **Consistency:** Ensure the KPI names in your Excel file exactly match the "Reported KPI Names" configured in your mapping settings.

### 3. Supported Period (Date) Formats
Your column headers should use one of the following recognized formats:
*   **Monthly:** `Jan 2024`, `January 2024`, `Sep 23`.
*   **Quarterly:** `Q1 FY24`, `Q3 CY22`, `JFM 2024` (Jan-Feb-Mar), `Jan-Mar 2024`.
*   **Fiscal/Calendar Year:** `FY 2023-24`, `FY2024`, `CY2024`, or just `2024`.
*   **Half-Year:** `H1 2023`, `H2 FY24`.
*   **Year-to-Date (YTD):** `YTD Nov 23`, `YTD Jan-Sept 2023`.
*   **Standard Dates:** `DD-MM-YYYY` or `DD/MM/YYYY`.

### 4. Data Values
*   **Numeric Values:** Ensure KPI values are numeric.
*   **Empty Cells:** Blank cells are skipped. If a KPI is not applicable for a period, you can leave it blank or use `n/a` or `na`.
*   **Duplicates:** Avoid having duplicate period headers (e.g., two columns both labeled "Jan 2024") in the same sheet, as the system will skip the duplicates.
*   **Precision & Matching:** If an identical value (checked to 6 decimal places) is already approved in the system, the upload will skip that specific entry to avoid redundant updates.

### 5. Automated System Actions & Side Effects
After a successful upload, the system automatically performs several background tasks:
*   **KPI Approval Workflow:** Newly uploaded values are created as **Unapproved**. If a value differs from an existing approved record, it will trigger a pending approval notification.
*   **Percentage Change Calculation:** The system automatically recalculates Year-on-Year and Month-on-Month percentage changes for all KPIs related to the Portfolio Company.
*   **Cumulative Recalculation:** The system triggers a recalculation of **Quarterly**, **YTD**, and **Year** (Annual) cumulative records based on the newly imported monthly data.
*   **Search Indexing:** The system updates search indexes (via Chewy/Sidekiq) to ensure the new data is searchable immediately.

### 6. Notifications
*   **Success/Error Summary:** Users receive an email summary of the import. If errors occur (e.g., missing KPIs, unrecognized date formats), a detailed report is sent via email.
*   **Approval Alerts:** Admins are notified if new data requires review/approval.

### 7. Common Pitfalls to Avoid
*   **Hidden Rows/Columns:** While the system attempts to clean the file, it's best to avoid hidden rows or columns that might contain "ghost" data.
*   **Future Dates:** "Actual" values for future dates (beyond the current day) are automatically skipped.
*   **Missing Target KPIs:** Ensure all KPIs mapped for the Portfolio Company are present in the workbook; the system will flag any missing target KPIs in the error report.
*   **Invalid Characters:** Avoid using special characters or non-numeric text in cells designated for KPI values (other than `na` or `n/a`).
*   **Sheet Selection:** The system processes **all sheets** in the workbook. Ensure all sheets follow the supported layout or do not contain conflicting data.
