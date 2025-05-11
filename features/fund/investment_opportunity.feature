Feature: Investment Opportunity
  Can create and view a investment_opportunity as a company

Scenario Outline: Create new investment_opportunity
  Given Im logged in as a user "" for an entity "<entity>"
  Given the user has role "company_admin"
  And I am at the investment_opportunities page
  When I create a new investment_opportunity "<investment_opportunity>"
  Then I should see the "<msg>"
  And an investment_opportunity should be created
  And I should see the investment_opportunity details on the details page
  And I should see the investment_opportunity in all investment_opportunities page

  Examples:
  	|entity                                 |investment_opportunity                  |msg	|
  	|entity_type=Investment Fund;enable_inv_opportunities=true;enable_documents=true  |company_name=Test IO|opportunity was successfully created|
    |entity_type=Investment Fund;enable_inv_opportunities=true;enable_documents=true  |company_name=IO 2   |opportunity was successfully created|


Scenario Outline: Create new document for an investment_opportunity
  Given Im logged in as a user "" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an investment_opportunity "<investment_opportunity>"
  Given there is an existing investor "" with "1" users
  Given the investors are added to the investment_opportunity
  When I upload a document for the investment_opportunity
  Then I should see the "Document was successfully saved"
  Then The document must be created with the owner set to the investment_opportunity
  And an email must go out to the investors for the document

  Examples:
  	|entity                                 |investment_opportunity                  |msg	|
  	|entity_type=Investment Fund;enable_inv_opportunities=true  |company_name=Test IO|opportunity was successfully created|
    |entity_type=Investment Fund;enable_inv_opportunities=true  |company_name=IO 2   |opportunity was successfully created|

Scenario Outline: Create new interest for an investment_opportunity
  Given Im logged in as a user "" for an entity "<entity>"
  Given the user has role "company_admin"
  Given the user has role "approver"
  Given there is an investment_opportunity "<investment_opportunity>"
  Given there is an existing investor "" with "1" users
  Given the investors are added to the investment_opportunity
  When I create an EOI "amount_cents=1000000"
  Then I should see the "Expression of interest was successfully created"
  Then the EOI must be created
  And I should see the EOI details on the details page
  And I should see the EOI in all EOIs page
  And the investment_opportunity eoi amount should be "0"
  And when the EOI is approved
  And the investment_opportunity eoi amount should be "1000000"


  Examples:
  	|entity                                 |investment_opportunity                  |msg	|
  	|entity_type=Investment Fund;enable_inv_opportunities=true  |min_ticket_size_cents=1000000|opportunity was successfully created|
    |entity_type=Investment Fund;enable_inv_opportunities=true  |min_ticket_size_cents=1000000|opportunity was successfully created|

Scenario Outline: Preview for an investment_opportunity
    Given Im logged in as a user "" for an entity "<entity>"
    Given the user has role "company_admin"
    Given there is an investment_opportunity "<investment_opportunity>"
    Given there is an existing investor "" with "1" users
    Given the investors are added to the investment_opportunity
    When I upload a document for the investment_opportunity
    And I add widgets for the investment_opportunity
    And I add track record for the investment_opportunity
    When I go to investment_opportunity preview
    Then I can see all the investment_opportunity preview details

  Examples:
    |entity                                 |investment_opportunity                  |msg	|
    |entity_type=Investment Fund;enable_inv_opportunities=true  |company_name=Test IO|opportunity was successfully created|


Scenario Outline: Create new interest for an investment_opportunity from RM and approve
  Given Im logged in as a user "" for an entity "entity_type=Investment Fund;enable_inv_opportunities=true"
  Given the user has role "company_admin"
  Given the user has role "approver"
  Given there is an investment_opportunity "<investment_opportunity>"
  Given there is an existing investor "category=RM" with "1" users
  Given the investor users have the role "rm"
  Given the investors are added to the investment_opportunity
  When the RM create an EOI "<eoi>" and the corresponding kyc ""
  And the investment_opportunity eoi amount should be "0"
  And when the EOI is approved
  And the investment_opportunity eoi amount should be "1000000"
  And a new investor should be created from the EOI


  Examples:
  	|investment_opportunity                  |eoi	|
  	|min_ticket_size_cents=1000000|investor_name=InvForRM;investor_email=invforrm@gmail.com;amount_cents=1000000|
    |min_ticket_size_cents=1000000|investor_name=InvForRM;investor_email=invforrm@gmail.com;amount_cents=1000000|
