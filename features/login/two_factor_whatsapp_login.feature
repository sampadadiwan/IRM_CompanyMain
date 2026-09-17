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

  # Mirrors the SMS "number stops being textable" case: no code can go out, so the user is
  # told to contact an administrator instead of being shown "Code sent to +…" for a message
  # the job silently refused to send.
  Scenario Outline: A WhatsApp-mode user whose WhatsApp was switched off is told to contact an administrator
    Given there is a user "<user>" for an entity "<entity>"
    And the user has two-factor authentication enabled in whatsapp mode
    And the user's WhatsApp has been switched off by an administrator
    And I am at the login page
    When I submit the login page expecting to be refused
    Then I should see "We can't send a verification code to your phone right now"
    And no WhatsApp code should have been sent

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  Scenario Outline: Authenticator-mode user never sees the WhatsApp fallback button, even with WhatsApp enabled
    # Once a user has chosen the authenticator app, WhatsApp/SMS fallback buttons are not
    # offered on the login screen — app-only is the deliberate policy, not just the
    # no-WhatsApp default. See features/login/two_factor_sms.feature for the SMS equivalent.
    Given there is a user "<user>" for an entity "<entity>"
    And the user has two-factor authentication enabled and configured
    And the user has WhatsApp enabled
    And I am at the login page
    When I fill and submit the login page
    Then I should be on the 2FA verification page
    And I should not see "Send code via WhatsApp"

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
