Feature: FundAssistant currency-aware aggregation
  As a fund manager asking the Fund Assistant for totals across funds
  I want sums of money fields to never silently mix currencies
  So that "what's the total called amount" gives a trustworthy number, not USD cents plus
  EUR cents added together as if they were the same unit

  Background:
    Given there is a user "first_name=FM-Analyst" for an entity "entity_type=Investment Fund;name=Acme FM;currency=INR"
    And the user has the company_admin role

  Scenario: Summing a money field across funds sharing one currency returns a single total with its currency
    Given there is a capital call of 100000 cents in a fund with currency "USD"
    And there is a capital call of 50000 cents in another fund with currency "USD"
    When I sum capital calls by "call_amount"
    Then the sum result should be a single total of 150000 with currency "USD"

  Scenario: Summing a money field across funds with different currencies returns a per-currency breakdown instead of one misleading total
    Given there is a capital call of 100000 cents in a fund with currency "USD"
    And there is a capital call of 50000 cents in another fund with currency "INR"
    When I sum capital calls by "call_amount"
    Then the sum result should report separate totals for "USD" and "INR" instead of one blended number

  # CapitalCommitment has a fund-currency-vs-folio-currency duality that isn't safe to
  # resolve with a single per-model rule (see CURRENCY_GROUPING's comment in
  # fund_assistant_data_manager.rb) -- it's deliberately left out of CURRENCY_GROUPING, and
  # this flag is how the caller finds out that particular total hasn't been currency-checked.
  Scenario: A model without a resolved currency source is flagged, not silently trusted
    Given there is a capital commitment for the entity
    When I sum capital commitments by "committed_amount"
    Then the sum result should be marked as currency_unresolved
