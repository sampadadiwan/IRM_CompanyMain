@rack_test
Feature: Evergreen folio statements
  Worked examples H4, H5, H7, E10, E11, E12, E13, E14, E15, E16, E17, X6, X7, X8, X9, X10, X11 — openspec/changes/evergreen-folio-soa/design.md#worked-examples

  # P subscribes ₹5 Cr on 20 Oct, pays on 25 Oct and is allotted 4,892.3679 units on 2 Nov (5,00,00,000 ÷ 10,220);
  # "Others" holds 1,00,000 opening units in F-099. Statements are for Q4 2026, generated on 2 Jan 2027.
  Background:
    Given Im logged in as a user "first_name=Asha" for an entity "name=Caphive Demo;entity_type=Investment Fund"
    And the user has role "company_admin"
    And the entity has evergreen funds switched on
    And today is "2026-10-20"
    And the evergreen fund "Alpha Evergreen Fund" with classes "A" and settings "redemption_calendar=monthly"
    And the fund has the evergreen statement template "Evergreen Statement"
    And "P Family Trust" is an investor of the fund with a portal user
    And "P Family Trust" has placed a "subscription" order "amount=50000000" received "2026-10-20 09:00"
    And "P Family Trust" has paid the subscription on "2026-10-25"
    And "Others" holds "100000" units of class "A" in folio "F-099" issued "2025-09-01"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    And the fund admin confirms dealing date "2026-11-02"
    And an approved NAV for class "A" on "2026-12-31" with NAV per unit "10,450" and units "104892.3679"
    And today is "2027-01-02"

  # H4 — Happy path: the GP generates one folio's Q4 statement from its folio page; a PDF lands on the folio, awaiting approval
  Scenario: Generate one folio's statement
    When I open folio "F-101"
    And I generate statements from "2026-10-01" to "2026-12-31"
    Then I should see "Statement is being generated — you'll be notified when done."
    And folio "F-101" should have "1" statement for "2026-10-01" to "2026-12-31"
    And the statement of folio "F-101" for "2026-10-01" to "2026-12-31" should be a PDF
    And the statement of folio "F-101" for "2026-10-01" to "2026-12-31" should have:
      | opening_units        | 0             |
      | subscribed_units     | 4892.3679     |
      | subscribed_amount    | 50000000      |
      | closing_units        | 4892.3679     |
      | closing_nav_per_unit | 10450         |
      | closing_value        | 51125244.6184 |
    And the statement transactions of folio "F-101" for "2026-10-01" to "2026-12-31" should be:
      | dealing_date | kind         | units      | nav_per_unit | amount          |
      | 2026-11-02   | Subscription | 4,892.3679 | ₹10,220.00   | ₹5,00,00,000.00 |
    And folio "F-099" should have "0" statements for "2026-10-01" to "2026-12-31"

  # H5 — Happy path: Generate statements on the Investors tab makes one statement per folio; the GP sees them awaiting approval
  Scenario: Generate statements for every folio
    When I open the unit register
    And I generate statements from "2026-10-01" to "2026-12-31"
    Then I should see "Statements are being generated — you'll be notified when done."
    And folio "F-101" should have "1" statement for "2026-10-01" to "2026-12-31"
    And folio "F-099" should have "1" statement for "2026-10-01" to "2026-12-31"
    When I open folio "F-101"
    Then I should see "Generated · awaiting approval"

  # H7 — Happy path: approving with Notify makes the statement visible to the investor and emails them
  Scenario: Approve and the investor reads it
    Given I open folio "F-101"
    And I generate statements from "2026-10-01" to "2026-12-31"
    When the fund admin approves the generated statements with notification
    Then the statement of folio "F-101" for "2026-10-01" to "2026-12-31" should be approved
    And "P Family Trust" should have received a document email
    When "P Family Trust" logs in to the portal
    And I open folio "F-101"
    Then I should see "Evergreen Statement 01 October,2026 to 31 December,2026"
    And I should not see "Generated · awaiting approval"

  # E10 — Edge case: a one-day period (start = end) is accepted
  Scenario: Start and end on the same day
    When I open folio "F-101"
    And I generate statements from "2026-12-31" to "2026-12-31"
    Then folio "F-101" should have "1" statement for "2026-12-31" to "2026-12-31"

  # E11 — Edge case: a folio's own template with the fund template's name is used for that folio
  Scenario: A folio template overrides the fund's
    Given folio "F-101" has its own statement template "Evergreen Statement"
    When I open folio "F-101"
    And I generate statements from "2026-10-01" to "2026-12-31"
    Then the statement of folio "F-101" for "2026-10-01" to "2026-12-31" should be generated from "folio F-101"

  # E12 — Edge case: generating the same period twice before approval leaves one statement
  Scenario: Generating twice keeps one statement
    When I open folio "F-101"
    And I generate statements from "2026-10-01" to "2026-12-31"
    And I open folio "F-101"
    And I generate statements from "2026-10-01" to "2026-12-31"
    Then folio "F-101" should have "1" statement for "2026-10-01" to "2026-12-31"

  # E13 — Edge case: a folio that never held units gets a statement of zeros
  Scenario: A folio with no units
    Given "Q Capital" holds "0" units of class "A" in folio "F-102" issued "2025-09-01"
    When I open folio "F-102"
    And I generate statements from "2026-10-01" to "2026-12-31"
    Then folio "F-102" should have "1" statement for "2026-10-01" to "2026-12-31"
    And the statement of folio "F-102" for "2026-10-01" to "2026-12-31" should have:
      | opening_units | 0 |
      | closing_units | 0 |

  # E14 — Edge case: a period before any approved NAV still generates; the NAV figures are blank
  Scenario: No approved NAV in the period
    When I open folio "F-099"
    And I generate statements from "2026-01-01" to "2026-03-31"
    Then folio "F-099" should have "1" statement for "2026-01-01" to "2026-03-31"
    And the statement of folio "F-099" for "2026-01-01" to "2026-03-31" should have no closing NAV

  # E15 — Edge case: units allotted after the period end are not in that period's closing units
  Scenario: Units issued after the end date are excluded
    When I open folio "F-101"
    And I generate statements from "2026-10-01" to "2026-10-31"
    Then the statement of folio "F-101" for "2026-10-01" to "2026-10-31" should have:
      | closing_units | 0 |

  # E16 — Edge case: an approved statement is not regenerated for the same template and period
  Scenario: Approved statements are not replaced
    Given I open folio "F-101"
    And I generate statements from "2026-10-01" to "2026-12-31"
    And the fund admin approves the generated statements with notification
    When I open folio "F-101"
    And I generate statements from "2026-10-01" to "2026-12-31"
    Then folio "F-101" should have "1" statement for "2026-10-01" to "2026-12-31"
    And the statement of folio "F-101" for "2026-10-01" to "2026-12-31" should be approved

  # E17 — Edge case: the investor never sees a statement that is not approved
  Scenario: Unapproved statements are hidden from the investor
    Given I open folio "F-101"
    And I generate statements from "2026-10-01" to "2026-12-31"
    When "P Family Trust" logs in to the portal
    And I open folio "F-101"
    Then I should not see "Evergreen Statement 01 October,2026"

  # X6 — Error case: a start date after the end date is refused
  Scenario: Start after end
    When I open folio "F-101"
    And I generate statements from "2026-12-31" to "2026-10-01"
    Then I should see "Start date must be on or before end date"
    And folio "F-101" should have "0" statements for "2026-12-31" to "2026-10-01"

  # X7 — Error case: with no statement template the form points to the sample and can't be submitted
  Scenario: No template on the fund
    Given the fund's statement templates are removed
    When I open folio "F-101"
    Then I should see "Upload a template tagged SOA Template to the fund's documents first."
    And the Generate button should be disabled

  # X8 — Error case: a read-only employee can't generate statements, even by a direct request
  Scenario: A read-only employee can't generate
    Given a read-only employee "Ravi" of the fund
    When "Ravi" logs in
    And I open folio "F-101"
    Then I should not see "Generate statement"
    When a request generates statements for folio "" with template "Evergreen Statement" from "2026-10-01" to "2026-12-31"
    Then I should see "Access Denied"
    And no statement should have been generated

  # X9 — Error case: another fund's template is refused
  Scenario: A template of another fund
    Given another fund "Beta Fund" has the evergreen statement template "Beta Statement"
    When I open folio "F-101"
    And a request generates statements for folio "F-101" with template "Beta Statement" from "2026-10-01" to "2026-12-31"
    Then I should see "Template not found"
    And no statement should have been generated

  # X10 — Error case: a folio without a KYC is skipped by the fund run; its Generate statement button is disabled
  Scenario: Folio without a KYC
    Given folio "F-099" has no KYC linked
    When I open the unit register
    And I generate statements from "2026-10-01" to "2026-12-31"
    Then folio "F-101" should have "1" statement for "2026-10-01" to "2026-12-31"
    And folio "F-099" should have "0" statements for "2026-10-01" to "2026-12-31"
    When I open folio "F-099"
    Then the Generate statement button should be disabled

  # X11 — Error case: an investor can't open another investor's folio
  Scenario: Another investor's folio
    Given "B LLP" is an investor of the fund with a portal user
    When "B LLP" logs in to the portal
    And I open folio "F-101"
    Then I should see "Access Denied"
