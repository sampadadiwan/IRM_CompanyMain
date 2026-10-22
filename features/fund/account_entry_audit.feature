@account_entry_audit @rack_test
Feature: Only changes people make are audited on account entries and portfolio investments
  The audit trail is kept for fund compliance. An account entry is audited only when a person
  creates, edits or deletes it on the Account Entries screen; allocation runs, imports and jobs
  write thousands of entries and leave no audit. A portfolio investment no longer audits the values
  a valuation recompute overwrites. The old AccountEntry audits are removed by a rake task that
  copies every row to a file before deleting it.

  Background:
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund;currency=INR"
    And the user has role "company_admin"
    And I am signed in as the current user
    And the entity has funds "Alpha Fund"
    And fund "Alpha Fund" has an entry "Alpha Fee" for folio "101" of investor "Acme Capital"

  # A1 — a hand edit on the screen is audited, against the user, with the changed column
  # (only a hand-made entry can be edited: AccountEntryPolicy#update? refuses generated ones)
  Scenario: Editing an entry on the screen is audited
    Given the entry "Alpha Fee" was made by hand
    When I change the notes of the entry "Alpha Fee" to "Hand fix" on the screen
    Then the entry "Alpha Fee" should have "1" "update" audit by the current user
    And its latest audit should record only the columns "notes"

  # A2 — a hand-made entry is audited on create
  Scenario: Creating an entry on the screen is audited
    When I create the entry "Hand Fee" for fund "Alpha Fund" on the screen
    Then the entry "Hand Fee" should have "1" "create" audit by the current user

  # A3 — a hand delete is audited and the entry is only soft-deleted
  Scenario: Deleting an entry on the screen is audited
    When I delete the entry "Alpha Fee"
    Then the entry "Alpha Fee" should have "1" "destroy" audit by the current user
    And the entry "Alpha Fee" should be soft-deleted

  # A4/A5 — Edge case: the same changes made outside the screen (as allocation runs, imports and jobs
  # do) write no audit, even with an acting user set the way ApplicationJob sets one
  Scenario: Changes outside the screen are not audited
    When the system creates the entry "Run Fee" for fund "Alpha Fund" as the current user
    And the system changes the notes of the entry "Alpha Fee" to "Recomputed" as the current user
    And the system deletes the entry "Run Fee" as the current user
    Then there should be no audits for account entries

  # P1 — Edge case: a recompute that changes only computed columns writes no audit
  Scenario: Recomputed portfolio investment values are not audited
    Given there is an existing portfolio company ""
    And there is an investment instrument for the portfolio company "name=Stock;category=Unlisted;sub_category=Equity;sector=Tech"
    And there is a portfolio investment for the fund
    When the computed values of the portfolio investment change
    Then the portfolio investment should have no new audit

  # P2/P3 — a person's edit is audited, without the computed values saved alongside it
  Scenario: A person's edit to a portfolio investment is audited without the computed values
    Given there is an existing portfolio company ""
    And there is an investment instrument for the portfolio company "name=Stock;category=Unlisted;sub_category=Equity;sector=Tech"
    And there is a portfolio investment for the fund
    When the notes of the portfolio investment change to "Board note" along with its computed values
    Then the portfolio investment should have "1" new "update" audit recording only the columns "notes"

  # R1 — the dry run only reports
  Scenario: The purge dry run deletes nothing
    Given there are "3" old audits for account entries
    When support runs the account entry audit purge without EXECUTE
    Then there should be "3" audits for account entries
    And the audits of other records should remain

  # R2/R3 — EXECUTE copies every AccountEntry audit to the export file, then deletes only those
  Scenario: The purge copies then deletes only account entry audits
    Given there are "3" old audits for account entries
    When support runs the account entry audit purge with EXECUTE and an export file
    Then there should be no audits for account entries
    And the audits of other records should remain
    And the export file should hold "3" audits for account entries

  # R4 — Edge case: EXECUTE without EXPORT is refused, so no audit is deleted without a copy
  Scenario: The purge refuses to delete without an export file
    Given there are "3" old audits for account entries
    When support runs the account entry audit purge with EXECUTE but no export file
    Then the purge should have been refused
    And there should be "3" audits for account entries

  # R5 — Edge case: an existing export file is never overwritten (a re-run after an interruption)
  Scenario: The purge refuses to overwrite an existing export file
    Given there are "3" old audits for account entries
    And the export file already exists
    When support runs the account entry audit purge with EXECUTE and an export file
    Then the purge should have been refused
    And there should be "3" audits for account entries
