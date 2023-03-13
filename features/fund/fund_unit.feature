Feature: Fund Unit
  Can generate and view fund units

Scenario Outline: Generate fund units from capital call
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing investor "" with "1" users
  Given there is an existing investor "" with "1" users
  Given there is a fund "<fund>" for the entity
  Given the investors are added to the fund  
  Given there are capital commitments of "folio_committed_amount_cents=100000000" from each investor
  Given there is a capital call "<call>"
  Given there is an existing investor "" with "1" users
  Given there is a capital commitment of "folio_committed_amount_cents=100000000" for the last investor 
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



Scenario Outline: Generate fund units from capital distribution
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing investor "" with "1" users
  Given there is an existing investor "" with "1" users
  Given there is a fund "<fund>" for the entity
  Given the investors are added to the fund  
  Given there are capital commitments of "folio_committed_amount_cents=100000000" from each investor
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

