@security @rack_test
Feature: A user's email cannot be changed once the user is created
  As a platform operator
  I want a user's email fixed after creation
  So that login, magic links, cross-region sync and investor access, which all key on it,
  cannot be re-pointed at someone else's mailbox

  Background:
    Given Im logged in as a user "first_name=Ravi;email=ravi@lockco.example" for an entity "name=Lock Co;entity_type=Investment Fund"
    And the user has role "company_admin"

  # E1 — Edge case: the users form (and JSON API) silently drop email, other fields still save
  Scenario: E1 Updating my user with a new email keeps the old email
    When I update my own user with email "attacker@evil.example" and first name "Ravindra"
    Then my user's email is still "ravi@lockco.example"
    And my user's first name is "Ravindra"

  # E2 — Edge case: Devise's account edit permits email by default; the model refuses it
  Scenario: E2 The account edit page cannot change my email
    When I submit the account edit form with email "attacker@evil.example"
    Then my user's email is still "ravi@lockco.example"

  # E3 — Edge case: a direct save is refused with an error, not dropped silently
  Scenario: E3 Saving a user with a changed email fails with an error
    When my user is saved with email "other@lockco.example"
    Then the save fails with "Email cannot be changed once the user is created"
    And my user's email is still "ravi@lockco.example"

  # E4 — Edge case: Devise's downcase/strip of a legacy mixed-case email is not a change
  Scenario: E4 A legacy mixed-case email does not block unrelated edits
    Given my user's email is stored as " Ravi@LockCo.example"
    When my user is saved with first name "Ravindra"
    Then the save succeeds
    And my user's email is still "ravi@lockco.example"
