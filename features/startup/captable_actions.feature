Feature: Cap table page actions
  As a portfolio company cap table user
  I want the cap table page to only offer the upload, view and download actions that apply
  So that a company's cap table is built from one kind of data and I am never offered an empty download

  Spec: openspec/changes/investment-subgroups-and-captable-actions/specs/startups/cap-table-actions/spec.md

  Background:
    Given Im logged in as a user "" for an entity "name=Startup Inc;entity_type=Investment Fund"
    Given the user has role "company_admin"
    And there is an existing portfolio company "investor_name=Startup Inc;category=Portfolio Company"
    And there is an investor named "John Doe"

  Scenario: A company with no data offers both entry points and no downloads
    When I go to the captable of the portfolio company
    Then I should see these cap table actions:
      | New Investment               |
      | Upload Investments           |
      | View Investments             |
      | Upload Shareholding Patterns |
      | View Shareholding Patterns   |
    And I should not see these cap table actions:
      | Download Investments           |
      | Download Shareholding Patterns |

  Scenario: A company with investments offers only the investment actions, including the download
    Given there are the following investments for "Startup Inc":
      | investor_name | category | investment_type | funding_round | quantity | price | investment_date |
      | John Doe      | Founder  | Equity          | Seed          | 1000     | 1.0   | 2024-01-01      |
    When I go to the captable of the portfolio company
    Then I should see these cap table actions:
      | New Investment       |
      | Upload Investments   |
      | View Investments     |
      | Download Investments |
    And I should not see these cap table actions:
      | Upload Shareholding Patterns   |
      | View Shareholding Patterns     |
      | Download Shareholding Patterns |

  Scenario: A company with approved shareholder positions offers only the shareholding actions, including the download
    Given there are the following shareholder positions for "Startup Inc":
      | investor_name | category | round_name | position_amount | quantity_actual |
      | John Doe      | Founder  | Seed       | 1000            | 1000            |
    When I go to the captable of the portfolio company
    Then I should see these cap table actions:
      | Upload Shareholding Patterns   |
      | View Shareholding Patterns     |
      | Download Shareholding Patterns |
    And I should not see these cap table actions:
      | New Investment       |
      | Upload Investments   |
      | View Investments     |
      | Download Investments |

  Scenario: Shareholder positions awaiting approval do not count as data yet
    Given there are the following shareholder positions for "Startup Inc":
      | investor_name | category | round_name | position_amount | status     |
      | John Doe      | Founder  | Seed       | 1000            | unapproved |
    When I go to the captable of the portfolio company
    Then I should see these cap table actions:
      | Upload Investments           |
      | Upload Shareholding Patterns |
    And I should not see these cap table actions:
      | Download Investments           |
      | Download Shareholding Patterns |

  Scenario: The investments list outside a portfolio company offers every action
    Given I am at the investments page
    Then I should see these cap table actions:
      | New Investment                 |
      | Upload Investments             |
      | View Investments               |
      | Download Investments           |
      | Upload Shareholding Patterns   |
      | View Shareholding Patterns     |
      | Download Shareholding Patterns |
