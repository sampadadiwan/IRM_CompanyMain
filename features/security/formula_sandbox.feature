Feature: C2 - stored formulas are evaluated only after an allowlist check of their parse tree
  Fund formulas, run checks, call-fee formulas, Calculation custom fields and the entity expense filter
  are Ruby text evaluated in the app process. FormulaSandbox parses each one (never runs it) with the
  local names of the binding it will run in, and checks every node, method, constant and query root
  against the site's profile (config/formula_sandbox.yml). FORMULA_SANDBOX=off keeps today's behaviour,
  log reports would-be refusals and still evaluates, enforce refuses. KPI computed formulas (N1) are
  folded as numbers, never evaluated, and is_erb notification bodies are filled in without ERB.
  Worked examples: docs/security/security_review_2026_10.md "C2 — Formula engine: allowlist-checked evaluation"

  # C2-1 — Error case: a fund formula that reads another fund's ledger is refused on save in enforce mode
  @security @rack_test
  Scenario: C2-1 A fund formula with an unpinned query root cannot be saved
    Given the formula sandbox mode is "enforce"
    And there is a user "first_name=Gita" for an entity "name=Artha;entity_type=Investment Fund"
    And there is a fund "name=C2 Fund" for the entity
    When I save a "GenerateAccountEntry" fund formula "AccountEntry.where(fund_id: 999).sum(:amount_cents)"
    Then the fund formula is refused by the formula sandbox with "constant call AccountEntry.where (not pinned to fund_id)"

  # C2-2 — Error case: a call-fee formula written past validation (update_column) is refused when it is evaluated
  @security @rack_test
  Scenario: C2-2 A stored call-fee formula using reflection is refused at evaluation
    Given the formula sandbox mode is "enforce"
    And a commitment "id=511;investor_name=Investor A;folio_id=F-511;unit_type=" with no fund unit settings
    And a call fee "Setup Fees" saved without validation with formula "capital_commitment.instance_variable_get(:@attributes)"
    When the call fee formula is calculated for a remittance with call amount 1000000 cents
    Then the call fee formula is refused by the formula sandbox with "denied method instance_variable_get"

  # C2-3 — Error case: dynamic dispatch through try is refused even though the denylist lets it through
  @security @rack_test
  Scenario: C2-3 A call-fee formula calling try is refused at evaluation
    Given the formula sandbox mode is "enforce"
    And a commitment "id=512;investor_name=Investor B;folio_id=F-512;unit_type=" with no fund unit settings
    And a call fee "Setup Fees" saved without validation with formula "capital_remittance.try(:capital_call)"
    When the call fee formula is calculated for a remittance with call amount 1000000 cents
    Then the call fee formula is refused by the formula sandbox with "denied method try"

  # C2-4 — Error case: a Calculation custom field reaching a process-wide constant is refused on save and at evaluation
  @security @rack_test
  Scenario: C2-4 A Calculation custom field calling ObjectSpace is refused on save and at evaluation
    Given the formula sandbox mode is "enforce"
    When I validate a Calculation custom field with meta_data "ObjectSpace.count_objects.size"
    Then the custom field is refused by the formula sandbox with "constant call ObjectSpace.count_objects"
    When the Calculation "ObjectSpace.count_objects.size" is evaluated on a commitment of "committed_amount_cents=1000000"
    Then the custom field evaluation is refused by the formula sandbox

  # C2-5 — Error case: a run check reading a global variable is refused at evaluation
  @security @rack_test
  Scenario: C2-5 A run check reading a global variable is refused
    Given the formula sandbox mode is "enforce"
    When the run check "check!($PROGRAM_NAME.present?, 'no program')" is evaluated for an unsaved fund
    Then the run check is refused by the formula sandbox with "node GlobalVariableReadNode"

  # C2-6 — Error case: text that reads as a method call with a regex argument is checked as the division it is in its binding
  @security @rack_test
  Scenario: C2-6 A formula that only looks safe without its binding's locals is refused
    Given the formula sandbox mode is "enforce"
    And a commitment "id=513;investor_name=Investor C;folio_id=F-513;unit_type=" with no fund unit settings
    And a call fee "Setup Fees" saved without validation with formula "capital_remittance /2; capital_commitment.instance_variable_get(:@attributes) #/"
    When the call fee formula is calculated for a remittance with call amount 1000000 cents
    Then the call fee formula is refused by the formula sandbox with "denied method instance_variable_get"

  # C2-7 — Happy path: the audit reports offenders per entity, site and rule, and writes nothing without EXECUTE=1
  @security @rack_test
  Scenario: C2-7 The formula audit is a dry run by default
    Given there is a user "first_name=Gita" for an entity "name=Artha;entity_type=Investment Fund"
    And there is a fund "name=C2 Audit Fund" for the entity
    And the fund has a stored "GenerateAccountEntry" formula "PortfolioInvestment.where(fund_id: capital_commitment.fund_id).pluck(:id).size"
    When I run the formula sandbox audit
    Then the audit output includes "constant call PortfolioInvestment.where (not pinned to fund_id)"
    And the audit output includes "Dry run — nothing written"
    And the stored formula is still "PortfolioInvestment.where(fund_id: capital_commitment.fund_id).pluck(:id).size"

  # C2-8 — Happy path: log mode logs the would-be refusal and returns exactly the value it returned before
  @security @rack_test
  Scenario: C2-8 Log mode logs a rejection and leaves the result unchanged
    Given the formula sandbox mode is "log"
    And formula sandbox log lines are captured
    And a commitment "id=514;investor_name=Investor D;folio_id=F-514;unit_type=" with no fund unit settings
    And a call fee "Setup Fees" with formula "capital_remittance.call_amount_cents.fdiv(100)"
    When the call fee formula is calculated for a remittance with call amount 1000000 cents
    Then the call fee formula result should be 10000.0
    And the formula sandbox logged "would_reject profile=call_fee"

  # C2-H1 — Happy path: the sample allocation fund still produces generated_account_entries.xlsx with the sandbox enforcing
  @import @rack_test
  Scenario Outline: C2-H1 The sample allocation is unchanged in enforce mode
    Given the formula sandbox mode is "enforce"
    And there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund;currency=INR"
    And the user has role "company_admin"
    And there is a fund "name=Comprehensive Test Fund Aug 2025 - Master Fund;currency=USD;unit_types=A,B,C,D,A4" for the entity
    And there is a fund "name=Comprehensive Test Fund Aug 2025;currency=INR;unit_types=A,B,C,D,A4;master_fund_id=1" for the entity
    And Given import file "allocate_account_entries_2/exchange_rates.xlsx" for "ExchangeRate"
    And Given import file "allocate_account_entries_2/investors.xlsx" for "Investor"
    And Given import file "allocate_account_entries_2/valuations.xlsx" for "Valuation"
    And Given import file "allocate_account_entries_2/fund_unit_settings.xlsx" for "FundUnitSetting"
    And Given import file "allocate_account_entries_2/capital_commitments.xlsx" for "CapitalCommitment"
    And Given import file "allocate_account_entries_2/capital_calls.xlsx" for "CapitalCall"
    And Given import file "allocate_account_entries_2/capital_remittance_payments.xlsx" for "CapitalRemittancePayment"
    And Given import file "allocate_account_entries_2/capital_distributions.xlsx" for "CapitalDistribution"
    And Given import file "allocate_account_entries_2/portfolio_investments.xlsx" for "PortfolioInvestment"
    And Given import file "allocate_account_entries_2/account_entries.xlsx" for "AccountEntry"
    And Given import file "allocate_account_entries_2/fund_formulas.xlsx" for "FundFormula"
    And the Allocation Run "<allocation_run>" is created for the "Comprehensive Test Fund Aug 2025"
    Then the account entries generated match the account entries in "allocate_account_entries_2/generated_account_entries.xlsx"
    And the AllocationRun status is set to "Success"

    Examples:
      | allocation_run                             |
      | start_date=01/04/2023;end_date=30/06/2024, |

  # C2-H2 — Happy path: a call-fee formula gives the same value in enforce mode
  @security @rack_test
  Scenario: C2-H2 A call-fee formula is unchanged in enforce mode
    Given the formula sandbox mode is "enforce"
    And a commitment "id=515;investor_name=Investor E;folio_id=F-515;unit_type=" with no fund unit settings
    And a call fee "Setup Fees" with formula "capital_remittance.call_amount_cents * 2 / 100.0"
    When the call fee formula is calculated for a remittance with call amount 1000000 cents
    Then the call fee formula result should be 20000.0

  # C2-H3 — Happy path: a GenerateCustomField formula still writes the commitment's own custom field in enforce mode
  @security @rack_test
  Scenario: C2-H3 A GenerateCustomField formula is unchanged in enforce mode
    Given the formula sandbox mode is "enforce"
    When the allocation engine evaluates "capital_commitment.json_fields['c2_flag'] = 'yes'; capital_commitment.committed_amount_cents / 100" with profile "custom_field" for a commitment of "committed_amount_cents=1000000"
    Then the allocation engine result is "10000"
    And the commitment custom field "c2_flag" is "yes"

  # C2-H4 — Happy path: a pre-run check passes and fails exactly as before in enforce mode
  @security @rack_test
  Scenario: C2-H4 A run check is unchanged in enforce mode
    Given the formula sandbox mode is "enforce"
    When the run check "check!(@fund.present?, 'Fund missing')" is evaluated for an unsaved fund
    Then the run check result is "true"
    When the run check "check!(@fund.nil?, 'Fund missing')" is evaluated for an unsaved fund
    Then the run check failed with "Fund missing"

  # C2-H5 — Happy path: widget metadata (C1) is read the same way whatever the sandbox mode
  @security @rack_test
  Scenario: C2-H5 Widget metadata is unchanged in enforce mode
    Given the formula sandbox mode is "enforce"
    Then the widget metadata "{months: 12, ratio_names: %w[XIRR TVPI]}" reads as '{"months":12,"ratio_names":["XIRR","TVPI"]}'

  # C2-H6 — Happy path: a Calculation custom field gives the same value in enforce mode as in off mode
  @security @rack_test
  Scenario: C2-H6 A Calculation custom field is unchanged in enforce mode
    Given the formula sandbox mode is "off"
    When the Calculation "(committed_amount_cents * 25 / 100.0).round(2)" is evaluated on a commitment of "committed_amount_cents=1000000"
    Then the custom field value is "250000.0"
    Given the formula sandbox mode is "enforce"
    When the Calculation "(committed_amount_cents * 25 / 100.0).round(2)" is evaluated on a commitment of "committed_amount_cents=1000000"
    Then the custom field value is "250000.0"

  # C2-H7 — Happy path: the explain breakdown of a formula is identical in off and enforce mode
  @security @rack_test
  Scenario: C2-H7 The formula explanation is unchanged in enforce mode
    Given the formula sandbox mode is "off"
    When the formula "fee = capital_commitment.committed_amount_cents * 2 / 100; fee + 1" is explained for a commitment of "committed_amount_cents=1000000"
    And I keep the explanation
    Given the formula sandbox mode is "enforce"
    When the formula "fee = capital_commitment.committed_amount_cents * 2 / 100; fee + 1" is explained for a commitment of "committed_amount_cents=1000000"
    Then the explanation equals the kept one
    And the explanation includes "fee" with "20000"

  # C2-H8 — Happy path: KPI computed formulas are folded as numbers with the same results, integer division included (N1)
  @security @rack_test
  Scenario: C2-H8 KPI computed formulas give the same values without eval
    Then the KPI formula " 120.0+-35.0+7.0" folds to "92.0"
    And the KPI formula "7.0/92.0" folds to "0.07608695652173914"
    And the KPI formula "1000000.0/0.0" folds to "Infinity"
    And the KPI formula "7 / 2" folds to "3"
    And the KPI formula "2 ** 99999999" is refused as not numeric

  # C2-X1 — Edge case: the same text is a different tree with different locals, and the cache keeps them apart
  @security @rack_test
  Scenario: C2-X1 The check cache is keyed by the binding's locals
    Then the text "fund_unit_setting.management_fee" checked with profile "fund_formula" and locals "" is refused with "unknown name fund_unit_setting"
    And the text "fund_unit_setting.management_fee" checked with profile "fund_formula" and locals "fund_unit_setting" passes
    And the text "fund_unit_setting.management_fee" checked with profile "fund_formula" and locals "" is refused with "unknown name fund_unit_setting"

  # C2-X2 — Edge case: a Cumulate formula holds entry names, which are never treated as code
  @security @rack_test
  Scenario: C2-X2 Cumulate entry names are not checked as code
    Given the formula sandbox mode is "enforce"
    And there is a user "first_name=Gita" for an entity "name=Artha;entity_type=Investment Fund"
    And there is a fund "name=C2 Fund" for the entity
    When I save a "CumulateAccountEntry" fund formula "Fees - Setup (Q1)"
    Then the fund formula is saved

  # C2-X3 — Edge case: a mistyped formula keeps the existing syntax-error messages in enforce mode
  @security @rack_test
  Scenario: C2-X3 The existing syntax-error message is kept
    Given the formula sandbox mode is "enforce"
    And there is a user "first_name=Gita" for an entity "name=Artha;entity_type=Investment Fund"
    And there is a fund "name=C2 Fund" for the entity
    When I save a "GenerateAccountEntry" fund formula "capital_commitment.committed_amount_cents * ("
    Then the fund formula is refused with "has invalid Ruby syntax"
    And the fund formula has no formula sandbox error
    Given a commitment "id=516;investor_name=Investor F;folio_id=F-516;unit_type=" with no fund unit settings
    And a call fee "Setup Fees" with formula "capital_remittance.call_amount_cents * ("
    When the call fee formula is calculated for a remittance with call amount 1000000 cents
    Then the call fee formula should fail with a FormulaError containing "SyntaxError"

  # C2-X4 — Edge case: off mode is today's behaviour: a formula outside the allowlist saves and evaluates, nothing is logged
  @security @rack_test
  Scenario: C2-X4 Off mode does not check
    Given the formula sandbox mode is "off"
    And formula sandbox log lines are captured
    And a commitment "id=517;investor_name=Investor G;folio_id=F-517;unit_type=" with no fund unit settings
    And a call fee "Setup Fees" with formula "capital_remittance.call_amount_cents.fdiv(100)"
    When the call fee formula is calculated for a remittance with call amount 1000000 cents
    Then the call fee formula result should be 10000.0
    And the formula sandbox logged nothing

  # C2-X5 — Edge case: a mistyped mode value checks and logs like log mode, never breaking a run
  @security @rack_test
  Scenario: C2-X5 An unknown mode value behaves as log
    Given the formula sandbox mode is "enforced"
    Then the formula sandbox mode in effect is "log"

  # C2-X6 — Edge case: only where's first argument is SQL; LIKE bind values are data
  @security @rack_test
  Scenario: C2-X6 LIKE bind values are not treated as SQL
    Then the text "capital_commitment.account_entries.where('name LIKE ?', '%usd').sum(:amount_cents)" checked with profile "fund_formula" and locals "capital_commitment" passes
    And the text "capital_commitment.account_entries.where(\"name LIKE '%usd'\").sum(:amount_cents)" checked with profile "fund_formula" and locals "capital_commitment" is refused with "raw SQL where"
    And the text "capital_commitment.account_entries.where('1=1) UNION SELECT 1 --').sum(:amount_cents)" checked with profile "fund_formula" and locals "capital_commitment" is refused with "raw SQL where"

  # C2-X7 — Edge case: a query root must be pinned to the formula's own fund, and a constant cannot be passed around
  @security @rack_test
  Scenario: C2-X7 Query roots are pinned to the fund
    Then the text "AccountEntry.where(fund_id: @fund.id).sum(:amount_cents)" checked with profile "fund_formula" and locals "" passes
    And the text "ExchangeRate.where(entity_id: @fund.entity_id).last" checked with profile "fund_formula" and locals "" passes
    And the text "AccountEntry.where(fund_id: 5).sum(:amount_cents)" checked with profile "fund_formula" and locals "" is refused with "not pinned to fund_id"
    And the text "root = AccountEntry; root.where(fund_id: 5).count" checked with profile "fund_formula" and locals "" is refused with "bare constant AccountEntry"

  # C2-X8 — Edge case: local start_date / end_date may be narrowed; the engine's own values may not be replaced or shadowed
  @security @rack_test
  Scenario: C2-X8 Reserved names cannot be written
    Then the text "end_date = end_date - 30; end_date" checked with profile "fund_formula" and locals "end_date" passes
    And the text "@end_date = nil" checked with profile "fund_formula" and locals "" is refused with "write to reserved @end_date"
    And the text "[1].map { |fund| AccountEntry.where(fund_id: fund.id).count }" checked with profile "fund_formula" and locals "fund" is refused with "write to reserved fund"

  # C2-X9 — Edge case: return and puts are allowed; rescue is not
  @security @rack_test
  Scenario: C2-X9 Control flow allowed and refused
    Then the text "return 0 if capital_commitment.nil?; puts 'debug'; 1" checked with profile "fund_formula" and locals "capital_commitment" passes
    And the text "begin; 1; rescue; 2; end" checked with profile "fund_formula" and locals "" is refused with "node RescueNode"

  # C2-X10 — Edge case: any custom field name reads through custom_fields, but Object's own methods do not
  @security @rack_test
  Scenario: C2-X10 Custom field readers versus Object methods
    Then the text "capital_commitment.custom_fields.code_b.to_d" checked with profile "fund_formula" and locals "capital_commitment" passes
    And the text "capital_commitment.custom_fields.display" checked with profile "fund_formula" and locals "capital_commitment" is refused with "method display"

  # C2-X11 — Edge case: an is_erb body renders its two known tags as values and any other tag as text, without ERB
  @security @rack_test
  Scenario: C2-X11 An is_erb notification body is never evaluated
    When the is_erb body "Dear &lt;%= @investor_kyc.full_name %&gt;, see &lt;%= ENV.store('C2_X11', 'ran') %&gt;" is rendered for KYC "Asha <b>Rao</b>"
    Then the rendered body includes "Dear Asha &lt;b&gt;Rao&lt;/b&gt;,"
    And the rendered body includes "&lt;%= ENV.store(&#39;C2_X11&#39;, &#39;ran&#39;) %&gt;"
    And the ERB tag in the body was not run

  # C2-X12 — Edge case: EXECUTE=1 backs every row up to JSONL first, then pins the query root to the fund
  @security @rack_test
  Scenario: C2-X12 The audit's mechanical rewrite runs only with EXECUTE=1, after a backup
    Given there is a user "first_name=Gita" for an entity "name=Artha;entity_type=Investment Fund"
    And there is a fund "name=C2 Audit Fund" for the entity
    And the fund has a stored "GenerateAccountEntry" formula "PortfolioInvestment.where(fund_id: capital_commitment.fund_id).pluck(:id).size"
    When I run the formula sandbox audit with EXECUTE=1
    Then the audit output includes "backup written"
    And the audit backup holds the formula before "PortfolioInvestment.where(fund_id: capital_commitment.fund_id).pluck(:id).size"
    And the stored formula is still "PortfolioInvestment.where(fund_id: @fund.id).pluck(:id).size"

  # C2-X13 — Edge case: a portfolio-numbers field map is read as a literal; a map that is not one is refused in enforce mode
  @security @rack_test
  Scenario: C2-X13 The GeneratePortfolioNumbersForFund field map is never evaluated in enforce mode
    Given the formula sandbox mode is "enforce"
    Then the portfolio numbers field map '{"FMV" => :fmv_cents}' reads as '{"FMV":"fmv_cents"}'
    And the portfolio numbers field map '{"FMV" => :fmv_cents.to_proc}' is refused
