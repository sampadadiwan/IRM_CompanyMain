Feature: Validation Rule Engine
  Rules fire warnings and blockers on Valuation, AllocationRun, and FundRatio records.
  Company admins can view all rules and customise them per entity via overrides.
  Rules are disabled by default; an entity opts in by creating enabled overrides.

  Background:
    Given there is a user "first_name=Test" for an entity "name=RuleTestFirm;entity_type=Investment Fund;currency=INR"
    And the user has role "company_admin"
    And the default validation rules are seeded

  # ── Valuation rules ─────────────────────────────────────────────────────────

  Scenario: Valuation date not on a quarter-end fires a warning
    Given there is an existing portfolio company ""
    And there is an investment instrument for the portfolio company "name=Stock;category=Unlisted;sub_category=Equity;sector=Tech"
    And the entity has opted in to all validation rules
    When the validation rules are evaluated for a Valuation with "valuation_date=2026-05-15;per_share_value_cents=100000"
    Then the rule "valuation_date_not_quarter_end" fires as a "warning"
    And the rule message includes "2026-05-15"

  Scenario: Valuation date on a quarter-end does not fire the date rule
    Given there is an existing portfolio company ""
    And there is an investment instrument for the portfolio company "name=Stock;category=Unlisted;sub_category=Equity;sector=Tech"
    And the entity has opted in to all validation rules
    When the validation rules are evaluated for a Valuation with "valuation_date=2026-03-31;per_share_value_cents=100000"
    Then the rule "valuation_date_not_quarter_end" does not fire

  Scenario: Large per-share increase fires a warning
    Given there is an existing portfolio company ""
    And there is an investment instrument for the portfolio company "name=Stock;category=Unlisted;sub_category=Equity;sector=Tech"
    And there is a valuation "valuation_date=2026-03-31;per_share_value_cents=100000" for the portfolio company
    And the entity has opted in to all validation rules
    When the validation rules are evaluated for a Valuation with "valuation_date=2026-06-30;per_share_value_cents=200000"
    Then the rule "valuation_large_increase" fires as a "warning"
    And the rule message includes "50"

  Scenario: Modest per-share increase does not fire the increase rule
    Given there is an existing portfolio company ""
    And there is an investment instrument for the portfolio company "name=Stock;category=Unlisted;sub_category=Equity;sector=Tech"
    And there is a valuation "valuation_date=2026-03-31;per_share_value_cents=100000" for the portfolio company
    And the entity has opted in to all validation rules
    When the validation rules are evaluated for a Valuation with "valuation_date=2026-06-30;per_share_value_cents=130000"
    Then the rule "valuation_large_increase" does not fire

  Scenario: Large per-share decrease fires a warning
    Given there is an existing portfolio company ""
    And there is an investment instrument for the portfolio company "name=Stock;category=Unlisted;sub_category=Equity;sector=Tech"
    And there is a valuation "valuation_date=2026-03-31;per_share_value_cents=100000" for the portfolio company
    And the entity has opted in to all validation rules
    When the validation rules are evaluated for a Valuation with "valuation_date=2026-06-30;per_share_value_cents=30000"
    Then the rule "valuation_large_decrease" fires as a "warning"

  @javascript
  Scenario: Submitting a valuation form with a non-quarter-end date shows the warning modal
    Given Im logged in as a user "first_name=Test" for an entity "name=RuleTestFirm;entity_type=Investment Fund;currency=INR"
    And the user has role "company_admin"
    And the default validation rules are seeded
    And the entity has opted in to all validation rules
    And there is an existing portfolio company ""
    And there is a fund "name=RuleTestFund;currency=INR" for the entity
    And there is an investment instrument for the portfolio company "name=Stock;category=Unlisted;sub_category=Equity;sector=Tech"
    When I visit the new valuation page for the portfolio company
    And I fill the valuation form with date "2026-05-15" and per_share_value "100"
    And I submit the valuation form
    Then the rule validation modal appears
    And the modal shows a warning containing "not a quarter-end"
    And the modal has a "Confirm & Save" button

  @javascript
  Scenario: Confirming the warning modal saves the valuation
    Given Im logged in as a user "first_name=Test" for an entity "name=RuleTestFirm;entity_type=Investment Fund;currency=INR"
    And the user has role "company_admin"
    And the default validation rules are seeded
    And the entity has opted in to all validation rules
    And there is an existing portfolio company ""
    And there is a fund "name=RuleTestFund;currency=INR" for the entity
    And there is an investment instrument for the portfolio company "name=Stock;category=Unlisted;sub_category=Equity;sector=Tech"
    When I visit the new valuation page for the portfolio company
    And I fill the valuation form with date "2026-05-15" and per_share_value "100"
    And I submit the valuation form
    And I click "Confirm & Save" in the modal
    Then the valuation is saved successfully

  # ── AllocationRun rules ──────────────────────────────────────────────────────

  Scenario: Allocation run end date not on a quarter-end fires a warning
    Given there is a fund "name=RuleTestFund;currency=INR" for the entity
    And the entity has opted in to all validation rules
    When the validation rules are evaluated for an AllocationRun with "end_date=2026-05-15;start_date=2026-04-01"
    Then the rule "allocation_run_date_not_quarter_end" fires as a "warning"

  Scenario: Allocation run end date on a quarter-end does not fire the date rule
    Given there is a fund "name=RuleTestFund;currency=INR" for the entity
    And the entity has opted in to all validation rules
    When the validation rules are evaluated for an AllocationRun with "end_date=2026-03-31;start_date=2026-01-01"
    Then the rule "allocation_run_date_not_quarter_end" does not fire

  Scenario: Already-locked allocation run fires a blocker
    Given there is a fund "name=RuleTestFund;currency=INR" for the entity
    And the entity has opted in to all validation rules
    When the validation rules are evaluated for an AllocationRun with "end_date=2026-03-31;start_date=2026-01-01;locked=true"
    Then the rule "allocation_run_already_locked" fires as a "blocker"

  Scenario: Valuation exists rule warns when portfolio companies have no recent valuation
    Given there is an existing portfolio company ""
    And there is a fund "name=RuleTestFund;currency=INR" for the entity
    And there is an investment instrument for the portfolio company "name=Stock;category=Unlisted;sub_category=Equity;sector=Tech"
    And there is a portfolio investment for the fund
    And the entity has opted in to all validation rules
    When the validation rules are evaluated for an AllocationRun with "end_date=2026-06-30;start_date=2026-04-01"
    Then the rule "allocation_run_valuation_exists" fires as a "warning"
    And the rule message includes the portfolio company name

  Scenario: Valuation exists rule does not fire when all portfolio companies have recent valuations
    Given there is an existing portfolio company ""
    And there is a fund "name=RuleTestFund;currency=INR" for the entity
    And there is an investment instrument for the portfolio company "name=Stock;category=Unlisted;sub_category=Equity;sector=Tech"
    And there is a portfolio investment for the fund
    And there is a valuation "valuation_date=2026-06-15;per_share_value_cents=100000" for the portfolio company
    And the entity has opted in to all validation rules
    When the validation rules are evaluated for an AllocationRun with "end_date=2026-06-30;start_date=2026-04-01"
    Then the rule "allocation_run_valuation_exists" does not fire

  Scenario: FX rates rule warns when instrument uses a foreign currency and rate is missing
    Given there is an existing portfolio company ""
    And there is a fund "name=RuleTestFund;currency=INR" for the entity
    And there is an investment instrument for the portfolio company "name=USStock;category=Unlisted;sub_category=Equity;sector=Tech;currency=USD"
    And there is a portfolio investment for the fund
    And the entity has opted in to all validation rules
    When the validation rules are evaluated for an AllocationRun with "end_date=2026-06-30;start_date=2026-04-01"
    Then the rule "allocation_run_fx_rates_exist" fires as a "warning"
    And the rule message includes "USD → INR"

  Scenario: FX rates rule does not fire when all required rates are present
    Given there is an existing portfolio company ""
    And there is a fund "name=RuleTestFund;currency=INR" for the entity
    And there is an investment instrument for the portfolio company "name=USStock;category=Unlisted;sub_category=Equity;sector=Tech;currency=USD"
    And there is a portfolio investment for the fund
    And there is an exchange rate "from=USD;to=INR;as_of=2026-06-28" for the entity
    And the entity has opted in to all validation rules
    When the validation rules are evaluated for an AllocationRun with "end_date=2026-06-30;start_date=2026-04-01"
    Then the rule "allocation_run_fx_rates_exist" does not fire

  Scenario: FX rates rule is skipped when all instruments share the fund currency
    Given there is an existing portfolio company ""
    And there is a fund "name=RuleTestFund;currency=INR" for the entity
    And there is an investment instrument for the portfolio company "name=Stock;category=Unlisted;sub_category=Equity;sector=Tech;currency=INR"
    And there is a portfolio investment for the fund
    And the entity has opted in to all validation rules
    When the validation rules are evaluated for an AllocationRun with "end_date=2026-06-30;start_date=2026-04-01"
    Then the rule "allocation_run_fx_rates_exist" does not fire

  Scenario: FX rates rule warns when tracking currency rate is missing
    Given there is a fund "name=RuleTestFund;currency=INR;tracking_currency=USD" for the entity
    And the entity has opted in to all validation rules
    When the validation rules are evaluated for an AllocationRun with "end_date=2026-06-30;start_date=2026-04-01"
    Then the rule "allocation_run_fx_rates_exist" fires as a "warning"
    And the rule message includes "INR → USD (tracking currency)"

  Scenario: FX rates rule does not fire when tracking currency rate is present
    Given there is a fund "name=RuleTestFund;currency=INR;tracking_currency=USD" for the entity
    And there is an exchange rate "from=INR;to=USD;as_of=2026-06-28" for the entity
    And the entity has opted in to all validation rules
    When the validation rules are evaluated for an AllocationRun with "end_date=2026-06-30;start_date=2026-04-01"
    Then the rule "allocation_run_fx_rates_exist" does not fire

  Scenario: Account entries rule is inactive when no names are configured
    Given there is a fund "name=RuleTestFund;currency=INR" for the entity
    And the entity has opted in to all validation rules
    When the validation rules are evaluated for an AllocationRun with "end_date=2026-06-30;start_date=2026-04-01"
    Then the rule "allocation_run_account_entries_exist" does not fire

  Scenario: Account entries rule warns when configured entries are missing
    Given there is a fund "name=RuleTestFund;currency=INR" for the entity
    And there is a validation rule override for "allocation_run_account_entries_exist" with "param_overrides=n_days:30,account_entry_names:Management Fee"
    When the validation rules are evaluated for an AllocationRun with "end_date=2026-06-30;start_date=2026-04-01"
    Then the rule "allocation_run_account_entries_exist" fires as a "warning"
    And the rule message includes "Management Fee"

  Scenario: Account entries rule does not fire when all configured entries are present
    Given there is a fund "name=RuleTestFund;currency=INR" for the entity
    And there is an account entry "name=Management Fee;reporting_date=2026-06-20" for the fund
    And there is a validation rule override for "allocation_run_account_entries_exist" with "param_overrides=n_days:30,account_entry_names:Management Fee"
    When the validation rules are evaluated for an AllocationRun with "end_date=2026-06-30;start_date=2026-04-01"
    Then the rule "allocation_run_account_entries_exist" does not fire

  # ── FundRatio rules ──────────────────────────────────────────────────────────

  Scenario: Fund ratio end date not on a quarter-end fires a warning
    Given there is a fund "name=RuleTestFund;currency=INR" for the entity
    And the entity has opted in to all validation rules
    When the validation rules are evaluated for a FundRatio with "end_date=2026-05-15"
    Then the rule "fund_ratio_date_not_quarter_end" fires as a "warning"

  Scenario: Fund ratio value above the max range fires a warning
    Given there is a fund "name=RuleTestFund;currency=INR" for the entity
    And the entity has opted in to all validation rules
    When the validation rules are evaluated for a FundRatio with "end_date=2026-03-31;value=15"
    Then the rule "fund_ratio_value_out_of_range" fires as a "warning"

  Scenario: Fund ratio value within range does not fire
    Given there is a fund "name=RuleTestFund;currency=INR" for the entity
    And the entity has opted in to all validation rules
    When the validation rules are evaluated for a FundRatio with "end_date=2026-03-31;value=5"
    Then the rule "fund_ratio_value_out_of_range" does not fire

  @javascript
  Scenario: Generate fund ratios form shows warning modal for non-quarter-end date
    Given Im logged in as a user "first_name=Test" for an entity "name=RuleTestFirm;entity_type=Investment Fund;currency=INR"
    And the user has role "company_admin"
    And the default validation rules are seeded
    And the entity has opted in to all validation rules
    And there is a fund "name=RuleTestFund;currency=INR" for the entity
    When I visit the generate fund ratios page for the fund
    And I fill the fund ratios end date with "2026-05-15"
    And I submit the fund ratios form
    Then the rule validation modal appears
    And the modal shows a warning containing "not a quarter-end"

  # ── Override management ──────────────────────────────────────────────────────

  @javascript
  Scenario: Company admin views all rules on the overrides index page
    Given Im logged in as a user "first_name=Test" for an entity "name=RuleTestFirm;entity_type=Investment Fund;currency=INR"
    And the user has role "company_admin"
    And the default validation rules are seeded
    When I visit the validation rule overrides page
    Then I see the rule "Valuation Date Not Quarter End" listed
    And I see the rule "Allocation Run Already Locked" listed
    And I see the rule "Fund Ratio Date Not Quarter End" listed

  @javascript
  Scenario: Company admin disables a rule via override
    Given Im logged in as a user "first_name=Test" for an entity "name=RuleTestFirm;entity_type=Investment Fund;currency=INR"
    And the user has role "company_admin"
    And the default validation rules are seeded
    When I visit the validation rule overrides page
    And I click "Set Override" for the rule "Valuation Date Not Quarter End"
    And I disable the rule enable toggle
    And I click "Save Override"
    Then I see "Override saved"
    And the rule "valuation_date_not_quarter_end" is disabled for the entity

  @javascript
  Scenario: Company admin tightens a threshold via param override
    Given Im logged in as a user "first_name=Test" for an entity "name=RuleTestFirm;entity_type=Investment Fund;currency=INR"
    And the user has role "company_admin"
    And the default validation rules are seeded
    When I visit the validation rule overrides page
    And I click "Set Override" for the rule "Valuation Large Increase"
    And I fill in the param "pct_threshold" with "20"
    And I click "Save Override"
    Then I see "Override saved"

  @javascript
  Scenario: Company admin escalates a warning to a blocker via severity override
    Given Im logged in as a user "first_name=Test" for an entity "name=RuleTestFirm;entity_type=Investment Fund;currency=INR"
    And the user has role "company_admin"
    And the default validation rules are seeded
    When I visit the validation rule overrides page
    And I click "Set Override" for the rule "Valuation Date Not Quarter End"
    And I select "Blocker — must fix before saving" from the severity dropdown
    And I click "Save Override"
    Then I see "Override saved"
    And the rule "valuation_date_not_quarter_end" has severity override "blocker" for the entity

  @javascript
  Scenario: Company admin sets a custom message via override
    Given Im logged in as a user "first_name=Test" for an entity "name=RuleTestFirm;entity_type=Investment Fund;currency=INR"
    And the user has role "company_admin"
    And the default validation rules are seeded
    When I visit the validation rule overrides page
    And I click "Set Override" for the rule "Valuation Date Not Quarter End"
    And I fill in the message override with "All valuations must be quarter-end per our policy."
    And I click "Save Override"
    Then I see "Override saved"

  # ── Override effects on evaluation ──────────────────────────────────────────

  Scenario: Disabled rule does not fire even when the condition is violated
    Given there is an existing portfolio company ""
    And there is an investment instrument for the portfolio company "name=Stock;category=Unlisted;sub_category=Equity;sector=Tech"
    And the entity has opted in to all validation rules
    And there is a validation rule override for "valuation_date_not_quarter_end" with "enabled=false"
    When the validation rules are evaluated for a Valuation with "valuation_date=2026-05-15;per_share_value_cents=100000"
    Then the rule "valuation_date_not_quarter_end" does not fire

  Scenario: Entity that has opted out of all validation rules fires no rules
    Given there is an existing portfolio company ""
    And there is an investment instrument for the portfolio company "name=Stock;category=Unlisted;sub_category=Equity;sector=Tech"
    And the entity has opted in to all validation rules
    And the entity has opted out of all validation rules
    When the validation rules are evaluated for a Valuation with "valuation_date=2026-05-15;per_share_value_cents=100000"
    Then the rule "valuation_date_not_quarter_end" does not fire

  Scenario: Tighter threshold override is used during evaluation
    Given there is an existing portfolio company ""
    And there is an investment instrument for the portfolio company "name=Stock;category=Unlisted;sub_category=Equity;sector=Tech"
    And there is a valuation "valuation_date=2026-03-31;per_share_value_cents=100000" for the portfolio company
    And there is a validation rule override for "valuation_large_increase" with "param_overrides=pct_threshold:20"
    When the validation rules are evaluated for a Valuation with "valuation_date=2026-06-30;per_share_value_cents=130000"
    Then the rule "valuation_large_increase" fires as a "warning"

  Scenario: Severity override escalates warning to blocker
    Given there is an existing portfolio company ""
    And there is an investment instrument for the portfolio company "name=Stock;category=Unlisted;sub_category=Equity;sector=Tech"
    And there is a validation rule override for "valuation_date_not_quarter_end" with "severity_override=blocker"
    When the validation rules are evaluated for a Valuation with "valuation_date=2026-05-15;per_share_value_cents=100000"
    Then the rule "valuation_date_not_quarter_end" fires as a "blocker"

  Scenario: Custom message override is shown in the evaluation result
    Given there is an existing portfolio company ""
    And there is an investment instrument for the portfolio company "name=Stock;category=Unlisted;sub_category=Equity;sector=Tech"
    And there is a validation rule override for "valuation_date_not_quarter_end" with "message_override=Our policy requires quarter-end dates."
    When the validation rules are evaluated for a Valuation with "valuation_date=2026-05-15;per_share_value_cents=100000"
    Then the rule message includes "Our policy requires quarter-end dates."
