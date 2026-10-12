@rack_test
Feature: Investor notice audience is scoped by owner
  As a GP publishing an investor notice from a Fund's or SecondarySale's page
  I want InvestorNoticeJob to generate entries only for investors who actually
  have access to that owner
  So that a fund-specific notice doesn't leak to every investor of the GP,
  and an entity-wide notice still reaches everyone

  Background:
    Given there is an entity "name=Scoping GP;entity_type=Investment Fund;enable_funds=true"
    Given there is a fund "name=Scoping Fund" for the entity "name=Scoping GP"
    Given there is an investor "investor_name=Fund Investor" for the entity "name=Scoping GP" with investor_entity "name=Fund Investor Co"
    Given there is an investor "investor_name=Outside Investor" for the entity "name=Scoping GP" with investor_entity "name=Outside Investor Co"

  # ── Scenario 1 ──────────────────────────────────────────────────────────────
  # Only "Fund Investor" has an AccessRight on the fund; "Outside Investor" is
  # part of the same GP but was never granted access to this fund.
  Scenario: Fund-owned notice only generates entries for investors granted access to that fund
    Given I grant "read" access to the fund for investor "Fund Investor"
    And there is an investor notice titled "Fund Update" owned by the fund with generate enabled
    When the investor notice job runs for "Fund Update"
    Then the investor notice "Fund Update" should have an entry for "Fund Investor"
    And the investor notice "Fund Update" should not have an entry for "Outside Investor"

  # ── Scenario 2 ──────────────────────────────────────────────────────────────
  # No owner at all — every investor of the GP is the audience, regardless of
  # per-fund AccessRights.
  Scenario: Entity-wide notice generates entries for every investor of the GP
    Given there is an entity-wide investor notice titled "Company Update" with generate enabled
    When the investor notice job runs for "Company Update"
    Then the investor notice "Company Update" should have an entry for "Fund Investor"
    And the investor notice "Company Update" should have an entry for "Outside Investor"

  # ── Scenario 3 ──────────────────────────────────────────────────────────────
  # A notice created before "Fund Investor" was granted access still picks
  # them up once InvestorAddedJob re-checks on investor-added, but must NOT
  # pick up "Outside Investor" who was never granted access to the fund.
  Scenario: Newly added investor only regenerates fund-owned notices they have access to
    Given there is an investor notice titled "Early Notice" owned by the fund with generate enabled
    And I grant "read" access to the fund for investor "Fund Investor"
    When a new investor "Fund Investor" is added to the entity
    Then the investor notice "Early Notice" should have an entry for "Fund Investor"
    And the investor notice "Early Notice" should not have an entry for "Outside Investor"

  # ── Scenario 4 ──────────────────────────────────────────────────────────────
  # The daily expiry sweep deactivates ended notices in bulk (no per-record
  # callbacks) and InvestorNotice.notices stops returning them.
  Scenario: Ended notices are deactivated by the daily expiry sweep
    Given there is an entity-wide investor notice titled "Ended Notice" with generate enabled
    And the investor notice "Ended Notice" ended yesterday
    When the investor notice expiry job runs
    Then the investor notice "Ended Notice" should be inactive
