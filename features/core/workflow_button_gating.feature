Feature: Workflow Button Gating
  A WorkflowTemplate can name specific buttons (by their visible label, not DOM id) via
  gated_button_labels, so admins can configure this without touching code. Those buttons
  are disabled client-side (via the workflow-gate Stimulus controller) while the
  workflowable object's current workflow instance is Incomplete (active) or Failed
  (rejected), and re-enabled once it Completes. This is a JS/UX gate, not a server-side
  authorization check — it only changes what's rendered as disabled on the show page.
  Worked examples E2 in openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Company"
    And the user has role "company_admin"

  Scenario Outline: Gated button is disabled while the workflow is incomplete
    Given there is a workflow template "name=KYC Edit Lock" with 1 step "name=Step 1;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "KYC Edit Lock" has workflowable_type "InvestorKyc"
    And the workflow template "KYC Edit Lock" has gated_button_labels "Edit"
    And the entity has an investor_kyc "name=Gated Kyc"
    And the investor_kyc "Gated Kyc" has workflow template "KYC Edit Lock"
    And the investor_kyc "Gated Kyc" has an active workflow instance for "KYC Edit Lock"
    When I visit the investor_kyc show page for "Gated Kyc"
    Then the button labeled "Edit" should be disabled

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  Scenario Outline: Gated button re-enables once the workflow completes
    Given there is a workflow template "name=KYC Edit Lock" with 1 step "name=Step 1;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "KYC Edit Lock" has workflowable_type "InvestorKyc"
    And the workflow template "KYC Edit Lock" has gated_button_labels "Edit"
    And the entity has an investor_kyc "name=Completing Kyc"
    And the investor_kyc "Completing Kyc" has workflow template "KYC Edit Lock"
    And the investor_kyc "Completing Kyc" has an active workflow instance for "KYC Edit Lock"
    When the actor submits "Approved" on the current step of the investor_kyc "Completing Kyc"
    And I visit the investor_kyc show page for "Completing Kyc"
    Then the button labeled "Edit" should not be disabled

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  Scenario Outline: Gated button stays disabled once the workflow fails
    Given there is a workflow template "name=KYC Edit Lock" with 1 step "name=Step 1;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "KYC Edit Lock" has workflowable_type "InvestorKyc"
    And the workflow template "KYC Edit Lock" has gated_button_labels "Edit"
    And the entity has an investor_kyc "name=Failing Kyc"
    And the investor_kyc "Failing Kyc" has workflow template "KYC Edit Lock"
    And the investor_kyc "Failing Kyc" has an active workflow instance for "KYC Edit Lock"
    When the actor submits "Rejected" on the current step of the investor_kyc "Failing Kyc"
    And I visit the investor_kyc show page for "Failing Kyc"
    Then the button labeled "Edit" should be disabled

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  Scenario Outline: A button not listed in gated_button_labels is unaffected
    Given there is a workflow template "name=KYC Edit Lock" with 1 step "name=Step 1;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "KYC Edit Lock" has workflowable_type "InvestorKyc"
    And the workflow template "KYC Edit Lock" has gated_button_labels "Edit"
    And the entity has an investor_kyc "name=Partially Gated Kyc"
    And the investor_kyc "Partially Gated Kyc" has workflow template "KYC Edit Lock"
    And the investor_kyc "Partially Gated Kyc" has an active workflow instance for "KYC Edit Lock"
    When I visit the investor_kyc show page for "Partially Gated Kyc"
    Then the button labeled "Delete" should not be disabled

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  Scenario Outline: Gate is opt-in -- an object that never had a workflow launched is never gated
    Given there is a workflow template "name=KYC Edit Lock" with 1 step "name=Step 1;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "KYC Edit Lock" has workflowable_type "InvestorKyc"
    And the workflow template "KYC Edit Lock" has gated_button_labels "Edit"
    And the entity has an investor_kyc "name=Untouched Kyc"
    And the investor_kyc "Untouched Kyc" has workflow template "KYC Edit Lock"
    When I visit the investor_kyc show page for "Untouched Kyc"
    Then the button labeled "Edit" should not be disabled

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # E2 (capital-call-journey) — journeys only warn in this release; they never disable buttons,
  # while the human-only scenarios above keep today's gating unchanged
  Scenario Outline: A journey with gated button labels does not disable buttons
    Given there is a journey template "KYC Journey" with steps:
      | name      | kind   | check       |
      | Documents | system | test.flag_1 |
    And the workflow template "KYC Journey" has gated_button_labels "Edit"
    And the entity has an investor_kyc "name=Journey Kyc"
    And the investor_kyc "Journey Kyc" has workflow template "KYC Journey"
    And I launch the workflow for investor_kyc "Journey Kyc"
    When I visit the investor_kyc show page for "Journey Kyc"
    Then the button labeled "Edit" should not be disabled

    Examples:
      | user | entity              |
      |      | entity_type=Company |
