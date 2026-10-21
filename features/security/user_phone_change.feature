@security @rack_test
Feature: Changing an existing mobile number needs a code emailed to the user
  As a platform operator
  I want an existing mobile number to change only after the user confirms an emailed code
  So that a hijacked session or a crafted request cannot re-point the number that receives
  SMS / WhatsApp sign-in codes

  # Rule (User#existing_phone_change_must_be_verified):
  #   no number    -> a number            free
  #   a number     -> a different number  emailed code (PhoneChangeStart / PhoneChangeConfirm)
  #   a number     -> none                emailed code
  #   a number     -> same, reformatted   free

  Background:
    Given Im logged in as a user "first_name=Ravi;email=ravi@phoneco.example;call_code=91;phone=9876543210" for an entity "name=Phone Co;entity_type=Investment Fund"
    And the user has role "company_admin"

  # PC-H1 — Happy path: request, receive the code by email, enter it, number changes
  Scenario: PC-H1 Changing my number with the emailed code
    When I ask to change the phone of "ravi@phoneco.example" to "9123456780" with call code "91"
    Then a phone change code is emailed to "ravi@phoneco.example"
    And the phone of "ravi@phoneco.example" is still "9876543210"
    When I enter the emailed code for "ravi@phoneco.example"
    Then I should see "Mobile number changed"
    And the phone of "ravi@phoneco.example" is "9123456780"
    And a "Your mobile number was changed" email is sent to "ravi@phoneco.example"

  # PC-H2 — Happy path: adding a first number needs no code
  Scenario: PC-H2 Adding a number to a user without one needs no code
    Given "ravi@phoneco.example" has no phone number yet
    When I update my own user with phone "9123456780" and call code "91"
    Then the phone of "ravi@phoneco.example" is "9123456780"

  # PC-H3 — Happy path: the screens offer the code path, not the plain field
  Scenario: PC-H3 The user page offers Change phone and the edit form locks the number
    When I visit the user page of "ravi@phoneco.example"
    Then I should see the change phone button
    When I visit the edit page of "ravi@phoneco.example"
    Then the phone fields are disabled

  # PC-E1 — Edge case: a wrong code is refused and counted
  Scenario: PC-E1 A wrong code leaves the number unchanged
    When I ask to change the phone of "ravi@phoneco.example" to "9123456780" with call code "91"
    And I enter a wrong code for "ravi@phoneco.example"
    Then I should see "That code is not correct. 4 attempts left."
    And the phone of "ravi@phoneco.example" is still "9876543210"

  # PC-E2 — Edge case: an expired code is refused
  Scenario: PC-E2 An expired code leaves the number unchanged
    When I ask to change the phone of "ravi@phoneco.example" to "9123456780" with call code "91"
    And the phone change code for "ravi@phoneco.example" has expired
    And I submit the emailed code for "ravi@phoneco.example"
    Then I should see "That code has expired"
    And the phone of "ravi@phoneco.example" is still "9876543210"

  # PC-E3 — Edge case: five wrong codes cancel the request; the right code is then refused
  Scenario: PC-E3 Too many wrong codes cancel the change
    When I ask to change the phone of "ravi@phoneco.example" to "9123456780" with call code "91"
    And I enter a wrong code for "ravi@phoneco.example" 5 times
    Then I should see "Too many wrong codes"
    When I submit the emailed code for "ravi@phoneco.example"
    Then I should see "There is no phone change waiting for a code"
    And the phone of "ravi@phoneco.example" is still "9876543210"

  # PC-E4 — Edge case: a second request within a minute is refused
  Scenario: PC-E4 Asking for another code too soon is refused
    When I ask to change the phone of "ravi@phoneco.example" to "9123456780" with call code "91"
    And I ask to change the phone of "ravi@phoneco.example" to "9123456781" with call code "91"
    Then I should see "Please wait a moment"
    And 1 phone change code is emailed to "ravi@phoneco.example"

  # PC-E5 — Edge case: a newer request supersedes the older code
  Scenario: PC-E5 A newer code makes the older one stop working
    When I ask to change the phone of "ravi@phoneco.example" to "9123456780" with call code "91"
    And the last phone change for "ravi@phoneco.example" was requested 2 minutes ago
    And I keep the emailed code for "ravi@phoneco.example"
    And I ask to change the phone of "ravi@phoneco.example" to "9123456781" with call code "91"
    And I submit the kept code for "ravi@phoneco.example"
    Then I should see "That code is not correct"
    And the phone of "ravi@phoneco.example" is still "9876543210"

  # PC-E6 — Edge case: an undiallable new number is refused before any code is sent
  Scenario: PC-E6 An invalid new number is refused
    When I ask to change the phone of "ravi@phoneco.example" to "12345" with call code "91"
    Then I should see "is not a valid phone number for country code +91"
    And 0 phone change codes are emailed to "ravi@phoneco.example"

  # PC-X1 — Error case: a crafted PATCH with a new number does not change it
  Scenario: PC-X1 A crafted update cannot change the number
    When I update my own user with phone "9123456780" and call code "91"
    Then the phone of "ravi@phoneco.example" is still "9876543210"

  # PC-X2 — Error case: a crafted PATCH cannot clear the number either
  Scenario: PC-X2 A crafted update cannot remove the number
    When I update my own user with phone "" and call code "91"
    Then the phone of "ravi@phoneco.example" is still "9876543210"

  # PC-X3 — Error case: a direct save is refused with an error; reformatting is not a change
  Scenario: PC-X3 Saving a changed number without the code fails
    When the user "ravi@phoneco.example" is saved with phone "9123456780"
    Then the phone save fails with "Phone can only be changed by confirming the code emailed to the user"
    And the phone of "ravi@phoneco.example" is still "9876543210"
    When the user "ravi@phoneco.example" is saved with phone "98765 43210"
    Then the phone save succeeds

  # PC-X4 — Error case: an admin's request emails the code to the TARGET, never the admin
  Scenario: PC-X4 An admin changing a colleague's number needs the colleague's code
    Given there is a colleague "first_name=Meera;email=meera@phoneco.example;call_code=91;phone=9811122233"
    When I ask to change the phone of "meera@phoneco.example" to "9123456780" with call code "91"
    Then a phone change code is emailed to "meera@phoneco.example"
    And 0 phone change codes are emailed to "ravi@phoneco.example"
    When I enter the emailed code for "meera@phoneco.example"
    Then the phone of "meera@phoneco.example" is "9123456780"

  # PC-X5 — Error case: cross-region sync is exempt; the origin region already checked
  Scenario: PC-X5 Sync can replicate a changed number
    When the user "ravi@phoneco.example" is synced with phone "9123456780"
    Then the phone of "ravi@phoneco.example" is "9123456780"
