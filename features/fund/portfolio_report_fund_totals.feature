@rack_test
Feature: Consolidated report, the total for a fund
  Each fund's total holds the fund's money as of the end date (taken once), cost and value added up over the companies,
  the % changes and collection % worked out from those, the number of companies, and the fund's own returns.
  Worked examples: openspec/changes/portfolio-report-fund-metrics/design.md#worked-examples

Background:
  Given Im logged in as a user "first_name=Meera" for an entity "name=Alpha Ventures;entity_type=Investment Fund"
  Given the user has role "company_admin"
  And the Inflexor quarter data

# H9 — Happy path: 125.5 of 502 Cr collected is 25%; 376.5 Cr (75%) is still to be called
Scenario: Collection percentages
  Given the fund has commitments and collections, some of them dated after 30 September 2026
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the total of "Inflexor Technology Discovery Fund 1" shows collected_percent "25.0"
  And the total of "Inflexor Technology Discovery Fund 1" shows uncollected_amount "376.5" crore
  And the total of "Inflexor Technology Discovery Fund 1" shows uncollected_percent "75.0"

# H10 — Happy path: value at 30 Jun 50 + 24 = 74, at 30 Sep 60 + 21 = 81, change 9.5%
Scenario: Totals add up the companies
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the total of "Inflexor Technology Discovery Fund 1" shows fmv_prior "74.0" crore
  And the total of "Inflexor Technology Discovery Fund 1" shows fmv "81.0" crore
  And the total of "Inflexor Technology Discovery Fund 1" shows fmv_change_percent "9.5"

# H11 — Happy path: cost still held 70 + invested 10 - exits 5 = 75
Scenario: Roll-forward total adds up
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the total of "Inflexor Technology Discovery Fund 1" shows cost_of_remaining_prior "70.0" crore
  And the total of "Inflexor Technology Discovery Fund 1" shows cost_of_investment_between "10.0" crore
  And the total of "Inflexor Technology Discovery Fund 1" shows cost_of_sold_between "5.0" crore
  And the total of "Inflexor Technology Discovery Fund 1" shows cost_of_remaining "75.0" crore

# H12 — Happy path: the latest TVPI run on or before the end date
Scenario: Latest fund ratio on or before the end date
  Given the fund has a "TVPI" ratio of 1.1 on "2026-06-30"
  And the fund has a "TVPI" ratio of 1.2 on "2026-09-30"
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the total of "Inflexor Technology Discovery Fund 1" shows tvpi "1.2"

# H13 — Happy path: the fund's IRR is its XIRR
Scenario: IRR comes from the fund's XIRR
  Given the fund has a "XIRR" ratio of 18.5 on "2026-09-30"
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the total of "Inflexor Technology Discovery Fund 1" shows irr "18.5"

# E15 — Edge case: two companies in the fund, the fund's 502 Cr counted once
Scenario: Money figures not multiplied by the number of companies
  Given the fund has commitments and collections, some of them dated after 30 September 2026
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the total of "Inflexor Technology Discovery Fund 1" shows committed_amount "502.0" crore

# E16 — Edge case: nothing committed, so no percentage
Scenario: Zero commitment
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the total of "Inflexor Technology Discovery Fund 1" shows collected_percent "N/A"
  And the total of "Inflexor Technology Discovery Fund 1" shows uncollected_percent "N/A"

# E17 — Edge case: three companies selected, two invested in the fund
Scenario: Company count counts only companies in the fund
  Given Company F is selected but has no investment
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the total of "Inflexor Technology Discovery Fund 1" shows company_count "2"

# E18 — Edge case: an investment after the end date is not counted
Scenario: Investment after the end date is not counted
  Given Company G is selected and its only investment in the fund is dated "2026-10-05"
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the total of "Inflexor Technology Discovery Fund 1" shows company_count "2"
  And the total of "Inflexor Technology Discovery Fund 1" shows cost_of_investment "80.0" crore

# E19 — Edge case: a fund with no value before the period has no change to show
Scenario: Total change with no prior value
  Given a second fund "Other Fund" that only Company D invests in, buying 5 crore on "2026-08-10"
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the total of "Other Fund" shows fmv_change_percent "N/A"

# E20 — Edge case: a run dated after the end date is ignored
Scenario: Run after the end date ignored
  Given the fund has a "TVPI" ratio of 1.2 on "2026-09-30"
  And the fund has a "TVPI" ratio of 1.5 on "2026-10-15"
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the total of "Inflexor Technology Discovery Fund 1" shows tvpi "1.2"

# E21 — Edge case: a ratio that was never run
Scenario: Ratio never run
  Given the fund has a "TVPI" ratio of 1.2 on "2026-09-30"
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the total of "Inflexor Technology Discovery Fund 1" shows dpi "N/A"

# E22 — Edge case: a ratio that exists only in another scenario
Scenario: Other scenarios ignored
  Given the fund has a "TVPI" ratio of 1.8 on "2026-09-30" in the scenario "Stress"
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the total of "Inflexor Technology Discovery Fund 1" shows tvpi "N/A"
