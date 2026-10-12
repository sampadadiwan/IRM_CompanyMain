@doc_checks @import
Feature: Document Checks — export to xlsx and import with ImportUpload
  The setup page's Export downloads every check in the columns the import reads back, so the sheet can be
  edited and uploaded (ImportUpload type DocCheck). A row with an Id updates that check; a row without one
  adds a check. Nothing is deleted. A row that can't be saved is reported in the results file and the other
  rows are still saved.
  Worked examples H14, H15, E24, E25, X11, X12 in
  openspec/changes/document-checks/design.md#worked-examples

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;enable_kycs=true;enable_doc_llm_validation=true;enable_import_uploads=true"
    And the user has role "company_admin"
    And the entity requires the individual KYC documents "CML, PAN Card, Passport"
    And the KYC form has the custom fields "dp=DP ID; client=Client ID"

  # H14 — the export is the import's format
  Scenario: The export lists every check in the import's columns
    Given the entity has the sample document checks
    Then the setup page should offer Export and Import
    When I export the document checks
    Then the export should have the columns "Id, Document, What To Do, Look For, KYC Field, Tip, Replace Existing, Expected Answer"
    And the export should have 11 checks
    And the export row for "DP ID" on "CML" should be "Fill in | DP ID | DP ID | 8 chars, starts with IN | No | "
    And the export row for "PAN" on "CML" should be "Compare | PAN | PAN |  |  | "
    And the export row for "Is it signed by the holder?" on "CML" should be "Question | Is it signed by the holder? |  |  |  | Yes"

  # H15 — export, edit one row, add one, upload it back
  Scenario: An edited export uploaded back updates and adds checks
    Given the entity has the sample document checks
    When I export the document checks
    And in the export I change the tip of "DP ID" on "CML" to "Printed in the header"
    And in the export I add the row "PAN Card | Compare | PAN | PAN | The card's PAN |  | "
    And I import the edited export
    Then the document check import should have 12 saved and 0 failed rows
    And the entity should have 12 document checks
    And the check "DP ID" on "CML" should have the tip "Printed in the header"
    And the check "PAN" on "PAN Card" should "compare" the field "PAN"
    And the check "PAN" on "PAN Card" should have been created by the import
    And the check "DP ID" on "CML" should not have been created by the import
    And the import's upload page should open and link to Document Checks

  # The sample upload file linked from the import page
  @rack_test
  Scenario: The sample upload file creates its checks
    When I import the document checks sample file
    Then the document check import should have 5 saved and 0 failed rows
    And the entity should have 5 document checks
    And the check "Name" on "PAN Card" should "compare" the field "full_name"

  # E24 duplicate without an Id, E25 document not on the list, X11 another entity's Id, X12 unknown field;
  # a lower-case document and a field given by name still import
  @rack_test
  Scenario: Rows that can't be saved are reported and the rest are saved
    Given the entity has the sample document checks
    And another entity has a document check
    When I import the document check rows:
      | Id    | Document         | What To Do | Look For      | KYC Field  | Tip | Replace Existing | Expected Answer |
      |       | CML              | Fill in    | DP ID         | DP ID      |     |                  |                 |
      |       | Board Resolution | Compare    | Name          | Full name  |     |                  |                 |
      | OTHER | CML              | Compare    | PAN           | PAN        |     |                  |                 |
      |       | Passport         | Compare    | Aadhaar       | Aadhaar    |     |                  |                 |
      |       | passport         | Fill in    | Date of birth | birth_date |     | Yes              |                 |
    Then the document check import should have 1 saved and 4 failed rows
    And the document check import results should say "Include its Id to update it instead"
    And the document check import results should say "Document 'Board Resolution' is not on your KYC document list"
    And the document check import results should say "No check found with Id"
    And the document check import results should say "KYC Field 'Aadhaar' is not on your KYC form"
    And the entity should have 12 document checks
    And the check "Date of birth" on "Passport" should "fill in" the field "birth_date"
    And the other entity's document check should be unchanged
