Feature: Resetting the two-factor method
  A user's two-factor METHOD (Authenticator / WhatsApp / SMS) can be cleared back to
  "none" — by the user from their profile, or by a company admin from the user's page —
  so a fresh method is chosen at the next sign-in. Two-factor itself is never switched
  off by a reset. See docs/technical/two_factor_authentication.md.

  Scenario Outline: User changes their own two-factor method after re-entering their password
    Given there is a user "<user>" for an entity "<entity>"
    And the user has two-factor authentication enabled and configured with backup codes
    And I am at the login page
    When I fill and submit the login page
    Then I should be on the 2FA verification page
    When I enter a valid TOTP code
    Then I should see "Signed in successfully"
    When I visit my own user page
    Then I should see the two-factor method badge "Authenticator"
    And I should see the "Change 2FA Method" two-factor button
    When I open the reset two-factor modal
    Then the reset modal should warn me about the consequences of a self reset
    And the reset submit button should be disabled
    When I confirm the self-service reset with password "password"
    Then I should be redirected to the login page
    And I should see "Your two-factor method has been reset"
    And the user should have no two-factor method but two-factor still enabled
    And the user should have received a two-factor reset email
    When I fill and submit the login page
    Then I should be on the 2FA mode selection page
    And I should see the two-factor reset banner
    When I select the Authenticator mode
    Then I should be on the 2FA enrollment page
    When I enter a valid TOTP code and confirm
    Then I should see backup codes
    And the user should have 2FA enabled in authenticator mode

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  Scenario Outline: A wrong password refuses the self-service reset
    Given there is a user "<user>" for an entity "<entity>"
    And the user has two-factor authentication enabled and configured
    And I am at the login page
    When I fill and submit the login page
    Then I should be on the 2FA verification page
    When I enter a valid TOTP code
    Then I should see "Signed in successfully"
    When I visit my own user page
    And I open the reset two-factor modal
    And I confirm the self-service reset with password "wrong-password"
    Then I should see "The password you entered is incorrect"
    And the user should still be in authenticator mode

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  @stub-whatsapp
  Scenario Outline: A company admin resets a colleague's WhatsApp method and they re-enroll on next login
    Given there is a user "<user>" for an entity "<entity>"
    And the user is a company admin
    And there is a colleague "<colleague>" in the same entity using WhatsApp two-factor
    And I am at the login page
    When I fill and submit the login page
    And I visit the colleague's user page
    Then I should see the two-factor method badge "Whatsapp"
    And I should see the "Reset 2FA Method" two-factor button
    When I open the reset two-factor modal
    Then the reset modal should warn me about the consequences of an admin reset
    When I confirm the admin reset with message "As discussed, please set up the Authenticator app."
    Then I should see "Two-factor method reset for"
    And the colleague should have no two-factor method but two-factor still enabled
    And the colleague should have received a two-factor reset email mentioning "As discussed, please set up the Authenticator app."
    When I log out
    And I log in as the colleague
    Then I should be on the 2FA mode selection page
    And I should see the two-factor reset banner from an administrator

    Examples:
      | user | entity              | colleague                                    |
      |      | entity_type=Company | first_name=Alex;last_name=Colleague          |

  Scenario Outline: A user without the admin role cannot reset a colleague's method
    Given there is a user "<user>" for an entity "<entity>"
    And there is a colleague "<colleague>" in the same entity using WhatsApp two-factor
    And I am at the login page
    When I fill and submit the login page
    And I post a two-factor reset for the colleague directly
    Then the colleague should still be in whatsapp mode

    Examples:
      | user | entity              | colleague                                    |
      |      | entity_type=Company | first_name=Alex;last_name=Colleague          |
