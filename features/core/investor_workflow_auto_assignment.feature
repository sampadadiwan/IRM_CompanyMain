Feature: Investor Workflow Auto-Assignment
  Investor covers two distinct workflow use cases, distinguished by `category`
  rather than by a separate workflowable_type:
    - "Investor Onboarding"                    fires the moment a non-portfolio-company
                                                 investor is created (catch-all, auto_launch).
    - "Portfolio Company KPI Report Review"    is assigned the moment a Portfolio Company
                                                 investor is created, but is NEVER auto-launched
                                                 by that rule. A fresh instance is only launched
                                                 explicitly, each time KPIs are imported for that
                                                 portfolio company's KPI report — because the
                                                 auto-assignment engine only ever assigns a
                                                 template ONCE per record, which is wrong for a
                                                 periodic event like a KPI upload.

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

  # ── Portfolio Company KPI Report Review — assigned once, launched per upload ──

  Scenario: Portfolio Company KPI Report Review is assigned but NOT launched when the portfolio company is created
    Given there is a workflow template "name=Portfolio Company KPI Report Review" with 1 step "name=Data Accuracy Check;states=Accurate,Needs Correction,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "Portfolio Company KPI Report Review" has workflowable_type "Investor"
    And there is an auto-assignment rule for template "Portfolio Company KPI Report Review" type "Investor" with conditions '[{"attribute":"category","operator":"eq","value":"Portfolio Company"}]' auto_launch false priority 0
    When there is an existing portfolio company "name=Acme Robotics"
    Then the investor "Acme Robotics" should have workflow template "Portfolio Company KPI Report Review"
    And the investor "Acme Robotics" should not have an active workflow instance

  Scenario: A new review instance launches the first time KPIs are imported for the portfolio company
    Given there is a workflow template "name=Portfolio Company KPI Report Review" with 1 step "name=Data Accuracy Check;states=Accurate,Needs Correction,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "Portfolio Company KPI Report Review" has workflowable_type "Investor"
    And there is an auto-assignment rule for template "Portfolio Company KPI Report Review" type "Investor" with conditions '[{"attribute":"category","operator":"eq","value":"Portfolio Company"}]' auto_launch false priority 0
    And there is an existing portfolio company "name=Blue Harbor Foods"
    And the investor "Blue Harbor Foods" should not have an active workflow instance
    And a KPI report shell exists for "Blue Harbor Foods" as of "2026-01-31"
    When Kpis are imported into the KPI report for "Blue Harbor Foods" as of "2026-01-31"
    Then the investor "Blue Harbor Foods" should have an active workflow instance

  Scenario: A second KPI import while a review is already active does not launch a second instance
    Given there is a workflow template "name=Portfolio Company KPI Report Review" with 1 step "name=Data Accuracy Check;states=Accurate,Needs Correction,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "Portfolio Company KPI Report Review" has workflowable_type "Investor"
    And there is an auto-assignment rule for template "Portfolio Company KPI Report Review" type "Investor" with conditions '[{"attribute":"category","operator":"eq","value":"Portfolio Company"}]' auto_launch false priority 0
    And there is an existing portfolio company "name=Cedar Point Logistics"
    And a KPI report shell exists for "Cedar Point Logistics" as of "2026-01-31"
    And Kpis are imported into the KPI report for "Cedar Point Logistics" as of "2026-01-31"
    And the investor "Cedar Point Logistics" should have an active workflow instance
    And a KPI report shell exists for "Cedar Point Logistics" as of "2026-02-28"
    When Kpis are imported into the KPI report for "Cedar Point Logistics" as of "2026-02-28"
    Then the investor "Cedar Point Logistics" should have an active workflow instance
    And the investor "Cedar Point Logistics" should have exactly 1 workflow instance in total

  Scenario: A fresh review launches on the next KPI import once the previous review is archived
    Given there is a workflow template "name=Portfolio Company KPI Report Review" with 1 step "name=Data Accuracy Check;states=Accurate,Needs Correction,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "Portfolio Company KPI Report Review" has workflowable_type "Investor"
    And there is an auto-assignment rule for template "Portfolio Company KPI Report Review" type "Investor" with conditions '[{"attribute":"category","operator":"eq","value":"Portfolio Company"}]' auto_launch false priority 0
    And there is an existing portfolio company "name=Dune Ridge Energy"
    And a KPI report shell exists for "Dune Ridge Energy" as of "2026-01-31"
    And Kpis are imported into the KPI report for "Dune Ridge Energy" as of "2026-01-31"
    And the investor "Dune Ridge Energy" should have an active workflow instance
    When I archive the active workflow for investor "Dune Ridge Energy"
    And a KPI report shell exists for "Dune Ridge Energy" as of "2026-02-28"
    And Kpis are imported into the KPI report for "Dune Ridge Energy" as of "2026-02-28"
    Then the investor "Dune Ridge Energy" should have an active workflow instance
    And the investor "Dune Ridge Energy" should have exactly 2 workflow instances in total
