Feature: Capital distribution fixes — approval, completion, wording and background reporting
  Approving a distribution needs the Approver role (as for capital calls); marking all payments
  completed is refused on the server for an unapproved distribution, not just hidden in the menu;
  the Send Notification hint no longer claims completion emails investors; and the payment and
  recompute jobs report correctly.
  Worked examples X1, X2, X4, X5, E23 in openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;enable_funds=true;currency=INR"
    And the user has role "company_admin"
    And there is an existing investor "" with "1" users
    And there is an existing investor "" with "1" users
    And there is a fund "name=Growth Fund II;currency=INR" for the entity
    And the investors are added to the fund
    And there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor

  # X1 — without the Approver role there is no Approve, and a direct request is refused
  Scenario: A user without the Approver role cannot approve a distribution
    Given there is a capital distribution "title=Q3 2026 Exit Proceeds;income_cents=300000000;approved=false"
    When I open the capital distribution page
    And I open the distribution's Actions menu
    Then the distribution's Actions menu should not offer "Approve"
    When I send the distribution "approve" request directly
    Then I should see "Access Denied" on the page
    And the distribution should not be approved

  # X1 (the allowed side) — an approver approves, and the approver is recorded
  Scenario: An approver approves a distribution
    Given the user has role "approver"
    And there is a capital distribution "title=Q3 2026 Exit Proceeds;income_cents=300000000;approved=false"
    When I open the capital distribution page
    And I open the distribution's Actions menu
    And I click "Approve" in the distribution's Actions menu and confirm
    Then the distribution should be approved by me

  # X2 — Mark Payments Completed is refused for an unapproved distribution, menu and request alike
  Scenario: Marking all payments completed is refused for an unapproved distribution
    Given the user has role "approver"
    And there is a capital distribution "title=Q3 2026 Exit Proceeds;income_cents=300000000;approved=false"
    When I open the capital distribution page
    And I open the distribution's Actions menu
    Then the distribution's Actions menu should not offer "Mark Payments Completed"
    When I send the distribution "payments_completed" request directly
    Then I should see "Access Denied" on the page
    And no payment of the distribution should be completed

  # X2 (the allowed side) — once approved, the same action completes every payment
  Scenario: Marking all payments completed works once the distribution is approved
    Given there is a capital distribution "title=Q3 2026 Exit Proceeds;income_cents=300000000;approved=true"
    When I open the capital distribution page
    And I open the distribution's Actions menu
    And I click "Mark Payments Completed" in the distribution's Actions menu and confirm
    Then every payment of the distribution should be completed

  # E23 — the Send Notification hint describes what actually happens
  Scenario: The Send Notification hint says where emails are sent from
    When I open the new capital distribution form
    Then I should see "Allow emailing investors about this distribution. Emails are sent from Actions → Send Payment Notifications." on the page
    And the page should not mention "when distribution payment is marked completed"

  # X4 — a generation error with no user to email is logged, not raised a second time
  Scenario: Payment generation errors with no user are logged without failing again
    Given there is a capital distribution "title=Q3 2026 Exit Proceeds;income_cents=300000000;approved=false"
    When payment generation for the distribution hits an error with no user
    Then the payment generation job should finish without raising

  # X5 — Recompute Fees' first progress message names the distribution
  Scenario: Recompute Fees names the distribution in its first message
    Given there is a capital distribution "title=Q3 2026 Exit Proceeds;income_cents=300000000;approved=true"
    When the distribution's fees are recomputed by me
    Then the first recompute message should be "Recomputing fees for all payments for distribution Q3 2026 Exit Proceeds"
