Feature: Capital Calls
  Calls to capital commitments


Scenario Outline: Create new commitment after capital call
  Given Im logged in as a user "" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing investor "" with "1" users
  Given there is an existing investor "" with "1" users
  Given there is a fund "<fund>" for the entity
  Given the investors are added to the fund
  Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
  Given there is a capital call "<call>"
  Given there is an existing investor "" with "1" users
  Given there is a capital commitment of "orig_folio_committed_amount_cents=100000000" for the last investor
  Given the investors are added to the fund
  Then the corresponding remittances should be created
  Then I should see the remittances

Examples:
  	|entity                                 |fund                 | call |
  	|entity_type=Investment Fund;enable_funds=true;currency=INR  |name=Test  | percentage_called=20 |
    |entity_type=Investment Fund;enable_funds=true;enable_units=true;currency=USD  |name=Merger;unit_types=Series A,Series B| percentage_called=20;generate_remittances_verified=true |


@doc_gen @notification @import
Scenario Outline: Create new capital call
  Given Im logged in as a user "" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is a fund "<fund>" for the entity
  And Given I upload an investors file for the fund
  Given the investors have approved investor access
  Given the fund has capital call template
  Given the investors are added to the fund
  And Given import file "capital_commitments.xlsx" for "CapitalCommitment"
  And Given the commitments have a cc "advisor@gmail.com"
  And Given import file "account_entries.xlsx" for "AccountEntry"
  When I create a new capital call "<call>"
  Then I should see the capital call details
  Then the corresponding remittances should be created
  Then I should see the remittances
  Given the remittance have a document "Sample" from "public/sample_uploads/sample_kyc1.pdf" attached
  Given there is a custom notification for the capital call with subject "<subject>" with email_method "notify_capital_remittance"
  Given each investor has a "verified" kyc linked to the commitment
  Given the fund has capital call template
  And when the capital call docs are generated
  Then the generated doc must be attached to the capital remittances
  And the generated call notices have as_of set to the remittance date
  Given the generated call notices are approved
  Then when the capital call is approved
  And the capital call notifications are sent
  And the investors must receive email with subject "<subject>" with the document "Sample.pdf" attached
  And the remittances must be marked with notification sent
  And the capital call collected amount should be "0"
  When I mark the remittances as paid
  Then I should see the remittances
  Then I should see the remittance payments with investing entity names
  And the capital call collected amount should be "0"
  When I mark the remittances as verified
  Then I should see the remittances
  And the capital call collected amount should be "<collected_amount>"
  And the remittance rollups should be correct


  Examples:
  	|entity                                         |fund                |msg	| call | collected_amount | subject |
  	|entity_type=Investment Fund;enable_funds=true;enable_units=true;currency=INR  |name=SAAS Fund;currency=INR      |Fund was successfully created| percentage_called=20;call_basis=Percentage of Commitment | 3520000 | This is a capital call for Fund 1 |
    |entity_type=Investment Fund;enable_funds=true;enable_units=true;currency=INR  |name=SAAS Fund;unit_types=Series A,Series B;currency=INR    |Fund was successfully created| call_basis=Investable Capital Percentage;amount_to_be_called_cents=10000000 | 40000 | This is a capital call for Fund 2 |


@import
Scenario Outline: Capital Call recompute fees
  Given Im logged in as a user "" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is a fund "<fund>" for the entity
  And Given I upload an investors file for the fund
  Given the investors have approved investor access
  Given the investors are added to the fund
  And Given import file "capital_commitments.xlsx" for "CapitalCommitment"
  And Given the commitments have a cc "advisor@gmail.com"
  And Given import file "test_files/account_entries_recompute_fees_1.xlsx" for "AccountEntry"
  When I create a new capital call "<call>" with fees
  Then I should see the capital call details
  Then the corresponding remittances should be created with fees
  Then I should see the remittances
  And The remittances should have the proper fees and call amount
  And Given import file "test_files/account_entries_recompute_fees_2.xlsx" for "AccountEntry"
  When I recompute the capital call fees
  Then The remittances should have the updated proper fees and call amount



  Examples:
  |entity                                         |fund                |msg	| call | collected_amount | subject |
  |entity_type=Investment Fund;enable_funds=true;enable_units=true;currency=INR  |name=SAAS Fund;currency=INR      |Fund was successfully created| percentage_called=20;call_basis=Percentage of Commitment | 3520000 | This is a capital call for Fund 1 |
  |entity_type=Investment Fund;enable_funds=true;enable_units=true;currency=INR  |name=SAAS Fund;unit_types=Series A,Series B;currency=INR    |Fund was successfully created| call_basis=Investable Capital Percentage;amount_to_be_called_cents=10000000 | 40000 | This is a capital call for Fund 2 |


