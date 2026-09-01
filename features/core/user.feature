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
  	|investor	  |entity_type=Investor             |first_name=Mohith;email=m1@gmail.com |User was successfully created.|
    |employee   	                |entity_type=Company        |first_name=Tim;email=m2@gmail.com    |User was successfully created.|
    |investor  	        |entity_type=Investment Advisor        |first_name=Tim;email=m2@gmail.com    |User was successfully created.|
    |investor  	        |entity_type=Family Office  |first_name=Tim;email=m2@gmail.com    |User was successfully created.|
    
# Scenario Outline: Update a user
#   Given Im logged in as a user "" for an entity "entity_type=Company"
#   And the user has role "company_admin"
#   And update my password having phone "7721046692"
#   Then a whatsapp notification is sent indicating account update

Scenario: Updating a user's call_code, phone or email syncs to their investor access
  Given Im logged in as a user "" for an entity "entity_type=Company"
  And the user has role "company_admin"
  And there is an existing investor "investor_name=SyncCo;primary_email=sync@b.c" with "1" users
  When I update the investor user's call_code to "44", phone to "7700900123" and email to "synced@example.com"
  Then the investor access for the investor user should have phone "7700900123" and email "synced@example.com"
