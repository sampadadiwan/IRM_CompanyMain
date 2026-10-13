Feature: Investor Advisor
  Features for Investor Advisors

@import
Scenario Outline: Import Investor Advisors
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  And given there are investor advisors "terrie@hansen-inc.com,jeanice@hansen-inc.com,tameika@hansen-inc.com,daisey@hansen-inc.com"
  Given there is a fund "name=SAAS Fund;currency=INR" for the entity
  And Given import file "investors.xlsx" for "Investor"
  And Given import file "investor_kycs.xlsx" for "InvestorKyc"
  And Given import file "investor_access.xlsx" for "InvestorAccess"
  And Given import file "capital_commitments_with_kycs.xlsx" for "CapitalCommitment"
  Given the fund has "1" capital call
  Given the capital calls are approved
  Given the fund has "1" capital distribution
  Given the capital distributions are approved
  And Given I upload "investor_advisors.xlsx" file for Investment Advisors
  Then the investor advisors should be added to each investor
  Given I log out
  Given I log in with email "terrie@hansen-inc.com"
  And I switch to becoming the advisor for "Investor 1"
  Then my active entity should be the switched entity
  And my roles should include "investor_advisor"
  And my roles should not include "company_admin"
  And my roles should not include "super"
  And I should see the fund in all funds page
  When I am at the fund details page
  Then I should be able to see my capital commitments
  Then I should be able to see my capital remittances
  Then I should be able to see my capital distributions
  Then I should be able to see my investor kycs
  And I revert to my home entity
  Then I am back in my original entity
  Given I log out
  Given I log in with email "jeanice@hansen-inc.com"
  And I switch to becoming the advisor for "Investor 2"
  And I should see the fund in all funds page
  When I am at the fund details page
  Then I should be able to see my capital commitments
  Then I should be able to see my capital remittances
  Then I should be able to see my capital distributions
  Then I should be able to see my investor kycs
  And all the investor advisors should be able to receive notifications for the folios they represent
  And all the investor advisors should be able to switch to the investors they represent and view their details


@import
Scenario Outline: Import Investor Advisors when User not present
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  And given there are investor advisors "terrie@hansen-inc.com,jeanice@hansen-inc.com,tameika@hansen-inc.com,daisey@hansen-inc.com"
  Given there is a fund "name=SAAS Fund;currency=INR" for the entity
  And Given I upload an investors file for the fund
  And Given I upload "capital_commitments.xlsx" file for "Commitments" of the fund
  And Given I upload "investor_advisors_without_users.xlsx" file for Investment Advisors
  Then the investor advisors should be added to each investor

Scenario Outline: Create new investor advisor for capital commitment
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
  Given I go to Add Investor Advisor page for commmitment
  And I fill IA form with details of a user that exists with role "investor_advisor"
  Then Investor Advisor is successfully created
  Given I go to Add Investor Advisor page for commmitment
  And I fill IA form with details of a user that is already an Investor Advisor for this fund
  Then Investor Advisor is successfully created
  Given I go to Add Investor Advisor page for commmitment
  And I fill IA form with details of a user that exists with role ""
  Then Investor Advisor creation fails with error "User has not been setup as an investor advisor"
  Given I go to Add Investor Advisor page for commmitment
  And I fill IA form with details of a user that does not exist with details "advisor_entity_name,first_name,last_name"
  Then Investor Advisor is successfully created
  Given I go to Add Investor Advisor page for commmitment
  And I fill IA form with details of a user that does not exist with details "advisor_entity_name,last_name"
  Then Investor Advisor creation fails with error "User could not be created. First name can't be blank"
  And I fill IA form with details of a user that does not exist with details "advisor_entity_name,first_name,last_name"
  Then Investor Advisor is successfully created
  Given I go to Add Investor Advisor page for commmitment
  And I fill IA form with details of a user that does not exist with details "advisor_entity_name"
  Then Investor Advisor creation fails with error "User could not be created. First name can't be blank, Last name can't be blank"
  And I fill IA form with details of a user that does not exist with details "advisor_entity_name,first_name,last_name"
  Then Investor Advisor is successfully created
  Given I go to Add Investor Advisor page for commmitment
  And I fill IA form with details of a user that does not exist with details ""
  Then Investor Advisor creation fails with error "Entity could not be created. Name can't be blank"
  And I fill IA form with details of a user that does not exist with details "advisor_entity_name,first_name,last_name"
  Then Investor Advisor is successfully created
  Given I go to Add Investor Advisor page for commmitment
  And I fill IA form with details of a user that does not exist with details "first_name,last_name"
  Then Investor Advisor creation fails with error "Entity could not be created. Name can't be blank"
  And I fill IA form with details of a user that does not exist with details "advisor_entity_name,first_name,last_name"
  Then Investor Advisor is successfully created

  Examples:
  	|user	    |entity                                 |fund                 |msg	|
  	|  	      |entity_type=Investment Fund;enable_funds=true  |name=Test fund      |Fund was successfully created|

