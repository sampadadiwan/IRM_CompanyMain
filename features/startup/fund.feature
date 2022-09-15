Feature: Fund
  Can create and view a fund as a startup

Scenario Outline: Create new fund
  Given Im logged in as a user "<user>" for an entity "<entity>"
  And I am at the funds page
  When I create a new fund "<fund>"
  Then I should see the "<msg>"
  And an fund should be created
  And I should see the fund details on the details page
  And I should see the fund in all funds page

  Examples:
  	|user	    |entity                                 |fund                 |msg	|
  	|  	        |entity_type=Investment Fund;enable_funds=true  |name=Test fund      |Fund was successfully created|
    |  	        |entity_type=Investment Fund;enable_funds=true  |name=Merger Fund    |Fund was successfully created|



Scenario Outline: Create new capital commitment
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given there is an existing investor "name=Accel" with "2" users
  Given there is an existing investor "name=Sequoia" with "2" users
  Given there is a fund "<fund>" for the entity
  Given the investors are added to the fund  
  When I add a capital commitment "1000000" for investor "Accel"
  Then the fund total committed amount must be "1000000"
  When I add a capital commitment "1000000" for investor "Sequoia"
  Then the fund total committed amount must be "2000000"
  
  Examples:
  	|user	    |entity                                 |fund                 |msg	|
  	|  	        |entity_type=Investment Fund;enable_funds=true  |name=Test fund      |Fund was successfully created|
    |  	        |entity_type=Investment Fund;enable_funds=true  |name=Merger Fund    |Fund was successfully created|



Scenario Outline: Create new capital call
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given there is an existing investor "name=Accel" with "2" users
  Given there is an existing investor "name=Sequoia" with "2" users
  Given there is a fund "<fund>" for the entity
  Given the investors are added to the fund  
  Given there are capital commitments of "committed_amount_cents=100000000" from each investor
  When I create a new capital call "percentage_called=20"
  Then I should see the capital call details
  Then the corresponding remittances should be created
  Then I should see the remittances
  When I mark the remittances as paid
  Then I should see the remittances
  When I mark the remittances as verified
  Then I should see the remittances
  
  Examples:
  	|user	    |entity                                 |fund                 |msg	|
  	|  	        |entity_type=Investment Fund;enable_funds=true  |name=Test fund      |Fund was successfully created|
    |  	        |entity_type=Investment Fund;enable_funds=true  |name=Merger Fund    |Fund was successfully created|
