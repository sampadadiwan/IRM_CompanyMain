Feature: User
  Can create and view a user as a startup

Scenario Outline: Create new user
  Given Im logged in as a user "" for an entity "<entity>"
  And the user has role "company_admin"
  And I am at the users page
  When I create a new user "<user>"
  Then I should see the "<msg>"
  And an user should be created
  And I should see the user details on the details page
  And I should see the user in all users page
  And the created user should have the roles "<roles>"

  Examples:
  	|roles                      |entity                     |user                                 |msg	|
  	|investor,secondary_buyer	  |entity_type=VC             |first_name=Mohith;email=m1@gmail.com |A message with a confirmation link has been sent to your email address.|
    |startup   	                |entity_type=Startup        |first_name=Tim;email=m2@gmail.com    |A message with a confirmation link has been sent to your email address.|
    |secondary_buyer  	        |entity_type=Advisor        |first_name=Tim;email=m2@gmail.com    |A message with a confirmation link has been sent to your email address.|
    |secondary_buyer  	        |entity_type=Family Office  |first_name=Tim;email=m2@gmail.com    |A message with a confirmation link has been sent to your email address.|
    |holding         	          |entity_type=Holding        |first_name=Tim;email=m2@gmail.com    |A message with a confirmation link has been sent to your email address.|
