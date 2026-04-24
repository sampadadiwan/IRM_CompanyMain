Feature: ReportBuilderQueryEngine — two-pass query orchestration

  Background:
    Given a report builder entity and user
    And that entity has an investor "Sharma Capital"

  Scenario: Engine returns empty array when config is invalid
    Given a report builder config with root model "NonExistentModel"
    And a report builder entity and user
    When I run the report engine
    Then the engine should return 0 rows

  Scenario: Engine returns root-only rows with a single column
    Given a report on "Investor" selecting column "investor_name"
    When I run the report engine
    Then the engine should return 1 row
    And every row should have a key "investor_name"
    And the first row's "investor_name" should equal "Sharma Capital"

  Scenario: Engine returns zero rows when entity scoping excludes all records
    Given a report builder entity and user
    And a report on "Investor" selecting column "investor_name"
    When I run the report engine
    Then the engine should return 0 rows

  Scenario: Engine includes aggregated child data for joined relations
    Given a report on "Investor" selecting column "investor_name"
    And that investor has 2 capital commitments of 1000000 paise each
    And the report joins "capital_commitments" with "count" aggregate on "id"
    When I run the report engine
    Then the engine should return 1 row
    And every row should have a key "capital_commitments.id"

  Scenario: Engine zero-fills root rows that have no matching children
    Given another investor "No Deal Investor" with no commitments
    And a report on "Investor" selecting column "investor_name"
    And that investor has 1 capital commitments of 1000000 paise each
    And the report joins "capital_commitments" with "count" aggregate on "id"
    When I run the report engine
    Then the engine should return 2 rows
    And every row should have a key "capital_commitments.id"

  Scenario: Root filter narrows the result set
    Given another investor "Filtered Out" with no commitments
    And a report on "Investor" selecting column "investor_name"
    And the report has root filter "investor_name_eq" = "Sharma Capital"
    When I run the report engine
    Then the engine should return 1 row
    And the first row's "investor_name" should equal "Sharma Capital"

  Scenario: Sort ascending orders rows correctly
    Given another investor "Alpha Investor" with no commitments
    And a report on "Investor" selecting column "investor_name"
    And the report is sorted by "investor_name" "asc"
    When I run the report engine
    Then the engine should return 2 rows
    And the rows should be ordered by "investor_name" ascending

  Scenario: Sort descending orders rows correctly
    Given another investor "Zeta Investor" with no commitments
    And a report on "Investor" selecting column "investor_name"
    And the report is sorted by "investor_name" "desc"
    When I run the report engine
    Then the engine should return 2 rows
    And the rows should be ordered by "investor_name" descending

  Scenario: Limit restricts the number of rows for preview
    Given another investor "Second Investor" with no commitments
    And a report on "Investor" selecting column "investor_name"
    When I run the report engine with a limit of 1
    Then the engine should return 1 row

  Scenario: count returns total matching rows regardless of limit
    Given another investor "Second Investor" with no commitments
    And a report on "Investor" selecting column "investor_name"
    When I count rows via the report engine
    Then the engine row count should be 2

  Scenario: columns includes GVP columns plus formula column keys
    Given a report on "Investor" selecting column "investor_name"
    When I run the report engine
    Then the engine columns should include a column with key "investor_name"
