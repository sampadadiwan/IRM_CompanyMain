@security
Feature: Fund parent ids stay in the record's own firm and fund - 2026-10 security review (H9, H10)
  H9: a feeder's master fund is one of the firm's own funds and never the fund itself.
  H10: a payment's remittance, a remittance's call and commitment, and a fund unit's commitment are in
  the record's own fund, and an existing record never moves to another parent (the parent ids are
  read-only; an attempt to move one is refused, so no counter moves with it). A remittance's or unit's
  investor is one of the firm's own investors.
  Design and worked examples: docs/security/security_review_2026_10.md ("H9 — Fund#master_fund_id",
  "H10 — Parent ids on payments, remittances, fund units").

  Background:
    Given there is a user "first_name=Meera" for an entity "name=Acme Capital;entity_type=Investment Fund;enable_funds=true;currency=INR"
    And the user has role "company_admin"
    And there is an existing investor "" with "1" users
    And there is an existing investor "" with "1" users
    And there is a fund "name=Acme Growth Fund I;currency=INR" for the entity
    And the investors are added to the fund
    And there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And there is a capital call "percentage_called=20"
    And another firm "Zeta Partners" has a fund with a commitment, a call and a remittance
    And I have an API token

  # ── H9: master fund ────────────────────────────────────────────────────────

  # H9-1 — Edge case: a company admin setting another firm's fund as their fund's master on update gets a 422
  Scenario: H9-1 Another firm's fund cannot be set as master on update
    When "me" sends PATCH "/funds/{fund}.json" with:
      """
      {"fund": {"master_fund_id": {beta_fund}}}
      """
    Then the API status is 422
    And the API answer has an error on "master_fund"
    And my fund has no master fund

  # H9-2 — Edge case: creating a fund whose master is another firm's fund gets a 422 and no fund is created
  Scenario: H9-2 Another firm's fund cannot be set as master on create
    When "me" sends POST "/funds.json" with:
      """
      {"fund": {"name": "Acme Feeder", "currency": "INR", "master_fund_id": {beta_fund}}}
      """
    Then the API status is 422
    And the API answer has an error on "master_fund"
    And there is no fund named "Acme Feeder"

  # H9-H — Happy path: a feeder linked to a master fund of the same firm is saved (what the feeder's LPs then
  # see of the master's portfolio is covered by master_fund_portfolio_access.feature)
  Scenario: H9-H A feeder links to its own firm's master fund
    Given my firm has a master fund "Acme Master Fund"
    When "me" sends PATCH "/funds/{fund}.json" with:
      """
      {"fund": {"master_fund_id": {master_fund}}}
      """
    Then the API status is 200
    And my fund's master fund is "Acme Master Fund"

  # H9-X1 — Edge case: a fund set as its own master gets a 422
  Scenario: H9-X1 A fund cannot be its own master
    When "me" sends PATCH "/funds/{fund}.json" with:
      """
      {"fund": {"master_fund_id": {fund}}}
      """
    Then the API status is 422
    And the API answer has an error on "master_fund"
    And my fund has no master fund

  # H9-X2 — Edge case: clearing the master of a feeder is saved
  Scenario: H9-X2 Clearing the master fund is saved
    Given my firm has a master fund "Acme Master Fund"
    And my fund is a feeder of "Acme Master Fund"
    When "me" sends PATCH "/funds/{fund}.json" with:
      """
      {"fund": {"master_fund_id": null}}
      """
    Then the API status is 200
    And my fund has no master fund

  # ── H10: payments, remittances, fund units ─────────────────────────────────

  # H10-1 — Edge case: a payment posted from my fund against Zeta's remittance gets a 422; Zeta's totals are unchanged
  Scenario: H10-1 A payment cannot be made against another firm's remittance
    Given I note the other firm's remittance totals
    When "me" sends POST "/capital_remittance_payments.json" with:
      """
      {"capital_remittance_payment": {"entity_id": {entity}, "fund_id": {fund}, "capital_remittance_id": {beta_remittance},
        "folio_amount": 1000, "payment_date": "2026-10-21"}}
      """
    Then the API status is 422
    And the API answer has an error on "capital_remittance"
    And the other firm's remittance totals are unchanged

  # H10-2 — Edge case: re-pointing my payment to the other folio's remittance is refused; the payment stays
  # on its remittance and neither remittance's collected amount moves
  Scenario: H10-2 A payment cannot be moved to another remittance
    Given the remittance has a plain payment of 1000
    And I remember the other folio's remittance
    And I note the collected amounts of both remittances
    When "me" sends PATCH "/capital_remittance_payments/{payment}.json" with:
      """
      {"capital_remittance_payment": {"capital_remittance_id": {remittance2}}}
      """
    Then the API status is 422
    And the API answer has an error on "capital_remittance"
    And the payment is still on its remittance
    And the collected amounts of both remittances are unchanged

  # H10-3 — Edge case: re-pointing my remittance to Zeta's call is refused; the remittance stays on its call
  Scenario: H10-3 A remittance cannot be moved to another firm's call
    When "me" sends PATCH "/capital_remittances/{remittance}.json" with:
      """
      {"capital_remittance": {"capital_call_id": {beta_call}}}
      """
    Then the API status is 422
    And the API answer has an error on "capital_call"
    And the remittance is still on its own call

  # H10-4 — Edge case: a fund unit in my fund on Zeta's commitment is refused
  Scenario: H10-4 A fund unit cannot use another firm's commitment
    When I build a fund unit in my fund on the other firm's commitment
    Then the fund unit is refused with an error on "capital_commitment"

  # H10-X1 — Edge case: a payment with fund A and a remittance of my own fund B gets a 422
  Scenario: H10-X1 A payment's remittance must be in the payment's fund
    Given my firm has a second fund "Acme Fund II" with a commitment, a call and a remittance
    When "me" sends POST "/capital_remittance_payments.json" with:
      """
      {"capital_remittance_payment": {"entity_id": {entity}, "fund_id": {fund}, "capital_remittance_id": {second_remittance},
        "folio_amount": 1000, "payment_date": "2026-10-21"}}
      """
    Then the API status is 422
    And the API answer has an error on "capital_remittance"

  # H10-H — Happy path: a payment on my own remittance is created and raises its collected amount
  Scenario: H10-H A payment on my own remittance is created
    Given I note the collected amount of the remittance
    When "me" sends POST "/capital_remittance_payments.json" with:
      """
      {"capital_remittance_payment": {"entity_id": {entity}, "fund_id": {fund}, "capital_remittance_id": {remittance},
        "folio_amount": 1000, "payment_date": "2026-10-21", "reference_no": "UTR-H10"}}
      """
    Then the API status is 201
    And the remittance's collected amount went up by 1000

  # H10-X2 — Edge case: an update-only re-import of a payment (same firm, fund and remittance re-assigned) saves
  Scenario: H10-X2 An update-only re-import of a payment still saves
    Given the remittance has a plain payment of 1000
    When the payment is re-saved the way an update-only import does
    Then the re-saved payment kept its remittance and has the notes "Re-imported"

  # H10-X3 — Edge case: editing a remittance's notes is saved (the read-only parents are untouched)
  Scenario: H10-X3 Editing a remittance's notes still works
    When "me" sends PATCH "/capital_remittances/{remittance}.json" with:
      """
      {"capital_remittance": {"notes": "Checked by ops"}}
      """
    Then the API status is 200
    And the remittance has the notes "Checked by ops"
    And the remittance is still on its own call
