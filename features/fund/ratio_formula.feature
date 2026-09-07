Feature: Ratio Formula Management
  As a fund manager
  I want to define custom rules for financial ratios
  So that I can include specific account entries in my performance metrics

  Background:
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund;currency=INR"
    Given the user has role "company_admin"
    Given there is a fund "name=Demo Fund 2;currency=INR;unit_types=A1,A2" for the entity

  @import
  Scenario: Custom rule affects XIRR calculation
    Given Im logged in as user "Test"
    # Re-use working setup from existing tests
    And Given import file "fund_ratios/exchange_rates.xlsx" for "ExchangeRate"
    And Given import file "fund_ratios/investors.xlsx" for "Investor"
    And Given import file "fund_ratios/valuations.xlsx" for "Valuation"
    And Given import file "fund_ratios/investor_kycs.xlsx" for "InvestorKyc"
    And Given import file "fund_ratios/capital_commitments.xlsx" for "CapitalCommitment"
    And Given import file "fund_ratios/capital_distributions.xlsx" for "CapitalDistribution"
    And Given import file "fund_ratios/portfolio_investments.xlsx" for "PortfolioInvestment"
    And Given import file "fund_ratios/account_entries.xlsx" for "AccountEntry"
    And Given import file "fund_ratios/capital_calls.xlsx" for "CapitalCall"
    And Given import file "fund_ratios/capital_remittance_payments.xlsx" for "CapitalRemittancePayment"

    # Create the rule via factory/model
    Given there is a RatioFormula for the fund "Demo Fund 2" with "level=Fund;action=add_cashflow;ratio=XIRR;account_entry_names=Custom Inflow;period=all"

    # Add the custom entry that should be picked up by the formula
    And there is an AccountEntry "name=Custom Inflow;amount_cents=100000000;reporting_date=2024-01-01;entry_type=Income" for the fund

    When given the fund_ratios are computed for the date "31-03-2024"
    Then the FundRatio "XIRR" should be different from a computation without the formula



