Feature: Import Doc Questions
  Can bulk import the questions the LLM asks of an uploaded document

  Background:
    Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
    Given the user has role "company_admin"

  @import
  Scenario: Import creates doc questions from xlsx
    Given Given import file "doc_questions.xlsx" for "DocQuestion"
    Then there should be "3" doc questions for the entity
    And the doc question "Is the document signed by the investor?" should have type "validation" for class "InvestorKyc" document name "PAN Card" tags "kyc,identity"
    And the doc question "What is the PAN number?" should have extract to "A 10 character alphanumeric PAN"
    And the doc question "Summarise the key terms of the agreement" should have type "general" for class "Offer" document name "" tags "offer,agreement"
    And every imported doc question should be owned by the entity

  @import
  Scenario: Re-importing the same file reports every row as a duplicate
    Given Given import file "doc_questions.xlsx" for "DocQuestion"
    Then there should be "3" doc questions for the entity
    And re-importing "doc_questions.xlsx" for "DocQuestion" should fail with "already exists" on every row
    And there should be "3" doc questions for the entity

  @import
  Scenario: An edited row from the download updates its question instead of duplicating it
    Given Given import file "doc_questions.xlsx" for "DocQuestion"
    Then there should be "3" doc questions for the entity
    When I re-import the doc questions carrying their Ids, with the question text edited
    Then there should be "3" doc questions for the entity
    And the edited doc question should have been saved
    And the edited doc question should still belong to the upload that created it

  @import
  Scenario: A row with an Id no question has is rejected rather than creating one
    Given Given import file "doc_questions.xlsx" for "DocQuestion"
    When I re-import the doc questions carrying an Id that does not exist
    Then there should be "3" doc questions for the entity
    And the import results should mention "No question found with Id"

  @import
  Scenario: A row naming a type or class the app does not know fails with a usable message
    Given Given import file "doc_questions_bad_values.xlsx" for "DocQuestion" expecting failures
    Then the import upload should have "0" processed and "3" failed rows
    And the import results should mention "Type 'Wibble' is not valid"
    And the import results should mention "For 'Fund' is not valid"
    And the import results should mention "Document Name or Tags must be specified"

  @import
  Scenario: A column the importer needs is missing so the whole upload is rejected
    Given Given import file "doc_questions_missing_column.xlsx" for "DocQuestion" expecting failures
    Then the import upload should have "0" processed and "1" failed rows
    And the import upload status should mention "Column(s) not found: Type"
