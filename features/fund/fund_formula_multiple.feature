Feature: GenerateAccountEntryMultiple fund formulas
  A single GenerateAccountEntryMultiple formula embeds the list of account entry
  names as an array literal, e.g.
    capital_commitment.quarterly(["Management Fees", "Custody Fees"], nil, @start_date, @end_date)
  The allocation engine evaluates the formula once per name — substituting the
  array with each single name — creating one account entry per name per
  commitment. This produces the same entries as N single-name GenerateAccountEntry
  formulas while cutting the number of formulas drastically.

  The generated entry names are prefixed based on the period helper wrapping the
  names array (quarterly -> "Quarterly ", year_to_date -> "YTD ",
  since_inception -> "Since Inception "), with meta_data name_prefix as an
  explicit override.

  # ─── Model level: name parsing, prefix derivation, per-name substitution ───

  @rack_test
  Scenario: Entry names are parsed from the formula's array literal
    Given a multiple fund formula with formula:
      """
      capital_commitment.quarterly(["Management Fees", "Custody Fees", "Audit Fees"], nil, @start_date, @end_date)
      """
    Then the multiple entry names should be "Management Fees, Custody Fees, Audit Fees"

  @rack_test
  Scenario Outline: Entry name prefix is derived from the period helper
    Given a multiple fund formula with formula:
      """
      capital_commitment.<method>(["Management Fees", "Audit Fees"], nil, @start_date, @end_date)
      """
    Then the multiple entry prefix should be "<prefix>"

    Examples:
      | method          | prefix           |
      | quarterly       | Quarterly        |
      | period          | Quarterly        |
      | year_to_date    | YTD              |
      | since_inception | Since Inception  |

  @rack_test
  Scenario: meta_data name_prefix overrides the derived prefix
    Given a multiple fund formula with formula:
      """
      capital_commitment.quarterly(["Management Fees"], nil, @start_date, @end_date)
      """
    And the multiple fund formula has meta_data "name_prefix=Custom Prefix "
    Then the multiple entry prefix should be exactly "Custom Prefix "

  @rack_test
  Scenario: No prefix when the formula does not use a known period helper
    Given a multiple fund formula with formula:
      """
      capital_commitment.on_date(["Management Fees"], nil, @end_date)
      """
    Then the multiple entry prefix should be exactly ""

  @rack_test
  Scenario: The names array is substituted with each single name
    Given a multiple fund formula with formula:
      """
      capital_commitment.quarterly(["Management Fees", "Custody Fees"], nil, @start_date, @end_date)
      """
    Then the formula for entry name "Custody Fees" should be:
      """
      capital_commitment.quarterly("Custody Fees", nil, @start_date, @end_date)
      """

  @rack_test
  Scenario: The names array is found even when a guard clause contains another string array
    # Guard arrays appear as method receivers (["active"].include?(...)), not as
    # call arguments, so the argument-position preference skips them.
    Given a multiple fund formula with formula:
      """
      raise SkipRule.new("skip") unless ["active", "closed"].include?(capital_commitment.json_fields["status"]); capital_commitment.quarterly(["Management Fees", "Custody Fees"], nil, @start_date, @end_date)
      """
    Then the multiple entry names should be "Management Fees, Custody Fees"
    And the multiple entry prefix should be "Quarterly"
    And the formula for entry name "Management Fees" should be:
      """
      raise SkipRule.new("skip") unless ["active", "closed"].include?(capital_commitment.json_fields["status"]); capital_commitment.quarterly("Management Fees", nil, @start_date, @end_date)
      """

  @rack_test
  Scenario: Duplicate names in the array are de-duplicated
    Given a multiple fund formula with formula:
      """
      capital_commitment.quarterly(["Management Fees", "Management Fees", "Custody Fees"], nil, @start_date, @end_date)
      """
    Then the multiple entry names should be "Management Fees, Custody Fees"

  @rack_test
  Scenario: Names with quotes are substituted safely
    Given a multiple fund formula with formula:
      """
      capital_commitment.quarterly(["Manager's Fees"], nil, @start_date, @end_date)
      """
    Then the formula for entry name "Manager's Fees" should be:
      """
      capital_commitment.quarterly("Manager's Fees", nil, @start_date, @end_date)
      """

  # ─── Model level: validations ───

  @rack_test
  Scenario: A well-formed multiple formula is valid
    Given a multiple fund formula with formula:
      """
      capital_commitment.quarterly(["Management Fees", "Audit Fees"], nil, @start_date, @end_date)
      """
    When I validate the multiple fund formula
    Then the multiple fund formula should be valid

  @rack_test
  Scenario: A multiple formula without a names array is rejected
    Given a multiple fund formula with formula:
      """
      capital_commitment.quarterly("Management Fees", nil, @start_date, @end_date)
      """
    When I validate the multiple fund formula
    Then the multiple fund formula should be invalid with a formula error containing "non-empty array of quoted account entry names"

  Scenario: A multiple formula with generate_ytd_qtly enabled is rejected
    Given a multiple fund formula with formula:
      """
      capital_commitment.quarterly(["Management Fees"], nil, @start_date, @end_date)
      """
    And the multiple fund formula has generate_ytd_qtly enabled
    When I validate the multiple fund formula
    Then the multiple fund formula should be invalid with a generate_ytd_qtly error containing "cannot be enabled for GenerateAccountEntryMultiple"

  @rack_test
  Scenario: GenerateAccountEntry formulas are not affected by the multiple names validation
    Given a fund formula with formula "@committed_capital * @fee_rate / 365"
    When I validate the fund formula
    Then the fund formula should be valid

  # ─── Engine level: full allocation run ───

  @rack_test
  Scenario: One formula generates separate entries and fund rollups per name
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund;currency=INR"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=Multiple Test Fund;currency=INR" for the entity
    Given the investors are added to the fund
    # commitment_date must be on/before the run's end_date or get_commitments filters the commitment out
    Given there are capital commitments of "committed_amount_cents=100000000;commitment_date=2023-01-01" from each investor
    And the commitments have the following seed account entries:
      | name            | reporting_date | amount_cents |
      | Management Fees | 2023-06-30     | 100000       |
      | Management Fees | 2024-02-15     | 25000        |
      | Custody Fees    | 2024-01-10     | 10000        |
    And the fund has a GenerateAccountEntryMultiple formula "Quarterly Reporting" with entry type "Reporting" and formula:
      """
      capital_commitment.quarterly(["Management Fees", "Custody Fees"], nil, @start_date, @end_date)
      """
    And the fund formula "Quarterly Reporting" has roll_up enabled
    And the fund has a GenerateAccountEntryMultiple formula "Since Inception Reporting" with entry type "Reporting" and formula:
      """
      capital_commitment.since_inception(["Management Fees", "Custody Fees"], nil, @start_date, @end_date)
      """
    And the fund has a GenerateAccountEntryMultiple formula "Custom Reporting" with entry type "Reporting" and formula:
      """
      capital_commitment.quarterly(["Management Fees"], nil, @start_date, @end_date)
      """
    # meta_data name_prefix must override the method-derived "Quarterly " prefix,
    # and must be applied exactly once (no double-prefixing)
    And the fund formula "Custom Reporting" has meta_data "name_prefix=Custom "
    And the Allocation Run "start_date=01/01/2024;end_date=31/03/2024" is created for the "Multiple Test Fund"
    Then the AllocationRun status is set to "Success"
    And each commitment should have a generated account entry "Quarterly Management Fees" with amount cents "25000"
    And each commitment should have a generated account entry "Quarterly Custody Fees" with amount cents "10000"
    And each commitment should have a generated account entry "Since Inception Management Fees" with amount cents "125000"
    And each commitment should have a generated account entry "Since Inception Custody Fees" with amount cents "10000"
    And the fund should have a cumulative fund level entry "Quarterly Management Fees" with amount cents "50000"
    And the fund should have a cumulative fund level entry "Quarterly Custody Fees" with amount cents "20000"
    And the fund should have a cumulative fund level entry "Since Inception Management Fees" with amount cents "250000"
    And the fund should have a cumulative fund level entry "Since Inception Custody Fees" with amount cents "20000"
    And the generated account entry "Quarterly Custody Fees" explanation should contain:
      """
      capital_commitment.quarterly("Custody Fees", nil, @start_date, @end_date)
      """
    # roll_up=true: commitment-level cumulative rollup per prefixed name
    And each commitment should have a cumulative rollup entry "Quarterly Management Fees" with amount cents "25000"
    And each commitment should have a cumulative rollup entry "Quarterly Custody Fees" with amount cents "10000"
    # meta_data name_prefix override, applied exactly once end-to-end
    And each commitment should have a generated account entry "Custom Management Fees" with amount cents "25000"
    And the fund should have a cumulative fund level entry "Custom Management Fees" with amount cents "50000"
    # Re-run the same period: previous generated entries must be replaced, not duplicated
    And the Allocation Run "start_date=01/01/2024;end_date=31/03/2024" is created for the "Multiple Test Fund"
    Then the AllocationRun status is set to "Success"
    And there should be exactly "2" generated entries named "Quarterly Management Fees"
    And there should be exactly "2" generated entries named "Since Inception Custody Fees"
    And there should be exactly "2" generated entries named "Custom Management Fees"
    And each commitment should have a generated account entry "Quarterly Management Fees" with amount cents "25000"

  @rack_test
  Scenario: Multiple formulas see entries generated earlier in the same run despite memoized period helpers
    # Regression for the fund 54 / allocation run 1812 mismatch: quarterly and
    # since_inception are memoized per commitment instance + arguments
    # (CapitalCommitmentShared), and commitment instances live for the whole run.
    # A generate_ytd_qtly formula earlier in the run calls those helpers with the
    # SAME arguments before its entries reach the scratch DB, memoizing stale
    # sums. The Multiple formulas must flush the memo, otherwise they generate
    # 0 / stale amounts instead of including the freshly generated entries.
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund;currency=INR"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=Memo Test Fund;currency=INR" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "committed_amount_cents=100000000;commitment_date=2023-01-01" from each investor
    And the commitments have the following seed account entries:
      | name            | reporting_date | amount_cents |
      | Management Fees | 2023-12-31     | 40000        |
    And the fund has a GenerateAccountEntry formula "Management Fees" with entry type "Expense" and formula:
      """
      25000
      """
    And the fund formula "Management Fees" has generate_ytd_qtly enabled
    And the fund has a GenerateAccountEntryMultiple formula "Quarterly Reporting" with entry type "Reporting" and formula:
      """
      capital_commitment.quarterly(["Management Fees"], nil, @start_date, @end_date)
      """
    And the fund has a GenerateAccountEntryMultiple formula "Since Inception Reporting" with entry type "Reporting" and formula:
      """
      capital_commitment.since_inception(["Management Fees"], nil, @start_date, @end_date)
      """
    And the Allocation Run "start_date=01/01/2024;end_date=31/03/2024" is created for the "Memo Test Fund"
    Then the AllocationRun status is set to "Success"
    # 25000 is generated by the first formula during this run; 40000 is the
    # seeded prior-quarter entry. Before the memo flush these asserted 0 and
    # 40000 — the stale sums memoized by the generate_ytd_qtly variants.
    And each commitment should have a generated account entry "Quarterly Management Fees" of type "Reporting" with amount cents "25000"
    And each commitment should have a generated account entry "Since Inception Management Fees" of type "Reporting" with amount cents "65000"
