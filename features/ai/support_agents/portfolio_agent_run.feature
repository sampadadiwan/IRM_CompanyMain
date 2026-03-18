Feature: Portfolio Agent Run View
  As a fund manager
  I want to run portfolio company agents on selected companies
  So that I can analyze multiple portfolio companies at once

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is a support agent "agent_type=PortfolioCompanyAgent;name=PortCo Analyst;enabled=true"
    And there is an existing portfolio company "name=TechCorp;category=Portfolio Company"
    And portfolio company is added to list of companies
    And there is an existing portfolio company "name=HealthInc;category=Portfolio Company"
    And portfolio company is added to list of companies
    And there is an existing portfolio company "name=ConsumerBrand;category=Portfolio Company"
    And portfolio company is added to list of companies
    And the portfolio companies are tagged randomly from "Fintech, SaaS, Healthcare, D2C"
    And the portfolio companies belong to sectors "FinTech, HealthTech, E-commerce"

  Scenario: View portfolio agent run page with filters
    When I visit the portfolio agent run page
    Then I should see the page title "Portfolio Agent Run"
    And I should see the filter section for tags and sectors
    And I should see the company selection dropdown
    And I should see the run agent button
    And I should see a table of portfolio companies

  Scenario: Filter portfolio companies by tags
    Given the portfolio companies are tagged with "Fintech"
    When I visit the portfolio agent run page
    And I select tag "Fintech" from the filter
    And I click the search button
    Then I should only see portfolio companies with tag "Fintech"

  Scenario: Filter portfolio companies by sectors
    When I visit the portfolio agent run page
    And I select sector "FinTech" from the filter
    And I click the search button
    Then I should only see portfolio companies with sector "FinTech"

  Scenario: Filter portfolio companies by specific company selection
    When I visit the portfolio agent run page
    And I select 2 companies from the dropdown
    And I click the search button
    Then I should see exactly 2 companies in the table

  Scenario: Display last run times for companies
    Given the agent has run for "TechCorp" 2 hours ago
    When I visit the portfolio agent run page
    Then I should see "2 hours ago" in the "Last Run" column for "TechCorp"


  Scenario: Display agent report status with issue counts
    Given the agent report for "TechCorp" has 3 KPI blocking issues
    And the agent report for "TechCorp" has 2 valuation blocking issues
    And the agent report for "TechCorp" has 1 missing document
    When I visit the portfolio agent run page
    Then I should see "3 KPI" button in danger state for "TechCorp"
    And I should see "2 Val" button in danger state for "TechCorp"
    And I should see "1 Doc" button in danger state for "TechCorp"

  Scenario: Display agent report with no issues
    Given the agent report for "HealthInc" has no issues
    When I visit the portfolio agent run page
    Then I should see "0 KPI" button in success state for "HealthInc"
    And I should see "0 Val" button in success state for "HealthInc"
    And I should see "0 Doc" button in success state for "HealthInc"

  Scenario: Table displays company information
    When I visit the portfolio agent run page
    Then I should see "TechCorp" in the company name column
    And I should see a link to the company page

  Scenario: Subscribe to Turbo Stream updates
    When I visit the portfolio agent run page
    Then the page should subscribe to portfolio agent batch stream
    And the page should be ready to receive batch completion updates
