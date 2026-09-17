Feature: Import Deal Investors
  Bulk-imports deal investors, deal-activity statuses, and notes from the
  three-sheet "Deal Investors" xlsx template.

  Background:
    Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Company"
    Given the user has role "company_admin"
    And there exists a deal "name=Series A;amount_cents=500000;skip_templates=1" for my company

  @import
  Scenario: Import new deal investors from the multi-sheet template
    Given there are "3" existing investor ""
    And the deal has deal activity templates "Deck Sent,Meeting 1" imported
    When I import deal investors using the new template
    Then "1" deal investor should be created for the deal
    And the imported deal investor should have the correct attributes
    And the deal investor should have deal activities created

  @import
  Scenario: Import generates the first step's tasks once, not twice
    Given there are "3" existing investor ""
    And the deal has deal activity templates "Deck Sent,Meeting 1" imported
    And the deal step "Deck Sent" has the following tasks: "Send deck, Log intro call"
    When I import deal investors using the new template
    And the step tasks job runs again for the imported deal investor
    Then the imported deal investor should have one task each for "Send deck, Log intro call"

  @import
  Scenario: Import updates deal activity statuses from the Deal Steps sheet
    Given there are "3" existing investor ""
    And the deal has deal activity templates "Deck Sent,Meeting 1" imported
    When I import deal investors using the new template with deal steps
    Then the deal investor activities should have updated statuses

  @import
  Scenario: Import raises tasks for the first step the Deal Steps sheet left incomplete
    Given there are "3" existing investor ""
    And the deal has deal activity templates "Deck Sent,Meeting 1" imported
    And the deal step "Deck Sent" has the following tasks: "Send deck"
    And the deal step "Meeting 1" has the following tasks: "Book intro call"
    When I import deal investors using the new template with deal steps
    Then the imported deal investor should be on the step "Meeting 1"
    And the imported deal investor should have one task each for "Book intro call"
    And the imported deal investor should have no task for "Send deck"

  @import
  Scenario: Import creates notes from the Notes sheet
    Given there are "3" existing investor ""
    When I import deal investors using the new template with notes
    Then notes should be created for the deal investor

  @import
  Scenario: Import sets the last interaction date to the latest note date
    Given there are "3" existing investor ""
    When I import deal investors using the new template with notes on mixed dates
    Then the deal investor last interaction date should be "2026-04-15"

  @import
  Scenario: Import creates notes with a reminder
    Given there are "3" existing investor ""
    When I import deal investors using the new template with reminder notes
    Then a reminder should be created for the note

  @import
  Scenario: Import skips duplicate when investor already exists as deal investor
    Given there are "3" existing investor ""
    And there is an existing deal investor for the deal
    When I import deal investors using the new template
    Then the import should have "1" failed rows with error "already exists"

  @import
  Scenario: Import with pre-money valuation defaults to zero when omitted
    Given there are "3" existing investor ""
    When I import deal investors using the new template without pre money valuation
    Then "1" deal investor should be created for the deal
    And the deal investor pre money valuation should be "0"

  @import
  Scenario: Import handles custom fields on deal investor
    Given there are "3" existing investor ""
    When I import deal investors using the new template with custom fields
    Then "1" deal investor should be created for the deal
    And the deal investor should have the custom field stored
