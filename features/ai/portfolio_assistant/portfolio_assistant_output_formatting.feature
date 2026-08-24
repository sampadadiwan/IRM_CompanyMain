Feature: PortfolioAssistant output formatting fixes
  As a portfolio manager reading the Portfolio Assistant's chat responses
  I want the assistant's own text preserved and its hyperlinks to open correctly
  So that a coincidental word match or a stripped HTML attribute never corrupts my answer

  Background:
    Given there is a user "first_name=FM-Analyst" for an entity "entity_type=Investment Fund;name=Acme FM"

  # Regression test for: BaseAssistant#clean_response! used to strip everything before the
  # LAST occurrence of the bare substring "thought" anywhere in the response, mangling any
  # legitimate answer that happened to contain that word.
  Scenario: A genuine leaked "Thought:" prefix is stripped
    Given there is a chat response with the following content:
      """
      Thought: I should look up the company first.
      Here is the summary you asked for.
      """
    When the assistant cleans the response
    Then the response content should equal "Here is the summary you asked for."

  Scenario: A KPI name containing the word "thought" is left untouched
    Given there is a chat response with content "The 'thought leadership score' KPI is 87 for this company."
    When the assistant cleans the response
    Then the response content should equal "The 'thought leadership score' KPI is 87 for this company."

  Scenario: A sentence that happens to contain the word "thought" is left untouched
    Given there is a chat response with content "We thought the runway would extend to Q3, but the latest KPI update shows otherwise."
    When the assistant cleans the response
    Then the response content should equal "We thought the runway would extend to Q3, but the latest KPI update shows otherwise."

  # Regression test for: the full-page chat UI's HTML sanitizer allowlisted `href` but not
  # `target`, so every `target="_blank"` link the assistant emitted (per its own system
  # prompt) silently opened in the same tab instead of a new one.
  Scenario: Hyperlink target attribute survives HTML sanitization
    When I render the markdown "<a href=\"/investors/123\" target=\"_blank\">Acme Co</a>" to HTML
    Then the rendered HTML should include "target=\"_blank\""
    And the rendered HTML should include "href=\"/investors/123\""
