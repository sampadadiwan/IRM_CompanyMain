@maker_checker
Feature: Approving a capital distribution with maker–checker (OWASP review 2026-11 M13 — F4)
  Distributions follow the same rule as calls: with the setting on, whoever prepared one cannot approve it.
  Imported distributions and open-ended redemption settlements keep working exactly as today.
  Worked examples H16–H17, E28–E31:
  openspec/changes/archive/2026-11-10-capital-call-distribution-maker-checker/business-rules.md#4-approving-a-distribution--phase-2

  # H16 — Happy path: Ravi approves Meera's distribution → approved by Ravi; Mark Payments Completed offered
  Scenario: H16 A checker approves the distribution
    Given the firm "Nilgiri Capital" has maker-checker on
    And "Meera" created the distribution "Tea Estates Exit"
    When "Ravi" approves the distribution "Tea Estates Exit"
    Then "Ravi" sees the flash "Capital distribution was successfully approved."
    And the distribution "Tea Estates Exit" is approved by "Ravi"
    And "Ravi" sees "Mark Payments Completed" on the page

  # H17 — Happy path: Solo Ventures (off) — Sam creates and approves → "Yes · by Sam Mehta (also prepared it)"
  Scenario: H17 Setting off: a self-approved distribution is labelled
    Given "Sam" created the distribution "Solo Exit"
    When "Sam" approves the distribution "Solo Exit"
    Then the distribution "Solo Exit" is approved by "Sam"
    When "Sam" opens the distribution "Solo Exit"
    Then the Approved row shows "Yes · by Sam Mehta (also prepared it)"
    And the Prepared by row shows "Sam Mehta"

  # E28 — Edge case: Meera opens Actions on her distribution → greyed out with the distribution wording
  Scenario: E28 The preparer sees why Approve is greyed out
    Given the firm "Nilgiri Capital" has maker-checker on
    And "Meera" created the distribution "Tea Estates Exit"
    When "Meera" opens the distribution "Tea Estates Exit"
    Then the page shows Approve disabled with the reason "You prepared this distribution, so another approver must approve it (maker–checker is on)."
    And the page shows Request approval

  # E29 — Edge case: Ravi changed a payment's income → greyed out for Ravi; Priya approves
  Scenario: E29 The payment editor cannot approve
    Given the firm "Nilgiri Capital" has maker-checker on
    And "Meera" created the distribution "Tea Estates Exit"
    And "Ravi" changes the income of the "₹0.72 Cr" payment of "Tea Estates Exit" to "₹0.75 Cr"
    When "Ravi" opens the distribution "Tea Estates Exit"
    Then the page shows Approve disabled with the reason "You prepared this distribution"
    When "Priya" approves the distribution "Tea Estates Exit"
    Then the distribution "Tea Estates Exit" is approved by "Priya"

  # E30 — Edge case: an imported distribution, not approved; Ravi marks payments completed → works as today
  Scenario: E30 Imported distributions complete without approval, as today
    Given the firm "Nilgiri Capital" has maker-checker on
    And "Meera" created the distribution "Imported Exit"
    And the distribution "Imported Exit" was imported
    When "Ravi" marks the payments of "Imported Exit" completed
    Then the payments of "Imported Exit" are completed
    And the distribution "Imported Exit" is not approved

  # E31 — Edge case: an open-ended fund's redemptions settle → the settlement distribution is created approved
  Scenario: E31 Open-ended redemption settlements are created approved as today
    Given the firm "Nilgiri Capital" has maker-checker on
    And the fund of "Nilgiri Capital" settles a dealing date
    When "Ravi" creates the redemption settlement
    Then the settlement is approved with no preparer recorded
