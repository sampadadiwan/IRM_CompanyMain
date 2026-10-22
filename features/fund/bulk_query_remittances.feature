# bulk-path-query-optimisation, phase 2 — capital remittance re-saves and their document checks.
# Phase 8 — call generation reads the remittance form type once.
# Worked examples: openspec/changes/bulk-path-query-optimisation/business-rules.md (H1, H2, H7, X1, X3, H9, E12)

@bulk_query @rack_test
Feature: Capital call generation loads each remittance's related records per batch
  Generating a call re-saves every remittance (after payments are generated) and each new payment
  un-verifies its remittance. Both used to fetch every remittance's commitment, investor, fund and
  documents one at a time; they now arrive with the batch. Results must not change.

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;enable_funds=true;currency=INR"
    And the user has role "company_admin"
    And there is an existing investor "" with "1" users
    And there is an existing investor "" with "1" users
    And there is an existing investor "" with "1" users
    And there is a fund "name=Alpha Fund I" for the entity
    And the investors are added to the fund
    And there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And there is a capital call "name=Q3 Call;percentage_called=10" whose remittances are not generated yet
    And the call asks for 10% from every close

  # H1 — Happy path: the re-save pass reads each remittance's commitment from its batch
  # (3 remittances: 3 commitment lookups without the batch preload, 6 when payments are generated too)
  Scenario: H1 Remittances are re-saved without per-remittance commitment lookups
    Given I count queries by call site
    When the call's remittances are generated
    Then each remittance of the call should be called at 10% of its commitment
    And at most 0 queries came from "CapitalRemittance#set_call_amount"

  # H7 — Happy path: the same when generation also creates payments and each un-verifies its remittance
  Scenario: H7 Generating verified remittances and their payments skips per-remittance lookups
    Given the call generates its remittances already verified
    And I count queries by call site
    When the call's remittances are generated
    Then each remittance of the call should have one payment of its call amount
    And at most 0 queries came from "CapitalRemittance#set_call_amount"

  # H2 — Happy path: a payment's un-verify loads the remittance's documents with their folders and
  # signatures in one pass (3 documents: 47 queries without the preload, 35 with)
  Scenario: H2 Un-verifying a remittance with documents loads them in one pass
    Given the call's remittances are generated
    And the first remittance of the call has 3 documents
    And I count queries by call site
    When a payment dated "2099-01-01" is recorded for the first remittance of the call
    Then the first remittance of the call should have payment date "2099-01-01"
    And at most 0 queries came from "Document#setup_folder"

  # X1 — Error case: an invalid document still blocks the remittance's save after the preload
  Scenario: X1 An invalid document still stops the remittance from being saved
    Given the call generates its remittances already verified
    And the call's remittances are generated
    And the first remittance of the call has a document that is no longer valid
    When a payment dated "2099-01-01" is recorded for the first remittance of the call
    Then the first remittance of the call should keep its payment date

  # X3 — Error case (control for X1): the same payment without the invalid document does move the payment
  # date, so X1 fails because of the document and not for some other reason
  Scenario: X3 A valid remittance takes the new payment's date
    Given the call generates its remittances already verified
    And the call's remittances are generated
    When a payment dated "2099-01-01" is recorded for the first remittance of the call
    Then the first remittance of the call should have payment date "2099-01-01"

  # H8 — Happy path (found in review): generating the call again when every remittance already exists and
  # nothing changes leaves the fund untouched, as before (a belongs_to touch fires only on a changed save)
  Scenario: H8 Re-generating an unchanged call does not touch the fund
    Given the call's remittances are generated
    And I note the fund's last update
    When the call's remittances are generated
    Then the fund should not have been touched

  # H8 — Happy path (control): generating creates remittances, so the fund is touched once
  Scenario: H8 control Generating a call touches the fund
    Given I note the fund's last update
    When the call's remittances are generated
    Then the fund should have been touched

  # H9 — Happy path (phase 8): call generation reads the remittance form once, not once per remittance
  Scenario: H9 Generated remittances get the entity's form without a lookup each
    Given the entity has a capital remittance form
    And I count queries by call site
    When the call's remittances are generated
    Then every remittance of the call should have that form
    And at most 0 queries came from "CapitalRemittance#setup_form_type"

  # E12 — Edge case (phase 8): with no remittance form the remittances are generated without one, as before
  Scenario: E12 Remittances are generated without a form when the entity has none
    Given the entity has no capital remittance form
    When the call's remittances are generated
    Then every remittance of the call should have that form
