Feature: Records with allocated fund units cannot be deleted
  A stakeholder, capital commitment, capital call, remittance, distribution or distribution
  payment cannot be deleted while fund units are allocated against it: the units must be
  deleted first (BlocksDestroyWithFundUnits). Once they are gone the delete goes through.

@import
Scenario Outline: Deleting a record with allocated fund units is refused
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
  Given the capital calls are approved
  And Given import file "fund_ratios/capital_remittance_payments.xlsx" for "CapitalRemittancePayment"
  Given the units are generated
  When I delete the "<record>" that has fund units allocated
  Then I get the error "Cannot delete this <label> as fund units have been allocated against it. Please delete those fund units first."
  And the "<record>" and its fund units are not deleted

Examples:
  | record             | label              |
  | stakeholder        | stakeholder        |
  | capital commitment | capital commitment |
  | capital call       | capital call       |

Scenario Outline: Deleting a distribution record with allocated fund units is refused
  Given Im logged in as a user "" for an entity "entity_type=Investment Fund;enable_funds=true"
  Given the user has role "company_admin"
  Given there is an existing investor "" with "1" users
  Given there is an existing investor "" with "1" users
  Given there is a fund "name=Test" for the entity
  Given the investors are added to the fund
  Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
  Given there is a capital distribution "gross_amount_cents=20000000;cost_of_investment_cents=15000000;reinvestment_cents=0;fee_cents=0;completed=true"
  Given the investors are added to the fund
  Then the corresponding distribution payments should be created
  Given the distribution payments are completed
  Given the units are generated
  When I delete the "<record>" that has fund units allocated
  Then I get the error "Cannot delete this <label> as fund units have been allocated against it. Please delete those fund units first."
  And the "<record>" and its fund units are not deleted

Examples:
  | record                       | label                        |
  | capital distribution         | capital distribution         |
  | capital distribution payment | capital distribution payment |

@import
Scenario: Deleting a remittance whose units the payment check misses is refused
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
  Given the capital calls are approved
  And Given import file "fund_ratios/capital_remittance_payments.xlsx" for "CapitalRemittancePayment"
  Given the units are generated
  When I delete a remittance that has fund units but no payments
  Then I get the error "Cannot delete this capital remittance as fund units have been allocated against it. Please delete those fund units first."
  And the "capital remittance" and its fund units are not deleted

@import
Scenario Outline: A record can be deleted once its fund units are deleted
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
  Given the capital calls are approved
  And Given import file "fund_ratios/capital_remittance_payments.xlsx" for "CapitalRemittancePayment"
  Given the units are generated
  Given the fund units allocated against the "<record>" are deleted
  When I delete the "<record>"
  Then I see the delete notice "<notice>"
  And the "<record>" is deleted

Examples:
  | record             | notice                                         |
  | stakeholder        | Stakeholder was successfully deleted.          |
  | capital commitment | Capital commitment was successfully destroyed. |
  | capital call       | Capital call was successfully destroyed.       |

Scenario Outline: A distribution record can be deleted once its fund units are deleted
  Given Im logged in as a user "" for an entity "entity_type=Investment Fund;enable_funds=true"
  Given the user has role "company_admin"
  Given there is an existing investor "" with "1" users
  Given there is an existing investor "" with "1" users
  Given there is a fund "name=Test" for the entity
  Given the investors are added to the fund
  Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
  Given there is a capital distribution "gross_amount_cents=20000000;cost_of_investment_cents=15000000;reinvestment_cents=0;fee_cents=0;completed=true"
  Given the investors are added to the fund
  Then the corresponding distribution payments should be created
  Given the distribution payments are completed
  Given the units are generated
  Given the fund units allocated against the "<record>" are deleted
  When I delete the "<record>"
  Then I see the delete notice "<notice>"
  And the "<record>" is deleted

Examples:
  | record                       | notice                                                   |
  | capital distribution         | Capital distribution was successfully destroyed.         |
  | capital distribution payment | Capital distribution payment was successfully destroyed. |

@rack_test
Scenario: Delete All keeps the records with fund units and reports them
  Given Im logged in as a user "" for an entity "entity_type=Investment Fund;enable_funds=true"
  Given the user has role "company_admin"
  Given there is an existing investor "" with "1" users
  Given there is an existing investor "" with "1" users
  Given there is a fund "name=Test" for the entity
  Given the investors are added to the fund
  Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
  Given there is a capital distribution "gross_amount_cents=20000000;cost_of_investment_cents=15000000;reinvestment_cents=0;fee_cents=0;completed=true"
  Given the investors are added to the fund
  Then the corresponding distribution payments should be created
  Given the distribution payments are completed
  Given the units are generated
  When Delete All is run for "CapitalDistributionPayment" on the fund
  Then the distribution payments with fund units are not deleted
  And Delete All reports "Cannot delete this capital distribution payment as fund units have been allocated against it" instead of completing
