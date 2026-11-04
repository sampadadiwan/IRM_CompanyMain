Feature: Security C6 - who can create a user, and which grants a new user picks up
  The New User form posts to Devise registrations#create, which now authorizes the request with
  UserPolicy#create? (a company admin of the new user's firm, or support), never carries the
  password in a failed-create redirect, and links a new user only to unclaimed grants at the
  user's own firm. Admin-chosen initial passwords are kept (documented behaviour).
  Design: docs/security/security_review_2026_10.md, card "C6 — User creation"

  # C6-1 — Error case: an LP user cannot create users
  @security @rack_test
  Scenario: C6-1 An LP user posting the New User form is denied
    Given Im logged in as a user "first_name=Lakshmi" for an entity "name=Lakshmi Family;entity_type=Investor"
    When I post a new user "c6-1@lakshmi.example" with password "Secret#2026x"
    Then I am denied access
    And no user "c6-1@lakshmi.example" exists

  # C6-2 — Error case: an employee who is not a company admin cannot create users
  @security @rack_test
  Scenario: C6-2 A non-admin employee posting the New User form is denied
    Given Im logged in as a user "first_name=Esha" for an entity "name=Artha;entity_type=Investment Fund"
    When I post a new user "c6-2@artha.example" with password "Secret#2026x"
    Then I am denied access
    And no user "c6-2@artha.example" exists

  # C6-3 — Edge case: an advisor-firm account no longer claims another GP's unclaimed grant
  @security @rack_test
  Scenario: C6-3 A new advisor-firm user does not pick up another firm's unclaimed grant
    Given Im logged in as a user "first_name=Ana" for an entity "name=Advisory Co;entity_type=Investor Advisor"
    And the user has role "company_admin"
    And there is another tenant "Zeta Capital" with a fund "Zeta Fund"
    And there is an unclaimed grant for "claim@victim.example" at "Zeta Capital" on an LP firm "Mehta Family"
    When I post a new user "claim@victim.example" with password "Secret#2026x"
    Then the user "claim@victim.example" is created in my entity
    And the unclaimed grant is still unclaimed

  # C6-4 — Error case: a failed create reopens the form without the password in the URL
  @security @rack_test
  Scenario: C6-4 Mismatched passwords redirect back without the password
    Given Im logged in as a user "first_name=Gita" for an entity "name=Artha;entity_type=Investment Fund"
    And the user has role "company_admin"
    When I post a new user "c6-4@artha.example" with mismatched passwords
    Then the New User form is reopened without the password in the URL
    And no user "c6-4@artha.example" exists

  # C6-H — Happy path: a company admin creates a user with a password, who can then log in
  @security @rack_test
  Scenario: C6-H A company admin creates a user through the New User form
    Given Im logged in as a user "first_name=Gita" for an entity "name=Artha;entity_type=Investment Fund"
    And the user has role "company_admin"
    And I am at the users page
    When I create a new user "first_name=Ravi;email=ravi@artha.example"
    Then I should see the "User was successfully created."
    And an user should be created
    And the user "ravi@artha.example" can log in with password "password"

  # C6-H2 — Happy path: an LP-firm admin's new user picks up the unclaimed grant at their own firm
  @security @rack_test
  Scenario: C6-H2 A new user of an LP firm is linked to that firm's unclaimed grant
    Given Im logged in as a user "first_name=Kavya" for an entity "name=Kavya Family;entity_type=Investor"
    And the user has role "company_admin"
    And there is another tenant "Zeta Capital" with a fund "Zeta Fund"
    And there is an unclaimed grant for "rohan@kavya.example" at "Zeta Capital" on my firm
    When I post a new user "rohan@kavya.example" with password "Secret#2026x"
    Then the user "rohan@kavya.example" is created in my entity
    And the unclaimed grant is linked to the user "rohan@kavya.example"

  # C6-X — Exception: support can create a user without being a company admin
  @security @rack_test
  Scenario: C6-X Support creates a user
    Given Im logged in as a user "first_name=Sam" for an entity "name=Artha;entity_type=Investment Fund"
    And the user has role "support"
    When I post a new user "c6-x@artha.example" with password "Secret#2026x"
    Then the user "c6-x@artha.example" is created in my entity
    And the user "c6-x@artha.example" can log in with password "Secret#2026x"

  # C6-X2 — Edge case: a company admin posting another firm's entity_id still creates in their own firm
  @security @rack_test
  Scenario: C6-X2 A posted entity id is overwritten with the admin's own firm
    Given Im logged in as a user "first_name=Gita" for an entity "name=Artha;entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is another tenant "Zeta Capital" with a fund "Zeta Fund"
    When I post a new user "c6-x2@artha.example" for the entity "Zeta Capital"
    Then the user "c6-x2@artha.example" is created in my entity
