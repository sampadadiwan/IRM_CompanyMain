Feature: NDA Status Dashboard (Module 3)
  As a GP I want to see which investors have accepted, declined, or are pending
  NDA acceptance for my Data Room folders, and manage user-level exemptions.

  Background:
    Given there is a user "" for an entity "entity_type=Investment Fund;enable_funds=true"
    Given the entity has "enable_data_rooms" permission
    Given the GP entity has a data room folder
    Given the data room folder has an enabled NDA config

  # ── Phase 1: NdaExemption Model ────────────────────────────────────────────

  # An NdaExemption record can be created linking a user to an NDA config.
  Scenario: NdaExemption stores user, exempted_by, and reason
    Given there is an LP user for the GP entity
    When the GP creates an NDA exemption for the LP user with reason "Signed offline"
    Then an NDA exemption record should exist for the LP user
    And the NDA exemption reason should be "Signed offline"
    And the NDA exemption exempted_by should be the GP user

  # Duplicate exemptions are prevented by the unique constraint.
  Scenario: Duplicate NdaExemption is rejected
    Given there is an LP user for the GP entity
    When the GP creates an NDA exemption for the LP user with reason "First"
    Then creating a duplicate NDA exemption for the LP user should raise an error

  # Deleting an NDA config cascades to its exemptions.
  Scenario: NdaExemption is destroyed when NdaConfig is destroyed
    Given there is an LP user for the GP entity
    When the GP creates an NDA exemption for the LP user with reason "Temp"
    And the NDA config is destroyed
    Then there should be 0 NDA exemptions for the LP user

  # ── Phase 2: NdaStatusResolver ──────────────────────────────────────────────

  # The resolver returns the correct investor universe from InvestorAccess.
  Scenario: Resolver returns investors from InvestorAccess
    Given there is an LP investor "Acme Capital" with approved access to the GP entity
    When the resolver resolves NDA status for the folder
    Then the resolver result should include investor "Acme Capital"
    And the resolver counters should show pending 1

  # The resolver correctly identifies an accepted investor.
  Scenario: Resolver shows accepted status for investor that signed
    Given there is an LP investor "Acme Capital" with approved access to the GP entity
    And the investor "Acme Capital" has accepted the NDA
    When the resolver resolves NDA status for the folder
    Then the investor "Acme Capital" status should be "Accepted"
    And the resolver counters should show accepted 1

  # The resolver correctly identifies a declined investor.
  Scenario: Resolver shows declined status for investor that declined
    Given there is an LP investor "Acme Capital" with approved access to the GP entity
    And the investor "Acme Capital" has declined the NDA
    When the resolver resolves NDA status for the folder
    Then the investor "Acme Capital" status should be "Declined"
    And the resolver counters should show declined 1

  # When all users of an investor are individually exempt, investor status is "Exempt".
  Scenario: Investor status is Exempt when all users are exempt
    Given there is an LP investor "Acme Capital" with approved access to the GP entity
    And all users of investor "Acme Capital" are exempt from the NDA
    When the resolver resolves NDA status for the folder
    Then the investor "Acme Capital" status should be "Exempt"
    And the resolver counters should show exempt 1

  # Investors without approved InvestorAccess do not appear in the resolver.
  Scenario: Unapproved investor does not appear in resolver results
    Given there is an LP investor "Acme Capital" with unapproved access to the GP entity
    When the resolver resolves NDA status for the folder
    Then the resolver result should not include investor "Acme Capital"

  # ── Phase 3: Gate Exemption Check ───────────────────────────────────────────

  # An exempt user bypasses the NDA gate even if their stakeholder has not accepted.
  Scenario: Exempt user bypasses NDA gate
    Given there is an LP user for the GP entity
    And the LP user has an NDA exemption
    Then the NDA exemption check should pass for the LP user

  # A non-exempt user whose stakeholder has not accepted is blocked by the gate.
  Scenario: Non-exempt user with no stakeholder acceptance is blocked
    Given there is an LP user for the GP entity
    Then the NDA exemption check should not pass for the LP user

  # ── Phase 4: NdaStatusPolicy ────────────────────────────────────────────────

  # GP employees of the same entity are allowed to view the dashboard.
  Scenario: GP employee is authorized for NDA status actions
    Then the NDA status policy should allow summary for the GP user
    And the NDA status policy should allow index for the GP user
    And the NDA status policy should allow create_exemption for the GP user
    And the NDA status policy should allow destroy_exemption for the GP user
    And the NDA status policy should allow create_signatory for the GP user
    And the NDA status policy should allow destroy_signatory for the GP user

  # LP users are denied access to the dashboard.
  Scenario: LP user is denied NDA status actions
    Given there is an LP user for the GP entity
    Then the NDA status policy should deny summary for the LP user
    And the NDA status policy should deny index for the LP user

  # GP users from a different entity are denied access.
  Scenario: Other-entity GP is denied NDA status actions
    Given there is a GP user from a different entity
    Then the NDA status policy should deny summary for the other GP user

  # ── Phase 5: NdaSignatory ──────────────────────────────────────────────────

  # An NdaSignatory record can be created linking a user to an NDA config.
  Scenario: NdaSignatory stores user and tagged_by
    Given there is an LP user for the GP entity
    When the GP tags the LP user as an NDA signatory
    Then an NDA signatory record should exist for the LP user
    And the NDA signatory tagged_by should be the GP user

  # Duplicate signatories are prevented by the unique constraint.
  Scenario: Duplicate NdaSignatory is rejected
    Given there is an LP user for the GP entity
    When the GP tags the LP user as an NDA signatory
    Then creating a duplicate NDA signatory for the LP user should raise an error

  # Deleting an NDA config cascades to its signatories.
  Scenario: NdaSignatory is destroyed when NdaConfig is destroyed
    Given there is an LP user for the GP entity
    When the GP tags the LP user as an NDA signatory
    And the NDA config is destroyed
    Then there should be 0 NDA signatories for the LP user

  # Resolver shows nda_tagged true for a signatory user.
  Scenario: Resolver shows signatory user as nda_tagged
    Given there is an LP investor "Acme Capital" with approved access to the GP entity
    And the LP user is tagged as a signatory for the NDA
    When the resolver resolves NDA status for the folder
    Then the LP user should be marked as nda_tagged in the resolver result

  # Resolver shows nda_tagged false for a non-signatory user.
  Scenario: Resolver shows non-signatory user as not nda_tagged
    Given there is an LP investor "Acme Capital" with approved access to the GP entity
    When the resolver resolves NDA status for the folder
    Then the LP user should not be marked as nda_tagged in the resolver result
