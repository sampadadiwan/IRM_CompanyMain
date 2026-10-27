@rack_test
Feature: Company report, what the fund bought and sold in the quarter
  Each fund's data in the company report says whether the company was bought or sold in the period (the start date to the end
  date, both included) and the cost of each: cost_of_investment_between for purchases and cost_of_sold_between for sales (the
  cost of what was sold, positive), so a template can write "The fund invested X in the quarter" only when it did.
  Worked examples: openspec/changes/portfolio-report-quarter-activity-and-change-sign/design.md#worked-examples

Background:
  Given Im logged in as a user "first_name=Meera" for an entity "name=Alpha Ventures;entity_type=Investment Fund"
  Given the user has role "company_admin"
  And the Inflexor quarter data

# H1 — Happy path: Company A bought 500 shares for 10 Cr on 15 Aug
Scenario: H1 Purchase in the quarter
  When the company report data is built for "2026-07-01" to "2026-09-30"
  Then the fund data of "Company A" shows buy_pis_present "true"
  And the fund data of "Company A" shows cost_of_investment_between "10.0" crore

# H2 — Happy path: a second purchase of 4 Cr on 20 Sep makes 14 Cr
Scenario: H2 Several purchases in the quarter
  Given "Company A" buys 4 crore of shares on "2026-09-20"
  When the company report data is built for "2026-07-01" to "2026-09-30"
  Then the fund data of "Company A" shows cost_of_investment_between "14.0" crore

# H3 — Happy path: 500 shares sold for 7 Cr at a cost of 5 Cr on 10 Sep, the cost of sold is 5 Cr and not the 7 Cr received
Scenario: H3 Sale in the quarter
  When the company report data is built for "2026-07-01" to "2026-09-30"
  Then the fund data of "Company A" shows sell_pis_present "true"
  And the fund data of "Company A" shows cost_of_sold_between "5.0" crore

# H4 — Happy path: both the purchase and the sale are in the quarter
Scenario: H4 Buy and sale in the same quarter
  When the company report data is built for "2026-07-01" to "2026-09-30"
  Then the fund data of "Company A" shows buy_pis_present "true"
  And the fund data of "Company A" shows sell_pis_present "true"
  And the fund data of "Company A" shows cost_of_investment_between "10.0" crore
  And the fund data of "Company A" shows cost_of_sold_between "5.0" crore

# H5 — Happy path: a second fund has its own 3 Cr purchase, each fund counts only its own
Scenario: H5 Each fund has its own figures
  Given "Company A" buys 3 crore of shares in the second fund "Beta Fund" on "2026-09-01"
  When the company report data is built for "2026-07-01" to "2026-09-30"
  Then the fund data of "Company A" shows cost_of_investment_between "10.0" crore
  And the data of "Company A" in the fund "Beta Fund" shows cost_of_investment_between "3.0" crore
  And the data of "Company A" in the fund "Beta Fund" shows cost_of_sold_between "0.0" crore

# H6 — Happy path: the figures up to the end date are as before
Scenario: H6 Existing fund data unchanged
  When the company report data is built for "2026-07-01" to "2026-09-30"
  Then the fund data of "Company A" shows cost_of_investment "50.0" crore
  And the fund data of "Company A" shows cost_of_remaining "45.0" crore
  And the fund data of "Company A" shows sold_amount "7.0" crore

# E1 — Edge case: Company B has only its January purchase, nothing in the quarter
Scenario: E1 No trades in the quarter
  When the company report data is built for "2026-07-01" to "2026-09-30"
  Then the fund data of "Company B" shows buy_pis_present "false"
  And the fund data of "Company B" shows sell_pis_present "false"
  And the fund data of "Company B" shows cost_of_investment_between "0.0" crore
  And the fund data of "Company B" shows cost_of_sold_between "0.0" crore

