@doc_checks @doc_checks_fake_ai
Feature: Document Checks — the KYC journey's "Validate documents"
  The journey task passes by itself when the KYC's documents have been checked and nothing needs attention;
  otherwise it says what's left. A replaced document moves it back. Earlier Doc Questions answers stay
  visible on the KYC.
  Worked examples H7, E13, E20, E21, E22, E23 in openspec/changes/document-checks/design.md#worked-examples

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;enable_kycs=true;enable_doc_llm_validation=true"
    And the user has role "company_admin"
    And there is an existing investor "" with "1" users
    And the entity's investor KYC journeys are removed
    And the entity's investor KYC journeys are seeded
    And the entity requires the individual KYC documents "CML, PAN Card, Passport"
    And AML is enabled for the entity
    And the KYC form has the custom fields "dp=DP ID; client=Client ID"
    And the AI reads the sample documents

  # H7 — checked with nothing needing attention: the task passes with no click
  Scenario: Checked documents validate the task by themselves
    Given the entity has the sample document checks
    And there is an individual KYC for the investor "full_name=Asha Rao;PAN=ABCPK1234F;address=D109, MW"
    And the KYC's form link was sent
    And the KYC is submitted
    And the KYC has the documents "CML, PAN Card, Passport"
    When documents are checked for the KYC
    Then the KYC's journey should show:
      | task               | status  | message           |
      | Validate documents | passed  | Validated by AI   |
      | Run AML screening  | current | No AML report yet |

  # E13 — replacing a document after the task passed moves it back, and the document shows as changed
  Scenario: A replaced document moves the task back
    Given the entity has the sample document checks
    And there is an individual KYC for the investor "full_name=Asha Rao;PAN=ABCPK1234F;address=D109, MW"
    And the KYC's form link was sent
    And the KYC is submitted
    And the KYC has the documents "CML, PAN Card, Passport"
    And documents are checked for the KYC
    And the KYC's journey current task should be "Run AML screening"
    When the KYC's "CML" document is replaced
    Then the KYC's journey should have moved back to "Validate documents" with "Documents changed after validation"
    And the KYC's documents should not be all valid
    When I open the KYC's Document checks tab
    Then the Document checks tab should show the documents:
      | document | status                            |
      | CML      | This document changed after the check |
      | PAN Card | All OK                                |

  # E21 — checks are set up but the documents haven't been checked
  Scenario: Not checked yet
    Given the entity has the sample document checks
    And there is an individual KYC for the investor "full_name=Asha Rao"
    And the KYC's form link was sent
    And the KYC is submitted
    And the KYC has the documents "CML, PAN Card, Passport"
    When the KYC's journey is evaluated
    Then the KYC's journey should show:
      | task               | status  | message                                                      |
      | Validate documents | current | Documents not checked yet — check documents or mark reviewed |

  # E22 — two items need attention; Mark reviewed still passes the task
  Scenario: Items needing attention keep the task open until reviewed
    Given the entity has the sample document checks
    And there is an individual KYC for the investor "full_name=Asha Rao;PAN=ABCPK1243F;address=D109, MW"
    And the KYC's form link was sent
    And the KYC is submitted
    And the KYC has the documents "CML, PAN Card, Passport"
    And the AI reads:
      | document | look for | value    |
      | PAN Card | Name     | R. Kumar |
    When documents are checked for the KYC
    Then the KYC's document check results should include:
      | document | item  | outcome  |
      | CML      | PAN   | mismatch |
      | PAN Card | Name  | mismatch |
      | CML      | DP ID | ok       |
    And the last document check should be "done" with 9 OK and 2 needing attention
    And the KYC's journey should show:
      | task               | status  | message                                                          |
      | Validate documents | current | 2 document items need attention — resolve them or mark reviewed |
    When I mark "Validate documents" reviewed on the KYC
    Then the KYC's journey current task should be "Run AML screening"

  # E23 — no checks for this KYC's documents: a person checks them
  Scenario: Without document checks the documents are checked by hand
    Given there is an individual KYC for the investor "full_name=Asha Rao"
    And the KYC's form link was sent
    And the KYC is submitted
    And the KYC has the documents "CML, PAN Card, Passport"
    When the KYC's journey is evaluated
    Then the KYC's journey should show:
      | task               | status  | message                               |
      | Validate documents | current | Check the documents and mark reviewed |

  # E20 — answers stored by Doc Questions stay visible, read-only
  Scenario: Earlier AI answers are still shown
    Given the entity has the sample document checks
    And there is an individual KYC for the investor "full_name=Asha Rao"
    And the KYC has earlier AI answers for "CML"
    When I open the KYC's Document checks tab
    Then I should see "Earlier AI answers (before Document Checks)"
