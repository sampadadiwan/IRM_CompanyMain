Feature: Deal Grid Columns
  A deal can have per-deal column configuration for the investor grid.
  Configured columns are additive (base columns always show) and support custom labels and position (Start / End).

Scenario: Configure grid columns when creating a deal and verify they appear in the investor grid
  Given Im logged in as a user "" for an entity "entity_type=Company"
  Given the user has role "company_admin"
  And I am at the deals page
  When I create a new deal "name=Grid Column Deal;amount_cents=50000"
  Then I should see the "Deal was successfully created"
  And an deal should be created
  When I edit the deal grid columns with field "primary_amount" label "Inv Amount" and position "End"
  Then I should see the "Deal was successfully updated"
  And I visit the deal list view
  Then the investor grid should show the column "Inv Amount"
  And the investor grid should show the base column "Status"

Scenario: Configure multiple grid columns with mixed positions
  Given Im logged in as a user "" for an entity "entity_type=Company"
  Given the user has role "company_admin"
  And I am at the deals page
  When I create a new deal "name=Multi Column Deal;amount_cents=75000"
  Then I should see the "Deal was successfully created"
  And an deal should be created
  When I add grid column with field "primary_amount" label "Raised" and position "Start"
  And I add grid column with field "secondary_investment" label "Secondary" and position "End"
  And I save the deal form
  Then I should see the "Deal was successfully updated"
  And I visit the deal list view
  Then the investor grid should show the column "Raised"
  And the investor grid should show the column "Secondary"
  And the investor grid should show the base column "Status"

Scenario: Editing grid columns updates the investor grid
  Given Im logged in as a user "" for an entity "entity_type=Company"
  Given the user has role "company_admin"
  And I am at the deals page
  When I create a new deal "name=Edit Column Deal;amount_cents=30000"
  Then I should see the "Deal was successfully created"
  And an deal should be created
  When I edit the deal grid columns with field "primary_amount" label "Old Label" and position "End"
  Then I should see the "Deal was successfully updated"
  And I visit the deal list view
  Then the investor grid should show the column "Old Label"
  When I edit the deal grid columns with field "primary_amount" label "New Label" and position "End"
  Then I should see the "Deal was successfully updated"
  And I visit the deal list view
  Then the investor grid should show the column "New Label"
  And the investor grid should not show the column "Old Label"

Scenario: Grid column configuration stores expected table size
  Given Im logged in as a user "" for an entity "entity_type=Company"
  Given the user has role "company_admin"
  And I am at the deals page
  When I create a new deal "name=Grid Size Deal;amount_cents=82000"
  Then I should see the "Deal was successfully created"
  And an deal should be created
  When I add grid column with field "primary_amount" label "Raised" and position "Start"
  And I add grid column with field "secondary_investment" label "Secondary" and position "End"
  And I save the deal form
  Then I should see the "Deal was successfully updated"
  And the deal should store 2 grid columns

Scenario: Deal with no grid columns configured shows all standard columns
  Given Im logged in as a user "" for an entity "entity_type=Company"
  Given the user has role "company_admin"
  And I am at the deals page
  When I create a new deal "name=Default Column Deal;amount_cents=20000"
  Then I should see the "Deal was successfully created"
  And an deal should be created
  And I visit the deal list view
  Then the investor grid should show the base column "Status"
  And the investor grid should show the base column "Tier"
  And the investor grid should show the base column "Health"
