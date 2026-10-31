@security
Feature: Bulk document approval - 2026-10 security review (H1)
  The "Approve Generated Documents" page (approve by date range, and "Approve KYC Docs" on the KYC
  list) approves every unapproved generated document of the firm in one go, and with "notification"
  emails them to LPs. It is now authorized like approving one document: an approver employee of the
  firm with documents enabled, or support - for the page and for the approval itself. A folder tree
  must be the user's own firm's, and the background job re-checks that. Each refusal is paired with
  the legitimate use that must keep working.
  Design and worked examples: docs/security/security_review_2026_10.md#h1--bulk-document-approval

  Background:
    Given Im logged in as a user "first_name=Asha" for an entity "name=Artha;entity_type=Investment Fund;enable_funds=true;currency=INR"
    And the user has role "company_admin"
    And my firm has a folder "Q3 Notices" with 2 generated documents awaiting approval

  # H1-1 — Edge case: a company admin who is not an approver cannot bulk-approve the firm's generated documents
  @rack_test
  Scenario: H1-1 A non-approver employee bulk approving is refused
    When I bulk approve the firm's generated documents from yesterday to today with notification
    Then I am denied access
    And the folder's generated documents are still unapproved
    And no document owner was notified

  # H1-2 — Edge case: an approver of another firm cannot approve (and email) this firm's folder tree
  @rack_test
  Scenario: H1-2 Another firm's approver approving this firm's folder is refused
    Given I am signed in as an approver of another firm "Zeta Capital"
    When I bulk approve the documents of the folder from yesterday to today with notification
    Then I am denied access
    And the folder's generated documents are still unapproved
    And no document owner was notified

  # H1-3 — Edge case: another firm's approver opening the page with this firm's folder learns nothing about it
  @rack_test
  Scenario: H1-3 Another firm's approver opening the approval page for this firm's folder is refused
    Given I am signed in as an approver of another firm "Zeta Capital"
    When I open the approval page for the folder
    Then I am denied access
    And the folder's name is not on the page

  # H1-4 — Edge case: the job, run for another firm with this firm's folder (any caller), approves nothing
  Scenario: H1-4 The approval job run for another firm with this firm's folder approves nothing
    Given there is an approver of another firm "Zeta Capital"
    When the document approval job runs for "Zeta Capital" with the folder and notification
    Then the folder's generated documents are still unapproved
    And no document owner was notified

  # H1-H — Happy path: the firm's approver approves the call notices by date range; the call journey moves on
  @rack_test
  Scenario: H1-H The firm's approver approves call notices by date range and the journey progresses
    Given there is an existing investor "" with "1" users
    And there is a fund "name=Alpha Fund I" for the entity
    And the investors are added to the fund
    And there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And each investor has a "verified" kyc linked to the commitment
    And the entity's capital call journeys are seeded
    And the fund has capital call template
    And there is a capital call "percentage_called=10"
    And the call's notices are generated for verified investors
    And the call's journey is evaluated
    And the call's journey current task should be "Approve notices"
    And the user has role "approver"
    When I bulk approve the firm's generated "CapitalRemittance" documents from yesterday to today
    Then the call's notices are approved by me
    And the call's journey current task should be "Review custom notification"

  # H1-H2 — Happy path: the firm's approver uses "Approve KYC Docs" and the KYC's generated document is approved
  @rack_test
  Scenario: H1-H2 The firm's approver approves KYC documents from the Approve KYC Docs page
    Given there is an existing investor "" with "1" users
    And the investor has a KYC with a generated document awaiting approval
    And the user has role "approver"
    When I open the Approve KYC Docs page
    And I press "Approve All"
    Then the KYC's generated document is approved by me
    And the folder's generated documents are still unapproved

  # H1-X — Happy path: support can open the approval page
  @rack_test
  Scenario: H1-X Support opening the approval page is allowed
    Given I am signed in as a support user of my firm
    When I open the approval page
    Then I see the approval form

  # H1-X2 — Edge case: an LP user, even one holding the approver role, cannot open the approval page
  @rack_test
  Scenario: H1-X2 An LP user opening the approval page is refused
    Given there is an existing investor "" with "1" users
    And I am signed in as the investor's user holding the approver role
    When I open the approval page
    Then I am denied access
