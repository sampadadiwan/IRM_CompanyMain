Feature: Investor KYC journey — rollout
  The rollout task, new-company setup and the Workflow Templates menu all run the same setup: one
  "Investor KYC" journey, a catch-all auto-assignment rule (the default every KYC form type uses unless
  a form-type rule says otherwise) and the workflow templates permission. Investment and Angel Funds
  get it. It is a dry run unless EXECUTE=1, is safe to re-run, and never gives a journey to a KYC that
  already exists.
  Worked examples H1, H11, E18, E19, E20, X3, X4 in
  openspec/changes/investor-kyc-journey/design.md#worked-examples

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;enable_kycs=true"
    And the user has role "company_admin"
    And there is an existing investor "" with "1" users
    And the entity's investor KYC journeys are removed

  # H1 — the dry run reports the plan and writes nothing
  Scenario: The dry run reports the plan and changes nothing
    When I run the KYC journey rollout for the entity
    Then the rollout output should mention "DRY RUN"
    And the rollout output should mention "templates: investor_kyc_full"
    And the rollout output should mention "rules: all_to_full"
    And the entity should have no investor KYC journey

  # H1 — seeding through the rake task
  Scenario: Running the rollout seeds the journey, the rule and the permission
    When I run the KYC journey rollout for the entity with EXECUTE
    Then the entity should have the investor KYC journey with 9 tasks
    And every new KYC should go to the investor KYC journey
    And the entity should have workflow templates enabled

  # H1 — new fund and angel fund companies get it (SetupCompany)
  Scenario: New fund and angel fund companies are set up with the KYC journey
    When a new fund company is created
    Then the new company should have the investor KYC journey with 9 tasks
    When a new angel fund company is created
    Then the new company should have the investor KYC journey with 9 tasks

  # E18 — a KYC that existed before the rollout gets no journey
  Scenario: A KYC that existed before the rollout gets no journey
    Given there is an individual KYC for the investor
    When I run the KYC journey rollout for the entity with EXECUTE
    Then the KYC has no journey

  # E19 — re-running keeps an admin's changes and creates nothing twice
  Scenario: Re-running the rollout keeps an admin's edits and creates nothing twice
    Given I run the KYC journey rollout for the entity with EXECUTE
    And I am the approver on the Compliance sign-off
    And the investor KYC journey's "Run AML screening" task is removed
    When I run the KYC journey rollout for the entity with EXECUTE
    Then the entity should have exactly 1 investor KYC journey and 1 KYC auto-assignment rule
    And the investor KYC journey should have no "Run AML screening" task
    And the Compliance sign-off should still have me as approver

  # E20 — an entity with its own KYC rule keeps it; the journey template is added without a rule
  Scenario: An entity that already routes KYCs gets the template but no rule
    Given the entity has its own human approval workflow for KYCs
    When I run the KYC journey rollout for the entity
    Then the rollout output should mention "templates: investor_kyc_full"
    And the rollout output should not mention "rules:"
    When I run the KYC journey rollout for the entity with EXECUTE
    Then the entity should have exactly 1 investor KYC journey and 1 KYC auto-assignment rule

  # H11 — a company admin sets the journey up from the Workflow Templates page
  Scenario: A company admin sets up the KYC journey from the Workflow Templates page
    When I open the Workflow Templates page
    And I choose "Set up investor KYC journeys" from the Set up journeys menu and proceed
    Then I should see "Investor KYC journeys set up: KYC journey, auto-assignment rule. New KYCs will get a journey." on the page
    And the entity should have the investor KYC journey with 9 tasks
    And the Set up journeys menu should show "Investor KYC journeys set up" as done

  # X3 — not offered to a user who is not a company admin, and a direct request is refused
  Scenario: The KYC setup is not offered to a user who is not a company admin
    Given the user is no longer a company admin
    When I open the Workflow Templates page
    Then the Set up journeys menu should not be shown
    When I send the "investor_kyc" journey setup request directly
    Then I should see "Access Denied" on the page
    And the entity should have no investor KYC journey

  # X4 — an Angel Fund admin is offered only the KYC journey; setting up calls is refused
  Scenario: An Angel Fund admin is offered only the KYC journey
    Given I log out
    And Im logged in as a user "" for an entity "entity_type=Angel Fund;enable_kycs=true"
    And the user has role "company_admin"
    And the entity's investor KYC journeys are removed
    When I open the Workflow Templates page
    Then the Set up journeys menu should offer only "Set up investor KYC journeys"
    When I send the "capital_call" journey setup request directly
    Then I should see "Access Denied" on the page

  # E25 — one default journey; a duplicated journey for one form type, by a form-type rule
  Scenario: One default journey, and a specific journey for one KYC form type
    Given the entity's investor KYC journeys are seeded
    And the entity has the KYC form types "Individual — Default, Individual — Fund IV, Non Individual — Default"
    When a KYC is created with each form type
    Then the KYCs should have the journeys:
      | form type                 | journey      |
      | Individual — Default      | Investor KYC |
      | Individual — Fund IV      | Investor KYC |
      | Non Individual — Default  | Investor KYC |
    When I open the "Investor KYC" workflow template and click Duplicate
    And the template "Copy of Investor KYC" is renamed "Investor KYC — Fund IV"
    And I add an auto-assignment rule to "Investor KYC — Fund IV" for the KYC form type "Individual — Fund IV" with priority 50
    Then the rule for "Investor KYC — Fund IV" should match only the form type "Individual — Fund IV"
    When a KYC is created with each form type
    Then the KYCs should have the journeys:
      | form type                 | journey                |
      | Individual — Default      | Investor KYC           |
      | Individual — Fund IV      | Investor KYC — Fund IV |
      | Non Individual — Default  | Investor KYC           |

  # E26 — Duplicate copies every task; setup does not touch the copy
  Scenario: Duplicating the KYC journey copies its tasks and setup leaves the copy alone
    Given the entity's investor KYC journeys are seeded
    When I open the "Investor KYC" workflow template and click Duplicate
    Then the template "Copy of Investor KYC" should have the same 9 tasks as "Investor KYC"
    When I run the KYC journey rollout for the entity
    Then the rollout output should mention "already set up"
    And the template "Copy of Investor KYC" should have the same 9 tasks as "Investor KYC"

  # E27 — the rule form lists only this entity's KYC form types
  Scenario: The rule form lists this entity's KYC form types
    Given the entity's investor KYC journeys are seeded
    And the entity has the KYC form types "Individual — Fund IV, Non Individual — Fund IV"
    And another entity has its own KYC form type "Other Co"
    Then the KYC form type list on a new rule for "Investor KYC" should be exactly "Any type — Default, Individual — Default, Individual — Fund IV, Non Individual — Default, Non Individual — Fund IV"

  # Review fix — the picker and typed JSON conditions together save, and a typed form_type_id is replaced
  Scenario: A KYC rule with other JSON conditions and a form type saves both
    Given the entity's investor KYC journeys are seeded
    And the entity has the KYC form types "Individual — Fund IV"
    When I add an auto-assignment rule to "Investor KYC" for the KYC form type "Individual — Fund IV" with other conditions:
      """
      [{"attribute":"kyc_type","operator":"eq","value":"Individual"},{"attribute":"form_type_id","operator":"eq","value":"999"}]
      """
    Then the rule for "Investor KYC" should have the conditions:
      """
      [{"attribute":"kyc_type","operator":"eq","value":"Individual"},{"attribute":"form_type_id","operator":"eq","value":"<form type id>"}]
      """
