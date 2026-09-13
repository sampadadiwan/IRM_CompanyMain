@cs_agent
Feature: Customer Support Agent guide search ranking
  As a fund manager user asking the Customer Support Agent a "how to" question
  I want the user-guide search to surface the passage that matches all my keywords
  So that the agent answers from the right guide

  Scenario: Creating a stakeholder is answered from the Investors guide, not the Investor Access guide
    When the guide search tool is called with keywords "create stakeholder"
    Then the top result should come from "docs/user_guides/investors_user_guide.md"
    And the top result should mention "Creating a Stakeholder"
    And the results should include "docs/user_guides/investor_access_tutorial.md"

  Scenario: Filler words passed through from the question do not sway the ranking
    When the guide search tool is called with keywords "how to create a stakeholder?"
    Then the top result should come from "docs/user_guides/investors_user_guide.md"
    And the top result should mention "Creating a Stakeholder"

  Scenario: Stakeholder and investor are searched as synonyms
    When the guide search tool is called with keywords "stakeholder"
    Then the results should include "docs/user_guides/investors_user_guide.md"

  Scenario: Passages matching every keyword outrank passages matching one common word
    When the guide search tool is called with keywords "capital call create"
    Then the top result should come from a guide named like "capital_call"
    And every result should contain at least 2 of the keywords

  Scenario: No single guide crowds out the others
    When the guide search tool is called with keywords "create stakeholder investor"
    Then no guide should appear more than 3 times in the results

  Scenario: An FAQ question line ranks like a heading, so a "how to" question lands on the FAQ entry
    When the guide search tool is called with keywords "create stakeholder"
    Then the top result should be a heading or FAQ question line

  Scenario: Industry jargon is searched as a synonym of the guide's own term
    When the guide search tool is called with keywords "drawdown"
    Then the results should include "docs/user_guides/capital_calls_user_guide.md"

  Scenario: The word "where" carries navigation intent instead of being dropped as filler
    When the guide search tool is called with keywords "where capital calls"
    Then the top result should come from a guide named like "capital_call"
    And the top result should be a heading or FAQ question line