@import
Scenario Outline: Compute KYC Fund Ratios with ratio formulas
  Given The fund has kyc level data generation enabled
  And Given import file "kyc_fund_ratios/exchange_rates.xlsx" for "ExchangeRate"
  And Given import file "kyc_fund_ratios/investors.xlsx" for "Investor"
  And Given import file "kyc_fund_ratios/valuations.xlsx" for "Valuation"
  And Given import file "kyc_fund_ratios/investor_kycs.xlsx" for "InvestorKyc"
  And Given import file "kyc_fund_ratios/capital_commitments.xlsx" for "CapitalCommitment"
  And Given import file "kyc_fund_ratios/capital_distributions.xlsx" for "CapitalDistribution"
  And Given import file "kyc_fund_ratios/portfolio_investments.xlsx" for "PortfolioInvestment"
  And Given import file "kyc_fund_ratios/account_entries.xlsx" for "AccountEntry"
  And Given import file "kyc_fund_ratios/capital_calls.xlsx" for "CapitalCall"
  Given the capital calls are approved
  And Given import file "kyc_fund_ratios/capital_remittance_payments.xlsx" for "CapitalRemittancePayment"
  Given the second commitment of the kyc has custom_fields "skip_doc_gen:yes"
  Given the KYC has commitments in different funds also

  Given there is a RatioFormula for the fund "Demo Fund 2" with "level=Fund;action=add_cashflow;ratio=XIRR;account_entry_names=Custom Inflow;period=all"
  Given there is a RatioFormula for the fund "Demo Fund 2" with "level=Fund;action=reduce_cashflow;ratio=XIRR;account_entry_names=Custom Outflow,Custom Outflow1;period=all"
  Given there is a RatioFormula for the fund "Demo Fund 2" with "level=Folio;action=add_cashflow;ratio=XIRR;account_entry_names=Custom Inflow;period=all"
  Given there is a RatioFormula for the fund "Demo Fund 2" with "level=Folio;action=reduce_cashflow;ratio=XIRR;account_entry_names=Custom Outflow,Custom Outflow1;period=all"
  Given there is a RatioFormula for the fund "Demo Fund 2" with "level=PortfolioCompany;action=add_cashflow;ratio=XIRR;account_entry_names=Custom Inflow;period=all"


  # Add the custom entry that should be picked up by the formula
  And there is an AccountEntry "name=Custom Inflow;amount_cents=110000000;reporting_date=2024-01-01;entry_type=Income" for the fund
  And there is an AccountEntry "name=Custom Outflow;amount_cents=50000000;reporting_date=2024-01-01;entry_type=Income" for the fund
  And there is an AccountEntry "name=Custom Outflow1;amount_cents=20000000;reporting_date=2024-01-01;entry_type=Income" for the fund
  # AE for Comm 1
  And there is an AccountEntry "name=Custom Inflow;amount_cents=110000000;reporting_date=2024-01-01;entry_type=Income;capital_commitment_id=1;folio_id=TSTF21" for the fund
  And there is an AccountEntry "name=Custom Outflow;amount_cents=50000000;reporting_date=2024-01-01;entry_type=Income;capital_commitment_id=1;folio_id=TSTF21" for the fund
  And there is an AccountEntry "name=Custom Outflow1;amount_cents=20000000;reporting_date=2024-01-01;entry_type=Income;capital_commitment_id=1;folio_id=TSTF21" for the fund
  # AE for Comm 2
  And there is an AccountEntry "name=Custom Inflow;amount_cents=110000000;reporting_date=2024-01-01;entry_type=Income;capital_commitment_id=2;folio_id=TSTF23" for the fund
  And there is an AccountEntry "name=Custom Outflow;amount_cents=50000000;reporting_date=2024-01-01;entry_type=Income;capital_commitment_id=2;folio_id=TSTF23" for the fund
  And there is an AccountEntry "name=Custom Outflow1;amount_cents=20000000;reporting_date=2024-01-01;entry_type=Income;capital_commitment_id=2;folio_id=TSTF23" for the fund
  # AE for Comm 3
  And there is an AccountEntry "name=Custom Inflow;amount_cents=110000000;reporting_date=2024-01-01;entry_type=Income;capital_commitment_id=3;folio_id=TSTF22" for the fund
  And there is an AccountEntry "name=Custom Outflow;amount_cents=50000000;reporting_date=2024-01-01;entry_type=Income;capital_commitment_id=3;folio_id=TSTF22" for the fund
  And there is an AccountEntry "name=Custom Outflow1;amount_cents=20000000;reporting_date=2024-01-01;entry_type=Income;capital_commitment_id=3;folio_id=TSTF22" for the fund


  # add_numerator reduce_numerator add_denominator reduce_denominator
  Given there is a RatioFormula for the fund "Demo Fund 2" with "level=Fund;action=add_numerator;ratio=RVPI;account_entry_names=Custom Inflow;period=all"
  Given there is a RatioFormula for the fund "Demo Fund 2" with "level=Fund;action=reduce_numerator;ratio=TVPI;account_entry_names=Custom Outflow,Custom Outflow1;period=all"
  Given there is a RatioFormula for the fund "Demo Fund 2" with "level=Fund;action=add_denominator;ratio=DPI;account_entry_names=Custom Outflow;period=all"
  Given there is a RatioFormula for the fund "Demo Fund 2" with "level=Folio;action=add_numerator;ratio=RVPI;account_entry_names=Custom Inflow;period=all"
  Given there is a RatioFormula for the fund "Demo Fund 2" with "level=Folio;action=add_denominator;ratio=TVPI;account_entry_names=Custom Inflow;period=all"
  Given there is a RatioFormula for the fund "Demo Fund 2" with "level=Folio;action=reduce_denominator;ratio=DPI;account_entry_names=Custom Outflow;period=all"

  Given I inspect the ratio formulas
  And given the fund_ratios are computed for the date "31-03-2024"
  Then KYC ratios must be computed for the commitments except for commitment with skip_doc_gen
  Then the fund ratios computed must match the ratios in "kyc_fund_ratios/formula_fund_ratios.xlsx"
  And the cashflow CSV documents should be created for the fund ratios

