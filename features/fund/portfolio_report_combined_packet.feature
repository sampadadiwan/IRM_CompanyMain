@rack_test
Feature: Portfolio report combined packet
  A run builds an ordered list of reports and joins the pieces into one combined document.
  Worked examples: openspec/changes/portfolio-report-combined-packet/design.md#worked-examples

Background:
  Given Im logged in as a user "first_name=Meera" for an entity "name=Alpha Ventures;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given portfolio companies "Gamma Corp, Ace Limited, Beta Corp" are created in that order
  And "Ace Limited" has a Revenue KPI of 1000
  And "Beta Corp" has a Revenue KPI of 2500
  And a normal portfolio report "Analyst Report" with templates "Company One-Pager, Company Profile"
  And a consolidated portfolio report "Portfolio Overview" with the fixture template "Cover and Summary"
  And a consolidated portfolio report "Disclaimer" with the fixture template "Legal Disclaimer"
  And extracts with data exist for "Ace Limited, Beta Corp" for report "Analyst Report"

# H5 — Happy path: three rows give one combined file in row order
Scenario: Three-row list, one combined file
  When I run the portfolio report with rows "Portfolio Overview:Cover and Summary, Analyst Report:Company One-Pager, Disclaimer:Legal Disclaimer"
  Then one combined document "Cover and Summary 2026-01-01 to 2026-09-30 - 3 companies" exists in Portfolio Reports / Generated Portfolio Reports
  And the combined document "Cover and Summary" reads in this order: "Portfolio Overview | Summary notes | Legal Disclaimer"
  And in the combined document "Cover and Summary" the company pages run "Ace Limited, Beta Corp, Gamma Corp"
  And each company has its own "Company One-Pager" report document
  And no document exists for the consolidated part "Legal Disclaimer"
  And the completion message links to "Cover and Summary 2026-01-01 to 2026-09-30 - 3 companies"

# E2 — Edge: only a consolidated row still gives a combined document
Scenario: Only a consolidated row
  When I run the portfolio report with rows "Portfolio Overview:Cover and Summary"
  Then one combined document "Cover and Summary 2026-01-01 to 2026-09-30 - 3 companies" exists in Portfolio Reports / Generated Portfolio Reports
  And the combined document "Cover and Summary" contains "Portfolio Overview"

# E3 — Edge: one normal report for one company makes no combined document
Scenario: One normal report, one company
  Given the run is for the companies "Ace Limited"
  When I run the portfolio report with rows "Analyst Report:Company One-Pager"
  Then no combined document exists
  And "Ace Limited" has its own "Company One-Pager" report document
  And the completion message links to "Company One-Pager Ace Limited"

# E5 — Edge: a company without an extract still gets a section, and it is information, not an error
Scenario: No extract, generate missing off
  When I run the portfolio report with rows "Portfolio Overview:Cover and Summary, Analyst Report:Company One-Pager, Disclaimer:Legal Disclaimer"
  Then the completion message says "The following companies had no extract: Gamma Corp"
  And the completion message is a success
  And the combined document "Cover and Summary" contains "No data available"

# E7 — Edge: two rows of the same report share each company's extract
Scenario: Same report, two templates
  Given no extracts exist
  When I run the portfolio report with rows "Analyst Report:Company One-Pager, Analyst Report:Company Profile" and generate missing extracts on
  Then 3 extracts exist for report "Analyst Report"
  And each company has its own "Company One-Pager" report document
  And each company has its own "Company Profile" report document

# E9 — Edge: a run queued before release still works
Scenario: Run queued with the original arguments
  When a job queued with only the original arguments is performed for "Analyst Report:Company One-Pager"
  Then one combined document "Company One-Pager 2026-01-01 to 2026-09-30 - 3 companies" exists in Portfolio Reports / Generated Portfolio Reports
  And each company has its own "Company One-Pager" report document

# E10 — Edge: regenerating replaces company reports and saves a new combined file
Scenario: Regenerating
  When I run the portfolio report with rows "Portfolio Overview:Cover and Summary, Analyst Report:Company One-Pager, Disclaimer:Legal Disclaimer"
  And I run the portfolio report with rows "Portfolio Overview:Cover and Summary, Analyst Report:Company One-Pager, Disclaimer:Legal Disclaimer"
  Then "Ace Limited" has its own "Company One-Pager" report document
  And 2 combined documents named "Cover and Summary" exist

# E11 — Edge: different real templates join into an intact package
Scenario: Different templates join cleanly
  When I run the portfolio report with rows "Portfolio Overview:Cover and Summary, Analyst Report:Company One-Pager, Disclaimer:Legal Disclaimer"
  Then the combined document "Cover and Summary" package is intact
  And the combined document "Cover and Summary" contains "QUERIES FOR MANAGEMENT"
  And the combined document "Cover and Summary" contains "Legal Disclaimer"

# E22 — Edge: a part that fills its page leaves no blank page before the next part
Scenario: No blank page between parts
  When I run the portfolio report with rows "Portfolio Overview:Cover and Summary, Analyst Report:Company One-Pager, Disclaimer:Legal Disclaimer"
  Then every part of the combined document "Cover and Summary" after the first starts a new page without a break paragraph of its own

# X6 — Failure: a company's section fails, the rest is kept
Scenario: A company section fails
  Given generating "Company One-Pager" for "Beta Corp" will fail
  When I run the portfolio report with rows "Portfolio Overview:Cover and Summary, Analyst Report:Company One-Pager, Disclaimer:Legal Disclaimer"
  Then the completion message says "Beta Corp"
  And the completion message is an error
  And an error email is sent
  And in the combined document "Cover and Summary" the company pages run "Ace Limited, Gamma Corp"
  And in the combined document "Cover and Summary" the company pages do not include "Beta Corp"
  And "Beta Corp" has no "Company One-Pager" report document

# X7 — Failure: a consolidated part fails, the rest is kept
Scenario: A consolidated part fails
  Given generating the consolidated part "Cover and Summary" will fail
  When I run the portfolio report with rows "Portfolio Overview:Cover and Summary, Analyst Report:Company One-Pager, Disclaimer:Legal Disclaimer"
  Then the completion message says "Cover and Summary (consolidated)"
  And the completion message is an error
  And an error email is sent
  And the combined document "Cover and Summary" contains "Legal Disclaimer"
  And in the combined document "Cover and Summary" the company pages run "Ace Limited, Beta Corp, Gamma Corp"

# X8 — Failure: nothing generated means no combined document
Scenario: Every part fails
  Given every part will fail to generate
  When I run the portfolio report with rows "Portfolio Overview:Cover and Summary, Analyst Report:Company One-Pager, Disclaimer:Legal Disclaimer"
  Then the completion message is an error
  And an error email is sent
  And no combined document exists

# X9 — Failure: joining fails, company reports are kept
Scenario: Joining fails
  Given joining the parts will fail
  When I run the portfolio report with rows "Portfolio Overview:Cover and Summary, Analyst Report:Company One-Pager, Disclaimer:Legal Disclaimer"
  Then the completion message says "Error merging portfolio report documents"
  And the completion message is an error
  And an error email is sent
  And each company has its own "Company One-Pager" report document
  And no combined document exists
