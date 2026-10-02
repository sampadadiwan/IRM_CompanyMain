Feature: Capital call journey — checks, seeded journeys and launch
  A new call in a fund entity gets the Full journey automatically (imported calls get Light).
  Each task is decided by a capital call check reading the call's data.
  Worked examples H2, H5, H6, H7, E3, E4, E5, E17, E19, E20, E21, E22, E23, E25, E28, E29, X5 in
  openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;enable_funds=true;currency=INR"
    And the user has role "company_admin"
    And there is an existing investor "" with "1" users
    And there is an existing investor "" with "1" users
    And there is an existing investor "" with "1" users
    And there is a fund "name=Alpha Fund I" for the entity
    And the investors are added to the fund
    And there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And each investor has a "verified" kyc linked to the commitment

  # H2 — New call launches Full; system steps pass as their data appears
  Scenario: A new call gets the Full journey and moves through its first tasks
    Given the entity's capital call journeys are seeded
    When there is a capital call "percentage_called=10"
    Then the corresponding remittances should be created
    And the call has the "Capital Call — Full: Notify Investors" journey
    When the call's journey is evaluated
    Then the call's journey should show:
      | task                     | status  | message                              |
      | Create remittances       | passed  |                                      |
      | Add call notice template | current | The fund has no call notice template |
    Given the fund has capital call template
    When the call's journey is evaluated
    Then the call's journey should show:
      | task                     | status  | message                |
      | Add call notice template | passed  |                        |
      | Generate notices         | current | 0 of 3 notices generated |

  # E20 — Unverified KYC blocks a notice; H2 continued
  Scenario: Generated, then approved notices move the journey on, and unverified KYC is called out
    Given the entity's capital call journeys are seeded
    And the fund has capital call template
    And there is a capital call "percentage_called=10"
    And 1 investor on the call has unverified KYC
    When the call's notices are generated for verified investors
    And the call's journey is evaluated
    Then the call's journey should show:
      | task             | status  | message                                                                |
      | Generate notices | current | 1 investor has unverified KYC — notices are not generated for them    |
    When the remaining investor's KYC is verified and their notice generated
    And the call's journey is evaluated
    Then the call's journey should show:
      | task             | status  | message                             |
      | Generate notices | passed  |                                     |
      | Approve notices  | current | 3 of 3 call notices await approval |
    When the generated call notices are approved
    And the call's journey is evaluated
    Then the call's journey current task should be "Review email"

  # H5, E28 — approval and sending are picked up without hooks (page view / tick)
  Scenario: Approving and sending the call are picked up by the next evaluation
    Given the entity's capital call journeys are seeded
    And the fund has capital call template
    And there is a capital call "percentage_called=10"
    And the call's notices are generated and approved
    And the call's journey is evaluated
    And both review tasks are marked reviewed
    When when the capital call is approved
    And the call's notices are marked sent
    And the 15-minute tick runs
    Then the call's journey should show:
      | task             | status  |
      | Approve call     | passed  |
      | Send notices     | passed  |
      | Collect payments | current |

  # E29 — a confirmed review stays done after sending, and its history names who confirmed it
  Scenario: Confirmed reviews stay done after the notices are sent
    Given the entity's capital call journeys are seeded
    And the fund has capital call template
    And there is a capital call "percentage_called=10"
    And the call's notices are generated and approved
    And the call's journey is evaluated
    And both review tasks are marked reviewed
    When when the capital call is approved
    And the call's notices are marked sent
    And the call's journey is evaluated
    Then the call's journey should show:
      | task          | status |
      | Review email  | passed |
      | Check preview | passed |
      | Send notices  | passed |
    And the "Review email" history should record "passed" from "current" by me via "ui"
    And the "Check preview" history should record "passed" from "current" by me via "ui"
    And the "Review email" history should have no "skipped" event

  # H6, H7, E4 — payments, verification, completion without unit prices
  Scenario: Paying and verifying the call completes the journey when there are no unit prices
    Given the entity's capital call journeys are seeded
    And the fund has capital call template
    And there is a capital call "percentage_called=10"
    And the call has no unit prices
    And the call's notices are generated and approved
    And the call's journey is evaluated
    And both review tasks are marked reviewed
    And when the capital call is approved
    And the call's notices are marked sent
    When I mark the remittances as paid
    And the call's journey is evaluated
    Then the call's journey current task should be "Verify remittances"
    When the call's remittances are verified
    And the call's journey is evaluated
    Then the call's journey should show:
      | task           | status | message                         |
      | Allocate units | na     | No unit prices set on this call |
    And the call's journey should be complete

  # E3, E25 — imported calls get Light; on Full their notice tasks are n/a
  Scenario: An imported call gets the Light journey
    Given the entity's capital call journeys are seeded
    When an imported capital call "percentage_called=10" is created
    Then the call has the "Capital Call — Light: Record Only" journey

  Scenario: An imported call on the Full journey shows its notice tasks as not applicable
    Given the entity's capital call journeys are seeded
    And every capital call in the entity gets the Full journey
    When an imported capital call "percentage_called=10" is created
    And the call's journey is evaluated
    Then the call's journey should show:
      | task                     | status | message                                 |
      | Add call notice template | na     | Notices are not sent for imported calls |
      | Approve call             | na     | Imported calls are not approved in CapHive |
      | Send notices             | na     | Notices are not sent for imported calls |

  # E22 — Light journey completes
  Scenario: A Light journey shows only its four tasks
    Given the entity's capital call journeys are seeded
    When an imported capital call "percentage_called=10" is created
    And the call's journey is evaluated
    Then the call's journey should have the tasks "Create remittances, Collect payments, Verify remittances, Allocate units"

  # E23 — Call set not to notify
  Scenario: A call set not to notify shows its notice and email tasks as not applicable
    Given the entity's capital call journeys are seeded
    When there is a capital call "percentage_called=10;send_call_notice_flag=false"
    And the call's journey is evaluated
    Then the call's journey should show:
      | task             | status | message                                  |
      | Generate notices | na     | This call is set to not notify investors |
      | Review email     | na     | This call is set to not notify investors |
      | Send notices     | na     | This call is set to not notify investors |

  # E5 — Missing template
  Scenario: A fund without a call notice template stops at the template task
    Given the entity's capital call journeys are seeded
    When there is a capital call "percentage_called=10"
    And the call's journey is evaluated
    Then the call's journey current task should be "Add call notice template"

  # E21 — Uploaded remittances
  Scenario: An upload-basis call passes Create remittances once its remittances exist and imports are done
    Given the entity's capital call journeys are seeded
    When there is a capital call "call_basis=Upload;percentage_called=0"
    And the call's journey is evaluated
    Then the call's journey should show:
      | task               | status  | message                     |
      | Create remittances | current | No remittances uploaded yet |
    When remittances are uploaded for 2 investors on the call
    And the call's journey is evaluated
    Then the call's journey should show:
      | task               | status | message                  |
      | Create remittances | passed | 2 remittances uploaded   |

  # E19 — Large call stays cheap: checks count, they never load remittance rows
  Scenario: Evaluating a call never loads all remittance columns
    Given the entity's capital call journeys are seeded
    And there is a capital call "percentage_called=10"
    When the call's journey is evaluated while counting queries
    Then no query selected every column of capital_remittances

  # X5 — Entity without seeded journeys
  Scenario: A call in an entity whose journeys were never seeded gets no journey
    Given the entity's capital call journeys are removed
    When there is a capital call "percentage_called=10"
    Then the call has no journey

  # Disabled journey templates: the seeded templates and rules are all still there, but the admin
  # has retired them, so a new call gets nothing — no instance, so no step bar and no reminders.
  Scenario: A call created while the journey templates are disabled gets no journey
    Given the entity's capital call journeys are seeded
    And the entity's capital call journey templates are disabled
    When there is a capital call "percentage_called=10"
    Then the call has no journey
    And the call should have no workflow template

  # J2.2 — work that moves a call forward re-checks its journey at once, so open pages update
  # without waiting for the 15-minute tick
  Scenario Outline: Notice generation and approval update open call pages at once
    Given the entity's capital call journeys are seeded
    And the user has role "approver"
    And the fund has capital call template
    And there is a capital call "percentage_called=10"
    And the call's journey is evaluated
    And journey activity on calls is recorded
    When <action>
    Then open pages for the call should have been told about the change

    Examples:
      | action                                                      |
      | the call's notices are generated by the doc job             |
      | the call's notices are generated and approved in bulk       |
      | the call's notices are generated and approved by date range |

  Scenario: Recording payments after the notices are sent updates open call pages at once
    Given the entity's capital call journeys are seeded
    And the user has role "approver"
    And the fund has capital call template
    And there is a capital call "percentage_called=10"
    And the call is ready for sign-off
    And when the capital call is approved
    And the call's notices are marked sent
    And the call's journey is evaluated
    And journey activity on calls is recorded
    When I record full payment on each of the call's remittances
    Then the call's journey should have been re-checked
    And open pages for the call should have been told about the change

  # A re-check that finds nothing new tells nobody (no page reloads for nothing)
  Scenario: Re-running remittance generation re-checks the journey but changes nothing on open pages
    Given the entity's capital call journeys are seeded
    And there is a capital call "percentage_called=10"
    And the call's journey is evaluated
    And journey activity on calls is recorded
    When the call's remittances are generated by the call job
    Then the call's journey should have been re-checked
    And open pages for the call should not have been told about any change

  # J2.2 — the hooks are no-ops on calls without a journey (every call created before the rollout)
  Scenario: Forward-moving actions on a call without a journey behave as before
    Given the entity's capital call journeys are removed
    And the user has role "approver"
    And the fund has capital call template
    And there is a capital call "percentage_called=10"
    And journey activity on calls is recorded
    When the call's remittances are generated by the call job
    And the call's notices are generated and approved in bulk
    Then the call's notices should all be approved
    And the call has no journey
    And open pages for the call should not have been told about any change

  # E17 — a journey never stops a call being deleted (the record's assignment and journey go with it)
  Scenario: A call with a journey can be deleted
    Given the entity's capital call journeys are seeded
    And there is a capital call "percentage_called=10"
    And the call has the "Capital Call — Full: Notify Investors" journey
    When I delete the call
    Then the call and its journey should be gone
