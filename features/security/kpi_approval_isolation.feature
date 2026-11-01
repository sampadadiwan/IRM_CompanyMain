Feature: KPI approval isolation - 2026-10 security review (H14)
  The portfolio company submits KPIs; the fund that owns them (the KPI's entity) reviews them.
  Approving, rejecting and unapproving were role checks only, so an approver or company admin of any
  firm - or an LP user holding the approver role - could act on another fund's KPIs. Each scenario
  closes one such way in, and is paired with the fund's own and support's legitimate use.
  Design and worked examples: docs/security/security_review_2026_10.md (card "H14 — KPI approval").

  Background:
    Given Im logged in as a user "first_name=Asha" for an entity "name=Artha;entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is an existing portfolio company "name=MyStartup;category=Portfolio Company"
    And the following KPI mappings exist for the portfolio company:
      | reported_kpi_name |
      | Revenue           |
      | EBITDA            |

  # H14-1 — Edge case: another firm's approver cannot approve this fund's KPI
  @security @rack_test
  Scenario: H14-1 Another firm's approver approving my fund's KPI is refused
    Given there is an unapproved KPI "name=Revenue;value=1000" for the company
    And I am signed in as an approver of another firm "Zeta Capital"
    When I approve the KPI by its address
    Then I am denied access
    And the KPI "Revenue" should have "unapproved" status in the database

  # H14-2 — Edge case: another firm's admin posting this fund's entity to approve-all / reject-all is refused
  @security @rack_test
  Scenario: H14-2 Another firm's admin approving or rejecting all of my fund's pending KPIs is refused
    Given the following unapproved KPIs exist for the company:
      | name    | value |
      | Revenue | 2000  |
      | EBITDA  | 500   |
    And KPI report journey moves are watched
    And I am signed in as a company admin of another firm "Zeta Capital"
    When I reject all pending KPIs of the portfolio company for the fund "Artha"
    Then I am denied access
    When I approve all pending KPIs of the portfolio company for the fund "Artha"
    Then I am denied access
    And all KPIs for "MyStartup" should have "unapproved" status in the database
    And no KPI report journey was moved

  # H14-3 — Edge case: another firm's approver cannot unapprove this fund's approved KPI
  @security @rack_test
  Scenario: H14-3 Another firm's approver unapproving my fund's KPI is refused
    Given there is an approved KPI "name=Revenue;value=1000" for the company
    And I am signed in as an approver of another firm "Zeta Capital"
    When I unapprove the KPI by its address
    Then I am denied access
    And the KPI "Revenue" should have "approved" status in the database

  # H14-4 — Edge case: an LP user of the fund holding the approver role gets no Approve / Reject
  @security @rack_test
  Scenario: H14-4 An LP user with the approver role cannot approve a KPI shared with them
    Given there is an unapproved KPI "name=Revenue;value=1000" for the company
    And there is an LP user of my firm with the approver role who is shown the KPI
    Then the LP user is offered no Approve or Reject on the KPI
    When the LP user approves the KPI by its address
    Then I am denied access
    And the KPI "Revenue" should have "unapproved" status in the database

  # H14-X — Edge case: with nothing pending, another firm's reject-all no longer moves this fund's journeys
  @security @rack_test
  Scenario: H14-X Another firm's reject-all with nothing pending is refused and moves no journey
    Given there is an approved KPI "name=Revenue;value=1000" for the company
    And KPI report journey moves are watched
    And I am signed in as a company admin of another firm "Zeta Capital"
    When I reject all pending KPIs of the portfolio company for the fund "Artha"
    Then I am denied access
    And no KPI report journey was moved
    And the KPI "Revenue" should have "approved" status in the database

  # H14-H — Happy path: the fund's own approver approves one KPI and rejects another
  @security @rack_test
  Scenario: H14-H The fund's approver approves and rejects its KPIs
    Given there is an unapproved KPI "name=Revenue;value=1000" for the company
    And there is an unapproved KPI "name=EBITDA;value=500" for the company as the second KPI
    And I am signed in as an approver of my firm
    When I approve the KPI by its address
    Then the KPI "Revenue" should have "approved" status in the database
    When I reject the second KPI by its address
    Then the KPI "EBITDA" should not exist in the database

  # H14-H2 — Happy path: support still approves and rejects KPIs as themselves
  @security @rack_test
  Scenario: H14-H2 A support user approves and rejects the fund's KPIs
    Given there is an unapproved KPI "name=Revenue;value=1000" for the company
    And there is an unapproved KPI "name=EBITDA;value=500" for the company as the second KPI
    And I am signed in as a support user of another firm "CapHive Support"
    When I approve the KPI by its address
    Then the KPI "Revenue" should have "approved" status in the database
    When I reject the second KPI by its address
    Then the KPI "EBITDA" should not exist in the database
