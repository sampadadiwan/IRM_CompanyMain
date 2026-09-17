# Deal Update Agent — Business Design

## Purpose

The Deal Update Agent lets team members update the deal board by sending a plain-language email — no need to open the app. After a call, a team member sends an email like *"Met with Sequoia today, they're interested in 5M"* to the deal's shared email address, and the agent automatically creates a meeting note or task on the deal board.

This solves the post-call capture problem: notes and follow-ups often get delayed or lost because logging into the platform mid-day is friction. Email works on every phone, requires no app, and captures updates in real-time.

---

## Who Is This For?

- **Fund managers** — capture meeting notes and follow-ups immediately after investor calls
- **Deal team members** — log updates from the field without switching contexts
- **Anyone with deal access** — every deal has a single shared email address that all authorized team members use

---

## How It Works

### 1. Every Deal Has a Shared Email Address

When a deal is created, a single email address is auto-generated — e.g., `42@dev.caphive.app` (deal ID as default). The address is shown on the deal page with a copy button, styled as a pill badge. Fund managers (company admins) can customize the address via an inline edit — e.g., change to `series-b@dev.caphive.app`.

The address is:
- **Shared** — the same address for all users with deal access
- **Readable** — deal ID or custom name, not random hex
- **Persistent** — stays the same across visits, can be saved as a contact
- **Editable** — fund managers can change it to a memorable name

### 2. Send an Email to Update the Deal

The team member sends an email to the address. The email body should mention:
- **Who** they met or spoke with (the stakeholder/investor name)
- **What happened** or **what needs to be done**
- **When** (optional — for tasks, mention a due date like "by next Friday")

**Examples:**

| Email Text | What Gets Created |
|-----------|-------------------|
| "Had a great call with Sequoia Capital. They want to see the data room." | Meeting Note on Sequoia Capital |
| "Need to send term sheet to Accel by Friday" | Task assigned to sender, due Friday, on Accel |
| "Ask Neil to send term sheet to Accel by Friday" | Task assigned to Neil (if Neil has deal access), due Friday, on Accel |
| "@Priya to follow up with Tiger Global on the data room" | Task assigned to Priya, on Tiger Global |
| "Caught up with Tiger Global, positive signals on the 10M commitment" | Meeting Note on Tiger Global |

### 3. The Agent Processes Automatically

Within seconds, the agent:
1. Identifies the deal from the address and the sender from the From email, then verifies the sender has access to the deal
2. Parses the email using AI to determine: note or task? which stakeholder? any due date?
3. Matches the stakeholder name against the deal's investor list
4. Creates the note or task on the deal board

### 4. Confirmation Email

The sender receives a confirmation email showing exactly what was created:
- The type (Meeting Note or Task)
- The deal name
- The matched stakeholder
- Due date (for tasks)
- A preview of the filed content

### 5. When the Agent Is Unsure → Warehouse + Reply

If the agent can't confidently match the stakeholder or determine the intent, the email goes to the **Warehouse** — a holding area on the deal page. The sender receives a reply email explaining why it couldn't be auto-filed:
- **Conflicting stakeholder** — the subject line mentions one investor but the email body mentions a different one (e.g., subject says "Update on Sequoia" but body talks about "Met with Accel today"). The agent can't determine which investor the update is about. Sender is advised to send separate emails — one per investor.
- **Unknown intent** — the agent couldn't determine if it was a meeting note or a task
- **Unmatched stakeholder** — the investor name didn't match anyone on the deal

A team member can then review the warehouse tab and:
- **File it** — pick the correct stakeholder, choose note or task, and for tasks: set the due date and assign to a team member before filing
- **Discard it** — mark it as irrelevant

After resolving the last warehouse item, the page redirects back to the deal.

---

## Security

