Feature: LP Company Dashboard
  An LP opens one page per portfolio company — the holdings card for the selected fund, then the widgets of the
  LP layout chosen for the company by its tags. It replaces the per-holding preview page, and the fund team can
  preview it as any LP.
  Worked examples: openspec/changes/lp-folio-portfolio-dashboard/business-rules.md
  (H10–H14, H16, H17, E44, E46, E47, E50, E53–E68, E78, E80–E87, E90, E93, E97, X9–X16, X21)

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;currency=INR"
    Given the user has role "company_admin"
    Given there is a fund "name=Growth Fund I;currency=INR;show_portfolios=true" for the entity
    Given the fund has the LP allocation formulas
    Given the fund "Growth Fund I" holds:
      | company          | instrument    | purchases | cost_cr | fmv_cr | tags          |
      | Acme Robotics    | Series B CCPS | 1         | 25.00   | 40.00  | Robotics      |
      | Bluefin Health   | Series A CCPS | 1         | 20.00   | 22.00  | HealthTech    |
      | Cedar Logistics  | Series A CCPS | 1         | 15.00   | 18.00  |               |
      | Fenix Mobility   | Seed CCPS     | 1         | 5.00    | 5.00   |               |
      | Fenix Mobility   | Series A CCPS | 1         | 8.00    | 8.00   |               |
      | Paywise Payments | Series A CCPS | 1         | 6.00    | 9.00   | Fintech, NBFC |
    Given LP "Ravi Menon" has folio "F-012" in "Growth Fund I"
    Given folio "F-012" has allocation entries:
      | formula                  | company         | instrument    | amount |
      | Allocated Portfolio Cost | Acme Robotics   | Series B CCPS | 2.50   |
      | Allocated Portfolio FMV  | Acme Robotics   | Series B CCPS | 4.00   |
      | Allocated Portfolio Cost | Cedar Logistics | Series A CCPS | 1.50   |
      | Allocated Portfolio Cost | Bluefin Health  | Series A CCPS | 0.00   |
    Given the fund "Growth Fund I" LP portfolio view is "allocated" with allocation formula "Allocated Portfolio Cost"
    Given the LP layout "LP" has widgets:
      | widget         | size   | metadata               |
      | Data Card      | Medium |                        |
      | Key Kpis       | Medium |                        |
      | Valuations     | XL     |                        |
      | Embed Document | XL     | {name: 'Founder Video'} |
    Given the LP layout "Default" has widgets:
      | widget   |
      | Notes    |
      | Captable |
    Given the company "Acme Robotics" is shown to LPs
    Given the company "Bluefin Health" is shown to LPs
    Given the company "Acme Robotics" has a "video" document named "Founder Video"

  # H10 — Happy path: Ravi opens Acme from his portfolio; the holdings card shows his own share under own share
  Scenario: LP opens a shared company
    Given the fund "Growth Fund I" LP portfolio view is "allocated_with_share" with allocation formula "Allocated Portfolio Cost" and FMV formula "Allocated Portfolio FMV"
    When LP "Ravi Menon" opens the portfolio of "Growth Fund I"
    And I click "Acme Robotics"
    Then the LP company page should be open for "Acme Robotics"
    And the LP holdings card should list "Series B CCPS"
    And the LP holdings card should show Your cost "₹2.50 Cr" and Your FMV "₹4.00 Cr"

  # H11 — Happy path: only the "LP" layout's widgets — no Notes or Captable from Default
  Scenario: Only LP layout widgets render
    When LP "Ravi Menon" opens the company "Acme Robotics"
    Then the LP company page should show the widgets "Data Card, Key Kpis, Valuations, Embed Document"
    And the LP company page should not show the widgets "Notes, Captable"

  # H12 — Happy path: the founder video plays inline
  Scenario: Founder video plays
    When LP "Ravi Menon" opens the company "Acme Robotics"
    Then a video should play inline

  # H13 — Happy path: the fund team previews Acme as Ravi
  Scenario: Preview as LP
    When the fund team previews "Acme Robotics" as "Ravi Menon" for "Growth Fund I"
    Then I should see "Preview — viewing as Ravi Menon (F-012)."
    And the LP company page should show the widgets "Data Card, Key Kpis, Valuations, Embed Document"

  # H14 — Happy path: Anita holds Acme through two funds; the selector defaults to Growth Fund I and switches to II
  Scenario: Fund selector
    Given there is a fund "name=Growth Fund II;currency=INR;show_portfolios=true" for the entity
    Given the fund "Growth Fund II" holds:
      | company       | instrument    | purchases | cost_cr | fmv_cr |
      | Acme Robotics | Series C CCPS | 1         | 10.00   | 12.00  |
    Given the fund "Growth Fund II" has the formula "Allocated Cost II" of type "AllocatePortfolioInvestment"
    Given the fund "Growth Fund II" LP portfolio view is "allocated" with allocation formula "Allocated Cost II"
    Given LP "Anita Rao" has folio "F-031" in "Growth Fund I"
    Given LP "Anita Rao" has folio "G-007" in "Growth Fund II"
    Given folio "F-031" has allocation entries:
      | formula                  | company       | instrument    | amount |
      | Allocated Portfolio Cost | Acme Robotics | Series B CCPS | 1.25   |
    Given folio "G-007" has allocation entries:
      | formula           | company       | instrument    | amount |
      | Allocated Cost II | Acme Robotics | Series C CCPS | 0.50   |
    When LP "Anita Rao" opens the company "Acme Robotics"
    Then the LP holdings card should list "Series B CCPS"
    When the LP switches the fund selector to "Growth Fund II"
    Then the LP holdings card should list "Series C CCPS"
    And the LP holdings card should not list "Series B CCPS"

  # H16 — Happy path: an old holding link lands on the company's LP page
  Scenario: Old holding link redirects
    When LP "Ravi Menon" opens the old holding link of "Acme Robotics" "Series B CCPS" in "Growth Fund I"
    Then the LP company page should be open for "Acme Robotics"

  # H17 — Happy path: after the carry-over Ravi can open Cedar, whose holding had Show Portfolio on
  Scenario: Carry-over at release
    Given the holding "Cedar Logistics" "Series A CCPS" of "Growth Fund I" had Show Portfolio "on"
    When the carry-over runs
    And LP "Ravi Menon" opens the company "Cedar Logistics"
    Then the LP company page should be open for "Cedar Logistics"

  # E44 — Edge case: in Ravi's list Acme (shared) is a link, Cedar (not shared) is plain text
  Scenario: Company link only when openable
    When LP "Ravi Menon" opens the portfolio of "Growth Fund I"
    Then the LP portfolio should link "Acme Robotics" and not "Cedar Logistics"

  # E46 — Edge case: the company switch alone grants nothing when the fund is Hidden
  Scenario: Switch alone grants nothing
    Given the fund "Growth Fund I" LP portfolio view is "hidden"
    When LP "Ravi Menon" opens the company "Acme Robotics" for "Growth Fund I"
    Then the LP company page should be refused

  # E47 — Edge case: a disabled widget never shows
  Scenario: Disabled widget
    Given the LP layout widget "Valuations" in "LP" is disabled
    When LP "Ravi Menon" opens the company "Acme Robotics"
    Then the LP company page should not show the widgets "Valuations"

  # E50 — Edge case: a company carried over in a Hidden fund stays invisible
  Scenario: Carried over in a hidden fund
    Given there is a fund "name=Growth Fund II;currency=INR;show_portfolios=false" for the entity
    Given the fund "Growth Fund II" holds:
      | company       | instrument    | purchases | cost_cr | fmv_cr |
      | Acme Robotics | Series C CCPS | 1         | 10.00   | 12.00  |
    Given LP "Anita Rao" has folio "G-007" in "Growth Fund II"
    Given the holding "Acme Robotics" "Series C CCPS" of "Growth Fund II" had Show Portfolio "on"
    When the carry-over runs
    And LP "Anita Rao" opens the company "Acme Robotics" for "Growth Fund II"
    Then the LP company page should be refused

  # E53 — Edge case: Cedar is visible to Ravi but not shared
  Scenario: Switched-off company address
    When LP "Ravi Menon" opens the company "Cedar Logistics"
    Then the LP company page should say it is not shared

  # E54 — Edge case: no usable LP layout — holdings card plus a message, never the internal widgets
  Scenario: No usable LP layout
    Given every widget of the LP layout "LP" is disabled
    When LP "Ravi Menon" opens the company "Acme Robotics"
    Then the LP holdings card should list "Series B CCPS"
    And I should see "No further company information has been shared."
    And the LP company page should not show the widgets "Notes, Captable"

  # E54a — Edge case: no Reports menu, no layout selector, no run buttons for LPs
  Scenario: No internal controls
    When LP "Ravi Menon" opens the company "Acme Robotics"
    Then the company page should have no internal controls

  # E55 — Edge case: Key KPIs and KPIs show Actual only (Revenue 62.0), never Budget (70.0)
  Scenario: KPIs Actual only
    Given the LP layout "LP" has widgets:
      | widget | size | position |
      | Kpis   | XL   | 5        |
    Given the company "Acme Robotics" has KPIs:
      | as_of      | tag    | kpi     | value |
      | 30/09/2026 | Actual | Revenue | 62.0  |
      | 30/09/2026 | Budget | Revenue | 70.0  |
    When LP "Ravi Menon" opens the company "Acme Robotics"
    Then the KPIs widget should show "62.00" and not "70.00"

  # E56 — Edge case: only Budget KPIs — "No KPIs reported yet."
  Scenario: Only Budget KPIs
    Given the LP layout "LP" has widgets:
      | widget | size | position |
      | Kpis   | XL   | 5        |
    Given the company "Cedar Logistics" is shown to LPs
    Given the company "Cedar Logistics" has KPIs:
      | as_of      | tag    | kpi     | value |
      | 30/09/2026 | Budget | Revenue | 70.0  |
    When LP "Ravi Menon" opens the company "Cedar Logistics"
    Then I should see "No KPIs reported yet."

  # E57 — Edge case: Portfolio Stats show the selected fund only
  Scenario: Widget data limited to fund
    Given there is a fund "name=Growth Fund II;currency=INR;show_portfolios=true" for the entity
    Given the fund "Growth Fund II" holds:
      | company       | instrument    | purchases | cost_cr | fmv_cr |
      | Acme Robotics | Series C CCPS | 1         | 10.00   | 12.00  |
    Given the LP layout "LP" has widgets:
      | widget          | size | position |
      | Portfolio Stats | XL   | 6        |
    When LP "Ravi Menon" opens the company "Acme Robotics"
    Then the LP totals should show FMV "40" Cr for "Growth Fund I"
    And the LP totals should not show FMV "52" Cr for "Growth Fund I"

  # E58 — Edge case: Priya's holdings card shows only the Fenix holding allocated to her
  Scenario: Holdings card hides unallocated holdings
    Given the company "Fenix Mobility" is shown to LPs
    Given LP "Priya Shah" has folio "F-051" in "Growth Fund I"
    Given folio "F-051" has allocation entries:
      | formula                  | company        | instrument    | amount |
      | Allocated Portfolio Cost | Fenix Mobility | Series A CCPS | 0.40   |
    When LP "Priya Shah" opens the company "Fenix Mobility"
    Then the LP holdings card should list "Series A CCPS"
    And the LP holdings card should not list "Seed CCPS"

  # E59 — Edge case: a Hidden second fund is not offered in the selector
  Scenario: Only qualifying funds in selector
    Given there is a fund "name=Growth Fund II;currency=INR;show_portfolios=false" for the entity
    Given the fund "Growth Fund II" holds:
      | company       | instrument    | purchases | cost_cr | fmv_cr |
      | Acme Robotics | Series C CCPS | 1         | 10.00   | 12.00  |
    Given LP "Ravi Menon" has folio "F-013" in "Growth Fund II"
    When LP "Ravi Menon" opens the company "Acme Robotics"
    Then I should not see "Growth Fund II"
    And the LP holdings card should list "Series B CCPS"

  # E60 — Edge case: Bluefin has no "Founder Video", so no Embed Document widget
  Scenario: Missing named document
    Given the fund "Growth Fund I" LP portfolio view is "whole_fund"
    When LP "Ravi Menon" opens the company "Bluefin Health"
    Then the LP company page should show the widgets "Data Card"
    And a video should not play inline

  # E61 — Edge case: a PDF named "Founder Video" shows in the PDF viewer
  Scenario: PDF embed unchanged
    Given the fund "Growth Fund I" LP portfolio view is "whole_fund"
    Given the company "Bluefin Health" has a "pdf" document named "Founder Video"
    When LP "Ravi Menon" opens the company "Bluefin Health"
    Then the PDF viewer should be shown

  # E62 — Edge case: with two "Founder Video" documents the latest plays
  Scenario: Latest named document
    Given the company "Acme Robotics" has a "video" document named "Founder Video"
    When LP "Ravi Menon" opens the company "Acme Robotics"
    Then the video should be the latest "Founder Video" document of "Acme Robotics"

  # E63 — Edge case: the Embed Document widget exposes only the named document
  Scenario: Only the named document exposed
    When LP "Ravi Menon" opens the company "Acme Robotics"
    Then I should not see "Documents"
    And a video should play inline

  # E64 — Edge case: a video in Embed Document plays on the internal fund dashboard too
  Scenario: Video on internal dashboards too
    Given the fund "Growth Fund I" has a "video" document named "Fund Video"
    Given the fund dashboard of "Growth Fund I" has an Embed Document widget named "Fund Video"
    When the fund team opens the fund dashboard of "Growth Fund I"
    Then a video should play inline

  # E65 — Edge case: previewing Bluefin as Ravi (hidden for him) shows his refusal
  Scenario: Preview for LP without access
    When the fund team previews "Bluefin Health" as "Ravi Menon" for "Growth Fund I"
    Then the LP company page should be refused

  # E66 — Edge case: the fund team's holding page has no Preview or Show Portfolio buttons
  Scenario: Fund team holding page
    When the fund team opens the holding "Acme Robotics" "Series B CCPS" of "Growth Fund I"
    Then I should not see "Show Portfolio"
    And I should not see "Hide Portfolio"
    And I should see "Add Valuation"

  # E67 — Edge case: the retired preview page's Widgets and Track Record tabs are gone, even where records exist
  Scenario: Legacy preview content not shown
    Given the holding "Acme Robotics" "Series B CCPS" of "Growth Fund I" has a legacy widget "Company Overview"
    When the fund team opens the holding "Acme Robotics" "Series B CCPS" of "Growth Fund I"
    Then the holding page should have no Widgets or Track Record tab
    And I should not see "Company Overview"

  # E68 — Edge case: an old link to a holding hidden from Ravi is refused
  Scenario: Old link to a hidden holding
    When LP "Ravi Menon" opens the old holding link of "Bluefin Health" "Series A CCPS" in "Growth Fund I"
    Then the LP company page should be refused

  # E78 — Edge case: previewing with no usable LP layout says so in the banner
  Scenario: Preview with no usable LP layout
    Given every widget of the LP layout "LP" is disabled
    When the fund team previews "Acme Robotics" as "Ravi Menon" for "Growth Fund I"
    Then I should see "This LP sees only the holdings card. Add widgets to an LP layout"
    And I should see "Open LP layout"

  # E80 — Edge case: the holding page points to the company
  Scenario: Holding page points to the company
    When the fund team opens the holding "Acme Robotics" "Series B CCPS" of "Growth Fund I"
    Then I should see "Sharing with LPs has moved to the company: use Show to LPs on the company page and the LP layouts in dashboard settings."

  # E81 — Edge case: a FinTech company gets "LP, FinTech" instead of "LP"
  Scenario: Tag-specific layout replaces LP
    Given the LP layout "LP, FinTech" has widgets:
      | widget    |
      | Data Card |
      | Kpis      |
    Given the company "Paywise Payments" is shown to LPs
    Given LP "Priya Shah" has folio "F-051" in "Growth Fund I"
    Given folio "F-051" has allocation entries:
      | formula                  | company          | instrument    | amount |
      | Allocated Portfolio Cost | Paywise Payments | Series A CCPS | 0.30   |
    When LP "Priya Shah" opens the company "Paywise Payments"
    Then the LP company page should show the widgets "Data Card, Kpis"
    And the LP company page should not show the widgets "Valuations, Embed Document"

  # E82 — Edge case: layout tags match ignoring case and spaces
  Scenario: Case and spaces ignored
    Given the LP layout "lp ,  fintech" has widgets:
      | widget |
      | Kpis   |
    Given the company "Paywise Payments" is shown to LPs
    Given LP "Priya Shah" has folio "F-051" in "Growth Fund I"
    Given folio "F-051" has allocation entries:
      | formula                  | company          | instrument    | amount |
      | Allocated Portfolio Cost | Paywise Payments | Series A CCPS | 0.30   |
    When LP "Priya Shah" opens the company "Paywise Payments"
    Then the LP company page should show the widgets "Kpis"
    And the LP company page should not show the widgets "Valuations"

  # E83 — Edge case: the layout matching the most company tags wins
  Scenario: Most matching tags wins
    Given the LP layout "LP, FinTech" has widgets:
      | widget |
      | Kpis   |
    Given the LP layout "LP, FinTech, NBFC" has widgets:
      | widget          |
      | Portfolio Stats |
    Given the company "Paywise Payments" is shown to LPs
    Given LP "Priya Shah" has folio "F-051" in "Growth Fund I"
    Given folio "F-051" has allocation entries:
      | formula                  | company          | instrument    | amount |
      | Allocated Portfolio Cost | Paywise Payments | Series A CCPS | 0.30   |
    When LP "Priya Shah" opens the company "Paywise Payments"
    Then the LP company page should show the widgets "Portfolio Stats"
    And the LP company page should not show the widgets "Kpis"

  # E84 — Edge case: a tie goes to the layout name that comes first
  Scenario: Tie goes to the first name
    Given the LP layout "LP, Fintech" has widgets:
      | widget |
      | Kpis   |
    Given the LP layout "LP, NBFC" has widgets:
      | widget          |
      | Portfolio Stats |
    Given the company "Paywise Payments" is shown to LPs
    Given LP "Priya Shah" has folio "F-051" in "Growth Fund I"
    Given folio "F-051" has allocation entries:
      | formula                  | company          | instrument    | amount |
      | Allocated Portfolio Cost | Paywise Payments | Series A CCPS | 0.30   |
    When LP "Priya Shah" opens the company "Paywise Payments"
    Then the LP company page should show the widgets "Kpis"
    And the LP company page should not show the widgets "Portfolio Stats"

  # E85 — Edge case: a matching layout with every widget disabled is skipped for "LP"
  Scenario: Empty matching layout skipped
    Given the LP layout "LP, FinTech" has widgets:
      | widget | enabled |
      | Kpis   | no      |
    Given the company "Paywise Payments" is shown to LPs
    Given LP "Priya Shah" has folio "F-051" in "Growth Fund I"
    Given folio "F-051" has allocation entries:
      | formula                  | company          | instrument    | amount |
      | Allocated Portfolio Cost | Paywise Payments | Series A CCPS | 0.30   |
    When LP "Priya Shah" opens the company "Paywise Payments"
    Then the LP company page should show the widgets "Data Card, Valuations"

  # E86 — Edge case: a widget tagged NBFC inside "LP" shows only for NBFC companies
  Scenario: Widget tag narrows within LP
    Given the LP layout "LP" has widgets:
      | widget | size | position | tags |
      | Kpis   | XL   | 7        | NBFC |
    Given the company "Paywise Payments" is shown to LPs
    Given LP "Priya Shah" has folio "F-051" in "Growth Fund I"
    Given folio "F-051" has allocation entries:
      | formula                  | company          | instrument    | amount |
      | Allocated Portfolio Cost | Paywise Payments | Series A CCPS | 0.30   |
      | Allocated Portfolio Cost | Acme Robotics    | Series B CCPS | 0.50   |
    When LP "Priya Shah" opens the company "Paywise Payments"
    Then the LP company page should show the widgets "Kpis, Data Card"
    When LP "Priya Shah" opens the company "Acme Robotics"
    Then the LP company page should not show the widgets "Kpis"
    And the LP company page should show the widgets "Data Card"

  # E87 — Edge case: the viewing LP's own tags never unlock a widget
  Scenario: Viewer's tags ignored
    Given the LP layout "LP" has widgets:
      | widget | size | position | tags |
      | Kpis   | XL   | 7        | NBFC |
    Given the LP user of "Ravi Menon" is tagged "NBFC"
    When LP "Ravi Menon" opens the company "Acme Robotics"
    Then the LP company page should not show the widgets "Kpis"

  # E90 — Edge case: "LPX" and "Help" are internal layouts, never used for LPs
  Scenario: Only the exact LP tag
    Given the LP layout "LPX" has widgets:
      | widget |
      | Notes  |
    Given the LP layout "Help" has widgets:
      | widget |
      | Notes  |
    When LP "Ravi Menon" opens the company "Acme Robotics"
    Then the LP company page should not show the widgets "Notes"
    And the LP company page should show the widgets "Data Card"

  # E93 — Edge case: the preview banner names the layout and the matched tag
  Scenario: Preview names the layout
    Given the LP layout "LP, FinTech" has widgets:
      | widget    |
      | Data Card |
    Given the company "Paywise Payments" is shown to LPs
    Given LP "Priya Shah" has folio "F-050" in "Growth Fund I"
    Given LP "Priya Shah" has folio "F-051" in "Growth Fund I"
    Given folio "F-051" has allocation entries:
      | formula                  | company          | instrument    | amount |
      | Allocated Portfolio Cost | Paywise Payments | Series A CCPS | 0.30   |
    When the fund team previews "Paywise Payments" as "Priya Shah" for "Growth Fund I"
    Then I should see "Preview — viewing as Priya Shah (F-050, F-051). Layout: \"LP, FinTech\" (company tag Fintech)."

  # X9 — Error case: Bluefin is outside Ravi's visible set
  Scenario: Company outside visible set
    When LP "Ravi Menon" opens the company "Bluefin Health"
    Then the LP company page should be refused

  # X10 — Error case: an LP of another fund manager is refused
  Scenario: Other fund manager's LP
    Given there is an LP "Lena Fischer" of another fund manager
    When LP "Lena Fischer" opens the company "Acme Robotics"
    Then the LP company page should be refused

  # X11 — Error case: a fund the LP cannot access is refused
  Scenario: Fund not accessible
    Given there is a fund "name=Growth Fund II;currency=INR;show_portfolios=true" for the entity
    When LP "Ravi Menon" opens the company "Acme Robotics" for "Growth Fund II"
    Then the LP company page should be refused

  # X12 — Error case: a Hidden fund's company page is refused
  Scenario: Hidden fund page
    Given the fund "Growth Fund I" LP portfolio view is "hidden"
    When LP "Ravi Menon" opens the company "Acme Robotics" for "Growth Fund I"
    Then the LP company page should be refused

  # X13 — Error case: only the chosen layout's widgets render; the internal dashboard is refused
  Scenario: Widget outside the chosen LP layout
    Given the LP layout "LP, FinTech" has widgets:
      | widget          |
      | Portfolio Stats |
    When LP "Ravi Menon" opens the company "Acme Robotics"
    Then the LP company page should not show the widgets "Portfolio Stats, Notes"
    When LP "Ravi Menon" requests the internal page of "Acme Robotics"
    Then I should see "Access Denied"

  # X14 — Error case: the company's internal pages stay closed to LPs
  Scenario: Internal addresses stay closed
    When LP "Ravi Menon" requests the internal page of "Acme Robotics"
    Then I should see "Access Denied"

  # X15 — Error case: an LP cannot use preview
  Scenario: LP uses preview
    When LP "Ravi Menon" requests the preview of "Acme Robotics"
    Then the LP company page should be refused

  # X16 — Error case: ?preview=true on Cedar's old holding link no longer opens anything
  Scenario: Preview parameter bypass
    When LP "Ravi Menon" opens the old holding link of "Cedar Logistics" "Series A CCPS" in "Growth Fund I"
    Then the LP company page should say it is not shared

  # E97 — Edge case: without the KPI module the LP page skips KPI widgets, though the layout still holds Key Kpis
  Scenario: KPI widgets skipped without the KPI module
    Given the fund manager does not have the "KPI" module
    When LP "Ravi Menon" opens the company "Acme Robotics"
    Then the LP company page should show the widgets "Data Card, Valuations, Embed Document"
    And the LP company page should not show the widgets "Key Kpis"

  # X21 — Error case: without the fund portfolios module the LP company page is refused
  Scenario: LP page refused without the module
    Given the fund manager does not have the "fund portfolios" module
    When LP "Ravi Menon" opens the company "Acme Robotics"
    Then the LP company page should be refused
