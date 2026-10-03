@doc_checks_fake_ai
Feature: Document Checks — the KYC tab, resolving items and the attention list
  Each document of the KYC's own list shows ✓ All OK or ⚠ n need attention, and an item is settled where it
  is shown: Use document value, or Mark as OK with a reason (and Undo). Trial runs change nothing, and the
  attention list gathers every item across the entity's KYCs.
  Worked examples H4, H5, H6, H8, H9, H12, E19, X6, X7, X8, X10 in
  openspec/changes/document-checks/design.md#worked-examples

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;enable_kycs=true;enable_doc_llm_validation=true"
    And the user has role "company_admin"
    And there is an existing investor "" with "1" users
    And the entity requires the individual KYC documents "CML, PAN Card, Passport"
    And the KYC form has the custom fields "dp=DP ID; client=Client ID"
    And the entity has the sample document checks
    And the AI reads the sample documents
    And in-app alerts are captured

  # H4 — Try on a KYC shows what would happen and changes nothing
  Scenario: A trial run changes nothing on the KYC
    Given there is an individual KYC for the investor "full_name=Asha Rao;PAN=ABCPK1234F"
    And the KYC has the documents "CML, PAN Card, Passport"
    When I try the checks on the KYC
    Then the trial should say "Trial run — nothing on this KYC was changed"
    And the trial should say "DP ID — filled in: IN303622"
    And the KYC's "dp" should be empty
    And the KYC should have no current document check

  # H5 — a mismatch fixed in one click
  Scenario: Using the document's value fixes a mismatch
    Given there is an individual KYC for the investor "full_name=Asha Rao;PAN=ABCPK1243F"
    And the KYC has the documents "CML, PAN Card, Passport"
    And documents are checked for the KYC
    When I open the KYC's Document checks tab
    Then the Document checks tab title should be "Document checks (1)"
    And the "PAN" item should say "PAN — doesn't match"
    And the "PAN" item should show "Document: ABCPK1234F · KYC: ABCPK1243F"
    When I use the document value for the "PAN" item, confirming "Change PAN from ABCPK1243F to ABCPK1234F?"
    Then the "PAN" item should say "PAN — updated from the document by"
    And the KYC's "PAN" should be "ABCPK1234F"
    And the KYC's documents should be all valid

  # H6 — a legitimate difference marked OK with a reason; E19 — and undone
  Scenario: Marking an item OK, then undoing it
    Given there is an individual KYC for the investor "full_name=Asha Rao;PAN=ABCPK1234F"
    And the KYC has the documents "CML, PAN Card, Passport"
    And the AI reads:
      | document | look for          | value  |
      | CML      | First holder name | A. RAO |
    And documents are checked for the KYC
    When I open the KYC's Document checks tab
    Then the Document checks tab should show the documents:
      | document | status              |
      | CML      | 1 needs attention   |
      | PAN Card | All OK              |
    When I mark the "First holder name" item OK with "Initial matches passport"
    Then the "First holder name" item should say "Marked OK by"
    And the "First holder name" item should say "Initial matches passport"
    And the KYC's documents should be all valid
    When I undo the "First holder name" item
    Then the "First holder name" item should say "First holder name — doesn't match"
    And the KYC's documents should not be all valid

  # X8 — a reason is required
  Scenario: Marking an item OK without a reason is refused
    Given there is an individual KYC for the investor "full_name=Asha Rao;PAN=ABCPK1243F"
    And the KYC has the documents "CML, PAN Card, Passport"
    And documents are checked for the KYC
    When I open the KYC's Document checks tab
    And I mark the "PAN" item OK with ""
    Then the "PAN" item should show "Say why this is OK"
    And the KYC's documents should not be all valid

  # H12 — progress, document by document
  Scenario: Progress is shown document by document
    Given there is an individual KYC for the investor "full_name=Asha Rao;PAN=ABCPK1234F"
    And the KYC has the documents "CML, PAN Card, Passport"
    When documents are checked for the KYC
    Then the documents should have been checked in the order "CML, PAN Card, Passport"

  # H8 — bulk Check documents: every KYC but the verified one
  Scenario: Checking documents in bulk skips verified KYCs
    Given there is an individual KYC for the investor "full_name=Asha Rao;PAN=ABCPK1234F"
    And the KYC has the documents "CML, PAN Card, Passport"
    And there is an individual KYC for the investor "full_name=Ravi Mehta;PAN=ABCPK1234F"
    And there is a verified individual KYC for the investor "full_name=Kiran Iyer"
    When documents are checked in bulk for the KYCs "Asha Rao, Ravi Mehta, Kiran Iyer"
    Then the KYC "Asha Rao" should have been checked
    And the KYC "Ravi Mehta" should have been checked
    And the KYC "Kiran Iyer" should not have been checked

  # H9 — the attention list, filtered by reason, and Check again for a selected KYC
  Scenario: Working through the attention list
    Given there is an individual KYC for the investor "full_name=Asha Rao;PAN=ABCPK1243F"
    And the KYC "Asha Rao" has the documents "CML, PAN Card, Passport" and has been checked
    And there is an individual KYC for the investor "full_name=Ravi Mehta;PAN=ABCPK1234F"
    And the KYC "Ravi Mehta" has the documents "" and has been checked
    When I open Documents needing attention
    Then the attention list should show the KYCs "Ravi Mehta, Asha Rao"
    When I filter the attention list by reason "Doesn't match"
    Then the attention list should show the KYCs "Asha Rao"
    When I tick "Asha Rao" and click Check again
    Then I should see "Checking documents for 1 KYC"

  # X10 — a fund user who can view but not edit the KYC sees results, can't change them
  Scenario: A view-only user sees the results but can't resolve them
    Given there is an individual KYC for the investor "full_name=Asha Rao;PAN=ABCPK1243F"
    And the KYC has the documents "CML, PAN Card, Passport"
    And documents are checked for the KYC
    And I can view but not edit the KYC
    When I open the KYC's Document checks tab
    Then the "PAN" item should say "PAN — doesn't match"
    And the "PAN" item should not offer to resolve it
    And I should not be able to check documents

  # X6, X7 — another entity's user and the investor never reach these results
  Scenario: Other entities and investors can't see the results
    Given there is an individual KYC for the investor "full_name=Asha Rao;PAN=ABCPK1243F"
    And the KYC has the documents "CML, PAN Card, Passport"
    And documents are checked for the KYC
    And a fund admin "Olu" of another entity
    Then "Olu" can't see or resolve this entity's Document Checks
    And the investor user can't see the KYC's Document checks
