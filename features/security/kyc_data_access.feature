Feature: CKYC and KRA data access - 2026-10 security review (C7)
  CKYC / KRA rows hold an investor's PAN, addresses and the paid lookups made for them. They are
  now authorized against the KYC they belong to: the comparison screen opens for the users who can
  open that KYC, and re-fetching, OTPs and deletes need the edit right on it. Each refusal is paired
  with the legitimate use that must keep working.
  Design and worked examples: docs/security/security_review_2026_10.md#c7--ckyc--kra-data

  Background:
    Given Im logged in as a user "first_name=Gita" for an entity "name=Artha;entity_type=Investment Fund"
    And the user has role "company_admin"
    And CKYC and KRA are enabled for the entity with a valid FI code
    And the CKYC and KRA services are stubbed
    And the KYC "ABCDE1234F" of my firm has CKYC and KRA data

  # C7-1 — Edge case: another firm cannot open the CKYC/KRA comparison of this firm's KYC
  @security @rack_test
  Scenario: C7-1 Another firm's admin opening the CKYC and KRA comparison is refused
    Given I am signed in as a company admin of another firm "Zeta Capital"
    When I open the CKYC and KRA comparison of the KYC
    Then I am denied access
    And the KYC's PAN is not in the response
    And no CKYC or KRA service was called

  # C7-2 — Edge case: another firm cannot trigger a paid KRA re-fetch on this firm's data
  @security @rack_test
  Scenario: C7-2 Another firm's admin re-fetching the KRA data is refused
    Given I am signed in as a company admin of another firm "Zeta Capital"
    When I ask to re-fetch the KYC's KRA data
    Then I am denied access
    And the KYC's PAN is not in the response
    And no CKYC or KRA service was called

  # C7-3 — Edge case: another firm cannot send a CKYC OTP to this firm's investor
  @security @rack_test
  Scenario: C7-3 Another firm's admin sending a CKYC OTP is refused
    Given I am signed in as a company admin of another firm "Zeta Capital"
    When I ask to send a CKYC OTP for the KYC's CKYC data
    Then I am denied access
    And the KYC's PAN is not in the response
    And no CKYC or KRA service was called

  # C7-4 — Edge case: another firm cannot delete this firm's KRA data
  @security @rack_test
  Scenario: C7-4 Another firm's admin deleting the KRA data is refused
    Given I am signed in as a company admin of another firm "Zeta Capital"
    When I ask to delete the KYC's "KRA" data
    Then I am denied access
    And the KYC's "KRA" data still exists
    And no CKYC or KRA service was called

  # C7-5 — Edge case: an employee whose KYC list hides the KYC (fund F only, KYC only in fund G) cannot open its comparison
  @security @rack_test
  Scenario: C7-5 An employee limited to fund F cannot compare a KYC committed only to fund G
    Given the KYC is committed only to my fund "Artha G"
    And a second KYC "PQRST6789K" of my firm with CKYC and KRA data is committed to my fund "Artha F"
    And I am signed in as an employee of my firm with access to the fund "Artha F" only
    When I open the CKYC and KRA comparison of the KYC
    Then I am denied access
    And the KYC's PAN is not in the response
    But I can open the CKYC and KRA comparison of the second KYC

  # C7-H — Happy path: the KYC firm's admin compares, re-fetches and downloads with an OTP
  @security @rack_test
  Scenario: C7-H The firm's company admin compares, re-fetches and downloads CKYC with an OTP
    Then I can open the CKYC and KRA comparison of the KYC
    And I can re-fetch the KYC's KRA data
    And I can download the KYC's CKYC data with an OTP

  # C7-H2 — Happy path: an employee with KYC create and update rights does the same
  @security @rack_test
  Scenario: C7-H2 An employee with KYC create and update rights compares, re-fetches and downloads CKYC
    Given I am signed in as an employee of my firm with KYC create and update rights
    Then I can open the CKYC and KRA comparison of the KYC
    And I can re-fetch the KYC's KRA data
    And I can download the KYC's CKYC data with an OTP

  # C7-X — Edge case: a successful fetch is kept even for the firm's admin; a failed one can still be deleted
  @security @rack_test
  Scenario: C7-X The firm's admin cannot delete a successful CKYC fetch but can delete a failed KRA fetch
    Given the KYC's CKYC data is a successful fetch
    When I ask to delete the KYC's "CKYC" data
    Then I am denied access
    And the KYC's "CKYC" data still exists
    When I ask to delete the KYC's "KRA" data
    Then the KYC's "KRA" data is deleted
