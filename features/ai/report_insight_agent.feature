Feature: Report Insight Agent
  Tests to check Report insight generation and notification

Scenario Outline: Check Insight generation for a report
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given "report_analysis_agent" support agent is enabled for the entity
  Given there is a fund "name=SAAS Fund;currency=INR;unit_types=Series A,Series B,Series C1" for the entity
  And Given I upload an investors file for the fund
  And Given I upload "capital_commitments_multi_currency.xlsx" file for "Commitments" of the fund
  Then I should see the "Import in progress"
  Then There should be "8" capital commitments created
  And the imported data must have the form_type updated
  And the capital commitments must have the data in the sheet
  Given I ransack filter the "Commitments"
  And I save the filtered data as a report "Commitments Report" with Ai prompt and notification recipient "test1234@email.com"
  Then the report should have the expected data
  Given I generate the insight for the report
  Then  the report insight should be generated
  And the recipient should receive an email notification with the insight summary
  Then I should be able to view the report details
  Given the user has "tag_list=reportrecipient" assigned
  Given I go to edit the report
  Given I edit the report "notification_recipients=report_recipient@email.com,investor"
  Given I click on "Save"
  Then I should see the "Cannot mix email addresses and user tags"
  Given I edit the report "notification_recipients=somebademail@"
  Given I click on "Save"
  Then I should see the "Invalid email format: somebademail@"
  Given I edit the report "notification_recipients=reportrecipient"
  Given I click on "Save"
  Then I should see the "Report was successfully updated."
  Given I generate the insight for the report
  Then  the report insight should be generated
  And the user with tag "reportrecipient" should receive an email notification with the insight summary
