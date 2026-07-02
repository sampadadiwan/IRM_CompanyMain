Feature: Data Rooms
  As an LP investor I want to view data rooms shared by my GP entities so I can access
  documents they have explicitly given me access to.

  # ── Scenario 1 ──────────────────────────────────────────────────────────────
  # Verifies the model-level setup: entity.data_room_folder returns the "Data Room"
  # child folder once it is created, and enable_data_rooms is set on permissions.
  # These are the two conditions that gate the Data Rooms card on the LP dashboard.
  Scenario: Data room folder and enable_data_rooms flag are set up correctly
    Given there is a user "" for an entity "entity_type=Investment Fund;enable_funds=true"
    Given the entity has "enable_data_rooms" permission
    Given the GP entity has a data room folder
    Then the GP entity should have a data_room_folder present
    Then the GP entity should have enable_data_rooms enabled

  # ── Scenario 2 ──────────────────────────────────────────────────────────────
  # Verifies the Data Rooms card appears on the LP vc_dashboard when the GP entity has
  # enable_data_rooms AND a data_room_folder.
  # @current_entity is resolved from request.domain; in tests we set entity.domain =
  # "localhost" so Capybara requests to localhost pick up that entity as @current_entity.
  Scenario: Data Rooms card appears on LP dashboard when GP entity has enable_data_rooms
    Given there is a user "" for an entity "entity_type=Investment Fund;enable_funds=true"
    Given the entity has "enable_data_rooms" permission
    Given the GP entity has a data room folder
    Given the GP entity domain is set to "localhost"
    Given there is an existing investor "" with "1" users
    Given I login as the investor user
    When I visit the investor dashboard
    Then I should see the Data Rooms card on the dashboard

  # ── Scenario 3 ──────────────────────────────────────────────────────────────
  # Verifies the Data Rooms card is absent when enable_data_rooms is NOT set on the GP entity.
  # All other conditions are identical to scenario 2.
  Scenario: Data Rooms card is hidden when GP entity lacks enable_data_rooms
    Given there is a user "" for an entity "entity_type=Investment Fund;enable_funds=true"
    Given the GP entity has a data room folder
    Given the GP entity domain is set to "localhost"
    Given there is an existing investor "" with "1" users
    Given I login as the investor user
    When I visit the investor dashboard
    Then I should not see the Data Rooms card on the dashboard

  # ── Scenario 4 ──────────────────────────────────────────────────────────────
  # Verifies the data rooms listing page (/folders/data_rooms) shows only the GP entities
  # where the LP has an investor relationship (investee_entities scope).
  # A second GP entity with enable_data_rooms but NO investor relationship must not appear.
  Scenario: LP sees only their GP entities on the data rooms listing page
    Given there is a user "" for an entity "entity_type=Investment Fund;enable_funds=true"
    Given the entity has "enable_data_rooms" permission
    Given the GP entity has a data room folder
    Given there is a different GP entity with "enable_data_rooms" that the LP is not invested in
    Given there is an existing investor "" with "1" users
    Given I login as the investor user
    When I visit the data rooms listing page
    Then I should see the GP entity in the data rooms list
    And I should not see the other GP entity in the data rooms list

  # ── Scenario 5 ──────────────────────────────────────────────────────────────
  # Verifies sub-folder level access within a data room.
  # The Folder.for_investor scope requires a matching AccessRight on the folder
  # (in addition to the investor relationship and approved InvestorAccess).
  # Folder A has an explicit AccessRight for the LP investor; Folder B does not.
  # The LP must be able to access Folder A but NOT Folder B.
  Scenario: LP can access only sub-folders with explicit access rights in the data room
    Given there is a user "" for an entity "entity_type=Investment Fund;enable_funds=true"
    Given the entity has "enable_data_rooms" permission
    Given the GP entity has a data room folder
    Given there is an existing investor "" with "1" users
    Given the data room has sub-folders "Accessible Folder" and "Restricted Folder"
    Given the LP investor has been given explicit access to the sub-folder "Accessible Folder"
    Then the LP investor can access "Accessible Folder" via the for_investor scope
    And the LP investor cannot access "Restricted Folder" via the for_investor scope
