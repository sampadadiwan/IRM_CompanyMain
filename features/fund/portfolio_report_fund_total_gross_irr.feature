@rack_test
Feature: Consolidated report, the fund total shows the fund's Gross Portfolio IRR
  Each fund's total holds the fund's own Gross Portfolio IRR beside its IRR: the latest stored run on or before the end date,
  in the Default scenario, or "N/A" when there is none. It is the fund's, so a company's fund line does not repeat it.
  Worked examples: openspec/changes/portfolio-report-category-gross-irr/design.md#worked-examples

Background:
  Given Im logged in as a user "first_name=Meera" for an entity "name=Alpha Ventures;entity_type=Investment Fund"
  Given the user has role "company_admin"
  And the Inflexor quarter data

# H4 — Happy path: runs of 16.0 (30 Jun) and 18.0 (30 Sep), the later one on the end date is shown
Scenario: H4 Latest run on or before the end date
  Given the fund has a "Gross Portfolio IRR" ratio of 16.0 on "2026-06-30"
  And the fund has a "Gross Portfolio IRR" ratio of 18.0 on "2026-09-30"
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the total of "Inflexor Technology Discovery Fund 1" shows gross_portfolio_irr "18.0" as a number

# H5 — Happy path: the fund's IRR is its XIRR 14.2 and its Gross Portfolio IRR 18.0, side by side
Scenario: H5 Shown beside the fund's IRR
  Given the fund has a "XIRR" ratio of 14.2 on "2026-09-30"
  And the fund has a "Gross Portfolio IRR" ratio of 18.0 on "2026-09-30"
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the total of "Inflexor Technology Discovery Fund 1" shows irr "14.2" as a number
  And the total of "Inflexor Technology Discovery Fund 1" shows gross_portfolio_irr "18.0" as a number

# H6 — Happy path: two funds, 18.0 and 11.5, each total shows its own
Scenario: H6 Each fund has its own value
  Given a second fund "Other Fund" that only Company D invests in, buying 5 crore on "2026-08-10"
  And the fund has a "Gross Portfolio IRR" ratio of 18.0 on "2026-09-30"
  And the fund "Other Fund" has a "Gross Portfolio IRR" ratio of 11.5 on "2026-09-30"
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the total of "Inflexor Technology Discovery Fund 1" shows gross_portfolio_irr "18.0" as a number
  And the total of "Other Fund" shows gross_portfolio_irr "11.5" as a number

# H7 — Happy path: Company A's own IRR in the fund is 22.0 and its fund line has no Gross Portfolio IRR
Scenario: H7 Company fund line keeps the company's IRR
  Given "Company A" has an IRR of 22.0 in the Inflexor fund on "2026-09-30"
  And the fund has a "Gross Portfolio IRR" ratio of 18.0 on "2026-09-30"
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the line of "Company A" shows irr "22.0"
  And the line of "Company A" has no gross_portfolio_irr field

# E3 — Edge case: a run of 19.5 dated 15 Oct is after the end date, 18.0 is still shown
Scenario: E3 Run after the end date ignored
  Given the fund has a "Gross Portfolio IRR" ratio of 18.0 on "2026-09-30"
  And the fund has a "Gross Portfolio IRR" ratio of 19.5 on "2026-10-15"
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the total of "Inflexor Technology Discovery Fund 1" shows gross_portfolio_irr "18.0" as a number

# E4 — Edge case: the only run on or before the end date is in the Stress scenario, so there is none to show
Scenario: E4 Other scenarios ignored
  Given the fund has a "Gross Portfolio IRR" ratio of 18.0 on "2026-09-30" in the scenario "Stress"
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the total of "Inflexor Technology Discovery Fund 1" shows gross_portfolio_irr "N/A"

# E5 — Edge case: the ratio was never run, "N/A" and the report still builds
Scenario: E5 No run
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the total of "Inflexor Technology Discovery Fund 1" shows gross_portfolio_irr "N/A"

# E6 — Edge case: the only run is dated exactly on the end date, so it is used
Scenario: E6 Run exactly on the end date
  Given the fund has a "Gross Portfolio IRR" ratio of 18.0 on "2026-09-30"
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the total of "Inflexor Technology Discovery Fund 1" shows gross_portfolio_irr "18.0" as a number

# E7 — Edge case: 17.0 then 18.0 stored for the same date, the later run wins
Scenario: E7 Two runs on the same date
  Given the fund has a "Gross Portfolio IRR" ratio of 17.0 on "2026-09-30"
  And the fund has a "Gross Portfolio IRR" ratio of 18.0 on "2026-09-30"
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the total of "Inflexor Technology Discovery Fund 1" shows gross_portfolio_irr "18.0" as a number

# E8 — Edge case: a run of 0.0 is a value, not a missing one
Scenario: E8 Zero is a value
  Given the fund has a "Gross Portfolio IRR" ratio of 0.0 on "2026-09-30"
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the total of "Inflexor Technology Discovery Fund 1" shows gross_portfolio_irr "0.0" as a number

# E9 — Edge case: a negative return of -3.2 is shown as it is
Scenario: E9 Negative return
  Given the fund has a "Gross Portfolio IRR" ratio of -3.2 on "2026-09-30"
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the total of "Inflexor Technology Discovery Fund 1" shows gross_portfolio_irr "-3.2" as a number

# E10 — Edge case: a run named "Gross Portfolio IRR (USD)" is another ratio, so there is none to show
Scenario: E10 Labelled run not matched
  Given the fund has a "Gross Portfolio IRR (USD)" ratio of 18.0 on "2026-09-30"
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the total of "Inflexor Technology Discovery Fund 1" shows gross_portfolio_irr "N/A"

# E11 — Edge case: two companies in the fund, the fund's 18.0 is taken once, not 36.0
Scenario: E11 Two companies in one fund
  Given the fund has a "Gross Portfolio IRR" ratio of 18.0 on "2026-09-30"
  When the consolidated report data is built for "2026-07-01" to "2026-09-30"
  Then the total of "Inflexor Technology Discovery Fund 1" shows company_count "2"
  And the total of "Inflexor Technology Discovery Fund 1" shows gross_portfolio_irr "18.0" as a number
