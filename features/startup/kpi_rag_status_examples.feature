Feature: KPI RAG status — real-world rule patterns
  Extends the single "ratio vs Budget" example in kpis.feature with the other rule shapes funds
  actually use, the live-computation behavior added in Phase 3 of the redesign, and the
  PriorPeriod comparator added afterwards (judging a KPI against its own most recent earlier
  report, already in the DB, instead of a separately tagged upload). Reference:
  docs/modules/portfolio/kpis/kpi_rag_rules_redesign.md.

  RAG status is computed automatically the moment a KPI's own value (or its comparator's value)
  is saved — there is no explicit "compute" step in any scenario below.

  Background:
    Given Im logged in as a user "first_name=Test;email=test@example.com" for an entity "name=Test Company;entity_type=Company"
    And the user has role "company_admin"
    And KPI is enabled for the user
    Given there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"

  @rag_status @rack_test
  Scenario: Gross Margin % judged as a flat threshold, no comparator KPI needed, higher is better
    Given an Investor KPI Mapping for "Gross Margin" exists with RAG comparator "none", direction "higher_is_better", red threshold 0.40, green threshold 0.55
    And a KpiReport "as_of=2024-01-01;period=YTD" exists for the entity
    And a KPI "name=Gross Margin;value=0.45" exists for the kpi report
    Then the KPI "Gross Margin" should have RAG status "amber"

  @rag_status @rack_test
  Scenario: Cash Runway (months) judged as a flat threshold, higher is better
    Given an Investor KPI Mapping for "Cash Runway" exists with RAG comparator "none", direction "higher_is_better", red threshold 6, green threshold 12
    And a KpiReport "as_of=2024-01-01;period=YTD" exists for the entity
    And a KPI "name=Cash Runway;value=8" exists for the kpi report
    Then the KPI "Cash Runway" should have RAG status "amber"

  @rag_status @rack_test
  Scenario: NPS judged as a flat industry-anchored threshold, higher is better
    Given an Investor KPI Mapping for "NPS" exists with RAG comparator "none", direction "higher_is_better", red threshold 0, green threshold 30
    And a KpiReport "as_of=2024-01-01;period=YTD" exists for the entity
    And a KPI "name=NPS;value=35" exists for the kpi report
    Then the KPI "NPS" should have RAG status "green"

  @rag_status @rack_test
  Scenario: CAC Payback (months) judged as a flat threshold, lower is better
    Given an Investor KPI Mapping for "CAC Payback" exists with RAG comparator "none", direction "lower_is_better", red threshold 18, green threshold 12
    And a KpiReport "as_of=2024-01-01;period=YTD" exists for the entity
    And a KPI "name=CAC Payback;value=20" exists for the kpi report
    Then the KPI "CAC Payback" should have RAG status "red"

  @rag_status @rack_test
  Scenario: Customer Concentration % judged as a flat threshold, lower is better
    Given an Investor KPI Mapping for "Customer Concentration" exists with RAG comparator "none", direction "lower_is_better", red threshold 0.50, green threshold 0.30
    And a KpiReport "as_of=2024-01-01;period=YTD" exists for the entity
    And a KPI "name=Customer Concentration;value=0.55" exists for the kpi report
    Then the KPI "Customer Concentration" should have RAG status "red"

  @rag_status @rack_test
  Scenario: Leverage Ratio judged against a fixed debt covenant, lower is better
    Given an Investor KPI Mapping for "Leverage Ratio" exists with RAG comparator "none", direction "lower_is_better", red threshold 4.0, green threshold 3.6
    And a KpiReport "as_of=2024-01-01;period=YTD" exists for the entity
    And a KPI "name=Leverage Ratio;value=4.2" exists for the kpi report
    Then the KPI "Leverage Ratio" should have RAG status "red"

  @rag_status @rack_test
  Scenario: Revenue Growth YoY judged against the prior year, not Budget
    Given an Investor KPI Mapping for "Revenue Growth" exists with RAG comparator "PriorYear", direction "higher_is_better", red threshold 1.10, green threshold 1.20
    And a KpiReport "as_of=2024-01-01;period=YTD;tag_list=PriorYear" exists for the entity
    And a KPI "name=Revenue Growth;value=1000" exists for the kpi report
    And a KpiReport "as_of=2024-01-01;period=YTD" exists for the entity
    And a KPI "name=Revenue Growth;value=1150" exists for the kpi report
    Then the KPI "Revenue Growth" should have RAG status "amber"

  @rag_status @rack_test
  Scenario: Net Burn overspending against Budget, lower is better
    Given an Investor KPI Mapping for "Net Burn" exists with RAG comparator "Budget", direction "lower_is_better", red threshold 1.2, green threshold 1.0
    And a KpiReport "as_of=2024-01-01;period=YTD;tag_list=Budget" exists for the entity
    And a KPI "name=Net Burn;value=100" exists for the kpi report
    And a KpiReport "as_of=2024-01-01;period=YTD" exists for the entity
    And a KPI "name=Net Burn;value=130" exists for the kpi report
    Then the KPI "Net Burn" should have RAG status "red"

  @rag_status @rack_test
  Scenario: RAG status recomputes automatically once a comparator arrives after the actual
    Given an Investor KPI Mapping for "Revenue" exists with RAG comparator "Budget", direction "higher_is_better", red threshold 0.7, green threshold 0.9
    And a KpiReport "as_of=2024-01-01;period=YTD" exists for the entity
    And a KPI "name=Revenue;value=100" exists for the kpi report
    Then the KPI "Revenue" should have no RAG status
    Given a KpiReport "as_of=2024-01-01;period=YTD;tag_list=Budget" exists for the entity
    And a KPI "name=Revenue;value=120" exists for the kpi report
    Then the KPI "Revenue" should have RAG status "amber"

  @rag_status @rack_test
  Scenario: A zero-valued comparator forces a red status regardless of thresholds
    Given an Investor KPI Mapping for "Revenue" exists with RAG comparator "Budget", direction "higher_is_better", red threshold 0.7, green threshold 0.9
    And a KpiReport "as_of=2024-01-01;period=YTD;tag_list=Budget" exists for the entity
    And a KPI "name=Revenue;value=0" exists for the kpi report
    And a KpiReport "as_of=2024-01-01;period=YTD" exists for the entity
    And a KPI "name=Revenue;value=100" exists for the kpi report
    Then the KPI "Revenue" should have RAG status "red"

  @rag_status @rack_test
  Scenario: Revenue judged against its own prior period, already in the DB, no separate tagged upload needed
    Given an Investor KPI Mapping for "Revenue" exists with RAG comparator "PriorPeriod", direction "higher_is_better", red threshold 0.95, green threshold 1.00
    And a KpiReport "as_of=2024-01-31;period=month" exists for the entity
    And a KPI "name=Revenue;value=100" exists for the kpi report
    And a KpiReport "as_of=2024-02-28;period=month" exists for the entity
    And a KPI "name=Revenue;value=90" exists for the kpi report
    Then the KPI "Revenue" should have RAG status "red"

  @rag_status @rack_test
  Scenario: Prior-period RAG status recomputes automatically once the earlier period arrives after the later one
    Given an Investor KPI Mapping for "Revenue" exists with RAG comparator "PriorPeriod", direction "higher_is_better", red threshold 0.95, green threshold 1.00
    And a KpiReport "as_of=2024-02-28;period=month" exists for the entity
    And a KPI "name=Revenue;value=90" exists for the kpi report
    Then the KPI "Revenue" should have no RAG status
    Given a KpiReport "as_of=2024-01-31;period=month" exists for the entity
    And a KPI "name=Revenue;value=100" exists for the kpi report
    Then the KPI "Revenue" should have RAG status "red"

  @rag_status @rack_test
  Scenario: A zero-valued prior period forces a red status under the PriorPeriod comparator too
    Given an Investor KPI Mapping for "Revenue" exists with RAG comparator "PriorPeriod", direction "higher_is_better", red threshold 0.95, green threshold 1.00
    And a KpiReport "as_of=2024-01-31;period=month" exists for the entity
    And a KPI "name=Revenue;value=0" exists for the kpi report
    And a KpiReport "as_of=2024-02-28;period=month" exists for the entity
    And a KPI "name=Revenue;value=100" exists for the kpi report
    Then the KPI "Revenue" should have RAG status "red"

  @rag_status @rack_test
  Scenario: An unapproved comparator is not used — approving it retroactively unlocks the RAG status
    Given an Investor KPI Mapping for "Revenue" exists with RAG comparator "Budget", direction "higher_is_better", red threshold 0.7, green threshold 0.9
    And a KpiReport "as_of=2024-01-01;period=YTD;tag_list=Budget" exists for the entity
    And a KPI "name=Revenue;value=120;status=unapproved" exists for the kpi report
    And a KpiReport "as_of=2024-01-01;period=YTD" exists for the entity
    And a KPI "name=Revenue;value=100" exists for the kpi report
    Then the KPI "Revenue" should have no RAG status
    When the KPI "Revenue" tagged "Budget" is approved
    Then the KPI "Revenue" should have RAG status "amber"

  @rag_status @rack_test
  Scenario: An unapproved KPI has no RAG status of its own, even with an approved comparator already in place
    Given an Investor KPI Mapping for "Revenue" exists with RAG comparator "Budget", direction "higher_is_better", red threshold 0.7, green threshold 0.9
    And a KpiReport "as_of=2024-01-01;period=YTD;tag_list=Budget" exists for the entity
    And a KPI "name=Revenue;value=120" exists for the kpi report
    And a KpiReport "as_of=2024-01-01;period=YTD" exists for the entity
    And a KPI "name=Revenue;value=100;status=unapproved" exists for the kpi report
    Then the KPI "Revenue" should have no RAG status
    When the KPI "Revenue" tagged "Actual" is approved
    Then the KPI "Revenue" should have RAG status "amber"

  @rag_status @rack_test
  Scenario: An unapproved prior period is not used — approving it retroactively unlocks the later period's RAG status
    Given an Investor KPI Mapping for "Revenue" exists with RAG comparator "PriorPeriod", direction "higher_is_better", red threshold 0.95, green threshold 1.00
    And a KpiReport "as_of=2024-01-31;period=month" exists for the entity
    And a KPI "name=Revenue;value=100;status=unapproved" exists for the kpi report
    And a KpiReport "as_of=2024-02-28;period=month" exists for the entity
    And a KPI "name=Revenue;value=90" exists for the kpi report
    Then the KPI "Revenue" should have no RAG status
    When the KPI "Revenue" as of "2024-01-31" is approved
    Then the KPI "Revenue" should have RAG status "red"

  @rag_status @rack_test
  Scenario: Unapproving a KPI clears its own RAG status
    Given an Investor KPI Mapping for "Revenue" exists with RAG comparator "Budget", direction "higher_is_better", red threshold 0.7, green threshold 0.9
    And a KpiReport "as_of=2024-01-01;period=YTD;tag_list=Budget" exists for the entity
    And a KPI "name=Revenue;value=120" exists for the kpi report
    And a KpiReport "as_of=2024-01-01;period=YTD" exists for the entity
    And a KPI "name=Revenue;value=100" exists for the kpi report
    Then the KPI "Revenue" should have RAG status "amber"
    When the KPI "Revenue" tagged "Actual" is unapproved
    Then the KPI "Revenue" should have no RAG status

  @rag_status @rack_test
  Scenario: Unapproving a comparator KPI reverts whatever was judged against it
    Given an Investor KPI Mapping for "Revenue" exists with RAG comparator "Budget", direction "higher_is_better", red threshold 0.7, green threshold 0.9
    And a KpiReport "as_of=2024-01-01;period=YTD;tag_list=Budget" exists for the entity
    And a KPI "name=Revenue;value=120" exists for the kpi report
    And a KpiReport "as_of=2024-01-01;period=YTD" exists for the entity
    And a KPI "name=Revenue;value=100" exists for the kpi report
    Then the KPI "Revenue" should have RAG status "amber"
    When the KPI "Revenue" tagged "Budget" is unapproved
    Then the KPI "Revenue" should have no RAG status

  @rag_status
  Scenario: Recomputing RAG status for a mapping's existing KPIs after rules are added retroactively
    Given a KpiReport "as_of=2024-01-01;period=YTD;tag_list=Budget" exists for the entity
    And a KPI "name=Revenue;value=120" exists for the kpi report
    And a KpiReport "as_of=2024-01-01;period=YTD" exists for the entity
    And a KPI "name=Revenue;value=100" exists for the kpi report
    Then the KPI "Revenue" should have no RAG status
    Given an Investor KPI Mapping for "Revenue" exists with RAG comparator "Budget", direction "higher_is_better", red threshold 0.7, green threshold 0.9
    Then the KPI "Revenue" should have no RAG status
    When I visit the Investor KPI Mapping show page for "Revenue"
    And I click "Recompute RAG Status" and confirm
    Then the KPI "Revenue" should have RAG status "amber"

  @rag_status
  Scenario: A KPI mapping with no RAG rules configured has no RAG status
    Given a KpiReport "as_of=2024-01-01;period=YTD;tag_list=Budget" exists for the entity
    And a KPI "name=Revenue;value=90" exists for the kpi report
    And a KpiReport "as_of=2024-01-01;period=YTD" exists for the entity
    And a KPI "name=Revenue;value=100" exists for the kpi report
    Then the KPI "Revenue" should have no RAG status

  @rag_status @rack_test
  Scenario: Red and green thresholds out of order for the chosen direction are rejected
    When I attempt to save an Investor KPI Mapping for "Retention" with RAG comparator "none", direction "higher_is_better", red threshold 0.9, green threshold 0.7
    Then the mapping save should fail with an error about RAG thresholds
