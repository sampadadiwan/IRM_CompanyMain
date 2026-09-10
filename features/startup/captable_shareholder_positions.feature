Feature: Cap Table handling of Shareholder Position uploads
  As a startup dashboard user
  I want the cap table (and horizontal cap table) to correctly roll up uploaded Shareholder
  Position rows alongside (or instead of) Investment records
  So Quantity, % and Fully Diluted figures are accurate even for companies with no Investment records

  Background:
    Given Im logged in as a user "" for an entity "name=Startup Inc;entity_type=Investment Fund"
    Given the user has role "company_admin"
    And there is an existing portfolio company "investor_name=Startup Inc;category=Portfolio Company"
    And there is an investor named "John Doe"

  Scenario: Reflects the uploaded Quantity Actuals in the Quantity column, not just the Fully Diluted Quantity column
    Given there are the following shareholder positions for "Startup Inc":
      | investor_name | category | round_name | position_amount | quantity_actual |
      | John Doe       | Founder  | March 2025 | 10500            | 10500            |
    When I go to the captable of the portfolio company
    Then I should see "John Doe" with quantity "10500" and fully diluted "10500" in the "March 2025" round

  Scenario: Splits the Fully Diluted Quantity between the equity and dilution buckets so the total is not double-counted
    Given there are the following shareholder positions for "Startup Inc":
      | investor_name | category | round_name | position_amount | quantity_actual |
      | John Doe       | Founder  | March 2025 | 5000             | 5500             |
    When I go to the captable of the portfolio company
    Then I should see "John Doe" with quantity "5500" and fully diluted "5000" in the "March 2025" round

  Scenario: Still uses the full Fully Diluted Quantity for the dilution bucket when no Quantity Actual is uploaded
    Given there are the following shareholder positions for "Startup Inc":
      | investor_name | category | round_name | position_amount |
      | John Doe       | Founder  | March 2025 | 2500             |
    When I go to the captable of the portfolio company
    Then I should see "John Doe" with quantity "0" and fully diluted "2500" in the "March 2025" round

  Scenario: Computes each investor's % from the sum of every Quantity Actual in the round
    Given there is an investor named "Golden Angels"
    And there is an investor named "Rojer Jones"
    And there is an investor named "Shore Ventures"
    And there are the following shareholder positions for "Startup Inc":
      | investor_name  | category | round_name | position_amount | quantity_actual |
      | John Doe       | Founder  | March 2025 | 10500            | 10500            |
      | Golden Angels  | Self     | March 2025 | 5000             | 5500             |
      | Rojer Jones    | Other    | March 2025 | 2500             | 2500             |
      | Shore Ventures | Other    | March 2025 | 5600             | 6500             |
    When I go to the captable of the portfolio company
    Then I should see "John Doe" with quantity "10500", percentage "42.0%", and fully diluted "10500" in the "March 2025" round
    And I should see "Golden Angels" with quantity "5500", percentage "22.0%", and fully diluted "5000" in the "March 2025" round
    And I should see "Rojer Jones" with quantity "2500", percentage "10.0%", and fully diluted "2500" in the "March 2025" round
    And I should see "Shore Ventures" with quantity "6500", percentage "26.0%", and fully diluted "5600" in the "March 2025" round

  Scenario: Uses a Shareholder Position round_name directly as the cap table round label
    Given there are the following shareholder positions for "Startup Inc":
      | investor_name | category | round_name     | position_amount |
      | John Doe       | Other    | Secondary Sale | 10               |
    When I go to the captable of the portfolio company
    Then I should see "Funding Round: Secondary Sale"

  Scenario: Does not duplicate an investor across categories when Investment rounds and Shareholder Position snapshots disagree on category
    And there are the following investments for "Startup Inc":
      | investor_name | category | investment_type | funding_round | quantity | price | investment_date |
      | John Doe       | Founder  | Equity          | Series A      | 100      | 1.0   | 2024-06-01      |
    And there are the following shareholder positions for "Startup Inc":
      | investor_name | category | subgroup   | position_date | position_amount |
      | John Doe       | Employee | Management | 2025-01-31     | 10               |
    When I go to the captable with params ""
    Then I should see the horizontal cap table table
    And the horizontal cap table should show "John Doe" nested under subgroup "Management" under category "Employee", in that order

  Scenario: Groups shareholders within a category by their subgroup for the horizontal cap table
    Given there is an investor named "Jack"
    And there are the following shareholder positions for "Startup Inc":
      | investor_name | category | subgroup | position_date | position_amount |
      | Jack           | Founder  | A        | 2025-01-31     | 10               |
    When I go to the captable with params ""
    Then I should see the horizontal cap table table
    And the horizontal cap table should show "Jack" nested under subgroup "A" under category "Founder", in that order
