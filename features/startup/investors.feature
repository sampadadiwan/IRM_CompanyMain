Feature: Investor
  Can create and view an investor as a startup

Scenario Outline: Create new investor
  Given Im logged in as a user "<user>" for an entity "<entity>"
  And I am at the investor page
  When I create a new investor "<investor>"
  Then I should see the "<msg>"
  And an investor should be created
  And an investor entity should be created
  And I should see the investor details on the details page

  Examples:
  	|user	      |entity               |investor     |msg	|
  	|  	        |entity_type=Startup  |name=Sequoia |Investor was successfully created|
    |  	        |entity_type=Startup  |name=Bearing |Investor was successfully created|


Scenario Outline: Create new investor from exiting entity
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given there is an existing investor entity "<investor>"
  And I am at the investor page
  When I create a new investor "<investor>" for the existing investor entity
  Then I should see the "<msg>"
  And an investor should be created
  And an investor entity should not be created
  And I should see the investor details on the details page

  Examples:
  	|user	      |entity               |investor         |msg	|
  	|  	        |entity_type=Startup  |name=Accel       |Investor was successfully created|
    |  	        |entity_type=Startup  |name=Bearing     |Investor was successfully created|
    |  	        |entity_type=Startup  |name=Kalaari     |Investor was successfully created|


Scenario Outline: Import investor access
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Startup"
  And Given I upload an investor access file for employees
  Then I should see the "Import upload was successfully created"
  Then There should be "2" investor access created


Scenario Outline: Import investor kycs
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  And Given I upload an investors file for the startup
  And Given I upload an investor kyc file for employees
  Then I should see the "Import upload was successfully created"
  Then There should be "2" investor kycs created
  And the corresponding investor kyc users must be created
  And the investor kycs must have the data in the sheet

Scenario Outline: Import investors
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Startup"
  And Given I upload an investors file for the startup
  Then I should see the "Import upload was successfully created"
  Then There should be "6" investors created
  And the investors must have the data in the sheet

Scenario Outline: Import Fund investors
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given there is a fund "name=Tech Fund" for the entity
  And Given I upload an investors file for the fund
  Then I should see the "Import upload was successfully created"
  Then There should be "6" investors created
  And the investors must have the data in the sheet
  And the investors must be added to the fund

