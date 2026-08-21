# Deal Update Agent — Business Design

## Purpose

The Deal Update Agent lets team members update the deal board by sending a plain-language email — no need to open the app. After a call, a team member sends an email like *"Met with Sequoia today, they're interested in 5M"* to a unique deal address, and the agent automatically creates a meeting note or task on the deal board.

This solves the post-call capture problem: notes and follow-ups often get delayed or lost because logging into the platform mid-day is friction. Email works on every phone, requires no app, and captures updates in real-time.

---

## Who Is This For?

- **Fund managers** — capture meeting notes and follow-ups immediately after investor calls
- **Deal team members** — log updates from the field without switching contexts
- **Anyone with deal access** — every user with access to a deal gets their own unique email address for that deal

---

## How It Works

### 1. Every User Gets a Unique Address Per Deal

When a user visits a deal page, a unique email address is automatically generated for them — e.g., `d7f3a91c2b8e4406@updates.caphive.com`. This address is shown below the deal name with a copy button.

The address is:
- **Personal** — tied to one user + one deal
- **Unguessable** — 16 random hex characters
- **Persistent** — stays the same across visits, can be saved as a contact

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
| "Caught up with Tiger Global, positive signals on the 10M commitment" | Meeting Note on Tiger Global |

### 3. The Agent Processes Automatically

Within seconds, the agent:
1. Verifies the sender's identity (matches the email to the address owner)
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

### 5. When the Agent Is Unsure → Warehouse

If the agent can't confidently match the stakeholder or determine the intent, the email goes to the **Warehouse** — a holding area on the deal page. A team member can:
- **File it** — pick the correct stakeholder and create the note/task manually
- **Discard it** — mark it as irrelevant

The sender is notified that their email needs manual review.

---

## Security

- **Address = credential** — possession of the address proves identity + deal access
- **Sender verification** — the From email must match the address owner's registered email
- **SPF/DKIM/DMARC** — email authentication headers are checked
- **Silent drops** — failed authentication never gets a reply (doesn't confirm the address exists)
- **Access revocation** — when a user loses deal access, their address is immediately revoked

---

## What the Agent Creates

### Meeting Notes
- Attached to the matched investor on the deal board
- Date set to today
- Flagged as "created by agent" for audit trail
- Full email body preserved as note content

### Tasks
- Attached to the matched investor on the deal board
- Assigned to the sender
- Due date extracted from the email (e.g., "by Friday" → next Friday)
- Flagged as "created by agent" for audit trail

---

## The Warehouse

The Warehouse tab appears on the deal page when there are pending items. Each item shows:
- When it was received
- Who sent it
- The detected intent (Meeting Note / Task / Unknown)
- A preview of the content
- Actions: File (pick stakeholder) or Discard

---

## Phase Roadmap

### Phase 1 — MVP (Current Release)

| Feature | Included |
|---------|----------|
| Per-(deal, user) email address | Yes |
| Address shown on deal page with copy button | Yes |
| AI parsing of email intent and stakeholder | Yes |
| Stakeholder matching against deal investors | Yes |
| Auto-creation of Meeting Notes and Tasks | Yes |
| Confirmation and warehouse notification emails | Yes |
| Warehouse UI for manual filing | Yes |
| Sender verification (email + SPF/DKIM/DMARC) | Yes |
| Address revocation on access removal | Yes |
| Message-ID deduplication | Yes |
| Automated test suite (11 scenarios) | Yes |

### Phase 2 — Planned

| Feature | Description |
|---------|-------------|
| WhatsApp channel | Send updates via WhatsApp in addition to email |
| Disambiguation replies | When multiple stakeholders match, the agent asks "did you mean 1) Sequoia or 2) Sequoia Capital India?" |
| Global stakeholder search | Search beyond the deal's investors if no match found |
| Attachments | File attachments alongside notes (e.g., term sheets, meeting decks) |
| Undo (30-day) | Reply "undo" to a confirmation email to reverse the action |

### Phase 3 — Future

| Feature | Description |
|---------|-------------|
| New stakeholder creation | If no match at all, offer to add as a new investor on the deal |
| Warehouse bulk actions | Select multiple warehouse items and file/discard in batch |
| Admin UI | Manage addresses, view usage stats, rotate addresses |
| Merge tool | Merge duplicate warehouse items |

### Phase 4 — Vision

| Feature | Description |
|---------|-------------|
| Slack channel | Post deal updates from Slack |
| AI queries via MCP | Ask the agent questions about the deal ("who haven't we spoken to in 2 weeks?") |

---

## Benefits

1. **Zero friction** — email works on every device, no app needed
2. **Real-time capture** — notes are logged seconds after the call, not hours later
3. **Automatic organization** — the agent matches stakeholders and files in the right place
4. **Audit trail** — every agent-created item is flagged and linked to the source email
5. **Safe fallback** — uncertain items go to the warehouse, never filed incorrectly
