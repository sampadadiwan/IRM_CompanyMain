# Worked examples H19–H24, E54–E63 — openspec/changes/archive/2026-11-07-dashboard-insight-widgets/business-rules.md#7
Feature: Ops Dashboard insight widgets
  Needs Attention counts stuck work and links to it; Overdue Tasks by Assignee shows who is behind; Stuck Workflows
  lists journeys waiting too long on a step; Side-letter Obligations lists obligations falling due across LPs.

  Background:
    Given today is "2026-09-30"
    And Im logged in as a user "first_name=Meera;last_name=Ops" for an entity "name=Demo Capital;entity_type=Investment Fund;currency=INR"
    And the user has role "company_admin"
    And the ops insight LP "Asha Family Office" has a commitment in "Growth Fund I"

  # H19 — Happy path: 3 overdue tasks, 2 KYCs submitted but not verified, 4 Overdue remittances, 1 open e-sign request
  @rack_test
  Scenario: Needs Attention counts what is stuck
    Given the "Needs Attention" widget on the "Ops Dashboard" has settings ""
    And there are 3 ops insight open tasks due "2026-09-20" for "Meera"
    And the ops insight LP "Asha Family Office" has a KYC "Asha Mehta" with status "completed" expiring "2027-06-30"
    And the ops insight LP "Asha Family Office" has a KYC "Rohan Mehta" with status "completed" expiring "2027-06-30"
    And the ops insight LP "Asha Family Office" owes 5 lakh on call "Call 1" in "Growth Fund I" due "2026-08-01" with status "Overdue"
    And the ops insight LP "Asha Family Office" owes 5 lakh on call "Call 2" in "Growth Fund I" due "2026-08-15" with status "Overdue"
    And the ops insight LP "Asha Family Office" owes 5 lakh on call "Call 3" in "Growth Fund I" due "2026-09-01" with status "Overdue"
    And the ops insight LP "Asha Family Office" owes 5 lakh on call "Call 4" in "Growth Fund I" due "2026-09-15" with status "Overdue"
    And the ops insight LP "Asha Family Office" has a document "Commitment Agreement" in "Growth Fund I" with e-sign status "requested"
    When I open the Ops Dashboard for the ops insight widgets
    Then the ops insight cards should show:
      | Overdue tasks        | 3 |
      | KYCs to verify       | 2 |
      | Overdue remittances  | 4 |
      | Open e-sign requests | 1 |

  # H20 — Happy path: the same cards on the fund manager's home page
  @rack_test
  Scenario: Needs Attention on the FM Landing Page
    Given the "Needs Attention" widget on the "FM Landing Page" has settings ""
    And there are 3 ops insight open tasks due "2026-09-20" for "Meera"
    And the ops insight LP "Asha Family Office" owes 5 lakh on call "Call 1" in "Growth Fund I" due "2026-08-01" with status "Overdue"
    When I open my home page for the ops insight widgets
    Then the ops insight card "Overdue tasks" should show 3
    And the ops insight card "Overdue remittances" should show 1

  # H21 — Happy path: each card opens the list it counts, holding the same rows
  @rack_test
  Scenario Outline: Each card opens the matching list
    Given the "Needs Attention" widget on the "Ops Dashboard" has settings ""
    And there are 3 ops insight open tasks due "2026-09-20" for "Meera"
    And the ops insight LP "Asha Family Office" has a KYC "Asha Mehta" with status "completed" expiring "2027-06-30"
    And the ops insight LP "Asha Family Office" owes 5 lakh on call "Call 1" in "Growth Fund I" due "2026-08-01" with status "Overdue"
    And the ops insight LP "Asha Family Office" owes 5 lakh on call "Call 2" in "Growth Fund I" due "2026-08-15" with status "Overdue"
    And the ops insight LP "Asha Family Office" owes 5 lakh on call "Call 3" in "Growth Fund I" due "2026-09-01" with status "Overdue"
    And the ops insight LP "Asha Family Office" owes 5 lakh on call "Call 4" in "Growth Fund I" due "2026-09-15" with status "Overdue"
    And the ops insight LP "Asha Family Office" has a document "Commitment Agreement" in "Growth Fund I" with e-sign status "requested"
    When I open the Ops Dashboard for the ops insight widgets
    Then the ops insight card "<card>" should show <count>
    And the list behind the ops insight card "<card>" should hold <count> records

    Examples:
      | card                 | count |
      | Overdue tasks        | 3     |
      | KYCs to verify       | 1     |
      | Overdue remittances  | 4     |
      | Open e-sign requests | 1     |

  # H22 — Happy path: Meera 3 overdue, Ravi 1, unassigned 2 → bars Meera 3, Unassigned 2, Ravi 1
  @rack_test
  Scenario: Overdue Tasks by Assignee
    Given the "Overdue Tasks by Assignee" widget on the "Ops Dashboard" has settings ""
    And there are 3 ops insight open tasks due "2026-09-20" for "Meera"
    And there are 1 ops insight open tasks due "2026-09-25" for "Ravi"
    And there are 2 ops insight open tasks due "2026-09-10" for "nobody"
    When I open the Ops Dashboard for the ops insight widgets
    Then the ops insight widget "Overdue Tasks by Assignee" should list "Meera Ops, Unassigned, Ravi Ops"
    And the ops insight widget "Overdue Tasks by Assignee" row "Unassigned" should show "2"

  # H23 — Happy path: a capital call journey on "Approve notice" since 15 Sep 2026 has waited 15 days
  @rack_test
  Scenario: Stuck Workflows
    Given the "Stuck Workflows" widget on the "Ops Dashboard" has settings ""
    And there is an ops insight journey on the call "Call 3" in "Growth Fund I" at step "Approve notice" since "2026-09-15" with status "active"
    When I open the Ops Dashboard for the ops insight widgets
    Then the ops insight widget "Stuck Workflows" should list "Call 3"
    And the ops insight widget "Stuck Workflows" row "Call 3" should show "15"

  # H24 — Happy path: Side-letter Obligations on the Ops Dashboard names the investor
  @rack_test
  Scenario: Side-letter Obligations on the Ops Dashboard
    Given the "Side-letter Obligations" widget on the "Ops Dashboard" has settings ""
    And the ops insight LP "Asha Family Office" has a side-letter obligation "Quarterly ESG report" in "Growth Fund I" due "2026-10-15" with status "active" and review "approved"
    When I open the Ops Dashboard for the ops insight widgets
    Then the ops insight widget "Side-letter Obligations" should list "Quarterly ESG report"
    And I should see "Asha Family Office"

  # E54 — Edge case: an open task due today is not overdue
  @rack_test
  Scenario: A task due today is not overdue
    Given the "Needs Attention" widget on the "Ops Dashboard" has settings ""
    And there are 1 ops insight open tasks due "2026-09-30" for "Meera"
    When I open the Ops Dashboard for the ops insight widgets
    Then the ops insight card "Overdue tasks" should show 0

  # E55 — Edge case: KYCs not sent or with only the link sent are not waiting to be verified
  @rack_test
  Scenario: KYCs not yet submitted are not counted as to verify
    Given the "Needs Attention" widget on the "Ops Dashboard" has settings ""
    And the ops insight LP "Asha Family Office" has a KYC "Asha Mehta" with status "not_sent" expiring "2027-06-30"
    And the ops insight LP "Asha Family Office" has a KYC "Rohan Mehta" with status "link_sent" expiring "2027-06-30"
    When I open the Ops Dashboard for the ops insight widgets
    Then the ops insight card "KYCs to verify" should show 0

  # E57 — Edge case: failed and cancelled e-sign requests are not open
  @rack_test
  Scenario: Failed and cancelled e-sign requests are not open
    Given the "Needs Attention" widget on the "Ops Dashboard" has settings ""
    And the ops insight LP "Asha Family Office" has a document "Failed Agreement" in "Growth Fund I" with e-sign status "failed"
    And the ops insight LP "Asha Family Office" has a document "Cancelled Agreement" in "Growth Fund I" with e-sign status "cancelled"
    When I open the Ops Dashboard for the ops insight widgets
    Then the ops insight card "Open e-sign requests" should show 0

  # E58 — Edge case: nothing stuck shows all four cards at 0
  @rack_test
  Scenario: All zero
    Given the "Needs Attention" widget on the "Ops Dashboard" has settings ""
    When I open the Ops Dashboard for the ops insight widgets
    Then the ops insight cards should show:
      | Overdue tasks        | 0 |
      | KYCs to verify       | 0 |
      | Overdue remittances  | 0 |
      | Open e-sign requests | 0 |

  # E59 — Edge case: 12 assignees with top_n 10 give 10 bars plus "Others"
  @rack_test
  Scenario: top_n groups the rest as Others
    Given the "Overdue Tasks by Assignee" widget on the "Ops Dashboard" has settings "{top_n: 10}"
    And there are 3 ops insight open tasks due "2026-09-20" for "Meera"
    And 11 more ops insight people each have an overdue task
    When I open the Ops Dashboard for the ops insight widgets
    Then the ops insight widget "Overdue Tasks by Assignee" row "Others" should show "2"

  # E60 — Edge case: no overdue tasks
  @rack_test
  Scenario: No overdue tasks
    Given the "Overdue Tasks by Assignee" widget on the "Ops Dashboard" has settings ""
    And there are 1 ops insight open tasks due "2026-10-05" for "Meera"
    When I open the Ops Dashboard for the ops insight widgets
    Then the ops insight widget "Overdue Tasks by Assignee" should say "No overdue tasks."

  # E61 — Edge case: exactly the day limit counts (on the step since 23 Sep 2026 = 7 days, days 7)
  @rack_test
  Scenario: Exactly the day limit is stuck
    Given the "Stuck Workflows" widget on the "Ops Dashboard" has settings "{days: 7}"
    And there is an ops insight journey on the call "Call 3" in "Growth Fund I" at step "Approve notice" since "2026-09-23" with status "active"
    When I open the Ops Dashboard for the ops insight widgets
    Then the ops insight widget "Stuck Workflows" row "Call 3" should show "7"

  # E62 — Edge case: complete and archived journeys are left out, however old
  @rack_test
  Scenario: Complete and archived journeys are left out
    Given the "Stuck Workflows" widget on the "Ops Dashboard" has settings ""
    And there is an ops insight journey on the call "Call 1" in "Growth Fund I" at step "Approve notice" since "2026-08-01" with status "complete"
    And there is an ops insight journey on the call "Call 2" in "Growth Fund I" at step "Approve notice" since "2026-08-01" with status "archived"
    When I open the Ops Dashboard for the ops insight widgets
    Then the ops insight widget "Stuck Workflows" should say "No journey has waited 7 days or more on a step."

  # E63 — Edge case: six days on a step is not stuck (since 24 Sep 2026)
  @rack_test
  Scenario: Six days is not stuck
    Given the "Stuck Workflows" widget on the "Ops Dashboard" has settings ""
    And there is an ops insight journey on the call "Call 3" in "Growth Fund I" at step "Approve notice" since "2026-09-24" with status "active"
    When I open the Ops Dashboard for the ops insight widgets
    Then the ops insight widget "Stuck Workflows" should not list "Call 3"
