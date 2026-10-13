@allocation_run_checker @incremental_allocation_ui
Feature: Incremental allocation from the fund formulas page
  Support moves a fund onto incremental since-inception allocation (and back), and recomputes tracking
  formulas' stored starting values, from Actions > Incremental allocation. Every change is previewed in
  the background, applied only from that preview, refused if the fund changed since or is busy, and kept
  as a FundFormulaOperation. The rake tasks print the same plans.
  See openspec/changes/incremental-allocation-ui.

  Background:
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund;currency=INR"
    And the user has role "company_admin"
    And there is a fund "name=Incremental Fund;currency=INR;unit_types=A1" for the entity
    And the fund has folios "101,102"

  # ── Access ───────────────────────────────────────────────────────────────────

  @rack_test
  Scenario: Support sees the new actions in the Actions menu
    Given the user has role "support"
    When the user opens the fund formulas page
    Then the Actions menu should list "Enable All"
    And the Actions menu should list "Incremental allocation"
    And the Actions menu should list "Suggest run checks"

  @rack_test
  Scenario: Other users see only the existing actions
    When the user opens the fund formulas page
    Then the Actions menu should list "Enable All"
    And the Actions menu should not list "Incremental allocation"
    And the Actions menu should not list "Suggest run checks"

  @rack_test
  Scenario: A non-support user cannot start a preview directly
    When the user posts a preview of "enable_incremental"
    Then the request should be refused as unauthorized
    And no fund formula operation should exist for the fund

  @rack_test
  Scenario: A non-support user cannot open or act on an operation directly
    Given a suggestion set exists for the fund
    When the user requests every operation page and action directly
    Then every request should be refused as unauthorized
    And the fund should have no check formulas

  @rack_test
  Scenario: Enable All still enables every formula from the Actions menu
    Given the fund has a disabled formula "Quarterly Fees"
    When the user chooses Enable All from the Actions menu
    Then formula "Quarterly Fees" should be enabled

  @rack_test
  Scenario: Support opens the incremental allocation page
    Given the user has role "support"
    When the user requests the incremental allocation page
    Then the incremental allocation page should show the recommended steps

  @rack_test
  Scenario: Steps the fund's data shows done are marked, and the switch is next
    Given the user has role "support"
    And the fund has a post-run check that Since Inception totals match history
    And there is a finished allocation run "start_date=2024-01-01;end_date=2024-03-31"
    When the user requests the incremental allocation page
    Then the recommended steps "checks" and "baseline" should be done
    And the next recommended step should be "switch"
    And the incremental allocation page should mark 2 steps done

  @rack_test
  Scenario: A fund switched on with the rake task still shows when it was switched
    Given the user has role "support"
    And the fund has a formula "Since Inception Apportioned" adding up the since-inception totals of "Apportioned Fees, Apportioned Others"
    And the fund was switched on with the rake task
    When the user requests the incremental allocation page
    Then the recommended steps should show when the fund was switched on

  @rack_test
  Scenario: A fund already on incremental allocation is offered switching off and recomputing
    Given the user has role "support"
    And the fund has a formula "Since Inception Apportioned" adding up the since-inception totals of "Apportioned Fees, Apportioned Others"
    When support previews "enable_incremental"
    And support applies the preview
    And the user requests the incremental allocation page
    Then the incremental allocation page should say "On incremental allocation"
    And the incremental allocation page should offer "Preview switching off"
    And the incremental allocation page should offer "Preview recomputing starting values"
    And the incremental allocation page should not offer "Preview switching to incremental"

  # ── Switching on ─────────────────────────────────────────────────────────────

  @rack_test
  Scenario: Preview leaves the fund unchanged, and apply switches it on
    Given the user has role "support"
    And the fund has a formula "Since Inception Apportioned" adding up the since-inception totals of "Apportioned Fees, Apportioned Others"
    When support previews "enable_incremental"
    Then the operation should be "previewed"
    And the preview should edit formula "Since Inception Apportioned"
    And formula "Since Inception Apportioned" should be unchanged since the preview
    And the fund should not be on incremental allocation
    When support applies the preview
    Then the operation should be "applied"
    And the fund should be on incremental allocation
    And formula "Since Inception Apportioned" should carry forward its own total with a description

  @rack_test
  Scenario: A blocked fund cannot be applied
    Given the user has role "support"
    And the fund has a formula "Open History" summing "Audit Fees" from inception
    When support previews "enable_incremental"
    Then the operation should be "blocked"
    And the preview should list a blocker mentioning "reads a date range with no start"
    When support applies the preview
    Then the operation should be refused with "cannot be applied"
    And the fund should not be on incremental allocation

  @rack_test
  Scenario: A preview is refused when the fund changed after it was made
    Given the user has role "support"
    And the fund has a formula "Since Inception Apportioned" adding up the since-inception totals of "Apportioned Fees, Apportioned Others"
    When support previews "enable_incremental"
    And formula "Since Inception Apportioned" is edited after the preview
    And support applies the preview
    Then the operation should be "refused"
    And the operation should be refused with "changed since this preview"
    And the fund should not be on incremental allocation

  @rack_test
  Scenario: Apply is refused while an allocation run is in progress
    Given the user has role "support"
    And the fund has a formula "Since Inception Apportioned" adding up the since-inception totals of "Apportioned Fees, Apportioned Others"
    When support previews "enable_incremental"
    And an allocation run for the fund is still in progress
    And support applies the preview
    Then the operation should be refused with "has not finished yet"
    And the operation should be "previewed"
    And the fund should not be on incremental allocation

  @rack_test
  Scenario: An apply that fails part-way writes nothing
    Given the user has role "support"
    And the fund has a formula "Since Inception Apportioned" adding up the since-inception totals of "Apportioned Fees, Apportioned Others"
    And writing the incremental flag will fail with "disk full"
    When support previews "enable_incremental"
    And support applies the preview
    Then the operation should be "failed"
    And the operation should record the error "disk full"
    And formula "Since Inception Apportioned" should be unchanged since the preview
    And the fund should not be on incremental allocation

  @rack_test
  Scenario: Apply is refused while the preview is already being applied
    Given the user has role "support"
    And the fund has a formula "Since Inception Apportioned" adding up the since-inception totals of "Apportioned Fees, Apportioned Others"
    When support previews "enable_incremental"
    And the preview is being applied
    And support applies the preview
    Then the operation should be refused with "cannot be applied"
    And the operation should be "applying"

  @rack_test
  Scenario: A second apply job cannot overwrite an applied operation
    Given the user has role "support"
    And the fund has a formula "Since Inception Apportioned" adding up the since-inception totals of "Apportioned Fees, Apportioned Others"
    When support previews "enable_incremental"
    And support applies the preview
    And the apply job runs again for the operation
    Then the operation should be "applied"
    And the fund should be on incremental allocation

  Scenario: Only one preview runs per fund at a time
    Given the user has role "support"
    When support previews "enable_incremental" while another preview is still running
    Then no new preview should start

  @rack_test
  Scenario: A preview that never finished stops blocking the fund
    Given the user has role "support"
    And a preview for the fund has been in progress for 13 hours
    When support previews "suggest_checks"
    Then the operation should be "previewed"
    And the stale preview should be marked failed

  @rack_test
  Scenario: An allocation run is refused while a switch is being applied
    Given the user has role "support"
    And the fund has a formula "Since Inception Apportioned" adding up the since-inception totals of "Apportioned Fees, Apportioned Others"
    When support previews "enable_incremental"
    And the preview is being applied
    And the user starts an allocation run for the fund
    Then the allocation run should be refused because the formulas are being changed

  # ── Switching off ────────────────────────────────────────────────────────────

  @rack_test
  Scenario: Switching off restores the formulas and their descriptions
    Given the user has role "support"
    And the fund has a formula "Since Inception Apportioned" adding up the since-inception totals of "Apportioned Fees, Apportioned Others"
    When support previews "enable_incremental"
    And support applies the preview
    And support previews "disable_incremental"
    Then the preview should edit formula "Since Inception Apportioned"
    When support applies the preview
    Then the operation should be "applied"
    And the fund should not be on incremental allocation
    And formula "Since Inception Apportioned" should add up single-name since-inception totals again with no description
    And the fund formula operations history should list:
      | operation           | status  |
      | enable_incremental  | applied |
      | disable_incremental | applied |

  @rack_test
  Scenario: A description edited by hand after the switch is kept on switch-off
    Given the user has role "support"
    And the fund has a formula "Since Inception Apportioned" adding up the since-inception totals of "Apportioned Fees, Apportioned Others"
    When support previews "enable_incremental"
    And support applies the preview
    And the description of formula "Since Inception Apportioned" is changed by hand to "Reviewed by finance"
    And support previews "disable_incremental"
    Then the preview should warn "description edited since the migration"
    When support applies the preview
    Then the operation should be "applied"
    And formula "Since Inception Apportioned" should add up the since-inception totals of "Apportioned Fees, Apportioned Others"
    And formula "Since Inception Apportioned" should have description "Reviewed by finance"

  @rack_test
  Scenario: Switching off a second time restores the formula as edited between the switches
    Given the user has role "support"
    And the fund has a formula "Since Inception Apportioned" adding up the since-inception totals of "Apportioned Fees, Apportioned Others"
    When support previews "enable_incremental"
    And support applies the preview
    And support previews "disable_incremental"
    And support applies the preview
    And formula "Since Inception Apportioned" is changed by hand to add up the since-inception totals of "Apportioned Fees, Apportioned Others, Apportioned Interest"
    And support previews "enable_incremental"
    And support applies the preview
    And support previews "disable_incremental"
    And support applies the preview
    Then the operation should be "applied"
    And the fund should not be on incremental allocation
    And formula "Since Inception Apportioned" should add up the since-inception totals of "Apportioned Fees, Apportioned Others, Apportioned Interest"

  # ── Starting values ──────────────────────────────────────────────────────────

  @rack_test
  Scenario: A tracking formula that never stored a value has nothing to recompute
    Given the user has role "support"
    And the fund has a tracking formula "Audit Fees tracking" totalling "Audit Fees"
    When support previews recomputing starting values
    Then the operation should be "blocked"
    And the preview should warn "no stored entries, nothing to recompute"
    When support applies the preview
    Then the operation should be refused with "cannot be applied"

  @rack_test
  Scenario: Recomputing a tracking formula's starting value from full history
    Given the user has role "support"
    And the fund has a tracking formula "Audit Fees tracking" totalling "Audit Fees"
    And folio "101" has "Audit Fees" entries of "300" on "2024-01-15" and "200" on "2024-02-15"
    And formula "Audit Fees tracking" stored "900" for folio "101" on "2024-02-29"
    When support previews recomputing starting values
    Then the operation should be "previewed"
    And the preview should recompute "Audit Fees tracking" for folio "101" from "900" to "500"
    When support applies the preview
    Then the operation should be "applied"
    And the stored "Audit Fees tracking" for folio "101" on "2024-02-29" should be "500"

  # ── Rake ─────────────────────────────────────────────────────────────────────

  @rack_test
  Scenario: The rake dry run prints the plan the page previews
    Given the user has role "support"
    And the fund has a formula "Since Inception Apportioned" adding up the since-inception totals of "Apportioned Fees, Apportioned Others"
    When support previews "enable_incremental"
    Then the rake dry run of "allocation:enable_incremental" should print the same plan as the preview
