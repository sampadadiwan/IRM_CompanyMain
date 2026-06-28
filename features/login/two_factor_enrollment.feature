Feature: Two-Factor Authentication Enrollment
  Users with 2FA enabled choose a mode (Authenticator or WhatsApp) before first use.

  Scenario Outline: User sees mode selection on first login with 2FA enabled
    Given there is a user "<user>" for an entity "<entity>"
    And the user has two-factor authentication enabled but not configured
    And I am at the login page
    When I fill and submit the login page
    Then I should be on the 2FA mode selection page

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  Scenario Outline: User enrolls via Authenticator mode
    Given there is a user "<user>" for an entity "<entity>"
    And the user has two-factor authentication enabled but not configured
    And I am at the login page
    When I fill and submit the login page
    Then I should be on the 2FA mode selection page
    When I select the Authenticator mode
    Then I should be on the 2FA enrollment page
    And I should see a QR code for setup
    When I enter a valid TOTP code and confirm
    Then I should see backup codes
    And the user should have 2FA enabled in authenticator mode

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  Scenario Outline: User enters invalid code during Authenticator enrollment
    Given there is a user "<user>" for an entity "<entity>"
    And the user has two-factor authentication enabled but not configured
    And I am at the login page
    When I fill and submit the login page
    Then I should be on the 2FA mode selection page
    When I select the Authenticator mode
    Then I should be on the 2FA enrollment page
    When I enter an invalid TOTP code and confirm
    Then I should see "Invalid code"
    And I should still be on the enrollment page

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  @stub-whatsapp
  Scenario Outline: User enrolls via WhatsApp mode
    Given there is a user "<user>" for an entity "<entity>"
    And the user has two-factor authentication enabled but not configured
    And the user has WhatsApp enabled
    And I am at the login page
    When I fill and submit the login page
    Then I should be on the 2FA mode selection page
    And I should see the WhatsApp mode option
    When I select the WhatsApp mode
    Then I should be on the WhatsApp 2FA enrollment page
    When I enter the WhatsApp OTP to confirm enrollment
    Then I should see "Two-factor authentication via WhatsApp is now enabled"
    And the user should have 2FA enabled in whatsapp mode

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  Scenario Outline: WhatsApp mode option is not shown when WhatsApp is not enabled
    Given there is a user "<user>" for an entity "<entity>"
    And the user has two-factor authentication enabled but not configured
    And I am at the login page
    When I fill and submit the login page
    Then I should be on the 2FA mode selection page
    And I should not see the WhatsApp mode option

    Examples:
      | user | entity              |
      |      | entity_type=Company |
