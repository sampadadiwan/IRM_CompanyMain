@rack_test
Feature: Linking an approved KYC to existing evergreen folios
  Worked examples H6, H8, E6, E7, E8, E9, X12, X13, X14 — openspec/changes/evergreen-folio-soa/design.md#worked-examples

  Background:
    Given Im logged in as a user "first_name=Asha" for an entity "name=Caphive Demo;entity_type=Investment Fund"
    And the user has role "company_admin"
    And the entity has evergreen funds switched on
    And today is "2026-10-20"
    And the evergreen fund "Alpha Evergreen Fund" with classes "A" and settings "redemption_calendar=monthly"

  # H6 — Happy path: the clean-up task links a folio's only approved KYC; the dry run changes nothing
  Scenario: The clean-up task links the single approved KYC
    Given "B LLP" holds "7000" units of class "A" in folio "F-031" issued "2025-09-01"
    And folio "F-031" has no KYC linked
    When the folio KYC link task runs ""
    Then the task output should mention "F-031 B LLP → KYC"
    And the task output should mention "Would link 1; 0 need a manual choice"
    And folio "F-031" should have no KYC linked
    When the folio KYC link task runs "with EXECUTE=1"
    Then the task output should mention "Linked 1; 0 need a manual choice"
    And folio "F-031" should be for investing entity "B LLP"

  # H8 — Happy path: the GP links one of two approved KYCs with the picker; the badge goes and orders are accepted
  Scenario: The GP links a KYC on the folio page
    Given "B LLP" holds "7000" units of class "A" in folio "F-031" issued "2025-09-01"
    And folio "F-031" has no KYC linked
    And "B LLP" has another approved KYC "B Holdings"
    When I open folio "F-031"
    Then I should see "No KYC linked"
    And the investing entity picker should offer "B Holdings, B LLP"
    When I link the investing entity "B Holdings"
    Then I should see "Investing entity linked"
    And I should not see "No KYC linked"
    And the folio page should have no investing entity picker
    And folio "F-031" should be for investing entity "B Holdings"
    When "B LLP" tries to place a "redemption" order "folio=F-031;units=100" received "2026-10-20 09:00"
    Then the order should be accepted

  # E6 — Edge case: the picker offers only the folio investor's approved KYCs — not pending ones, not another investor's
  Scenario: The picker lists only the investor's approved KYCs
    Given "P Family Trust" is an investor of the fund with a portal user
    And "B LLP" holds "7000" units of class "A" in folio "F-031" issued "2025-09-01"
    And folio "F-031" has no KYC linked
    And "B LLP" has a pending KYC "B Pending"
    When I open folio "F-031"
    Then the investing entity picker should offer "B LLP"

  # E7 — Edge case: the task lists a folio whose investor has two approved KYCs and leaves it unlinked
  Scenario: Two approved KYCs are left for the picker
    Given "B LLP" holds "7000" units of class "A" in folio "F-031" issued "2025-09-01"
    And folio "F-031" has no KYC linked
    And "B LLP" has another approved KYC "B Holdings"
    When the folio KYC link task runs "with EXECUTE=1"
    Then the task output should mention "F-031 B LLP — 2 or more approved KYCs, link on the folio page"
    And folio "F-031" should have no KYC linked

  # E8 — Edge case: the task lists a folio whose investor has no approved KYC; the folio page points to KYC
  Scenario: No approved KYC is left for the picker
    Given "B LLP" holds "7000" units of class "A" in folio "F-031" issued "2025-09-01"
    And folio "F-031" has no KYC linked
    And "B LLP" has no approved KYC
    When the folio KYC link task runs "with EXECUTE=1"
    Then the task output should mention "F-031 B LLP — 0 approved KYCs, link on the folio page"
    When I open folio "F-031"
    Then I should see "B LLP has no approved KYC — approve one in KYC first."
    And the folio page should have no investing entity picker

  # E9 — Edge case: re-running the task skips folios already linked
  Scenario: The task is idempotent
    Given "B LLP" holds "7000" units of class "A" in folio "F-031" issued "2025-09-01"
    And folio "F-031" has no KYC linked
    When the folio KYC link task runs "with EXECUTE=1"
    And the folio KYC link task runs "with EXECUTE=1"
    Then the task output should mention "Linked 0; 0 need a manual choice"
    And folio "F-031" should be for investing entity "B LLP"

  # X12 — Error case: a direct request linking another investor's KYC is refused
  Scenario: Another investor's KYC can't be linked
    Given "P Family Trust" is an investor of the fund with a portal user
    And "B LLP" holds "7000" units of class "A" in folio "F-031" issued "2025-09-01"
    And folio "F-031" has no KYC linked
    When I open folio "F-031"
    And a request links folio "F-031" to the KYC "P Family Trust" of "P Family Trust"
    Then I should see "Choose one of B LLP's approved KYCs"
    And folio "F-031" should have no KYC linked

  # X13 — Error case: a linked folio's KYC can't be changed
  Scenario: A linked folio keeps its KYC
    Given "B LLP" holds "7000" units of class "A" in folio "F-031" issued "2025-09-01"
    And "B LLP" has another approved KYC "B Holdings"
    When I open folio "F-031"
    And a request links folio "F-031" to the KYC "B Holdings" of "B LLP"
    Then I should see "This folio already has an investing entity"
    And folio "F-031" should be for investing entity "B LLP"

  # X14 — Error case: a read-only employee sees no picker and a direct request is refused
  Scenario: A read-only employee can't link
    Given "B LLP" holds "7000" units of class "A" in folio "F-031" issued "2025-09-01"
    And folio "F-031" has no KYC linked
    And a read-only employee "Ravi" of the fund
    When "Ravi" logs in
    And I open folio "F-031"
    Then the folio page should have no investing entity picker
    When a request links folio "F-031" to the KYC "B LLP" of "B LLP"
    Then folio "F-031" should have no KYC linked
