# Granola Meeting Notes Sync — Proposal

> **Audience:** Business team, product, QA, support — non-technical.
> **Companion document:** [Design](design.md)

> **Planning phase — no code changes.** This document proposes and explains the change. Do not
> edit application code while writing it; implementation happens later, in the tasks phase.

---

## Why

Our funds run their investor meetings with Granola, an AI note-taking app that records the call and
writes a summary. Those summaries never reach CapHive: the investor's Notes tab stays empty unless a
partner retypes or pastes the meeting in by hand, so the CRM history, the "last interaction" date and
the quarterly note summaries all miss most of the actual conversations with LPs.

## What Changes

CapHive connects to a fund's Granola account and pulls in meeting notes on its own, filing each one
as a Note on the investor the meeting was with. Anything CapHive is not sure about waits in a review
inbox instead of being guessed.

- A partner can connect **their own** Granola account from their profile, or a fund admin can
  connect the fund's **shared Granola workspace** from the entity settings. Both can be used at once.
- Every ~15 minutes CapHive checks each connection for new or changed Granola meetings.
- A meeting is matched to an investor by comparing the **meeting attendees' email addresses** with
  the investor contacts (stakeholders) already saved in CapHive.
- When the attendees point to exactly one investor, the meeting summary is **filed automatically** as
  a Note on that investor, dated on the meeting date, with the matched contact recorded as the
  person the meeting was with, tagged `granola`, and linked back to the meeting in Granola.
- When the match is ambiguous (the attendees belong to more than one investor, or only an email
  domain matches), the meeting goes into a **Granola Inbox** where a team member picks the investor
  or discards it.
- Meetings with no known investor contact (internal meetings, portfolio-company calls, recruiting)
  are **never filed**. They are kept out of sight under an "Ignored" filter, so that if the contact
  is added to CapHive later the meeting can be re-matched.
- If a meeting is updated in Granola after it was filed, CapHive updates the note, **unless someone
  has already edited that note in CapHive**, in which case CapHive leaves the person's edit alone.
- The investor's "last interaction" date moves to the **meeting date**, not the date the sync ran.

### Flow Diagram

```
Current flow:
  Partner meets LP ─▶ Granola writes summary ─▶ (stays in Granola)
                                               └─▶ partner maybe copy-pastes into CapHive by hand

New flow:
  Partner meets LP ─▶ Granola writes summary
                         │
                         ▼   (every ~15 min)
                 CapHive checks Granola
                         │
          ┌──────────────┼──────────────────┬─────────────────────┐
          ▼              ▼                  ▼                     ▼
   one investor     several investors   no investor          internal only
   matched          / domain-only       contact in the       (all attendees are
          │         match                meeting              fund team)
          ▼              ▼                  ▼                     ▼
   Note filed on    Granola Inbox        Ignored              Ignored
   the investor     (team member picks)  (re-matchable later)
```

---

## User Stories

### US-1: Connect my own Granola account

**As a** fund partner,
**I want** to connect my Granola account to CapHive,
**So that** my investor meetings show up on the right investor without me copying anything.

**Acceptance criteria:**
- My profile has a **Granola** section with an **API key** field and a **Connect** button.
- A wrong or revoked key is rejected on Connect with "Granola rejected this API key. Check it and
  try again." and nothing is saved.
- After connecting I see "Connected", the time of the last sync, and **Sync now** and **Disconnect**
  buttons.
- On first connect CapHive imports my meetings from the **last 90 days**.
- The key is never shown again after saving (it appears as `grn_••••••••1a2b`).

### US-2: Connect the fund's Granola workspace

**As a** fund admin,
**I want** to connect our shared Granola workspace once for the whole fund,
**So that** meetings shared into the workspace are filed even for partners who never connect their own account.

**Acceptance criteria:**
- Entity settings has a **Granola workspace** section, visible only to fund admins.
- It works the same way as US-1 (Connect, Sync now, Disconnect, last sync time, 90-day backfill).
- Private notes are never available through a workspace connection, only the shared meeting summary.

### US-3: Meeting with one LP is filed automatically

**As a** fund partner,
**I want** a meeting with an LP's contacts to appear on that LP's Notes tab,
**So that** the team sees the conversation without me doing anything.

**Acceptance criteria:**
- The note appears on the investor's Notes tab within ~15 minutes of Granola finishing the summary.
- The note shows the Granola meeting title, the summary, the meeting date, "With: <contact name>",
  the tag `granola`, and an **Open in Granola** link.
