Good — that actually simplifies the design and keeps your system consistent. Instead of inventing a new `InvestorEmail` model, the PRD should **reuse `IncomingEmail` and extend its usage to support investor filing**.

Below is the **revised PRD aligned with your existing Rails architecture**.

---

# Product Requirements Document

## Feature: Outlook Email Filing to Investor Records

---

# 1. Overview

Fund managers frequently communicate with investors through email. Important discussions about capital calls, distributions, reporting, compliance, and documentation occur in inboxes but are not systematically stored inside CapHive.

This feature introduces an **Outlook Add-in that allows users to file emails under investors directly from Outlook**.

Emails will be matched to investors based on **email addresses stored in `InvestorAccess.email`**, and the email will be stored using the existing **`IncomingEmail` model**.

---

# 2. Goals

### Primary Goals

1. Allow Outlook users to **file emails into CapHive under investors**.
2. Automatically match emails using **`InvestorAccess.email`**.
3. Store the email inside the **existing `IncomingEmail` model**.
4. Provide a **central communication history for investors**.

### Secondary Goals

* Enable searchable investor communication history
* Improve collaboration across fund teams
* Provide audit traceability of investor interactions

---

# 3. Non-Goals

Initial version will **not include**:

* Automatic ingestion of all mailbox emails
* AI-based matching or inference
* Email reply capability from CapHive
* Thread-level grouping

The feature is strictly **manual filing from Outlook**.

---

# 4. Users

Primary users:

* Fund managers
* Investor relations teams
* Fund operations teams

Secondary users:

* Compliance teams
* Fund administrators

---

# 5. Problem Statement

Investor communication lives in personal inboxes and is not visible within CapHive.

Consequences:

* Lack of centralized investor communication records
* Operational context is lost
* Hard to track discussions historically
* Difficult for teams to collaborate on investor relationships

---

# 6. Proposed Solution

Create an **Outlook Add-in** that allows users to:

1. Open an email
2. Click **"File to CapHive"**
3. CapHive identifies the investor automatically
4. User confirms or overrides the match
5. Email is stored in **`IncomingEmail`**

---

# 7. Key Matching Logic

Investor matching will use the **InvestorAccess table**.

Relationship:

```
Investor
  has_many InvestorAccess
       email
```

Example:

Investor: **ABC Family Office**

InvestorAccess emails:

```
john@abcfo.com
assistant@abcfo.com
legal@abcfo.com
```

Matching occurs if the email appears in:

* sender
* to
* cc

---

# 8. User Workflow

### Step 1 — User Opens Email

Example email:

```
From: john@abcfo.com
To: fundmanager@fund.com
Subject: Capital call question
```

---

### Step 2 — Launch Add-in

User clicks:

```
File to CapHive
```

---

### Step 3 — Extract Email Data

The Outlook add-in extracts:

* sender email
* recipient emails
* cc emails
* subject
* email body
* attachments
* timestamp
* message ID

---

### Step 4 — Backend Matching

Add-in sends metadata to CapHive API.

Matching rule:

```
emails = [from_email] + to_emails + cc_emails

# Filter by approved accesses only
InvestorAccess.approved.where(email: emails)
```

---

### Step 5 — Match Result

Three possible outcomes.

---

### Case 1 — Single Match

Response:

```
Matched Investor: ABC Family Office
Reason: sender email matched InvestorAccess.email
Confidence: High
```

User confirms filing.

---

### Case 2 — Multiple Matches

Example:

```
legal@lawfirm.com
```

Used by multiple investors.

System response:

```
Multiple investors found
```

User selects the correct investor.

---

### Case 3 — No Match

System response:

```
No investor found
```

User can manually search and select an investor.

---

# 9. Data Storage (IncomingEmail)

The email will be stored using the **existing `IncomingEmail` model**.

Proposed fields used:

```
IncomingEmail
---------------------
id
entity_id
owner_id (investor_id)
owner_type (Investor)
subject
body (contains body_text or body_html)
from
to
cc_emails (to be added)
message_id (to be added)
internet_message_id (to be added)
received_at (to be added)
filed_by_user_id (to be added)
created_at
```

**Note:** `IncomingEmail` uses a polymorphic `owner` association. For this feature, `owner_type` will be `Investor` and `owner_id` will be the `investor_id`.

Attachments can be stored using the existing file storage mechanism used by `IncomingEmail`.

---

# 10. Matching Algorithm

Pseudocode:

```
emails = [from_email] + to_emails + cc_emails

# Filter by approved accesses only
matches = InvestorAccess.approved.where(email: emails)

if matches.count == 1
  return matches.first.investor

if matches.count > 1
  return multiple_matches

else
  return no_match
```

---

# 11. API Design

### Match Investor

```
POST /api/email_match
```

Input:

```
{
  from_email,
  to_emails[],
  cc_emails[]
}
```

