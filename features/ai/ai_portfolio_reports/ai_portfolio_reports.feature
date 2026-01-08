Feature: AI Portfolio Reports
  As an analyst
  I want to create AI-powered portfolio reports
  So that I can efficiently analyze portfolio companies

  Background:
    Given I am logged in as an analyst
    And a portfolio company "TechCorp" exists

  Scenario: Create a new AI portfolio report
    Given I am at the AI portfolio reports page
    When I create a new AI portfolio report for "TechCorp"
    Then an AI portfolio report should be created
    And I should see "Report created!"

  Scenario: Insert chart into section
    Given an AI portfolio report exists for "TechCorp"
    When I visit the AI portfolio report details page
    And I open the chart modal
    And I enter chart prompt "Show revenue trend"
    And I click "Insert Chart"
    Then the chart should be saved to the database
