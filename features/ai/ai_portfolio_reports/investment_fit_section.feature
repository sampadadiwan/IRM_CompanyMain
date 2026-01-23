Feature: Investment Fit Section
  As an analyst
  I want to generate an investment fit section in portfolio reports
  So that I can evaluate companies against custom investment criteria

  Background:
    Given I am logged in as an analyst
    And a portfolio company "TechCorp" exists
    And an investment criteria template "Growth Stage Criteria" exists with criteria:
      | name           | value                    |
      | Revenue        | Minimum $10M ARR         |
      | Growth Rate    | At least 50% YoY         |

  Scenario: Generate investment fit section for a portfolio report
    Given an AI portfolio report exists for "TechCorp"
    When I generate an investment fit section using template "Growth Stage Criteria"
    Then the section should contain an investment fit evaluation
    And the section should display the template name "Growth Stage Criteria"