- The note's author is the partner who owned the meeting in Granola (see Behavior Rules for the
  workspace case).
- The investor's last interaction date becomes the meeting date.
- Syncing the same meeting again never creates a second note.

### US-4: Review meetings CapHive could not place

**As a** fund admin (or the partner who owned the meeting),
**I want** a single inbox of Granola meetings that need a decision,
**So that** ambiguous meetings still end up on the right investor, and never on the wrong one.

**Acceptance criteria:**
- A **Granola Inbox** page lists meetings waiting for review, newest first, with title, date,
  attendees and the candidate investors CapHive found.
- For each meeting I can choose an investor (candidates first, then any investor) and click **File**,
  or click **Discard**.
- Filing creates the note exactly as in US-3. Discarding removes it from the inbox and it will not
  come back on later syncs.
- An **Ignored** filter shows meetings with no investor match. **Re-match** runs matching again
  against the current contacts.
- The inbox shows a count badge of meetings awaiting review.

### US-5: Meeting with several LPs

**As a** fund team member,
**I want** a meeting whose attendees belong to more than one investor to wait for my decision,
**So that** a co-investor call or a duplicated LP record does not scatter notes onto the wrong investors.

**Acceptance criteria:**
- Such a meeting is not filed automatically. It appears in the Granola Inbox with every matched
  investor listed as a candidate.
- I can file it to **one or more** of the candidates, and each chosen investor gets its own note.

### US-6: Granola edits after the meeting

**As a** fund partner,
**I want** late edits in Granola to reach CapHive, without wiping out anything a colleague changed,
**So that** the note is current but nobody's edit is lost.

**Acceptance criteria:**
- A note nobody has edited in CapHive is updated when the Granola meeting changes.
- A note someone has edited in CapHive is left alone. It shows "Edited in CapHive — later Granola
  changes are not applied."

### US-7: Know when the connection breaks

**As a** fund partner (or admin, for the workspace),
**I want** to be told when my Granola connection stops working,
**So that** meetings do not silently stop arriving.

**Acceptance criteria:**
- If Granola rejects the key during a sync, the connection shows **Needs attention** with the reason,
  syncing pauses, and the person who connected it gets an email and an in-app notification.
- Reconnecting with a valid key resumes syncing from where it stopped.

---

## UI Behavior

### Profile → Granola (per-user) / Entity settings → Granola workspace

```
┌─────────────────────────────────────────────────────┐
│  Granola                                             │
│                                                     │
│  Status:     ● Connected                             │
│  API key:    grn_••••••••1a2b                        │
│  Last sync:  30/09/2026 14:15 — 3 filed, 1 to review │
│                                                     │
│  [ Sync now ]   [ Disconnect ]                       │
│                                                     │
│  Meetings are matched to investors by attendee       │
│  email. Only meetings with a known investor contact  │
│  are imported.                                       │
└─────────────────────────────────────────────────────┘

Not connected:
┌─────────────────────────────────────────────────────┐
│  Granola                                             │
│  API key: [ grn_...                           ]      │
│  [ Connect ]                                         │
│  Where do I find my key? (Granola → Settings → API)  │
└─────────────────────────────────────────────────────┘
```

**Behavior notes:**
- **Connect** checks the key with Granola before saving. An invalid key shows the error inline.
- **Sync now** queues a sync and shows "Sync started". The last sync line refreshes when it finishes.
- **Disconnect** asks "Stop importing from Granola? Notes already imported are kept." Notes are
  never deleted by disconnecting.
- **Needs attention** replaces "Connected" in red, with the reason and a key field to reconnect.

### Granola Inbox

```
┌──────────────────────────────────────────────────────────────────────────┐
│  Granola Inbox                         [ To review (2) ] [ Ignored ]      │
│                                                                          │
│  Q3 check-in — Acme Pension               28/09/2026   owner: R. Menon   │
│  Attendees: jane@acmepension.com, raj@ourfund.com                        │
│  Candidates: ☐ Acme Pension Fund   ☐ Acme Pension (Co-invest SPV)        │
│  Other investor: [ search…            ▾ ]                                │
│                                           [ File ]  [ Discard ]  ↗Granola │
│ ──────────────────────────────────────────────────────────────────────── │
│  Intro call — Bluewater Family Office     27/09/2026   owner: A. Shah    │
│  Attendees: tom@bluewater.co (domain match only)                         │
│  Candidates: ☐ Bluewater Family Office                                   │
│                                           [ File ]  [ Discard ]  ↗Granola │
└──────────────────────────────────────────────────────────────────────────┘
```

