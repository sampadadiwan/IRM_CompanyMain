Feature: Capital distribution journey — rollout
  The rollout task, new-company setup and the Workflow Templates button all run the same setup: the
  Full and Light distribution journeys, their auto-assignment rules and the workflow templates
  permission. It is a dry run unless EXECUTE=1, is safe to re-run, and never gives a journey to a
  distribution that already exists.
  Worked examples H1, H10, E19, E20, E25, X3 in
  openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;enable_funds=true;currency=INR"
    And the user has role "company_admin"
    And there is an existing investor "" with "1" users
    And there is a fund "name=Growth Fund II;currency=INR" for the entity
    And the investors are added to the fund
    And there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And the entity's capital distribution journeys are removed

  # H1 — the dry run reports the plan and writes nothing
  @rack_test
  Scenario: The dry run reports the plan and changes nothing
    When I run the distribution journey rollout for the entity
    Then the rollout output should mention "DRY RUN"
    And the rollout output should mention "templates: capital_distribution_full, capital_distribution_light"
    And the entity should have no capital distribution journeys

  # H1 — seeding through the rake task
  @rack_test
  Scenario: Running the rollout seeds both journeys, the rules and the permission
    When I run the distribution journey rollout for the entity with EXECUTE
    Then the entity should have the Full distribution journey with 10 tasks and the Light one with 3 tasks
    And imported distributions should go to Light and other distributions to Full
    And the entity should have workflow templates enabled

  # H1 — a new fund company gets the distribution journeys too (SetupCompany)
  @rack_test
  Scenario: A new fund company is set up with the distribution journeys
    When a new fund company is created
    Then the new company should have the Full distribution journey with 10 tasks and the Light one with 3 tasks

  # E19 — a distribution that existed before the rollout gets no journey
  Scenario: A distribution that existed before the rollout gets no journey
    Given there is a capital distribution "title=Q3 2026 Exit Proceeds;income_cents=300000000;approved=false"
    When I run the distribution journey rollout for the entity with EXECUTE
    Then the distribution has no journey

  # E20 — re-running keeps an admin's changes and creates nothing twice
  @rack_test
  Scenario: Re-running the rollout keeps an admin's added step and creates nothing twice
    Given I run the distribution journey rollout for the entity with EXECUTE
    And the Full distribution journey has a "CFO sign-off" approval step before "Approve distribution"
    When I run the distribution journey rollout for the entity with EXECUTE
    Then the entity should have exactly 1 Full and 1 Light distribution journey
    And the Full distribution journey should still have a "CFO sign-off" step
    And the entity should have exactly 2 capital distribution auto-assignment rules

  # E25 — a Full journey set up before the CFO sign-off existed gets it on the next setup, with no approver
  @rack_test
  Scenario: Re-running the rollout adds the CFO sign-off to an older Full journey
    Given I run the distribution journey rollout for the entity with EXECUTE
    And the Full distribution journey has no "CFO sign-off" step
    When I run the distribution journey rollout for the entity
    Then the rollout output should mention "add CFO sign-off to the Full journey"
    When I run the distribution journey rollout for the entity with EXECUTE
    Then the Full distribution journey should have a "CFO sign-off" step with no approver before "Approve distribution"

  # H10 — a company admin sets the journeys up from the Workflow Templates page
  Scenario: A company admin sets up the distribution journeys from the Workflow Templates page
    When I open the Workflow Templates page
    And I choose "Set up capital distribution journeys" from the Set up journeys menu and proceed
    Then I should see "Capital distribution journeys set up: Full and Light journeys, auto-assignment rules. New distributions will get a journey." on the page
    And the entity should have the Full distribution journey with 10 tasks and the Light one with 3 tasks
    And the Set up journeys menu should show "Capital distribution journeys set up" as done

  # X3 — not offered to a user who is not a company admin, and a direct request is refused
  Scenario: The distribution setup button is not offered to a user who is not a company admin
    Given the user is no longer a company admin
    When I open the Workflow Templates page
    Then the Set up journeys menu should not be shown
    When I send the "capital_distribution" journey setup request directly
    Then I should see "Access Denied" on the page
    And the entity should have no capital distribution journeys
