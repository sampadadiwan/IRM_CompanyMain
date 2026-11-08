Feature: Folder page
  The folder page names the folder and where it sits in one header, with its actions beside it, says
  what its defaults are for (they are copied into every new document uploaded there), and lists its
  documents without repeating the folder's name and path.

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Company"
    And the user has role "company_admin"
    And the entity has a folder "name=Reports"
    And the entity has a child folder "name=Quarterly"

  # FP1 — the header replaces "Viewing Folder" and the Name / Parent / Full Path rows: path links + actions
  Scenario: The folder header shows where the folder sits and what can be done with it
    When I open the folder page of the child folder
    Then the folder header should show "Quarterly" under the firm name and "Reports" as links
    And the folder actions should offer "Edit, New Sub Folder, Download Folder"

  # FP2 — the defaults are explained as what new documents start with, one row per setting
  Scenario: The folder defaults say what new documents start with
    Given the child folder's defaults are "download=true;printing=false"
    When I open the folder page of the child folder
    Then the "New documents start with" card should show "Download" as "Yes" and "Print" as "No"

  # FP3 — Edge case: the Documents tab lists only this folder's own documents, without a second path heading
  Scenario: The Documents tab lists the folder's documents without repeating its path
    Given the child folder has a document "Q2 Statement" tagged "statement"
    When I open the folder page of the child folder
    Then the folder's Documents tab should list "Q2 Statement"
    And the folder's Documents tab should not repeat the folder path

  # FP4 — a private folder says so, with what that means
  Scenario: A private folder is marked Private
    Given the child folder is private
    When I open the folder page of the child folder
    Then the folder header should show the badge "Private"
