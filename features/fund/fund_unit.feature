Feature: Fund Unit
  Can generate and view fund units

Scenario Outline: Generate fund units from capital call
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing investor "" with "1" users
  Given there is an existing investor "" with "1" users
  Given there is a fund "<fund>" for the entity
  Given the investors are added to the fund
  Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
  Given there is a capital call "<call>"
  Given there is an existing investor "" with "1" users
  Given there is a capital commitment of "orig_folio_committed_amount_cents=100000000" for the last investor
  Given the investors are added to the fund
  Then the corresponding remittances should be created
  Then I should see the remittances
  Given the remittances are paid and verified
  Given the units are generated
  Then there should be correct units for the calls payment for each investor
  # To check idempotency we run it again
  Given the units are generated
  Then there should be correct units for the calls payment for each investor

Examples:
  	|user	    |entity                                 |fund                 | call |
  	|  	        |entity_type=Investment Fund;enable_funds=true  |name=Test  | percentage_called=20 |
    |  	        |entity_type=Investment Fund;enable_funds=true  |name=Merger| percentage_called=20;generate_remittances_verified=true |


Scenario Outline: Generate fund units from capital call when remittance is overpaid
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing investor "" with "1" users
  Given there is an existing investor "" with "1" users
  Given there is a fund "<fund>" for the entity
  Given the investors are added to the fund
  Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
  Given there is a capital call "<call>"
  Given there is an existing investor "" with "1" users
  Given there is a capital commitment of "orig_folio_committed_amount_cents=100000000" for the last investor
  Given the investors are added to the fund
  Then the corresponding remittances should be created
  Then I should see the remittances
  Given the remittances are overpaid and verified
  Given the units are generated
  Then there should be correct units for the calls payment for each investor
  # To check idempotency we run it again
  Given the units are generated
  Then there should be correct units for the calls payment for each investor

Examples:
  	|user	    |entity                                 |fund                 | call |
  	|  	        |entity_type=Investment Fund;enable_funds=true  |name=Test  | percentage_called=20 |
    |  	        |entity_type=Investment Fund;enable_funds=true  |name=Merger| percentage_called=20;generate_remittances_verified=true |

Scenario Outline: Generate fund units from capital distribution
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing investor "" with "1" users
  Given there is an existing investor "" with "1" users
  Given there is a fund "<fund>" for the entity
  Given the investors are added to the fund
  Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
  Given there is a capital distribution "<distribution>"
  # Given there is an existing investor "" with "1" users
  # Given there is a capital commitment of "committed_amount_cents=100000000" for the last investor
  Given the investors are added to the fund
  Then the corresponding distribution payments should be created
  Then I should see the distribution payments
  Given the distribution payments are completed
  Given the units are generated
  Then there should be correct units for the distribution payments for each investor
  # To check idempotency we run it again
  Given the units are generated
  Then there should be correct units for the distribution payments for each investor

Examples:
  	|user	    |entity                                 |fund                 | distribution |
  	|  	        |entity_type=Investment Fund;enable_funds=true  |name=Test  | gross_amount_cents=20000000;cost_of_investment_cents=15000000;reinvestment_cents=0;fee_cents=0;completed=true |
    |  	        |entity_type=Investment Fund;enable_funds=true  |name=Merger| gross_amount_cents=20000000;cost_of_investment_cents=15000000;reinvestment_cents=0;fee_cents=0;completed=true |

@import
Scenario Outline: Import fund units
  Given Im logged in as a user "" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is a fund "<fund>" for the entity
  And Given I upload an investors file for the fund
  Given the investors are added to the fund
  And Given I upload "capital_commitments_multi_currency.xlsx" file for "Commitments" of the fund
  When I create a new capital call "<call>"
  Then I should see the capital call details
  Then when the capital call is approved
  And Given I upload "capital_remittances.xlsx" file for Call remittances of the fund
  And Given I upload "capital_distributions.xlsx" file for Distributions of the fund
  And Given I upload "fund_units.xlsx" file for Fund Units of the fund
  Then There should be "5" fund units created with data in the sheet

  Examples:
  	|entity                                         |fund                |msg	| call | collected_amount |
  	|entity_type=Investment Fund;enable_funds=true  |name=SAAS Fund;currency=INR      |Fund was successfully created| name=Call 1;call_basis=Upload | 2120000 |


Scenario Outline: Transfer Fund Units
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund;currency=INR"
  Given the user has role "company_admin"
  Given there is a fund "name=Demo Fund 2;currency=INR;unit_types=A1,A2" for the entity
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
  Given the units are generated
  When fund units are transferred "<transfer>"
  Then the units should be transferred
  And I should be able to see the transferred fund units
  And the account entries are adjusted upon fund unit transfer
  And the remittances are adjusted upon fund unit transfer
  And distributions are adjusted upon fund unit transfer
  And adjustments are create upon fund unit transfer

Examples:
  	|fund                 | call                 | transfer |
  	|name=Test;unit_types=A,B,C  | percentage_called=20 | price=100,premium=10,transfer_ratio=1,transfer_account_entries=true,account_entries_excluded=nil|
    |name=Merger;unit_types=A,B,C| percentage_called=20;generate_remittances_verified=true | price=1000,premium=100,transfer_ratio=.5,transfer_account_entries=true,account_entries_excluded=nil |

Scenario Outline: Transfer Fund Units Validations
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund;currency=INR"
  Given the user has role "company_admin"
  Given there is a fund "name=Demo Fund 2;currency=INR;unit_types=A1,A2" for the entity
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
  Given the units are generated
  Given there is a fund "name=Demo Fund 3;currency=INR;unit_types=A1,A2" for the entity
  When fund units are transferred "<transfer>" and from_commitment has attrs "<from_commitment>" and to_commitment has attrs "<to_commitment>"
  Then I should get the error "<message>"

