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
    Then The card is deleted fromt the kanban board

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