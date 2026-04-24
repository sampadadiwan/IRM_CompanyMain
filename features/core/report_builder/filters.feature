Feature: Report Builder filters — root and child scope filtering

  Background:
    Given a report builder entity and user
    And that entity has an investor "Filter Test Investor"

  Scenario: Root filter excludes non-matching investors from the engine result
    Given another investor "Should Be Excluded" with no commitments
    And a report on "Investor" selecting column "investor_name"
    And the report has root filter "investor_name_eq" = "Filter Test Investor"
    When I run the report engine
    Then the engine should return 1 row
    And the first row's "investor_name" should equal "Filter Test Investor"

  Scenario: Root filter with _cont (contains) matches partial names
    Given another investor "Alpha Fund" with no commitments
    And a report on "Investor" selecting column "investor_name"
    And the report has root filter "investor_name_cont" = "Filter Test"
    When I run the report engine
    Then the engine should return 1 row
    And the first row's "investor_name" should equal "Filter Test Investor"

  Scenario: Root filter matching no records returns an empty result
    Given a report on "Investor" selecting column "investor_name"
    And the report has root filter "investor_name_eq" = "Ghost Investor That Does Not Exist"
    When I run the report engine
    Then the engine should return 0 rows

  Scenario: Child filter applied before aggregation excludes non-matching children
    Given that investor has 2 capital commitments of 1000000 paise each
    When I aggregate capital commitments with child filter "fund_close" = "Second Close" using "count"
    Then the investor with no commitments should not appear in the aggregation result

  Scenario: Child filter does not eliminate the root row — it just reduces the aggregate
    Given that investor has 2 capital commitments of 1000000 paise each
    And a report on "Investor" selecting column "investor_name"
    And the report joins "capital_commitments" with "count" aggregate on "id"
    And the report has root filter "investor_name_eq" = "Filter Test Investor"
    When I run the report engine
    Then the engine should return 1 row

  Scenario: count respects root filters
    Given another investor "Extra Investor" with no commitments
    And a report on "Investor" selecting column "investor_name"
    And the report has root filter "investor_name_eq" = "Filter Test Investor"
    When I count rows via the report engine
    Then the engine row count should be 1
