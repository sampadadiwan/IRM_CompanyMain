Feature: Fund documents panel - LP latest documents and search
  On the fund page an LP sees every document shared with them anywhere in the fund's folder tree,
  newest first, without having to open folders one by one. LPs and the fund owner can search the
  whole fund folder tree by document name or tag. Search only ever returns documents the user may
  see, and only from this fund's folders.

  Background:
    Given there is a user "first_name=Gita" for an entity "entity_type=Investment Fund;enable_funds=true"
    And the user has role "company_admin"
    And there is a fund "name=Alpha Fund" for the entity
    And there is an existing investor "" with "1" users
    And the investors are added to the fund
    # Rows are created top to bottom, so the last row is the newest document
    And the fund has these documents shared with the investor:
      | name                  | folder                 | tags         |
      | Annual Report 2025    | Reports                |              |
      | Statement - Q2 2026   | Reports/Quarterly      |              |
      | Capital Call Notice 3 | Notices                | capital-call |
      | Board Minutes         | Reports/Quarterly/2026 | governance   |
    And the fund has a document "Statement - Q2 2026 Draft" in folder "Reports/Quarterly" not shared with the investor
    And another fund "Beta Fund" has a document "Statement - Q2 2026 Beta" shared with the investor

  # D1 — Edge case: the LP lands on every shared doc in the fund tree (subfolders included), newest first, without clicking a folder
  Scenario: LP sees the latest documents from all fund folders, newest first, with their folder
    Given I login as the investor user
    When I open the Documents section of the fund page as the investor
    Then the documents panel title should be "Latest Documents"
    And the documents panel should list exactly "Board Minutes, Capital Call Notice 3, Statement - Q2 2026, Annual Report 2025" in that order
    And the document "Board Minutes" should show the folder "2026"
    And the document "Annual Report 2025" should show the folder "Reports"

  Scenario Outline: LP searches the fund documents
    Given I login as the investor user
    When I open the Documents section of the fund page as the investor
    And I search the documents panel for "<term>"
    Then the documents panel title should be "Search results"
    And the documents panel should list exactly "<results>"

    Examples:
      | term           | results               |
      # D3 — Edge case: the words match the name in a different order from how they were typed
      | 2026 statement | Statement - Q2 2026   |
      # D4 — Edge case: the word only appears in the tags, not in the name
      | governance     | Board Minutes         |
      # D5 — Edge case: upper-case search text still matches a mixed-case name
      | STATEMENT Q2   | Statement - Q2 2026   |
      # D6 — Edge case: "Statement - Q2 2026 Draft" matches by name but has no access right for this LP, so it is left out
      # D7 — Edge case: "Statement - Q2 2026 Beta" matches by name and is shared with the LP, but lives in another fund, so it is left out
      | q2 statement   | Statement - Q2 2026   |
      # D8 — Edge case: a word typed after a match is ANDed, so it narrows to the one doc carrying both
      | capital notice | Capital Call Notice 3 |

  # D9 — Edge case: nothing matches, so the panel says why it is empty instead of looking like a fund with no documents
  Scenario: LP search with no match explains the empty list
    Given I login as the investor user
    When I open the Documents section of the fund page as the investor
    And I search the documents panel for "zzzz nothing"
    Then the documents panel should list exactly ""
    And the documents panel should show the empty message 'No documents match "zzzz nothing"'

  # D10 — Edge case: clearing the search returns the LP to the latest documents, not to an empty root folder
  Scenario: LP clears the search and is back on the latest documents
    Given I login as the investor user
    When I open the Documents section of the fund page as the investor
    And I search the documents panel for "governance"
    Then the documents panel should list exactly "Board Minutes"
    When I clear the documents panel search
    Then the documents panel title should be "Latest Documents"
    And the documents panel should list exactly "Board Minutes, Capital Call Notice 3, Statement - Q2 2026, Annual Report 2025" in that order

  # D11 — Edge case: the fund owner's panel opens on the (empty) root folder, yet search reaches a doc two folders down
  Scenario: Fund owner searches the fund documents tab and finds a doc in a subfolder
    Given I am signed in as the current user
    When I visit the fund details page
    And I click on fund documents tab
    Then the documents panel should list exactly ""
    When I search the documents panel for "minutes board"
    Then the documents panel title should be "Search results"
    And the documents panel should list exactly "Board Minutes"
    And the document "Board Minutes" should show the folder "2026"

  # D12 — Edge case: % and _ typed by the user are literal characters, not LIKE wildcards
  # D13 — Edge case: several words are ANDed - every word must appear, in any order, in the name or tags
  @rack_test
  Scenario: name_or_tags_matching treats % and _ literally and ANDs every word
    Given the fund has these documents shared with the investor:
      | name           | folder | tags |
      | Fee 50% rebate | Fees   |      |
      | Fee 500 rebate | Fees   |      |
      | Q_2 memo       | Fees   |      |
      | QX2 memo       | Fees   |      |
    Then searching the entity's documents for "50%" should return exactly "Fee 50% rebate"
    And searching the entity's documents for "Q_2" should return exactly "Q_2 memo"
    And searching the entity's documents for "rebate fee 500" should return exactly "Fee 500 rebate"
    And searching the entity's documents for "2026 statement" should return exactly "Statement - Q2 2026, Statement - Q2 2026 Beta, Statement - Q2 2026 Draft"
    And searching the entity's documents for "statement annual" should return exactly ""
    And searching the entity's documents for "CAPITAL-CALL" should return exactly "Capital Call Notice 3"
