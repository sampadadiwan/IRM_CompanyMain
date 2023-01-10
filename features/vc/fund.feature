Feature: Fund
  Can view a fund as an investor

Scenario Outline: View a fund
  Given there is a user "" for an entity "<entity>"
  Given the user has role "<role>"
  Given there is an existing investor "" with "1" users
  Given there is an existing investor "" with "1" users
  Given there is a fund "<fund>" for the entity
  Given the investors are added to the fund    
  Given Im logged in as a user "first_name=Emp1" for an entity "entity_type=Investor"
  Given my firm is an investor in the fund
  Given there are capital commitments of "committed_amount_cents=100000000" from each investor
  Given there is a capital call "percentage_called=20"
  Given there is a capital distribution "gross_amount_cents=2000000"
  And I should see the fund in all funds page
  When I am at the fund details page
  And I should see the fund details on the details page
  Then I should be able to see my capital commitments
  Then I should be able to see my capital remittances
  Then I should be able to see my capital distributions

  Examples:
  	|entity                                 |fund                       |role|
  	|entity_type=Investment Fund;enable_funds=true  |name=Test 1 fund   |company_admin |
    |entity_type=Investment Fund;enable_funds=true  |name=Test 2 Fund   |employee|
    |entity_type=Investment Fund;enable_funds=true  |name=Test 3 Fund   |Investor|

  