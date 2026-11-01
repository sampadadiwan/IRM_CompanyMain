@security
Feature: Bulk actions are authorized - 2026-10 security review (H6)
  Every bulk action first asks the model's policy for bulk_actions? on the class (LPs and other
  investor personas are refused outright on every fund, KYC and secondaries route), then its job holds
  each row to the predicate the single-record button uses, so a staff user changes only the rows they
  could change one at a time and gets a "Not authorized" line for the rest. Enable All / Disable All
  needs update on the fund. The documents menu also renders for LPs, so there the per-row check is what
  refuses them.
  Design and worked examples: docs/security/security_review_2026_10.md ("H6 — Bulk actions" and
  "Secondaries bulk jobs (H6)" under H8).

  # ── Fund bulk actions ──────────────────────────────────────────────────────

  # H6-1 — Edge case: an LP bulk-verifying their own remittance is refused (403) and nothing is verified
  Scenario: H6-1 An LP cannot bulk verify remittances
    Given there is a user "first_name=Meera" for an entity "name=Acme Capital;entity_type=Investment Fund;enable_funds=true;currency=INR"
    And the user has role "company_admin"
    And there is an existing investor "" with "1" users
    And there is an existing investor "" with "1" users
    And there is a fund "name=Acme Growth Fund I;currency=INR" for the entity
    And the investors are added to the fund
    And there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And there is a capital call "percentage_called=20"
    And I have an API token
    And every remittance of the call is paid in full but unverified
    And "Lena" is the investor user of folio 1
    When "Lena" sends POST "/capital_remittances/bulk_actions.json?capital_call_id={call}&bulk_action=verify"
    Then the API status is 403
    And no remittance of the call is verified

  # H6-3 — Edge case: an LP bulk-disabling the fund's formulas is refused (403) and every formula stays enabled
  Scenario: H6-3 An LP cannot bulk disable formulas
    Given there is a user "first_name=Meera" for an entity "name=Acme Capital;entity_type=Investment Fund;enable_funds=true;currency=INR"
    And the user has role "company_admin"
    And there is an existing investor "" with "1" users
    And there is an existing investor "" with "1" users
    And there is a fund "name=Acme Growth Fund I;currency=INR" for the entity
    And the investors are added to the fund
    And there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And there is a capital call "percentage_called=20"
    And I have an API token
    And there is an enabled fund formula "Management Fee" at sequence "1"
    And "Lena" is the investor user of folio 1
    When "Lena" sends POST "/fund_formulas/bulk_actions.json?fund_id={fund}&bulk_action=disable"
    Then the API status is 403
    And every formula of my fund is still enabled

  # H6-4 — Edge case: an LP calling Disable All (enable_formulas) on a fund they invest in is refused (403)
  Scenario: H6-4 An LP cannot Disable All formulas
    Given there is a user "first_name=Meera" for an entity "name=Acme Capital;entity_type=Investment Fund;enable_funds=true;currency=INR"
    And the user has role "company_admin"
    And there is an existing investor "" with "1" users
    And there is an existing investor "" with "1" users
    And there is a fund "name=Acme Growth Fund I;currency=INR" for the entity
    And the investors are added to the fund
    And there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And there is a capital call "percentage_called=20"
    And I have an API token
    And there is an enabled fund formula "Management Fee" at sequence "1"
    And "Lena" is the investor user of folio 1
    When "Lena" sends PATCH "/fund_formulas/enable_formulas.json?fund_id={fund}&enable=false"
    Then the API status is 403
    And every formula of my fund is still enabled

  # H6-5 — Edge case: an LP bulk-verifying their own KYC is refused (403) and the KYC stays unverified
  Scenario: H6-5 An LP cannot bulk verify their own KYC
    Given there is a user "first_name=Meera" for an entity "name=Acme Capital;entity_type=Investment Fund;enable_funds=true;enable_kycs=true;currency=INR"
    And the user has role "company_admin"
    And there is an existing investor "" with "1" users
    And there is an existing investor "" with "1" users
    And there is a fund "name=Acme Growth Fund I;currency=INR" for the entity
    And the investors are added to the fund
    And there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And there is a capital call "percentage_called=20"
    And I have an API token
    And folio 1 has a KYC that is not verified
    And "Lena" is the investor user of folio 1
    When "Lena" sends POST "/investor_kycs/bulk_actions.json?bulk_action=verify"
    Then the API status is 403
    And the KYC of folio 1 is still not verified

  # H6-6 — Edge case: an LP bulk-deleting a document they can see (their own upload) deletes nothing: the
  # documents menu lets them in, but each row needs destroy?, which only the fund's staff hold
  Scenario: H6-6 An LP cannot bulk delete a document they can see
    Given there is a user "first_name=Meera" for an entity "name=Acme Capital;entity_type=Investment Fund;enable_funds=true;enable_documents=true;currency=INR"
    And the user has role "company_admin"
    And there is an existing investor "" with "1" users
    And there is an existing investor "" with "1" users
    And there is a fund "name=Acme Growth Fund I;currency=INR" for the entity
    And the investors are added to the fund
    And there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And there is a capital call "percentage_called=20"
    And I have an API token
    And "Lena" is the investor user of folio 1
    And "Lena" uploaded a document "Lena Bank Proof" on folio 1
    When "Lena" sends POST "/documents/bulk_actions.json?owner_type=CapitalCommitment&owner_id={folio1}&bulk_action=delete"
    Then the document "Lena Bank Proof" still exists

  # H6-7 — Edge case: a read-only employee's bulk verify changes no remittance and mails "Not authorized"
  Scenario: H6-7 A read-only employee's bulk verify verifies nothing
    Given there is a user "first_name=Meera" for an entity "name=Acme Capital;entity_type=Investment Fund;enable_funds=true;currency=INR"
    And the user has role "company_admin"
    And there is an existing investor "" with "1" users
    And there is an existing investor "" with "1" users
    And there is a fund "name=Acme Growth Fund I;currency=INR" for the entity
    And the investors are added to the fund
    And there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And there is a capital call "percentage_called=20"
    And I have an API token
    And every remittance of the call is paid in full but unverified
    And "Ravi" is an employee of my firm with "read" access to my fund
    When "Ravi" sends POST "/capital_remittances/bulk_actions.json?capital_call_id={call}&bulk_action=verify"
    Then the API status is 202
    And no remittance of the call is verified
    And an errors email says "Not authorized to verify"

  # H6-H1 — Happy path: a company admin's bulk verify still verifies every remittance of the call
  Scenario: H6-H1 A company admin bulk verifies remittances
    Given there is a user "first_name=Meera" for an entity "name=Acme Capital;entity_type=Investment Fund;enable_funds=true;currency=INR"
    And the user has role "company_admin"
    And there is an existing investor "" with "1" users
    And there is an existing investor "" with "1" users
    And there is a fund "name=Acme Growth Fund I;currency=INR" for the entity
    And the investors are added to the fund
    And there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And there is a capital call "percentage_called=20"
    And I have an API token
    And every remittance of the call is paid in full but unverified
    When "me" sends POST "/capital_remittances/bulk_actions.json?capital_call_id={call}&bulk_action=verify"
    Then the API status is 202
    And every remittance of the call is verified

  # H6-H2 — Happy path: a company admin's Disable All (enable_formulas) still disables the fund's formulas
  Scenario: H6-H2 A company admin uses Disable All
    Given there is a user "first_name=Meera" for an entity "name=Acme Capital;entity_type=Investment Fund;enable_funds=true;currency=INR"
    And the user has role "company_admin"
    And there is an existing investor "" with "1" users
    And there is an existing investor "" with "1" users
    And there is a fund "name=Acme Growth Fund I;currency=INR" for the entity
    And the investors are added to the fund
    And there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And there is a capital call "percentage_called=20"
    And I have an API token
    And there is an enabled fund formula "Management Fee" at sequence "1"
    And there is an enabled fund formula "Setup Fee" at sequence "2"
    When "me" sends PATCH "/fund_formulas/enable_formulas.json?fund_id={fund}&enable=false"
    Then the API status is 204
    And every formula of my fund is disabled

  # H6-X1 — Edge case: with update on fund A only (read on B), a bulk disable over both funds' formulas
  # disables A's and leaves B's enabled
  Scenario: H6-X1 A bulk disable changes only the fund the employee may update
    Given there is a user "first_name=Meera" for an entity "name=Acme Capital;entity_type=Investment Fund;enable_funds=true;currency=INR"
    And the user has role "company_admin"
    And there is an existing investor "" with "1" users
    And there is an existing investor "" with "1" users
    And there is a fund "name=Acme Growth Fund I;currency=INR" for the entity
    And the investors are added to the fund
    And there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And there is a capital call "percentage_called=20"
    And I have an API token
    And there is an enabled fund formula "A Management Fee" at sequence "1"
    And my firm has a second fund "Acme Fund II" with a commitment, a call and a remittance
    And the fund "Acme Fund II" has an enabled formula "B Management Fee"
    And "Dev" is an employee of my firm with "read,update" access to my fund
    And "Dev" is an employee of my firm with "read" access to the fund named "Acme Fund II"
    When "Dev" sends POST "/fund_formulas/bulk_actions.json?bulk_action=disable&all=true"
    Then the API status is 202
    And every formula of my fund is disabled
    And every formula of the fund "Acme Fund II" is still enabled
    And an errors email says "Not authorized to disable"

  # ── Secondaries bulk actions ───────────────────────────────────────────────

  # H6-2 — Edge case: the seller (an LP) bulk-verifying the sale's allocations is refused (403)
  Scenario: H6-2 A seller cannot bulk verify allocations
    Given my company has a fixed-price sale with an approved offer, a short-listed interest and an unverified allocation
    And "Seller" is the seller on that sale
    When "Seller" sends POST "/allocations/bulk_actions.json?secondary_sale_id={sale}&bulk_action=verify"
    Then the API status is 403
    And the sale's allocation is still unverified

  # H6-H3 — Happy path: the company admin bulk-verifies the sale's offers (this used to raise a 500:
  # bulk_actions? checked sale access on the Offer class)
  Scenario: H6-H3 A company admin bulk verifies offers
    Given my company has a fixed-price sale with an approved offer, a short-listed interest and an unverified allocation
    When "me" sends POST "/offers/bulk_actions.json?secondary_sale_id={sale}&bulk_action=verify"
    Then the API status is 202
    And the sale's offer is verified

  # H6-S1 — Edge case: an employee with read-only access to the sale passes the class check, but each
  # allocation needs update?, so none is verified
  Scenario: H6-S1 A read-only employee's bulk verify leaves allocations unverified
    Given my company has a fixed-price sale with an approved offer, a short-listed interest and an unverified allocation
    And "Rhea" is an employee of my company with read-only access to the sale
    When "Rhea" sends POST "/allocations/bulk_actions.json?secondary_sale_id={sale}&bulk_action=verify"
    Then the API status is 202
    And the sale's allocation is still unverified
    And an errors email says "Not authorized to verify"

  # H6-S2 — Edge case: the same read-only employee's bulk verify of offers verifies none
  Scenario: H6-S2 A read-only employee's bulk verify leaves offers unverified
    Given my company has a fixed-price sale with an approved offer, a short-listed interest and an unverified allocation
    And "Rhea" is an employee of my company with read-only access to the sale
    When "Rhea" sends POST "/offers/bulk_actions.json?secondary_sale_id={sale}&bulk_action=verify"
    Then the API status is 202
    And the sale's offer is still unverified
    And an errors email says "Not authorized to verify"

  # H6-S3 — Happy path (pre-existing bug): bulk "generate spa" reaches OfferSpaJob with the arguments it
  # takes (sale, offer, user); it used to pass (offer, user) and raise ArgumentError on every offer
  Scenario: H6-S3 Bulk generate SPA passes the sale, the offer and the user
    Given my company has a fixed-price sale with an approved offer, a short-listed interest and an unverified allocation
    And the offer of that sale is verified
    And SPA generation for offers is stubbed
    When "me" sends POST "/offers/bulk_actions.json?secondary_sale_id={sale}&bulk_action=generate%20spa"
    Then the API status is 202
    And OfferSpaJob was run for the offer with the sale, the offer and me

  # H6-SH — Happy path: the company admin bulk-verifies the sale's allocations
  Scenario: H6-SH A company admin bulk verifies allocations
    Given my company has a fixed-price sale with an approved offer, a short-listed interest and an unverified allocation
    When "me" sends POST "/allocations/bulk_actions.json?secondary_sale_id={sale}&bulk_action=verify"
    Then the API status is 202
    And the sale's allocation is verified
