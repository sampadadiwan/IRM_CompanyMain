@rack_test
Feature: A recovered environment's search is rebuilt and proven full
  Search boxes query Elasticsearch, which holds a derived copy of selected tables and is not
  backed up: after a DR its indexes are empty. The DR therefore rebuilds every index the live app
  maintains, before traffic is switched on, and fails if any import reports errors or any index's
  count differs from its MySQL scope. dr:verify then checks every index holds its records.

  These scenarios exercise Dr::SearchIndexes, the logic the reindex task and dr:verify call. The
  reindex against a real Elasticsearch is proven by the staging DR drill (see the qa-checklist of
  openspec/changes/fix-dr-search-index-after-restore).

  # H1 — Happy path: every index class in the repo except the ones live does not maintain
  Scenario: A DR rebuilds 29 indexes and skips AccountEntryIndex
    When the search indexes a DR owns are discovered
    Then 29 search indexes are owned by the DR
    And the owned search indexes include "FolderIndex", "DocumentIndex" and "FaqEntryIndex"
    And "AccountEntryIndex" is not owned by the DR

  # H2 — Happy path
  Scenario: A clean reindex with matching counts passes
    When an index is graded after reindex with import "clean", Elasticsearch 52026 and MySQL 52026
    Then the search grade is "ok"

  # H3 — Happy path
  Scenario: Verification passes when the index holds every record
    When an index is graded in verification with Elasticsearch 10000 and MySQL 10000
    Then the search grade is "ok"

  # E1 — Edge case: an empty table is an empty index, not a failure
  Scenario: An empty table with an empty index passes
    When an index is graded after reindex with import "clean", Elasticsearch 0 and MySQL 0
    Then the search grade is "ok"

  # E2 — Edge case: traffic is back on during verification, so a few records may be in flight
  Scenario: Small drift during verification passes
    When an index is graded in verification with Elasticsearch 9995 and MySQL 10000
    Then the search grade is "ok"

  # E3 — Edge case: a new index file is owned without anyone editing a list
  Scenario: A newly added index file is discovered automatically
    Given a new search index file "dr_probe_widget_index.rb" defining "DrProbeWidgetIndex"
    When the search indexes are discovered from that tree
    Then the discovered search indexes include "DrProbeWidgetIndex"

  # E4 — Edge case: a scoped index is counted against its scope, not the whole table
  Scenario: FaqEntryIndex is counted against published entries only
    When the MySQL scope of "FaqEntryIndex" is read
    Then that scope's SQL includes "status"

  # E5 — Edge case: every exclusion is a real index with a stated reason
  Scenario: Every excluded index exists and says why it is excluded
    Then every excluded search index is a real index class with a reason

  # E6 — Edge case: on a live environment an index live never updates drifts - warn, don't block
  Scenario: Drift in an index the live app does not maintain is a warning in verification
    When an unmaintained index is graded in verification with Elasticsearch 2000 and MySQL 2270
    Then the search grade is "warn" mentioning "live does not keep"

  # E7 — Edge case: the reindex itself holds every index to an exact match, maintained or not
  Scenario: An unmaintained index must still match exactly right after the reindex
    When an unmaintained index is graded after reindex with Elasticsearch 2269 and MySQL 2270
    Then the search grade is "fail" mentioning "1 missing"

  # X1 — Error case: Chewy's import returns false instead of raising
  Scenario: An import that reports errors fails the reindex
    When an index is graded after reindex with import "errors", Elasticsearch 52026 and MySQL 52026
    Then the search grade is "fail" mentioning "import reported errors"

  # X2 — Error case: traffic is off during the reindex, so counts must match exactly
  Scenario: A missing document after reindex fails it
    When an index is graded after reindex with import "clean", Elasticsearch 52025 and MySQL 52026
    Then the search grade is "fail" mentioning "1 missing"

  # X3 — Error case: the bug - an empty index used to pass as a reachable one
  Scenario: An empty index fails verification
    When an index is graded in verification with Elasticsearch 0 and MySQL 52026
    Then the search grade is "fail" mentioning "search index empty"

  # X4 — Error case
  Scenario: Large drift fails verification
    When an index is graded in verification with Elasticsearch 9000 and MySQL 10000
    Then the search grade is "fail" mentioning "1000 missing"

  # X5 — Error case: the commands the DR tools print must exist
  Scenario: The reindex command printed after a database repair is real
    When I read the database repair task's follow-up instructions
    Then they do not mention "deploy:chewy_reset"
    And they tell the operator to run "recovery:reindex_search"
    And the Capistrano recovery tasks define "reindex_search"

  # E8 — Edge case (decision 2026-11-08): an incomplete index warns, it never fails the recovery
  Scenario: One incomplete index makes the search verdict a warning, not a failure
    When the run's search verdict is taken over 28 complete indexes and "AmlReportIndex: NoMethodError: undefined method 'name'"
    Then the search grade is "warn" mentioning "1 of 29 incomplete"
    And the search grade is "warn" mentioning "ONLY=<Index>"

  # H4 — Happy path
  Scenario: All indexes complete gives an ok verdict
    When the run's search verdict is taken over 29 complete indexes
    Then the search grade is "ok" mentioning "29/29"

  # H5 — Happy path: the index the first batch drill tripped on now builds
  Scenario: AmlReportIndex takes its name from custom_name
    When the "name" field of "AmlReportIndex" is read for an AML report with custom name "Asha Rao"
    Then the indexed value is "Asha Rao"
