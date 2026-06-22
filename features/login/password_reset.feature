Feature: Password Reset
  A user should be able to reset a forgotten password via the emailed link
  and sign in with the new password afterwards.

Scenario: Reset password successfully via emailed link
  Given there is a user "" for an entity "entity_type=Company"
  And I am at the login page
  When I request a password reset
  Then the user receives an email with "Reset password instructions" in the subject
  When I click on the link in the email "Change my password"
  And I set my new password to "NewPassw0rd!23"
  Then I should see the "Your password has been changed successfully. You are now signed in."
  And I should be able to log in with the password "NewPassw0rd!23"
