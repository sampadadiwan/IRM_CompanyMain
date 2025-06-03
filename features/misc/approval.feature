Feature: Approval
  Can create and view a approval as a company

Scenario Outline: Create new approval
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  And I am at the approvals page
  When I create a new approval "<approval>"
  Then I should see the "<msg>"
  And an approval should be created
  And I should see the approval details on the details page
  And I should see the approval in all approvals page

  Examples:
  	|user	    |entity               |approval                 |msg	|
  	|  	        |entity_type=Company  |title=Test approval      |Approval was successfully created|
    |  	        |entity_type=Company  |title=Merger Approval    |Approval was successfully created|

Scenario Outline: Create new approval for Fund
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is a fund "name=Test Fund;unit_types=Series A,Series B" for the entity
  Given there is an existing investor "" with "1" users
  Given there is an existing investor "" with "1" users
  Given the investors are added to the fund
  Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
  Given there are capital commitments of "orig_folio_committed_amount_cents=200000000" from each investor
  When I create a new approval "<approval>" for the fund
  Then I should see the "<msg>"
  And an approval should be created
  And the approval should have the right access rights
  And the approval should have the right approval responses created
  And I should see the approval details on the details page
  And I should see the approval in all approvals page

  Examples:
  	|user	    |entity               |approval                 |msg	|
  	|  	        |entity_type=Company  |title=Test approval      |Approval was successfully created|
    |  	        |entity_type=Company  |title=Merger Approval    |Approval was successfully created|

Scenario Outline: Edit approval
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  And I am at the approvals page
  When I create a new approval "<approval>"
  Then I should see the "<msg>"
  And an approval should be created
  When I edit the approval "title=Updated Title"
  And I should see the approval details on the details page
  And I should see the approval in all approvals page

  Examples:
  	|user	    |entity               |approval                 |msg	|
  	|  	        |entity_type=Company  |title=Test approval      |Approval was successfully created|
    |  	        |entity_type=Company  |title=MErger Approval    |Approval was successfully created|


Scenario Outline: Grant Access Rights to approval
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given the user has role "approver"
  Given there is an existing investor "" with "2" users
  Given there is an existing investor "" with "2" users
  Given there is an approval "<approval>" for the entity
  Given the investors are added to the approval  
  When I visit the approval details page
  Then the approval responses are generated with status "Pending"  
  Then I should see the approval response details for each response
  When the approval is approved  
  Then the investor gets the approval notification

  Examples:
  	|user	    |entity               |approval                 |
  	|  	        |entity_type=Company  |title=Test approval      |
    |  	        |entity_type=Company  |title=Merger Approval    |


Scenario Outline: Grant Access Rights to approval after approved
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given the user has role "approver"
  Given there is an existing investor "" with "2" users
  Given there is an existing investor "" with "2" users
  Given there is an approval "<approval>" for the entity
  Given the investors are added to the approval  
  When I visit the approval details page
  Then the approval responses are generated with status "Pending"  
  Then the investor gets the approval notification
  When the Send Reminder button on approval is clicked
  Then the investor gets the approval notification
  And when the approval response is accepted
  Then the investor gets the accepted notification

  Examples:
  	|user	    |entity               |approval                                 |msg	|
  	|  	        |entity_type=Company  |title=Test approval;approved=true      |Approval was successfully created|
    |  	        |entity_type=Company  |title=Merger Approval;approved=true    |Approval was successfully created|



Scenario Outline: Provide approval response
  Given there is a user "<user>" for an entity "<entity>"
  Given there is an existing investor "" with "2" users
  Given there is an approval "<approval>" for the entity
  Given the investors are added to the approval  
  Given Im logged in as an investor
  When I visit the approval details page
  Then I should see my approval response  
  When I select "Approved" for the approval response
  Then the approval response is "Approved"
  And the approved count of the approval is "1"
  And the rejected count of the approval is "0"
  When I select "Rejected" for the approval response
  Then the approval response is "Rejected"
  And the approved count of the approval is "0"
  And the rejected count of the approval is "1"
  
  Examples:
  	|user	    |entity               |approval                 |msg	|
  	|  	        |entity_type=Company  |title=Test approval      |Approval was successfully created|
    |  	        |entity_type=Company  |title=Merger Approval    |Approval was successfully created|



Scenario Outline: Provide approval response
  Given there is a user "<user>" for an entity "entity_type=Company;sub_domain=test"
  Given there is an existing investor "" with "1" users
  Given there is an approval "<approval>" for the entity
  Given the investors are added to the approval 
  When the approval is approved internally 
  When I select "<status>" in the approval notification email
  Then the approval response is "<status>"
  And the approval response user is correctly captured
  
  Examples:
  	|user	    |approval                 |msg	| status |
  	|  	      |title=Test approval;response_enabled_email=true      |Approval was successfully created| Approved |
    |  	      |title=Merger Approval;response_enabled_email=true    |Approval was successfully created| Rejected |
