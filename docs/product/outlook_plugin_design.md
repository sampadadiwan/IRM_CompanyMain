Good — that actually simplifies the design and keeps your system consistent. Instead of inventing a new `InvestorEmail` model, the PRD should **reuse `IncomingEmail` and extend its usage to support investor filing**.

Below is the **revised PRD aligned with your existing Rails architecture**.

---

# Product Requirements Document

## Feature: Outlook Email Filing to Investor Records

---

# 1. Overview

Fund managers frequently communicate with investors through email. Important discussions about capital calls, distributions, reporting, compliance, and documentation occur in inboxes but are not systematically stored inside CapHive.

This feature introduces an **Outlook Add-in that allows users to file emails under investors directly from Outlook**.

Emails will be matched to investors based on **email addresses stored in `InvestorAccess.email`** and **investor domains stored in `Investor.primary_email`**, and the email will be stored using the existing **`IncomingEmail` model**.

---

# 2. Goals

### Primary Goals

1. Allow Outlook users to **file emails into CapHive under investors**.
2. Automatically match emails using **investor domains (`Investor.primary_email`)** and **contact emails (`InvestorAccess.email`)**.
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

Investor matching uses a multi-tiered domain and email approach.

Relationship:

```
Investor
  primary_email (used for domain matching)
  has_many InvestorAccess
       email (used for contact matching)
```

### Matching Algorithm (Priority Order)

Most specific first — matching stops at the first tier that produces candidates.
Participants means From, To **and** CC on every tier.

1.  **Contact Match**: A participant address is a known, approved `InvestorAccess.email`.
2.  **Primary Email Match**: A participant address is an `Investor.primary_email` exactly.
3.  **Domain Match**: A participant address shares a domain with `Investor.primary_email`.
    Generic mail hosts (gmail.com, outlook.com, …) are excluded, since a shared suffix
    there says nothing about the counterparty.

> Superseded earlier drafts of this section listed domain matching first with a direct
> email fallback, and described matching on From and CC only. The implementation does the
> opposite ordering — specific before general, which is the correct precedence — and reads
> To as well, without which no outbound email could ever be matched.
> See `InvestorEmailMatcher` and `docs/technical/mail_addin_review.md`.

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

Matching logic (implemented in `InvestorEmailMatcher`):

```ruby
# 1. Match from_email domain to investor primary_email domain
# 2. Match cc_emails domains to investor primary_email domain
# 3. Match all emails to InvestorAccess.email
```

---

### Step 5 — Match Result

Three possible outcomes.

---

### Case 1 — Single Match

Response:

```
Matched Investor: ABC Family Office
Reason: domain matched investor primary_email
Confidence: High
```

User confirms filing.

---

### Case 2 — Multiple Matches

Example:

```
legal@lawfirm.com
```

Used by multiple investors or domains shared across entities.

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

```ruby
def match
  # 1. Match from_email domain
  matches = Investor.where("primary_email LIKE ?", "%@#{from_domain}")

  # 2. Match cc_emails domains
  if matches.none?
    matches = Investor.where(cc_domain_queries)
  end

  # 3. Fallback to InvestorAccess
  if matches.none?
    matches = InvestorAccess.approved.where(email: all_emails)
  end

  return matches
end
```

---

# 11. API Design

### Match Investor

```
POST /email_matches
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
  investors: [
    { id, name }
  ]
}
```

---

### File Email

```
POST /incoming_emails
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
Sender domain matched investor record

Subject
Capital call clarification

[ Confirm Filing ]

[ Change Investor ]

---------------------------------
```

---

# 13. Permissions

Before filing an email:

The system uses `Pundit.policy_scope!` to ensure the current user can only match investors they have access to.

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

# 20. Technical Implementation Detail

The investor matching logic is encapsulated in the `InvestorEmailMatcher` service.

```ruby
# app/services/investor_email_matcher.rb
class InvestorEmailMatcher
  include Pundit::Authorization

  def initialize(from_email:, user:, to_emails: [], cc_emails: [])
    # ...
  end

  def match
    # Tiered matching logic:
    # 1. From domain -> Investor.primary_email domain
    # 2. CC domains -> Investor.primary_email domain
    # 3. Fallback to InvestorAccess.email
  end
end
```

---

## Important Strategic Note

This feature is more powerful than it looks.

Once emails are stored in `IncomingEmail`, you unlock:

* **Investor communication timeline**
* **AI summaries of investor interactions**
* **automatic compliance flagging**
* **meeting prep generation for fund managers**

In other words, this can become the **central communication layer of CapHive**.
