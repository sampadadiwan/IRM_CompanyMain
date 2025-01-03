Feature: Capital Distributions
  Capital Distributions fees

Scenario Outline: Create a capital distribution
  Given there is a user "<user>" for an entity "<entity>"
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund;currency=INR" for the entity
  Given there is an existing investor "name=Investor 1"
  Given there is a capital commitment of "folio_committed_amount_cents=100000000;folio_currency=INR" for the last investor
  Given there is a capital commitment of "folio_committed_amount_cents=100000000;folio_currency=INR;fund_close=Second Close" for the last investor
  Given there is a AccountEntry for distribution
  When I create a Capital Distribution
  Then it should create Capital Distribution
  Then the amount payment should be shown on Capital Distribution Payment page

  Examples:
    | user             | entity                           |
    | first_name=Test  | name=Urban;entity_type=Investment Fund |
