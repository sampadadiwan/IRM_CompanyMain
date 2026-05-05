Feature: Deal Kanban
  Can create and view a deal as a company

Scenario Outline: Create new deal
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  And I am at the deals page
  When I have Boards Permissions
  When I create a new deal "<deal>"
  Then I should see the "<msg>"
  And an deal should be created

  Examples:
  	|user	      |entity               |deal                             |msg	|
  	|  	        |entity_type=Company  |name=Series A;amount_cents=10000 |Deal was successfully created|
    |  	        |entity_type=Company  |name=Series B;amount_cents=12000 |Deal was successfully created|

Scenario: Fill form to create new deal investor
    Given Im logged in as a user "<user>" for an entity "<entity>"
    Given the user has role "company_admin"
    And I am at the deals page
    When I have Boards Permissions
    When I create a new deal "<deal>"
    Then I should see the "<msg>"
    And an deal should be created
    When I click on the Add Item and select any Investor and save

    Examples:
  	|user	      |entity               |deal                             |msg	|
  	|  	        |entity_type=Company  |name=Series A;amount_cents=10000 |Deal was successfully created|
    |  	        |entity_type=Company  |name=Series B;amount_cents=12000 |Deal was successfully created|

Scenario: Delete deal investor from kanban board
    Given Im logged in as a user "<user>" for an entity "<entity>"
    Given the user has role "company_admin"
    And I am at the deals page
    When I have Boards Permissions
    When I create a new deal "<deal>"
    Then I should see the "<msg>"
    And an deal should be created
    When I click on the Add Item and select any Investor and save
    When I click on a Kanban Card
    Then The offcanvas opens
    When I click on the delete button on offcanvas
    Then The card is deleted from the kanban board

    Examples:
  	|user	      |entity               |deal                             |msg	|
  	|  	        |entity_type=Company  |name=Series A;amount_cents=10000 |Deal was successfully created|

Scenario: Delete and Add same deal investor from kanban board
    Given Im logged in as a user "<user>" for an entity "<entity>"
    Given the user has role "company_admin"
    And I am at the deals page
    When I have Boards Permissions
    When I create a new deal "<deal>"
    Then I should see the "<msg>"
    And an deal should be created
    When I click on the Add Item and select any Investor and save
    When I click on a Kanban Card
    Then The offcanvas opens
    When I click on the delete button on offcanvas
    Then The card is deleted from the kanban board
    When I click on the Add Item and select previously deleted Investor and save
    When I click on a Kanban Card
    Then The offcanvas opens

    Examples:
  	|user	      |entity               |deal                             |msg	|
  	|  	        |entity_type=Company  |name=Series A;amount_cents=10000 |Deal was successfully created|

Scenario: Kanban Column creation
    Given Im logged in as a user "<user>" for an entity "<entity>"
    Given the user has role "company_admin"
    And I am at the deals page
    When I have Boards Permissions
    When I create a new deal "<deal>"
    Then I should see the "<msg>"
    And an deal should be created
    When I click on the action dropdown and create a Kanban Column

    Examples:
  	|user	      |entity               |deal                             |msg	|error |
  	|  	        |entity_type=Company  |name=Series A;amount_cents=10000 |Deal was successfully created|"Title\ncan't be blank"|
  	|  	        |entity_type=Company  |name=Series C;amount_cents=100000 |Deal was successfully created|"Days\ncan't be blank"|

Scenario: Duplicate Deal Investor error
    Given Im logged in as a user "<user>" for an entity "<entity>"
    Given the user has role "company_admin"
    And I am at the deals page
    When I have Boards Permissions
    When I create a new deal "<deal>"
    Then I should see the "<msg>"
    And an deal should be created
    When I click on the action dropdown and select the same Investor and save
    Then I should see the error "<error>"

    Examples:
  	|user	      |entity               |deal                             |msg	|error |
  	|  	        |entity_type=Company  |name=Series A;amount_cents=10000 |Deal was successfully created|"Deal Investor could not be created! Investor already added to this deal. Duplicate Investor."|

Scenario: No investor selected Deal Investor error
    Given Im logged in as a user "<user>" for an entity "<entity>"
    Given the user has role "company_admin"
    And I am at the deals page
    When I have Boards Permissions
    When I create a new deal "<deal>"
    Then I should see the "<msg>"
    And an deal should be created
    When I click on the action dropdown and dont select any Investor and save
    Then I should see the error "<error>"

    Examples:
  	|user	      |entity               |deal                             |msg	|error |
  	|  	        |entity_type=Company  |name=Series A;amount_cents=10000 |Deal was successfully created|"Deal Investor could not be created! Investor must exist"|


