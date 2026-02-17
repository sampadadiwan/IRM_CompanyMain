Feature: Upload Documents Modal for Portfolio Company
  As an analyst
  I want to upload documents for a portfolio company via a modal
  So that the AI can use them to generate portfolio report sections

  Background:
    Given I am logged in as an analyst
    And a portfolio company "Apple" exists

  Scenario: Add Documents link appears when portfolio company is selected
    Given I am at the new AI portfolio report page
    When I select portfolio company "Apple"
    Then I should see the "Add Documents" link

  Scenario: Open documents modal and see empty state
    Given I am at the new AI portfolio report page
    When I select portfolio company "Apple"
    And I click "Add Documents" on Ai Portfolio Report Page
    Then I should see the documents modal
    And I should see "No documents uploaded yet."

  Scenario: Fetch existing documents for portfolio company in modal
    Given the portfolio company "Apple" has an evaluation folder with documents:
      | name              |
      | pitch_deck.pdf    |
    And I am at the new AI portfolio report page
    When I select portfolio company "Apple"
    And I click "Add Documents" on Ai Portfolio Report Page
    Then I should see the documents modal
    And I should see document "pitch_deck.pdf" in the documents list
    

  Scenario: Modal displays documents table when documents exist
    Given the portfolio company "Apple" has an evaluation folder with documents:
      | name              |
      | pitch_deck.pdf    |
    And I am at the new AI portfolio report page
    When I select portfolio company "Apple"
    And I click "Add Documents" on Ai Portfolio Report Page
    Then I should see the documents table in the modal
    And the documents table should have 1 row

  Scenario: Modal shows upload section
    Given I am at the new AI portfolio report page
    When I select portfolio company "Apple"
    And I click "Add Documents" on Ai Portfolio Report Page
    Then I should see the documents modal
    And I should see the upload documents section
    And I should see the "Upload Documents" button

  
