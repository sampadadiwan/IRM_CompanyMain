# Security Hardening — Release Notes

**Release:** Security Hardening pass · **Date:** 10 July 2026

---

## What this release is

This is a **security hardening** release. It contains **no new features** and **does not change how
you do your day-to-day work** — the screens, buttons, and workflows are the same.

What it does is make the platform safer by tightening five things:

1. **Login links** are harder to misuse.
2. **Each client organization's data stays strictly separate** from every other organization.
3. **Only the right people** can approve documents, publish them, or grant access to data.
4. **Advanced formula and note fields** reject unsafe entries.
5. **Shared and login links expire**, so a forwarded or leaked link can't be used forever.

Most of these changes are invisible in normal use. This document explains, in plain terms, **what
changed, why it matters, and how to check that it works**.

> **Tip for testers:** For the "keep organizations separate" checks below, you'll need two test
> organizations (call them **Organization A** and **Organization B**) with some data in each, and an
> admin login for A. The idea in each test is: while logged in to A, try to reach B's data — and
> confirm you can't.

---

## 1. Safer login links

**What changed**

- The link an admin/support user uses to **"log in as" a client** now only works for the admin who
  is already logged in. If that link is ever seen by anyone else, it can't be used to get into the
  account.
- The login link sent over **WhatsApp** now **expires after 1 minute**.
- Login links can **only be used to log in** — they can no longer be reused for any other purpose.

**Why it matters**

Prevents someone who happens to see a login link (in an activity log, chat history, browser history,
or a shared screen) from using it to get into an account.

**How to test**

- **Email login (should work as before):** On the login page, choose the "log in without password"
  option, enter your email, then open the link in your inbox → you should be signed in. Wait past the
  stated expiry time and click the same link again → it should say the link is invalid.
- **"Log in as" a client (should work as before):** As an admin who is set up to support a client,
  open that client's user record and click the **Login** button → you should be signed in as them.
- **Leaked-link check (should now fail):** If you copy the "Login" action and try to open it while
  **not** logged in, it should **not** sign you in.

---

## 2. Stronger protection against password guessing

**What changed**

Repeated failed login attempts for the same email address are now correctly slowed down, and simply
being logged in no longer lets someone bypass those limits.

**Why it matters**

Makes automated password-guessing attacks much harder.

**How to test**

> Note: these limits are **switched off in test environments**, so this can only be checked in a
> staging or production-like environment.

Attempt many rapid failed logins for a single email address → after a number of attempts you should
start seeing a "rate limit exceeded / try again later" response.

---

## 3. Keeping each organization's data separate

**What changed**

Across **funds, reports, documents, investor records, and access grants**, the platform now strictly
prevents viewing, creating, editing, or moving records that belong to a **different** client
organization — even if someone tampers with a web address or a form. Specifically:

- **Portfolio investment reports** can only be generated for **your own** funds.
- **Fund formulas** can only be copied from a fund you're allowed to see. (Support staff may copy
  across organizations to help clients; regular users only within their own organization.)
- **Funds, documents, and investor records** can no longer be moved to another organization by
  editing them.
- **Fund analytics, email recipient lists, and notifications** only work with your own fund's data.
- **Shared-document lists** only show your own organization's shares.
- **Report links** can no longer be manipulated to open an unintended page.

**Why it matters**

This is the core "your data stays yours" guarantee between the different client organizations that
share the platform.

**How to test**

1. Log in as an **admin of Organization A**.
2. Identify a record that belongs to **Organization B** (for example a fund, a report, or a
   document) and note its ID from B's web address.
3. While still logged in as A, try to open or act on **B's** record by changing the ID in the web
   address to B's → you should get a **"Not Found"** or **"not accessible"** message, and **none of
   B's information should appear**.
4. Confirm your **own** organization's funds, reports, and documents still open and work normally.

---

## 4. Document approvals and public visibility

**What changed**

- A document can only be **approved** by someone with the **approver** role. It can no longer be
  approved by any other route.
- Only **company admins** can mark a document as **publicly visible**. The "Allow Public Visibility"
  option is now hidden for everyone else.
- A **newly created** document always starts as **not approved** and **not public**.

**Why it matters**

Preserves the document approval process and prevents documents being exposed more widely than
intended.

**How to test**

- As an **approver**, open a document that is pending approval and click **Approve** → it becomes
  approved and records who approved it.
- As a **non-approver**, you should **not** be able to approve a document.
- As a **non-admin**, the "Allow Public Visibility" option should **not** appear when you edit a
  document. As an **admin**, it should appear.

---

## 5. Granting investor access

**What changed**

- Only **company admins** can **grant or approve** investor access.
- A person can still **request** access for themselves, but a request always starts as **not
  approved** — you cannot approve your own request.
- An existing access grant can no longer be silently switched to a different organization, investor,
  or person by editing it.

**Why it matters**

Keeps control over who can see investor data in the hands of the right administrators.

**How to test**

- As a **company admin**, grant and approve access for a user → it works.
- As a **regular employee**, you should **not** be able to grant or approve access.
- As an **investor-side user**, submit an access request → it appears as **pending**, waiting for an
  admin to approve.

---

## 6. Safer formula and note fields

**What changed**

Fields that accept **calculation formulas** or **fee notes** now reject entries that contain
data-changing or system commands.

**Why it matters**

Prevents misuse of these advanced fields.

**How to test**

- In a **fund formula** or a **call/distribution fee note**, try saving text that includes a blocked
  word (for example a database or system command) → it should be **rejected** with a message.
- Confirm that **normal financial formulas** (numbers, the usual field names, and math) still save as
  before.

---

## 7. Shared document links expire

**What changed**

Links that share a document with an external recipient now **expire after 30 days**.

**Why it matters**

A forwarded or leaked share link can't be used indefinitely.

**How to test**

- Share a document to an email address and open the link → the document opens normally.
- (Links older than 30 days will show a **"Not Found"** page.)

---

## Still to confirm — not included in this release

One item is intentionally **left for your decision**: the incoming-notification endpoints used by
**WhatsApp** and the **e-signature provider** do not yet verify that a message genuinely came from
that provider. Closing this needs confirmation of which providers to verify against and how. Until
then, treat those incoming notifications as not fully trusted.

---

## What has **not** changed

- **No change** to your daily workflows, screens, or where you click.
- **Admins keep** their existing ability to manage their own organization's users and permissions.
- **Support staff keep** the cross-organization access they need to help clients — and that access
  continues to be recorded for auditing.

---

## How this release was checked

Beyond manual review, the changes were verified with the platform's **automated test suite**,
including:

- Email and WhatsApp login flows (including two-step verification).
- Shared-document viewing and link expiry.
- The "keep organizations separate" rules for funds, documents, reports, and shared items.
- The approval, publish, and investor-access permission rules.
- A dedicated set of new automated checks covering the items in this release.

All of these checks passed.
