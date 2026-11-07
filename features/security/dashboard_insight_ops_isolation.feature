# Worked examples X3, X10, X11 — openspec/changes/dashboard-insight-widgets/business-rules.md#1, #6, #7
Feature: Ops and investor insight widgets count only what the viewer may see
  Needs Attention, Investor Pending Actions and the task counts go through the same policy scopes as the lists
  they link to, so another firm's records and records the viewer cannot open are never counted.

  Background:
    Given today is "2026-09-30"
    And Im logged in as a user "first_name=Meera;last_name=Ops" for an entity "name=Demo Capital;entity_type=Investment Fund;currency=INR"
    And the user has role "company_admin"
    And the ops insight LP "Asha Family Office" has a commitment in "Growth Fund I"

  # X3 — Error case: another firm's overdue task never appears in Demo Capital's count
  @rack_test
  Scenario: Other firm's data never appears
    Given the "Needs Attention" widget on the "Ops Dashboard" has settings ""
    And there are 1 ops insight open tasks due "2026-09-20" for "Meera"
    And another firm has an overdue ops insight task
    When I open the Ops Dashboard for the ops insight widgets
    Then the ops insight card "Overdue tasks" should show 1

  # X10 — Error case: an employee without access to a fund does not see that fund's remittance on the LP's dashboard
  @rack_test
  Scenario: Employee without fund access
    Given the "Investor Pending Actions" widget on the "Investor Dashboard" has settings ""
    And the ops insight LP "Asha Family Office" owes 20 lakh on call "Call 3" in "Growth Fund I" due "2026-09-15" with status "Overdue"
    And the ops insight LP "Asha Family Office" owes 10 lakh on call "Second Fund Call" in "Second Fund" due "2026-09-10" with status "Overdue"
    And the ops insight employee "Ravi" can access only the fund "Growth Fund I"
    And I sign in as the ops insight employee "Ravi"
    When I open the investor dashboard of "Asha Family Office" for the ops insight widgets
    Then the ops insight section "Unpaid calls" should list "Call 3"

  # X11 — Error case: an employee who is not an admin counts only the tasks his task policy lets him see
  @rack_test
  Scenario: Employee sees only their tasks' scope
    Given the "Needs Attention" widget on the "Ops Dashboard" has settings ""
    And the ops insight employee "Ravi" can access only the fund "Growth Fund I"
    And there are 1 ops insight open tasks due "2026-09-20" for "Ravi"
    And there are 2 ops insight open tasks due "2026-09-20" for "Meera"
    And I sign in as the ops insight employee "Ravi"
    When I open the Ops Dashboard for the ops insight widgets
    Then the ops insight card "Overdue tasks" should show 1
