@rack_test
Feature: Compute Hurdle
  Capital commitment preferred return (hurdle) is calculated from
  remittance payments and optionally reduced by distributions.

  Background:
    Given Im logged in as a user "first_name=Hurdle" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is a fund "name=Hurdle Fund;currency=INR;unit_types=Class A" for the entity
    Given there is an existing investor "name=Hurdle Investor"
    Given there is a capital commitment of "orig_folio_committed_amount_cents=10000000;folio_currency=INR;unit_type=Class A" for the last investor
    Given the fund unit setting "Class A" has a hurdle rate of "0.10"

  Scenario: Computes hurdle on remittance contributions using base currency
    Given there is a hurdle remittance payment of "amount_cents=36500000;payment_date=2023-01-01" for the commitment
    Then the compute_hurdle for the commitment as of "2023-12-31" should equal "3639517" cents

  Scenario: Distributions reduce the hurdle amount
    Given there is a hurdle remittance payment of "amount_cents=36500000;payment_date=2023-01-01" for the commitment
    And there is a hurdle distribution payment of "gross_payable_cents=18250000;payment_date=2023-01-01" for the commitment
    Then the compute_hurdle with use_distributions for the commitment as of "2023-12-31" should equal "1819759" cents

  Scenario: Computes hurdle using tracking currency amounts
    Given there is a hurdle remittance payment of "amount_cents=36500000;tracking_amount_cents=73000000;payment_date=2023-01-01" for the commitment
    Then the compute_hurdle with use_tracking_currency for the commitment as of "2023-12-31" should equal "7279034" cents

  Scenario: Tracking currency with distributions reduces the hurdle
    Given there is a hurdle remittance payment of "amount_cents=36500000;tracking_amount_cents=73000000;payment_date=2023-01-01" for the commitment
    And there is a hurdle distribution payment of "gross_payable_cents=18250000;tracking_gross_payable_cents=36500000;payment_date=2023-01-01" for the commitment
    Then the compute_hurdle with use_tracking_currency and use_distributions for the commitment as of "2023-12-31" should equal "3639517" cents
