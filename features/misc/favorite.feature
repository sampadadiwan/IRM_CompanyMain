Feature: Favorite
  Can add a page to favorites and view it in the favorites list

Scenario Outline: Add a page to favorites and view it in the favorites list
  Given Im logged in as a user "" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund;currency=INR;unit_types=Series A,Series B,Series C1" for the entity
  And Given import file "investors.xlsx" for "Investor"
  And Given import file "capital_commitments_multi_currency.xlsx" for "CapitalCommitment"
  Given I am using first fund
  Given I have no favorites
  Given I go to fund page
  And I click on Add to Favorites button
  Then I should see the "Favorited!"
  Given I click on Add to Favorites button
  Then I should see the "Already in favorites."
  Given I go to fund page
  Given I click on "Favorites"
  Then I should see the fund in the favorites list
  Given I click View All in favorites
  Then I should see the fund in the favorites list page
  And I click on the fund in the favorites list page
  Then I should be on the fund details page
  Given I click on "Favorites"
  Then I should see the fund in the favorites list
  Given I click View All in favorites
  Then I should see the fund in the favorites list page
  And I click on "Delete"
  And I click on "Proceed"
  Then I should see the "Removed from favorites."
  Given I go to fund page
  And I click on Add to Favorites button
  Then I should see the "Favorited!"
  Given I click on "Favorites"
  Given I click View All in favorites
  Then I should see the fund in the favorites list page
  And I click on "Delete"
  And I click on "Proceed"
  Then I should see the "Removed from favorites."
  Given I go to the investor page
  And I click on Add to Favorites button
  Then I should see the "Favorited!"
  Given I click on Add to Favorites button
  Then I should see the "Already in favorites."
  Given I go to the investor page
  Given I click on "Favorites"
  Then I should see the investors in the favorites list
  Given I click View All in favorites
  Then I should see the investors in the favorites list page
  And I click on the investors in the favorites list page
  Then I should be on the investors details page
  Given I click on "Favorites"
  Then I should see the investors in the favorites list
  Given I click View All in favorites
  Then I should see the investors in the favorites list page
  And I click on "Delete"
  And I click on "Proceed"
  Then I should see the "Removed from favorites."
