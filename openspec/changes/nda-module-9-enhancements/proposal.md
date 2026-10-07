# NDA Module 9 — Signatory Gating & Enhancements — Proposal

> **Audience:** Business team, product, QA, support — non-technical.
> **Companion document:** [Design](design.md)

> **Planning phase — no code changes.** This document proposes and explains the change. Do not
> edit application code while writing it; implementation happens later, in the tasks phase.

---

## Why

The NDA signatory tagging system exists — GPs can tag specific LP users as designated signatories from the NDA Status Dashboard — but it is purely informational. Any LP user with investor access can accept or decline the NDA regardless of whether they are tagged. This defeats the purpose of signatory tagging: compliance requires that only authorised persons sign binding agreements. Additionally, after a GP creates an NDA for the first time, there is no prompt to tag signatories, so investors default to having zero signatories and no one can sign.

---

## What Changes

- **Signatory gating on accept/decline:** Only users tagged as NDA signatories can accept or decline the NDA. Non-signatories who navigate to an NDA-protected folder see a blocked page explaining that a designated signatory must accept on their behalf.
- **Post-first-creation signatory prompt:** After a GP saves NDA settings for the first time (not on version bumps or updates), the NDA Status Dashboard opens with all investor rows auto-expanded and a banner prompting them to tag signatories.
- **Zero-signatory warning on dashboard:** Investors with no tagged signatories show a warning icon on the dashboard so GPs can spot and fix the gap.
- **Folder access unchanged:** Once any signatory accepts, folder access opens for all users under that investor (existing stakeholder-level behaviour, unchanged).

### Flow Diagram

**LP accessing NDA-protected folder — before vs. after signatory gating:**

```mermaid
flowchart LR
    A["LP user opens folder"] --> B{"NDA accepted?"}
    B -- Yes --> C["Folder opens"]
    B -- No --> D["Acceptance screen"]
    D --> E["Any LP user accepts/declines"]
    E --> C
    classDef manual fill:#fdecea,stroke:#c62828,color:#000
    class E manual
```

```mermaid
flowchart LR
    A["LP user opens folder"] --> B{"NDA accepted?"}
    B -- Yes --> C["Folder opens"]
    B -- No --> D{"User is signatory?"}
    D -- Yes --> E["Acceptance screen"]
    D -- No --> F["Blocked page"]
    E --> G["Signatory accepts/declines"]
    G --> C
    classDef new fill:#e8f5e9,stroke:#2e7d32,color:#000
    class D,F,G new
```

**GP first NDA creation — before vs. after signatory prompt:**

```mermaid
flowchart LR
    A["GP saves NDA settings"] --> B["Modal closes"]
    B --> C["GP navigates away"]
    classDef manual fill:#fdecea,stroke:#c62828,color:#000
    class C manual
```

```mermaid
flowchart LR
    A["GP saves first NDA"] --> B["Redirect to NDA Dashboard"]
    B --> C["Banner: 'Tag signatories'"]
    C --> D["Investor rows auto-expanded"]
    D --> E["GP tags signatories"]
    classDef new fill:#e8f5e9,stroke:#2e7d32,color:#000
    class B,C,D,E new
```

---

## User Stories

### US-1: Signatory accepts NDA

**As a** designated NDA signatory,
**I want** to review and accept the NDA when I access a protected folder,
**So that** the folder opens for all users under my investor.

**Acceptance criteria:**
- Tagged signatory sees the existing NDA acceptance screen (PDF + accept/decline buttons)
- After acceptance, all users under the same investor can access the folder (unchanged stakeholder-level behaviour)
- The acceptance record stores the signatory user who signed

### US-2: Non-signatory sees blocked page

**As an** LP user who is not tagged as an NDA signatory,
**I want** to see a clear message when I access an NDA-protected folder that hasn't been accepted yet,
**So that** I understand someone else must sign on my behalf.

**Acceptance criteria:**
- Non-signatory sees a blocked page with: entity logo, folder name, message "NDA acceptance is pending. A designated signatory for your organisation must accept the NDA before you can access this folder.", contact email (if configured), and "Back to Data Rooms" link
- No accept or decline buttons are shown
- Once a signatory accepts, the non-signatory can access the folder on next visit (no page refresh needed beyond re-navigating)

### US-3: GP guided to tag signatories after first NDA creation

**As a** GP user,
**I want** to be guided to tag signatories immediately after creating the first NDA on a folder,
**So that** investors can start accepting right away.

**Acceptance criteria:**
- After saving NDA settings for the first time (new NDA config creation), GP is redirected to the NDA Status Dashboard with a `first_creation=true` query param
- Dashboard shows a dismissible banner: "NDA settings saved. Tag designated signatories for each investor below."
- All investor rows are auto-expanded to show user detail rows with Tag/Untag buttons
- This prompt does NOT appear on NDA settings updates or version bumps — only on first creation

