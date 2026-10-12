Feature: Derivatives — OTC swaps
  Interest-rate, cross-currency, total-return and credit-default swaps need a notional, maturity,
  counterparty and agreement; each periodic settlement is recorded as a net amount and does not
  close the swap. Values come from counterparty statements only.
  Worked examples: openspec/changes/fund-market-data/business-rules.md (H17, X26)

  Background:
    Given there is a user "" for an entity "entity_type=Investment Fund;currency=INR"
    And the user has role "company_admin"
    Given these funds exist with rate sources:
      | fund                   | currency | sources |
      | Horizon Evergreen Fund | INR      | manual  |
    And the fund "Horizon Evergreen Fund" has derivatives switched on

  # H17 — Happy path: a pay-fixed IRS on ₹10 Cr settles a quarter (₹2,10,000 paid fixed, ₹1,95,000 received floating) as −₹15,000 and stays open
  Scenario: Interest-rate swap settlement
    Given "Horizon Evergreen Fund" has an agreement document "ISDA Bank X"
    And "Horizon Evergreen Fund" has a swap "IRS MIBOR 10Cr" on "100000000" with the agreement
    Then the contract should be saved
    When the event "type=settlement;date=30 Sep 2026;amount=-15000" is recorded on "IRS MIBOR 10Cr"
    Then the event should be recorded
    And the ledger should have a "Derivative Settlement" entry of "-15000" for "IRS MIBOR 10Cr"
    And the contract "IRS MIBOR 10Cr" should be open

  # X26 — Error case: a swap saved without an agreement document is refused
  Scenario: Swap without agreement
    Given "Horizon Evergreen Fund" has a derivative contract:
      | name              | IRS no ISDA   |
      | contract_type     | irs           |
      | side              | long          |
      | underlying_type   | rate          |
      | underlying_name   | MIBOR         |
      | notional          | 100000000     |
      | trade_date        | 01 Jul 2026   |
      | expiry_date       | 30 Jun 2029   |
      | listed            | false         |
      | counterparty_name | Bank X        |
    Then the contract should be refused with "Agreement can't be blank"
