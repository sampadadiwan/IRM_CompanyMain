Feature: Capital Distributions
  Capital Distributions fees

Scenario Outline: Create a capital distribution
  Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund;currency=INR" for the entity
  Given there is an existing investor "name=Investor 1"
  Given there is a capital commitment of "orig_folio_committed_amount_cents=100000000;folio_currency=INR" for the last investor
  Given there is a capital commitment of "orig_folio_committed_amount_cents=100000000;folio_currency=INR;fund_close=Second Close" for the last investor
  Given there is a AccountEntry for distribution "<income_account_entry>"
  Given there is a AccountEntry for distribution "<tax_account_entry>"
  Given there is a AccountEntry for distribution "<fv_account_entry>"
  When I create a Capital Distribution "<capital_distribution>"
  Then it should create Capital Distribution
  And the data should be correctly displayed for each Capital Distribution Payment

  Examples:
    | capital_distribution | income_account_entry | tax_account_entry | fv_account_entry |
    | title=Capital Distribution 1;income_cents=10000000;cost_of_investment_cents=5000000;reinvestment_cents=2000000;distribution_date=2024-12-15 | name=Portfolio Cashflows;reporting_date=2024-12-02;entry_type=Income;amount_cents=100000 | name=TDS;reporting_date=2024-12-02;entry_type=Tax;amount_cents=50000 | name=FV for Redemption;reporting_date=2024-12-02;entry_type=FV For Redemption;amount_cents=10000 |



@notification
Scenario Outline: Create new capital distrbution
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing investor "" with "2" users
  Given there is an existing investor "" with "2" users
  Given there is a fund "<fund>" for the entity
  Given the investors are added to the fund
  Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
  And Given the commitments have a cc "advisor@gmail.com"
  When I create a new capital distribution "cost_of_investment_cents=10000000;"
  Then I should see the capital distrbution details
  Then when the capital distrbution is approved
  Then I should see the capital distrbution payments generated correctly
  And I should be able to see the capital distrbution payments
  And when the capital distrbution payments are marked as paid
  Then the capital distribution must reflect the payments
  When the capital distribution notifications are sent
  Then the investors must receive email with subject "Capital Distribution" with the document "" attached

  Examples:
  	|user	    |entity                                 |fund                 |msg	|
  	|  	        |entity_type=Investment Fund;enable_funds=true  |name=Test fund      |Fund was successfully created|
    |  	        |entity_type=Investment Fund;enable_funds=true  |name=Merger Fund    |Fund was successfully created|

@doc_gen @notification
Scenario Outline: Capital Distribution Payment Doc Gen
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing investor "" with "2" users
  Given there is an existing investor "" with "2" users
  Given there is a fund "<fund>" for the entity
  Given the investors are added to the fund
  Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
  And Given the commitments have a cc "advisor@gmail.com"
  When I create a new capital distribution "cost_of_investment_cents=10050000;"
  Then I should see the capital distrbution details
  Then when the capital distrbution is approved
  Then I should see the capital distrbution payments generated correctly
  And I should be able to see the capital distrbution payments
  Given the fund has a template "Distribution Template" of type "Distribution Template"
  And We Generate documents for the capital distribution
  And The distribution payment documents are approved
  Then Distribution notice should be generate for all distribution payments with verified KYC
  And the generated distribution notices have as_of set to the payment date
  And when the capital distrbution payments are marked as paid
  Then the capital distribution must reflect the payments
  When the capital distribution notifications are sent
  Then the investors must receive email with subject "Capital Distribution" with the document "Distribution Template" attached

  Examples:
  	|user	    |entity                                 |fund                 |msg	|
  	|  	        |entity_type=Investment Fund;enable_funds=true  |name=Test fund      |Fund was successfully created|

