@rack_test
Feature: Consolidated report, the fair market value change is the change in value per unit
  The change in fair market value is the weighted average, over the instruments held at the earlier date, of each one's change
  in value per unit to the end date, weighted by its value then. Units bought or sold since do not move it. The amounts
  fmv, fmv_prior and fmv_fy_start stay as they were: the units held at each date at that date's value per unit.
  Worked examples: openspec/changes/portfolio-report-quarter-activity-and-change-sign/design.md#worked-examples

Background:
  Given Im logged in as a user "first_name=Meera" for an entity "name=Alpha Ventures;entity_type=Investment Fund"
  Given the user has role "company_admin"
  And a fund for the per-unit change

# H19 — Happy path: 10 units at 100 on 30 Jun, 5 more bought in August, 110 on 30 Sep. 1,100 against 1,000 is +10%, not +65%
Scenario: H19 Price rises and units are bought
  Given "Company P" holds 10 units of "A" in the fund bought on "2026-02-01"
  And "Company P" buys 5 more units of "A" on "2026-08-01"
  And "Company P" values "A" at 100 rupees per unit on "2026-06-30"
  And "Company P" values "A" at 110 rupees per unit on "2026-09-30"
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the line of "Company P" shows fmv_change_percent "10.0"
  And the line of "Company P" shows fmv_prior "1000" rupees
  And the line of "Company P" shows fmv "1650" rupees

# H20 — Happy path: 4 of the 10 units are sold in August, the price is still +10%
Scenario: H20 Price rises and units are sold
  Given "Company P" holds 10 units of "A" in the fund bought on "2026-02-01"
  And "Company P" sells 4 units of "A" on "2026-08-01"
  And "Company P" values "A" at 100 rupees per unit on "2026-06-30"
  And "Company P" values "A" at 110 rupees per unit on "2026-09-30"
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the line of "Company P" shows fmv_change_percent "10.0"

# H21 — Happy path: instrument A, 1,000 at +10%, and instrument B, 3,000 at -20%: (100 - 600) / 4,000 = -12.5%
Scenario: H21 Several instruments weighted by prior value
  Given "Company P" holds 10 units of "A" in the fund bought on "2026-02-01"
  And "Company P" holds 30 units of "B" in the fund bought on "2026-02-01"
  And "Company P" values "A" at 100 rupees per unit on "2026-06-30"
  And "Company P" values "A" at 110 rupees per unit on "2026-09-30"
  And "Company P" values "B" at 100 rupees per unit on "2026-06-30"
  And "Company P" values "B" at 80 rupees per unit on "2026-09-30"
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the line of "Company P" shows fmv_change_percent "-12.5"

# H22 — Happy path: Company P (+10%) and Company Q (-20%) in one fund; the total is -12.5% from the sums, not the -5% average
Scenario: H22 Fund total from the sums
  Given "Company P" holds 10 units of "A" in the fund bought on "2026-02-01"
  And "Company Q" holds 30 units of "A" in the fund bought on "2026-02-01"
  And "Company P" values "A" at 100 rupees per unit on "2026-06-30"
  And "Company P" values "A" at 110 rupees per unit on "2026-09-30"
  And "Company Q" values "A" at 100 rupees per unit on "2026-06-30"
  And "Company Q" values "A" at 80 rupees per unit on "2026-09-30"
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the line of "Company P" shows fmv_change_percent "10.0"
  And the line of "Company Q" shows fmv_change_percent "-20.0"
  And the total of "Unit Fund" shows fmv_change_percent "-12.5"

# H23 — Happy path: 8 units at 90 at the financial year start (31 Mar), 100 on 30 Jun, 108 on 30 Sep: +20% since the year start, +8% in the quarter
Scenario: H23 Financial year start
  Given "Company P" holds 8 units of "A" in the fund bought on "2025-06-01"
  And "Company P" values "A" at 90 rupees per unit on "2026-03-31"
  And "Company P" values "A" at 100 rupees per unit on "2026-06-30"
  And "Company P" values "A" at 108 rupees per unit on "2026-09-30"
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the line of "Company P" shows fmv_fy_start_change_percent "20.0"
  And the line of "Company P" shows fmv_change_percent "8.0"

