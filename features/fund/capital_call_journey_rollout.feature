Feature: Capital call journey — rollout
  The rollout task seeds the Full and Light journeys, their auto-assignment rules and the workflow
  templates permission for fund entities. It is a dry run unless EXECUTE=1, is safe to re-run, and
  never gives a journey to a call that already exists.
  Worked examples H1, H10, H11, E14, E15 in
  openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;enable_funds=true;currency=INR"
    And the user has role "company_admin"
    And there is an existing investor "" with "1" users
    And there is a fund "name=Alpha Fund I" for the entity
    And the investors are added to the fund
    And there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And the entity's capital call journeys are removed

  # H11 — Dry run writes nothing
  @rack_test
  Scenario: The dry run reports the plan and changes nothing
    When I run the journey rollout for the entity
    Then the rollout output should mention "DRY RUN"
    And the rollout output should mention "templates: capital_call_full, capital_call_light"
    And the entity should have no capital call journeys

  # H1 — Seeding
  @rack_test
  Scenario: Running the rollout seeds both journeys, the rules and the permission
    When I run the journey rollout for the entity with EXECUTE
    Then the entity should have the Full journey with 12 tasks and the Light journey with 4 tasks
    And imported calls should go to Light and other calls to Full
    And the entity should have workflow templates enabled

  # H10 — calls created after the rollout get a journey
  @rack_test
  Scenario: A call created after the rollout gets the Full journey
    Given I run the journey rollout for the entity with EXECUTE
    When there is a capital call "percentage_called=10"
    Then the call has the "Capital Call — Full: Notify Investors" journey

  # E15 — existing calls are untouched
  Scenario: A call that existed before the rollout gets no journey
    Given there is a capital call "percentage_called=10"
    When I run the journey rollout for the entity with EXECUTE
    Then the call has no journey

  # E14 — re-running keeps an admin's changes
  @rack_test
  Scenario: Re-running the rollout keeps an admin's added step and creates nothing twice
    Given I run the journey rollout for the entity with EXECUTE
    And the Full journey has a "CFO sign-off" approval step before "Approve call"
    When I run the journey rollout for the entity with EXECUTE
    Then the entity should have exactly 1 Full and 1 Light journey
    And the Full journey should still have a "CFO sign-off" step
    And the entity should have exactly 2 capital call auto-assignment rules

  # H1 from the UI — the same setup service as the rake task, run by a company admin
  Scenario: A company admin sets up the journeys from the Workflow Templates page
    When I open the Workflow Templates page
    And I choose "Set up capital call journeys" from the Set up journeys menu and proceed
    Then I should see "Capital call journeys set up: Full and Light journeys, auto-assignment rules" on the page
    And the entity should have the Full journey with 12 tasks and the Light journey with 4 tasks
    And imported calls should go to Light and other calls to Full
    And the Set up journeys menu should show "Capital call journeys set up" as done

  Scenario: The setup button is not offered to a user who is not a company admin
    Given the user is no longer a company admin
    When I open the Workflow Templates page
    Then the Set up journeys menu should not be shown
