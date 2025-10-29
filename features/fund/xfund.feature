Feature: Fund
  Can create and view a fund as a company

Scenario Outline: Create new fund
  Given Im logged in as a user "" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing investor "" with "1" users
  And I am at the funds page
  When I create a new fund "<fund>"
  Then I should see the "<msg>"
  And an fund should be created
  Given the investors are added to the fund
  And I should see the fund details on the details page
  And I should see the fund in all funds page
  And I visit the fund details page
  When I click on fund documents tab
  When I create a new document "name=Quarterly Report;send_email=true" in folder "Data Room"
  And an document should be created
  And an email must go out to the investors for the document
  And the fund document details must be setup right
  And I visit the fund details page
  When I click on fund documents tab
  And I should see the document in all documents page

  Examples:
    |entity                                         |fund                |msg	|
  	|entity_type=Investment Fund;enable_funds=true  |name=Test fund      |Fund was successfully created|
    |entity_type=Investment Fund;enable_funds=true;enable_units=true  |name=Merger Fund;unit_types=Series A,Series B    |Fund was successfully created|


Scenario Outline: View fund with employee access
  Given Im logged in as a user "" for an entity "<entity>"
  Given there is a fund "<fund>" for the entity
  And I am "given" employee access to the fund
  When I am at the fund details page
  And I should see the fund details on the details page
  And I should see the fund in all funds page

  Examples:
  	|entity                                 |fund                 |msg	|
  	|entity_type=Investment Fund;enable_funds=true;enable_units=true  |name=Test fund      |Fund was successfully created|
    |entity_type=Investment Fund;enable_funds=true;enable_units=true  |name=Merger Fund    |Fund was successfully created|

Scenario Outline: View fund - without employee access
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given there is a fund "<fund>" for the entity
  And I am "no" employee access to the fund
  When I am at the fund details page
  Then I should see the "<msg>"

  Examples:
  	|user	    |entity                                 |fund                 |msg	|
  	|  	        |entity_type=Investment Fund;enable_funds=true  |name=Test fund      |Access Denied|
    |  	        |entity_type=Investment Fund;enable_funds=true  |name=Merger Fund    |Access Denied|



Scenario Outline: Create new capital commitment
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing investor "name=A1" with "2" users
  Given there is an existing investor "name=A2" with "2" users
  Given there is a fund "<fund>" for the entity
  Given the fund has capital commitment template
  Given the investors are added to the fund
  When I add a capital commitment "1000000" for investor "A1"
  Then I should see the capital commitment details
  Then the fund total committed amount must be "1000000"
  When I add a capital commitment "1000000" for investor "A2"
  Then I should see the capital commitment details
  Then the fund total committed amount must be "2000000"
  Given each investor has a "verified" kyc linked to the commitment
  And when the capital commitment docs are generated
  Then the generated doc must be attached to the capital commitments


  Examples:
  	|user	    |entity                                 |fund                 |msg	|
  	|  	      |entity_type=Investment Fund;enable_funds=true  |name=Test fund      |Fund was successfully created|
    |         |entity_type=Investment Fund;enable_funds=true;enable_units=true  |name=Merger Fund;unit_types=Series A,Series B    |Fund was successfully created|





Scenario Outline: Fund E-Signatures Report
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing investor "name=A1" with "2" users
  Given there is an existing investor "name=A2" with "2" users
  Given there is a fund "<fund>" for the entity
  Given the fund has capital commitment template
  Given the investors are added to the fund
  When I add a capital commitment "1000000" for investor "A1"
  Then I should see the capital commitment details
  Then the user goes to the fund e-signature report
  And the user should see all esign report for all docs sent for esign


  Examples:
    |user	    |entity                                 |fund                 |msg	|
    |  	      |entity_type=Investment Fund;enable_funds=true  |name=Test fund 888      |Fund was successfully created|


Scenario Outline: Duplicate account entry bulk upload
    Given Im logged in as a user "" for an entity "<entity>"
    Given the user has role "company_admin"
    Given there is a fund "<fund>" for the entity
    And Given I upload an investors file for the fund
    Given the investors have approved investor access
    Given the fund has capital call template
    Given the investors are added to the fund
    And Given import file "capital_commitments.xlsx" for "CapitalCommitment"
    And Given the commitments have a cc "advisor@gmail.com"
    And Given I upload "account_entries_with_dup.xlsx" "<error_count>" error file for Account Entries
    Then I should see that the duplicate account entries are not uploaded

    Examples:
      |entity                                         |fund                |msg	| error_count|
      |entity_type=Investment Fund;enable_funds=true  |name=SAAS Fund;currency=INR      |Fund was successfully created| 5 |