Scenario Outline: Editing the call date cascades to all capital remittances, including verified ones
  Given Im logged in as a user "" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing investor "" with "1" users
  Given there is an existing investor "" with "1" users
  Given there is a fund "<fund>" for the entity
  Given the investors are added to the fund
  Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
  Given there is a capital call "<call>"
  Then the corresponding remittances should be created
  Then when the capital call is approved
  When I mark the remittances as paid
  When I mark the remittances as verified
  When I change the capital call's call date to "2026-09-01"
  Then I should see the call date change warning naming all the remittances
  When I confirm the call date change
  Then every capital remittance's remittance date should be "2026-09-01"

  Examples:
  	|entity                                 |fund                 | call |
  	|entity_type=Investment Fund;enable_funds=true;currency=INR  |name=Test  | percentage_called=20 |


Scenario Outline: Create a capital call
  Given there is a user "<user>" for an entity "<entity>"
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund;currency=INR" for the entity
  Given there is an existing investor "name=Investor 1"
  Given there is a capital commitment of "orig_folio_committed_amount_cents=100000000;folio_currency=INR" for the last investor
  Given there is a capital commitment of "orig_folio_committed_amount_cents=100000000;folio_currency=INR;fund_close=Second Close" for the last investor
  When I create a Capital Call with percentage of commitment
  Given it should create Capital Remittances according to the close percentage

  Examples:
    | user             | entity                           |
    | first_name=Test  | name=Urban;entity_type=Investment Fund |

Scenario Outline: Create a capital call with Upload call basis
  Given there is a user "<user>" for an entity "<entity>"
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund;currency=INR" for the entity
  Given there is an existing investor "name=Investor 1"
  Given there is a capital commitment of "orig_folio_committed_amount_cents=100000000;folio_currency=INR" for the last investor
  Given there is a capital commitment of "orig_folio_committed_amount_cents=100000000;folio_currency=INR;fund_close=Second Close" for the last investor
  When I create a Capital Call with upload call basis
  Given it should create a Capital Call with given data

  Examples:
    | user             | entity                           |
    | first_name=Test  | name=Urban;entity_type=Investment Fund |

Scenario Outline: Create a capital call with Upload call basis
  Given there is a user "<user>" for an entity "<entity>"
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund;currency=INR" for the entity
  Given there is an existing investor "name=Investor 1"
  Given there is a capital commitment of "orig_folio_committed_amount_cents=100000000;folio_currency=INR" for the last investor
  Given there is a capital commitment of "orig_folio_committed_amount_cents=100000000;folio_currency=INR;fund_close=Second Close" for the last investor
  When I create a Capital Call with investable call basis
  Given it should create a Investable Capital Call with given data

  Examples:
    | user             | entity                           |
    | first_name=Test  | name=Urban;entity_type=Investment Fund |

@notification
Scenario Outline: Generate fund units from capital call
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing investor "" with "1" users
  Given there is an existing investor "" with "1" users
  Given there is a fund "<fund>" for the entity
  Given the investors are added to the fund
  Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
  Given there is a capital call "<call>"
  Given there is an existing investor "" with "1" users
  Given there is a capital commitment of "orig_folio_committed_amount_cents=100000000" for the last investor
  Given the investors are added to the fund
  Then the corresponding remittances should be created
  Then I should see the remittances
  Given the capital calls are approved
  Given the remittances are paid and verified
  Given the remittances has some units already allocated
  Given the units are generated
  Then it should generate only the remaining units
  Given the units are generated
  Then error email for fund units already allocated should be sent

Examples:
    |user     |entity                                 |fund                 | call |
    |           |entity_type=Investment Fund;enable_funds=true  |name=Test  | percentage_called=20 |

