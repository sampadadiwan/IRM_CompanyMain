Feature: Kyc Pan And Bank Verification
  Test behavior of the Sebi Fields in Investor Kyc

Scenario Outline: Kyc PAN Verification
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is an existing investor "investor_name=Investor 1 test"
  Given Entity PAN verification is enabled
  Given I go to create InvestorKyc "PAN=ABCD9876F"
  Then I should see the "Investor kyc was successfully saved."
  Then Kyc Pan Verification is triggered
  And when the Kyc name is updated
  Then Kyc Pan Verification is triggered
  And when the Kyc PAN is updated
  Then Kyc Pan Verification is triggered


Scenario Outline: Kyc Bank Verification
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban32;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is an existing investor "investor_name=Investor 2 test"
  Given Entity Bank verification is enabled
  Given I go to create InvestorKyc "PAN=AGHJF6726F"
  Then I should see the "Investor kyc was successfully saved."
  Then Kyc Bank Verification is triggered
  And when the Kyc name is updated
  Then Kyc Bank Verification is triggered
  And when the Kyc Bank Account number is updated
  Then Kyc Bank Verification is triggered
  And when the Kyc Bank IFSC is updated
  Then Kyc Bank Verification is triggered