@doc_gen
Scenario Outline: Bulk distribution document generation doesn't re-query the distribution's payments per document
  # Regression guard for a memory/N+1 fix: CapitalDistributionPaymentDocGenerator used to
  # re-query and re-materialize every payment in the distribution once per document being
  # generated (O(N^2) row loads across a bulk run). With 5 payments in one distribution, the
  # fix caches that per-distribution query for the whole run instead of once per payment, so
  # the query count stays flat instead of growing with the number of payments. The count is
  # scoped to queries filtered by capital_distribution_id (excludes the per-payment folio_id
  # uniqueness check, which legitimately runs once per payment and isn't part of this fix) —
  # expect exactly 3: the model-existence check, the bulk payments load, and one distribution-
  # wide payments fetch shared across all 5 documents generated in this run.
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there are "5" existing investor "" with "1" users
  Given there is a fund "<fund>" for the entity
  Given the investors are added to the fund
  Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
  When I create a new capital distribution "cost_of_investment_cents=10050000;"
  Then I should see the capital distrbution details
  Then when the capital distrbution is approved
  Then I should see the capital distrbution payments generated correctly
  Given the fund has a template "Distribution Template" of type "Distribution Template"
  Given I start counting SQL queries against "capital_distribution_payments" filtered by "capital_distribution_id" excluding "folio_id"
  When I generate distribution payment documents directly for the capital distribution
  Then the number of SELECT queries against "capital_distribution_payments" filtered by "capital_distribution_id" excluding "folio_id" should be at most "3"

  Examples:
  	|user	    |entity                                 |fund                 |
  	|  	        |entity_type=Investment Fund;enable_funds=true  |name=Test fund      |

@doc_gen @notification
Scenario Outline: Capital Distribution Payment custom notification
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing investor "" with "2" users
  Given there is an existing investor "" with "2" users
  Given there is a fund "<fund>" for the entity
  Given the investors are added to the fund
  Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
  And Given the commitments have a cc "advisor@gmail.com"
  When I create a new capital distribution "cost_of_investment_cents=10050000;"
  Then I should see the capital distrbution details
  Then when the capital distrbution is approved
  Then I should see the capital distrbution payments generated correctly
  And I should be able to see the capital distrbution payments
  Given the fund has a template "Distribution Template" of type "Distribution Template"
  Given there is a custom notification for the capital distribution with subject "Custom Dist Notification" with email_method "send_notification"
  And We Generate documents for the capital distribution
  And The distribution payment documents are approved
  Then Distribution notice should be generate for all distribution payments with verified KYC
  And when the capital distrbution payments are marked as paid
  Then the capital distribution must reflect the payments
  When the capital distribution notifications are sent
  Then the investors must receive email with subject "Custom Dist Notification" with the document "Distribution Template" attached

  Examples:
   	|user	    |entity                                 |fund                 |msg	|
   	|  	        |entity_type=Investment Fund;enable_funds=true  |name=Test fund      |Fund was successfully created|

@notification
Scenario Outline: Capital Distribution Payment custom notification with placeholders
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing investor "" with "2" users
  Given there is an existing investor "" with "2" users
  Given there is a fund "<fund>" for the entity
  Given the investors are added to the fund
  Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
  And Given the commitments have a cc "advisor@gmail.com"
  When I create a new capital distribution "cost_of_investment_cents=10050000;"
  Then I should see the capital distrbution details
  Then when the capital distrbution is approved
  Then I should see the capital distrbution payments generated correctly
  And I should be able to see the capital distrbution payments
  Given the fund has a template "Distribution Template" of type "Distribution Template"
  Given there is a custom notification with placeholders for the capital distribution with subject "Custom Dist Placeholder" with email_method "send_notification"
  And We Generate documents for the capital distribution
  And The distribution payment documents are approved
  Then Distribution notice should be generate for all distribution payments with verified KYC
  And when the capital distrbution payments are marked as paid
  Then the capital distribution must reflect the payments
  When the capital distribution notifications are sent
  Then the capital distribution notification placeholders are resolved correctly

  Examples:
    |user     |entity                                 |fund                 |msg   |
    |           |entity_type=Investment Fund;enable_funds=true  |name=Test fund      |Fund was successfully created|

Scenario Outline: Capital Distribution with Display Only fee type
  Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=Display Only Fund;currency=INR" for the entity
  Given there is an existing investor "name=Investor 1"
  Given there is a capital commitment of "orig_folio_committed_amount_cents=100000000;folio_currency=INR" for the last investor
  Given there is a AccountEntry for distribution "name=Audit Entry;reporting_date=2024-12-01;entry_type=Display Only;amount_cents=99999"
  When I create a Capital Distribution "title=CD with Display Only;income_cents=10000000;cost_of_investment_cents=5000000;reinvestment_cents=0;distribution_date=2024-12-15"
  Then it should create Capital Distribution
  And the Display Only fee should not affect income_with_fees_cents
  And the Display Only fee should not affect cost_of_investment_with_fees_cents
  And the ae_audit should contain the Display Only fee details
  And the json_fields should contain the Display Only fee name with amount "99999"
  And the distribution payments should have the "Display Only" fee details

