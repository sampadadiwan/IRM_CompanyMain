# Support Console — who may use it, and about which clients.
# Worked examples: openspec/changes/archive/2026-10-22-support-console/design.md#worked-examples
@rack_test @support_console
Feature: Support Console access

  Background:
    Given the client "Golden Angels" has support access "on"
    And the client "Beta Capital" has support access "on"
    And the client "Gamma Ventures" has support access "off"
    And "Meera" is a support user
    And "Kiran" is a support user
    And "Meera" is mapped to "Golden Angels" until "2099-12-31"
    And "Meera" is mapped to "Gamma Ventures" until "2099-12-31"
    And "Kiran" is mapped to "Beta Capital" until "2099-12-31"

  # H2 — Happy path: the picker lists only the clients Meera is mapped to with support access on
  Scenario: Picker lists mapped clients only
    Given I am logged in as "Meera"
    When I open the Support Console
    Then the client picker lists "Golden Angels"
    And the client picker does not list "Beta Capital, Gamma Ventures"

  # E1 — Edge case: a support user with no qualifying mapping sees the empty-state message and no picker
  Scenario: No mapped clients
    Given "Kiran"'s mapping to "Beta Capital" is disabled
    And I am logged in as "Kiran"
    When I open the Support Console
    Then I should see "You are not mapped to any client with support access. Ask a super user to add a support mapping."
    And I see no client picker

  # E5 — Edge case: a mapping that ends today still gives access
  Scenario: Mapping ending today is still open
    Given "Kiran"'s mapping to "Beta Capital" is disabled
    And "Kiran" is mapped to "Golden Angels" until "today"
    And I am logged in as "Kiran"
    When I open the Support Console for "Golden Angels"
    Then I see the conversations for "Golden Angels"

  # E6 — Edge case: a mapping that ended yesterday is closed even before disable_expired has run
  Scenario: Mapping ended yesterday, still marked enabled
    Given "Kiran"'s mapping to "Beta Capital" is disabled
    And "Kiran" is mapped to "Golden Angels" until "yesterday"
    And I am logged in as "Kiran"
    When I open the Support Console
    Then the client picker does not list "Golden Angels"
    When I open the Support Console for "Golden Angels"
    Then I am sent home with "Not authorized."

  # E7 — Edge case: a mapped client without support access is not pickable or reachable
  Scenario: Client without support access
    Given I am logged in as "Meera"
    When I open the Support Console
    Then the client picker does not list "Gamma Ventures"
    When I open the Support Console for "Gamma Ventures"
    Then I am sent home with "Not authorized."

  # X1 — Error case: a client's own employee cannot open the console
  Scenario: Non-support user is refused
    Given "Asha" is an employee of "Golden Angels"
    And I am logged in as "Asha"
    When I open the Support Console
    Then I am sent home with "Not authorized."

  # X2 — Error case: a super user without the support role cannot open the console
  Scenario: Super user without the support role is refused
    Given "Priya" is a super user without the support role
    And I am logged in as "Priya"
    When I open the Support Console
    Then I am sent home with "Not authorized."

  # E8 — Edge case: the mapping is disabled after the question was queued; the job refuses and never calls the relay
  @sync-http
  Scenario: Mapping disabled while the question is queued
    Given "Meera" has a queued question about "Golden Angels"
    And "Meera"'s mapping to "Golden Angels" is disabled
    When the queued turn runs
    Then the queued turn is refused with "Your support access to Golden Angels has ended."
    And the relay was not called

  # X3 — Error case: direct requests for an unmapped client, or another client's conversation, are refused
  Scenario: Direct requests for another client
    Given I am logged in as "Meera"
    When I post a question about "Beta Capital" directly
    Then I am sent home with "Not authorized."
    And no support console messages were created
    When I open "Kiran"'s conversation about "Beta Capital" through "Golden Angels"
    Then I am sent home with "Not authorized."

  # X30 — Error case: a CapHive employee without the support role cannot reach the console's agent through the old AI-agent chat routes
  Scenario: Old chat route refused for the console's agent
    Given "Asha" works at CapHive
    And I am logged in as "Asha"
    When I post a question to the console's agent through the AI-agent chat route about "Golden Angels"
    Then no support console messages were created

  # X31 — Error case: a support user cannot delete a console conversation through the old AI-agent chat routes; it stays for retention
  Scenario: Old chat route cannot delete a console conversation
    Given "Ravi" is a support user at CapHive
    And "Ravi" is mapped to "Golden Angels" until "2099-12-31"
    And "Ravi" has a conversation about "Golden Angels" with a finished answer
    And I am logged in as "Ravi"
    When I delete that conversation through the AI-agent chat route
    Then that conversation still exists
