Feature: Fund writes over the JSON API do what the website does
  A bearer-token caller creates, updates and deletes fund records through the same actions and
  operations as the website forms, and gets JSON answers (201 / 200 / 204 / 422) where the website
  gets redirects. Requests carry the fields the forms post, including the record's entity_id and fund_id.
  Reference: docs/modules/funds/funds_json_api.md

  Background:
    Given there is a user "first_name=Meera" for an entity "name=Acme Capital;entity_type=Investment Fund;enable_funds=true;currency=INR"
    And the user has role "company_admin"
    And there is an existing investor "" with "1" users
    And there is an existing investor "" with "1" users
    And there is a fund "name=Acme Growth Fund I;currency=INR" for the entity
    And the investors are added to the fund
    And there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And there is a capital call "percentage_called=20"
    And another firm "Beta Partners" has a fund with a commitment, a call and a remittance
    And I have an API token

  # H1 — Happy path: a call posted as JSON runs CapitalCallCreate like the form and generates one remittance per commitment
  Scenario: H1 A capital call created by API generates its remittances like the form
    When "me" sends POST "/capital_calls.json" with:
      """
      {"capital_call": {"entity_id": {entity}, "fund_id": {fund}, "name": "API Q2", "percentage_called": 10,
        "call_date": "2026-10-20", "due_date": "2026-11-20", "call_basis": "Percentage of Commitment",
        "fund_closes": ["All"]}}
      """
    Then the API status is 201
    And the API answer at "name" is "API Q2"
    And the capital call "API Q2" has 2 remittances in my firm

  # H3 — Happy path: a payment posted as JSON runs CapitalRemittancePaymentCreate and raises the remittance's collected amount
  Scenario: H3 A remittance payment created by API updates the remittance
    Given I note the collected amount of the remittance
    When "me" sends POST "/capital_remittance_payments.json" with:
      """
      {"capital_remittance_payment": {"entity_id": {entity}, "fund_id": {fund}, "capital_remittance_id": {remittance}, "folio_amount": 1000,
        "payment_date": "2026-10-21", "reference_no": "UTR-1"}}
      """
    Then the API status is 201
    And the remittance's collected amount went up by 1000
    And the last CapitalRemittancePayment belongs to my firm

  # E17 — Edge case: an employee with a create right on the fund adds a payment
  Scenario: E17 An employee with create access adds a payment
    Given "Sam" is an employee of my firm with create access to the fund
    When "Sam" sends POST "/capital_remittance_payments.json" with:
      """
      {"capital_remittance_payment": {"entity_id": {entity}, "fund_id": {fund}, "capital_remittance_id": {remittance}, "folio_amount": 500,
        "payment_date": "2026-10-21"}}
      """
    Then the API status is 201

  # E18 — Edge case: an investor's token cannot create a call on the fund they invest in
  Scenario: E18 An investor cannot create a capital call
    Given "Iris" is an investor user in the fund
    And I note the CapitalCall count
    When "Iris" sends POST "/capital_calls.json" with:
      """
      {"capital_call": {"fund_id": {fund}, "name": "LP call", "percentage_called": 10,
        "call_date": "2026-10-20", "due_date": "2026-11-20", "call_basis": "Percentage of Commitment",
        "fund_closes": ["All"]}}
      """
    Then the API status is 403
    And the CapitalCall count is unchanged

  # H2 — Happy path: a call updated as JSON runs CapitalCallUpdate like the edit form
  Scenario: H2 A capital call updated by API
    When "me" sends PATCH "/capital_calls/{call}.json" with:
      """
      {"capital_call": {"notes": "Updated by script"}}
      """
    Then the API status is 200
    And the API answer at "notes" is "Updated by script"

  # H4 — Happy path: a distribution payment deleted as JSON is gone (204)
  Scenario: H4 A distribution payment deleted by API
    Given there is a capital distribution payment for the fund
    And I remember that distribution payment
    When "me" sends DELETE "/capital_distribution_payments/{distribution_payment}.json"
    Then the API status is 204
    And the CapitalDistributionPayment with id "{distribution_payment}" is gone

  # X13 — Error case: deleting a remittance whose units are allocated is a JSON 422, not a redirect
  Scenario: X13 A remittance with allocated units cannot be deleted by API
    Given the remittance has a payment of 1000 with units allocated
    When "me" sends DELETE "/capital_remittances/{remittance}.json"
    Then the API status is 422
    And the API answer has an error on "base"
    And the CapitalRemittance with id "{remittance}" still exists

  # E16 — Edge case: an open-ended fund created by API answers 201 with the fund, not the website's redirect
  Scenario: E16 An open-ended fund created by API
    Given the entity has evergreen funds switched on
    And the entity has "enable_units" permission
    When "me" sends POST "/funds.json" with:
      """
      {"fund_type": "open_ended", "fund": {"name": "API Evergreen Fund", "unit_types": "A", "currency": "INR"},
       "evergreen_fund_setting": {"redemption_forms": ["units", "amount", "all"],
         "class_terms": [{"unit_type": "A", "initial_price": 10000}]}}
      """
    Then the API status is 201
    And the API answer at "name" is "API Evergreen Fund"

  # X24 — Error case: an open-ended fund with bad dealing dates is a JSON 422, never the HTML wizard
  Scenario: X24 An invalid open-ended fund by API is a JSON 422
    Given the entity has evergreen funds switched on
    And the entity has "enable_units" permission
    When "me" sends POST "/funds.json" with:
      """
      {"fund_type": "open_ended", "fund": {"name": "Bad Dates Fund", "unit_types": "A", "currency": "INR"},
       "evergreen_fund_setting": {"subscription_dates_text": "not-a-date",
         "class_terms": [{"unit_type": "A", "initial_price": 10000}]}}
      """
    Then the API status is 422
    And the API answer is JSON
    And the API answer has an error on "base"
