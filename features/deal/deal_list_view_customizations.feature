Feature: Deal List View Customizations
  Deal admins can configure which analytics cards are shown and list view navigation
  should safely break out of sidepanel/frame contexts.

Scenario: Deal analytics stats selection is persisted and reflected on list view
  Given Im logged in as a user "" for an entity "entity_type=Company"
  Given the user has role "company_admin"
  And I am at the deals page
  When I create a new deal "name=Analytics Config Deal;amount_cents=50000"
  Then I should see the "Deal was successfully created"
  And an deal should be created
  When I edit the deal analytics stats to "Primary Amount=Primary Raise, Secondary Amount=Secondary Raise"
  Then I should see the "Deal was successfully updated"
  And the deal should have analytics stats "primary_amount, secondary_amount"
  And I visit the deal list view
  Then the deal analytics card "Primary Raise" should be visible
  And the deal analytics card "Secondary Raise" should be visible
  And the deal analytics card "Total of Deal Amount" should not be visible
  And the deal analytics card "Completed %" should not be visible
  And the deal analytics card "Number of Deal Investors" should not be visible

Scenario: Deal analytics card descriptions remain visible
  Given Im logged in as a user "" for an entity "entity_type=Company"
  Given the user has role "company_admin"
  And I am at the deals page
  When I create a new deal "name=Analytics Description Deal;amount_cents=65000"
  Then I should see the "Deal was successfully created"
  And an deal should be created
  When I edit the deal analytics stats to "Total Target=Total Target"
  Then I should see the "Deal was successfully updated"
  And I visit the deal list view
  Then the deal analytics description should include "The deal's total fundraising target"

Scenario: List view sidepanel and documents navigation are configured for top-level navigation
  Given Im logged in as a user "" for an entity "entity_type=Company"
  Given the user has role "company_admin"
  And I am at the deals page
  When I create a new deal "name=Sidepanel Nav Deal;amount_cents=42000"
  Then I should see the "Deal was successfully created"
  And an deal should be created
  And there is an existing investor ""
  And there is a deal investor for the last investor
  When I fetch the deal investor sidepanel content
  Then the deal list sidepanel frame should target top
  When I visit the deal documents folder page
  Then the All Documents button should target top
  And the documents frame should target top
