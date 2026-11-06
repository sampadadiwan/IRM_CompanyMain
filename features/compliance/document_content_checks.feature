Feature: Document-content checks (AI reading)
  AI reads the declared facts of a document once per version, with quote and page; a person confirms
  them; plain rules compare the confirmed facts with CapHive's records and reference lists. AI never
  decides pass or fail. The AI is stubbed at LlmService.
  Worked examples: openspec/changes/archive/2026-11-06-fund-compliance-monitoring/business-rules.md (group 9)

  Background:
    Given the Horizon compliance setup
    And Horizon checks IC note contents on "Horizon Growth Fund I"
    And "Horizon Growth Fund I" invested ₹18.0 cr in "Orbit Health" on "2026-10-05"

  # H40 — Happy path: Arjun uploads the Orbit IC note; AI reads it once — "AI-read — 6 facts to confirm", each with quote + page
  Scenario: H40 Read on upload
    Given AI reading is on for the "IC note" input
    And the document AI reads the Orbit Health IC note
    When "Arjun" uploads the IC note of "Orbit Health"
    And the documents are read
    Then the IC note of "Orbit Health" shows "AI-read — 6 facts to confirm"
    And the IC note fact "Amount approved" of "Orbit Health" reads "₹15.00 cr" from "INR 15 crore" on page 2
    And the IC note fact "Signatories" of "Orbit Health" reads "A. Rao, K. Shah, M. Iyer" from "Signed:" on page 3
    And 1 document was sent to the AI
    When the documents are read
    Then 1 document was sent to the AI

  # H41 — Happy path: confirmed ₹15.00 cr approved, ₹18.00 cr invested — Breach "₹3.00 cr over approved"
  Scenario: H41 Invested more than approved
    Given the IC note of "Orbit Health" has been read and confirmed
    When the nightly compliance run happens on "2026-11-07"
    Then the "Invested within IC approval" check on "Horizon Growth Fund I" is "breach"
    And the working shows "₹18.00 cr invested > ₹15.00 cr approved — ₹3.00 cr over approved"
    And the "Invested within IC approval" item on "Horizon Growth Fund I" is "open"

  # H42 — Happy path: 3 listed IC members signed, quorum 3 — 3 ≥ 3 passes
  Scenario: H42 Quorum met
    Given the IC note of "Orbit Health" has been read and confirmed
    When the nightly compliance run happens on "2026-11-07"
    Then the "IC quorum" check on "Horizon Growth Fund I" is "pass"

  # H43 — Happy path: reading off; Meera enters and confirms the facts by hand; the next run compares them
  Scenario: H43 Facts by hand
    Given AI reading is off for the "IC note" input
    And the document AI reads the Orbit Health IC note
    When "Arjun" uploads the IC note of "Orbit Health"
    And "Meera" enters the IC note facts of "Orbit Health" by hand:
      | company         | Orbit Health            |
      | amount_approved | 150000000               |
      | approval_date   | 2026-09-28              |
      | signatories     | A. Rao, K. Shah, M. Iyer |
      | conflicts       |                         |
      | business        | digital health clinics  |
    And the nightly compliance run happens on "2026-11-07"
    Then no document was sent to the AI
    And the "Invested within IC approval" check on "Horizon Growth Fund I" is "breach"
    And the working shows "₹3.00 cr over approved"
    And the "IC quorum" check on "Horizon Growth Fund I" is "pass"

  # H44 — Happy path: a new PPM version uploaded with reading on — PPM review duty with AI notes, Due until marked done
  Scenario: H44 PPM notes
    Given AI reading is on for the "PPM" input
    And the document AI reads the PPM changes as "Section 4 (fees) changed: management fee 2% → 1.75%"
    When a new PPM version is uploaded to "Horizon Growth Fund I"
    And the documents are read
    Then "Horizon Growth Fund I" has a "PPM change review" duty with AI notes "Section 4 (fees) changed" that is "due"
    When the nightly compliance run happens on "2026-11-07"
    Then "Horizon Growth Fund I" has a "PPM change review" duty with AI notes "management fee 2% → 1.75%" that is "due"

  # H45 — Happy path: an IC note uploaded before reading was on is read when Meera presses Read now
  Scenario: H45 Read now
    Given the IC note of "Orbit Health" was uploaded on "2026-10-06"
    And AI reading is on for the "IC note" input
    And the document AI reads the Orbit Health IC note
    When the documents are read
    Then no document was sent to the AI
    When "Meera" presses Read now on the IC note of "Orbit Health"
    Then the IC note of "Orbit Health" shows "AI-read — 6 facts to confirm"

  # E66 — Edge case: facts that would satisfy every rule but are unconfirmed — Needs review "AI-read, unconfirmed", never Pass
  Scenario: E66 Unconfirmed never passes
    Given the IC note of "Orbit Health" has been read with:
      | amount_approved | 200000000 |
    When the nightly compliance run happens on "2026-11-07"
    Then the "Invested within IC approval" check on "Horizon Growth Fund I" is "needs_review"
    And the working shows "Needs review — AI-read, unconfirmed"
    And the "IC quorum" check on "Horizon Growth Fund I" is "needs_review"

  # E67 — Edge case: AI read ₹1.50 cr; Meera sets ₹15.00 cr and confirms — history recorded; the run breaches 18.00 > 15.00
  Scenario: E67 Misread corrected
    Given the IC note of "Orbit Health" has been read with:
      | amount_approved | 15000000 |
    Then the IC note fact "Amount approved" of "Orbit Health" shows "₹1.50 cr"
    When "Meera" sets the IC note fact "Amount approved" of "Orbit Health" to "150000000" and confirms on "2026-11-06"
    Then the history of the IC note fact "Amount approved" of "Orbit Health" shows "AI read ₹1.50 cr → Meera set ₹15.00 cr, 06/11/2026"
    When the nightly compliance run happens on "2026-11-07"
    Then the "Invested within IC approval" check on "Horizon Growth Fund I" is "breach"
    And the working shows "₹3.00 cr over approved"

  # E68 — Edge case: a confirmed note's file is replaced — its facts become unconfirmed and it is read again
  Scenario: E68 Replaced document
    Given the IC note of "Orbit Health" has been read and confirmed
    When "Arjun" replaces the IC note file of "Orbit Health"
    And the documents are read
    Then the IC note of "Orbit Health" shows "AI-read — 6 facts to confirm"
    And the IC note facts of "Orbit Health" are all unconfirmed
    And 2 documents were sent to the AI

  # E69 — Edge case: the note has no conflicts section — "Not found in document"; the conflicts check is Needs review
  Scenario: E69 Fact not found
    Given the IC note of "Orbit Health" has been read with:
      | conflicts | NOT FOUND |
    Then the IC note fact "Conflicts" of "Orbit Health" shows "Not found in document"
    When the nightly compliance run happens on "2026-11-07"
    Then the "No conflicted member approved" check on "Horizon Growth Fund I" is "needs_review"
    And the working shows "Needs review — Conflicts not found in document"

  # E70 — Edge case: approved ₹18.00 cr equals invested — 18.00 ≤ 18.00 passes
  Scenario: E70 Approved equals invested
    Given the IC note of "Orbit Health" has been read and confirmed with:
      | amount_approved | 180000000 |
    When the nightly compliance run happens on "2026-11-07"
    Then the "Invested within IC approval" check on "Horizon Growth Fund I" is "pass"

  # E71 — Edge case: approval dated 05 Oct (the investment date) passes; corrected to 06 Oct it breaches
  Scenario: E71 Approval date boundary
    Given the IC note of "Orbit Health" has been read and confirmed with:
      | approval_date | 2026-10-05 |
    When the nightly compliance run happens on "2026-11-07"
    Then the "Approved before investing" check on "Horizon Growth Fund I" is "pass"
    When "Meera" sets the IC note fact "Approval date" of "Orbit Health" to "2026-10-06" and confirms on "2026-11-07"
    And the nightly compliance run happens on "2026-11-08"
    Then the "Approved before investing" check on "Horizon Growth Fund I" is "breach"
    And the working shows "Approval date 06/10/2026 is after the record date 05/10/2026"

  # E72 — Edge case: 2 members signed, quorum 3 — 2 < 3 breach
  Scenario: E72 Quorum short
    Given the IC note of "Orbit Health" has been read and confirmed with:
      | signatories | A. Rao, K. Shah |
    When the nightly compliance run happens on "2026-11-07"
    Then the "IC quorum" check on "Horizon Growth Fund I" is "breach"
    And the working shows "2 IC members signed, quorum 3"

  # E73 — Edge case: signed by A. Rao, K. Shah and P. Das (not listed) — members 2 < 3, breach naming P. Das
  Scenario: E73 Non-member signatory
    Given the IC note of "Orbit Health" has been read and confirmed with:
      | signatories | A. Rao, K. Shah, P. Das |
    When the nightly compliance run happens on "2026-11-07"
    Then the "IC quorum" check on "Horizon Growth Fund I" is "breach"
    And the working shows "P. Das — not an IC member"

  # E74 — Edge case: reading not enabled; an IC note uploaded — nothing sent to AI; "Needs review — reading not enabled"
  Scenario: E74 Reading off
    Given the document AI reads the Orbit Health IC note
    When "Arjun" uploads the IC note of "Orbit Health"
    And the hourly compliance tick happens at "2026-11-07 02:00" "Asia/Kolkata"
    And the nightly compliance run happens on "2026-11-07"
    Then no document was sent to the AI
    And the "Invested within IC approval" check on "Horizon Growth Fund I" is "needs_review"
    And the working shows "Needs review — reading not enabled"

  # E75 — Edge case: cap 200 with 199 read — the 200th is read, the 201st queues; the digest says "1 document waiting"
  Scenario: E75 Cap boundary
    Given AI reading is on for the "IC note" input
    And the monthly reading cap is 200
    And 199 documents were already read this month
    And "Horizon Growth Fund I" invested ₹5.0 cr in "Kite Pay" on "2026-10-20"
    And the document AI reads the Orbit Health IC note
    When "Arjun" uploads IC notes for "Orbit Health" and "Kite Pay"
    And the documents are read
    Then the IC note of "Orbit Health" is "read"
    And the IC note of "Kite Pay" is "capped"
    And 1 document was sent to the AI
    When the compliance digest is sent on "2026-11-07"
    Then the digest lines include "1 document waiting — cap reached"

  # E76 — Edge case: the note names "Orbit Labs Pvt Ltd" — Breach naming both
  Scenario: E76 Company mismatch
    Given the IC note of "Orbit Health" has been read and confirmed with:
      | company | Orbit Labs Pvt Ltd |
    When the nightly compliance run happens on "2026-11-07"
    Then the "IC note names the investee" check on "Horizon Growth Fund I" is "breach"
    And the working shows "Document names Orbit Labs Pvt Ltd; record is Orbit Health"

  # E77 — Edge case: the file tagged "IC Note" on Orbit Health is Kite Pay's — Needs review "appears to concern Kite Pay"
  Scenario: E77 Wrong deal
    Given the IC note of "Orbit Health" has been read and confirmed with:
      | company | Kite Pay Private Limited |
    When the nightly compliance run happens on "2026-11-07"
    Then the "IC note names the investee" check on "Horizon Growth Fund I" is "needs_review"
    And the working shows "Document appears to concern Kite Pay"

  # E78 — Edge case: business "tobacco products" — Breach "Excluded sector: Tobacco"
  Scenario: E78 Excluded sector
    Given the IC note of "Orbit Health" has been read and confirmed with:
      | business | tobacco products |
    When the nightly compliance run happens on "2026-11-07"
    Then the "Not in an excluded sector" check on "Horizon Growth Fund I" is "breach"
    And the working shows "Excluded sector: Tobacco"

  # E79 — Edge case: director V. Menon is on the sponsor's associates list — related-party breach naming V. Menon
  Scenario: E79 Associate director
    Given AI reading is on for the "investee profile" input
    And the document AI reads the directors "S. Kapoor, V. Menon"
    When "Arjun" uploads the investee profile of "Orbit Health"
    And the documents are read
    And "Meera" confirms the investee profile facts of "Orbit Health"
    And the nightly compliance run happens on "2026-11-07"
    Then the "No sponsor associate among directors" check on "Horizon Growth Fund I" is "breach"
    And the working shows "Related party among directors: V. Menon"

  # E136 — Edge case: SEBI v1.1 — an investor's confirmed owner countries include China — Needs review naming China
  Scenario: E136 Land-border owner
    Given SEBI v1.1 is published effective "2026-12-02"
    And "Border Test Fund" is a SEBI fund whose investors commit "Alpha LP = 60; Beta LP = 40"
    And the confirmed KYC ownership of "Alpha LP" lists owners "Lee Holdings" in "China, Singapore"
    And the confirmed KYC ownership of "Beta LP" lists owners "Rao Family Trust" in "India"
    When the nightly compliance run happens on "2026-12-05" for "Border Test Fund"
    Then the "Beneficial owner in a land-border country" check on "Border Test Fund" is "needs_review"
    And the working shows "Alpha LP"
    And the working shows "Beneficial owner in a land-border country: China"
    And the working does not show "Beta LP"

  # X44 — Error case: adding "Amount approved" to the IC note input without a type — "Choose a fact type"
  Scenario: X44 Fact without type
    When "Meera" adds the fact "Amount approved" to the IC note input without a type
    Then the definition is refused with "Choose a fact type"

  # X45 — Error case: a blurred scan — "Could not read document"; checks Needs review; nothing sent; manual entry offered
  Scenario: X45 Unreadable scan
    Given AI reading is on for the "IC note" input
    And the document AI reads the Orbit Health IC note
    When "Arjun" uploads a blurred scan as the IC note of "Orbit Health"
    And the documents are read
    Then the IC note of "Orbit Health" shows "Could not read document"
    And no document was sent to the AI
    When the nightly compliance run happens on "2026-11-07"
    Then the "Invested within IC approval" check on "Horizon Growth Fund I" is "needs_review"
    And the working shows "Needs review — could not read document"
    When "Meera" enters the IC note facts of "Orbit Health" by hand:
      | amount_approved | 150000000 |
    And the nightly compliance run happens on "2026-11-08"
    Then the "Invested within IC approval" check on "Horizon Growth Fund I" is "breach"

  # X46 — Error case: the AI provider errors while reading — as X45; Read now retries
  Scenario: X46 AI error while reading
    Given AI reading is on for the "IC note" input
    And the document AI fails with a provider error
    When "Arjun" uploads the IC note of "Orbit Health"
    And the documents are read
    Then the IC note of "Orbit Health" shows "Could not read document"
    Given the document AI reads the Orbit Health IC note
    When "Meera" presses Read now on the IC note of "Orbit Health"
    Then the IC note of "Orbit Health" shows "AI-read — 6 facts to confirm"

  # X47 — Error case: R. Mehta declared a conflict and also signed — Breach "Conflicted member approved: R. Mehta"
  Scenario: X47 Conflicted member signed
    Given the IC note of "Orbit Health" has been read and confirmed with:
      | signatories | A. Rao, K. Shah, R. Mehta |
      | conflicts   | R. Mehta                  |
    When the nightly compliance run happens on "2026-11-07"
    Then the "No conflicted member approved" check on "Horizon Growth Fund I" is "breach"
    And the working shows "Conflicted member approved: R. Mehta"
