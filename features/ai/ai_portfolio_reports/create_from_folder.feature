Feature: Create AI Portfolio Report from Folder
    As an analyst
    I want to create an AI portfolio report from a document Folder
    so that I can quickly generate reports from uploaded documents

    Scenario: Successfully create report from a folder with documents
        Given I am logged in as an analyst
        And a portfolio company "ACE" exist with category "Portfolio Company"
        And the portfolio company has a folder with a document
        When I visit the documents page for the folder
        And I click "Actions"
        And I click "Create AI Portfolio Report"
        And I click "Proceed"
        Then an AI portfolio report should be created for "ACE"
        
        