Scenario Outline: Create new investor advisor for capital commitment
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
  Given I go to Add Investor Advisor page for commmitment
  And I fill IA form with details of a user that exists with role "investor_advisor"
  Then Investor Advisor is successfully created
  Then the AccessRight for the advisor must be added for the fund
  Given I delete the InvestorAccess of this User on the investors page
  Then the AccessRight for the advisor must be deleted for the fund
  And the AccessRights Cache for the advisor must not have the fund
  Given I go to Add Investor Advisor page for commmitment
  And I fill IA form with details of a user that is already an Investor Advisor for this fund
  Then Investor Advisor is successfully created
  And Its the same InvestorAdvisor with the InvestorAccess created again

  Examples:
  	|user	    |entity                                 |fund                 |msg	|
  	|  	      |entity_type=Investment Fund;enable_funds=true  |name=Test fund      |Fund was successfully created|


# ── Security Scenarios ────────────────────────────────────────────────────────
# These scenarios directly test that each security fix is effective.

@security @rack_test
Scenario: SEC-1 Allowed roles whitelist — model rejects platform-level role at save
  # Finding 2: allowed_roles must block system-wide roles that no entity admin
  # has authority to bestow. :super is the key example — it transcends entities.
  Given Im logged in as a user "first_name=Fund Manager" for an entity "name=AlphaVC;entity_type=Investment Fund"
  Given the user has role "company_admin"
  And the entity has the investor advisors feature enabled
  And there is an existing investor advisor user
  When I try to build an investor advisor with allowed_roles including "super"
  Then the investor advisor should fail validation with "contains invalid role"

@security @import @rack_test
Scenario: SEC-2 Allowed roles whitelist — import raises error for platform-level role in spreadsheet
  # Finding 2 (import path): the import service must reject rows whose
  # Allowed Roles column contains roles outside ALLOWED_ADVISOR_ROLES.
  Given Im logged in as a user "first_name=Fund Manager" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  And given there are investor advisors "terrie@hansen-inc.com"
  Given there is a fund "name=SAAS Fund;currency=INR" for the entity
  And Given import file "investors.xlsx" for "Investor"
  And Given import file "investor_kycs.xlsx" for "InvestorKyc"
  And Given import file "investor_access.xlsx" for "InvestorAccess"
  And Given import file "capital_commitments_with_kycs.xlsx" for "CapitalCommitment"
  When I process an investor advisor import row with allowed_roles "super"
  Then the import row should raise an invalid roles error

@security @rack_test
Scenario: SEC-3 Allowed roles whitelist — all entity-level roles are accepted
  # Finding 2 (positive case): employee, investor, company_admin, rm, and
  # approver must all pass validation because entity admins legitimately grant these.
  Given Im logged in as a user "first_name=Fund Manager" for an entity "name=AlphaVC2;entity_type=Investment Fund"
  Given the user has role "company_admin"
  And the entity has the investor advisors feature enabled
  And there is an existing investor advisor user
  When I try to build an investor advisor with allowed_roles including "employee"
  Then the investor advisor should pass allowed_roles validation
  When I try to build an investor advisor with allowed_roles including "investor"
  Then the investor advisor should pass allowed_roles validation
  When I try to build an investor advisor with allowed_roles including "company_admin"
  Then the investor advisor should pass allowed_roles validation
  When I try to build an investor advisor with allowed_roles including "approver"
  Then the investor advisor should pass allowed_roles validation
  When I try to build an investor advisor with allowed_roles including "rm"
  Then the investor advisor should pass allowed_roles validation

