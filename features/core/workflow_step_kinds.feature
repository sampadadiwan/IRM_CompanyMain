Feature: Workflow step kinds
  A workflow step is human (approvers vote — today's behaviour), system (passes when a registered
  data check passes) or acknowledge (one person confirms). Existing steps stay human, and a step's
  check must be registered for the template's record type.
  Worked examples E1, X1, X2 in openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples

  # E1 — Existing steps are human
  @rack_test
  Scenario Outline: Steps created without a kind are human and keep human states
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is a workflow template "name=KYC Review"
    When I add a step "name=Legal Review;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop" to the template
    Then step 1 should be of kind "human"
    And step 1 should have states "Approved,Rejected"
    And no step of the template should be evaluated from data

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # X1 — System step without a check
  Scenario Outline: A system step needs a check registered for the template's record type
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is a workflow template "name=Call Journey;workflowable_type=CapitalCall"
    When I try to add a "system" step "Remittances" with check ""
    Then the step should not be saved with the error "Check must be a Capital Call check"

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # X2 — Check list scoped to the record type
  @rack_test
  Scenario Outline: Only checks for the template's record type can be chosen
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is a workflow template "name=Call Journey;workflowable_type=CapitalCall"
    Then the check options for the template should include "test.flag_1"
    And the check options for the template should not include "test_kyc.flag"
    When I try to add a "system" step "KYC check" with check "test_kyc.flag"
    Then the step should not be saved with the error "Check must be a Capital Call check"
    When I try to add a "system" step "Flag one" with check "test.flag_1"
    Then the step should be saved with kind "system" and states "Passed"

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # X1 / X2 through the step editor screen
  @rack_test
  Scenario Outline: The step editor offers kinds and only matching checks
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is a workflow template "name=Call Journey;workflowable_type=CapitalCall"
    When I visit the new step page for the workflow template "Call Journey"
    Then I should see the step kinds "Human, System, Acknowledge"
    And the Check list should offer "Test flag 1" and not "Test kyc flag"
    When I fill in the step name "Remittances", choose kind "System" and save without a check
    Then I should see "Check must be a Capital Call check"

    Examples:
      | user | entity              |
      |      | entity_type=Company |
