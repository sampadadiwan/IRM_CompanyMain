Feature: Tasks for Deal Steps

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Company"
    And the user has role "company_admin"
    And there exists a deal "name=Unicorn Series A;amount_cents=100000000;status=Open;currency=USD" for my company
    And I manually start the deal
    And there is another user "first_name=Inv;last_name=User" for another entity "entity_type=Investor"
    And another entity is an investor "category=Lead Investor" in entity
    And another entity is a deal_investor "status=Active" in the deal

  Scenario: Automatically generate tasks when a deal investor moves to a new step
    Given the deal step "Due Diligence" has the following tasks:
      """
      Verify Legal Docs
      Financial Audit
      Background Check
      """
    When I move the deal investor "the other entity" to the step "Due Diligence"
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

  Scenario: Automatically generate tasks from comma separated list
    Given the deal step "KYC" has the following tasks: "ID Verification, AML Check, Proof of Funds"
    When I move the deal investor "the other entity" to the step "KYC"
    Then the deal investor "the other entity" should have the following tasks:
      | details         |
      | ID Verification |
      | AML Check       |
      | Proof of Funds  |
