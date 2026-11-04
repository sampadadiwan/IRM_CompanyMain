Feature: Security L8 - KYC and bank PII is filtered from logs
  Request logs, exception mail and ActiveRecord #inspect now show [FILTERED] for PAN, IFSC, date
  of birth, bank account numbers, Aadhaar, passport and the KYC document data fields. The short
  keys are anchored so a bare "pan" does not also hide company_name and the like.
  Design: docs/security/security_review_2026_10.md, "Authentication and session — Medium / Low", L8

  # L8-H — Happy path: every PII key is filtered, and an investor's PAN is hidden from inspect
  @security
  Scenario: L8-H PII keys are filtered
    Then the log filter hides the values of:
      | key                  |
      | pan                  |
      | ifsc_code            |
      | birth_date           |
      | bank_account_number  |
      | aadhaar_number       |
      | pan_card_data        |
      | address_proof_data   |
      | bank_routing_info    |
      | virtual_bank_account |
      | passport_number      |
    And an investor's inspect hides the PAN "ABCDE1234F"

  # L8-1 — Edge case: keys that merely contain "pan" or "birth_date" stay visible
  @security
  Scenario: L8-1 Look-alike keys stay visible
    Then the log filter keeps the values of:
      | key                 |
      | company_name        |
      | company_id          |
      | span                |
      | pan_verified        |
      | birth_date_verified |
      | call_code           |
