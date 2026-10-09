Feature: Capital call page refreshes itself when remittances are generated
  Remittances are created by CapitalCallJob in the background after a call is created, and the
  call's totals only settle when CapitalRemittancesCountersJob runs after it. An open call page
  shows a "Generating remittances… N of M" line while the job runs, reloads its Remittances tab and
  its stats cards, and the user who started the job gets a notice when it ends — so nobody has to
  refresh the page by hand. See CapitalCallJob (progress) and CapitalCall#broadcast_remittances_change.

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;enable_funds=true;currency=INR"
    And the user has role "company_admin"
    And there is an existing investor "" with "1" users
    And there is an existing investor "" with "1" users
    And there is a fund "name=Alpha Fund I" for the entity
    And the investors are added to the fund
    And there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And there is a capital call "name=Q3 Call;percentage_called=10" whose remittances are not generated yet

  Scenario: The remittances list and the stats cards fill in without a reload, and the user is told
    When I open the call page
    Then the call page should show no remittances
    When I generate the call's remittances while the page is open
    Then without reloading, the call page should show each of the call's remittances
    And without reloading, the call page's "Called" card should show the call's call amount
    And I should see an "info" alert "Remittances generated for Q3 Call: 2 created."

  Scenario: The progress line counts up while the job runs and goes away when it ends
    Given remittance generation reports progress after every commitment
    When I open the call page
    And I watch the call page's progress line
    When I generate the call's remittances while the page is open
    Then the progress line should have shown "Generating remittances… 1 of 2"
    And the progress line should have shown "Generating remittances… 2 of 2"
    And the progress line should be empty
    And without reloading, the call page should show each of the call's remittances

  Scenario: A page opened while the job is running shows how far it has got
    Given remittance generation for the call is 1 of 2 done
    When I open the call page
    Then I should see "Generating remittances… 1 of 2" on the page

  Scenario: Remittances that fail to save are reported in a warning
    Given the remittance for the first commitment will fail to save
    When I open the call page
    And I generate the call's remittances while the page is open
    Then I should see a "warning" alert "Q3 Call: 1 of 2 remittances created, 1 failed."

  Scenario: Remittances that already exist are counted, not created again
    Given the call's remittances are generated
    When I open the call page
    And I generate the call's remittances while the page is open
    Then I should see an "info" alert "Remittances generated for Q3 Call: 0 created, 2 already present."

  Scenario: A filter the user applied to the remittances list survives the refresh
    When I open the call page
    And I filter the call's remittances by payment status "Pending"
    When I generate the call's remittances while the page is open
    Then without reloading, the call page should show each of the call's remittances
    And the remittances list should still be filtered by payment status "Pending"

  Scenario: A user without access cannot load the call's stats cards
    Given the capital call belongs to another company
    When I load the call's stats cards directly
    Then I should see "Access Denied" on the page
