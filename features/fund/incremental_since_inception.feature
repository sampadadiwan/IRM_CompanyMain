Feature: Incremental since_inception allocation
  A fund with json_fields incremental_since_inception = true is allocated from a trimmed scratch
  copy of its account entries (rows since the financial-year start, uploaded rows, and the latest
  row per key before that), so since_inception cannot re-sum all history. It carries forward the
  previous run's stored "Since Inception <name>" total and adds the movement after it instead.
  See docs/modules/allocation/incremental_allocation_history.md section 12.

  Every scenario runs October 2024 on a fund with an April financial year, so the copy keeps
  rows from 2024-04-01.

  Background:
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund;currency=INR"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=Incremental Fund;currency=INR" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "committed_amount_cents=100000000;commitment_date=2023-01-01" from each investor

  @rack_test
  Scenario: The stored total is carried forward instead of re-summing history
    # The stored total is deliberately NOT the sum of the fees before it (10000 + 20000), which
    # proves the helper reads it rather than recomputing.
    Given the fund allocates incrementally
    And the commitments have the following seed account entries:
      | name                           | reporting_date | amount_cents | generated |
      | Management Fees                | 2023-06-30     | 10000        | true      |
      | Management Fees                | 2024-09-30     | 20000        | true      |
      | Since Inception Management Fees | 2024-09-30    | 99000        | true      |
      | Management Fees                | 2024-10-15     | 5000         | true      |
    And the fund has a GenerateAccountEntry formula "Since Inception Management Fees" with entry type "Reporting" and formula:
      """
      capital_commitment.since_inception("Management Fees", nil, @start_date, @end_date)
      """
    And the Allocation Run "start_date=01/10/2024;end_date=31/10/2024" is created for the "Incremental Fund"
    Then the AllocationRun status is set to "Success"
    And each commitment should have a generated account entry "Since Inception Management Fees" with amount cents "104000"

  @rack_test
  Scenario: A fund without the flag still re-sums all history
    Given the fund has an April financial year
    And the commitments have the following seed account entries:
      | name                           | reporting_date | amount_cents | generated |
      | Management Fees                | 2023-06-30     | 10000        | true      |
      | Management Fees                | 2024-09-30     | 20000        | true      |
      | Since Inception Management Fees | 2024-09-30    | 99000        | true      |
      | Management Fees                | 2024-10-15     | 5000         | true      |
    And the fund has a GenerateAccountEntry formula "Since Inception Management Fees" with entry type "Reporting" and formula:
      """
      capital_commitment.since_inception("Management Fees", nil, @start_date, @end_date)
      """
    And the Allocation Run "start_date=01/10/2024;end_date=31/10/2024" is created for the "Incremental Fund"
    Then the AllocationRun status is set to "Success"
    And each commitment should have a generated account entry "Since Inception Management Fees" with amount cents "35000"

  @rack_test
  Scenario: Days between the stored total and the window are added
    # Stored total at 31 Aug; the 15 Sep fee falls in neither the stored total nor the window.
    Given the fund allocates incrementally
    And the commitments have the following seed account entries:
      | name                           | reporting_date | amount_cents | generated |
      | Management Fees                | 2023-06-30     | 10000        | true      |
      | Since Inception Management Fees | 2024-08-31    | 99000        | true      |
      | Management Fees                | 2024-09-15     | 20000        | true      |
      | Management Fees                | 2024-10-15     | 5000         | true      |
    And the fund has a GenerateAccountEntry formula "Since Inception Management Fees" with entry type "Reporting" and formula:
      """
      capital_commitment.since_inception("Management Fees", nil, @start_date, @end_date)
      """
    And the Allocation Run "start_date=01/10/2024;end_date=31/10/2024" is created for the "Incremental Fund"
    Then the AllocationRun status is set to "Success"
    And each commitment should have a generated account entry "Since Inception Management Fees" with amount cents "124000"

  Scenario: Earlier entries without a stored total fail the run
    # Summing only what the trimmed copy holds would silently understate the total.
    Given the fund allocates incrementally
    And the commitments have the following seed account entries:
      | name            | reporting_date | amount_cents | generated |
      | Management Fees | 2023-06-30     | 10000        | true      |
      | Management Fees | 2024-10-15     | 5000         | true      |
    And the fund has a GenerateAccountEntry formula "Since Inception Management Fees" with entry type "Reporting" and formula:
      """
      capital_commitment.since_inception("Management Fees", nil, @start_date, @end_date)
      """
    Then running the Allocation Run "start_date=01/10/2024;end_date=31/10/2024" for the "Incremental Fund" should fail with "No 'Since Inception Management Fees' entry before 2024-10-01"

  @rack_test
  Scenario: A commitment with no earlier entries needs no stored total
    Given the fund allocates incrementally
    And the commitments have the following seed account entries:
      | name            | reporting_date | amount_cents | generated |
      | Management Fees | 2024-10-15     | 5000         | true      |
    And the fund has a GenerateAccountEntry formula "Since Inception Management Fees" with entry type "Reporting" and formula:
      """
      capital_commitment.since_inception("Management Fees", nil, @start_date, @end_date)
      """
    And the Allocation Run "start_date=01/10/2024;end_date=31/10/2024" is created for the "Incremental Fund"
    Then the AllocationRun status is set to "Success"
    And each commitment should have a generated account entry "Since Inception Management Fees" with amount cents "5000"

  @rack_test
  Scenario: A formula totalling several names carries forward its own stored total
    Given the fund allocates incrementally
    And the commitments have the following seed account entries:
      | name                 | reporting_date | amount_cents | generated |
      | Fee A                | 2023-06-30     | 10000        | true      |
      | Fee B                | 2023-06-30     | 20000        | true      |
      | Since Inception Fees | 2024-09-30     | 50000        | true      |
      | Fee A                | 2024-10-15     | 1000         | true      |
      | Fee B                | 2024-10-15     | 2000         | true      |
    And the fund has a GenerateAccountEntry formula "Since Inception Fees" with entry type "Reporting" and formula:
      """
      capital_commitment.since_inception(["Fee A", "Fee B"], nil, @start_date, @end_date, carry_forward_name: fund_formula.name)
      """
    And the Allocation Run "start_date=01/10/2024;end_date=31/10/2024" is created for the "Incremental Fund"
    Then the AllocationRun status is set to "Success"
    And each commitment should have a generated account entry "Since Inception Fees" with amount cents "53000"

  Scenario Outline: The scratch copy drops old generated rows except the latest per key
    # Old Fee: three rows before the 2024-04-01 floor and one after. The trimmed copy keeps the
    # latest before the floor (2024-01-31) and the one after. Uploaded rows are always kept.
    Given <fund setup>
    And the commitments have the following seed account entries:
      | name         | reporting_date | amount_cents | generated |
      | Old Fee      | 2023-05-31     | 100          | true      |
      | Old Fee      | 2023-06-30     | 100          | true      |
      | Old Fee      | 2024-01-31     | 100          | true      |
      | Old Fee      | 2024-05-31     | 100          | true      |
      | Uploaded Fee | 2020-01-31     | 100          | false     |
    And the fund has a GenerateAccountEntry formula "Old Fee Rows" with entry type "Reporting" and formula:
      """
      capital_commitment.account_entries.where(name: "Old Fee").count
      """
    And the fund has a GenerateAccountEntry formula "Uploaded Fee Rows" with entry type "Reporting" and formula:
      """
      capital_commitment.account_entries.where(name: "Uploaded Fee").count
      """
    And the Allocation Run "start_date=01/10/2024;end_date=31/10/2024" is created for the "Incremental Fund"
    Then the AllocationRun status is set to "Success"
    And each commitment should have a generated account entry "Old Fee Rows" with amount cents "<old rows>"
    And each commitment should have a generated account entry "Uploaded Fee Rows" with amount cents "1"

    Examples:
      | fund setup                        | old rows |
      | the fund allocates incrementally  | 2        |
      | the fund has an April financial year | 4     |
