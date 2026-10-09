Feature: Investor KYC journey — end to end, fund user and investor
  One KYC walked from creation to verified, with the fund user and the investor each doing their own
  part: the fund user checks the email and previews it as the investor will receive it, then sends the
  form; the investor opens their own emailed link and submits with their documents; the fund user then
  validates the documents, screens AML, reviews, signs off and verifies. The per-task features prove
  each check in isolation — this one proves the eleven tasks hand over to each other in a browser,
  and that the investor never sees the journey.
  Worked examples H5, X3 in openspec/changes/investor-kyc-email-review-steps/design.md#worked-examples

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;enable_kycs=true"
    And the user has role "company_admin"
    And there is an existing investor "" with "1" users
    And the entity's investor KYC journeys are removed
    And the entity's investor KYC journeys are seeded
    # The names the KYC form's own upload fields produce ("Upload PAN / Tax ID", "Upload Address
    # Proof"), so the investor filling the form really does satisfy the company's required list
    And the entity requires the individual KYC documents "PAN / Tax ID, Address Proof"
    And AML is enabled for the entity
    And the entity has a KYC email "Complete your KYC for Urban Fund"
    And I am the approver on the Compliance sign-off
    And there is an individual KYC for the investor

  # H5 — the whole journey, both actors
  Scenario: A KYC goes all the way to verified, the fund user and the investor each doing their part
    # The email gate: the journey asks about the email before it asks anyone to send anything
    When I open the KYC page
    Then the KYC journey panel should be shown
    And the panel should say "Your KYC email \"Complete your KYC for Urban Fund\" will be sent — check it and mark reviewed"
    And the panel review action "View notification" should open the entity's KYC email in a new tab
    When I click Mark reviewed in the journey panel
    Then the panel should say "Preview the email as"
    And the panel review action "Preview KYC Required Notification" should click "investor_kyc_preview_notify_kyc_required_custom_0_btn"
    When I click Mark reviewed in the journey panel
    Then the step bar should show:
      | task              | mark |
      | Set up KYC email  | ✓    |
      | Preview the email | ✓    |
      | Send KYC form     | ●    |

    # The fund user sends the form. The two confirmations keep their ✓ — they were genuinely done,
    # and the skip rule only stands tasks aside that were never confirmed (E1)
    When I click the KYC panel action and proceed
    Then the step bar should show:
      | task              | mark |
      | Set up KYC email  | ✓    |
      | Preview the email | ✓    |
      | Send KYC form     | ✓    |
      | Submit KYC        | ●    |
    And the investor user receives a KYC email

    # The investor's turn, through their own emailed link — and they see no journey (X3)
    When I open the KYC edit page as the investor via a valid signed link
    Then the KYC journey panel should not be shown
    Given I fill the kyc form
    And I click "Submit KYC" and confirm the dialog
    Then the investor kyc submission_status should be "completed"

    # Back to the fund user: the submission and its documents have moved the journey on
    When I switch back to the fund user's session
    And I open the KYC page
    Then the step bar should show:
      | task                      | mark |
      | Submit KYC                | ✓    |
      | Upload required documents | ✓    |
      | Validate documents        | ●    |

    # Documents checked by hand, then the AML result arrives
    When I click Mark reviewed in the journey panel
    Then the step bar should show:
      | task               | mark |
      | Validate documents | ✓    |
      | Run AML screening  | ●    |
    When the KYC's AML result arrives as "no_match" while the page is open
    Then without reloading, the step bar should show:
      | task              | mark |
      | Run AML screening | ✓    |
      | Clear AML match   | n/a  |
      | Review KYC        | ●    |

    # Review, sign-off, verify
    When I click Mark reviewed in the journey panel
    Then the step bar should show:
      | task                | mark |
      | Review KYC          | ✓    |
      | Compliance sign-off | ●    |
    When I sign off the KYC's Compliance sign-off
    And I open the KYC page
    Then the panel action "Verify" should click "investor_kyc_toggle_verified_btn"
    When I click the KYC panel action
    Then the KYC should be verified
    And the KYC's journey should be complete
    And the KYC's journey should show:
      | task                      | status | message                            |
      | Set up KYC email          | passed |                                    |
      | Preview the email         | passed |                                    |
      | Send KYC form             | passed |                                    |
      | Submit KYC                | passed |                                    |
      | Upload required documents | passed |                                    |
      | Validate documents        | passed |                                    |
      | Run AML screening         | passed |                                    |
      | Review KYC                | passed |                                    |
      | Verify KYC                | passed |                                    |
