Feature: Fund JSON API — error answers
  Error answers stay exactly as existing clients know them: 422 = the record's errors,
  403 = {"error": "Access Denied"} (also for a missing record), 400 = Rails' own answer. What
  changes is only where an answer used to be a server error or a redirect.
  Reference: docs/modules/funds/funds_json_api.md

  Background:
    Given there is a user "first_name=Meera" for an entity "name=Acme Capital;entity_type=Investment Fund;enable_funds=true;currency=INR"
    And the user has role "company_admin"
    And there is an existing investor "" with "1" users
    And there is a fund "name=Acme Growth Fund I;currency=INR" for the entity
    And the investors are added to the fund
    And there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And there is a capital call "percentage_called=20"
    And another firm "Beta Partners" has a fund with a commitment, a call and a remittance
    And I have an API token

  # X8 — Error case: a capital call create without its request object is Rails' 400 like every other endpoint (was a 500)
  Scenario: X8 A request without its object is a 400
    When "me" sends POST "/capital_calls.json" without the request object
    Then Rails answers it as a bad request (400), not a server error

  # X9 — Error case: a validation failure answers 422 with the record's errors, exactly as before
  Scenario: X9 A validation failure keeps today's 422 body
    When "me" sends POST "/capital_calls.json" with:
      """
      {"capital_call": {"entity_id": {entity}, "fund_id": {fund}, "name": "No due date", "percentage_called": 10,
        "call_date": "2026-10-20", "call_basis": "Percentage of Commitment", "fund_closes": ["All"]}}
      """
    Then the API status is 422
    And the API answer has an error on "due_date"

  # X10 — Error case: an id that doesn't exist keeps today's answer — 403 Access Denied (unchanged for existing clients)
  Scenario: X10 A missing record keeps today's 403
    When "me" sends GET "/capital_calls/999999999.json"
    Then the API status is 403
    And the API answer at "error" is "Access Denied"

  # X11 — Error case: another firm's record is refused with today's 403 body
  Scenario: X11 Another firm's record keeps today's 403
    When "me" sends GET "/capital_calls/{beta_call}.json"
    Then the API status is 403
    And the API answer at "error" is "Access Denied"

  # X12 — Error case: the website's answer to another firm's record is unchanged (redirect + Access Denied)
  @rack_test
  Scenario: X12 The website still shows Access Denied
    Given I am signed in as the current user
    When I open "/capital_calls/{beta_call}" in the browser
    Then I should see "Access Denied"

  # X14 — Error case: deleting a payment whose units are allocated is refused with a 422, as before
  Scenario: X14 A payment with allocated units cannot be deleted
    Given the remittance has a payment of 1000 with units allocated
    When "me" sends DELETE "/capital_remittance_payments/{payment}.json"
    Then the API status is 422
    And the CapitalRemittancePayment with id "{payment}" still exists
