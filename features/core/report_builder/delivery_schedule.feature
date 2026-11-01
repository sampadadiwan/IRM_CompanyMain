@report_builder
Feature: Report Builder delivery — a schedule you can trust

  Worked examples: openspec/changes/report-builder-delivery/business-rules.md
  Save schedule checks every recipient, asks before emailing people outside
  the company, and names the time zone; Send test to me emails the signed-in
  user alone; the tab says when the report was last sent and when it goes next.

  Background:
    Given the Acme report builder data
    And the Acme delivery report "LPs"
    And Meera's email is "meera@acme.test" and Acme has the user "ravi@acme.test"

  # H4 — Happy path: recipients inside Acme save without a popup, in the chosen time zone
  @rack_test
  Scenario: Save a schedule inside Acme
    Given I am signed in as Meera
    When I save the schedule "weekly" in "Asia/Kolkata" to "meera@acme.test, ravi@acme.test" from the builder
    Then the builder message says "Schedule saved — weekly on Monday at 09:00 IST to 2 people"
    And the schedule emails "meera@acme.test, ravi@acme.test" "weekly" in "Asia/Kolkata"

  # H5 — Happy path: an outsider is named in the Immediate Actions popup; Proceed saves
  @javascript
  Scenario: Outsider warning, Proceed
    Given Meera is on the builder for the report
    When I turn the schedule on with the recipients "meera@acme.test, lp@gmail.com"
    And I click Save schedule
    Then the popup reads "Emails 1 person outside Acme Capital" and "lp@gmail.com"
    When I click Proceed in the popup
    Then I see a green message "Schedule saved — daily at 09:00 IST to 2 people"
    And the schedule emails "meera@acme.test, lp@gmail.com" "daily" in "Asia/Kolkata"

  # H6 — Happy path: Send test to me emails Meera alone, with the Excel file
  @rack_test
  Scenario: Send test to me
    Given the report has a "daily" schedule in "Asia/Kolkata" to "ravi@acme.test"
    And I am signed in as Meera
    And the email queue is empty
    When I send a test of the schedule from the builder
    Then the builder message says "A test is on its way to meera@acme.test"
    And exactly one email went out, to "meera@acme.test", with the subject "Scheduled Report: LPs" and an Excel file

  # H7 — Happy path: Last sent and Next, in the schedule's time zone
  @rack_test
  Scenario: Last sent and next
    Given the report has a "weekly" schedule in "Asia/Kolkata" to "ravi@acme.test"
    And the schedule was last sent at "2026-11-02 03:30 UTC" and goes next at "2026-11-09 03:30 UTC"
    And I am signed in as Meera
    When I open the builder
    Then the Delivery tab reads "Last sent 02 Nov 2026 09:00 IST · Next 09 Nov 2026 09:00 IST"

  # H8 — Happy path: a test send doesn't change Last sent
  @rack_test
  Scenario: A test isn't a scheduled send
    Given the report has a "weekly" schedule in "Asia/Kolkata" to "ravi@acme.test"
    And the schedule was last sent at "2026-11-02 03:30 UTC" and goes next at "2026-11-09 03:30 UTC"
    And I am signed in as Meera
    When I send a test of the schedule from the builder
    And I open the builder
    Then the Delivery tab reads "Last sent 02 Nov 2026 09:00 IST"

  # E3 — Edge case: Cancel in the outsider popup saves nothing
  @javascript
  Scenario: Outsider warning, Cancel
    Given Meera is on the builder for the report
    When I turn the schedule on with the recipients "meera@acme.test, lp@gmail.com"
    And I click Save schedule
    And I click Cancel in the popup
    Then the report has no schedule

  # E4 — Edge case: addresses are stored lower-case, without duplicates, whatever separates them
  @rack_test
  Scenario: Addresses tidied
    Given I am signed in as Meera
    When I save the schedule "daily" in "Asia/Kolkata" to "Meera@Acme.test; ravi@acme.test\nmeera@acme.test" from the builder
    Then the schedule emails "meera@acme.test, ravi@acme.test" "daily" in "Asia/Kolkata"

  # E5 — Edge case: switching off saves at once and keeps the recipients
  @rack_test
  Scenario: Turning off
    Given the report has a "daily" schedule in "Asia/Kolkata" to "ravi@acme.test"
    And I am signed in as Meera
    When I turn the schedule off from the builder
    Then the builder message says "Schedule turned off"
    And the schedule is off and still emails "ravi@acme.test"

  # E6 — Edge case: a schedule saved before this change keeps UTC, and says so
  @rack_test
  Scenario: An old UTC schedule
    Given the report has a "daily" schedule in "UTC" to "ravi@acme.test"
    And I am signed in as Meera
    When I open the builder
    Then the Delivery tab's time zone is "UTC"
    And the Delivery tab reads "Not sent yet · Next"
    And the Delivery tab reads "09:00 UTC"

  # E7 — Edge case: a schedule never sent says so, with its next send
  @rack_test
  Scenario: Never sent
    Given I am signed in as Meera
    When I save the schedule "daily" in "Asia/Kolkata" to "ravi@acme.test" from the builder
    Then the Delivery tab reads "Not sent yet · Next"
    And the Delivery tab reads "09:00 IST"

  # X2 — Error case: a bad address is named under the field; what was typed stays; nothing saved
  @javascript
  Scenario: Invalid address
    Given Meera is on the builder for the report
    When I turn the schedule on with the recipients "meera@acme.test, bob@"
    And I click Save schedule
    Then the recipients field says "bob@ isn't an email address"
    And the recipients field still reads "meera@acme.test, bob@"
    And the report has no schedule

  # X3 — Error case: an empty list can't be saved
  @rack_test
  Scenario: Empty list
    Given I am signed in as Meera
    When I save the schedule "daily" in "Asia/Kolkata" to "" from the builder
    Then the builder message says "Schedule wasn't saved — Add at least one email"
    And the Delivery tab says "Add at least one email" under the recipients
    And the report has no schedule

  # X4 — Error case: a save with an outsider that wasn't confirmed is refused
  @rack_test
  Scenario: Outsider without confirming
    Given I am signed in as Meera
    When I send the schedule save "daily" to "lp@gmail.com" without confirming
    Then the request is refused with status 422
    And the refusal says "Confirm sending to people outside Acme Capital first"
    And the report has no schedule

  # X5 — Error case: another company can't check, test or save Acme's schedule
  @rack_test
  Scenario: Another company
    Given I am signed in as Omar from another entity
    And the email queue is empty
    When Omar sends a test and a recipients check for the report
    Then both are refused
    And no email went out
