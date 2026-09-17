Feature: Shareholder Position Fully Diluted/Quantity Actuals approval workflow
  As a startup dashboard user
  I want re-uploaded Fully Diluted Quantity/% and Quantity Actuals changes to be staged for review
  So that an approved position is never silently overwritten by a re-upload

  Background:
    Given Im logged in as a user "" for an entity "name=Startup Inc;entity_type=Investment Fund"
    Given the user has role "company_admin"
    And there is an existing portfolio company "investor_name=Startup Inc;category=Portfolio Company"
    And there is an investor named "Test Investor"

  Scenario: Stages a changed Quantity Actuals as a pending update without touching the approved row
    When I upload a shareholder positions file for "Startup Inc" with:
      | ShareHolder   | Category | As Of      | Fully Dilluted Quantity | Quantity Actuals |
      | Test Investor | Founder  | March 2025 | 1000                    | 500               |
    And I upload a shareholder positions file for "Startup Inc" with:
      | ShareHolder   | Category | As Of      | Fully Dilluted Quantity | Quantity Actuals |
      | Test Investor | Founder  | March 2025 | 1000                    | 600               |
    Then the shareholder position upload should succeed
    And the approved shareholder position for "Test Investor" at "Startup Inc" should have:
      | quantity_actual | 500  |
      | position_amount | 1000 |
    And the unapproved shareholder position for "Test Investor" at "Startup Inc" should have:
      | quantity_actual | 600  |
      | position_amount | 1000 |

  Scenario: Stages a changed Fully Diluted Quantity as a pending update without touching the approved row
    When I upload a shareholder positions file for "Startup Inc" with:
      | ShareHolder   | Category | As Of      | Fully Dilluted Quantity | Quantity Actuals |
      | Test Investor | Founder  | March 2025 | 1000                    | 500               |
    And I upload a shareholder positions file for "Startup Inc" with:
      | ShareHolder   | Category | As Of      | Fully Dilluted Quantity | Quantity Actuals |
      | Test Investor | Founder  | March 2025 | 1200                    | 500               |
    Then the shareholder position upload should succeed
    And the approved shareholder position for "Test Investor" at "Startup Inc" should have:
      | position_amount | 1000 |
    And the unapproved shareholder position for "Test Investor" at "Startup Inc" should have:
      | position_amount | 1200 |

  Scenario: Accepting a pending Quantity Actuals change overwrites the approved row and removes the pending one
    Given I upload a shareholder positions file for "Startup Inc" with:
      | ShareHolder   | Category | As Of      | Fully Dilluted Quantity | Quantity Actuals |
      | Test Investor | Founder  | March 2025 | 1000                    | 500               |
    And I upload a shareholder positions file for "Startup Inc" with:
      | ShareHolder   | Category | As Of      | Fully Dilluted Quantity | Quantity Actuals |
      | Test Investor | Founder  | March 2025 | 1000                    | 600               |
    When I go to the captable of the portfolio company
    Then I should see a pending updates banner for "March 2025"
    And I should see "Test Investor" as a pending update with Accept and Deny buttons
    When I click "Accept" for the pending update for "Test Investor"
    Then I should not see a pending updates banner
    And the approved shareholder position for "Test Investor" at "Startup Inc" should have:
      | quantity_actual | 600 |
    And 0 unapproved shareholder positions should exist for "Test Investor" at "Startup Inc"

  Scenario: Denying a pending Quantity Actuals change discards it and leaves the approved row unchanged
    Given I upload a shareholder positions file for "Startup Inc" with:
      | ShareHolder   | Category | As Of      | Fully Dilluted Quantity | Quantity Actuals |
      | Test Investor | Founder  | March 2025 | 1000                    | 500               |
    And I upload a shareholder positions file for "Startup Inc" with:
      | ShareHolder   | Category | As Of      | Fully Dilluted Quantity | Quantity Actuals |
      | Test Investor | Founder  | March 2025 | 1000                    | 600               |
    When I go to the captable of the portfolio company
    When I click "Deny" for the pending update for "Test Investor"
    Then I should not see a pending updates banner
    And the approved shareholder position for "Test Investor" at "Startup Inc" should have:
      | quantity_actual | 500 |
    And 0 unapproved shareholder positions should exist for "Test Investor" at "Startup Inc"

  Scenario: A pure Fully Dilluted %-only change cannot be individually accepted or rejected
    Given there is an investor named "Other Holder"
    Given I upload a shareholder positions file for "Startup Inc" with:
      | ShareHolder   | Category | As Of      | Fully Dilluted Quantity | Fully Dilluted % | Quantity Actuals |
      | Test Investor | Founder  | March 2025 | 1000                    | 20%               | 500               |
      | Other Holder  | Founder  | March 2025 | 4000                    | 80%               | 2000              |
    And I upload a shareholder positions file for "Startup Inc" with:
      | ShareHolder   | Category | As Of      | Fully Dilluted Quantity | Fully Dilluted % | Quantity Actuals |
      | Test Investor | Founder  | March 2025 | 1000                    | 25%               | 500               |
      | Other Holder  | Founder  | March 2025 | 4000                    | 75%               | 2000              |
    When I go to the captable of the portfolio company
    Then I should see a pending updates banner for "March 2025"
    And I should see "Test Investor" as a pending update with a percent-only change message

  Scenario: Accept All approves every pending update shown for a round
    Given there is an investor named "Jane Doe"
    And I upload a shareholder positions file for "Startup Inc" with:
      | ShareHolder   | Category | As Of      | Fully Dilluted Quantity | Quantity Actuals |
      | Test Investor | Founder  | March 2025 | 1000                    | 500               |
      | Jane Doe      | Founder  | March 2025 | 2000                    | 800               |
    And I upload a shareholder positions file for "Startup Inc" with:
      | ShareHolder   | Category | As Of      | Fully Dilluted Quantity | Quantity Actuals |
      | Test Investor | Founder  | March 2025 | 1000                    | 600               |
      | Jane Doe      | Founder  | March 2025 | 2000                    | 900               |
    When I go to the captable of the portfolio company
    And I click "Accept All" and confirm
    Then I should not see a pending updates banner
    And the approved shareholder position for "Test Investor" at "Startup Inc" should have:
      | quantity_actual | 600 |
    And the approved shareholder position for "Jane Doe" at "Startup Inc" should have:
      | quantity_actual | 900 |

  Scenario: Reject All discards every pending update shown for a round
    Given there is an investor named "Jane Doe"
    And I upload a shareholder positions file for "Startup Inc" with:
      | ShareHolder   | Category | As Of      | Fully Dilluted Quantity | Quantity Actuals |
      | Test Investor | Founder  | March 2025 | 1000                    | 500               |
      | Jane Doe      | Founder  | March 2025 | 2000                    | 800               |
    And I upload a shareholder positions file for "Startup Inc" with:
      | ShareHolder   | Category | As Of      | Fully Dilluted Quantity | Quantity Actuals |
      | Test Investor | Founder  | March 2025 | 1000                    | 600               |
      | Jane Doe      | Founder  | March 2025 | 2000                    | 900               |
    When I go to the captable of the portfolio company
    And I click "Reject All" and confirm
    Then I should not see a pending updates banner
    And the approved shareholder position for "Test Investor" at "Startup Inc" should have:
      | quantity_actual | 500 |
    And the approved shareholder position for "Jane Doe" at "Startup Inc" should have:
      | quantity_actual | 800 |
