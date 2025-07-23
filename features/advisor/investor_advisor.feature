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
  And I should see the fund in all funds page
  When I am at the fund details page
  Then I should be able to see my capital commitments
  Then I should be able to see my capital remittances
  Then I should be able to see my capital distributions
  Then I should be able to see my investor kycs
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