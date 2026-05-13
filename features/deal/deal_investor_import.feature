Feature: Import Deal Investors
  Can bulk import deal investors into a deal, including Update Only mode

  Background:
    Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Company"
    Given the user has role "company_admin"
    And there exists a deal "name=Series A;amount_cents=500000" for my company

  @import
  Scenario: Import new deal investors from xlsx
    Given there are "3" existing investor ""
    When I import deal investors using "deal_investors.xlsx"
    Then "1" deal investor should be created for the deal
    And the imported deal investor should have the correct attributes from "deal_investors.xlsx"
    And the deal investor should have deal activities created

  @import
  Scenario: Import deal investors with Update Only - investor exists
    Given there are "3" existing investor ""
    And there is an existing deal investor for the deal
    When I import deal investors using "deal_investors_update_only.xlsx"
    Then the deal investor should be updated with data from "deal_investors_update_only.xlsx"

  @import
  Scenario: Import deal investors with Update Only - investor does not exist as deal investor
    Given there are "3" existing investor ""
    When I import deal investors using "deal_investors_update_only.xlsx"
    Then the import should have "1" failed rows with error "not found for update"

  @import
  Scenario: Import deal investors skips duplicate when no Update Only flag
    Given there are "3" existing investor ""
    And there is an existing deal investor for the deal
    When I import deal investors using "deal_investors.xlsx"
    Then the import should have "1" failed rows with error "already exists"
