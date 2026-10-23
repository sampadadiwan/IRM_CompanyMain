# Query budgets for the misc pack (round 2 of the bulk-path query work, tmp/query_fixes_round2.md).
# Counts queries by the line that issued them (features/step_definitions/query_budget_steps.rb).

@rack_test
Feature: The approval responses list loads each response's owner in one query

  # R4 — Happy path: an investor with several responses on one approval (one per owner) sees the list, and the
  # owners - read by each row's policy check and shown on its quick-response button - are preloaded, not read
  # row by row
  Scenario: R4-H1 Approval responses on the approval page preload their owners
    Given there is a user "" for an entity "entity_type=Company"
    Given there is an existing investor "" with "1" users
    Given there is an approval "title=Test approval" for the entity
    Given the investors are added to the approval
    And the investor has responses on the approval for 3 different funds
    Given Im logged in as an investor
    And I count queries by call site
    When I visit the approval details page
    Then I should see a quick response for each of the 3 funds
    # owners come from the list's preload, not one lookup per row in each row's policy check (was 3 here)
    And at most 0 statements containing 'FROM "funds"' came from "app/packs/core/base/policies/application_policy.rb"
    And at least 1 statement containing 'FROM "funds"' came from "app/packs/misc/approvals/views/approval_responses/_index.html.erb"
