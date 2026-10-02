Feature: NDA Inheritance (Module 5)
  As a GP I want NDA settings on a parent folder to automatically cascade to child
  folders so that I don't have to configure each folder individually. Child folders
  can override (set their own NDA) or opt out (no NDA even if parent has one).

  Background:
    Given there is a user "" for an entity "entity_type=Investment Fund;enable_funds=true"
    Given the entity has "enable_data_rooms" permission
    Given the GP entity has a data room folder

  # ── Scenario 1: Default inheritance mode ────────────────────────────────────
  Scenario: New folders default to inherit mode
    Given there is a child folder "Sub Folder" in the data room
    Then the folder "Sub Folder" should have nda_inheritance_mode "inherit"

  # ── Scenario 2: Child inherits parent's NDA ─────────────────────────────────
  Scenario: Child folder inherits NDA from parent
    Given the data room folder has an NDA config
    And there is a child folder "Deal Pipeline" in the data room
    Then the folder "Deal Pipeline" should have nda_inheritance_mode "inherit"
    And the folder "Deal Pipeline" effective_nda_config should be the data room's config
    And the folder "Deal Pipeline" nda_source_folder should be the data room folder
    And the folder "Deal Pipeline" should require NDA

  # ── Scenario 3: Grandchild inherits through chain ──────────────────────────
  Scenario: Grandchild inherits NDA through parent chain
    Given the data room folder has an NDA config
    And there is a child folder "Deal Pipeline" in the data room
    And there is a child folder "Fund Alpha" under "Deal Pipeline"
    Then the folder "Fund Alpha" effective_nda_config should be the data room's config
    And the folder "Fund Alpha" nda_source_folder should be the data room folder

  # ── Scenario 4: Override replaces parent NDA ───────────────────────────────
  Scenario: Child with own NDA overrides parent
    Given the data room folder has an NDA config
    And there is a child folder "Deal Pipeline" in the data room
    And the folder "Deal Pipeline" has its own NDA config
    Then the folder "Deal Pipeline" should have nda_inheritance_mode "own"
    And the folder "Deal Pipeline" effective_nda_config should be its own config
    And the folder "Deal Pipeline" nda_source_folder should be itself

  # ── Scenario 5: Override does not affect siblings ──────────────────────────
  Scenario: Override on one child does not affect sibling inheritance
    Given the data room folder has an NDA config
    And there is a child folder "Deal Pipeline" in the data room
    And there is a child folder "Reports" in the data room
    And the folder "Deal Pipeline" has its own NDA config
    Then the folder "Reports" effective_nda_config should be the data room's config
    And the folder "Reports" nda_source_folder should be the data room folder

  # ── Scenario 6: Opt-out blocks inheritance ─────────────────────────────────
  Scenario: Opted-out folder does not require NDA
    Given the data room folder has an NDA config
    And there is a child folder "Public Docs" in the data room
    And the folder "Public Docs" is opted out of NDA
    Then the folder "Public Docs" should have nda_inheritance_mode "opt_out"
    And the folder "Public Docs" effective_nda_config should be nil
    And the folder "Public Docs" should not require NDA

  # ── Scenario 7: Opt-out breaks chain for descendants ───────────────────────
  Scenario: Opt-out breaks inheritance chain for descendants
    Given the data room folder has an NDA config
    And there is a child folder "Public Docs" in the data room
    And the folder "Public Docs" is opted out of NDA
    And there is a child folder "Quarterly" under "Public Docs"
    Then the folder "Quarterly" effective_nda_config should be nil
    And the folder "Quarterly" should not require NDA

  # ── Scenario 8: No ancestor has NDA ────────────────────────────────────────
  Scenario: Inherit mode with no ancestor NDA resolves to nil
    Given there is a child folder "Empty Sub" in the data room
    Then the folder "Empty Sub" effective_nda_config should be nil
    And the folder "Empty Sub" should not require NDA

  # ── Scenario 9: Revert from opt-out to inherit ─────────────────────────────
  Scenario: Reverting from opt-out restores inherited NDA
    Given the data room folder has an NDA config
    And there is a child folder "Temp Exempt" in the data room
    And the folder "Temp Exempt" is opted out of NDA
    When the folder "Temp Exempt" reverts to inherit mode
    Then the folder "Temp Exempt" effective_nda_config should be the data room's config
    And the folder "Temp Exempt" should require NDA

  # ── Scenario 10: NdaInheritanceResolver batch resolution ───────────────────
  Scenario: Resolver matches model methods for a mixed tree
    Given the data room folder has an NDA config
    And there is a child folder "Deal Pipeline" in the data room
    And there is a child folder "Reports" in the data room
    And the folder "Reports" is opted out of NDA
    And there is a child folder "Fund Alpha" under "Deal Pipeline"
    And the folder "Deal Pipeline" has its own NDA config
    Then the resolver results should match model methods for all folders

  # ── Scenario 11: Non-Data-Room folders unaffected ──────────────────────────
  Scenario: Non-Data-Room folders are not affected by NDA inheritance
    Given the entity has a folder "name=Regular Folder"
    Then the folder "Regular Folder" should have nda_inheritance_mode "inherit"
    And the folder "Regular Folder" effective_nda_config should be nil
    And the folder "Regular Folder" should not require NDA
