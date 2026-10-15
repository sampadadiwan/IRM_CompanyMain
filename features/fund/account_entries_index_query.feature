@account_entries_index_query @rack_test
Feature: Account Entries list reads entries on their own
  The Account Entries list used to load every row together with its fund, investor,
  commitment and KYC in one oversized query. It now reads the page of entries alone and
  fetches the related records in small look-ups for just the rows on the page. The content
  of the list must not change, and the number of related look-ups must not grow with the
  number of rows shown.

  Background:
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund;currency=INR"
    And the user has role "company_admin"
    And I am signed in as the current user
    And the entity has funds "Alpha Fund,Beta Fund"

  Scenario: Related details are still shown on each row
    Given fund "Alpha Fund" has an entry "Alpha Fee" for folio "101" of investor "Acme Capital"
    When I request the account entries feed for fund "Alpha Fund"
    Then the feed should list "1" rows
    And the feed row "Alpha Fee" should show fund "Alpha Fund", investor "Acme Capital" and investing entity "Acme Capital KYC"

  Scenario: The main query does not select related table columns
    Given fund "Alpha Fund" has an entry "Alpha Fee" for folio "101" of investor "Acme Capital"
    When I open the account entries list for fund "Alpha Fund" capturing the database queries
    Then the account entries page should load
    And the page load should have read account entries without selecting any related table columns

  Scenario: An entry without a commitment or investor is still listed
    Given fund "Alpha Fund" has a fund-level entry "Alpha Fund Fee"
    When I request the account entries feed for fund "Alpha Fund"
    Then the feed should list "1" rows
    And the feed row "Alpha Fund Fee" should have no investor and no folio

  Scenario: Related look-ups do not grow with the page size
    Given fund "Alpha Fund" has "12" entries each on its own folio
    When I request the account entries feed for fund "Alpha Fund" with "5" per page
    And I request the account entries feed for fund "Alpha Fund" with "10" per page
    Then both page sizes should have listed their full page
    And both page sizes should have made the same number of related look-ups

  Scenario: An employee sees only the funds they have access to, without repeats
    Given fund "Alpha Fund" has an entry "Alpha Fee" for folio "101" of investor "Acme Capital"
    And fund "Beta Fund" has an entry "Beta Fee" for folio "201" of investor "Beta Partners"
    And an employee with access to fund "Alpha Fund" only
    And I am signed in as the employee
    When I request the account entries feed
    Then the feed should list only the entries "Alpha Fee"

  Scenario: A user of another entity does not see this entity's entries
    Given fund "Alpha Fund" has an entry "Alpha Fee" for folio "101" of investor "Acme Capital"
    And there is a user "first_name=Other" for an entity "name=Other Co;entity_type=Investment Fund;currency=INR"
    And the user has role "company_admin"
    And the entity has funds "Gamma Fund"
    And fund "Gamma Fund" has an entry "Gamma Fee" for folio "301" of investor "Gamma Partners"
    And I am signed in as the current user
    When I request the account entries feed
    Then the feed should list only the entries "Gamma Fee"
