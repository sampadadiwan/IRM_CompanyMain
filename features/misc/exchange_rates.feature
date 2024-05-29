Feature: Import Exchange Rates
  Imports Exchange Rates and marks latest

@import
Scenario Outline: Import Exchange Rates
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
	And Given I upload an exchange_rates file
  Then I should see the "Import in progress"
  Then There should be 2 exchange rates created