Scenario Outline: Capital Distribution with Reinvestment fee type
  Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=Reinvestment Fund;currency=INR" for the entity
  Given there is an existing investor "name=Investor 1"
  Given there is a capital commitment of "orig_folio_committed_amount_cents=100000000;folio_currency=INR" for the last investor
  Given there is a AccountEntry for distribution "name=Dividend Reinvestment;reporting_date=2024-12-01;entry_type=Reinvestment;amount_cents=50000"
  When I create a Capital Distribution "title=CD with Reinvestment;income_cents=10000000;cost_of_investment_cents=5000000;reinvestment_cents=0;distribution_date=2024-12-15"
  Then it should create Capital Distribution
  And the reinvestment_with_fees_cents should be correctly calculated
  And the net_payable_cents should account for reinvestment correctly

Scenario Outline: Capital Distribution with Expense fee type
  Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=Expense Fund;currency=INR" for the entity
  Given there is an existing investor "name=Investor 1"
  Given there is a capital commitment of "orig_folio_committed_amount_cents=100000000;folio_currency=INR" for the last investor
  Given there is a AccountEntry for distribution "name=Management Fees;reporting_date=2024-12-01;entry_type=Expense;amount_cents=25000"
  When I create a Capital Distribution "title=CD with Expense;income_cents=10000000;cost_of_investment_cents=5000000;reinvestment_cents=0;distribution_date=2024-12-15"
  Then it should create Capital Distribution
  And the expense should reduce the income_with_fees_cents correctly
  And the distribution payments should have the "Expense" fee details

Scenario Outline: Capital Distribution with Tax fee type
  Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=Expense Fund;currency=INR" for the entity
  Given there is an existing investor "name=Investor 1"
  Given there is a capital commitment of "orig_folio_committed_amount_cents=100000000;folio_currency=INR" for the last investor
  Given there is a AccountEntry for distribution "name=Management Fees;reporting_date=2024-12-01;entry_type=Tax;amount_cents=50000"
  When I create a Capital Distribution "title=CD with Tax;income_cents=10000000;cost_of_investment_cents=5000000;reinvestment_cents=0;distribution_date=2024-12-15"
  Then it should create Capital Distribution
  And the tax should reduce the income_with_fees_cents correctly
  And the distribution payments should have the "Tax" fee details

Scenario: Clone a capital distribution copies its setup fields and fee rows into a new draft
  Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=Clone Fund;currency=INR" for the entity
  Given there is an existing investor "name=Investor 1"
  Given there is a capital commitment of "orig_folio_committed_amount_cents=100000000;folio_currency=INR" for the last investor
  Given there is a AccountEntry for distribution "name=Portfolio Cashflows;reporting_date=2024-12-02;entry_type=Income;amount_cents=100000"
  Given there is a AccountEntry for distribution "name=TDS;reporting_date=2024-12-02;entry_type=Tax;amount_cents=50000"
  When I create a Capital Distribution "title=Original Distribution;income_cents=10000000;cost_of_investment_cents=5000000;reinvestment_cents=0;distribution_date=2024-12-15"
  Then it should create Capital Distribution
  When I clone the capital distribution
  Then the new distribution form should show the source title as a copy with "2" fee rows
  When I save the cloned capital distribution
  Then a new Capital Distribution should exist as an independent clone with matching fee rows
  And the source capital distribution's fee rows should be unchanged

Scenario: Create With Fees copies only the fee rows into a blank new distribution
  Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=Create With Fees Fund;currency=INR" for the entity
  Given there is an existing investor "name=Investor 1"
  Given there is a capital commitment of "orig_folio_committed_amount_cents=100000000;folio_currency=INR" for the last investor
  Given there is a AccountEntry for distribution "name=Portfolio Cashflows;reporting_date=2024-12-02;entry_type=Income;amount_cents=100000"
  When I create a Capital Distribution "title=Fee Source Distribution;income_cents=10000000;cost_of_investment_cents=5000000;reinvestment_cents=0;distribution_date=2024-12-15"
  Then it should create Capital Distribution
  When I create with fees from the capital distribution
  Then the new distribution form should have a blank title with "1" fee rows pre-filled
