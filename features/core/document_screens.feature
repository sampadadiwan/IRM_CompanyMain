Feature: Document screens - list, show page and form
  The Documents list heads a folder with its clickable path, shows each document's status in its own
  column and keeps every row action in one menu. The show page puts the status and actions above the
  viewer and explains what users can do with the document. The form groups its fields in numbered
  sections with iOS-style toggles, suggests tags already used in the folder, and creates a new folder
  in a popup without leaving the form.

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Company"
    And the user has role "company_admin"
    And the entity has a folder "name=Reports"
    And the entity has a child folder "name=Quarterly"

  # DS1 — the folder path is the heading: firm name for the root, then each folder, all clickable
  Scenario: The folder path heads the document list, every part opening that folder
    Given the child folder has a document "Q2 Statement" tagged "statement"
    When I open the child folder on the documents page
    Then the folder path should show the firm name, "Reports" and "Quarterly" as links

  # DS2 — Edge case: Show is in the row menu too (the name link already opens the document)
  Scenario: Every row action is in the document row actions menu
    Given the child folder has a document "Q2 Statement" tagged "statement"
    When I open the child folder on the documents page
    And I open the document row actions menu
    Then the document row actions menu should offer "Show, Edit, Delete"
    When I choose "Show" from the document row actions menu
    Then I should be on the show page of the document

  # DS3 — a generated document waiting for approval says so in the Status column and on the show page;
  # approving explains what happens first, then flips the status
  Scenario: A generated document is approved from its show page after the explain popup
    Given the user has role "approver"
    And the child folder has a document "Drawdown Notice" generated from a template and not yet approved
    When I open the child folder on the documents page
    Then the document row should show the status "Pending Approval"
    When I open the show page of the document
    And I click Approve on the document
    Then the approve popup should explain "Investors can see it"
    When I click Proceed in the popup
    Then the document header should show the status "Approved"
    And the document should be approved

  # DS4 — the show page cards: details, what users can do (one row per setting), tab icons
  Scenario: The show page explains the document and what users can do with it
    Given the child folder has a document "Q2 Statement" tagged "statement"
    When I open the show page of the document
    Then the show page should have the details card and the "What users can do" card
    And the "What users can do" card should show "Download" as "Yes"

  # DS5 — Edge case: tags already on the document are not offered back; clicking a chip adds it once and hides it
  Scenario: The form suggests tags used in the folder, except the document's own
    Given the child folder has a document "Q1 Statement" tagged "statement, quarterly"
    And the child folder has a document "Q2 Statement" tagged "statement"
    When I edit the document
    Then the tag suggestions should offer "quarterly"
    And the tag suggestions should not offer "statement"
    When I click the tag suggestion "quarterly"
    Then the tags field should read "statement, quarterly"
    And the tag suggestion "quarterly" should be hidden

  # DS6 — the New folder popup creates the folder inside the picked one and selects it, without leaving the form
  Scenario: A new folder is created from the document form and picked
    When I open the new document form from the child folder
    And I create the folder "Board Packs" from the document form
    Then the folder "Board Packs" should be created inside the child folder and picked

  # DS7 — Edge case: a blank name is refused inside the popup, nothing is created
  Scenario: The New folder popup refuses a blank name
    When I open the new document form from the child folder
    And I create the folder "" from the document form
    Then the New folder popup should say "Enter a name for the folder."

  # DS8 — the eSignatures section only exists while the Template toggle is on
  Scenario: Turning on the Template toggle shows the eSignatures section
    When I open the new document form from the child folder
    Then the eSignatures section should be hidden
    When I turn on the document toggle "document_template"
    Then the eSignatures section should be visible

  # DS9 — Edge case: Edit/Delete load when the menu opens and follow the policy; a view-only employee gets neither
  Scenario: An employee who may only view a document gets no Edit or Delete in its row menu
    Given the entity has a fund "Alpha Fund" with a document "Fund Deck"
    And I am signed in as an employee with view-only access to the fund
    When I open the fund's documents folder on the documents page
    And I open the document row actions menu
    Then the document row actions menu should say "You can view this document but not change it."
    And the document row actions menu should not offer "Edit, Delete"
