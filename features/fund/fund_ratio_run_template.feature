@import
Feature: Fund Ratio Run Templates — configuration, bulk trigger, tag trigger
  FundRatioRunTemplate stores a reusable filter configuration per entity.
  Triggering a template enqueues FundRatiosScenarioJob with the stored
  params and the supplied end_date, then creates/reuses a FundRatioRun
  via the existing fingerprint mechanism.

  Background:
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund;currency=INR"
    Given the user has role "company_admin"
    Given there is a fund "name=Demo Fund 2;currency=INR;unit_types=A1" for the entity
    And Given import file "fund_ratios/exchange_rates.xlsx" for "ExchangeRate"

  # ── CRUD ─────────────────────────────────────────────────────────────────────

  Scenario: Creating a cross-fund template stores all filter fields
    Given there is a second fund "name=Demo Fund B;currency=INR" for the entity
    When I create a template "name=CF-Benchmark;run_type=cross-fund" with the two funds
    Then a FundRatioRunTemplate should exist with name "CF-Benchmark" and run_type "cross-fund"
    And the template "CF-Benchmark" should record both fund ids

  Scenario: Creating a cross-portfolio template stores tag and sector filters
    When I create a template "name=PE-Pack;run_type=cross-portfolio;tag=PE;portfolio_companies_tags=growth"
    Then a FundRatioRunTemplate should exist with name "PE-Pack" and tag "PE"
    And the template "PE-Pack" should store portfolio_companies_tags "growth"

  Scenario: Template names must be unique within an entity
    When I create a template "name=Duplicate;run_type=cross-fund"
    Then creating another template "name=Duplicate;run_type=cross-portfolio" should fail with a validation error

  Scenario: Updating a template changes its stored fields
    Given there is a template "name=Old Name;run_type=cross-fund" for the entity
    When I update the template "Old Name" name to "New Name"
    Then a FundRatioRunTemplate should exist with name "New Name" and run_type "cross-fund"
    And no FundRatioRunTemplate should exist with name "Old Name"

  Scenario: Destroying a template removes it
    Given there is a template "name=Temp Delete;run_type=cross-fund" for the entity
    When I destroy the template "Temp Delete"
    Then no FundRatioRunTemplate should exist with name "Temp Delete"

  # ── Single trigger ────────────────────────────────────────────────────────────

  Scenario: Triggering a single template enqueues a FundRatiosScenarioJob and creates a FundRatioRun
    Given there is a second fund "name=Demo Fund B;currency=INR" for the entity
    And Given import file "fund_ratios/investors.xlsx" for "Investor"
    And Given import file "fund_ratios/valuations.xlsx" for "Valuation"
    And Given import file "fund_ratios/portfolio_investments.xlsx" for "PortfolioInvestment"
    And there is a template "name=Single-Trigger;run_type=cross-fund" with both funds for the entity
    When I trigger template "Single-Trigger" for end_date "31-03-2024"
    Then a FundRatioRun should exist with run_type "cross-fund" and end_date "31-03-2024"
    And FundRatios should exist linked to that FundRatioRun

  # ── Trigger All ──────────────────────────────────────────────────────────────

  Scenario: Trigger All enqueues jobs for every entity template
    Given there is a second fund "name=Demo Fund B;currency=INR" for the entity
    And Given import file "fund_ratios/investors.xlsx" for "Investor"
    And Given import file "fund_ratios/valuations.xlsx" for "Valuation"
    And Given import file "fund_ratios/portfolio_investments.xlsx" for "PortfolioInvestment"
    And there is a template "name=All-A;tag=batch" with the first fund for the entity
    And there is a template "name=All-B;tag=batch" with the second fund for the entity
    When I trigger all templates for end_date "31-03-2024"
    Then 2 FundRatioRuns should exist for end_date "31-03-2024"

  # ── Trigger by Tag ───────────────────────────────────────────────────────────

  Scenario: Trigger by Tag only enqueues templates with the matching tag
    Given there is a second fund "name=Demo Fund B;currency=INR" for the entity
    And Given import file "fund_ratios/investors.xlsx" for "Investor"
    And Given import file "fund_ratios/valuations.xlsx" for "Valuation"
    And Given import file "fund_ratios/portfolio_investments.xlsx" for "PortfolioInvestment"
    And there is a template "name=Tagged-A;tag=monthly" with the first fund for the entity
    And there is a template "name=Tagged-B;tag=monthly" with the second fund for the entity
    And there is a template "name=Tagged-C;tag=quarterly" with both funds for the entity
    When I trigger templates by tag "monthly" for end_date "31-03-2024"
    Then 2 FundRatioRuns should exist for end_date "31-03-2024"

  # ── Validation Rules ─────────────────────────────────────────────────────────

  Scenario: Triggering a template on a non-quarter-end date fires a warning when opted in
    Given the default validation rules are seeded
    And the entity has opted in to all validation rules
    And there is a template "name=VR-Template;run_type=cross-fund" for the entity
    When the validation rules are evaluated for a FundRatioRunTemplate "VR-Template" with trigger_end_date "2024-03-15"
    Then the rule "fund_ratio_run_template_date_not_quarter_end" fires as a "warning"

  Scenario: Triggering a template on a quarter-end date does not fire the date warning
    Given the default validation rules are seeded
    And the entity has opted in to all validation rules
    And there is a template "name=VR-QE-Template;run_type=cross-fund" for the entity
    When the validation rules are evaluated for a FundRatioRunTemplate "VR-QE-Template" with trigger_end_date "2024-03-31"
    Then the rule "fund_ratio_run_template_date_not_quarter_end" does not fire

  # ── UI — modal interaction ────────────────────────────────────────────────────

  @javascript
  Scenario: Run modal for a specific template opens and submits to the server
    Given I am at the login page
    When I fill and submit the login page
    And there is a template "name=Modal-Test;run_type=cross-fund" for the entity
    When I visit the ratio run templates index
    And I open the Run modal for template "Modal-Test"
    And I fill in the run end date "2024-03-31" and submit
    Then I should see a flash notice containing "Enqueued"

  # ── Idempotency ──────────────────────────────────────────────────────────────

  Scenario: Triggering the same template twice for the same end_date reuses the FundRatioRun
    Given there is a second fund "name=Demo Fund B;currency=INR" for the entity
    And Given import file "fund_ratios/investors.xlsx" for "Investor"
    And Given import file "fund_ratios/portfolio_investments.xlsx" for "PortfolioInvestment"
    And there is a template "name=Idem-Template;run_type=cross-fund" with both funds for the entity
    When I trigger template "Idem-Template" for end_date "31-03-2024"
    And I trigger template "Idem-Template" for end_date "31-03-2024"
    Then only one FundRatioRun should exist for the template "Idem-Template" on "31-03-2024"
