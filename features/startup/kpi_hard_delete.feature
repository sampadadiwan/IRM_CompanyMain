Feature: KPI hard delete without audits
  KPIs and KPI reports are deleted for good and leave no audit trail, so a KPI mapping can be
  deleted once nothing references it any more.

  Background:
    Given Im logged in as a user "first_name=Test;email=test@example.com" for an entity "name=Test Company;entity_type=Company"
    And the user has role "company_admin"
    And KPI is enabled for the user
    Given there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
    And a KpiReport "as_of=2026-03-31;period=Quarter" exists for the entity

  Scenario: H1 - Delete a KPI, then its mapping
    Given a KPI "name=Revenue;value=100" exists for the kpi report
    When the KPI is deleted
    Then the KPI should no longer exist in the database
    When the KPI mapping "Revenue" is deleted
    Then the KPI mapping "Revenue" should no longer exist

  Scenario: H2 - Deleting a report removes its KPIs for good
    Given a KPI "name=Revenue;value=100" exists for the kpi report
    And a KPI "name=Costs;value=40" exists for the kpi report
    When the KPI report is deleted
    Then the KPI report and its "2" KPIs should no longer exist in the database

  Scenario: H3 - No audits are written for KPIs and reports
    Given a KPI "name=Revenue;value=100" exists for the kpi report
    When the KPI value is changed to "250"
    Then there should be no audit entries for KPIs or KPI reports

  Scenario: E1 - A deleted report's period can be uploaded again
    Given a KPI "name=Revenue;value=100" exists for the kpi report
    When the KPI report is deleted
    Then a KpiReport "as_of=2026-03-31;period=Quarter" exists for the entity

  Scenario: E3 - Deleting a report writes no audit entries
    Given a KPI "name=Revenue;value=100" exists for the kpi report
    When the KPI report is deleted
    Then there should be no audit entries for KPIs or KPI reports

  Scenario: X1 - A mapping still used by a live KPI is not deleted
    Given a KPI "name=Revenue;value=100" exists for the kpi report
    When the KPI mapping "Revenue" is deleted
    Then the KPI mapping "Revenue" should still exist

  Scenario: E2 - The release purge removes soft-deleted rows and unblocks their mapping
    Given a KPI "name=Revenue;value=100" exists for the kpi report
    And the kpis and kpi_reports tables still have the legacy deleted_at column
    And a KpiReport "as_of=2026-06-30;period=Quarter" exists for the entity
    And a KPI "name=Legacy;value=5" exists for the kpi report
    And that KPI and its report were soft-deleted before this release
    When the purge migration runs
    Then the legacy KPI and report should no longer exist in the database
    And the live KPI "Revenue" should still exist
    When the KPI mapping "Legacy" is deleted
    Then the KPI mapping "Legacy" should no longer exist

  Scenario: E4 - After the migration there is no deleted_at and name uniqueness still holds
    Given a KPI "name=Revenue;value=100" exists for the kpi report
    And the kpis and kpi_reports tables still have the legacy deleted_at column
    When the purge migration runs
    Then the kpis and kpi_reports tables should have no deleted_at column
    And a duplicate approved KPI "Revenue" in the same report should be rejected
