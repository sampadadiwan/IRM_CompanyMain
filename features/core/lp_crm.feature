Feature: LP CRM
  Track prospective-LP relationships using existing building blocks:
  contacts are InvestorAccess records (approved=false, custom fields for details),
  notes/tasks link to a contact via touch_point, and the contact show page
  surfaces that history as tabs.
  See docs/features/lp_relationship_crm_alt_mvp_prd.md

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Company"
    And the user has role "company_admin"
    And the LP CRM custom fields are seeded
    And there is an existing investor ""

  Scenario: Seeding the CRM custom fields is idempotent
    Then the entity should have the LP CRM custom fields configured
    When the LP CRM custom fields are seeded
    Then the entity should have the LP CRM custom fields configured

  Scenario: Add a contact-only person with CRM details
    Given I am at the stakeholder details page
    And I click on "New Users"
    And I fill the investor access form with "email=cfo@lp.com;first_name=Jane;last_name=Cfo;approved=false"
    And I fill the contact custom fields with designation "CFO", POC role "Decision Maker" and intro "Met at the Delhi summit"
    And I click on "Save"
    Then I should see the "Added cfo@lp.com to investor users"
    And the contact "cfo@lp.com" should be stored unapproved with designation "CFO" and POC role "Decision Maker"
    And no access email should have been sent to "cfo@lp.com"
    When I visit the contact page for "cfo@lp.com"
    Then I should see the contact details "CFO", "Decision Maker" and "Met at the Delhi summit"
    And I should see the "Notes" and "Tasks" tabs but no "Fund Access" tab

  Scenario: Log a note and a task against a touch point from the contact tabs
    Given there is a contact "cfo@lp.com" named "Jane Cfo" for the investor
    And there is a contact "ops@lp.com" named "Omar Ops" for the investor
    When I visit the contact page for "cfo@lp.com"
    And I add a note "Discussed side letter terms" from the contact Notes tab
    Then the note "Discussed side letter terms" should be linked to the contact "cfo@lp.com"
    And I should see "Jane Cfo" in the notes list
    When I add a task "Send the fund deck" from the contact Tasks tab
    Then the task "Send the fund deck" should be linked to the contact "cfo@lp.com"
    And the note and task show pages should link "Jane Cfo" back to the contact
    When I visit the contact page for "ops@lp.com"
    Then the contact tabs should not show the note "Discussed side letter terms"

  # Deal-side touch points: a DealInvestor offers its parent LP's contacts, so a
  # conversation logged inside a deal names the same person as one logged on the
  # LP record — and shows up in that person's history on the contact page.
  Scenario: Log a deal note and task against a touch point from the LP's contacts
    Given there is a contact "cfo@lp.com" named "Jane Cfo" for the investor
    And the investor is in an open deal
    When I add a note "Term sheet walkthrough" against the deal investor with touch point "cfo@lp.com"
    Then the note "Term sheet walkthrough" should be linked to the contact "cfo@lp.com" and owned by the deal investor
    When I add a task "Send the revised term sheet" against the deal investor with touch point "cfo@lp.com"
    Then the task "Send the revised term sheet" should be linked to the contact "cfo@lp.com" and owned by the deal investor
    When I visit the contact page for "cfo@lp.com"
    Then the contact Notes tab should show the deal note "Term sheet walkthrough"
    And the contact Tasks tab should show the deal task "Send the revised term sheet"

  Scenario: A contact of another stakeholder cannot be a deal touch point
    Given there is a contact "cfo@lp.com" named "Jane Cfo" for the investor
    And the investor is in an open deal
    And there is a contact "other@elsewhere.com" named "Otto Other" for a different stakeholder
    Then the deal investor note form should not offer the contact "other@elsewhere.com"
    And a note on the deal investor with touch point "other@elsewhere.com" should be rejected

  # The create stream prepends the new row into the list on screen; a note saved
  # without the contact that list is filtered to must not be prepended, or it
  # sits there looking like it belongs until the next reload.
  Scenario: A note saved without the touch point does not linger in the contact's list
    Given there is a contact "cfo@lp.com" named "Jane Cfo" for the investor
    When I visit the contact page for "cfo@lp.com"
    And I add a note "General fund update" from the contact Notes tab without a touch point
    Then the contact tabs should not show the note "General fund update"
    And the note "General fund update" should have no touch point

  Scenario: Set the engagement status on a stakeholder
    When I set the stakeholder engagement status to "Due Diligence"
    Then the investor engagement status should be "Due Diligence"

  Scenario: Import contacts with CRM custom field columns
    When I upload a stakeholder users file with CRM columns for "import.crm@lp.com"
    Then the imported contact "import.crm@lp.com" should be unapproved with designation "COO", POC role "Finance" and intro "Met via bulk import"
    And the entity should have the LP CRM custom fields configured
