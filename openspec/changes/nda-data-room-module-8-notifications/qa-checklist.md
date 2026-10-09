# NDA Module 8 — Notifications & Reminders — QA Checklist

> **Audience:** QA tester running manual checks against a deployed build.
> **Companion documents:** [Proposal](proposal.md) · [Design](design.md) · [Spec](specs/)

> **Manual QA only.** This checklist is for hand-testing in a browser + email inbox.
> It does NOT replace the automated Cucumber tests.

---

## Contents

- [ID Legend](#id-legend)
- [Setup](#setup)
- [H — Happy Path](#h--happy-path)
- [E — Edge Cases](#e--edge-cases)
- [X — Error Cases](#x--error-cases)
- [J — UI Journeys](#j--ui-journeys)
- [R — Role Sweep](#r--role-sweep)
- [C — Cross-Cutting](#c--cross-cutting)
- [Sign-off](#sign-off)

---

## ID Legend

| Prefix | Meaning |
|---|---|
| H | Happy path — normal user workflow |
| E | Edge case — boundary or unusual condition |
| X | Error case — failure / recovery |
| J | UI journey — step-by-step screen check |
| R | Role sweep — access control by role |
| C | Cross-cutting — email format, dates, mobile, tenant isolation, regression |

---

## Setup

**Before testing, ensure:**
1. Log in as a GP user (e.g. `fm1@ian.com` / `password`)
2. Navigate to a Data Room folder that has NDA enabled with a PDF uploaded
3. The NDA config has notification_emails set (e.g. `ops@test.com, legal@test.com`)
4. The NDA config has a contact_email set
5. At least three investors with InvestorAccess to the entity:
   - Investor A: 3 users (User A1 as signatory, User A2, User A3), no acceptance yet (Pending)
   - Investor B: 1 user (User B1 as signatory), no acceptance yet (Pending)
   - Investor C: 1 user, marked exempt_from_nda on InvestorAccess
6. The NDA config has validity_type = "fixed_period" with validity_days = 365
7. Check your email inbox (or use a mail-catching tool like Mailhog/Mailtrap)

---

## H — Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass/Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | GP notified when LP accepts NDA | NDA config has notification_emails set. Investor A is Pending. | 1. Log in as User A1 (LP). 2. Navigate to the NDA-gated folder. 3. View and click "Accept". | ops@test.com and legal@test.com each receive an email with subject "NDA Accepted — [Investor A] on [Folder]". Email body contains investor name, folder name, NDA version, signer name, and date/time. | | |
| ☐ | H2 | LP users notified when colleague accepts | Investor A has 3 users. User A1 is the signer. | 1. (Continuing from H1 — User A1 has accepted.) 2. Check inbox for User A2 and User A3. | User A2 and A3 each receive email with subject "NDA Access Granted — [Folder]". Email contains folder name, who signed, date/time, and a link to the folder. User A1 does NOT receive this email. | | |
| ☐ | H3 | GP revokes accepted investor | Investor A has status Accepted (from H1). | 1. Log in as GP. 2. Go to NDA Status Dashboard. 3. Click "Revoke" next to Investor A. 4. Enter "Deal terminated" as reason. 5. Click "Revoke Access". | Investor A status changes to "Revoked" on the dashboard. Reason column shows "Deal terminated". User A1, A2, A3 each receive email with subject "NDA Access Revoked — [Folder]". Email mentions folder name and contact_email. | | |
| ☐ | H4 | GP sends bulk reminders | Investor B is Pending. User B1 is signatory. | 1. Log in as GP. 2. Go to NDA Status Dashboard. 3. Click "Send Reminders". 4. Confirm dialog shows "Send NDA reminders to X pending investors (Y NDA-tagged users)?". 5. Click "Send Reminders". | Flash message: "Reminders sent to X users". User B1 receives email with subject "NDA Reminder — [Folder]". Email contains folder link and contact_email. | | |
| ☐ | H5 | Expiry approaching alert (7 days) | Investor A accepted 358 days ago (7 days to expiry). Ask developer to adjust accepted_at or use time travel. | 1. Ask developer to run NdaExpiryCheckJob (`NdaExpiryCheckJob.perform_now` in console). | ops@test.com and legal@test.com receive "NDA Expiring Soon — [Investor A] on [Folder]". User A1 (signatory) receives same. Email contains investor name, folder name, and expiry date. | | |
| ☐ | H6 | Expired alert | Investor A accepted 365 days ago (expiry today). | 1. Ask developer to run NdaExpiryCheckJob. | ops@test.com and legal@test.com receive "NDA Expired — [Investor A] on [Folder]". User A1 receives same. Email contains investor name, folder name, and expiry date. | | |

---

## E — Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass/Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | No notification_emails configured | NDA config has notification_emails blank. | 1. Log in as LP. 2. Accept the NDA. | No GP email sent. LP users of the investor still receive the acceptance confirmation. | | |
| ☐ | E2 | Investor has only one user | Investor B has only User B1. | 1. Log in as User B1. 2. Accept the NDA. | No LP confirmation email sent (B1 is the signer and there are no other users). GP notification_emails still receive accept email. | | |
| ☐ | E3 | Revoke unavailable for Pending | Investor B is Pending. | 1. Log in as GP. 2. Go to NDA Status Dashboard. 3. Look at Investor B row. | No "Revoke" button visible for Investor B. | | |
| ☐ | E4 | Revoke without reason | Investor A is Accepted. | 1. Log in as GP. 2. Click "Revoke" on Investor A. 3. Leave reason empty. 4. Confirm. | Status changes to "Revoked". Reason column is blank. Revocation email still sent to LP users. | | |
| ☐ | E5 | No pending investors for reminders | All investors are Accepted or Exempt. | 1. Log in as GP. 2. Go to NDA Status Dashboard. | "Send Reminders" button is disabled or message says "No pending investors to remind". | | |
| ☐ | E6 | Exempt investor excluded from reminders | Investor C is exempt. | 1. Log in as GP. 2. Click "Send Reminders". | Investor C's users do NOT receive a reminder email. Only non-exempt Pending investors' signatories are emailed. | | |
| ☐ | E7 | Duplicate expiry alert prevented | Approaching alert already sent for Investor A. | 1. Run NdaExpiryCheckJob once (alert sent). 2. Run NdaExpiryCheckJob again. | No duplicate email sent. Only the first run sends the alert. | | |
| ☐ | E8 | Version bump notifies stale acceptances | Investor A accepted v1. Investor B is Pending. | 1. Log in as GP. 2. Go to NDA Settings. 3. Upload a new NDA PDF. 4. Save. | Investor A users receive email "NDA Updated — [Folder]" with old version (1) and new version (2), plus a link. Investor B (Pending) does NOT receive a version change email. | | |

---

## X — Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass/Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | LP acceptance not delayed by notifications | notification_emails set. | 1. Log in as LP. 2. Accept the NDA. 3. Observe redirect timing. | Redirect to folder happens immediately (no visible delay). Emails arrive in background (may take a few seconds). | | |
| ☐ | X2 | Expiry job failure does not affect already-sent alerts | Multiple entities with NDAs. | 1. Ask developer to run NdaExpiryCheckJob. 2. If one entity errors, others still process. | Alerts for successfully processed entities are sent. Failed entity does not block others. Check logs for per-entity error. | | |

---

## J — UI Journeys

### J1 — GP views dashboard and sends reminders

| ☐ | ID | Step | Expected result | Pass/Fail | Notes |
|---|---|---|---|---|---|
| ☐ | J1.1 | Log in as GP. Navigate to a Data Room folder with NDA enabled. Click "NDA Status" to open the dashboard. | Dashboard loads. Status counters show (e.g. "Accepted: 1 Pending: 2 Declined: 0 Revoked: 0 Exempt: 1"). "Revoked" counter is visible. | | |
| ☐ | J1.2 | Look at the dashboard table columns. | Table shows: Investor, Status, Signed By, Date, Reason, Actions. "Reason" column is new. | | |
| ☐ | J1.3 | Look at the toolbar. | "Send Reminders" button is visible next to "Export". | | |
| ☐ | J1.4 | Click "Send Reminders". | Confirmation dialog appears: "Send NDA reminders to X pending investors (Y NDA-tagged users)?". Cancel and Send Reminders buttons shown. | | |
| ☐ | J1.5 | Click "Cancel" on the dialog. | Dialog closes. No reminders sent. | | |
| ☐ | J1.6 | Click "Send Reminders" again, then confirm. | Flash message: "Reminders sent to Y users". Dialog closes. | | |

### J2 — GP revokes an accepted investor

| ☐ | ID | Step | Expected result | Pass/Fail | Notes |
|---|---|---|---|---|---|
| ☐ | J2.1 | On the dashboard, find an investor with "Accepted" status. | "Revoke" button/link is visible in the Actions column. | | |
| ☐ | J2.2 | Click "Revoke". | Dialog appears: "Revoke NDA Acceptance. Are you sure you want to revoke the NDA acceptance for [Investor Name]? All users will lose access to this folder until the NDA is re-accepted. Reason (optional): [text field]. Cancel / Revoke Access buttons." | | |
| ☐ | J2.3 | Click "Cancel" on the dialog. | Dialog closes. Investor remains "Accepted". | | |
| ☐ | J2.4 | Click "Revoke" again. Enter "Compliance review" as reason. Click "Revoke Access". | Investor status changes to "Revoked". Reason column shows "Compliance review". "Revoke" button disappears for this investor. | | |
| ☐ | J2.5 | Check that a Revoked investor can re-accept. Log in as LP user of the revoked investor. Navigate to the folder. | NDA acceptance screen is shown (same as first-time visitor). | | |
| ☐ | J2.6 | Accept the NDA as the revoked investor's user. | Investor status returns to "Accepted" on the dashboard. | | |

### J3 — LP accepts and receives confirmation

| ☐ | ID | Step | Expected result | Pass/Fail | Notes |
|---|---|---|---|---|---|
| ☐ | J3.1 | Log in as LP User A1 (signatory of Investor A with 3 users). Navigate to NDA-gated folder. | NDA acceptance screen shown with PDF and Accept/Decline buttons. | | |
| ☐ | J3.2 | Click "Accept". | Redirected to the folder contents. No delay. | | |
| ☐ | J3.3 | Check User A1's inbox. | User A1 does NOT receive a confirmation email (they are the signer). | | |
| ☐ | J3.4 | Check User A2's inbox. | User A2 receives "NDA Access Granted — [Folder]" email with folder name, signer name, date, and folder link. | | |
| ☐ | J3.5 | Check GP inbox (notification_emails). | ops@test.com receives "NDA Accepted — [Investor A] on [Folder]" email. | | |

### J4 — LP declines NDA

| ☐ | ID | Step | Expected result | Pass/Fail | Notes |
|---|---|---|---|---|---|
| ☐ | J4.1 | Log in as LP user of a Pending investor. Navigate to NDA-gated folder. Click "Decline". | Decline confirmation screen shown. | | |
| ☐ | J4.2 | Check GP inbox. | notification_emails receive "NDA Declined — [Investor] on [Folder]" email. | | |
| ☐ | J4.3 | Check LP user's inbox. | LP user does NOT receive a decline notification. | | |

---

## R — Role Sweep

| ☐ | ID | Role | Action | Expected | Pass/Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | R1 | GP (entity employee) | Access NDA Status Dashboard | Allowed — dashboard loads | | |
| ☐ | R2 | GP (entity employee) | Click "Revoke" on accepted investor | Allowed — dialog appears | | |
| ☐ | R3 | GP (entity employee) | Click "Send Reminders" | Allowed — dialog appears | | |
| ☐ | R4 | LP (investor user) | Try to access NDA Status Dashboard URL directly | Denied — redirected or 403 | | |
| ☐ | R5 | LP (investor user) | Try to POST to revoke URL directly | Denied — 403 or redirect | | |
| ☐ | R6 | LP (investor user) | Try to POST to send_reminders URL directly | Denied — 403 or redirect | | |
| ☐ | R7 | GP from different entity | Try to access another entity's NDA Status Dashboard | Denied — cannot see other entity's NDA data | | |

---

## C — Cross-Cutting

| ☐ | ID | What to check | Steps | Expected result | Pass/Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | C1 | Email date format | Trigger any NDA notification email. | All dates in emails render in "Mon dd, yyyy" format (e.g. "Oct 06, 2026"), not raw timestamps. | | |
| ☐ | C2 | Dashboard date format | View NDA Status Dashboard with revoked and accepted investors. | All dates use the locale format (e.g. "06 Oct 2026"), not raw timestamps or ISO format. | | |
| ☐ | C3 | Mobile width — dashboard | Open NDA Status Dashboard on a narrow viewport (≤ 480px). | Table is scrollable or columns stack. "Send Reminders" and "Export" buttons are accessible. No horizontal page scroll (table scrolls independently). | | |
| ☐ | C4 | Mobile width — revoke dialog | Open revoke confirmation dialog on narrow viewport. | Dialog is readable. Reason text field and buttons are accessible. Dialog doesn't overflow the screen. | | |
| ☐ | C5 | Tenant isolation — dashboard | Log in as GP of Entity A. Open NDA Status Dashboard. Note investors shown. Log in as GP of Entity B. Open NDA Status Dashboard. | Entity B cannot see Entity A's investors, NDA configs, or notification recipients. | | |
| ☐ | C6 | Tenant isolation — emails | Trigger NDA accept for Entity A. | Only Entity A's notification_emails receive the email. No cross-entity email leakage. | | |
| ☐ | C7 | XLSX export includes reason | Revoke an investor with reason "Test reason". Export XLSX from dashboard. | XLSX contains a "Reason" column. Revoked investor's row shows "Test reason". Other rows have blank reason. | | |
| ☐ | C8 | Regression — NDA acceptance flow | Accept an NDA as LP. | NDA acceptance flow works as before (redirect to folder, PDF shown, Accept/Decline buttons). No change to existing behavior. | | |
| ☐ | C9 | Regression — NDA settings form | Edit NDA config settings (change contact_email, toggle validity). | Settings form saves correctly. notification_emails field works as before. Version does not change unless PDF is replaced. | | |
| ☐ | C10 | Regression — NDA dashboard existing features | View dashboard, tag/untag signatory, export XLSX. | All existing dashboard features work: status counters, signatory tagging, XLSX export (now with reason column). | | |
| ☐ | C11 | Regression — NDA gate | Visit NDA-gated folder as LP with no acceptance. | NDA acceptance screen shown. Gate behavior unchanged. | | |

---

## Sign-off

| Tester | Build / Commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | <!-- Pass / Fail --> | |
