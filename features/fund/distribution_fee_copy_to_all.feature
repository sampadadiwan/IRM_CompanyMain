@javascript
Feature: Copying a distribution fee row carries its dates in the user's format
  A distribution fee row's date field is a locale-date widget: a VISIBLE text input
  carrying the id and no name, plus a HIDDEN input carrying the ISO value that is
  actually submitted (LocaleDateFormBuilder#date_field).

  "Copy To All" reads the source row by input name, so what it picks up is the hidden
  input's ISO string. It used to write that straight into the target rows' visible
  field, so copying 01/02/2026 filled every other row with the text "2026-02-01" —
  an ISO date shown to a user whose every other date reads dd/mm/yyyy, and one the
  locale-date controller then had to re-parse back out. It now renders the value in
  the widget's own format before writing it.

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;enable_funds=true"
    Given the user has role "company_admin"
    Given there is a fund "name=Fee Copy Fund;currency=INR" for the entity
    Given there is an existing investor "name=Investor 1"
    Given there is a capital commitment of "orig_folio_committed_amount_cents=100000000;folio_currency=INR" for the last investor

  Scenario: Copy To All shows the copied date in the locale format, not ISO
    Given my browser sends an Accept-Language header of "en-GB"
    When I open the new Capital Distribution form for "Fee Copy Fund"
    And I add "3" distribution fee rows
    And I fill in the first fee row start date with "01/02/2026"
    And I copy the first fee row to all rows
    Then every fee row start date should display "01/02/2026"
    And every fee row should submit the start date "2026-02-01"

  Scenario: The copied date follows the active locale
    Given my browser sends an Accept-Language header of "en-US"
    When I open the new Capital Distribution form for "Fee Copy Fund"
    And I add "2" distribution fee rows
    And I fill in the first fee row start date with "02/01/2026"
    And I copy the first fee row to all rows
    Then every fee row start date should display "02/01/2026"
    And every fee row should submit the start date "2026-01-02"

  Scenario: Copying a row with no date clears the other rows rather than restoring ISO
    Given my browser sends an Accept-Language header of "en-GB"
    When I open the new Capital Distribution form for "Fee Copy Fund"
    And I add "2" distribution fee rows
    And I fill in the second fee row start date with "05/03/2026"
    And I copy the first fee row to all rows
    Then every fee row start date should display ""
    And every fee row should submit the start date ""
