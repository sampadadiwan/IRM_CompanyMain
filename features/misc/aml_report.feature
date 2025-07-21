
Feature: Aml Report Generation
  Can access models as a company

Scenario Outline: Dont Generate AML report and Bulk Generate Aml Report
  Given Im logged in as a user "first_name=Testuser" for an entity "name=Urban1;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given the entity has aml enabled "true"
  Given there is an existing investor "investor_name=Investor 11"
  Given I create a new InvestorKyc "PAN=ABCD1234F;full_name=nil" to trigger aml report generation
  Then I should see the "Investor kyc was successfully saved."
  Then aml report is not generated for the investor kyc
  And I update full name to nil for the KYC
  Given I create a new InvestorKyc "PAN=ABCFG1234;full_name=somegoodname" to trigger aml report generation
  Then I should see the "Investor kyc was successfully saved."
  Then aml report is not generated for the investor kyc
  Given I bulk generate aml reports for investor kycs
  Then Aml report should be generated for the kycs that have full name
  Then we get the email with error "Investing Entity is blank for Investor Kyc ID 1" and subject "GenerateAMLReports completed for 2 records, with 1 errors"

Scenario Outline: Dont Generate Aml Report on Kyc Update
  Given Im logged in as a user "first_name=Testuser1" for an entity "name=Urban12;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given the entity has aml enabled "true"
  Given there is an existing investor "investor_name=Investor 112"
  Given I create a new InvestorKyc "PAN=ABCD1234FG;full_name=nil" to trigger aml report generation
  Then I should see the "Investor kyc was successfully saved."
  Then aml report is not generated for the investor kyc
  Given I update the last investor kycs name to "somegoodname"
  Then I should see the "Investor kyc was successfully saved."
  Then aml report is not generated for the investor kyc