**Behavior notes:**
- Filing or discarding removes the row without a page reload.
- **File** is disabled until at least one investor is chosen.
- The **Ignored** tab lists unmatched meetings with a **Re-match** button per row and a
  **Re-match all** button at the top.

### Investor → Notes tab (filed note)

```
┌─────────────────────────────────────────────────────┐
│  28/09/2026 · Q3 check-in — Acme Pension   [granola] │
│  By R. Menon · With: Jane Doe                        │
│                                                     │
│  • Reaffirmed commitment to Fund III                  │
│  • Asked for updated DPI by fund vintage             │
│  • Next step: send Q3 report by 15 Oct               │
│                                                     │
│  Open in Granola ↗                                   │
└─────────────────────────────────────────────────────┘
```

---

## What This Feature Does NOT Cover

| Excluded | Covered In |
|---|---|
| Filing meetings onto a deal pipeline stakeholder (Deal Investor) | Later phase — v1 files onto the Investor only |
| Importing the full meeting transcript | Not planned — summary and private notes only; the Granola link opens the transcript |
| Sending notes from CapHive back to Granola | Not planned — Granola's API is read-only |
| Creating new investor contacts automatically from unknown attendees | Later phase — the reviewer adds the contact, then clicks Re-match |
| Instant sync the moment a meeting ends | Not possible today — Granola offers no push notifications, so CapHive checks every ~15 minutes |
| Deleting CapHive notes when a meeting is deleted in Granola | Not planned — CapHive keeps its copy |

---

## Validation Rules

| Field | Rule | Default |
|---|---|---|
| Granola API key | Required to connect; must start with `grn_`; must be accepted by Granola on Connect | — |
| Per-user connection | At most one per user per entity | — |
| Workspace connection | At most one per entity; fund admins only | — |
| Investor chosen when filing from the inbox | At least one investor, from the same entity | — |
| Backfill window on first connect | Fixed at 90 days | 90 days |

---

## Behavior Rules

| Scenario | What User Sees |
|---|---|
| Every external attendee is a contact of the same one investor | Note filed automatically on that investor |
| Some attendees are that investor's contacts, others are unknown | Filed automatically on the matched investor (the unknown person is usually a colleague at the LP) |
| Attendees are contacts of two or more different investors | Meeting waits in the Granola Inbox with all of them as candidates |
| Only an attendee's email domain matches an investor's contacts | Meeting waits in the Granola Inbox (domain matches are never auto-filed) |
| No attendee matches any investor contact | Meeting is Ignored (hidden under the Ignored filter) |
| All attendees are fund team members | Meeting is Ignored |
| The same meeting comes through a partner's key and the workspace key | Filed once. The second copy is recognised and skipped |
| Meeting changes in Granola, note unedited in CapHive | Note text, date and contact are updated |
| Meeting changes in Granola, note edited in CapHive | Note left as is, with "Edited in CapHive — later Granola changes are not applied" |
| A filed note is deleted in CapHive | It is not re-imported on later syncs |
| A discarded inbox meeting changes in Granola | It stays discarded |
| Workspace key: Granola meeting owner has a CapHive login in this fund | That person is shown as the note's author |
| Workspace key: meeting owner has no CapHive login | The admin who connected the workspace is the author, with "Imported from Granola (owner: name)" |
| Per-user key: meeting has private notes | Private notes are appended under a "Private notes" heading |
| Granola rejects the key during a sync | Connection shows Needs attention, sync pauses, connector notified by email + in-app |
| Granola is temporarily down or rate-limits | Retried automatically. Nobody is notified unless it keeps failing for 24 hours |
| Sync runs, nothing new | Last sync time updates; nothing else changes |

---

## Resolved Design Decisions

