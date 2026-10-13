@rack_test
Feature: Site registry configuration guard
  SITES and CURRENT_SITE are only read on the cross-region hand-off path, so a bad value used
  to surface days later as "Invalid or expired link" or a 500, with nothing naming the setting.
  SiteRegistry.validate! runs at boot instead, and must name the setting and the offending value.

  @site-registry
  Scenario: X11 A region list that cannot be parsed stops the boot check
    Given the region list is set to "not json at all"
    And the active region is set to "IN"
    When the site registry is validated
    Then validation should fail naming "SITES"
    And the validation message should mention "not valid JSON"

  @site-registry
  Scenario: X11 A region list that is not an object stops the boot check
    Given the region list is set to "[1,2]"
    And the active region is set to "IN"
    When the site registry is validated
    Then validation should fail naming "SITES"
    And the validation message should mention "must be a JSON object"

  @site-registry
  Scenario: X12 An insecure address stops the boot check, naming the region
    Given the region list is set to '{"IN":"https://app.caphive.com","US":"http://app.caphive.us"}'
    And the active region is set to "IN"
    When the site registry is validated
    Then validation should fail naming "SITES[US]"
    And the validation message should mention "must be an https URL"

  @site-registry
  Scenario: X12 A loopback address is exempt from the https rule
    Given the region list is set to '{"IN":"http://localhost:3000","US":"http://localhost:3001"}'
    And the active region is set to "IN"
    When the site registry is validated
    Then validation should succeed

  @site-registry
  Scenario: X13 An active region absent from the list stops the boot check, naming both
    Given the region list is set to '{"IN":"https://app.caphive.com"}'
    And the active region is set to "SG"
    When the site registry is validated
    Then validation should fail naming "CURRENT_SITE"
    And the validation message should mention "SG"
    And the validation message should mention "IN"

  @site-registry
  Scenario: X13 An unset active region stops the boot check
    Given the region list is set to '{"IN":"https://app.caphive.com"}'
    And the active region is unset
    When the site registry is validated
    Then validation should fail naming "CURRENT_SITE"

  @site-registry
  Scenario: Region codes resolve regardless of case and surrounding space
    Given the region list is set to '{"IN":"https://app.caphive.com","US":"https://app.caphive.us"}'
    And the active region is set to " us "
    When the site registry is validated
    Then validation should succeed
    And the active region code should be "US"
    And the registry should know the region " Us "
    And the registry should not know the region "SG"
    And the base URL for region "us" should be "https://app.caphive.us"
    And the peer regions should be "IN"

  @site-registry
  Scenario: A trailing slash is stripped from a region's base URL
    Given the region list is set to '{"IN":"https://app.caphive.com/","US":"https://app.caphive.us"}'
    And the active region is set to "IN"
    When the site registry is validated
    Then the base URL for region "IN" should be "https://app.caphive.com"

  # features/support/twilio_stub.rb sets CURRENT_SITE="LOCAL" for the SMS country logic, which
  # is not a key in SITES. The boot check makes that impossible in a deployed app, but a render
  # path must still degrade rather than 500 the whole page over it.
  @site-registry
  Scenario: A render path survives an active region that is not a deployed region
    Given the region list is set to '{"IN":"https://app.caphive.com","US":"https://app.caphive.us"}'
    And the active region is set to "LOCAL"
    When the site registry is validated
    Then validation should fail naming "CURRENT_SITE"
    But the safe active region code should be empty
    And asking for the safe active region code should not raise

  @site-registry
  Scenario: The safe active region code is the real one when configuration is sound
    Given the region list is set to '{"IN":"https://app.caphive.com","US":"https://app.caphive.us"}'
    And the active region is set to "US"
    Then the safe active region code should be "US"
