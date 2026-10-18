Feature: Calls and distributions in bulk, and the fields to confirm them (phase 10)
  Approve / allocate units for many calls and approve / redeem units for many distributions in one
  request — each exactly as its single button, with the same permission — and read back what happened:
  approval, fund dates, and when the units job finished. Additive; single-record actions unchanged.
  Findings: Orios trial P12, G16, G17, G18 (P13 withdrawn — the currency columns stay custom fields, as before)
  Reference: docs/modules/funds/funds_json_api.md

  Background:
    Given there is a user "first_name=Meera" for an entity "name=Acme Capital;entity_type=Investment Fund;enable_funds=true;currency=INR"
    And the user has role "company_admin"
    And the entity has "enable_import_uploads" permission
    And there is an existing investor "" with "1" users
    And there is an existing investor "" with "1" users
    And there is a fund "name=Acme Growth Fund I;currency=INR" for the entity
    And the investors are added to the fund
    And there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And there is a capital call "percentage_called=20"
    And there are 2 more capital calls on my fund
    And I have an API token

  # H35 — Happy path (P12): an approver approves every call of the fund in one request; each goes through the Approve button's rules
  Scenario: H35 Bulk approve capital calls
    Given "me" is an approver
    When "me" sends POST "/capital_calls/bulk_actions.json?fund_id={fund}&bulk_action=approve"
    Then the API status is 202
    And the API answer at "count" is "3"
    And every capital call of my fund is approved

  # X52 — Error case (P12): a company admin without the approver role cannot bulk approve — nothing is approved
  Scenario: X52 Bulk approve needs the approver role
    When "me" sends POST "/capital_calls/bulk_actions.json?fund_id={fund}&bulk_action=approve"
    Then the API status is 202
    And no capital call of my fund is approved

  # H36 — Happy path (P12, G18): bulk allocate units runs the units job per approved call and stamps units_job_finished_at
  Scenario: H36 Bulk allocate units
    Given "me" is an approver
    And every capital call of my fund is approved already
    When "me" sends POST "/capital_calls/bulk_actions.json?fund_id={fund}&bulk_action=allocate units"
    Then the API status is 202
    And every capital call of my fund has units_job_finished_at set

  # E42 — Edge case (G18): the single Allocate Units answers an API caller 202 JSON, and the call's JSON says when it finished
  Scenario: E42 Allocate units answers JSON and reports completion
    Given every capital call of my fund is approved already
    When "me" sends PATCH "/capital_calls/{call}/allocate_units.json"
    Then the API status is 202
    And the API answer at "status" is "queued"
    When "me" sends GET "/capital_calls/{call}.json"
    Then the API answer at "units_job_finished_at" is present
    And the API answer at "approved" is "true"

  # H37 — Happy path (P12): an approver approves the fund's distributions in one request
  Scenario: H37 Bulk approve distributions
    Given "me" is an approver
    And there is a capital distribution payment for the fund
    When "me" sends POST "/capital_distributions/bulk_actions.json?fund_id={fund}&bulk_action=approve"
    Then the API status is 202
    And every capital distribution of my fund is approved

  # H38 — Happy path (P12, G18): bulk redeem units runs the units job per distribution and stamps units_job_finished_at
  Scenario: H38 Bulk redeem units
    Given there is a capital distribution payment for the fund
    And every capital distribution of my fund has unit prices
    When "me" sends POST "/capital_distributions/bulk_actions.json?fund_id={fund}&bulk_action=redeem units"
    Then the API status is 202
    And every capital distribution of my fund has units_job_finished_at set

  # H39 — Happy path (G16): the fund JSON carries its start and close dates
  Scenario: H39 Fund JSON has its dates
    Given my fund's start date is "2021-04-01" and first close date is "2021-06-30"
    When "me" sends GET "/funds/{fund}.json"
    Then the API answer at "start_date" is "2021-04-01"
    And the API answer at "first_close_date" is "2021-06-30"

  # H40 — Happy path (G17): call and distribution JSON say whether they are approved
  Scenario: H40 Call and distribution JSON carry approved
    Given there is a capital distribution payment for the fund
    When "me" sends GET "/capital_calls/{call}.json"
    Then the API answer at "approved" is "false"
    When "me" sends GET "/capital_distributions.json?fund_id={fund}"
    Then the API answer at "0.approved" is "false"

  # E43 — Edge case (P13 withdrawn, backward compatible): the template's currency columns are still saved on the distribution as custom fields, as before; a sheet without them still imports
  Scenario: E43 Distribution currency columns stay custom fields
    When I import "CapitalDistribution" rows into my fund:
      | Fund               | Title      | Income | Date       | Generate Payments | Payments Paid | Reinvestment | Folio No | Distribution Basis | Face Value For Redemption | Send Notification | From Currency | To Currency | Exchange Rate | As Of      |
      | Acme Growth Fund I | Q1 payout  | 1000   | 2026-04-05 | No                | No            | 0            |          |                    | 0                         | No                | USD           | INR         | 83.2          | 2026-04-05 |
    Then the import's status is "Completed"
    And the capital distribution "Q1 payout" has "83.2" in its custom fields
    When I import "CapitalDistribution" rows into my fund:
      | Fund               | Title      | Income | Date       | Generate Payments | Payments Paid | Reinvestment | Folio No | Distribution Basis | Face Value For Redemption | Send Notification |
      | Acme Growth Fund I | Q2 payout  | 1000   | 2026-07-05 | No                | No            | 0            |          |                    | 0                         | No                |
    Then the import's status is "Completed"
