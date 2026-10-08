Feature: Cap table sample upload files
  As a portfolio company cap table user
  I want the sample files offered on the upload pages to match the current import format
  So that filling in a sample and uploading it imports subgroups and instruments correctly

  Spec: openspec/changes/investment-subgroups-and-captable-actions/specs/startups/cap-table-sample-uploads/spec.md

  Background:
    Given Im logged in as a user "" for an entity "name=Startup Inc;entity_type=Investment Fund"
    Given the user has role "company_admin"

  Scenario: The investments sample imports as-is with its subgroup and instrument columns
    Given there is an existing portfolio company "investor_name=AX;category=Portfolio Company"
    When I go to the captable of the portfolio company
    And I click the "Upload Investments" button
    Then the upload page should offer the sample file "investments.xlsx"
    When I upload the sample file "investments.xlsx"
    Then the upload should succeed with 2 rows
    And the investment for "John Doe" should have:
      | category            | Founder  |
      | investment_type     | Equity   |
      | funding_round       | Founding |
      | quantity            | 3500     |
      | subgroup            |          |
      | instrument_name     |          |
      | instrument_quantity |          |
    And the investment for "NorthInc Ventures" should have:
      | category            | Other         |
      | investment_type     | Convertible   |
      | funding_round       | Series A      |
      | quantity            | 1500          |
      | subgroup            | Institutional |
      | instrument_name     | CCPS Series A |
      | instrument_quantity | 15            |
    And the imported investments should not have custom fields named:
      | Subgroup            |
      | Instrument Name     |
      | Instrument Quantity |

  Scenario Outline: The investments import accepts the subgroup header as "<header>"
    Given there is an existing portfolio company "investor_name=AX;category=Portfolio Company"
    When I go to the captable of the portfolio company
    And I click the "Upload Investments" button
    And I upload an investments file with:
      | Portfolio Company | Category | Currency | Investor Name | <header>      | Investment Type | Funding Round | Quantity | Price | Investment Date | Notes | Update Only |
      | AX                | Other    | USD      | Angel One     | Institutional | Equity          | Seed          | 100      | 10    | 01/01/2025      |       | No          |
    Then the upload should succeed with 1 row
    And the investment for "Angel One" should have:
      | subgroup | Institutional |
    And the imported investments should not have custom fields named:
      | <header> |

    Examples:
      | header    |
      | Subgroup  |
      | SubGroup  |
      | Sub Group |

  Scenario: An update-only investments import changes the subgroup and instrument details
    Given there is an existing portfolio company "investor_name=AX;category=Portfolio Company"
    And there are the following investments for "AX":
      | investor_name     | category | investment_type | funding_round | quantity | price | investment_date | instrument_name | instrument_quantity |
      | NorthInc Ventures | Other    | Convertible     | Series A      | 1500     | 1.0   | 2025-06-25      | CCPS            | 10                  |
    When I go to the captable of the portfolio company
    And I click the "Upload Investments" button
    And I upload an update-only investments file for "NorthInc Ventures" with:
      | Subgroup            | Institutional |
      | Instrument Name     | CCPS Series A |
      | Instrument Quantity | 15            |
    Then the upload should succeed with 1 row
    And the investment for "NorthInc Ventures" should have:
      | subgroup            | Institutional |
      | instrument_name     | CCPS Series A |
      | instrument_quantity | 15            |

  Scenario: An update-only investments import that omits the subgroup/instrument columns keeps the existing values
    Given there is an existing portfolio company "investor_name=AX;category=Portfolio Company"
    And there are the following investments for "AX":
      | investor_name     | category | investment_type | funding_round | quantity | price | investment_date | subgroup      | instrument_name | instrument_quantity |
      | NorthInc Ventures | Other    | Convertible     | Series A      | 1500     | 1.0   | 2025-06-25      | Institutional | CCPS            | 10                   |
    When I go to the captable of the portfolio company
    And I click the "Upload Investments" button
    And I upload an update-only investments file for "NorthInc Ventures" with:
      | Quantity | 2000 |
    Then the upload should succeed with 1 row
    And the investment for "NorthInc Ventures" should have:
      | quantity            | 2000          |
      | subgroup            | Institutional |
      | instrument_name     | CCPS          |
      | instrument_quantity | 10            |

  Scenario: The shareholder positions sample imports as-is for both of its As Of snapshots
    Given there is an existing portfolio company "investor_name=Ace Ltd;category=Portfolio Company"
    When I go to the captable of the portfolio company
    And I click the "Upload Shareholding Patterns" button
    Then the upload page should offer the sample file "shareholder_positions.xlsx"
    When I upload the sample file "shareholder_positions.xlsx"
    Then the upload should succeed with 15 rows
    And the shareholder position for "Seed Ventures LP" as of "2025-12-31" should have:
      | category        | Other         |
      | subgroup        | Institutional |
      | instrument      | CCPS          |
      | quantity_actual | 900000        |
      | position_amount | 900000        |
    And the shareholder position for "ESOP Pool" as of "Series A" should have:
      | category        | Employee |
      | instrument      | Options  |
      | quantity_actual | 550000   |
      | position_amount | 1300000  |
    And the shareholder position for "Growth Capital Fund" as of "Series A" should have:
      | subgroup   | Institutional |
      | instrument | CCPS          |
    When I go to the captable of the portfolio company
    Then I should see "Funding Round: Series A"
    And the horizontal cap table should show "Seed Ventures LP" nested under subgroup "Institutional" under category "Other", in that order
    And the horizontal cap table should show "Angel Syndicate" nested under subgroup "Angel" under category "Other", in that order
