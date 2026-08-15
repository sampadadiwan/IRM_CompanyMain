Feature: Authenticator help and download links on the two-factor screens
  A user who is setting up 2FA is signed out, so the normal /user_guides route would
  bounce them to the login page. The authenticator setup guide is therefore published
  at /help/<guide_id>, and the setup screens link to it alongside app store downloads.

  Scenario: The authenticator setup guide is readable without signing in
    When I visit the public authenticator setup guide
    Then I should see "What Is an Authenticator App?"
    And I should see a download link for "Google Authenticator"
    And I should see a download link for "Microsoft Authenticator"
    And I should not be asked to sign in

  Scenario: The two-factor overview guide is readable without signing in
    When I visit the public two factor guide
    Then I should see "Two-Factor Authentication User Guide"
    And I should not be asked to sign in

  Scenario: Guides outside the published allowlist are not exposed
    When I visit the public guide "capital_calls_user_guide"
    Then I should be redirected to the login page

  Scenario: An arbitrary file name is refused
    # The allowlist is checked before the file is ever resolved, so a real file
    # outside docs/user_guides is refused for the same reason an unpublished guide is.
    When I visit the public guide "Gemfile"
    Then I should be redirected to the login page

  Scenario: Path traversal out of the guides directory is refused
    # Percent-encoded so the browser does not normalise the ".." away before the
    # request is sent — the segments have to actually reach the controller.
    When I visit the public guide "..%2F..%2FGemfile"
    Then I should be redirected to the login page

  Scenario: A .md suffix on a published guide still resolves
    When I visit the public guide "authenticator_app_setup_user_guide.md"
    Then I should see "What Is an Authenticator App?"

  Scenario Outline: Mode selection offers the guide and reveals downloads for Authenticator
    Given there is a user "<user>" for an entity "<entity>"
    And the user has two-factor authentication enabled but not configured
    And I am at the login page
    When I fill and submit the login page
    Then I should be on the 2FA mode selection page
    And I should see a link to the authenticator setup guide
    And I should see the authenticator download links

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  Scenario Outline: Downloads stay hidden until Authenticator is chosen
    Given there is a user "<user>" for an entity "<entity>"
    And the user has two-factor authentication enabled but not configured
    And the user has WhatsApp enabled
    And I am at the login page
    When I fill and submit the login page
    Then I should be on the 2FA mode selection page
    And I should not see the authenticator download links
    When I choose the Authenticator mode without continuing
    Then I should see the authenticator download links
    When I choose the WhatsApp mode without continuing
    Then I should not see the authenticator download links

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  Scenario Outline: Enrollment page carries the downloads and the guide
    Given there is a user "<user>" for an entity "<entity>"
    And the user has two-factor authentication enabled but not configured
    And I am at the login page
    When I fill and submit the login page
    When I select the Authenticator mode
    Then I should be on the 2FA enrollment page
    And I should see a link to the authenticator setup guide
    And I should see the authenticator download links

    Examples:
      | user | entity              |
      |      | entity_type=Company |
