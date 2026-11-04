Feature: Security L7 - persona switch by POST; no password in the failed sign-up redirect
  The persona picker submitted a GET, so any link or image could flip a signed-in user's persona.
  set_persona is now POST-only (form and route). A failed New User create redirects back with the
  permitted fields only, never the password (shared with C6).
  Design: docs/security/security_review_2026_10.md, "Authentication and session — Medium / Low", L7

  # L7-H — Happy path: the persona picker's POST switches the persona
  @security @rack_test
  Scenario: L7-H Switching persona by POST
    Given Im logged in as a user "" for an entity "entity_type=Company"
    And the user has role "employee,investor"
    And the user has curr role "employee"
    When I switch my persona to "investor"
    Then my persona is "investor"

  # L7-1 — Error case: a GET link to set_persona no longer switches the persona
  @security @rack_test
  Scenario: L7-1 A GET link cannot switch persona
    Given Im logged in as a user "" for an entity "entity_type=Company"
    And the user has role "employee,investor"
    And the user has curr role "employee"
    When a link opens "/users/set_persona?user[persona]=investor"
    Then my persona is "employee"

  # L7-2 — Error case: a failed New User create reopens the form without the password in the URL
  @security @rack_test
  Scenario: L7-2 A failed sign-up redirect carries no password
    Given Im logged in as a user "first_name=Gita" for an entity "name=Artha;entity_type=Investment Fund"
    And the user has role "company_admin"
    When I post a new user "l7-2@artha.example" with mismatched passwords
    Then the New User form is reopened without the password in the URL
    And no user "l7-2@artha.example" exists
