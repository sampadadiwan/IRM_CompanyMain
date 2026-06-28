@stub-whatsapp
Feature: Two-Factor Authentication via WhatsApp at Login
  Users enrolled in WhatsApp mode receive an OTP automatically on login.

  Scenario Outline: User with WhatsApp 2FA logs in and verifies via WhatsApp code
    Given there is a user "<user>" for an entity "<entity>"
    And the user has two-factor authentication enabled in whatsapp mode
    And I am at the login page
    When I fill and submit the login page
    Then I should be on the 2FA verification page
    And I should see "Code sent to"
    When I enter the WhatsApp OTP to verify
    Then I should see "Signed in successfully"

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  Scenario Outline: User with WhatsApp 2FA enters wrong code
    Given there is a user "<user>" for an entity "<entity>"
    And the user has two-factor authentication enabled in whatsapp mode
    And I am at the login page
    When I fill and submit the login page
    Then I should be on the 2FA verification page
    When I enter an invalid TOTP code
    Then I should see "Invalid code"

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  Scenario Outline: Authenticator-mode user with WhatsApp enabled sees optional WhatsApp button
    Given there is a user "<user>" for an entity "<entity>"
    And the user has two-factor authentication enabled and configured
    And the user has WhatsApp enabled
    And I am at the login page
    When I fill and submit the login page
    Then I should be on the 2FA verification page
    And I should see "Send code via WhatsApp"

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  Scenario Outline: Authenticator-mode user without WhatsApp does not see WhatsApp button
    Given there is a user "<user>" for an entity "<entity>"
    And the user has two-factor authentication enabled and configured
    And I am at the login page
    When I fill and submit the login page
    Then I should be on the 2FA verification page
    And I should not see "Send code via WhatsApp"

    Examples:
      | user | entity              |
      |      | entity_type=Company |
