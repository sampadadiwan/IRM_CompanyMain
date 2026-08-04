@javascript
Feature: Deal step activity access

  Scenario: Read-only employee cannot change deal activity status from grid view
    Given there is a user "email=readonly.employee@example.com;first_name=Read;last_name=Only" for an entity "entity_type=Company;enable_deals=true"
    And the user has role "employee"
    And given there is a deal "name=ReadOnly Deal;amount_cents=100000000;status=Open;currency=USD" for the entity
    And I manually start the deal
    And there is another user "first_name=Inv;last_name=User" for another entity "entity_type=Investor"
    And another entity is an investor "category=Lead Investor" in entity
    And another entity is a deal_investor "status=Active" in the deal
    And user "readonly.employee@example.com" has deals enabled
    And I am "yes" employee access to the deal
    And the current activity for investor "the other entity" is "Financial DD"
    And I am at the login page
    When I fill and submit the login page
    And I am on the grid view of the deal "ReadOnly Deal"
    And I try to change the activity "Financial DD" for investor "the other entity" from the grid
    Then I should see the "Access denied: you do not have permission to update this deal investor."
    And no deal activity patch request should be sent from the grid
    And the current activity for investor "the other entity" should still be "Financial DD"

  Scenario: Employee with create read and update access can change deal activity status from grid view
    Given there is an entity "name=Deal Access Entity;entity_type=Company;enable_deals=true"
    And there is a user "email=company.admin@example.com;first_name=Company;last_name=Admin" for the entity "name=Deal Access Entity"
    And the user "company.admin@example.com" has role "company_admin"
    And there is a user "email=deal.employee@example.com;first_name=Deal;last_name=Employee" for the entity "name=Deal Access Entity"
    And the user "deal.employee@example.com" has role "employee"
    And given there is a deal "name=Update Access Deal;amount_cents=100000000;status=Open;currency=USD" for the entity
    And I manually start the deal
    And I grant "create,read,update" access to the deal for user "deal.employee@example.com"
    And there is another user "first_name=Inv;last_name=User" for another entity "entity_type=Investor"
    And another entity is an investor "category=Lead Investor" in entity
    And another entity is a deal_investor "status=Active" in the deal
    And the current activity for investor "the other entity" is "Financial DD"
    And I log in with email "deal.employee@example.com"
    And I am on the grid view of the deal "Update Access Deal"
    When I mark the activity "Financial DD" as completed for investor "the other entity" in the grid
    Then the current activity for investor "the other entity" should be the next activity after "Financial DD"
