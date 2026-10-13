@rack_test
Feature: Two-Factor Authentication with Magic Link
  Users with 2FA enabled must complete 2FA after clicking a magic link.

  Scenario Outline: User logs in via magic link and completes 2FA
    Given there is a user "<user>" for an entity "<entity>"
    And the user has two-factor authentication enabled and configured
    And I am at the login page without password
    When I fill and submit the login without password
    Then I should see the "<msg>"
    And the user receives an email with "<subject>" in the subject
    And when I click on the link in the email "<link>"
    Then I should be on the 2FA verification page
    When I enter a valid TOTP code
    Then I should see "Signed in successfully"

    Examples:
      |user | entity              | msg                                                                  | subject                          | link          |
      |     | entity_type=Company |If that address is registered, a login link is on its way.             | Login Link: Expires in 10 minutes | Click To Login|

  Scenario Outline: User without 2FA logs in via magic link normally
    Given there is a user "<user>" for an entity "<entity>"
    And I am at the login page without password
    When I fill and submit the login without password
    Then I should see the "<msg>"
    And the user receives an email with "<subject>" in the subject
    And when I click on the link in the email "<link>"
    Then I should see the "<login_msg>"
    And I should not be on the 2FA verification page

    Examples:
      |user | entity              | login_msg               | subject                          | link          | msg |
      |     | entity_type=Company |Signed in successfully   | Login Link: Expires in 10 minutes | Click To Login|If that address is registered, a login link is on its way.|