Scenario: Filter Deal Investors using tags
  Given Im logged in as a user "<user>" for an entity "<entity>"
    Given the user has role "company_admin"
    And I am at the deals page
    When I have Boards Permissions
    When I create a new deal "<deal>"
    Then I should see the "<msg>"
    And an deal should be created
    When I click on the Add Item and select any Investor and save
    When I click on a Kanban Card and edit the form
    When I click on a Kanban Card's tags


    Examples:
  	|user	      |entity               |deal                             |msg	|
  	|  	        |entity_type=Company  |name=Series A;amount_cents=10000 |Deal was successfully created|
    |  	        |entity_type=Company  |name=Series B;amount_cents=12000 |Deal was successfully created|

Scenario: Move card from one column to another
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  And I am at the deals page
  When I have Boards Permissions
  When I create a new deal "<deal>"
  Then I should see the "<msg>"
  And an deal should be created
  When I click on the Add Item and select any Investor and save
  When I move card from one column to another


  Examples:
  |user	      |entity               |deal                             |msg	|
  |  	        |entity_type=Company  |name=Series A;amount_cents=10000 |Deal was successfully created|
  |  	        |entity_type=Company  |name=Series B;amount_cents=12000 |Deal was successfully created|

Scenario: Move card sequence in same column
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  And I am at the deals page
  When I have Boards Permissions
  When I create a new deal "<deal>"
  Then I should see the "<msg>"
  And an deal should be created
  When I click on the Add Item and select any Investor and save
  When I move card to the top position


  Examples:
  |user	      |entity               |deal                             |msg	|
  |  	        |entity_type=Company  |name=Series A;amount_cents=10000 |Deal was successfully created|
  |  	        |entity_type=Company  |name=Series B;amount_cents=12000 |Deal was successfully created|

Scenario: Plane Kanban Board
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  And I am at the Boards Page
  When I have Boards Permissions
  When I create a new board "<board>"

  Examples:
  |user	      |entity               |board                            |msg	|
  |  	        |entity_type=Company  |name=Series A |Deal was successfully created|
  |  	        |entity_type=Company  |name=Series B |Deal was successfully created|

Scenario: Archive a Kanban Column
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  And I am at the Boards Page
  When I have Boards Permissions
  When I create a new board "<board>"
  When I add an item to the board

  Examples:
  |user	      |entity               |board                            |msg	|
  |  	        |entity_type=Company  |name=Series A |Deal was successfully created|
  |  	        |entity_type=Company  |name=Series B |Deal was successfully created|


Scenario: Deals Board details
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  And I am at the deals page
  When I have Boards Permissions
  When I create a new deal "<deal>"
  Then I should see the "<msg>"
  And an deal should be created
  When I click on the Add Item and select any Investor and save
  When I click on a Kanban Card
  Then The offcanvas opens
  And i click on the details button
  Then I should see the details of the deal investor

  Examples:
  |user	      |entity               |deal                             |msg	|
  |  	        |entity_type=Company  |name=Series F;amount_cents=10000 |Deal was successfully created|

Scenario Outline: Deal edit and details
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  And I am at the deals page
  When I have Boards Permissions
  When I create a new deal "<deal>"
  Then I should see the "<msg>"
  And an deal should be created
  When I click on the Add Item and select any Investor and save
  When I edit the deal "<edit>"
  Then deal and cards should be updated
  When i click on deal details i should see the tabs "<tabs>"
  And i should see be able to edit the deal from deal tab
  Examples:
  	|user	      |entity               |deal                             |msg	|edit |tabs|
  	|  	        |entity_type=Company  |name=Series G;amount_cents=10000 |Deal was successfully created|card_view_attrs="Pre Money Valuation, Total Amount, Tier, Status, Deal Lead"|"Access Rights, Deal"|

Scenario Outline: Deal preview
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  And I am at the deals page
  When I have Boards Permissions
  When I create a new deal "<deal>"
  Then I should see the "<msg>"
  And an deal should be created
  When I click on the Add Item and select any Investor and save
  And I view the deal details
  Given I add widgets for the deal
  And I add track record for the deal
  When I go to deal preview
  Then I can see the deal preview details
  Examples:
  	|user	      |entity               |deal                             |msg	|edit |
  	|  	        |entity_type=Company  |name=Series G;amount_cents=10000 |Deal was successfully created|card_view_attrs="Pre Money Valuation, Total Amount, Tier, Status, Deal Lead"|


Scenario: Add cards to Generic Kanban Board
    Given Im logged in as a user "<user>" for an entity "<entity>"
    Given the user has role "company_admin"
    When I have Boards Permissions
    And I am at the Boards Page
    When I create a new board "<board>"
    Then I should see the "<msg>"
    And I create two new cards and save

Examples:
|user	      |entity               |deal                             |msg	|
|  	        |entity_type=Company  |name=Amazing Board|Board was successfully created|
