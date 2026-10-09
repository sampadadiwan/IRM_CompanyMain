@doc_checks @doc_checks_fake_ai
Feature: Document Checks — the settings page
  The page reads as a summary: a tile per KYC document saying what its checks do. Suggested checks for every
  document are reviewed and added in one go, and each document is edited in its own side panel, where a check
  is added by kind (Fill in / Compare / Ask yes-no) and written as a sentence. A field removed from the KYC
  form is flagged, never silently dropped.
  Worked examples H1, H2, E1–E5, E16, X4 in openspec/changes/document-checks/design.md#worked-examples

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;enable_kycs=true;enable_doc_llm_validation=true"
    And the user has role "company_admin"
    And there is an existing investor "" with "1" users
    And the entity requires the individual KYC documents "CML, PAN Card, Passport"
    And the entity requires the non-individual KYC documents "PAN Card, Board Resolution"
    And the KYC form has the custom fields "dp=DP ID; client=Client ID"

  # E1 — a tile per document on either list, PAN Card once
  Scenario: Every KYC document has a tile
    When I open the Document Checks settings
    Then I should see the documents "CML, PAN Card, Passport, Board Resolution"
    And the "CML" tile should say "No checks"
    And the Document Checks page should say "4 documents · 0 checks · 4 without checks"

  # E2 — nothing on the lists yet
  Scenario: With no KYC documents the page says where to add them
    Given the entity requires no KYC documents
    When I open the Document Checks settings
    Then the Document Checks page should say "Add the documents you collect in Settings → KYC documents. They'll appear here."

  # H1 — suggested checks for every document, added in one go
  Scenario: Adding the suggested checks for all documents at once
    When I open the Document Checks settings
    Then the Document Checks page should say "Suggested for your documents: 12 checks across 3 documents"
    When I review the suggested checks
    Then the suggested checks should be:
      | document | action          | field               | look for                    |
      | CML      | Fill in         | DP ID               | DP ID                       |
      | CML      | Fill in         | Client ID           | Client ID                   |
      | CML      | Fill in         | Address             | Address                     |
      | CML      | Fill in         | Bank account number | Bank account number         |
      | CML      | Fill in         | IFSC code           | IFSC code                   |
      | CML      | Compare         | PAN                 | PAN                         |
      | CML      | Compare         | Full name           | First holder name           |
      | CML      | Yes-no question |                     | Is it signed by the holder? |
      | PAN Card | Compare         | PAN                 | PAN                         |
      | PAN Card | Compare         | Full name           | Name                        |
      | Passport | Compare         | Full name           | Name                        |
      | Passport | Fill in         | Expiry date         | Expiry date                 |
    And the suggested checks should say "Not available on your KYC form: CML · Email, CML · Mobile"
    And the suggested checks should say "No suggestions for Board Resolution — add your own from their tiles."
    When I untick the suggested "Expiry date" on "Passport"
    And I click "Add 11 checks"
    Then the Document Checks page should say "Added 11 checks"
    And the entity should have 8 document checks on "CML"
    And the entity should have 2 document checks on "PAN Card"
    And the entity should have 1 document checks on "Passport"
    And the "CML" tile should say "8 checks"
    And the "CML" tile should say "Fills DP ID, Client ID, Address +2"
    And the "CML" tile should say "Compares PAN, Full name"
    And the "CML" tile should say "Asks: Is it signed by the holder?"

  # H1 (one document) — an empty tile previews its suggestions and adds just those
  Scenario: Adding one document's suggestions from its tile
    When I open the Document Checks settings
    Then the "Passport" tile should say "Compares Full name"
    And the "Passport" tile should say "Fills Expiry date"
    When I click "Add 2 suggested" on the "Passport" tile
    Then the Document Checks page should say "Added 2 checks"
    And the entity should have 2 document checks on "Passport"
    And the entity should have 0 document checks on "CML"
    And the "Passport" tile should say "2 checks"

  # E4 — what is already set up isn't suggested again
  Scenario: Checks already set up aren't suggested again
    Given the entity has the sample document checks
    When I open the Document Checks settings
    And I review the suggested checks
    Then the suggested checks should not list "CML"
    And the suggested checks should not list "Passport"
    And the suggested checks should be:
      | document | action  | field | look for |
      | PAN Card | Compare | PAN   | PAN      |

  # H2 — add a check by kind, pick the field, "Look for" fills itself, save the document
  Scenario: Adding a check fills Look for from the field
    When I open the Document Checks settings
    And I edit the "Board Resolution" document
    Then the "Board Resolution" document should say "No checks yet. Add one below"
    When I add a "Compare" check to the "Board Resolution" document on the field "Full name"
    Then the "Board Resolution" document should have the checks:
      | action  | field     | look for  |
      | Compare | Full name | Full name |
    When I change the last check's look for on the "Board Resolution" document to "Company name"
    And I save the "Board Resolution" document
    Then the "Board Resolution" tile should say "1 check"
    And the "Board Resolution" tile should say "Compares Full name"
    And the entity should have the document checks on "Board Resolution":
      | action  | field     | look for     |
      | compare | full_name | Company name |

  # An added check that was never filled in doesn't block the save
  Scenario: An untouched new check is ignored when saving
    Given the entity has the document checks:
      | document | action  | field | look for |
      | CML      | compare | PAN   | PAN      |
    When I open the Document Checks settings
    And I edit the "CML" document
    And I add a "Fill in" check to the "CML" document
    And I add a "Fill in" check to the "CML" document on the field "DP ID"
    And I save the "CML" document
    Then the entity should have 2 document checks on "CML"

  # E3 — a field once per document: greyed out in the dropdown, and refused if posted anyway
  Scenario: The same field twice on a document is refused
    Given the entity has the document checks:
      | document | action  | field | look for |
      | CML      | compare | PAN   | PAN      |
    When I open the Document Checks settings
    And I edit the "CML" document
    And I add a "Fill in" check to the "CML" document
    Then the new check on the "CML" document should show "PAN (already used on this document)" greyed out
    When a request saves the "CML" document with a second check on the field "PAN"
    Then the save should be refused with "Already used on this document"
    And the entity should have 1 document checks on "CML"

  # E16 — the KYC form lost a field a check uses: flagged on the page and in the next check
  Scenario: A check whose field was removed is flagged
    Given the entity has the document checks:
      | document | action  | field | look for |
      | CML      | fill_in | dp    | DP ID    |
    And the KYC form's custom field "dp" is deleted
    When I open the Document Checks settings
    Then the Document Checks page should say "1 check uses a field that no longer exists"
    When I edit the "CML" document
    Then the "CML" document should say "This field no longer exists — pick another"
    Given there is an individual KYC for the investor "full_name=Asha Rao"
    And the KYC has the documents "CML"
    And the AI reads:
      | document | look for | value    |
      | CML      | DP ID    | IN303622 |
    When documents are checked for the KYC
    Then the KYC's document check results should include:
      | document | item  | outcome       |
      | CML      | DP ID | field_missing |

  # X4 — a field that isn't on the list can't be saved, even by a crafted request
  Scenario: A field outside the allowed list is refused
    When a request saves a Fill in check on "CML" for the field "verified"
    Then the save should be refused with "Pick a KYC field"
    And the entity should have 0 document checks on "CML"

  # Editing one part of a saved check keeps the rest (the swap-safe save writes both parked columns back)
  Scenario: Editing only a check's look for keeps its field
    Given the entity has the document checks:
      | document | action  | field     | look for          |
      | CML      | compare | PAN       | PAN               |
      | CML      | compare | full_name | First holder name |
    When a request saves the "CML" document with the look for of "PAN" changed to "Permanent account number"
    Then the entity should have the document checks on "CML":
      | action  | field     | look for                 |
      | compare | PAN       | Permanent account number |
      | compare | full_name | First holder name        |
