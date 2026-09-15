Feature: Shareholder Position Import
  As a startup dashboard user
  I want to upload shareholder position spreadsheets
  So that founder/employee/other holdings are recorded even without formal Investment records

  Background:
    Given Im logged in as a user "" for an entity "name=Startup Inc;entity_type=Investment Fund"
    Given the user has role "company_admin"
    And there is an existing portfolio company "investor_name=Startup Inc;category=Portfolio Company"
    And there is an investor named "Test Investor"

  Scenario: Uploads a brand-new position from a Fully Dilluted Quantity column
    When I upload a shareholder positions file for "Startup Inc" with:
      | ShareHolder   | Category | As Of      | Fully Dilluted Quantity |
      | Test Investor | Founder  | March 2025 | 1000                    |
    Then the shareholder position upload should succeed
    And 1 shareholder positions should have been created
    And the approved shareholder position for "Test Investor" at "Startup Inc" should have:
      | position_amount | 1000     |
      | category        | Founder  |

  Scenario: Rejects an unrecognized Category value
    When I upload a shareholder positions file for "Startup Inc" with:
      | ShareHolder   | Category      | As Of      | Fully Dilluted Quantity |
      | Test Investor | Lead Investor | March 2025 | 1000                    |
    Then the shareholder position upload should have 1 failed rows
    And 0 shareholder positions should have been created

  Scenario: Stores an optional Subgroup
    When I upload a shareholder positions file for "Startup Inc" with:
      | ShareHolder   | Category | Subgroup   | As Of      | Fully Dilluted Quantity |
      | Test Investor | Founder  | Management | March 2025 | 1000                    |
    Then the shareholder position upload should succeed
    And the approved shareholder position for "Test Investor" at "Startup Inc" should have:
      | subgroup | Management |

  Scenario: Resolves the Portfolio Company per row when the upload is not scoped to a single company
    Given there is an existing portfolio company "investor_name=Beta Corp;category=Portfolio Company"
    And there is an investor named "Jackie"
    And there is an investor named "Ronald"
    When I upload a shareholder positions file with:
      | ShareHolder | Portfolio Company | Category | As Of      | Fully Dilluted Quantity |
      | Jackie      | Startup Inc        | Founder  | March 2025 | 1000                    |
      | Ronald      | Beta Corp          | Founder  | March 2025 | 2000                    |
    Then the shareholder position upload should succeed
    And the approved shareholder position for "Jackie" at "Startup Inc" should have:
      | position_amount | 1000 |
    And the approved shareholder position for "Ronald" at "Beta Corp" should have:
      | position_amount | 2000 |

  Scenario: Resolves the Portfolio Company from a Stakeholder column alias
    When I upload a shareholder positions file with:
      | ShareHolder   | Stakeholder | Category | As Of      | Fully Dilluted Quantity |
      | Test Investor | Startup Inc | Founder  | March 2025 | 1000                    |
    Then the shareholder position upload should succeed
    And the approved shareholder position for "Test Investor" at "Startup Inc" should have:
      | position_amount | 1000 |

  Scenario: Fails the row when the named Portfolio Company cannot be found
    When I upload a shareholder positions file with:
      | ShareHolder   | Portfolio Company | Category | As Of      | Fully Dilluted Quantity |
      | Test Investor | Nonexistent Co     | Founder  | March 2025 | 1000                    |
    Then the shareholder position upload should have 1 failed rows

  Scenario: Rejects an upload missing a Portfolio Company/Stakeholder column
    When I upload a shareholder positions file with:
      | ShareHolder   | Category | As Of      | Fully Dilluted Quantity |
      | Test Investor | Founder  | March 2025 | 1000                    |
    Then the shareholder position upload should fail with "Portfolio Company"

  Scenario: Rejects an upload missing both Fully Dilluted % and Fully Dilluted Quantity columns
    When I upload a shareholder positions file for "Startup Inc" with:
      | ShareHolder   | Category | As Of      |
      | Test Investor | Founder  | March 2025 |
    Then the shareholder position upload should fail with "Fully Dilluted Quantity"

  Scenario: Accepts an upload with only a Fully Dilluted Quantity column and no Fully Dilluted % column
    When I upload a shareholder positions file for "Startup Inc" with:
      | ShareHolder   | Category | As Of      | Fully Dilluted Quantity |
      | Test Investor | Founder  | March 2025 | 1000                    |
    Then the shareholder position upload should succeed

  Scenario: Parses a dd/mm/yyyy As Of date
    When I upload a shareholder positions file for "Startup Inc" with:
      | ShareHolder   | Category | As Of      | Fully Dilluted Quantity |
      | Test Investor | Founder  | 31/01/2025 | 1000                    |
    Then the shareholder position upload should succeed
    And the approved shareholder position for "Test Investor" at "Startup Inc" should have:
      | position_date | 2025-01-31 |

  Scenario: Treats a non-date As Of value as a free-text round name
    When I upload a shareholder positions file for "Startup Inc" with:
      | ShareHolder   | Category | As Of          | Fully Dilluted Quantity |
      | Test Investor | Founder  | Secondary Sale | 1000                    |
    Then the shareholder position upload should succeed
    And the approved shareholder position for "Test Investor" at "Startup Inc" should have:
      | round_name    | Secondary Sale |
      | position_date |                |

  Scenario: Prefers the uploaded Fully Dilluted Quantity over Fully Dilluted % when both are present
    When I upload a shareholder positions file for "Startup Inc" with:
      | ShareHolder   | Category | As Of      | Fully Dilluted Quantity | Fully Dilluted % |
      | Test Investor | Founder  | March 2025 | 10500                   | 100%             |
    Then the shareholder position upload should succeed
    And the approved shareholder position for "Test Investor" at "Startup Inc" should have:
      | position_amount | 10500 |

  Scenario: Rejects an upload with only a Fully Dilluted % column and no Fully Dilluted Quantity column
    When I upload a shareholder positions file for "Startup Inc" with:
      | ShareHolder   | Category | As Of      | Fully Dilluted % |
      | Test Investor | Founder  | March 2025 | 20%              |
    Then the shareholder position upload should fail with "Fully Dilluted Quantity"
    And 0 shareholder positions should have been created
