Feature: Investor Access
  Create, Update, Approve and Delete Investor Access and verify turbo responses

Scenario Outline: Investor show page Investor Access turbo response checks
  Given Im logged in as a user "first_name=Mohith" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing investor entity "<investor>"
  And I am at the investor page
  When I create a new investor "<investor>" for the existing investor entity
  Then I should see the "<msg>"
  And an investor should be created
  And an investor entity should not be created
  And I should see the investor details on the details page
  And investor access stakeholders are "not visible"
  Given I click on "New Users"
  Given I fill the investor access form with "email=test@email.com;first_name=Test1;last_name=User1;phone=1234567890;approved=false"
  Given I click on "Save"
  Then I should see the "Added test@email.com to investor users"
  And I should see the new investor access in the investor access list
  Given I "approve" the investor access for "test@email.com"
  Then I should see the "Approved test@email.com"
  Given I "unapprove" the investor access for "test@email.com"
  Then I should see the "Un-approved test@email.com"
  Given I click on "Edit" for the investor access for "test@email.com"
  Given I fill the investor access form with "approved=true;cc=somecc1@gmail.com"
  Given I click on "Save"
  Then I should see the "Updated test@email.com"
  And I should see the updated investor access in the investor access list
  Given I "delete" the investor access for "test@email.com"
  Then I should see the "Destroyed test@email.com"
  And the investor access should be removed from the investor access list


  Examples:
  	|entity              |investor                         |msg	|
  	|entity_type=Company |investor_name=Accelo1;primary_email=a@b1.c   |Investor was successfully created|


Scenario Outline: Investor show page Investor Access turbo response checks
  Given Im logged in as a user "first_name=Mohith" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing investor entity "<investor>"
  And I am at the investor page
  When I create a new investor "<investor>" for the existing investor entity
  Then I should see the "<msg>"
  And an investor should be created
  And an investor entity should not be created
  And I should see the investor details on the details page
  And investor access stakeholders are "not visible"
  Given I click on "New Users"
  Given I fill the investor access form with "email=test@email.com;first_name=Test1;last_name=User1;phone=1234567890;approved=true"
  Given I click on "Save"
  Then I should see the "Added test@email.com to investor users"
  And I should see the new investor access in the investor access list
  Given I "unapprove" the investor access for "test@email.com"
  Then I should see the "Un-approved test@email.com"
  Given I "approve" the investor access for "test@email.com"
  Then I should see the "Approved test@email.com"
  # add second IA
  Given I click on "New Users"
  Given I fill the investor access form with "email=test2@email.com;first_name=Test2;last_name=User2;phone=1234567891;approved=true"
  Given I click on "Save"
  Then I should see the "Added test2@email.com to investor users"
  And I should see the new investor access in the investor access list
  Given I click on "Edit" for the investor access for "test2@email.com"
  Given I fill the investor access form with "approved=false;cc=somecc1@gmail.com"
  Given I click on "Save"
  Then I should see the "Updated test2@email.com"
  And I should see the updated investor access in the investor access list
  Given I "delete" the investor access for "test2@email.com"
  Then I should see the "Destroyed test2@email.com"
  And the investor access should be removed from the investor access list
  # add and immediately delete third IA
  Given I click on "New Users"
  Given I fill the investor access form with "email=test3@email.com;first_name=Test3;last_name=User3;phone=1234567892;approved=true"
  Given I click on "Save"
  Then I should see the "Added test3@email.com to investor users"
  And I should see the new investor access in the investor access list
  Given I "delete" the investor access for "test3@email.com"
  Then I should see the "Destroyed test3@email.com"
  And the investor access should be removed from the investor access list

  Examples:
  	|entity              |investor                         |msg	|
  	|entity_type=Company |investor_name=Accelo2;primary_email=a@b2.c   |Investor was successfully created|

Scenario Outline: All Investor Accesses page turbo response checks
  Given Im logged in as a user "first_name=Mohith" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing investor entity "<investor>"
  And I am at the investor page
  When I create a new investor "<investor>" for the existing investor entity
  Then I should see the "<msg>"
  And an investor should be created
  And an investor entity should not be created
  And I should see the investor details on the details page
  And investor access stakeholders are "not visible"
  Given I click on "New Users"
  Given I fill the investor access form with "email=test@email.com;first_name=Test1;last_name=User1;phone=1234567890;approved=true"
  Given I click on "Save"
  Then I should see the "Added test@email.com to investor users"
  And I should see the new investor access in the investor access list
  Given I go to all investor accesses page
  And investor access stakeholders are "visible"
  And I should see the new investor access in the investor access list
  Given I "unapprove" the investor access for "test@email.com"
  Then I should see the "Un-approved test@email.com"
  Given I "approve" the investor access for "test@email.com"
  Then I should see the "Approved test@email.com"
  # add second IA
  And I should see the investor details on the details page
  And investor access stakeholders are "not visible"
  Given I click on "New Users"
  Given I fill the investor access form with "email=test2@email.com;first_name=Test2;last_name=User2;phone=1234567891;approved=true"
  Given I click on "Save"
  Then I should see the "Added test2@email.com to investor users"
  And I should see the new investor access in the investor access list
  Given I go to all investor accesses page
  And investor access stakeholders are "visible"
  And I should see the new investor access in the investor access list
  Given I click on "Edit" for the investor access for "test2@email.com"
  Given I fill the investor access form with "approved=false;cc=somecc1@gmail.com"
  Given I click on "Save"
  Then I should see the "Updated test2@email.com"
  And I should see the updated investor access in the investor access list
  Given I "delete" the investor access for "test2@email.com"
  Then I should see the "Destroyed test2@email.com"
  And the investor access should be removed from the investor access list
  # act on third IA
  And I should see the investor details on the details page
  And investor access stakeholders are "not visible"
  Given I click on "New Users"
  Given I fill the investor access form with "email=test3@email.com;first_name=Test3;last_name=User3;phone=1234567892;approved=true"
  Given I click on "Save"
  Then I should see the "Added test3@email.com to investor users"
  And I should see the new investor access in the investor access list
  Given I go to all investor accesses page
  And investor access stakeholders are "visible"
  And I should see the new investor access in the investor access list
  Given I "delete" the investor access for "test3@email.com"
  Then I should see the "Destroyed test3@email.com"
  And the investor access should be removed from the investor access list

  Examples:
  	|entity              |investor                         |msg	|
  	|entity_type=Company |investor_name=Accelo3;primary_email=a@b3.c   |Investor was successfully created|