# H24 — Happy path: after a sale the amounts are still the units held at each date at that date's value: 1,000, 660 and 1,000
Scenario: H24 Amounts unchanged
  Given "Company P" holds 10 units of "A" in the fund bought on "2025-06-01"
  And "Company P" sells 4 units of "A" on "2026-08-01"
  And "Company P" values "A" at 100 rupees per unit on "2026-03-31"
  And "Company P" values "A" at 100 rupees per unit on "2026-06-30"
  And "Company P" values "A" at 110 rupees per unit on "2026-09-30"
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the line of "Company P" shows fmv_prior "1000" rupees
  And the line of "Company P" shows fmv "660" rupees
  And the line of "Company P" shows fmv_fy_start "1000" rupees

# E25 — Edge case: the value per unit is the same, so there is no change
Scenario: E25 Price unchanged
  Given "Company P" holds 10 units of "A" in the fund bought on "2026-02-01"
  And "Company P" values "A" at 100 rupees per unit on "2026-06-30"
  And "Company P" values "A" at 100 rupees per unit on "2026-09-30"
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the line of "Company P" shows fmv_change_percent "0.0"

# E26 — Edge case: 100 to 90 is -10%
Scenario: E26 Price falls
  Given "Company P" holds 10 units of "A" in the fund bought on "2026-02-01"
  And "Company P" values "A" at 100 rupees per unit on "2026-06-30"
  And "Company P" values "A" at 90 rupees per unit on "2026-09-30"
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the line of "Company P" shows fmv_change_percent "-10.0"

# E27 — Edge case: all 10 units are sold in August, the holding still gained 10% while held, it does not read as -100%
Scenario: E27 Holding sold entirely in the period
  Given "Company P" holds 10 units of "A" in the fund bought on "2026-02-01"
  And "Company P" sells 10 units of "A" on "2026-08-01"
  And "Company P" values "A" at 100 rupees per unit on "2026-06-30"
  And "Company P" values "A" at 110 rupees per unit on "2026-09-30"
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the line of "Company P" shows fmv_change_percent "10.0"

# E28 — Edge case: the only valuation before the start is dated 20 Jun, so that is the value per unit on 30 Jun
Scenario: E28 Older valuation used
  Given "Company P" holds 10 units of "A" in the fund bought on "2026-02-01"
  And "Company P" values "A" at 100 rupees per unit on "2026-06-20"
  And "Company P" values "A" at 110 rupees per unit on "2026-09-30"
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the line of "Company P" shows fmv_change_percent "10.0"

# E29 — Edge case: a USD instrument in the INR fund; the USD value per unit is flat at 1 and the rate rises 5% (80 to 84), so +5%
Scenario: E29 Fund currency
  Given the units are valued in USD
  And there is an exchange rate from "USD" to "INR" of "80" as of "2026-01-01"
  And there is an exchange rate from "USD" to "INR" of "80" as of "2026-06-30"
  And there is an exchange rate from "USD" to "INR" of "84" as of "2026-09-30"
  And "Company P" holds 10 units of "A" in the fund bought on "2026-02-01"
  And "Company P" values "A" at 1 rupees per unit on "2026-06-30"
  And "Company P" values "A" at 1 rupees per unit on "2026-09-30"
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the line of "Company P" shows fmv_change_percent "5.0"

# E30 — Edge case: no valuation before the start, so the purchase price of 100 is the value per unit then; 110 at the end is +10%
Scenario: E30 Purchase price is the value before any valuation
  Given "Company P" holds 10 units of "A" in the fund bought on "2026-02-01" at 100 rupees per unit
  And "Company P" values "A" at 110 rupees per unit on "2026-09-30"
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the line of "Company P" shows fmv_change_percent "10.0"
  And the line of "Company P" shows fmv_prior "1000" rupees

# E31 — Edge case: the only purchase is in August, nothing was held at the start
Scenario: E31 Bought only in the period
  Given "Company P" holds 10 units of "A" in the fund bought on "2026-08-01"
  And "Company P" values "A" at 110 rupees per unit on "2026-09-30"
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the line of "Company P" shows fmv_change_percent "N/A"

# E32 — Edge case: instrument A was held and gained 10%; instrument B was bought in August and has no weight
Scenario: E32 New instrument beside an old one
  Given "Company P" holds 10 units of "A" in the fund bought on "2026-02-01"
  And "Company P" holds 5 units of "B" in the fund bought on "2026-08-01"
  And "Company P" values "A" at 100 rupees per unit on "2026-06-30"
  And "Company P" values "A" at 110 rupees per unit on "2026-09-30"
  And "Company P" values "B" at 60 rupees per unit on "2026-09-30"
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the line of "Company P" shows fmv_change_percent "10.0"
