Feature: Investor KYC fixes that ship with the KYC journey
  A fund user ticking "I confirm all details provided are complete…" now marks the KYC submitted
  (the tick used to be thrown away), and bulk Unverify puts KYCs back to "completed" exactly like
  the KYC page's UnVerify — Request Updates is what reopens a KYC for the investor.
  Worked examples H9, E16, E17 in openspec/changes/investor-kyc-journey/design.md#worked-examples

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;enable_kycs=true"
    And the user has role "company_admin"
    And there is an existing investor "" with "1" users
    And the entity's investor KYC journeys are removed
    And the entity's investor KYC journeys are seeded
    And the entity requires the individual KYC documents "PAN Card, Address Proof, Photo"
    And AML is not enabled for the entity

  # H9 — the fund fills the KYC in and ticks complete
  @rack_test
  Scenario: A fund user ticking complete marks the KYC submitted
    Given there is an individual KYC for the investor
    When a fund user ticks complete on the KYC
    Then the KYC's status should be "completed"
    And the KYC should have been submitted just now
    And the KYC's journey should show:
      | task          | status | message               |
      | Send KYC form | na     | Filled in by the fund |
      | Submit KYC    | passed |                       |

  # E16 — unticking moves it back to draft and the journey back to Submit KYC
  @rack_test
  Scenario: A fund user unticking complete moves the journey back
    Given there is an individual KYC for the investor
    And the KYC has the documents "PAN Card, Address Proof, Photo"
    And a fund user ticks complete on the KYC
    When a fund user unticks complete on the KYC
    Then the KYC's status should be "draft_saved"
    And the KYC's journey should have moved back to "Submit KYC" with "Marked incomplete"

  # E17 — bulk Unverify matches the single UnVerify
  @rack_test
  Scenario: Bulk Unverify puts KYCs back to completed
    Given there are 3 verified individual KYCs with journeys
    When I bulk "unverify" the KYCs
    Then each of the KYCs should be "completed" with the journey back at "Upload required documents"
    And the investor should not be able to edit the KYC

  # Review fix — bulk Unverify leaves KYCs that were never verified alone (no fake submission)
  @rack_test
  Scenario: Bulk Unverify does not mark an unsubmitted KYC as submitted
    Given there is an individual KYC for the investor that was never submitted
    When I bulk "unverify" the KYCs
    Then the KYC's status should be "not_sent"

  # Save submits with form.submit() (skipping Turbo's own button disabling), so a second click used to
  # save the form — and every attached file — again. The first click now locks the wizard's buttons.
  Scenario: Clicking Save twice on the KYC form submits it once
    Given there is an individual KYC for the investor
    When I open the KYC edit form with submits counted
    And I click the KYC form's Save button twice
    Then the KYC form should have been submitted 1 time
    And the KYC form's Save button should be disabled and show "Saving..."
