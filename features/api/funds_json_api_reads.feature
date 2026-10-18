Feature: Fund JSON API — reads: currency, fund summary, commitment statement
  Amounts say which currency they are in; the fund summary returns the overview's figures; a
  folio's statement returns its calls, payments, distributions and ledger totals in one answer.
  Access is the same as the matching page. Existing fields are unchanged.
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
    And I have an API token

  # H8 — Happy path: the summary returns the overview's committed / called / collected / due figures and counts
  Scenario: H8 The fund summary matches the overview
    Given folio 1 pays its remittance in full
    When "me" sends GET "/funds/{fund}/summary.json"
    Then the API status is 200
    And the API answer at "currency" is "INR"
    And the API answer matches the fund's own committed, called, collected and due amounts
    And the API answer at "capital_commitments_count" is "2"
    And the API answer at "capital_calls_count" is "1"

  # E19 — Edge case: a fund that tracks in another currency returns the tracking figures too
  Scenario: E19 The summary carries the tracking currency figures
    Given my fund tracks in "USD"
    When "me" sends GET "/funds/{fund}/summary.json"
    Then the API status is 200
    And the API answer at "tracking_currency" is "USD"
    And the API answer at "tracking_committed_amount" is present

  # X23 — Error case: an employee without access to the fund cannot read its summary
  Scenario: X23 The summary needs access to the fund
    Given "Nina" is an employee of my firm with no fund access
    When "Nina" sends GET "/funds/{fund}/summary.json"
    Then the API status is 403

  # H9 — Happy path: an investor reads their own folio's statement — one call fully paid, due 0
  Scenario: H9 An investor reads their own statement
    Given folio 1 pays its remittance in full
    And "Iris" is the investor user of folio 1
    When "Iris" sends GET "/capital_commitments/{folio1}/statement.json"
    Then the API status is 200
    And the API answer at "remittances.0.due_amount" is "0.0"
    And the API answer at "remittance_payments.0.capital_remittance_id" is present
    And the API answer at "currency" is "INR"

  # E12 — Edge case: a folio with nothing paid, distributed or booked has empty lists and zero totals
  Scenario: E12 A statement with no activity
    Given "Iris" is the investor user of folio 2
    When "Iris" sends GET "/capital_commitments/{folio2}/statement.json"
    Then the API status is 200
    And the API answer at "remittance_payments" is "[]"
    And the API answer at "distribution_payments" is "[]"
    And the API answer at "ledger_totals" is "{}"

  # E13 — Edge case: the ledger comes back as totals per entry type, not as entries
  Scenario: E13 The statement returns ledger totals
    Given folio 1 has account entries of "NAV:1000,NAV:500,Fee:200"
    When "me" sends GET "/capital_commitments/{commitment}/statement.json"
    Then the API status is 200
    And the API answer at "ledger_totals.NAV" is "1500.0"
    And the API answer at "ledger_totals.Fee" is "200.0"

  # X22 — Error case: an investor cannot read another investor's folio statement
  Scenario: X22 An investor cannot read another folio's statement
    Given "Iris" is the investor user of folio 1
    And I remember folio 2
    When "Iris" sends GET "/capital_commitments/{folio2}/statement.json"
    Then the API status is 403

  # H13 — Happy path: a capital call says which currency its amounts are in
  Scenario: H13 A capital call carries its currency
    When "me" sends GET "/capital_calls/{call}.json"
    Then the API status is 200
    And the API answer at "currency" is "INR"

  # H14 — Happy path: the commitment answer keeps the fields the website's grid renders
  Scenario: H14 The commitment answer keeps the grid fields
    When "me" sends GET "/capital_commitments/{commitment}.json"
    Then the API status is 200
    And the API answer has the keys "investor_kyc, investor, dt_actions, investor_link, folio_link"

  # H19 — Happy path: every fund list endpoint answers 200 with a JSON array (smoke: three list views were 500s)
  Scenario: H19 Every fund list answers JSON
    Given there is a capital distribution payment for the fund
    And folio 1 has account entries of "NAV:1000"
    Then every fund list answers 200 with JSON for "me"
