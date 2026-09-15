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

  # Enrollment is only for a user with no verified method. Once one exists, the route to a
  # different method is the reset flow (password re-proven), not an enrollment URL.
  Scenario Outline: A user with a verified method cannot re-enter enrollment mid-login
    Given there is a user "<user>" for an entity "<entity>"
    And the user has two-factor authentication enabled and configured
    And I am at the login page
    When I fill and submit the login page
    Then I should be on the 2FA verification page
    When I visit the 2FA mode selection page directly
    Then I should be on the 2FA verification page
    When I visit the 2FA enrollment page directly
    Then I should be on the 2FA verification page
    And the user should still be in authenticator mode

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

  Scenario Outline: A code pasted with spaces around it is accepted
    Given there is a user "<user>" for an entity "<entity>"
    And the user has two-factor authentication enabled and configured
    And I am at the login page
    When I fill and submit the login page
    Then I should be on the 2FA verification page
    When I enter a valid TOTP code with spaces around it
    Then I should see "Signed in successfully"

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # Each password login starts a fresh set of three attempts. Two misses, a trip back to
  # the login page and one more miss must not read "Too many failed attempts".
  Scenario Outline: Failed attempts do not carry over into a fresh login
    Given there is a user "<user>" for an entity "<entity>"
    And the user has two-factor authentication enabled and configured
    And I am at the login page
    When I fill and submit the login page
    Then I should be on the 2FA verification page
    When I enter an invalid TOTP code 2 times
    Then I should see "1 attempt(s) remaining"
    When I am at the login page
    And I fill and submit the login page
    Then I should be on the 2FA verification page
    When I enter an invalid TOTP code
    Then I should see "2 attempt(s) remaining"
    And I should not see "Too many failed attempts"

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # The back button after enrollment, or a bookmarked code screen, used to 404.
  Scenario Outline: A signed-in user who returns to a two-factor URL is sent into the app
    Given there is a user "<user>" for an entity "<entity>"
    And the user has two-factor authentication enabled and configured
    And I am at the login page
    When I fill and submit the login page
    Then I should be on the 2FA verification page
    When I enter a valid TOTP code
    Then I should see "Signed in successfully"
    When I visit the 2FA verification page directly
    Then I should not be on a two-factor page
    And I should not see "Session expired"

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