# E2 — Edge case: from 11 Sep both the 15 Aug purchase and the 10 Sep sale are earlier
Scenario: E2 Only earlier trades
  When the company report data is built for "2026-09-11" to "2026-09-30"
  Then the fund data of "Company A" shows buy_pis_present "false"
  And the fund data of "Company A" shows sell_pis_present "false"
  And the fund data of "Company A" shows cost_of_investment_between "0.0" crore
  And the fund data of "Company A" shows cost_of_sold_between "0.0" crore

# E3 — Edge case: a purchase on the start date is counted
Scenario: E3 Buy on the start date
  When the company report data is built for "2026-08-15" to "2026-09-30"
  Then the fund data of "Company A" shows buy_pis_present "true"
  And the fund data of "Company A" shows cost_of_investment_between "10.0" crore

# E4 — Edge case: a purchase on the end date is counted
Scenario: E4 Buy on the end date
  When the company report data is built for "2026-07-01" to "2026-08-15"
  Then the fund data of "Company A" shows buy_pis_present "true"
  And the fund data of "Company A" shows cost_of_investment_between "10.0" crore

# E5 — Edge case: from 16 Aug the 15 Aug purchase is the day before the start
Scenario: E5 Day before the start
  When the company report data is built for "2026-08-16" to "2026-09-30"
  Then the fund data of "Company A" shows buy_pis_present "false"
  And the fund data of "Company A" shows cost_of_investment_between "0.0" crore

# E6 — Edge case: to 14 Aug the 15 Aug purchase and the 10 Sep sale are after the end date
Scenario: E6 Day after the end
  When the company report data is built for "2026-07-01" to "2026-08-14"
  Then the fund data of "Company A" shows buy_pis_present "false"
  And the fund data of "Company A" shows sell_pis_present "false"
  And the fund data of "Company A" shows cost_of_investment_between "0.0" crore

# E7 — Edge case: from 1 Sep the purchase is earlier and only the sale is in the period
Scenario: E7 Sale only
  When the company report data is built for "2026-09-01" to "2026-09-30"
  Then the fund data of "Company A" shows buy_pis_present "false"
  And the fund data of "Company A" shows cost_of_investment_between "0.0" crore
  And the fund data of "Company A" shows sell_pis_present "true"
  And the fund data of "Company A" shows cost_of_sold_between "5.0" crore

# E8 — Edge case: a sale on the end date is counted
Scenario: E8 Sale on the end date
  When the company report data is built for "2026-07-01" to "2026-09-10"
  Then the fund data of "Company A" shows sell_pis_present "true"
  And the fund data of "Company A" shows cost_of_sold_between "5.0" crore

# E9 — Edge case: Company B's purchase of 3 Cr in the same fund is not in Company A's 10 Cr
Scenario: E9 Another company's purchase
  Given "Company B" buys 3 crore of shares on "2026-09-01"
  When the company report data is built for "2026-07-01" to "2026-09-30"
  Then the fund data of "Company A" shows cost_of_investment_between "10.0" crore
  And the fund data of "Company B" shows cost_of_investment_between "3.0" crore

# E10 — Edge case: Company H bought and sold everything before the quarter, its fund data is still there with nothing in the quarter
Scenario: E10 Exited before the quarter
  Given Company H bought 6 crore of shares on "2026-02-01" and sold them all on "2026-05-01"
  When the company report data is built for "2026-07-01" to "2026-09-30"
  Then the fund data of "Company H" shows buy_pis_present "false"
  And the fund data of "Company H" shows sell_pis_present "false"
  And the fund data of "Company H" shows cost_of_investment_between "0.0" crore
  And the fund data of "Company H" shows cost_of_sold_between "0.0" crore

# X1 — Error case: the job hands the dates over as text, and the result is the same as for dates (H1, H3)
Scenario: X1 Dates arrive as text
  When the company report data is built for the text dates "2026-07-01" to "2026-09-30"
  Then the fund data of "Company A" shows buy_pis_present "true"
  And the fund data of "Company A" shows cost_of_investment_between "10.0" crore
  And the fund data of "Company A" shows sell_pis_present "true"
  And the fund data of "Company A" shows cost_of_sold_between "5.0" crore