@security @rack_test
Scenario: SEC-4 IDOR blocked — user from unrelated entity cannot create advisor for another entity's investor
  # Finding 1: create_for_investor? must check user entity, not just ID equality.
  # A user from RogueCo should never pass the policy for ManagingCo's investor.
  Given Im logged in as a user "first_name=Attacker" for an entity "name=RogueCo;entity_type=Investment Fund"
  Given the user has role "company_admin"
  And the entity has the investor advisors feature enabled
  And there is a separate managing entity with an investor
  When I check create_for_investor policy against the other entity's investor
  Then the policy should deny create_for_investor access

@security @rack_test
Scenario: SEC-5 IDOR blocked — user from the owning entity is allowed through create_for_investor
  # Finding 1 (positive case): an admin of the managing entity must still be
  # able to add advisors through this path.
  Given Im logged in as a user "first_name=Fund Manager" for an entity "name=ManagingCo;entity_type=Investment Fund"
  Given the user has role "company_admin"
  And the entity has the investor advisors feature enabled
  And there is an investor belonging to this managing entity
  When I check create_for_investor policy for this entity's own investor
  Then the policy should allow create_for_investor access

@security @rack_test
Scenario: SEC-6 Feature flag enforced — entity without enable_investor_advisors cannot create advisors
  # Finding 4: create? must check enable_investor_advisors, not just entity membership.
  # Disabling the flag must block writes, not just hide the index page.
  Given Im logged in as a user "first_name=Fund Manager" for an entity "name=LockedFund;entity_type=Investment Fund"
  Given the user has role "company_admin"
  And the entity does not have the investor advisors feature enabled
  And there is an existing investor "name=TestInv" with "1" users
  When I check the create investor advisor policy
  Then the policy should deny create access

@security @rack_test
Scenario: SEC-7 Feature flag enforced — entity with enable_investor_advisors can create advisors
  # Finding 4 (positive case): the flag being on must still allow the existing flow.
  Given Im logged in as a user "first_name=Fund Manager" for an entity "name=EnabledFund;entity_type=Investment Fund"
  Given the user has role "company_admin"
  And the entity has the investor advisors feature enabled
  And there is an existing investor "name=TestInv" with "1" users
  When I check the create investor advisor policy
  Then the policy should allow create access

@security @rack_test
Scenario: SEC-8 Revert endpoint — non-advisor user is denied
  # Finding 3: the revert path of switch must check investor_advisor? before running.
  # A regular investor user must receive Pundit::NotAuthorizedError.
  Given Im logged in as a user "first_name=Investor" for an entity "name=BetaFund;entity_type=Investment Fund"
  Given the user has role "investor"
  Then the user is not in advisor context
  And attempting the advisor revert switch should be denied

@security @rack_test
Scenario: SEC-9 Revert endpoint — switched advisor can revert normally
  # Finding 3 (positive case): a user who is genuinely in advisor context must
  # be able to revert without error.
  Given Im logged in as a user "first_name=Advisor" for an entity "name=AdvisoryFirm2;entity_type=Investor Advisor"
  Given the user has role "investor_advisor"
  And there is an investor advisor record for this user in another entity
  And I have switched into that advisor entity
  Then the advisor revert should succeed and return to the home entity

@security
Scenario: SEC-10 GET request does not trigger entity switch
  # Finding 6: switch_advisor before_action must only fire on POST requests.
  # A GET visit to any page with investor_advisor_id in the query string must
  # not modify the user's entity_id in the database.
  Given Im logged in as a user "first_name=Advisor" for an entity "name=AdvisoryFirm;entity_type=Investor Advisor"
  Given the user has role "investor_advisor"
  And there is an investor advisor record for this user in another entity
  When I visit a page with the investor_advisor_id parameter as a GET request
  Then my active entity should not have changed

@security @rack_test
Scenario: SEC-11 Invalid fund_id in new_for_investor redirects gracefully without 500
  # Finding 7: a missing @fund must redirect, not crash with NoMethodError.
  # The response must be a redirect, not an error, regardless of fund_id value.
  Given Im logged in as a user "first_name=Fund Manager" for an entity "name=SafeFund;entity_type=Investment Fund"
  Given the user has role "company_admin"
  And the entity has the investor advisors feature enabled
  And there is an existing investor "name=TestInv" with "1" users
  When I visit the new_for_investor page with an invalid fund_id
  Then I should be redirected to the funds page with an alert

