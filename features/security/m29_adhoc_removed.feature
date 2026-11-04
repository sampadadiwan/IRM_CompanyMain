Feature: M29 - the AiPolars / account_entries#adhoc endpoint is removed
  AccountEntriesController#adhoc sent params[:query] to an LLM and eval'd the Polars code it returned
  (AiPolars). It had no view and no links, so it is deleted rather than hardened: the action, its policy
  predicate, both routes and the service are gone.
  Worked examples: docs/security/security_review_2026_10.md "Funds / KPI / portfolio — Medium and Low", M29

  # M29-1 — Error case: there is no adhoc route, action, policy predicate or AiPolars service left to reach
  @security @rack_test
  Scenario: M29-1 The adhoc account entries endpoint no longer exists
    Then the account entries adhoc endpoint no longer exists
