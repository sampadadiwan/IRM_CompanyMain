@rack_test
Feature: Company report, the data of each fund
  In the report of one company, each fund's data holds what the fund received from sales up to the end date and the
  cost of what is still held, besides the existing fmv, cost of investment, irr and moic.
  Worked examples: openspec/changes/portfolio-report-fund-metrics/design.md#worked-examples

Background:
  Given Im logged in as a user "first_name=Meera" for an entity "name=Alpha Ventures;entity_type=Investment Fund"
  Given the user has role "company_admin"
  And the Inflexor quarter data

# H14 — Happy path: 500 shares sold for 7 Cr on 10 Sep
Scenario: Sold amount
  When the company report data is built for "2026-07-01" to "2026-09-30"
  Then the fund data of "Company A" shows sold_amount "7.0" crore

# H15 — Happy path: bought for 50 Cr, sold at a cost of 5 Cr: 45 Cr still held, the cost of investment stays 50 Cr
Scenario: Cost of remaining on the company page
  When the company report data is built for "2026-07-01" to "2026-09-30"
  Then the fund data of "Company A" shows cost_of_remaining "45.0" crore
  And the fund data of "Company A" shows cost_of_investment "50.0" crore

# E23 — Edge case: a sale after the end date is not part of what was received by then
Scenario: Sale after the end date ignored
  Given "Company A" sells 2 crore of shares on "2026-10-05"
  When the company report data is built for "2026-07-01" to "2026-09-30"
  Then the fund data of "Company A" shows sold_amount "7.0" crore

# E24 — Edge case: nothing sold
Scenario: No sales
  When the company report data is built for "2026-07-01" to "2026-09-30"
  Then the fund data of "Company B" shows sold_amount "0.0" crore