- **Address identifies the deal** — the email address maps to a specific deal
- **Sender verified by From email** — the From email is matched to a registered user in the deal's entity
- **Deal access required** — the user must have an access right on the deal or be a company admin
- **SPF/DKIM/DMARC** — email authentication headers are checked
- **Silent drops** — failed authentication never gets a reply (doesn't confirm the address exists)

---

## What the Agent Creates

### Meeting Notes
- Attached to the matched investor on the deal board
- Date set to today
- Traceable to the source email via the agent's audit log (the link lives on the agent email record, not on the note itself)
- Full email body preserved as note content

### Tasks
- Attached to the matched investor on the deal board
- Assigned to the person mentioned in the email (e.g., "Neil to follow up" or "@Priya"), or to the sender if no one is mentioned
- Due date extracted from the email (e.g., "by Friday" → next Friday)
- Email attachments (PDFs, decks) are automatically filed to the deal's document store alongside the task
- Traceable to the source email via the agent's audit log (the link lives on the agent email record, not on the task itself)

---

## The Warehouse

The Warehouse tab appears on the deal page when there are pending items. Each item shows:
- When it was received
- Who sent it
- The detected intent badge: **Meeting Note** (blue), **Task** (blue), **Conflicting** (yellow — subject and body named different investors), or **Unknown** (grey)
- A preview of the content
- Actions: File (pick stakeholder) or Discard

When filing as a **Task**, additional fields appear inline:
- **Due date** — calendar picker (read-only text input, consistent with app-wide date format), pre-filled from the AI parse if available
- **Assignee** — dropdown of team members with direct deal access only (not all company admins)

After the last item is resolved (filed or discarded), the page redirects to the deal instead of staying on the empty warehouse list.

---

## Phase Roadmap

### Phase 1 — MVP (Current Release)

| Feature | Included |
|---------|----------|
| One shared address per deal (deal ID as default, customizable by fund manager) | Yes |
| Address shown on deal page with copy button | Yes |
| AI parsing of email intent and stakeholder | Yes |
| Stakeholder matching against deal investors | Yes |
| Auto-creation of Meeting Notes and Tasks | Yes |
| Confirmation email (success) and warehouse reply email (explains why it wasn't auto-filed) | Yes |
| Warehouse UI for manual filing | Yes |
| Sender verification (email + SPF/DKIM/DMARC) | Yes |
| Access-based auth (user must have deal access to send) | Yes |
| Message-ID deduplication | Yes |
| Automated test suite (14 scenarios) | Yes |

### Phase 2 — Done

| Feature | Description | Status |
|---------|-------------|--------|
| Auto-reply detection | Out-of-office, bounce notifications, and auto-generated replies are silently dropped before processing — prevents garbage notes from mail loops | Done |
| Signature/reply chain stripping | Quoted replies, signatures, disclaimers, and "Sent from my iPhone" are stripped before AI parsing — cleaner notes, fewer wasted AI tokens | Done |
| Attachments (Tasks) | Email attachments (PDFs, decks) are filed to the deal's document store alongside created Tasks. Notes attachment support deferred until usage justifies it | Done |
| Assignee parsing | Tasks can be assigned to other deal team members by mentioning their name naturally — "Neil to follow up", "Ask Priya to send", or "@Khushali". Falls back to sender if no match | Done |
| Address rotation | Generate a new random address, invalidating the old one — a safety net for compromised addresses | Deferred — inline edit (already live) covers the "change address" use case; auth layer blocks unauthorized senders |
| WhatsApp channel | Send deal updates via WhatsApp message (pending Product spec) | Blocked |

### Phase 3 — Planned

| Feature | Description |
|---------|-------------|
| Tier C global matching | If no match on the deal, search across all investors in the org and confirm before filing |
| Multi-item per email | A single email producing multiple notes/tasks |
| New stakeholder creation | If no match at all, offer to create a new investor via email domain dedupe |
| Sender timezone date resolution | Resolve relative dates in the sender's timezone |

### Phase 4 — Vision

| Feature | Description |
|---------|-------------|
| WhatsApp channel | Full WhatsApp integration beyond basic forwarding |
| Slack channel | Post deal updates from Slack |
| AI queries via MCP | Ask the agent questions about the deal ("who haven't we spoken to in 2 weeks?") |

---

## Benefits

1. **Zero friction** — email works on every device, no app needed
2. **Real-time capture** — notes are logged seconds after the call, not hours later
3. **Automatic organization** — the agent matches stakeholders and files in the right place
4. **Audit trail** — every agent-created item is flagged and linked to the source email
5. **Safe fallback** — uncertain items go to the warehouse, never filed incorrectly