Examples:
    # to commitment has a later date — now allowed; transfer_date is used as as_of so no date-ordering constraint
  	|fund                 | call                 | transfer | from_commitment | to_commitment | message |
  	|name=Test;unit_types=A,B,C  | percentage_called=20 | price=100,premium=10,transfer_ratio=1,transfer_account_entries=true,account_entries_excluded=nil| commitment_date=2020-01-01 | commitment_date=2020-01-02 | nil |
    # to commitment has the same date
    |name=Merger;unit_types=A,B,C| percentage_called=20;generate_remittances_verified=true | price=1000,premium=100,transfer_ratio=.5,transfer_account_entries=true,account_entries_excluded=nil | commitment_date=2020-01-01 | commitment_date=2020-01-01 | nil |
    # to commitment has the earlier date
    |name=Merger;unit_types=A,B,C| percentage_called=20;generate_remittances_verified=true | price=1000,premium=100,transfer_ratio=.5,transfer_account_entries=true,account_entries_excluded=nil | commitment_date=2020-01-02 | commitment_date=2020-01-01 | nil |
    # different funds
    |name=Merger;unit_types=A,B,C| percentage_called=20;generate_remittances_verified=true | price=1000,premium=100,transfer_ratio=.5,transfer_account_entries=true,account_entries_excluded=nil | commitment_date=2020-01-01;fund_id=1 | commitment_date=2020-01-01;fund_id=2 | Commitments are not from the same fund. |
    # different unit types
    |name=Merger;unit_types=A,B,C| percentage_called=20;generate_remittances_verified=true | price=1000,premium=100,transfer_ratio=.5,transfer_account_entries=true,account_entries_excluded=nil | commitment_date=2020-01-01;unit_type=A2 | commitment_date=2020-01-01;unit_type=A1| Commitments are not the same unit type. |
    # different fund and different unit type (date ordering no longer an error)
    |name=Merger;unit_types=A,B,C| percentage_called=20;generate_remittances_verified=true | price=1000,premium=100,transfer_ratio=.5,transfer_account_entries=true,account_entries_excluded=nil | commitment_date=2020-01-01;unit_type=A2;fund_id=1  | commitment_date=2020-01-02;unit_type=A1;fund_id=2 | Commitments are not from the same fund.Commitments are not the same unit type. |


Scenario Outline: Transfer Fund Units - Invalid Ratio
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund;currency=INR"
  Given the user has role "company_admin"
  Given there is a fund "name=Demo Fund 2;currency=INR;unit_types=A1,A2" for the entity
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
  Given the units are generated
  When fund units are transferred with ratio percentage <ratio>
  Then I should get the error "<message>"

Examples:
  | ratio | message                             |
  | 0     | Transfer ratio must be greater than 0. |
  | -10   | Transfer ratio must be greater than 0. |
  | 110   | Transfer ratio must be 100 or less.    |


Scenario: Transfer Fund Units - fails when from commitment has no remaining units
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund;currency=INR"
  Given the user has role "company_admin"
  Given there is a fund "name=Demo Fund 2;currency=INR;unit_types=A1,A2" for the entity
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
  Given the units are generated
  Given the fund units are fully transferred
  When fund units are transferred with ratio percentage 50
  Then I should get the error "From commitment does not have enough units."


Scenario: Transfer Fund Units without account entries
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund;currency=INR"
  Given the user has role "company_admin"
  Given there is a fund "name=Demo Fund 2;currency=INR;unit_types=A1,A2" for the entity
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
  Given the units are generated
  When fund units are transferred "price=1000,premium=100,transfer_ratio=.5,transfer_account_entries=false,account_entries_excluded=nil"
  Then the units should be transferred
  And account entries are not affected by the transfer
  And the remittances are adjusted upon fund unit transfer
  And distributions are adjusted upon fund unit transfer
  And adjustments are create upon fund unit transfer


Scenario: Transfer Fund Units with excluded account entries
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund;currency=INR"
  Given the user has role "company_admin"
  Given there is a fund "name=Demo Fund 2;currency=INR;unit_types=A1,A2" for the entity
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
  Given the units are generated
  When the fund units are transferred excluding the first account entry
  Then the excluded account entry is copied in full to the to commitment
  And the other account entries are pro-rated


Scenario: Fund unit counter caches are correct after transfer
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund;currency=INR"
  Given the user has role "company_admin"
  Given there is a fund "name=Demo Fund 2;currency=INR;unit_types=A1,A2" for the entity
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
  Given the units are generated
  When fund units are transferred "price=1000,premium=100,transfer_ratio=.5,transfer_account_entries=true,account_entries_excluded=nil"
  Then the fund unit counter caches are correct after transfer


@import
Scenario Outline: Import fund units that are same except issue date
  Given Im logged in as a user "" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is a fund "<fund>" for the entity
  And Given I upload an investors file for the fund
  Given the investors are added to the fund
  And Given I upload "capital_commitments_multi_currency.xlsx" file for "Commitments" of the fund
  When I create a new capital call "<call>"
  Then I should see the capital call details
  Then when the capital call is approved
  And Given I upload "capital_remittances.xlsx" file for Call remittances of the fund
  And Given I upload "capital_distributions.xlsx" file for Distributions of the fund
  And Given I upload "fund_units_diff_issue_date.xlsx" file for Fund Units of the fund
  Then There should be "5" fund units created with data in the "fund_units_diff_issue_date.xlsx" sheet

  Examples:
  	|entity                                         |fund                |msg	| call | collected_amount |
  	|entity_type=Investment Fund;enable_funds=true  |name=SAAS Fund;currency=INR      |Fund was successfully created| name=Call 1;call_basis=Upload | 2120000 |
