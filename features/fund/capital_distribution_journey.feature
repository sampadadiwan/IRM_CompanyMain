Feature: Capital distribution journey — tasks, launch and not-applicable rules
  Each new distribution in a set-up company gets a journey: Full (10 tasks) unless it was imported,
  which gets Light (3 tasks). Every task is worked out from the distribution's own data. Notice tasks
  are not applicable when the fund has no Distribution Template; notice, review and email tasks are not
  applicable when investors are not emailed. Distributions created before setup get no journey.
  Every action that completes or undoes a task re-checks the journey at once (hooks), moving it on or
  back and resetting later sign-offs given before an undo.
  Worked examples H2, H6, H7, H8, H9, E1, E2, E3, E4, E5, E7, E8–E15, E18, E19, E21, E24 in
  openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;enable_funds=true;currency=INR"
    And the user has role "company_admin"
    And the user has role "approver"
    And there is an existing investor "" with "1" users
    And there is an existing investor "" with "1" users
    And there is an existing investor "" with "1" users
    And there is a fund "name=Growth Fund II;currency=INR" for the entity
    And the investors are added to the fund
    And there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And each investor has a "verified" kyc linked to the commitment
    And the entity's capital distribution journeys are seeded

  # H2 — a new distribution gets Full; payment generation passes Create payments
  @rack_test
  Scenario: A new distribution gets the Full journey and moves past Create payments
    Given the fund has a Distribution Template
    And there is a capital distribution "title=Q3 2026 Exit Proceeds;income_cents=300000000;approved=false"
    When the distribution's journey is evaluated
    Then the distribution has the "Capital Distribution — Full: Notify Investors" journey
    And the distribution's journey should show:
      | task             | status  | message                 |
      | Create payments  | passed  | 3 payments created      |
      | Generate notices | current | 0 of 3 notices generated |
    And the distribution's journey current task should be "Generate notices"

  # H9 — an imported distribution gets Light
  @rack_test
  Scenario: An imported distribution gets the Light journey
    When an imported capital distribution "title=Historic 2024 Payout;income_cents=100000000" is created
    And the distribution's journey is evaluated
    Then the distribution has the "Capital Distribution — Light: Record Only" journey
    And the distribution's journey should have the tasks "Create payments, Mark payments completed, Redeem units"

  # E1 — no Distribution Template: the notice tasks are not applicable
  @rack_test
  Scenario: Notice tasks are not applicable when the fund has no Distribution Template
    Given there is a capital distribution "title=Q3 2026 Exit Proceeds;income_cents=300000000;approved=false"
    When the distribution's journey is evaluated
    Then the distribution's journey should show:
      | task             | status  | message                         |
      | Generate notices | na      | No distribution notice template |
      | Approve notices  | na      | No distribution notice template |
      | Review custom notification | current |                                 |

  # E2 — Send Notification off: notice, review and email tasks are not applicable
  @rack_test
  Scenario: Notice, review and email tasks are not applicable when investors are not emailed
    Given the fund has a Distribution Template
    And there is a capital distribution "title=Q3 2026 Exit Proceeds;income_cents=300000000;approved=false;send_notification_on_complete=false"
    When the distribution's journey is evaluated
    Then the distribution's journey should show:
      | task                 | status  | message                                         |
      | Generate notices     | na      | Investors are not emailed for this distribution |
      | Review custom notification | na      | Investors are not emailed for this distribution |
      | Email investors      | na      | Investors are not emailed for this distribution |
      | Approve distribution | current | The distribution is not approved yet            |

  # E3 — every commitment set to Skip Doc Gen: nobody is emailed
  @rack_test
  Scenario: Notice, review and email tasks are not applicable when every commitment skips doc gen
    Given the fund has a Distribution Template
    And every commitment of the fund is set to skip doc gen
    And there is a capital distribution "title=Q3 2026 Exit Proceeds;income_cents=300000000;approved=false"
    When the distribution's journey is evaluated
    Then the distribution's journey should show:
      | task             | status | message                                |
      | Generate notices | na     | Every commitment is set to Skip Doc Gen |
      | Email investors  | na     | Every commitment is set to Skip Doc Gen |

  # E4 — Upload basis: waits for the upload, and says when it failed
  @rack_test
  Scenario: An Upload distribution waits for its payments and reports a failed upload
    Given there is a capital distribution "title=Q3 2026 Exit Proceeds;income_cents=300000000;approved=false;distribution_on=Upload"
    When the distribution's journey is evaluated
    Then the distribution's journey should show:
      | task            | status  | message                 |
      | Create payments | current | No payments uploaded yet |
    When a payment upload for the distribution has failed
    And the distribution's journey is evaluated
    Then the distribution's journey should show:
      | task            | status  | message                                  |
      | Create payments | current | Payment upload failed — fix and re-import |

  # E5 — an investor with unverified KYC gets no notice, and the task says so
  @rack_test
  Scenario: Generate notices says when unverified KYC blocks a notice
    Given the fund has a Distribution Template
    And there is a capital distribution "title=Q3 2026 Exit Proceeds;income_cents=300000000;approved=false"
    And the KYC of 1 investor in the distribution is not verified
    When the distribution's notices are generated for investors with verified KYC
    And the distribution's journey is evaluated
    Then the distribution's journey should show:
      | task             | status  | message                                                     |
      | Generate notices | current | 1 investor has unverified KYC — notices are not generated for them |

  # E24 — the seeded CFO sign-off has no approver yet, so it is n/a instead of waiting forever
  @rack_test
  Scenario: The seeded CFO sign-off is not applicable until an approver is picked
    Given there is a capital distribution "title=Q3 2026 Exit Proceeds;income_cents=300000000;approved=false"
    And both distribution review tasks are marked reviewed
    When the distribution's journey is evaluated
    Then the distribution's journey should show:
      | task                 | status  | message                                                      |
      | CFO sign-off         | na      | No approver set — pick one on this step in the journey template |
      | Approve distribution | current | The distribution is not approved yet                         |

  # E7 — no unit prices: Redeem units is not applicable
  @rack_test
  Scenario: Redeem units is not applicable without unit prices
    Given there is a capital distribution "title=Q3 2026 Exit Proceeds;income_cents=300000000;approved=false"
    And the distribution has no unit prices
    When the distribution's journey is evaluated
    Then the distribution's journey should show:
      | task         | status | message                            |
      | Redeem units | na     | The distribution has no unit prices |

  # E19 — a distribution in a company that is not set up gets no journey, and its page is unchanged
  @rack_test
  Scenario: A distribution in a company without distribution journeys gets none
    Given the entity's capital distribution journeys are removed
    And there is a capital distribution "title=Q3 2026 Exit Proceeds;income_cents=300000000;approved=false"
    Then the distribution has no journey
    When I open the capital distribution page
    Then the page should not show a journey

  # Disabled journey templates: everything is still seeded, but the admin has retired it, so a new
  # distribution gets no instance — and with no instance its page shows no journey card
  @rack_test
  Scenario: A distribution created while the journey templates are disabled gets no journey
    Given the entity's capital distribution journey templates are disabled
    And there is a capital distribution "title=Q4 2026 Exit Proceeds;income_cents=300000000;approved=false"
    Then the distribution has no journey
    And the distribution should have no workflow template
    When I open the capital distribution page
    Then the page should not show a journey

  # ── Progress hooks: the journey moves on as soon as the work is done (phase 5) ─────────────

  # H6 — Approve and Mark Payments Completed move the journey on at once
  @rack_test
  Scenario: Approving and completing payments move the journey on without anyone viewing the page
    Given there is a capital distribution "title=Q3 2026 Exit Proceeds;income_cents=300000000;approved=false"
    And both distribution review tasks are marked reviewed
    And journey activity on distributions is recorded
    When I approve the distribution through the app
    Then the distribution's journey current task should be "Mark payments completed"
    When I mark all the distribution's payments completed through the app
    Then the distribution's journey current task should be "Email investors"
    And the distribution's journey should have been re-checked
    And open pages for the distribution should have been told about the change

  # H7 — sending the notifications passes Email investors
  @rack_test
  Scenario: Sending payment notifications passes Email investors
    Given there is a capital distribution "title=Q3 2026 Exit Proceeds;income_cents=300000000;approved=true"
    And both distribution review tasks are marked reviewed
    And the distribution's payments are marked completed
    When the distribution's payment notifications are sent by the job
    Then the distribution's journey should show:
      | task            | status |
      | Email investors | passed |

  # H8 — redeeming units completes the journey
  @rack_test
  Scenario: Redeeming units completes the journey
    Given there is a capital distribution "title=Q3 2026 Exit Proceeds;income_cents=300000000;cost_of_investment_cents=150000000;approved=true"
    And both distribution review tasks are marked reviewed
    And the distribution's payments are marked completed and emailed
    When the distribution's units are redeemed by the units job
    Then the distribution's journey should be complete

  # ── Undo hooks: the journey moves back and later sign-offs are reset (phase 5) ──────────────

  # E8 — Recompute Fees after the CFO signed off moves back to Generate notices and resets the sign-off
  @rack_test
  Scenario: Recompute Fees after the CFO signed off moves back and resets the sign-off
    Given the fund has a Distribution Template
    And the Full distribution journey has a "CFO sign-off" approval step before "Approve distribution"
    And there is a capital distribution "title=Q3 2026 Exit Proceeds;income_cents=300000000;approved=false"
    And the distribution's notices are generated and 3 of them is approved
    And both distribution review tasks are marked reviewed
    And the CFO signs off on the distribution
    When the distribution's fees are recomputed by me
    Then the distribution's journey current task should be "Generate notices"
    And the distribution's journey message for "Generate notices" should be "Fees were recomputed after the notices were generated — unapprove them on the Documents screen, then click Generate Documents"
    And the CFO vote on step "CFO sign-off" should be archived

  # E9 — unticking Completed on one payment moves back to Mark payments completed
  @rack_test
  Scenario: Unticking a payment's Completed box moves the journey back
    Given there is a capital distribution "title=Q3 2026 Exit Proceeds;income_cents=300000000;approved=true"
    And both distribution review tasks are marked reviewed
    And the distribution's payments are marked completed
    And the distribution's journey is evaluated
    When I untick Completed on one of the distribution's payments through the app
    Then the distribution's journey current task should be "Mark payments completed"
    And the history should show "regressed" for step "Mark payments completed"

  # E10 — deleting a payment moves back to Create payments
  @rack_test
  Scenario: Deleting a payment moves the journey back to Create payments
    Given there is a capital distribution "title=Q3 2026 Exit Proceeds;income_cents=300000000;approved=false"
    And both distribution review tasks are marked reviewed
    When I delete one of the distribution's payments through the app
    Then the distribution's journey current task should be "Create payments"

  # E11 — regenerating notices after some were approved is an undo, and resets the later review
  @rack_test
  Scenario: Regenerating notices keeps the journey on Approve notices and resets the review
    Given the fund has a Distribution Template
    And there is a capital distribution "title=Q3 2026 Exit Proceeds;income_cents=300000000;approved=false"
    And the distribution's notices are generated and 3 of them is approved
    And both distribution review tasks are marked reviewed
    When I unapprove one of the distribution's notices through the app
    And the distribution's notices are regenerated by the doc job
    Then the distribution's journey current task should be "Approve notices"
    And the history should show "regressed" for step "Approve notices"
    And the "Review custom notification" confirmation on the distribution should have been reset

  # E12 — unapproving one notice moves back to Approve notices
  @rack_test
  Scenario: Unapproving a notice moves the journey back to Approve notices
    Given the fund has a Distribution Template
    And there is a capital distribution "title=Q3 2026 Exit Proceeds;income_cents=300000000;approved=false"
    And the distribution's notices are generated and 3 of them is approved
    And both distribution review tasks are marked reviewed
    When I unapprove one of the distribution's notices through the app
    Then the distribution's journey current task should be "Approve notices"

  # E13 — deleting redeemed units moves back to Redeem units
  @rack_test
  Scenario: Deleting redeemed units moves the journey back to Redeem units
    Given there is a capital distribution "title=Q3 2026 Exit Proceeds;income_cents=300000000;cost_of_investment_cents=150000000;approved=true"
    And both distribution review tasks are marked reviewed
    And the distribution's payments are marked completed and emailed
    And the commitments of the fund have unit type "Series A"
    And the distribution's units are redeemed by the units job
    When I delete the distribution's redeemed units in bulk
    Then the distribution's journey current task should be "Redeem units"

  # E14 — editing the fund's distribution email resets both reviews on a distribution not yet emailed,
  # and leaves one that was already emailed alone
  @rack_test
  Scenario: Editing the distribution email resets the reviews only where investors were not yet emailed
    Given the fund has a distribution email
    And there is a capital distribution "title=Q3 2026 Exit Proceeds;income_cents=300000000;approved=false"
    And both distribution review tasks are marked reviewed
    And I remember this distribution as "pending"
    And there is a capital distribution "title=Q2 2026 Exit Proceeds;income_cents=300000000;approved=true"
    And both distribution review tasks are marked reviewed
    And the distribution's payments are marked completed and emailed
    And I remember this distribution as "emailed"
    When I edit the fund's distribution email
    Then on distribution "pending" the journey current task should be "Review custom notification"
    And on distribution "pending" the journey message for "Review custom notification" should be "Email template changed after review"
    And on distribution "emailed" the "Review custom notification" confirmation should still be recorded

  # E15 — changing the distribution date recomputes the fees and moves back like Recompute Fees
  @rack_test
  Scenario: Changing the distribution date moves the journey back to Generate notices
    Given the fund has a Distribution Template
    And there is a capital distribution "title=Q3 2026 Exit Proceeds;income_cents=300000000;approved=false"
    And the distribution's notices are generated and 3 of them is approved
    And both distribution review tasks are marked reviewed
    When I change the distribution's date through the app
    Then the distribution's journey current task should be "Generate notices"

  # E18 — approving notices by date range re-checks each distribution once
  @rack_test
  Scenario: Approving notices by date range re-checks each distribution once
    Given the fund has a Distribution Template
    And there is a capital distribution "title=Q3 2026 Exit Proceeds;income_cents=300000000;approved=false"
    And the distribution's notices are generated and 0 of them is approved
    And the distribution's journey is evaluated
    And journey activity on distributions is recorded
    When the distribution notices are approved by date range
    Then the distribution's journey should have been re-checked once
    And the distribution's journey current task should be "Review custom notification"

  # E19 — no journey, no work: approving notices of a distribution without a journey evaluates nothing
  Scenario: Approving notices of a distribution without a journey re-checks nothing
    Given the entity's capital distribution journeys are removed
    And the fund has a Distribution Template
    And there is a capital distribution "title=Q3 2026 Exit Proceeds;income_cents=300000000;approved=false"
    And the distribution's notices are generated and 0 of them is approved
    And journey activity on distributions is recorded
    When the distribution notices are approved by date range
    Then the distribution's journey should not have been re-checked
    And the distribution has no journey

  # E21 — a distribution with a journey (and no units) can still be deleted
  @rack_test
  Scenario: A distribution with a journey can be deleted
    Given there is a capital distribution "title=Q3 2026 Exit Proceeds;income_cents=300000000;approved=false"
    And the distribution's journey is evaluated
    When I delete the distribution through the app
    Then the distribution and its journey should be gone
