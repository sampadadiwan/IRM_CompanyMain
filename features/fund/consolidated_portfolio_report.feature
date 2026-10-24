@rack_test
Feature: Consolidated portfolio report
  A consolidated report is built once for all selected companies, from a template that loops the companies.
  Worked examples: openspec/changes/portfolio-report-combined-packet/design.md#worked-examples

Background:
  Given Im logged in as a user "first_name=Meera" for an entity "name=Alpha Ventures;entity_type=Investment Fund"
  Given the user has role "company_admin"

# H1 — Happy path: tick Consolidated and save
Scenario: Tick Consolidated on a report
  When I create a portfolio report "Portfolio Overview" ticking Consolidated
  And I reopen the portfolio report for editing
  Then the Consolidated box is ticked
  And the portfolio report "Portfolio Overview" has no sections

# H16 — a section filled in anyway is still saved
Scenario: A consolidated report keeps a section that was filled in
  When I create a portfolio report "Portfolio Overview" ticking Consolidated with the section "Overview" filled in
  Then the portfolio report "Portfolio Overview" has the section "Overview"

# H17 — sections are optional for a normal report too
Scenario: A normal report is saved without a section
  When I create a portfolio report "Analyst Report" without ticking Consolidated and leave the section blank
  Then the portfolio report "Analyst Report" has no sections

# H18 — a report without sections is ready once it has a template
Scenario: A report without sections is ready with a template
  When I create a portfolio report "Analyst Report" without ticking Consolidated and leave the section blank
  And the portfolio report "Analyst Report" has a template
  And I visit the portfolio reports page
  Then the portfolio report "Analyst Report" shows as ready

# E1 — Edge: reports created before the change stay normal
Scenario: Existing reports are not consolidated
  Given there is an existing portfolio company "name=Ace Limited;category=Portfolio Company"
  And I setup a portfolio report "name:Analyst Report"
  When I reopen the portfolio report for editing
  Then the Consolidated box is not ticked

# H2 — Happy path: companies A-Z in the loop
Scenario: Companies are listed alphabetically
  Given portfolio companies "Gamma Corp, Ace Limited, Beta Corp" are created in that order
  And a consolidated portfolio report "Portfolio Overview" with template "Cover and Summary"
  When the consolidated report is built for the selected companies
  Then the document text lists "Ace Limited, Beta Corp, Gamma Corp" in that order, each once

# H3 — Happy path: per-company values in the loop
Scenario: Each company shows its own IRR in its fund
  Given portfolio companies "Gamma Corp, Ace Limited, Beta Corp" are created in that order
  And "Ace Limited" has an IRR of 14 in the fund "Alpha Fund"
  And "Beta Corp" has an IRR of 9 in the fund "Alpha Fund"
  And a consolidated portfolio report "Portfolio Overview" with template "Cover and Summary"
  When the consolidated report is built for the selected companies
  Then the document shows "Ace Limited" with "Alpha Fund" IRR 14
  And the document shows "Beta Corp" with "Alpha Fund" IRR 9

# H4 — Happy path: no extracts are read or created
Scenario: Building a consolidated report needs no extracts
  Given portfolio companies "Gamma Corp, Ace Limited, Beta Corp" are created in that order
  And a consolidated portfolio report "Portfolio Overview" with template "Cover and Summary"
  When the consolidated report is built for the selected companies
  Then no extract was created

# E4 — Edge: a company with no investments and no logo is still listed
Scenario: Company without investments or logo is still listed
  Given portfolio companies "Gamma Corp, Ace Limited" are created in that order
  And "Ace Limited" has an IRR of 14 in the fund "Alpha Fund"
  And a consolidated portfolio report "Portfolio Overview" with template "Cover and Summary"
  When the consolidated report is built for the selected companies
  Then the document shows "Gamma Corp" with no fund lines
  And the document shows "Ace Limited" with "Alpha Fund" IRR 14

# H15 — Happy path: fund totals across the selected companies
Scenario: Fund totals add up the selected companies
  Given portfolio companies "Gamma Corp, Ace Limited, Beta Corp" are created in that order
  And "Ace Limited" has an IRR of 14 in the fund "Alpha Fund"
  And "Beta Corp" has an IRR of 9 in the fund "Alpha Fund"
  And "Gamma Corp" has an IRR of 5 in the fund "Alpha Fund"
  And the companies have these custom fields: "Ace Limited=100, Beta Corp=250, Gamma Corp=50"
  And a consolidated portfolio report "Portfolio Overview" with the fund totals template
  When the consolidated report is built for the selected companies
  Then the "Alpha Fund" total FMV and cost are the sums of the companies' lines
  And the "Alpha Fund" total commitment is 400

# E20 — Edge: one entry per fund, summed over that fund's companies only
Scenario: One total per fund
  Given portfolio companies "Gamma Corp, Ace Limited, Beta Corp" are created in that order
  And "Ace Limited" has an IRR of 14 in the fund "Alpha Fund"
  And "Beta Corp" has an IRR of 9 in the fund "Alpha Fund"
  And "Gamma Corp" has an IRR of 5 in the fund "Beta Fund"
  And the companies have these custom fields: "Ace Limited=100, Beta Corp=250, Gamma Corp=50"
  And a consolidated portfolio report "Portfolio Overview" with the fund totals template
  When the consolidated report is built for the selected companies
  Then the "Alpha Fund" total FMV and cost are the sums of the companies' lines
  And the "Alpha Fund" total commitment is 350
  And the "Beta Fund" total FMV and cost are the sums of the companies' lines
  And the "Beta Fund" total commitment is 50

# E21 — Edge: a blank number counts as zero and a text field has no total
Scenario: Blank and text custom fields
  Given portfolio companies "Gamma Corp, Ace Limited, Beta Corp" are created in that order
  And "Ace Limited" has an IRR of 14 in the fund "Alpha Fund"
  And "Beta Corp" has an IRR of 9 in the fund "Alpha Fund"
  And "Gamma Corp" has an IRR of 5 in the fund "Alpha Fund"
  And the companies have these custom fields: "Ace Limited=100, Beta Corp=250"
  And a consolidated portfolio report "Portfolio Overview" with the fund totals template
  When the consolidated report is built for the selected companies
  Then the "Alpha Fund" total commitment is 350
  And the "Alpha Fund" total has no value for the text field
