Feature: The compliance assistant's data tools reject what they cannot safely run
  As a fund manager running AI compliance rules
  I want the assistant's data tools to refuse arguments they cannot execute safely
  So that a hallucinated or prompt-injected argument cannot destroy or exfiltrate data

  # AiDataManager's tools take their arguments from an LLM, and three of them reached a sink
  # that executes what it is given:
  #
  #   @record.send(associated_data.underscore.to_sym)  -> any zero-arg method on the record;
  #                                                       `destroy` has arity 0
  #   .where(where)                                    -> raw SQL, verbatim
  #   .sum(sum_field.to_sym)                           -> raw SQL; a subquery here executes
  #                                                       and its value is returned
  #
  # Same class as the `scope` bypass fixed in FundAssistantDataManager and the aggregate
  # field bypass fixed in perform_aggregation: an LLM-supplied string reaching a method that
  # trusts its caller.
  Background:
    Given there is a user "first_name=FM-Analyst" for an entity "entity_type=Investment Fund;name=Acme FM;currency=INR"
    And the user has the company_admin role
    And there is a fund with a capital call for the compliance assistant

  Scenario: associated_data cannot reach a method that is not an association
    When the compliance assistant calls get_data with associated_data "destroy"
    Then the tool response should be an error mentioning "is not an association"
    And the fund should still exist

  Scenario: associated_data cannot reach an arbitrary reader either
    When the compliance assistant calls get_data with associated_data "to_json"
    Then the tool response should be an error mentioning "is not an association"

  Scenario: a where clause cannot carry a subquery
    When the compliance assistant calls get_data on "capital_calls" where "1=1 OR (SELECT count(*) FROM users) > 0"
    Then the tool response should be an error mentioning "may not contain subqueries"

  Scenario: a where clause cannot carry a statement separator
    When the compliance assistant calls get_data on "capital_calls" where "1=1; DROP TABLE users"
    Then the tool response should be an error mentioning "may not contain subqueries"

  Scenario: a where clause cannot reference a column the model does not have
    When the compliance assistant calls get_data on "capital_calls" where "secret_col = 1"
    Then the tool response should be an error mentioning "Unknown column"

  Scenario: sum_field cannot carry raw SQL
    When the compliance assistant calls get_data on "capital_calls" summing "(SELECT max(id) FROM users)"
    Then the tool response should be an error mentioning "is not a column"

  Scenario: order_by cannot carry raw SQL
    When the compliance assistant calls get_latest_data on "capital_calls" ordered by "(SELECT max(id) FROM users)"
    Then the tool response should be an error mentioning "is not a column"

  Scenario: a missing associated_data is reported rather than raising
    When the compliance assistant calls get_data with associated_data ""
    Then the tool response should be an error mentioning "associated_data is required"

  Scenario: a filter cannot reach another table's columns through an association
    # Document declares `approved_by` (a User). Permitting `users.<column>` here made
    # `count: true` a binary oracle over password hashes — an injection reintroduced by
    # being generous about joins, so nothing outside the target model is addressable.
    When the compliance assistant calls get_data on "documents" where "users.encrypted_password like 'x%'"
    Then the tool response should be an error mentioning "Unknown column"

  Scenario: a bare column belonging to another table is rejected, not passed to the database
    When the compliance assistant calls get_data on "documents" where "folio_id = 'X'"
    Then the tool response should be an error mentioning "Unknown column"

  Scenario: an association whose own model has a polymorphic belongs_to still works
    # FundRatio declares a polymorphic `computation_context`. The first version of this
    # guard called .klass on every ransackable association to build its allowlist, which
    # raised ArgumentError for the polymorphic one and killed the rule run.
    When the compliance assistant calls get_data on "fund_ratios" where "name is not null"
    Then the tool response should not be an error

  Scenario: a single-record association rejects collection arguments
    When the compliance assistant calls get_data on "entity" where "name is not null"
    Then the tool response should be an error mentioning "not a collection"

  Scenario: a filter value containing a forbidden word is still allowed
    When the compliance assistant calls get_data on "capital_calls" where "name like '%update%'"
    Then the tool response should not be an error

  Scenario: a SQL function in a filter is still allowed
    # Function names are not columns, so the identifier check has to know them or every
    # rule using one fails with "Unknown column 'lower'".
    When the compliance assistant calls get_data on "capital_calls" where "lower(name) like '%call%'"
    Then the tool response should not be an error

  Scenario: a money field can be summed by its exposed name
    When the compliance assistant calls get_data on "capital_calls" summing "call_amount"
    Then the tool response should not be an error

  Scenario: rows are capped so an association cannot be materialised whole
    When the compliance assistant calls get_data on "capital_calls" for rows
    Then the logged query should be capped

  Scenario: a legitimate association and filter still work
    When the compliance assistant calls get_data on "capital_calls" where "approved is not null"
    Then the tool response should not be an error

  Scenario: a legitimate sum over a real column still works
    When the compliance assistant calls get_data on "capital_calls" summing "call_amount_cents"
    Then the tool response should not be an error
