# Worked examples H1–H9, H16–H18, E1–E12, E23–E27, X6 — openspec/changes/grid-columns-inline-settings/business-rules.md#1-table-columns--phase-1
# (X1–X5, X7–X9, X19, X20: features/security/grid_columns_inline_settings_isolation.feature)
Feature: Table columns in place
  Every customisable table has a columns button next to its search box that opens the table's columns in a side
  panel; saving stores the whole list at once and reloads only the table. Configure Grids shows the same list.

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;currency=INR"
    And the user has role "company_admin"
    And there is an investor named "Ravi Menon"
    And there is an investor named "Acme Family Office"
    And my firm's "Investor" form type has a text field "risk_rating"
    And the investor "Ravi Menon" has "risk_rating" set to "Low"

  # H1 — Happy path: the button sits beside the search box; the panel lists the saved columns in order
  Scenario: Button and panel list
    Given my firm's "Investor" columns are "investor_name, category, city, tag_list, investor_access_count"
    When I open the "/investors" page
    Then the columns button should be beside the search box
    When I open the columns panel
    Then the columns panel should be titled "Investors columns"
    And the columns editor should list "Stakeholder, Category, City, Tags, Access"

  # H2 — Happy path: reorder, rename, remove and add, then only the table reloads with the search kept
  Scenario: Edit and save in place
    Given my firm's "Investor" columns are "investor_name, category, city, tag_list, investor_access_count"
    When I open the "/investors" page
    And I search the table for "Ravi"
    And I open the columns panel
    And I move the column "investor_access_count" above "city"
    And I rename the column "tag_list" to "Segment"
    And I remove the column "city"
    And I add the column "Risk rating"
    And I save the columns
    Then the columns panel should close
    And the "investors" table headings should be "Stakeholder, Category, Access, Segment, Risk rating"
    And the search box should still say "Ravi"
    And a saved message should say "Investors columns saved"
    And my firm's "Investor" columns should be "investor_name, category, investor_access_count, tag_list, custom_fields.risk_rating"

  # H3 — Happy path: with nothing saved the panel starts from the page's standard columns; the first save keeps them
  Scenario: First save keeps the standard columns
    Given my firm's "CapitalCall" form type has a text field "call_note"
    And my firm has no saved "CapitalCall" columns
    When I open the "/capital_calls" page
    And I open the columns panel
    Then the columns editor should list "Name, Due Date, Call Amount, Collected Amount, Due Amount, Approved"
    When I add the column "Call note"
    And I save the columns
    Then my firm's "CapitalCall" columns should be "name, due_date, call_amount, collected_amount, due_amount, approved, custom_fields.call_note"

  # H4 — Happy path: the firm has no form type for the record type; the save creates it
  Scenario: Form type created on the first save
    Given my firm has no "CapitalCall" form type
    When I open the "/capital_calls" page
    And I open the columns panel
    And I save the columns
    Then my firm's "CapitalCall" form type should exist tagged "Default" with 6 columns

  # H5 — Happy path: an open report with its own columns — the panel edits the report's, not the firm's
  Scenario: Report's own columns
    Given a report "LPs by city" on "/investors" with columns "investor_name, city, category"
    When I open the "/investors?report_id={report}" page
    And I open the columns panel
    Then the columns panel should be titled "Columns of report 'LPs by city'"
    When I remove the column "city"
    And I save the columns
    Then the report's columns should be "investor_name, category"
    And the "investors" table headings should be "Stakeholder, Category"
    And my firm should have no saved "Investor" columns

  # H6 — Happy path: reset removes the saved columns; the table shows the page's standard columns
  Scenario: Reset to standard columns
    Given my firm's "Investor" columns are "investor_name, city"
    When I open the "/investors" page
    And I open the columns panel
    And I reset to the standard columns
    And I save the columns
    Then my firm should have no saved "Investor" columns
    And the "investors" table headings should be "Stakeholder, Tags, Category, Access, City"

  # H7 — Happy path: Escape closes the panel and nothing is saved
  Scenario: Cancel with Escape
    Given my firm's "Investor" columns are "investor_name, category, city"
    When I open the "/investors" page
    And I open the columns panel
    And I remove the column "city"
    And I press Escape
    Then the columns panel should close
    And my firm's "Investor" columns should be "investor_name, category, city"

  # H8 — Happy path: the firm's columns show for a colleague, who has no button
  Scenario: Firm-wide, no button for a plain employee
    Given my firm's "Investor" columns are "investor_name, city"
    And I am signed in as a plain employee of my firm
    When I open the "/investors" page
    Then the "investors" table headings should be "Stakeholder, City"
    And there should be no columns button

  # H16 — Happy path: Configure Grids shows the same list, with Show / Edit / Delete on each saved column
  Scenario: Configure Grids page
    Given my firm's "Investor" columns are "investor_name, category, city"
    When I open Configure Grids for my firm's "Investor" form type
    Then the columns editor should list "Stakeholder, Category, City"
    And every saved column should have Show, Edit and Delete
    When I open Show for the column "city"
    Then the detail panel should show the column "City"

  # H17 — Happy path: save on the full page refreshes it; Delete removes a column at once after the popup
  Scenario: Save and delete on the full page
    Given my firm's "Investor" columns are "investor_name, category, city"
    When I open Configure Grids for my firm's "Investor" form type
    And I move the column "category" above "investor_name"
    And I save the columns
    Then my firm's "Investor" columns should be "category, investor_name, city"
    And the columns editor should list "Category, Stakeholder, City"
    When I delete the column "city" and confirm
    Then my firm's "Investor" columns should be "category, investor_name"

  # H18 — Happy path: a derived field added in the panel shows each record's value
  Scenario: Add a derived field
    Given my firm's "Investor" columns are "investor_name, category"
    When I open the "/investors" page
    And I open the columns panel
    And I add the derived field "RM" with key "custom_fields.risk_rating"
    And I save the columns
    Then the "investors" table headings should be "Stakeholder, Category, RM"
    And the "investors" table should show "Low"

  # E1 — Edge case: a derived field is renamed and moved; its key, data type and alignment stay
  Scenario: Derived field renamed and moved
    Given my firm's "Investor" columns are "investor_name, category"
    And my firm's "Investor" columns include the derived field "Risk band" with key "custom_fields.risk_rating"
    When I open the "/investors" page
    And I open the columns panel
    And I rename the column "custom_fields.risk_rating" to "Risk"
    And I move the column "custom_fields.risk_rating" above "investor_name"
    And I save the columns
    Then my firm's derived "Investor" column should have key "custom_fields.risk_rating", data type "String", alignment "text-center", heading "Risk" at position 1

  # E2 — Edge case: the all-funds commitments list adds Fund Name itself (locked, not stored); Stakeholder is an ordinary row
  Scenario: Columns the page adds itself
    Given my firm has no saved "CapitalCommitment" columns
    When I open the "/capital_commitments" page
    And I open the columns panel
    Then the column "fund_name" should be locked
    And the column "investor_name" should not be locked
    When I save the columns
    Then my firm's "CapitalCommitment" columns should be "folio_id, investor_name, investor_kyc_full_name, unit_type, fund_close, committed_amount, call_amount, collected_amount, distribution_amount"

  # E3 — Edge case: an investor's commitments hide the Stakeholder column; it is flagged and kept on save
  Scenario: Saved column hidden on this page
    Given my firm's "CapitalCommitment" columns are "folio_id, investor_name, committed_amount"
    When I open the commitments of the investor "Ravi Menon"
    And I open the columns panel
    Then the column "investor_name" should be marked not shown on this page
    When I save the columns
    Then my firm's "CapitalCommitment" columns should be "folio_id, investor_name, committed_amount"

  # E4 — Edge case: a report without its own columns — the panel edits the firm's columns
  Scenario: Report without its own columns
    Given a report "All LPs" on "/investors" with no columns
    When I open the "/investors?report_id={report}" page
    And I open the columns panel
    Then the columns panel should be titled "Investors columns"
    When I save the columns
    Then my firm's "Investor" columns should be "investor_name, tag_list, category, investor_access_count, city"
    And the report's columns should be ""

  # E5 — Edge case: a column removed by someone else while the panel is open is skipped
  Scenario: Column removed meanwhile
    Given my firm's "Investor" columns are "investor_name, category, city"
    When I open the "/investors" page
    And I open the columns panel
    And someone else removes my firm's "Investor" column "city"
    And I save the columns
    Then my firm's "Investor" columns should be "investor_name, category"

  # E6 — Edge case: the same save twice gives one set, positions 1..n
  @rack_test
  Scenario: Double save
    When I save the "Investor" columns "investor_name, city" directly twice
    Then my firm's "Investor" columns should be "investor_name, city"

  # E7 — Edge case: a cleared heading saves no override, so the standard name shows
  Scenario: Blank heading
    Given my firm's "Investor" columns are "investor_name, category"
    When I open the "/investors" page
    And I open the columns panel
    And I clear the heading of the column "category"
    And I save the columns
    Then my firm's "Investor" column "category" should have heading "Category"
    And my firm's "Investor" column "category" should store no heading override

  # E8 — Edge case: a column listed twice is saved once, at its first position
  @rack_test
  Scenario: Column listed twice
    When I save the "Investor" columns "city, investor_name, city" directly
    Then my firm's "Investor" columns should be "city, investor_name"

  # E9 — Edge case: a table inside a fund page tab reloads alone; the fund page stays
  Scenario: Table inside a tab
    Given there is a fund "Growth Fund I" with no commitments
    When I open the "/funds/{fund}" page
    And I open the columns panel
    And I remove the column "fund_close"
    And I save the columns
    Then the columns panel should close
    And I should still be on the fund page
    And my firm's "CapitalCommitment" columns should be "folio_id, investor_name, investor_kyc_full_name, unit_type, committed_amount, call_amount, collected_amount, distribution_amount"

  # E10 — Edge case: a field of a related record (the commitment's investor) can be added
  Scenario: Related record field
    When I open the "/capital_commitments" page
    And I open the columns panel
    And I add the first column offered under "Investor"
    And I save the columns
    Then the column added from the related group should be saved

  # E11 — Edge case: the snapshot column is never listed
  Scenario: Snapshot column not listed
    When I open the "/capital_commitments?snapshot=true" page
    And I open the columns panel
    Then the columns editor should not list "Snapshot Date"

  # E23 — Edge case: data type and alignment set in a row's details
  Scenario: Data type and alignment
    Given my firm's "Investor" columns are "investor_name, category"
    When I open the "/investors" page
    And I open the columns panel
    And I set the column "category" to data type "Decimal" and alignment "Right"
    And I save the columns
    Then my firm's "Investor" column "category" should have data type "Decimal" and alignment "text-end"
    And the "Category" column heading of the "investors" table should be right-aligned

  # E24 — Edge case: a derived field's key is changed in its details
  Scenario: Derived key edit
    Given my firm's "Investor" columns are "investor_name"
    And my firm's "Investor" columns include the derived field "Risk band" with key "custom_fields.risk_rating"
    When I open the "/investors" page
    And I open the columns panel
    And I change the key of the derived column "custom_fields.risk_rating" to "city"
    And I save the columns
    Then my firm's derived "Investor" column should have key "city", data type "String", alignment "text-center", heading "Risk band" at position 2

  # E25 — Edge case: a page without a search box keeps the button at the table's corner
  Scenario: Page without a search box
    When I open the "/investors?hide_search=true" page
    Then the columns button should be at the table's corner

  # E26 — Edge case: Configure Grids for a second form type of the same record type edits that one
  Scenario: Second form type
    Given my firm has "CapitalCommitment" form types tagged "Default, Feeder"
    When I open Configure Grids for my firm's "CapitalCommitment" form type tagged "Feeder"
    And I remove the column "fund_close"
    And I save the columns
    Then the "CapitalCommitment" form type tagged "Feeder" should have columns "folio_id, investor_name, investor_kyc_full_name, unit_type, committed_amount, call_amount, collected_amount, distribution_amount"
    And the "CapitalCommitment" form type tagged "Default" should have no columns

  # E27 — Edge case: Configure Grids on a report with no columns starts from the standard ones and saves to the report
  Scenario: Report page Configure Grids
    Given a report "All LPs" on "/investors" with no columns
    When I open Configure Grids for the report
    Then the columns editor should list "Stakeholder, Tags, Category, Access, City"
    When I save the columns
    Then the report's columns should be "investor_name, tag_list, category, investor_access_count, city"

  # X6 — Error case: an empty list is refused in the panel; nothing is saved
  Scenario: Empty list refused
    Given my firm's "Investor" columns are "investor_name, category"
    When I open the "/investors" page
    And I open the columns panel
    And I remove every column
    And I save the columns
    Then the columns editor should say "Keep at least one column"
    And my firm's "Investor" columns should be "investor_name, category"

  # H9 — Happy path (phase 3): an AG grid has the columns button; saving reloads the grid with the new columns
  Scenario: AG grid columns
    Given my firm's "CapitalCommitment" form type has a text field "tranche"
    And my firm has no saved "CapitalCommitment" columns
    When I open the "/capital_commitments?ag=true" page
    And I open the columns panel
    And I add the column "Tranche"
    And I save the columns
    Then the columns panel should close
    And my firm's "CapitalCommitment" columns should be "folio_id, investor_name, investor_kyc_full_name, unit_type, fund_close, committed_amount, call_amount, collected_amount, distribution_amount, custom_fields.tranche"
    And the AG grid should show the column "Tranche"

  # E12 — Edge case (phase 3): an investor's commitments grid hides Stakeholder; it is flagged and kept on save
  Scenario: AG grid with column rules
    Given my firm's "CapitalCommitment" columns are "folio_id, investor_name, committed_amount"
    When I open the AG commitments grid of the investor "Ravi Menon"
    And I open the columns panel
    Then the column "investor_name" should be marked not shown on this page
    And the column "fund_name" should be locked
    When I save the columns
    Then my firm's "CapitalCommitment" columns should be "folio_id, investor_name, committed_amount"
