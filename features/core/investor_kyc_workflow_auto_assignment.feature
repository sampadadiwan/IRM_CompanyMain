Feature: InvestorKyc Workflow Auto-Assignment
  Three templates cover the full KYC lifecycle, each triggered at a different point:
    - "KYC Onboarding Kick-off"     fires the moment a KYC record is created (catch-all)
    - "KYC Submission Review"       fires when the investor marks the form complete
    - "Post-Verification KYC Audit" fires when the fund marks the KYC as verified

  The idempotency guard ensures only ONE template ever auto-assigns to a given KYC —
  whichever rule fires first wins; later triggers are skipped.

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Company"
    And the user has role "company_admin"

  # ── KYC Onboarding Kick-off — fires on create ─────────────────────────────────

  Scenario: KYC Onboarding Kick-off is assigned and launched the moment a KYC is created
    Given there is a workflow template "name=KYC Onboarding Kick-off" with 1 step "name=Investor Outreach;states=Link Sent,No Response,Declined;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "KYC Onboarding Kick-off" has workflowable_type "InvestorKyc"
    And there is an auto-assignment rule for template "KYC Onboarding Kick-off" type "InvestorKyc" with conditions "[]" auto_launch true priority 0
    When the entity has an investor_kyc "name=Alice Sharma"
    Then the investor_kyc "Alice Sharma" should have workflow template "KYC Onboarding Kick-off"
    And the investor_kyc "Alice Sharma" should have an active workflow instance

  Scenario: KYC Onboarding Kick-off does not fire when no auto-assignment rule is configured
    Given there is a workflow template "name=KYC Onboarding Kick-off" with 1 step "name=Investor Outreach;states=Link Sent,No Response,Declined;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "KYC Onboarding Kick-off" has workflowable_type "InvestorKyc"
    When the entity has an investor_kyc "name=Bob Mehta"
    Then the investor_kyc "Bob Mehta" should not have a workflow template

  # ── KYC Submission Review — fires when completed_by_investor = true ───────────

  Scenario: KYC Submission Review is not assigned on create because completed_by_investor is still false
    Given there is a workflow template "name=KYC Submission Review" with 1 step "name=Document Verification;states=Verified,Incomplete,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "KYC Submission Review" has workflowable_type "InvestorKyc"
    And there is an auto-assignment rule for template "KYC Submission Review" type "InvestorKyc" with conditions '[{"attribute":"completed_by_investor","operator":"eq","value":"true"}]' auto_launch true priority 0
    When the entity has an investor_kyc "name=Priya Patel"
    Then the investor_kyc "Priya Patel" should not have a workflow template

  Scenario: KYC Submission Review fires when the investor marks the form as complete
    Given there is a workflow template "name=KYC Submission Review" with 1 step "name=Document Verification;states=Verified,Incomplete,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "KYC Submission Review" has workflowable_type "InvestorKyc"
    And there is an auto-assignment rule for template "KYC Submission Review" type "InvestorKyc" with conditions '[{"attribute":"completed_by_investor","operator":"eq","value":"true"}]' auto_launch true priority 0
    And the entity has an investor_kyc "name=Rakesh Gupta"
    And the investor_kyc "Rakesh Gupta" should not have a workflow template
    When I update the investor_kyc "Rakesh Gupta" attribute "completed_by_investor" to "true"
    Then the investor_kyc "Rakesh Gupta" should have workflow template "KYC Submission Review"
    And the investor_kyc "Rakesh Gupta" should have an active workflow instance

  # ── Post-Verification KYC Audit — fires when verified = true ─────────────────

  Scenario: Post-Verification KYC Audit is not assigned on create
    Given there is a workflow template "name=Post-Verification KYC Audit" with 1 step "name=Compliance File Audit;states=Audit Passed,Exceptions Found,Audit Failed;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "Post-Verification KYC Audit" has workflowable_type "InvestorKyc"
    And there is an auto-assignment rule for template "Post-Verification KYC Audit" type "InvestorKyc" with conditions '[{"attribute":"verified","operator":"eq","value":"true"}]' auto_launch false priority 0
    When the entity has an investor_kyc "name=Deepa Krishnan"
    Then the investor_kyc "Deepa Krishnan" should not have a workflow template

  Scenario: Post-Verification KYC Audit does not fire when only completed_by_investor flips to true
    Given there is a workflow template "name=Post-Verification KYC Audit" with 1 step "name=Compliance File Audit;states=Audit Passed,Exceptions Found,Audit Failed;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "Post-Verification KYC Audit" has workflowable_type "InvestorKyc"
    And there is an auto-assignment rule for template "Post-Verification KYC Audit" type "InvestorKyc" with conditions '[{"attribute":"verified","operator":"eq","value":"true"}]' auto_launch false priority 0
    And the entity has an investor_kyc "name=Suresh Nair"
    When I update the investor_kyc "Suresh Nair" attribute "completed_by_investor" to "true"
    Then the investor_kyc "Suresh Nair" should not have a workflow template

  Scenario: Post-Verification KYC Audit fires when the KYC is marked as verified
    Given there is a workflow template "name=Post-Verification KYC Audit" with 1 step "name=Compliance File Audit;states=Audit Passed,Exceptions Found,Audit Failed;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "Post-Verification KYC Audit" has workflowable_type "InvestorKyc"
    And there is an auto-assignment rule for template "Post-Verification KYC Audit" type "InvestorKyc" with conditions '[{"attribute":"verified","operator":"eq","value":"true"}]' auto_launch false priority 0
    And the entity has an investor_kyc "name=Meena Iyer"
    And the investor_kyc "Meena Iyer" should not have a workflow template
    When I update the investor_kyc "Meena Iyer" attribute "verified" to "true"
    Then the investor_kyc "Meena Iyer" should have workflow template "Post-Verification KYC Audit"

  # ── Idempotency — first assignment blocks later triggers ─────────────────────

  Scenario: Kick-off template assigned on create blocks Submission Review from re-assigning when investor completes
    Given there is a workflow template "name=KYC Onboarding Kick-off" with 1 step "name=Investor Outreach;states=Link Sent,No Response,Declined;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "KYC Onboarding Kick-off" has workflowable_type "InvestorKyc"
    And there is an auto-assignment rule for template "KYC Onboarding Kick-off" type "InvestorKyc" with conditions "[]" auto_launch false priority 0
    And there is a workflow template "name=KYC Submission Review" with 1 step "name=Document Verification;states=Verified,Incomplete,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "KYC Submission Review" has workflowable_type "InvestorKyc"
    And there is an auto-assignment rule for template "KYC Submission Review" type "InvestorKyc" with conditions '[{"attribute":"completed_by_investor","operator":"eq","value":"true"}]' auto_launch false priority 0
    And the entity has an investor_kyc "name=Dev Kapoor"
    And the investor_kyc "Dev Kapoor" should have workflow template "KYC Onboarding Kick-off"
    When I update the investor_kyc "Dev Kapoor" attribute "completed_by_investor" to "true"
    Then the investor_kyc "Dev Kapoor" should still have workflow template "KYC Onboarding Kick-off"
    And the investor_kyc "Dev Kapoor" should have exactly 1 workflow assignment

  Scenario: Submission Review assigned on investor completion blocks Post-Verification Audit from re-assigning
    Given there is a workflow template "name=KYC Submission Review" with 1 step "name=Document Verification;states=Verified,Incomplete,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "KYC Submission Review" has workflowable_type "InvestorKyc"
    And there is an auto-assignment rule for template "KYC Submission Review" type "InvestorKyc" with conditions '[{"attribute":"completed_by_investor","operator":"eq","value":"true"}]' auto_launch false priority 0
    And there is a workflow template "name=Post-Verification KYC Audit" with 1 step "name=Compliance File Audit;states=Audit Passed,Exceptions Found,Audit Failed;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "Post-Verification KYC Audit" has workflowable_type "InvestorKyc"
    And there is an auto-assignment rule for template "Post-Verification KYC Audit" type "InvestorKyc" with conditions '[{"attribute":"verified","operator":"eq","value":"true"}]' auto_launch false priority 0
    And the entity has an investor_kyc "name=Ananya Singh"
    And the investor_kyc "Ananya Singh" should not have a workflow template
    When I update the investor_kyc "Ananya Singh" attribute "completed_by_investor" to "true"
    And the investor_kyc "Ananya Singh" should have workflow template "KYC Submission Review"
    When I update the investor_kyc "Ananya Singh" attribute "verified" to "true"
    Then the investor_kyc "Ananya Singh" should still have workflow template "KYC Submission Review"
    And the investor_kyc "Ananya Singh" should have exactly 1 workflow assignment
