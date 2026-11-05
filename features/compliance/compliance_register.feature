Feature: Compliance register
  A failed check opens one item per check per fund pack; it stays open until the data clears it or an
  approved explanation exists. Worked examples: openspec/changes/fund-compliance-monitoring/business-rules.md (group 4)

  Background:
    Given the Horizon compliance setup

  # H25 — Happy path: the sponsor pays ₹0.15 cr; ₹2.25 ≥ ₹2.25 clears the pro-rata item, both figures kept
  Scenario: H25 Cleared by data
    When the nightly compliance run happens on "2026-11-05"
    Then the "Continuing interest — pro-rata" item on "Horizon Growth Fund I" is "open"
    Given the sponsor pays a further ₹0.15 cr on "2026-11-06"
    When the nightly compliance run happens on "2026-11-07"
    Then the "Continuing interest — pro-rata" item on "Horizon Growth Fund I" is closed as "Cleared by data"
    And the item keeps its failing working "₹2.10 cr < ₹2.25 cr" and its clearing working "₹2.25 cr ≥ ₹2.25 cr"

  # H26 — Happy path: assign → explain → approve moves In progress → Pending approval → Explained
  Scenario: H26 Assign, explain, approve
    When the nightly compliance run happens on "2026-11-05"
    And "Meera" assigns the "Single-investee concentration" item to "Arjun"
    Then the "Single-investee concentration" item on "Horizon Growth Fund I" is "in_progress"
    When "Meera" explains the "Single-investee concentration" item with "Exit of Acme agreed for Q4"
    Then the "Single-investee concentration" item on "Horizon Growth Fund I" is "pending_approval"
    When "Rahul" approves the explanation of the "Single-investee concentration" item
    Then the "Single-investee concentration" item on "Horizon Growth Fund I" is "explained"

  # E31 — Edge case: the same breach the next day keeps one item opened 5 Nov
  Scenario: E31 Same breach next day
    When the nightly compliance run happens on "2026-11-05"
    And the nightly compliance run happens on "2026-11-06"
    Then "Horizon Growth Fund I" has 1 register item for "Single-investee concentration" opened on "2026-11-05"

  # E32 — Edge case: explaining without assigning goes to Pending approval
  Scenario: E32 Explain without assigning
    When the nightly compliance run happens on "2026-11-05"
    And "Meera" explains the "Single-investee concentration" item with "Exit of Acme agreed for Q4"
    Then the "Single-investee concentration" item on "Horizon Growth Fund I" is "pending_approval"

  # E33 — Edge case: explained at 26.67%, then 27.50% reopens "Worsened since approval"
  Scenario: E33 Worsens after approval
    Given the "Single-investee concentration" item was explained and approved after the "2026-11-05" run
    And "Acme Foods" costs ₹74.25 cr
    When the nightly compliance run happens on "2026-11-06"
    Then the "Single-investee concentration" item on "Horizon Growth Fund I" is "open"
    And the item is marked "Worsened since approval"

  # E34 — Edge case: the same or a better figure keeps it Explained
  Scenario: E34 Same or better after approval
    Given the "Single-investee concentration" item was explained and approved after the "2026-11-05" run
    When the nightly compliance run happens on "2026-11-06"
    Then the "Single-investee concentration" item on "Horizon Growth Fund I" is "explained"
    Given "Acme Foods" costs ₹70.47 cr
    When the nightly compliance run happens on "2026-11-07"
    Then the "Single-investee concentration" item on "Horizon Growth Fund I" is "explained"

  # E35 — Edge case: on the fix-by date itself (5 Nov + 30 days = 5 Dec) the item is not overdue
  Scenario: E35 Fix-by date itself
    When the nightly compliance run happens on "2026-11-05"
    Then the "Single-investee concentration" item has fix-by "2026-12-05"
    And on "2026-12-05" the item is not overdue

  # E36 — Edge case: the day after fix-by it is overdue and owner + approver are emailed
  Scenario: E36 Day after fix-by
    When the nightly compliance run happens on "2026-11-05"
    And the morning compliance housekeeping happens on "2026-12-06"
    Then on "2026-12-06" the item is overdue
    And "Meera" got the compliance notice "Overdue: Single-investee concentration on Horizon Growth Fund I"
    And "Rahul" got the compliance notice "Overdue: Single-investee concentration on Horizon Growth Fund I"

  # E37 — Edge case: cleared 7 Nov, failing again 20 Nov opens a new item
  Scenario: E37 New episode
    When the nightly compliance run happens on "2026-11-05"
    Given the sponsor pays a further ₹0.15 cr on "2026-11-06"
    When the nightly compliance run happens on "2026-11-07"
    Given a payment of ₹-0.15 cr dated "2026-11-19" is recorded on "2026-11-19"
    When the nightly compliance run happens on "2026-11-20"
    Then "Horizon Growth Fund I" has 2 register items for "Continuing interest — pro-rata"
    And the newest "Continuing interest — pro-rata" item was opened on "2026-11-20"

  # E38 — Edge case: 0 days to fix — first seen 5 Nov is overdue on 6 Nov
  Scenario: E38 Zero days to fix
    Given the "Single-investee concentration" check has 0 days to fix
    When the nightly compliance run happens on "2026-11-05"
    Then on "2026-11-06" the item is overdue

  # E39 — Edge case: a rejected explanation returns to In progress and Meera is told
  Scenario: E39 Rejected explanation
    When the nightly compliance run happens on "2026-11-05"
    And "Meera" explains the "Single-investee concentration" item with "Exit of Acme agreed for Q4"
    And "Rahul" rejects the explanation of the "Single-investee concentration" item
    Then the "Single-investee concentration" item on "Horizon Growth Fund I" is "in_progress"
    And "Meera" got the compliance notice "Your explanation request was rejected"

  # E40 — Edge case: an explained item whose check then passes clears by data
  Scenario: E40 Explained then cleared
    Given the "Single-investee concentration" item was explained and approved after the "2026-11-05" run
    And "Acme Foods" costs ₹60.0 cr
    When the nightly compliance run happens on "2026-11-06"
    Then the "Single-investee concentration" item on "Horizon Growth Fund I" is closed as "Cleared by data"

  # X31 — Error case: approving an already explained item changes nothing and sends no second notice
  Scenario: X31 Approve twice
    Given the "Single-investee concentration" item was explained and approved after the "2026-11-05" run
    When "Rahul" approves the explanation request again
    Then the request decision fails with "Already decided"
    And "Meera" got the compliance notice "Your explanation request was approved" exactly once

  # X32 — Error case: explaining a cleared item is refused "Item is closed"
  Scenario: X32 Explain a cleared item
    When the nightly compliance run happens on "2026-11-05"
    Given the sponsor pays a further ₹0.15 cr on "2026-11-06"
    When the nightly compliance run happens on "2026-11-07"
    Then explaining the closed "Continuing interest — pro-rata" item is refused with "Item is closed"
