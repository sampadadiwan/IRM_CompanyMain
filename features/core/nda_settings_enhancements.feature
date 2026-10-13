# frozen_string_literal: true

# Worked examples from design.md#worked-examples
# @see openspec/changes/nda-settings-enhancements/design.md
@rack_test
Feature: NDA Settings Enhancements
  As a GP I want the NDA settings workflow to handle inherited NDA overrides
  gracefully, lock validity types after acceptance, show expiry summaries,
  and allow editing expired NDAs.

  Background:
    Given there is a user "" for an entity "entity_type=Investment Fund;enable_funds=true"
    Given the entity has "enable_data_rooms" permission
    Given the GP entity has a data room folder
    Given the data room folder has an enabled NDA config
    Given there is a child folder "Subfund A" in the data room
    Given there is an LP investor "Capital Partners" with approved access to the GP entity

  # ── Resign on Override ─────────────────────────────────────────────────────

  # H1 — Happy path: override with resign unchecked, acceptances migrated
  Scenario: Override inherited NDA without resign carries forward acceptances
    Given the investor "Capital Partners" has access to folder "Subfund A"
    And the investor "Capital Partners" has accepted the NDA
    When the GP detects inherited acceptances on folder "Subfund A"
    Then the inherited accepted count for "Subfund A" should be 1
    When the GP overrides folder "Subfund A" with resign_required false
    Then the folder "Subfund A" should have its own NDA config
    And the folder "Subfund A" NDA should have 1 accepted investor
    And the original NDA should still have 1 accepted investor

  # H2 — Happy path: override with resign checked, fresh start
  Scenario: Override inherited NDA with resign starts fresh
    Given the investor "Capital Partners" has access to folder "Subfund A"
    And the investor "Capital Partners" has accepted the NDA
    When the GP overrides folder "Subfund A" with resign_required true
    Then the folder "Subfund A" should have its own NDA config
    And the folder "Subfund A" NDA should have 0 accepted investors

  # E1 — Edge case: no inherited acceptances, no resign checkbox needed
  Scenario: Override without inherited acceptances shows zero count
    When the GP detects inherited acceptances on folder "Subfund A"
    Then the inherited accepted count for "Subfund A" should be 0

  # E2 — Edge case: parent acceptances untouched after override
  Scenario: Parent NDA acceptances preserved after child override
    Given the investor "Capital Partners" has access to folder "Subfund A"
    And the investor "Capital Partners" has accepted the NDA
    When the GP overrides folder "Subfund A" with resign_required false
    Then the original NDA should still have 1 accepted investor

  # ── Validity Locking ───────────────────────────────────────────────────────

  # H3 — Happy path: locked validity with expiry summary
  Scenario: Validity locking when acceptances exist with fixed period
    Given the NDA config has validity_type "fixed_period" and validity_days 90
    And the investor "Capital Partners" has accepted the NDA
    Then the NDA config accepted count should be 1
    And the validity type should be locked
    And the earliest expiry should be 90 days after the acceptance date
    And the latest expiry should be 90 days after the acceptance date

  # E3 — Edge case: no acceptances, radios enabled
  Scenario: Validity not locked when no acceptances exist
    Then the NDA config accepted count should be 0
    And the validity type should not be locked

  # E4 — Edge case: fixed period but no accepted dates
  Scenario: No expiry summary when no acceptances for fixed period
    Given the NDA config has validity_type "fixed_period" and validity_days 90
    Then the NDA config accepted count should be 0
    And there should be no expiry dates computed

  # E8 — Edge case: specific date expiry summary
  Scenario: Specific date shows single expiry date
    Given the NDA config has validity_type "specific_date" and validity_date "2027-12-31"
    Then the NDA config validity_date should display as "Dec 31, 2027"

  # ── Expired NDA Edit ───────────────────────────────────────────────────────

  # H4 — Happy path: save expired NDA with new future date
  Scenario: Expired NDA date min clamped to tomorrow
    Given the NDA config has validity_type "specific_date" and validity_date "past"
    Then the date min for the NDA form should be tomorrow

  # E5 — Edge case: save expired NDA without changing date
  Scenario: Expired NDA allows saving non-date fields
    Given the NDA config has validity_type "specific_date" and validity_date "past"
    When the GP updates the NDA config contact_email to "legal@fund.com"
    Then the NDA config contact_email should be "legal@fund.com"
    And the NDA config validity_date should be in the past

  # ── Version Record ─────────────────────────────────────────────────────────

  # Verifies that version record stores actual resign_required value
  Scenario: Override version record stores resign_required true
    Given the investor "Capital Partners" has access to folder "Subfund A"
    And the investor "Capital Partners" has accepted the NDA
    When the GP overrides folder "Subfund A" with resign_required true
    Then the folder "Subfund A" NDA version record should have resign_required true

  Scenario: Override version record stores resign_required false
    Given the investor "Capital Partners" has access to folder "Subfund A"
    And the investor "Capital Partners" has accepted the NDA
    When the GP overrides folder "Subfund A" with resign_required false
    Then the folder "Subfund A" NDA version record should have resign_required false
