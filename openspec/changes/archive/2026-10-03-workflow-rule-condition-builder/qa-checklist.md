# Workflow Rule Condition Builder — Manual QA Checklist

> **Audience:** Testers running the feature by hand on a deployed build. No code knowledge needed.
> **Companion documents:** [Proposal](proposal.md) · [Design](design.md)

> **How to use:** work top to bottom. Tick ☐ → ☑ and write Pass or Fail for each row. For a Fail,
> put the defect link in Notes. Row IDs match the design's worked examples (H/E/X) and UI journeys
> (J), so a failure maps straight to the automated test that should have caught it.

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
| Environment | Staging |
| Accounts | Priya — fund admin of Acme Capital (can edit workflow templates); an Acme employee without template edit rights; an investor user of Acme |
| Second entity | Beta Partners, with its own admin and a KYC form "Individual — Beta" (note its id from the form type page URL) and a custom field "Tax residency" |
| Seed data | Acme Capital: Investment Fund with workflow templates enabled; KYC journeys and capital call journeys set up (Workflow Templates → Set up journeys). KYC forms "Individual — Default", "Individual — Fund IV", "Non Individual — Default". Both Individual forms have custom fields Nationality (Select: India, USA, UK), Ticket size (Number), Passport copy (File), Age (Calculation). Fund "Acme Fund IV". Duplicate "Investor KYC" and rename the copy "Investor KYC — Fund IV (domestic)". Create a commitment workflow template "Commitment — Large" |
| Background work | None. Rules apply when the record is saved |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | A form-type rule routes only that form type | Setup done | 1. Open "Investor KYC — Fund IV (domestic)" → Auto-assignment rules → New. 2. + Add condition: Form type · is · Individual — Fund IV. 3. Priority 0, tick Auto-launch, Save. 4. Create a KYC with New KYC → Individual (Fund IV). 5. Create a KYC with New KYC → Individual (Default) | KYC from step 4 shows the "Investor KYC — Fund IV (domestic)" journey; KYC from step 5 shows "Investor KYC" | | |
| ☐ | H2 | A custom option field routes by value | Rule from H1 deleted | 1. New rule on Fund IV (domestic): Nationality · is · India, priority 0. 2. Create three Individual KYCs: Nationality India, USA, left empty | Only the India KYC gets Fund IV (domestic); the others get "Investor KYC" | | |
| ☐ | H3 | Amounts are in currency units | "Commitment — Large" exists | 1. On "Commitment — Large" add rule: Committed amount · at least · 5000000. 2. In Acme Fund IV add a commitment of 6,000,000 and one of 2,000,000 | The 6,000,000 commitment gets "Commitment — Large"; the 2,000,000 one does not | | |
| ☐ | H4 | The seeded imported rule still works | Capital call journeys set up | 1. Import a capital call (call upload). 2. Create a call by hand | Imported call shows the Light journey; hand-made call shows Full | | |
| ☐ | H5 | Rules table reads in words | A rule with Form type is Individual — Fund IV and Nationality is India | Open the template page | Rules table shows "Form type is Individual — Fund IV and Nationality is India" | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | Field list contents | Setup done | 1. New rule on a KYC template. 2. + Add condition, open Field | Under "KYC fields": Form type, Verified, Expiry date. Under "Custom fields": Nationality, Ticket size. Not present: Passport copy, Age, Tax residency, PAN, Committed amount | | |
| ☐ | E8 | Totals filled in later are not offered | Setup done | 1. New rule on a capital call template, open Field. 2. New rule on "Commitment — Large", open Field | Step 1: no Call amount, Collected amount, Capital fee or Other fee. Step 2: Committed amount is offered | | |
| ☐ | E2 | Number custom field compares as a number | — | 1. Rule: Ticket size · at least · 10. 2. KYCs with Ticket size 9 and 25 | 25 gets the rule's journey; 9 does not | | |
| ☐ | E3 | "is blank" needs no value | — | 1. Rule: Nationality · is blank (value box disappears). 2. Save. 3. KYCs with no nationality and with India | Saves without a value; empty-nationality KYC matches; India does not | | |
| ☐ | E4 | Saved rule loads as rows | Rule from H5 | Edit the rule | Two rows with fields, operators and values pre-selected; no separate "KYC form type" control | | |
| ☐ | E5 | JSON round trip | — | 1. New rule, row Nationality · is · India. 2. Click View as JSON, change "India" to "UK". 3. Click View as rows. 4. Save | Row shows UK after step 3; template page shows "Nationality is UK" | | |
| ☐ | E6 | Deleted custom field | Rule Form type is Individual — Fund IV and Nationality is India | 1. Delete Nationality from both Individual forms. 2. Create a Fund IV KYC. 3. Edit the rule. 4. Click Save. 5. Remove the red row, Save | Step 2: KYC gets "Investor KYC". Step 3: red row "Unknown field: nationality". Step 4: refused with "Condition 2: Unknown field "nationality"." Step 5: saves | | |
| ☐ | E7 | Rule-only fields don't change list search | — | Ask a developer to open the KYC list with `?q[form_type_id_eq]=<Fund IV id>` | The list is unfiltered, same as before the release | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | Unknown field | — | View as JSON: `[{"attribute":"json_fields.nationalty","operator":"eq","value":"India"}]`, Save | "Condition 1: Unknown field "nationalty"." Not saved; the JSON is still there | | |
| ☐ | X2 | Wrong operator | — | View as JSON: `[{"attribute":"form_type_id","operator":"gt","value":"1"}]`, Save | "Condition 1: "greater than" can't be used with Form type." Not saved | | |
| ☐ | X3 | Another company's form type | Beta's form id noted | View as JSON: `[{"attribute":"form_type_id","operator":"eq","value":"<Beta id>"}]`, Save | "Condition 1: Form type <Beta id> is not one of this company's form types." Not saved | | |
| ☐ | X4 | Non-number and missing value | — | View as JSON: `[{"attribute":"json_fields.ticket_size","operator":"gteq","value":"abc"},{"attribute":"json_fields.nationality","operator":"eq","value":""}]`. Save | "Condition 1: Ticket size needs a number." and "Condition 2: Nationality needs a value." Not saved | | |
| ☐ | X5 | Malformed JSON | — | View as JSON: `{"attribute":"verified"}`, Save | "The JSON is not a valid list of conditions." No error page | | |
| ☐ | X6 | A condition the search cannot apply is skipped | Developer-only | Ask a developer to run the automated scenario X6 and confirm the log line | Rule does not match; log has "[WorkflowRuleMatcher] Rule <id>: Ransack applied" | | |

