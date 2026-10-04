Feature: Capital call journey — the call page
  The call page shows the journey as a step bar (every task by name with its mark), a
  "What's needed now" panel with the next action or Mark reviewed, and readiness warnings until the
  notices are sent. The Approve / Send confirmations don't repeat the journey — the panel is on the page.
  Worked examples H3, H12, H18, E6, E27 in openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;enable_funds=true;currency=INR"
    And the user has role "company_admin"
    And the user has role "approver"
    And there is an existing investor "" with "1" users
    And there is an existing investor "" with "1" users
    And there is an existing investor "" with "1" users
    And there is a fund "name=Alpha Fund I" for the entity
    And the investors are added to the fund
    And there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And each investor has a "verified" kyc linked to the commitment
    And the entity's capital call journeys are seeded
    And the fund has capital call template
    And there is a capital call "percentage_called=10"

  # H3 — Panel while notices are partly approved
  Scenario: The panel shows how many notices await approval and links to them
    Given the call's notices are generated and 1 of them is approved
    When I open the capital call page
    Then the step bar should show:
      | task               | mark |
      | Create remittances | ✓    |
      | Generate notices   | ✓    |
      | Approve notices    | ●    |
      | Review custom notification | ○    |
    And the panel should say "Approve notices: 2 of 3 call notices await approval"
    And the panel action "View notices to approve" should click "capital_call_view_notices_to_approve_btn"

  # Mark reviewed through the page (J2.4)
  Scenario: Mark reviewed on the page moves the journey on
    Given the call's notices are generated and approved
    When I open the capital call page
    And I click Mark reviewed in the journey panel
    Then the panel should say "Check preview: On the Remittances tab, open a remittance's Actions menu and choose Preview Notification"

  # Review custom notification names the call email that will go out and links to it (new tab), or
  # offers the call's New Call Notification form when there is none; Mark reviewed stays beside it
  Scenario: Review custom notification with no custom notification offers to create one
    Given the call's notices are generated and approved
    When I open the capital call page
    Then the panel should say "Review custom notification: No custom notification is set up"
    And the panel review action "New Call Notification" should go to "/custom_notifications/new" in this tab
    And I should see the Mark reviewed button in the journey panel

  Scenario: Review custom notification shows the call's own notification in a new tab
    Given the call's notices are generated and approved
    And there is a custom notification for the capital call with subject "Your capital call" with email_method "notify_capital_remittance"
    When I open the capital call page
    Then the panel should say "Call email \"Your capital call\" (set on this call) will be sent"
    And the panel review action "View notification" should go to the custom notification in a new tab

  # Check preview says where the per-remittance preview is and opens the Remittances tab
  Scenario: Check preview points at each remittance's Preview Notification
    Given the call's notices are generated and approved
    When I open the capital call page
    And I click Mark reviewed in the journey panel
    Then the panel review action "Open remittances" should click "#remittances-tab"

  # H12 — Advisory only: Approve proceeds with earlier tasks outstanding, and its confirmation
  # doesn't repeat them (the step bar on the page already shows them)
  Scenario: Approve proceeds with outstanding journey tasks and its confirmation does not list them
    Given the call's notices are generated and approved
    When I open the capital call page
    Then the step bar should show:
      | task         | mark |
      | Review custom notification | ●    |
    When I click Approve in the call's Actions menu
    Then the confirmation should not mention journey steps
    When I confirm the dialog
    Then the call should be approved

  # H18 (J2.5) — the panel's action drives the real control on this page, not a reload of it
  Scenario: The panel action runs the call's own Approve button
    Given the call's notices are generated and approved
    And the call's journey is evaluated
    And both review tasks are marked reviewed
    When I open the capital call page
    Then the panel action "Approve" should click "capital_call_approve_btn"
    When I click the panel action
    Then the confirmation should not mention journey steps
    When I confirm the dialog
    Then the call should be approved

  # H18 (J2.3) — Approve notices drives the Actions menu's "View Generated Notices To Approve" link, which opens
  # the notices still awaiting approval in a new window (the call page stays put)
  Scenario: The panel action for notices opens the notices to approve in a new window
    Given the call's notices are generated and 1 of them is approved
    When I open the capital call page
    Then the panel action "View notices to approve" should click "capital_call_view_notices_to_approve_btn"
    When I click the panel action, a new window should open on the notices awaiting approval
    And the call page should still be open in the original window

  # E6, E27 — Readiness warnings until notices are sent
  Scenario: Readiness warnings show before sending and disappear after
    Given 1 commitment on the call is set to skip doc gen
    And 1 investor on the call has nobody subscribed to Capital Call emails
    When I open the capital call page
    Then the panel should warn "1 commitment has Skip Doc Gen set and will not be emailed"
    And the panel should warn "nobody subscribed to Capital Call emails"
    Given the call's notices are marked sent
    When I open the capital call page
    Then the panel should not show any warnings

  # J2.2 — real time: the panel updates itself when notice generation finishes (no reload)
  Scenario: The step bar updates by itself when the call's notices are generated
    When I open the capital call page
    Then the step bar should show:
      | task             | mark |
      | Generate notices | ●    |
    When the call's notices are generated by the doc job while the page is open
    Then without reloading, the step bar should show:
      | task             | mark |
      | Generate notices | ✓    |
      | Approve notices  | ●    |

  # J2.2 — a sign-off given elsewhere (the CFO's session) updates the open page
  Scenario: The step bar updates by itself when the CFO signs off elsewhere
    Given the Full journey has a "CFO sign-off" approval step before "Approve call"
    And there is a capital call "name=Second call;percentage_called=5"
    And the call is ready for sign-off
    When I open the capital call page
    Then the step bar should show:
      | task         | mark |
      | CFO sign-off | ●    |
    When the CFO signs off on the call while the page is open
    Then without reloading, the step bar should show:
      | task         | mark |
      | CFO sign-off | ✓    |
      | Approve call | ●    |

  # A journey finished a day or more ago gets out of the way: the card is hidden and the breadcrumb's
  # journey icon (next to Favourites and User Guide) brings it back for anyone who wants to look at it
  Scenario: A journey complete since yesterday is hidden until the breadcrumb's journey icon is clicked
    Given the call's journey is complete
    And the call's journey was completed 2 days ago
    When I open the call page
    Then the journey card should be hidden
    When I click the breadcrumb's journey icon
    Then the journey card should be visible
    And the step bar should show:
      | task              | mark |
      | Collect payments  | ✓    |
      | Verify remittances| ✓    |
      | Allocate units    | n/a  |
    When I click the breadcrumb's journey icon
    Then the journey card should be hidden

  # The moment it finishes, the journey is still there to be seen — only the icon is new
  Scenario: A journey that has just completed stays on the page and can be put away
    Given the call's journey is complete
    When I open the call page
    Then the journey card should be visible
    And the journey card should say the journey is complete
    When I click the breadcrumb's journey icon
    Then the journey card should be hidden

  # Nothing changes while there is still work to do: no icon, card where it has always been
  Scenario: An unfinished journey shows its card and no breadcrumb journey icon
    When I open the capital call page
    Then the journey card should be visible
    And the breadcrumb should not offer the journey icon
