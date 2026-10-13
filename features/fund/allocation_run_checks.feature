@allocation_run_checker @allocation_run_checks
Feature: Allocation run pre-run and post-run checks
  A fund's own checks are FundFormulas with rule type PreRunCheck or PostRunCheck. They create no
  account entries: each passes, warns or fails. Pre-run checks run before the allocation deletes or
  computes anything; post-run checks run after every formula. Every check of a kind runs, then any
  failure stops the run. Failed and warning check results are stored on the run's allocation run
  report, which shows each check as its own finding (1.5.n pre-run, 1.6.n post-run).
  See docs/modules/allocation/allocation_run_checks.md.

  Background:
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund;currency=INR"
    Given the user has role "company_admin"
    Given there is a fund "name=Checks Fund;currency=INR;unit_types=A1" for the entity

  # ── Check formulas ───────────────────────────────────────────────────────────

  @rack_test
  Scenario Outline: A check formula needs no entry type
    Given a "<rule_type>" fund formula "Units configured" without an entry type
    Then the check formula should be valid

    Examples:
      | rule_type    |
      | PreRunCheck  |
      | PostRunCheck |

  @rack_test
  Scenario: A check formula cannot generate YTD numbers or roll up
    Given a "PreRunCheck" fund formula "Units configured" without an entry type
    And the check formula has generate_ytd_qtly and roll_up enabled
    Then the check formula should be invalid on "generate_ytd_qtly" and "roll_up"

  @rack_test
  Scenario: A formula that writes entries still needs an entry type
    Given a "GenerateAccountEntry" fund formula "Management Fees" without an entry type
    Then the check formula should be invalid on "entry_type"

  @rack_test
  Scenario: Check formulas are left out of the dependency graph and the allocation run's formulas
    Given the fund has a "GenerateAccountEntry" formula "Management Fees"
    And the fund has a "PreRunCheck" check "Units configured" with formula:
      """
      @fund.present?
      """
    Then the dependency graph should list only "Management Fees"
    And the allocation engine's formulas should be only "Management Fees"

  # ── How a check's outcome is decided ─────────────────────────────────────────

  @rack_test
  Scenario Outline: A check's outcome
    Given the fund has folios "101"
    And there is a finished allocation run "start_date=2024-01-01;end_date=2024-03-31"
    And the fund has a "PreRunCheck" check "The check" with formula:
      """
      <formula>
      """
    When the "pre" checks are run for that allocation run
    Then check "The check" should have result "<result>" mentioning "<summary>"

    Examples:
      | formula                                                               | result  | summary                            |
      | @fund.present? && @end_date == Date.new(2024, 3, 31)                  | pass    | Passed                             |
      | nil                                                                   | pass    | Passed                             |
      | 1 > 2                                                                 | fail    | Check returned false               |
      | raise "3 commitments have no unit type"                               | fail    | 3 commitments have no unit type    |
      | check!(false, "Fund has no unit settings")                            | fail    | Fund has no unit settings          |
      | raise CheckWarning, "Valuations are stale"                            | warn    | Valuations are stale               |
      | raise SkipRule, "Not applicable to this fund"                         | skipped | Not applicable to this fund        |
      | @fund.no_such_method                                                  | fail    | NoMethodError                      |

  @rack_test
  Scenario: Every check runs even after one fails
    Given the fund has folios "101"
    And there is a finished allocation run "start_date=2024-01-01;end_date=2024-03-31"
    And the fund has a "PreRunCheck" check "First" with formula:
      """
      raise "first problem"
      """
    And the fund has a "PreRunCheck" check "Second" with formula:
      """
      raise "second problem"
      """
    And the fund has a "PreRunCheck" check "Third" with formula:
      """
      true
      """
    When the "pre" checks are run for that allocation run
    Then check "First" should have result "fail" mentioning "first problem"
    And check "Second" should have result "fail" mentioning "second problem"
    And check "Third" should have result "pass" mentioning "Passed"

  # ── Pre-run check helpers ────────────────────────────────────────────────────

  @rack_test
  Scenario: allowed_entry_names flags names outside the list, matching exactly
    Given the fund has folios "101"
    And there is a finished allocation run "start_date=2024-01-01;end_date=2024-03-31"
    And these account entries were uploaded:
      | name         | entry_type        | amount | reporting_date | generated |
      | Audit Fees   | Non Deal Expense  | 100    | 2024-02-01     | false     |
      | audit fees   | Non Deal Expense  | 50     | 2024-02-02     | false     |
      | Travel       | Non Deal Expense  | 30     | 2024-02-03     | false     |
      | Bank Charges | non deal expense  | 10     | 2024-02-04     | false     |
      | Old Head     | Non Deal Expense  | 10     | 2023-12-31     | false     |
      | Generated    | Non Deal Expense  | 10     | 2024-02-05     | true      |
    And the fund has a "PreRunCheck" check "Expense heads" with formula:
      """
      allowed_entry_names("Non Deal Expense", ["Audit Fees", "Bank Charges"])
      """
    When the "pre" checks are run for that allocation run
    Then check "Expense heads" should have result "fail" mentioning "audit fees"
    And check "Expense heads" should mention "Travel"
    And check "Expense heads" should not mention "Bank Charges"
    And check "Expense heads" should not mention "Old Head"
    And check "Expense heads" should not mention "Generated"

  @rack_test
  Scenario: allowed_entry_names can warn instead of fail
    Given the fund has folios "101"
    And there is a finished allocation run "start_date=2024-01-01;end_date=2024-03-31"
    And these account entries were uploaded:
      | name   | entry_type      | amount | reporting_date | generated |
      | Travel | Non Deal Income | 30     | 2024-02-03     | false     |
    And the fund has a "PreRunCheck" check "Income heads" with formula:
      """
      allowed_entry_names("Non Deal Income", ["Income from Temporary Investments", "Miscelleneous Income"], severity: :warning)
      """
    When the "pre" checks are run for that allocation run
    Then check "Income heads" should have result "warn" mentioning "Travel"

  @rack_test
  Scenario: required_custom_fields lists each uploaded entry missing a custom field
    Given the fund has folios "101"
    And there is a finished allocation run "start_date=2024-01-01;end_date=2024-03-31"
    And these account entries were uploaded:
      | name       | entry_type       | amount | reporting_date | generated | folio | custom_fields                                    |
      | Audit Fees | Non Deal Expense | 100    | 2024-02-01     | false     |       | fund_level_udr_code=U1,expense_head=Audit        |
      | Travel     | Non Deal Expense | 30     | 2024-02-03     | false     | 101   | fund_level_udr_code=,expense_head=Travel         |
    And the fund has a "PreRunCheck" check "UDR codes" with formula:
      """
      required_custom_fields(:account_entries, ["Fund Level UDR Code", "Expense Head"])
      """
    When the "pre" checks are run for that allocation run
    Then check "UDR codes" should have result "fail" mentioning "1 of 2 uploaded entries"
    And check "UDR codes" should mention "Fund Level UDR Code"
    And check "UDR codes" should not mention "Audit Fees"

  @rack_test
  Scenario: required_custom_fields can be limited to fund-level uploads or to entry types
    Given the fund has folios "101"
    And there is a finished allocation run "start_date=2024-01-01;end_date=2024-03-31"
    And these account entries were uploaded:
      | name       | entry_type       | amount | reporting_date | generated | folio | custom_fields             |
      | Audit Fees | Non Deal Expense | 100    | 2024-02-01     | false     |       | fund_level_udr_code=U1    |
      | Taxes Paid | Tax              | 30     | 2024-02-03     | false     | 101   |                           |
      | Custody    | Non Deal Expense | 40     | 2024-02-04     | false     | 101   |                           |
    And the fund has a "PreRunCheck" check "Fund level only" with formula:
      """
      required_custom_fields(:account_entries, ["Fund Level UDR Code"], fund_level_only: true)
      """
    And the fund has a "PreRunCheck" check "Expenses only" with formula:
      """
      required_custom_fields(:account_entries, ["Fund Level UDR Code"], entry_types: ["Non Deal Expense"])
      """
    And the fund has a "PreRunCheck" check "Options on investments" with formula:
      """
      required_custom_fields(:portfolio_investments, ["Fund Level UDR Code"], fund_level_only: true)
      """
    When the "pre" checks are run for that allocation run
    Then check "Fund level only" should have result "pass" mentioning "1 uploaded fund-level entries checked"
    And check "Expenses only" should have result "fail" mentioning "Custody"
    And check "Expenses only" should not mention "Taxes Paid"
    And check "Options on investments" should have result "fail" mentioning "only apply to :account_entries"

  @rack_test
  Scenario: entries_mapped_to_portfolio_investment requires this fund's portfolio investment as parent
    Given there is an existing portfolio company ""
    And there is an investment instrument for the portfolio company "name=Stock;category=Unlisted;sub_category=Equity;sector=Tech"
    And there is a portfolio investment for the fund
    And the fund has folios "101"
    And there is a finished allocation run "start_date=2024-01-01;end_date=2024-03-31"
    And these account entries were uploaded:
      | name         | entry_type   | amount | reporting_date | generated | parent               |
      | Deal Mapped  | Deal Expense | 100    | 2024-02-01     | false     | portfolio investment |
      | Deal Company | Deal Expense | 100    | 2024-02-02     | false     | portfolio company    |
      | Deal Nothing | Deal Expense | 100    | 2024-02-03     | false     |                      |
      | Other Case   | deal expense | 100    | 2024-02-04     | false     |                      |
    And the fund has a "PreRunCheck" check "Deals mapped" with formula:
      """
      entries_mapped_to_portfolio_investment(["Deal Expense", "Deal Expense Capitalized", "Deal income"])
      """
    When the "pre" checks are run for that allocation run
    Then check "Deals mapped" should have result "fail" mentioning "2 uploaded deal entries"
    And check "Deals mapped" should mention "Deal Company"
    And check "Deals mapped" should mention "Deal Nothing"
    And check "Deals mapped" should not mention "Deal Mapped"
    And check "Deals mapped" should not mention "Other Case"

  @rack_test
  Scenario: fx_rates_present fails for a currency pair with no recent rate
    Given there is an existing portfolio company ""
    And there is an investment instrument for the portfolio company "name=USStock;category=Unlisted;sub_category=Equity;sector=Tech;currency=USD"
    And there is a portfolio investment for the fund
    And the fund has folios "101"
    And there is a finished allocation run "start_date=2026-04-01;end_date=2026-06-30"
    And the fund has a "PreRunCheck" check "FX rates" with formula:
      """
      fx_rates_present(within_days: 5)
      """
    When the "pre" checks are run for that allocation run
    Then check "FX rates" should have result "fail" mentioning "USD"

  @rack_test
  Scenario: fx_rates_present passes once the rate is loaded
    Given there is an existing portfolio company ""
    And there is an investment instrument for the portfolio company "name=USStock;category=Unlisted;sub_category=Equity;sector=Tech;currency=USD"
    And there is a portfolio investment for the fund
    And there is an exchange rate "from=USD;to=INR;as_of=2026-06-28" for the entity
    And the fund has folios "101"
    And there is a finished allocation run "start_date=2026-04-01;end_date=2026-06-30"
    And the fund has a "PreRunCheck" check "FX rates" with formula:
      """
      fx_rates_present(within_days: 5)
      """
    When the "pre" checks are run for that allocation run
    Then check "FX rates" should have result "pass" mentioning "within 5 days"

  @rack_test
  Scenario: fx_rates_present accepts a window in calendar months
    Given there is an existing portfolio company ""
    And there is an investment instrument for the portfolio company "name=USStock;category=Unlisted;sub_category=Equity;sector=Tech;currency=USD"
    And there is a portfolio investment for the fund
    And there is an exchange rate "from=USD;to=INR;as_of=2026-04-15" for the entity
    And the fund has folios "101"
    And there is a finished allocation run "start_date=2026-04-01;end_date=2026-06-30"
    And the fund has a "PreRunCheck" check "FX within 3 months" with formula:
      """
      fx_rates_present(within_months: 3)
      """
    And the fund has a "PreRunCheck" check "FX within 5 days" with formula:
      """
      fx_rates_present(within_days: 5)
      """
    When the "pre" checks are run for that allocation run
    Then check "FX within 3 months" should have result "pass" mentioning "within 3 months"
    And check "FX within 5 days" should have result "fail" mentioning "USD"

  Scenario: valuations_present warns about a held company with no recent valuation
    Given there is an existing portfolio company ""
    And there is an investment instrument for the portfolio company "name=Stock;category=Unlisted;sub_category=Equity;sector=Tech"
    And there is a portfolio investment for the fund
    And the fund has folios "101"
    And there is a finished allocation run "start_date=2026-04-01;end_date=2026-06-30"
    And the fund has a "PreRunCheck" check "Valuations" with formula:
      """
      valuations_present(within_days: 30, severity: :warning)
      """
    When the "pre" checks are run for that allocation run
    Then check "Valuations" should have result "warn" mentioning "no valuation dated within 30 days"

  @rack_test
  Scenario: folio_shares_total fails a code whose folio percentages do not add up to 100
    Given the fund has folios "101,102"
    And there is a finished allocation run "start_date=2024-01-01;end_date=2024-03-31"
    And folio "101" has custom field "udr_1" of "60"
    And folio "102" has custom field "udr_1" of "40"
    And folio "101" has custom field "udr_2" of "70"
    And these account entries were uploaded:
      | name       | entry_type       | amount | reporting_date | generated | custom_fields               |
      | Audit Fees | Non Deal Expense | 100    | 2024-02-01     | false     | fund_level_udr_code=UDR - 1 |
      | Bank Fees  | Non Deal Expense | 100    | 2024-02-02     | false     | fund_level_udr_code=UDR - 2 |
    And the fund has a "PreRunCheck" check "Shares" with formula:
      """
      folio_shares_total(:fund_level_udr_code)
      """
    When the "pre" checks are run for that allocation run
    Then check "Shares" should have result "fail" mentioning "UDR - 2"
    And check "Shares" should mention "70.0"
    And check "Shares" should not mention "UDR - 1"

  @rack_test
  Scenario: folio_shares_total passes when every code is shared out 100%
    Given the fund has folios "101,102"
    And there is a finished allocation run "start_date=2024-01-01;end_date=2024-03-31"
    And folio "101" has custom field "udr_1" of "60"
    And folio "102" has custom field "udr_1" of "40"
    And these account entries were uploaded:
      | name       | entry_type       | amount | reporting_date | generated | custom_fields               |
      | Audit Fees | Non Deal Expense | 100    | 2024-02-01     | false     | fund_level_udr_code=UDR - 1 |
    And the fund has a "PreRunCheck" check "Shares" with formula:
      """
      folio_shares_total(:fund_level_udr_code)
      """
    When the "pre" checks are run for that allocation run
    Then check "Shares" should have result "pass" mentioning "shared out 100%"

  @rack_test
  Scenario: unit_settings_present lists unit types missing a setting or a key
    Given the fund has folios "101"
    And there is a finished allocation run "start_date=2024-01-01;end_date=2024-03-31"
    And the fund has a unit setting "A1" with json fields "catch_up=0.2"
    And the fund has a "PreRunCheck" check "Catch up only" with formula:
      """
      unit_settings_present(["catch_up"])
      """
    And the fund has a "PreRunCheck" check "Catch up and hurdle" with formula:
      """
      unit_settings_present(["catch_up", "hurdle_rate"])
      """
    When the "pre" checks are run for that allocation run
    Then check "Catch up only" should have result "pass" mentioning "catch_up"
    And check "Catch up and hurdle" should have result "fail" mentioning "hurdle_rate"

  @rack_test
  Scenario: since_inception_matches_history compares each folio's stored total with its history
    Given the fund has folios "101,102"
    And there is a finished allocation run "start_date=2024-01-01;end_date=2024-03-31"
    And these account entries were uploaded:
      | name                       | entry_type | amount | reporting_date | generated | folio |
      | Audit Fees                 | Fee        | 10000  | 2024-01-15     | true      | 101   |
      | Since Inception Audit Fees | Reporting  | 10000  | 2024-03-31     | true      | 101   |
      | Audit Fees                 | Fee        | 10000  | 2024-01-15     | true      | 102   |
      | Since Inception Audit Fees | Reporting  | 15000  | 2024-03-31     | true      | 102   |
    And the fund has a "PostRunCheck" check "History" with formula:
      """
      since_inception_matches_history(["Audit Fees"])
      """
    When the "post" checks are run for that allocation run
    Then check "History" should have result "fail" mentioning "1 stored Since Inception total differs"
    And check "History" should mention "102"
    And check "History" should not mention "101"

  @rack_test
  Scenario: since_inception_matches_history passes when every stored total equals its history
    Given the fund has folios "101,102"
    And there is a finished allocation run "start_date=2024-01-01;end_date=2024-03-31"
    And these account entries were uploaded:
      | name                       | entry_type | amount | reporting_date | generated | folio |
      | Audit Fees                 | Fee        | 10000  | 2024-01-15     | true      | 101   |
      | Since Inception Audit Fees | Reporting  | 10000  | 2024-03-31     | true      | 101   |
      | Audit Fees                 | Fee        | 4000   | 2023-12-15     | true      | 102   |
      | Audit Fees                 | Fee        | 6000   | 2024-02-15     | true      | 102   |
      | Since Inception Audit Fees | Reporting  | 10000  | 2024-03-31     | true      | 102   |
    And the fund has a "PostRunCheck" check "History" with formula:
      """
      since_inception_matches_history(["Audit Fees"])
      """
    When the "post" checks are run for that allocation run
    Then check "History" should have result "pass" mentioning "match the full history"

  # ── Post-run check helpers ───────────────────────────────────────────────────

  @rack_test
  Scenario: fund_entries_allocated and fund_entries_tie_to_folios
    Given the fund has folios "101,102"
    And there is a finished allocation run "start_date=2024-01-01;end_date=2024-03-31"
    And the fund has an "AllocateAccountEntry-Name" formula "Audit Fees"
    And the fund has an "AllocateAccountEntryIndividual-EntryType" formula "Non Deal Expense"
    And these account entries were uploaded:
      | name       | entry_type       | amount | reporting_date | generated |
      | Audit Fees | Non Deal Expense | 20000  | 2024-02-01     | false     |
      | Travel     | Deal Expense     | 3000   | 2024-02-03     | false     |
      | Legal      | Legal Expense    | 5000   | 2024-02-04     | false     |
      | Bank       | Bank Charges     | 700    | 2024-02-05     | false     |
    # Audit Fees is picked up by both formulas (by name, and by its entry type)
    And the run allocated "Audit Fees" of "9980" to folio "101" and "10000" to folio "102" by formula "Audit Fees"
    And the run allocated "Quarterly Audit Fees" of "50000" to folio "101" and "0" to folio "102" by formula "Audit Fees"
    And the run allocated "Audit Fees" of "10000" to folio "101" and "10000" to folio "102" by formula "Non Deal Expense"
    And the run produced a fund total of "99999" for "Audit Fees"
    And the fund has a "PostRunCheck" check "Allocated" with formula:
      """
      fund_entries_allocated(except: ["Bank"])
      """
    And the fund has a "PostRunCheck" check "Ties out" with formula:
      """
      fund_entries_tie_to_folios
      """
    And the fund has a "PostRunCheck" check "Ties out loosely" with formula:
      """
      fund_entries_tie_to_folios(tolerance: 1000)
      """
    When the "post" checks are run for that allocation run
    # Travel (Deal Expense) and Legal have no formula that picks them up; Bank is excepted
    Then check "Allocated" should have result "fail" mentioning "Travel"
    And check "Allocated" should mention "Legal"
    And check "Allocated" should not mention "Bank"
    # 200.00 vs 199.80 by name is within 1.00; the run's own rollup and the Quarterly child are ignored
    And check "Ties out" should have result "pass" mentioning "every one matches"
    And check "Ties out loosely" should have result "pass" mentioning "within 1,000.00"

  @rack_test
  Scenario: fund_entries_tie_to_folios fails an under-allocated entry
    Given the fund has folios "101,102"
    And there is a finished allocation run "start_date=2024-01-01;end_date=2024-03-31"
    And the fund has an "AllocateAccountEntry-Name" formula "Travel"
    And these account entries were uploaded:
      | name   | entry_type       | amount | reporting_date | generated |
      | Travel | Non Deal Expense | 3000   | 2024-02-03     | false     |
    And the run allocated "Travel" of "1000" to folio "101" and "1000" to folio "102" by formula "Travel"
    And the fund has a "PostRunCheck" check "Ties out" with formula:
      """
      fund_entries_tie_to_folios
      """
    When the "post" checks are run for that allocation run
    Then check "Ties out" should have result "fail" mentioning "Travel"
    And check "Ties out" should mention "10.00"

  @rack_test
  Scenario: portfolio_allocations_tie compares each investment with what its formula allocated
    Given there is an existing portfolio company ""
    And there is an investment instrument for the portfolio company "name=Stock;category=Unlisted;sub_category=Equity;sector=Tech"
    And there is a portfolio investment for the fund
    And the fund has folios "101,102"
    And there is a finished allocation run "start_date=2020-01-01;end_date=2020-03-31"
    And the fund has an "AllocatePortfolioInvestment" formula "Portfolio Cost"
    And the fund has an "AllocatePortfolioInvestment" formula "Portfolio Short"
    And the run allocated "100%" of the portfolio investment amount to the folios by formula "Portfolio Cost"
    And the run allocated "50%" of the portfolio investment amount to the folios by formula "Portfolio Short"
    And the fund has a "PostRunCheck" check "Portfolio full" with formula:
      """
      portfolio_allocations_tie("Portfolio Cost" => :amount_cents)
      """
    And the fund has a "PostRunCheck" check "Portfolio short" with formula:
      """
      portfolio_allocations_tie("Portfolio Short" => :amount_cents)
      """
    And the fund has a "PostRunCheck" check "Portfolio unknown" with formula:
      """
      portfolio_allocations_tie("No Such Formula" => :amount_cents)
      """
    When the "post" checks are run for that allocation run
    Then check "Portfolio full" should have result "pass" mentioning "every one matches"
    And check "Portfolio short" should have result "fail" mentioning "does not match"
    And check "Portfolio unknown" should have result "fail" mentioning "No portfolio investment allocation formula named"

  @rack_test
  Scenario: A post-run helper cannot be used as a pre-run check
    Given the fund has folios "101"
    And the fund has a "PreRunCheck" check "Too early" with formula:
      """
      fund_entries_tie_to_folios
      """
    When the "pre" checks are run without an allocation run for "2024-01-01" to "2024-03-31"
    Then check "Too early" should have result "fail" mentioning "can only be a PostRunCheck"

  # ── The allocation run report ────────────────────────────────────────────────

  @rack_test
  Scenario: Stored check results become one finding per check and survive a re-check
    Given the fund has folios "101,102"
    And there is a finished allocation run "start_date=2024-01-01;end_date=2024-03-31;status=Pre-run checks failed (1): Expense heads: 1 name is not allowed"
    And the run stored these check results:
      | kind | name           | result | summary                  |
      | pre  | Expense heads  | fail   | 1 name is not allowed    |
      | pre  | Units present  | pass   | Passed                   |
    When I check that allocation run
    Then the report status should be "Fail"
    And check "1.5.1" should be "fail" mentioning "1 name is not allowed"
    And check "1.5.2" should be "pass"
    And check "1.6" should be "skipped"
    And check "1.2" should be "skipped" mentioning "stopped by a failed pre-run check"
    And check "2.1" should be "skipped" mentioning "stopped by a failed pre-run check"
    When I check that allocation run
    Then check "1.5.1" should be "fail" mentioning "1 name is not allowed"

  @rack_test
  Scenario: A successful run with checks but nothing stored reports them as passed
    Given the fund has folios "101,102"
    And the fund has a "PreRunCheck" check "Units present" with formula:
      """
      true
      """
    And the fund has a "PostRunCheck" check "Ties out" with formula:
      """
      true
      """
    And there is a finished allocation run "start_date=2024-01-01;end_date=2024-03-31"
    When I check that allocation run
    Then check "1.5" should be "pass" mentioning "none of them failed"
    And check "1.6" should be "pass" mentioning "none of them failed"

  Scenario: A fund without checks reports them as not applicable
    Given the fund has folios "101,102"
    And there is a finished allocation run "start_date=2024-01-01;end_date=2024-03-31"
    When I check that allocation run
    Then check "1.5" should be "skipped" mentioning "no pre-run checks"
    And check "1.6" should be "skipped" mentioning "no post-run checks"

  # ── End to end: the allocation engine ────────────────────────────────────────

  @rack_test
  Scenario: A failed pre-run check stops the run before anything is deleted
    Given there is an existing investor "" with "1" users
    Given there is an existing investor "" with "1" users
    Given the investors are added to the fund
    Given there are capital commitments of "committed_amount_cents=100000000;commitment_date=2023-01-01" from each investor
    And the fund has a GenerateAccountEntry formula "Management Fees" with entry type "Expense" and formula:
      """
      25000
      """
    And the Allocation Run "start_date=01/01/2024;end_date=31/03/2024" is created for the "Checks Fund"
    Then the AllocationRun status is set to "Success"
    Given I remember the fund's account entries
    And the fund has a "PreRunCheck" check "NAV uploaded" with formula:
      """
      raise "NAV missing for #{@end_date}"
      """
    And the fund has a "PreRunCheck" check "Units configured" with formula:
      """
      check!(false, "Fund has no unit settings")
      """
    And the fund has a "PreRunCheck" check "Always fine" with formula:
      """
      true
      """
    When the Allocation Run "start_date=01/01/2024;end_date=31/03/2024" is created for the "Checks Fund"
    Then the latest allocation run status should start with "Pre-run checks failed (2): NAV uploaded: NAV missing for 2024-03-31; Units configured: Fund has no unit settings"
    And the fund's account entries should be unchanged
    And the latest allocation run should have a report
    And the report status should be "Fail"
    And check "1.5.1" should be "fail" mentioning "NAV missing"
    And check "1.5.2" should be "fail" mentioning "Fund has no unit settings"
    And check "1.5.3" should be "pass"
    And check "1.2" should be "skipped" mentioning "stopped by a failed pre-run check"

  @rack_test
  Scenario: A failed post-run check fails the run but keeps its entries
    Given there is an existing investor "" with "1" users
    Given there is an existing investor "" with "1" users
    Given the investors are added to the fund
    Given there are capital commitments of "committed_amount_cents=100000000;commitment_date=2023-01-01" from each investor
    And these account entries were uploaded:
      | name       | entry_type       | amount | reporting_date | generated |
      | Audit Fees | Non Deal Expense | 10000  | 2024-02-01     | false     |
      | Travel     | Non Deal Expense | 3000   | 2024-02-03     | false     |
      | Legal      | Deal Expense     | 5000   | 2024-02-04     | false     |
    And the fund has an "AllocateAccountEntry-Name" formula "Audit Fees" with formula:
      """
      fund_account_entry.amount_cents / 2
      """
    And the fund has an "AllocateAccountEntry-Name" formula "Travel" with formula:
      """
      fund_account_entry.amount_cents / 4
      """
    And the fund has a "PostRunCheck" check "Allocated" with formula:
      """
      fund_entries_allocated
      """
    And the fund has a "PostRunCheck" check "Ties out" with formula:
      """
      fund_entries_tie_to_folios
      """
    When the Allocation Run "start_date=01/01/2024;end_date=31/03/2024" is created for the "Checks Fund"
    Then the latest allocation run status should start with "Post-run checks failed (2)"
    And each commitment should have a generated account entry "Audit Fees" with amount cents "5000"
    And each commitment should have a generated account entry "Travel" with amount cents "750"
    And the latest allocation run should have a report
    And check "1.6.1" should be "fail" mentioning "Legal"
    And check "1.6.2" should be "fail" mentioning "Travel"
    And check "1.6.2" should not mention "Audit Fees"

  @rack_test
  Scenario: A warning check lets the run finish and still builds the report
    Given there is an existing investor "" with "1" users
    Given the investors are added to the fund
    Given there are capital commitments of "committed_amount_cents=100000000;commitment_date=2023-01-01" from each investor
    And the fund has a GenerateAccountEntry formula "Management Fees" with entry type "Expense" and formula:
      """
      25000
      """
    And the fund has a "PreRunCheck" check "Valuations current" with formula:
      """
      raise CheckWarning, "2 portfolio companies have stale valuations"
      """
    When the Allocation Run "start_date=01/01/2024;end_date=31/03/2024" is created for the "Checks Fund"
    Then the AllocationRun status is set to "Success"
    And each commitment should have a generated account entry "Management Fees" with amount cents "25000"
    And the latest allocation run should have a report
    And check "1.5.1" should be "warn" mentioning "stale valuations"

  @rack_test
  Scenario: A run whose checks all pass stores nothing and builds no report
    Given there is an existing investor "" with "1" users
    Given the investors are added to the fund
    Given there are capital commitments of "committed_amount_cents=100000000;commitment_date=2023-01-01" from each investor
    And the fund has a GenerateAccountEntry formula "Management Fees" with entry type "Expense" and formula:
      """
      25000
      """
    And the fund has a "PreRunCheck" check "Always fine" with formula:
      """
      true
      """
    And the fund has a "PostRunCheck" check "Also fine" with formula:
      """
      true
      """
    When the Allocation Run "start_date=01/01/2024;end_date=31/03/2024" is created for the "Checks Fund"
    Then the AllocationRun status is set to "Success"
    And the latest allocation run should have no report
