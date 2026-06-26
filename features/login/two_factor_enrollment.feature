Feature: Two-Factor Authentication Enrollment
  Users with 2FA enabled need to set up their authenticator app before first use.

  Scenario Outline: User enrolls in 2FA for the first time
    Given there is a user "<user>" for an entity "<entity>"
    And the user has two-factor authentication enabled but not configured
    And I am at the login page
    When I fill and submit the login page
    Then I should be on the 2FA enrollment page
    And I should see a QR code for setup
    When I enter a valid TOTP code and confirm
    Then I should see backup codes
    And the user should have 2FA enabled

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  Scenario Outline: User enters invalid code during enrollment
    Given there is a user "<user>" for an entity "<entity>"
    And the user has two-factor authentication enabled but not configured
    And I am at the login page
    When I fill and submit the login page
    Then I should be on the 2FA enrollment page
    When I enter an invalid TOTP code and confirm
    Then I should see "Invalid code"
    And I should still be on the enrollment page

    Examples:
      | user | entity              |
      |      | entity_type=Company |
