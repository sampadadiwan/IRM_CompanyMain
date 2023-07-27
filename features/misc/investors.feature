Feature: Investor
  Can create and view an investor as a company

Scenario Outline: Create new investor
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  And I am at the investor page
  When I create a new investor "<investor>"
  Then I should see the "<msg>"
  And an investor should be created
  And an investor entity should be created
  And I should see the investor details on the details page

  Examples:
  	|user	      |entity               |investor     |msg	|
  	|  	        |entity_type=Company  |name=Sequoia |Investor was successfully created|
    |  	        |entity_type=Company  |name=Bearing |Investor was successfully created|


Scenario Outline: Create new investor from exiting entity
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing investor entity "<investor>"
  And I am at the investor page
  When I create a new investor "<investor>" for the existing investor entity
  Then I should see the "<msg>"
  And an investor should be created
  And an investor entity should not be created
  And I should see the investor details on the details page

  Examples:
  	|user	      |entity               |investor         |msg	|
  	|  	        |entity_type=Company  |name=Accel       |Investor was successfully created|
    |  	        |entity_type=Company  |name=Bearing     |Investor was successfully created|


Scenario Outline: Import investor access
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Company"
  Given the user has role "company_admin"
  And Given I upload an investors file for the company
  And Given I upload an investor access file for employees
  Then I should see the "Import upload was successfully created"
  Then There should be "2" investor access created
  And the investor accesses must have the data in the sheet


Scenario Outline: Import investor kycs
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  And Given I upload an investors file for the company
  And Given I upload an investor kyc file for employees
  Then I should see the "Import upload was successfully created"
  Then There should be "2" investor kycs created
  And the investor kycs must have the data in the sheet
  And Aml Report should be generated for each investor kyc

Scenario Outline: Import investors
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Company"
  Given the user has role "company_admin"
  And Given I upload an investors file for the company
  Then I should see the "Import upload was successfully created"
  Then There should be "6" investors created
  And the investors must have the data in the sheet

Scenario Outline: Import Fund investors
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=Tech Fund" for the entity
  And Given I upload an investors file for the fund
  Then I should see the "Import upload was successfully created"
  Then There should be "6" investors created
  And the investors must have the data in the sheet
  And the investors must be added to the fund

Scenario Outline: Create investor kyc - no ckyc
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  And Given I upload an investors file for the company
  Given I create a new InvestorKyc
  Then I should see the "Investor kyc was successfully saved. Please upload the required documents for the KYC."
  And I should be on the new documents page
  And when I upload the document for the kyc
  Then I should see the "Document was successfully saved."
  Then I should see the investor kyc details on the details page

Scenario Outline: Create investor kyc
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  And Given Entity has ckyc_kra_enabled set to true
  And I create a new InvestorKyc with pan "ABCD1234E"
  Then I should see ckyc and kra data comparison page
  Then I select one and see the edit page and save