| # | Decision | Resolution |
|---|---|---|
| 1 | Whose Granola key is used? | Both: per-user keys (profile) and one workspace key per entity (entity settings), usable together |
| 2 | Auto-file or review? | Auto-file only an unambiguous single-investor match on exact contact email. Everything else goes to review or is ignored |
| 3 | Meetings with several investors | Always to review. The reviewer may file to several investors, one note each |
| 4 | Domain-only matches | Review, never auto-filed |
| 5 | Meetings with no investor contact | Ignored and never shown on any investor, kept only so they can be re-matched |
| 6 | What content is imported | Meeting title, summary, private notes (per-user key only), meeting date, contact, link to Granola. No transcript |
| 7 | Granola edits vs CapHive edits | Granola updates apply until someone edits the note in CapHive; after that the CapHive edit wins |
| 8 | Last interaction date | Meeting date, not sync time |
| 9 | Deal pipeline stakeholders | Out of scope for v1. Notes go on the Investor |
| 10 | History on first connect | Last 90 days |
| 11 | Visibility once imported | Imported notes follow normal CapHive note visibility: the author and fund admins. The Granola Inbox follows the same rule. Fund admins see every meeting, other users see the meetings they own |

---

## Capabilities

### New Capabilities

- `granola-notes-sync`: connecting Granola accounts (per-user and workspace), periodic import of
  meeting notes, attendee-to-investor matching, auto-filing as investor notes, the review inbox, and
  update/edit-ownership rules.

### Modified Capabilities

None. There is no existing notes spec. The last-interaction date rule for imported notes is part of
the new capability.

---

## Impact

- **Investor Notes tab**: shows imported Granola notes with a `granola` tag and an Open in Granola link.
- **User profile**: new Granola connection section.
- **Entity settings**: new Granola workspace section for fund admins.
- **New Granola Inbox page** for the fund team.
- **Background jobs**: a new scheduled sync every ~15 minutes.
- **Notifications**: a new "Granola connection needs attention" email and in-app notification.
- **External dependency**: Granola's public API (read-only, API-key based).
- **Investor "last interaction" date**: set from meeting dates for imported notes.

---

## Benefits

1. Investor meetings reach the LP's record without anyone copying notes.
2. The CRM history, "last interaction" and not-interacted reports reflect real meetings.
3. The quarterly Note Summarizer agent gets far more material to summarise.
4. Nothing lands on the wrong investor. Unclear matches wait for a person.
5. Meetings that aren't about investors (portfolio companies, internal, personal) never enter CapHive.

---

## FAQ

| Question | Answer |
|---|---|
| Who can connect Granola? | Any fund team member can connect their own account. Only fund admins can connect the workspace |
| Who can see the Granola Inbox? | Fund admins see every meeting for the fund. Other team members see only meetings they own in Granola — the same rule CapHive already applies to notes |
| Do investors (LPs) see these notes? | No. Notes are internal, as they are today |
| Will my private Granola notes become visible to my colleagues? | Fund admins can see them once the meeting is filed, as with any note you write in CapHive. The profile screen warns about this before you connect. Meetings without an investor contact are never imported |
| What happens to my portfolio-company or internal meetings? | They are not imported. CapHive keeps only a hidden "ignored" record (title, date, attendees) so the meeting can be re-matched if an LP contact is added later |
| What if a contact's email in CapHive is wrong or missing? | The meeting is Ignored. Fix the contact, then press Re-match in the Ignored tab |
| Does disconnecting delete imported notes? | No |
| Can the same meeting be imported twice? | No. Each Granola meeting is recorded once per fund, whichever key brought it in |
| How quickly do meetings appear? | Within about 15 minutes of Granola finishing the summary, or immediately with Sync now |
| Does this need a paid Granola plan? | API access depends on the fund's Granola plan. Check with Granola. Connect will say so if the key is rejected |
| Does this cost anything in CapHive? | No new billing |
| How does matching work in detail? | See [design.md](design.md) — Key Components |

---

## Design Principle for the Next Phase

Keep it DRY and simple. The deal-ingest email agent already implements this whole pattern: take
something in, match it to a stakeholder, file it or park it for review. Reuse its shape and do not
invent a new framework. Areas that risk complexity and need explicit handling in design:

- **Two connection kinds**: model them as one connection record with a kind, not two features.
- **Duplicate prevention across keys**: one meeting record per fund, keyed by Granola's meeting id.
- **Edit ownership**: detect "edited in CapHive" without adding callbacks to every note save.
- **The last-interaction change** touches shared note code. It must not change behaviour for
  manually created notes.
- **Secret storage**: the API key reads a partner's whole meeting history and must be encrypted.
