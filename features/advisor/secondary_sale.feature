Feature: Secondary Sale
  Can view a sale as an Advisor

Scenario Outline: View sale - not externally visible
  Given there is a user "<user>" for an entity "entity_type=Company"
  Given there is a sale "<sale>"
  Given Im logged in as a user "first_name=Emp1" for an entity "<entity>"
  And I should not see the sale in all sales page
  And I should not see the sale details on the details page

  Examples:
  	|user	    |entity                     |sale             |
  	|  	        |entity_type=Investment Advisor        |name=Grand Sale  |
    |  	        |entity_type=Family Office  |name=Winter Sale |




