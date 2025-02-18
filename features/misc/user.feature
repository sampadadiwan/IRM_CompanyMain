Feature: User
  Can create and view a user as a company

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
  	|investor	  |entity_type=Investor             |first_name=Mohith;email=m1@gmail.com |A message with a confirmation link has been sent to your email address.|
    |employee   	                |entity_type=Company        |first_name=Tim;email=m2@gmail.com    |A message with a confirmation link has been sent to your email address.|
    |investor  	        |entity_type=Investment Advisor        |first_name=Tim;email=m2@gmail.com    |A message with a confirmation link has been sent to your email address.|
    |investor  	        |entity_type=Family Office  |first_name=Tim;email=m2@gmail.com    |A message with a confirmation link has been sent to your email address.|
    
# Scenario Outline: Update a user
#   Given Im logged in as a user "" for an entity "entity_type=Company"
#   And the user has role "company_admin"
#   And update my password having phone "7721046692"
#   Then a whatsapp notification is sent indicating account update
