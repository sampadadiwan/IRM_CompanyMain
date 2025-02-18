Feature: Secondary Sale
  Can view a sale as a Investor

Scenario Outline: View sale - not externally visible
  Given there is a user "<user>" for an entity "<entity>"
  Given there is a sale "<sale>"
  Given Im logged in as a user "first_name=Emp1" for an entity "entity_type=Investor"
  Given my firm is an investor in the company
  And I should not see the sale in all sales page
  And I should not see the sale details on the details page

  Examples:
  	|user	    |entity               |sale             |msg	|
  	|  	        |entity_type=Company  |name=Grand Sale  |Secondary sale was successfully created|
    |  	        |entity_type=Company  |name=Winter Sale |Secondary sale was successfully created|



Scenario Outline: View sale - externally visible, but no access
  Given there is a user "<user>" for an entity "<entity>"
  Given there is a sale "<sale>"
  Given Im logged in as a user "first_name=Emp1" for an entity "entity_type=Investor"
  Given my firm is an investor in the company
  And I should not see the sale in all sales page
  And I should not see the sale details on the details page

  Examples:
  	|user	    |entity               |sale                                     |msg	|
  	|  	        |entity_type=Company  |name=Grand Sale  |Secondary sale was successfully created|
    |  	        |entity_type=Company  |name=Winter Sale |Secondary sale was successfully created|

Scenario Outline: View sale - with access
  Given there is a user "first_name=Emp1" for an entity "<entity>"
  Given there is a sale "<sale>"
  Given Im logged in as a user "first_name=Emp1" for an entity "entity_type=Investor"
  Given my firm is an investor in the company
  And the investor has "<access>" access rights to the sale
  And I should see the sale in all sales page
  And I should see the sale details on the details page

  Examples:
  	|access	    |entity               |sale                                     |msg	|
  	|Buyer      |entity_type=Company  |name=Grand Sale  |Secondary sale was successfully created|
    |Seller     |entity_type=Company  |name=Winter Sale |Secondary sale was successfully created|


Scenario Outline: View sale - make offer
  Given there is a user "<user>" for an entity "<entity>"
  Given there is a sale "<sale>"
  Given params "<params>" are set for the sale
  Given Im logged in as a user "first_name=Emp1" for an entity "entity_type=Investor"
  Given my firm is an investor in the company
  And the investor has "Seller" access rights to the sale
  And I should see the sale details on the details page
  Then when I place an offer "quantity=100;price=1000" from the offers tab
  Then I should see the offer
  And the sale offer amount must not be updated
  And when the offer is approved
  Then the sale offer amount must be updated


  Examples:
  	|user	      |entity               |sale                                     |msg	|params |
  	|  	        |entity_type=Company  |name=Grand Sale  |Secondary sale was successfully created|show_holdings=true|
    |  	        |entity_type=Company  |name=Winter Sale |Secondary sale was successfully created|show_holdings=true|


Scenario Outline: Express Interest
  Given there is a user "<user>" for an entity "<entity>"
  Given there is a sale "<sale>"
  Given Im logged in as a user "first_name=Emp1;last_name=Buyer" for an entity "entity_type=Investor"
  Given my firm is an investor in the company
  And the investor has "Buyer" access rights to the sale
  And I should see the sale details on the details page
  Given there are "approved" offers for the sale
  Then I should be able to create an interest in the sale
  Then I should see the interest details

  Examples:
|user	      |entity                   |sale                                     |
  	|  	        |entity_type=Company  |name=Grand Sale;visible_externally=false  |
    |  	        |entity_type=Company  |name=Winter Sale;visible_externally=false |
