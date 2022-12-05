Feature: Login
  Login should be allowed only if there are valid credentials

Scenario Outline: Login Successfully
  Given there is a user "<user>" for an entity "<entity>"
  And I am at the login page
  When I fill and submit the login page
  Then I should see the "<msg>"

  Examples:
  	|user	              |entity               |msg	|
  	|  	                |entity_type=Investor       |Signed in successfully|
    |  	                |entity_type=Company  |Signed in successfully|
    |accept_terms=false |entity_type=Company  |Please accept the Terms and Conditions|
    |system_created=true|entity_type=Company  |Please change your password at the earliest|

Scenario Outline: Login Successfully
  Given there is a user "<user>"
  And I am at the login page
  When I fill and submit the login page
  Then I should see the "<msg>"

  Examples:
  	|user	  |msg	|
  	|  	    |Signed in successfully|
    |  	    |Signed in successfully|


Scenario Outline: Login Incorrectly
  Given there is a user "<user>"
  And I am at the login page
  When I fill the password incorrectly and submit the login page
  Then I should see the "<msg>"

  Examples:
  	|user		|msg	|
  	|	      |Invalid Email or password|
    
