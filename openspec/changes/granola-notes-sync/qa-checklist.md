# Granola Meeting Notes Sync — Manual QA Checklist

> **Audience:** Testers running the feature by hand on a deployed build. No code knowledge needed.
> **Companion documents:** [Proposal](proposal.md) · [Design](design.md)

> **How to use:** work top to bottom. Tick ☐ → ☑ and write Pass or Fail for each row. For a Fail,
> put the defect link in Notes. Row IDs match the design's worked examples (H/E/X) and UI journeys
> (J), so a failure maps straight to the automated test that should have caught it. Rows marked
> **🛠 Dev-assisted** need a developer to set something up or fast-forward time.

**ID legend:** **H** = Happy path · **E** = Edge case · **X** = Error case · **J** = UI journey
step (J2.3 = journey 2, step 3) · **R** = Role sweep · **C** = Cross-cutting check

---

## Contents

- [Test Setup](#test-setup)
- [Happy Path](#happy-path)
- [Edge Cases](#edge-cases)
- [Error Cases](#error-cases)
- [UI Journeys](#ui-journeys)
- [Role Sweep](#role-sweep)
- [Cross-cutting Checks](#cross-cutting-checks)
- [Sign-off](#sign-off)

---

## Test Setup

| Item | Detail |
|---|---|
| Environment | Staging (IN or US; the two are separate, so test the one being released) |
| Fund entity | **Alpha Capital** |
| Accounts | **Priya**, fund admin (priya@alphacap.com). **Raj**, fund employee, not admin (raj@alphacap.com). **Olivia**, a user in a *different* entity (for isolation checks) |
| Investors + contacts | Acme Pension: Jane Doe, jane@acmepension.com. Acme Co-invest SPV: Mark Lee, mark@acmepension.com. Bluewater FO: Ann Roy, ann@bluewater.co |
| Granola | Two Granola test accounts with API access: Raj's personal one and the fund's workspace (admin: Priya). Their API keys come from Granola → Settings → API. A deliberately invalid key: `grn_bad` |
| Creating test meetings | In Granola, record short meetings whose calendar invite includes the attendee emails each row lists. Summaries only need to contain the quoted text |
| Making sync run now | Click **Sync now** on the relevant panel and wait up to a minute. Only rows marked 🛠 need a developer |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Connect a personal Granola key | Log in as Raj; not connected | 1. My profile → Granola panel. 2. Paste Raj's key. 3. Click **Connect** | Status **Connected**; key shown as `grn_••••••••` + last 4 characters; after a few minutes "Last sync" shows a time | | |
| ☐ | H2 | Meeting with one LP is filed automatically | H1 done. In Granola, Raj records "Q3 check-in" with jane@acmepension.com; summary "Reaffirmed Fund III"; private note "Pushy on fees" | 1. Click **Sync now**. 2. Open Acme Pension → Notes tab | One note: dated on the meeting date, "By Raj", "With: Jane Doe", tag `granola`, the summary, a "Private notes" heading with "Pushy on fees", and an **Open in Granola ↗** link that opens the meeting | | |
| ☐ | H3 | Syncing again adds nothing | H2 done | 1. Click **Sync now** twice. 2. Reopen Acme Pension → Notes | Still exactly one note for that meeting | | |
| ☐ | H4 | Meeting with two LPs goes to review, then filed to both | Raj records "Co-invest sync" with jane@ and mark@acmepension.com | 1. Sync now. 2. Log in as Priya → Investors menu → **Granola Inbox**. 3. Tick Acme Pension and Acme Co-invest SPV. 4. Click **File** | After step 2: the row shows "attendees belong to 2 investors" and both candidates. After File: the row disappears, the count drops by 1, and each investor has the note | | |
| ☐ | H5 | Domain-only match, filed to one investor | Raj records "Intro call" with tom@bluewater.co (not a contact) | 1. Sync now. 2. Priya → Granola Inbox. 3. Tick Bluewater FO, click **File** | Row shows "email domain match only". After File: Bluewater FO has the note | | |
| ☐ | H6 | Granola edits flow through | H2's note not edited in CapHive | 1. In Granola, change the summary to "Reaffirmed Fund III and IV". 2. Sync now. 3. Reopen the note | The note shows the new summary | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | Same meeting through two keys isn't duplicated | Priya connects the workspace (Entity settings → Granola workspace); the H2 meeting is shared to the workspace | 1. Sync now on both panels. 2. Open Acme Pension → Notes | Still one note, by Raj, with private notes | | |
| ☐ | E2 | Internal-only meeting is not imported | Raj records a meeting with only priya@ and raj@alphacap.com | 1. Sync now. 2. Check Inbox (both tabs) and investors' notes | No note anywhere. It appears only in Inbox → **Ignored**, with no summary text | | |
| ☐ | E3 | A stranger on gmail isn't matched | Raj records a meeting with stranger@gmail.com | 1. Sync now. 2. Check the Inbox | Only in **Ignored**; no investor suggested | | |
| ☐ | E4 | An old meeting doesn't rewind "last interaction" | 🛠 Dev-assisted: a meeting dated 01/08/2026 exists in Granola, and Acme Pension's last interaction is later | 1. Sync now. 2. Check Acme Pension's last interaction date | Note filed; last interaction date **unchanged** | | |
| ☐ | E5 | Workspace meeting owned by an outsider | Workspace connected by Priya; the meeting owner advisor@consult.io has no CapHive login; attendee jane@ | 1. Sync now (workspace). 2. Open the note | Author Priya, with "Imported from Granola (owner: advisor@consult.io)"; **no** private notes | | |
| ☐ | E6 | A note edited in CapHive is protected | H2's note exists | 1. Priya edits it and adds "Follow up in Nov". 2. Change the summary in Granola. 3. Sync now | The note keeps "Follow up in Nov" and shows "Edited in CapHive — later Granola changes are not applied" | | |
| ☐ | E7 | A deleted note stays deleted | H2's note exists | 1. Priya deletes it. 2. Change the meeting in Granola. 3. Sync now | No note reappears on Acme Pension | | |
| ☐ | E8 | Discard sticks | A meeting is in the Inbox | 1. Click **Discard**. 2. Change the meeting in Granola. 3. Sync now | Row gone and doesn't come back | | |
| ☐ | E9 | Rescue an ignored meeting | A meeting with sam@startup.io is in **Ignored** | 1. Add sam@startup.io as a stakeholder of Bluewater FO. 2. Back in Ignored, click **Re-match** | Row leaves Ignored; the note appears on Bluewater FO | | |
| ☐ | E10 | Employees see only their own meetings | Inbox has one of Raj's meetings and one resolved to Priya | 1. Raj opens the Granola Inbox. 2. Priya opens it | Raj sees only his; Priya sees both | | |
| ☐ | E11 | Disconnect keeps notes | H2 done | 1. Raj clicks **Disconnect** and confirms | Panel back to Not connected; Acme Pension's note is still there | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | Invalid key | Raj not connected | 1. Paste `grn_bad`. 2. Click **Connect** | Under the field: "Granola rejected this API key. Check it and try again." Still Not connected | | |
| ☐ | X2 | Non-admins can't connect the workspace | Log in as Raj | 1. Open Entity settings | No Granola workspace section | | |
| ☐ | X3 | No second personal connection | Raj connected | 🛠 Dev-assisted: submit another connection for Raj (not possible from the UI) | Refused; nothing changes | | |
| ☐ | X4 | Revoked key | Raj connected | 1. Revoke the key in Granola. 2. Sync now. 3. Check Raj's email and bell. 4. Paste a new valid key | Step 2: panel turns red **Needs attention** with a reason. Step 3: email and bell alert "Granola connection needs attention". Step 4: Connected again, and new meetings arrive | | |
| ☐ | X5 | Granola down for a day | 🛠 Dev-assisted: simulate 24h of failures | — | Exactly one alert to Raj; none again until a sync succeeds | | |
| ☐ | X6 | Can't file to another fund's investor | 🛠 Dev-assisted: submit File with an investor id from another entity | — | "Investor not found"; nothing filed | | |
| ☐ | X7 | Re-match after disconnect | Raj disconnected; one of his meetings in Ignored | 1. Priya clicks **Re-match** on it | "The Granola connection that imported this meeting has been disconnected — reconnect to re-match" | | |

---

## UI Journeys

Check that each numbered callout ①②③ on the design's wireframes ([UI Changes](design.md#ui-changes)) looks and behaves as described.

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J1.1 | My profile → Granola | Open it (not connected) | ① Not connected, ② empty key field + "Where do I find my key?", ③ the private-notes visibility warning | | |
| ☐ | J1.2 | same | Connect with a valid key | Panel switches to Connected with the masked key | | |
| ☐ | J1.3 | same | Wait a few minutes | ⑤ "Last sync … — N filed, N to review" | | |
| ☐ | J1.4 | same | Click ⑥ **Sync now** | "Sync started" message | | |
| ☐ | J1.5 | same | Click ⑦ **Disconnect** | A confirmation prompt first; then Not connected | | |
| ☐ | J2.1 | Investor → Notes | Open a filed Granola note | ① `granola` tag, ② "With: <contact>", ③ summary, ④ **Open in Granola ↗** | | |
| ☐ | J2.2 | same | Edit the note, then open it again after a Granola change | ⑤ "Edited in CapHive" line visible | | |
| ☐ | J3.1 | Investors menu | Look at the menu (fund with a connection) | "Granola Inbox (n)" with the correct count | | |
| ☐ | J3.2 | Investors menu | Same, for a fund with **no** connection | No Granola Inbox link | | |
| ☐ | J3.3 | Granola Inbox | Open a row | ② title/date/owner, ③ reason, ④ candidates, ⑤ "Other investor" search | | |
| ☐ | J3.4 | same | Tick nothing | ⑥ **File** greyed out | | |
| ☐ | J3.5 | same | Search ⑤ for an investor that isn't a candidate, pick it, File | Filed to that investor | | |
| ☐ | J3.6 | same | File or Discard | Row disappears **without a page reload**; count updates | | |
| ☐ | J4.1 | Granola Inbox → Ignored | Open the tab | Rows show title, date and attendees only (no summary) | | |
| ☐ | J5.1 | Email | Open the needs-attention email | The link goes to the right panel (profile or entity settings) | | |

---

## Role Sweep

✓ = allowed and works · ✗ = correctly blocked or hidden · ! = wrong (log a defect)

| ID | Screen / action | Fund admin (Priya) | Employee (Raj) | Investor user | Other-entity user (Olivia) |
|---|---|---|---|---|---|
| R1 | Granola panel on own profile | | | | |
| R2 | Granola workspace panel in entity settings | | | | |
| R3 | Open the Granola Inbox | | | | |
| R4 | See another user's meeting in the Inbox | | | | |
| R5 | File / Discard / Re-match | | | | |
| R6 | Open an imported Granola note by direct URL | | | | |

Expected: R1 ✓ ✓ ✗ ✗ · R2 ✓ ✗ ✗ ✗ · R3 ✓ ✓ ✗ ✗ · R4 ✓ ✗ ✗ ✗ · R5 ✓ ✓(own) ✗ ✗ · R6 ✓ ✓(own) ✗ ✗

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Needs-attention email | Arrives for the person who connected; any date shown as `Sep 30, 2026` | | |
| ☐ | C2 | Dates on the panel, Inbox and notes | Follow the user's locale (e.g. `30/09/2026` for en) | | |
| ☐ | C3 | Narrow / mobile width | Panel and Inbox usable with no horizontal scroll | | |
| ☐ | C4 | Tenant isolation | Olivia can't open any Alpha Capital meeting, connection or note, even by direct URL | | |
| ☐ | C5 | Regression: My profile, Entity settings, Investor Notes tab, Investors menu | Everything that worked before still works (edit profile, save settings, add a manual note) | | |
| ☐ | C6 | Empty states | Inbox with nothing to review shows a friendly empty message | | |
| ☐ | C7 | Manual notes unaffected | Adding a manual note still sets the investor's last interaction as before | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
