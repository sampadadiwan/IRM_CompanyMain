Feature: Date range sanity rule for portfolio investments
  A new or changed portfolio investment date must fall within past_years before and future_years
  after today (default 20 / 20, blocker). PortfolioInvestmentCreate checks the rule before it sets
  up the aggregate or creates the valuation, so a rejected create leaves nothing behind. Editing
  other fields of a legacy investment whose stored date is out of range is still allowed.

  Background:
    Given there is a user "first_name=Test" for an entity "name=RuleTestFirm;entity_type=Investment Fund;currency=INR"
    And the user has role "company_admin"
    And the default validation rules are seeded
    And there is a fund "name=RuleTestFund;currency=INR" for the entity
    And there is an existing portfolio company "investor_name=Acme"
    And there is an investment instrument for the portfolio company "name=Stock;category=Unlisted;sub_category=Equity;sector=Tech;currency=INR"

  # ── Happy path ──────────────────────────────────────────────────────────────

  Scenario: H5: An entity that disables the rules can save a portfolio investment dated 50 years ago
    # Creating a buy also creates a valuation on the investment date, so both rules must be off
    Given there is a validation rule override for "portfolio_investment_date_out_of_range" with "enabled=false"
    And there is a validation rule override for "valuation_date_out_of_range" with "enabled=false"
    When I create a portfolio investment dated "<50 years ago>"
    Then the portfolio investment is saved

  Scenario: H6: A legacy portfolio investment stays editable while its date is unchanged
    Given there is a legacy portfolio investment dated "<25 years ago>"
    When I update the portfolio investment "notes" to "Corrected the notes only"
    Then the portfolio investment is saved

  # ── Error cases ─────────────────────────────────────────────────────────────

  Scenario: X5: Creating a portfolio investment dated 21 years from now fails before any side effects
    When I create a portfolio investment dated "<21 years from now>"
    Then the portfolio investment is rejected with "Investment date <21 years from now> must be within 20 years before and 20 years after today."
    And no aggregate portfolio investment or valuation is created

  Scenario: X6: A portfolio investment import row with an out-of-range date fails
    # Portfolio investment imports stop at the first failed row (fail fast), so the valid row comes first
    When I import portfolio investments
      | Fund         | Portfolio Company Name | Investment Date | Amount (Excluding Expenses) | Quantity | Instrument | Currency | Investment Domicile | Notes | Excused Folio Ids | Proforma |
      | RuleTestFund | Acme                   | <1 year ago>    | 100000                      | 100      | Stock      | INR      | Domestic            |       |                   | No       |
      | RuleTestFund | Acme                   | 0224-01-15      | 100000                      | 100      | Stock      | INR      | Domestic            |       |                   | No       |
    Then the import has 1 processed and 1 failed row
    And import row 1 succeeds
    And import row 2 fails with "Investment date 0224-01-15 must be within 20 years before and 20 years after today."

  Scenario: X12: Disabling only the portfolio investment rule still applies the valuation rule to a buy
    Given there is a validation rule override for "portfolio_investment_date_out_of_range" with "enabled=false"
    When I create a portfolio investment dated "<50 years ago>"
    Then the portfolio investment create fails with "Valuation date <50 years ago> must be within 20 years before and 20 years after today."

  Scenario: X7: Changing a portfolio investment's date to 25 years ago is rejected
    Given there is a portfolio investment dated "<10 years ago>"
    When I update the portfolio investment "investment_date" to "<25 years ago>"
    Then the portfolio investment is rejected with "Investment date <25 years ago> must be within 20 years before and 20 years after today."
