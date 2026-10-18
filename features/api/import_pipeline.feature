Feature: Import pipeline, entity settings and totals — fixes from the Orios onboarding trial
  An API client (the client-onboarding agent) onboards a fund only through the website's .json
  endpoints. What it needs: to see an import's outcome and why rows failed, dates read the way the
  app is configured, a fund import that works, entity settings it can read and update safely,
  rolled-up totals that match their remittances, and JSON answers. Existing behaviour that works
  is unchanged.
  Findings: docs/modules/ai/client_onboarding/api_improvements_from_orios_trial.md (P1–P10)
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
    And I have an API token

  # H20 — Happy path (P1): every row fails — outcome "failed", the first failure's row and message in row_errors; status unchanged
  Scenario: H20 An import where every row fails says so
    When I import "CapitalCall" rows into my fund:
      | Fund *       | Name *  | Percentage Called * | Call Date * | Due Date *  | Call Basis               |
      | No Such Fund | Call A  | 10                  | 2026-04-01  | 2026-05-01  | Percentage of Commitment |
      | No Such Fund | Call B  | 10                  | 2026-04-01  | 2026-05-01  | Percentage of Commitment |
    And "me" sends GET "/import_uploads/{import_upload}.json"
    Then the API status is 200
    And the API answer at "outcome" is "failed"
    And the API answer at "failed_row_count" is "2"
    And the API answer at "row_errors.0.row" is "2"
    And the API answer at "row_errors.0.message" is present
    And the import's status is "Completed"

  # H21 — Happy path (P1): some rows import, some fail — outcome "partially_failed"
  Scenario: H21 A partly failed import says so
    When I import "CapitalCall" rows into my fund:
      | Fund *             | Name *     | Percentage Called * | Call Date * | Due Date *  | Call Basis               |
      | Acme Growth Fund I | Good call  | 10                  | 2026-04-01  | 2026-05-01  | Percentage of Commitment |
      | No Such Fund       | Bad call   | 10                  | 2026-04-01  | 2026-05-01  | Percentage of Commitment |
    And "me" sends GET "/import_uploads/{import_upload}.json"
    Then the API answer at "outcome" is "partially_failed"
    And the API answer at "row_errors.0.row" is "3"

  # E25 — Edge case (P1): an upload still being processed is "running"
  Scenario: E25 A running import says running
    Given my fund has a running import upload
    When "me" sends GET "/import_uploads/{import_upload}.json"
    Then the API answer at "outcome" is "running"

  # E26 — Edge case (P1): only the first N failed rows are kept on the upload (N = 20; 2 here)
  Scenario: E26 Row errors are capped
    Given an upload keeps at most 2 row errors
    When I import "CapitalCall" rows into my fund:
      | Fund *       | Name *  | Percentage Called * | Call Date * | Due Date *  | Call Basis               |
      | No Such Fund | Call A  | 10                  | 2026-04-01  | 2026-05-01  | Percentage of Commitment |
      | No Such Fund | Call B  | 10                  | 2026-04-01  | 2026-05-01  | Percentage of Commitment |
      | No Such Fund | Call C  | 10                  | 2026-04-01  | 2026-05-01  | Percentage of Commitment |
    And "me" sends GET "/import_uploads/{import_upload}.json"
    Then the API answer at "failed_row_count" is "3"
    And the API answer at "row_errors.1.row" is "3"
    And the API answer at "row_errors.2" is null

  # H22 — Happy path (P2): a text date is read in the uploader's language, as their screens show dates — unchanged behaviour
  Scenario: H22 Text dates follow the uploader's language
    When I import "CapitalCall" rows into my fund on a thread left in locale "en":
      | Fund *             | Name *        | Percentage Called * | Call Date * | Due Date *  | Call Basis               |
      | Acme Growth Fund I | April call    | 10                  | 05/04/2026  | 05/05/2026  | Percentage of Commitment |
    Then the capital call "April call" has call date "2026-04-05"
    When I import "CapitalCall" rows into my fund on a thread left in locale "en-US":
      | Fund *             | Name *        | Percentage Called * | Call Date * | Due Date *  | Call Basis               |
      | Acme Growth Fund I | May call      | 10                  | 05/04/2026  | 06/04/2026  | Percentage of Commitment |
    Then the capital call "May call" has call date "2026-05-04"

  # E27 — Edge case (P2): an ISO date is read unambiguously
  Scenario: E27 ISO dates are always accepted
    When I import "CapitalCall" rows into my fund:
      | Fund *             | Name *     | Percentage Called * | Call Date * | Due Date *  | Call Basis               |
      | Acme Growth Fund I | ISO call   | 10                  | 2026-04-05  | 2026-05-05  | Percentage of Commitment |
    Then the import of 1 row processed 1 and failed 0
    And the capital call "ISO call" has call date "2026-04-05"

  # X28 — Error case (P2): an impossible date fails that row with the expected format named
  Scenario: X28 An impossible date names the expected format
    When I import "CapitalCall" rows into my fund:
      | Fund *             | Name *     | Percentage Called * | Call Date * | Due Date *  | Call Basis               |
      | Acme Growth Fund I | Bad date   | 10                  | 45/45/2026  | 2026-05-05  | Percentage of Commitment |
    And "me" sends GET "/import_uploads/{import_upload}.json"
    Then the API answer at "outcome" is "failed"
    And the API answer at "row_errors.0.message" is present

  # H23 — Happy path (P3): a fund import creates the fund (every row used to fail "wrong number of arguments")
  Scenario: H23 Fund import works
    When I import "Fund" rows into my firm:
      | Name        | Currency | Unit Types | Commitment Doc List | Tag List | Details | Fund Signatory Emails | Show Fund Ratios To Lps | Show Fund Portfolios To Lps |
      | Orios Fund  | INR      | A          |                     |          | Trial   |                       | No                      | No                          |
    Then the import of 1 row processed 1 and failed 0

  # E28 — Edge case (P3): every importer's save_row takes the arguments ImportUtil passes
  Scenario: E28 Every importer accepts process_row's arguments
    Then every importer's save_row accepts the four arguments process_row passes

  # H24 — Happy path (P5): a PATCH of entity settings without an id updates the one row, not a second
  Scenario: H24 Settings PATCH without an id updates the existing row
    When "me" sends PATCH "/entities/{entity}.json" with:
      """
      {"entity": {"entity_setting_attributes": {"sandbox": true, "sandbox_emails": "ops@acme.test"}}}
      """
    Then the API status is 200
    And my firm has exactly one settings row with sandbox on

  # E29 — Edge case (P5): the entity JSON names the settings row's id
  Scenario: E29 Entity JSON shows the settings id
    When "me" sends GET "/entities/{entity}.json"
    Then the API answer at "entity_setting.id" is my firm's settings row id

  # H25 — Happy path (P5): the dedupe keeps the row the app reads, deletes the extra, adds the unique index
  Scenario: H25 Duplicate settings rows are cleaned up
    Given my firm has a duplicate settings row from before the fix
    When support runs the settings dedupe with EXECUTE=1
    Then only the settings row the app was reading remains, and the unique index is back

  # H26 — Happy path (P6): after a bulk verify the fund, call and commitment totals equal their verified remittances
  Scenario: H26 Bulk verify leaves totals equal to the sums
    Given every remittance of the call is paid in full but unverified
    When "me" sends POST "/capital_remittances/bulk_actions.json?capital_call_id={call}&bulk_action=verify"
    Then every remittance of the call is verified
    And the fund, call and commitment collected totals equal their verified remittances

  # E30 — Edge case (P6): a second verify on the same remittances toggles back; totals still equal the sums
  Scenario: E30 A repeated bulk verify keeps totals right
    Given every remittance of the call is paid in full but unverified
    When "me" sends POST "/capital_remittances/bulk_actions.json?capital_call_id={call}&bulk_action=verify"
    And "me" sends POST "/capital_remittances/bulk_actions.json?capital_call_id={call}&bulk_action=verify"
    Then the fund, call and commitment collected totals equal their verified remittances

  # H27 — Happy path (P6): recompute totals re-sums a drifted fund
  Scenario: H27 Recompute fixes drifted totals
    Given every remittance of the call is paid in full but unverified
    And "me" sends POST "/capital_remittances/bulk_actions.json?capital_call_id={call}&bulk_action=verify"
    And the fund's collected total has drifted
    When "me" sends PATCH "/funds/{fund}/recompute_totals.json"
    Then the API status is 202
    And the API answer at "status" is "recompute_queued"
    And the fund, call and commitment collected totals equal their verified remittances

  # X29 — Error case (P6): an employee who cannot edit the fund cannot recompute its totals
  Scenario: X29 Recompute needs edit access to the fund
    Given "Nina" is an employee of my firm with no fund access
    When "Nina" sends PATCH "/funds/{fund}/recompute_totals.json"
    Then the API status is 403

  # H28 — Happy path (P7): with exactly one commitment form type, a blank Form Tag uses it
  Scenario: H28 A blank Form Tag uses the only form type
    Given my firm has CapitalCommitment form types tagged "Default"
    When I import "CapitalCommitment" rows into my fund:
      | Fund *             | Stakeholder *      | KYC Investing Entity | Folio No * | Committed Amount (Folio Currency) * | Committed Amount (Fund Currency) | Folio Currency * | Unit Type | Fund Close  | Onboarding Completed | Notes | Commitment Date * | Investor Signatory Emails | From Currency | To Currency | Exchange Rate | As Of | Update Only | Form Tag |
      | Acme Growth Fund I | {first_investor}   |                      | ORI-055    | 1000000                             |                                  | INR              |           | First Close | No                   |       | 2026-04-05        |                           |               |             |               |       | No          |          |
    Then the import of 1 row processed 1 and failed 0
    And a commitment with folio "ORI-055" exists in my fund

  # X30 — Error case (P7): with several form types and no Form Tag, the row error says which tags to use
  Scenario: X30 A blank Form Tag with several form types names them
    Given my firm has CapitalCommitment form types tagged "Default, Feeder"
    When I import "CapitalCommitment" rows into my fund:
      | Fund *             | Stakeholder *      | KYC Investing Entity | Folio No * | Committed Amount (Folio Currency) * | Committed Amount (Fund Currency) | Folio Currency * | Unit Type | Fund Close  | Onboarding Completed | Notes | Commitment Date * | Investor Signatory Emails | From Currency | To Currency | Exchange Rate | As Of | Update Only | Form Tag |
      | Acme Growth Fund I | {first_investor}   |                      | ORI-056    | 1000000                             |                                  | INR              |           | First Close | No                   |       | 2026-04-05        |                           |               |             |               |       | No          |          |
    And "me" sends GET "/import_uploads/{import_upload}.json"
    Then the API answer at "row_errors.0.message" is "Error Form Tag not specified. Set Form Tag to one of: Default, Feeder."

  # H29 — Happy path (P8): an investor upload without the optional Tags / City / Sector columns imports
  Scenario: H29 Optional columns may be left out
    When I import "Investor" rows into my firm:
      | Name *      | Primary Email *   | Category *  |
      | Orios LP 1  | lp1@orios.example | Co-Investor |
    Then the import of 1 row processed 1 and failed 0

  # X31 — Error case (P8): a required column is still required
  Scenario: X31 A missing required column is still refused
    When I import "Investor" rows into my firm:
      | Name *      | Primary Email *   |
      | Orios LP 2  | lp2@orios.example |
    Then the import's status starts with "Column(s) not found: Category"

  # E31 — Edge case (P8): a single-currency capital-call workbook with no Exchange Rates sheet imports
  Scenario: E31 No Exchange Rates sheet is read as no rates
    When I import "CapitalCall" rows into my fund:
      | Fund *             | Name *       | Percentage Called * | Call Date * | Due Date *  | Call Basis               |
      | Acme Growth Fund I | No rates     | 10                  | 2026-04-05  | 2026-05-05  | Percentage of Commitment |
    Then the import of 1 row processed 1 and failed 0

  # H30 — Happy path (P9): a bulk action by API answers 202 queued, not a redirect
  Scenario: H30 Bulk actions answer JSON
    When "me" sends POST "/capital_remittances/bulk_actions.json?capital_call_id={call}&bulk_action=verify"
    Then the API status is 202
    And the API answer at "status" is "queued"
    And the API answer at "count" is "2"

  # E32 — Edge case (P10): support can still set feature flags
  Scenario: E32 Support can set feature flags
    Given my firm's "enable_evergreen_funds" feature flag starts off
    And "Suresh" is a support user of my firm
    When "Suresh" sends PATCH "/entities/{entity}.json" with:
      """
      {"entity": {"permissions": ["enable_evergreen_funds"]}}
      """
    Then my firm's "enable_evergreen_funds" feature flag is on

  # E33 — Edge case (P1, review item 3): every row imported with a warning status is "succeeded", the warning shown separately
  Scenario: E33 A successful import with a warning is succeeded
    Given my fund has an import upload that imported every row with the status "Payments imported, but some remittances were not marked Verified"
    When "me" sends GET "/import_uploads/{import_upload}.json"
    Then the API answer at "outcome" is "succeeded"
    And the API answer at "warning" is "Payments imported, but some remittances were not marked Verified"
    And the API answer at "row_errors" is "[]"
