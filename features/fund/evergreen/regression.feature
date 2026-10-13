@rack_test
Feature: Closed-ended funds are unchanged by evergreen funds
  Backward compatibility gate (B1–B8): a closed-ended fund, and any fund on an entity without the
  evergreen switch, behaves exactly as before.
  Worked examples E1, E47, E64 — openspec/changes/open-ended-funds/design.md#backward-compatibility

  # E1 — Edge case: a closed-ended fund on an evergreen-enabled entity keeps its closed-ended page and is not evergreen.
  Scenario: A closed-ended fund on an evergreen-enabled entity keeps its closed-ended page
    Given Im logged in as a user "first_name=Asha" for an entity "name=Caphive Demo;entity_type=Investment Fund"
    And the user has role "company_admin"
    And the entity has evergreen funds switched on
    And there is a fund "name=Beta Growth Fund;currency=INR;unit_types=A" for the entity
    When I open the fund page
    Then I should see the closed-ended fund page
    And the fund should not be evergreen

  # E47 — Edge case: an entity without the evergreen switch offers no evergreen action and refuses the settings page.
  Scenario: An entity without the switch sees no evergreen option
    Given Im logged in as a user "first_name=Gamma" for an entity "name=Gamma Advisors;entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is a fund "name=Gamma Fund;currency=INR;unit_types=A" for the entity
    When I open the fund page
    Then the fund actions should not offer evergreen
    When I request the evergreen settings page directly
    Then I should not see the evergreen settings form

  # E64 — Edge case: a closed-ended fund on an evergreen-enabled entity sends no evergreen notifications and user tags stay as they were.
  Scenario: A closed-ended fund sends no evergreen notifications and user tags are unchanged
    Given Im logged in as a user "first_name=Asha" for an entity "name=Caphive Demo;entity_type=Investment Fund"
    And the user has role "company_admin"
    And the entity has evergreen funds switched on
    And the user is tagged "Kpi,Tasks"
    And the closed-ended fund "Beta Growth Fund" has a call with unit price "10,000" and a paid remittance of "10,00,000"
    When the daily notification check runs on "2026-10-26"
    Then no evergreen notification should have been sent
    And the user should still be tagged "Kpi,Tasks"

  # E179 — Edge case: on an evergreen-enabled entity, a closed-ended fund's capital call and distribution open on their own pages (not the evergreen settlement page) and its order book address says the fund is not evergreen.
  Scenario: Closed-ended calls and distributions keep their own pages
    Given Im logged in as a user "first_name=Asha" for an entity "name=Caphive Demo;entity_type=Investment Fund"
    And the user has role "company_admin"
    And the entity has evergreen funds switched on
    And the closed-ended fund "Beta Growth Fund" has a call with unit price "10,000" and a paid remittance of "10,00,000"
    And the closed-ended fund has a distribution
    When I open the closed-ended call
    Then I should be on the closed-ended call page
    When I open the closed-ended distribution
    Then I should be on the closed-ended distribution page
    When I open the order book
    Then I should see "This fund is not evergreen"

  # X108 — Error case: the entity's evergreen switch is turned off after a fund was made evergreen; no reminder is sent, the GP and investor pages fall back to closed-ended, and the order book is refused.
  Scenario: Evergreen switched off at the entity hides everything evergreen
    Given Im logged in as a user "first_name=Asha" for an entity "name=Caphive Demo;entity_type=Investment Fund"
    And the user has role "company_admin"
    And the entity has evergreen funds switched on
    And the user is tagged "FundOps"
    And today is "2026-09-01"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly"
    And "Q Capital" is an investor of the fund with a portal user
    And today is "2026-10-20"
    And "Q Capital" has placed a "subscription" order "amount=25000000" received "2026-10-20 09:00"
    And the entity has evergreen funds switched off
    And the email queue is cleared
    When the daily notification check runs on "2026-10-26"
    Then "Q Capital" should receive no email with subject "Alpha Long-Short Fund: Payment due before the cut-off"
    And there should be 0 "payment_reminder" notification logs for the order of "Q Capital"
    When I open the fund page
    Then I should see the closed-ended fund page
    And the fund actions should not offer evergreen
    When I open the order book
    Then I should see "This fund is not evergreen"
    When "Q Capital" logs in to the portal
    And I open the fund as an investor
    Then I should not see the evergreen investor page
