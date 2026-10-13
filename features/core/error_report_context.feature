@notification
Feature: Error emails carry the context needed to act on them
  In order to act on a production error report without guessing
  As support
  I want every error email to name the job, the person who triggered it, the call site
  and the arguments it ran with

  Background:
    Given the default support email is "support@example.com"
    And there is a user "first_name=Trig;last_name=User;email=trigger@mapping.com" for an entity "name=MappingEntity;entity_type=Company"

  @rack_test
  Scenario: A job-triggered error email names the job, the actor, the call site and the arguments
    Given a job "TrackingCurrencyJob" enqueued by "trigger@mapping.com" from "app/packs/funds/funds/controllers/funds_controller.rb:333:in 'tracking_currency'"
    When the job reports "Missing rates: USD->INR on 1899-12-30" by email
    Then an email should be sent to "support@example.com" with subject containing "Errors in TrackingCurrencyJob"
    And the error email context should show "Source" as "TrackingCurrencyJob"
    And the error email context should show "Triggered by" as "Trig User (trigger@mapping.com"
    And the error email context should show "Triggered from" as "funds_controller.rb:333"
    And the error email context should show "Job arguments" as "fund_id: 7"
    And the error email context should show "Environment" as "test"
    And the error email should still list "Missing rates: USD->INR on 1899-12-30"

  Scenario: A scheduled run with no acting user says so rather than leaving it blank
    Given a job "TrackingCurrencyJob" enqueued by nobody
    When the job reports "Missing rates: USD->INR on 1899-12-30" by email
    Then the error email context should show "Triggered by" as "Not attributed"

  @rack_test
  Scenario: A caller that passes no context still gets the environment block
    When I trigger "notify_errors" with "error_msg=error:something_went_wrong"
    Then an email should be sent to "support@example.com" with subject containing "Errors"
    And the error email context should show "Environment" as "test"
