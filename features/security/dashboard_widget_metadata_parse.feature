Feature: C1 - dashboard widget metadata is read as a plain literal, never evaluated
  Widget metadata ({months: 12, ratio_names: %w[XIRR TVPI]}) used to be eval'd, so anyone who could save a
  widget - LPs included - could run code in the app process. It is now built by RubyLiteral from the parse
  tree: plain values keep working exactly as before, anything else is refused on save and ignored on render.
  Worked examples: docs/security/security_review_2026_10.md "C1 — Dashboard widget metadata"

  # C1-1 — Error case: a GP admin saving an expression on the widget form is refused
  @security @rack_test
  Scenario: C1-1 A GP admin cannot save a calculation as widget metadata
    Given Im logged in as a user "first_name=Gita" for an entity "name=Artha;entity_type=Investment Fund"
    And the user has role "company_admin"
    When I post a new dashboard widget with metadata "{title: 6 * 7}"
    Then the widget is refused with the plain-values error

  # C1-2 — Error case: an expression already in the table (written by update_column) is not run on render; defaults are used
  @security @rack_test
  Scenario: C1-2 A stored expression is ignored when the widget is opened
    Given Im logged in as a user "first_name=Gita" for an entity "name=Artha;entity_type=Investment Fund"
    And the user has role "company_admin"
    And a "Fund Ratios" widget in my entity whose metadata "{title: ENV.store('C1_2_MARKER', 'ran')}" was written by update_column
    When I open that widget
    Then the widget page renders
    And the expression in the widget metadata was not run
    And the widget metadata args are '{}'

  # C1-3 — Error case: an LP user creating a widget in their own entity cannot store an expression either
  @security @rack_test
  Scenario: C1-3 An LP user cannot save an expression as widget metadata
    Given Im logged in as a user "first_name=Lata" for an entity "name=Lata Family Office;entity_type=Investor"
    And the user has role "investor"
    When I post a new dashboard widget with metadata "{title: ENV.store('C1_3_MARKER', 'ran')}"
    Then the widget is refused with the plain-values error

  # C1-H — Happy path: a GP employee fills the dynamic fields (months, ratio names, condensed), saves, and the widget renders with them
  @security @javascript
  Scenario: C1-H The widget form's dynamic fields still save and render
    Given Im logged in as a user "first_name=Ravi" for an entity "name=Artha;entity_type=Investment Fund"
    And the user has role "employee"
    And a dashboard widget "Fund Ratios" exists for "Fund Dashboard"
    When I go to the edit page for the "Fund Ratios" widget
    Then I should see the "Widget Configuration" section
    When I fill in metadata "metadata_months" with "36"
    And I fill in metadata "metadata_ratio_names" with "XIRR, TVPI"
    And I select "ON" from "metadata_condensed"
    Then the "metadata" hidden field should contain "condensed: true"
    When I save the widget form
    Then the saved "Fund Ratios" widget metadata args include '{"months": 36, "ratio_names": ["XIRR", "TVPI"], "condensed": true}'
    And I should see "XIRR, TVPI"

  # C1-X1 — Edge case: %w[] and %i[] word arrays give the same arrays eval gave
  @security @rack_test
  Scenario: C1-X1 Word-array metadata renders with the same values
    Given Im logged in as a user "first_name=Gita" for an entity "name=Artha;entity_type=Investment Fund"
    And the user has role "company_admin"
    And a "Fund Ratios" widget in my entity is saved with metadata "{ratio_names: %w[XIRR TVPI DPI], months: 12}"
    When I open that widget
    Then the widget page renders
    And the widget metadata args are '{"ratio_names": ["XIRR", "TVPI", "DPI"], "months": 12}'

  # C1-X2 — Edge case: duplicate keys resolve last-wins, as eval did
  @security @rack_test
  Scenario: C1-X2 Duplicate metadata keys keep the last value
    Given Im logged in as a user "first_name=Gita" for an entity "name=Artha;entity_type=Investment Fund"
    And the user has role "company_admin"
    And a "Fund Ratios" widget in my entity is saved with metadata "{months: 12, condensed: true, months: 36}"
    When I open that widget
    Then the widget page renders
    And the widget metadata args are '{"months": 36, "condensed": true}'

  # C1-X3 — Edge case: escaped quotes inside single- and double-quoted strings unescape as eval did
  @security @rack_test
  Scenario: C1-X3 Escaped quotes in metadata strings
    Given Im logged in as a user "first_name=Gita" for an entity "name=Artha;entity_type=Investment Fund"
    And the user has role "company_admin"
    And a "Fund Ratios" widget in my entity is saved with metadata:
      """
      {title: 'Fund\'s view', note: "say \"hi\""}
      """
    When I open that widget
    Then the widget page renders
    And the widget metadata args are:
      """
      {"title": "Fund's view", "note": "say \"hi\""}
      """

  # C1-X4 — Edge case: blank metadata gives no settings, as eval of "" did
  @security @rack_test
  Scenario: C1-X4 Blank metadata
    Given Im logged in as a user "first_name=Gita" for an entity "name=Artha;entity_type=Investment Fund"
    And the user has role "company_admin"
    And a "Fund Ratios" widget in my entity is saved with metadata ""
    When I open that widget
    Then the widget page renders
    And the widget metadata args are '{}'

  # C1-X4 — Edge case: leading whitespace before the hash is ignored
  @security @rack_test
  Scenario: C1-X4 Metadata with leading whitespace
    Given Im logged in as a user "first_name=Gita" for an entity "name=Artha;entity_type=Investment Fund"
    And the user has role "company_admin"
    And a "Fund Ratios" widget in my entity is saved with metadata "   {months: 24}"
    When I open that widget
    Then the widget page renders
    And the widget metadata args are '{"months": 24}'

  # C1-X4 — Edge case: a trailing tab (as pasted from a spreadsheet) is ignored
  @security @rack_test
  Scenario: C1-X4 Metadata with a trailing tab
    Given Im logged in as a user "first_name=Gita" for an entity "name=Artha;entity_type=Investment Fund"
    And the user has role "company_admin"
    And a "Fund Ratios" widget in my entity is saved with metadata "{months: 24}" and a trailing tab
    When I open that widget
    Then the widget page renders
    And the widget metadata args are '{"months": 24}'

  # C1-X5 — Edge case: an xlsx import with one literal row and one expression row saves the literal and reports the expression row
  @security @rack_test @import
  Scenario: C1-X5 Import keeps the literal row and reports the expression row
    Given Im logged in as a user "first_name=Gita" for an entity "name=Artha;entity_type=Investment Fund"
    And the user has role "company_admin"
    When I import a dashboard widgets sheet with a literal row and an expression row
    Then the literal row is saved and the expression row is reported