### US-4: GP sees zero-signatory warning

**As a** GP user viewing the NDA Status Dashboard,
**I want** to see a warning when an investor has no tagged signatories,
**So that** I know no one can sign the NDA for that investor.

**Acceptance criteria:**
- Investors with zero tagged signatories show a warning icon (⚠) and tooltip "No signatories tagged — no one can accept the NDA for this investor" in the Status column
- The warning is visible in all status filter views (All, Pending, Declined, etc.)

### US-5: Exempt investors bypass signatory gating

**As an** LP user whose investor is marked exempt from NDA,
**I want** to access the folder without any NDA screen,
**So that** the exemption continues to work as before.

**Acceptance criteria:**
- NDA-exempt investors bypass the gate entirely (unchanged behaviour)
- Signatory gating does not apply to exempt investors

---

## UI Behavior

### Blocked Page (Non-Signatory LP)

```
┌─────────────────────────────────────────────────────┐
│  [Entity Logo]                Back to Data Rooms ▸   │
│                                                      │
│  Non-Disclosure Agreement                            │
│                                                      │
│  [Entity Name]  |  Folder: [Folder Name]             │
│                                                      │
│  ┌─ alert-info ───────────────────────────────────┐  │
│  │ 🔒 NDA acceptance is pending. A designated     │  │
│  │    signatory for your organisation must accept  │  │
│  │    the NDA before you can access this folder.   │  │
│  └────────────────────────────────────────────────┘  │
│                                                      │
│  Questions? Contact: nda@fund.com                    │
│                                                      │
│  [ Back to Data Rooms ]                              │
│                                                      │
└─────────────────────────────────────────────────────┘
```

**Behavior notes:**
- Rendered inside `documents_frame` turbo-frame (same as declined/lapsed pages)
- Uses the same layout pattern as the existing declined and lapsed views (logo, entity context, message, contact, back link)
- No PDF iframe, no accept/decline buttons
- Shown to non-signatories only when no signatory has accepted yet for their investor

### NDA Status Dashboard — Post-First-Creation State

```
┌─────────────────────────────────────────────────────┐
│  NDA Status — [Folder Name]                          │
│                                                      │
│  ┌─ alert-success dismissible ─────────────────────┐ │
│  │ ✓ NDA settings saved. Tag designated signatories │ │
│  │   for each investor below.                   ✕   │ │
│  └──────────────────────────────────────────────────┘ │
│                                                      │
│  [Status counters]  [Send Reminders] [Export]        │
│                                                      │
│  ┌──────────────────────────────────────────────┐    │
│  │ Investor A  |  Pending  |  ⚠ No signatories  │    │
│  │  ├─ user1@co.com          [ Tag ]             │    │
│  │  └─ user2@co.com          [ Tag ]             │    │
│  │ Investor B  |  Pending  |  ⚠ No signatories  │    │
│  │  ├─ user3@co.com          [ Tag ]             │    │
│  │  └─ user4@co.com          [ Tag ]             │    │
│  └──────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────┘
```

**Behavior notes:**
- Banner appears only on first creation redirect (query param `first_creation=true`)
- Banner is dismissible (standard Bootstrap close button)
- All investor rows auto-expanded on first creation (JS: collapse show by default)
- Zero-signatory warning icon appears in status column whenever an investor has no tagged signatories

---

## What This Feature Does NOT Cover

| Excluded | Covered In |
|---|---|
| E-sign / Zoho integration for NDA signing | Future module (post-MVP) |
| Multi-signatory requirement (e.g., 2-of-3 must sign) | Future enhancement if needed |
| Auto-tagging signatories based on investor role/title | Future enhancement |
| Notification changes for signatory gating | Existing Module 8 notifications already target signatories |
| NDA settings UI changes (form fields, validation types) | Modules 1/4/5 (already shipped) |

---

## Validation Rules

| Field | Rule | Default |
|---|---|---|
| Signatory status | User must have an `NdaSignatory` record for this `NdaConfig` to accept/decline | No signatory = blocked |
| Exemption | `InvestorAccess.exempt_from_nda` bypasses signatory gating entirely | `false` |
| First-creation detection | NDA config `create` action (not `update`) triggers the signatory prompt | N/A |

---

## Behavior Rules

