Feature: Entity Database Dump
  As a Company Admin
  I want to be able to generate a database dump for my entity
  So that I can have a portable backup of my data

  Background:
    Given there is a user "first_name=Admin;last_name=User" for an entity "name=Test Entity"
    And the user has role "company_admin"
    And the user has curr role "company_admin"
    And the user is logged in
    And the entity has database dumps enabled
    And the email queue is cleared

  Scenario: Manually triggering a database dump from the UI
    Given I am at the entity page for "Test Entity"
    Given the user has the tag "db_dump_notification"
    When I click on "Generate DB Dump"
    And I confirm the dialog "Proceed"
    Then I should see "Database dump generation started"
    When the database dump job runs for "Test Entity"
    Then a document named "DB Dump" should be created for "Test Entity" in the "Temp" folder
    And the user should receive an email with "Download link" in the subject
    And the email body should contain "The daily database dump for Test Entity is ready for download"


  Scenario: Job cleans up old dumps
    Given a database dump document exists for "Test Entity" created 10 days ago
    And the entity retention period is set to 7 days
    When the database dump job runs for "Test Entity"
    Then the old database dump document should be deleted
