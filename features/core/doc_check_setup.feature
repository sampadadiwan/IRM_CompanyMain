@doc_checks_fake_ai
Feature: Document Checks — the settings page
  Every document on the entity's KYC lists is a card. A check is picked, not typed: what to do, then the
  KYC field, and "Look for" fills itself. Presets add only what they can map, and a field removed from the
  KYC form is flagged, never silently dropped.
  Worked examples H1, H2, E1–E5, E16, X4 in openspec/changes/document-checks/design.md#worked-examples

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;enable_kycs=true;enable_doc_llm_validation=true"
    And the user has role "company_admin"
    And there is an existing investor "" with "1" users
    And the entity requires the individual KYC documents "CML, PAN Card, Passport"
    And the entity requires the non-individual KYC documents "PAN Card, Board Resolution"
    And the KYC form has the custom fields "dp=DP ID; client=Client ID"

  # E1 — a card per document on either list, PAN Card once
  Scenario: Every KYC document is a card
    When I open the Document Checks settings
    Then I should see the document cards "CML, PAN Card, Passport, Board Resolution"
    And the "CML" card should say "No checks yet"

  # E2 — nothing on the lists yet
  Scenario: With no KYC documents the page says where to add them
    Given the entity requires no KYC documents
    When I open the Document Checks settings
    Then the Document Checks page should say "Add the documents you collect in Settings → KYC documents. They'll appear here."

  # H1 — the CML preset adds what it can map and says what it couldn't
  Scenario: The CML preset adds the standard checks it can map
    When I open the Document Checks settings
    And I click "Use CML preset" on the "CML" card
    Then the "CML" card should have the checks:
      | action          | field               | look for                    |
      | Fill in         | DP ID               | DP ID                       |
      | Fill in         | Client ID           | Client ID                   |
      | Fill in         | Address             | Address                     |
      | Fill in         | Bank account number | Bank account number         |
      | Fill in         | IFSC code           | IFSC code                   |
      | Compare         | PAN                 | PAN                         |
      | Compare         | Full name           | First holder name           |
      | Yes-no question |                     | Is it signed by the holder? |
    And the "CML" card should say "Not added: Email, Mobile — your KYC form has no matching field. Add a custom field to the KYC form, then use the preset again."
    And the "CML" card should say "Unsaved changes"
    When I save the "CML" card
    Then the "CML" card should say "8 checks"
    And the entity should have 8 document checks on "CML"

  # E4 — a second preset adds nothing already there
  Scenario: Using a preset again adds no duplicates
    Given the entity has the sample document checks
    When I open the Document Checks settings
    And I click "Use CML preset" on the "CML" card
    Then the "CML" card should say "Not added: Email, Mobile"
    And the "CML" card should have 8 checks
    And the entity should have 8 document checks on "CML"

  # E5 — only CML, PAN, Aadhaar and Passport have presets
  Scenario: A document without a preset offers none
    When I open the Document Checks settings
    Then the "Board Resolution" card should not offer a preset

  # H2 — pick the field, "Look for" fills itself, save the card
  Scenario: Adding a check fills Look for from the field
    When I open the Document Checks settings
    And I add a check on the "PAN Card" card to "Compare" the field "Full name"
    Then the "PAN Card" card should have the checks:
      | action  | field     | look for  |
      | Compare | Full name | Full name |
    When I change the last check's look for on the "PAN Card" card to "Name"
    And I save the "PAN Card" card
    Then the "PAN Card" card should say "1 check"
    And the entity should have the document checks on "PAN Card":
      | action  | field     | look for |
      | compare | full_name | Name     |

  # E3 — a field once per card: greyed out in the dropdown, and refused if posted anyway
  Scenario: The same field twice on a card is refused
    Given the entity has the document checks:
      | document | action  | field | look for |
      | CML      | compare | PAN   | PAN      |
    When I open the Document Checks settings
    And I click "Add a check" on the "CML" card
    Then the new check on the "CML" card should show "PAN (already used on this card)" greyed out
    When a request saves the "CML" card with a second check on the field "PAN"
    Then the save should be refused with "Already used on this card"
    And the entity should have 1 document checks on "CML"

  # E16 — the KYC form lost a field a check uses: flagged on the page and in the next check
  Scenario: A check whose field was removed is flagged
    Given the entity has the document checks:
      | document | action  | field | look for |
      | CML      | fill_in | dp    | DP ID    |
    And the KYC form's custom field "dp" is deleted
    When I open the Document Checks settings
    Then the Document Checks page should say "1 check uses a field that no longer exists"
    And the "CML" card should say "This field no longer exists — pick another"
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

  # Editing one part of a saved check keeps the rest (code review: the swap-safe save must write both
  # parked columns back)
  Scenario: Editing only a check's look for keeps its field
    Given the entity has the document checks:
      | document | action  | field     | look for          |
      | CML      | compare | PAN       | PAN               |
      | CML      | compare | full_name | First holder name |
    When a request saves the "CML" card with the look for of "PAN" changed to "Permanent account number"
    Then the entity should have the document checks on "CML":
      | action  | field     | look for                 |
      | compare | PAN       | Permanent account number |
      | compare | full_name | First holder name        |
