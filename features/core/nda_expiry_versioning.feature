# frozen_string_literal: true

Feature: NDA Expiry & Versioning (Module 4)
  As a GP I want NDA acceptances to expire after a configured time period, and
  when I upload a new NDA PDF the version auto-increments so LPs must re-accept.

  Background:
    Given there is a user "" for an entity "entity_type=Investment Fund;enable_funds=true"
    Given the entity has "enable_data_rooms" permission
    Given the GP entity has a data room folder
    Given the data room folder has an enabled NDA config
    Given there is an LP investor "Acme Capital" with approved access to the GP entity
    Given the LP user is tagged as a signatory for the NDA

  # ── Version Bump ────────────────────────────────────────────────────────────

  # When GP uploads a new PDF, the NDA config version increments from 1 to 2.
  @rack_test
  Scenario: Version increments when NDA document changes
    When the GP uploads a new NDA PDF on the config
    Then the NDA config version should be 2

  # NdaConfigVersion record is created on version bump.
  @rack_test
  Scenario: Version history record is created on bump
    When the GP uploads a new NDA PDF on the config
    Then there should be 1 NDA config version record
    And the latest version record version should be 2
    And the latest version record uploaded_by should be the GP user

  # Version 1 record is created when NDA config is first created with a version record.
  @rack_test
  Scenario: First version record stores resign_required false
    When a version 1 record is created for the NDA config
    Then the version 1 record resign_required should be false

  # ── Version Gate ────────────────────────────────────────────────────────────

  # LP accepted version 1, config is now version 2 — acceptance is stale.
  Scenario: Acceptance is stale when version mismatches
    Given the investor "Acme Capital" has accepted the NDA at version 1
    And the NDA config version is bumped to 2
    Then the acceptance should not be version-current for the NDA config

  # LP accepted version 2, config is version 2 — acceptance is current.
  @rack_test
  Scenario: Acceptance is current when version matches
    Given the NDA config version is bumped to 2
    And the investor "Acme Capital" has accepted the NDA at version 2
    Then the acceptance should be version-current for the NDA config

  # ── resign_required flag ────────────────────────────────────────────────────

  # When resign_required is false between acceptance version and current, acceptance stays valid.
  @rack_test
  Scenario: Version gap with resign_required false keeps acceptance valid
    Given the investor "Acme Capital" has accepted the NDA at version 1
    And a version 2 record exists with resign_required false
    And the NDA config version is set to 2
    Then the acceptance should be version-current for the NDA config

  # When resign_required is true between versions, acceptance is stale.
  Scenario: Version gap with resign_required true makes acceptance stale
    Given the investor "Acme Capital" has accepted the NDA at version 1
    And a version 2 record exists with resign_required true
    And the NDA config version is set to 2
    Then the acceptance should not be version-current for the NDA config

  # Mixed: v2 resign_required=false, v3 resign_required=true → stale.
  Scenario: Any resign_required true in version range makes acceptance stale
    Given the investor "Acme Capital" has accepted the NDA at version 1
    And a version 2 record exists with resign_required false
    And a version 3 record exists with resign_required true
    And the NDA config version is set to 3
    Then the acceptance should not be version-current for the NDA config

  # ── Time-based Expiry: fixed_period ─────────────────────────────────────────

  # LP accepted 91 days ago with 90-day validity — expired.
  @rack_test
  Scenario: Fixed period acceptance is expired after validity_days
    Given the NDA config has fixed_period validity of 90 days
    And the investor "Acme Capital" accepted the NDA 91 days ago
    Then the acceptance should be time-expired for the NDA config

  # LP accepted 30 days ago with 90-day validity — still valid.
  Scenario: Fixed period acceptance is valid within validity_days
    Given the NDA config has fixed_period validity of 90 days
    And the investor "Acme Capital" accepted the NDA 30 days ago
    Then the acceptance should not be time-expired for the NDA config

  # ── Time-based Expiry: specific_date ────────────────────────────────────────

  # NDA config validity_date is in the past — expired.
  @rack_test
  Scenario: Specific date acceptance is expired when validity_date is past
    Given the NDA config has specific_date validity set to 30 days ago
    And the investor "Acme Capital" has accepted the NDA
    Then the acceptance should be time-expired for the NDA config

  # NDA config validity_date is in the future — still valid.
  Scenario: Specific date acceptance is valid when validity_date is future
    Given the NDA config has specific_date validity set to 30 days from now
    And the investor "Acme Capital" has accepted the NDA
    Then the acceptance should not be time-expired for the NDA config

  # ── Time-based Expiry: until_revoked ────────────────────────────────────────

  # until_revoked NDAs never expire by time.
  Scenario: Until_revoked acceptance never expires by time
    Given the investor "Acme Capital" accepted the NDA 365 days ago
    Then the acceptance should not be time-expired for the NDA config

  # ── Resolver: Expired Status ────────────────────────────────────────────────

  # Accepted investor with version mismatch shows as "Expired" with reason "version".
  @rack_test
  Scenario: Resolver shows Expired status for version mismatch
    Given the investor "Acme Capital" has accepted the NDA at version 1
    And the NDA config version is bumped to 2
    When the resolver resolves NDA status for the folder
    Then the investor "Acme Capital" status should be "Expired"
    And the investor "Acme Capital" expiry_reason should be "version"

  # Accepted investor with time-expired acceptance shows as "Expired" with reason "period".
  @rack_test
  Scenario: Resolver shows Expired status for time expiry
    Given the NDA config has fixed_period validity of 90 days
    And the investor "Acme Capital" accepted the NDA 91 days ago
    When the resolver resolves NDA status for the folder
    Then the investor "Acme Capital" status should be "Expired"
    And the investor "Acme Capital" expiry_reason should be "period"

  # Accepted investor with valid version and time shows as "Accepted".
  @rack_test
  Scenario: Resolver shows Accepted for valid acceptance
    Given the investor "Acme Capital" has accepted the NDA
    When the resolver resolves NDA status for the folder
    Then the investor "Acme Capital" status should be "Accepted"
    And the resolver counters should show accepted 1

  # Resolver expired counter increments for expired investors.
  @rack_test
  Scenario: Resolver counters include expired count
    Given the investor "Acme Capital" has accepted the NDA at version 1
    And the NDA config version is bumped to 2
    When the resolver resolves NDA status for the folder
    Then the resolver counters should show expired 1

  # ── NdaConfigVersion Cascade ────────────────────────────────────────────────

  # Destroying the NDA config cascades to version records.
  @rack_test
  Scenario: NdaConfigVersion records are destroyed with NdaConfig
    When a version 1 record is created for the NDA config
    And the NDA config is destroyed
    Then there should be 0 NDA config version records for the config

  # ── Lapsed Page (specific_date past) ────────────────────────────────────────

  # When specific_date is past, re-acceptance would create an immediately-expired
  # record. The gate should identify this as a lapsed state.
  @rack_test
  Scenario: Specific date NDA is lapsed when validity_date is past
    Given the NDA config has specific_date validity set to 30 days ago
    Then the NDA config should be identified as lapsed

  # When specific_date is in the future, the NDA is not lapsed.
  Scenario: Specific date NDA is not lapsed when validity_date is future
    Given the NDA config has specific_date validity set to 30 days from now
    Then the NDA config should not be identified as lapsed

  # ── Validation: Past validity_date on existing config ───────────────────────

  # GP can update other fields on a config whose specific_date has passed.
  @rack_test
  Scenario: GP can update non-date fields on a config with past validity_date
    Given the NDA config has specific_date validity set to 30 days ago
    When the GP updates the NDA config contact_email to "legal@firm.com"
    Then the NDA config contact_email should be "legal@firm.com"
