@javascript
Feature: Portfolio report parts list
  The options page builds an ordered list of reports. The browser checks the rows; the server repeats the checks.
  Worked examples: openspec/changes/portfolio-report-combined-packet/design.md#worked-examples

Background:
  Given Im logged in as a user "first_name=Meera" for an entity "name=Alpha Ventures;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given portfolio companies "Gamma Corp, Ace Limited, Beta Corp" are created in that order
  And a normal portfolio report "Analyst Report" with templates "Company One-Pager, Company Profile"
  And a normal portfolio report "Quarterly Review" with templates "Review Pack"
  And a consolidated portfolio report "Portfolio Overview" with the fixture template "Cover and Summary"
  And a consolidated portfolio report "Disclaimer" with the fixture template "Legal Disclaimer"
  And report runs and extract runs are recorded instead of queued

# H7 — Happy path: add and remove rows
Scenario: Add and remove rows
  When I open the options page for the selected companies
  Then the options page has 1 report row
  When I click Add report
  And I click Add report
  Then the options page has 3 report rows
  When I remove report row 2
  Then the options page has 2 report rows
  When I remove report row 2
  Then the options page has 1 report row
  And report row 1 has no Remove button

# H8 — Happy path: templates follow the row's report
Scenario: Templates follow the row's report
  When I open the options page for the selected companies
  And I click Add report
  And I choose the report "Quarterly Review" in row 2
  Then row 2 offers only the templates "Review Pack - Quarterly Review"
  And row 2 has the template "Review Pack" selected
  And row 1 offers only the templates "Company One-Pager - Analyst Report, Company Profile - Analyst Report"

# H9 — Happy path: Extracts Only covers the normal reports
Scenario: Extracts only on normal reports
  When I open the options page for the selected companies
  And I choose the report "Portfolio Overview (Consolidated)" in row 1
  And I click Add report
  And I click "Generate Extracts Only" on the options page
  Then extracts were queued only for "Analyst Report"

# H10 — Happy path: consolidated reports are labelled
Scenario: Consolidated label in report choices
  When I open the options page for the selected companies
  Then the report choices read "Analyst Report, Quarterly Review, Portfolio Overview (Consolidated), Disclaimer (Consolidated)"

# E6 — Edge: gaps in row numbers keep the order
Scenario: Gaps in row numbers
  When a request posts rows numbered 0, 2 and 5 for "Analyst Report:Company One-Pager", "Portfolio Overview:Cover and Summary" and "Disclaimer:Legal Disclaimer"
  Then one report run was queued
  And the queued run starts with "Analyst Report" and continues with "Portfolio Overview, Disclaimer"

# E8 — Edge: the earlier single report fields still work
Scenario: Older single-report fields
  When a request posts one report "Analyst Report" and template "Company One-Pager" without rows
  Then one report run was queued
  And the queued run starts with "Analyst Report" and continues with ""
  And the queued run has no additional reports

# E17 — Edge: a fixed row clears its message and the list then submits
Scenario: A fixed row clears its message
  When I open the options page for the selected companies
  And I click Add report
  And I click "Generate Report" on the options page
  Then "Each template can be used only once in a list. Remove the repeated template." is shown beside row 2
  When I choose the template "Company Profile" in row 2
  Then "Each template can be used only once in a list. Remove the repeated template." is no longer shown
  When I click "Generate Report" on the options page
  Then one report run was queued
  And the queued run starts with "Analyst Report" and continues with "Analyst Report"

# X1 — Failure: a row without a template blocks the submit
Scenario: Row without a template
  Given a normal portfolio report "Empty Report" with no templates
  When I open the options page for the selected companies
  And I click Add report
  And I choose the report "Empty Report" in row 2
  And I click "Generate Report" on the options page
  Then "Choose a template for every report in the list." is shown beside row 2
  And nothing was queued

# X2 — Failure: a repeated template blocks the submit
Scenario: Repeated template
  When I open the options page for the selected companies
  And I click Add report
  And I click "Generate Report" on the options page
  Then "Each template can be used only once in a list. Remove the repeated template." is shown beside row 2
  And nothing was queued

# X3 — Failure: a template from another report is refused
Scenario: Template from another report
  When a request posts the rows "Analyst Report:Review Pack" in mode "full_report"
  Then "The selected template does not belong to the chosen report." is shown on the options page
  And nothing was queued

# X4 — Failure: a report from another entity is not found
Scenario: Report from another entity
  Given another entity has a report "Other Fund Report" and a portfolio company "Other Co"
  When a request posts a row naming the other entity's report
  Then nothing was queued

# X5 — Failure: Extracts Only with consolidated reports only is blocked
Scenario: Extracts only, all consolidated
  When I open the options page for the selected companies
  And I choose the report "Portfolio Overview (Consolidated)" in row 1
  And I click "Generate Extracts Only" on the options page
  Then "Consolidated reports don't use extracts, so there is nothing to generate." is shown on the options page
  And nothing was queued

# X10 — Failure: a company from another entity is ignored
Scenario: Company from another entity
  Given another entity has a report "Other Fund Report" and a portfolio company "Other Co"
  When a request posts one row "Analyst Report:Company One-Pager" that also names the other entity's company
  Then one report run was queued
  And the queued run does not include the other entity's company

# X11 — Failure: a user without access is refused
Scenario: No access
  Given a user "Pat" with no access rights in the same entity
  When "Pat" posts one row "Analyst Report:Company One-Pager" to the options step
  Then nothing was queued

# X12 — Failure: a posted row without a template is refused
Scenario: Posted row without a template
  When a request posts the rows "Analyst Report:" in mode "full_report"
  Then "Choose a template for every report in the list." is shown on the options page
  And nothing was queued

# X13 — Failure: a posted repeated template is refused
Scenario: Posted repeated template
  When a request posts the rows "Analyst Report:Company One-Pager, Analyst Report:Company One-Pager" in mode "full_report"
  Then "Each template can be used only once in a list. Remove the repeated template." is shown on the options page
  And nothing was queued

# X14 — Failure: posted Extracts Only with consolidated reports only is refused
Scenario: Posted extracts only, all consolidated
  When a request posts the rows "Portfolio Overview:Cover and Summary" in mode "extracts_only"
  Then "Consolidated reports don't use extracts, so there is nothing to generate." is shown on the options page
  And nothing was queued

# H14 — Happy path: a Preview that matches no company says so
Scenario: Preview with no match says so
  When I preview with a fund that has no portfolio investments
  Then "No portfolio companies match the selected filters." is shown on the options page

# E19 — Edge: Next needs a company
Scenario: Next needs a company
  When I open the company step
  Then Next is disabled
  When I choose the first company in the list
  Then Next is enabled
  When I clear the company list
  Then Next is disabled
