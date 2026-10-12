Feature: Capital distribution journey — the distribution page
  A distribution with a journey shows the step bar (every task by name with its mark), a "What's needed
  now" panel whose button runs the real control in the Actions menu, readiness warnings until investors
  are emailed, and a "View Generated Notices To Approve" link that opens this distribution's unapproved
  notices in a new window. The panel is only for people who can see the distribution.
  Worked examples H3, H4, H5, E6, E16, E17, E22, X6 in openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
  UI journey J2.1–J2.6 in openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#what-users-see

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
    And the fund has a Distribution Template
    And there is a capital distribution "title=Q3 2026 Exit Proceeds;income_cents=300000000;approved=false"

  # H3 — panel while notices are partly approved; its button clicks the Actions menu link
  @rack_test
  Scenario: The panel shows how many notices await approval and links to them
    Given the distribution's notices are generated and 1 of them is approved
    When I open the distribution's journey page
    Then the step bar should show:
      | task             | mark |
      | Create payments  | ✓    |
      | Generate notices | ✓    |
      | Approve notices  | ●    |
      | Review custom notification | ○    |
    And the panel should say "Approve notices: 2 of 3 notices await approval"
    And the panel action "View notices to approve" should click "capital_distribution_view_notices_to_approve_btn"

  # H4 — Mark reviewed on the page moves the journey on (J2.4)
  @rack_test
  Scenario: Mark reviewed on the page moves the journey on
    Given the distribution's notices are generated and 3 of them is approved
    When I open the distribution's journey page
    Then the panel should say "Review custom notification: No custom notification is set up"
    And the panel review action "New Distribution Notification" should go to "/custom_notifications/new" in this tab
    When I click Mark reviewed in the journey panel
    Then the panel should say "Check preview: On the Payments tab, open a payment and choose Preview Notification"
    And the panel review action "Open payments" should click "#payments-tab"

  # Review custom notification names the distribution's own notification and opens it in a new tab
  @rack_test
  Scenario: Review custom notification shows the distribution's own notification in a new tab
    Given the distribution's notices are generated and 3 of them is approved
    And there is a custom notification for the capital distribution with subject "Your distribution" with email_method "send_notification"
    When I open the distribution's journey page
    Then the panel should say "Distribution email \"Your distribution\" (set on this distribution) will be sent"
    And the panel review action "View notification" should go to the custom notification in a new tab

  # H5 — the panel's Approve runs the Actions menu's Approve and its confirmation (J2.5)
  Scenario: The panel action runs the distribution's own Approve button
    Given the distribution's notices are generated and 3 of them is approved
    And both distribution review tasks are marked reviewed
    When I open the distribution's journey page
    Then the panel action "Approve" should click "capital_distribution_approve_btn"
    When I click the panel action and proceed
    Then the distribution should be approved by me
    And the panel should say "Mark payments completed: 0 of 3 payments marked completed"

  # E6 — readiness warnings until investors are emailed (J2.6)
  @rack_test
  Scenario: Readiness warnings show until investors are emailed
    Given 1 commitment of the distribution is set to skip doc gen
    And 1 investor of the distribution has nobody subscribed to Distribution emails
    When I open the distribution's journey page
    Then the panel should warn "1 commitment has Skip Doc Gen set and will not be emailed"
    And the panel should warn "1 investor has nobody subscribed to Distribution emails"
    Given the distribution's investors have been emailed
    When I open the distribution's journey page
    Then the panel should not show any warnings

  # E22 — the notices link opens only this distribution's unapproved notices, in a new window
  Scenario: View Generated Notices To Approve opens this distribution's unapproved notices in a new window
    Given the distribution's notices are generated and 1 of them is approved
    And another distribution of the fund has an unapproved notice
    When I open the distribution's journey page
    And I open the distribution's Actions menu
    Then "View Generated Notices To Approve" should open a new window listing 2 notices with the approval hint
    And the distribution page should still be open in the original window

  # X6 — a user of another company can't load the journey panel
  @rack_test
  Scenario: A user of another company cannot load the distribution's journey panel
    Given the distribution belongs to another company
    When I load the distribution's journey panel directly
    Then I should see "Access Denied" on the page

  # E16 — real time: the panel updates itself when the notice job finishes (no reload)
  Scenario: The step bar updates by itself when the distribution's notices are generated
    When I open the distribution's journey page
    Then the step bar should show:
      | task             | mark |
      | Generate notices | ●    |
    When the distribution's notices are generated by the doc job while the page is open
    Then without reloading, the step bar should show:
      | task             | mark |
      | Generate notices | ✓    |
      | Approve notices  | ●    |

  # E17 — a colleague completing the payments elsewhere updates the open page
  Scenario: The step bar updates by itself when a colleague marks the payments completed
    Given the distribution is approved and reviewed with notices approved
    When I open the distribution's journey page
    Then the step bar should show:
      | task                    | mark |
      | Mark payments completed | ●    |
    When a colleague marks the distribution's payments completed while the page is open
    Then without reloading, the step bar should show:
      | task                    | mark |
      | Mark payments completed | ✓    |
      | Email investors         | ●    |

  # A journey finished a day or more ago gets out of the way: the card is hidden and the breadcrumb's
  # journey icon (next to Favourites and User Guide) brings it back for anyone who wants to look at it
  Scenario: A journey complete since yesterday is hidden until the breadcrumb's journey icon is clicked
    Given there is a capital distribution "title=Q4 2026 Exit Proceeds;income_cents=300000000;cost_of_investment_cents=150000000;approved=true"
    And the distribution's notices are generated and 3 of them is approved
    And both distribution review tasks are marked reviewed
    And the distribution's payments are marked completed and emailed
    And the distribution's units are redeemed by the units job
    And the distribution's journey was completed 2 days ago
    When I open the distribution page
    Then the journey card should be hidden
    When I click the breadcrumb's journey icon
    Then the journey card should be visible
    And the step bar should show:
      | task                    | mark |
      | Create payments         | ✓    |
      | Mark payments completed | ✓    |
    When I click the breadcrumb's journey icon
    Then the journey card should be hidden

  # The moment it finishes, the journey is still there to be seen — only the icon is new
  Scenario: A journey that has just completed stays on the page and can be put away
    Given there is a capital distribution "title=Q4 2026 Exit Proceeds;income_cents=300000000;cost_of_investment_cents=150000000;approved=true"
    And the distribution's notices are generated and 3 of them is approved
    And both distribution review tasks are marked reviewed
    And the distribution's payments are marked completed and emailed
    And the distribution's units are redeemed by the units job
    When I open the distribution page
    Then the journey card should be visible
    And the journey card should say the journey is complete
    When I click the breadcrumb's journey icon
    Then the journey card should be hidden

  # Nothing changes while there is still work to do: no icon, card where it has always been
  Scenario: An unfinished journey shows its card and no breadcrumb journey icon
    When I open the distribution's journey page
    Then the journey card should be visible
    And the breadcrumb should not offer the journey icon
