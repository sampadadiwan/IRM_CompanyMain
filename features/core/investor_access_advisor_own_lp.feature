Feature: A GP can add an advisor as a contact of the advisor's own LP record
  The Users-tab form refuses users holding the investor_advisor role, so that client access goes
  through Add Investor Advisor (which also creates the advisor's fund grants). That must not stop a
  GP adding an advisor to the LP record of the advisor's OWN firm - there they are a plain contact,
  exactly like their colleagues. "Home" is advisor_entity_id, or entity_id when none is recorded.
  Worked examples: openspec/changes/fix-advisor-add-own-lp-contact/report.md#verification

  Background:
    Given Im logged in as a user "first_name=Gita" for an entity "name=Artha;entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is a fund "name=Artha Select" for the entity
    And there is an advisor "srikant@advisor.example" whose home is the investor entity "Srikant Home"
    And the investor entity "Srikant Home" is an LP of the fund

  # H1 — Happy path: matrix row 3 - the GP adds an at-home advisor to their own LP from the Users form
  @rack_test
  Scenario: H1 The Users form adds an advisor to their own firm's LP record
    When I add "srikant@advisor.example" from the Users form of the "Srikant Home" stakeholder
    Then the page says "Investor access was successfully created."
    And "srikant@advisor.example" is an approved contact of "Srikant Home" flagged as an advisor

  # H2 — Happy path: matrix row 3 - once added, the advisor receives their own LP's call notices
  @rack_test
  Scenario: H2 An advisor added to their own LP receives its capital call notices
    When "srikant@advisor.example" is added to "Srikant Home" through the Users form path
    Then the contact row is saved
    And "srikant@advisor.example" is a capital call recipient for "Srikant Home" on the fund

  # E1 — Edge case: matrix row 4 - judged by home, not by the client they are switched into
  @rack_test
  Scenario: E1 An advisor switched into a client can still be added to their own LP
    Given "srikant@advisor.example" is switched into a client "Harshal"
    When "srikant@advisor.example" is added to "Srikant Home" through the Users form path
    Then the contact row is saved

  # E2 — Edge case: matrix row 5 - an advisor whose home is a fund company (fund-of-funds LP)
  @rack_test
  Scenario: E2 An advisor whose home is a fund company can be added to that company's LP record
    Given there is an advisor "fof@advisor.example" whose home is the fund company "Feeder Capital"
    And the fund company "Feeder Capital" is an LP of the fund
    When "fof@advisor.example" is added to "Feeder Capital" through the Users form path
    Then the contact row is saved

  # E3 — Edge case: a legacy advisor with no recorded home is judged by their entity
  @rack_test
  Scenario: E3 A legacy advisor with no recorded home can be added to their entity's LP record
    Given "srikant@advisor.example" has no recorded advisor home
    When "srikant@advisor.example" is added to "Srikant Home" through the Users form path
    Then the contact row is saved

  # E4 — Edge case: deleting the own-LP row still removes the advisor's personal fund grants at home
  @rack_test
  Scenario: E4 Deleting an advisor's own-LP contact row removes their personal fund grant in the home entity
    Given "srikant@advisor.example" is added to "Srikant Home" through the Users form path
    And "srikant@advisor.example" has a personal grant on the fund in "Srikant Home"
    When the contact row is deleted
    Then "srikant@advisor.example" has no personal grant on the fund in "Srikant Home"

  # X1 — Error case: matrix row 6 - a client's investor still needs Add Investor Advisor
  @rack_test
  Scenario: X1 An advisor cannot be added to a client's investor from the Users form
    Given there is an investor entity "Harshal" that is an LP of the fund
    When "srikant@advisor.example" is added to "Harshal" through the Users form path
    Then the contact row is refused with "belongs to a user with the Investor Advisor role and cannot be added as investor access from this page"

  # X2 — Error case: matrix row 7 - an advisor from another firm stays blocked
  @rack_test
  Scenario: X2 An advisor from another firm cannot be added to an unrelated LP from the Users form
    Given there is an advisor "other@advisor.example" whose home is the investor entity "Other Firm"
    When "other@advisor.example" is added to "Srikant Home" through the Users form path
    Then the contact row is refused with "belongs to a user with the Investor Advisor role and cannot be added as investor access from this page"

  # X3 — Error case: matrix row 2 - a plain user of another entity is still refused
  @rack_test
  Scenario: X3 A plain user of another entity is still refused
    Given there is a plain user "plain@other.example" in the investor entity "Other Firm"
    When "plain@other.example" is added to "Srikant Home" through the Users form path
    Then the contact row is refused with "cannot be given access"
