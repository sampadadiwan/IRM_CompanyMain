Feature: Outlook Email Matcher
  As a fund manager
  I want to automatically match emails to investors
  So that I can file them efficiently

  Background:
    Given a fund exists
    And an investor exists in that fund
    And an approved investor access exists for "john@example.com" for that investor

  Scenario: Matching a single investor by from_email
    When I match an email from "john@example.com"
    Then the match result should be "single"
    And the matched investor should be that investor

  Scenario: Matching multiple investors by CC domain
    Given another investor exists in that fund
    And that other investor has primary_email "contact@jane.com"
    When I match an email from "external@example.com" with cc "info@jane.com"
    Then the match result should be "single"
    And the matched investor should be that other investor

  Scenario: No match found
    When I match an email from "unknown@example.com"
    Then the match result should be "none"

  Scenario: API - Match investor
    When I call the match API with from "john@example.com"
    Then the API response should indicate "single" match
    And the API response should include the investor "john@example.com"

  Scenario: API - File email
    When I call the file email API for the investor with "john@example.com" and subject "Test Subject"
    Then the API response should be successful
    And an incoming email should be created for that investor with subject "Test Subject"