@import
Scenario Outline: Compute KYC Fund Ratios with ratio formulas with labels
  Given The fund has kyc level data generation enabled
  And Given import file "kyc_fund_ratios/exchange_rates.xlsx" for "ExchangeRate"
  And Given import file "kyc_fund_ratios/investors.xlsx" for "Investor"
  And Given import file "kyc_fund_ratios/valuations.xlsx" for "Valuation"
  And Given import file "kyc_fund_ratios/investor_kycs.xlsx" for "InvestorKyc"
  And Given import file "kyc_fund_ratios/capital_commitments.xlsx" for "CapitalCommitment"
  And Given import file "kyc_fund_ratios/capital_distributions.xlsx" for "CapitalDistribution"
  And Given import file "kyc_fund_ratios/portfolio_investments.xlsx" for "PortfolioInvestment"
  And Given import file "kyc_fund_ratios/account_entries.xlsx" for "AccountEntry"
  And Given import file "kyc_fund_ratios/capital_calls.xlsx" for "CapitalCall"
  Given the capital calls are approved
  And Given import file "kyc_fund_ratios/capital_remittance_payments.xlsx" for "CapitalRemittancePayment"
  Given the second commitment of the kyc has custom_fields "skip_doc_gen:yes"
  Given the KYC has commitments in different funds also

  Given there is a RatioFormula for the fund "Demo Fund 2" with "level=Fund;action=add_cashflow;ratio=XIRR;account_entry_names=Custom Inflow;period=all"
  Given there is a RatioFormula for the fund "Demo Fund 2" with "level=Fund;action=reduce_cashflow;ratio=XIRR;account_entry_names=Custom Outflow,Custom Outflow1;period=all"
  Given there is a RatioFormula for the fund "Demo Fund 2" with "level=Folio;action=add_cashflow;ratio=XIRR;account_entry_names=Custom Inflow;period=all"
  Given there is a RatioFormula for the fund "Demo Fund 2" with "level=Folio;action=reduce_cashflow;ratio=XIRR;account_entry_names=Custom Outflow,Custom Outflow1;period=all"
  Given there is a RatioFormula for the fund "Demo Fund 2" with "level=PortfolioCompany;action=add_cashflow;ratio=XIRR;account_entry_names=Custom Inflow;period=all"
  Given there is a RatioFormula for the fund "Demo Fund 2" with "level=Fund;action=add_cashflow;ratio=XIRR;account_entry_names=Custom Outflow;period=all;label=xirr outflow"
  Given there is a RatioFormula for the fund "Demo Fund 2" with "level=Folio;action=add_cashflow;ratio=XIRR;account_entry_names=Custom Inflow;period=all;label=xirr folio label test"
  Given there is a RatioFormula for the fund "Demo Fund 2" with "level=PortfolioCompany;action=add_cashflow;ratio=XIRR;account_entry_names=Custom Inflow;period=all;label=xirr pc label test"

  # Gross Portfolio IRR is a Fund-level, cashflow-based ratio (like XIRR): an unlabeled formula
  # adjusts the default Gross Portfolio IRR, and a labeled one produces a separate labelled ratio.
  Given there is a RatioFormula for the fund "Demo Fund 2" with "level=Fund;action=add_cashflow;ratio=Gross Portfolio IRR;account_entry_names=Custom Inflow;period=all"
  Given there is a RatioFormula for the fund "Demo Fund 2" with "level=Fund;action=add_cashflow;ratio=Gross Portfolio IRR;account_entry_names=Custom Outflow;period=all;label=gross portfolio irr label"


  # Add the custom entry that should be picked up by the formula
  And there is an AccountEntry "name=Custom Inflow;amount_cents=110000000;reporting_date=2024-01-01;entry_type=Income" for the fund
  And there is an AccountEntry "name=Custom Outflow;amount_cents=50000000;reporting_date=2024-01-01;entry_type=Income" for the fund
  And there is an AccountEntry "name=Custom Outflow1;amount_cents=20000000;reporting_date=2024-01-01;entry_type=Income" for the fund
  # AE for Comm 1
  And there is an AccountEntry "name=Custom Inflow;amount_cents=110000000;reporting_date=2024-01-01;entry_type=Income;capital_commitment_id=1;folio_id=TSTF21" for the fund
  And there is an AccountEntry "name=Custom Outflow;amount_cents=50000000;reporting_date=2024-01-01;entry_type=Income;capital_commitment_id=1;folio_id=TSTF21" for the fund
  And there is an AccountEntry "name=Custom Outflow1;amount_cents=20000000;reporting_date=2024-01-01;entry_type=Income;capital_commitment_id=1;folio_id=TSTF21" for the fund
  # AE for Comm 2
  And there is an AccountEntry "name=Custom Inflow;amount_cents=110000000;reporting_date=2024-01-01;entry_type=Income;capital_commitment_id=2;folio_id=TSTF23" for the fund
  And there is an AccountEntry "name=Custom Outflow;amount_cents=50000000;reporting_date=2024-01-01;entry_type=Income;capital_commitment_id=2;folio_id=TSTF23" for the fund
  And there is an AccountEntry "name=Custom Outflow1;amount_cents=20000000;reporting_date=2024-01-01;entry_type=Income;capital_commitment_id=2;folio_id=TSTF23" for the fund
  # AE for Comm 3
  And there is an AccountEntry "name=Custom Inflow;amount_cents=110000000;reporting_date=2024-01-01;entry_type=Income;capital_commitment_id=3;folio_id=TSTF22" for the fund
  And there is an AccountEntry "name=Custom Outflow;amount_cents=50000000;reporting_date=2024-01-01;entry_type=Income;capital_commitment_id=3;folio_id=TSTF22" for the fund
  And there is an AccountEntry "name=Custom Outflow1;amount_cents=20000000;reporting_date=2024-01-01;entry_type=Income;capital_commitment_id=3;folio_id=TSTF22" for the fund


  # add_numerator reduce_numerator add_denominator reduce_denominator
  Given there is a RatioFormula for the fund "Demo Fund 2" with "level=Fund;action=add_numerator;ratio=RVPI;account_entry_names=Custom Inflow;period=all"
  Given there is a RatioFormula for the fund "Demo Fund 2" with "level=Fund;action=reduce_numerator;ratio=TVPI;account_entry_names=Custom Outflow,Custom Outflow1;period=all"
  Given there is a RatioFormula for the fund "Demo Fund 2" with "level=Fund;action=add_denominator;ratio=DPI;account_entry_names=Custom Outflow;period=all"

  Given there is a RatioFormula for the fund "Demo Fund 2" with "level=Fund;action=add_denominator;ratio=DPI;account_entry_names=Custom Outflow;period=all;label=fund dpi label"

  Given there is a RatioFormula for the fund "Demo Fund 2" with "level=Folio;action=add_numerator;ratio=RVPI;account_entry_names=Custom Inflow;period=all"
  Given there is a RatioFormula for the fund "Demo Fund 2" with "level=Folio;action=add_denominator;ratio=TVPI;account_entry_names=Custom Inflow;period=all"
  Given there is a RatioFormula for the fund "Demo Fund 2" with "level=Folio;action=reduce_denominator;ratio=DPI;account_entry_names=Custom Outflow;period=all"
  Given there is a RatioFormula for the fund "Demo Fund 2" with "level=Folio;action=reduce_denominator;ratio=DPI;account_entry_names=Custom Outflow;period=all;label=folio dpi label"
  Given there is a RatioFormula for the fund "Demo Fund 2" with "level=Folio;action=reduce_denominator;ratio=DPI;account_entry_names=Custom Outflow;period=all;label=folio dpi label"


  Given I inspect the ratio formulas
  And given the fund_ratios are computed for the date "31-03-2024"
  Then KYC ratios must be computed for the commitments except for commitment with skip_doc_gen
  Then the fund ratios computed must match the ratios in "kyc_fund_ratios/formula_fund_ratios_labels.xlsx"
  And the same owner should not have multiple ratios with same label
  And the cashflow CSV documents should be created for the fund ratios

