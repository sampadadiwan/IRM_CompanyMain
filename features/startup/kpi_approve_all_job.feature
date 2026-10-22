# Feature: KPI grid "Approve all" runs in KpiApproveAllJob instead of inside the web request

@kpi_approve_all_job @rack_test
Feature: Approve all KPIs in a background job
  As a fund manager
  I want "Approve all" to approve a portfolio company's staged KPIs in the background
  So that a company with hundreds of staged KPIs does not time the page out

  Background:
    Given there is a user "first_name=FundAdmin" for an entity "name=TestFund;entity_type=Investment Fund"
    And a portfolio company "TestCo" exists under the current entity
    And investor KPI mappings exist for "TestCo" with autofill types:
      | standard_kpi_name   | autofill     |
      | Revenue             | cumulate     |
      | Assets              | forward_fill |
      | Gross Profit Margin | compute      |
    And "TestCo" has pending quarterly KPIs:
      | name    | period  | as_of      | value     |
      | Revenue | Quarter | 2025-06-30 | 770000000 |
      | Revenue | Quarter | 2025-09-30 | 825000000 |

  # H1 — Happy path: the job approves every pending KPI and queues the cumulation job
  Scenario: H1 The approve-all job approves the pending KPIs
    When the approve-all job runs for the pending KPIs of "TestCo"
    Then "TestCo" should have no pending KPIs
    And a KpiCumulateJob should be enqueued with a scalar portfolio_company_id

  # E1 — Edge case: a double click queues the job twice; the second run finds nothing pending and does not fail
  Scenario: E1 A second run of the same job approves nothing and does not fail
    When the approve-all job runs for the pending KPIs of "TestCo"
    And the approve-all job runs again for the same KPIs
    Then "TestCo" should have no pending KPIs

  # E2 — Edge case: a KPI deleted after the click is skipped, the rest are approved
  Scenario: E2 A KPI deleted before the job runs is skipped
    Given the pending KPIs of "TestCo" are listed for approval
    And the pending "Revenue" KPI for "2025-06-30" of "TestCo" is deleted
    When the approve-all job runs for the listed KPIs
    Then "TestCo" should have no pending KPIs
    And "TestCo" should have 1 approved "Revenue" KPI

  # H2 — Happy path: the alert names the company and tells the user to refresh the grid they clicked from
  Scenario: H2 The approve-all alert names the company and asks for a refresh
    When the approve-all job runs for the pending KPIs of "TestCo"
    Then the approve-all alert should read "Approved 2 KPIs for TestCo. Cumulative values are being computed. Refresh the page to see them."

  # E5 — Edge case: a second run finds everything approved and says so, instead of "Approved 0 KPIs"
  Scenario: E5 A run with nothing left to approve says so
    When the approve-all job runs for the pending KPIs of "TestCo"
    And the approve-all job runs again for the same KPIs
    Then the approve-all alert should read "Nothing left to approve for TestCo. These KPIs were already approved."

  # E6 — Edge case: "Approve all" with nothing pending answers at once and queues no job
  Scenario: E6 Approve all with nothing pending queues no job
    Given the approve-all job runs for the pending KPIs of "TestCo"
    When the user asks to approve all KPIs of "TestCo"
    Then the approve-all notice should read "There are no pending KPIs to approve."
    And no approve-all job should be queued