@rack_test
Scenario Outline: Generate fund units from capital call with phased remittance payments
  Given there is a user "" for an entity "entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is an existing investor "investor_name=Investor 1" with "1" users
  Given there is an existing investor "investor_name=Investor 2" with "1" users
  Given there is a fund "name=TestFund" for the entity
  Given the investors are added to the fund
  Given there are capital commitments of "<commitment>" from each investor
  Given there is a capital call "<call>"
  Then the corresponding remittances should be created
  Given the capital calls are approved

  # Phase 1: Pay 50%
  Given remittances are paid "<paid_percentage1>" and verified
  Given the units are generated
  Then there should be correct units generated for the latest payment

  # Phase 2: Pay remaining 50%
  Given remittances are paid "<paid_percentage2>" and verified
  Given the units are generated
  Then there should be correct units generated for the latest payment
  And the total units should match the total paid amount
  Then the total units should be "4"

Examples:
  | commitment                     | call                 | paid_percentage1         | paid_percentage2         |
  | orig_folio_committed_amount_cents=100000000 | percentage_called=20 | 50 | 50 |

Scenario Outline: Delete Remittance with no payments
  Given there is a user "<user>" for an entity "<entity>"
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing investor "investor_name=Investor 1" with "1" users
  Given there is an existing investor "investor_name=Investor 2" with "1" users
  Given there is a fund "name=TestFund" for the entity
  Given the investors are added to the fund
  Given there are capital commitments of "<commitment>" from each investor
  Given there is a capital call "<call>"
  Then the corresponding remittances should be created
  Given I delete a remittance with no payments
  Then the remittance is successfully deleted
Examples:
  | commitment                     | call                 | paid_percentage1         | paid_percentage2         | user |entity |
  | orig_folio_committed_amount_cents=100000000 | percentage_called=20 | 50 | 50 | first_name=Test |name=Urban;entity_type=Investment Fund |

Scenario Outline: Delete Remittance with payment units alocated
  Given there is a user "<user>" for an entity "<entity>"
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing investor "investor_name=Investor 1" with "1" users
  Given there is an existing investor "investor_name=Investor 2" with "1" users
  Given there is a fund "name=TestFund" for the entity
  Given the investors are added to the fund
  Given there are capital commitments of "<commitment>" from each investor
  Given there is a capital call "<call>"
  Then the corresponding remittances should be created
  Given the capital calls are approved
  Given remittances are paid "<paid_percentage1>" and verified
  Given the units are generated
  Then there should be correct units generated for the latest payment
  Given I delete a remittance having payments with allocated units
  Then I get the error "Cannot delete this remittance as units have already been allocated for payments"

Examples:
  | commitment                     | call                 | paid_percentage1         | paid_percentage2         | user |entity |
  | orig_folio_committed_amount_cents=100000000 | percentage_called=20 | 50 | 50 | first_name=Test |name=Urban;entity_type=Investment Fund |


# Edge case: a fund with no commitments can't get a call at all (openspec funds/capital-call-creation);
# more cases in capital_call_requires_commitments.feature
Scenario Outline: Capital call on a fund with no commitments is refused
  Given there is a user "<user>" for an entity "<entity>"
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is a fund "name=EmptyFund;currency=INR" for the entity
  When I submit the new capital call form named "Empty fund call"
  Then the capital call form shows the no commitments error and keeps the name "Empty fund call"
  And no capital call is created

  Examples:
    | user             | entity                                                   |
    | first_name=Test  | name=Urban;entity_type=Investment Fund;enable_funds=true |


# State machine: approve? requires !record.approved; cannot approve a call twice
@rack_test
Scenario Outline: Approved capital call cannot be approved again
  Given there is a user "" for an entity "<entity>"
  Given the user has role "company_admin"
  Given the user has role "approver"
  Given there is a fund "name=TestFund" for the entity
  Given the fund has "1" capital call
  Given the capital calls are approved
  Then user "false" have "approve" access to the capital calls

  Examples:
    | entity                                               |
    | entity_type=Investment Fund;enable_funds=true        |


# State machine: unapprove? requires record.approved, the inverse of approve? — the two
# buttons are mutually exclusive by construction, never shown at the same time.
@rack_test
Scenario Outline: Unapproved capital call cannot be unapproved, but an approved one can be
  Given there is a user "" for an entity "<entity>"
  Given the user has role "company_admin"
  Given the user has role "approver"
  Given there is a fund "name=TestFund" for the entity
  Given the fund has "1" capital call
  Then user "false" have "unapprove" access to the capital calls
  Given the capital calls are approved
  Then user "true" have "unapprove" access to the capital calls
  Then user "false" have "approve" access to the capital calls

  Examples:
    | entity                                               |
    | entity_type=Investment Fund;enable_funds=true        |


