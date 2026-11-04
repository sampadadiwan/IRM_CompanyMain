Feature: Web sessions expire - 2026-10 security review (N7)
  N7 was raised as "a saved session cookie never expires on the server". It does: the session cookie
  expires 60 minutes after the last request (config/initializers/session_store.rb expire_after),
  enforced by the server through the cookie's signed expiry, so a copied cookie stops working.
  This scenario pins that behaviour. Design: docs/security/security_review_2026_10.md (N7).

  Background:
    Given Im logged in as a user "first_name=Nia" for an entity "name=Artha;entity_type=Investment Fund"
    And the user has role "company_admin"

  # N7-X — Edge case: a copied session cookie, replayed with no Expires, works at 59 minutes and is refused by the server at 61
  @security @rack_test
  Scenario: N7-X A copied session cookie stops signing in 60 minutes after it was issued
    When I keep a copy of my session cookie
    And I replay the copied session cookie 59 minutes later
    Then I am still signed in
    When I replay the copied session cookie 2 minutes later
    Then I am sent to sign in
