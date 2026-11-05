Feature: Fund pack setup
  Attaching packs to funds with a classification per pack, overrides, disabling, detaching and monitoring.
  Worked examples: openspec/changes/fund-compliance-monitoring/business-rules.md (group 2)

  Background:
    Given the Horizon compliance setup

  # H11 — Happy path: SEBI (Category II) + fund agreement on Growth I, fund agreement on GIFT
  Scenario: H11 Packs on two funds
    When "Meera" attaches "Horizon — fund agreement limits" to "Horizon Growth Fund I" as "All funds"
    And "Meera" attaches "Horizon — fund agreement limits" to "Horizon GIFT Opportunities" as "All funds"
    Then the setup grid shows "Horizon Growth Fund I" with "SEBI — AIF" as "Category II"
    And the setup grid shows "Horizon Growth Fund I" with "Horizon — fund agreement limits" as "All funds"
    And the setup grid shows "Horizon GIFT Opportunities" with "Horizon — fund agreement limits" as "All funds"

  # H12 — Happy path: the fund's Category "Category II" pre-fills the SEBI classification
  Scenario: H12 Category pre-fills
    Given "Horizon Growth Fund I" has no SEBI attachment
    When "Meera" attaches "SEBI — AIF" to "Horizon Growth Fund I" without a classification
    Then the setup grid shows "Horizon Growth Fund I" with "SEBI — AIF" as "Category II"

  # H14 — Happy path: a 20% override is pending until Rahul approves, then "20% (pack: 25%)"
  Scenario: H14 Override approved
    When "Meera" requests an override of "Single-investee concentration" on "Horizon Growth Fund I" to 20 because "Board policy 2026-07"
    And the nightly compliance run happens on "2026-11-05"
    Then the "Single-investee concentration" check on "Horizon Growth Fund I" is "breach"
    And the working shows "Override pending approval"
    And the working shows "> 25%"
    When "Rahul" approves the latest request
    And the nightly compliance run happens on "2026-11-06"
    Then the "Single-investee concentration" check on "Horizon Growth Fund I" is "breach"
    And the working shows "20% (pack: 25%)"

  # H15 — Happy path: "Investors in scheme" disabled with approval stops running and is labelled
  Scenario: H15 Disable approved
    When "Meera" requests to disable "Investors in scheme" on "Horizon Growth Fund I" because "Not relevant for this fund"
    And "Rahul" approves the latest request
    And the nightly compliance run happens on "2026-11-05"
    Then "Horizon Growth Fund I" has no "Investors in scheme" result
    And the latest request is labelled "approved by Rahul Test"

  # H16 — Happy path: detaching SEBI closes its open item "Pack detached"; history stays readable
  Scenario: H16 Detach approved
    When the nightly compliance run happens on "2026-11-05"
    And "Meera" requests to detach "SEBI — AIF" from "Horizon Growth Fund I" because "Fund migrated to IFSCA"
    And "Rahul" approves the latest request
    Then the "Single-investee concentration" item on "Horizon Growth Fund I" is closed as "Pack detached"
    And the "Single-investee concentration" check on "Horizon Growth Fund I" is "breach"

  # H17 — Happy path: monitoring on with Meera as owner — first run tonight, Q3 SEBI report duty dated
  Scenario: H17 Monitoring on
    Given monitoring is off for Horizon
    When "Meera" turns monitoring on
    Then the setup says "Monitoring on — first run tonight"
    When the nightly compliance run happens on "2026-11-05"
    Then "Horizon Growth Fund I" has a "Quarterly SEBI report filed" duty for "FY27-Q3" due "2027-01-15"

  # H18 — Happy path: a result from before the override was approved shows 25% and no override
  Scenario: H18 Setup as of a past day
    When the nightly compliance run happens on "2026-11-09"
    And "Meera" requests an override of "Single-investee concentration" on "Horizon Growth Fund I" to 20 because "Board policy 2026-07"
    And "Rahul" approves the latest request
    And the nightly compliance run happens on "2026-11-10"
    Then the "2026-11-09" "Single-investee concentration" result shows the setup "No override" with limit 25
    And the "2026-11-10" "Single-investee concentration" result shows the setup "20% (pack: 25%)" with limit 20

  # E9 — Edge case: SEBI on Seed Fund with no Category — amber "no classification — no checks run", 0 SEBI results
  Scenario: E9 No classification
    When "Meera" attaches "SEBI — AIF" to "Horizon Seed Fund" without a classification
    And the nightly compliance run happens on "2026-11-05" for "Horizon Seed Fund"
    Then the dashboard of "Horizon Seed Fund" says "SEBI — AIF: no classification — no checks run"
    And "Horizon Seed Fund" has no "SEBI — AIF" results

  # E10 — Edge case: a fund with no pack is listed "Not monitored"
  Scenario: E10 Not monitored
    Then the Compliance home lists "Horizon Seed Fund" as "Not monitored"

  # E11 — Edge case: Category "Cat 2 0724" is not a SEBI classification — no pre-fill
  Scenario: E11 Category not in pack list
    Given "Horizon Seed Fund" has the Category "Cat 2 0724"
    When "Meera" attaches "SEBI — AIF" to "Horizon Seed Fund" without a classification
    Then the setup grid shows "Horizon Seed Fund" with "SEBI — AIF" as "⚠ choose"

  # E12 — Edge case: Rahul rejects a pending override — discarded, Meera told in-app
  Scenario: E12 Override rejected
    When "Meera" requests an override of "Single-investee concentration" on "Horizon Growth Fund I" to 20 because "Board policy 2026-07"
    And "Rahul" rejects the latest request
    Then the override is not in force on "Horizon Growth Fund I"
    And "Meera" got the compliance notice "Your override request was rejected"

  # E13 — Edge case: a reason of exactly 10 characters is accepted
  Scenario: E13 Reason exactly 10 characters
    When "Meera" requests an override of "Single-investee concentration" on "Horizon Growth Fund I" to 20 because "Board 2026"
    Then the request was accepted

  # E14 — Edge case: a quorum equal to the 5 members is accepted
  Scenario: E14 Quorum equals members
    When "Meera" saves the IC members "A. Rao, K. Shah, M. Iyer, R. Mehta, S. Nair" with quorum 5
    Then the setup saves

  # E15 — Edge case: a company admin has viewer, editor and approver by default
  Scenario: E15 Admin roles by default
    Then "Meera" is a compliance viewer, editor and approver

  # E16 — Edge case: attaching SEBI twice (double click) creates one attachment
  Scenario: E16 Double-click attach
    Given "Horizon Growth Fund I" has no SEBI attachment
    When "Meera" attaches "SEBI — AIF" to "Horizon Growth Fund I" twice
    Then "Horizon Growth Fund I" carries "SEBI — AIF" once

  # E17 — Edge case: with the override pending, the nightly run uses 25% and says so
  Scenario: E17 Pending override, run happens
    When "Meera" requests an override of "Single-investee concentration" on "Horizon Growth Fund I" to 20 because "Board policy 2026-07"
    And the nightly compliance run happens on "2026-11-05"
    Then the "Single-investee concentration" check on "Horizon Growth Fund I" is "breach"
    And the working shows "Override pending approval"
    And the working shows "26.67% > 25%"

  # X14 — Error case: attaching SEBI again is refused naming the pack
  Scenario: X14 Same pack twice
    When "Meera" attaches "SEBI — AIF" to "Horizon Growth Fund I" as "Category II"
    Then attaching is refused with "SEBI — AIF is already attached to this fund"

  # X15 — Error case: monitoring is blocked while an input is missing
  Scenario: X15 Monitoring blocked
    Given monitoring is off for Horizon
    And "Horizon Seed Fund" carries "SEBI — AIF" as "Category II"
    When "Meera" turns monitoring on
    Then the setup says "1 input missing — Estimated expenses"
    And monitoring is still off for Horizon

  # X16 — Error case: a quorum above the 5 members is refused
  Scenario: X16 Quorum > members
    When "Meera" saves the IC members "A. Rao, K. Shah, M. Iyer, R. Mehta, S. Nair" with quorum 6
    Then the setup is refused with "Quorum cannot exceed 5 members"

  # X17 — Error case: a 5-character reason is refused
  Scenario: X17 Short reason
    When "Meera" requests an override of "Single-investee concentration" on "Horizon Growth Fund I" to 20 because "Board"
    Then the compliance request is refused with "Give a reason (at least 10 characters)"