@import
Scenario Outline: Compute KYC Fund Ratios with skip_portfolio_fmv ratio formulas
  Given The fund has kyc level data generation enabled
  And Given import file "kyc_fund_ratios/exchange_rates.xlsx" for "ExchangeRate"
  And Given import file "kyc_fund_ratios/investors.xlsx" for "Investor"
  And Given import file "kyc_fund_ratios/valuations.xlsx" for "Valuation"
  And Given import file "kyc_fund_ratios/investor_kycs.xlsx" for "InvestorKyc"
  And Given import file "kyc_fund_ratios/capital_commitments.xlsx" for "CapitalCommitment"
  And Given import file "kyc_fund_ratios/capital_distributions.xlsx" for "CapitalDistribution"
  And Given import file "kyc_fund_ratios/portfolio_investments.xlsx" for "PortfolioInvestment"
  And Given import file "kyc_fund_ratios/account_entries.xlsx" for "AccountEntry"
  And Given import file "kyc_fund_ratios/capital_calls.xlsx" for "CapitalCall"
  Given the capital calls are approved
  And Given import file "kyc_fund_ratios/capital_remittance_payments.xlsx" for "CapitalRemittancePayment"
  Given the second commitment of the kyc has custom_fields "skip_doc_gen:yes"
  Given the KYC has commitments in different funds also

  # Base (unlabeled) XIRR formulas, same as the other KYC scenarios
  Given there is a RatioFormula for the fund "Demo Fund 2" with "level=Fund;action=add_cashflow;ratio=XIRR;account_entry_names=Custom Inflow;period=all"
  Given there is a RatioFormula for the fund "Demo Fund 2" with "level=Fund;action=reduce_cashflow;ratio=XIRR;account_entry_names=Custom Outflow,Custom Outflow1;period=all"
  Given there is a RatioFormula for the fund "Demo Fund 2" with "level=Folio;action=add_cashflow;ratio=XIRR;account_entry_names=Custom Inflow;period=all"
  Given there is a RatioFormula for the fund "Demo Fund 2" with "level=Folio;action=reduce_cashflow;ratio=XIRR;account_entry_names=Custom Outflow,Custom Outflow1;period=all"
  Given there is a RatioFormula for the fund "Demo Fund 2" with "level=PortfolioCompany;action=add_cashflow;ratio=XIRR;account_entry_names=Custom Inflow;period=all"

  # skip_portfolio_fmv formulas: for XIRR the code-computed portfolio FMV is left out of the
  # cash flow entirely; for MOIC it is subtracted from the numerator. Labelled so each forms its
  # own ratio and the default XIRR/MOIC are left untouched.
  Given there is a RatioFormula for the fund "Demo Fund 2" with "level=Fund;action=add_cashflow;ratio=XIRR;account_entry_names=Custom Inflow;period=all;label=xirr skip fmv;skip_portfolio_fmv=true"
  Given there is a RatioFormula for the fund "Demo Fund 2" with "level=Fund;action=add_numerator;ratio=MOIC;account_entry_names=Custom Inflow;period=all;label=moic skip fmv;skip_portfolio_fmv=true"


  # Add the custom entry that should be picked up by the formula
  And there is an AccountEntry "name=Custom Inflow;amount_cents=110000000;reporting_date=2024-01-01;entry_type=Income" for the fund
  And there is an AccountEntry "name=Custom Outflow;amount_cents=50000000;reporting_date=2024-01-01;entry_type=Income" for the fund
  And there is an AccountEntry "name=Custom Outflow1;amount_cents=20000000;reporting_date=2024-01-01;entry_type=Income" for the fund
  # AE for Comm 1
  And there is an AccountEntry "name=Custom Inflow;amount_cents=110000000;reporting_date=2024-01-01;entry_type=Income;capital_commitment_id=1;folio_id=TSTF21" for the fund
  And there is an AccountEntry "name=Custom Outflow;amount_cents=50000000;reporting_date=2024-01-01;entry_type=Income;capital_commitment_id=1;folio_id=TSTF21" for the fund
  And there is an AccountEntry "name=Custom Outflow1;amount_cents=20000000;reporting_date=2024-01-01;entry_type=Income;capital_commitment_id=1;folio_id=TSTF21" for the fund
  # AE for Comm 2
  And there is an AccountEntry "name=Custom Inflow;amount_cents=110000000;reporting_date=2024-01-01;entry_type=Income;capital_commitment_id=2;folio_id=TSTF23" for the fund
  And there is an AccountEntry "name=Custom Outflow;amount_cents=50000000;reporting_date=2024-01-01;entry_type=Income;capital_commitment_id=2;folio_id=TSTF23" for the fund
  And there is an AccountEntry "name=Custom Outflow1;amount_cents=20000000;reporting_date=2024-01-01;entry_type=Income;capital_commitment_id=2;folio_id=TSTF23" for the fund
  # AE for Comm 3
  And there is an AccountEntry "name=Custom Inflow;amount_cents=110000000;reporting_date=2024-01-01;entry_type=Income;capital_commitment_id=3;folio_id=TSTF22" for the fund
  And there is an AccountEntry "name=Custom Outflow;amount_cents=50000000;reporting_date=2024-01-01;entry_type=Income;capital_commitment_id=3;folio_id=TSTF22" for the fund
  And there is an AccountEntry "name=Custom Outflow1;amount_cents=20000000;reporting_date=2024-01-01;entry_type=Income;capital_commitment_id=3;folio_id=TSTF22" for the fund

  # add_numerator reduce_numerator add_denominator reduce_denominator - same base set as the
  # non-label KYC scenario so the non-skip ratios line up with formula_fund_ratios.xlsx
  Given there is a RatioFormula for the fund "Demo Fund 2" with "level=Fund;action=add_numerator;ratio=RVPI;account_entry_names=Custom Inflow;period=all"
  Given there is a RatioFormula for the fund "Demo Fund 2" with "level=Fund;action=reduce_numerator;ratio=TVPI;account_entry_names=Custom Outflow,Custom Outflow1;period=all"
  Given there is a RatioFormula for the fund "Demo Fund 2" with "level=Fund;action=add_denominator;ratio=DPI;account_entry_names=Custom Outflow;period=all"
  Given there is a RatioFormula for the fund "Demo Fund 2" with "level=Folio;action=add_numerator;ratio=RVPI;account_entry_names=Custom Inflow;period=all"
  Given there is a RatioFormula for the fund "Demo Fund 2" with "level=Folio;action=add_denominator;ratio=TVPI;account_entry_names=Custom Inflow;period=all"
  Given there is a RatioFormula for the fund "Demo Fund 2" with "level=Folio;action=reduce_denominator;ratio=DPI;account_entry_names=Custom Outflow;period=all"

  Given I inspect the ratio formulas
  And given the fund_ratios are computed for the date "31-03-2024"
  Then KYC ratios must be computed for the commitments except for commitment with skip_doc_gen
  # Reusing the non-label excel for now - only the two skip_portfolio_fmv ratios ("xirr skip fmv",
  # "moic skip fmv") are extra rows. Update the file name and the expected numbers separately.
  Then the fund ratios computed must match the ratios in "kyc_fund_ratios/formula_fund_ratios_skip_portfolio_fmv.xlsx"
  And the same owner should not have multiple ratios with same label
  And the cashflow CSV documents should be created for the fund ratios

  Scenario: Access Ratio Formulas page
    Given Im logged in as user "Test"
    And I go to the fund show page for "Demo Fund 2"
    And I click link "Actions"
    And I click link "Account Entries"
    And I click link "Ratio Formulas"
    Then I should see "Ratio Formulas for Demo Fund 2"
    And I should see "New Ratio Formula"
