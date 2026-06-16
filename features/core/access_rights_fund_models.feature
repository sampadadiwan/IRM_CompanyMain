@access_rights_fund_models
Feature: Fund child model access rights

  All fund-pack models delegate model_with_access_rights to their fund.
  Employee access requires a user-level AccessRight on the fund.
  Investor access (where supported) requires an approved InvestorAccess plus an
  investor-level AccessRight on the fund.  Some models add a fund flag gate
  (show_fund_ratios, show_fund_units, show_portfolios) that must also be true.
  ExpressionOfInterest delegates to its InvestmentOpportunity instead of to a Fund.

  Background:
    # entity_type=Investment Fund so entity.is_fund? returns true for scope routing
    Given there is an entity "name=Fund Entity;entity_type=Investment Fund"
    And there is a fund "name=Main Fund" for the entity "name=Fund Entity"
    # entity_type=Investor prevents setup_defaults adding unexpected roles
    And there is an entity "name=Investor Firm;entity_type=Investor"
    And there is an investor "investor_name=Big LP" for the entity "name=Fund Entity" with investor_entity "name=Investor Firm"
    And there is a user "email=employee@example.com" for the entity "name=Fund Entity"
    And the user "employee@example.com" has role "employee"
    And there is a user "email=investor@example.com" for the entity "name=Investor Firm"
    And the user "investor@example.com" has role "investor"
    And there is an approved investor access for "investor@example.com" and investor "Big LP"

  # ---------------------------------------------------------------------------
  # CapitalCall — employee-only (CapitalCallPolicy.show? = permissioned_employee? only)
  # ---------------------------------------------------------------------------

  Scenario: Employee with fund AR can show a capital call
    Given I grant "read" access to the fund for user "employee@example.com"
    And there is a capital call record for the fund
    Then the user "employee@example.com" should be allowed "show" on the record

  Scenario: Employee without fund AR is denied a capital call
    And there is a capital call record for the fund
    Then the user "employee@example.com" should be denied "show" on the record

  Scenario: Investor is denied show on capital call (employee-only model)
    Given I grant "read" access to the fund for investor "Big LP"
    And there is a capital call record for the fund
    Then the user "investor@example.com" should be denied "show" on the record

  # ---------------------------------------------------------------------------
  # CapitalDistribution — employee-only
  # ---------------------------------------------------------------------------

  Scenario: Employee with fund AR can show a capital distribution
    Given I grant "read" access to the fund for user "employee@example.com"
    And there is a capital distribution for the fund
    Then the user "employee@example.com" should be allowed "show" on the record

  Scenario: Employee without fund AR is denied a capital distribution
    And there is a capital distribution for the fund
    Then the user "employee@example.com" should be denied "show" on the record

  Scenario: Investor is denied show on capital distribution (employee-only model)
    Given I grant "read" access to the fund for investor "Big LP"
    And there is a capital distribution for the fund
    Then the user "investor@example.com" should be denied "show" on the record

  # ---------------------------------------------------------------------------
  # FundReport — employee-only
  # ---------------------------------------------------------------------------

  Scenario: Employee with fund AR can show a fund report
    Given I grant "read" access to the fund for user "employee@example.com"
    And there is a fund report for the fund
    Then the user "employee@example.com" should be allowed "show" on the record

  Scenario: Employee without fund AR is denied a fund report
    And there is a fund report for the fund
    Then the user "employee@example.com" should be denied "show" on the record

  Scenario: Investor is denied show on fund report (employee-only model)
    Given I grant "read" access to the fund for investor "Big LP"
    And there is a fund report for the fund
    Then the user "investor@example.com" should be denied "show" on the record

  # ---------------------------------------------------------------------------
  # CapitalRemittance — employee OR investor
  # ---------------------------------------------------------------------------

  Scenario: Employee with fund AR can show a capital remittance
    Given I grant "read" access to the fund for user "employee@example.com"
    And there is a capital remittance for the fund
    Then the user "employee@example.com" should be allowed "show" on the record

  Scenario: Approved investor with fund AR can show a capital remittance
    Given I grant "read" access to the fund for investor "Big LP"
    And there is a capital remittance for the fund
    Then the user "investor@example.com" should be allowed "show" on the record

  Scenario: Investor without fund AR is denied a capital remittance
    # Investor has approved InvestorAccess but no AccessRight on the fund
    And there is a capital remittance for the fund
    Then the user "investor@example.com" should be denied "show" on the record

  Scenario: Employee without fund AR is denied a capital remittance
    And there is a capital remittance for the fund
    Then the user "employee@example.com" should be denied "show" on the record

  # ---------------------------------------------------------------------------
  # CapitalRemittancePayment — employee OR investor
  # ---------------------------------------------------------------------------

  Scenario: Employee with fund AR can show a capital remittance payment
    Given I grant "read" access to the fund for user "employee@example.com"
    And there is a capital remittance payment for the fund
    Then the user "employee@example.com" should be allowed "show" on the record

  Scenario: Approved investor with fund AR can show a capital remittance payment
    Given I grant "read" access to the fund for investor "Big LP"
    And there is a capital remittance payment for the fund
    Then the user "investor@example.com" should be allowed "show" on the record

  Scenario: Investor without fund AR is denied a capital remittance payment
    And there is a capital remittance payment for the fund
    Then the user "investor@example.com" should be denied "show" on the record

  # ---------------------------------------------------------------------------
  # CapitalDistributionPayment — employee OR investor
  # ---------------------------------------------------------------------------

  Scenario: Employee with fund AR can show a capital distribution payment
    Given I grant "read" access to the fund for user "employee@example.com"
    And there is a capital distribution payment for the fund
    Then the user "employee@example.com" should be allowed "show" on the record

  Scenario: Approved investor with fund AR can show a capital distribution payment
    Given I grant "read" access to the fund for investor "Big LP"
    And there is a capital distribution payment for the fund
    Then the user "investor@example.com" should be allowed "show" on the record

  Scenario: Investor without fund AR is denied a capital distribution payment
    And there is a capital distribution payment for the fund
    Then the user "investor@example.com" should be denied "show" on the record

  # ---------------------------------------------------------------------------
  # AccountEntry — employee OR investor; index blocked for investors
  # ---------------------------------------------------------------------------

  Scenario: Employee with fund AR can show an account entry
    Given I grant "read" access to the fund for user "employee@example.com"
    And there is an account entry for the fund
    Then the user "employee@example.com" should be allowed "show" on the record

  Scenario: Approved investor with fund AR can show an account entry
    Given I grant "read" access to the fund for investor "Big LP"
    And there is an account entry for the fund
    Then the user "investor@example.com" should be allowed "show" on the record

  Scenario: Investor without fund AR is denied an account entry
    And there is an account entry for the fund
    Then the user "investor@example.com" should be denied "show" on the record

  Scenario: Investor is denied account entry index (investor curr_role blocks index)
    Given I grant "read" access to the fund for investor "Big LP"
    And there is an account entry for the fund
    Then the user "investor@example.com" should be denied "index" on the record

  # ---------------------------------------------------------------------------
  # CommitmentAdjustment — employee OR investor
  # ---------------------------------------------------------------------------

  Scenario: Employee with fund AR can show a commitment adjustment
    Given I grant "read" access to the fund for user "employee@example.com"
    And there is a commitment adjustment for the fund
    Then the user "employee@example.com" should be allowed "show" on the record

  Scenario: Approved investor with fund AR can show a commitment adjustment
    Given I grant "read" access to the fund for investor "Big LP"
    And there is a commitment adjustment for the fund
    Then the user "investor@example.com" should be allowed "show" on the record

  Scenario: Investor without fund AR is denied a commitment adjustment
    And there is a commitment adjustment for the fund
    Then the user "investor@example.com" should be denied "show" on the record

  # ---------------------------------------------------------------------------
  # PortfolioScenario — employee OR investor
  # ---------------------------------------------------------------------------

  Scenario: Employee with fund AR can show a portfolio scenario
    Given I grant "read" access to the fund for user "employee@example.com"
    And there is a portfolio scenario for the fund
    Then the user "employee@example.com" should be allowed "show" on the record

  Scenario: Approved investor with fund AR can show a portfolio scenario
    Given I grant "read" access to the fund for investor "Big LP"
    And there is a portfolio scenario for the fund
    Then the user "investor@example.com" should be allowed "show" on the record

  Scenario: Investor without fund AR is denied a portfolio scenario
    And there is a portfolio scenario for the fund
    Then the user "investor@example.com" should be denied "show" on the record

  # ---------------------------------------------------------------------------
  # ExcusedInvestor — employee OR investor
  # ---------------------------------------------------------------------------

  Scenario: Employee with fund AR can show an excused investor
    Given I grant "read" access to the fund for user "employee@example.com"
    And there is an excused investor for the fund
    Then the user "employee@example.com" should be allowed "show" on the record

  Scenario: Approved investor with fund AR can show an excused investor
    Given I grant "read" access to the fund for investor "Big LP"
    And there is an excused investor for the fund
    Then the user "investor@example.com" should be allowed "show" on the record

  Scenario: Investor without fund AR is denied an excused investor
    And there is an excused investor for the fund
    Then the user "investor@example.com" should be denied "show" on the record

  # ---------------------------------------------------------------------------
  # FundRatio — employee OR investor when fund.show_fund_ratios is true
  # ---------------------------------------------------------------------------

  Scenario: Employee with fund AR can show a fund ratio regardless of flag
    Given I grant "read" access to the fund for user "employee@example.com"
    And there is a fund ratio for the fund
    Then the user "employee@example.com" should be allowed "show" on the record

  Scenario: Investor with AR and show_fund_ratios true can show a fund ratio
    Given the fund has show_fund_ratios enabled
    And I grant "read" access to the fund for investor "Big LP"
    And there is a fund ratio for the fund
    Then the user "investor@example.com" should be allowed "show" on the record

  Scenario: Investor with AR but show_fund_ratios false is denied a fund ratio
    # show_fund_ratios defaults to false; investor path requires flag to be true
    Given I grant "read" access to the fund for investor "Big LP"
    And there is a fund ratio for the fund
    Then the user "investor@example.com" should be denied "show" on the record

  Scenario: Investor without fund AR is denied a fund ratio even with flag enabled
    Given the fund has show_fund_ratios enabled
    And there is a fund ratio for the fund
    Then the user "investor@example.com" should be denied "show" on the record

  # ---------------------------------------------------------------------------
  # FundUnit — employee OR investor when fund.show_fund_units is true
  # ---------------------------------------------------------------------------

  Scenario: Employee with fund AR can show a fund unit regardless of flag
    Given I grant "read" access to the fund for user "employee@example.com"
    And there is a fund unit for the fund
    Then the user "employee@example.com" should be allowed "show" on the record

  Scenario: Investor with AR and show_fund_units true can show a fund unit
    # show_fund_units defaults to true
    Given I grant "read" access to the fund for investor "Big LP"
    And there is a fund unit for the fund
    Then the user "investor@example.com" should be allowed "show" on the record

  Scenario: Investor with AR but show_fund_units false is denied a fund unit
    Given the fund has show_fund_units disabled
    And I grant "read" access to the fund for investor "Big LP"
    And there is a fund unit for the fund
    Then the user "investor@example.com" should be denied "show" on the record

  Scenario: Investor without fund AR is denied a fund unit even with flag enabled
    # show_fund_units is true by default; access right gate still blocks investor
    And there is a fund unit for the fund
    Then the user "investor@example.com" should be denied "show" on the record

  # ---------------------------------------------------------------------------
  # PortfolioInvestment — employee OR investor when fund.show_portfolios is true
  # ---------------------------------------------------------------------------

  Scenario: Employee with fund AR can show a portfolio investment regardless of flag
    Given I grant "read" access to the fund for user "employee@example.com"
    And there is a portfolio investment record for the fund
    Then the user "employee@example.com" should be allowed "show" on the record

  Scenario: Investor with AR and show_portfolios true can show a portfolio investment
    Given the fund has show_portfolios enabled
    And I grant "read" access to the fund for investor "Big LP"
    And there is a portfolio investment record for the fund
    Then the user "investor@example.com" should be allowed "show" on the record

  Scenario: Investor with AR but show_portfolios false is denied a portfolio investment
    # show_portfolios defaults to false
    Given I grant "read" access to the fund for investor "Big LP"
    And there is a portfolio investment record for the fund
    Then the user "investor@example.com" should be denied "show" on the record

  Scenario: Investor without fund AR is denied a portfolio investment even with flag enabled
    Given the fund has show_portfolios enabled
    And there is a portfolio investment record for the fund
    Then the user "investor@example.com" should be denied "show" on the record

  # ---------------------------------------------------------------------------
  # InvestmentOpportunity — employee OR investor; model_with_access_rights = self
  # ---------------------------------------------------------------------------

  Scenario: Employee with IO AR can show an investment opportunity
    And there is an investment opportunity
    And I grant "read" access to the investment opportunity for user "employee@example.com"
    Then the user "employee@example.com" should be allowed "show" on the record

  Scenario: Employee without IO AR is denied an investment opportunity
    And there is an investment opportunity
    Then the user "employee@example.com" should be denied "show" on the record

  Scenario: Investor with IO AR can show an investment opportunity
    And there is an investment opportunity
    And I grant "read" access to the investment opportunity for investor "Big LP"
    Then the user "investor@example.com" should be allowed "show" on the record

  Scenario: Investor without IO AR is denied an investment opportunity
    And there is an investment opportunity
    Then the user "investor@example.com" should be denied "show" on the record

  Scenario: Investor is denied new on investment opportunity even with IO AR (investor must not create IOs)
    When the entity has enable_inv_opportunities enabled
    And there is an investment opportunity
    And I grant "read" access to the investment opportunity for investor "Big LP"
    Then the user "investor@example.com" should be denied "new, create" on the record

  Scenario: Investor is denied update on investment opportunity even with IO AR
    When the entity has enable_inv_opportunities enabled
    And there is an investment opportunity
    And I grant "read" access to the investment opportunity for investor "Big LP"
    Then the user "investor@example.com" should be denied "update, edit" on the record

  # ---------------------------------------------------------------------------
  # ExpressionOfInterest — employee OR investor OR rm; model_with_access_rights = IO
  # ---------------------------------------------------------------------------

  Scenario: Employee with IO AR can show an expression of interest
    And there is an investment opportunity
    And I grant "read" access to the investment opportunity for user "employee@example.com"
    And there is an expression of interest for the investment opportunity
    Then the user "employee@example.com" should be allowed "show" on the record

  Scenario: Employee without IO AR is denied an expression of interest
    And there is an investment opportunity
    And there is an expression of interest for the investment opportunity
    Then the user "employee@example.com" should be denied "show" on the record

  Scenario: Investor with IO AR can show an expression of interest
    And there is an investment opportunity
    And I grant "read" access to the investment opportunity for investor "Big LP"
    And there is an expression of interest for the investment opportunity
    Then the user "investor@example.com" should be allowed "show" on the record

  Scenario: Investor who submitted an EOI can show it (EOI creation auto-grants IO access)
    # ExpressionOfInterest.after_create_commit :give_access_rights creates an AccessRight
    # on the InvestmentOpportunity for the investor — so submitting an EOI always grants access.
    And there is an investment opportunity
    And there is an expression of interest for the investment opportunity
    Then the user "investor@example.com" should be allowed "show" on the record
