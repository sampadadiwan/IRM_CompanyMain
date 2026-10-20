# Support Console — conversations are kept for 90 days after their last message.
# Worked examples: openspec/changes/support-console/design.md#worked-examples
@rack_test @support_console @sync-http
Feature: Support Console retention

  Background:
    Given the client "Golden Angels" has support access "on"
    And "Meera" is a support user
    And "Meera" is mapped to "Golden Angels" until "2099-12-31"

  # E20 — Edge case: at 91 days the conversation and its transcript go and its query record stays; at 90 days it is kept
  Scenario: 90-day retention
    Given "Meera" has a conversation about "Golden Angels" last active 91 days ago with Claude session "cs-old"
    And "Meera" has a conversation about "Golden Angels" last active 90 days ago with Claude session "cs-keep"
    When the Support Console retention runs
    Then the conversation with "Question 91 days ago" is gone
    And the machine was asked to delete transcript "cs-old"
    And the conversation with "Question 90 days ago" is kept
    And the machine was not asked to delete transcript "cs-keep"
    And 2 support console queries remain, 1 of them detached from any conversation

  # E23 — Edge case: a turn left running by a restart is closed so the conversation can be used again
  Scenario: Interrupted turn is closed
    Given a turn about "Golden Angels" has been running for 21 minutes
    When the Support Console retention runs
    Then that turn is closed with "The answer was interrupted. Please ask again."

  # E28 — Edge case: with the relay gone, a conversation past 90 + 7 days is deleted anyway and the leftover transcript reported
  Scenario: Relay gone, grace period over
    Given "Meera" has a conversation about "Golden Angels" last active 98 days ago with Claude session "cs-orphan"
    And "Meera" has a conversation about "Golden Angels" last active 92 days ago with Claude session "cs-wait"
    And the relay cannot delete transcripts
    When the Support Console retention runs
    Then the conversation with "Question 98 days ago" is gone
    And the conversation with "Question 92 days ago" is kept
