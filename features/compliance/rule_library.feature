Feature: Rule library
  CapHive and entity packs: drafts, validation, test runs, publishing and versions.
  Worked examples: openspec/changes/fund-compliance-monitoring/business-rules.md (group 1)

  Background:
    Given the Horizon compliance setup
    And Priya is a CapHive content admin

  # H1 — Happy path: a CapHive draft pack stays private to customers
  Scenario: H1 Draft pack stays private
    When Priya creates a draft CapHive pack "SEBI — AIF Draft" with 5 classifications
    Then "Meera" cannot see the pack "SEBI — AIF Draft"
    And "Meera" can see the pack "SEBI — AIF"

  # H2 — Happy path: a grouped measure is saved and offered to checks
  Scenario: H2 Grouped measure
    When Priya creates a draft CapHive pack "Draft Pack" with 5 classifications
    And Priya adds the measure "largest investment cost per investee" to the draft
    Then the draft saves without errors

  # H3 — Happy path: an arithmetic measure reads "lower of 2.5% of corpus and ₹5.00 cr"
  Scenario: H3 Arithmetic measure
    When Priya creates a draft CapHive pack "Draft Pack" with 5 classifications
    And Priya adds the measure "required interest" to the draft
    Then the draft saves without errors
    And the measure "required_interest" reads "lower of 2.5% of corpus and ₹5.00 cr"

  # H4 — Happy path: a test run on the CapHive demo entity shows figures and leaves nothing for the customer
  Scenario: H4 Test run on demo entity
    Given the CapHive Demo entity has a fund "Demo Fund" with an investment of ₹30.0 cr
    When Priya test-runs the SEBI draft on "Demo Fund"
    Then the test run shows results with figures
    And no compliance results exist for "Horizon Growth Fund I"

  # H5 — Happy path: publishing with reviewer A. Kapoor (20 Nov) gives "Published v1", offered in Attach pack
  Scenario: H5 Publish v1
    When Priya creates a draft CapHive pack "New Regime Pack" with 5 classifications
    And Priya test-runs the draft
    And Priya publishes the draft effective "2026-12-01" with counsel "A. Kapoor" on "2026-11-20"
    Then the pack "New Regime Pack" is "Published v1"
    And the pack "New Regime Pack" is offered in Attach pack

  # H6 — Happy path: an entity pack edit stays a draft until published — runs keep using v1's 15%
  Scenario: H6 Entity pack draft until publish
    Given "Horizon Growth Fund I" also carries the fund agreement pack
    When "Meera" drafts the fund agreement pack with the single-sector limit at 12%
    And the nightly compliance run happens on "2026-11-05"
    Then the "Single-sector limit" check on "Horizon Growth Fund I" is "pass"
    And the working shows "≤ 15%"

  # H7 — Happy path: an entity pack check without a citation is allowed
  Scenario: H7 Entity check needs no citation
    When "Meera" saves an entity pack check without a citation
    Then the draft saves without errors

  # H8 — Happy path: v2 effective 01 Jan 2027 — the 31 Dec run records v1, the 01 Jan run v2
  Scenario: H8 Version switch on effective date
    Given SEBI v2 is published on "2026-12-01" effective "2027-01-01" for "all" funds
    When the nightly compliance run happens on "2026-12-31"
    Then the "Single-investee concentration" check on "Horizon Growth Fund I" is "breach"
    And the result records version "v1"
    When the nightly compliance run happens on "2027-01-01"
    Then the "Single-investee concentration" check on "Horizon Growth Fund I" is "breach"
    And the result records version "v2"

  # H9 — Happy path: an amount limit entered without a currency is the pack's currency (₹5.00 cr INR)
  Scenario: H9 Amount limit currency default
    When Priya creates a draft CapHive pack "Draft Pack" with 5 classifications
    And Priya adds an amount limit of 50000000 with no currency
    Then the draft saves without errors
    And the limit reads "₹5.00 cr"

  # H10 — Happy path: an on-demand duty needs no due rule
  Scenario: H10 On-demand duty
    When "Meera" saves an on-demand duty "Key-person event notified" without a due rule
    Then the draft saves without errors

  # E1 — Edge case: a retired pack is not offered; its old results stay viewable
  Scenario: E1 Retired pack
    When the nightly compliance run happens on "2026-11-05"
    And the SEBI pack is retired on "2027-03-01"
    And the compliance date is "2027-03-02"
    Then the pack "SEBI — AIF" is not offered in Attach pack
    And the "Single-investee concentration" check on "Horizon Growth Fund I" is "breach"

  # E2 — Edge case: an approved 20% override is dropped when v2's 18% is stricter — digest and history say so
  Scenario: E2 Override flagged in digest
    Given an approved override of "Single-investee concentration" on "Horizon Growth Fund I" at 20
    And SEBI v2 is published on "2026-12-01" effective "2027-01-01" for "all" funds with the concentration limit at 18
    When the nightly compliance run happens on "2027-01-01"
    Then the next digest includes "Override 20% dropped — v2 limit 18% is stricter"

  # E3 — Edge case: time to fix 0 and 365 are both accepted
  Scenario: E3 Time to fix boundaries
    When Priya creates a draft CapHive pack "Draft Pack" with 5 classifications
    And Priya sets a check's time to fix to 0
    Then the draft saves without errors
    When Priya sets a check's time to fix to 365
    Then the draft saves without errors

  # E4 — Edge case: a KYC custom field can be measured
  Scenario: E4 Custom field in a measure
    When Priya creates a draft CapHive pack "Draft Pack" with 5 classifications
    And Priya adds the measure "investors not qualified purchasers" to the draft
    Then the draft saves without errors

  # E5 — Edge case: a check applying to "all" applies to any classification
  Scenario: E5 Applies to all
    Given "Horizon Growth Fund I" is classified "Category I" under SEBI
    When the nightly compliance run happens on "2026-11-05"
    Then the "Investors in scheme" check on "Horizon Growth Fund I" is "pass"

  # E6 — Edge case: editing a tested draft clears the test — publish refused "Run a test first"
  Scenario: E6 Draft edited after test
    When Priya creates a draft CapHive pack "Draft Pack" with 5 classifications
    And Priya test-runs the draft
    And Priya adds an amount limit of 50000000 with no currency
    And Priya publishes the draft effective "2026-12-01" with counsel "A. Kapoor" on "2026-11-20"
    Then publishing is refused with "Run a test first"

  # E7 — Edge case: Horizon granted support access, so Priya may test-run on it; still no register rows
  Scenario: E7 Test run on consenting customer
    Given Horizon has granted CapHive support access to Priya
    When Priya test-runs the SEBI draft on "Horizon Growth Fund I"
    Then the test run shows results with figures
    And "Horizon Growth Fund I" has 0 open register items

  # X1 — Error case: a pack with no classifications is refused
  Scenario: X1 No classifications
    When Priya creates a draft CapHive pack "Empty Pack" with 0 classifications
    Then the draft is refused with "Add at least one classification"

  # X2 — Error case: a CapHive check without a citation is refused
  Scenario: X2 CapHive check without citation
    When Priya creates a draft CapHive pack "Draft Pack" with 5 classifications
    And Priya adds a check without a citation
    Then the draft is refused with "Citation is required"

  # X3 — Error case: a check applying to "Category IV" is refused naming it
  Scenario: X3 Unknown classification
    When Priya creates a draft CapHive pack "Draft Pack" with 5 classifications
    And Priya adds a check applying to "Category IV"
    Then the draft is refused with "Unknown classification: Category IV"

  # X4 — Error case: time to fix 366 and −1 are both refused
  Scenario: X4 Time to fix out of range
    When Priya creates a draft CapHive pack "Draft Pack" with 5 classifications
    And Priya sets a check's time to fix to 366
    Then the draft is refused with "Time to fix must be 0–365 days"
    When Priya sets a check's time to fix to -1
    Then the draft is refused with "Time to fix must be 0–365 days"

  # X5 — Error case: a measure over "commited_amount" is refused "Unknown field: commited_amount"
  Scenario: X5 Unknown field
    When Priya creates a draft CapHive pack "Draft Pack" with 5 classifications
    And Priya adds the measure "misspelt commitment" to the draft
    Then the draft is refused with "Unknown field: commited_amount"

  # X6 — Error case: an IC-note check without a checks-from date is refused
  Scenario: X6 Doc check without checks-from
    When "Meera" saves an IC note check without a checks-from date
    Then the draft is refused with "Checks from date is required"

  # X7 — Error case: a quarterly duty without a due rule is refused
  Scenario: X7 Scheduled duty without due rule
    When Priya creates a draft CapHive pack "Draft Pack" with 5 classifications
    And Priya adds a quarterly duty without a due rule
    Then the draft is refused with "Due rule is required"

  # X68 — Error case: a limit currency must be a three-letter code on a fixed amount limit — "US$" and a currency on a % limit are refused
  Scenario: X68 Unknown limit currency refused
    When Priya creates a draft CapHive pack "Draft Pack" with 5 classifications
    And Priya adds an amount limit of 150000 in "US$"
    Then the draft is refused with "Unknown currency: US$"
    When Priya adds a percentage limit of 25 in "USD"
    Then the draft is refused with "A currency applies only to a fixed amount limit"

  # X8 — Error case: publishing an untested draft is refused "Run a test first"
  Scenario: X8 Publish without test
    When Priya creates a draft CapHive pack "Draft Pack" with 5 classifications
    And Priya publishes the draft effective "2026-12-01" with counsel "A. Kapoor" on "2026-11-20"
    Then publishing is refused with "Run a test first"

  # X9 — Error case: publishing without a counsel review is refused
  Scenario: X9 Publish without counsel
    When Priya creates a draft CapHive pack "Draft Pack" with 5 classifications
    And Priya test-runs the draft
    And Priya publishes the draft effective "2026-12-01" with counsel "" on ""
    Then publishing is refused with "Record the counsel review"

  # X10 — Error case: v2 effective on v1's date is refused "Effective date must be after v1's"
  Scenario: X10 v2 date not after v1
    When Priya drafts SEBI v2
    And Priya test-runs the draft
    And Priya publishes the draft effective "2026-12-01" with counsel "A. Kapoor" on "2026-11-20"
    Then publishing is refused with "Effective date must be after v1's"
