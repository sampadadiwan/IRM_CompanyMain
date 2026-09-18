@allocation_run_checker @run_check_suggestions
Feature: Suggesting a fund's run checks
  Support generates pre/post-run check formulas for a fund from Actions > Suggest run checks. Fixed rules
  read the fund's enabled formulas, custom field forms and past uploads; optional AI suggestions go
  through the same validation. Every rule suggestion, and every AI suggestion that is a plain helper call
  with literal arguments, is test-run against the fund's last successful allocation run; other AI text is
  shown untested until a person adds it. Suggestions can be added, at a chosen severity, or downloaded as
  an importable xlsx.
  See openspec/changes/incremental-allocation-ui.

  Background:
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund;currency=INR"
    And the user has role "company_admin"
    And the user has role "support"
    And there is a fund "name=Suggest Fund;currency=INR;unit_types=A1" for the entity
    And the fund has folios "101,102"
    And every folio holds "50" percent of "udr_1"
    And the fund allocates entry type "Non Deal Expense" by each upload's fund level UDR code
    And the fund reports the quarterly total of "Audit Fees"
    And these account entries were uploaded:
      | name       | entry_type       | amount | reporting_date | generated | custom_fields                |
      | Audit Fees | Non Deal Expense | 1000   | 2024-02-01     | false     | fund_level_udr_code=UDR - 1  |

  # ── Rules ────────────────────────────────────────────────────────────────────

  Scenario: Rules suggest checks from the fund's formulas and uploads, with evidence
    When support generates run check suggestions
    Then a suggestion should call 'allowed_entry_names("Non Deal Expense", ["Audit Fees"])'
    And the suggestion calling "allowed_entry_names" should cite formula "Quarterly Audit Fees"
    And a suggestion should call 'required_custom_fields(:account_entries, ["Fund Level Udr Code"], fund_level_only: true)'
    And the suggestion calling "required_custom_fields" should cite formula "Non Deal Expense"
    And a suggestion should call "folio_shares_total(:fund_level_udr_code)"
    And a suggestion should call "fund_entries_allocated"
    And a suggestion should call "fund_entries_tie_to_folios(tolerance: 1.0)"

  Scenario: The same data gives the same suggestions
    When support generates run check suggestions
    Then generating the suggestions again should give the same formulas

  Scenario: A rule that does not apply suggests nothing
    When support generates run check suggestions
    Then no suggestion should call "fx_rates_present"
    And no suggestion should call "valuations_present"

  Scenario: A fund holding a foreign currency instrument gets an FX rate check
    Given there is an existing portfolio company ""
    And there is an investment instrument for the portfolio company "name=USStock;category=Unlisted;sub_category=Equity;sector=Tech;currency=USD"
    And there is a portfolio investment for the fund
    When support generates run check suggestions
    Then a suggestion should call "fx_rates_present(within_days: 5)"
    And a suggestion should call "valuations_present(within_months: 3, severity: :warning)"

  Scenario: The fund's since-inception totals get a history check
    Given the fund stores the since-inception total of "Audit Fees"
    When support generates run check suggestions
    Then a suggestion should call 'since_inception_matches_history(["Audit Fees"])'

  Scenario: A disabled formula is no reason for a check
    Given formula "Non Deal Expense" is disabled
    When support generates run check suggestions
    Then no suggestion should call "allowed_entry_names"
    And no suggestion should call "required_custom_fields"
    And no suggestion should call "folio_shares_total"
    And no suggestion should call "fund_entries_allocated"

  Scenario: Unit setting keys the formulas read get a unit settings check, with evidence
    Given the fund has a formula "Hurdle" reading the unit setting "hurdle_rate"
    When support generates run check suggestions
    Then a suggestion should call 'unit_settings_present(["hurdle_rate"])'
    And the suggestion calling "unit_settings_present" should cite formula "Hurdle"
    And the suggestion calling "unit_settings_present" should note "Unit types in use: A1 (2)"

  Scenario: A check the fund already has is marked, in any list order
    Given the fund has a "PreRunCheck" check "Expense heads" with formula:
      """
      allowed_entry_names("Non Deal Expense", ["Audit Fees"], severity: :warning)
      """
    When support generates run check suggestions
    Then the suggestion calling "allowed_entry_names" should be marked already present

  # ── Test runs ────────────────────────────────────────────────────────────────

  Scenario: Suggestions are tested against the last successful run
    Given there is a finished allocation run "start_date=2024-01-01;end_date=2024-03-31"
    And these account entries were uploaded:
      | name   | entry_type       | amount | reporting_date | generated | custom_fields               |
      | Travel | Non Deal Expense | 300    | 2024-02-10     | false     | fund_level_udr_code=UDR - 1 |
    When support generates run check suggestions
    Then the suggestion calling "allowed_entry_names" should have test result "fail" mentioning "Travel"
    And the suggestion calling "folio_shares_total" should have test result "pass"

  Scenario: A fund with no successful run gets untested suggestions
    When support generates run check suggestions
    Then the suggestion calling "allowed_entry_names" should have test result "not_tested"

  # ── Adding and exporting ─────────────────────────────────────────────────────

  Scenario: Add a check as a warning
    Given there is a finished allocation run "start_date=2024-01-01;end_date=2024-03-31"
    When support generates run check suggestions
    And support adds the suggestion calling "allowed_entry_names" as a "warning"
    Then the added count should be 1
    And the fund should have a "PreRunCheck" check formula 'allowed_entry_names("Non Deal Expense", ["Audit Fees"], severity: :warning)'

  Scenario: Several checks are added at once, and adding one again is refused
    Given there is a finished allocation run "start_date=2024-01-01;end_date=2024-03-31"
    When support generates run check suggestions
    And support adds the suggestions calling "allowed_entry_names" and "fund_entries_allocated"
    Then the added count should be 2
    When support adds the suggestion calling "allowed_entry_names" as a "fail"
    Then the added count should be 0
    And the add should be refused for "Pre-run check: Non Deal Expense names" with "already present"

  Scenario: A downloaded file imports as the same formulas
    When support generates run check suggestions
    And support downloads the suggestions calling "allowed_entry_names" and "fund_entries_allocated" and imports the file into the fund
    Then the import should create exactly those formulas

  # ── AI ───────────────────────────────────────────────────────────────────────

  Scenario: AI suggestions are validated like rule suggestions, and only plain helper calls are test-run
    Given there is a finished allocation run "start_date=2024-01-01;end_date=2024-03-31"
    And the AI suggests these checks:
      | name                     | description                | rule_type    | formula                                                |
      | Pre-run check: Folios    | The fund needs folios.     | PreRunCheck  | check!(@fund.capital_commitments.exists?, "No folios") |
      | Post-run check: Ties     | Entries tie within 2.      | PostRunCheck | fund_entries_tie_to_folios(tolerance: 2.0)             |
      | Pre-run check: Unsafe    | Deletes entries.           | PreRunCheck  | AccountEntry.where(fund_id: @fund.id).delete_all       |
      | Not a check              | Writes an entry.           | GenerateAccountEntry | 1                                              |
    When support generates run check suggestions with AI
    Then a suggestion from AI should call 'check!(@fund.capital_commitments.exists?, "No folios")'
    And the suggestion calling 'check!(@fund.capital_commitments.exists?, "No folios")' should have test result "not_tested" mentioning "only evaluated once a person adds it"
    And the suggestion calling "fund_entries_tie_to_folios(tolerance: 2.0)" should have been test-run against the run
    And the AI suggestion "Pre-run check: Unsafe" should be rejected with "CRUD"
    And the AI suggestion "Not a check" should be rejected with "Not a PreRunCheck or PostRunCheck"
    And a suggestion should call "fund_entries_allocated"

  Scenario: The rule suggestions survive an AI failure
    Given the AI service is unavailable
    When support generates run check suggestions with AI
    Then the suggestion set should record the AI error "LLM unavailable"

  # ── Pages ────────────────────────────────────────────────────────────────────

  Scenario: Support returns to the latest suggestion set
    When support generates run check suggestions
    And the user opens Suggest run checks
    Then the latest suggestion set should open
