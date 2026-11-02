# Worked examples (H9, X1, X3, E20, E21): openspec/changes/fix-portfolio-dashboard-widgets/design.md#worked-examples
Feature: Documents widget shows any folder the viewer may see
  The Documents widget's Folder ID can point at any folder; the documents shown are the ones the viewer may see.

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is an existing portfolio company "name=Flipkart Unlisted;category=Portfolio Company"

  # H9 — Happy path: a folder of the viewer's own entity that is not inside the company's folder
  @javascript
  Scenario: Folder outside the company's own folder
    Given the entity has a folder "Acme Shared Docs" outside the company folder with the document "Board Pack"
    And the company dashboard has a Documents widget for that folder
    When I open the company page
    And I choose the folder "Acme Shared Docs" in the Documents widget
    Then the Documents widget should list "Board Pack"

  # X1 — Error case: a folder of another entity gives no documents and no folder name
  @javascript
  Scenario: Folder of another entity
    Given another entity has a folder "Beta Board Pack" with the document "Beta Secret"
    And the company dashboard has a Documents widget for that folder
    When I open the company page
    Then the Documents widget should list no documents and not name the folder "Beta Board Pack"

  # X3 — Error case: an investor viewer gets no documents and no folder name for a folder not shared with them
  @javascript
  Scenario: Folder not shared with an investor viewer
    Given the entity has a folder "Acme Shared Docs" outside the company folder with the document "Board Pack"
    And the portfolio company has a user who is signed in as an investor
    And the company dashboard has a Documents widget for that folder
    When I open the company page
    Then the Documents widget should list no documents and not name the folder "Acme Shared Docs"

  # E20 — Edge case: the same investor viewer sees the folder's documents once it is shared with them
  @javascript
  Scenario: Folder shared with an investor viewer
    Given the entity has a folder "Acme Shared Docs" outside the company folder with the document "Board Pack"
    And that folder and its documents are shared with the portfolio company
    And the portfolio company has a user who is signed in as an investor
    And the company dashboard has a Documents widget for that folder
    When I open the company page
    Then the Documents widget should list "Board Pack"

  # E21 — Edge case: an employee who is not a company admin sees the documents in the folder itself
  @javascript
  Scenario: Folder of the entity viewed by an employee
    Given the entity has a folder "Acme Shared Docs" outside the company folder with the document "Board Pack"
    And an employee of the entity who is not a company admin is signed in
    And the company dashboard has a Documents widget for that folder
    When I open the company page
    Then the Documents widget should list "Board Pack"
