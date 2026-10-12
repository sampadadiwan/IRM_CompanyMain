Feature: Master Fund Portfolio Access
  As an investor with access to a feeder fund
  I want to see the master fund's portfolio investments
  So that I can view the full investment picture without needing separate access rights on the master fund

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing portfolio company "name=AcmeCorp;category=Portfolio Company"
    Given there is an investment instrument for the portfolio company "name=Common Stock;category=Unlisted;sub_category=Equity;sector=Tech"

  # ---------------------------------------------------------------------------
  # SCENARIO 1: Investor sees master fund PIs via feeder fund access
  # ---------------------------------------------------------------------------
  @rack_test
  Scenario: Investor with feeder fund access sees master fund PIs when show_portfolios is true
    Given there is a fund "name=Master Growth Fund;show_portfolios=true" for the entity
    And the current fund is the master fund
    And there are "2" portfolio investments "quantity=200"
    And there is a fund "name=Feeder Fund I" for the entity
    And the current fund is a feeder of the master fund

    # Grant the investor access to the FEEDER fund only (not the master fund)
    And there is an existing investor entity "entity_type=Family Office" with employee "first_name=Investor"
    And another user is "yes" investor access to the fund
    And the user has curr role "investor"
    And I log out
    And I am signed in as the current user

    When I view the master fund's portfolio investments
    Then I should see "AcmeCorp"

  # ---------------------------------------------------------------------------
  # SCENARIO 2: Investor blocked when master fund show_portfolios is false
  # ---------------------------------------------------------------------------
  Scenario: Investor with feeder fund access cannot see master fund PIs when show_portfolios is false
    Given there is a fund "name=Master Growth Fund;show_portfolios=false" for the entity
    And the current fund is the master fund
    And there are "2" portfolio investments "quantity=200"
    And there is a fund "name=Feeder Fund I" for the entity
    And the current fund is a feeder of the master fund

    # Grant the investor access to the FEEDER fund only
    And there is an existing investor entity "entity_type=Family Office" with employee "first_name=Investor"
    And another user is "yes" investor access to the fund
    And the user has curr role "investor"
    And I log out
    And I am signed in as the current user

    When I view the master fund's portfolio investments
    Then I should not see "AcmeCorp"

  # ---------------------------------------------------------------------------
  # SCENARIO 3: Employee always sees master fund PIs (baseline)
  # ---------------------------------------------------------------------------
  @rack_test
  Scenario: Employee sees master fund PIs directly (existing behavior unchanged)
    Given there is a fund "name=Master Growth Fund;show_portfolios=true" for the entity
    And the current fund is the master fund
    And there are "2" portfolio investments "quantity=200"
    And there is a fund "name=Feeder Fund I" for the entity
    And the current fund is a feeder of the master fund

    # Employee/company_admin role (set in Background) — no special access setup needed
    When I view the master fund's portfolio investments
    Then I should see "AcmeCorp"

  # ---------------------------------------------------------------------------
  # SCENARIO 4: Investor without any access sees nothing (security baseline)
  # ---------------------------------------------------------------------------
  Scenario: Investor without any fund access cannot see master fund PIs
    Given there is a fund "name=Master Growth Fund;show_portfolios=true" for the entity
    And the current fund is the master fund
    And there are "2" portfolio investments "quantity=200"
    And there is a fund "name=Feeder Fund I" for the entity
    And the current fund is a feeder of the master fund

    # Investor exists but was NOT granted access (given = "no")
    And there is an existing investor entity "entity_type=Family Office" with employee "first_name=Investor"
    And another user is "no" investor access to the fund
    And the user has curr role "investor"
    And I log out
    And I am signed in as the current user

    When I view the master fund's portfolio investments
    Then I should not see "AcmeCorp"
