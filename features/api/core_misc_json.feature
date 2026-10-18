Feature: Core and misc endpoints answer bearer-token callers in JSON
  The core / misc endpoints the Funds pack relies on (KYCs, KYC data, approval responses, access rights,
  valuations) answer a bearer-token caller in JSON where they used to crash (500) or redirect (302).
  The website's answers are unchanged.
  Reference: docs/modules/funds/funds_json_api.md

  Background:
    Given there is a user "first_name=Meera" for an entity "name=Acme Capital;entity_type=Investment Fund;enable_funds=true;currency=INR"
    And the user has role "company_admin"
    And there is an existing investor "" with "1" users
    And there is an existing investor "" with "1" users
    And there is a fund "name=Acme Growth Fund I;currency=INR" for the entity
    And the investors are added to the fund
    And there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And there is a capital call "percentage_called=20"
    And another firm "Beta Partners" has a fund with a commitment, a call and a remittance
    And I have an API token

  # ── Custom notifications ───────────────────────────────────────────────────

  # X51 — Error case: a KYC that fails validation answers 422 with its errors (was a NameError 500)
  Scenario: X51 A KYC failing validation answers 422 with errors
    Given I remember folio 1's investor
    And I note the InvestorKyc count
    When "me" sends POST "/investor_kycs.json" with:
      """
      {"validate": "true",
        "investor_kyc": {"investor_id": {folio1_investor}, "entity_id": {entity}, "kyc_type": "individual",
          "full_name": "Incomplete"}}
      """
    Then the API status is 422
    And the API answer has an error on "PAN"
    And the InvestorKyc count is unchanged

  # H31 — Happy path: a KYC reads as JSON (was a 500 on the missing pan_card_data column)
  Scenario: H31 A KYC reads as JSON
    Given folio 1's investor has an unverified KYC
    When "me" sends GET "/investor_kycs/{kyc}.json"
    Then the API status is 200
    And the API answer at "id" is "{kyc}"

  # H33 — Happy path: KYC data over the API answers JSON — KRA fetched (201), CKYC waiting for the OTP (202)
  Scenario: H33 KRA and CKYC data requests answer JSON instead of redirects
    Given folio 1's investor has an unverified KYC
    And the KRA service answers successfully
    When "me" sends POST "/kyc_datas.json" with:
      """
      {"kyc_data": {"investor_kyc_id": {kyc}, "entity_id": {entity}, "source": "kra", "PAN": "ABCDE1234F",
        "birth_date": "1990-01-01"}}
      """
    Then the API status is 201
    And the API answer at "status" is "kra_fetched"
    When "me" sends POST "/kyc_datas.json" with:
      """
      {"kyc_data": {"investor_kyc_id": {kyc}, "entity_id": {entity}, "source": "ckyc", "PAN": "ABCDE1234F",
        "phone": "9876543210"}}
      """
    Then the API status is 202
    And the API answer at "status" is "otp_required"
    And the API answer at "next" is present

  # ── Approvals ──────────────────────────────────────────────────────────────

  # H34 — Happy path: the investor's approve answers JSON (was a 302 to the approval page)
  Scenario: H34 An investor approves a response over the API
    Given my firm has two approvals on the fund
    And folio 1 has a pending response on the approval
    And "Lata" is the investor user of folio 1
    When "Lata" sends PATCH "/approval_responses/{approval_response}/approve.json?status=Approved"
    Then the API status is 200
    And the API answer is JSON
    And the status of ApprovalResponse "{approval_response}" is "Approved"

  # ── E-signatures, documents, folders, stamp papers ────────────────────────

  # H32 — Happy path: creating access rights answers 201 with the rows created (was a 500 after saving)
  Scenario: H32 Access rights created by API answer with the rows
    Given "Ravi" is an employee of my firm with no fund access
    And I remember the user "Ravi"
    When "me" sends POST "/access_rights.json" with:
      """
      {"access_right": {"owner_type": "Fund", "owner_id": {fund}, "access_type": "Fund", "user_id": [{ravi_id}],
        "permissions": ["read"], "notify": false}}
      """
    Then the API status is 201
    And the API answer is a list of 1 row
    And the API answer at "0.owner_id" is "{fund}"
    And my fund has an access right for the user "Ravi"

  # ── Investor notices, valuations, form fields ──────────────────────────────

  # E40 — Edge case: a PATCH without per_share_value keeps the price (it used to be set to 0)
  Scenario: E40 A valuation PATCH without a price keeps the price
    Given both firms have a portfolio instrument and my firm has a valuation of 1234 per share
    When "me" sends PATCH "/valuations/{valuation}.json" with:
      """
      {"valuation": {"valuation_date": "2026-07-31"}}
      """
    Then the API status is 200
    And the valuation_date of Valuation "{valuation}" is "2026-07-31"
    And the per_share_value_cents of Valuation "{valuation}" is "123400.0"
