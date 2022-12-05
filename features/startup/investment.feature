Feature: Investment
  Can create and view an investment as a company

Scenario Outline: Create new investment Equity & Preferred
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given there is an existing investor "<investor>"
  And I am at the investments page
  And I create an investment "<investment>"
  Then I should see the "<msg>"
  And an investment should be created
  And I should see the investment details on the details page
  And I should see the investment in all investments page
  And a holding should be created for the investor  
  And the funding round must be updated with the investment
  And the entity must be updated with the investment  
  And the aggregate investments must be created

  Examples:
  	|user	      |entity               |investor     |investment                                   |msg	|
  	|  	        |entity_type=Company  |name=Sequoia |category=Lead Investor;investment_instrument=Equity;quantity=100;price_cents=1000;investor_id=4     |Investment was successfully created|
    |  	        |entity_type=Company  |name=Bearing |category=Co-Investor;investment_instrument=Preferred;quantity=80;price_cents=2000;investor_id=4     |Investment was successfully created|

Scenario Outline: Create new investment Option Fails
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given there is an existing investor "<investor>"
  And I am at the investments page
  And I create an investment "<investment>"
  Then I should see the "<msg>"

  Examples:
  	|user	      |entity               |investor     |investment                                    |msg	|
    |  	        |entity_type=Company  |name=Bearing |category=Co-Investor;investment_instrument=Options;quantity=80;price_cents=2000;investor_id=4     |not associated with Option Pool|


Scenario Outline: Create new investment Options
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given a esop pool "name=Pool 1;approved=true" is created with vesting schedule "12:20,24:30,36:50"
  Given there is an existing investor "<investor>"
  And I am at the investments page
  And I create an investment "<investment>"
  Then I should see the "<msg>"
  And an investment should be created
  And I should see the investment details on the details page
  And I should see the investment in all investments page
  And a holding should be created for the investor  
  And the funding round must be updated with the investment
  And the entity must be updated with the investment  
  And the aggregate investments must be created
Examples:
  	|user	      |entity               |investor     |investment                                    |msg	|
    |  	        |entity_type=Company  |name=Bearing |category=Co-Investor;investment_instrument=Options;quantity=80;price_cents=2000;investor_id=4     |Investment was successfully created|


Scenario Outline: Create new investment
  Given Im logged in as a user "last_name=Tester" for an entity "entity_type=Company"
  Given a esop pool "name=Pool 1;approved=true" is created with vesting schedule "12:20,24:30,36:50"
  Given there is an existing investor "name=Sequoia"
  And I am at the investments page
  And I create an investment "investment_instrument=Equity;quantity=100;investor_id=4"
  And I create an investment "investment_instrument=Preferred;quantity=200;investor_id=4"
  And I create an investment "investment_instrument=Options;quantity=300;investor_id=4"
  Then when I see the aggregated investments
  Then I must see one "1" aggregated investment for the investor
  And I must see the aggregated investment with "Equity=100;Preferred=200;Options=300"

Scenario Outline: Edit investment
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given there is an existing investor "<investor>"
  And I am at the investments page
  And I create an investment "<investment>"
  Then I should see the "<msg>"
  And an investment should be created
  And a holding should be created for the investor
  And I should see the investment details on the details page
  And when I edit the investment "quantity=200;price_cents=3000"
  And I should see the investment details on the details page
  And a holding should be created for the investor  
  And the funding round must be updated with the investment
  And the entity must be updated with the investment  
  And the aggregate investments must be created

  Examples:
  	|user	      |entity               |investor     |investment                                                                                                             |msg	|
  	|  	        |entity_type=Company  |name=Sequoia |category=Lead Investor;investment_instrument=Equity;quantity=100;price_cents=1000;investor_id=4     |Investment was successfully created|
    |  	        |entity_type=Company  |name=Bearing |category=Co-Investor;investment_instrument=Preferred;quantity=80;price_cents=2000;investor_id=4     |Investment was successfully created|


Scenario Outline: Create new holding
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Company"
  Given there are "2" employee investors
  Given there is a FundingRound "name=Series A"
  And Given I create a holding for each employee with quantity "100"
  Then There should be a corresponding holdings created for each employee
  And when the holdings are approved
  Then There should be a corresponding investment created
  And the funding round must be updated with the investment
  And the entity must be updated with the investment  
  And the aggregate investments must be created


Scenario Outline: Import holding
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Company"
  Given a esop pool "name=Pool 1" is created with vesting schedule "12:20,24:30,36:50"
  And Given I upload a holdings file
  Then I should see the "Import upload was successfully created"
  Then There should be "6" holdings created
  And There should be "6" users created for the holdings  
  And There should be "0" Investments created for the holdings
  And when the holdings are approved
  And Investments is updated with the holdings 
  And the funding round must be updated with the investment
  And the entity must be updated with the investment  
  And the aggregate investments must be created


Scenario Outline: Investments updates funding round and entity
  Given there is a user "first_name=Test" for an entity "entity_type=Company"
  Given a esop pool "name=Pool 1" is created with vesting schedule "12:20,24:30,36:50"
  Given there is are "3" investors
  Given there is a FundingRound "name=Series A"
  Given there are "4" investments "<investment>"
  Given there is a FundingRound "name=Series A"
  Given there are "4" investments "<inv2>"
  And the funding rounds must be updated with the right investment
  And the entity must be updated with the investment  
  And the aggregate investments must be created
  And the percentage must be computed correctly
 Examples:
  	|investment                                    | inv2                                           |
  	|investment_instrument=Equity;quantity=100     | investment_instrument=Preferred;quantity=200   |
    |investment_instrument=Preferred;quantity=80   | investment_instrument=Options;quantity=100   |
    |investment_instrument=Options;quantity=50     | investment_instrument=Equity;quantity=300   |


Scenario Outline: Investments updates funding round and entity
  Given there is a user "first_name=Test" for an entity "entity_type=Company"
  Given a esop pool "name=Pool 1" is created with vesting schedule "12:20,24:30,36:50"
  Given there is are "1" investors
  Given there is a FundingRound "name=Series A"
  Given there are "2" investments "<investment>"
  Given there are "2" investments "<inv2>"
  And the funding rounds must be updated with the right investment
  And the entity must be updated with the investment  
  And the aggregate investments must be created
 Examples:
  	|investment                                    | inv2                                           |
  	|investment_instrument=Equity;quantity=100     | investment_instrument=Preferred;quantity=200   |
    |investment_instrument=Preferred;quantity=80   | investment_instrument=Options;quantity=100   |
    |investment_instrument=Options;quantity=50     | investment_instrument=Equity;quantity=300   |
