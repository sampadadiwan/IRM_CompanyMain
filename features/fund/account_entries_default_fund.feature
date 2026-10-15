@account_entries_index_query @rack_test
Feature: Account Entries list opens on the first fund
  The list used to open on every fund of the entity, which made the database sort the whole
  ledger. It now opens on the first fund the user can access. The user can still pick any
  fund, or several, themselves.

  Background:
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund;currency=INR"
    And the user has role "company_admin"
    And I am signed in as the current user
    And the entity has funds "Alpha Fund,Beta Fund"
    And fund "Alpha Fund" has an entry "Alpha Fee" for folio "101" of investor "Acme Capital"
    And fund "Beta Fund" has an entry "Beta Fee" for folio "201" of investor "Beta Partners"

  Scenario: With no fund selected the list opens on the first fund
    When I open the account entries list without selecting a fund
    Then the feed should list only the entries "Alpha Fee"
    And the filter should show only fund "Alpha Fund"

  Scenario: The page says which fund is shown
    When I open the account entries list without selecting a fund
    Then the page should say it shows fund "Alpha Fund"

  Scenario: No notice when the user picked the fund or All Funds
    When I choose fund "Beta Fund" in the account entries list
    Then the page should not say which fund it shows
    When I choose all funds in the account entries list
    Then the page should not say which fund it shows

  Scenario: The fund positioned first is the default
    Given fund "Beta Fund" is positioned first
    When I open the account entries list without selecting a fund
    Then the feed should list only the entries "Beta Fee"
    And the filter should show only fund "Beta Fund"

  Scenario: A request narrowed to an import is not given a default fund
    Given fund "Beta Fund" has an import with the entry "Beta Imported"
    When I open the account entries list for that import
    Then the feed should list only the entries "Beta Imported"
    And the page should not say which fund it shows

  Scenario: A request narrowed to a folio is not given a default fund
    When I open the account entries list narrowed to folio "201"
    Then the feed should list only the entries "Beta Fee"
    And the page should not say which fund it shows

  Scenario: Delete Results and Export All act on the fund that is shown
    When I open the account entries list without selecting a fund
    Then the delete results and export links should be for fund "Alpha Fund"

  Scenario: A fund the user picks is listed as given
    When I choose fund "Beta Fund" in the account entries list
    Then the feed should list only the entries "Beta Fee"

  Scenario: Choosing All Funds on purpose is respected
    When I choose all funds in the account entries list
    Then the feed should list only the entries "Alpha Fee,Beta Fee"
    And the delete results and export links should not name a fund

  Scenario: Deleting an entry returns to the list of its fund
    When I delete the entry "Beta Fee"
    Then I should be back on the account entries list of fund "Beta Fund"

  Scenario: The user can still select several funds
    When I open the account entries list with the funds "Alpha Fund,Beta Fund" in a fund_id_in filter
    Then the feed should list only the entries "Alpha Fee,Beta Fee"

  Scenario: An employee opens on the first fund they can access
    Given an employee with access to fund "Beta Fund" only
    And I am signed in as the employee
    When I open the account entries list without selecting a fund
    Then the feed should list only the entries "Beta Fee"

  Scenario: An entity without funds gets an empty list
    Given there is a user "first_name=Empty" for an entity "name=Empty Co;entity_type=Investment Fund;currency=INR"
    And the user has role "company_admin"
    And I am signed in as the current user
    When I open the account entries list without selecting a fund
    Then the feed should be empty

  Scenario: A fund of another entity is not replaced by a default
    Given there is a user "first_name=Other" for an entity "name=Other Co;entity_type=Investment Fund;currency=INR"
    And the entity has funds "Gamma Fund"
    And I am signed in as the first user of entity "Urban"
    When I choose fund "Gamma Fund" in the account entries list
    Then the feed should be empty
