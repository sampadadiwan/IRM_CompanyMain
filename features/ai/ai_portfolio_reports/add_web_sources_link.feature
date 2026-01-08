Feature: Web Search Source Links
  As an analyst
  I want web search content appended to document content
  So that I get comprehensive insights with sources

  Background:
    Given I am logged in as an analyst
    And a portfolio company "AURAA" exists

  Scenario: Web search augments existing document content
    Given an AI portfolio report exists for "AURAA"
    And the report has a section "Market Size & Target" with document content
    When I enable web search for the section
    Then the section should preserve the original document content
    And the section should contain "Additional Insights from Web Search"
    And the section content should be saved to content_html_with_web

  Scenario: Web search sources include clickable links
    Given an AI portfolio report exists for "AURAA"
    And the report has a section "Market Size & Target" with document content 
    When I enable web search for the sectionx   
    Then the section should contain clickable source links    
    And each source link should have a valid URL
