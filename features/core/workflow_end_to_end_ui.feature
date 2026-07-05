Feature: Workflow End-to-End via the UI
  Every workflowable object type (Folder, Investor KYC, Capital Commitment, Capital Call,
  Approval) exposes a Workflow tab on its show page. This feature drives the entire
  lifecycle — launch, in-app actor response, completion — through real browser
  interactions (clicking the tab, using the Launch Workflow modal, filling in the
  actor response form) rather than calling services/models directly, so a regression
  in any of that UI wiring is actually caught.

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Company"
    And the user has role "company_admin"

  Scenario Outline: End-to-end via UI: launch, respond, and complete a workflow on a folder
    Given there is a workflow template "name=E2E Folder Review" with 1 step "name=Sign-off;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "E2E Folder Review" has workflowable_type "Folder"
    And the entity has a folder "name=E2E Folder"
    And the folder "E2E Folder" has workflow template "E2E Folder Review"
    When I visit the folder show page for "E2E Folder"
    And I open the Workflow tab
    And I launch the workflow "E2E Folder Review" from the launch modal
    Then I should see a flash notice containing "Workflow launched"
    When I open the Workflow tab
    And I click "View Full Workflow Timeline"
    And I submit "Approved" via the in-app response form
    Then the folder "E2E Folder" should have workflow status "complete"

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  Scenario Outline: End-to-end via UI: launch, respond, and complete a workflow on an investor KYC
    Given there is a workflow template "name=E2E KYC Review" with 1 step "name=Sign-off;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "E2E KYC Review" has workflowable_type "InvestorKyc"
    And the entity has an investor_kyc "name=E2E Kyc"
    And the investor_kyc "E2E Kyc" has workflow template "E2E KYC Review"
    When I visit the investor_kyc show page for "E2E Kyc"
    And I open the Workflow tab
    And I launch the workflow "E2E KYC Review" from the launch modal
    Then I should see a flash notice containing "Workflow launched"
    When I open the Workflow tab
    And I click "View Full Workflow Timeline"
    And I submit "Approved" via the in-app response form
    Then the investor_kyc "E2E Kyc" should have workflow status "complete"

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  Scenario Outline: End-to-end via UI: launch, respond, and complete a workflow on a capital commitment
    Given there is a workflow template "name=E2E Commitment Review" with 1 step "name=Sign-off;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "E2E Commitment Review" has workflowable_type "CapitalCommitment"
    And the entity has a capital_commitment "name=E2E Commitment"
    And the capital_commitment "E2E Commitment" has workflow template "E2E Commitment Review"
    When I visit the capital_commitment show page for "E2E Commitment"
    And I open the Workflow tab
    And I launch the workflow "E2E Commitment Review" from the launch modal
    Then I should see a flash notice containing "Workflow launched"
    When I open the Workflow tab
    And I click "View Full Workflow Timeline"
    And I submit "Approved" via the in-app response form
    Then the capital_commitment "E2E Commitment" should have workflow status "complete"

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  Scenario Outline: End-to-end via UI: launch, respond, and complete a workflow on a capital call
    Given there is a workflow template "name=E2E Call Review" with 1 step "name=Sign-off;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "E2E Call Review" has workflowable_type "CapitalCall"
    And the entity has a capital_call "name=E2E Call"
    And the capital_call "E2E Call" has workflow template "E2E Call Review"
    When I visit the capital_call show page for "E2E Call"
    And I open the Workflow tab
    And I launch the workflow "E2E Call Review" from the launch modal
    Then I should see a flash notice containing "Workflow launched"
    When I open the Workflow tab
    And I click "View Full Workflow Timeline"
    And I submit "Approved" via the in-app response form
    Then the capital_call "E2E Call" should have workflow status "complete"

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  Scenario Outline: End-to-end via UI: launch, respond, and complete a workflow on an approval
    Given there is a workflow template "name=E2E Approval Review" with 1 step "name=Sign-off;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "E2E Approval Review" has workflowable_type "Approval"
    And the entity has an approval "name=E2E Approval"
    And the approval "E2E Approval" has workflow template "E2E Approval Review"
    When I visit the approval show page for "E2E Approval"
    And I open the Workflow tab
    And I launch the workflow "E2E Approval Review" from the launch modal
    Then I should see a flash notice containing "Workflow launched"
    When I open the Workflow tab
    And I click "View Full Workflow Timeline"
    And I submit "Approved" via the in-app response form
    Then the approval "E2E Approval" should have workflow status "complete"

    Examples:
      | user | entity              |
      |      | entity_type=Company |
