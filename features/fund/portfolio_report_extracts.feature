@javascript
Feature: Portfolio report extracts
  Extracts without documents, the dashboard widget and deleting an extract.
  Worked examples: openspec/changes/portfolio-report-combined-packet/design.md#worked-examples

Background:
  Given Im logged in as a user "first_name=TestAdmin" for an entity "name=TestEnt;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is an existing portfolio company "name=Delta Inc;category=Portfolio Company"
  Given I setup a portfolio report "name:Analyst Report;include_kpi:true;include_portfolio_investments:true"

# H11 — Happy path: extract built from notes and KPIs when there are no documents
Scenario: Notes and KPIs stand in for missing documents
  Given the company has notes and KPIs but no documents
  When the extract is generated for the company
  Then the extract has data
  And the extract records no source documents
  And the LLM was given the notes and the KPIs
  And a warning says no documents were found and the extract was built from notes and KPIs

# H11 — in a bulk run the warning is sent once, at the end, not per company
Scenario: A bulk run reports missing documents once
  Given the company has notes and KPIs but no documents
  When the extracts are generated for the company in a bulk run
  Then the bulk run reports the missing documents in one warning at the end

# E12 — Edge: KPIs alone are enough
Scenario: KPIs alone are enough
  Given the company has KPIs but no documents or notes
  When the extract is generated for the company
  Then the extract has data
  And the LLM was given the KPIs and no notes

# E12 — Edge: a KPI's display value (currency, unit, %) is sent instead of the bare number
Scenario: KPIs keep their display value
  Given the company has a Revenue KPI shown as "₹1.2M" but no documents or notes
  When the extract is generated for the company
  Then the LLM was given the KPI as "₹1.2M"

# E13 — Edge: documents present, extract built exactly as before
Scenario: Extracts built from documents are unchanged
  Given There is a kpi report form type setup
  And the company has notes and KPIs but no documents
  And I add relevant documents to the kpi report
  When the extract is generated for the company
  Then the extract has data
  And the LLM was given the documents and notes but no KPIs
  And no warning is shown

# E14 — Edge: nothing at all leaves the extract empty and the LLM uncalled
Scenario: Nothing at all leaves the extract empty
  Given the company has no documents, notes or KPIs in the period
  When the extract is generated for the company
  Then the LLM was not called
  And the extract has no data
  And the company is reported as having nothing to extract from

# H12 — Happy path: the widget skips a blank latest extract and shows the latest with data
Scenario: A blank latest extract is skipped by the widget
  Given the company has extracts for the report:
    | end_date   | data |
    | 2025-03-31 | yes  |
    | 2025-06-30 | yes  |
    | 2025-09-30 | no   |
  And the company dashboard has a Portfolio Report widget for the report
  When I open the company dashboard
  Then the widget shows the extract ending "2025-06-30"

# H12 — however many blank extracts come first (nothing, or an empty {}), the widget still finds the one with data
Scenario: Many blank extracts in a row are skipped by the widget
  Given the company has extracts for the report:
    | end_date   | data |
    | 2025-03-31 | yes  |
    | 2025-06-30 | yes  |
  And the company has 12 blank extracts newer than those
  And the company dashboard has a Portfolio Report widget for the report
  When I open the company dashboard
  Then the widget shows the extract ending "2025-06-30"

# E15 — Edge: only blank extracts hide the widget
Scenario: Only blank extracts hide the widget
  Given the company has extracts for the report:
    | end_date   | data |
    | 2025-06-30 | no   |
    | 2025-09-30 | no   |
  And the company dashboard has a Portfolio Report widget for the report
  When I open the company dashboard
  Then the widget does not show any extract

# H13 — Happy path: delete an extract from its details page
Scenario: Delete an extract with confirmation
  Given the company has extracts for the report:
    | end_date   | data |
    | 2025-06-30 | yes  |
  When I open the details page of the extract ending "2025-06-30"
  And I click Delete and confirm
  Then I am on the extract list of the report with "Portfolio report extract deleted successfully."
  And the extract no longer exists

# E18 — Edge: cancelling the confirmation keeps the extract
Scenario: Cancelling keeps the extract
  Given the company has extracts for the report:
    | end_date   | data |
    | 2025-06-30 | yes  |
  When I open the details page of the extract ending "2025-06-30"
  And I click Delete and cancel
  Then the extract still exists
  And the details page is unchanged

# E16 — Edge: a deleted extract is regenerated only when asked
Scenario Outline: A deleted extract is regenerated when asked
  Given the company has notes and KPIs but no documents
  And the company has an extract with data for the whole period
  When I open the details page of the extract for the whole period
  And I click Delete and confirm
  And the report is generated for the company with generate missing extracts "<setting>"
  Then <outcome>

  Examples:
    | setting | outcome                                                  |
    | on      | a new extract with data exists for the company and period |
    | off     | only an empty extract exists for the company and period   |

# X15 — Failure: a user without permission cannot delete
Scenario: Delete without permission is refused
  Given the company has extracts for the report:
    | end_date   | data |
    | 2025-06-30 | yes  |
  And a user "Pat" with no access rights in the same entity
  When "Pat" signs in
  And "Pat" sends a delete request for the extract ending "2025-06-30"
  Then the extract still exists
  And the policy refuses "Pat" to delete the extract

# X16 — Failure: another entity's extract cannot be deleted
Scenario: Another entity's extract cannot be deleted
  Given the company has extracts for the report:
    | end_date   | data |
    | 2025-06-30 | yes  |
  And a company admin "Omar" of another entity
  When "Omar" signs in
  And "Omar" sends a delete request for the extract ending "2025-06-30"
  Then the extract still exists