---

## UI Journeys

Journey 1: add a KYC rule by form type and custom field (design [What users see](design.md#what-users-see)).

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J1.1 | New Auto-Assignment Rule | Click "+ Add condition" | A new row with an empty Field dropdown | | |
| ☐ | J1.2 | same | Pick a field | Operator list fills with that field's operators; Value becomes the right input (dropdown, number, date, text) | | |
| ☐ | J1.3 | same | Pick "is blank", then "is one of" | Value hides for "is blank"; becomes multi-select for "is one of" | | |
| ☐ | J1.4 | same | Pick or type a value | Row complete | | |
| ☐ | J1.5 | same | Click ✕ on a row | Row disappears | | |
| ☐ | J1.6 | same | Click "View as JSON", then "View as rows" | JSON textarea with the same conditions; rows come back unchanged | | |
| ☐ | J1.7 | same | Click Save | Template page with notice "Auto-assignment rule created.", or the form with numbered condition errors | | |
| ☐ | J1.8 | same, a Date field (e.g. Commitment date on a commitment template) | Pick a date | Date shows in your locale format (e.g. 19/08/2026 for en) | | |

---

## Role Sweep

| ID | Screen / action | Fund admin (Priya) | Employee without template edit | Investor | Other-entity admin |
|---|---|---|---|---|---|
| R1 | Open New / Edit rule on an Acme template | ✓ | ✗ | ✗ | ✗ |
| R2 | Save a rule | ✓ | ✗ | ✗ | ✗ |
| R3 | See the rules table on the template page | ✓ | as today | ✗ | ✗ |
| R4 | See Acme's form types / custom fields in their own rule builder | — | — | — | ✗ (never listed) |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Emails / alerts sent by this feature arrive | N/A — the feature sends none | | |
| ☐ | C2 | Dates on changed screens | Date conditions in the rules table and date inputs follow the user's locale format | | |
| ☐ | C3 | Narrow / mobile width | Builder rows stack; no horizontal scroll; ✕ and + Add condition reachable | | |
| ☐ | C4 | Tenant isolation | Beta's admin never sees Acme's form types or custom fields; a direct URL to an Acme rule is denied | | |
| ☐ | C5 | Regression on modified screens | Template page rules table, rule edit/delete, duplicate template, KYC journey setup and capital call journey setup all still work | | |
| ☐ | C6 | Empty states | New rule with no rows shows "No conditions = applies to every new …"; a rule with none reads "Always (catch-all)" | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
