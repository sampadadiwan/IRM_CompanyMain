Feature: Cross Portfolio Dashboard
  As a fund admin
  I want to view aggregated portfolio company data across multiple funds
  So that I can analyze performance using Fund, Tag, and Sector filters

  Background:
    Given Im logged in as a user "first_name=Admin" for an entity "entity_type=Investment Fund;enable_funds=true;enable_investors=true"
    And the user has role "company_admin"

  Scenario Outline: Creating a new cross portfolio dashboard
    Given I visit the Aggregated Portfolio Dashboard widget page
    Then I fill the new dashboard widget form with data 1
    Then the dashboard widget must be created
    Then I visit the Aggregated Portfolio Dashboard widget page
    Then I fill the new dashboard widget form with data 2
    Then the dashboard widget must be created
    Then I visit the Aggregated Portfolio Dashboard widget page
    Then I fill the new dashboard widget form with data 3
    Then the dashboard widget must be created
    Then I visit the Aggregated Portfolio Dashboard widget page
    Then I fill the new dashboard widget form with data 4
    Then the dashboard widget must be created

    Given there is a fund "name=Alpha Fund;currency=INR" for the entity
    And I am "yes" employee access to the fund
    And there is a fund "name=Beta Fund;currency=INR" for the entity
    And I am "yes" employee access to the fund

    Given there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
    And portfolio company is added to list of companies
    And there is an existing portfolio company "name=MyFavStartup2;category=Portfolio Company"
    And portfolio company is added to list of companies
    And there is an existing portfolio company "name=MyFavStartup3;category=Portfolio Company"
    And portfolio company is added to list of companies
    And investor access "approved=1" in the portfolio company

    And the portfolio companies are tagged randomly from "Fintech, AI, SaaS, Healthcare"
    And the portfolio companies belong to sectors "AgriTech, PropTech, InsurTech, Logistics"

    And investment instruments exist for each portfolio company
    And portfolio investments are created

    Then I navigate to the cross portfolio dashboard
    And All calculations should be correct

  Scenario Outline: Aggregated stats reflect correct values for tags via URL
    Given I visit the Aggregated Portfolio Dashboard widget page
    Then I fill the new dashboard widget form with data 1
    Then the dashboard widget must be created
    Then I visit the Aggregated Portfolio Dashboard widget page
    Then I fill the new dashboard widget form with data 2
    Then the dashboard widget must be created
    Then I visit the Aggregated Portfolio Dashboard widget page
    Then I fill the new dashboard widget form with data 3
    Then the dashboard widget must be created
    Then I visit the Aggregated Portfolio Dashboard widget page
    Then I fill the new dashboard widget form with data 4
    Then the dashboard widget must be created
    Then I visit the Aggregated Portfolio Dashboard widget page
    Then I fill the new dashboard widget form with data 5
    Then the dashboard widget must be created


    Given there is a fund "name=Alpha Fund;currency=INR" for the entity
    And I am "yes" employee access to the fund

    Given there is a fund "name=Beta Fund;currency=INR" for the entity
    And I am "yes" employee access to the fund

    Given fund ratio "Gross Portfolio IRR" for fund "Alpha Fund" exist
    Given fund ratio "Gross Portfolio MOIC" for fund "Alpha Fund" exist

    Given fund ratio "Gross Portfolio MOIC" for fund "Beta Fund" exist
    Given fund ratio "Gross Portfolio IRR" for fund "Beta Fund" exist


    Given there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
    And portfolio company is added to list of companies
    And there is an existing portfolio company "name=MyFavStartup2;category=Portfolio Company"
    And portfolio company is added to list of companies
    And the portfolio companies are tagged with "AI"

    Given investments exist for tag "AI" with amount 10000
    Given I calculate expected bought amount for tag "AI"
    When I visit the cross portfolio dashboard with tags "AI"

    Then the Bought Amount stat should be correct

    Then the fund ratios for funds with tables and chart are shown
    Then the fund ratios fetched for funds "Alpha Fund,Beta Fund" should be correct and latest



