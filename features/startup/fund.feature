Feature: Fund
  Can create and view a fund as a startup

Scenario Outline: Create new fund
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
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


Scenario Outline: View fund with employee access
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given there is a fund "<fund>" for the entity
  And I am "given" employee access to the fund
  When I am at the fund details page  
  And I should see the fund details on the details page
  And I should see the fund in all funds page

  Examples:
  	|user	    |entity                                 |fund                 |msg	|
  	|  	        |entity_type=Investment Fund;enable_funds=true  |name=Test fund      |Fund was successfully created|
    |  	        |entity_type=Investment Fund;enable_funds=true  |name=Merger Fund    |Fund was successfully created|

Scenario Outline: View fund - without employee access
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given there is a fund "<fund>" for the entity
  And I am "no" employee access to the fund
  When I am at the fund details page  
  Then I should see the "<msg>"

  Examples:
  	|user	    |entity                                 |fund                 |msg	|
  	|  	        |entity_type=Investment Fund;enable_funds=true  |name=Test fund      |Access Denied|
    |  	        |entity_type=Investment Fund;enable_funds=true  |name=Merger Fund    |Access Denied|

  

Scenario Outline: Create new capital commitment
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
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
  Given the user has role "company_admin"
  Given there is an existing investor "name=Accel" with "2" users
  Given there is an existing investor "name=Sequoia" with "2" users
  Given there is a fund "<fund>" for the entity
  Given the investors are added to the fund  
  Given there are capital commitments of "committed_amount_cents=100000000" from each investor
  When I create a new capital call "percentage_called=20"
  Then I should see the capital call details
  Then when the capital call is approved
  Then the corresponding remittances should be created
  Then I should see the remittances
  And the capital call collected amount should be "0"
  When I mark the remittances as paid
  Then I should see the remittances
  And the capital call collected amount should be "0"
  When I mark the remittances as verified
  Then I should see the remittances
  And the capital call collected amount should be "400000"
  And the investors must receive email with subject "Capital Call"
  
  Examples:
  	|user	    |entity                                 |fund                 |msg	|
  	|  	        |entity_type=Investment Fund;enable_funds=true  |name=Test fund      |Fund was successfully created|
    |  	        |entity_type=Investment Fund;enable_funds=true  |name=Merger Fund    |Fund was successfully created|


Scenario Outline: Create new capital distrbution
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing investor "name=Accel" with "2" users
  Given there is an existing investor "name=Sequoia" with "2" users
  Given there is a fund "<fund>" for the entity
  Given the investors are added to the fund  
  Given there are capital commitments of "committed_amount_cents=100000000" from each investor
  When I create a new capital distribution "carry_cents=10000000;carry_cents=100000"
  Then I should see the capital distrbution details
  Then when the capital distrbution is approved
  Then I should see the capital distrbution payments generated correctly
  And I should be able to see the capital distrbution payments
  And when the capital distrbution payments are marked as paid
  Then the capital distribution must reflect the payments
  And the investors must receive email with subject "Capital Distribution"
  
  Examples:
  	|user	    |entity                                 |fund                 |msg	|
  	|  	        |entity_type=Investment Fund;enable_funds=true  |name=Test fund      |Fund was successfully created|
    |  	        |entity_type=Investment Fund;enable_funds=true  |name=Merger Fund    |Fund was successfully created|
