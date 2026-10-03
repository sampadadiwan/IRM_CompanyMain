@doc_checks
Feature: Document Checks — Doc Questions retired (deploy 2)
  After the retirement deploy only Document Checks remain: the Doc Questions screens, import type and KYC
  action are gone, its table and the dead documents.qna column are dropped, and earlier AI answers stay on
  each KYC. The drop migration refuses to run while any Doc Question is unconverted.
  Worked examples R1–R5 in openspec/changes/document-checks/design.md#worked-examples

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;enable_kycs=true;enable_doc_llm_validation=true;enable_import_uploads=true"
    And the user has role "company_admin"
    And there is an existing investor "" with "1" users
    And the entity requires the individual KYC documents "CML, PAN Card, Passport"

  # R1
  Scenario: The old settings pages are gone
    Then the page "/doc_questions" should not be found
    And the page "/doc_questions/new" should not be found
    And the KYC list's Document checks menu should link to "/doc_checks"

  # R2
  Scenario: The old import type is gone and old uploads still open
    Then "DocQuestion" should not be an import type
    And an earlier "DocQuestion" import upload should still open

  # R3
  Scenario: The old KYC action is gone
    Given there is an individual KYC for the investor "full_name=Asha Rao;PAN=ABCPK1234F"
    Then posting to the KYC's old "validate_docs_with_ai" action should not be found
    And the KYC page's Check documents button should post to Document Checks

  # R4
  Scenario: The old data is gone and the history is kept
    Then the database should have no table "doc_questions"
    And the database should have no table "doc_check_conversion_logs"
    And the "documents" table should have no column "qna"
    And the "investor_kycs" table should still have the column "doc_question_answers"

  # R5
  Scenario: The drop refuses to remove unconverted questions
    Given an environment still has 2 Doc Questions, 1 of them converted
    When the retirement migration runs
    Then it should stop with "1 Doc Questions are not converted — run doc_checks:convert_doc_questions first"
    And the Doc Questions table should still be there
    When the other Doc Question is converted and the retirement migration runs
    Then the database should have no table "doc_questions"
