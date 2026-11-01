Feature: Core / misc low findings - 2026-10 security review
  Hardening fixes from the "Core / misc — Medium and Low" table. Each refusal is paired with the
  legitimate use that must keep working. Scenarios set up their own data (no shared Background), so
  findings can be added independently.
  Design and worked examples: docs/security/security_review_2026_10.md#core--misc--medium-and-low

  # L10-1 — Edge case: the uncalled deal activity reorder endpoints are gone, so another firm cannot move a deal's steps by id
  @security @rack_test
  Scenario: L10-1 Both old deal step reorder addresses give 404 and the steps keep their order
    Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Company"
    And the user has role "company_admin"
    And there exists a deal "name=Series A;amount_cents=500000" for my company without templates
    And the deal has "3" step templates
    And I am signed in as a company admin of another firm "Zeta Capital"
    When they post a new position for the deal step "Existing Template 1" to the old reorder address
    Then the address is not found
    When they open the old single-step reorder address for the deal step "Existing Template 1"
    Then the address is not found
    And the deal's template steps are in the order "Existing Template 1, Existing Template 2, Existing Template 3"

  # L10-H — Happy path: the deal's admin still reorders a step from the activity edit form
  @security @rack_test
  Scenario: L10-H The deal's company admin moves a step to the top from its edit form
    Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Company"
    And the user has role "company_admin"
    And there exists a deal "name=Series A;amount_cents=500000" for my company without templates
    And the deal has "3" step templates
    When I set the order of the deal step "Existing Template 3" to 1 from its edit form
    Then the deal's template steps are in the order "Existing Template 3, Existing Template 1, Existing Template 2"

  # ---- L1 direct-upload endpoint -------------------------------------------------------------

  # L1-1 — Edge case: the upload endpoint was mounted for anyone; a visitor who is not signed in and opened no magic link stores files in the bucket
  @security @rack_test
  Scenario: L1-1 An anonymous upload is not found
    Given I am not signed in
    When a file is posted to the upload endpoint
    Then the address is not found

  # L1-2 — Edge case: a magic-link visit opens uploads for 2 hours only
  @security @rack_test
  Scenario: L1-2 A magic-link visitor can't upload once the 2-hour window has passed
    Given there is a user "first_name=FundAdmin" for an entity "name=VentureFund;entity_type=Investment Fund"
    And there is an existing portfolio company "name=MyStartup;category=Portfolio Company"
    And a KpiReport "as_of=2024-12-31;period=Month" exists for the portfolio company "MyStartup"
    And there is a user "first_name=PortCoUser" for an existing entity "name=MyStartup;category=Portfolio Company"
    And "PortCoUser" opens the KPI report's magic link without signing in
    And 3 hours pass
    When a file is posted to the upload endpoint
    Then the address is not found

  # L1-H — Happy path: a signed-in user's Uppy upload is stored
  @security @rack_test
  Scenario: L1-H A signed-in user uploads a file
    Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
    When a file is posted to the upload endpoint
    Then the upload is stored

  # L1-H2 — Happy path: a portfolio company user who opened the KPI magic link uploads while signed out
  @security @rack_test
  Scenario: L1-H2 A magic-link visitor uploads within the window
    Given there is a user "first_name=FundAdmin" for an entity "name=VentureFund;entity_type=Investment Fund"
    And there is an existing portfolio company "name=MyStartup;category=Portfolio Company"
    And a KpiReport "as_of=2024-12-31;period=Month" exists for the portfolio company "MyStartup"
    And there is a user "first_name=PortCoUser" for an existing entity "name=MyStartup;category=Portfolio Company"
    And "PortCoUser" opens the KPI report's magic link without signing in
    And 1 hour passes
    When a file is posted to the upload endpoint
    Then the upload is stored

  # ---- L6 ActionCable --------------------------------------------------------------------------

  # L6-1 — Edge case: ActionCable identified nobody, so an anonymous socket could subscribe to any stream name it knew
  @security
  Scenario: L6-1 A socket with no signed-in user and no magic-link visit is refused
    When a live-update socket connects with no user
    Then the socket is refused

  # L6-2 — Edge case: a magic-link visit older than the 2-hour window no longer identifies a socket
  @security
  Scenario: L6-2 A socket from an expired magic-link visit is refused
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
    When a live-update socket connects from a magic-link visit by "Test" 3 hours ago
    Then the socket is refused

  # L6-H — Happy path: signed-in users and recent magic-link visitors keep their live updates
  @security
  Scenario: L6-H Signed-in and magic-link sockets are identified as their user
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
    When a live-update socket connects signed in as "Test"
    Then the socket belongs to "Test"
    When a live-update socket connects from a magic-link visit by "Test" 30 minutes ago
    Then the socket belongs to "Test"

  # L6-H2 — Happy path: deactivating a user, or changing their password, closes their open sockets
  @security
  Scenario: L6-H2 Deactivation and password change disconnect the user's sockets
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
    And live-update disconnects are recorded
    When "Test" sets a new password on their profile
    Then the sockets of "Test" were disconnected 1 time
    When "Test" is deactivated through their user record
    Then the sockets of "Test" were disconnected 2 times

  # ---- L11 blog / deal activities ------------------------------------------------------------

  # L11-1 — Edge case: BlogPolicy allowed every write to every signed-in user
  @security @rack_test
  Scenario: L11-1 A company admin can't write a blog
    Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
    And the user has role "company_admin"
    When I post a new blog "Quarterly update"
    Then I am denied access
    And there is no blog "Quarterly update"

  # L11-H — Happy path: support writes blogs; anyone signed in reads them
  @security @rack_test
  Scenario: L11-H Support writes a blog
    Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
    And the user has role "support"
    When I post a new blog "Quarterly update"
    Then there is a blog "Quarterly update"

  # L11-2 — Edge case: the activity list was wider than show?: an employee saw activities of deals they have no access to
  @security
  Scenario: L11-2 An employee lists only the activities of deals they can see
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
    And my firm has the deals "Alpha" and "Beta" each with the step "Term sheet"
    And my firm has the employee "Kiran" with access to the deal "Alpha" only
    Then the deal activities "Kiran" lists are those of the deal "Alpha" only

  # L11-H2 — Happy path: a company admin lists every activity of the firm
  @security
  Scenario: L11-H2 A company admin lists every deal's activities
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
    And the user has role "company_admin"
    And my firm has the deals "Alpha" and "Beta" each with the step "Term sheet"
    Then the deal activities the user lists are those of the deals "Alpha, Beta"

  # L11-3 — Edge case: deal activity search ran unauthorized (and crashed); it now returns the user's own list only
  @security @rack_test
  Scenario: L11-3 Deal activity search shows only the deals the employee can see
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
    And my firm has the deals "Alpha" and "Beta" each with the step "Term sheet"
    And my firm has the employee "Kiran" with access to the deal "Alpha" only
    And "Kiran" is signed in for the deal activity search
    When they search deal activities for "Term"
    Then the search lists the step of the deal "Alpha" but not the deal "Beta"

  # ---- L12 small lookups ---------------------------------------------------------------------

  # L12-1 — Edge case: deals#create clone_from_id copied another firm's deal step templates
  @security
  Scenario: L12-1 A new deal can't clone another firm's deal
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
    And the firm "Zeta Capital" has a deal "Zeta Secret" with the step "Zeta diligence"
    When my firm creates a deal "Series B" cloned from the deal "Zeta Secret"
    Then the deal is refused with "Clone from must be in this record's firm"
    And no deal step "Zeta diligence" exists in my firm

  # L12-H1 — Happy path: a new deal clones the steps of one of the firm's own deals
  @security
  Scenario: L12-H1 A new deal clones my firm's deal steps
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
    And my firm has the deals "Alpha" and "Beta" each with the step "Term sheet"
    When my firm creates a deal "Series B" cloned from the deal "Alpha"
    Then the deal "Series B" has the step "Term sheet Alpha"

  # L12-2 — Edge case: CallFee.where(id: fee_formula_ids) applied another firm's fee formula to this call
  @security
  Scenario: L12-2 A capital call can't use another firm's fee formula
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
    And my firm has a fund "Alpha Fund" with the fee formula "Mgmt Fee"
    And the firm "Zeta Capital" has a fund "Zeta Fund" with the fee formula "Zeta Fee"
    When a capital call of the fund "Alpha Fund" selects the fee formula "Zeta Fee"
    Then the capital call is refused with "Fee formula ids must be call fee formulas of this firm"
    And a capital call of the fund "Alpha Fund" storing the fee formula "Zeta Fee" does not apply it

  # L12-H2 — Happy path: reusing a fee formula from another fund of the same firm is real (prod) and keeps working
  @security
  Scenario: L12-H2 A capital call uses a fee formula from another fund of my firm
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
    And my firm has a fund "Alpha Fund" with the fee formula "Mgmt Fee"
    And my firm has a fund "Beta Fund"
    When a capital call of the fund "Beta Fund" selects the fee formula "Mgmt Fee"
    Then the capital call accepts the fee formulas

  # L12-3 — Edge case: fund_formulas#generate_formula ran the paid LLM call for any signed-in user
  @security @rack_test
  Scenario: L12-3 A company admin can't run the formula generator
    Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
    And the user has role "company_admin"
    And the formula generator is stubbed
    When I ask the formula generator for "Management fee at 2% of commitment"
    Then I am denied access
    And the formula generator was called 0 times

  # L12-H3 — Happy path: support generates formulas
  @security @rack_test
  Scenario: L12-H3 Support runs the formula generator
    Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
    And the user has role "support"
    And the formula generator is stubbed
    When I ask the formula generator for "Management fee at 2% of commitment"
    Then the formula generator was called 1 time

  # L12-4 — Edge case: investor_kpi_mappings#generate loaded any investor by id and created mappings unauthorized
  @security @rack_test
  Scenario: L12-4 Another firm's admin can't generate KPI mappings for my portfolio company
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
    And there is an existing portfolio company "name=MyStartup;category=Portfolio Company"
    And I am signed in as a company admin of another firm "Zeta Capital"
    When they generate KPI mappings for the portfolio company "MyStartup"
    Then I am denied access
    And the portfolio company "MyStartup" has no KPI mappings

  # L12-H4 — Happy path: the firm's company admin may generate its portfolio company's mappings; a plain employee may not
  @security
  Scenario: L12-H4 Only those who may create mappings may generate them
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is an existing portfolio company "name=MyStartup;category=Portfolio Company"
    And my firm has the employee "Kiran" with access to nothing
    Then the user may generate KPI mappings for the portfolio company "MyStartup"
    And "Kiran" may not generate KPI mappings for the portfolio company "MyStartup"

  # L12-5 — Edge case: the auto-assignment rule screens loaded another firm's workflow template by id, and a rule could name it
  @security @rack_test
  Scenario: L12-5 Another firm's admin can't open or use my workflow template's rules
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
    And my firm has the workflow template "KYC Approval"
    And I am signed in as a company admin of another firm "Zeta Capital"
    When they open the new auto-assignment rule page of the template "KYC Approval"
    Then I am denied access
    And a rule of the firm "Zeta Capital" for the template "KYC Approval" is refused with "Workflow template must be in this record's firm"

  # L12-H5 — Happy path: a rule of the firm's own template saves
  @security
  Scenario: L12-H5 A rule for my firm's template saves
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
    And my firm has the workflow template "KYC Approval"
    Then a rule of my firm for the template "KYC Approval" saves

  # L12-6 — Edge case: investors#generate_reports took the portfolio report template id from the request unscoped
  @security @rack_test
  Scenario: L12-6 A report draft can't use another firm's report template
    Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is an existing portfolio company "name=MyStartup;category=Portfolio Company"
    And the firm "Zeta Capital" has the portfolio report template "Zeta Quarterly"
    When I generate a report for "MyStartup" with the template "Zeta Quarterly"
    Then I am denied access
    And no report draft exists for "MyStartup"
    And a report draft for "MyStartup" with the template "Zeta Quarterly" is refused

  # L12-H6 — Happy path: a draft with the firm's own template is valid
  @security
  Scenario: L12-H6 A report draft with my firm's template is valid
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
    And there is an existing portfolio company "name=MyStartup;category=Portfolio Company"
    And my firm has the portfolio report template "Urban Quarterly"
    Then a report draft for "MyStartup" with the template "Urban Quarterly" is valid

  # L12-7 — Edge case: entities#search listed every firm in the system to any signed-in user (investors included)
  @security @rack_test
  Scenario: L12-7 An investor can't search firms
    Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
    And the user has curr role "investor"
    When I search firms for "Zeta"
    Then I am denied access

  # L12-H7 — Happy path: an employee's stakeholder autocomplete lists only firms already linked as the firm's stakeholders
  @security @rack_test
  Scenario: L12-H7 An employee's firm search lists only linked stakeholder firms
    Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
    And my firm has the stakeholder firm "Zeta Holdings"
    And the firm "Zeta Partners" has no link to my firm
    And the firm search index finds "Zeta Holdings, Zeta Partners"
    When I search firms for "Zeta"
    Then the firm search lists "Zeta Holdings" but not "Zeta Partners"

  # ---- L14 `*_type` request params -----------------------------------------------------------

  # L14-1 … L14-14 — Edge case: a request naming a class that is not a model (Kernel), or a model this screen does not list (notes of a Fund), was constantized and answered 500; it is now refused as not found
  @security @rack_test
  Scenario Outline: <id> An unknown type name in <address> is refused, not constantized
    Given the firm "Alpha Capital" with company admin "Priya"
    And "Ravi" is a plain employee of "Alpha Capital"
    And "<who>" is signed in
    When they send a "<method>" request to "<address>"
    Then I am denied access

    Examples:
      | id     | who   | method | address                                                             |
      | L14-1  | Ravi  | GET    | /custom_notifications?owner_type=Kernel&owner_id=1                  |
      | L14-2  | Priya | GET    | /documents?owner_type=Kernel&owner_id=1                             |
      | L14-4  | Priya | GET    | /tasks?owner_type=Kernel&owner_id=1                                 |
      | L14-5  | Priya | GET    | /access_rights?owner_type=Kernel&owner_id=1                         |
      | L14-5b | Priya | GET    | /investors?owner_type=Kernel&owner_id=1                             |
      | L14-6  | Priya | GET    | /valuations?owner_type=Kernel&owner_id=1                            |
      | L14-7  | Priya | GET    | /custom_notifications?q[owner_type_eq]=Kernel&q[owner_id_eq]=1      |
      | L14-8  | Priya | GET    | /events?owner_type=Kernel&owner_id=1                                |
      | L14-9  | Priya | GET    | /boards/owner_ids?owner_type=Kernel                                 |
      | L14-10 | Priya | GET    | /grid_view_preferences/configure_grids?owner_type=Kernel&owner_id=1 |
      | L14-11 | Priya | POST   | /reports/prompt?model_class=Kernel                                  |
      | L14-12 | Priya | POST   | /ai_checks/run_checks?owner_type=Kernel&owner_id=1                  |
      | L14-13 | Priya | POST   | /task_templates/generate?for_class=Kernel&for_class_id=1            |
      | L14-14 | Priya | GET    | /notes?owner_type=Fund&owner_id=1                                   |

  # L14-3 — Edge case: the tasks board heading looked its owner up by id in any firm, so it printed another firm's stakeholder name
  @security @rack_test
  Scenario: L14-3 The tasks board heading does not name another firm's stakeholder
    Given the firm "Alpha Capital" with company admin "Priya"
    And the firm "Zeta Capital" with company admin "Zed"
    And "Zeta Capital" has an investor "Zeta Secret Stakeholder"
    And "Priya" is signed in
    When they open the tasks board for the investor "Zeta Secret Stakeholder"
    Then the response does not mention "Zeta Secret Stakeholder"

  # L14-H — Happy path: the firm's own stakeholder still heads its tasks board, and its notes list still opens
  @security @rack_test
  Scenario: L14-H The firm's own stakeholder's board heading and notes still load
    Given the firm "Alpha Capital" with company admin "Priya"
    And "Alpha Capital" has an investor "Ajay Family Trust"
    And "Priya" is signed in
    When they open the tasks board for the investor "Ajay Family Trust"
    Then the response mentions "Ajay Family Trust"
    When they open the notes of the investor "Ajay Family Trust"
    Then the page loads
