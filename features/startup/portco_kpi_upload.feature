Feature: Portfolio Company KPI Self-Reporting
  As a Portfolio Company user
  I want to be able to fill out KPI reports requested by the Fund
  So that I can report my performance directly

  Background:
    Given there is a user "first_name=FundAdmin" for an entity "name=VentureFund;entity_type=Investment Fund"
    And there is an existing portfolio company "name=MyStartup;category=Portfolio Company"
    And a KpiReport "as_of=2024-12-31;period=Month" exists for the portfolio company "MyStartup"

  @kpi_self_report
  Scenario: Portfolio Company user fills out a pre-created KPI report
    Given Im logged in as a user "first_name=PortCoUser" for an existing entity "name=MyStartup;category=Portfolio Company"
    When I fill out the KPI report "as_of=2024-12-31" for portfolio company "MyStartup" with notes "This report was filled by the startup"

    Then the KPI report should have notes "This report was filled by the startup"
    And the KPI report should be owned by user "PortCoUser"
