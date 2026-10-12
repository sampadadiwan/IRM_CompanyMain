@import @allocation_run_templates
Feature: Allocation Run Templates and Groups
  An AllocationRunTemplate stores one fund plus the parameters it is always run with
  (everything on the allocation screen except the period). An AllocationRunTemplateGroup
  is an ordered list of templates run one after another for one period. Every group run is
  checked up front, stops at the first failure, and is recorded per template.

  Background:
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund;currency=INR"
    Given the user has role "company_admin"
    Given there is a fund "name=Master Fund;currency=INR;unit_types=A1" for the entity
    Given there is a second fund "name=Feeder Fund;currency=INR" for the entity

  # ── Templates ────────────────────────────────────────────────────────────────

  Scenario: Saving a template from a past allocation run copies the fund and every option but not the period
    Given there is a past allocation run "start_date=2024-01-01;end_date=2024-03-31;rule_for=Accounting;tag_list=quarterly;fund_ratios=true" on the first fund
    When I save that allocation run as an allocation run template named "Master — quarterly"
    Then an allocation run template "Master — quarterly" should exist for the first fund
    And the template "Master — quarterly" should carry "rule_for=Accounting;tag_list=quarterly;run_allocations=true;fund_ratios=true;generate_soa=false"

  Scenario: A template that neither runs formulas nor generates statements is refused
    When I try to create an allocation run template "name=Does nothing;run_allocations=false;generate_soa=false" on the first fund
    Then the template should not be saved with an error containing "Select at least one"

  Scenario: Template names are unique within an entity
    Given there is an allocation run template "name=Dup" on the first fund
    When I try to create an allocation run template "name=Dup" on the second fund
    Then the template should not be saved with an error containing "Name has already been taken"

  Scenario: A template inside a group cannot be deleted until it is removed from the group
    Given there is an allocation run template "name=In group" on the first fund
    And there is an allocation run group "Quarterly close" with templates "In group"
    When I try to delete the allocation run template "In group"
    Then the template "In group" should still exist
    When I remove every template from the group "Quarterly close" by deleting the group
    Then I can delete the allocation run template "In group"

  # ── Groups ───────────────────────────────────────────────────────────────────

  Scenario: A group keeps its templates in position order
    Given there is an allocation run template "name=Master — quarterly" on the first fund
    And there is an allocation run template "name=Feeder — quarterly" on the second fund
    And there is an allocation run group "Quarterly close" with templates "Master — quarterly,Feeder — quarterly"
    Then the group "Quarterly close" should run "Master — quarterly" before "Feeder — quarterly"

  Scenario: A group without templates is refused
    When I try to create an allocation run group "Empty" with no templates
    Then the group should not be saved with an error containing "at least one"

  Scenario: Deleting a group keeps its run history
    Given there is an allocation run template "name=Master — quarterly" on the first fund
    And there is an allocation run group "Quarterly close" with templates "Master — quarterly"
    And the group "Quarterly close" has a finished run for "2024-01-01" to "2024-03-31"
    When I delete the group "Quarterly close"
    Then a group run named "Quarterly close" should still exist without a group

  # ── Pre-flight checks ────────────────────────────────────────────────────────

  Scenario: Every template passes the pre-flight for a clean period
    Given there is an allocation run template "name=Master — quarterly" on the first fund
    And there is an allocation run template "name=Feeder — quarterly" on the second fund
    And there is an allocation run group "Quarterly close" with templates "Master — quarterly,Feeder — quarterly"
    When I run the pre-flight check for "Quarterly close" from "2024-01-01" to "2024-03-31"
    Then the pre-flight should be startable
    And the pre-flight check for "Master — quarterly" should be "ready"
    And the pre-flight check for "Feeder — quarterly" should be "ready"

  Scenario: A locked period on one fund blocks the whole group and nothing runs
    Given there is an allocation run template "name=Master — quarterly" on the first fund
    And there is an allocation run template "name=Feeder — quarterly" on the second fund
    And there is an allocation run group "Quarterly close" with templates "Master — quarterly,Feeder — quarterly"
    And there is a locked allocation run from "2024-01-01" to "2024-03-31" on the second fund
    When I run the pre-flight check for "Quarterly close" from "2024-01-01" to "2024-03-31"
    Then the pre-flight should not be startable
    And the pre-flight check for "Master — quarterly" should be "ready"
    And the pre-flight check for "Feeder — quarterly" should be "blocked" with a message containing "locked allocation run"
    When I try to start the group "Quarterly close" from "2024-01-01" to "2024-03-31"
    Then no group run should have been recorded

  Scenario: A formula tag that no longer exists in entity settings blocks the template
    Given the entity formula tag list is "quarterly,annual"
    And there is an allocation run template "name=Old tags;tag_list=quarterly,retired" on the first fund
    And there is an allocation run group "Quarterly close" with templates "Old tags"
    When I run the pre-flight check for "Quarterly close" from "2024-01-01" to "2024-03-31"
    Then the pre-flight check for "Old tags" should be "blocked" with a message containing "retired"

  Scenario: A missing statement document blocks a template that generates statements
    Given there is an allocation run template "name=Statements;generate_soa=true;statement_for=Commitment" on the first fund with a statement document
    And there is an allocation run group "Quarterly close" with templates "Statements"
    And the statement document of the template "Statements" is deleted
    When I run the pre-flight check for "Quarterly close" from "2024-01-01" to "2024-03-31"
    Then the pre-flight check for "Statements" should be "blocked" with a message containing "statement document"

  Scenario: A gap after the last locked run is a warning, not a blocker
    Given there is an allocation run template "name=Master — quarterly" on the first fund
    And there is an allocation run group "Quarterly close" with templates "Master — quarterly"
    And there is a locked allocation run from "2023-10-01" to "2023-12-31" on the first fund
    When I run the pre-flight check for "Quarterly close" from "2024-02-01" to "2024-03-31"
    Then the pre-flight should be startable
    And the pre-flight check for "Master — quarterly" should be "warning" with a message containing "gap"

  Scenario: An employee without rights on one fund cannot run the group
    Given there is an allocation run template "name=Master — quarterly" on the first fund
    And there is an allocation run template "name=Feeder — quarterly" on the second fund
    And there is an allocation run group "Quarterly close" with templates "Master — quarterly,Feeder — quarterly"
    And there is an employee with allocation rights on the first fund only
    When that employee runs the pre-flight check for "Quarterly close" from "2024-01-01" to "2024-03-31"
    Then the pre-flight check for "Feeder — quarterly" should be "blocked" with a message containing "right to run allocations"

  Scenario: Only one group can run at a time for an entity
    Given there is an allocation run template "name=Master — quarterly" on the first fund
    And there is an allocation run group "Quarterly close" with templates "Master — quarterly"
    And the group "Quarterly close" has a running run for "2024-01-01" to "2024-03-31"
    When I run the pre-flight check for "Quarterly close" from "2024-04-01" to "2024-06-30"
    Then the pre-flight should not be startable with a group blocker containing "already running"

  Scenario: A manual allocation on a fund a running group has yet to reach is refused
    Given there is an allocation run template "name=Master — quarterly" on the first fund
    And there is an allocation run group "Quarterly close" with templates "Master — quarterly"
    And the group "Quarterly close" has a running run for "2024-01-01" to "2024-03-31"
    Then the first fund should be busy for a manual allocation
    And the second fund should not be busy for a manual allocation

  # ── Running a group ──────────────────────────────────────────────────────────

  Scenario: Templates run in order and every one succeeds
    Given there is an allocation run template "name=Master — quarterly" on the first fund
    And there is an allocation run template "name=Feeder — quarterly" on the second fund
    And there is an allocation run group "Quarterly close" with templates "Master — quarterly,Feeder — quarterly"
    And the allocation engine will succeed for every template
    When I start the group "Quarterly close" from "2024-01-01" to "2024-03-31"
    Then the group run should finish with status "success"
    And the group run items should be "Master — quarterly=success,Feeder — quarterly=success"
    And each group run item should link to a new allocation run for "2024-01-01" to "2024-03-31"
    And the engine should have run "Master — quarterly" before "Feeder — quarterly"
    And the user should have received an allocation group run email containing "finished successfully"

  Scenario: The group stops at the first failure and skips the rest
    Given there is an allocation run template "name=Master — quarterly" on the first fund
    And there is an allocation run template "name=Feeder — quarterly" on the second fund
    And there is an allocation run template "name=Feeder B — quarterly" on the second fund
    And there is an allocation run group "Quarterly close" with templates "Master — quarterly,Feeder — quarterly,Feeder B — quarterly"
    And the allocation engine will fail for "Feeder — quarterly" with "Formula X blew up"
    When I start the group "Quarterly close" from "2024-01-01" to "2024-03-31"
    Then the group run should finish with status "failed"
    And the group run items should be "Master — quarterly=success,Feeder — quarterly=failed,Feeder B — quarterly=skipped"
    And the group run message should contain "Formula X blew up"
    And the user should have received an allocation group run email containing "stopped after a failure"

  Scenario: A run left at Pending counts as a failure
    Given there is an allocation run template "name=Master — quarterly" on the first fund
    And there is an allocation run group "Quarterly close" with templates "Master — quarterly"
    And the allocation engine will leave "Master — quarterly" at status "Pending"
    When I start the group "Quarterly close" from "2024-01-01" to "2024-03-31"
    Then the group run should finish with status "failed"
    And the group run items should be "Master — quarterly=failed"

  Scenario: Resuming after a fix reuses the templates that already succeeded
    Given there is an allocation run template "name=Master — quarterly" on the first fund
    And there is an allocation run template "name=Feeder — quarterly" on the second fund
    And there is an allocation run group "Quarterly close" with templates "Master — quarterly,Feeder — quarterly"
    And the allocation engine will fail for "Feeder — quarterly" with "Formula X blew up"
    When I start the group "Quarterly close" from "2024-01-01" to "2024-03-31"
    Then the group run should finish with status "failed"
    Given the allocation engine will succeed for every template
    When I run the pre-flight check for "Quarterly close" from "2024-01-01" to "2024-03-31"
    Then the pre-flight check for "Master — quarterly" should be "reused"
    And the pre-flight check for "Feeder — quarterly" should be "ready"
    When I start the group "Quarterly close" from "2024-01-01" to "2024-03-31"
    Then the group run should finish with status "success"
    And the group run items should be "Master — quarterly=reused,Feeder — quarterly=success"
    And the engine should have run only "Feeder — quarterly" in the latest run
    And the latest group run should be resumed from the previous one

  Scenario: Running without resume re-runs every template
    Given there is an allocation run template "name=Master — quarterly" on the first fund
    And there is an allocation run template "name=Feeder — quarterly" on the second fund
    And there is an allocation run group "Quarterly close" with templates "Master — quarterly,Feeder — quarterly"
    And the allocation engine will fail for "Feeder — quarterly" with "Formula X blew up"
    When I start the group "Quarterly close" from "2024-01-01" to "2024-03-31"
    Given the allocation engine will succeed for every template
    When I start the group "Quarterly close" from "2024-01-01" to "2024-03-31" without resume
    Then the group run items should be "Master — quarterly=success,Feeder — quarterly=success"
    And the engine should have run "Master — quarterly" before "Feeder — quarterly"

  Scenario: A restarted worker continues from the template that was running
    Given there is an allocation run template "name=Master — quarterly" on the first fund
    And there is an allocation run template "name=Feeder — quarterly" on the second fund
    And there is an allocation run group "Quarterly close" with templates "Master — quarterly,Feeder — quarterly"
    And the group "Quarterly close" has a running run for "2024-01-01" to "2024-03-31" with "Master — quarterly" already successful
    And the allocation engine will succeed for every template
    When the group run job is performed again for that run
    Then the group run should finish with status "success"
    And the engine should have run only "Feeder — quarterly" in the latest run

  # ── UI ───────────────────────────────────────────────────────────────────────

  @javascript
  Scenario: The templates page lists groups in run order and the run modal leads to the pre-flight page
    Given I am signed in as the current user
    And there is an allocation run template "name=Master — quarterly" on the first fund
    And there is an allocation run template "name=Feeder — quarterly" on the second fund
    And there is an allocation run group "Quarterly close" with templates "Master — quarterly,Feeder — quarterly"
    And the allocation engine will succeed for every template
    When I visit the allocation run templates page
    Then I should see the group "Quarterly close" listing "Master — quarterly" before "Feeder — quarterly"
    When I open the run modal for the group "Quarterly close" and check the period "2024-01-01" to "2024-03-31"
    Then I should be on the pre-flight page showing "Every template passed"
    When I confirm the pre-flight with "Start run"
    Then I should see the group run progress page with status "Success"

  @javascript
  Scenario: Save as template from the allocation screen asks only for a name
    Given I am signed in as the current user
    And there is a past allocation run "start_date=2024-01-01;end_date=2024-03-31;rule_for=Reporting" on the first fund
    When I visit the allocation screen of the first fund
    And I save the first past run as a template named "Master — from screen"
    Then an allocation run template "Master — from screen" should exist for the first fund
    And the template "Master — from screen" should carry "rule_for=Reporting;run_allocations=true"
