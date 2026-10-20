# Support Console — starting and stopping the shared support machine, idle stop, and the conversation's usage.
# EC2 is SupportConsoleMachineStub (features/support/support_console_machine_stub.rb); the relay is stubbed.
# Worked examples: openspec/changes/support-console/design.md#worked-examples
@rack_test @support_console @sync-http
Feature: Support Console machine

  Background:
    Given the client "Golden Angels" has support access "on"
    And "Meera" is a support user
    And "Meera" is mapped to "Golden Angels" until "2099-12-31"

  # H7 — Happy path: a support user starts the stopped machine; the badge says running once the relay answers
  Scenario: Start the machine
    Given the support machine is "stopped"
    And I am logged in as "Meera"
    When I open the machine badge
    Then the machine badge shows "Machine stopped"
    When I click the machine button "support-console-start"
    Then the support machine was sent "start"
    When I open the machine badge
    Then the machine badge shows "Machine running"

  # H8 — Happy path: a support user stops the running machine
  Scenario: Stop the machine
    Given the support machine is "running"
    And I am logged in as "Meera"
    When I open the machine badge
    And I click the machine button "support-console-stop-machine"
    Then the support machine was sent "stop"
    When I open the machine badge
    Then the machine badge shows "Machine stopped"

  # E33 — Edge case: the stop popup says how many answers in progress a stop would cut off
  Scenario: Stop warns about answers in progress
    Given the support machine is "running"
    And "Meera" has a conversation about "Golden Angels" with a turn still running
    And I am logged in as "Meera"
    When I open the machine badge
    Then I should see "1 answer in progress will be cut off"

  # H9 — Happy path: a question asked while the machine is stopped starts it, waits, then is answered
  Scenario: A question starts a stopped machine
    Given the support machine is "stopped"
    And the relay is down until the machine starts, then answers "Started and answered"
    And I am logged in as "Meera"
    When I open the Support Console for "Golden Angels"
    And I ask "Why?"
    Then the support machine was sent "start"
    And I see the answer "Started and answered"
    And the last turn is completed

  # E36 — Edge case: a server error from a running, healthy machine is not treated as a stopped machine
  Scenario: Machine error on a running machine
    Given the support machine is "running"
    And the relay fails with status 500
    And I am logged in as "Meera"
    When I open the Support Console for "Golden Angels"
    And I ask "Why?"
    Then I see the answer "The Support Console is unavailable right now. Try again in a few minutes."
    And the relay was asked 1 time
    And the support machine was not sent anything

  # H10 — Happy path: the footer totals the whole conversation's tokens and approximate cost
  Scenario: Conversation usage
    Given the relay answers with 1000 tokens costing 0.10 and then 2500 tokens costing 0.25
    And I am logged in as "Meera"
    When I open the Support Console for "Golden Angels"
    And I ask "First?"
    And I ask "Second?"
    Then I should see "Conversation: 3.5k tokens · ≈ $0.35"

  # H11 — Happy path: after 15 minutes with no questions the idle check stops the machine
  Scenario: Idle machine is stopped
    Given the support machine is "running", started 2 hours ago
    When the idle check runs
    Then the support machine was sent "stop"

  # E34 — Edge case: the idle check never stops a machine with an answer in progress
  Scenario: Idle check leaves a busy machine running
    Given the support machine is "running", started 2 hours ago
    And "Meera" has a conversation about "Golden Angels" with a turn still running
    When the idle check runs
    Then the support machine was not sent anything

  # E35 — Edge case: idle time counts from the last start, so a machine started 10 minutes ago keeps running
  Scenario: Recently started machine is not idle
    Given the support machine is "running", started 10 minutes ago
    When the idle check runs
    Then the support machine was not sent anything

  # X34 — Error case: a user without the support role cannot start or stop the machine
  Scenario: Non-support user cannot control the machine
    Given the support machine is "stopped"
    And "Asha" works at CapHive
    And I am logged in as "Asha"
    When I post "start" to the machine
    Then I am sent home with "Not authorized."
    And the support machine was not sent anything
