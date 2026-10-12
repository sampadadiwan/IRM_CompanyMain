Feature: Deal Template Management
  GPs can control whether a new deal gets default step templates, and can
  bulk-import step templates from an XLSX file on the Deal Steps tab.

  Background:
    Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Company"
    Given the user has role "company_admin"

  # ── Feature 1: No Templates checkbox ────────────────────────────────────────

  @templates @rack_test
  Scenario: Creating a deal with "no templates" skips template seeding
    Given there exists a deal "name=Source Deal;amount_cents=500000" for my company without templates
    And the deal has "3" step templates
    When I create a deal cloning from the source deal with skip_templates
    Then the cloned deal should have "0" step templates

  @templates @rack_test
  Scenario: Creating a deal without the flag inherits cloned templates
    Given there exists a deal "name=Source Deal;amount_cents=500000" for my company without templates
    And the deal has "3" step templates
    When I create a deal cloning from the source deal
    Then the cloned deal should have "3" step templates

  # ── Feature 2: Import templates from XLSX ───────────────────────────────────

  @import
  Scenario: Importing deal activity templates creates template records
    Given there exists a deal "name=Series A;amount_cents=500000" for my company without templates
    When I import deal activity templates using an XLSX with "3" rows
    Then the deal should have "3" activity templates
    And the imported templates should have the correct titles and days

  @import
  Scenario: Importing templates appends to existing templates preserving sequence
    Given there exists a deal "name=Series A;amount_cents=500000" for my company without templates
    And the deal has "2" step templates
    When I import deal activity templates using an XLSX with "3" rows
    Then the deal should have "5" activity templates
    And the imported templates are sequenced after the existing ones

  @import
  Scenario: Importing with missing required columns disables Save with a column error
    Given there exists a deal "name=Series A;amount_cents=500000" for my company without templates
    When I import deal activity templates using an XLSX with missing columns
    Then the import should fail with a column error

  @import
  Scenario: Importing templates on a deal with investors regenerates investor activities
    Given there exists a deal "name=Series A;amount_cents=500000" for my company without templates
    And there are "2" existing investor ""
    And there is an existing deal investor for the deal
    When I import deal activity templates using an XLSX with "2" rows
    Then the deal should have "2" activity templates
    And the deal investor activities should be regenerated to match the imported templates
