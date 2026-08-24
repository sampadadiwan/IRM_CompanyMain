Feature: FundAssistant and SpecificFundAssistant report/tool coverage gaps
  As a fund manager relying on scheduled AI reports
  I want default report queries to actually be sent and documented tool filters to work
  So that scheduled reports aren't silently empty and valid requests aren't wrongly rejected

  Background:
    Given there is a user "first_name=FM-Analyst" for an entity "entity_type=Investment Fund;name=Acme FM;currency=INR"
    And the user has the company_admin role

  # Regression test for: FundAssistant had no default_report_queries override, silently
  # inheriting BaseAssistant's empty [] -- a scheduled report for it would send zero prompts.
  Scenario: FundAssistant has a non-empty scheduled report query list
    When I ask FundAssistant for its default report queries
    Then it should return more than one query

  # Regression test for: SpecificFundAssistant defined OPERATIONAL_QUERIES but
  # default_report_queries only ever returned STRATEGIC_QUERIES, so the operational half of
  # the monthly report was dead code, never actually sent.
  Scenario: SpecificFundAssistant's scheduled report includes both strategic and operational queries
    Given there is a fund for the entity
    When I ask SpecificFundAssistant for its default report queries
    Then the queries should include one from STRATEGIC_QUERIES
    And the queries should include one from OPERATIONAL_QUERIES

  # Regression test for: the "at least one filter" guard didn't check `query`, so a request
  # scoped only via a Ransack query (no fund_ids/folio_ids/scope) was wrongly rejected even
  # though it supplied a real filter.
  Scenario: ListCapitalDistributionPayments accepts a query-only filter without being rejected
    When I call the list_capital_distribution_payments tool with only a query filter
    Then the tool should return a plain list, not an "at least one filter" error
