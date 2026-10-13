@rack_test
Feature: NDA Configuration (Module 1)
  As a GP I want to configure NDA settings on Data Room folders so that LPs
  must accept an NDA before they can view the folder's contents.

  Background:
    Given there is a user "" for an entity "entity_type=Investment Fund;enable_funds=true"
    Given the entity has "enable_data_rooms" permission
    Given the GP entity has a data room folder

  # ── Scenario 1: Create NDA config with click-through ──────────────────────
  # A GP can create an NDA config on a Data Room folder with the simplest
  # settings: click-through acceptance, until_revoked validity.
  Scenario: GP creates NDA config with click-through acceptance
    When the GP creates an NDA config on the data room folder with:
      | enabled           | true          |
      | acceptance_method | click_through |
      | validity_type     | until_revoked |
    Then the data room folder should have an NDA config
    And the NDA config should be enabled
    And the NDA config acceptance_method should be "click_through"
    And the NDA config validity_type should be "until_revoked"

  # ── Scenario 2: nda_required? reflects enabled state ──────────────────────
  # Folder#nda_required? returns true when config is enabled, false when disabled.
  Scenario: nda_required? returns true when NDA is enabled
    When the GP creates an NDA config on the data room folder with:
      | enabled           | true          |
      | acceptance_method | click_through |
      | validity_type     | until_revoked |
    Then the data room folder nda_required? should be true

  Scenario: nda_required? returns false when NDA is disabled
    When the GP creates an NDA config on the data room folder with:
      | enabled           | false         |
      | acceptance_method | click_through |
      | validity_type     | until_revoked |
    Then the data room folder nda_required? should be false

  # ── Scenario 4: Folder without NDA config ─────────────────────────────────
  # A Data Room folder with no config returns nda_required? = false.
  Scenario: Folder without NDA config does not require NDA
    Then the data room folder nda_required? should be false

  # ── Scenario 5: Fixed period validity ─────────────────────────────────────
  # GP can set validity_type to fixed_period with a specific number of days.
  Scenario: GP creates NDA config with fixed period validity
    When the GP creates an NDA config on the data room folder with:
      | enabled           | true          |
      | acceptance_method | click_through |
      | validity_type     | fixed_period  |
      | validity_days     | 90            |
    Then the NDA config validity_type should be "fixed_period"
    And the NDA config validity_days should be 90

  # ── Scenario 6: Specific date validity ────────────────────────────────────
  # GP can set validity_type to specific_date with a future expiry date.
  Scenario: GP creates NDA config with specific date validity
    When the GP creates an NDA config on the data room folder with:
      | enabled           | true          |
      | acceptance_method | click_through |
      | validity_type     | specific_date |
      | validity_date     | future        |
    Then the NDA config validity_type should be "specific_date"
    And the NDA config validity_date should be in the future

  # ── Scenario 7: Contact email and notification emails ─────────────────────
  # GP can set an optional contact email and notification recipient list.
  Scenario: GP sets contact email and notification recipients
    When the GP creates an NDA config on the data room folder with:
      | enabled              | true                       |
      | acceptance_method    | click_through              |
      | validity_type        | until_revoked              |
      | contact_email        | legal@firm.com             |
      | notification_emails  | ops@firm.com, cfo@firm.com |
    Then the NDA config contact_email should be "legal@firm.com"
    And the NDA config notification_emails should contain "ops@firm.com"
    And the NDA config notification_emails should contain "cfo@firm.com"

  # ── Scenario 8: Update existing NDA config ────────────────────────────────
  # GP can update an existing NDA config (change validity, toggle enabled).
  Scenario: GP updates an existing NDA config
    Given the data room folder has an enabled NDA config
    When the GP updates the NDA config with:
      | validity_type | fixed_period |
      | validity_days | 180          |
    Then the NDA config validity_type should be "fixed_period"
    And the NDA config validity_days should be 180

  # ── Scenario 9: Disable existing NDA config ──────────────────────────────
  # GP can disable NDA by setting enabled to false.
  Scenario: GP disables an existing NDA config
    Given the data room folder has an enabled NDA config
    When the GP updates the NDA config with:
      | enabled | false |
    Then the NDA config should not be enabled
    And the data room folder nda_required? should be false

  # ── Scenario 10: Entity auto-set from folder ─────────────────────────────
  # NDA config's entity_id is automatically set from the folder's entity.
  Scenario: Entity is automatically set from folder
    When the GP creates an NDA config on the data room folder with:
      | enabled           | true          |
      | acceptance_method | click_through |
      | validity_type     | until_revoked |
    Then the NDA config entity should match the folder entity

  # ── Scenario 11: Validation — document required when enabled ──────────────
  # Enabling NDA without uploading a document fails validation.
  Scenario: NDA config requires document when enabled
    When the GP tries to create an NDA config without a document:
      | enabled           | true          |
      | acceptance_method | click_through |
      | validity_type     | until_revoked |
    Then the NDA config should have an error on "nda_document"

  # ── Scenario 12: Validation — invalid contact email ───────────────────────
  Scenario: NDA config rejects invalid contact email
    When the GP creates an NDA config on the data room folder with:
      | enabled           | true          |
      | acceptance_method | click_through |
      | validity_type     | until_revoked |
      | contact_email     | not-an-email  |
    Then the NDA config should have an error on "contact_email"

  # ── Scenario 13: Validation — invalid notification emails ─────────────────
  Scenario: NDA config rejects invalid notification emails
    When the GP creates an NDA config on the data room folder with:
      | enabled              | true          |
      | acceptance_method    | click_through |
      | validity_type        | until_revoked |
      | notification_emails  | bad@@email    |
    Then the NDA config should have an error on "notification_emails"

  # ── Scenario 14: Validation — past validity date rejected ─────────────────
  Scenario: NDA config rejects past validity date
    When the GP creates an NDA config on the data room folder with:
      | enabled           | true          |
      | acceptance_method | click_through |
      | validity_type     | specific_date |
      | validity_date     | past          |
    Then the NDA config should have an error on "validity_date"

  # ── Scenario 15: in_data_room? detection ──────────────────────────────────
  # Folder#in_data_room? correctly identifies Data Room hierarchy membership.
  Scenario: in_data_room? returns true for Data Room folder and children
    Given there is a child folder "Deal Pipeline" in the data room
    Then the data room folder in_data_room? should be true
    And the folder "Deal Pipeline" in_data_room? should be true

  Scenario: in_data_room? returns false for non-Data-Room folders
    Given the entity has a folder "name=Regular Folder"
    Then the folder "Regular Folder" in_data_room? should be false

  # ── Scenario 17: One-to-one constraint ────────────────────────────────────
  # A folder can only have one NDA config (unique index on folder_id).
  Scenario: Folder cannot have duplicate NDA configs
    Given the data room folder has an enabled NDA config
    Then creating a second NDA config on the data room folder should fail

  # ── Scenario 18: Policy — only GP employees can manage NDA config ─────────
  # NDA config policy requires curr_role_employee? and folder.in_data_room?.
  Scenario: Policy allows GP employee on Data Room folder
    Then the NDA config policy should allow the GP user on the data room folder

  Scenario: Policy denies on non-Data-Room folder
    Given the entity has a folder "name=Regular Folder"
    Then the NDA config policy should deny on the folder "Regular Folder"
