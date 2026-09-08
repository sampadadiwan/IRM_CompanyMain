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

Scenario: Updating roles as company admin leaves other roles unaffected
  Given Im logged in as a user "" for an entity "entity_type=Company;name=Role Update Co"
  And the user has role "company_admin"
  And there is a user "email=grantee@example.com;first_name=Grant;last_name=Ee" for the entity "name=Role Update Co"
  And the user "grantee@example.com" has role "support"
  And the user "grantee@example.com" has role "investor"
  And the user "grantee@example.com" has role "investor_advisor"
  When I update the roles of "grantee@example.com" to "approver,employee"
  Then the user "grantee@example.com" should have the roles "approver,employee,support,investor,investor_advisor"
  And the user "grantee@example.com" should not have the role "company_admin"

Scenario: A company admin can add or remove the company admin role
  Given Im logged in as a user "" for an entity "entity_type=Company;name=Admin Toggle Co"
  And the user has role "company_admin"
  And there is a user "email=teammate@example.com;first_name=Team;last_name=Mate" for the entity "name=Admin Toggle Co"
  And the user "teammate@example.com" has role "company_admin"
  When I update the roles of "teammate@example.com" to "employee"
  Then the user "teammate@example.com" should have the roles "employee"
  And the user "teammate@example.com" should not have the role "company_admin"

Scenario: Removing all editable roles clears them even when nothing is selected
  Given Im logged in as a user "" for an entity "entity_type=Company;name=Clear Roles Co"
  And the user has role "company_admin"
  And there is a user "email=clearme@example.com;first_name=Clear;last_name=Me" for the entity "name=Clear Roles Co"
  And the user "clearme@example.com" has role "approver"
  And the user "clearme@example.com" has role "support"
  When I remove all roles from "clearme@example.com"
  Then the user "clearme@example.com" should not have the role "approver"
  And the user "clearme@example.com" should not have the role "employee"
  And the user "clearme@example.com" should not have the role "company_admin"
  And the user "clearme@example.com" should have the roles "support"

Scenario: Removing the employee role does not touch an investor role the form never showed
  Given Im logged in as a user "" for an entity "entity_type=Company;name=Investor Role Co"
  And the user has role "company_admin"
  And there is a user "email=invemp@example.com;first_name=Inv;last_name=Emp" for the entity "name=Investor Role Co"
  And the user "invemp@example.com" has role "investor"
  When I remove all roles from "invemp@example.com"
  Then the user "invemp@example.com" should not have the role "employee"
  And the user "invemp@example.com" should have the roles "investor"

Scenario: A non company admin cannot grant themselves the company admin role
  Given Im logged in as a user "" for an entity "entity_type=Company;name=Non Admin Co"
  And the user has role "employee"
  When I directly submit a role update of "company_admin" for myself
  Then the user should have the roles "employee"
  And the user should not have the role "company_admin"
