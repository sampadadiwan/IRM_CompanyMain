@doc_checks_fake_ai
Feature: Document Checks — checking a KYC's documents
  The AI reads values off each document on the KYC's own list; CapHive fills in fields, compares them
  with the KYC and answers yes-no questions. Every item ends OK or needing attention, with a reason, and a
  problem with one document never stops the others. The AI is a fake here (DocChecks::FakeReader).
  Worked examples H3, H13, E6–E12, E14, E15, E17, E18, X1, X2, X3, X5 in
  openspec/changes/document-checks/design.md#worked-examples

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;enable_kycs=true"
    And the user has role "company_admin"
    And there is an existing investor "" with "1" users
    And the entity requires the individual KYC documents "CML, PAN Card, Passport"
    And the entity requires the non-individual KYC documents "PAN Card, Board Resolution"
    And the KYC form has the custom fields "dp=DP ID; client=Client ID"
    And the entity has the sample document checks
    And the AI reads the sample documents
    And in-app alerts are captured

  # H3 — everything reads and matches: fields filled in, one AI call per document
  Scenario: Checking a KYC whose documents all match
    Given there is an individual KYC for the investor "full_name=Asha Rao;PAN=ABCPK1234F;address=D109, MW;ifsc_code=;bank_account_number=;expiry_date="
    And the KYC has the documents "CML, PAN Card, Passport"
    When documents are checked for the KYC
    Then the last document check should be "done" with 11 OK and 0 needing attention
    And the AI should have been called 3 times
    And the KYC's document check results should include:
      | document | item                        | outcome | note    | document value | KYC value  |
      | CML      | DP ID                       | ok      | filled  | IN303622       |            |
      | CML      | Address                     | ok      | kept    | D109, MW       | D109, MW   |
      | CML      | PAN                         | ok      | matches | ABCPK1234F     | ABCPK1234F |
      | CML      | Is it signed by the holder? | ok      | yes     |                |            |
      | Passport | Expiry date                 | ok      | filled  | 2031-05-14     |            |
    And the KYC's "dp" should be "IN303622"
    And the KYC's "client" should be "86478611"
    And the KYC's "ifsc_code" should be "HDFC0000123"
    And the KYC's "expiry_date" should be "2031-05-14"
    And the KYC's documents should be all valid
    And the user gets a "success" alert "Documents checked for Asha Rao — all OK"

  # H13 — the AI rules tool still answers a question about a document, through the new reader
  Scenario: The AI rules tool asks a question about a document
    Given there is an individual KYC for the investor "full_name=Asha Rao"
    And the KYC has the documents "CML"
    And the AI reads:
      | document | look for            | value |
      | *        | Is the PAN visible? | yes   |
    When an AI rule asks "Is the PAN visible?" about the KYC's "CML" document
    Then the AI rule should get the answer "yes"

  # E6 — a company KYC only has the documents on the non-individual list
  Scenario: A company KYC ignores documents only individuals give
    Given there is a non-individual KYC for the investor "full_name=Rao Holdings;PAN=AAACR1234K"
    And the KYC has the documents "PAN Card, CML"
    And the AI reads:
      | document | look for | value        |
      | PAN Card | Name     | Rao Holdings |
    When documents are checked for the KYC
    Then the KYC's document check results should only cover "PAN Card"
    And the AI should have been called 1 times

  # E7 — the uploaded name carries the form's "Upload " prefix and different case
  Scenario: A document is found despite an upload prefix and different case
    Given there is an individual KYC for the investor "full_name=Asha Rao;PAN=ABCPK1234F"
    And the KYC has the documents "CML, Upload pan card, Passport"
    When documents are checked for the KYC
    Then the KYC's document check results should include:
      | document | item | outcome | note    |
      | PAN Card | Name | ok      | matches |

  # E8, E9 — case, spaces, punctuation and (for names) word order are ignored
  Scenario: Comparing ignores case, punctuation and the order of names
    Given there is an individual KYC for the investor "full_name=Asha Rao;PAN=ABCPK1234F"
    And the KYC has the documents "CML, PAN Card, Passport"
    And the AI reads:
      | document | look for | value        |
      | CML      | PAN      | abcpk 1234-f |
      | Passport | Name     | RAO ASHA     |
    When documents are checked for the KYC
    Then the KYC's document check results should include:
      | document | item | outcome | note    |
      | CML      | PAN  | ok      | matches |
      | Passport | Name | ok      | matches |

  # E10 — a value already on the KYC is kept (Replace existing values is off)
  Scenario: Fill in keeps a value the KYC already has
    Given there is an individual KYC for the investor "full_name=Asha Rao;PAN=ABCPK1234F;properties=client:86478612"
    And the KYC has the documents "CML, PAN Card, Passport"
    When documents are checked for the KYC
    Then the KYC's document check results should include:
      | document | item      | outcome | note | document value | KYC value |
      | CML      | Client ID | ok      | kept | 86478611       | 86478612  |
    And the KYC's "client" should be "86478612"

  # E11 — the AI can't find a value: it needs attention
  Scenario: A value that isn't on the document needs attention
    Given there is an individual KYC for the investor "full_name=Asha Rao;PAN=ABCPK1234F"
    And the KYC has the documents "CML, PAN Card, Passport"
    And the AI finds nothing for "DP ID" on "CML"
    When documents are checked for the KYC
    Then the KYC's document check results should include:
      | document | item  | outcome   |
      | CML      | DP ID | not_found |
    And the KYC's "dp" should be empty
    And the last document check should be "done" with 10 OK and 1 needing attention
    And the user gets a "warning" alert "Documents checked for Asha Rao — 1 needs attention"

  # E12 — a document on the KYC's list that isn't uploaded keeps the KYC from being valid
  Scenario: A document that isn't uploaded needs attention
    Given there is an individual KYC for the investor "full_name=Asha Rao;PAN=ABCPK1234F"
    And the KYC has the documents "CML, PAN Card"
    When documents are checked for the KYC
    Then the KYC's document check results should include:
      | document | item        | outcome      |
      | Passport | Name        | not_uploaded |
      | Passport | Expiry date | not_uploaded |
    And the KYC's documents should not be all valid
    And the AI should have been called 2 times

  # E14 — one check at a time per KYC
  Scenario: A second check while one is running is refused
    Given there is an individual KYC for the investor "full_name=Asha Rao"
    And a document check is already running for the KYC
    When documents are checked for the KYC
    Then the document check should be refused with "Documents are already being checked for Asha Rao"

  # E15 — a document taken off the KYC's list disappears from its results
  Scenario: A document removed from the list is not checked again
    Given there is an individual KYC for the investor "full_name=Asha Rao;PAN=ABCPK1234F"
    And the KYC has the documents "CML, PAN Card, Passport"
    And documents are checked for the KYC
    And the entity no longer requires "Passport" from individuals
    When documents are checked for the KYC
    Then the KYC's document check results should have no "Passport" items
    And the KYC's document check results should only cover "CML, PAN Card"

  # E17 — a yes-no question answered differently from what's expected
  Scenario: A yes-no question answered No needs attention
    Given there is an individual KYC for the investor "full_name=Asha Rao;PAN=ABCPK1234F"
    And the KYC has the documents "CML, PAN Card, Passport"
    And the AI reads:
      | document | look for                    | value |
      | CML      | Is it signed by the holder? | no    |
    When documents are checked for the KYC
    Then the KYC's document check results should include:
      | document | item                        | outcome           | document value |
      | CML      | Is it signed by the holder? | unexpected_answer | No             |

  # E18 — a different PAN: both values are kept for the user to compare
  Scenario: A value that doesn't match the KYC needs attention
    Given there is an individual KYC for the investor "full_name=Asha Rao;PAN=ABCPK1243F"
    And the KYC has the documents "CML, PAN Card, Passport"
    When documents are checked for the KYC
    Then the KYC's document check results should include:
      | document | item | outcome  | document value | KYC value  |
      | CML      | PAN  | mismatch | ABCPK1234F     | ABCPK1243F |
    And the KYC's "PAN" should be "ABCPK1243F"

  # X1 — a Word file can't be read; the other documents are still checked
  Scenario: An unreadable file needs attention and the others are still read
    Given there is an individual KYC for the investor "full_name=Asha Rao;PAN=ABCPK1243F"
    And the KYC has the documents "CML, Passport"
    And the KYC's "PAN Card" document is a Word file
    When documents are checked for the KYC
    Then the KYC's document check results should include:
      | document | item | outcome         |
      | PAN Card | Name | unreadable_file |
      | CML      | PAN  | mismatch        |
      | Passport | Name | ok              |
    And the AI should have been called 2 times
    And the last document check should be "done" with 9 OK and 2 needing attention
    And the user gets a "warning" alert "Documents checked for Asha Rao — 2 need attention"

  # X2 — the AI's answer for one document isn't JSON
  Scenario: An AI answer that can't be read needs attention for that document only
    Given there is an individual KYC for the investor "full_name=Asha Rao;PAN=ABCPK1234F"
    And the KYC has the documents "CML, PAN Card, Passport"
    And the AI gives an unreadable answer for "CML"
    When documents are checked for the KYC
    Then the KYC's document check results should include:
      | document | item  | outcome          |
      | CML      | DP ID | unreadable_reply |
      | PAN Card | Name  | ok               |

  # X3 — the AI service is down: the check couldn't run, nothing changed, earlier results stay
  Scenario: When the AI service is down nothing changes
    Given there is an individual KYC for the investor "full_name=Asha Rao;PAN=ABCPK1234F"
    And the KYC has the documents "CML, PAN Card, Passport"
    And documents are checked for the KYC
    And the KYC's "dp" should be "IN303622"
    And the AI service is down
    When documents are checked for the KYC
    Then the last document check couldn't run with "the AI service is unavailable"
    And the KYC's document check results should include:
      | document | item  | outcome |
      | CML      | DP ID | ok      |
    And the KYC's documents should be all valid
    And the user gets a "danger" alert "Couldn't check documents for Asha Rao — the AI service is unavailable. Try again later."

  # X5 — text in a tip is sent as text; nothing in it is run against the KYC
  Scenario: A tip that looks like a placeholder is harmless
    Given there is an individual KYC for the investor "full_name=Asha Rao;PAN=ABCPK1234F"
    And the KYC has the documents "CML, PAN Card, Passport"
    And the check "DP ID" on "CML" has the tip "$destroy the record"
    When documents are checked for the KYC
    Then the KYC should still exist
    And the AI should have been sent the tip "$destroy the record"
    And the KYC's document check results should include:
      | document | item  | outcome | note   |
      | CML      | DP ID | ok      | filled |

  # Row 11 of the design's walkthrough — a Mark as OK carries over when the item reads the same again
  # (code review: rows with and without a carried-over resolution must insert together)
  Scenario: Checking again keeps a Mark as OK on an unchanged item
    Given there is an individual KYC for the investor "full_name=Asha Rao;PAN=ABCPK1243F"
    And the KYC has the documents "CML, PAN Card, Passport"
    And documents are checked for the KYC
    And the "PAN" item is marked OK with "PAN on file is the newer one"
    When documents are checked for the KYC
    Then the last document check should be "done" with 11 OK and 0 needing attention
    And the "PAN" item should still be marked OK with "PAN on file is the newer one"

  # Card ④ Expiry — a run left running by a dead worker doesn't block the next check
  Scenario: A check left running long ago doesn't block a new one
    Given there is an individual KYC for the investor "full_name=Asha Rao;PAN=ABCPK1234F"
    And the KYC has the documents "CML, PAN Card, Passport"
    And a document check for the KYC was left running an hour ago
    When documents are checked for the KYC
    Then the old document check should be expired
    And the last document check should be "done" with 11 OK and 0 needing attention

  # Fill in only fills an empty field — re-decided at the end, so a value saved meanwhile is kept
  Scenario: A value saved while the documents are being read is kept
    Given there is an individual KYC for the investor "full_name=Asha Rao;PAN=ABCPK1234F"
    And the KYC has the documents "CML, PAN Card, Passport"
    And someone saves the KYC's "client" as "99999999" while the documents are being read
    When documents are checked for the KYC
    Then the KYC's "client" should be "99999999"
    And the KYC's document check results should include:
      | document | item      | outcome | note | KYC value |
      | CML      | Client ID | ok      | kept | 99999999  |

  # A failure after the results are stored (here the journey hook) keeps them as the KYC's current results
  Scenario: A failure after the check is stored keeps the results
    Given there is an individual KYC for the investor "full_name=Asha Rao;PAN=ABCPK1234F"
    And the KYC has the documents "CML, PAN Card, Passport"
    When documents are checked for the KYC and the journey hook fails afterwards
    Then the last document check should still be current
