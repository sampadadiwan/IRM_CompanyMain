Feature: Deleting an investor deletes its fund ratios

Background:
  Given Im logged in as a user "first_name=Admin" for an entity "entity_type=Investment Fund;enable_funds=true"
  And the user has role "company_admin"
  And there is a fund "name=Fund A" for the entity
  And there is an existing investor "name=Pepkit Media Pvt Ltd"

Scenario: H1 Delete with confirmation removes the investor and its fund ratios
  Given the investor has 4 fund ratios
  When I open the investor page
  And I click delete on the investor page
  Then the confirmation popup says "Deleting this investor will also delete its 4 associated fund ratios. Proceed?"
  When I confirm the popup
  Then I should see the "Stakeholder was successfully deleted."
  And the investor now has 0 fund ratios

@rack_test
Scenario: H2 Fund ratios are soft deleted
  Given the investor has 4 fund ratios
  When the investor is deleted
  Then the investor's 4 fund ratios are soft deleted

Scenario: E1 Cancel keeps the investor and ratios
  Given the investor has 4 fund ratios
  When I open the investor page
  And I click delete on the investor page
  And I cancel the popup
  Then the investor still exists
  And the investor now has 4 fund ratios

Scenario: E2 Investor without ratios
  When I open the investor page
  And I click delete on the investor page
  Then the confirmation popup says "This will permanently delete this item. Proceed?"
  When I confirm the popup
  Then I should see the "Stakeholder was successfully deleted."

@rack_test
Scenario: E3 Another investor's ratios are untouched
  Given the investor has 4 fund ratios
  And there is another investor "Other Co" with 2 fund ratios
  When the investor is deleted
  Then the other investor still has 2 fund ratios

@rack_test
Scenario: E4 Fund owned ratios are untouched
  Given the investor has 4 fund ratios
  And the fund has 1 fund ratio owned by the fund
  When the investor is deleted
  Then the fund still has 1 fund ratio owned by the fund

Scenario: E5 Fund dashboard IRR widget skips an orphaned ratio
  Given the investor has 4 fund ratios
  And the investor was deleted leaving its fund ratios orphaned
  And the "Portfolio IRR" widget is enabled on the "Portfolio Dashboard"
  When I open the fund dashboard "Portfolio Dashboard"
  Then I should see the "No data available."

@rack_test
Scenario: E7 Clean-up query finds only orphaned ratios
  Given the investor has 4 fund ratios
  And there is another investor "Other Co" with 2 fund ratios
  And the investor was deleted leaving its fund ratios orphaned
  Then the orphaned investor fund ratios query finds 4 ratios

Scenario: E8 Single ratio uses singular wording
  Given the investor has 1 fund ratios
  When I open the investor page
  And I click delete on the investor page
  Then the confirmation popup says "Deleting this investor will also delete its associated fund ratio. Proceed?"
