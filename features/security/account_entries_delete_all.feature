@security
Feature: Delete Results on the ledger is authorized - 2026-10 security review (H7)
  "Delete Results" (account_entries#delete_all) is a staff action: an LP is refused. The job then
  decides per fund, never per row and never by scanning the ledger: it keeps only the user's own funds
  (policy_scope(Fund)) where a single entry's Delete would be allowed (destroy on the fund; every fund
  for a company admin), and deletes the filtered entries of those funds only.
  Design and worked examples: docs/security/security_review_2026_10.md ("H7 — account_entries#delete_all").

  Background:
    Given there is a user "first_name=Meera" for an entity "name=Acme Capital;entity_type=Investment Fund;enable_funds=true;currency=INR"
    And the user has role "company_admin"
    And there is an existing investor "" with "1" users
    And there is an existing investor "" with "1" users
    And there is a fund "name=Acme Growth Fund I;currency=INR" for the entity
    And the investors are added to the fund
    And there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And there is a capital call "percentage_called=20"
    And I have an API token
    And folio 1 has account entries of "NAV:500,Fee:100,Fee:200"

  # H7-1 — Edge case: an LP calling Delete Results on their own fund is refused (403); every entry remains
  Scenario: H7-1 An LP cannot delete account entries
    Given "Lena" is the investor user of folio 1
    When "Lena" sends POST "/account_entries/delete_all.json?fund_id={fund}"
    Then the API status is 403
    And my fund has 1 account entries of type "NAV"
    And my fund has 2 account entries of type "Fee"

  # H7-2 — Edge case: a read-only employee may reach the list, but holds destroy on no fund: nothing is deleted
  Scenario: H7-2 A read-only employee deletes nothing
    Given "Ravi" is an employee of my firm with "read" access to my fund
    When "Ravi" sends POST "/account_entries/delete_all.json?fund_id={fund}"
    Then my fund has 1 account entries of type "NAV"
    And my fund has 2 account entries of type "Fee"

  # H7-H — Happy path: a company admin deletes the results filtered by entry type "Fee"; only those go
  Scenario: H7-H A company admin deletes the filtered results
    When "me" sends POST "/account_entries/delete_all.json?fund_id={fund}&q[entry_type_eq]=Fee"
    Then my fund has 0 account entries of type "Fee"
    And my fund has 1 account entries of type "NAV"

  # H7-X1 — Edge case: with destroy on fund A and read on fund B, "all funds" deletes A's entries only
  Scenario: H7-X1 All funds deletes only from funds the user may delete in
    Given my firm has a second fund "Acme Fund II" with a commitment, a call and a remittance
    And the fund "Acme Fund II" has account entries of "NAV:300,Fee:50"
    And "Dev" is an employee of my firm with "read,destroy" access to my fund
    And "Dev" is an employee of my firm with "read" access to the fund named "Acme Fund II"
    When "Dev" sends POST "/account_entries/delete_all.json"
    Then my fund has 0 account entries of type "NAV"
    And my fund has 0 account entries of type "Fee"
    And the fund "Acme Fund II" has 2 account entries

  # H7-X2 — Edge case: a company admin naming another firm's fund deletes nothing there: that fund is not in
  # their own funds, so the job never touches its ledger
  Scenario: H7-X2 Another firm's fund id deletes nothing
    Given another firm "Zeta Partners" has a fund with a commitment, a call and a remittance
    And the other firm's fund has account entries of "NAV:300,Fee:50"
    When "me" sends POST "/account_entries/delete_all.json?fund_id={beta_fund}"
    Then the other firm's fund still has 2 account entries
    And my fund has 1 account entries of type "NAV"
