Feature: Notifications, digest and export
  Internal notices only — the digest goes out only when something changed; exports respect fund access.
  Worked examples: openspec/changes/fund-compliance-monitoring/business-rules.md (group 6)

  Background:
    Given the Horizon compliance setup

  # H29 — Happy path: the first digest says "3 new breaches, 1 needs review, 1 duty due in 7 days"
  Scenario: H29 First digest
    Given "Horizon Growth Fund I" also carries the fund agreement pack
    And a needs-review result is stored for "Horizon Growth Fund I" on "2027-01-08"
    And a duty of "Horizon Growth Fund I" is due on "2027-01-15"
    When the nightly compliance run happens on "2027-01-08"
    And the compliance digest is sent on "2027-01-08"
    Then "Meera" got a digest saying "3 new breaches, 1 needs review, 1 duty due in 7 days"

  # H30 — Happy path: assigning an item tells the assignee by email and in-app
  Scenario: H30 Assignment email
    When the nightly compliance run happens on "2026-11-05"
    And "Meera" assigns the "Single-investee concentration" item to "Arjun"
    Then "Arjun" got the compliance notice "Single-investee concentration on Horizon Growth Fund I assigned to you"
    And an email went to "Arjun" about "assigned to you"

  # H31 — Happy path: Meera exports Q2 FY27 for Growth Fund I with results, items and duties
  Scenario: H31 Quarter export
    When the nightly compliance run happens on "2026-09-30"
    And "Meera" exports the register from "2026-07-01" to "2026-09-30"
    Then the export has results for "Horizon Growth Fund I"
    And the export has register items for "Horizon Growth Fund I"

  # E45 — Edge case: a quiet day sends no email
  Scenario: E45 Quiet day
    When the nightly compliance run happens on "2026-11-05"
    And the compliance digest is sent on "2026-11-05"
    And the nightly compliance run happens on "2026-11-06"
    And the compliance digest is sent on "2026-11-06"
    Then "Meera" got 1 compliance digest

  # E46 — Edge case: an explanation asks the approvers (Rahul) by email and in-app
  Scenario: E46 Approval request
    When the nightly compliance run happens on "2026-11-05"
    And "Meera" explains the "Single-investee concentration" item with "Exit of Acme agreed for Q4"
    Then "Rahul" got the compliance notice "Explanation request from Meera Test needs approval"
    And an email went to "Rahul" about "needs approval"

  # E47 — Edge case: Vikram cannot see GIFT Opportunities, so his export has no GIFT rows
  Scenario: E47 Export respects access
    Given "Horizon GIFT Opportunities" also carries the fund agreement pack
    When the nightly compliance run happens on "2026-11-05" for "Horizon GIFT Opportunities"
    And "Vikram" exports the register from "2026-11-01" to "2026-11-30"
    Then the export has no rows for "Horizon GIFT Opportunities"
