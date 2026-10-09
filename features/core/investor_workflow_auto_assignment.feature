Feature: Investor Workflow Auto-Assignment
  Investor workflows are distinguished by `category` rather than by a separate workflowable_type:
    - "Investor Onboarding" fires the moment a non-portfolio-company investor is created
      (catch-all, auto_launch).
    - A Portfolio Company template can be assigned on create (auto_launch false). KPI imports no
      longer launch it: KPI reports have their own journey (openspec/changes/kpi-report-journey,
      design Decision 10; covered by features/startup/kpi_report_journey.feature E14).

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Company"
    And the user has role "company_admin"

  # ── Investor Onboarding — fires on create for non-portfolio-company investors ─

  Scenario: Investor Onboarding is assigned and launched the moment a regular investor is created
    Given there is a workflow template "name=Investor Onboarding" with 1 step "name=Welcome & Data Room Access;states=Access Granted,Pending,Declined;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "Investor Onboarding" has workflowable_type "Investor"
    And there is an auto-assignment rule for template "Investor Onboarding" type "Investor" with conditions '[{"attribute":"category","operator":"not_eq","value":"Portfolio Company"}]' auto_launch true priority 0
    When there is an existing investor "name=Alice Sharma"
    Then the investor "Alice Sharma" should have workflow template "Investor Onboarding"
    And the investor "Alice Sharma" should have an active workflow instance

  Scenario: Investor Onboarding does not fire for a Portfolio Company investor
    Given there is a workflow template "name=Investor Onboarding" with 1 step "name=Welcome & Data Room Access;states=Access Granted,Pending,Declined;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "Investor Onboarding" has workflowable_type "Investor"
    And there is an auto-assignment rule for template "Investor Onboarding" type "Investor" with conditions '[{"attribute":"category","operator":"not_eq","value":"Portfolio Company"}]' auto_launch true priority 0
    When there is an existing portfolio company "name=Green Valley Foods"
    Then the investor "Green Valley Foods" should not have a workflow template

  Scenario: Investor Onboarding does not fire when no auto-assignment rule is configured
    Given there is a workflow template "name=Investor Onboarding" with 1 step "name=Welcome & Data Room Access;states=Access Granted,Pending,Declined;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "Investor Onboarding" has workflowable_type "Investor"
    When there is an existing investor "name=Bob Mehta"
    Then the investor "Bob Mehta" should not have a workflow template

  # ── Portfolio Company template — assigned on create, never launched by KPI imports ──

  Scenario: Portfolio Company KPI Report Review is assigned but NOT launched when the portfolio company is created
    Given there is a workflow template "name=Portfolio Company KPI Report Review" with 1 step "name=Data Accuracy Check;states=Accurate,Needs Correction,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "Portfolio Company KPI Report Review" has workflowable_type "Investor"
    And there is an auto-assignment rule for template "Portfolio Company KPI Report Review" type "Investor" with conditions '[{"attribute":"category","operator":"eq","value":"Portfolio Company"}]' auto_launch false priority 0
    When there is an existing portfolio company "name=Acme Robotics"
    Then the investor "Acme Robotics" should have workflow template "Portfolio Company KPI Report Review"
    And the investor "Acme Robotics" should not have an active workflow instance
