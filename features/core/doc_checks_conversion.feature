Feature: Document Checks — converting legacy Doc Questions
  Support converts each fund's Doc Questions into Document Checks. A dry run reports what converts and
  what doesn't; nothing is guessed, and running it again changes nothing.
  Worked examples H10, H11, X9 in openspec/changes/document-checks/design.md#worked-examples

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;enable_kycs=true;enable_doc_llm_validation=true"
    And the entity requires the individual KYC documents "CML, PAN"
    And the KYC form has the custom fields "dp=DP ID; client=Client ID; mobil_contact_no=Mobile"
    And the entity has the Doc Questions:
      | document     | type       | question                                                     | response hint                 |
      | CML          | Extraction | Extract the DP ID. DP ID is alpha numeric 8 charterers field | Extract into field dp         |
      | CML          | Validation | Extract Client ID                                            | extract to field client       |
      | CML          | Extraction | First Holders Name                                           | extract to field full_name    |
      | CML          | Extraction | Address                                                      |                               |
      | CML          | Extraction | Extract the phone number                                     | Extract to field mobil_contact |
      | CML          | Extraction | Extract bank account no                                      | Extract to field bank_account_number |
      | CML          | Extraction | Bank Account Number                                          |                               |
      | CML          | Validation | Is the document signed?                                      |                               |
      | Incorporation | Extraction | Extract Name                                                | extract to field full_name    |

  # H10 — the dry run reports everything and writes nothing
  Scenario: The dry run reports what converts and what doesn't
    When the Doc Questions conversion runs for the entity
    Then the conversion report should convert:
      | question                                                     | action   | field               |
      | Extract the DP ID. DP ID is alpha numeric 8 charterers field | fill_in  | dp                  |
      | Extract Client ID                                            | fill_in  | client              |
      | First Holders Name                                           | fill_in  | full_name           |
      | Address                                                      | fill_in  | address             |
      | Extract bank account no                                      | fill_in  | bank_account_number |
      | Is the document signed?                                      | question |                     |
    And the conversion report should not convert:
      | question                 | reason                                                  |
      | Extract the phone number | Field mobil_contact not found                           |
      | Bank Account Number      | Field bank_account_number is already used on this document |
      | Extract Name             | Document "Incorporation" is not on the KYC document lists |
    And the entity should have 0 document checks

  # H11 — executing twice converts once
  Scenario: Converting twice creates the checks once
    When the Doc Questions conversion runs for the entity with execute
    And the Doc Questions conversion runs for the entity with execute
    Then the entity should have 6 document checks
    And 3 Doc Questions should be logged as not converted

  # X9 — a field the hint names that doesn't exist is reported, never guessed
  Scenario: A field that doesn't exist is reported
    When the Doc Questions conversion runs for the entity
    Then the conversion report should not convert:
      | question                 | reason                                                  |
      | Extract the phone number | Field mobil_contact not found                           |
      | Bank Account Number      | Field bank_account_number is already used on this document |
      | Extract Name             | Document "Incorporation" is not on the KYC document lists |

  # X9 — a "$placeholder" question asked the AI to compare with the KYC: it becomes a person's Compare check
  Scenario: A question with a placeholder is reported, not converted
    Given the entity has the Doc Questions:
      | document | type       | question                            | response hint |
      | PAN      | Validation | Is $full_name present in the document |             |
    When the Doc Questions conversion runs for the entity
    Then the conversion report should not convert:
      | question                              | reason                                                     |
      | Extract the phone number              | Field mobil_contact not found                              |
      | Bank Account Number                   | Field bank_account_number is already used on this document |
      | Extract Name                          | Document "Incorporation" is not on the KYC document lists  |
      | Is $full_name present in the document | Uses a $placeholder — set it up as a Compare check instead |
