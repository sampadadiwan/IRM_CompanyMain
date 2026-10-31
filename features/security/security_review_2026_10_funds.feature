@security @rack_test
Feature: Funds / KPI / portfolio — Medium findings of the October 2026 security review
  M8, M9, M10, M19, M20, M21, M23, M24, M26, N2 and N3 from docs/security/security_review_2026_10.md
  ("Funds / KPI / portfolio — Medium and Low" and "New findings from the fix-design passes"). Each rule
  is checked where it is decided: policies and models directly, jobs by running them, and the M10
  allowlists through real requests.

  Background:
    # entity_type=Investment Fund so entity.is_fund? is true for the fund scopes
    Given there is an entity "name=Fund Entity;entity_type=Investment Fund"
    And there is a fund "name=Main Fund" for the entity "name=Fund Entity"
    # entity_type=Investor prevents setup_defaults adding unexpected roles
    And there is an entity "name=Investor Firm;entity_type=Investor"
    And there is an investor "investor_name=Big LP" for the entity "name=Fund Entity" with investor_entity "name=Investor Firm"
    And there is a user "email=admin@example.com" for the entity "name=Fund Entity"
    And the user "admin@example.com" has role "company_admin"
    And there is a user "email=employee@example.com" for the entity "name=Fund Entity"
    And the user "employee@example.com" has role "employee"
    And there is a user "email=investor@example.com" for the entity "name=Investor Firm"
    And the user "investor@example.com" has role "investor"
    And there is an approved investor access for "investor@example.com" and investor "Big LP"
    And another firm "Other Firm" has a fund "Other Fund" and a company admin "other@example.com"

  # ---------------------------------------------------------------------------------------------
  # M8 — cross-fund ratio runs read only funds the triggering user can see
  # ---------------------------------------------------------------------------------------------

  # M8-X1 — Edge case: a run naming another firm's fund fails with a notification and writes no run
  Scenario: M8-X1 A cross-fund run naming another firm's fund is refused
    When "admin@example.com" runs cross-fund ratios on the funds "Main Fund,Other Fund"
    Then no fund ratio run was saved
    And "admin@example.com" was told "Fund ratios not run"

  # M8-X2 — Edge case: the anchor fund must also be one the user can see
  Scenario: M8-X2 A cross-fund run anchored on another firm's fund is refused
    When "admin@example.com" runs cross-fund ratios on the funds "Main Fund" anchored on "Other Fund"
    Then no fund ratio run was saved
    And "admin@example.com" was told "Fund ratios not run"

  # M8-X3 — Edge case: an employee with no access right on the fund cannot run it either (same firm)
  Scenario: M8-X3 A fund-restricted employee's run on a fund they cannot see is refused
    When "employee@example.com" runs cross-fund ratios on the funds "Main Fund"
    Then no fund ratio run was saved
    And "employee@example.com" was told "Fund ratios not run"

  # M8-H1 — Happy path: a run over the user's own funds is saved as before
  Scenario: M8-H1 A cross-fund run over my own fund is saved
    When "admin@example.com" runs cross-fund ratios on the funds "Main Fund"
    Then a fund ratio run was saved for the funds "Main Fund"

  # M8-X4 — Edge case: a stored template never names another firm's fund (source or anchor)
  Scenario: M8-X4 A ratio run template naming another firm's fund is invalid
    Then a ratio run template of "Fund Entity" on the funds "Other Fund" is invalid
    And a ratio run template of "Fund Entity" anchored on "Other Fund" is invalid
    And a ratio run template of "Fund Entity" on the funds "Main Fund" is valid

  # M8-E1 — Edge case: in a batch, a template over another firm's fund fails alone; the rest still run
  Scenario: M8-E1 A batch skips the refused template and runs the others
    Given "Fund Entity" has a stored ratio run template "Bad" on the funds "Other Fund"
    And "Fund Entity" has a stored ratio run template "Good" on the funds "Main Fund"
    When "admin@example.com" runs the ratio run templates "Bad,Good" as a batch
    Then a fund ratio run was saved for the funds "Main Fund"
    And "admin@example.com" was told "Fund ratios not run"

  # ---------------------------------------------------------------------------------------------
  # M9 — a generation template_id is resolved inside the parent's own templates
  # ---------------------------------------------------------------------------------------------

  # M9-X1 — Edge case: another firm's Commitment Template id finds no template
  Scenario: M9-X1 Commitment documents with another firm's template find no template
    Given the fund "Main Fund" has a commitment
    And the fund "Other Fund" has a "Commitment Template" named "Foreign Agreement"
    When the commitment documents are generated with the template "Foreign Agreement"
    Then the generation reports "No templates found"
    And no commitment document was rendered

  # M9-H1 — Happy path: the fund's own Commitment Template is found
  Scenario: M9-H1 Commitment documents with the fund's own template find it
    Given the fund "Main Fund" has a commitment
    And the fund "Main Fund" has a "Commitment Template" named "Fund Agreement"
    When the commitment documents are generated with the template "Fund Agreement"
    Then the generation does not report "No templates found"

  # M9-X2 — Edge case: KYC documents with another firm's template find no template
  Scenario: M9-X2 KYC documents with another firm's template find no template
    Given "Big LP" has an unverified KYC
    And the fund "Other Fund" has a "SOA Template" named "Foreign Statement"
    When the KYC documents are generated with the template "Foreign Statement"
    Then the generation reports "No templates found"

  # M9-H3 — Happy path: a template of the KYC's own firm is found
  Scenario: M9-H3 KYC documents with my firm's template find it
    Given "Big LP" has an unverified KYC
    And the fund "Main Fund" has a "SOA Template" named "Investor Statement"
    When the KYC documents are generated with the template "Investor Statement"
    Then the generation does not report "No templates found"

  # M9-E1 — Edge case: an empty KYC id list (a scoped search that matched nothing) never falls back to
  # every KYC of an entity named by the request
  Scenario: M9-E1 An empty KYC list with another firm's entity id finds no records
    Given the fund "Main Fund" has a "SOA Template" named "Investor Statement"
    When the KYC documents for no KYCs are generated for the entity "Other Firm" with the template "Investor Statement"
    Then the generation reports "No records found"

  # ---------------------------------------------------------------------------------------------
  # M10 — request-named templates are allowlisted
  # ---------------------------------------------------------------------------------------------

  # M10-X1 — Edge case: a commitment report other than lp_statement is a 404
  Scenario: M10-X1 A crafted commitment report name is not rendered
    Given the fund "Main Fund" has a commitment
    And I log in with email "admin@example.com"
    When I open the commitment report "../../users/index"
    Then the response is not found

  # M10-X2 — Edge case: a documents list template the app does not link to is a 404
  Scenario: M10-X2 A crafted documents template is not rendered
    Given I log in with email "admin@example.com"
    When I open the documents list with the template "/users/index"
    Then the response is not found

  # M10-H2 — Happy path: the plain documents list still renders
  Scenario: M10-H2 The plain documents list still renders
    Given I log in with email "admin@example.com"
    When I open the documents list with the template ""
    Then the response is OK

  # M10-X3 — Edge case: an unknown access-right form_type gets the default form, not a request-named partial
  Scenario: M10-X3 A crafted access-right form type falls back to the default form
    Given I log in with email "admin@example.com"
    When I open the new access right form of the fund "Main Fund" with the form type "../users/show"
    Then the response is OK
    And the page shows "New Access Right"

  # ---------------------------------------------------------------------------------------------
  # M19 — KPI recompute and the periodic trigger are fund-only; the all-tenant trigger is support-only
  # ---------------------------------------------------------------------------------------------

  # M19-H1 — Happy path: the fund's own employee may recompute
  Scenario: M19-H1 The fund's employee may recompute a KPI report
    Given "Fund Entity" has a KPI report for the portfolio company "Acme Robotics" with a portco user "portco@example.com"
    Then the user "employee@example.com" should be allowed "recompute_percentage_change,recompute_cumulative,recompute_fx_conversion" on the record

  # M19-X1 — Edge case: the portfolio company's own user may not recompute the fund's report
  Scenario: M19-X1 A portfolio company user may not recompute
    Given "Fund Entity" has a KPI report for the portfolio company "Acme Robotics" with a portco user "portco@example.com"
    Then the user "portco@example.com" should be denied "recompute_percentage_change,recompute_cumulative,recompute_fx_conversion" on the record

  # M19-X2 — Edge case: another firm's KPI user may not recompute
  Scenario: M19-X2 Another firm's user may not recompute
    Given "Fund Entity" has a KPI report for the portfolio company "Acme Robotics" with a portco user "portco@example.com"
    Then the user "other@example.com" should be denied "recompute_percentage_change,recompute_cumulative,recompute_fx_conversion" on the record

  # M19-H2 / M19-X4 — Happy path and edge case: the periodic trigger on one report is fund-only
  Scenario: M19-H2 The periodic trigger on a report is for the report's fund firm only
    Given "Fund Entity" has a KPI report for the portfolio company "Acme Robotics" with a portco user "portco@example.com"
    Then the user "employee@example.com" should be allowed "trigger_periodic_reports" on the record
    And the user "other@example.com" should be denied "trigger_periodic_reports" on the record
    And the user "portco@example.com" should be denied "trigger_periodic_reports" on the record

  # M19-X3 — Edge case: the all-tenant periodic trigger (no report, no company) is support-only
  Scenario: M19-X3 Only support may fire the all-tenant periodic trigger
    Given there is a user "email=support@example.com" for the entity "name=Fund Entity"
    And the user "support@example.com" has role "support"
    And the record is the KPI report class
    Then the user "admin@example.com" should be denied "trigger_periodic_reports" on the record
    And the user "support@example.com" should be allowed "trigger_periodic_reports" on the record

  # ---------------------------------------------------------------------------------------------
  # M20 — portfolio report templates stay in their report's firm
  # ---------------------------------------------------------------------------------------------

  # M20-H1 / M20-X1 / M20-X2 — the report's own company admin manages its templates; another firm's
  # company admin can neither open nor change them
  Scenario: M20-X1 Another firm cannot open or change a portfolio report template
    Given "Fund Entity" has a portfolio report template
    Then the user "admin@example.com" should be allowed "show,create,update,destroy" on the record
    And the user "other@example.com" should be denied "show,create,update,destroy" on the record

  # M20-X4 — Edge case: a template's style document must be its report's firm's
  Scenario: M20-X4 A portfolio report template cannot use another firm's style document
    Given "Fund Entity" has a portfolio report template
    And the fund "Other Fund" has a "Style" named "Foreign Style"
    And the fund "Main Fund" has a "Style" named "House Style"
    Then the portfolio report template with the style document "Foreign Style" is invalid
    And the portfolio report template with the style document "House Style" is valid

  # ---------------------------------------------------------------------------------------------
  # M21 — deleting an exchange rate needs the rights to add one
  # ---------------------------------------------------------------------------------------------

  # M21-X1 / M21-H1 — another firm's user cannot delete the rate; the firm's own admin can
  Scenario: M21-X1 Another firm cannot delete an exchange rate
    Given "Fund Entity" has an exchange rate "USD" to "INR"
    Then the user "admin@example.com" should be allowed "destroy" on the record
    And the user "other@example.com" should be denied "destroy" on the record

  # M21-X2 — Edge case: a fund-specific rate needs update access on that fund
  Scenario: M21-X2 A fund-restricted employee cannot delete a fund's own exchange rate
    Given "Fund Entity" has an exchange rate "USD" to "INR" for the fund "Main Fund"
    Then the user "employee@example.com" should be denied "destroy" on the record
    And the user "admin@example.com" should be allowed "destroy" on the record

  # ---------------------------------------------------------------------------------------------
  # M23 — LPs never open fund-level account entries by id
  # ---------------------------------------------------------------------------------------------

  # M23-X1 — Edge case: a fund-level entry (no investor) is refused to an LP with fund access
  Scenario: M23-X1 An LP cannot open a fund-level account entry
    Given I grant "read" access to the fund for investor "Big LP"
    And there is a fund-level account entry for the fund
    Then the user "investor@example.com" should be denied "show,explain" on the record

  # M23-H1 — Happy path: the LP's own entry still opens
  Scenario: M23-H1 An LP can still open their own account entry
    Given I grant "read" access to the fund for investor "Big LP"
    And there is an account entry for the fund
    Then the user "investor@example.com" should be allowed "show,explain" on the record

  # ---------------------------------------------------------------------------------------------
  # M24 — a fund formula never moves to another fund
  # ---------------------------------------------------------------------------------------------

  # M24-X1 — Edge case: moving a formula to another firm's fund is refused and it stays where it was
  Scenario: M24-X1 A fund formula cannot be moved to another firm's fund
    Given the fund "Main Fund" has a formula "Management Fee"
    When the formula "Management Fee" is moved to the fund "Other Fund"
    Then the formula "Management Fee" is on the fund "Main Fund"

  # M24-X2 / M24-H1 — a new formula's fund must be in the formula's own firm
  Scenario: M24-X2 A new formula on another firm's fund is invalid
    Then a new formula of "Fund Entity" on the fund "Other Fund" is invalid
    And a new formula of "Fund Entity" on the fund "Main Fund" is valid

  # ---------------------------------------------------------------------------------------------
  # M26 — API destroy / add, and e-sign signer rows, need fund / document rights
  # ---------------------------------------------------------------------------------------------

  # M26-X1 / M26-X2 — Edge case: a plain employee with no fund rights loses add and destroy
  Scenario: M26-X1 A plain employee cannot change or destroy an aggregate portfolio investment
    Given there is an aggregate portfolio investment for the fund
    Then the user "employee@example.com" should be denied "add_valuation,add_investment,destroy" on the record
    And the user "admin@example.com" should be allowed "add_valuation,add_investment,destroy" on the record

  # M26-H1 / M26-H2 — Happy path: an employee with update and destroy rights on the fund keeps them
  Scenario: M26-H2 An employee with fund rights may change and destroy an aggregate portfolio investment
    Given I grant "read,update,destroy" access to the fund for user "employee@example.com"
    And there is an aggregate portfolio investment for the fund
    Then the user "employee@example.com" should be allowed "add_valuation,add_investment,destroy" on the record

  # M26-X3 / M26-X4 / M26-H3 — signer rows need edit rights on the document
  Scenario: M26-X3 A plain employee cannot add or change a document's signers
    Given the fund "Main Fund" has a document "Side Letter"
    And there is a signer row on the document "Side Letter"
    Then the user "employee@example.com" should be denied "create,update,destroy" on the record
    And the user "admin@example.com" should be allowed "create,update,destroy" on the record
    And the user "other@example.com" should be denied "create,update,destroy" on the record

  # ---------------------------------------------------------------------------------------------
  # N2 — the fund formula's name is data in the roll-up formulas, never formula text
  # ---------------------------------------------------------------------------------------------

  # N2-X1 — Edge case: a name holding a quote and #{...} reaches the roll-up helper unchanged
  Scenario: N2-X1 A formula name with a quote is passed as data to the roll-ups
    Then the roll-up formulas for the formula name "Manager's #{1+1} Fee" pass that exact name

  # N2-H1 — Happy path: an ordinary name keeps the stored explanation text unchanged
  Scenario: N2-H1 An ordinary formula name keeps the stored roll-up text
    Then the stored roll-up text for the formula name "Management Fee" is "capital_commitment.quarterly('Management Fee', nil, @start_date, @end_date) + carry"

  # ---------------------------------------------------------------------------------------------
  # N3 — the formula generator's examples come from the user's own firm
  # ---------------------------------------------------------------------------------------------

  # N3-X1 / N3-H1 — another firm's same-named formula never reaches the prompt; mine does
  Scenario: N3-X1 Formula generator examples are scoped to my firm
    Given the fund "Other Fund" has a formula "Carry" described as "OTHER FIRM SECRET"
    And the fund "Main Fund" has a formula "Carry" described as "OUR OWN EXAMPLE"
    When "admin@example.com" asks the formula generator for "Carry"
    Then the generator prompt includes "OUR OWN EXAMPLE"
    And the generator prompt does not include "OTHER FIRM SECRET"
