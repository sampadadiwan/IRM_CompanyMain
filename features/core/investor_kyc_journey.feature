Feature: Investor KYC journey
  Every new KYC in a set-up entity gets the "Investor KYC" journey. Each task's status is worked out
  from the KYC's own data — status, documents, AI validation answers, AML result — so the step bar
  can't drift from reality. Verifying closes the journey: any task not done by then shows
  "Verified without this step".
  Worked examples H2, H5, H7, H10, E1, E2, E4–E14, E18, E21, E23, X6 in
  openspec/changes/investor-kyc-journey/design.md#worked-examples

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;enable_kycs=true"
    And the user has role "company_admin"
    And there is an existing investor "" with "1" users
    And the entity's investor KYC journeys are removed
    And the entity's investor KYC journeys are seeded
    And the entity requires the individual KYC documents "PAN Card, Address Proof, Photo"
    And AML is enabled for the entity

  # H2 — a new KYC gets the journey, waiting on the form
  Scenario: A new KYC gets the journey and waits for the form to be sent
    Given there is an individual KYC for the investor
    When the KYC's journey is evaluated
    Then the KYC has the "Investor KYC" journey
    And the KYC's journey current task should be "Send KYC form"
    And the KYC's journey should show:
      | task                | status  | message                                                                  |
      | Send KYC form       | current | The KYC form has not been sent — send it, or fill it in and tick complete |
      | Compliance sign-off | na      | No approver set — pick one on this step in the journey template          |

  # E1 — missing required documents are named
  Scenario: Missing required documents are listed
    Given there is an individual KYC for the investor
    And the KYC's form link was sent
    And the KYC is submitted
    And the KYC has the documents "Photo"
    When the KYC's journey is evaluated
    Then the KYC's journey should show:
      | task                      | status  | message                                                |
      | Send KYC form             | passed  |                                                        |
      | Submit KYC                | passed  |                                                        |
      | Upload required documents | current | 2 required documents missing: PAN Card, Address Proof |

  # E2 — nothing required: the task is not applicable
  Scenario: No required documents
    Given the entity requires no KYC documents
    And there is an individual KYC for the investor
    And the KYC's form link was sent
    And the KYC is submitted
    When the KYC's journey is evaluated
    Then the KYC's journey should show:
      | task                      | status | message                   |
      | Upload required documents | na     | No documents are required |

  # H5 — a full AI pass completes Validate documents with no click
  Scenario: AI validation passing every answer validates the documents
    Given the entity has 8 KYC document questions on "PAN Card"
    And there is an individual KYC for the investor
    And the KYC's form link was sent
    And the KYC is submitted
    And the KYC has the documents "PAN Card, Address Proof, Photo"
    And the KYC's AI validation found 0 of 8 answers failing
    When the KYC's journey is evaluated
    Then the KYC's journey should show:
      | task                | status  | message          |
      | Validate documents  | passed  | Validated by AI  |
      | Run AML screening   | current | No AML report yet |

  # E3 (data part) — AI could not validate some answers: a person checks and marks reviewed
  Scenario: AI validation with failing answers asks for a manual check
    Given the entity has 8 KYC document questions on "PAN Card"
    And there is an individual KYC for the investor
    And the KYC's form link was sent
    And the KYC is submitted
    And the KYC has the documents "PAN Card, Address Proof, Photo"
    And the KYC's AI validation found 1 of 8 answers failing
    When the KYC's journey is evaluated
    Then the KYC's journey should show:
      | task               | status  | message                                                             |
      | Validate documents | current | AI could not validate 1 of 8 answers — check them and mark reviewed |
    When I mark "Validate documents" reviewed on the KYC
    Then the KYC's journey current task should be "Run AML screening"

  # E4 — no document questions: a manual check
  Scenario: Without document questions the documents are checked by hand
    Given there is an individual KYC for the investor
    And the KYC's form link was sent
    And the KYC is submitted
    And the KYC has the documents "PAN Card, Address Proof, Photo"
    When the KYC's journey is evaluated
    Then the KYC's journey should show:
      | task               | status  | message                               |
      | Validate documents | current | Check the documents and mark reviewed |

  # E7, H10 — a potential match holds the KYC until it is overridden
  Scenario: A potential AML match is cleared by an override
    Given there is an individual KYC for the investor
    And the KYC's form link was sent
    And the KYC is submitted
    And the KYC has the documents "PAN Card, Address Proof, Photo"
    And the KYC's AML result is "potential_match"
    When the KYC's journey is evaluated
    And I mark "Validate documents" reviewed on the KYC
    Then the KYC's journey should show:
      | task              | status  | message                                                                                |
      | Run AML screening | passed  |                                                                                        |
      | Clear AML match   | current | AML found a potential match — review the report and override it if it is a false positive |
    When I override the KYC's AML status to "no_match" with reason "Namesake, DOB differs"
    And the KYC's journey is evaluated
    Then the KYC's journey current task should be "Review KYC"
    And the KYC's journey message for "Clear AML match" should include "Namesake, DOB differs"

  # H6 (data part) — no match: Clear AML match is not applicable
  Scenario: No AML match
    Given there is an individual KYC for the investor
    And the KYC's form link was sent
    And the KYC is submitted
    And the KYC has the documents "PAN Card, Address Proof, Photo"
    And the KYC's AML result is "no_match"
    When the KYC's journey is evaluated
    And I mark "Validate documents" reviewed on the KYC
    Then the KYC's journey should show:
      | task            | status  | message      |
      | Clear AML match | na      | No AML match |
      | Review KYC      | current | Check the KYC details and mark reviewed |

  # E8 — AML off
  Scenario: AML not enabled
    Given AML is not enabled for the entity
    And there is an individual KYC for the investor
    When the KYC's journey is evaluated
    Then the KYC's journey should show:
      | task              | status | message                      |
      | Run AML screening | na     | AML screening is not enabled |
      | Clear AML match   | na     | AML screening is not enabled |

  # H7, E9 — review, the sign-off (n/a without an approver, a vote with one) and Verify
  Scenario: Review and Compliance sign-off lead to Verify KYC
    Given I am the approver on the Compliance sign-off
    And there is an individual KYC for the investor
    And the KYC's form link was sent
    And the KYC is submitted
    And the KYC has the documents "PAN Card, Address Proof, Photo"
    And the KYC's AML result is "no_match"
    When the KYC's journey is evaluated
    And I mark "Validate documents" reviewed on the KYC
    And I mark "Review KYC" reviewed on the KYC
    Then the KYC's journey current task should be "Compliance sign-off"
    When I sign off the KYC's Compliance sign-off
    Then the KYC's journey current task should be "Verify KYC"
    When the KYC is verified directly
    And the KYC's journey is evaluated
    Then the KYC's journey should be complete

  # E9 — no approver picked: the sign-off is skipped
  Scenario: Without an approver the Compliance sign-off is not applicable
    Given there is an individual KYC for the investor
    And the KYC's form link was sent
    And the KYC is submitted
    And the KYC has the documents "PAN Card, Address Proof, Photo"
    And the KYC's AML result is "no_match"
    When the KYC's journey is evaluated
    And I mark "Validate documents" reviewed on the KYC
    And I mark "Review KYC" reviewed on the KYC
    Then the KYC's journey current task should be "Verify KYC"

  # E6 — verified with tasks undone: the closing check finishes the journey
  Scenario: A KYC verified without documents or AML still completes its journey
    Given there is an individual KYC for the investor
    And the KYC is verified directly
    When the KYC's journey is evaluated
    Then the KYC's journey should be complete
    And the KYC's journey should show:
      | task                      | status | message                    |
      | Send KYC form             | na     | Filled in by the fund      |
      | Submit KYC                | passed |                            |
      | Upload required documents | na     | Verified without this step |
      | Validate documents        | na     | Verified without this step |
      | Run AML screening         | na     | Verified without this step |
      | Verify KYC                | passed |                            |

  # E18 — an entity that was never set up: no journey
  Scenario: A KYC in an entity without the journey gets none
    Given the entity's investor KYC journeys are removed
    And there is an individual KYC for the investor
    Then the KYC has no journey

  # E21 — deleting a KYC that has a journey
  Scenario: A KYC with a journey can be deleted
    Given there is an individual KYC for the investor
    When the KYC's journey is evaluated
    And I delete the KYC
    Then the KYC should be deleted

  # E23 — a KYC the investor created never reminds the investor
  Scenario: Reminders for an investor-created KYC never go to the investor
    Given the investor created the KYC themselves
    Then the KYC's journey owner for reminders should be nobody

  # X6 — a check that errors shows the engine's message
  Scenario: A check that fails with an error
    Given there is an individual KYC for the investor
    And the KYC's form link was sent
    And the KYC is submitted
    And the KYC has the documents "PAN Card, Address Proof, Photo"
    And the Validate documents check raises an error
    When the KYC's journey is evaluated
    Then the KYC's journey should show:
      | task               | status | message                                                 |
      | Validate documents | error  | Could not check this step — support has been notified |

  # E10 — Request Updates moves back to Submit KYC and resets the review and the sign-off
  Scenario: Request Updates moves the journey back and resets later sign-offs
    Given I am the approver on the Compliance sign-off
    And there is an individual KYC for the investor
    And the KYC is at Verify KYC with my review and sign-off
    When I request updates on the KYC
    Then the KYC's journey should have moved back to "Submit KYC" with "Updates requested"
    And the "Review KYC" confirmation on the KYC should have been reset
    And the Compliance sign-off vote on the KYC should have been reset

  # E11 — UnVerify moves back to Verify KYC; with a document missing, to that task instead
  Scenario: UnVerify moves the journey back
    Given there is an individual KYC for the investor
    And the KYC is at Verify KYC with my review and sign-off
    When I verify the KYC from its page
    Then the KYC's journey should be complete
    When I unverify the KYC from its page
    Then the KYC's journey should have moved back to "Verify KYC" with "Unverified"

  Scenario: UnVerify of a KYC verified without its documents reopens the documents task
    Given there is an individual KYC for the investor
    And the KYC is verified directly
    And the KYC's journey is evaluated
    When I unverify the KYC from its page
    Then the KYC's journey should have moved back to "Upload required documents" with "Unverified"

  # E12 — editing the details after the review
  Scenario: Editing the KYC after it was reviewed moves the journey back to Review KYC
    Given there is an individual KYC for the investor
    And the KYC's form link was sent
    And the KYC is submitted
    And the KYC has the documents "PAN Card, Address Proof, Photo"
    And the KYC's AML result is "no_match"
    And the KYC's journey is evaluated
    And I mark "Validate documents" reviewed on the KYC
    And I mark "Review KYC" reviewed on the KYC
    When a fund user edits the KYC's address to "12 New Street, Mumbai"
    Then the KYC's journey should have moved back to "Review KYC" with "KYC details changed after review"

  # E5 — a document replaced after the AI pass
  Scenario: Replacing a document after the AI pass moves the journey back to Validate documents
    Given the entity has 8 KYC document questions on "PAN Card"
    And there is an individual KYC for the investor
    And the KYC's form link was sent
    And the KYC is submitted
    And the KYC has the documents "PAN Card, Address Proof, Photo"
    And the KYC's AI validation found 0 of 8 answers failing
    And the KYC's journey is evaluated
    And the KYC's journey current task should be "Run AML screening"
    When the KYC's "PAN Card" document is replaced
    Then the KYC's journey should have moved back to "Validate documents" with "Documents changed after validation"
    When I mark "Validate documents" reviewed on the KYC
    Then the KYC's journey current task should be "Run AML screening"

  # Deleting a required document moves back to Upload required documents
  Scenario: Deleting a required document moves the journey back
    Given there is an individual KYC for the investor
    And the KYC's form link was sent
    And the KYC is submitted
    And the KYC has the documents "PAN Card, Address Proof, Photo"
    And the KYC's journey is evaluated
    And I mark "Validate documents" reviewed on the KYC
    When the KYC's "Photo" document is deleted
    Then the KYC's journey should have moved back to "Upload required documents" with "Document deleted"

  # E13 — an upload before Validate documents is reached is not a move back
  Scenario: A document uploaded while the investor is filling the form is not a move back
    Given there is an individual KYC for the investor
    And the KYC's form link was sent
    And the KYC's journey is evaluated
    When the KYC has the documents "PAN Card"
    Then the KYC's journey current task should be "Submit KYC"
    And the KYC's journey history should have no move back

  # E14 — the documents-first form changes nothing until the investor submits
  Scenario: Uploading documents first does not complete any task
    Given there is an individual KYC for the investor
    And the KYC's form link was sent
    And the KYC's journey is evaluated
    When the investor uploads documents first and the form is pre-filled
    And the KYC's journey is evaluated
    Then the KYC's journey current task should be "Submit KYC"
    And the KYC's journey should show:
      | task                      | status  |
      | Submit KYC                | current |
      | Upload required documents | not_yet |
      | Validate documents        | not_yet |
