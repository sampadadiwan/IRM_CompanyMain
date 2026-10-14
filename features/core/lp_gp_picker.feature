Feature: LP dashboard GP picker keeps the picked GP
  An LP with access to several GPs picks one in the top-bar GP picker. The pick must stick:
  it goes into the URL (so Back from a fund page returns to it) and into the session (so the
  sidebar Dashboard link or the home page show it again), but only while the LP still has
  approved investor access to that GP.

  # One LP user with approved investor access to two GPs. "Beta Capital" sorts after
  # "Alpha Capital", so it is never the default first GP - seeing it proves the pick stuck.
  Background:
    Given there is a user "" for an entity "name=Alpha Capital;entity_type=Investment Fund;enable_funds=true"
    And there is an existing investor "" with "1" users
    And there is a second GP entity "name=Beta Capital;enable_funds=true" that the investor user can access
    And the second GP entity has a fund "Beta Growth Fund" shared with the investor
    And I login as the investor user

  # G1 — Edge case: Back from a fund page returns to the picked (second) GP, not the alphabetically first one
  Scenario: Picked GP survives a visit to a fund page and the browser Back button
    When I visit the investor dashboard
    Then the GP picker should show "Alpha Capital"
    When I pick the GP "Beta Capital" in the GP picker
    Then the page URL should carry the GP "Beta Capital"
    And the GP picker should show "Beta Capital"
    And I should see the banner for the GP "Beta Capital"
    When I open the fund page of "Beta Growth Fund"
    And I go back in the browser
    Then the page URL should carry the GP "Beta Capital"
    And the GP picker should show "Beta Capital"
    And I should see the banner for the GP "Beta Capital"

  # G2 — Edge case: the sidebar Dashboard link carries no gp_entity_id, so the pick must come from the session
  Scenario: Picked GP is remembered when using the sidebar Dashboard link
    When I visit the investor dashboard
    And I pick the GP "Beta Capital" in the GP picker
    Then the page URL should carry the GP "Beta Capital"
    When I click Dashboard in the sidebar
    Then the GP picker should show "Beta Capital"
    And I should see the banner for the GP "Beta Capital"

  # G3 — Edge case: the home page "/" (logo / home icon / fresh tab) also uses the remembered pick
  Scenario: Picked GP is remembered on the home page
    When I visit the investor dashboard
    And I pick the GP "Beta Capital" in the GP picker
    Then the page URL should carry the GP "Beta Capital"
    When I visit the investor dashboard
    Then the GP picker should show "Beta Capital"
    And I should see the banner for the GP "Beta Capital"

  # G4 — Edge case: the remembered GP's investor access is unapproved, so it is ignored and the first GP is shown
  Scenario: Remembered GP whose investor access is unapproved falls back to the first GP
    When I visit the investor dashboard
    And I pick the GP "Beta Capital" in the GP picker
    Then the page URL should carry the GP "Beta Capital"
    When the investor user's access to the GP "Beta Capital" is unapproved
    And I visit the investor dashboard
    Then the GP picker should show "Alpha Capital"
    And I should see the banner for the GP "Alpha Capital"
    And I should not see the banner for the GP "Beta Capital"

  # G5 — Edge case: the remembered GP's investor access is deleted outright, so it is ignored and the first GP is shown
  Scenario: Remembered GP whose investor access is revoked falls back to the first GP
    When I visit the investor dashboard
    And I pick the GP "Beta Capital" in the GP picker
    Then the page URL should carry the GP "Beta Capital"
    When the investor user's access to the GP "Beta Capital" is revoked
    And I visit the investor dashboard
    Then the GP picker should show "Alpha Capital"
    And I should see the banner for the GP "Alpha Capital"
    And I should not see the banner for the GP "Beta Capital"
