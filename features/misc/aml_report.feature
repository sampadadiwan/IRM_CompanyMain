
@doc_gen
Feature: Aml Report Generation
  Can access models as a company

@notification
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

Scenario Outline: Generate AML report Manually with and without PAN
  Given Im logged in as a user "first_name=Testuser" for an entity "name=Urban1;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given the entity has aml enabled "true"
  Given there is an existing investor "investor_name=Investor 11"
  Given I create a new InvestorKyc "PAN=ABCDE1234F;full_name=Some Name" to trigger aml report generation
  Then I should see the "Investor kyc was successfully saved."
  Then aml report is not generated for the investor kyc
  Given I go to view the KYC
  Given I click on "KYC Actions"
  Given I mock aml and click on "Generate AML Report"
  Then AML Report is Generated with PAN
  Given I create a new InvestorKyc "PAN=123456789;full_name=Good Name" to trigger aml report generation
  Then I should see the "Investor kyc was successfully saved."
  Then aml report is not generated for the investor kyc
  Given I go to view the KYC
  Given I click on "KYC Actions"
  Given I mock aml and click on "Generate AML Report"
  Then AML Report is Generated without PAN

Scenario: Manually override AML status with a reason, tracked in the audit trail
  Given Im logged in as a user "first_name=Testuser2" for an entity "name=Urban13;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given the entity has aml enabled "true"
  Given there is an existing investor "investor_name=Investor 113"
  Given I create a new InvestorKyc "PAN=ABCDE9999F;full_name=Some Match Name" to trigger aml report generation
  Then I should see the "Investor kyc was successfully saved."
  Given I go to view the KYC
  Given I click on "KYC Actions"
  Given I mock aml and click on "Generate AML Report"
  Then I should see "Potential Match"
  Given I click on "Override AML status"
  When I select "No Match" from "AML Status"
  When I fill in "Reason for override" with "Name match is a different person, verified manually via PAN and DOB."
  Given I click on "Save Override"
  Then I should see "AML status overridden."
  Then I should see "No Match"
  Then I should see the AML override reason tooltip containing "Manually overridden: Name match is a different person, verified manually via PAN and DOB."
  Then the aml status override should be recorded in the audit trail with comment "Name match is a different person, verified manually via PAN and DOB."
  Given I click on "KYC Actions"
  Given I mock aml and click on "Generate AML Report"
  Then I should see "No Match"
  Then I should not see "Potential Match"

# incident 45847776 - AmlReportsController#index derived the breadcrumb from
# @aml_reports.first.investor_kyc, so any request where the policy-scoped relation came back
# empty 500ed. The two scenarios below cover the minimal shape (no reports at all) and the
# real-world trigger (reports exist but belong to another entity).
Scenario: Viewing AML reports for a KYC that has none renders an empty page, not an error
  Given Im logged in as a user "first_name=Testuser4" for an entity "name=Urban14;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given the entity has aml enabled "true"
  Given there is an existing investor "investor_name=Investor 114"
  Given I create a new InvestorKyc "PAN=ABCDE8888F;full_name=No Reports Name" to trigger aml report generation
  Then I should see the "Investor kyc was successfully saved."
  Then aml report is not generated for the investor kyc
  Given I go to the AML reports page for the KYC
  Then I should see the AML reports page with no reports for the KYC

Scenario: Viewing AML reports owned by another entity renders an empty page, not an error
  Given Im logged in as a user "first_name=Testuser5" for an entity "name=Urban15;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given the entity has aml enabled "true"
  Given there is an existing investor entity "investor_name=Investor 115;entity_type=Investor" with employee "first_name=LpUser"
  Given the existing investor user has role "employee"
  Given I create a new InvestorKyc "PAN=ABCDE7777F;full_name=Cross Entity Name" to trigger aml report generation
  Then I should see the "Investor kyc was successfully saved."
  Given I go to view the KYC
  Given I click on "KYC Actions"
  Given I mock aml and click on "Generate AML Report"
  Then AML Report is Generated with PAN
  Given I log in as the investor entity employee with aml enabled
  Given I go to the AML reports page for the KYC
  Then I should see the AML reports page with no reports for the KYC