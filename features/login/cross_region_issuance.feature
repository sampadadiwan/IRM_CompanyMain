Feature: Region selector and hand-off credential issuance
  Which regions a user is offered, and which a hand-off credential may be minted for.

  The selector's options and the controller's authorisation now come from the same place
  (User#switchable_region_codes), so they cannot disagree. The view does no parsing of its own:
  it used to split the stored `regions` string on "," and render whatever fell out, which made
  " in ,US, us" three options and the JSON form '["US","IN"]' two broken ones.

  @cross-region-issuance @rack_test
  Scenario: H1 A user with two deployed regions can switch between them
    Given the regions are "IN,US"
    And a user "neha@siliconroad.com" whose stored regions are "IN,US"
    Then that user's switchable regions should be "IN,US"
    And the region selector should be shown for that user

  @cross-region-issuance @rack_test
  Scenario: E1 A user with one deployed region has nothing to switch to
    Given the regions are "IN,US"
    And a user "raj@siliconroad.com" whose stored regions are "IN"
    Then that user's switchable regions should be "IN"
    And the region selector should not be shown for that user

  @cross-region-issuance @rack_test
  Scenario: E2 Inconsistent casing and spacing resolves to clean region codes
    Given the regions are "IN,US"
    And a user "messy@siliconroad.com" whose stored regions are " in ,US, us"
    Then that user's switchable regions should be "IN,US"
    And the region selector should be shown for that user

  @cross-region-issuance @rack_test
  Scenario: E2 A credential minted for a lower-case destination verifies on that region
    Given the regions are "IN,US"
    And a user "messy@siliconroad.com" whose stored regions are " in ,US, us"
    And the current region is "IN"
    When a hand-off credential is minted for that user targeting " us "
    And the current region is "US"
    Then the credential should verify successfully
    And the credential should carry origin region "IN"

  @cross-region-issuance @rack_test
  Scenario: E3 A region code with no deployment is not offered, and is not deleted
    Given the regions are "IN,US"
    And a user "sandeep@siliconroad.com" whose stored regions are "IN,SG"
    Then that user's switchable regions should be "IN"
    And that user's stored regions should still be "IN,SG"
    And the region selector should not be shown for that user

  @cross-region-issuance @rack_test
  Scenario: E4 Regions stored as a JSON array still resolve
    Given the regions are "IN,US"
    And a user "jason@siliconroad.com" whose stored regions are "[\"US\",\"IN\"]"
    Then that user's switchable regions should be "IN,US"
    And the region selector should be shown for that user

  @cross-region-issuance @rack_test
  Scenario: A hand-off credential survives a query string unaltered
    Given the regions are "IN,US"
    And a user "neha@siliconroad.com" whose stored regions are "IN,US"
    And the current region is "IN"
    When a hand-off credential is minted for that user targeting "US"
    Then the credential should contain no plus character
    And the credential should survive query string parsing unchanged

  @cross-region-issuance @rack_test
  Scenario: X9 A region with no deployment is refused before any credential is minted
    Given the regions are "IN,US"
    And a user "sandeep@siliconroad.com" whose stored regions are "IN,SG"
    And the current region is "IN"
    When a hand-off credential is minted for that user targeting "SG"
    Then minting should be refused

  @cross-region-issuance @rack_test
  Scenario: X10 A user may not mint a credential for a region they do not have
    Given the regions are "IN,US"
    And a user "raj@siliconroad.com" whose stored regions are "IN"
    Then that user should not be permitted to switch to "US"
    And that user should be permitted to switch to "IN"

  @cross-region-issuance
  Scenario: X10 A user with every region is still refused an undeployed one
    Given the regions are "IN,US"
    And a user "neha@siliconroad.com" whose stored regions are "IN,US,SG"
    Then that user should not be permitted to switch to "SG"
    And that user should not be permitted to switch to ""
