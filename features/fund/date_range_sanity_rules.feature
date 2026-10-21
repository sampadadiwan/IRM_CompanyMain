Feature: Date range sanity rules
  Valuation, fund ratio, fund ratio run template and allocation run dates must fall within
  past_years before and future_years after today (default 20 / 20, blocker). Each entity can
  widen, relax or switch off the window per rule through a validation rule override.
  Dates are written relative to today (<21 years ago>, <25 years from now>) because the window
  moves with the current date.

  Background:
    Given there is a user "first_name=Test" for an entity "name=RuleTestFirm;entity_type=Investment Fund;currency=INR"
    And the user has role "company_admin"
    And the default validation rules are seeded
    And there is a fund "name=RuleTestFund;currency=INR" for the entity
    And there is an existing portfolio company "investor_name=Acme"
    And there is an investment instrument for the portfolio company "name=Stock;category=Unlisted;sub_category=Equity;sector=Tech"

  # ── Happy path ──────────────────────────────────────────────────────────────

  Scenario: H1: A valuation dated inside the window is accepted
    When the validation rules are evaluated for a Valuation with "valuation_date=<5 years ago>;per_share_value_cents=100000"
    Then the rule "valuation_date_out_of_range" does not fire

  Scenario: H2: Dates exactly on either boundary are accepted
    When the validation rules are evaluated for a Valuation with "valuation_date=<20 years ago>;per_share_value_cents=100000"
    Then the rule "valuation_date_out_of_range" does not fire
    When the validation rules are evaluated for a Valuation with "valuation_date=<20 years from now>;per_share_value_cents=100000"
    Then the rule "valuation_date_out_of_range" does not fire

  Scenario: H4: Widening the window for one entity leaves other entities on the default
    Given there is a validation rule override for "valuation_date_out_of_range" with "param_overrides=past_years:30"
    When the validation rules are evaluated for a Valuation with "valuation_date=<25 years ago>;per_share_value_cents=100000"
    Then the rule "valuation_date_out_of_range" does not fire
    Given I switch to another entity "name=OtherFirm;entity_type=Investment Fund;currency=INR" with a portfolio company
    When the validation rules are evaluated for a Valuation with "valuation_date=<25 years ago>;per_share_value_cents=100000"
    Then the rule "valuation_date_out_of_range" fires as a "blocker"

  # ── Edge cases ──────────────────────────────────────────────────────────────

  Scenario: E1: A blank date is not checked
    When the validation rules are evaluated for an AllocationRun with "start_date=<1 year ago>;end_date="
    Then the rule "allocation_run_date_out_of_range" does not fire

  Scenario: E2: A non-numeric past_years falls back to 20
    Given there is a validation rule override for "valuation_date_out_of_range" with "param_overrides=past_years:abc"
    When the validation rules are evaluated for a Valuation with "valuation_date=<21 years ago>;per_share_value_cents=100000"
    Then the rule "valuation_date_out_of_range" fires as a "blocker"

  @javascript
  Scenario: E3: An entity that downgrades the rule to a warning gets a confirmable warning
    Given there is a validation rule override for "valuation_date_out_of_range" with "severity_override=warning"
    And I am at the login page
    And I fill and submit the login page
    When I visit the new valuation page for the portfolio company
    And I fill the valuation form with date "0224-03-31" and per_share_value "100"
    And I submit the valuation form
    Then the rule validation modal appears
    And the modal shows a warning containing "Valuation date 0224-03-31 must be within 20 years before and 20 years after today."
    And the modal has a "Confirm & Save" button
    When I click "Confirm & Save" in the modal
    Then the valuation is saved successfully

  Scenario: E4: An allocation group run checked for an out-of-range period lists the blocker
    Given there is an allocation run template "name=Quarterly" on the first fund
    And there is an allocation run group "Close" with templates "Quarterly"
    When I run the pre-flight check for "Close" from "<1 year ago>" to "<25 years from now>"
    Then the pre-flight check for "Quarterly" should be "blocked" with a message containing "must be within 20 years before and 20 years after today."

  Scenario: E5: Triggering templates by tag with an out-of-range end date skips every template
    Given there is a template "name=Q3-A;tag=q3" with the first fund for the entity
    And there is a template "name=Q3-B;tag=q3" with the first fund for the entity
    And I am at the login page
    And I fill and submit the login page
    And background jobs are captured instead of run
    When I trigger the fund ratio run templates tagged "q3" with end date "<25 years from now>"
    Then I see "Enqueued 0 ratio calculations for tag 'q3'"
    And no "FundRatioRunTemplateBatchJob" job is enqueued
    And no "FundRatiosScenarioJob" job is enqueued

  # ── Error cases ─────────────────────────────────────────────────────────────

  Scenario: X1: A date too far in the past is blocked and the message names the date and window
    When the validation rules are evaluated for a Valuation with "valuation_date=<21 years ago>;per_share_value_cents=100000"
    Then the rule "valuation_date_out_of_range" fires as a "blocker"
    And the rule message includes the date "Valuation date <21 years ago> must be within 20 years before and 20 years after today."

  Scenario: X2: A fund ratio end date too far in the future is blocked
    When the validation rules are evaluated for a FundRatio with "end_date=<21 years from now>"
    Then the rule "fund_ratio_date_out_of_range" fires as a "blocker"
    And the rule message includes the date "Fund ratio end date <21 years from now> must be within 20 years before and 20 years after today."

  @javascript
  Scenario: X3: The valuation form rejects a mistyped year
    Given I am at the login page
    And I fill and submit the login page
    When I visit the new valuation page for the portfolio company
    And I fill the valuation form with date "0224-03-31" and per_share_value "100"
    And I submit the valuation form
    Then I see "Valuation date 0224-03-31 must be within 20 years before and 20 years after today."
    And no valuation dated "0224-03-31" exists for the portfolio company

  Scenario: X4: A valuation import row with an out-of-range date fails and the other rows import
    When I import valuations
      | Portfolio Company | Instrument | Valuation Date | Valuation | Per Share Value |
      | Acme              | Stock      | 2204-03-31     | 100000    | 100             |
      | Acme              | Stock      | <1 year ago>   | 100000    | 100             |
    Then the import has 1 processed and 1 failed row
    And import row 1 fails with "Valuation date 2204-03-31 must be within 20 years before and 20 years after today."
    And import row 2 succeeds

  Scenario: X8: Generate Fund Ratios with an end date 30 years ago starts no calculation
    Given I am at the login page
    And I fill and submit the login page
    And background jobs are captured instead of run
    When I visit the generate fund ratios page for the fund
    And I fill the fund ratios end date with "<30 years ago>"
    And I submit the fund ratios form
    Then I see the date "Fund ratio end date <30 years ago> must be within 20 years before and 20 years after today."
    And no "FundRatiosJob" job is enqueued

  Scenario: X9: Triggering one template with an out-of-range end date enqueues nothing
    Given there is a template "name=Single;tag=q3" with the first fund for the entity
    And I am at the login page
    And I fill and submit the login page
    And background jobs are captured instead of run
    When I trigger the fund ratio run template "Single" with end date "<25 years from now>"
    Then I see "Cannot enqueue 'Single': Run template end date must be within 20 years before and 20 years after today."
    And no "FundRatiosScenarioJob" job is enqueued

  Scenario: X10: A manual allocation run with a mistyped start year is not created
    Given I am at the login page
    And I fill and submit the login page
    And background jobs are captured instead of run
    When I run allocations for the fund from "0224-01-01" to "<1 year ago>"
    Then I see "Allocation run dates 0224-01-01"
    And I see "must be within 20 years before and 20 years after today."
    And no allocation run is created for the fund
    And no "AccountEntryAllocationJob" job is enqueued
