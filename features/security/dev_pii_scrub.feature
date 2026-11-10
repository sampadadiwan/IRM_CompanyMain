Feature: P1 - a production copy restored for development has its investors' personal data scrubbed
  EntitySetting.disable_all (step 4 of docs/operations/prod_restore.md) now also runs DevPiiScrubber, so every
  restored dump replaces PANs, bank account numbers, dates of birth, provider responses, identity custom fields and
  the same values in history. IFSC codes stay. The same real value becomes the same fake within a run, so
  duplicates and matching behave as in production. It refuses any database that isn't a local development/test one.
  Design: docs/security/owasp_2026_11_changes.md › "P1 — Scrub PII from production copies used for development"

  # P1-H — Happy path: every listed value is replaced, IFSC and ordinary fields are kept
  @security
  Scenario: P1-H The scrub replaces personal data and keeps the rest
    Given there is a user "first_name=Vikram" for an entity "name=Scrub Firm;entity_type=Investment Fund"
    And a scrub test KYC "Kumar Family Trust" with PAN "ABCPK1234F", bank account "50100123456789", IFSC "HDFC0001234" and birth date "1970-05-01"
    And its history records the PAN changing from "ABCPK1234E" to "ABCPK1234F"
    When the development PII scrub runs
    Then the KYC "Kumar Family Trust" no longer has PAN "ABCPK1234F" but has a PAN-shaped value with "P" as 4th letter
    And the KYC "Kumar Family Trust" no longer has bank account "50100123456789" but has 14 digits
    And the KYC "Kumar Family Trust" no longer has birth date "1970-05-01"
    And the KYC "Kumar Family Trust" still has IFSC "HDFC0001234" and its name
    And its history shows "[SCRUBBED]" for the PAN

  # P1-1 — Edge case: the same real PAN on two KYCs becomes the same fake, so duplicates still match
  @security
  Scenario: P1-1 The same PAN stays the same fake everywhere in one run
    Given there is a user "first_name=Vikram" for an entity "name=Scrub Firm;entity_type=Investment Fund"
    And a scrub test KYC "Holder One" with PAN "AAAPA1111A", bank account "111122223333", IFSC "SBIN0000001" and birth date "1980-01-01"
    And a scrub test KYC "Holder Two" with PAN "AAAPA1111A", bank account "999988887777", IFSC "SBIN0000001" and birth date "1981-01-01"
    When the development PII scrub runs
    Then the KYCs "Holder One" and "Holder Two" share the same new PAN

  # P1-2 — Edge case: identity custom fields are replaced, look-alike custom fields are kept
  @security
  Scenario: P1-2 Identity custom fields are scrubbed, look-alikes are not
    Given there is a user "first_name=Vikram" for an entity "name=Scrub Firm;entity_type=Investment Fund"
    And a scrub test KYC "Kumar Family Trust" with PAN "ABCPK1234F", bank account "50100123456789", IFSC "HDFC0001234" and birth date "1970-05-01"
    And the KYC "Kumar Family Trust" has custom fields "aadhaar_number=123412341234;passport_no=Z1234567;company_name=Kumar Holdings;pan_verified=yes"
    When the development PII scrub runs
    Then the KYC "Kumar Family Trust" custom field "aadhaar_number" is no longer "123412341234"
    And the KYC "Kumar Family Trust" custom field "passport_no" is no longer "Z1234567"
    And the KYC "Kumar Family Trust" custom field "company_name" is still "Kumar Holdings"
    And the KYC "Kumar Family Trust" custom field "pan_verified" is still "yes"

  # P1-X1 — Error case: the scrub refuses outside development / test
  @security
  Scenario: P1-X1 The scrub refuses a production environment
    When the development PII scrub is started with Rails.env "production"
    Then the PII scrub is refused with "only in development or test"

  # P1-3 — Happy path: disable_all (the restore guide's step 4) runs the scrub in development
  @security
  Scenario: P1-3 disable_all scrubs the restored copy
    Given there is a user "first_name=Vikram" for an entity "name=Scrub Firm;entity_type=Investment Fund"
    And a scrub test KYC "Kumar Family Trust" with PAN "ABCPK1234F", bank account "50100123456789", IFSC "HDFC0001234" and birth date "1970-05-01"
    When EntitySetting.disable_all runs in development
    Then the KYC "Kumar Family Trust" no longer has PAN "ABCPK1234F" but has a PAN-shaped value with "P" as 4th letter
    And every entity setting is in sandbox mode