# Access control: only permissioned employees can create capital calls
@rack_test
Scenario Outline: Capital call creation is restricted to permissioned employees
  Given there is a user "" for an entity "<entity>"
  Given the user has role "<role>"
  Given there is a fund "name=TestFund" for the entity
  Given the fund has "1" capital call
  Then user "<can_create>" have "create" access to the capital calls

  Examples:
    | entity                                               | role          | can_create |
    | entity_type=Investment Fund;enable_funds=true        | company_admin | true       |
    | entity_type=Investment Fund;enable_funds=true        | employee      | false      |
    | entity_type=Investment Fund;enable_funds=true        | investor      | false      |

  # Capital call notices attach the remittance's own documents (CapitalRemittanceMailer#
  # attach_all_files), so the same size limit applies - and the same all-or-nothing rule:
  # an oversized notice on one remittance stops the notices for the whole call.
  @doc_gen @notification @import @attachment
  Scenario: An oversized document on a remittance stops every call notice
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is a fund "name=SAAS Fund" for the entity
    And Given I upload an investors file for the fund
    Given the investors have approved investor access
    Given the fund has capital call template
    Given the investors are added to the fund
    And Given import file "capital_commitments.xlsx" for "CapitalCommitment"
    And Given import file "account_entries.xlsx" for "AccountEntry"
    When I create a new capital call "name=Call 1"
    Then the corresponding remittances should be created
    Given the remittance have a document "Sample" from "public/sample_uploads/sample_kyc1.pdf" attached
    Given there is a custom notification for the capital call with subject "Call Notice" with email_method "notify_capital_remittance"
    Given each investor has a "verified" kyc linked to the commitment
    And when the capital call docs are generated
    Given the generated call notices are approved
    Then when the capital call is approved
    Given one remittance has an oversized document "Sample" of 20 MB
    And the notification deliveries are cleared
    And in-app alerts are captured
    And the capital call notifications are sent
    Then no call notice reaches an investor, only the blocked-send report
    # An email alone is a poor place to learn that the button you just pressed did nothing.
    # This path shipped without it: it never passed a user_id to report_blocked_send, so the
    # alert was skipped and nothing failed.
    And the triggering user gets a danger in-app alert mentioning "over the 7 MB limit"

  # The counterpart to the rule above. A remittance that has ALREADY been notified is not part
  # of this run, so an oversized document sitting on it must not stop the notices for the
  # remittances that have never been sent one.
  @doc_gen @notification @import @attachment
  Scenario: An oversized document on an already-notified remittance does not block the rest
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is a fund "name=SAAS Fund" for the entity
    And Given I upload an investors file for the fund
    Given the investors have approved investor access
    Given the fund has capital call template
    Given the investors are added to the fund
    And Given import file "capital_commitments.xlsx" for "CapitalCommitment"
    And Given import file "account_entries.xlsx" for "AccountEntry"
    When I create a new capital call "name=Call 1"
    Then the corresponding remittances should be created
    Given the remittance have a document "Sample" from "public/sample_uploads/sample_kyc1.pdf" attached
    Given there is a custom notification for the capital call with subject "Call Notice" with email_method "notify_capital_remittance"
    Given each investor has a "verified" kyc linked to the commitment
    And when the capital call docs are generated
    Given the generated call notices are approved
    Then when the capital call is approved
    Given one remittance has an oversized document "Sample" of 20 MB
    And the remittance with the oversized document is already notified
    And the notification deliveries are cleared
    And the capital call notifications are sent
    Then the remittances that were not yet notified still receive their notices

  # The REMINDER button is a separate send path with its own copy of the preflight wiring -
  # CapitalCall#reminder_capital_call, not CapitalCallJob#notify - and the code comment on
  # #blocked_by_attachment_size? says outright that the two have to be kept in step by hand.
  # Nothing tested it, so the two could drift and only the initial notice would fail.
  #
  # It also runs inside the request rather than in a job, which is why it returns the block
  # instead of only broadcasting: the controller has to replace "Reminder sent for capital call."
  # with the real reason before redirecting.
  @doc_gen @notification @import @attachment
  Scenario: An oversized document stops the whole capital call reminder run
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is a fund "name=SAAS Fund" for the entity
    And Given I upload an investors file for the fund
    Given the investors have approved investor access
    Given the fund has capital call template
    Given the investors are added to the fund
    And Given import file "capital_commitments.xlsx" for "CapitalCommitment"
    And Given import file "account_entries.xlsx" for "AccountEntry"
    When I create a new capital call "name=Call 1"
    Then the corresponding remittances should be created
    Given the remittance have a document "Sample" from "public/sample_uploads/sample_kyc1.pdf" attached
    Given there is a custom notification for the capital call with subject "Call Reminder" with email_method "reminder_capital_remittance"
    Given each investor has a "verified" kyc linked to the commitment
    And when the capital call docs are generated
    Given the generated call notices are approved
    Then when the capital call is approved
    Given one remittance has an oversized document "Sample" of 20 MB
    And the notification deliveries are cleared
    And in-app alerts are captured
    When the capital call reminders are sent
    Then the reminder run is blocked, naming the oversized document
    And the triggering user gets a danger in-app alert mentioning "over the 7 MB limit"

  # Regression guard on the reminder path: within the limit it must be untouched.
  @doc_gen @notification @import @attachment
  Scenario: Capital call reminders under the size limit are unaffected
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is a fund "name=SAAS Fund" for the entity
    And Given I upload an investors file for the fund
    Given the investors have approved investor access
    Given the fund has capital call template
    Given the investors are added to the fund
    And Given import file "capital_commitments.xlsx" for "CapitalCommitment"
    And Given import file "account_entries.xlsx" for "AccountEntry"
    When I create a new capital call "name=Call 1"
    Then the corresponding remittances should be created
    Given the remittance have a document "Sample" from "public/sample_uploads/sample_kyc1.pdf" attached
    Given there is a custom notification for the capital call with subject "Call Reminder" with email_method "reminder_capital_remittance"
    Given each investor has a "verified" kyc linked to the commitment
    And when the capital call docs are generated
    Given the generated call notices are approved
    Then when the capital call is approved
    And the notification deliveries are cleared
    When the capital call reminders are sent
    Then the reminder run goes ahead

  # skip_doc_gen? is the only filter the preflight applies in Ruby (it reads a json_fields key,
  # so it cannot be scoped into the relation). A remittance that would never be emailed must not
  # block the call for everyone else - the equivalent adhoc case is the one that actually bit us
  # in practice, where a dormant commitment silenced a whole fund.
  @doc_gen @notification @import @attachment
  Scenario: An oversized document on a skip_doc_gen remittance does not block the call
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is a fund "name=SAAS Fund" for the entity
    And Given I upload an investors file for the fund
    Given the investors have approved investor access
    Given the fund has capital call template
    Given the investors are added to the fund
    And Given import file "capital_commitments.xlsx" for "CapitalCommitment"
    And Given import file "account_entries.xlsx" for "AccountEntry"
    When I create a new capital call "name=Call 1"
    Then the corresponding remittances should be created
    Given the remittance have a document "Sample" from "public/sample_uploads/sample_kyc1.pdf" attached
    Given there is a custom notification for the capital call with subject "Call Notice" with email_method "notify_capital_remittance"
    Given each investor has a "verified" kyc linked to the commitment
    And when the capital call docs are generated
    Given the generated call notices are approved
    Then when the capital call is approved
    Given one remittance has an oversized document "Sample" of 20 MB
    And the commitment with the oversized document has skip_doc_gen enabled
    And the notification deliveries are cleared
    And the capital call notifications are sent
    Then the remittances that were not yet notified still receive their notices

  # Regression guard: normal-sized notices are completely unaffected.
  @doc_gen @notification @import @attachment
  Scenario: Call notices under the size limit send exactly as before
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is a fund "name=SAAS Fund" for the entity
    And Given I upload an investors file for the fund
    Given the investors have approved investor access
    Given the fund has capital call template
    Given the investors are added to the fund
    And Given import file "capital_commitments.xlsx" for "CapitalCommitment"
    And Given import file "account_entries.xlsx" for "AccountEntry"
    When I create a new capital call "name=Call 1"
    Then the corresponding remittances should be created
    Given the remittance have a document "Sample" from "public/sample_uploads/sample_kyc1.pdf" attached
    Given there is a custom notification for the capital call with subject "Call Notice" with email_method "notify_capital_remittance"
    Given each investor has a "verified" kyc linked to the commitment
    And when the capital call docs are generated
    Given the generated call notices are approved
    Then when the capital call is approved
    And the notification deliveries are cleared
    And the capital call notifications are sent
    Then some capital call notification emails should have been sent
    And the investors must receive email with subject "Call Notice" with the document "Sample.pdf" attached
