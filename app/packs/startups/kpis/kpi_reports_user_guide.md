# KPI Reports: Notifications, Uploads, and Approvals (User Guide)

This guide explains how KPI reporting notifications are sent, how portfolio company (portco) users upload KPIs from the notification email, and how approvals work after upload.

## 1) How KPI notification emails are sent

### When notifications are triggered
- An investor or admin sends a reminder for a specific portfolio company from the KPI report workflow.
- The system ensures the KPI report shell exists for the required period and enables **self‑reporting** for that report before notifying users.

### What the system does behind the scenes
1. **KPI report shell selection**
   - The system targets the **quarter‑end “Actual” KPI report** for the portfolio company.
   - If the request is sent **more than 15 days after quarter end** and the previous quarter report is still empty (no KPIs), it reuses the previous quarter shell instead.
   - This behavior is enforced by the KPI report controller when sending notifications.
2. **Self‑reporting is enabled**
   - The report is flagged to allow portco uploads (`enable_portco_upload = true`).
3. **Emails are delivered to all notification users for that portfolio company**
   - Each eligible user receives a KPI reminder email.

### What the email contains
- **Subject**: “Reminder to report KPIs for <Company> - <Report Date>”.
- **Link**: A direct link to open the KPI report edit screen.
- **Purpose**: It is a reminder and entry point for upload.

> Tip: If you do not receive the email, confirm that you are listed as a notification user for the portfolio company and that your account is active.

## 2) How portco users upload KPIs from the email

### Step‑by‑step upload flow
1. **Open the email** and click the KPI report link.
2. You will land on the **KPI report edit screen** for the relevant period.
3. Use the **upload section** to upload your KPI Excel (XLSX) file.
   - The system accepts standard KPI workbook formats used by your investor.
   - Upload completion triggers an automated workbook scan and import job.
4. After upload, your data is **staged** (not yet official). See the approval section for what happens next.

### What the system does with your upload
- The workbook is parsed and mapped against the KPI definitions assigned to your company.
- New or changed values are stored as **unapproved** records.
- If a value is identical to the current approved value, it is skipped (to avoid duplicates).
- If any parsing errors occur (missing mappings, invalid dates), the system sends an error report to the uploader via email.

## 3) How KPI approvals work after upload

### Why approvals are required
All uploaded KPI values are staged as **unapproved** so the investor/approver can review them before they become official reporting data.

### What approvers see
- By default, KPI views show **approved** data only.
- Approvers can view staged uploads by enabling **“View Including Staged”** (or by adding `?view_unapproved=true` to the KPI grid URL).
- Unapproved values are highlighted with a **“Pending”** badge and warning color.

### Approving staged KPIs
An authorized user (Approver, Company Admin, or Super user) can:
- **Approve a single KPI** (from the KPI grid view), or
- **Approve all pending KPIs** for the company at once.

During approval:
- If an approved KPI already exists for the same period and metric, it is **overwritten** by the staged value.
- If no approved KPI exists, the staged KPI is simply marked **approved**.
- Post‑approval, the system recalculates cumulative and percentage‑change metrics.

### What portco users should expect
- After upload, you may see your values marked **Pending** until approval is complete.
- Official dashboards and performance tables will **not** reflect your submitted values until approved.

## 4) Common questions

### “I uploaded KPIs but don’t see them in the dashboards.”
Your upload is likely **pending approval**. Approved data is the only data used in dashboards and performance tables.

### “Which KPI report period should I upload for?”
The reminder email link brings you directly to the correct period’s KPI report. Always start from that link to avoid uploading into the wrong period.

### “Who can approve KPIs?”
Only users with approval permissions (Approver, Company Admin, or Super) can approve staged KPI data.

---

## Reference (for administrators)
- Notification workflow: [`SendPortcoNotification`](app/packs/startups/kpis/services/send_portco_notification.rb)
- Reminder email: [`KpiReportNotifier`](app/packs/startups/kpis/mailers/kpi_report_notifier.rb) and [`KpiReportsMailer`](app/packs/startups/kpis/mailers/kpi_reports_mailer.rb)
- Approval actions: [`KpisController#approve`](app/packs/startups/kpis/controllers/kpis_controller.rb) and [`KpisController#approve_all`](app/packs/startups/kpis/controllers/kpis_controller.rb)
- KPI import & approval process: [`kpi_import_process.md`](app/packs/startups/kpis/jobs/kpi_import_process.md)
