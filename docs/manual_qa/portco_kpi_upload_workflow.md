# Manual QA: Portfolio Company KPI Upload Workflow

**Feature:** Portco self-reporting via magic link and pending dashboard
**Scope:** End-to-end workflow from fund admin sending a notification through to reviewed status

---

## Prerequisites

- Two browser sessions (or one incognito): one logged in as **Fund Admin**, one as **Portco User** (or use a magic link directly without logging in)
- A portfolio company with at least one approved user
- At least one KPI mapping configured for that portfolio company

---

## 1. Fund Admin Sends a Notification

| # | Action | Expected Result |
|---|--------|-----------------|
| 1.1 | Log in as Fund Admin, go to KPI Reports | Index page loads |
| 1.2 | Select a portfolio company and click **Send Portco Notification** | Job enqueues without error |
| 1.3 | Check the KPI report record in the admin UI | Status badge shows **Link Sent** |
| 1.4 | Check that `link_sent_at` is populated on the record | Timestamp present |
| 1.5 | Check the portco contact's inbox | Reminder email received with a magic link and expiry date shown |
| 1.6 | Re-send to the same portco immediately | Status stays **Link Sent** (does not regress); no duplicate shell created |

---

## 2. Portco User Opens the Magic Link (No Login)

| # | Action | Expected Result |
|---|--------|-----------------|
| 2.1 | Click the magic link from the email in a fresh browser (not logged in) | KPI Report edit page loads without redirect to login |
| 2.2 | Verify the status badge on the form | Shows **Link Sent** |
| 2.3 | Verify portco-facing fields are editable | KPI data, notes fields are editable |
| 2.4 | Verify fund-admin-only fields are read-only | Entity selector, tag, etc. cannot be changed |
| 2.5 | Verify two buttons are visible: **Save Draft** and **Submit Report** | Both buttons present; no admin-style "Save" button |

---

## 3. Save Draft

| # | Action | Expected Result |
|---|--------|-----------------|
| 3.1 | Enter some KPI data and click **Save Draft** | Redirects back to the **Edit** page (same signed link URL) with a success notice |
| 3.2 | Verify status badge on form | Shows **Draft Saved** |
| 3.3 | As Fund Admin, check the report | Status shows **Draft Saved** |
| 3.4 | Click **Save Draft** again without changes | Succeeds silently; status stays **Draft Saved** |
| 3.5 | Verify no email was sent to the fund team | Fund inbox has no new notification |

---

## 4. Submit Report

| # | Action | Expected Result |
|---|--------|-----------------|
| 4.1 | Click **Submit Report** | Confirmation dialog appears: "Submit this report to the fund? You will not be able to edit it after submission." |
| 4.2 | Confirm submission | Redirects to Edit page with notice "KPI report submitted. The fund team has been notified." |
| 4.3 | Verify status badge | Shows **Submitted** |
| 4.4 | Verify submitted_at timestamp is visible on the form | Timestamp present next to the badge |
| 4.5 | Verify form is now locked | Save Draft and Submit buttons replaced by a **"Report Already Submitted"** badge |
| 4.6 | Attempt to edit any field | Fields are read-only; form cannot be saved |
| 4.7 | Check Fund Admin's inbox | Notification email received: "KPIs submitted by [Company] for [date]" |

---

## 5. Double-Submit Guard

| # | Action | Expected Result |
|---|--------|-----------------|
| 5.1 | After submission, open the original magic link again | Form shows **"Report Already Submitted"** — no submit button present |
| 5.2 | Submit a second time (e.g. via back button or direct POST) | Record stays **Submitted**; fund team receives **no second notification email** |

---

## 6. Fund Admin Reviews the Submission

| # | Action | Expected Result |
|---|--------|-----------------|
| 6.1 | Log in as Fund Admin, open the submitted report | Status badge shows **Submitted** with submitted_at timestamp |
| 6.2 | Verify **Mark as Reviewed** button is visible | Button present (outside the main form) |
| 6.3 | Click **Mark as Reviewed** and confirm | Redirects to Edit page with notice "Report marked as reviewed." |
| 6.4 | Verify status badge | Shows **Reviewed** |
| 6.5 | Verify **Mark as Reviewed** button is gone | Button no longer shown for Reviewed reports |
| 6.6 | As portco user, open the same report via magic link | Still shows "Report Already Submitted" — locked |

---

## 7. Automated Reminders Skip Submitted / Reviewed Reports

| # | Action | Expected Result |
|---|--------|-----------------|
| 7.1 | Trigger `GeneratePeriodicKpiReportsJob` for a portco with status **Submitted** | No email sent; server log shows "skipping [company] — already submitted" |
| 7.2 | Trigger the same job for a portco with status **Reviewed** | No email sent; log shows "skipping [company] — already reviewed" |
| 7.3 | Trigger for a portco with status **Link Sent** or **Draft Saved** | Reminder email is sent as expected |

---

## 8. Expired / Invalid Magic Link

| # | Action | Expected Result |
|---|--------|-----------------|
| 8.1 | Tamper with the `signed_id` param in the URL | Redirects to root with alert "This link has expired or is invalid. Please request a new one." |
| 8.2 | Use a fully expired token (advance clock past 15 days in test env) | Same friendly redirect — no 500 error, no login redirect |

---

## 9. Designated KPI Contact (Kpi Tag)

| # | Action | Expected Result |
|---|--------|-----------------|
| 9.1 | Portfolio company has two approved users; add `Kpi` tag to one of them | Tag saved on user profile |
| 9.2 | Fund Admin sends a portco notification | Only the tagged user receives the reminder email |
| 9.3 | Remove the `Kpi` tag from all users at that company | Both approved users receive the next reminder |

---

## 10. Portco Pending Dashboard (Logged-In Portco User)

| # | Action | Expected Result |
|---|--------|-----------------|
| 10.1 | Log in as portco user, navigate to **KPI Reports → Pending KPI Requests** | Dashboard loads showing only their company's pending reports |
| 10.2 | Verify submitted/reviewed reports are absent | Submitted and Reviewed reports do not appear in the list |
| 10.3 | Click **Fill Report** for a pending entry | Opens the edit page for that report |
| 10.4 | Log in as a portco user from a different company | Sees only their own company's pending reports |

---

## 11. Regression — Non-KPI Notifications Unaffected

| # | Action | Expected Result |
|---|--------|-----------------|
| 11.1 | Add `Kpi` tag to a user at a portfolio company | Tag saved |
| 11.2 | Send a **document** or **capital call** notification to that portco | All approved users receive it — not just the Kpi-tagged user |

---

## Status Reference

| Status | Meaning |
|--------|---------|
| Shell Created | Report created, link not yet sent |
| Link Sent | Reminder email delivered to portco |
| Draft Saved | Portco saved progress, not yet submitted |
| Submitted | Portco clicked Submit — fund notified |
| Reviewed | Fund admin marked as reviewed |
