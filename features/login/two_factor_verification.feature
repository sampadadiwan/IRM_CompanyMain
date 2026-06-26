Feature: Two-Factor Authentication Verification
  Users with 2FA enabled must enter a TOTP code after password authentication.

  Scenario Outline: User logs in with password and completes 2FA
    Given there is a user "<user>" for an entity "<entity>"
    And the user has two-factor authentication enabled and configured
    And I am at the login page
    When I fill and submit the login page
    Then I should be on the 2FA verification page
    When I enter a valid TOTP code
    Then I should see "Signed in successfully"

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  Scenario Outline: User enters invalid TOTP code
    Given there is a user "<user>" for an entity "<entity>"
    And the user has two-factor authentication enabled and configured
    And I am at the login page
    When I fill and submit the login page
    Then I should be on the 2FA verification page
    When I enter an invalid TOTP code
    Then I should see "Invalid code"

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  Scenario Outline: User enters wrong TOTP code 3 times
    Given there is a user "<user>" for an entity "<entity>"
    And the user has two-factor authentication enabled and configured
    And I am at the login page
    When I fill and submit the login page
    Then I should be on the 2FA verification page
    When I enter an invalid TOTP code 3 times
    Then I should be redirected to the login page
    And I should see "Too many failed attempts"

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  Scenario Outline: User without 2FA logs in normally
    Given there is a user "<user>" for an entity "<entity>"
    And I am at the login page
    When I fill and submit the login page
    Then I should see "Signed in successfully"
    And I should not be on the 2FA verification page

    Examples:
      | user | entity              |
      |      | entity_type=Company |
