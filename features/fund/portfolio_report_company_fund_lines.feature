@rack_test
Feature: Consolidated report, a company's line in a fund
  Each company's fund line in the consolidated report holds the fund's money as of the end date, cost and value for the
  day before the period, the period and the end date, the cost of exits, the % changes in value, and the value at the
  start of the financial year.
  Worked examples: openspec/changes/portfolio-report-fund-metrics/design.md#worked-examples

Background:
  Given Im logged in as a user "first_name=Meera" for an entity "name=Alpha Ventures;entity_type=Investment Fund"
  Given the user has role "company_admin"
  And the Inflexor quarter data

# H1 — Happy path: the prior value is worked out as of the day before the start date
Scenario: Prior value uses the day before the start date
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the line of "Company A" shows fmv_prior "50.0" crore

# H2 — Happy path: the financial year starts in April, so its value is as of 31 March
Scenario: April financial year
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the line of "Company A" shows fmv_fy_start "45.0" crore

# H3 — Happy path: the fund's money is on the company's fund line
Scenario: Fund money figures on the company fund line
  Given the fund has commitments and collections, some of them dated after 30 September 2026
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the line of "Company A" shows committed_amount "502.0" crore
  And the line of "Company A" shows collected_amount "125.5" crore

# H4 — Happy path: 40 Cr bought before the period, 10 Cr in it
Scenario: Purchases split around the start date
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the line of "Company A" shows cost_of_investment_prior "40.0" crore
  And the line of "Company A" shows cost_of_investment_between "10.0" crore
  And the line of "Company A" shows cost_of_investment "50.0" crore

# H5 — Happy path: a sale at a cost of 5 Cr is an exit of 5 Cr, a positive number
Scenario: Exits in the quarter are positive
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the line of "Company A" shows cost_of_sold_between "5.0" crore

# H6 — Happy path: 40 + 10 - 5 = 45
Scenario: Roll-forward adds up
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the line of "Company A" shows cost_of_remaining_prior "40.0" crore
  And the line of "Company A" shows cost_of_remaining "45.0" crore
  And the roll-forward of "Company A" adds up

# H7 — Happy path: value 50 to 60 is +20%
Scenario: Value rises
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the line of "Company A" shows fmv_change_percent "20.0"

# H8 — Happy path: value 45 at the financial year start to 60 is +33.3%
Scenario: Change since the financial year start
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the line of "Company A" shows fmv_fy_start_change_percent "33.3"

# E1 — Edge case: a purchase on the start date is in the period, not before it
Scenario: Purchase on the start date counts as in the period
  Given "Company B" buys 3 crore of shares on "2026-07-01"
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the line of "Company B" shows cost_of_investment_between "3.0" crore
  And the line of "Company B" shows cost_of_investment_prior "30.0" crore

# E2 — Edge case: a purchase on the end date is in the period
Scenario: Purchase on the end date counts as in the period
  Given "Company B" buys 2 crore of shares on "2026-09-30"
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the line of "Company B" shows cost_of_investment_between "2.0" crore

# E3 — Edge case: the fund's own year starts in January, so the start-of-year value is as of 31 December
Scenario: January financial year on the fund
  Given Company C held shares since 2025, worth 12 crore at 31 December 2025 and 15 crore at 31 March 2026
  And the fund starts its financial year in January
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the line of "Company C" shows fmv_fy_start "12.0" crore

# E4 — Edge case: the fund has no setting, so the entity's January year applies
Scenario: Entity setting used when the fund has none
  Given Company C held shares since 2025, worth 12 crore at 31 December 2025 and 15 crore at 31 March 2026
  And the entity starts its financial year in January and the fund has no setting of its own
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the line of "Company C" shows fmv_fy_start "12.0" crore

# E5 — Edge case: a quarter starting on the financial year start has the same value for both days
Scenario: Quarter starts at the financial year start
  Given Company C held shares since 2025, worth 12 crore at 31 December 2025 and 15 crore at 31 March 2026
  When the consolidated report data is built for "2026-04-01" to "2026-06-30"
  Then the line of "Company C" shows fmv_prior "15.0" crore
  And the line of "Company C" shows fmv_fy_start "15.0" crore

# E6 — Edge case: more was committed and collected after 30 Sep; the report for 30 Sep leaves it out
Scenario: Past end date shows the money figures as of that date
  Given the fund has commitments and collections, some of them dated after 30 September 2026
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the line of "Company A" shows committed_amount "502.0" crore
  And the line of "Company A" shows collected_amount "125.5" crore

# E7 — Edge case: a company with no sale has no exits and its cost still held is prior plus the period
Scenario: No exits
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the line of "Company B" shows cost_of_sold_between "0.0" crore
  And the roll-forward of "Company B" adds up

# E8 — Edge case: the gross cost stays 50 Cr although 5 Cr was exited
Scenario: Gross cost is unchanged by exits
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the line of "Company A" shows cost_of_investment "50.0" crore
  And the line of "Company A" shows cost_of_remaining "45.0" crore

# E9 — Edge case: nothing was held before the start date
Scenario: No holding before the start date
  Given Company D first buys 5 crore of shares on "2026-08-10"
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the line of "Company D" shows cost_of_remaining_prior "0.0" crore

# E10 — Edge case: value 24 to 21 is -12.5%
Scenario: Value falls
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the line of "Company B" shows fmv_change_percent "-12.5"

# E11 — Edge case: 10 Cr more is bought at the same price; nothing is revalued but the change is +100%
Scenario: A purchase in the quarter raises the change
  Given Company E is worth 10 crore at 30 June and buys 10 crore more at the same price in August
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the line of "Company E" shows fmv_change_percent "100.0"

# E12 — Edge case: no value before the start date, nothing to compare with
Scenario: No prior value
  Given Company D first buys 5 crore of shares on "2026-08-10"
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the line of "Company D" shows fmv_change_percent "N/A"

# E13 — Edge case: no value at the financial year start
Scenario: No value at the financial year start
  Given Company D first buys 5 crore of shares on "2026-08-10"
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the line of "Company D" shows fmv_fy_start_change_percent "N/A"

# E14 — Edge case: a template that reads only the old fields renders as before
Scenario: Existing consolidated template
  Given portfolio companies "Gamma Corp, Ace Limited" are created in that order
  And "Ace Limited" has an IRR of 14 in the fund "Alpha Fund"
  And a consolidated portfolio report "Portfolio Overview" with template "Cover and Summary"
  When the consolidated report is built for the selected companies
  Then the document shows "Ace Limited" with "Alpha Fund" IRR 14