@security @import
Scenario: SEC-12 Roles after switch are scoped to allowed_roles only — no privilege escalation
  # Findings 2 + 8: after switching, the advisor must hold only the roles
  # configured in allowed_roles, never anything beyond them.
  Given Im logged in as a user "first_name=Fund Manager" for an entity "name=GreenVC;entity_type=Investment Fund"
  Given the user has role "company_admin"
  And given there are investor advisors "terrie@hansen-inc.com"
  Given there is a fund "name=SAAS Fund;currency=INR" for the entity
  And Given import file "investors.xlsx" for "Investor"
  And Given import file "investor_kycs.xlsx" for "InvestorKyc"
  And Given import file "investor_access.xlsx" for "InvestorAccess"
  And Given import file "capital_commitments_with_kycs.xlsx" for "CapitalCommitment"
  And Given I upload "investor_advisors.xlsx" file for Investment Advisors
  Given I log out
  Given I log in with email "terrie@hansen-inc.com"
  And I switch to becoming the advisor for "Investor 1"
  Then my roles should include "investor_advisor"
  And my roles should not include "company_admin"
  And my roles should not include "super"
  And my permissions should match the investor advisor permissions
  And my extended permissions should match the investor advisor extended permissions

@security
Scenario: SEC-13 Mass assignment blocked — user_id is ignored in strong params
  # Finding 5: submitting user_id in the form must not override the user
  # resolved from the email field.
  Given Im logged in as a user "first_name=Fund Manager" for an entity "name=MassTestFund;entity_type=Investment Fund"
  Given the user has role "company_admin"
  And the entity has the investor advisors feature enabled
  And there is an existing investor advisor user
  Then user_id is not accepted as a permitted parameter for investor advisor creation

@security @rack_test
Scenario: SEC-14 Permissions and extended_permissions are accepted from the UI
  # User requirement: entity admins must be able to set permissions and
  # extended_permissions from the form. These are intentionally permitted.
  Given Im logged in as a user "first_name=Fund Manager" for an entity "name=MassTestFund2;entity_type=Investment Fund"
  Given the user has role "company_admin"
  And the entity has the investor advisors feature enabled
  Then permissions and extended_permissions are accepted as permitted parameters

@security @rack_test
Scenario: SEC-15 Only company admins can create or update investor advisors
  # Policy change: create? now requires company_admin. A regular employee of
  # the same entity must be denied even with the feature flag on.
  Given Im logged in as a user "first_name=Employee" for an entity "name=StaffFund;entity_type=Investment Fund"
  Given the user has role "employee"
  And the entity has the investor advisors feature enabled
  And there is an existing investor "name=TestInv" with "1" users
  When I check the create investor advisor policy
  Then the policy should deny create access

@security
Scenario: SEC-16 company_admin role in allowed_roles — blocked for non-company-admin granter
  # Belt-and-suspenders: even if someone bypasses the policy check, the model
  # validation must reject company_admin in allowed_roles when acting_user is
  # not a company admin.
  Given Im logged in as a user "first_name=Employee" for an entity "name=StaffFund2;entity_type=Investment Fund"
  Given the user has role "employee"
  And the entity has the investor advisors feature enabled
  And there is an existing investor advisor user
  When a non-company-admin tries to build an investor advisor with allowed_roles "company_admin"
  Then the investor advisor should fail validation with "cannot include 'company_admin'"

@security @rack_test
Scenario: SEC-17 company_admin role in allowed_roles — allowed for company_admin granter
  # Positive case: a company admin may legitimately grant company_admin to an
  # advisor so they have full admin access when operating in that entity.
  Given Im logged in as a user "first_name=Fund Manager" for an entity "name=AdminGrantFund;entity_type=Investment Fund"
  Given the user has role "company_admin"
  And the entity has the investor advisors feature enabled
  And there is an existing investor advisor user
  When a company_admin tries to build an investor advisor with allowed_roles "company_admin"
  Then the investor advisor should pass the company_admin granter validation