Response:

```
{
  match_type: "single | multiple | none",
  investors: []
}
```

---

### File Email

```
POST /api/incoming_emails
```

Payload:

```
{
  investor_id,
  subject,
  body_html,
  body_text,
  from_email,
  to_emails[],
  cc_emails[],
  attachments[],
  message_id,
  internet_message_id
}
```

---

# 12. Outlook Add-in UI

Example task pane:

```
---------------------------------
CapHive

Matched Investor
ABC Family Office

Reason
Sender email matched investor contact

Subject
Capital call clarification

[ Confirm Filing ]

[ Change Investor ]

---------------------------------
```

---

# 13. Permissions

Before filing an email:

```
current_user.can_view?(investor)
```

Users must have access to the investor within CapHive.

---

# 14. Audit Trail

Each filing records:

```
filed_by_user_id
filing_timestamp
match_reason
```

Ensures traceability.

---

# 15. Duplicate Prevention

Use `internet_message_id` to prevent duplicate entries.

Rule:

```
IncomingEmail.find_by(internet_message_id)
```

If found, prevent duplicate filing.

---

# 16. Edge Cases

### Shared investor email

Handled by manual selection.

---

### Internal forwarded emails

Matching may fail.

User selects investor manually.

---

### Multiple investors in thread

User selects the appropriate investor.

---

### Attachments

Stored along with the `IncomingEmail`.

---

# 17. Success Metrics

Success criteria:

* > 90% investor match accuracy
* Email filing completed in **under 2 clicks**
* > 50% of investor emails filed within 3 months

---

# 18. Future Enhancements

### Phase 2

* Auto-suggest investor on email open
* Email thread grouping
* Attachment parsing

### Phase 3

* Automatic mailbox ingestion via Microsoft Graph
* AI summarization of investor communication
* Task extraction

### Phase 4

* Investor communication timeline
* Sentiment detection
* Compliance alerts

---

# 19. Estimated Timeline

| Task                      | Time   |
| ------------------------- | ------ |
| Outlook add-in scaffold   | 1 week |
| Matching API              | 2 days |
| IncomingEmail integration | 3 days |
| Add-in UI                 | 3 days |
| Attachments               | 3 days |
| Testing                   | 1 week |

Estimated MVP:

**3–4 weeks**

---

## Important Strategic Note

This feature is more powerful than it looks.

Once emails are stored in `IncomingEmail`, you unlock:

* **Investor communication timeline**
* **AI summaries of investor interactions**
* **automatic compliance flagging**
* **meeting prep generation for fund managers**

In other words, this can become the **central communication layer of CapHive**.

---

If you'd like, I can also show you **how the Rails service object for investor matching should be written** (it’s about a 30-line clean service that will make this feature extremely robust).



Below is a **clean PRD focused specifically on the technical architecture and implementation**, aligned with:

* **Rails backend**
* **ERB templates**
* **Devise authentication (`/users/sign_in`)**
* **Existing `IncomingEmail` model**
* **Investor → InvestorAccess.email matching**
* **No React**

---

# Product Requirements Document (PRD)

## Feature

**Outlook Add-in for Filing Emails to Investors**

---

# 1. Overview

Fund managers and investor relations teams communicate with investors primarily through email. Important investor communication often remains inside personal inboxes and is not systematically stored within CapHive.

This feature introduces an **Outlook Add-in that allows users to file emails from Outlook into CapHive under the appropriate investor**.

The system will:

1. Extract email metadata from the currently opened Outlook email
2. Match the email to an investor using **InvestorAccess.email**
3. Allow the user to confirm or override the match
4. Store the email in the **existing `IncomingEmail` model**

The add-in will use **CapHive’s existing Rails backend, ERB templates, and Devise authentication**.

---

# 2. Goals

## Primary Goals

* Enable users to **file emails into CapHive directly from Outlook**
* Automatically **match investors via `InvestorAccess.email`**
* Store emails using the **existing `IncomingEmail` model**
* Use **existing Devise authentication**

## Secondary Goals

* Create a **central investor communication history**
* Improve **team collaboration**
* Provide **auditability of investor communication**

---

# 3. Non-Goals (MVP)

The first version will **not include**:

* Automatic mailbox ingestion
* AI-based investor matching
* Email thread reconstruction
* Sending emails from CapHive
* Automatic filing without user confirmation

---

# 4. Users

Primary users:

* Fund managers
* Investor relations teams
* Fund operations teams

Secondary users:

* Compliance teams
* Fund administrators

---

# 5. High-Level Architecture

The Outlook add-in consists of:

1. **Outlook Add-in Manifest (XML)**
2. **Rails-hosted Web UI (ERB)**
3. **Office.js JavaScript integration**
4. **Rails APIs for matching and storing emails**

