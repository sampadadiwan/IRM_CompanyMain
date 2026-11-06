Feature: Changes over time
  History is never rewritten; dated reference lists; approvals; corrections; dates and periods.
  Worked examples: openspec/changes/archive/2026-11-06-fund-compliance-monitoring/business-rules.md (group 11)

  Background:
    Given the Horizon compliance setup

  # H54 — Happy path: R. Mehta (to 15 Oct 2026) counts on a note signed 15 Oct — 3 members ≥ quorum 3
  Scenario: H54 Member on last day
    Given Horizon checks IC note contents on "Horizon Growth Fund I"
    And the dated IC members list
    And "Horizon Growth Fund I" invested ₹18.0 cr in "Orbit Health" on "2026-10-20"
    And the IC note of "Orbit Health" has been read and confirmed with:
      | approval_date | 2026-10-15                |
      | signatories   | A. Rao, K. Shah, R. Mehta |
    When the nightly compliance run happens on "2026-11-07"
    Then the "IC quorum" check on "Horizon Growth Fund I" is "pass"

  # H55 — Happy path: Cat II → Cat II — LVF approved 12 Nov — 12 Nov uses 25%, 13 Nov uses 50%; pending before
  Scenario: H55 Classification change
    When "Meera" requests to classify "Horizon Growth Fund I" as "Category II — LVF" under SEBI
    Then the classification change is "pending"
    When the nightly compliance run happens on "2026-11-12"
    Then the "Single-investee concentration" check on "Horizon Growth Fund I" is "breach"
    And the working shows "> 25%"
    When "Rahul" approves the latest request
    And the nightly compliance run happens on "2026-11-13"
    Then the "Single-investee concentration (Large Value Fund)" check on "Horizon Growth Fund I" is "pass"
    And the working shows "≤ 50%"

  # H56 — Happy path: remapping Sponsor on 12 Nov — 11 Nov unchanged, 13 Nov uses the new mapping; history row
  Scenario: H56 Mapping change
    When the nightly compliance run happens on "2026-11-11"
    And "Meera" remaps the sponsor/manager input to "Promoter" on "2026-11-12"
    And the nightly compliance run happens on "2026-11-13"
    Then the "Continuing interest — amount" result of "Horizon Growth Fund I" on "2026-11-11" is still "pass" with "₹6.00 cr"
    And the "Continuing interest — amount" check on "Horizon Growth Fund I" is "breach"
    And the setup history records the sponsor/manager mapping change

  # H57 — Happy path: v2.1 corrects v2 on the same effective date — v2 results superseded; fault-only items "Pack corrected"
  Scenario: H57 Correction version
    Given SEBI v2 with a wrong investor limit of 100 is published on "2026-12-01" effective "2027-01-01"
    When the nightly compliance run happens on "2027-01-01"
    Then the "Investors in scheme" check on "Horizon Growth Fund I" is "breach"
    Given SEBI v2.1 correcting the investor limit to 1000 is published on "2027-01-02" effective "2027-01-01"
    When the nightly compliance run happens on "2027-01-03"
    Then the v2 results of "Horizon Growth Fund I" are marked "Superseded — pack correction"
    And the "Investors in scheme" item on "Horizon Growth Fund I" is closed as "Pack corrected"

  # H58 — Happy path: the export states its data basis
  Scenario: H58 Export basis
    When the nightly compliance run happens on "2026-09-30"
    And "Meera" exports the register from "2026-07-01" to "2026-09-30"
    Then the export states "Computed on data as entered at run time"

  # H59 — Happy path: Anil (company admin) approves Meera's override
  Scenario: H59 Company admin approves
    When "Meera" requests an override of "Single-investee concentration" on "Horizon Growth Fund I" to 20 because "Board policy 2026-07"
    And "Anil" approves the latest request
    Then the override request is "approved"

  # H60 — Happy path: a dated list entry is saved with both dates
  Scenario: H60 Dated list entry
    When "Meera" saves the IC member "R. Mehta" from "2025-04-01" to "2026-10-15"
    Then the setup saves
    And the IC member "R. Mehta" is stored from "2025-04-01" to "2026-10-15"

  # H61 — Happy path: FY basis — quarters end 30 Jun, 30 Sep, 31 Dec, 31 Mar; the year ends 31 Mar
  Scenario: H61 FY period basis
    Then on the "fy_apr" basis "2026-05-10" is in quarter "FY27-Q1" ending "2026-06-30"
    And on the "fy_apr" basis "2026-08-10" is in quarter "FY27-Q2" ending "2026-09-30"
    And on the "fy_apr" basis "2026-11-10" is in quarter "FY27-Q3" ending "2026-12-31"
    And on the "fy_apr" basis "2027-02-10" is in quarter "FY27-Q4" ending "2027-03-31"
    And on the "fy_apr" basis "2026-11-10" is in year "FY27" ending "2027-03-31"

  # E103 — Edge case: signed 16 Oct by Rao, Shah, Mehta — Mehta left 15 Oct — 2 < 3, naming R. Mehta
  Scenario: E103 Member day after "to"
    Given Horizon checks IC note contents on "Horizon Growth Fund I"
    And the dated IC members list
    And "Horizon Growth Fund I" invested ₹18.0 cr in "Orbit Health" on "2026-10-20"
    And the IC note of "Orbit Health" has been read and confirmed with:
      | approval_date | 2026-10-16                |
      | signatories   | A. Rao, K. Shah, R. Mehta |
    When the nightly compliance run happens on "2026-11-07"
    Then the "IC quorum" check on "Horizon Growth Fund I" is "breach"
    And the working shows "2 IC members signed, quorum 3"
    And the working shows "R. Mehta — not an IC member on 16/10/2026"

  # E104 — Edge case: S. Nair from 05 Oct counts on a note signed 05 Oct
  Scenario: E104 "From" equals signed date
    Given Horizon checks IC note contents on "Horizon Growth Fund I"
    And the dated IC members list
    And "Horizon Growth Fund I" invested ₹18.0 cr in "Orbit Health" on "2026-10-20"
    And the IC note of "Orbit Health" has been read and confirmed with:
      | approval_date | 2026-10-05               |
      | signatories   | A. Rao, K. Shah, S. Nair |
    When the nightly compliance run happens on "2026-11-07"
    Then the "IC quorum" check on "Horizon Growth Fund I" is "pass"

  # E105 — Edge case: blank dates mean always — A. Rao counts on a 2019 note
  Scenario: E105 Blank dates = always
    Given the dated IC members list
    Then on "2019-06-01" the IC members among "A. Rao" are 1 against quorum 3

  # E106 — Edge case: an investor committing on the duty's from date (01 Nov) gets a duty due 16 Nov
  Scenario: E106 Event "from" equals record date
    Given a new investor "First Day LP" commits ₹2.0 cr to "Horizon Growth Fund I" on "2026-11-01"
    When the nightly compliance run happens on "2026-11-05"
    Then "Horizon Growth Fund I" has a due-diligence duty for "First Day LP" due "2026-11-16"

  # E107 — Edge case: 316 imported — 312 dated before 01 Nov, 4 on/after — 4 duties
  Scenario: E107 Import straddles from date
    Given 312 investors committing on "2026-10-20" and 4 on "2026-11-02" are imported into "Horizon Growth Fund I"
    When the nightly compliance run happens on "2026-11-05"
    Then "Horizon Growth Fund I" has 4 due-diligence duties

  # E108 — Edge case: 312 new investors after the from date are one digest line
  Scenario: E108 Bulk digest line
    Given 0 investors committing on "2026-10-20" and 312 on "2026-11-02" are imported into "Horizon Growth Fund I"
    When the nightly compliance run happens on "2026-11-05"
    And the compliance digest is sent on "2026-11-05"
    Then the digest lines include "312 new investors — 312 due-diligence duties"

  # E109 — Edge case: Solo Capital's only user Sam requests and approves — "Self-approved — single approver"
  Scenario: E109 Single approver
    Given Solo Capital with one user "Sam" and a SEBI fund "Solo Fund"
    When "Sam" requests an override of "Single-investee concentration" on "Solo Fund" to 20 because "Board policy 2026-07"
    And "Sam" approves the latest request
    Then the latest request is labelled "Self-approved — single approver"

  # E110 — Edge case: the export shows the self-approval label
  Scenario: E110 Single approver in export
    Given Solo Capital with one user "Sam" and a SEBI fund "Solo Fund"
    When the nightly compliance run happens on "2026-11-05" for "Solo Fund"
    And "Sam" explains and self-approves the "Single-investee concentration" item on "Solo Fund"
    And "Sam" exports the register from "2026-11-01" to "2026-11-30"
    Then the export shows "Self-approved — single approver" for an approval

  # E111 — Edge case: Horizon has a second eligible user (Anil), so Meera's self-approval is refused
  Scenario: E111 Second eligible user exists
    When "Meera" requests an override of "Single-investee concentration" on "Horizon Growth Fund I" to 20 because "Board policy 2026-07"
    And "Meera" approves the latest request
    Then the request decision fails with "Another approver must approve your request"

  # E112 — Edge case: Rahul deactivated with a pending explanation — returns to Meera; digest says so once
  Scenario: E112 Deactivated approver
    When the nightly compliance run happens on "2026-11-05"
    And "Meera" explains the "Single-investee concentration" item with "Exit of Acme agreed for Q4"
    And "Rahul" is deactivated
    And the morning reassignment happens on "2026-11-06" and "2026-11-07"
    Then the digest notes mention "pending approval" once

  # E113 — Edge case: Arjun deactivated with 2 assigned items — both to Meera; one line, not repeated
  Scenario: E113 Deactivated assignee
    When the nightly compliance run happens on "2026-11-05"
    And "Meera" assigns the "Single-investee concentration" item to "Arjun"
    And "Meera" assigns the "Continuing interest — pro-rata" item to "Arjun"
    And "Arjun" is deactivated
    And the morning reassignment happens on "2026-11-06" and "2026-11-07"
    Then both items are assigned to "Meera"
    And the digest notes mention "2 items of a deactivated user returned to Meera Test" once

  # E114 — Edge case: v2 (01 Jan) published 02 Jan after the run — applies on 03 Jan, "Published late", no re-run
  Scenario: E114 Published one day late
    When the nightly compliance run happens on "2027-01-02"
    Given SEBI v2 is published at "2027-01-02 10:00" effective "2027-01-01" for "all" funds
    When the nightly compliance run happens on "2027-01-03"
    Then the "Single-investee concentration" check on "Horizon Growth Fund I" is "breach"
    And the result records version "v2"
    And the digest notes mention "published late" once
    And "Horizon Growth Fund I" has no compliance run on "2027-01-01"

  # E115 — Edge case: published 01 Jan 01:00 IST, before the run on its date — applies 01 Jan, not late
  Scenario: E115 Published before the run on its date
    Given SEBI v2 is published at "2027-01-01 01:00" effective "2027-01-01" for "all" funds
    When the nightly compliance run happens on "2027-01-01"
    Then the "Single-investee concentration" check on "Horizon Growth Fund I" is "breach"
    And the result records version "v2"
    And the digest notes do not mention "published late"

  # E116 — Edge case: a US entity's 02:00 ET runs fall on 31 Dec / 01 Jan IST → v1 / v2
  Scenario: E116 Regime time zone
    Given SEBI v2 is published on "2026-12-01" effective "2027-01-01" for "all" funds
    When the nightly compliance run happens at "2026-12-31 02:00" Eastern time
    Then the result records version "v1"
    When the nightly compliance run happens at "2027-01-01 02:00" Eastern time
    Then the result records version "v2"

  # E117 — Edge case: an event on Fri 06 Nov + 15 calendar days is due Sat 21 Nov
  Scenario: E117 Calendar days
    Given a new investor "Friday LP" commits ₹2.0 cr to "Horizon Growth Fund I" on "2026-11-06"
    When the nightly compliance run happens on "2026-11-06"
    Then "Horizon Growth Fund I" has a due-diligence duty for "Friday LP" due "2026-11-21"

  # E118 — Edge case: on the calendar basis the year ends 31 Dec
  Scenario: E118 Calendar-quarter basis
    Then on the "calendar" basis "2026-11-10" is in year "2026" ending "2026-12-31"

  # E119 — Edge case: 31 Mar 2027 is Q4 FY27; 01 Apr 2027 is Q1 FY28
  Scenario: E119 FY quarter boundary
    Then on the "fy_apr" basis "2027-03-31" is in quarter "FY27-Q4" ending "2027-03-31"
    And on the "fy_apr" basis "2027-04-01" is in quarter "FY28-Q1" ending "2027-06-30"

  # E120 — Edge case: SEBI attached 20 Nov 2026 — first quarterly duty is the quarter ending 31 Dec 2026
  Scenario: E120 Attached mid-period
    Given "Horizon Seed Fund" carries SEBI as "Category II" attached on "2026-11-20"
    When the nightly compliance run happens on "2026-11-21" for "Horizon Seed Fund"
    Then "Horizon Seed Fund" has quarterly SEBI duties only for "FY27-Q3"

  # E121 — Edge case: attached 31 Dec 2026 — first duty is the quarter ending 31 Dec 2026
  Scenario: E121 Attached on period end
    Given "Horizon Seed Fund" carries SEBI as "Category II" attached on "2026-12-31"
    When the nightly compliance run happens on "2026-12-31" for "Horizon Seed Fund"
    Then "Horizon Seed Fund" has quarterly SEBI duties only for "FY27-Q3"

  # E122 — Edge case: an event duty with no named owner goes to the compliance owner (Meera)
  Scenario: E122 No owner named
    Given a new investor "Owner Test LP" commits ₹2.0 cr to "Horizon Growth Fund I" on "2026-11-03"
    When the nightly compliance run happens on "2026-11-05"
    Then the due-diligence duty for "Owner Test LP" is owned by "Meera"

  # E123 — Edge case: a payment dated 01 Nov recorded 20 Nov changes nothing before 21 Nov
  Scenario: E123 Backdated payment
    When the nightly compliance run happens on "2026-11-20"
    Given a payment of ₹0.15 cr dated "2026-11-01" is recorded on "2026-11-20"
    When the nightly compliance run happens on "2026-11-21"
    Then the "Continuing interest — pro-rata" result of "Horizon Growth Fund I" on "2026-11-20" is still "breach" with "₹2.10 cr"
    And the "Continuing interest — pro-rata" check on "Horizon Growth Fund I" is "pass"

  # E124 — Edge case: a soft-deleted commitment is excluded from figures
  Scenario: E124 Soft-deleted commitment
    Given the sponsor's commitment is deleted
    When the nightly compliance run happens on "2026-11-05"
    Then the "Continuing interest — amount" check on "Horizon Growth Fund I" is "breach"
    And the working shows "Corpus = ₹294.00 cr"

  # E137 — Edge case: a commitment with no commitment date still counts toward corpus (never silently dropped)
  Scenario: E137 Undated commitment
    Given a commitment of ₹10.0 cr with no commitment date is added to "Horizon Growth Fund I"
    When the nightly compliance run happens on "2026-11-05"
    Then the "Continuing interest — amount" check on "Horizon Growth Fund I" is "pass"
    And the working shows "Corpus = ₹310.00 cr"

  # E125 — Edge case: a deleted failing investment drops off the list — "14 of 16"
  Scenario: E125 Deleted failing row
    Given "Horizon Growth Fund I" also carries the fund agreement pack
    And "Horizon Growth Fund I" has 14 investments with signed IC notes from "2026-04-02"
    And "Horizon Growth Fund I" invested in "Acme B2" on "2026-09-12" with no IC note
    And "Horizon Growth Fund I" invested in "Zen Seed" on "2026-10-03" with an IC note scan not marked signed
    And "Horizon Growth Fund I" invested in "Kite A" on "2026-10-20" with an IC note e-signed on "2026-10-24"
    When the nightly compliance run happens on "2026-11-05"
    And the "Zen Seed" investment is deleted
    And the nightly compliance run happens on "2026-11-06"
    Then the IC note list shows "14 of 16 OK"
    And the IC note list does not include "Zen Seed"

  # E126 — Edge case: the min-investment item for investor X closes "Record deleted" when X's commitment is deleted
  Scenario: E126 Item for deleted record
    Given "Horizon Growth Fund I" has investors committing "9000000"
    When the nightly compliance run happens on "2026-11-05"
    Then the "Minimum investment per investor" item on "Horizon Growth Fund I" is "open"
    Given the commitment of "Small LP 1" is deleted
    When the nightly compliance run happens on "2026-11-06"
    Then the "Minimum investment per investor" item on "Horizon Growth Fund I" is closed as "Record deleted"

  # E127 — Edge case: a sale of Acme with no IC note is not listed (buys only)
  Scenario: E127 Sells not checked
    Given "Horizon Growth Fund I" also carries the fund agreement pack
    And "Horizon Growth Fund I" sells part of "Acme Foods" on "2026-10-10"
    When the nightly compliance run happens on "2026-11-05"
    Then the "IC note for every investment" check on "Horizon Growth Fund I" is "pass"

  # E128 — Edge case: the Orbit note moved to Kite Pay leaves Orbit Health "Missing"
  Scenario: E128 IC note moved
    Given "Horizon Growth Fund I" also carries the fund agreement pack
    And "Horizon Growth Fund I" invested in "Orbit Health" on "2026-10-05" with an IC note e-signed on "2026-09-28"
    And "Horizon Growth Fund I" invested in "Kite Pay B" on "2026-10-20" with no IC note
    When the IC note of "Orbit Health" is moved to "Kite Pay B"
    And the nightly compliance run happens on "2026-11-05"
    Then the IC note list includes "Orbit Health" as "Missing"

  # E129 — Edge case: the confirmed Orbit note moved to Kite Pay — its facts are compared with Kite Pay, not Orbit Health
  Scenario: E129 Facts move with note
    Given Horizon checks IC note contents on "Horizon Growth Fund I"
    And "Horizon Growth Fund I" invested ₹18.0 cr in "Orbit Health" on "2026-10-05"
    And the IC note of "Orbit Health" has been read and confirmed
    And "Horizon Growth Fund I" invested ₹14.0 cr in "Kite Pay" on "2026-10-20"
    When the IC note of "Orbit Health" is moved to "Kite Pay"
    And the nightly compliance run happens on "2026-11-07"
    Then the "IC note names the investee" check on "Horizon Growth Fund I" is "needs_review"
    And the working shows "Kite Pay"
    And the working shows "Document appears to concern Orbit Health"
    And the "Invested within IC approval" check on "Horizon Growth Fund I" is "pass"

  # E130 — Edge case: v2 adds "Instrument class"; 40 confirmed notes — each "Needs review — new fact in v2", re-read within the cap
  Scenario: E130 New fact in v2
    Given Horizon checks IC note contents on "Horizon Growth Fund I"
    And AI reading is on for the "IC note" input
    And "Horizon Growth Fund I" has 40 investments with confirmed IC notes
    And version 2 of the IC note contents pack adds the fact "Instrument class" effective "2026-11-03"
    When the nightly compliance run happens on "2026-11-07"
    Then the "Invested within IC approval" check on "Horizon Growth Fund I" lists 40 records as "Needs review — new fact in v2"
    Given the monthly reading cap is 30
    And the document AI reads the Orbit Health IC note
    When the documents are read
    Then 30 documents were sent to the AI
    And 10 IC notes wait for the reading cap
    And the re-read IC note of "Noted Co 1" shows "AI-read — 1 fact to confirm"

  # E131 — Edge case: 1,000 non-zero investors, 3 zero and 2 transferred out — count 1,000, pass
  Scenario: E131 Investor count definition
    Given "Count Fund" has exactly 1000 investors
    And "Count Fund" also has 3 investors with zero commitments and 2 fully transferred out
    When the nightly compliance run happens on "2026-11-05" for "Count Fund"
    Then the "Investors in scheme" check on "Count Fund" is "pass"
    And the working shows "1,000 ≤ 1,000"

  # E132 — Edge case: no run on 06 Nov shows as a gap; no 06 Nov results appear later
  Scenario: E132 Missed run
    When the nightly compliance run happens on "2026-11-05"
    And the nightly compliance run happens on "2026-11-07"
    Then the run history of "Horizon Growth Fund I" shows a gap on "2026-11-06"
    And "Horizon Growth Fund I" has no compliance run on "2026-11-06"

  # E133 — Edge case: compliance off 01 Dec, on 10 Dec — no runs 02–09 Dec, none backfilled
  Scenario: E133 Compliance off and on
    Given monitoring is off for Horizon
    When the hourly compliance tick happens at "2026-12-05 02:05" "Asia/Kolkata"
    Then "Horizon Growth Fund I" has 0 compliance runs on "2026-12-05"
    Given monitoring is on for Horizon
    When the hourly compliance tick happens at "2026-12-10 02:05" "Asia/Kolkata"
    Then "Horizon Growth Fund I" has 1 compliance run on "2026-12-10"
    And "Horizon Growth Fund I" has 0 compliance runs on "2026-12-05"

  # E134 — Edge case: a payment saved during a run is either fully in or out — one repeatable-read snapshot on MySQL
  Scenario: E134 Payment during run
    Then a compliance run reads one snapshot per fund

  # E135 — Edge case: facts unconfirmed since 27 Oct — the 05 Nov digest says "facts waiting 9 days"
  Scenario: E135 Facts waiting age
    Given Horizon checks IC note contents on "Horizon Growth Fund I"
    And "Horizon Growth Fund I" invested ₹18.0 cr in "Orbit Health" on "2026-10-05"
    And the IC note of "Orbit Health" has facts waiting since "2026-10-27"
    When the compliance digest is sent on "2026-11-05"
    Then the digest lines include "facts waiting 9 days"

  # X62 — Error case: applicability C with Fund U having no start date — "Could not check — missing: fund start date"
  Scenario: X62 Missing start date (C)
    Given SEBI funds "Fund N1" started "2027-01-01", "Fund N0" started "2026-12-31" and "Fund U" with no start date
    And SEBI v2 with a new failing check is published on "2026-12-01" effective "2027-01-01" with a transition until "2027-06-30"
    When the nightly compliance run happens on "2027-01-02" for "Fund U"
    Then every SEBI check of "Fund U" says "Could not check — missing: fund start date"

  # X63 — Error case: a "for each new investor" duty without a from date is refused
  Scenario: X63 Event duty without from date
    Given Priya is a CapHive content admin
    When Priya creates a draft CapHive pack "Draft Pack" with 5 classifications
    And Priya adds a new-investor duty without a from date
    Then the draft is refused with "From date is required"

  # X67 — Error case: superseded v2 results stay viewable, marked "Superseded — pack correction"
  Scenario: X67 Superseded results kept
    Given SEBI v2 with a wrong investor limit of 100 is published on "2026-12-01" effective "2027-01-01"
    When the nightly compliance run happens on "2027-01-01"
    Given SEBI v2.1 correcting the investor limit to 1000 is published on "2027-01-02" effective "2027-01-01"
    When the nightly compliance run happens on "2027-01-03"
    Then the v2 results of "Horizon Growth Fund I" are still stored and marked "Superseded — pack correction"
