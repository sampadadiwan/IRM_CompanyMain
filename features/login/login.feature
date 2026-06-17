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
  Given there is a user "<user>" for an entity ""
  And I am at the login page
  When I fill and submit the login page
  Then I should see the "<msg>"

  Examples:
  	|user	  |msg	|
  	|  	    |Signed in successfully|
    |  	    |Signed in successfully|


Scenario Outline: Login Successfully, without password
  Given there is a user "<user>" for an entity ""
  And I am at the login page without password
  When I fill and submit the login without password
  Then I should see the "<msg>"
  And the user receives an email with "<subject>" in the subject
  And when I click on the link in the email "<link>"
  Then I should see the "<login_msg>"
  And the user should be confirmed

  Examples:
  	|user	  |login_msg	            | subject                         | link         | msg |
  	|  	    |Signed in successfully| Login Link: Expires in 10 minutes |Click To Login|If that address is registered, a login link is on its way.|
    |  	    |Signed in successfully| Login Link: Expires in 10 minutes |Click To Login|If that address is registered, a login link is on its way.|

Scenario Outline: Login Incorrectly
  Given there is a user "<user>" for an entity ""
  And I am at the login page
  When I fill the password incorrectly and submit the login page
  Then I should see the "<msg>"

  Examples:
  	|user		|msg	|
  	|	      |Invalid email or password|

Scenario: Invited user receives a confirmation email branded with their entity name
  Given Im logged in as a user "" for an entity "entity_type=Company"
  And the user has role "company_admin"
  And I am at the users page
  When I create a new user "first_name=Tim;email=invitee@gmail.com"
  Then an user should be created
  And the new user receives a confirmation email welcoming them to their entity