```
Outlook Client
     │
     │ opens
     ▼
Rails ERB Task Pane
     │
     │ Office.js extracts email metadata
     ▼
Rails API
     │
     ├─ Match Investor (InvestorAccess.email)
     │
     └─ Store Email (IncomingEmail)
```

---

# 6. Technology Stack

## Backend

* Ruby on Rails
* PostgreSQL
* Devise authentication

## Frontend

* ERB templates
* Vanilla JavaScript
* Office.js library

## Outlook Integration

* Outlook Add-in XML manifest
* Office.js APIs

No frontend frameworks (React/Vue) will be used.

---

# 7. Authentication

Authentication will reuse **CapHive's existing Devise login system**.

### Login Flow

1. Outlook opens the add-in task pane.
2. Task pane loads:

```
/outlook_addin/taskpane
```

3. If the user is **not authenticated**, they are redirected to:

```
/users/sign_in
```

4. User logs in via Devise.
5. After login, user returns to the Outlook add-in page.

### Session Handling

The add-in will rely on the **standard Rails session cookie** created by Devise.

No long-lived API tokens will be stored in the add-in.

---

# 8. Outlook Add-in Manifest

The Outlook add-in requires an **XML manifest file** that defines:

* Add-in metadata
* Ribbon button
* Task pane URL
* Permissions

Example:

```
public/manifests/caphive_outlook_addin.xml
```

Key configuration:

```
Task Pane URL:
https://app.caphive.com/outlook_addin/taskpane
```

Ribbon button:

```
File to CapHive
```

---

# 9. Rails Application Structure

### Controllers

```
app/controllers/outlook_addin_controller.rb
```

Actions:

```
taskpane
```

API controllers:

```
app/controllers/api/outlook/email_matches_controller.rb
app/controllers/api/incoming_emails_controller.rb
```

---

### Views

```
app/views/outlook_addin/taskpane.html.erb
```

---

### JavaScript

```
app/assets/javascripts/outlook_addin.js
```

Handles Office.js integration.

---

### Services

```
app/services/investor_email_matcher.rb
```

Responsible for investor matching.

---

# 10. Email Extraction (Office.js)

The Outlook add-in will use **Office.js** to extract the current email metadata.

Data extracted:

* subject
* sender email
* recipient emails
* cc emails
* body
* message id
* timestamp

Example data payload:

```
{
  subject,
  from_email,
  to_emails[],
  cc_emails[],
  body_html
}
```

---

# 11. Investor Matching Logic

Investors are matched through the **InvestorAccess model**.

Relationship:

```
Investor
  has_many InvestorAccess
      email
```

Matching rule:

```
emails = [from_email] + to_emails + cc_emails
matches = InvestorAccess.where(email: emails)
```

Possible outcomes:

| Outcome          | Description                       |
| ---------------- | --------------------------------- |
| Single Match     | Investor identified automatically |
| Multiple Matches | User must select investor         |
| No Match         | User selects investor manually    |

---

# 12. API Endpoints

## Match Investor

```
POST /api/outlook/email_matches
```

Input:

```
{
  from_email,
  to_emails[],
  cc_emails[]
}
```

Response:

```
{
  match_type: "single | multiple | none",
  investors: []
}
```

---

## Create Incoming Email

```
POST /api/incoming_emails
```

Payload:

```
{
  investor_id,
  subject,
  body_html,
  from_email,
  to_emails[],
  cc_emails[],
  message_id
}
```

Creates an `IncomingEmail`.

---

# 13. Data Storage

Emails will be stored using the existing **IncomingEmail model**.

Fields used:

```
IncomingEmail
---------------------
id
entity_id
investor_id
subject
body_html
from_email
to_emails
cc_emails
message_id
received_at
created_at
```

Attachments will use the existing CapHive attachment mechanism.

---

# 14. Outlook Add-in UI

Task pane layout:

```
---------------------------------
CapHive

Matched Investor
ABC Family Office

Reason
Sender email matched investor contact

Subject
Distribution clarification

[ Confirm Filing ]

[ Change Investor ]

---------------------------------
```

States supported:

* Loading
* Match found
* Multiple matches
* No match
* Filing success
* Error

---

# 15. Duplicate Protection

To avoid duplicate filings:

```
IncomingEmail.find_by(message_id)
```

If a record exists, the system will notify the user.

---

# 16. Permissions

Before filing the email:

```
current_user.can_view?(investor)
```

The user must have permission to access the investor.

---

# 17. Edge Cases

### Shared Email Addresses

Multiple investors may share an email.

User must select manually.

---

### Forwarded Emails

Matching may fail due to internal forwarding.

User may manually choose investor.

---

### Multiple Investors in Thread

User selects the correct investor.

---

# 18. Success Metrics

Success criteria:

* > 90% automatic investor match rate
* Filing email within **2 clicks**
* > 50% of investor communication recorded within 3 months

---

