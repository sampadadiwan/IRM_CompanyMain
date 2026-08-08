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
    When I visit the contact page for "ops@lp.com"
    Then the contact tabs should not show the note "Discussed side letter terms"

  Scenario: Set the engagement status on a stakeholder
    When I set the stakeholder engagement status to "Due Diligence"
    Then the investor engagement status should be "Due Diligence"

  Scenario: Import contacts with CRM custom field columns
    When I upload a stakeholder users file with CRM columns for "import.crm@lp.com"
    Then the imported contact "import.crm@lp.com" should be unapproved with designation "COO", POC role "Finance" and intro "Met via bulk import"
    And the entity should have the LP CRM custom fields configured
