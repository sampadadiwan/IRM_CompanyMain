Feature: Investor KYC journey — the KYC page
  A KYC with a journey shows fund users the step bar (every task by name with its mark), a "What's
  needed now" panel whose button runs the real control on the page, a second button beside Mark
  reviewed when a review task offers one, and warnings until the KYC is verified. Investors never see
  it. The bar updates without a reload when the investor submits, a job finishes or a colleague acts.
  Worked examples H3, H4, H6, H8, E3, E15, E22, X1, X2, X5 in
  openspec/changes/investor-kyc-journey/design.md#worked-examples
  UI journey J2.1–J2.6 in openspec/changes/investor-kyc-journey/design.md#what-users-see

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;enable_kycs=true"
    And the user has role "company_admin"
    And there is an existing investor "" with "1" users
    And the entity's investor KYC journeys are removed
    And the entity's investor KYC journeys are seeded
    And the entity requires the individual KYC documents "PAN Card, Address Proof, Photo"
    And AML is enabled for the entity
    And there is an individual KYC for the investor

  # H1, H4, J1.1–J1.5 (investor-kyc-email-review-steps) — the email gate: each task's own second
  # button beside Mark reviewed, then the hand-over to "Send KYC form"
  @rack_test
  Scenario: The panel walks through the two email tasks
    Given the entity has a KYC email "Complete your KYC for Urban Fund"
    When I open the KYC page
    Then the KYC journey panel should be shown
    And the panel should say "Your KYC email \"Complete your KYC for Urban Fund\" will be sent — check it and mark reviewed"
    And the panel review action "View notification" should open the entity's KYC email in a new tab
    When I click Mark reviewed in the journey panel
    Then the step bar should show:
      | task              | mark |
      | Set up KYC email  | ✓    |
      | Preview the email | ●    |
    And the panel should say "Preview the email as"
    And the panel review action "Preview KYC Required Notification" should click "investor_kyc_preview_notify_kyc_required_custom_0_btn"
    When I click Mark reviewed in the journey panel
    Then the step bar should show:
      | task              | mark |
      | Preview the email | ✓    |
      | Send KYC form     | ●    |

  # H2 — no company email: the panel offers the form that creates one
  @rack_test
  Scenario: The panel offers to create a KYC email when the company has none
    When I open the KYC page
    Then the panel should say "No KYC email is set up — CapHive's default text will be sent. Set one up, or mark reviewed to use the default"
    And the panel review action "Custom KYC Notification" should link to the new KYC email form

  # H3, J2.1 — the panel's button sends the form through the KYC Actions item, once the gate is passed
  Scenario: The panel sends the KYC form
    Given the KYC's email tasks are confirmed
    When I open the KYC page
    Then the KYC journey panel should be shown
    And the panel should say "The KYC form has not been sent — send it, or fill it in and tick complete"
    And the panel action "Send KYC Required Notification" should click "investor_kyc_notify_kyc_required_default_btn"
    When I click the KYC panel action and proceed
    Then the step bar should show:
      | task          | mark |
      | Send KYC form | ✓    |
      | Submit KYC    | ●    |
    And the panel should say "Waiting for the investor — form sent on"

  # H4, J2.2 — the investor submits while the fund user has the page open
  Scenario: The step bar moves on when the investor submits
    Given the KYC's form link was sent
    And the KYC has the documents "PAN Card, Address Proof, Photo"
    When I open the KYC page
    And the investor submits the KYC while the page is open
    Then without reloading, the step bar should show:
      | task                      | mark |
      | Submit KYC                | ✓    |
      | Upload required documents | ✓    |
      | Validate documents        | ●    |

  # E3, J2.3, J2.4 — AI could not validate: the second button opens the Validation tab, Mark reviewed passes it
  Scenario: AI could not validate an answer — check it and mark reviewed
    Given the entity has 8 document checks on "PAN Card"
    And the KYC's form link was sent
    And the KYC is submitted
    And the KYC has the documents "PAN Card, Address Proof, Photo"
    When I open the KYC page
    And the KYC's documents finish checking with 1 of 8 items needing attention while the page is open
    Then without reloading, the step bar should show:
      | task               | mark |
      | Validate documents | ●    |
    And the panel should say "1 document item needs attention — resolve it or mark reviewed"
    And the panel review action "Open document checks" should click "#docs-validation-tab"
    When I click Mark reviewed in the journey panel
    Then the step bar should show:
      | task               | mark |
      | Validate documents | ✓    |
      | Run AML screening  | ●    |

  # H6 — the AML result arrives while the page is open
  Scenario: The step bar moves on when the AML result arrives
    Given the entity has 8 document checks on "PAN Card"
    And the KYC's form link was sent
    And the KYC is submitted
    And the KYC has the documents "PAN Card, Address Proof, Photo"
    And the KYC's documents were checked with 0 of 8 items needing attention
    When I open the KYC page
    Then the panel action "Generate AML Report" should click "investor_kyc_generate_new_aml_report_btn"
    When the KYC's AML result arrives as "no_match" while the page is open
    Then without reloading, the step bar should show:
      | task              | mark |
      | Run AML screening | ✓    |
      | Clear AML match   | n/a  |
      | Review KYC        | ●    |

  # H8 — Verify from the panel completes the journey
  Scenario: Verify from the panel completes the journey
    Given the KYC's form link was sent
    And the KYC is submitted
    And the KYC has the documents "PAN Card, Address Proof, Photo"
    And the KYC's AML result is "no_match"
    And the KYC's journey is evaluated
    And I mark "Validate documents" reviewed on the KYC
    And I mark "Review KYC" reviewed on the KYC
    When I open the KYC page
    Then the panel action "Verify" should click "investor_kyc_toggle_verified_btn"
    When I click the KYC panel action
    Then the KYC should be verified
    And the KYC's journey should be complete

  # E15 — a colleague bulk-verifies while the page is open
  Scenario: A colleague's bulk Verify updates the open page
    Given the KYC's form link was sent
    And the KYC is submitted
    And the KYC has the documents "PAN Card, Address Proof, Photo"
    When I open the KYC page
    And a colleague bulk-verifies the KYC while the page is open
    Then without reloading, the step bar should show:
      | task       | mark |
      | Verify KYC | ✓    |

  # E22, J2.6 — warnings until verified
  @rack_test
  Scenario: A failed bank verification is shown as a warning
    Given the KYC's bank verification failed
    When I open the KYC page
    Then the panel should warn "Bank account verification failed"

  # X1 — investors never see the journey
  Scenario: The investor does not see the journey
    When I open the KYC page as the investor
    Then the KYC journey panel should not be shown

  # X2 — without permission to verify, the panel's Verify is a plain link
  @rack_test
  Scenario: The panel's Verify falls back to a link when the user may not verify
    Given I may not verify KYCs
    And the KYC's form link was sent
    And the KYC is submitted
    And the KYC has the documents "PAN Card, Address Proof, Photo"
    And the KYC's AML result is "no_match"
    And the KYC's journey is evaluated
    And I mark "Validate documents" reviewed on the KYC
    And I mark "Review KYC" reviewed on the KYC
    When I open the KYC page
    Then the Verify control should not be on the page
    And the panel action should be a plain link to the KYC

  # X5 — another entity's user cannot load the panel
  @rack_test
  Scenario: A user of another entity cannot load the journey panel
    When a user of another entity requests the KYC's journey panel
    Then the journey panel request should be refused

  # The run page's flow diagram: journey steps say what completes them and who owns them instead of
  # the approver panel (quorum, actors, "If rejected"), which only applies to sign-off steps
  @rack_test
  Scenario: The run diagram shows what completes each step and who owns it
    Given I own the "Send KYC form" step of the KYC journey
    When I open the KYC's journey run page
    Then the run diagram step "Send KYC form" should show "Checked automatically"
    And the run diagram step "Send KYC form" should show my name as owner
    And the run diagram step "Validate documents" should show "Needs review"
    And the run diagram step "Send KYC form" should not show "None assigned"
    And the run diagram step "Send KYC form" should not show "If rejected"
    And the run diagram step "Compliance sign-off" should show "If rejected"

  # The List | Graph switch restyles the same diagram (workflow_flow_view_controller)
  Scenario: The run diagram switches between list and graph
    When I open the KYC's journey run page
    And I switch the run diagram to "Graph"
    Then the run diagram should be laid out as a graph
    When I switch the run diagram to "List"
    Then the run diagram should be laid out as a list
