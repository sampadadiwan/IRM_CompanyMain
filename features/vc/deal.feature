Feature: Deal
  Can view an deal as a Investor

Scenario Outline: View deal without access
  Given Im logged in as a user "first_name=Emp1" for an entity "entity_type=Investor"
  Given there are "3" exisiting deals "<deal>" with another firm in the startups
  And I am at the deal_investors page
  Then I should not see the deal cards of the company

  Examples:
  	|deal                                 |
  	|name=Series A;amount_cents=10000     |
    |name=Series A;amount_cents=10000     |


Scenario Outline: View deal without access
  Given Im logged in as a user "first_name=Emp1" for an entity "entity_type=Investor"
  Given there are "3" exisiting deals "<deal>" with my firm in the startups
  And I am at the deal_investors page
  Then I should not see the deal cards of the company

  Examples:
  	|deal                                 |
  	|name=Series A;amount_cents=10000     |
    |name=Series A;amount_cents=10000     |


Scenario Outline: View deal with access
  Given Im logged in as a user "first_name=Emp1" for an entity "entity_type=Investor"
  Given there are "1" exisiting deals "<deal>" with my firm in the startups
  Given I have access to all deals
  And I am at the deal_investors page
  Then I should see the deal cards of the company

  Examples:
  	|deal                                 |
  	|name=Series A;amount_cents=10000     |
    |name=Series A;amount_cents=10000     |
