# frozen_string_literal: true

Feature: NDA Signatory Auto-Tag (Module 10)
  As a GP I want newly added investors to automatically get a default signatory
  tagged for folder NDAs, and I want the on-creation auto-tag to be scoped to
  folder-level access rights instead of entity-wide.

  Background:
    Given there is a user "" for an entity "entity_type=Investment Fund;enable_funds=true"
    Given the entity has "enable_data_rooms" permission
    Given the GP entity has a data room folder

  # ── Auto-tag on Investor Access Approval ───────────────────────────────────

  # When an investor access is created as approved and the folder has an NDA,
  # the user should be auto-tagged as signatory.
  Scenario: Auto-tag fires when new investor access is created as approved
    Given the data room folder has an enabled NDA config
    And there is a new LP investor "Gamma LP" with folder access but no investor access yet
    When the GP creates an approved investor access for "Gamma LP"
    Then there should be 1 NDA signatory for investor "Gamma LP"
    And the signatory for "Gamma LP" should be the newly added user

  # When an unapproved investor access is toggled to approved, auto-tag fires.
  Scenario: Auto-tag fires when unapproved access is toggled to approved
    Given the data room folder has an enabled NDA config
    And there is a new LP investor "Delta LP" with folder access and unapproved investor access
    When the GP approves the investor access for "Delta LP"
    Then there should be 1 NDA signatory for investor "Delta LP"

  # ── No Duplicate Signatory ─────────────────────────────────────────────────

  # If the investor already has a signatory, no duplicate is created.
  Scenario: No duplicate signatory when investor already has one
    Given there is an LP investor "Acme Capital" with approved access to the GP entity
    And the data room folder has an enabled NDA config
    And the LP user for "Acme Capital" is already a signatory for the folder NDA
    When the GP creates a second approved investor access for "Acme Capital"
    Then there should be 1 NDA signatory for investor "Acme Capital"

  # ── No Auto-tag Without Folder NDA ─────────────────────────────────────────

  # If the folder has no NDA config, no signatory is created.
  Scenario: No auto-tag when folder has no NDA
    Given there is a new LP investor "Epsilon LP" with folder access but no investor access yet
    When the GP creates an approved investor access for "Epsilon LP"
    Then there should be 0 NDA signatories in total

  # ── Folder-Scoped Auto-tag on NDA Creation ─────────────────────────────────

  # On NDA creation, only investors with folder-level access are tagged.
  Scenario: NDA creation only tags folder-access investors
    Given there is an LP investor "Acme Capital" with approved access to the GP entity
    And there is an LP investor "No Folder LP" with entity access but no folder access
    When the GP creates an NDA config with folder-scoped auto-tagging
    Then there should be 1 NDA signatory for investor "Acme Capital"
    And there should be 0 NDA signatories for investor "No Folder LP"

  # ── Entity-Level Investor Not Tagged ───────────────────────────────────────

  # An investor with entity access but no folder AccessRight is not auto-tagged
  # when their investor access is approved.
  Scenario: Entity-level investor without folder access not auto-tagged on access approval
    Given the data room folder has an enabled NDA config
    And there is an LP investor "No Folder LP" with entity access but no folder access
    When the GP approves the investor access for "No Folder LP"
    Then there should be 0 NDA signatories for investor "No Folder LP"
