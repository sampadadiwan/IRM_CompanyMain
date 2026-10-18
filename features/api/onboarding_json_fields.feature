Feature: JSON the client-onboarding agent needs
  The onboarding agent drives imports over the website's own .json endpoints with a bearer token.
  It needs each import's outcome, the entity's settings (sandbox) and a JSON reply when imported
  data is deleted. All three are additive: existing fields and the website are unchanged.
  Requests: docs/modules/ai/client_onboarding/api_requests_for_funds_api.md (G8–G10)
  Reference: docs/modules/funds/funds_json_api.md

  Background:
    Given there is a user "first_name=Meera" for an entity "name=Acme Capital;entity_type=Investment Fund;enable_funds=true;currency=INR"
    And the user has role "company_admin"
    And the entity has "enable_import_uploads" permission
    And there is an existing investor "" with "1" users
    And there is a fund "name=Acme Growth Fund I;currency=INR" for the entity
    And the investors are added to the fund
    And there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And there is a capital call "percentage_called=20"
    And another firm "Beta Partners" has a fund with a commitment, a call and a remittance
    And I have an API token

  # H16 — Happy path: an import upload's JSON reports total / processed / failed rows, created fields and the results file
  Scenario: H16 An import upload reports its outcome
    Given my fund has an import upload of 10 rows with 2 failed and a results file
    When "me" sends GET "/import_uploads/{import_upload}.json"
    Then the API status is 200
    And the API answer at "total_rows_count" is "10"
    And the API answer at "processed_row_count" is "8"
    And the API answer at "failed_row_count" is "2"
    And the API answer at "custom_fields_created" is "Source;Region"
    And the API answer at "results_url" is present
    And the API answer at "import_type" is "CapitalCommitment"

  # E23 — Edge case: a pending upload has zero counts and a null results_url, other fields as before
  Scenario: E23 A pending import upload has no results file yet
    Given my fund has a pending import upload
    When "me" sends GET "/import_uploads/{import_upload}.json"
    Then the API status is 200
    And the API answer at "failed_row_count" is "0"
    And the API answer at "results_url" is null

  # H17 — Happy path: the entity's company admin sees its settings, including sandbox
  Scenario: H17 A company admin sees the entity's settings
    Given my firm is in sandbox mode with sandbox emails "ops@acme.test"
    When "me" sends GET "/entities/{entity}.json"
    Then the API status is 200
    And the API answer at "entity_setting.sandbox" is "true"
    And the API answer at "entity_setting.sandbox_emails" is "ops@acme.test"
    And the API answer at "name" is "Acme Capital"

  # E22 — Edge case: an employee who cannot update the entity does not see its settings
  Scenario: E22 A plain employee does not see the entity's settings
    Given my firm is in sandbox mode with sandbox emails "ops@acme.test"
    And "Nina" is an employee of my firm with no fund access
    When "Nina" sends GET "/entities/{entity}.json"
    Then the API status is 200
    And the API answer has no "entity_setting"

  # X27 — Error case: another firm's user never sees this entity's settings
  Scenario: X27 Another firm's entity shows no settings
    When "me" sends GET "/entities/{beta_entity}.json"
    Then the API answer has no "entity_setting"

  # H18 — Happy path: deleting imported data by API answers 202 deletion_started and starts the job
  Scenario: H18 Deleting imported data by API answers JSON
    Given my fund has an import upload of 10 rows with 2 failed and a results file
    And import data deletion jobs are watched
    When "me" sends DELETE "/import_uploads/{import_upload}/delete_data.json"
    Then the API status is 202
    And the API answer at "status" is "deletion_started"
    And the API answer at "id" is "{import_upload}"
    And an import data deletion job was started for the upload

  # E24 — Edge case: the website's Delete data keeps its redirect and notice
  @rack_test
  Scenario: E24 The website's delete data is unchanged
    Given my fund has an import upload of 10 rows with 2 failed and a results file
    And import data deletion jobs are watched
    And I am signed in as the current user
    When I delete the import upload's data from the website
    Then I should see "Imported data deletion started"
    And an import data deletion job was started for the upload

  # X26 — Error case: another firm's upload cannot have its data deleted; no job starts
  Scenario: X26 Another firm's imported data cannot be deleted
    Given "Beta Partners" has an import upload
    And import data deletion jobs are watched
    When "me" sends DELETE "/import_uploads/{beta_import_upload}/delete_data.json"
    Then the API status is 403
    And no import data deletion job was started
