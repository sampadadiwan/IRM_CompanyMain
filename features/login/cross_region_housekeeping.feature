Feature: Stored region list housekeeping
  users.regions is free text on the Administrate dashboard and is written in a different shape
  by the multi-region sync, so production holds "IN,US", " in ,US, us" and '["US","IN"]' side
  by side. Everything that reads the column already normalises it; this tidies the stored
  values so the column itself is consistent - without adding or removing anyone's access.

  @cross-region-housekeeping
  Scenario: E14 Reporting mode lists what would change and writes nothing
    Given a user "messy@siliconroad.com" with stored regions " in ,US, us"
    And a user "jason@siliconroad.com" with stored regions "[\"US\",\"IN\"]"
    When I run the regions housekeeping in reporting mode
    Then it should report 2 users would change
    And "messy@siliconroad.com" should still have stored regions " in ,US, us"
    And "jason@siliconroad.com" should still have stored regions "[\"US\",\"IN\"]"

  @cross-region-housekeeping
  Scenario: E11 Execute mode normalises an inconsistently typed value
    Given a user "messy@siliconroad.com" with stored regions " in ,US, us"
    When I run the regions housekeeping in execute mode
    Then "messy@siliconroad.com" should have stored regions "IN,US"

  @cross-region-housekeeping
  Scenario: E12 Execute mode converts the JSON array form
    Given a user "jason@siliconroad.com" with stored regions "[\"US\",\"IN\"]"
    When I run the regions housekeeping in execute mode
    Then "jason@siliconroad.com" should have stored regions "IN,US"

  @cross-region-housekeeping
  Scenario: E13 A second run changes nothing
    Given a user "messy@siliconroad.com" with stored regions " in ,US, us"
    And a user "jason@siliconroad.com" with stored regions "[\"US\",\"IN\"]"
    When I run the regions housekeeping in execute mode
    And I run the regions housekeeping in execute mode
    Then it should report 0 users would change

  @cross-region-housekeeping
  Scenario: Housekeeping neither adds nor removes a region
    Given the regions are "IN,US"
    And a user "sandeep@siliconroad.com" with stored regions "in,sg"
    When I run the regions housekeeping in execute mode
    Then "sandeep@siliconroad.com" should have stored regions "IN,SG"
    And "sandeep@siliconroad.com" should have switchable regions "IN"

  @cross-region-housekeeping
  Scenario: An already-clean value is left alone
    Given a user "neha@siliconroad.com" with stored regions "IN,US"
    When I run the regions housekeeping in reporting mode
    Then it should report 0 users would change
