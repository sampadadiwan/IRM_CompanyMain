Feature: Fund JSON API — lists page and say how big they are
  For bearer-token callers every paged fund list adds size headers (total-count, total-pages,
  current-page, page-limit, link). Rows are exactly what they were before: per_page and `all` are not
  capped, the body stays a plain JSON array, and website requests are unchanged.
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
    And there are 5 more capital calls on my fund
    And I have an API token

  # H5 — Happy path: 12 remittances read 5 at a time — 5 rows, total-count 12, total-pages 3, a next link
  Scenario: H5 Paging through remittances
    When "me" sends GET "/capital_remittances.json?fund_id={fund}&per_page=5"
    Then the API status is 200
    And the API answer is a list of 5 rows
    And the API header "total-count" is "12"
    And the API header "total-pages" is "3"
    And the API header "link" mentions "rel=\"next\""

  # E6 — Edge case: a page past the end is an empty list with the real total, not a server error
  Scenario: E6 A page past the end is empty
    When "me" sends GET "/capital_remittances.json?fund_id={fund}&per_page=5&page=9"
    Then the API status is 200
    And the API answer is a list of 0 rows
    And the API header "total-count" is "12"

  # H6 — Happy path: the funds list pages for an API caller and returns fund JSON
  Scenario: H6 The funds list is paged
    When "me" sends GET "/funds.json"
    Then the API status is 200
    And the API answer is a list of 1 row
    And the API header "total-count" is "1"
    And the API answer at "0.name" is "Acme Growth Fund I"

  # H7 — Happy path: the distributions list pages for an API caller
  Scenario: H7 The distributions list is paged
    Given there is a capital distribution payment for the fund
    When "me" sends GET "/capital_distributions.json?fund_id={fund}"
    Then the API status is 200
    And the API header "total-count" is "1"

  # H15 — Happy path: the LP app's per-folio all=true still returns every remittance of the folio
  Scenario: H15 The mobile app's per-folio list is whole
    When "me" sends GET "/capital_remittances.json?capital_commitment_id={commitment}&all=true"
    Then the API status is 200
    And the API answer is a list of 6 rows

  # E3 — Edge case: `all` for one folio returns every row of it, as before
  Scenario: E3 All rows of one folio
    When "me" sends GET "/capital_remittances.json?capital_commitment_id={commitment}&all=1"
    Then the API status is 200
    And the API answer is a list of 6 rows

  # X15 — Error case (compatibility): `all` on a whole fund still returns every row — no cap, no 422, as before
  Scenario: X15 All rows of a fund are not capped
    When "me" sends GET "/capital_remittances.json?fund_id={fund}&all=1"
    Then the API status is 200
    And the API answer is a list of 12 rows
    # The whole-ledger branch of account entries (no folio filter) also behaves exactly as before
    Given folio 1 has account entries of "NAV:1,NAV:2,NAV:3,NAV:4,NAV:5,NAV:6,NAV:7"
    When "me" sends GET "/account_entries.json?fund_id={fund}&all=1"
    Then the API status is 200
    And the API answer is a list of 7 rows

  # E7 — Edge case: the website's own all=1 is unchanged
  @rack_test
  Scenario: E7 The website's all is unaffected
    Given I am signed in as the current user
    When the website reads "/capital_remittances.json?fund_id={fund}&all=1&jbuilder=true"
    Then the website gets a list of 12 rows

  # E4 — Edge case: a large per_page is honoured as before (the app's own 1,000 limit still applies)
  Scenario: E4 A large per_page is not clamped
    When "me" sends GET "/capital_remittances.json?fund_id={fund}&per_page=500"
    Then the API status is 200
    And the API answer is a list of 12 rows

  # E5 — Edge case: per_page zero or negative falls back to the default page size (10)
  Scenario: E5 per_page zero or negative
    When "me" sends GET "/capital_remittances.json?fund_id={fund}&per_page=0"
    Then the API answer is a list of 10 rows
    When "me" sends GET "/capital_remittances.json?fund_id={fund}&per_page=-5"
    Then the API answer is a list of 10 rows

  # E8 — Edge case: the website's fund Distributions tab still lists every distribution, unpaged
  @rack_test
  Scenario: E8 The website's distributions list is unchanged
    Given there is a capital distribution payment for the fund
    And I am signed in as the current user
    When the website reads "/capital_distributions.json?fund_id={fund}"
    Then the website gets a list of 1 row

  # H16 — Happy path: each payment in the list names its folio (read through the payment's own commitment association)
  Scenario: H16 Payments list their folio
    Given the remittances are paid
    When "me" sends GET "/capital_remittance_payments.json?fund_id={fund}&all=true"
    Then the API status is 200
    And the API answer is a list of 2 rows
    And every payment in the API answer names a folio of my fund

  # E9 — Edge case: more payments must not mean more queries (Demo Fund 2: 4,109 payments ran ~8,200 queries, 23 s → 2 s)
  Scenario: E9 The payments list does not query once per row
    Given the remittances are paid
    When I count the SQL queries for "/capital_remittance_payments.json?fund_id={fund}&all=true"
    And every remittance of my fund is paid
    And I count the SQL queries again for "/capital_remittance_payments.json?fund_id={fund}&all=true"
    Then the API answer is a list of 12 rows
    And the second query count is the same as the first
