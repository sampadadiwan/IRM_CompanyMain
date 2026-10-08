# frozen_string_literal: true

Feature: NDA Notifications, Revocation & Expiry Jobs (Module 8)
  As a GP I want to revoke an LP's NDA acceptance, receive notifications on
  NDA events, and have expiry alerts sent automatically by a daily cron job.

  Background:
    Given there is a user "" for an entity "entity_type=Investment Fund;enable_funds=true"
    Given the entity has "enable_data_rooms" permission
    Given the GP entity has a data room folder
    Given the data room folder has an enabled NDA config
    Given there is an LP investor "Acme Capital" with approved access to the GP entity
    Given the LP user is tagged as a signatory for the NDA

  # ── Revocation ──────────────────────────────────────────────────────────────

  # GP can revoke an accepted NDA. Creates a new append-only row with status=revoked.
  Scenario: GP revokes an accepted NDA
    Given the investor "Acme Capital" has accepted the NDA
    When the GP revokes the NDA for investor "Acme Capital"
    Then the latest NDA acceptance for "Acme Capital" should have status "revoked"
    And there should be 2 NDA acceptance records for investor "Acme Capital"

  # Revocation stores optional reason text.
  Scenario: Revocation stores reason
    Given the investor "Acme Capital" has accepted the NDA
    When the GP revokes the NDA for investor "Acme Capital" with reason "Deal terminated"
    Then the latest NDA acceptance for "Acme Capital" should have reason "Deal terminated"

  # Cannot revoke an investor who hasn't accepted.
  Scenario: Cannot revoke a pending investor
    Then revoking the NDA for investor "Acme Capital" should fail

  # Cannot revoke an already-revoked investor.
  Scenario: Cannot revoke an already-revoked investor
    Given the investor "Acme Capital" has accepted the NDA
    And the GP has revoked the NDA for investor "Acme Capital"
    Then revoking the NDA for investor "Acme Capital" should fail

  # revoked? predicate returns true for revoked records.
  Scenario: revoked? predicate returns true for revoked records
    Given the investor "Acme Capital" has accepted the NDA
    When the GP revokes the NDA for investor "Acme Capital"
    Then the latest NDA acceptance revoked? should be true

  # ── Resolver: Revoked Status ────────────────────────────────────────────────

  # Revoked investor shows as "Revoked" in the resolver.
  Scenario: Resolver shows Revoked status
    Given the investor "Acme Capital" has accepted the NDA
    And the GP has revoked the NDA for investor "Acme Capital"
    When the resolver resolves NDA status for the folder
    Then the investor "Acme Capital" status should be "Revoked"
    And the resolver counters should show revoked 1

  # ── NdaExpiryReminder Dedup Guard ──────────────────────────────────────────

  # NdaExpiryReminder records one row per [config, investor, date, kind].
  Scenario: Expiry reminder is created successfully
    When an expiry reminder is created for "Acme Capital" with kind "approaching" and expiry date 7 days from now
    Then there should be 1 expiry reminder for the NDA config

  # Duplicate reminder (same config, investor, date, kind) is rejected.
  Scenario: Duplicate expiry reminder is rejected
    Given an expiry reminder exists for "Acme Capital" with kind "approaching" and expiry date 7 days from now
    Then creating a duplicate expiry reminder should raise an error

  # already_sent? class method returns true for existing reminder.
  Scenario: already_sent? returns true for existing reminder
    Given an expiry reminder exists for "Acme Capital" with kind "approaching" and expiry date 7 days from now
    Then already_sent? should return true for the same parameters

  # already_sent? returns false when no reminder exists.
  Scenario: already_sent? returns false when no reminder exists
    Then already_sent? should return false for "Acme Capital" with kind "approaching" and expiry date 7 days from now

  # ── NdaExpiryCheckJob: classify ────────────────────────────────────────────

  # Expiry date in the past → kind "expired".
  Scenario: Expiry scanner classifies past date as expired
    Given the NDA config has fixed_period validity of 90 days
    And the investor "Acme Capital" accepted the NDA 91 days ago
    Then the expiry classification should be "expired"

  # Expiry date within 7 days → kind "approaching".
  Scenario: Expiry scanner classifies near-future date as approaching
    Given the NDA config has fixed_period validity of 90 days
    And the investor "Acme Capital" accepted the NDA 85 days ago
    Then the expiry classification should be "approaching"

  # Expiry date more than 7 days away → nil (no alert).
  Scenario: Expiry scanner returns nil for far-future date
    Given the NDA config has fixed_period validity of 90 days
    And the investor "Acme Capital" accepted the NDA 30 days ago
    Then the expiry classification should be nil

  # until_revoked configs are skipped by the scanner.
  Scenario: Expiry scanner skips until_revoked configs
    Given the investor "Acme Capital" accepted the NDA 365 days ago
    Then the NDA config should not be scannable for expiry

  # ── NdaNotificationRecipients ──────────────────────────────────────────────

  # :accepted event returns GP notification_emails only.
  Scenario: Accepted event resolves GP emails
    Given the NDA config has notification_emails "ops@firm.com, legal@firm.com"
    When notification recipients are resolved for event "accepted" and investor "Acme Capital"
    Then the GP email recipients should include "ops@firm.com"
    And the GP email recipients should include "legal@firm.com"
    And there should be 0 LP user recipients

  # :revoked event returns LP users of the investor (no GP emails).
  Scenario: Revoked event resolves LP users
    When notification recipients are resolved for event "revoked" and investor "Acme Capital"
    Then there should be 0 GP email recipients
    And the LP user recipients should include the LP user

  # :reminder event returns signatory users of pending investors.
  Scenario: Reminder event resolves pending signatory users
    When notification recipients are resolved for event "reminder"
    Then the LP user recipients should include the LP user

  # :reminder event excludes accepted investors.
  Scenario: Reminder event excludes accepted investors
    Given the investor "Acme Capital" has accepted the NDA
    When notification recipients are resolved for event "reminder"
    Then there should be 0 LP user recipients

  # Exempt investors are excluded from notifications.
  Scenario: Exempt investors are excluded from notifications
    Given the investor access has exempt_from_nda set to true
    When notification recipients are resolved for event "revoked" and investor "Acme Capital"
    Then there should be 0 LP user recipients

  # ── NdaExpiryReminder Cascade ──────────────────────────────────────────────

  # Destroying the NDA config cascades to expiry reminders.
  Scenario: Expiry reminders are destroyed with NdaConfig
    Given an expiry reminder exists for "Acme Capital" with kind "approaching" and expiry date 7 days from now
    When the NDA config is destroyed
    Then there should be 0 expiry reminders for the NDA config
