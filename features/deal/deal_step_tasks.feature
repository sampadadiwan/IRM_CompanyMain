@javascript
Feature: Tasks for Deal Steps

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Company"
    And the user has role "company_admin"
    And there exists a deal "name=Unicorn Series A;amount_cents=100000000;status=Open;currency=USD" for my company
    And I manually start the deal
    And there is another user "first_name=Inv;last_name=User" for another entity "entity_type=Investor"
    And another entity is an investor "category=Lead Investor" in entity
    And another entity is a deal_investor "status=Active" in the deal

  Scenario: New deal task shows deal investors in For
    Given I am on the deal tasks page for "Unicorn Series A"
    When I open the new task form
    Then the task For field should have deal investor options

  Scenario: Automatically generate tasks when a deal activity is completed in Grid View
    Given the deal step "Legal DD" has the following tasks: "Verify Legal, Financial Audit"
    And I am on the grid view of the deal "Unicorn Series A"
    When I mark the activity "Financial DD" as completed for investor "the other entity" in the grid
    Then the current activity for investor "the other entity" should be the next activity after "Financial DD"
    And the deal investor "the other entity" should have the following tasks:
      | details         |
      | Verify Legal    |
      | Financial Audit |

  Scenario: Automatically generate tasks when a deal investor moves to a new step
    Given the deal step "Financial DD" has the following tasks:
      """
      Verify Legal Docs
      Financial Audit
      Background Check
      """
    When I move the deal investor "the other entity" to the step "Financial DD"
    Then the deal investor "the other entity" should have the following tasks:
      | details           |
      | Verify Legal Docs |
      | Financial Audit   |
      | Background Check  |
    And I should see "Verify Legal Docs" in the deal tasks view

  Scenario: Tasks are copied from template to investor activities
    Given the deal step "Term Sheet" has the following tasks:
      """
      Draft Term Sheet
      """
    When I move the deal investor "the other entity" to the step "Term Sheet"
    Then the deal investor "the other entity" should have the following tasks:
      | details          |
      | Draft Term Sheet |

  Scenario: Automatically generate tasks when a previous deal activity is completed
    Given the deal step "Financial DD" has the following tasks: "Step 1 Task"
    And the deal step "Legal DD" has the following tasks: "Step 2 Task"
    And the current activity for investor "the other entity" is "Legal DD"
    And I visit the deal details page
    When I mark the activity "Financial DD" as completed for investor "the other entity" in the grid
    Then the current activity for investor "the other entity" should still be "Legal DD"
    And the deal investor "the other entity" should have the following tasks:
      | details     |
      | Step 2 Task |

  Scenario: Automatically generate tasks from comma separated list
    Given the deal step "KYC" has the following tasks: "ID Verification, AML Check, Proof of Funds"
    When I move the deal investor "the other entity" to the step "KYC"
    Then the deal investor "the other entity" should have the following tasks:
      | details         |
      | ID Verification |
      | AML Check       |
      | Proof of Funds  |

