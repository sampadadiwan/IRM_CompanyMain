# Support Console — every lookup is recorded; lookups that saw another client's rows alert super users.
# Worked examples: openspec/changes/archive/2026-10-22-support-console/design.md#worked-examples
@rack_test @support_console @sync-http
Feature: Support Console query record

  Background:
    Given the client "Golden Angels" has support access "on"
    And "Meera" is a support user
    And "Priya" is a super user without the support role
    And "Meera" is mapped to "Golden Angels" until "2099-12-31"
    And I am logged in as "Meera"

  # H5 — Happy path: a lookup that ran is recorded with who asked, the client, the statement, rows and duration, and super users can review it
  Scenario: Lookup recorded
    Given the relay answers "3 Q2 entries, none for Q3" after these lookups:
      | sql                                                                            | outcome | row_count |
      | SELECT name, SUM(amount_cents) FROM account_entries WHERE entity_id = 18 GROUP BY name | ran     | 3         |
    When I open the Support Console for "Golden Angels"
    And I ask "Why is the closing balance zero?"
    Then a support console query is recorded for "Meera" about "Golden Angels" with outcome "ran" and 3 rows
    When I am logged in as "Priya"
    And I open the Support Console query list
    Then I should see "Golden Angels"
    And I should see "ran"

  # E13 — Edge case: a lookup without the client filter was blocked on the machine and is recorded as blocked
  Scenario: Unscoped lookup blocked
    Given the relay answers "Answered after filtering" after these lookups:
      | sql                        | outcome | reason     |
      | SELECT * FROM capital_calls | blocked | add filter |
    When I open the Support Console for "Golden Angels"
    And I ask "Show the capital calls"
    Then a support console query is recorded as "blocked" because "add filter"

  # E14 — Edge case: a lookup naming another client's id was blocked and is recorded so
  Scenario: Other client named
    Given the relay answers "Only Golden Angels" after these lookups:
      | sql                                            | outcome | reason       |
      | SELECT * FROM capital_calls WHERE entity_id = 25 | blocked | other client |
    When I open the Support Console for "Golden Angels"
    And I ask "Compare the calls"
    Then a support console query is recorded as "blocked" because "other client"

  # E15 — Edge case: a lookup that returned another client's rows is flagged and super users are alerted once
  Scenario: Flagged rows
    Given the relay answers "An answer" after these lookups:
      | sql                                     | outcome | row_count | flagged |
      | SELECT * FROM investors WHERE id < 100 | ran     | 99        | yes     |
    When I open the Support Console for "Golden Angels"
    And I ask "List the investors"
    Then the support console query is flagged
    And the super user "Priya" has 1 flagged-lookup alert
    And the support user "Meera" has no flagged-lookup alerts
    When I am logged in as "Priya"
    And I open the flagged Support Console queries
    Then I should see "Golden Angels"

  # E16 — Edge case: a non-SELECT statement was blocked and is recorded so
  Scenario: Non-SELECT blocked
    Given the relay answers "I cannot change data" after these lookups:
      | sql                                | outcome | reason      |
      | UPDATE capital_calls SET amount = 0 | blocked | SELECT only |
    When I open the Support Console for "Golden Angels"
    And I ask "Zero the call"
    Then a support console query is recorded as "blocked" because "SELECT only"

  # E17 — Edge case: a capped result records the full total row count
  Scenario: Large result
    Given the relay answers "Aggregated instead" after these lookups:
      | sql                                                 | outcome | row_count |
      | SELECT * FROM account_entries WHERE entity_id = 18 | ran     | 5312      |
    When I open the Support Console for "Golden Angels"
    And I ask "List every account entry"
    Then a support console query is recorded for "Meera" about "Golden Angels" with outcome "ran" and 5312 rows

  # E19 — Edge case: a lookup that timed out is recorded as failed
  Scenario: Slow lookup
    Given the relay answers "Used a narrower lookup" after these lookups:
      | sql                                       | outcome | reason            |
      | SELECT * FROM account_entries a JOIN account_entries b | failed  | query timed out |
    When I open the Support Console for "Golden Angels"
    And I ask "Why so slow?"
    Then a support console query is recorded as "failed" because "query timed out"

  # X10 — Error case: an "OR 1=1" lookup that slipped past the hook is flagged from its rows and super users are alerted
  Scenario: Filter bypass is flagged
    Given the relay answers "An answer" after these lookups:
      | sql                                                   | outcome | row_count | flagged |
      | SELECT * FROM capital_calls WHERE entity_id = 18 OR 1=1 | ran     | 40        | yes     |
    When I open the Support Console for "Golden Angels"
    And I ask "Show the calls"
    Then the support console query is flagged
    And the super user "Priya" has 1 flagged-lookup alert

  # X14 — Error case: the same lookup event recorded again adds no row and no second alert
  Scenario: No duplicate record or alert
    Given the relay answers "An answer" after these lookups:
      | sql                                     | outcome | row_count | flagged |
      | SELECT * FROM investors WHERE id < 100 | ran     | 99        | yes     |
    When I open the Support Console for "Golden Angels"
    And I ask "List the investors"
    And the same lookup event is recorded again
    Then nothing new is recorded
    And 1 support console query is recorded
    And the super user "Priya" has 1 flagged-lookup alert

  # X23 — Edge case: a follow-up by another support user is recorded, and labelled, as that user's
  Scenario: Follow-up by another support user
    Given "Ravi" is a support user
    And "Ravi" is mapped to "Golden Angels" until "2099-12-31"
    And "Meera" has a conversation about "Golden Angels" with a finished answer
    And the relay answers "Q4 has 2 entries" after these lookups:
      | sql                                                                 | outcome | row_count |
      | SELECT name FROM account_entries WHERE entity_id = 18 AND quarter = 4 | ran     | 2         |
    When I am logged in as "Ravi"
    And I open that conversation
    And I ask "And for Q4?"
    Then a support console query is recorded for "Ravi" about "Golden Angels" with outcome "ran" and 2 rows
    And the question "And for Q4?" is labelled with "Ravi"