| Scenario | What User Sees |
|---|---|
| Signatory LP visits NDA-protected folder, NDA not yet accepted | Standard NDA acceptance screen with PDF + accept/decline |
| Non-signatory LP visits NDA-protected folder, NDA not yet accepted | Blocked page: "A designated signatory must accept" |
| Non-signatory LP visits NDA-protected folder, NDA already accepted by a signatory | Folder opens normally (stakeholder-level access) |
| Exempt LP visits NDA-protected folder | Folder opens normally (exemption bypasses everything) |
| GP creates first NDA on a folder | Redirected to NDA Status Dashboard with tagging prompt + auto-expanded rows |
| GP updates existing NDA settings (edit, version bump) | Normal modal close, no redirect to dashboard |
| Investor has zero tagged signatories | Dashboard shows ⚠ warning icon with tooltip |
| Signatory declines NDA | Decline recorded, other signatories for that investor can still accept |
| All signatories decline | Non-signatories remain blocked until a signatory accepts or GP tags new signatories |

---

## Resolved Design Decisions

| # | Decision | Resolution |
|---|---|---|
| 1 | Where does signatory gating happen — controller or policy? | Controller-level `before_action` in `NdaAcceptancesController` + gate logic in `DocumentsController#ensure_nda_accepted`. Policy remains "LP with access" — signatory check is a separate concern. |
| 2 | What do non-signatories see? | A dedicated blocked page (new view template), not a modified acceptance screen. Clean separation avoids conditional UI complexity. |
| 3 | When does the signatory tagging prompt appear? | Only on `create` action for NdaConfig (first NDA on a folder). Updates, version bumps, and edits do not trigger it. Detected by controller action, not model state. |
| 4 | Should non-signatories be able to view the NDA PDF without signing? | No — the blocked page does not show the PDF. The PDF is only shown to designated signatories on the acceptance screen. |
| 5 | What if an investor has zero signatories? | No one can accept. Dashboard shows a warning. GP must tag at least one signatory. |
| 6 | Does signatory gating apply to exempt investors? | No — exemption bypasses the entire NDA gate, including signatory checks. |

---

## Capabilities

### New Capabilities

- `nda/signatory-gating`: Restricts NDA accept/decline to designated signatories; shows blocked page to non-signatories; adds zero-signatory warnings on GP dashboard; guides GP to tag signatories after first NDA creation.

### Modified Capabilities

_(none — no existing specs are affected)_

---

## Impact

- **NDA acceptance flow:** The LP-facing acceptance screen and folder gate both gain signatory checks. Non-signatories see a new blocked page.
- **NDA Status Dashboard:** Gains zero-signatory warning icons and post-first-creation banner with auto-expanded rows.
- **NDA settings save flow:** First-time creation now redirects to the dashboard instead of closing the modal.
- **NDA acceptance policy:** Unchanged — signatory check is a controller concern, not a Pundit policy change.
- **Notifications:** No changes — Module 8 notifications already route to signatories.

---

## Benefits

1. **Compliance enforcement** — Only authorised signatories can bind their organisation to the NDA, closing the gap where any LP user could sign.
2. **Guided GP workflow** — Post-creation prompt ensures signatories are tagged immediately, preventing the "NDA enabled but no one can sign" problem.
3. **Visibility** — Zero-signatory warnings on the dashboard give GPs a clear signal to fix the gap before LPs encounter it.
4. **Non-disruptive for LPs** — Non-signatories see a clear explanation instead of a confusing form they can't use. Once a signatory accepts, access opens automatically for everyone under that investor.

---

## FAQ

| Question | Answer |
|---|---|
| Who can tag signatories? | GP employees of the entity — from the NDA Status Dashboard (unchanged from current). |
| What happens to investors who already accepted before this change? | Their acceptance stands. Signatory gating only applies to new accept/decline actions going forward. Existing accepted investors keep folder access. |
| Can an investor have multiple signatories? | Yes. Any one of them accepting opens access for the whole investor. |
| What if all signatories decline? | The investor remains in "Pending/Declined" state. Non-signatories stay blocked. The GP can tag new signatories or follow up. |
| Does this affect email notifications? | No. Module 8 notifications already target signatories for reminders and expiry alerts. |
| Is there a migration needed? | No DB migration — the `nda_signatories` table and model already exist. Only controller/view changes. |
| What about the first_creation query param — can someone abuse it? | The banner is purely cosmetic (auto-expand + dismissible message). No security impact. |
| Does the blocked page show the NDA PDF? | No. Non-signatories see only the message and contact info. |

---

## Design Principle for the Next Phase

- **Reuse the existing view pattern:** The blocked page should follow the same layout as the `declined.html.erb` and `lapsed.html.erb` templates (logo, entity context, message, contact, back link). No new layout or component framework needed.
- **Keep signatory check in the controller, not the policy:** The Pundit policy (`NdaAcceptancePolicy`) answers "is this user an LP with access?" The signatory check is a separate business rule that belongs in a `before_action`. This avoids coupling policy logic to NdaSignatory queries.
- **First-creation detection by controller action, not model flag:** Use the fact that the `NdaConfigsController#create` action is called (vs. `update`) rather than adding a boolean column. Simple and no migration needed.
