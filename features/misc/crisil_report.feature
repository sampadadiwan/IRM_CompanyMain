Feature: Crisil Report
  Test Crisil Report generation

Scenario Outline: Generate Crisil Report for fund
  Given Im logged in as a user "" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is a fund "<fund>" for the entity
  And Given I upload an investors file for the fund
  Given the investors have approved investor access
  Given the fund has capital call template
  Given the investors are added to the fund
  And Given I upload "capital_commitments.xlsx" file for "Commitments" of the fund
  And Given the commitments have a cc "advisor@gmail.com"
  And Given I upload "account_entries.xlsx" file for Account Entries
  When I create a new capital call "<call>"
  Then I should see the capital call details
  Given there is a custom notification for the capital call with subject "<subject>" with email_method "notify_capital_remittance"
  Then when the capital call is approved
  Then the corresponding remittances should be created
  Then I should see the remittances
  And the capital call collected amount should be "0"
  When I mark the remittances as paid
  Then I should see the remittances
  And the capital call collected amount should be "0"
  When I mark the remittances as verified
  Then I should see the remittances
  And the capital call collected amount should be "<collected_amount>"
  And the remittance rollups should be correct
  Given I generate Crisil report for the fund
  Then the Crisil report should be generated


Examples:
  |entity                                         |fund                |msg	| call | collected_amount | subject |
  |entity_type=Investment Fund;enable_funds=true  |name=SAAS Fund;currency=INR      |Fund was successfully created| percentage_called=20;call_basis=Percentage of Commitment | 3520000 | This is a capital call for Fund 1 |
  |entity_type=Investment Fund;enable_funds=true;enable_units=true;currency=INR  |name=SAAS Fund;unit_types=Series A,Series B    |Fund was successfully created| call_basis=Investable Capital Percentage;amount_to_be_called_cents=10000000 | 40000 | This is a capital call for Fund 2 |
