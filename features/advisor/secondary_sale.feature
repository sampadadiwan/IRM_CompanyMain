Feature: Secondary Sale
  Can view a sale as an Advisor

Scenario Outline: View sale - not externally visible
  Given there is a user "<user>" for an entity "entity_type=Startup"
  Given there is a sale "<sale>"
  Given Im logged in as a user "first_name=Emp1" for an entity "<entity>"
  And I should not see the sale in all sales page
  And I should not see the sale details on the details page

  Examples:
  	|user	    |entity                     |sale             |
  	|  	        |entity_type=Investment Advisor        |name=Grand Sale  |
    |  	        |entity_type=Family Office  |name=Winter Sale |


Scenario Outline: View sale - externally visible
  Given there is a user "<user>" for an entity "entity_type=Startup"
  Given there is a sale "<sale>"
  Given Im logged in as a user "first_name=Emp1" for an entity "<entity>"
  And I should see the sale in all sales page
  And I should see the sale details on the details page

  Examples:
  	|user	    |entity                     |sale                                     |
  	|  	        |entity_type=Investment Advisor        |name=Grand Sale;visible_externally=true  |
    |  	        |entity_type=Family Office  |name=Winter Sale;visible_externally=true |


Scenario Outline: Express Interest
  Given there is a user "<user>" for an entity "entity_type=Startup"
  Given there is a sale "<sale>"
  Given Im logged in as a user "first_name=Emp1" for an entity "<entity>"
  Given there are "approved" offers for the sale
  Then I should be able to create an interest in the sale
  Then I should see the interest details

  Examples:
  	|user	    |entity                     |sale                                     |
  	|  	        |entity_type=Investment Advisor        |name=Grand Sale;visible_externally=true  |
    |  	        |entity_type=Family Office  |name=Winter Sale;visible_externally=true |


