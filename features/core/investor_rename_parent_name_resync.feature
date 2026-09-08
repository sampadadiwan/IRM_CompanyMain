Feature: AccountEntry parent_name resync on investor rename

  AccountEntry#parent_name is a denormalized snapshot of parent.to_s, written once at
  creation (AccountEntryShared#setup_defaults) and never re-derived afterwards. Renaming
  an investor therefore has to rewrite it for every account entry hanging off that
  investor directly, and off each of its AggregatePortfolioInvestment / PortfolioInvestment
  rows -- their #to_s embeds portfolio_company_name.

  account_entries is one of the largest tables in production, and doing that resync as a
  single unbounded UPDATE locked enough rows to exceed InnoDB's lock table
  ("Mysql2::Error: The total number of locks exceeds the lock table size"). It is now
  batched at UpdateInvestor::RESYNC_BATCH_SIZE rows per statement, for every parent type.

  These scenarios pin the statement count as well as the resulting values: a
  correctness-only assertion passes just as happily against the unbounded single-statement
  version, so it would not catch a regression that dropped the batching.

  Background:
    Given there is an entity "name=Fund Entity;entity_type=Investment Fund"
    And there is a fund "name=Growth Fund" for the entity "name=Fund Entity"
    And there is an investor "investor_name=LP Alpha;category=LP" for the entity "name=Fund Entity" with investor_entity "name=Investor Firm"

  Scenario: Directly-parented account entries are resynced across several batches
    Given the account entry resync batch size is 2
    And there are 5 account entries parented on the investor "LP Alpha"
    When I rename the investor "LP Alpha" to "LP Alpha Renamed"
    Then the account entries parented on the investor "LP Alpha Renamed" should have parent name "LP Alpha Renamed : LP"
    And 3 account entry update statements should have been issued

  Scenario: The resync is scoped to the renamed investor
    Given there is an investor "investor_name=LP Beta;category=LP" for the entity "name=Fund Entity" with investor_entity "name=Other Firm"
    And there are 2 account entries parented on the investor "LP Beta"
    And there are 2 account entries parented on the investor "LP Alpha"
    When I rename the investor "LP Alpha" to "LP Alpha Renamed"
    Then the account entries parented on the investor "LP Beta" should have parent name "LP Beta : LP"

  Scenario: Entries parented on the investor's portfolio investments are resynced, also in batches
    Given there is a portfolio investment for the investor "LP Alpha" in the fund "Growth Fund"
    And the account entry resync batch size is 2
    And there are 3 account entries parented on the aggregate portfolio investment
    And there are 3 account entries parented on the portfolio investment
    When I rename the investor "LP Alpha" to "LP Alpha Renamed"
    Then every account entry parent name should match its parent
    And 4 account entry update statements should have been issued
