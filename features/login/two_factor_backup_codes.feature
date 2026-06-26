Feature: Two-Factor Authentication Backup Codes
  Users can use backup codes if they don't have access to their authenticator app.

  Scenario Outline: User logs in using a backup code
    Given there is a user "<user>" for an entity "<entity>"
    And the user has two-factor authentication enabled and configured with backup codes
    And I am at the login page
    When I fill and submit the login page
    Then I should be on the 2FA verification page
    When I enter a valid backup code
    Then I should see "Signed in successfully"
    And the backup code should be consumed

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  Scenario Outline: User enters an invalid backup code
    Given there is a user "<user>" for an entity "<entity>"
    And the user has two-factor authentication enabled and configured with backup codes
    And I am at the login page
    When I fill and submit the login page
    Then I should be on the 2FA verification page
    When I enter an invalid backup code
    Then I should see "Invalid code"

    Examples:
      | user | entity              |
      |      | entity_type=Company |
