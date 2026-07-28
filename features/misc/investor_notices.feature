Feature: Investor notices scoped to the selected GP
  As an LP investor with approved access to multiple GP entities
  I want the dashboard notices carousel to only show notices from the GP
  selected in the GP switcher dropdown
  So that I am not shown another GP's notices while viewing one GP's data

  # Shared setup: one LP user ("the investor user") with approved InvestorAccess
  # to two GP entities (Alpha Fund and Beta Fund), each of which has published
  # an active investor notice targeted at the LP's investor entity.
  Background:
    Given there is a user "" for an entity "name=Alpha Fund;entity_type=Investment Fund;enable_funds=true"
    Given there is an existing investor "" with "1" users
    Given the GP entity has an active investor notice titled "Alpha GP Notice"
    Given there is a second GP entity "name=Beta Fund" that the investor user can access
    Given the second GP entity has an active investor notice titled "Beta GP Notice"
    Given I login as the investor user

  # ── Scenario 1 ──────────────────────────────────────────────────────────────
  # Switching the GP dropdown submits a GET with gp_entity_id; the carousel is
  # inside the vc_dashboard turbo frame, so the notices must follow the selection.
  Scenario: Carousel only shows notices from the GP selected in the dropdown
    When I visit the investor dashboard with GP "Alpha Fund" selected
    Then I should see the investor notice "Alpha GP Notice"
    And I should not see the investor notice "Beta GP Notice"
    When I visit the investor dashboard with GP "Beta Fund" selected
    Then I should see the investor notice "Beta GP Notice"
    And I should not see the investor notice "Alpha GP Notice"

  # ── Scenario 2 ──────────────────────────────────────────────────────────────
  # With no explicit selection, _vc_dashboard defaults to the first GP entity
  # (sorted by name), so only that GP's notices should appear on first load.
  Scenario: Carousel defaults to the first GP's notices on first load
    When I visit the investor dashboard
    Then I should see the investor notice "Alpha GP Notice"
    And I should not see the investor notice "Beta GP Notice"
