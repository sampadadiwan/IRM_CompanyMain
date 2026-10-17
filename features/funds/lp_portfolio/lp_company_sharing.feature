Feature: Company sharing and LP layouts
  The fund team shares a portfolio company with LPs (one switch per company) and lays out what LPs see in LP
  layouts of the Portfolio Company Dashboard — "LP", or "LP, <tag>" for companies with that tag. Guidance notices
  point to the next place to act.
  Worked examples: openspec/changes/lp-folio-portfolio-dashboard/business-rules.md
  (H8, H8a, H9, H18, E45, E48, E49, E51, E52, E52a, E52b, E72–E77, E88, E89, E91, E92, E94, X6, X7, X8, X19, E96, E97)

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

  # H8 — Happy path: Set up LP layout creates "LP" with Data Card, Key KPIs, Valuations
  Scenario: Fund team sets up the LP layout
    When I set up the LP layout
    Then I should see "LP layout ready."
    And the LP layout "LP" should hold "Data Card, Key Kpis, Valuations"

  # H8a — Happy path: an LP-safe widget added to "LP" is saved in its position
  Scenario: Fund team adds an LP-safe widget
    Given the LP layout "LP" has widgets:
      | widget     | size   |
      | Data Card  | Medium |
      | Key Kpis   | Medium |
      | Valuations | XL     |
    When a request saves a "Kpis" widget into the layout "LP"
    Then the LP layout "LP" should hold "Data Card, Key Kpis, Valuations, Kpis"

  # H9 — Happy path: Show to LPs turns the switch on; the LPs menu reads Visible to LPs and offers Hide from LPs
  Scenario: Fund team shows a company
    When I open the company page of "Cedar Logistics"
    And I click Show to LPs
    Then I should see "Shared with LPs."
    And I should see "Visible to LPs"
    When I open the LPs menu
    Then I should see "Hide from LPs"
    And the company "Cedar Logistics" should be shown to LPs

  # H18 — Happy path: Hide from LPs confirms with the action summary, then turns the switch off
  Scenario: Hide from LPs confirms
    Given the company "Acme Robotics" is shown to LPs
    When I open the company page of "Acme Robotics"
    And I hide the company from LPs and confirm
    Then I should see "Hidden from LPs."
    And the company "Acme Robotics" should not be shown to LPs

  # E45 — Edge case: a double submit sets the switch on once, no error
  @rack_test
  Scenario: Double submit
    When I submit Show to LPs for "Cedar Logistics" twice
    Then I should see "Shared with LPs."
    And the company "Cedar Logistics" should be shown to LPs

  # E48 — Edge case: one holding with Show Portfolio on is enough for the company
  Scenario: Mixed holdings carry over
    Given the holding "Fenix Mobility" "Seed CCPS" of "Growth Fund I" had Show Portfolio "on"
    When the carry-over runs
    Then the company "Fenix Mobility" should be shown to LPs

  # E49 — Edge case: running the carry-over again changes nothing
  Scenario: Carry-over idempotent
    Given the holding "Acme Robotics" "Series B CCPS" of "Growth Fund I" had Show Portfolio "on"
    When the carry-over runs
    And the carry-over runs
    Then the carry-over should report 0 changed and 0 skipped

  # E51 — Edge case: a deleted holding's flag is ignored
  Scenario: Carry-over ignores deleted holdings
    Given the holding "Bluefin Health" "Series A CCPS" of "Growth Fund I" had Show Portfolio "on"
    And the holding "Bluefin Health" "Series A CCPS" of "Growth Fund I" is deleted
    When the carry-over runs
    Then the company "Bluefin Health" should not be shown to LPs

  # E52 — Edge case: Add widget on an LP layout offers only the LP-safe types, with the help text
  Scenario: Widget form lists LP-safe types only
    When I add a widget to the LP layout "LP"
    Then the widget type list should offer only the LP-safe types
    And I should see "LP layout: only widgets that are safe to show LPs are listed."

  # E52a — Edge case: Set up LP layout a second time adds nothing
  @rack_test
  Scenario: Set up twice
    When I submit Set up LP layout twice
    Then the LP layout "LP" should hold "Data Card, Key Kpis, Valuations"

  # E52b — Edge case: removing a widget from "LP" leaves the Default layout unchanged
  Scenario: Internal layouts unaffected
    Given the LP layout "LP" has widgets:
      | widget    |
      | Data Card |
    Given the LP layout "Default" has widgets:
      | widget    |
      | Data Card |
      | Notes     |
    When I remove the "Data Card" widget from the LP layout "LP"
    Then the LP layout "Default" should hold "Data Card, Notes"

  # E72 — Edge case: the Show to LPs tooltip says what LPs will see
  Scenario: Show to LPs tooltip
    When I open the company page of "Cedar Logistics"
    And I open the LPs menu
    Then the element "Show to LPs" should have the tooltip "LPs who hold this company will be able to open its page. They see the holdings card and the widgets of the LP layout that matches this company's tags."

  # E73 — Edge case: shared, but no LP layout with enabled widgets applies
  Scenario: Shared with no usable LP layout
    Given the company "Acme Robotics" is shown to LPs
    When I open the company page of "Acme Robotics"
    Then I should see "LPs see only the holdings card for this company. Add widgets to an LP layout"
    And I should see "Set up LP layout"

  # E74 — Edge case: shared, but every fund holding it hides its portfolio
  Scenario: Shared, but every fund hides it
    Given the company "Acme Robotics" is shown to LPs
    Given the fund "Growth Fund I" LP portfolio view is "hidden"
    When I open the company page of "Acme Robotics"
    Then I should see "No LP can open this page yet: every fund holding this company hides its portfolio from LPs. Change it in Fund › Edit › LP portfolio view."

  # E75 — Edge case: widget settings invite the fund team to create an LP layout
  Scenario: Settings invite
    When I visit the widget settings
    Then I should see "Want to share company pages with LPs? Create an LP layout."
    And I should see "Set up LP layout"

  # E76 — Edge case: an open LP layout says which shared companies see it
  Scenario: LP layout explains itself
    Given the LP layout "LP" has widgets:
      | widget    |
      | Data Card |
    Given the LP layout "LP, FinTech" has widgets:
      | widget    |
      | Data Card |
    Given the company "Paywise Payments" is shown to LPs
    When I open the LP layout "LP, FinTech" in widget settings
    Then I should see "LPs see this layout for shared companies tagged Fintech (1 today: Paywise Payments). Other companies use \"LP\"."
    And I should see "Only LP-safe widgets can be added. Check it with Preview as LP on any company."

  # E77 — Edge case: Embed Document help on an LP layout
  Scenario: Embed Document help
    When I add a widget to the LP layout "LP"
    Then I should see "Embed Document: shows the company's latest document with this exact name, e.g. \"Founder Video\". Upload it to each company you share."

  # E88 — Edge case: New LP layout for a tag copies "LP"; editing it leaves "LP" alone
  Scenario: New LP layout for a tag
    Given the LP layout "LP" has widgets:
      | widget     |
      | Data Card  |
      | Key Kpis   |
      | Valuations |
    When I create a new LP layout for the tag "FinTech"
    Then I should see "LP layout \"LP, FinTech\" created."
    And the LP layout "LP, FinTech" should hold "Data Card, Key Kpis, Valuations"
    When I remove the "Valuations" widget from the LP layout "LP, FinTech"
    Then the LP layout "LP" should hold "Data Card, Key Kpis, Valuations"

  # E89 — Edge case: a 40-character LP layout name is accepted
  Scenario: Long layout name
    When a request saves a "Data Card" widget into the layout "LP, Enterprise Infrastructure - Software"
    Then the LP layout "LP, Enterprise Infrastructure - Software" should hold "Data Card"

  # E91 — Edge case: the company page names the layout LPs see and why
  Scenario: Company page names the layout
    Given the LP layout "LP" has widgets:
      | widget    |
      | Data Card |
    Given the LP layout "LP, FinTech" has widgets:
      | widget    |
      | Data Card |
    Given the company "Paywise Payments" is shown to LPs
    Given the company "Acme Robotics" is shown to LPs
    When I open the company page of "Paywise Payments"
    Then I should see "LPs see the \"LP, FinTech\" layout for this company (matched on its tag Fintech)."
    And I should see "Open layout"
    When I open the company page of "Acme Robotics"
    Then I should see "LPs see the \"LP\" layout for this company (no tag-specific layout matches)."

  # E92 — Edge case: two layouts match equally — the company page names the winner
  Scenario: Company page warns about a tie
    Given the LP layout "LP, Fintech" has widgets:
      | widget    |
      | Data Card |
    Given the LP layout "LP, NBFC" has widgets:
      | widget    |
      | Data Card |
    Given the company "Paywise Payments" is shown to LPs
    When I open the company page of "Paywise Payments"
    Then I should see "Two LP layouts match this company's tags (\"LP, Fintech\" and \"LP, NBFC\"). LPs see \"LP, Fintech\". Remove a tag or a layout to choose."

  # E94 — Edge case: in an LP layout the widget Tags field explains the per-company narrowing
  Scenario: Widget tags help
    When I add a widget to the LP layout "LP"
    Then I should see "Optional. Show this widget only for companies with one of these tags. Leave empty for every company using this layout."

  # X6 — Error case: an internal widget is refused in an LP layout, added or moved in
  Scenario: Internal widget into an LP layout
    When a request saves a "Notes" widget into the layout "LP"
    Then the widget save should be refused with "This widget can't be added to an LP layout: it isn't safe to show LPs."
    When a request moves the Default "Notes" widget into the layout "LP, FinTech"
    Then the widget save should be refused with "This widget can't be added to an LP layout: it isn't safe to show LPs."

  # X7 — Error case: an LP cannot change the company switch
  @rack_test
  Scenario: LP changes the company switch
    Given LP "Ravi Menon" has folio "F-012" in "Growth Fund I"
    When LP "Ravi Menon" opens the portfolio of "Growth Fund I"
    And "the LP" submits Show to LPs for "Cedar Logistics" directly
    Then the company "Cedar Logistics" should not be shown to LPs

  # X8 — Error case: a read-only employee cannot change the switch
  @rack_test
  Scenario: Read-only employee changes the switch
    Given there is a read-only employee "Kiran" in the entity
    When "Kiran" submits Show to LPs for "Cedar Logistics" directly
    Then the company "Cedar Logistics" should not be shown to LPs

  # X19 — Error case: a holding whose company was deleted is skipped and counted
  Scenario: Carry-over meets deleted company
    Given the holding "Acme Robotics" "Series B CCPS" of "Growth Fund I" had Show Portfolio "on"
    Given the holding "Cedar Logistics" "Series A CCPS" of "Growth Fund I" had Show Portfolio "on"
    And the company "Acme Robotics" is deleted
    When the carry-over runs
    Then the carry-over should report 1 changed and 1 skipped
    And the company "Cedar Logistics" should be shown to LPs

  # E96 — Edge case: without the fund portfolios module there is no LPs menu, LP notice or LP layout setup
  Scenario: LP sharing hidden without the module
    Given the fund manager does not have the "fund portfolios" module
    When I open the company page of "Acme Robotics"
    Then the company page should have no LP sharing controls
    When I visit the widget settings
    Then I should not see "Set up LP layout"

  # E97 — Edge case: without the KPI module the starter LP layout leaves Key Kpis out, the widget form offers no KPI
  # widgets, and a direct request to add one is refused
  Scenario: No KPI widgets offered without the KPI module
    Given the fund manager does not have the "KPI" module
    When I set up the LP layout
    Then the LP layout "LP" should hold "Data Card, Valuations"
    When I add a widget to the LP layout "LP"
    Then the widget type list should offer only the LP-safe types
    When a request saves a "Kpis" widget into the layout "LP"
    Then the widget save should be refused with "This widget can't be added to an LP layout: it isn't safe to show LPs."
