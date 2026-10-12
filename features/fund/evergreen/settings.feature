Feature: Evergreen fund settings
  Edit an open-ended fund's terms and fill from a preset. A fund's type is chosen on New Fund and can't
  be changed (evergreen-fund-on-create), so H1, X1, X4, E138 and X83 are retired here.
  Worked examples H2, E137, E139, X2, X3, X81, X82, X84 — openspec/changes/open-ended-funds/design.md#worked-examples

  Background:
    Given Im logged in as a user "first_name=Asha" for an entity "name=Caphive Demo;entity_type=Investment Fund"
    And the user has role "company_admin"
    And the entity has evergreen funds switched on

  # H2 — Happy path: picking a preset fills the form without saving anything.
  Scenario: Apply a preset fills the form without saving
    Given there is a fund "name=Alpha Long-Short Fund;currency=INR;unit_types=A" for the entity
    And the fund is evergreen
    When I open the evergreen settings of the fund
    And I pick the preset "us_tender_offer"
    Then the settings form should select "Quarterly" for "redemption_calendar"
    And the settings form should show "gate_pct" as "5"
    And the settings form should select "Each quarter" for "gate_period"
    And the settings form should select "Soft — redeem with a fee" for "lock_up_type"
    And the settings form should show "early_fee_pct" as "2"
    And the fund setting "redemption_calendar" should be "quarterly"
    And the fund setting "gate_pct" should be "0.0"

  # X2 — Error case: a gate of 120 % is outside 0–100 and is not saved.
  @rack_test
  Scenario: Gate out of range is not saved
    Given there is a fund "name=Alpha Long-Short Fund;currency=INR;unit_types=A" for the entity
    And the fund is evergreen
    When I open the evergreen settings of the fund
    And I set the evergreen field "gate_pct" to "120"
    And I save the evergreen settings
    Then I should see "must be between 0 and 100"

  # X3 — Error case: clearing every redemption form is refused — at least one way to redeem is required.
  Scenario: At least one redemption form is required
    Given there is a fund "name=Alpha Long-Short Fund;currency=INR;unit_types=A" for the entity
    And the fund is evergreen
    When I open the evergreen settings of the fund
    And I clear every redemption form
    # The Redemptions step's required check stops Next; the server's "Allow at least one way to redeem" is the backstop
    And I try to go past the redemptions step
    Then the ways to redeem should be marked "Choose at least one"
    And the fund's redemption forms should be unchanged

  # ---- Edge cases (E137–E139, X81–X84) ----

  # E137 — Edge case: the top of each notification range is accepted — reminder days 30 and a large-redemption threshold of 100 %.
  @rack_test
  Scenario: Reminder days 30 and threshold 100 are accepted
    Given there is a fund "name=Alpha Long-Short Fund;currency=INR;unit_types=A" for the entity
    And the fund is evergreen
    When I open the notifications step of the evergreen settings
    And I set the reminder days to "30"
    And I set the large redemption threshold to "100"
    And I save the evergreen settings
    Then I should see "Settings saved"
    And the fund reminder days should be "30"
    And the fund large redemption threshold should be "100"

  # X81 — Error case: reminder days 31, one past the 1–30 range, is refused and the default 2 stays.
  @rack_test
  Scenario: Reminder days 31 is refused
    Given there is a fund "name=Alpha Long-Short Fund;currency=INR;unit_types=A" for the entity
    And the fund is evergreen
    When I open the notifications step of the evergreen settings
    And I set the reminder days to "31"
    And I save the evergreen settings
    Then I should see "Reminder days must be between 1 and 30"
    And the fund reminder days should be "2"

  # X82 — Error case: custom redemption dates must be strict ISO dates — "03/04/2027" (ambiguous) and "2027-02-30" (no such day) are named and nothing is saved.
  @rack_test
  Scenario: Custom dealing dates must be valid YYYY-MM-DD dates
    Given there is a fund "name=Alpha Long-Short Fund;currency=INR;unit_types=A" for the entity
    And the fund is evergreen
    When I open the evergreen settings of the fund
    And I choose "Custom" for the evergreen field "redemption_calendar"
    And I fill the evergreen field "redemption_dates_text" with "2027-03-31, 03/04/2027, 2027-02-30"
    And I save the evergreen settings
    Then I should see "These dates are not valid YYYY-MM-DD dates: 03/04/2027, 2027-02-30"
    And the fund setting "redemption_calendar" should be "quarterly"

  # X84 — Error case: choosing "A set day of the month" reveals the day field, and day 29 (outside 1–28) is refused.
  Scenario: A dealing day of the month above 28 is refused
    Given there is a fund "name=Alpha Long-Short Fund;currency=INR;unit_types=A" for the entity
    And the fund is evergreen
    When I open the evergreen settings of the fund
    And I choose "First business day" for the evergreen field "dealing_day"
    Then the evergreen field "dealing_day_n" should be hidden
    When I choose "A set day of the month" for the evergreen field "dealing_day"
    Then the evergreen field "dealing_day_n" should be visible
    When I fill the evergreen field "dealing_day_n" with "29"
    And I save the evergreen settings
    Then I should see "Dealing day n must be in 1..28"
    And the fund setting "dealing_day" should be "first"

  # E139 — Edge case: switching payment timing to "after" reveals "Days to pay" and moves open dealing dates to "after"; a confirmed date keeps "before".
  Scenario: Open dealing dates follow a changed payment timing
    Given there is a fund "name=Alpha Long-Short Fund;currency=INR;unit_types=A" for the entity
    And the fund is evergreen
    And the fund has a confirmed dealing date on "2026-11-02"
    And the fund has an open dealing date on "2026-12-01"
    When I open the evergreen settings of the fund
    And I choose "Before dealing (by the cut-off)" for the evergreen field "payment_timing"
    Then the evergreen field "pay_after_days" should be hidden
    When I choose "After dealing" for the evergreen field "payment_timing"
    Then the evergreen field "pay_after_days" should be visible
    When I save the evergreen settings
    Then I should see "Settings saved"
    And the fund setting "payment_timing" should be "after"
    And the dealing date on "2026-12-01" should have payment timing "after"
    And the dealing date on "2026-11-02" should have payment timing "before"
